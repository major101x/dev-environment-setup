# The fzf callbacks are the test seam

The picker cannot be tested end to end. fzf reads `/dev/tty` directly, so no piped stdin drives
it and no assertion can be made about what it draws. A harness that insisted on testing the TUI
as a user sees it would test nothing at all.

But the TUI is not one process. fzf re-enters `setup.sh` for every render — `__tui_list`,
`__tui_header`, `__tui_preview`, `__tui_tab`, `__tui_click` — and each of those is an ordinary
command with ordinary stdout. **That re-entry is the seam**, and `test/tui.bats` drives it
directly.

It is also where the failures are. Both bugs found by hand during #6 live in the callbacks and
produce no error message at all:

- **The log redirect.** `setup.sh` does `exec > >(tee -a "$LOG_FILE")`. A callback that does not
  skip it sends its render to `setup.log`, and the picker comes up empty. `tee` also forwards to
  the original stdout, so "the callback printed something" is *not* the assertion that catches
  this — "the callback wrote nothing to the log" is. (The redirect itself is gone as of
  [ADR-0012](0012-the-log-is-written-per-install-step.md): only a run opens the log now, so a
  callback cannot inherit it. The assertion stays, because it is what says so.)
- **`set -e` on arithmetic.** A bare `(( ))` that evaluates false is a failed command, and aborts
  the callback mid-render. The output is truncated, not absent, so the assertion that catches it
  is that a render reaches its closing border.

Every assertion in the harness was checked against a mutated copy of `setup.sh` that reintroduces
the bug it guards. An assertion that stays green against the bug it names is decoration.

## Considered and rejected

**A pty wrapper (`script -qec`) driving fzf.** It would get a little further — far enough to see
that *a* frame was drawn — but it cannot assert on the frame's content without reimplementing a
terminal emulator, and it makes the suite timing-dependent. The issue that asked for this harness
(#13) named it as optional for the same reason. Still available if the callbacks stop being
enough.

**Extracting the registry and the render functions into a sourceable library.** A cleaner seam in
the abstract, and it would let tests call the functions in-process rather than paying a fork per
assertion. Rejected for now: the re-entrant callbacks are what fzf actually runs in production, so
testing them as subprocesses tests the real path, redirect and all — which is precisely the bug
class at issue.
