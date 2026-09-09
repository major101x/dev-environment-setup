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

# The same, without base dependencies -- which leads every plan and delivers no
# Tool (#68). An assertion about how many Tools collapse into how many Install
# Steps is about the registry's mapping (ADR-0004), and base dependencies is not
# in it. The plan's full shape is asserted in `test/lifecycle.bats`.
tool_steps() { install_steps "$1" | grep -v '^install_base_deps '; }
tool_step_count() { tool_steps "$1" | grep -c . || true; }

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

@test "--list-tools exits 0 and lists every tool in the registry" {
  run "$SETUP_SH" --list-tools
  [ "$status" -eq 0 ]
  [ "$(grep -c '^  [a-z]' <<<"$output")" -eq "$(registry_tool_count)" ]
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
  [ "$(tool_step_count "$output")" -eq 9 ]
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
  [ "$(tool_step_count "$output")" -eq 1 ]
  [ "$(step_label "$output" install_go)" = "go, golangci-lint, air" ]
}

@test "--profile with two profiles unions and deduplicates" {
  run "$SETUP_SH" --dry-run --profile=go,rust --no-auth
  [ "$status" -eq 0 ]
  [ "$(toolset_count "$output")" -eq 4 ]
  [ "$(tool_step_count "$output")" -eq 2 ]
}

# The one place in the suite that writes the registry's size down, on the one
# line below. Everything else asks `registry_tool_count` or `planned_step_count`
# instead, so a Tool joining the registry fails here and nowhere else, and
# costs a single edit (#58). The numbers are not decoration: a registry that
# changes size without anyone noticing is exactly what they are here to catch.
@test "--all resolves the whole registry" {
  local tools=29 steps=25
  run "$SETUP_SH" --dry-run --all --no-auth
  [ "$status" -eq 0 ]
  [ "$(toolset_count "$output")" -eq "$tools" ]
  # The Toolset, less the four Tools that share a step with an earlier one
  # (`puppeteer`, `eza`, `golangci-lint`, `air`). Nothing is subtracted for
  # having no step any more: `claude-code` was the last such Tool and #53 gave
  # it an installer.
  [ "$(tool_step_count "$output")" -eq "$steps" ]
  # The registry's Steps and the plan's differ by one since #68: base
  # dependencies is an Install Step the registry cannot name, because it
  # delivers no Tool. Said here rather than absorbed into `steps`, so the two
  # numbers stay distinguishable and neither can drift into the other.
  [ "$(install_step_count "$output")" -eq "$((steps + 1))" ]
  [ "$(planned_step_count)" -eq "$((steps + 1))" ]
  # `registry_tool_count` reads the registry's declaration rather than a run, so
  # this is the one place it meets a run and the two are made to agree; every
  # other site takes it on trust. `planned_step_count` needs no such line --
  # it *is* this run, counted the way `install_step_count` counts it.
  [ "$(registry_tool_count)" -eq "$tools" ]
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
  [ "$(tool_step_count "$output")" -eq 1 ]
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

# --- the toolchain key is gone from what a run saves --------------------------
#
# #56: the picker asked whether to include toolchain PATH setup, `save_config`
# wrote the answer as `toolchain`, `--replay` read it back into
# `INCLUDE_TOOLCHAIN` -- and the one place that variable was read printed a line.
# The installers appended to `~/.bashrc` whatever the answer had been, so
# answering `n` declined nothing. The Decision "LTS everywhere" in `CONTEXT.md`
# records why it was deleted rather than wired up.
#
# Named for the one key, not for a general rule about the round trip: this is a
# grep for `toolchain`, and `save_config` legitimately writes `updated`, which
# nothing reads back either. That one is provenance for a person reading the
# file; `toolchain` was state the run pretended to act on.
@test "a saved config carries no toolchain key" {
  local sh; sh="$(runnable)"
  probe_forced eza=false >/dev/null
  run "$sh" --search=eza --no-auth
  [ "$status" -eq 0 ]
  local cfg="$XDG_CONFIG_HOME/dev-setup/config.json"
  [ -s "$cfg" ]
  ! grep -q '"toolchain"' "$cfg" ||
    { echo "config.json still carries a toolchain key" >&2; return 1; }
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

# --- base dependencies says when it stops fetching ----------------------------
#
# `STEP_DOWNLOADS` opens the Step in `downloading`; what moves it to `installing`
# is the Step calling `phase` itself, once its bytes have landed (ADR-0011). For
# base dependencies that boundary is between `apt-get update` and
# `apt-get install`, and telling those two apart is most of why #68 put it on the
# screen at all.
#
# Static, because the behavioural route cannot reach it: `simulate_install_step`
# emits `downloading` then `installing` off the `STEP_DOWNLOADS` entry alone, so
# the dry-run assertion in `test/lifecycle.bats` passes on the map entry whether
# or not the body calls `phase` -- and a real run blanket-stubs every Step body
# through `runnable`, deliberately, so no real run executes this one either. The
# order is the assertion, not the presence: a `phase installing` above the update
# would report the fetch as an unpack.
@test "base dependencies reports the phase between its fetch and its unpack" {
  local body u p i
  body="$(sed -n '/^install_base_deps() {/,/^}/p' "$SETUP_SH" | grep -v '^[[:space:]]*#')"
  [ -n "$body" ] || { echo "no install_base_deps body found" >&2; return 1; }
  u="$(grep -n 'apt-get update'  <<<"$body" | head -n1 | cut -d: -f1)"
  p="$(grep -n 'phase installing' <<<"$body" | head -n1 | cut -d: -f1)"
  i="$(grep -n 'apt-get install' <<<"$body" | head -n1 | cut -d: -f1)"
  [ -n "$u" ] && [ -n "$p" ] && [ -n "$i" ] ||
    { echo "install_base_deps: update=$u phase=$p install=$i" >&2; return 1; }
  (( u < p && p < i )) ||
    { echo "install_base_deps reports its phase out of order: $u $p $i" >&2; return 1; }
}

# --- an Install Step's apt source is written, not appended --------------------
#
# #62 asks that a vendor's repository end up configured once: "a second run
# leaves exactly one source file per vendor". A Step that appended its source
# line would satisfy that on the run that wrote it and break it on every run
# after, and the break is silent -- apt warns about the duplicate and carries
# on, so nothing fails until someone reads the warnings.
#
# Nothing executes an installer body here (that is the blanket stub in
# `runnable`, and deliberate), so this is the same trade the no-tty rule makes:
# a static assertion over the Step bodies instead of a run. Scoped to them for
# the same reason, and blunt for the same one -- it is a grep, so it asks only
# that the redirect into `sources.list.d` is `>`.
@test "no install step appends to an apt source list" {
  local fn body
  while read -r fn; do
    body="$(sed -n "/^$fn() {/,/^}/p" "$SETUP_SH" | grep -v '^[[:space:]]*#')"
    [ -n "$body" ] || { echo "no body found for install step: $fn" >&2; return 1; }
    ! grep -q '>>[[:space:]]*/etc/apt/sources\.list\.d/' <<<"$body" ||
      { echo "$fn appends to an apt source list" >&2; return 1; }
  done < <(registry_install_steps)
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
  local heads; heads="$(tool_steps "$output" | sed 's/^[^ ]* -> //; s/,.*//')"
  # ...appears in that same relative order in the registry listing.
  local registry; registry="$(list_keys)"
  [ "$(grep -c . <<<"$registry")" -eq "$(registry_tool_count)" ]
  [ "$(grep -Fxf <(echo "$heads") <(echo "$registry"))" = "$heads" ]
}

@test "one profile plans one exact sequence of install steps" {
  run "$SETUP_SH" --dry-run --profile=full-stack-web --no-auth
  [ "$status" -eq 0 ]
  [ "$(tool_steps "$output")" = "$(cat <<'EOF'
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
  local toolset; toolset="$(toolset_line "$output")"
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

# --- an Install Step never reads the terminal ---------------------------------
#
# Under ADR-0013 the install screen owns the terminal for the whole of a run, so
# an installer that reads the tty does not prompt -- it blocks forever, while
# the screen repaints over whatever it tried to ask. The rule is recorded in the
# glossary; this is what makes it fail rather than merely be stated.
#
# Scoped to Install Step bodies, because the one terminal read this script does
# make is legal and outside them: `github_auth`, which runs after the last Step
# and after the screen has been taken down. There was a second until #56 -- the
# picker's toolchain prompt, before any Step -- and the test below now holds the
# file to that count.
#
# Blunt on purpose. A `read` fed by a pipe or a file is not a terminal read, but
# telling those apart is a bash parser's job and this is a grep; a Step that has
# to consume a stream can use `mapfile` or a command substitution, and none has
# needed even that. Whole-line comments are stripped first, so a Step may say
# the word in one of those -- but not in a trailing comment, which this does not
# strip and which would fail here. Moving such a comment onto its own line is
# the fix; parsing bash to tell a `#` in a comment from a `#` in a string is
# not something a guard against a hang should be doing.
#
# `select` is matched alongside `read` because it is the other builtin that
# blocks on stdin, and it prompts, which is exactly the hang this is here for.
#
# What it does not reach: a Step's *body* is the whole of what it reads, so a
# terminal read inside a helper the Step calls would pass. Nothing is missed
# today -- the functions of this script an Install Step calls are `phase`, the
# four narration helpers (`step`, `info`, `warn`, `error`) and, since #62,
# `apt_vendor_keyring`, none of which reads anything -- and closing it properly
# means following calls, which is again a parser's job. A helper that grows a
# prompt is the gap to remember, and #62 widened it by one helper.
@test "no install step reads the terminal" {
  local fn body
  while read -r fn; do
    body="$(sed -n "/^$fn() {/,/^}/p" "$SETUP_SH" | grep -v '^[[:space:]]*#')"
    [ -n "$body" ] || { echo "no body found for install step: $fn" >&2; return 1; }
    [[ "$body" != *"/dev/tty"* ]] || { echo "$fn reads /dev/tty" >&2; return 1; }
    ! grep -qE '(^|[[:space:]&|;(])(read|select)([[:space:]]|$)' <<<"$body" ||
      { echo "$fn reads stdin" >&2; return 1; }
  done < <(registry_install_steps)
}

# --- and the whole script prompts exactly once --------------------------------
#
# The rule above is scoped to Install Step bodies because it is a blunt grep and
# `read` has honest uses -- `IFS=, read -ra` off a here-string in `parse_args`,
# `while read -r` over a pipe in half the renderers. This is the same rule at
# the scale of the file, made checkable by narrowing the pattern instead of the
# scope: a `read` carrying `-p` is a *prompt*, which is the one form that only
# makes sense against a person, and `select` is the other builtin that blocks
# while prompting.
#
# There was one such read too many. #56 found the picker asking whether to
# include toolchain PATH setup and nothing acting on the answer, so the run
# stopped for a question it then ignored. With it gone, `github_auth` is the
# only place this script waits on a person -- deliberately the last thing a run
# does, after the install screen is down (ADR-0013).
#
# `stty size </dev/tty` in the renderer is not caught and should not be: it asks
# the terminal its size and blocks on nobody. A Step may not touch /dev/tty at
# all, which is why the rule above is the stricter of the two.
#
# The flag cluster is spelled out as `(-flags )*-...p` rather than as the `-rp`
# this script happens to write, because `read -r -p`, `read -s -r -p` and
# `read -rn1 -p` are the same prompt spelled apart, and a pattern that only caught
# the joined form would let the next one through. Digits are allowed in the
# cluster for `-rn1` and `-N1`. Each spelling was run past it, and a `read -r -p`
# spliced into `interactive_picker` was watched to fail here.
@test "the only prompt in the whole script is github_auth's" {
  local lo hi n
  lo="$(grep -n '^github_auth() {' "$SETUP_SH" | cut -d: -f1)"
  hi="$(awk -v s="$lo" 'NR > s && /^}/ { print NR; exit }' "$SETUP_SH")"
  [ -n "$lo" ] && [ -n "$hi" ] || { echo "no github_auth body found" >&2; return 1; }
  while read -r n; do
    (( n > lo && n < hi )) ||
      { echo "setup.sh:$n prompts outside github_auth: $(sed -n "${n}p" "$SETUP_SH")" >&2; return 1; }
  done < <(grep -nE '^[[:space:]]*[^#]*(\bread[[:space:]]+(-[a-zA-Z0-9]+[[:space:]]+)*-[a-zA-Z0-9]*p\b|\bselect[[:space:]])' "$SETUP_SH" | cut -d: -f1)
}

# `claude-code` was in the `ai-agents` Profile with no installer, which is the
# Profile quietly delivering less than it lists. #53 gave it one, so the Profile
# now delivers every Tool it names -- one step per Tool, none of them shared.
#
# #59 then made it name agents and nothing else. The Profile is curated by a
# rule now, written down in the glossary: an interface you talk to that
# responds. A package manager, a notebook server, a model runner, a vector
# database and an MCP registration were riding along under a name that
# predicted none of them.
@test "--profile=ai-agents resolves to the agent CLIs and nothing else" {
  run "$SETUP_SH" --dry-run --profile=ai-agents --no-auth
  [ "$status" -eq 0 ]
  [[ "$(strip_ansi <<<"$output")" != *"No Install Step for tool:"* ]]
  # The whole list, not a count: "and nothing else" is the claim, and a count
  # would be satisfied by any two Tools. No `probe_forced` is needed to make it
  # hold, which is itself a consequence -- `jupyter` and `qdrant` took the only
  # unmet prerequisites in the Profile with them, so resolution has nothing to
  # add (ADR-0014) and the Toolset is the literal list.
  [ "$(toolset_line "$output")" = "opencode claude-code" ]
  [ "$(tool_step_count "$output")" -eq 2 ]
  [ "$(step_label "$output" install_opencode)" = "opencode" ]
  [ "$(step_label "$output" install_claude_code)" = "claude-code" ]
}

# Narrowing a Profile removes a default, not a capability. Every Tool that left
# is still one checkbox away by name and still in the Category it was in, and
# the three of them `python-ai` holds are still in it. The other two are not
# picked up by any Profile now -- `exa-mcp` stays in `default`, `qdrant` is in
# none -- so by name is the whole of how they are reached, which is why each is
# resolved on its own below rather than left to a Profile to prove.
@test "the tools that left ai-agents stay selectable, categorised and in python-ai" {
  local t
  run "$SETUP_SH" --list-tools
  [ "$status" -eq 0 ]
  for t in uv jupyter ollama qdrant exa-mcp; do
    grep -qE "^  $t +AI/ML +" <<<"$output" ||
      { echo "left ai-agents and left the registry: $t" >&2; return 1; }
  done

  # Selectable by name is the claim, so each is resolved on its own. Their
  # prerequisites are forced present because an addition would answer a
  # different question -- whether resolution still works, not whether the Tool
  # is still there to resolve.
  local sh; sh="$(probe_forced pip=true docker=true opencode=true)"
  for t in uv jupyter ollama qdrant exa-mcp; do
    run "$sh" --dry-run --search="$t" --no-auth
    [ "$status" -eq 0 ]
    [ "$(toolset_line "$output")" = "$t" ]
  done

  run "$sh" --dry-run --profile=python-ai --no-auth
  [ "$status" -eq 0 ]
  [ "$(toolset_line "$output")" = "uv jupyter ollama" ]
}

# The report that stopped the drop being silent outlives the Tool that motivated
# it. No Tool in the registry is stepless now, so the state is reached the only
# honest way left: a Tool spliced into a Profile with nothing to install it --
# which is exactly the mistake this guards against being made again.
@test "a tool with no install step is reported, not silently dropped" {
  override 'TOOL_CATEGORY[widget]="AI/ML"; TOOL_DESC[widget]="Widget"; ORDERED_TOOLS+=(widget); PROFILE_TOOLS[ai-agents]+=" widget"'
  run "$(script_copy)" --dry-run --profile=ai-agents --no-auth
  [ "$status" -eq 0 ]
  local plain; plain="$(strip_ansi <<<"$output")"
  [[ "$plain" == *"No Install Step for tool: widget"* ]]
  [ "$(toolset_count "$output")" -eq 3 ]
  [ "$(tool_step_count "$output")" -eq 2 ]
  [[ "$(install_steps "$output")" != *"widget"* ]]
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

# --- no Install Step writes a shell rc ----------------------------------------
#
# #70: Reachability is written centrally, to one file rewritten whole every run,
# because a Tool on disk the Owner's shell cannot find is installed and unusable
# and repairing that must not depend on the Step having had work to do. Two
# Steps used to append to `~/.bashrc` themselves, under a `grep -q` guard, and
# `install_go`'s own early return jumped straight over its append.
@test "no install step writes to a shell rc" {
  no_step_body_line_matches '>>.*(\.bashrc|\.bash_profile|\.zshrc|\.profile)' \
    "Reachability belongs in the file write_reachability owns (#70)."
}

# `~` is the older, sloppier spelling and it used to mean root's home. `$HOME`
# is the Owner's now and is the one spelling, so a tilde in a Step body is a
# line written before the Owner existed (#70, ADR-0019).
@test "no install step reaches a home directory through a bare tilde" {
  no_step_body_line_matches '~/' \
    "\$HOME is the Owner's and is the one spelling for it (#70)."
}

# A vendor installer piped into a shell writes wherever its own `$HOME` says, so
# it has to be the Owner's shell running it. This asserts the Step reaches for
# `owner_script` at all, not that one particular line sits inside it -- the
# realistic regression is a new Tool whose Step never thought about the Owner,
# and `install_go` legitimately pipes one installer to root (`-b /usr/local/bin`)
# alongside the one it runs as the Owner.
@test "an install step that pipes a downloaded installer into a shell runs one as the Owner" {
  local step body
  while read -r step; do
    body="$(step_body "$step")" || return 1
    grep -qE '^[^#]*curl[^|]*\|[[:space:]]*(bash|sh)\b' <<<"$body" || continue
    # A Step whose installer is genuinely root's says so in its own body, and
    # says why. `install_ollama` is the one: a system service, no home involved.
    grep -q '# owner: none' <<<"$body" && continue
    grep -q 'owner_script' <<<"$body" ||
      { echo "$step pipes an installer into a shell and never runs anything as the Owner" >&2
        return 1; }
  done < <(registry_install_steps)
}
