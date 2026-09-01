#!/usr/bin/env bats
#
# The install screen's renderer: `setup.sh __render WIDTH HEIGHT < snapshot`
# writes exactly one frame and does nothing else (#21). It is a pure function
# of the snapshot and the size, which is what lets these tests assert an
# exact frame: no install, no timing, no terminal. The layout is ADR-0007's
# bordered grid of every Install Step.

load helpers

setup() { sandbox; }
teardown() { sandbox_teardown; }

FIXTURES="$SETUP_ROOT/test/fixtures/render"

# One frame off a fixture snapshot: `render midrun 80 24`.
render() { run "$SETUP_SH" __render "$2" "$3" <"$FIXTURES/$1.snap"; }

# The frame with its colour stripped, which is how a person reads it.
plain() { strip_ansi <<<"$output"; }

# The lines of a frame, counted through a pipe: `$output` and `lines` both lose
# the blank line a frame ends on.
frame_lines() { "$SETUP_SH" __render "$2" "$3" <"$FIXTURES/$1.snap" | wc -l; }

# The longest line on stdin, in characters -- not bytes, since the box and
# every glyph in it are several, and not awk's `length`, which counts bytes.
widest() {
  local LC_ALL=C.UTF-8 l w=0
  while IFS= read -r l; do if (( ${#l} > w )); then w=${#l}; fi; done
  echo "$w"
}

# Every line on stdin is exactly `$1` characters.
each_exactly() {
  local LC_ALL=C.UTF-8 l
  while IFS= read -r l; do [ "${#l}" -eq "$1" ] || return 1; done
}

# --- one frame, and nothing else ----------------------------------------------

@test "a snapshot and a size produce one frame" {
  render midrun 80 24
  [ "$status" -eq 0 ]
  [ "$(frame_lines midrun 80 24)" -eq 24 ]
}

# Purity, asserted the only way it can be from outside: nothing in the
# environment reaches the frame.
@test "identical input produces identical output" {
  local a b
  a="$("$SETUP_SH" __render 80 24 <"$FIXTURES/midrun.snap")"
  b="$(TERM=dumb COLUMNS=200 LINES=5 LOG_FILE=/nonexistent/log HOME=/nonexistent \
    "$SETUP_SH" __render 80 24 <"$FIXTURES/midrun.snap")"
  [ -n "$a" ]
  [ "$a" = "$b" ]
}

# Dispatched before `main`, like every other subcommand: the log belongs to a
# run, and rendering a frame is not one (ADR-0012).
@test "the subcommand writes nothing to the log" {
  render midrun 80 24
  [ "$status" -eq 0 ]
  [ ! -e "$LOG_FILE" ]
}

@test "a line that is not a snapshot line is refused" {
  run "$SETUP_SH" __render 80 24 <<<"garbage"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a snapshot line"* ]]
}

@test "a state outside the lifecycle is refused" {
  run "$SETUP_SH" __render 80 24 <<<"step | gh | exploded"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a lifecycle state"* ]]
}

@test "a size that is not a size is refused" {
  run "$SETUP_SH" __render wide tall <"$FIXTURES/midrun.snap"
  [ "$status" -eq 1 ]
}

# --- every state looks like itself --------------------------------------------

# ADR-0005's seven, each with a glyph and a colour of its own. `already
# installed` is not a dimmer `done`: a re-run must read as "nothing to do".
@test "every lifecycle state has a distinct appearance" {
  render legend 80 24
  [ "$status" -eq 0 ]
  local frame; frame="$(plain)"
  [[ "$frame" == *"· redis-tools"* ]]
  [[ "$frame" == *"⢿ go, golangci-lint, air"* ]]
  [[ "$frame" == *"⢿ pocock-skills"* ]]
  [[ "$frame" == *"✔ gh"* ]]
  [[ "$frame" == *"= bun"* ]]
  [[ "$frame" == *"⊘ qdrant"* ]]
  [[ "$frame" == *"✘ docker"* ]]
  # The colour goes with the glyph, and no two states share one.
  [[ "$output" == *$'\033[90m·'* ]]
  [[ "$output" == *$'\033[36m⢿'* ]]
  [[ "$output" == *$'\033[32m✔'* ]]
  [[ "$output" == *$'\033[34m='* ]]
  [[ "$output" == *$'\033[33m⊘'* ]]
  [[ "$output" == *$'\033[31m✘'* ]]
}

# Story 5 of #15: a spinner and elapsed time tell a slow Step from a hung one.
@test "the active row shows a spinner and elapsed time" {
  render midrun 80 24
  [ "$status" -eq 0 ]
  plain | grep -qE '^ │ ⣻  pocock-skills +installing · 0:12 +│$'
}

@test "the spinner turns with the tick" {
  local a b
  a="$("$SETUP_SH" __render 80 24 <<<$'tick | 0\nstep | gh | installing')"
  b="$("$SETUP_SH" __render 80 24 <<<$'tick | 1\nstep | gh | installing')"
  [[ "$(strip_ansi <<<"$a")" == *"⣾ gh"* ]]
  [[ "$(strip_ansi <<<"$b")" == *"⣽ gh"* ]]
}

# --- the frame fits the terminal ----------------------------------------------

@test "rows are truncated, never wrapped, on a narrow terminal" {
  run "$SETUP_SH" __render 40 24 <<'SNAP'
elapsed | 1:47
step | a-label-far-too-long-for-a-narrow-terminal | done
step | gh | installing
SNAP
  [ "$status" -eq 0 ]
  [ "$(plain | widest)" -le 39 ]
  [[ "$(plain)" == *"✔ a-label-far-too-long-for-a-narr…"* ]]
}

# Every box line is exactly the width the caller asked for, less one column so
# the last cell never triggers a wrap.
@test "the box is one column narrower than the terminal" {
  local w
  for w in 40 52 80 120; do
    render midrun "$w" 24
    [ "$status" -eq 0 ]
    [ "$(plain | grep -c '^ [╭│╰]')" -eq 22 ]
    plain | grep '^ [╭│╰]' | each_exactly $(( w - 1 ))
  done
}

# ADR-0007: a live frame is padded to the terminal so its bottom edge does not
# jump as Steps complete.
@test "a live frame fills the terminal" {
  render midrun 120 40
  [ "$status" -eq 0 ]
  [ "$(frame_lines midrun 120 40)" -eq 40 ]
}

# The pressure case ADR-0007 was decided on: `--all` is 22 Install Steps, and
# 80x24 must show every one of them at once.
@test "a toolset with more install steps than fit on screen renders coherently" {
  render midrun 80 24
  [ "$status" -eq 0 ]
  [ "$(frame_lines midrun 80 24)" -eq 24 ]
  local label
  while IFS= read -r label; do
    [[ "$(plain)" == *" $label"* ]] || { echo "label missing: $label" >&2; return 1; }
  done < <(sed -n 's/^step | \([^|]*\) | .*/\1/p' "$FIXTURES/midrun.snap" | sed 's/ *$//')
}

@test "the column count falls as the terminal narrows" {
  render midrun 80 24
  plain | grep -qE '^ │ ✔ exa-mcp +· uv +│$'
  render midrun 40 24
  plain | grep -qE '^ │ ✔ exa-mcp +│$'
}

# --- what a failure shows -----------------------------------------------------

# Story 13 of #15: enough of a failed Step's output to diagnose it without
# opening the log.
@test "a failed step shows the tail of its output on the failure board" {
  render midrun 80 24
  [ "$status" -eq 0 ]
  plain | grep -qE '^ │ ✘ docker · exit 100 +│$'
  plain | grep -qF '     E: Sub-process /usr/bin/dpkg returned an error code (100)'
}

@test "a skipped step's board line names what it needed" {
  render midrun 80 24
  [ "$status" -eq 0 ]
  plain | grep -qE '^ │ ⊘ qdrant · unmet dependency: docker +│$'
}

# A board that quietly stops reads as "that is all of them", which is the one
# thing a cascade frame must not say (ADR-0007).
@test "a failure board that runs out of room counts what it dropped" {
  render cascade 80 24
  [ "$status" -eq 0 ]
  plain | grep -qF '✘ node, puppeteer · exit 1'
  plain | grep -qF '… and 4 more failed or skipped'
}

# --- the finalised frame ------------------------------------------------------

# Printed once and never repainted, so it is neither padded nor capped: that is
# what buys a version on every cell and keeps the whole failure board (ADR-0007).
@test "the finalised frame runs to its natural length" {
  render final 80 24
  [ "$status" -eq 0 ]
  [ "$(frame_lines final 80 24)" -gt 24 ]
  [[ "$(plain)" == *"✔ gh · 2.63.2"* ]]
  [[ "$(plain)" == *"= fastfetch · 2.30.1"* ]]
  [[ "$(plain)" == *"✘ docker · exit 100"* ]]
  [[ "$(plain)" == *"⊘ qdrant · unmet dependency: docker"* ]]
  [[ "$(plain)" == *"✘ ollama · exit 1"* ]]
  [[ "$(plain)" == *"N: See apt-secure(8) for repository creation"* ]]
  [[ "$(plain)" == *"curl: (28) Operation timed out after 30001 milliseconds"* ]]
}

@test "the finalised frame carries the summary counts" {
  render final 80 24
  [ "$status" -eq 0 ]
  plain | grep -qE '^ │ Done in 6:12\. +│$'
  plain | grep -qE '^ │ 16 done · 3 already installed · 1 skipped · 2 failed +│$'
  plain | grep -qE '^ │ exit status 1 - re-run to retry the failures +│$'
}

@test "a finalised frame with no failures does not mention an exit status" {
  render rerun-final 80 24
  [ "$status" -eq 0 ]
  [[ "$(plain)" != *"exit status"* ]]
  plain | grep -qE '^ │ 2 done · 20 already installed · 0 skipped · 0 failed +│$'
}

# --- exact frames -------------------------------------------------------------

# The fixtures are the frames as reviewed, colour stripped, one per snapshot
# and size. A layout change is a fixture change, made on purpose.
@test "every fixture frame is reproduced exactly" {
  local f name size
  for f in "$FIXTURES"/*.txt; do
    name="$(basename "$f" .txt)"
    size="${name##*.}"; name="${name%.*}"
    render "$name" "${size%x*}" "${size#*x}"
    [ "$status" -eq 0 ] || { echo "render failed: $f" >&2; return 1; }
    if [ "$(plain)" != "$(cat "$f")" ]; then
      echo "frame differs from $f:" >&2
      diff <(plain) "$f" >&2 || true
      return 1
    fi
  done
}
