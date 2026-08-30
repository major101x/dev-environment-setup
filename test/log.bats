#!/usr/bin/env bats
#
# The log. There is no blanket `exec > >(tee -a "$LOG_FILE") 2>&1` redirect any
# more: the run writes the log deliberately — its own narration, every
# transition, and each Install Step's output inside a section that names the
# Step (#20, ADR-0012).
#
# The Install Step assertions drive a *real* run, not `--dry-run`: a dry run
# calls no installer, so it has no output to capture, and capture is the whole
# subject here. `runnable` stands in for everything a real run would do to the
# machine — the root check, the apt base deps, every Install Step — and the
# test overrides the one Step it is about. How a Step is *run* is not patched.

load helpers

setup() { sandbox; }
teardown() { sandbox_teardown; }

# One Install Step with a body of its own, and a run that reaches it. `node` is
# forced present because `install_biome` declares it as a prerequisite, and
# `biome` absent so the Step has work to do.
stub_biome() {
  probe_forced node=true biome=false >/dev/null
  runnable >/dev/null
  override "install_biome() { $1 }"
}

# The run those stubs are for: one Tool, one Install Step, no `gh auth login`.
run_biome() { run "$(script_copy)" --search=biome --no-auth; }

# --- the run writes the log ---------------------------------------------------

@test "a run writes its narration to the log" {
  run "$SETUP_SH" --dry-run --yes --no-auth
  [ "$status" -eq 0 ]
  [ -e "$LOG_FILE" ]
  grep -qF "[INFO] Toolset:" "$LOG_FILE"
}

@test "the log carries no escape sequences" {
  run "$SETUP_SH" --dry-run --yes --no-auth
  [ "$status" -eq 0 ]
  ! grep -q $'\033' "$LOG_FILE"
}

# The one case where a plain log is not free: on a terminal the run colours what
# it prints, and inside a section the terminal's copy *is* the log's copy. A pty
# is the only way to make the run believe it has a terminal; without one there
# is no colour to leak and the assertion above passes for the wrong reason.
@test "the log is plain text even when the terminal is getting colour" {
  stub_biome 'info "installing biome";'
  script -qec "$(script_copy) --search=biome --no-auth" /dev/null >"$TEST_TMP/pty.out"
  # The pty worked — otherwise the log below is plain for want of any colour.
  grep -q $'\033' "$TEST_TMP/pty.out"
  ! grep -q $'\033' "$LOG_FILE"
  [ "$(log_step_output install_biome)" = "[INFO] installing biome" ]
}

# The redirect wrote every line twice by construction — once to the terminal,
# once to the log. Written deliberately, a line has one writer, and a second
# copy would mean two.
@test "a narration line is written to the log once" {
  run "$SETUP_SH" --dry-run --yes --no-auth
  [ "$status" -eq 0 ]
  [ "$(grep -cF "[INFO] Toolset:" "$LOG_FILE")" -eq 1 ]
}

@test "every transition reaches the log, in the order the stream saw it" {
  run "$SETUP_SH" --dry-run --all --no-auth --simulate-fail=install_biome
  [ "$status" -eq 1 ]
  [ "$(log_transitions)" = "$(transitions "$output")" ]
}

# --- an Install Step's output goes to the log ---------------------------------

@test "an install step's output is captured into a section that names it" {
  stub_biome 'echo "biome installer chatter";'
  run_biome
  [ "$status" -eq 0 ]
  [ "$(log_step_output install_biome)" = "biome installer chatter" ]
}

# A live install screen needs the terminal to itself (#22), which is the reason
# the redirect goes now rather than with the screen.
@test "an install step's output does not reach the terminal" {
  stub_biome 'echo "biome installer chatter";'
  run_biome
  [ "$status" -eq 0 ]
  [[ "$output" != *"biome installer chatter"* ]]
}

# Capture is not a failure path: a Step that worked says what it did, and the
# log keeps it.
@test "a successful step's output is preserved, not discarded" {
  stub_biome 'echo "line one"; echo "line two";'
  run_biome
  [ "$status" -eq 0 ]
  [ "$(step_states "$output" install_biome)" = "$(printf 'queued\ninstalling\ndone')" ]
  [ "$(log_step_output install_biome)" = "$(printf 'line one\nline two')" ]
}

@test "a failing step's output is captured and its section names the exit status" {
  stub_biome 'echo "what went wrong"; return 3;'
  run_biome
  [ "$status" -eq 1 ]
  [ "$(step_states "$output" install_biome)" = "$(printf 'queued\ninstalling\nfailed')" ]
  [ "$(log_step_output install_biome)" = "what went wrong" ]
  grep -qF "[STEP OUTPUT] install_biome | end | exit 3" "$LOG_FILE"
}

@test "a step's stderr is captured too" {
  stub_biome 'echo "on stderr" >&2;'
  run_biome
  [ "$status" -eq 0 ]
  [ "$(log_step_output install_biome)" = "on stderr" ]
}

# What the ticket calls the known trap, and ADR-0008 calls the silent TUI: under
# the blanket redirect a subcommand's stdout went to the log instead of back to
# the caller, which reads as an empty result and no error.
@test "a subcommand a step invokes still returns its output to the caller" {
  stub_biome 'local v; v="$(printf ok)"; echo "returned:$v";'
  run_biome
  [ "$status" -eq 0 ]
  [ "$(log_step_output install_biome)" = "returned:ok" ]
}

# --- transitions and output, side by side -------------------------------------

# A Step with a separable download reports `installing` itself, from inside the
# capture. That line is what the log has to interleave: the state the Step
# reached, in place among the output that got it there — and it still has to
# reach the stream, which the capture must not swallow.
@test "a phase a step reports lands in its section and in the stream" {
  local sh; sh="$(probe_forced go=false golangci-lint=false air=false)"
  runnable
  override 'install_go() { echo "fetching"; phase installing; echo "unpacking"; }'
  run "$sh" --profile=go --no-auth
  [ "$status" -eq 0 ]
  [ "$(step_states "$output" install_go)" = "$(printf 'queued\ndownloading\ninstalling\ndone')" ]
  [ "$(log_step_output install_go)" = "$(printf 'fetching\n[STEP] install_go | installing\nunpacking')" ]
}

# One section per Step, in run order: a log holding twenty Steps is only
# readable as twenty Steps if the delimiters say which is which.
@test "each install step gets its own section, in run order" {
  local sh; sh="$(probe_forced node=true biome=false vite=false)"
  runnable
  override 'install_biome() { echo "biome"; }'
  override 'install_vite() { echo "vite"; }'
  run "$sh" --profile=fe --no-auth
  [ "$status" -eq 0 ]
  [ "$(grep -o '^\[STEP OUTPUT\] install_\(biome\|vite\) | begin$' "$LOG_FILE")" = \
    "$(printf '[STEP OUTPUT] install_biome | begin\n[STEP OUTPUT] install_vite | begin')" ]
}

# A skipped Step is the one that never runs, so it has no output to delimit —
# an empty section would claim it produced none.
@test "a step that never runs gets no section" {
  local sh; sh="$(probe_forced node=false biome=false)"
  runnable
  run "$sh" --search=biome --no-auth
  [ "$status" -eq 0 ]
  [ "$(step_states "$output" install_biome)" = "$(printf 'queued\nskipped')" ]
  ! grep -qF "[STEP OUTPUT] install_biome" "$LOG_FILE"
}

# A log that cannot be written is a degraded run, not a dead one: the old
# redirect would have taken the whole run down with it, and a Step redirected
# into an unwritable path fails for a reason that has nothing to do with it.
@test "a run whose log cannot be written says so and installs anyway" {
  stub_biome 'echo "biome installer chatter";'
  # The directory, not the tree: everything else the run writes — its config,
  # its state — has to keep working, or the assertion is about the wrong thing.
  mkdir -p "$TEST_TMP/ro"
  chmod a-w "$TEST_TMP/ro"
  export LOG_FILE="$TEST_TMP/ro/setup.log"
  run_biome
  chmod u+w "$TEST_TMP/ro"
  [ "$status" -eq 0 ]
  [[ "$(strip_ansi <<<"$output")" == *"Cannot write $LOG_FILE"* ]]
  [ "$(step_states "$output" install_biome)" = "$(printf 'queued\ninstalling\ndone')" ]
  [[ "$output" == *"biome installer chatter"* ]]
}
