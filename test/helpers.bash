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
  mkdir -p "$HOME"
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
