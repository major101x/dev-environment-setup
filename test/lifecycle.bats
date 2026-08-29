#!/usr/bin/env bats
#
# The Install Step lifecycle: the transition stream every Install Step emits as
# it moves through the seven states of ADR-0005. `--dry-run` drives the same
# state machine against simulated Install Steps, so the whole lifecycle is
# exercised through the process boundary with no installs and no network.

load helpers

setup() { sandbox; mkdir -p "$TEST_TMP/bin"; }
teardown() { sandbox_teardown; }

# The transition stream, one `<step> | <state>[ | <detail>]` per line, in the
# order the run emitted it.
transitions() { strip_ansi <<<"$1" | sed -n 's/^\[STEP\] //p'; }

# The states one Install Step passed through, in order.
step_states() { transitions "$1" | awk -F' \\| ' -v s="$2" '$1 == s { print $2 }'; }

# The detail a state carried, if any.
step_detail() { transitions "$1" | awk -F' \\| ' -v s="$2" '$1 == s && NF > 2 { print $3 }'; }

# Every state named anywhere in the stream, deduplicated.
states_seen() { transitions "$1" | awk -F' \\| ' '{ print $2 }' | sort -u; }

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

# --- the queue -----------------------------------------------------------------

# Story 6 of #15: a person watching wants to know how much work is left, which
# only reads if every Step announces itself before the first one runs.
@test "every planned install step is queued before any of them runs" {
  run "$SETUP_SH" --dry-run --yes --no-auth
  [ "$status" -eq 0 ]
  local planned; planned="$(strip_ansi <<<"$output" | sed -n 's/.*\[DRY RUN\] Install Step: \([a-z_]*\) ->.*/\1/p')"
  local n; n="$(grep -c . <<<"$planned")"
  [ "$n" -eq 9 ]
  # The first n transitions are exactly those steps, queued, in plan order.
  [ "$(transitions "$output" | head -n "$n")" = "$(sed 's/$/ | queued/' <<<"$planned")" ]
}

@test "the transition stream names only steps that are in the plan" {
  run "$SETUP_SH" --dry-run --all --no-auth
  [ "$status" -eq 0 ]
  local planned; planned="$(strip_ansi <<<"$output" | sed -n 's/.*\[DRY RUN\] Install Step: \([a-z_]*\) ->.*/\1/p')"
  local s
  for s in $(transitions "$output" | awk -F' \\| ' '{ print $1 }' | sort -u); do
    grep -qx "$s" <<<"$planned"
  done
}

@test "every planned install step reaches exactly one terminal state" {
  run "$SETUP_SH" --dry-run --all --no-auth
  [ "$status" -eq 0 ]
  local planned; planned="$(strip_ansi <<<"$output" | sed -n 's/.*\[DRY RUN\] Install Step: \([a-z_]*\) ->.*/\1/p')"
  local s
  while read -r s; do
    [ "$(step_states "$output" "$s" | grep -cE '^(done|already installed|skipped|failed)$')" -eq 1 ]
  done <<<"$planned"
}

# --- the happy path ------------------------------------------------------------

@test "a step that installs walks queued, installing, done" {
  local sh; sh="$(probe_forced biome=false)"
  run "$sh" --dry-run --search=biome --no-auth
  [ "$status" -eq 0 ]
  [ "$(step_states "$output" install_biome)" = "$(printf 'queued\ninstalling\ndone')" ]
}

# ADR-0005 counts the Install Steps with a separable download: Go's tarball,
# Qdrant's image pull, Puppeteer's browser fetch. Those open in `downloading`;
# an apt-fused or `curl | bash` step has no download to report and does not.
@test "a step with a discrete download reports downloading before installing" {
  local sh; sh="$(probe_forced go=false golangci-lint=false air=false)"
  run "$sh" --dry-run --profile=go --no-auth
  [ "$status" -eq 0 ]
  [ "$(step_states "$output" install_go)" = "$(printf 'queued\ndownloading\ninstalling\ndone')" ]
}

@test "a step with no discrete download never reports downloading" {
  local sh; sh="$(probe_forced biome=false)"
  run "$sh" --dry-run --search=biome --no-auth
  [ "$status" -eq 0 ]
  [[ "$(step_states "$output" install_biome)" != *downloading* ]]
}

# No Step arrives at `done` out of nowhere: whatever an installer reports about
# itself, a Step that did work passed through `installing`.
@test "no step reaches done without passing through installing" {
  run "$SETUP_SH" --dry-run --all --no-auth
  [ "$status" -eq 0 ]
  local s
  for s in $(transitions "$output" | awk -F' \\| ' '$2 == "done" { print $1 }'); do
    [ "$(step_states "$output" "$s" | grep -c '^installing$')" -eq 1 ]
  done
}

# --- already installed ---------------------------------------------------------

@test "a tool already on the machine reports already installed" {
  fake_tool gh
  run "$SETUP_SH" --dry-run --yes --no-auth
  [ "$status" -eq 0 ]
  [ "$(step_states "$output" install_gh)" = "$(printf 'queued\nalready installed')" ]
}

# The re-run case ADR-0005 calls first-class: the script is idempotent, so a
# second run against a provisioned machine legitimately puts every row here.
@test "a second run against an already provisioned machine reports already installed" {
  local sh; sh="$(probe_forced gh=true fastfetch=true opencode=true node=true \
    puppeteer=true chrome=true docker=true pip=true eza=true exa-mcp=true pocock-skills=true)"
  run "$sh" --dry-run --yes --no-auth
  [ "$status" -eq 0 ]
  [ "$(states_seen "$output")" = "$(printf 'already installed\nqueued')" ]
}

# A step delivers more than one Tool, so one of them still missing is work.
@test "a step whose second tool is missing is not already installed" {
  local sh; sh="$(probe_forced pip=true eza=false)"
  run "$sh" --dry-run --search=eza --no-auth
  [ "$status" -eq 0 ]
  [ "$(step_states "$output" install_pip_eza)" = "$(printf 'queued\ninstalling\ndone')" ]
}

# --- failure and cascade -------------------------------------------------------

@test "an injected failure reports failed" {
  local sh; sh="$(probe_forced go=false golangci-lint=false air=false)"
  run "$sh" --dry-run --profile=go --simulate-fail=install_go --no-auth
  [ "$status" -eq 0 ]
  [ "$(step_states "$output" install_go | tail -n1)" = "failed" ]
  [ "$(step_detail "$output" install_go)" = "simulated failure" ]
}

# A prerequisite that is neither on the machine nor delivered by the plan.
@test "a step with an unmet prerequisite is skipped with the reason" {
  local sh; sh="$(probe_forced node=false pocock-skills=false)"
  run "$sh" --dry-run --search=pocock --no-auth
  [ "$status" -eq 0 ]
  [ "$(step_states "$output" install_pocock_skills)" = "$(printf 'queued\nskipped')" ]
  [ "$(step_detail "$output" install_pocock_skills)" = "unmet dependency: node" ]
}

# The cascade ADR-0005 exists to make readable: one failure, then its dependents
# reading as one cause rather than several mysteries.
@test "a failed step cascades into its dependents as unmet dependency" {
  local sh; sh="$(probe_forced node=false puppeteer=false pocock-skills=false)"
  run "$sh" --dry-run --profile=default --simulate-fail=install_node_and_puppeteer --no-auth
  [ "$status" -eq 0 ]
  [ "$(step_states "$output" install_node_and_puppeteer | tail -n1)" = "failed" ]
  [ "$(step_states "$output" install_pocock_skills | tail -n1)" = "skipped" ]
  [ "$(step_detail "$output" install_pocock_skills)" = "unmet dependency: node" ]
}

# A prerequisite the plan itself delivers is met, so nothing is skipped for it.
@test "a prerequisite delivered earlier in the plan is met" {
  local sh; sh="$(probe_forced node=false puppeteer=false pocock-skills=false)"
  run "$sh" --dry-run --profile=default --no-auth
  [ "$status" -eq 0 ]
  [ "$(step_states "$output" install_pocock_skills | tail -n1)" = "done" ]
}

# --- all seven states ----------------------------------------------------------

@test "all seven states are reachable in one dry run" {
  fake_tool gh
  local sh; sh="$(probe_forced node=false puppeteer=false pocock-skills=false go=false)"
  run "$sh" --dry-run --all --simulate-fail=install_node_and_puppeteer --no-auth
  [ "$status" -eq 0 ]
  local seen; seen="$(states_seen "$output")"
  local s
  for s in queued downloading installing done "already installed" skipped failed; do
    grep -qx "$s" <<<"$seen" || { echo "state never reached: $s" >&2; return 1; }
  done
}

# --- the flag ------------------------------------------------------------------

@test "--simulate-fail outside a dry run exits 1" {
  run "$SETUP_SH" --simulate-fail=install_go --profile=go --no-auth
  [ "$status" -eq 1 ]
  [[ "$(strip_ansi <<<"$output")" == *"--simulate-fail needs --dry-run"* ]]
}

@test "--simulate-fail with an unknown step exits 1" {
  run "$SETUP_SH" --dry-run --simulate-fail=install_nope --profile=go --no-auth
  [ "$status" -eq 1 ]
  [[ "$(strip_ansi <<<"$output")" == *"Unknown install step: install_nope"* ]]
}

# --- the dry run stays inert ---------------------------------------------------

# Criterion of #17 and the reason the stream is parseable at all: a consumer
# reading it off a pipe must not have to strip escapes first.
@test "a dry run emits no ANSI escape sequences" {
  run "$SETUP_SH" --dry-run --all --no-auth
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\033'* ]]
}

@test "a dry run runs no verification commands" {
  run "$SETUP_SH" --dry-run --all --no-auth
  [ "$status" -eq 0 ]
  [[ "$output" != *"--- Versions ---"* ]]
}

# The simulation stands in for the installer's runtime: no installer command
# runs, and the time a phase would take is slept instead.
@test "the dry run simulates timing instead of running installers" {
  local sh; sh="$(probe_forced go=false golangci-lint=false air=false)"
  local before after
  before=$(date +%s%N)
  DEV_SETUP_SIM_DELAY=0.4 run "$sh" --dry-run --profile=go --no-auth
  after=$(date +%s%N)
  [ "$status" -eq 0 ]
  # One Step, two working phases: downloading and installing.
  [ $(( (after - before) / 1000000 )) -ge 700 ]
}
