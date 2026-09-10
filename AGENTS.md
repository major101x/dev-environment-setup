# AGENTS.md

## Agent skills

### Issue tracker

GitHub Issues via `gh` CLI (major101x/dev-environment-setup). See `docs/agents/issue-tracker.md`.

### Triage labels

Canonical 5 labels as-is (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context (`CONTEXT.md` + `docs/adr/` at repo root). See `docs/agents/domain.md`.

## Who each document is for

Match the document to its reader before writing in it. These are different
audiences and they want opposite things.

- **`README.md` — a person who found this repo and wants a dev machine.** What
  it is, how to run it, what they can pick, what it will do to their machine
  without asking, what to do when something fails. No ADR citations, no issue
  numbers, no explanation of why the code is shaped the way it is. If a sentence
  only makes sense to someone maintaining the script, it belongs somewhere else.
- **`CONTEXT.md` and `docs/adr/` — whoever maintains this next.** The vocabulary,
  the decisions, and the alternatives that were rejected. This is where rationale
  lives, and it only needs to live here once.
- **Code comments — the next person to change that line.** The house rule that a
  non-obvious line names the issue or ADR that decided it applies *here* and in
  the domain docs above. It does not apply to the README.

The README drifted into maintainer prose once already, by each pass matching the
precedent it found in the file rather than the audience: twelve ADR citations and
a 500-word paragraph about `--dry-run`. Rationale written twice goes stale in one
of the two places.
