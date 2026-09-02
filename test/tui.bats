#!/usr/bin/env bats
#
# The fzf callbacks. fzf re-runs setup.sh for each of these, so they are the
# one part of the TUI that is testable without a tty — and the part with the
# two silent failure modes (issue #13):
#
#   1. the log. Under the old `exec > >(tee -a "$LOG_FILE")` redirect a callback
#      that did not skip it sent its stdout to the log instead of to fzf, and
#      the TUI rendered empty with no error. The redirect is gone (ADR-0012) and
#      only `main` opens the log, so the assertion below now guards that rule:
#      a callback, which never reaches `main`, writes nothing to the log.
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
# forwarded to the original stdout, so a callback that wrongly wrote to the log
# could still look non-empty here while rendering an empty TUI. The assertion
# that actually pins the bug down is the log one below.

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
  "$SETUP_SH" __tui_seed >/dev/null
  "$SETUP_SH" __tui_toggle "$(list_row profile go)" >/dev/null
  "$SETUP_SH" __tui_resolve >/dev/null
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

# TAB is an `execute-silent` now, not a `transform`: its stdout is no longer a
# key binding, so it has no reason to degrade quietly the way ADR-0009's
# version had to. With nowhere to record a check it says so and stops.
@test "__tui_toggle with TUI_STATE unset fails loudly instead of writing to /" {
  local row; row="$(list_row profile go)"
  run --separate-stderr env -u TUI_STATE "$SETUP_SH" __tui_toggle "$row"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *TUI_STATE* ]]
  [ ! -e /checked ]
  [ ! -e /profiles ]
}

# --- ADR-0010: the list paints the check, one field left of the type glyph ---

@test "__tui_list paints an unchecked marker in front of the type glyph" {
  run "$SETUP_SH" __tui_list
  [ "$status" -eq 0 ]
  local plain; plain="$(strip_ansi <<<"$output")"
  [[ "$plain" == *"[ ] · gh"* ]]
  [[ "$plain" == *"[ ] ◆ go"* ]]
}

@test "__tui_list paints a checked marker for a Tool in the state" {
  echo gh >"$TUI_STATE/checked"
  [ "$(row_check tool gh)" = "[x]" ]
  [ "$(row_check tool node)" = "[ ]" ]
}

@test "__tui_list paints a checked marker for a Profile in the state" {
  echo go >"$TUI_STATE/profiles"
  [ "$(row_check profile go)" = "[x]" ]
  [ "$(row_check profile rust)" = "[ ]" ]
  # the Profile set and the Tool set are separate: a checked Profile row does
  # not check the Tool row that shares its key
  [ "$(row_check tool go)" = "[ ]" ]
}

# ADR-0003 survives the new marker: the glyph still types the row, one field
# to the right. `go` is both a Profile key and a Tool key, and the parser has
# to keep telling them apart with a check in front of the glyph.
@test "the type glyph still types a row once a check sits in front of it" {
  echo go >"$TUI_STATE/profiles"
  printf 'go\n' >"$TUI_STATE/checked"
  run "$SETUP_SH" __tui_preview "$(list_row profile go)"
  [ "$status" -eq 0 ]
  [[ "$(strip_ansi <<<"$output")" == *"PROFILE  go"* ]]
  run "$SETUP_SH" __tui_preview "$(list_row tool go)"
  [ "$status" -eq 0 ]
  [[ "$(strip_ansi <<<"$output")" == *"TOOL     go"* ]]
}

# --- ADR-0010: the Default Toolset is seeded once, before fzf starts ---------

@test "__tui_seed checks exactly the Default Toolset" {
  "$SETUP_SH" __tui_seed
  local d
  for d in gh fastfetch opencode node puppeteer chrome docker pip eza exa-mcp pocock-skills; do
    grep -qx "$d" "$TUI_STATE/checked"
  done
  [ "$(grep -c . "$TUI_STATE/checked")" -eq 11 ]
  # seeding is not a user toggle, so it leaves no Profile provenance behind
  [ ! -s "$TUI_STATE/profiles" ]
}

@test "the seeded Default Toolset shows as checked rows in the list" {
  "$SETUP_SH" __tui_seed
  [ "$(row_check tool gh)" = "[x]" ]
  [ "$(row_check tool docker)" = "[x]" ]
  [ "$(row_check tool go)" = "[ ]" ]
}

# "Presets, not locks" is false if the preset reapplies itself behind the user,
# so a seeded Tool must stay individually uncheckable.
@test "a seeded Tool can be unchecked and stays unchecked" {
  "$SETUP_SH" __tui_seed
  "$SETUP_SH" __tui_toggle "$(list_row tool docker)"
  [ "$(row_check tool docker)" = "[ ]" ]
  "$SETUP_SH" __tui_list >/dev/null
  "$SETUP_SH" __tui_tab next
  "$SETUP_SH" __tui_tab prev
  [ "$(row_check tool docker)" = "[ ]" ]
}

# --- ADR-0010: TAB records into the state ------------------------------------

@test "__tui_toggle checks a Tool row, and a second TAB unchecks it" {
  "$SETUP_SH" __tui_toggle "$(list_row tool gh)"
  grep -qx gh "$TUI_STATE/checked"
  [ "$(row_check tool gh)" = "[x]" ]

  "$SETUP_SH" __tui_toggle "$(list_row tool gh)"
  ! grep -qx gh "$TUI_STATE/checked"
  [ "$(row_check tool gh)" = "[ ]" ]
}

@test "__tui_toggle on a Profile row checks every member Tool" {
  "$SETUP_SH" __tui_toggle "$(list_row profile go)"
  grep -qx go "$TUI_STATE/profiles"
  local t
  for t in go golangci-lint air; do grep -qx "$t" "$TUI_STATE/checked"; done
  [ "$(row_check tool air)" = "[x]" ]
}

# ADR-0003 again: the Tool `go` and the Profile `go` are different rows, and
# only the Profile one is a macro.
@test "__tui_toggle on the Tool \`go\` does not fire the Profile \`go\`" {
  "$SETUP_SH" __tui_toggle "$(list_row tool go)"
  grep -qx go "$TUI_STATE/checked"
  [ ! -s "$TUI_STATE/profiles" ]
  ! grep -qx air "$TUI_STATE/checked"
}

# The macro is one-way: turning the label off must not take the user's Tools
# with it. Per-Tool provenance ("was `air` stamped, or did you check it
# yourself?") answers a question nobody asked. See ADR-0009.
@test "un-toggling a Profile drops the label and not its Tools" {
  "$SETUP_SH" __tui_toggle "$(list_row profile go)"
  "$SETUP_SH" __tui_toggle "$(list_row profile go)"
  [ ! -s "$TUI_STATE/profiles" ]
  local t
  for t in go golangci-lint air; do grep -qx "$t" "$TUI_STATE/checked"; done
}

# ADR-0009's known trade-off, now deleted with the complete-or-label rule:
# unchecking a member of a Profile works while a query is active, because
# nothing is computed from a list position any more.
@test "__tui_toggle records the same check with a query active" {
  FZF_QUERY=go "$SETUP_SH" __tui_toggle "$(list_row profile go)"
  grep -qx go "$TUI_STATE/profiles"
  grep -qx air "$TUI_STATE/checked"
  FZF_QUERY=air "$SETUP_SH" __tui_toggle "$(list_row tool air)"
  ! grep -qx air "$TUI_STATE/checked"
}

@test "checking a Tool twice over records it once" {
  "$SETUP_SH" __tui_toggle "$(list_row profile go)"
  "$SETUP_SH" __tui_toggle "$(list_row tool rust)"
  "$SETUP_SH" __tui_toggle "$(list_row profile rust)"
  [ "$(grep -c '^rust$' "$TUI_STATE/checked")" -eq 1 ]
}

# --- ADR-0010: this is the bug the decision exists to kill --------------------
#
# fzf's `reload` clears its own selection — measured against 0.74.3 — and the
# Category tab strip reloads on every switch. Checking six Tools and clicking
# `Frontend` used to throw all six away, silently, with ENTER then falling
# through to the Default Toolset.

@test "checks survive switching Category tabs with the arrow keys" {
  "$SETUP_SH" __tui_toggle "$(list_row tool bun)"
  "$SETUP_SH" __tui_toggle "$(list_row tool vite)"
  "$SETUP_SH" __tui_tab next
  "$SETUP_SH" __tui_tab next     # Frontend
  [ "$(cat "$TUI_STATE/tab")" -eq 2 ]
  [ "$(row_check tool bun)" = "[x]" ]
  [ "$(row_check tool vite)" = "[x]" ]

  run "$SETUP_SH" __tui_resolve
  [ "$status" -eq 0 ]
  [ "$(grep '^tools: ' <<<"$output")" = "tools: bun vite" ]
}

@test "checks survive clicking a Category tab" {
  "$SETUP_SH" __tui_toggle "$(list_row profile go)"
  "$SETUP_SH" __tui_header >/dev/null          # writes the column map
  FZF_CLICK_HEADER_COLUMN=8 "$SETUP_SH" __tui_click
  [ "$(cat "$TUI_STATE/tab")" -eq 1 ]
  [ "$(row_check tool air)" = "[x]" ]
  grep -qx go "$TUI_STATE/profiles"
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

@test "the header says what ENTER and ESC do" {
  run "$SETUP_SH" __tui_header
  [ "$status" -eq 0 ]
  local plain; plain="$(strip_ansi <<<"$output")"
  [[ "$plain" == *"ENTER installs"* ]]
  [[ "$plain" == *"ESC cancels"* ]]
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

# --- ADR-0010: the preview reads the state, not fzf's selection --------------

@test "the Selected Toolset panel says nothing is checked on an empty state" {
  run "$SETUP_SH" __tui_preview "$(list_row profile go)"
  [ "$status" -eq 0 ]
  [[ "$(strip_ansi <<<"$output")" == *"nothing checked yet"* ]]
}

@test "the Selected Toolset panel counts the state, not the row it is given" {
  "$SETUP_SH" __tui_toggle "$(list_row profile go)"
  # hovering an unrelated Tool row must not change the answer
  run "$SETUP_SH" __tui_preview "$(list_row tool bun)"
  [ "$status" -eq 0 ]
  local plain; plain="$(strip_ansi <<<"$output")"
  [[ "$plain" == *"profiles: go"* ]]
  [[ "$plain" == *"3 tools will install:"* ]]
  [[ "$plain" == *"air go golangci-lint"* ]]
}

@test "the Selected Toolset panel drops a Tool the user unchecked" {
  "$SETUP_SH" __tui_toggle "$(list_row profile go)"
  "$SETUP_SH" __tui_toggle "$(list_row tool air)"
  run "$SETUP_SH" __tui_preview "$(list_row profile go)"
  [ "$status" -eq 0 ]
  local plain; plain="$(strip_ansi <<<"$output")"
  [[ "$plain" == *"profiles: go"* ]]
  [[ "$plain" == *"2 tools will install:"* ]]
}

# config.json gets the Profile label whether or not any of its Tools survived,
# so a panel that hid it would disagree with what --replay saves.
@test "the Selected Toolset panel shows a Profile label with nothing checked" {
  "$SETUP_SH" __tui_toggle "$(list_row profile rust)"
  "$SETUP_SH" __tui_toggle "$(list_row tool rust)"
  run "$SETUP_SH" __tui_preview "$(list_row profile rust)"
  [ "$status" -eq 0 ]
  local plain; plain="$(strip_ansi <<<"$output")"
  [[ "$plain" == *"profiles: rust"* ]]
  [[ "$plain" == *"nothing checked yet"* ]]
}

@test "the preview says TAB will check a Profile's Tools" {
  run "$SETUP_SH" __tui_preview "$(list_row profile go)"
  [ "$status" -eq 0 ]
  [[ "$(strip_ansi <<<"$output")" == *"TAB checks these Tools"* ]]
}

@test "the preview of a checked Profile says the label is what TAB drops" {
  "$SETUP_SH" __tui_toggle "$(list_row profile go)"
  run "$SETUP_SH" __tui_preview "$(list_row profile go)"
  [ "$status" -eq 0 ]
  local plain; plain="$(strip_ansi <<<"$output")"
  [[ "$plain" == *"uncheck any and"* ]]
  [[ "$plain" == *"the label, not the Tools"* ]]
}

# --- #24: the closure is visible before ENTER --------------------------------
#
# Resolution adds a missing prerequisite to the Toolset (ADR-0014). #24 is that
# addition arriving where the decision can still be taken back: the panel a
# person reads before ENTER, rather than a line printed once the run has begun.
# The closure here is the same `add_missing_prerequisites` the run calls, so
# what the panel promises and what ENTER installs cannot disagree.

@test "the panel names an auto-added prerequisite and the pick that pulled it in" {
  local sh; sh="$(probe_forced pip=false eza=false jupyter=false)"; SETUP_SH="$sh"
  printf 'jupyter\n' >"$TUI_STATE/checked"
  run "$sh" __tui_preview "$(list_row tool jupyter)"
  [ "$status" -eq 0 ]
  local plain; plain="$(strip_ansi <<<"$output")"
  [[ "$plain" == *"added as prerequisites:"* ]]
  [[ "$plain" == *"+ pip - required by jupyter (its install step also delivers eza)"* ]]
  # The count is what will install, not what was clicked.
  [[ "$plain" == *"2 tools will install:"* ]]
}

# "Live" is the whole point: an addition that only appeared once is a line the
# user has already scrolled past by the time they change their mind.
@test "the panel reflects an auto-addition as the selection changes" {
  local sh; sh="$(probe_forced pip=false eza=false jupyter=false)"; SETUP_SH="$sh"
  run "$sh" __tui_preview "$(list_row tool jupyter)"
  [[ "$(strip_ansi <<<"$output")" != *"+ pip"* ]]

  "$sh" __tui_toggle "$(list_row tool jupyter)"
  run "$sh" __tui_preview "$(list_row tool jupyter)"
  [[ "$(strip_ansi <<<"$output")" == *"+ pip - required by jupyter"* ]]

  "$sh" __tui_toggle "$(list_row tool jupyter)"
  run "$sh" __tui_preview "$(list_row tool jupyter)"
  [[ "$(strip_ansi <<<"$output")" != *"+ pip"* ]]
}

# Missing is the whole of it (ADR-0014), and the panel says exactly what
# resolution will do: a prerequisite already on the machine is not added, so it
# is not announced either.
@test "the panel does not add a prerequisite the machine already has" {
  local sh; sh="$(probe_forced pip=true jupyter=false)"; SETUP_SH="$sh"
  printf 'jupyter\n' >"$TUI_STATE/checked"
  run "$sh" __tui_preview "$(list_row tool jupyter)"
  [ "$status" -eq 0 ]
  local plain; plain="$(strip_ansi <<<"$output")"
  [[ "$plain" != *"added as prerequisites:"* ]]
  [[ "$plain" == *"1 tools will install:"* ]]
}

# The list is the source of truth for a check (ADR-0010), so a row that will
# install cannot read `[ ]`. It is not `[x]` either: the user did not pick it.
@test "an auto-added prerequisite is marked in the list rather than left looking unchecked" {
  local sh; sh="$(probe_forced pip=false eza=false jupyter=false)"; SETUP_SH="$sh"
  printf 'jupyter\n' >"$TUI_STATE/checked"
  [ "$(row_check tool pip)" = "[+]" ]
  [ "$(row_check tool jupyter)" = "[x]" ]
}

# Profiles are presets, not locks (ADR-0009), and an auto-addition is no more a
# lock than a Profile is. TAB on a row that will install always means "not
# that one" -- adopting it as a direct pick would leave TAB with nothing to do.
@test "TAB on an auto-added prerequisite declines it rather than adopting it" {
  local sh; sh="$(probe_forced pip=false eza=false jupyter=false)"; SETUP_SH="$sh"
  printf 'jupyter\n' >"$TUI_STATE/checked"
  "$sh" __tui_toggle "$(list_row tool pip)"
  [ "$(row_check tool pip)" = "[-]" ]
  [ "$(tui_state declined)" = "pip" ]
}

# Touching one row must not change two: the dependent stays checked, and the
# consequence is spelled out instead of applied behind the user.
@test "the panel marks the dependent of a declined prerequisite as unsatisfiable" {
  local sh; sh="$(probe_forced pip=false eza=false jupyter=false)"; SETUP_SH="$sh"
  printf 'jupyter\n' >"$TUI_STATE/checked"
  "$sh" __tui_toggle "$(list_row tool pip)"
  [ "$(row_check tool jupyter)" = "[x]" ]
  run "$sh" __tui_preview "$(list_row tool pip)"
  [ "$status" -eq 0 ]
  local plain; plain="$(strip_ansi <<<"$output")"
  [[ "$plain" == *"will be skipped:"* ]]
  [[ "$plain" == *"! jupyter - unmet dependency: pip"* ]]
  [[ "$plain" != *"added as prerequisites:"* ]]
  # And it is not also counted among what will install: a count that promises a
  # Tool two lines above the line withdrawing it is the confusion the panel is
  # there to remove.
  [[ "$plain" == *"0 tools will install:"* ]]
}

# An Install Step is many-to-one (ADR-0004): `install_pip_eza` delivers pip
# whichever of the two was picked, so declining pip with eza checked does not
# take pip off the machine and the dependent is not stuck. The panel must not
# promise a skip the run will not perform -- it asks the run-time gate's
# question of the plan.
@test "a decline another pick's Install Step still delivers is not a skip" {
  local sh; sh="$(probe_forced pip=false eza=false jupyter=false)"; SETUP_SH="$sh"
  printf 'jupyter\neza\n' >"$TUI_STATE/checked"
  "$sh" __tui_toggle "$(list_row tool pip)"
  [ "$(tui_state declined)" = "pip" ]
  run "$sh" __tui_preview "$(list_row tool pip)"
  [ "$status" -eq 0 ]
  local plain; plain="$(strip_ansi <<<"$output")"
  [[ "$plain" != *"will be skipped:"* ]]
  [[ "$plain" == *"2 tools will install:"* ]]
}

# `already installed` is decided before the dependency gate (ADR-0005): a Step
# with nothing left to do is not skipped for want of a prerequisite it will
# never use. The panel asks in the same order, or it would promise a skip
# against a Tool the run reports `already installed`.
@test "a decline does not strand a dependent that is already installed" {
  local sh; sh="$(probe_forced pip=false eza=false jupyter=true)"; SETUP_SH="$sh"
  printf 'jupyter\n' >"$TUI_STATE/checked"
  "$sh" __tui_toggle "$(list_row tool pip)"
  [ "$(tui_state declined)" = "pip" ]
  run "$sh" __tui_preview "$(list_row tool pip)"
  [ "$status" -eq 0 ]
  [[ "$(strip_ansi <<<"$output")" != *"will be skipped:"* ]]
}

@test "declining a prerequisite changes no other row's check" {
  local sh; sh="$(probe_forced node=false puppeteer=false pocock-skills=false bun=false)"
  SETUP_SH="$sh"
  printf 'pocock-skills\nbun\n' >"$TUI_STATE/checked"
  local before; before="$(cat "$TUI_STATE/checked")"
  "$sh" __tui_toggle "$(list_row tool node)"
  [ "$(cat "$TUI_STATE/checked")" = "$before" ]
  [ "$(tui_state declined)" = "node" ]
  [ "$(row_check tool pocock-skills)" = "[x]" ]
  [ "$(row_check tool bun)" = "[x]" ]
}

@test "TAB on a declined prerequisite checks it back and clears the warning" {
  local sh; sh="$(probe_forced pip=false eza=false jupyter=false)"; SETUP_SH="$sh"
  printf 'jupyter\n' >"$TUI_STATE/checked"
  "$sh" __tui_toggle "$(list_row tool pip)"
  "$sh" __tui_toggle "$(list_row tool pip)"
  [ "$(row_check tool pip)" = "[x]" ]
  [ -z "$(tui_state declined)" ]
  run "$sh" __tui_preview "$(list_row tool pip)"
  [[ "$(strip_ansi <<<"$output")" != *"will be skipped:"* ]]
}

# A decline is a negative pick about a prerequisite, not a record of every
# uncheck: nothing needs `bun`, so unchecking it is just an uncheck.
@test "unchecking a Tool nothing requires is not recorded as a decline" {
  local sh; sh="$(probe_forced bun=false)"; SETUP_SH="$sh"
  printf 'bun\n' >"$TUI_STATE/checked"
  "$sh" __tui_toggle "$(list_row tool bun)"
  [ "$(row_check tool bun)" = "[ ]" ]
  [ -z "$(tui_state declined)" ]
}

# Checking a Profile is a positive pick of every Tool in it, which includes any
# the user had declined -- otherwise the row would read `[x]` over a decline
# still in force.
@test "a Profile macro clears a decline on one of its Tools" {
  local sh; sh="$(probe_forced pip=false eza=false jupyter=false uv=false ollama=false)"
  SETUP_SH="$sh"
  printf 'jupyter\n' >"$TUI_STATE/checked"
  "$sh" __tui_toggle "$(list_row tool pip)"
  [ "$(tui_state declined)" = "pip" ]
  "$sh" __tui_toggle "$(list_row profile default)"
  [ -z "$(tui_state declined)" ]
  [ "$(row_check tool pip)" = "[x]" ]
}

# The seed establishes both sets from nothing (ADR-0010), and a decline left
# over from a previous state would be a lock the next run never agreed to.
@test "seeding the defaults clears an earlier decline" {
  local sh; sh="$(probe_forced pip=false eza=false jupyter=false)"; SETUP_SH="$sh"
  printf 'jupyter\n' >"$TUI_STATE/checked"
  "$sh" __tui_toggle "$(list_row tool pip)"
  [ -n "$(tui_state declined)" ]
  "$sh" __tui_seed
  [ -z "$(tui_state declined)" ]
}

# ENTER has to carry the decline out of the picker: resolution would otherwise
# add the prerequisite straight back and install the one Tool the user said no
# to. See #24 and ADR-0015.
@test "__tui_resolve reports the declined prerequisites" {
  local sh; sh="$(probe_forced pip=false eza=false jupyter=false)"; SETUP_SH="$sh"
  printf 'jupyter\n' >"$TUI_STATE/checked"
  "$sh" __tui_toggle "$(list_row tool pip)"
  run "$sh" __tui_resolve
  [ "$status" -eq 0 ]
  [ "$(grep '^tools: ' <<<"$output")" = "tools: jupyter" ]
  [ "$(grep '^declined: ' <<<"$output")" = "declined: pip" ]
}

# --- ADR-0010: ENTER installs exactly the state set --------------------------

@test "__tui_resolve returns the checked Tools and the toggled Profiles" {
  "$SETUP_SH" __tui_toggle "$(list_row profile go)"
  "$SETUP_SH" __tui_toggle "$(list_row tool bun)"
  run "$SETUP_SH" __tui_resolve
  [ "$status" -eq 0 ]
  [ "$(grep '^profiles: ' <<<"$output")" = "profiles: go" ]
  [ "$(grep '^tools: ' <<<"$output")" = "tools: go golangci-lint air bun" ]
}

# The Profile keys are provenance for config.json and --replay. Resolution
# ignores them: the state's Tools are the answer, so an unchecked member stays
# unchecked instead of being resurrected by a re-expansion.
@test "__tui_resolve does not re-expand a Profile whose member was unchecked" {
  "$SETUP_SH" __tui_toggle "$(list_row profile go)"
  "$SETUP_SH" __tui_toggle "$(list_row tool air)"
  run "$SETUP_SH" __tui_resolve
  [ "$status" -eq 0 ]
  [ "$(grep '^profiles: ' <<<"$output")" = "profiles: go" ]
  [ "$(grep '^tools: ' <<<"$output")" = "tools: go golangci-lint" ]
}

# An empty set installs nothing. A picker where cancelling installs eleven
# packages is a bug wearing a fallback's clothes; `--yes` is the deliberate
# way to ask for the Default Toolset.
@test "__tui_resolve on an empty state resolves to no tools at all" {
  run "$SETUP_SH" __tui_resolve
  [ "$status" -eq 0 ]
  [ "$(grep '^profiles: ' <<<"$output")" = "profiles: " ]
  [ "$(grep '^tools: ' <<<"$output")" = "tools: " ]
}

@test "__tui_resolve keeps a Profile label whose Tools were all unchecked" {
  "$SETUP_SH" __tui_toggle "$(list_row profile rust)"
  "$SETUP_SH" __tui_toggle "$(list_row tool rust)"
  run "$SETUP_SH" __tui_resolve
  [ "$status" -eq 0 ]
  [ "$(grep '^profiles: ' <<<"$output")" = "profiles: rust" ]
  [ "$(grep '^tools: ' <<<"$output")" = "tools: " ]
}

# --- ADR-0010: what the decision deletes -------------------------------------
#
# The point of the decision is subtraction. These read the source because that
# is where the deletions are: a `pos(N)` that came back, or a `--multi` that
# was re-added to make fzf's marker work again, would put the whole class of
# bug back without failing any behavioural test above.

# Comments may still name what was deleted — ADR-0010 is partly a record of why
# the arithmetic was there — so these read the code with the comments stripped.
@test "no pos(N) arithmetic remains in the picker" {
  local code; code="$(grep -v '^[[:space:]]*#' "$SETUP_SH")"
  [[ "$code" != *"pos("* ]]
}

@test "the picker has no --multi and no check-everything key" {
  local code; code="$(grep -v '^[[:space:]]*#' "$SETUP_SH")"
  [[ "$code" != *"--multi"* ]]
  [[ "$code" != *"ctrl-a"* ]]
  [[ "$code" != *"toggle-all"* ]]
}

# #34: `down` in fzf's default layout moves toward row 1 and clamps there, so
# `tab:toggle+down` never advanced and on row 1 the second TAB un-checked what
# the first one checked. Removing the movement removes the bug.
@test "TAB records and reloads without moving the cursor" {
  local bind; bind="$(grep -m1 -- '--bind "tab:' "$SETUP_SH")"
  [ -n "$bind" ]
  [[ "$bind" == *"__tui_toggle"* ]]
  [[ "$bind" == *"__tui_list"* ]]
  [[ "$bind" != *"+down"* ]]
  [[ "$bind" != *"transform"* ]]
}

# A stale query filtering a list it was never typed against shows the user an
# empty tab. Every binding that reloads clears it first.
@test "every Category tab switch clears the query" {
  local b
  for b in left right click-header; do
    local bind; bind="$(grep -m1 -- "--bind \"$b:" "$SETUP_SH")"
    [ -n "$bind" ]
    [[ "$bind" == *"clear-query"* ]]
    [[ "$bind" == *"__tui_list"* ]]
  done
}

# It has produced a silent wrong install twice.
@test "the interactive path has no Default Toolset fallback" {
  ! grep -q 'using Default Toolset' "$SETUP_SH"
}
