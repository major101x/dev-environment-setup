#!/usr/bin/env bats
#
# The non-interactive surface: the flags CI and scripted runs use. Every flag
# that would otherwise install is exercised under --dry-run, which is also the
# assertion that --dry-run really is inert.

load helpers

setup() { sandbox; }
teardown() { sandbox_teardown; }

# Count of `[DRY RUN] Would install: <tool>` lines — the resolved Toolset.
would_install_count() { strip_ansi <<<"$1" | grep -c 'Would install: ' || true; }

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
  [ "$(would_install_count "$output")" -eq 11 ]
  [[ "$(strip_ansi <<<"$output")" == *"Would install: gh"* ]]
}

@test "--profile=go resolves to 3 tools" {
  run "$SETUP_SH" --dry-run --profile=go --no-auth
  [ "$status" -eq 0 ]
  [ "$(would_install_count "$output")" -eq 3 ]
  local plain; plain="$(strip_ansi <<<"$output")"
  [[ "$plain" == *"Would install: go "* ]]
  [[ "$plain" == *"Would install: golangci-lint"* ]]
  [[ "$plain" == *"Would install: air"* ]]
}

@test "--profile with two profiles unions and deduplicates" {
  run "$SETUP_SH" --dry-run --profile=go,rust --no-auth
  [ "$status" -eq 0 ]
  [ "$(would_install_count "$output")" -eq 4 ]
}

@test "--all resolves every tool" {
  run "$SETUP_SH" --dry-run --all --no-auth
  [ "$status" -eq 0 ]
  [ "$(would_install_count "$output")" -eq 27 ]
}

@test "--search resolves a single tool" {
  run "$SETUP_SH" --dry-run --search=postgres --no-auth
  [ "$status" -eq 0 ]
  [ "$(would_install_count "$output")" -eq 1 ]
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
  [ "$(would_install_count "$output")" -eq 11 ]
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

# --- ADR-0001: full-stack-web resolves, it does not restate -------------------

@test "--profile=full-stack-web resolves to fe + be + docker + chrome + node" {
  run "$SETUP_SH" --dry-run --profile=full-stack-web --no-auth
  [ "$status" -eq 0 ]
  [ "$(would_install_count "$output")" -eq 9 ]
  local plain; plain="$(strip_ansi <<<"$output")"
  for t in bun pnpm biome vite postgres-client redis-tools docker chrome node; do
    [[ "$plain" == *"Would install: $t "* ]]
  done
  # c-build was in the old literal and is in none of the composed Profiles.
  [[ "$plain" != *"Would install: c-build"* ]]
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
  [ "$(would_install_count "$output")" -eq 10 ]
  [[ "$(strip_ansi <<<"$output")" == *"Would install: eza"* ]]
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
