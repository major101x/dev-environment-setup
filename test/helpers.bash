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
  # The Reachability file is `/etc/profile.d/dev-setup.sh` on a real machine
  # (#70). Sandboxed for the same reason `HOME` is: no test may write a login
  # shell's `PATH` on the machine running the suite.
  export REACHABILITY_FILE="$TEST_TMP/dev-setup-profile.sh"
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

# The Tool keys the current tab's list holds, in the order it paints them.
# What a Category tab *means* is this list, so an assertion about a tab reads
# it rather than grepping for a row it expects and hoping about the rest.
list_keys() {
  read_list
  strip_ansi <"$TEST_TMP/list" | sed -n 's/^\[.\] · \([a-z0-9-]*\) .*/\1/p'
}

# One of the picker's state sets read back off disk — `checked`, `profiles` or
# `declined`. A check lives in the state and the list paints it (ADR-0010), so
# a set is a file, and a file is what a test can assert against.
tui_state() { sed '/^$/d' "$TUI_STATE/$1" 2>/dev/null || true; }

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

# The resolved Toolset as the run narrates it: the Tool keys of one run, in
# resolution order, on one line. What a Profile *means* is this line, so the
# assertions about what a Profile resolves to read it rather than a count.
toolset_line() { strip_ansi <<<"$1" | sed -n 's/^\[INFO\] Toolset: //p'; }

# The transition stream, one `<step> | <state>[ | <detail>]` per line, in the
# order the run emitted it.
transitions() { strip_ansi <<<"$1" | sed -n 's/^\[STEP\] //p'; }

# The states one Install Step passed through, in order.
step_states() { transitions "$1" | awk -F' \\| ' -v s="$2" '$1 == s { print $2 }'; }

# The detail a state carried, if any.
step_detail() { transitions "$1" | awk -F' \\| ' -v s="$2" '$1 == s && NF > 2 { print $3 }'; }

# Every state named anywhere in the stream, deduplicated.
states_seen() { transitions "$1" | awk -F' \\| ' '{ print $2 }' | sort -u; }

# The plan without base dependencies, which leads every one of them (#68). A
# test about which Tools resolved to which Steps is not about base dependencies,
# and repeating that fact in every such assertion would say it a dozen times and
# mean it nowhere. The plan's full shape, base dependencies first, is asserted
# once in `test/lifecycle.bats`.
planned_tool_steps() {
  planned_steps "$1" | grep -vx "$(sed -n 's/^BASE_DEPS_STEP=\([a-z0-9_]*\)$/\1/p' "$SETUP_SH")"
}

# The label a dry run gave one Install Step in its plan -- the Tools it delivers,
# comma-joined, or for a Step that delivers none its own declared label (#68).
step_label() {
  strip_ansi <<<"$1" | sed -n "s/.*Install Step: $2 -> //p" | head -n1
}

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

# --- how big the registry is ----------------------------------------------------
#
# Written down literally on one line of one test -- `--all resolves the whole
# registry`, in test/cli.bats -- and derived everywhere else, so that a Tool
# joining the registry fails that one test and costs one edit rather than six
# (#58).
#
# What a caller checks against these is its own *parse*: that a sed reading a
# rendered list, or the table of Install Steps, did not quietly stop matching.
# A Tool leaving the registry moves both sides of such a check together, and
# catching that is the tripwire's job and only the tripwire's.

# The Tools the registry declares, counted off ORDERED_TOOLS. `--list-tools`
# walks TOOL_DESC rather than this array, so that one test does compare two
# independent routes; the picker's list walks this same array, and is only
# checking that its own sed matched every row.
registry_tool_count() {
  local n
  n="$(sed -n 's/^ORDERED_TOOLS=(\(.*\))$/\1/p' "$SETUP_SH" | wc -w)"
  # Line-anchored, so an ORDERED_TOOLS wrapped over two lines matches nothing
  # and every assertion derived from this would pass against zero. Post-checked
  # like `override` and `probe_forced` post-check their own splices.
  [ "$n" -gt 0 ] || { echo "registry_tool_count: no ORDERED_TOOLS line" >&2; return 1; }
  printf '%s' "$n"
}

# The Install Steps `--all` plans. Asked of the script instead of read off
# TOOL_INSTALL_STEP, so a test that parses that table has something arrived at
# by another route to check its parse against.
#
# A run writes its transitions to the log, and a caller may be about to read the
# log for the run it is actually testing, so this one is given a log of its own.
planned_step_count() {
  local n
  n="$(planned_steps "$(LOG_FILE="$TEST_TMP/registry-probe.log" \
    "$SETUP_SH" --dry-run --all --no-auth)" | grep -c . || true)"
  # A run that failed to plan anything is not a plan of no Steps, and would
  # silently satisfy the floor in `runnable` against nothing.
  [ "$n" -gt 0 ] || { echo "planned_step_count: --all planned no steps" >&2; return 1; }
  printf '%s' "$n"
}

# The Install Steps the registry names, off TOOL_INSTALL_STEP, sorted unique.
# The *names* -- where `planned_step_count` is a total reached by another
# route, so a caller wanting both has its parse and the check on it separate.
#
# Matching function names by prefix instead would pick up `install_selected_tools`,
# which is not an Install Step: the map is what makes one, except for the single
# Step the map cannot name, which is why that one is read off `BASE_DEPS_STEP`
# below rather than found by its prefix (#68).
# Every Install Step the script defines: the ones the registry maps a Tool to,
# plus the one it cannot name because it delivers no Tool (#68). Read off
# `BASE_DEPS_STEP` rather than written down, so the two cannot drift.
#
# It matters most for `runnable`, which stubs this list: base dependencies left
# off it is `apt-get update` running for real on the machine under test, which
# is the exact accident the blanket stub exists to prevent.
registry_install_steps() {
  local steps base
  steps="$(sed -n 's/^  \[[a-z0-9-]*\]=\(install_[a-z0-9_]*\)$/\1/p' "$SETUP_SH" | sort -u)"
  # An empty parse is a caller looping over nothing while believing it swept the
  # registry. Post-checked like `override` and `probe_forced` post-check theirs.
  [ -n "$steps" ] || { echo "registry_install_steps: TOOL_INSTALL_STEP parsed empty" >&2; return 1; }
  base="$(sed -n 's/^BASE_DEPS_STEP=\([a-z0-9_]*\)$/\1/p' "$SETUP_SH")"
  [ -n "$base" ] || { echo "registry_install_steps: no BASE_DEPS_STEP line" >&2; return 1; }
  printf '%s\n%s\n' "$base" "$steps"
}

# The picker's tab strip, off TUI_TABS: `All` and then one tab per Category,
# one per line. Written down literally in one test -- `__tui_header marks the
# current tab and lists every Category` -- and derived from here everywhere
# else, so a Category joining the strip costs the one edit rather than four
# (the same bargain `registry_tool_count` struck for the registry's size, #58).
#
# Split on whitespace with the quotes stripped, which is only a parse of the
# array because no tab label holds a space. One that did would arrive as two
# tabs here and as a tab strip nobody can click, so this is not the place that
# would notice it first.
registry_tabs() {
  local tabs
  tabs="$(sed -n 's/^TUI_TABS=(\(.*\))$/\1/p' "$SETUP_SH" | tr -d '"')"
  # Line-anchored, so a TUI_TABS wrapped over two lines matches nothing and
  # every count derived from it would be zero. Post-checked like the registry
  # parses above.
  [ -n "$tabs" ] || { echo "registry_tabs: no TUI_TABS line" >&2; return 1; }
  printf '%s\n' $tabs
}

# How many tabs the strip has, which is what `__tui_tab` wraps at.
tab_count() { registry_tabs | grep -c .; }

# The index one Category tab sits at, which is what `$TUI_STATE/tab` holds.
# Asked by name, because a test about a tab is about the Category and not about
# where in the strip it happens to have landed.
tab_index() {
  local n
  n="$(registry_tabs | grep -nxF "$1" | cut -d: -f1)" || true
  [ -n "$n" ] || { echo "tab_index: no such tab: $1" >&2; return 1; }
  printf '%s' "$((n - 1))"
}

# The script with presence probes forced to a fixed answer, so a test never
# depends on what happens to be installed on the machine running it.
# `probe_forced gh=true node=false` reads: gh is on this machine, node is not.
# Patches the same copy every other patcher here does, so a test can force a
# probe and stub a Step and get one script with both.
#
# Addressed to the TOOL_PRESENT block alone. A Tool is a key in several tables
# and its rows are spelled alike, so an unscoped substitution also rewrites the
# version probe next door -- which reads as a Tool that answers nothing rather
# than as a patched test.
probe_forced() {
  local copy spec tool answer
  copy="$(script_copy)"
  for spec in "$@"; do
    tool="${spec%%=*}"; answer="${spec#*=}"
    sed -i -E "/^declare -A TOOL_PRESENT=\(/,/^\)/ s|^  \[$tool\]='.*'\$|  [$tool]='$answer'|" "$copy"
    # A silently unapplied patch would make the test assert nothing -- and read
    # inside the block, or a row in another table could vouch for it.
    sed -n '/^declare -A TOOL_PRESENT=(/,/^)/p' "$copy" | grep -qF "  [$tool]='$answer'"
  done
  printf '%s' "$copy"
}

# An executable of that name on PATH, which is how the probes read presence.
# It answers `<name> 1.0.0`, so a version probe finds `1.0.0`; a second argument
# replaces that body, which is how a test says what a probe will find -- or that
# it was asked at all.
fake_tool() { fake_tool_at "$TEST_TMP/bin" "$@"; export PATH="$TEST_TMP/bin:$PATH"; }

# An executable of that name on PATH that answers a version and records being
# run, in `$TEST_TMP/ran-<name>`. The witness for "nothing executed this Tool":
# a presence probe reads `command -v` or `[[ -x ]]`, neither of which runs the
# binary, so a marker that appears is something that shelled out to the Tool
# itself.
witness_tool() { fake_tool "$1" "touch '$TEST_TMP/ran-$1'; echo '$1 9.9.9'"; }

# The same, somewhere else and off PATH: a probe that has to find a binary by
# its own means -- sourcing nvm, or globbing a cache -- can only be tested
# against one the test did not put in front of it.
fake_tool_at() {
  mkdir -p "$1"
  printf '#!/bin/sh\n%s\n' "${3:-echo \"$2 1.0.0\"}" >"$1/$2"
  chmod +x "$1/$2"
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
  # The Install Steps and nothing else, read off the registry -- base
  # dependencies among them since #68, which is why it no longer needs a line of
  # its own here.
  local fn steps
  steps="$(registry_install_steps)"
  # A sed that quietly matched fewer -- because the table was reformatted --
  # would leave real installers in place and the next real-run test would run
  # one. Checked against what the run itself plans, which reaches the same
  # Install Steps by another route, so the count can neither drift below the
  # registry nor be satisfied by the parse that produced it.
  [ "$(grep -c . <<<"$steps")" -eq "$(planned_step_count)" ]
  for fn in $steps; do
    override "$fn() { :; }"
  done
  script_copy
}

# The body of one Install Step, brace to brace. The static assertions in
# `test/cli.bats` are all "no Step does X", and every one of them needs the same
# extraction, so it lives here rather than three times over (#70).
step_body() {
  local body
  body="$(awk -v fn="$1" '
    $0 == fn "() {" { inside = 1; next }
    inside && /^}$/  { exit }
    inside           { print }
  ' "$SETUP_SH")"
  # A Step whose body did not parse would make every static guard below pass
  # over nothing, which is the same silent-no-match failure `override` counts
  # lines to avoid and `runnable` counts Steps to avoid (#70).
  [ -n "$body" ] || { echo "step_body: no body parsed for $1" >&2; return 1; }
  printf '%s\n' "$body"
}

# "No Install Step body contains <pattern>." Three static guards want the same
# walk and differ only in the predicate, so the walk is written once.
no_step_body_line_matches() {
  local pattern="$1" why="$2" step line body
  while read -r step; do
    # Assigned, then checked. Reading `step_body` through a process
    # substitution would discard its exit status, so a Step whose body failed to
    # parse would be walked over in silence -- the guard would pass by examining
    # nothing, which is the failure it exists to prevent (#70).
    body="$(step_body "$step")" || return 1
    while read -r line; do
      [[ "$line" =~ ^[[:space:]]*# ]] && continue
      [[ "$line" =~ $pattern ]] || continue
      echo "$step: $line" >&2
      echo "$why" >&2
      return 1
    done <<<"$body"
  done < <(registry_install_steps)
}

# The PATH lines `write_reachability` writes, read off the function itself --
# the file's contents are stated there and derived here, never restated (#58).
reachability_lines() {
  awk '/^write_reachability\(\) \{/ { inside = 1 }
       inside && /^export PATH=/       { print }
       inside && /^}$/                 { exit }' "$SETUP_SH"
}
