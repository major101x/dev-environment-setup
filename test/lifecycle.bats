#!/usr/bin/env bats
#
# The Install Step lifecycle: the transition stream every Install Step emits as
# it moves through the seven states of ADR-0005. `--dry-run` drives the same
# state machine against simulated Install Steps, so the whole lifecycle is
# exercised through the process boundary with no installs and no network.

load helpers

setup() { sandbox; }
teardown() { sandbox_teardown; }

# --- base dependencies, the Step that delivers no Tool -------------------------
#
# #68. `install_base_deps` used to run before `screen_start`, on the terminal,
# scrolling apt's account of 28 sources past a person who had just pressed ENTER
# on a picker. ADR-0012 said it would join the log sections "when the screen
# could show a failure itself" and ADR-0013 deferred it; this is that work.
#
# It is an Install Step that delivers no Tool -- the first of its kind, and the
# reason the glossary now says "zero or more". It is not a Tool: a Tool is what
# appears in the picker, and base dependencies is not something a person can
# decline. See ADR-0018.

@test "base dependencies is the first Install Step in the plan" {
  run "$SETUP_SH" --dry-run --profile=go --no-auth
  [ "$status" -eq 0 ]
  [ "$(planned_steps "$output" | head -n1)" = "install_base_deps" ]
}

# Labelled, not blank. Every other row's label is the Tools it delivers, joined
# with commas; this one delivers none, so it carries a label of its own -- the
# first label in the system not derived from Tools.
@test "base dependencies is labelled rather than left blank" {
  run "$SETUP_SH" --dry-run --profile=go --no-auth
  [ "$status" -eq 0 ]
  [ "$(step_label "$output" install_base_deps)" = "base dependencies" ]
}

# `apt-get update` fetches from every source on the machine and `apt-get install`
# unpacks: two operations, and the lifecycle already has a state for each. Being
# told which of the two is running is the whole point of putting it on the
# screen, so the split is asserted rather than left to the installer.
@test "base dependencies downloads and then installs" {
  run "$SETUP_SH" --dry-run --profile=go --no-auth
  [ "$status" -eq 0 ]
  [ "$(step_states "$output" install_base_deps)" = "$(printf 'queued\ndownloading\ninstalling\ndone')" ]
}

# The trap this walked into: `step_already_installed` loops over the Tools a Step
# delivers and returns 0 when it finds none missing -- which, over no Tools at
# all, is vacuously true. Base dependencies would have reported `already
# installed` on every run and never called apt once. A Step that delivers
# nothing has no presence probe to answer it, so it cannot be already installed.
@test "a step that delivers no tool is never already installed" {
  # `install_go` delivers three Tools and needs all three present to report
  # `already installed`; base dependencies delivers none, which is the case the
  # gate used to answer vacuously.
  local sh; sh="$(probe_forced go=true golangci-lint=true air=true)"
  run "$sh" --dry-run --profile=go --no-auth
  [ "$status" -eq 0 ]
  [ "$(step_states "$output" install_go | tail -n1)" = "already installed" ]
  [ "$(step_states "$output" install_base_deps | tail -n1)" = "done" ]
}

# --- the queue -----------------------------------------------------------------

# Story 6 of #15: a person watching wants to know how much work is left, which
# only reads if every Step announces itself before the first one runs.
@test "every planned install step is queued before any of them runs" {
  run "$SETUP_SH" --dry-run --yes --no-auth
  [ "$status" -eq 0 ]
  local planned; planned="$(planned_steps "$output")"
  # The Default Toolset's nine, and base dependencies ahead of them (#68).
  local n; n="$(grep -c . <<<"$planned")"
  [ "$n" -eq 10 ]
  # The first n transitions are exactly those steps, queued, in plan order.
  [ "$(transitions "$output" | head -n "$n")" = "$(sed 's/$/ | queued/' <<<"$planned")" ]
}

@test "the transition stream names only steps that are in the plan" {
  run "$SETUP_SH" --dry-run --all --no-auth
  [ "$status" -eq 0 ]
  local planned; planned="$(planned_steps "$output")"
  local s
  for s in $(transitions "$output" | awk -F' \\| ' '{ print $1 }' | sort -u); do
    grep -qx "$s" <<<"$planned"
  done
}

@test "every planned install step reaches exactly one terminal state" {
  run "$SETUP_SH" --dry-run --all --no-auth
  [ "$status" -eq 0 ]
  every_step_settled "$output"
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
# second run against a provisioned machine legitimately puts every Tool's row
# here. Every Tool's, and not every row: base dependencies delivers no Tool, so
# nothing can probe it as present and it refreshes the apt cache on every run
# (#68). Asserted over the Steps that deliver Tools rather than over the whole
# stream, which is the honest shape of the claim.
@test "a second run against an already provisioned machine reports already installed" {
  local sh; sh="$(probe_forced gh=true fastfetch=true opencode=true node=true \
    puppeteer=true chrome=true docker=true pip=true eza=true exa-mcp=true pocock-skills=true)"
  run "$sh" --dry-run --yes --no-auth
  [ "$status" -eq 0 ]
  # The whole stream, not each Step's last line: the claim is that nothing else
  # happens on a provisioned machine, and a Step that walked
  # `queued -> installing -> already installed` would satisfy a per-Step check
  # while breaking it. The five are base dependencies' four plus the state every
  # other Step lands in.
  [ "$(states_seen "$output")" = "$(printf 'already installed\ndone\ndownloading\ninstalling\nqueued')" ]
  local fn
  for fn in $(planned_steps "$output" | grep -vx install_base_deps); do
    [ "$(step_states "$output" "$fn" | tail -n1)" = "already installed" ]
  done
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
  # Non-zero: a run holding a failed Step cannot report success, dry or not.
  # The exit status and the summary are test/failure.bats' subject; here it is
  # only asserted so the stream and the status cannot drift apart.
  run "$sh" --dry-run --profile=go --simulate-fail=install_go --no-auth
  [ "$status" -eq 1 ]
  [ "$(step_states "$output" install_go | tail -n1)" = "failed" ]
  [ "$(step_detail "$output" install_go)" = "simulated failure" ]
}

# A prerequisite that is missing is no longer a skip: resolution adds it, and
# the Step that needed it runs behind the Step that delivers it (ADR-0014).
# `skipped` is what is left when that cannot work -- the cascade below.
@test "a step whose prerequisite is missing gets it added rather than skipped" {
  local sh; sh="$(probe_forced node=false puppeteer=false pocock-skills=false)"
  run "$sh" --dry-run --search=pocock --no-auth
  [ "$status" -eq 0 ]
  [ "$(planned_steps "$output")" = \
    "$(printf 'install_base_deps\ninstall_node_and_puppeteer\ninstall_pocock_skills')" ]
  [ "$(step_states "$output" install_pocock_skills)" = "$(printf 'queued\ninstalling\ndone')" ]
}

# The cascade ADR-0005 exists to make readable: one failure, then its dependents
# reading as one cause rather than several mysteries.
@test "a failed step cascades into its dependents as unmet dependency" {
  local sh; sh="$(probe_forced node=false puppeteer=false pocock-skills=false)"
  run "$sh" --dry-run --profile=default --simulate-fail=install_node_and_puppeteer --no-auth
  [ "$status" -eq 1 ]
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
  [ "$status" -eq 1 ]
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

# #10's contract, stated rather than assumed. The trailing Verification block
# was the run's second pass over the real Tools; its call site had been guarded
# under `--dry-run` by the time #25 deleted it, so this is not the repair of a
# live leak but the assertion that nothing re-grows in its place.
#
# The Tools are witnessed *and* forced absent: the dry run plans to install each
# one and must still never execute it. What a dry run may run is the declared
# presence probes, which ADR-0011 has it share with a real run so the preview
# answers `already installed` truthfully -- and they are read-only. Almost all
# ask the shell or the filesystem and never run the binary; qdrant's is the one
# that has to ask a daemon, and asking it to list container names is the whole
# of what a dry run does to the machine. #52 kept it and ADR-0011 records the
# bound it sits inside, so this argv is the line itself: spelled out argument
# for argument rather than left as a hole in the assertion.
@test "a dry run runs no tool, and asks docker only what qdrant's probe asks" {
  local sh t
  sh="$(probe_forced gh=false fastfetch=false eza=false opencode=false)"
  for t in gh fastfetch eza opencode; do witness_tool "$t"; done
  fake_tool docker "echo \"\$*\" >>'$TEST_TMP/docker-argv'"
  run "$sh" --dry-run --all --no-auth
  [ "$status" -eq 0 ]
  for t in gh fastfetch eza opencode; do [ ! -e "$TEST_TMP/ran-$t" ]; done
  # The file existing is half the assertion: the probe ran, and ran nothing else.
  [ "$(sort -u "$TEST_TMP/docker-argv")" = 'ps -a --format {{.Names}}' ]
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
