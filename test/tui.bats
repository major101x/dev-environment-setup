#!/usr/bin/env bats
#
# The fzf callbacks. fzf re-runs setup.sh for each of these, so they are the
# one part of the TUI that is testable without a tty — and the part with the
# two silent failure modes (issue #13):
#
#   1. the `exec > >(tee -a "$LOG_FILE")` redirect at the top of setup.sh —
#      a callback that does not skip it sends its stdout to the log instead of
#      to fzf, and the TUI renders empty with no error.
#   2. `set -e` on arithmetic — a false `(( ))` as a *bare* statement aborts the
#      callback mid-render, silently truncating its output. (Bare is the word
#      that matters: bash exempts a false `(( ))` that is the non-final command
#      of an `&&` list.) The guard is that a render reaches its closing border.
#
# `bash -n` catches neither. These assertions do.

load helpers

setup() { sandbox; }
teardown() { sandbox_teardown; }

# --- failure mode 1: stdout must reach fzf, not the log -----------------------
#
# "returns non-empty on stdout" is the smoke test, not the guard: `tee` also
# forwards to the original stdout, so a callback that wrongly inherits the
# redirect can still look non-empty here while rendering an empty TUI. The
# assertion that actually pins the bug down is the log one below.

@test "__tui_list returns non-empty on stdout" {
  run "$SETUP_SH" __tui_list
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "__tui_header returns non-empty on stdout" {
  run "$SETUP_SH" __tui_header
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "__tui_preview returns non-empty on stdout" {
  run "$SETUP_SH" __tui_preview "$(list_row tool gh)"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "callbacks write nothing to the log file" {
  "$SETUP_SH" __tui_list >/dev/null
  "$SETUP_SH" __tui_header >/dev/null
  "$SETUP_SH" __tui_preview "$(list_row tool gh)" >/dev/null
  "$SETUP_SH" __tui_toggle "$(list_row profile go)" >/dev/null
  "$SETUP_SH" __tui_resolve go >/dev/null <<<"$(list_row profile go)"
  [ ! -e "$LOG_FILE" ]
}

# --- failure mode 2: output must be complete, not truncated -------------------

@test "__tui_preview renders the whole Selected Toolset panel" {
  run "$SETUP_SH" __tui_preview "$(list_row tool gh)"
  [ "$status" -eq 0 ]
  [[ "$(strip_ansi <<<"$output" | tail -n1)" == ╰*╯ ]]
}

# The width floor is its own branch: everything below it computes the panel's
# inner width from 24 rather than from FZF_PREVIEW_COLUMNS.
@test "__tui_preview renders the whole panel below its 24-column width floor" {
  FZF_PREVIEW_COLUMNS=10 run "$SETUP_SH" __tui_preview "$(list_row tool gh)"
  [ "$status" -eq 0 ]
  [[ "$(strip_ansi <<<"$output" | tail -n1)" == ╰*╯ ]]
}

# --- regression: unbound TUI_STATE under set -u ------------------------------

@test "__tui_list with TUI_STATE unset produces no stderr" {
  run --separate-stderr env -u TUI_STATE "$SETUP_SH" __tui_list
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ -n "$output" ]
}

@test "__tui_header with TUI_STATE unset renders without writing to /" {
  run --separate-stderr env -u TUI_STATE "$SETUP_SH" __tui_header
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ -n "$output" ]
  [ ! -e /cols ]
}

@test "__tui_tab with TUI_STATE unset fails loudly instead of writing to /" {
  run --separate-stderr env -u TUI_STATE "$SETUP_SH" __tui_tab next
  [ "$status" -ne 0 ]
  [[ "$stderr" == *TUI_STATE* ]]
  [ ! -e /tab ]
}

@test "__tui_click with TUI_STATE unset fails loudly instead of writing to /" {
  run --separate-stderr env -u TUI_STATE "$SETUP_SH" __tui_click
  [ "$status" -ne 0 ]
  [[ "$stderr" == *TUI_STATE* ]]
  [ ! -e /tab ]
}

# --- regression: ADR-0003, `go` is both a Profile key and a Tool key ---------

@test "Profile \`go\` resolves to 3 tools (go golangci-lint air)" {
  local row; row="$(list_row profile go)"
  FZF_SELECT_COUNT=1 run "$SETUP_SH" __tui_preview "$row" "$row"
  [ "$status" -eq 0 ]
  local plain; plain="$(strip_ansi <<<"$output")"
  [[ "$plain" == *"PROFILE  go"* ]]
  [[ "$plain" == *"3 tools will install:"* ]]
  [[ "$plain" == *"air go golangci-lint"* ]]
}

@test "Tool \`go\` resolves to 1 tool" {
  local row; row="$(list_row tool go)"
  FZF_SELECT_COUNT=1 run "$SETUP_SH" __tui_preview "$row" "$row"
  [ "$status" -eq 0 ]
  local plain; plain="$(strip_ansi <<<"$output")"
  [[ "$plain" == *"TOOL     go"* ]]
  [[ "$plain" == *"1 tools will install:"* ]]
  # and that one tool is `go` itself, not some other single tool
  [ "$(grep -A1 '1 tools will install:' <<<"$plain" | tail -n1 | tr -d '│ ')" = go ]
}

# --- the selection panel reads FZF_SELECT_COUNT, not {+} ---------------------

@test "selection panel says \"nothing selected\" at FZF_SELECT_COUNT=0" {
  local row; row="$(list_row profile go)"
  FZF_SELECT_COUNT=0 run "$SETUP_SH" __tui_preview "$row" "$row"
  [ "$status" -eq 0 ]
  [[ "$(strip_ansi <<<"$output")" == *"nothing selected yet"* ]]
}

# --- tabs --------------------------------------------------------------------

@test "__tui_header marks the current tab and lists every Category" {
  run "$SETUP_SH" __tui_header
  [ "$status" -eq 0 ]
  local plain; plain="$(strip_ansi <<<"$output")"
  for tab in All Languages Frontend Backend/DB AI/ML Infra/DevOps; do
    [[ "$plain" == *"$tab"* ]]
  done
  # ADR-0009 removed the Profiles tab: it listed no Tool rows, so a Profile
  # could never stamp on the one tab built for picking Profiles.
  [[ "$plain" != *"Profiles"* ]]
  # tab 0 is active, so the reverse-video sequence sits on " All "
  [[ "$output" == *$'\033[7;36m All '* ]]
}

@test "__tui_tab next advances the tab and wraps" {
  local n=6  # ${#TUI_TABS[@]}
  "$SETUP_SH" __tui_tab next
  [ "$(cat "$TUI_STATE/tab")" -eq 1 ]
  for ((i = 1; i < n; i++)); do "$SETUP_SH" __tui_tab next; done
  [ "$(cat "$TUI_STATE/tab")" -eq 0 ]
}

@test "__tui_tab prev wraps backwards to the last tab" {
  "$SETUP_SH" __tui_tab prev
  [ "$(cat "$TUI_STATE/tab")" -eq 5 ]
}

@test "__tui_list follows the current tab" {
  echo 1 >"$TUI_STATE/tab"   # Languages
  run "$SETUP_SH" __tui_list
  [ "$status" -eq 0 ]
  [[ "$(strip_ansi <<<"$output")" == *"· go"* ]]
  [[ "$(strip_ansi <<<"$output")" != *"· gh"* ]]

  echo 2 >"$TUI_STATE/tab"   # Frontend
  run "$SETUP_SH" __tui_list
  [ "$status" -eq 0 ]
  [[ "$(strip_ansi <<<"$output")" == *"· bun"* ]]
  [[ "$(strip_ansi <<<"$output")" != *"· gh"* ]]
}

# The macro needs a list that holds every member, so Profile rows may only sit
# on a tab that also holds Tools. The All tab is the only one. See ADR-0009.
@test "the All tab is the only tab with Profile rows" {
  run "$SETUP_SH" __tui_list
  [ "$status" -eq 0 ]
  [[ "$(strip_ansi <<<"$output")" == *"◆ default"* ]]
  [[ "$(strip_ansi <<<"$output")" == *"· gh"* ]]

  local n=6 i
  for ((i = 1; i < n; i++)); do
    echo "$i" >"$TUI_STATE/tab"
    run "$SETUP_SH" __tui_list
    [ "$status" -eq 0 ]
    [[ "$(strip_ansi <<<"$output")" != *◆* ]]
  done
}

@test "__tui_click maps a header column onto its tab" {
  "$SETUP_SH" __tui_header >/dev/null    # writes the column map
  # column 3 lands inside " All " (tab 0); a column inside " Languages " is tab 1
  FZF_CLICK_HEADER_COLUMN=3 "$SETUP_SH" __tui_click
  [ "$(cat "$TUI_STATE/tab")" -eq 0 ]
  FZF_CLICK_HEADER_COLUMN=8 "$SETUP_SH" __tui_click
  [ "$(cat "$TUI_STATE/tab")" -eq 1 ]
}

# --- ADR-0009: a Profile row is a macro that stamps its Tools ----------------
#
# `__tui_toggle` is what TAB is bound to. It prints the fzf action chain to run,
# so the whole rule — stamp, or fall back to a plain label — is a string these
# tests can read. The fallback string is the one fzf ran before this existed.

@test "__tui_toggle on a Tool row is a plain toggle" {
  run "$SETUP_SH" __tui_toggle "$(list_row tool gh)"
  [ "$status" -eq 0 ]
  [ "$output" = "toggle+down+refresh-preview" ]
}

@test "__tui_toggle on a Profile row stamps every member Tool" {
  local expect="toggle" t
  for t in go golangci-lint air; do expect+="+pos($(list_pos tool "$t"))+select"; done
  # and leaves the cursor where a plain toggle would have left it
  expect+="+pos($(list_pos profile go))+down+refresh-preview"
  run "$SETUP_SH" __tui_toggle "$(list_row profile go)"
  [ "$status" -eq 0 ]
  [ "$output" = "$expect" ]
}

# ADR-0003 again: the Tool `go` and the Profile `go` are different rows, and
# only the Profile one is a macro.
@test "__tui_toggle on the Tool \`go\` does not stamp the Profile \`go\`" {
  run "$SETUP_SH" __tui_toggle "$(list_row tool go)"
  [ "$status" -eq 0 ]
  [ "$output" = "toggle+down+refresh-preview" ]
  [ ! -e "$TUI_STATE/stamped" ]
}

@test "a stamp is recorded so ENTER knows not to expand the Profile again" {
  "$SETUP_SH" __tui_toggle "$(list_row profile go)" >/dev/null
  grep -qx go "$TUI_STATE/stamped"
}

# `pos(N)` indexes the MATCHED list and clamps silently, so a position computed
# against the unfiltered list would check the wrong row rather than fail.
@test "__tui_toggle with a query active is a plain label, not a partial stamp" {
  FZF_QUERY=go run "$SETUP_SH" __tui_toggle "$(list_row profile go)"
  [ "$status" -eq 0 ]
  [ "$output" = "toggle+down+refresh-preview" ]
  [ ! -e "$TUI_STATE/stamped" ]
}

# The stamp is one-way: it only ever adds, so turning the label off must not
# take the user's Tools with it.
@test "un-toggling a selected Profile unstamps nothing" {
  local row; row="$(list_row profile go)"
  FZF_SELECT_COUNT=1 run "$SETUP_SH" __tui_toggle "$row" "$row"
  [ "$status" -eq 0 ]
  [ "$output" = "toggle+down+refresh-preview" ]
}

@test "a Profile still stamps while a different Profile is selected" {
  local go_row rust_row
  go_row="$(list_row profile go)"; rust_row="$(list_row profile rust)"
  FZF_SELECT_COUNT=1 run "$SETUP_SH" __tui_toggle "$go_row" "$rust_row"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pos($(list_pos tool air))+select"* ]]
}

# Complete or nothing: a stamp that could only place two of three Tools is the
# silent-wrong result this harness exists to catch, so it does not fire at all.
@test "a Profile whose member is missing from the list is a plain label" {
  sed 's/^  \[go\]="go golangci-lint air"/  [go]="go golangci-lint air nosuchtool"/' \
    "$SETUP_SH" >"$TEST_TMP/setup.sh"
  chmod +x "$TEST_TMP/setup.sh"
  grep -q 'nosuchtool' "$TEST_TMP/setup.sh"
  run "$TEST_TMP/setup.sh" __tui_toggle "$("$TEST_TMP/setup.sh" __tui_list | grep -m1 -F '◆ go ')"
  [ "$status" -eq 0 ]
  [ "$output" = "toggle+down+refresh-preview" ]
  [ ! -e "$TUI_STATE/stamped" ]
}

# Unlike __tui_tab and __tui_click, this one may not die when there is no state
# dir: its stdout IS the key binding, and a callback that prints nothing leaves
# TAB doing nothing at all. It degrades to the plain toggle instead.
@test "__tui_toggle with TUI_STATE unset degrades to a plain toggle" {
  local row; row="$(list_row profile go)"
  run --separate-stderr env -u TUI_STATE "$SETUP_SH" __tui_toggle "$row"
  [ "$status" -eq 0 ]
  [ "$output" = "toggle+down+refresh-preview" ]
  [ -z "$stderr" ]
  [ ! -e /stamped ]
}

# --- ADR-0009: ENTER expands an unstamped Profile, never a stamped one -------

@test "__tui_resolve expands an unstamped Profile" {
  run "$SETUP_SH" __tui_resolve <<<"$(list_row profile go)"
  [ "$status" -eq 0 ]
  [ "$(grep '^profiles: ' <<<"$output")" = "profiles: go" ]
  [ "$(grep '^tools: ' <<<"$output")" = "tools: go golangci-lint air" ]
}

@test "__tui_resolve does not expand a stamped Profile, so an unchecked member stays unchecked" {
  local rows
  rows="$(list_row profile go)"$'\n'"$(list_row tool go)"$'\n'"$(list_row tool golangci-lint)"
  run "$SETUP_SH" __tui_resolve go <<<"$rows"
  [ "$status" -eq 0 ]
  # the label survives, for config.json provenance...
  [ "$(grep '^profiles: ' <<<"$output")" = "profiles: go" ]
  # ...but `air`, unchecked in the picker, is not resurrected
  [ "$(grep '^tools: ' <<<"$output")" = "tools: go golangci-lint" ]
}

@test "__tui_resolve unions a stamped Profile with an unstamped one" {
  local rows
  rows="$(list_row profile go)"$'\n'"$(list_row tool go)"$'\n'"$(list_row profile rust)"
  run "$SETUP_SH" __tui_resolve go <<<"$rows"
  [ "$status" -eq 0 ]
  [ "$(grep '^profiles: ' <<<"$output")" = "profiles: go rust" ]
  [ "$(grep '^tools: ' <<<"$output")" = "tools: go rust" ]
}

# The panel is where the user sees the rule land: with `go` stamped and `air`
# unchecked, it has to say 1 Tool and not the Profile's 3. Contrast with
# "Profile `go` resolves to 3 tools" above, which is the unstamped case.
@test "the Selected Toolset panel does not re-expand a stamped Profile" {
  echo go >"$TUI_STATE/stamped"
  local prof tool_go
  prof="$(list_row profile go)"; tool_go="$(list_row tool go)"
  FZF_SELECT_COUNT=2 run "$SETUP_SH" __tui_preview "$prof" "$prof" "$tool_go"
  [ "$status" -eq 0 ]
  local plain; plain="$(strip_ansi <<<"$output")"
  [[ "$plain" == *"profiles: go"* ]]
  [[ "$plain" == *"1 tools will install:"* ]]
}

@test "__tui_resolve deduplicates a Tool checked twice over" {
  local rows
  rows="$(list_row profile go)"$'\n'"$(list_row tool go)"
  run "$SETUP_SH" __tui_resolve <<<"$rows"
  [ "$status" -eq 0 ]
  [ "$(grep '^tools: ' <<<"$output")" = "tools: go golangci-lint air" ]
}
