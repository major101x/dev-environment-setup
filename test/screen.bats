#!/usr/bin/env bats
#
# The live install screen (#22). On a terminal the run draws one frame per
# transition -- a reader process on the other end of the stream, painting in
# place -- and finalises before anything prints beneath it or reads stdin. Off
# a terminal the run is the plain lines it has always been.
#
# A pseudo-terminal is the only way to make the run believe stdout is one, so
# these drive `script -qec`. They are deliberately few and assert only the
# finalised state: a pty-driven test is timing-sensitive, and the frame itself
# is pinned exactly, with no timing in it, by test/render.bats.

load helpers

setup() { sandbox; }
teardown() { sandbox_teardown; }

# A run under a pty at 80x24, with the simulated installer's runtime cut short.
pty() { COLUMNS=80 LINES=24 DEV_SETUP_SIM_DELAY=0.01 run script -qec "$*" /dev/null; }

# The terminal after the last repaint: the finalised frame and whatever the run
# printed beneath it, carriage returns and escapes stripped.
after_last_repaint() {
  printf '%s' "$output" | tr -d '\r' | tr '\n' '\001' | sed -E 's/.*\x1b\[[0-9]+A//' \
    | tr '\001' '\n' | sed -E 's/\x1b\[[0-9;?]*[A-Za-z]//g'
}

# The box alone, top border to bottom border, out of a stretch of terminal.
box_of() { sed -n '/^ ╭/,/^ ╰/p'; }

# A real run that reaches one Install Step with a body of its own -- see
# test/log.bats for why `node` is forced present and `biome` absent.
biome_run() {
  probe_forced node=true biome=false >/dev/null
  runnable >/dev/null
  override "install_biome() { $1 }"
}

# --- when the screen is up -----------------------------------------------------

@test "a dry run on a terminal draws the install screen" {
  pty "$SETUP_SH" --dry-run --profile=go --no-auth
  [ "$status" -eq 0 ]
  [[ "$output" == *"╭─ Installing ·"* ]]
  [[ "$output" == *"╭─ Finished ·"* ]]
  [[ "$(after_last_repaint)" == *"go, golangci-lint, air"* ]]
}

@test "output is plain sequential lines when stdout is not a terminal" {
  run "$SETUP_SH" --dry-run --profile=go --no-auth
  [ "$status" -eq 0 ]
  [[ "$output" != *"╭"* ]]
  [[ "$output" != *$'\033'* ]]
  [ "$(step_states "$output" install_go | head -n1)" = "queued" ]
}

# Story 27 of #15: a non-interactive flag on a laptop is not a worse experience.
@test "a real run on a terminal shows the screen too" {
  biome_run 'echo "biome installer chatter";'
  pty "$(script_copy)" --search=biome --no-auth
  [ "$status" -eq 0 ]
  [[ "$output" == *"╭─ Installing ·"* ]]
  [[ "$(after_last_repaint | box_of)" == *"✔ biome"* ]]
  # What the Step said is in the log, and under its row while it ran; it is
  # not printed over the terminal, and a Step that landed keeps no tail.
  [[ "$(after_last_repaint)" != *"biome installer chatter"* ]]
  grep -qF "biome installer chatter" "$LOG_FILE"
}

@test "a dry run renders the real screen and installs nothing" {
  pty "$SETUP_SH" --dry-run --all --no-auth
  [ "$status" -eq 0 ]
  [[ "$output" == *"╭─ Finished ·"* ]]
  [ ! -e "$XDG_CONFIG_HOME/dev-setup/config.json" ]
  [ ! -e "$HOME/.nvm" ]
}

# --- the end of the run -------------------------------------------------------

@test "the screen finalises in place and the summary is printed beneath it" {
  pty "$SETUP_SH" --dry-run --all --no-auth --simulate-fail=install_docker
  [ "$status" -eq 1 ]
  local final; final="$(after_last_repaint)"
  grep -qE '^ │ [0-9]+ done · [0-9]+ already installed · [0-9]+ skipped · 1 failed +│$' <<<"$final"
  [[ "$(box_of <<<"$final")" == *"✘ docker · simulated failure"* ]]
  # Beneath, not over: the summary starts after the box's bottom border.
  local bottom summary
  bottom="$(grep -n '^ ╰' <<<"$final" | tail -n1 | cut -d: -f1)"
  summary="$(grep -n '^==> Summary' <<<"$final" | cut -d: -f1)"
  [ -n "$bottom" ] && [ -n "$summary" ] && [ "$bottom" -lt "$summary" ]
  grep -qE '^\[INFO\] 22 install steps: .* 1 failed$' <<<"$final"
}

# Story 24 of #15: what is on the terminal after the last repaint is the whole
# finalised frame, as ordinary output, so it is there to scroll back to.
@test "the finalised frame remains in scrollback" {
  pty "$SETUP_SH" --dry-run --profile=fe --no-auth
  [ "$status" -eq 0 ]
  local box; box="$(after_last_repaint | box_of)"
  [[ "$box" == "$(printf ' ╭─ Finished ·')"* ]]
  [[ "$box" == *"Done in "* ]]
  [[ "$box" == *$'\n ╰'* ]]
  # And nothing was painted over it afterwards.
  [[ "$(after_last_repaint)" != *"╭─ Installing"* ]]
}

# The one end-to-end smoke test the spec asks for: the real ANSI path, under a
# pty, ends on exactly the frame the pure renderer draws for the same snapshot.
@test "the finalised frame is the renderer's frame for the run's snapshot" {
  local sh; sh="$(probe_forced go=false golangci-lint=false air=false)"
  pty "$sh" --dry-run --profile=go --no-auth --simulate-fail=install_go
  [ "$status" -eq 1 ]
  local expected
  expected="$("$SETUP_SH" __render 80 24 <<'SNAP' | strip_ansi | box_of
final
step | go, golangci-lint, air | failed | simulated failure
SNAP
)"
  # Elapsed time is the one thing a live run cannot pin.
  [ "$(after_last_repaint | box_of | sed -E 's/[0-9]+:[0-9]{2}/T/g')" = \
    "$(sed -E 's/[0-9]+:[0-9]{2}/T/g' <<<"$expected")" ]
}

# --- what a failure shows -----------------------------------------------------

# Story 13 of #15: enough of a failed Step's output to diagnose it without
# opening the log.
@test "a failed step shows the tail of its output on screen" {
  # Three lines: the board keeps three, where the row in flight showed two.
  biome_run 'echo "first, this"; echo "what went wrong"; echo "and then this"; return 3;'
  pty "$(script_copy)" --search=biome --no-auth
  [ "$status" -eq 1 ]
  local box; box="$(after_last_repaint | box_of)"
  [[ "$box" == *"✘ biome · exit 3"* ]]
  [[ "$box" == *"    first, this"* ]]
  [[ "$box" == *"    what went wrong"* ]]
  [[ "$box" == *"    and then this"* ]]
}

# While the screen owns the terminal a narration line would tear the frame, so
# it goes to the log alone; off a terminal it is printed as before.
@test "narration during the run goes to the log, not over the screen" {
  biome_run 'return 3;'
  pty "$(script_copy)" --search=biome --no-auth
  [ "$status" -eq 1 ]
  [[ "$(strip_ansi <<<"$output")" != *"Install Step failed: install_biome"* ]]
  grep -qF "[ERROR] Install Step failed: install_biome (exit 3) - continuing" "$LOG_FILE"
  run "$(script_copy)" --search=biome --no-auth
  [ "$status" -eq 1 ]
  [[ "$output" == *"Install Step failed: install_biome"* ]]
}

# The screen is drawn from the stream, and the log still has every line of it.
@test "every transition reaches the log while the screen is up" {
  biome_run 'return 3;'
  pty "$(script_copy)" --search=biome --no-auth
  [ "$status" -eq 1 ]
  [ "$(log_transitions | grep -c '^install_biome | ')" -eq 3 ]
  [ "$(log_transitions | tail -n1)" = "install_biome | failed | exit 3" ]
}

# --- the terminal is handed back ------------------------------------------------

# Story 30 of #15: `gh auth login` prompts, and a redraw loop cannot share a
# terminal with a blocking read. The prompt is stood in for by a `read`, fed
# through the pty's stdin.
@test "the renderer stops before the GitHub authentication prompt reads stdin" {
  biome_run 'echo hi;'
  override 'github_auth() { local ans; read -r ans; echo "auth read: $ans"; }'
  run bash -c "printf 'token\n' | COLUMNS=80 LINES=24 script -qec '$(script_copy) --search=biome' /dev/null"
  [ "$status" -eq 0 ]
  local plain; plain="$(after_last_repaint)"
  [[ "$plain" == *"auth read: token"* ]]
  # The read happened beneath the finalised frame, with the cursor handed back
  # and no frame painted after it.
  local bottom prompt
  bottom="$(grep -n '^ ╰' <<<"$plain" | tail -n1 | cut -d: -f1)"
  prompt="$(grep -n 'auth read: token' <<<"$plain" | cut -d: -f1)"
  [ -n "$bottom" ] && [ "$bottom" -lt "$prompt" ]
  local after; after="${output##*auth read: token}"
  # `ESC[<n>A` and nothing else. The glob this replaces — `*$'\033['*A*` — put a
  # wildcard between the escape and the letter, so any escape followed by a
  # capital `A` anywhere later matched: the sandbox's own `mktemp` path prints
  # two lines below the prompt, and 15% of those names hold an `A`, which was
  # the whole of the flake (#48). The count is optional so that a bare `ESC[A`
  # is caught too, though `screen_paint` only ever emits one with a count.
  local cursor_up=$'\033'"\\[[0-9]*A"
  [[ ! "$after" =~ $cursor_up ]]
  [[ "$after" != *"╭"* ]]
  [[ "${output%%auth read: token*}" == *$'\033[?25h'* ]]
}

# --- when the screen cannot be up -----------------------------------------------

# A screen bug is not a run bug. A reader that dies leaves a pipe nobody reads,
# and a write to that is SIGPIPE -- which would end the run past a failed Step
# and before the summary, with no exit status to read (ADR-0006). The run keeps
# a read end open and steps down to plain lines instead.
@test "a reader that dies under the run does not take the run with it" {
  biome_run 'return 3;'
  override 'screen_reader() { local line; read -r line; exit 1; }'
  pty "$(script_copy)" --search=biome --no-auth
  [ "$status" -eq 1 ]
  local plain; plain="$(strip_ansi <<<"$output" | tr -d '\r')"
  [[ "$plain" == *"[STEP] install_biome | failed | exit 3"* ]]
  [[ "$plain" == *"==> Summary"* ]]
  [[ "$plain" == *"Failed: install_biome (biome) - exit 3"* ]]
}

# A screen needs the log: it owns the terminal, so an Install Step's output has
# to have somewhere else to go. Without one the run is the plain lines, still.
@test "a run whose log cannot be written stays plain even on a terminal" {
  biome_run 'echo "biome installer chatter";'
  mkdir -p "$TEST_TMP/ro"
  chmod a-w "$TEST_TMP/ro"
  LOG_FILE="$TEST_TMP/ro/setup.log" pty "$(script_copy)" --search=biome --no-auth
  chmod u+w "$TEST_TMP/ro"
  [ "$status" -eq 0 ]
  [[ "$output" != *"╭"* ]]
  [[ "$(strip_ansi <<<"$output")" == *"Cannot write $TEST_TMP/ro/setup.log"* ]]
  [[ "$output" == *"biome installer chatter"* ]]
}
