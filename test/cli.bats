#!/usr/bin/env bats
#
# The non-interactive surface: the flags CI and scripted runs use. Every flag
# that would otherwise install is exercised under --dry-run, which is also the
# assertion that --dry-run really is inert.

load helpers

setup() { sandbox; }
teardown() { sandbox_teardown; }

# The Tool count `--dry-run` reports for the resolved Toolset.
toolset_count() {
  strip_ansi <<<"$1" | sed -n 's/.*for \([0-9]*\) selected tools.*/\1/p'
}

# The Install Step lines `--dry-run` prints, stripped to `<fn> -> <tools>` and
# still in the order the run would execute them. Install Step, not Tool, is the
# unit the dry run reports (ADR-0004), so this is what the resolution assertions
# read.
install_steps() { strip_ansi <<<"$1" | sed -n 's/.*\[DRY RUN\] Install Step: //p'; }

install_step_count() { install_steps "$1" | grep -c . || true; }

# The Tools one named Install Step is labelled with, as printed.
step_label() { install_steps "$1" | sed -n "s/^$2 -> //p"; }

# Tool keys as the spec's registry table spells them: first column of the table
# under `## Tool registry`, one per line. The range ends at the next `## `
# heading rather than naming it, so renaming that section cannot silently
# widen the range and pull in keys the registry table never listed.
spec_registry_keys() {
  sed -n '/^## Tool registry/,/^## /p' "$SETUP_ROOT/docs/spec-interactive.md" |
    sed -n 's/^| `\([a-z0-9-]*\)` |.*/\1/p'
}

# Profile keys as the spec's Profiles table lists them, one per line.
spec_profile_keys() {
  sed -n '/^## Profiles/,/^## /p' "$SETUP_ROOT/docs/spec-interactive.md" |
    sed -n 's/^| `\([a-z0-9-]*\)` |.*/\1/p'
}

# The Tools column of one row of that table, one token per line. `,` and `+`
# are both separators: a leaf Profile lists Tool keys, and the one composite
# alias names the Profiles it is built from (ADR-0001).
spec_profile_tools() {
  sed -n '/^## Profiles/,/^## /p' "$SETUP_ROOT/docs/spec-interactive.md" |
    awk -F'|' -v p="$1" '{ k=$2; gsub(/[` ]/, "", k) } k==p { print $3 }' |
    tr ',+' '\n\n' | tr -d '`' | awk 'NF { $1=$1; print }'
}

# `$PROFILES_LISTING` is `--list-profiles` captured once; every helper below
# reads it rather than re-running the script per token.
is_profile_key() { awk -v p="$1" '$1==p { f=1 } END { exit !f }' <<<"$PROFILES_LISTING"; }

# One Profile's Tools as the script resolves them, sorted.
resolved_profile_tools() {
  awk -v p="$1" '$1==p { for (i=2; i<=NF; i++) print $i }' <<<"$PROFILES_LISTING" | sort -u
}

# The spec row put through the same resolution: a token naming a Profile
# expands to that Profile's Tools, any other token stands for itself. That is
# what lets one row say `fe + be + docker` and still be compared as a Tool set.
spec_profile_expansion() {
  local tok
  while read -r tok; do
    if is_profile_key "$tok"; then resolved_profile_tools "$tok"; else echo "$tok"; fi
  done < <(spec_profile_tools "$1") | sort -u
}

@test "--help exits 0 and prints usage" {
  run "$SETUP_SH" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: sudo ./setup.sh"* ]]
}

@test "--list-profiles exits 0 and matches the registry" {
  run "$SETUP_SH" --list-profiles
  [ "$status" -eq 0 ]
  for p in default go rust fe be python-ai ai-agents full-stack-web; do
    [[ "$output" == *"$p"* ]]
  done
  [[ "$output" == *"go               go golangci-lint air"* ]]
}

@test "--list-tools exits 0 and lists all 27 tools" {
  run "$SETUP_SH" --list-tools
  [ "$status" -eq 0 ]
  [ "$(grep -c '^  [a-z]' <<<"$output")" -eq 27 ]
  [[ "$output" == *"postgres-client"* ]]
}

@test "--yes resolves the Default Toolset" {
  run "$SETUP_SH" --dry-run --yes --no-auth
  [ "$status" -eq 0 ]
  [ "$(toolset_count "$output")" -eq 11 ]
  [[ "$(install_steps "$output")" == *"install_gh -> gh"* ]]
}

# The headline of ADR-0004: the Default Toolset's 11 Tools are 9 Install Steps,
# because `node`/`puppeteer` are one and `pip`/`eza` are one. A row per Tool
# would imply a granularity the installers do not have.
@test "the Default Toolset's 11 tools resolve to 9 install steps" {
  run "$SETUP_SH" --dry-run --yes --no-auth
  [ "$status" -eq 0 ]
  [ "$(toolset_count "$output")" -eq 11 ]
  [ "$(install_step_count "$output")" -eq 9 ]
}

@test "node and puppeteer selected together are one install step" {
  run "$SETUP_SH" --dry-run --yes --no-auth
  [ "$status" -eq 0 ]
  [ "$(step_label "$output" install_node_and_puppeteer)" = "node, puppeteer" ]
  [ "$(install_steps "$output" | grep -c 'install_node_and_puppeteer')" -eq 1 ]
}

@test "pip and eza selected together are one install step" {
  run "$SETUP_SH" --dry-run --yes --no-auth
  [ "$status" -eq 0 ]
  [ "$(step_label "$output" install_pip_eza)" = "pip, eza" ]
  [ "$(install_steps "$output" | grep -c 'install_pip_eza')" -eq 1 ]
}

@test "--profile=go resolves to 3 tools in one install step" {
  run "$SETUP_SH" --dry-run --profile=go --no-auth
  [ "$status" -eq 0 ]
  [ "$(toolset_count "$output")" -eq 3 ]
  [ "$(install_step_count "$output")" -eq 1 ]
  [ "$(step_label "$output" install_go)" = "go, golangci-lint, air" ]
}

@test "--profile with two profiles unions and deduplicates" {
  run "$SETUP_SH" --dry-run --profile=go,rust --no-auth
  [ "$status" -eq 0 ]
  [ "$(toolset_count "$output")" -eq 4 ]
  [ "$(install_step_count "$output")" -eq 2 ]
}

@test "--all resolves every tool into 22 install steps" {
  run "$SETUP_SH" --dry-run --all --no-auth
  [ "$status" -eq 0 ]
  [ "$(toolset_count "$output")" -eq 27 ]
  # 27 Tools, less `claude-code` which no Install Step delivers, less the four
  # Tools that share a step with an earlier one (`puppeteer`, `eza`,
  # `golangci-lint`, `air`).
  [ "$(install_step_count "$output")" -eq 22 ]
}

# Every Tool the run would touch is accounted for: named by a step's label or
# named as having no step. Nothing may fall between the two.
@test "--all leaves no tool unaccounted for" {
  run "$SETUP_SH" --dry-run --all --no-auth
  [ "$status" -eq 0 ]
  local plain; plain="$(strip_ansi <<<"$output")"
  local labelled; labelled="$(install_steps "$output" | sed 's/^[^ ]* -> //' | tr ',' '\n')"
  local stepless; stepless="$(sed -n 's/.*No Install Step for tool: \([a-z0-9-]*\).*/\1/p' <<<"$plain")"
  local t
  for t in $("$SETUP_SH" --list-tools | sed -n 's/^  \([a-z0-9-]*\) .*/\1/p'); do
    grep -qx "$t" <<<"$(printf '%s\n%s\n' "$labelled" "$stepless" | awk 'NF { $1=$1; print }')"
  done
}

@test "--search resolves a single tool" {
  run "$SETUP_SH" --dry-run --search=postgres --no-auth
  [ "$status" -eq 0 ]
  [ "$(toolset_count "$output")" -eq 1 ]
  [ "$(install_step_count "$output")" -eq 1 ]
  [ "$(step_label "$output" install_postgres_client)" = "postgres-client" ]
  [[ "$(strip_ansi <<<"$output")" == *"matched tool: postgres-client"* ]]
}

@test "--search with no match exits 1" {
  run "$SETUP_SH" --dry-run --search=nosuchtool --no-auth
  [ "$status" -eq 1 ]
  [[ "$(strip_ansi <<<"$output")" == *"No tool matching search"* ]]
}

@test "--replay without a saved config exits 1" {
  run "$SETUP_SH" --dry-run --replay --no-auth
  [ "$status" -eq 1 ]
  [[ "$(strip_ansi <<<"$output")" == *"No saved config"* ]]
}

@test "no flags and no tty falls back to the Default Toolset" {
  run "$SETUP_SH" --dry-run --no-auth </dev/null
  [ "$status" -eq 0 ]
  [ "$(toolset_count "$output")" -eq 11 ]
  [[ "$(strip_ansi <<<"$output")" == *"No TTY detected"* ]]
}

@test "an unknown flag exits 1" {
  run "$SETUP_SH" --nope
  [ "$status" -eq 1 ]
  [[ "$(strip_ansi <<<"$output")" == *"Unknown arg"* ]]
}

# --- --dry-run is inert ------------------------------------------------------

@test "--dry-run writes nothing to /usr/local/bin" {
  ls /usr/local/bin >"$TEST_TMP/bin.before" 2>/dev/null || : >"$TEST_TMP/bin.before"
  run "$SETUP_SH" --dry-run --all --no-auth
  [ "$status" -eq 0 ]
  ls /usr/local/bin >"$TEST_TMP/bin.after" 2>/dev/null || : >"$TEST_TMP/bin.after"
  diff "$TEST_TMP/bin.before" "$TEST_TMP/bin.after"
}

@test "--dry-run writes no config file" {
  run "$SETUP_SH" --dry-run --yes --no-auth
  [ "$status" -eq 0 ]
  [ ! -e "$XDG_CONFIG_HOME/dev-setup/config.json" ]
  [[ "$(strip_ansi <<<"$output")" == *"Would save picks"* ]]
}

@test "--dry-run runs no gh auth login" {
  run "$SETUP_SH" --dry-run --yes
  [ "$status" -eq 0 ]
  [[ "$(strip_ansi <<<"$output")" == *"Would run gh auth login (skipped)"* ]]
}

# --- ADR-0004: the Toolset resolves into Install Steps ------------------------

# Step order is derived from the Tool registry's order, so the same Toolset
# always plans the same run - and it is the *picker's* order, so what a person
# read down the list in is what the run works through. `--list-tools` sorts
# alphabetically and cannot say this; the TUI list is the registry's order made
# visible, so it is what the step order is checked against.
@test "install steps come out in the tool registry's order" {
  run "$SETUP_SH" --dry-run --all --no-auth
  [ "$status" -eq 0 ]
  # The Tool that first pulls each step in, in step order...
  local heads; heads="$(install_steps "$output" | sed 's/^[^ ]* -> //; s/,.*//')"
  # ...appears in that same relative order in the registry listing.
  local registry; registry="$("$SETUP_SH" __tui_list | strip_ansi |
    sed -n 's/^\[.\] · \([a-z0-9-]*\) .*/\1/p')"
  [ "$(grep -c . <<<"$registry")" -eq 27 ]
  [ "$(grep -Fxf <(echo "$heads") <(echo "$registry"))" = "$heads" ]
}

@test "one profile plans one exact sequence of install steps" {
  run "$SETUP_SH" --dry-run --profile=full-stack-web --no-auth
  [ "$status" -eq 0 ]
  [ "$(install_steps "$output")" = "$(cat <<'EOF'
install_node_and_puppeteer -> node, puppeteer
install_chrome_stable -> chrome
install_docker -> docker
install_bun -> bun
install_pnpm -> pnpm
install_biome -> biome
install_vite -> vite
install_postgres_client -> postgres-client
install_redis_tools -> redis-tools
EOF
)" ]
}

@test "resolving the same toolset twice plans the same steps" {
  run "$SETUP_SH" --dry-run --all --no-auth
  [ "$status" -eq 0 ]
  local first; first="$(install_steps "$output")"
  run "$SETUP_SH" --dry-run --all --no-auth
  [ "$status" -eq 0 ]
  [ "$(install_steps "$output")" = "$first" ]
}

# ADR-0004: "one row per Install Step, labelled by the Tools it delivers". What
# a step delivers is fixed by the installer, not by the checkboxes: selecting
# only `node` still gets Puppeteer, and a row naming only `node` would understate
# what lands on the machine.
@test "a step is labelled by what it delivers, not by what was selected" {
  run "$SETUP_SH" --dry-run --profile=full-stack-web --no-auth
  [ "$status" -eq 0 ]
  # `full-stack-web` holds `node` and not `puppeteer`.
  local toolset; toolset="$(strip_ansi <<<"$output" | sed -n 's/^\[INFO\] Toolset: //p')"
  [[ "$toolset" == *node* ]]
  [[ "$toolset" != *puppeteer* ]]
  [ "$(step_label "$output" install_node_and_puppeteer)" = "node, puppeteer" ]
}

# A typo in the Install Step map is invisible until a real install tries to run
# a command that does not exist, and the dry run would print the bad name
# happily. So the names it reports are checked against what the script defines.
@test "every install step the dry run names is a function that exists" {
  run "$SETUP_SH" --dry-run --all --no-auth
  [ "$status" -eq 0 ]
  local fn
  for fn in $(install_steps "$output" | sed 's/ ->.*//'); do
    grep -qE "^$fn\(\) \{" "$SETUP_SH"
  done
}

# `claude-code` is in the `ai-agents` Profile and has no installer. Dropping it
# silently is what made the Profile quietly deliver less than it lists.
@test "a tool with no install step is reported, not silently dropped" {
  # `ai-agents` names `jupyter` and `qdrant` without their prerequisites, so on
  # a machine missing either, resolution would add it (ADR-0014) and the counts
  # below would be about that instead. Forced present, the Profile resolves to
  # exactly the Tools it lists, which is what this test is about.
  local sh; sh="$(probe_forced pip=true docker=true)"
  run "$sh" --dry-run --profile=ai-agents --no-auth
  [ "$status" -eq 0 ]
  local plain; plain="$(strip_ansi <<<"$output")"
  [[ "$plain" == *"No Install Step for tool: claude-code"* ]]
  [ "$(toolset_count "$output")" -eq 7 ]
  [ "$(install_step_count "$output")" -eq 6 ]
  [[ "$(install_steps "$output")" != *"claude-code"* ]]
}

# --- ADR-0001: full-stack-web resolves, it does not restate -------------------

@test "--profile=full-stack-web resolves to fe + be + docker + chrome + node" {
  run "$SETUP_SH" --dry-run --profile=full-stack-web --no-auth
  [ "$status" -eq 0 ]
  [ "$(toolset_count "$output")" -eq 9 ]
  local steps; steps="$(install_steps "$output")"
  for t in bun pnpm biome vite postgres-client redis-tools docker chrome node; do
    [[ "$steps" == *"$t"* ]]
  done
  # c-build was in the old literal and is in none of the composed Profiles.
  [[ "$steps" != *"c-build"* ]]
}

# The property the ADR exists for. Patching a Tool into `fe` and asserting it
# comes out of the alias is the only way to tell resolution from a literal that
# happens to agree with it today.
@test "a tool added to fe reaches full-stack-web with no edit to the alias" {
  sed -E 's/^  \[fe\]="([^"]*)"/  [fe]="\1 eza"/' "$SETUP_SH" >"$TEST_TMP/setup.sh"
  chmod +x "$TEST_TMP/setup.sh"
  grep -q '\[fe\]=".* eza"' "$TEST_TMP/setup.sh"
  run "$TEST_TMP/setup.sh" --dry-run --profile=full-stack-web --no-auth
  [ "$status" -eq 0 ]
  [ "$(toolset_count "$output")" -eq 10 ]
  # Labelled by what the step delivers, so `pip` is named even though only
  # `eza` was selected -- `install_pip_eza` lays down both either way.
  [ "$(step_label "$output" install_pip_eza)" = "pip, eza" ]
}

# install_base_deps installs build-essential unconditionally, so gcc and make
# are never what c-build delivers. Its description has to say what is.
@test "c-build describes only what base deps do not already install" {
  run "$SETUP_SH" --list-tools
  [ "$status" -eq 0 ]
  local line; line="$(grep '^  c-build' <<<"$output")"
  [[ "$line" == *"cmake"* ]]
  [[ "$line" == *"pkg-config"* ]]
  [[ "$line" != *"gcc"* ]]
}

# A Tool key is a domain term, so the spec has to spell it the way the code
# does: `docs/agents/domain.md` forbids the drift, and a key that disagrees
# with the registry silently invalidates the `--profile=` examples beside it.
@test "every Tool key in the spec's registry table exists in --list-tools" {
  run "$SETUP_SH" --list-tools
  [ "$status" -eq 0 ]
  local keys; keys="$(spec_registry_keys)"
  [ -n "$keys" ]
  while read -r key; do
    grep -qE "^  $key +" <<<"$output" ||
      { echo "spec registry key absent from --list-tools: $key" >&2; return 1; }
  done <<<"$keys"
}

# The registry guard above only reaches the registry table. This one reaches
# the Profiles table, by resolving both sides to a Tool set and comparing
# those: it catches a Tool named wrongly, a Tool that never existed, and a
# Tool the row forgot, none of which a spelling check alone would see.
@test "every Profile row in the spec resolves to what --list-profiles resolves" {
  PROFILES_LISTING="$("$SETUP_SH" --list-profiles)"
  local keys; keys="$(spec_profile_keys)"
  [ -n "$keys" ]
  while read -r p; do
    diff <(spec_profile_expansion "$p") <(resolved_profile_tools "$p") ||
      { echo "spec Profile row disagrees with --list-profiles: $p" >&2; return 1; }
  done <<<"$keys"
}
