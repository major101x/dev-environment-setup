#!/usr/bin/env bats
#
# Prerequisites between Tools (#23). A prerequisite is declared data — the Tools
# an Install Step needs on the machine before it can do anything — and
# resolution closes the Toolset over it, so picking a dependent no longer
# guarantees a skip. Every addition is announced by name: a Tool the user did
# not ask for must never appear without an explanation.
#
# Driven through `--dry-run`, which resolves exactly as a real run does, with
# presence probes forced so a test never depends on what the machine running it
# happens to have.

load helpers

setup() { sandbox; }
teardown() { sandbox_teardown; }

# The additions a run announced, one `<tool> - required by <tool>` per line.
added_prerequisites() {
  strip_ansi <<<"$1" | sed -n 's/^\[INFO\] Added prerequisite: //p'
}

# The Toolset the run settled on, as it printed it.
toolset_line() { strip_ansi <<<"$1" | sed -n 's/^\[INFO\] Toolset: //p'; }

# The prerequisite table as the script declares it, one `<step> <tools>` per
# line — read out of the file, because the point of #23 is that this is data
# and not something reconstructed from the order installers happen to run in.
declared_requires() {
  sed -n '/^declare -A STEP_REQUIRES=(/,/^)/p' "$SETUP_SH" |
    sed -n 's/^  \[\([a-z_]*\)\]="\(.*\)"$/\1 \2/p'
}

# The Install Step that delivers one Tool, off the same map the script resolves
# with. The `=install_` shape matches TOOL_INSTALL_STEP and nothing else.
step_of_tool() { sed -n "s/^  \[$1\]=\(install_[a-z_]*\)\$/\1/p" "$SETUP_SH"; }

# --- the declaration ------------------------------------------------------------

# The four cases #23 opens with, all of which used to fail for a reason the run
# already knew: each is declared, and each is added when it is missing.
@test "the prerequisites of the skills bundle, vector db, notebook and mcp are added" {
  local sh; sh="$(probe_forced node=false pocock-skills=false docker=false qdrant=false \
    pip=false eza=false jupyter=false opencode=false exa-mcp=false)"

  run "$sh" --dry-run --search=pocock --no-auth
  [ "$status" -eq 0 ]
  [ "$(added_prerequisites "$output")" = "node - required by pocock-skills" ]

  run "$sh" --dry-run --search=qdrant --no-auth
  [ "$status" -eq 0 ]
  [ "$(added_prerequisites "$output")" = "docker - required by qdrant" ]

  run "$sh" --dry-run --search=jupyter --no-auth
  [ "$status" -eq 0 ]
  [ "$(added_prerequisites "$output")" = "pip - required by jupyter" ]

  run "$sh" --dry-run --search=exa-mcp --no-auth
  [ "$status" -eq 0 ]
  [ "$(added_prerequisites "$output")" = "opencode - required by exa-mcp" ]
}

# Ordering is not the mechanism, but it still has to hold: a prerequisite whose
# Install Step ran after its dependent would be met too late to help. Checked
# against the declared table rather than a hand-written list, so a prerequisite
# added later cannot quietly land in the wrong half of the plan.
@test "every declared prerequisite is delivered before the step that needs it" {
  run "$SETUP_SH" --dry-run --all --no-auth
  [ "$status" -eq 0 ]
  local plan; plan="$(planned_steps "$output")"
  [ "$(grep -c . <<<"$plan")" -eq 22 ]
  local dependent required tool provider di pi
  while read -r dependent required; do
    for tool in $required; do
      provider="$(step_of_tool "$tool")"
      [ -n "$provider" ]
      di="$(grep -n "^$dependent\$" <<<"$plan" | cut -d: -f1)"
      pi="$(grep -n "^$provider\$" <<<"$plan" | cut -d: -f1)"
      [ -n "$di" ] && [ -n "$pi" ] && [ "$pi" -lt "$di" ]
    done
  done < <(declared_requires)
  [ "$(declared_requires | grep -c .)" -ge 7 ]
}

# --- resolution adds what is missing --------------------------------------------

# The headline of #23: `--search=jupyter` used to install nothing useful, because
# the one Step it planned was skipped for want of pip.
@test "--search=jupyter resolves to include its prerequisite and says so" {
  local sh; sh="$(probe_forced pip=false eza=false jupyter=false)"
  run "$sh" --dry-run --search=jupyter --no-auth
  [ "$status" -eq 0 ]
  [ "$(added_prerequisites "$output")" = "pip - required by jupyter" ]
  [ "$(planned_steps "$output")" = "$(printf 'install_pip_eza\ninstall_jupyter')" ]
  [ "$(step_states "$output" install_jupyter | tail -n1)" = "done" ]
}

# The Toolset is what gets installed, so an addition that did not reach it would
# be an announcement about nothing.
@test "an added prerequisite is part of the toolset the run reports" {
  local sh; sh="$(probe_forced pip=false eza=false jupyter=false)"
  run "$sh" --dry-run --search=jupyter --no-auth
  [ "$status" -eq 0 ]
  [[ " $(toolset_line "$output") " == *" pip "* ]]
  [[ " $(toolset_line "$output") " == *" jupyter "* ]]
}

# `missing` is the whole of it. A prerequisite already on the machine is met,
# the run would not have skipped anything for it, and adding it would drag its
# Install Step — and every other Tool that step delivers — into a Toolset
# nobody asked for.
@test "a prerequisite already on the machine is not added" {
  local sh; sh="$(probe_forced pip=true jupyter=false)"
  run "$sh" --dry-run --search=jupyter --no-auth
  [ "$status" -eq 0 ]
  [ -z "$(added_prerequisites "$output")" ]
  [ "$(planned_steps "$output")" = "install_jupyter" ]
  [ "$(step_states "$output" install_jupyter | tail -n1)" = "done" ]
}

# Nor is one the user already picked: the Toolset is a set, and `fe` naming
# `node` itself must not produce a second copy or a second line about it.
@test "a prerequisite the user already picked is not announced" {
  local sh; sh="$(probe_forced node=false puppeteer=false)"
  run "$sh" --dry-run --profile=default --no-auth
  [ "$status" -eq 0 ]
  [ -z "$(added_prerequisites "$output")" ]
}

# One Tool, one line, however many dependents pulled it in: `fe` holds three
# Tools that each need node, and three lines about node would read as three
# additions.
@test "a prerequisite three tools need is added once and announced once" {
  local sh; sh="$(probe_forced node=false puppeteer=false bun=false pnpm=false biome=false vite=false)"
  run "$sh" --dry-run --profile=fe --no-auth
  [ "$status" -eq 0 ]
  [ "$(added_prerequisites "$output" | grep -c .)" -eq 1 ]
  [ "$(added_prerequisites "$output")" = "node - required by pnpm" ]
  [ "$(planned_steps "$output" | head -n1)" = "install_node_and_puppeteer" ]
}

# Two missing prerequisites are two lines, not a list: #23 asks for each
# addition on its own line so a Tool can be traced back to the pick that
# brought it in.
@test "each auto-added prerequisite is announced on its own line" {
  local sh; sh="$(probe_forced pip=false eza=false docker=false jupyter=false qdrant=false \
    uv=false ollama=false opencode=false exa-mcp=false)"
  run "$sh" --dry-run --profile=ai-agents --no-auth
  [ "$status" -eq 0 ]
  [ "$(added_prerequisites "$output")" = "$(printf 'docker - required by qdrant\npip - required by jupyter')" ]
}

# The announcement is narration, so it is in the log for the same reason every
# other line is: the log is what gets pasted into a bug report.
@test "the announcement reaches the log" {
  local sh; sh="$(probe_forced pip=false eza=false jupyter=false)"
  run "$sh" --dry-run --search=jupyter --no-auth
  [ "$status" -eq 0 ]
  grep -qF "[INFO] Added prerequisite: pip - required by jupyter" "$LOG_FILE"
}

# --- the same resolution either way ---------------------------------------------

# One resolution, so the two modes cannot drift. The picker's end is
# `__tui_resolve` — ENTER, the checked set — and what it produces is what
# `--replay` reads back, so the same selection is put through both entries and
# the plans compared.
@test "a toolset picked interactively resolves the same as the same toolset on the cli" {
  local sh; sh="$(probe_forced pip=false eza=false jupyter=false)"

  printf 'jupyter\n' >"$TUI_STATE/checked"
  : >"$TUI_STATE/profiles"
  run "$SETUP_SH" __tui_resolve
  [ "$status" -eq 0 ]
  [ "$(sed -n 's/^tools: //p' <<<"$output")" = "jupyter" ]

  mkdir -p "$XDG_CONFIG_HOME/dev-setup"
  cat >"$XDG_CONFIG_HOME/dev-setup/config.json" <<'JSON'
{
  "profiles": [],
  "tools": ["jupyter"],
  "toolchain": false
}
JSON

  run "$sh" --dry-run --replay --no-auth
  [ "$status" -eq 0 ]
  local replayed; replayed="$(planned_steps "$output")"
  local announced; announced="$(added_prerequisites "$output")"

  run "$sh" --dry-run --search=jupyter --no-auth
  [ "$status" -eq 0 ]
  [ "$(planned_steps "$output")" = "$replayed" ]
  [ "$(added_prerequisites "$output")" = "$announced" ]
  [ "$announced" = "pip - required by jupyter" ]
}

# --- what is still genuinely unavailable -----------------------------------------

# Auto-adding narrows `skipped` to the case it was always for: the prerequisite
# was planned, and did not land. The Step below it is not a second failure.
@test "a dependent whose prerequisite failed reaches skipped with the reason" {
  local sh; sh="$(probe_forced pip=false eza=false jupyter=false)"
  run "$sh" --dry-run --search=jupyter --simulate-fail=install_pip_eza --no-auth
  [ "$status" -eq 1 ]
  [ "$(step_states "$output" install_pip_eza | tail -n1)" = "failed" ]
  [ "$(step_states "$output" install_jupyter | tail -n1)" = "skipped" ]
  [ "$(step_detail "$output" install_jupyter)" = "unmet dependency: pip" ]
}

# --- a declaration that cannot be resolved ---------------------------------------

# A prerequisite graph that leads back to itself has no answer: closing a
# Toolset over it either never finishes or stops somewhere arbitrary and calls
# the result complete. It is a bug in the declaration, so the run says which
# cycle and stops rather than installing a set nobody can justify.
@test "a circular prerequisite declaration is rejected" {
  local sh; sh="$(script_copy)"
  probe_forced pip=false jupyter=false >/dev/null
  override 'STEP_REQUIRES[install_pip_eza]="jupyter"'
  run timeout 20 "$sh" --dry-run --search=jupyter --no-auth
  [ "$status" -eq 1 ]
  local plain; plain="$(strip_ansi <<<"$output")"
  [[ "$plain" == *"Prerequisite cycle"* ]]
  [[ "$plain" == *"jupyter"* ]]
  [[ "$plain" == *"pip"* ]]
}

@test "a self-referential prerequisite declaration is rejected" {
  local sh; sh="$(script_copy)"
  probe_forced jupyter=false >/dev/null
  override 'STEP_REQUIRES[install_jupyter]="jupyter"'
  run timeout 20 "$sh" --dry-run --search=jupyter --no-auth
  [ "$status" -eq 1 ]
  [[ "$(strip_ansi <<<"$output")" == *"Prerequisite cycle: jupyter -> jupyter"* ]]
}

# The cycle is in the declaration, not in the selection, so it is caught
# whatever was picked — a run that happened to select around it would install
# happily and leave the next one to find it.
@test "a cycle is rejected even when nothing selected touches it" {
  local sh; sh="$(script_copy)"
  override 'STEP_REQUIRES[install_jupyter]="jupyter"'
  run timeout 20 "$sh" --dry-run --profile=go --no-auth
  [ "$status" -eq 1 ]
  [[ "$(strip_ansi <<<"$output")" == *"Prerequisite cycle"* ]]
}

# The declared table is acyclic, and stays that way: this is the assertion the
# two above are the machinery for.
@test "the declared prerequisites hold no cycle" {
  run "$SETUP_SH" --dry-run --all --no-auth
  [ "$status" -eq 0 ]
  [[ "$(strip_ansi <<<"$output")" != *"Prerequisite cycle"* ]]
}
