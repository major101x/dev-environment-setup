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

# A copy of the script with presence probes forced to a fixed answer, so a test
# never depends on what happens to be installed on the machine running it.
# `probe_forced gh=true node=false` reads: gh is on this machine, node is not.
probe_forced() {
  cp "$SETUP_SH" "$TEST_TMP/setup.sh"
  local spec tool answer
  for spec in "$@"; do
    tool="${spec%%=*}"; answer="${spec#*=}"
    sed -i -E "s|^  \[$tool\]='.*'\$|  [$tool]='$answer'|" "$TEST_TMP/setup.sh"
    # A silently unapplied patch would make the test assert nothing.
    grep -qF "  [$tool]='$answer'" "$TEST_TMP/setup.sh"
  done
  chmod +x "$TEST_TMP/setup.sh"
  echo "$TEST_TMP/setup.sh"
}

# An executable of that name on PATH, which is how the probes read presence.
fake_tool() {
  printf '#!/bin/sh\necho "%s 1.0.0"\n' "$1" >"$TEST_TMP/bin/$1"
  chmod +x "$TEST_TMP/bin/$1"
  export PATH="$TEST_TMP/bin:$PATH"
}
