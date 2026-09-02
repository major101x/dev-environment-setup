#!/usr/bin/env bats
#
# What a failure costs a run. ADR-0006: a failed Install Step is marked failed
# and the run carries on, because the Steps are independent and one broken apt
# repository should not cost the other nineteen Tools. That is only safe if the
# failures are unmissable afterwards, so this suite is really about the two
# things that make it safe -- the end-of-run summary, and an exit status CI can
# read.
#
# `--dry-run --simulate-fail=<step>` is the seam: the same state machine, the
# same summary, the same exit status, with no installs and no network.

load helpers

setup() { sandbox; }
teardown() { sandbox_teardown; }

# The summary's counts line, as printed. `steps\?` because a plan of one Step
# says `1 install step`.
summary_counts() {
  strip_ansi <<<"$1" | sed -n 's/^\[INFO\] \([0-9]* install steps\?:.*\)$/\1/p'
}

# One count out of that line: `summary_count "$output" failed`.
summary_count() {
  summary_counts "$1" | tr ',' '\n' | sed -n "s/.*[^0-9]\([0-9]*\) $2\$/\1/p"
}

# Every Install Step the summary named as failed, one per line.
summary_failures() {
  strip_ansi <<<"$1" | sed -n 's/^\[ERROR\] Failed: \([a-z_]*\) .*/\1/p'
}

# --- the run continues ---------------------------------------------------------

# The whole of ADR-0006 in one assertion: the first Step fails, and the plan
# still finishes.
@test "a failing install step does not stop the ones after it" {
  local sh; sh="$(probe_forced gh=false)"
  run "$sh" --dry-run --profile=default --simulate-fail=install_gh --no-auth
  [ "$status" -eq 1 ]
  [ "$(step_states "$output" install_gh | tail -n1)" = "failed" ]
  # Not just "something ran after it": every planned Step reached a terminal
  # state, which is what "the run continues" has to mean.
  every_step_settled "$output"
}

# Several failures in one run, none of them stopping it -- including the last
# Step in the plan, which is where an off-by-one in the loop would hide.
@test "several failing install steps all run and all report" {
  local sh; sh="$(probe_forced gh=false fastfetch=false node=false puppeteer=false \
    pocock-skills=false docker=false)"
  run "$sh" --dry-run --profile=default \
    --simulate-fail=install_gh,install_fastfetch,install_pocock_skills --no-auth
  [ "$status" -eq 1 ]
  [ "$(step_states "$output" install_gh | tail -n1)" = "failed" ]
  [ "$(step_states "$output" install_fastfetch | tail -n1)" = "failed" ]
  [ "$(step_states "$output" install_pocock_skills | tail -n1)" = "failed" ]
  [ "$(step_states "$output" install_docker | tail -n1)" = "done" ]
}

# --- the summary ---------------------------------------------------------------

@test "every failed install step is named in the end-of-run summary" {
  local sh; sh="$(probe_forced gh=false fastfetch=false)"
  run "$sh" --dry-run --profile=default \
    --simulate-fail=install_gh,install_fastfetch --no-auth
  [ "$status" -eq 1 ]
  [ "$(summary_failures "$output")" = "$(printf 'install_gh\ninstall_fastfetch')" ]
}

# A Step is labelled by what it delivers (ADR-0004), and the summary is where a
# person looks first, so the failure line names the Tools they lost and why.
@test "a summary failure line names the tools and the reason" {
  local sh; sh="$(probe_forced node=false puppeteer=false)"
  run "$sh" --dry-run --profile=default --simulate-fail=install_node_and_puppeteer --no-auth
  [ "$status" -eq 1 ]
  local line; line="$(strip_ansi <<<"$output" | sed -n 's/^\[ERROR\] Failed: //p')"
  [ "$line" = "install_node_and_puppeteer (node, puppeteer) - simulated failure" ]
}

# Story 23 of #15: how many succeeded, failed and were skipped, at a glance.
@test "the summary counts every terminal state" {
  # Every probe pinned: the counts are the assertion, so what happens to be on
  # the machine running the test must not reach them.
  local sh; sh="$(probe_forced gh=true fastfetch=false opencode=false node=false \
    puppeteer=false chrome=false docker=false pip=false eza=false exa-mcp=false \
    pocock-skills=false)"
  run "$sh" --dry-run --profile=default --simulate-fail=install_node_and_puppeteer --no-auth
  [ "$status" -eq 1 ]
  # 9 steps: gh already installed, node+puppeteer failed, pocock-skills skipped
  # in its wake, the other six done.
  [ "$(summary_counts "$output")" = "9 install steps: 6 done, 1 already installed, 1 skipped, 1 failed" ]
}

@test "a run with no failures summarises none" {
  run "$SETUP_SH" --dry-run --yes --no-auth
  [ "$status" -eq 0 ]
  [ "$(summary_count "$output" failed)" -eq 0 ]
  [ -z "$(summary_failures "$output")" ]
}

# The counts describe the run that was planned, so they add up to it.
@test "the summary counts add up to the planned install steps" {
  run "$SETUP_SH" --dry-run --all --no-auth
  [ "$status" -eq 0 ]
  local planned; planned="$(planned_steps "$output" | grep -c .)"
  local total=$(( $(summary_count "$output" done) \
    + $(summary_count "$output" "already installed") \
    + $(summary_count "$output" skipped) \
    + $(summary_count "$output" failed) ))
  [ "$total" -eq "$planned" ]
  [[ "$(summary_counts "$output")" == "$planned install steps: "* ]]
}

# --- the exit status -----------------------------------------------------------
#
# ADR-0006's consequence: CI reads the exit status and nothing else, so a
# half-installed machine cannot come back as success.

@test "a run with no failures exits 0" {
  run "$SETUP_SH" --dry-run --yes --no-auth
  [ "$status" -eq 0 ]
}

# A plan of one Step, so the only Step in it failing is the whole run failing --
# and the counts line has to read `1 install step`, not `1 install steps`.
@test "a run whose only install step fails exits non-zero" {
  local sh; sh="$(probe_forced biome=false)"
  run "$sh" --dry-run --search=biome --simulate-fail=install_biome --no-auth
  [ "$status" -ne 0 ]
  [ "$(summary_counts "$output")" = "1 install step: 0 done, 0 already installed, 0 skipped, 1 failed" ]
}

@test "a run with several failed install steps exits non-zero" {
  local sh; sh="$(probe_forced gh=false fastfetch=false)"
  run "$sh" --dry-run --profile=default \
    --simulate-fail=install_gh,install_fastfetch --no-auth
  [ "$status" -ne 0 ]
}

# A re-run against a provisioned machine is the common case, and every row in
# `already installed` is a success.
@test "a run where every step is already installed exits 0" {
  local sh; sh="$(probe_forced gh=true fastfetch=true opencode=true node=true \
    puppeteer=true chrome=true docker=true pip=true eza=true exa-mcp=true pocock-skills=true)"
  run "$sh" --dry-run --yes --no-auth
  [ "$status" -eq 0 ]
  [ "$(states_seen "$output")" = "$(printf 'already installed\nqueued')" ]
  [ "$(summary_count "$output" "already installed")" -eq 9 ]
}

# A skip is not a failure: the run did not do the work, but nothing broke, and
# the reason is already on the Step's own line.
#
# A prerequisite that is merely missing is added now (ADR-0014), so a skip with
# nothing failing above it means one nothing can deliver. `claude-code` is the
# registry's real example — it is in a Profile and has no Install Step at all —
# and declaring it as a prerequisite is how that reaches a Step here. It is
# declared against `c-build`, which the registry orders last: a prerequisite
# ahead of the Tool that needs it is the only kind the declaration accepts.
@test "a run whose only unfinished steps were skipped exits 0" {
  local sh; sh="$(probe_forced c-build=false)"
  override 'STEP_REQUIRES[install_c_build]="claude-code"'
  run "$sh" --dry-run --search=c-build --no-auth
  [ "$status" -eq 0 ]
  [ "$(step_states "$output" install_c_build | tail -n1)" = "skipped" ]
  [ "$(step_detail "$output" install_c_build)" = "unmet dependency: claude-code" ]
  [[ "$(strip_ansi <<<"$output")" == *"No Install Step for tool: claude-code"* ]]
  [ "$(summary_count "$output" skipped)" -eq 1 ]
}
