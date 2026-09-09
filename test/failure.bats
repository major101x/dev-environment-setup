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

# Every Install Step the summary named as failed, one per line. The name is not
# required to be followed by a space: a Step that delivers no Tool carries no
# `(tools)` after it (#68), so the parenthesis is not what ends the name.
summary_failures() {
  strip_ansi <<<"$1" | sed -n 's/^\[ERROR\] Failed: \([a-z_]*\).*/\1/p'
}

# The whole of one summary failure line, from `Failed:` on.
summary_failure_line() {
  strip_ansi <<<"$1" | sed -n "s/^\[ERROR\] \(Failed: $2.*\)/\1/p"
}

# --- base dependencies is what everything else needs ---------------------------
#
# #68. Base dependencies delivers `ca-certificates`, `curl`, `gnupg` and the rest
# that every other Install Step reaches for, so its failure is not one failure
# among independent peers -- it is the reason none of the others can run. ADR-0006
# says a failed Step does not abort the run, and that stays true: what changes is
# that the Steps after this one are `skipped` for a named reason rather than each
# failing on its own `curl: command not found`.
#
# Expressed as a rule rather than as a `STEP_REQUIRES` edge, because there is
# exactly one Step every Step needs and a general Step-to-Step requirement built
# for a single edge is a mechanism nobody asked for. See ADR-0018.
@test "base dependencies failing skips the steps that still had work to do" {
  # Forced absent, so `install_go` genuinely has work and the skip is the
  # cascade rather than the machine happening to have Go.
  local sh; sh="$(probe_forced go=false golangci-lint=false air=false)"
  run "$sh" --dry-run --profile=go --simulate-fail=install_base_deps --no-auth
  [ "$status" -eq 1 ]
  [ "$(step_states "$output" install_go | tail -n1)" = "skipped" ]
  [ "$(step_detail "$output" install_go | tail -n1)" = "unmet dependency: base dependencies" ]
  [ "$(summary_count "$output" done)" -eq 0 ]
  [ "$(summary_failures "$output")" = "install_base_deps" ]
}

# ADR-0005 asks `already installed` before it asks about prerequisites, so a Step
# with nothing left to do is not skipped for want of one. That holds for this
# prerequisite too: base dependencies failing does not retroactively make an
# installed Tool uninstalled. The rule sits below the already-installed check for
# exactly this reason, and it is the placement that needs asserting.
@test "base dependencies failing does not skip a step that had nothing to do" {
  local sh; sh="$(probe_forced go=true golangci-lint=true air=true)"
  run "$sh" --dry-run --profile=go --simulate-fail=install_base_deps --no-auth
  [ "$status" -eq 1 ]
  [ "$(step_states "$output" install_go | tail -n1)" = "already installed" ]
}

# The run still ends with an account of itself. Before #68 base dependencies ran
# at the top level under `set -euo pipefail` with no trap, so apt failing killed
# the run where it stood: no summary, no counts, nothing said about which Steps
# were owed. As an Install Step it runs inside the subshell `run_install_step`
# already wraps every Step in, which reports the status instead of dying on it.
@test "base dependencies failing still reaches a summary" {
  run "$SETUP_SH" --dry-run --profile=default --simulate-fail=install_base_deps --no-auth
  [ "$status" -eq 1 ]
  [ "$(summary_count "$output" failed)" -eq 1 ]
  [ "$(summary_count "$output" done)" -eq 0 ]
  # Every Step the failure reached is either skipped for it or had nothing to do.
  local fn last
  for fn in $(planned_steps "$output" | grep -vx install_base_deps); do
    last="$(step_states "$output" "$fn" | tail -n1)"
    [ "$last" = "skipped" ] || [ "$last" = "already installed" ]
    if [ "$last" = "skipped" ]; then
      [ "$(step_detail "$output" "$fn" | tail -n1)" = "unmet dependency: base dependencies" ]
    fi
  done
}

@test "a failed step that delivers no tool is named without empty parentheses" {
  run "$SETUP_SH" --dry-run --profile=default --simulate-fail=install_base_deps --no-auth
  [ "$status" -eq 1 ]
  [ "$(summary_failure_line "$output" install_base_deps)" = "Failed: install_base_deps - simulated failure" ]
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
  # 10 steps since #68: base dependencies leads every plan and is the seventh
  # `done` here. Then gh already installed, node+puppeteer failed, pocock-skills
  # skipped in its wake, the other six done.
  [ "$(summary_counts "$output")" = "10 install steps: 7 done, 1 already installed, 1 skipped, 1 failed" ]
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

# The smallest plan a run can have: one Tool, and the base dependencies every
# Tool needs (#68). The Tool's Step failing is the whole of the Toolset failing.
@test "a run whose only selected install step fails exits non-zero" {
  local sh; sh="$(probe_forced biome=false)"
  run "$sh" --dry-run --search=biome --simulate-fail=install_biome --no-auth
  [ "$status" -ne 0 ]
  [ "$(summary_counts "$output")" = "2 install steps: 1 done, 0 already installed, 0 skipped, 1 failed" ]
}

# `1 install step`, not `1 install steps`. Before #68 the singular was easy --
# any one-Tool `--search` gave it. Base dependencies now leads every plan, so the
# only plan of one left is a Toolset whose Tools have no Install Step at all: the
# Tool is reported as stepless, nothing is added for it, and base dependencies is
# the whole of the plan. Spliced in the way the skip test below splices one, for
# the same reason -- the registry has no stepless Tool any more.
@test "a plan of one install step says step, not steps" {
  local sh; sh="$(script_copy)"
  override 'TOOL_CATEGORY[widget]="AI/ML"; TOOL_DESC[widget]="Widget"; ORDERED_TOOLS=(widget "${ORDERED_TOOLS[@]}")'
  run "$sh" --dry-run --search=widget --no-auth
  [ "$status" -eq 0 ]
  [ "$(planned_steps "$output")" = "install_base_deps" ]
  [ "$(summary_counts "$output")" = "1 install step: 1 done, 0 already installed, 0 skipped, 0 failed" ]
}

# A re-run against a provisioned machine is the common case, and every row in
# `already installed` is a success.
#
# Since #68 no run is ever *entirely* `already installed`: base dependencies
# delivers no Tool, so no presence probe can answer for it and it does its work
# on every run. That is the point of it -- an apt cache is stale whether or not
# the Tools are there -- and it is why `done`, `downloading` and `installing`
# appear here alongside `already installed` on a fully provisioned machine.
@test "a run where every selected step is already installed exits 0" {
  local sh; sh="$(probe_forced gh=true fastfetch=true opencode=true node=true \
    puppeteer=true chrome=true docker=true pip=true eza=true exa-mcp=true pocock-skills=true)"
  run "$sh" --dry-run --yes --no-auth
  [ "$status" -eq 0 ]
  [ "$(states_seen "$output")" = "$(printf 'already installed\ndone\ndownloading\ninstalling\nqueued')" ]
  [ "$(summary_count "$output" "already installed")" -eq 9 ]
  [ "$(summary_count "$output" done)" -eq 1 ]
}

# A skip is not a failure: the run did not do the work, but nothing broke, and
# the reason is already on the Step's own line.
#
# A prerequisite that is merely missing is added now (ADR-0014), so a skip with
# nothing failing above it means one nothing can deliver: a Tool with no Install
# Step, which nothing can add. `claude-code` was the registry's real example
# until #53 gave it an installer, so the Tool is spliced in here instead — no
# probe and no step, so absent on every machine — and declared against
# `c-build`, which the registry orders last: a prerequisite ahead of the Tool
# that needs it is the only kind the declaration accepts.
@test "a run whose only unfinished steps were skipped exits 0" {
  local sh; sh="$(probe_forced c-build=false)"
  override 'TOOL_CATEGORY[widget]="AI/ML"; TOOL_DESC[widget]="Widget"; ORDERED_TOOLS=(widget "${ORDERED_TOOLS[@]}"); STEP_REQUIRES[install_c_build]="widget"'
  run "$sh" --dry-run --search=c-build --no-auth
  [ "$status" -eq 0 ]
  [ "$(step_states "$output" install_c_build | tail -n1)" = "skipped" ]
  [ "$(step_detail "$output" install_c_build)" = "unmet dependency: widget" ]
  [[ "$(strip_ansi <<<"$output")" == *"No Install Step for tool: widget"* ]]
  [ "$(summary_count "$output" skipped)" -eq 1 ]
}
