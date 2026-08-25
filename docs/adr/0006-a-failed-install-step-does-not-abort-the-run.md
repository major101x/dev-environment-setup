# A failed Install Step does not abort the run

Installs are sequential, so a failure at step 7 of 20 previously left 13 Tools unattempted. A
dev-environment installer is a batch job: one broken apt repository or a rate-limited download
should not cost the user the other nineteen tools they asked for.

A failed Install Step is therefore **marked failed, and the run continues**. The final screen
state and the end-of-run summary carry the failures.

This is only safe *because* the screen exists. Continuing past errors in a script that streams
output means failures scroll past unnoticed; a screen that holds every row's terminal state until
the end makes them impossible to miss.

## Considered and rejected

**Abort on first failure** — the previous behaviour. Safer in a build pipeline, wrong for an
installer whose steps are independent.

**Prompt the user to retry / skip / abort.** Rejected because it breaks unattended and CI use,
which `--yes`, `--profile=` and `--no-auth` exist to serve.

## Consequences

The script's exit status must reflect partial failure — a run with failed steps cannot exit 0, or
CI will treat a half-installed machine as success.
