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
  for tab in All Profiles Languages Frontend Backend/DB AI/ML Infra/DevOps; do
    [[ "$plain" == *"$tab"* ]]
  done
  # tab 0 is active, so the reverse-video sequence sits on " All "
  [[ "$output" == *$'\033[7;36m All '* ]]
}

@test "__tui_tab next advances the tab and wraps" {
  local n=7  # ${#TUI_TABS[@]}
  "$SETUP_SH" __tui_tab next
  [ "$(cat "$TUI_STATE/tab")" -eq 1 ]
  for ((i = 1; i < n; i++)); do "$SETUP_SH" __tui_tab next; done
  [ "$(cat "$TUI_STATE/tab")" -eq 0 ]
}

@test "__tui_tab prev wraps backwards to the last tab" {
  "$SETUP_SH" __tui_tab prev
  [ "$(cat "$TUI_STATE/tab")" -eq 6 ]
}

@test "__tui_list follows the current tab" {
  echo 1 >"$TUI_STATE/tab"   # Profiles
  run "$SETUP_SH" __tui_list
  [ "$status" -eq 0 ]
  [[ "$(strip_ansi <<<"$output")" == *"◆ default"* ]]
  [[ "$(strip_ansi <<<"$output")" != *"· gh"* ]]

  echo 3 >"$TUI_STATE/tab"   # Frontend
  run "$SETUP_SH" __tui_list
  [ "$status" -eq 0 ]
  [[ "$(strip_ansi <<<"$output")" == *"· bun"* ]]
  [[ "$(strip_ansi <<<"$output")" != *"· gh"* ]]
}

@test "__tui_click maps a header column onto its tab" {
  "$SETUP_SH" __tui_header >/dev/null    # writes the column map
  # column 3 lands inside " All " (tab 0); a column inside " Profiles " is tab 1
  FZF_CLICK_HEADER_COLUMN=3 "$SETUP_SH" __tui_click
  [ "$(cat "$TUI_STATE/tab")" -eq 0 ]
  FZF_CLICK_HEADER_COLUMN=8 "$SETUP_SH" __tui_click
  [ "$(cat "$TUI_STATE/tab")" -eq 1 ]
}
