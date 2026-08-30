#!/usr/bin/env bash
# Shared setup for the bats suite.
bats_require_minimum_version 1.5.0

SETUP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP_SH="$SETUP_ROOT/setup.sh"

# Every test gets its own HOME/XDG/LOG_FILE. Nothing here may touch the real
# ~/.config/dev-setup or append to the repo's setup.log, and the log-redirect
# assertions need a log path of their own to prove a callback stayed off it.
sandbox() {
  TEST_TMP="$(mktemp -d)"
  export HOME="$TEST_TMP/home"
  export XDG_CONFIG_HOME="$TEST_TMP/config"
  export XDG_CACHE_HOME="$TEST_TMP/cache"
  export LOG_FILE="$TEST_TMP/setup.log"
  mkdir -p "$HOME" "$TEST_TMP/bin"
  TUI_STATE="$TEST_TMP/state"
  mkdir -p "$TUI_STATE"
  echo 0 >"$TUI_STATE/tab"
  export TUI_STATE
}

sandbox_teardown() {
  [[ -n "${TEST_TMP:-}" ]] && rm -rf "$TEST_TMP"
  return 0
}

strip_ansi() { sed -E 's/\x1b\[[0-9;]*m//g'; }

# One row exactly as __tui_list prints it, markers and colour intact — the
# callbacks are fed rows by fzf, so tests must feed them the same bytes.
# Type comes from the marker glyph, never the key: `go` and `rust` are each
# both a Profile key and a Tool key. See ADR-0003.
list_row() {
  read_list
  grep -m1 -F "$(row_mark "$1") $2 " "$TEST_TMP/list"
}

# The check marker `tui_list` painted on a row: `[x]` or `[ ]`. A check lives
# in TUI_STATE and the list paints it, so this is how a test reads a check
# back off the screen. See ADR-0010.
row_check() {
  read_list
  strip_ansi <"$TEST_TMP/list" | grep -m1 -F "$(row_mark "$1") $2 " | cut -c1-3
}

# Refetched rather than cached: the list is the current tab's, and a test that
# writes TUI_STATE/tab between calls must see the new one.
read_list() { "$SETUP_SH" __tui_list >"$TEST_TMP/list"; }

row_mark() {
  case "$1" in
    profile) printf '◆' ;;
    tool)    printf '·' ;;
    *) echo "row_mark: unknown type $1" >&2; return 1 ;;
  esac
}

# --- the Install Step transition stream ----------------------------------------
#
# Shared by every suite that reads a run's lifecycle off stdout. The stream is
# the run made observable (ADR-0011), so these are how a test sees what a run
# did: nothing here reaches inside the script.

# The transition stream, one `<step> | <state>[ | <detail>]` per line, in the
# order the run emitted it.
transitions() { strip_ansi <<<"$1" | sed -n 's/^\[STEP\] //p'; }

# The states one Install Step passed through, in order.
step_states() { transitions "$1" | awk -F' \\| ' -v s="$2" '$1 == s { print $2 }'; }

# The detail a state carried, if any.
step_detail() { transitions "$1" | awk -F' \\| ' -v s="$2" '$1 == s && NF > 2 { print $3 }'; }

# Every state named anywhere in the stream, deduplicated.
states_seen() { transitions "$1" | awk -F' \\| ' '{ print $2 }' | sort -u; }

# The Install Steps a dry run said it would run, in plan order.
planned_steps() {
  strip_ansi <<<"$1" | sed -n 's/.*\[DRY RUN\] Install Step: \([a-z_]*\) ->.*/\1/p'
}

# Every planned Install Step reached exactly one terminal state -- which is what
# "the run finished" means when a failure no longer stops it (ADR-0006).
every_step_settled() {
  local s
  while read -r s; do
    [[ -n "$s" ]] || continue
    [ "$(step_states "$1" "$s" | grep -cE '^(done|already installed|skipped|failed)$')" -eq 1 ] || return 1
  done <<<"$(planned_steps "$1")"
}

# The script with presence probes forced to a fixed answer, so a test never
# depends on what happens to be installed on the machine running it.
# `probe_forced gh=true node=false` reads: gh is on this machine, node is not.
# Patches the same copy every other patcher here does, so a test can force a
# probe and stub a Step and get one script with both.
probe_forced() {
  local copy spec tool answer
  copy="$(script_copy)"
  for spec in "$@"; do
    tool="${spec%%=*}"; answer="${spec#*=}"
    sed -i -E "s|^  \[$tool\]='.*'\$|  [$tool]='$answer'|" "$copy"
    # A silently unapplied patch would make the test assert nothing.
    grep -qF "  [$tool]='$answer'" "$copy"
  done
  printf '%s' "$copy"
}

# An executable of that name on PATH, which is how the probes read presence.
fake_tool() {
  printf '#!/bin/sh\necho "%s 1.0.0"\n' "$1" >"$TEST_TMP/bin/$1"
  chmod +x "$TEST_TMP/bin/$1"
  export PATH="$TEST_TMP/bin:$PATH"
}

# --- the log --------------------------------------------------------------------
#
# There is no blanket `tee` redirect: the run writes the log itself, and each
# Install Step's output goes into a section that names the Step (#20). These
# read the log back the way the transition helpers read stdout.

# The transition stream as the log recorded it, in the order it was written.
log_transitions() { sed -n 's/^\[STEP\] //p' "$LOG_FILE"; }

# One Install Step's captured output, delimiters excluded.
log_step_output() {
  awk -v s="$1" '
    $0 == "[STEP OUTPUT] " s " | begin" { inside = 1; next }
    $0 ~ "^\\[STEP OUTPUT\\] " s " \\| end"  { inside = 0 }
    inside
  ' "$LOG_FILE"
}

# --- patching the script under test ---------------------------------------------

# The copy every patch below edits. One per test, made on first use, so several
# patches compose on the same file.
script_copy() {
  if [[ ! -e "$TEST_TMP/setup.sh" ]]; then
    cp "$SETUP_SH" "$TEST_TMP/setup.sh"
    chmod +x "$TEST_TMP/setup.sh"
  fi
  printf '%s' "$TEST_TMP/setup.sh"
}

# A definition spliced in just before `main "$@"`, replacing whatever the script
# defined earlier. Nothing already in the file is edited, so a stub outlives any
# rewrite of the function it stands in for. One line, so that the splice can be
# checked by counting.
override() {
  local copy; copy="$(script_copy)"
  awk -v body="$1" '
    index($0, "main \"$@\"") == 1 && !spliced { print body; spliced = 1 }
    { print }
  ' "$copy" >"$copy.new"
  # A silently unspliced override would leave the real function in place, and
  # the test would assert against the thing it meant to stand in for. Counted
  # rather than grepped: the name it replaces is in the file either way.
  [ "$(wc -l <"$copy.new")" -eq "$(( $(wc -l <"$copy") + 1 ))" ]
  mv "$copy.new" "$copy"
  chmod +x "$copy"
}

# A real run — not `--dry-run` — minus everything that would touch the machine:
# the root check, the apt base deps, and every Install Step, each stubbed to a
# no-op. A test then overrides the one Step it is about, and the later
# definition is the one that runs. Blanket, not per-test, because a Step name
# left unstubbed by an oversight would curl an installer onto the machine
# running the suite.
#
# What is *not* stubbed is how a Step is run — the precondition gate, the
# capture, the transitions, the summary — which is what these tests are for.
runnable() {
  override 'require_root() { :; }'
  override 'install_base_deps() { :; }'
  # Verification is a second, disagreeing version probe that #15 deletes; here
  # it is a second of forks and a screenful of noise per test.
  override 'verify_versions() { :; }'
  # Read off TOOL_INSTALL_STEP, so the list is the Install Steps and nothing
  # else: matching function names by prefix would stub `install_selected_tools`
  # — the runner these tests are about — and the run would plan nothing.
  local fn steps
  steps="$(sed -n 's/^  \[[a-z0-9-]*\]=\(install_[a-z0-9_]*\)$/\1/p' "$SETUP_SH" | sort -u)"
  # The registry holds 22 Install Steps. A sed that quietly matched fewer --
  # because the table was reformatted -- would leave real installers in place
  # and the next real-run test would run one.
  [ "$(grep -c . <<<"$steps")" -ge 22 ]
  for fn in $steps; do
    override "$fn() { :; }"
  done
  script_copy
}
