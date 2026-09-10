#!/usr/bin/env bats
#
# The README is for a person who found this repo and wants a dev machine; the
# rationale for how the script is built lives in CONTEXT.md and docs/adr/ and
# only needs to live there once. AGENTS.md says so under "Who each document is
# for".
#
# It is asserted rather than merely written down because it drifted once
# already, one edit at a time: twelve ADR citations and a 500-word paragraph
# about `--dry-run` accumulated across roughly fifteen commits, each pass
# matching the precedent it found in the file rather than the audience. A
# convention nobody enforces comes back the same way it left.

load helpers

README="$SETUP_ROOT/README.md"

@test "the README cites no individual ADR" {
  local hits
  # `docs/adr/` on its own is the pointer at the bottom and is meant to be
  # there. What is banned is naming a *particular* decision at a reader who
  # came here to install something -- `ADR-0011`, or a link to one ADR's file.
  hits="$(grep -nE 'ADR-[0-9]{4}|docs/adr/[0-9]{4}-' "$README" || true)"
  [ -z "$hits" ] || {
    echo "The README cites individual ADRs:" >&2
    echo "$hits" >&2
    echo "Rationale belongs in CONTEXT.md and docs/adr/ - see AGENTS.md," >&2
    echo "\"Who each document is for\"." >&2
    return 1
  }
}

@test "the README carries no issue numbers" {
  local hits
  # `(#72)` reads as a footnote to someone maintaining this and as noise to
  # everybody else. The issue is not the reason a person cares that picking
  # docker grants a root-equivalent group.
  hits="$(grep -nE '\(#[0-9]+\)|\bsince #[0-9]+' "$README" || true)"
  [ -z "$hits" ] || {
    echo "The README refers to issue numbers:" >&2
    echo "$hits" >&2
    return 1
  }
}

# The rationale is not deleted, it is relocated -- so the README has to say
# where it went, or the next person to want it will put it back inline.
@test "the README points at where the rationale lives" {
  grep -q 'CONTEXT\.md' "$README" ||
    { echo "the README never mentions CONTEXT.md" >&2; return 1; }
  grep -q 'docs/adr' "$README" ||
    { echo "the README never points at docs/adr/" >&2; return 1; }
}
