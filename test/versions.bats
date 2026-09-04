#!/usr/bin/env bats
#
# The version a completed Install Step reports for each Tool it delivered
# (#19). The probes are declared per Tool, defaulting by convention to
# `<tool> --version`, and the answer rides out on the terminal transition as
# its detail — so the same line the screen draws is the one a pipe reads and
# these tests assert.
#
# Two seams, both at the process boundary: `--dry-run`, which reports without
# probing, and a *real* run with every installer stubbed (`runnable`), which is
# the only way to see a probe actually run. A fake binary on PATH answering
# `1.0.0` is what makes the probed value deterministic — nothing here depends
# on what happens to be installed on the machine running the suite.

load helpers

setup() { sandbox; }
teardown() { sandbox_teardown; }

# The declared table, one `<tool> <probe>` per line. Read out of the script so
# a Tool added to it cannot escape the assertions below.
declared_versions() {
  sed -n '/^declare -A TOOL_VERSION=(/,/^)/p' "$SETUP_SH" |
    sed -n 's/^  \[\([a-z0-9-]*\)\]=\(.*\)$/\1 \2/p'
}

# A run that reaches one Install Step for real, with everything that would
# touch the machine stubbed out. `node` is forced present because the npm-based
# Steps declare it as a prerequisite, so nothing else is pulled into the plan.
stubbed_run() {
  probe_forced node=true "$@" >/dev/null
  runnable >/dev/null
}

# --- a completed step reports what it delivered --------------------------------

# Story 9 of #15: confirm you got what you expected without running commands
# yourself. A Step that delivers one Tool is that Tool's row, so its version is
# the whole of the detail.
@test "a step that installed reports the version of the tool it delivered" {
  stubbed_run biome=false
  fake_tool biome
  run "$(script_copy)" --search=biome --no-auth
  [ "$status" -eq 0 ]
  [ "$(step_states "$output" install_biome | tail -n1)" = "done" ]
  [ "$(step_detail "$output" install_biome)" = "1.0.0" ]
}

# ADR-0004: the Install Step is the unit, and it is many-to-one. A version per
# Tool delivered means both of them, each named, because the row cannot say
# which number belongs to which otherwise.
@test "a step that delivers two tools reports a version for each, named" {
  stubbed_run pip=false eza=false
  fake_tool pip3
  fake_tool eza
  run "$(script_copy)" --search=eza --no-auth
  [ "$status" -eq 0 ]
  [ "$(step_detail "$output" install_pip_eza)" = "pip 1.0.0 · eza 1.0.0" ]
}

# Story 10 of #15: a re-run must not look like twenty suspiciously instant
# successes. `already installed` says what was found, which is the difference.
@test "an already installed step reports the version it found" {
  stubbed_run
  fake_tool gh
  run "$(script_copy)" --search=gh --no-auth
  [ "$status" -eq 0 ]
  [ "$(step_states "$output" install_gh | tail -n1)" = "already installed" ]
  [ "$(step_detail "$output" install_gh)" = "1.0.0" ]
}

# The version is on the transition, so it reaches the log by the same route as
# every other state change (ADR-0011, ADR-0012) — no second account of it.
@test "the version reaches the log with the transition that carried it" {
  stubbed_run biome=false
  fake_tool biome
  run "$(script_copy)" --search=biome --no-auth
  [ "$status" -eq 0 ]
  grep -qxF "[STEP] install_biome | done | 1.0.0" "$LOG_FILE"
}

# --- what the probe says, and nothing more -------------------------------------

# The probe's output is whatever its author felt like: `gh version 2.63.2
# (2024-12-05)`, `v22.11.0`, `go version go1.23.4 linux/amd64`. The version is
# the word carrying the number, wherever in the answer it sits.
@test "the version is taken from anywhere in what the probe answered" {
  stubbed_run biome=false
  fake_tool biome 'echo "not a version line"; echo "biome version 4.5.6, built today"'
  run "$(script_copy)" --search=biome --no-auth
  [ "$status" -eq 0 ]
  [ "$(step_detail "$output" install_biome)" = "4.5.6" ]
}

# A prefix the tool itself printed is kept — `go1.23.4` and `v22.11.0` are how
# Go and Node name their own versions, and inventing a tidier string would be
# reporting something neither of them said.
@test "a version the tool prints attached to a word keeps the word" {
  stubbed_run biome=false
  fake_tool biome 'echo "biome version v4.5.6 linux/amd64"'
  run "$(script_copy)" --search=biome --no-auth
  [ "$status" -eq 0 ]
  [ "$(step_detail "$output" install_biome)" = "v4.5.6" ]
}

# Never a fake value: a probe that answers with no version at all is reported
# as unanswered, because a made-up number is the one thing worse than not
# knowing.
@test "a probe that answers no version reports unknown rather than inventing one" {
  stubbed_run biome=false
  fake_tool biome 'exit 0'
  run "$(script_copy)" --search=biome --no-auth
  [ "$status" -eq 0 ]
  [ "$(step_detail "$output" install_biome)" = "(unknown)" ]
}

# The commoner way for a probe to answer nothing: there is no such binary. An
# installer that put its Tool somewhere the run cannot see reaches this, so the
# Tool is spliced in rather than named — nothing on the machine can answer for
# it, whatever the machine has.
@test "a probe with no binary behind it reports unknown" {
  stubbed_run
  override 'TOOL_CATEGORY[widget]="Frontend"; TOOL_DESC[widget]="Widget"; TOOL_INSTALL_STEP[widget]=install_widget; ORDERED_TOOLS+=(widget); install_widget() { :; }'
  run "$(script_copy)" --search=widget --no-auth
  [ "$status" -eq 0 ]
  [ "$(step_states "$output" install_widget | tail -n1)" = "done" ]
  [ "$(step_detail "$output" install_widget)" = "(unknown)" ]
}

# ADR-0004 again, with three: `install_go` delivers go, golangci-lint and air,
# and the row names all three whether one of them was picked or all of them.
@test "a step that delivers three tools reports a version for each" {
  stubbed_run go=false golangci-lint=false air=false
  fake_tool go 'echo "go version go1.23.4 linux/amd64"'
  fake_tool golangci-lint
  fake_tool air 'echo "v1.61.5"'
  run "$(script_copy)" --search=golangci --no-auth
  [ "$status" -eq 0 ]
  [ "$(step_detail "$output" install_go)" = "go go1.23.4 · golangci-lint 1.0.0 · air v1.61.5" ]
}

# The PATH case the table exists for, and the one a convention could never
# reach: `npm install -g` under nvm puts pnpm in a directory named after a Node
# version, which the run's own shell has never heard of. Nothing but sourcing
# nvm finds it, and a probe that did not would report `(unknown)` for a Tool it
# had just installed.
@test "a tool npm installed under nvm is still reached by its probe" {
  stubbed_run pnpm=false
  export NVM_DIR="$HOME/.nvm"
  mkdir -p "$NVM_DIR" "$HOME/nvmbin"
  printf 'export PATH="%s/nvmbin:$PATH"\n' "$HOME" >"$NVM_DIR/nvm.sh"
  fake_tool_at "$HOME/nvmbin" pnpm 'echo "9.14.4"'
  run "$(script_copy)" --search=pnpm --no-auth
  [ "$status" -eq 0 ]
  [ "$(step_detail "$output" install_pnpm)" = "9.14.4" ]
}

# The other kind of probe that has to find its own binary: puppeteer's browser
# lives under a versioned directory in a cache. The glob is the command, so a
# cache holding two builds would make the second an argument to the first --
# which is not an error, just a version reported for the wrong browser.
@test "a probe that globs a cache answers for one build, not all of them" {
  stubbed_run node=true puppeteer=false
  export NVM_DIR="$HOME/.nvm"
  mkdir -p "$NVM_DIR"
  printf 'export PATH="%s/nvmbin:$PATH"\n' "$HOME" >"$NVM_DIR/nvm.sh"
  fake_tool_at "$HOME/nvmbin" node 'echo "v22.11.0"'
  local v
  for v in 120.0.1 131.0.6778.85; do
    fake_tool_at "$HOME/.cache/puppeteer/chrome/linux-$v/chrome-linux64" chrome \
      "echo \"Google Chrome for Testing $v\""
  done
  run "$(script_copy)" --search=puppeteer --no-auth
  [ "$status" -eq 0 ]
  [ "$(step_detail "$output" install_node_and_puppeteer)" = "node v22.11.0 · puppeteer 131.0.6778.85" ]
}

# --- the tools that have no version --------------------------------------------

# The Matt Pocock skills bundle is a count of files on disk and the Exa MCP
# entry is a registration, not an executable. Both are declared to have no
# version and say so.
@test "a tool with no version reports installed rather than a fabricated value" {
  stubbed_run pocock-skills=false
  run "$(script_copy)" --search=pocock --no-auth
  [ "$status" -eq 0 ]
  [ "$(step_states "$output" install_pocock_skills | tail -n1)" = "done" ]
  [ "$(step_detail "$output" install_pocock_skills)" = "installed" ]
}

@test "only the tools that genuinely have no version are declared to have none" {
  [ "$(declared_versions | awk '$2 == "none" { print $1 }')" = \
    "$(printf 'exa-mcp\npocock-skills')" ]
}

# --- the convention ------------------------------------------------------------

# A Tool with no entry falls back to `<tool> --version`, so adding one is a
# registry edit and nothing else. Spliced in rather than named from the
# registry: a Tool that happens to use the convention today would pass this
# even if the fallback had been deleted.
@test "a tool with no declared probe falls back to the convention" {
  stubbed_run
  override 'TOOL_CATEGORY[widget]="Frontend"; TOOL_DESC[widget]="Widget"; TOOL_INSTALL_STEP[widget]=install_widget; ORDERED_TOOLS+=(widget); install_widget() { :; }'
  fake_tool widget
  run "$(script_copy)" --search=widget --no-auth
  [ "$status" -eq 0 ]
  [ "$(step_states "$output" install_widget | tail -n1)" = "done" ]
  [ "$(step_detail "$output" install_widget)" = "1.0.0" ]
}

@test "every declared version probe names a tool in the registry" {
  local listed; listed="$("$SETUP_SH" --list-tools)"
  local tool
  while read -r tool _; do
    grep -qE "^  $tool +" <<<"$listed" ||
      { echo "TOOL_VERSION names a tool the registry does not: $tool" >&2; return 1; }
  done < <(declared_versions)
  [ "$(declared_versions | grep -c .)" -ge 15 ]
}

# --- a dry run reports without probing -----------------------------------------

# #10's contract, kept by this feature rather than broken by it: a dry run
# executes no probe. Asserted by leaving one on PATH that records being asked.
@test "a dry run reports a simulated version and runs no probe" {
  local sh; sh="$(probe_forced node=true biome=false)"
  witness_tool biome
  run "$sh" --dry-run --search=biome --no-auth
  [ "$status" -eq 0 ]
  [ "$(step_detail "$output" install_biome)" = "(dry run)" ]
  [ ! -e "$TEST_TMP/ran-biome" ]
}

@test "a dry run reports a simulated version for an already installed step" {
  local sh; sh="$(probe_forced node=true biome=true)"
  witness_tool biome
  run "$sh" --dry-run --search=biome --no-auth
  [ "$status" -eq 0 ]
  [ "$(step_states "$output" install_biome | tail -n1)" = "already installed" ]
  [ "$(step_detail "$output" install_biome)" = "(dry run)" ]
  [ ! -e "$TEST_TMP/ran-biome" ]
}

# Declared data needs no probe, so the dry run knows it as surely as the run
# does and says the same thing.
@test "a dry run still reports the tools that have no version as installed" {
  local sh; sh="$(probe_forced opencode=true pocock-skills=false node=true puppeteer=true)"
  run "$sh" --dry-run --search=exa-mcp --no-auth
  [ "$status" -eq 0 ]
  [ "$(step_detail "$output" install_exa_mcp)" = "installed" ]
}

# --- the step's report is the only one ------------------------------------------
#
# #25 deleted the trailing Verification block, so what an Install Step said
# about the Tools it delivered is the run's whole account of a version. Two
# reports that can disagree are worse than one, and the second one was also
# where #10 and #11 lived.

@test "a real run reports a version once, on the step that delivered it" {
  stubbed_run biome=false
  fake_tool biome
  run "$(script_copy)" --search=biome --no-auth
  [ "$status" -eq 0 ]
  local plain; plain="$(strip_ansi <<<"$output")"
  [ "$(step_detail "$output" install_biome)" = "1.0.0" ]
  [ "$(grep -o '1\.0\.0' <<<"$plain" | wc -l)" -eq 1 ]
  [[ "$plain" != *"--- Versions ---"* ]]
}

# #11: fastfetch beside a logo emits cursor-forward escapes, and the deleted
# block ran it whatever the Toolset held. Nothing runs it now, so a Tool that
# writes escapes cannot put them on a piped stdout or in the log.
@test "a real run emits no escape sequences to a pipe or the log" {
  stubbed_run biome=false
  fake_tool fastfetch "printf '\033[47CDE: GNOME 46.0\n'"
  run "$(script_copy)" --search=biome --no-auth
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\033'* ]]
  ! grep -q $'\033' "$LOG_FILE"
}
