#!/usr/bin/env bats
#
# The Owner: who the machine is being set up for (#70, ADR-0019). The script
# needs root and `require_root` refuses without it, but root is the privilege,
# not the actor -- a run produces someone's dev machine, and until this every
# `$HOME` in the file resolved to `/root`.
#
# The suite runs un-`sudo`ed, so what is asserted here is what a run *says* and
# *writes*, through the same `--dry-run` process boundary every other flag test
# uses. Whether `runuser` actually drops privilege is the one claim only a real
# root run can settle; see the Owner section of ADR-0019.

load helpers

setup() { sandbox; }
teardown() { sandbox_teardown; }

# The line a run prints naming who it is for.
owner_line() { strip_ansi <<<"$1" | sed -n 's/^\[INFO\] Installing for //p'; }

# The suite cannot execute `runuser`, so it is stubbed and its argv recorded.
# Recording the argv rather than a bare "it ran" marker is the whole point:
# `open_log` calls `as_owner` before any Install Step or auth step, so a test
# that only asked whether `runuser` ran at all would pass with the behaviour it
# names deleted outright.
record_runuser() { fake_tool runuser "printf '%s\n' \"\$*\" >>'$TEST_TMP/runuser-argv'"; }
ran_as_owner()   { grep -qE "$1" "$TEST_TMP/runuser-argv" 2>/dev/null; }

# --- who the Owner is ---------------------------------------------------------

@test "the run names the Owner it read from SUDO_USER" {
  # A name `getent` can resolve, since an unresolvable one is the fallback case
  # below. `daemon` exists on every Ubuntu and its home is not this user's.
  SUDO_USER=daemon run "$SETUP_SH" --dry-run --profile=go --no-auth </dev/null
  [ "$status" -eq 0 ]
  [[ "$(owner_line "$output")" == daemon* ]] ||
    { echo "expected the run to name daemon, got: $(owner_line "$output")" >&2; return 1; }
  [[ "$(strip_ansi <<<"$output")" != *"no invoking user detected"* ]] ||
    { echo "a resolvable SUDO_USER should not report a fallback" >&2; return 1; }
}

@test "no invoking user means root is the Owner, and the run says which" {
  run "$SETUP_SH" --dry-run --profile=go --no-auth </dev/null
  [ "$status" -eq 0 ]
  local said; said="$(strip_ansi <<<"$output")"
  [[ "$said" == *"no invoking user detected"* ]] ||
    { echo "the fallback to root was silent" >&2; return 1; }
}

# `sudo -u root` and a plain root login are the same situation as no SUDO_USER
# at all, and the vendor installer for `claude-code` draws exactly this line.
@test "SUDO_USER=root is the same as no invoking user" {
  SUDO_USER=root run "$SETUP_SH" --dry-run --profile=go --no-auth </dev/null
  [ "$status" -eq 0 ]
  [[ "$(strip_ansi <<<"$output")" == *"no invoking user detected"* ]]
}

# A name no `getent` can resolve has no home to install into. Falling back is
# the only safe answer -- writing to a guessed path would be worse than root's.
@test "an Owner with no resolvable home falls back to root" {
  SUDO_USER=nosuchuser-zz99 run "$SETUP_SH" --dry-run --profile=go --no-auth </dev/null
  [ "$status" -eq 0 ]
  [[ "$(strip_ansi <<<"$output")" == *"no invoking user detected"* ]]
}

# --- Reachability -------------------------------------------------------------

@test "a run writes the Reachability file" {
  local sh; sh="$(runnable)"
  run "$sh" --profile=go --no-auth
  [ "$status" -eq 0 ]
  [ -s "$REACHABILITY_FILE" ] ||
    { echo "no Reachability file at $REACHABILITY_FILE" >&2; return 1; }
}

# The whole point of ADR-0019's Reachability: a Tool on disk that the Owner's
# shell cannot find is installed but not usable, and repairing that must not
# depend on the Install Step having had work to do. `install_go`'s own early
# return jumped over the `PATH` append, so a machine that had Go could never
# acquire the line that made Go usable.
@test "the Reachability file is written even when every Step is already installed" {
  local sh; sh="$(runnable)"
  probe_forced go=true golangci-lint=true air=true >/dev/null
  run "$sh" --profile=go --no-auth
  [ "$status" -eq 0 ]
  [[ "$(strip_ansi <<<"$output")" == *"already installed"* ]]
  [ -s "$REACHABILITY_FILE" ] ||
    { echo "an already-installed run wrote no Reachability file" >&2; return 1; }
}

# Rewritten whole, not appended to under a `grep` guard -- that is what makes it
# idempotent by construction (ADR-0019).
@test "the Reachability file does not grow when a run repeats" {
  local sh; sh="$(runnable)"
  run "$sh" --profile=go --no-auth
  [ "$status" -eq 0 ]
  local first; first="$(wc -c <"$REACHABILITY_FILE")"
  run "$sh" --profile=go --no-auth
  [ "$status" -eq 0 ]
  [ "$(wc -c <"$REACHABILITY_FILE")" -eq "$first" ] ||
    { echo "the Reachability file grew on a second run" >&2; return 1; }
}

# It is sourced by each user's own login shell, so `$HOME` in it must survive
# unexpanded -- a path baked in at write time would name one person's home to
# everybody.
@test "the Reachability file leaves HOME for the reading shell to expand" {
  local sh; sh="$(runnable)"
  run "$sh" --profile=go --no-auth
  [ "$status" -eq 0 ]
  grep -q '\$HOME/go/bin' "$REACHABILITY_FILE" ||
    { echo "no unexpanded \$HOME in the Reachability file:" >&2
      cat "$REACHABILITY_FILE" >&2; return 1; }
}

# `air` is delivered by `install_go` into `$HOME/go/bin` and nothing ever wrote
# that directory to a shell rc -- not even root's. It was unreachable for
# everybody, which is why the reported run could report `air v1.67.4` from a
# path no shell would ever search.
# Which lines those are is declared in `write_reachability` and derived here, so
# the set is written down once and a line added there cannot pass unnoticed.
@test "the Reachability file carries every PATH line write_reachability declares" {
  local sh; sh="$(runnable)"
  run "$sh" --all --no-auth
  [ "$status" -eq 0 ]
  local line n=0
  while read -r line; do
    n=$((n + 1))
    grep -qF "$line" "$REACHABILITY_FILE" ||
      { echo "declared but not written: $line" >&2; return 1; }
  done < <(reachability_lines)
  [ "$n" -gt 0 ] || { echo "write_reachability declares no PATH line" >&2; return 1; }
  [ "$n" -eq "$(grep -c '^export PATH=' "$REACHABILITY_FILE")" ] ||
    { echo "the file carries PATH lines the function does not declare" >&2; return 1; }
}

# `claude-code`'s installer writes no shell rc line at all and never mentions
# PATH -- read off the live installer on 2026-09-09 and recorded in CONTEXT.md.
# Unlike bun, uv and rust it has nothing of its own to fall back on, so if its
# directory is not carried here the Tool is installed and permanently
# unreachable: exactly the condition #70 exists to end.
@test "the Reachability file covers the Tool whose installer writes no rc line" {
  local sh; sh="$(runnable)"
  run "$sh" --all --no-auth
  [ "$status" -eq 0 ]
  grep -q '\$HOME/.local/bin' "$REACHABILITY_FILE" ||
    { echo "claude-code installs to \$HOME/.local/bin and nothing puts it on PATH" >&2
      cat "$REACHABILITY_FILE" >&2; return 1; }
}

# --- running as the Owner -----------------------------------------------------

# The suite cannot drop privilege, so this asserts the call, not its effect:
# `runuser` is stubbed and witnessed. The Owner is spliced in rather than taken
# from `SUDO_USER`, because a real name would also have to resolve to a home.
@test "a command that does not need root is run as the Owner" {
  local sh; sh="$(runnable)"
  override "OWNER=ghost; RUNNING_USER=root"
  record_runuser
  run "$sh" --profile=go --no-auth
  [ "$status" -eq 0 ]
  # Persistence by name, not merely "something ran": the picks are the Owner's
  # and are written as them, and a file root wrote into their home is one they
  # cannot overwrite on their next run.
  ran_as_owner '^-u ghost -- tee .*config\.json$' ||
    { echo "the picks were not saved as the Owner; runuser saw:" >&2
      cat "$TEST_TMP/runuser-argv" >&2; return 1; }
}

@test "no runuser when the Owner is already the running user" {
  local sh; sh="$(runnable)"
  witness_tool runuser
  run "$sh" --profile=go --no-auth
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_TMP/ran-runuser" ] ||
    { echo "dropped privilege to the user it was already running as" >&2; return 1; }
}

# --- what a previous run left in root's home ----------------------------------

@test "a run says when a previous run installed into root's home" {
  local sh; sh="$(runnable)"
  override "ROOT_HOME='$TEST_TMP/roothome'"
  mkdir -p "$TEST_TMP/roothome/.nvm"
  run "$sh" --profile=go --no-auth
  [ "$status" -eq 0 ]
  [[ "$(strip_ansi <<<"$output")" == *"previous run installed into root's home"* ]] ||
    { echo "the leftovers under root's home were not reported" >&2; return 1; }
}

# --- the GitHub credential is the Owner's -------------------------------------

# It fired at the end of every run whatever the Toolset held, so a run that
# picked only Go ended by asking where you use GitHub (#70).
@test "a run that did not pick gh never reaches the auth step" {
  local sh; sh="$(runnable)"
  run "$sh" --profile=go
  [ "$status" -eq 0 ]
  [[ "$(strip_ansi <<<"$output")" == *"gh is not in the Toolset"* ]] ||
    { echo "the auth step was reached for a Toolset with no gh in it" >&2; return 1; }
}

@test "a run that picked gh still reaches the auth step" {
  local sh; sh="$(runnable)"
  fake_tool gh 'echo "not logged in"'
  run "$sh" --search=gh
  [ "$status" -eq 0 ]
  [[ "$(strip_ansi <<<"$output")" == *"gh auth login"* ]] ||
    { echo "picking gh did not reach the auth step" >&2; return 1; }
}

# `gh` resolves its config from $HOME, so under sudo the credential landed in
# root's and the person's own gh stayed logged out.
@test "the gh credential is written as the Owner" {
  local sh; sh="$(runnable)"
  override "OWNER=ghost; RUNNING_USER=root"
  fake_tool gh 'echo "not logged in"'
  record_runuser
  run "$sh" --search=gh
  [ "$status" -eq 0 ]
  # By name: `gh` resolves its config from $HOME, so the login itself has to be
  # the Owner's process or the credential lands in root's home again.
  ran_as_owner '^-u ghost -- gh auth login$' ||
    { echo "gh auth login did not run as the Owner; runuser saw:" >&2
      cat "$TEST_TMP/runuser-argv" >&2; return 1; }
}
