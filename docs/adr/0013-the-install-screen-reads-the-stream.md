# The install screen reads the transition stream, in a process of its own

The run has been emitting its lifecycle as a plain-text transition stream since ADR-0011, on the
grounds that "the run emits, the screen reads" — a screen that computes its own state can only be
tested by screenshotting it. ADR-0012 then took the terminal back from installer chatter so that
a screen could own it. This is the screen (#22), and the question it settles is *how* a bash
script draws a live frame over a run that is, for minutes at a time, inside an installer.

## Decision

**The screen is a reader on the other end of the stream.** `screen_start` forks a reader process
with the terminal as its stdout, and moves the run's fd 3 — the stream, and nothing but the
stream — onto a pipe to it. The run does not draw. The reader keeps a snapshot, repaints on every
transition and on a quarter-second timer for the spinner, and finalises when the run says
`[SCREEN] end`. Then the run waits for it, restores fd 3 to stdout, and only then prints the
summary beneath the frame and goes on to `gh auth login`.

Said, not inferred from EOF: an installer can leave a daemon behind holding the write end of the
pipe, and a reader waiting on EOF would then be waiting on that daemon.

**A frame is a pure function of a snapshot and a size** (#21, ADR-0007), and the reader calls the
same `render_frame` that `setup.sh __render` does. So the live path and the tested path share
everything but the source of the snapshot, and the one pty smoke test in `test/screen.bats` can
assert that a live run ends on exactly the frame the pure renderer draws for the same snapshot.

**It is up when stdout is a terminal, and only when the log is open.** A terminal means under
`--profile=go` on a laptop as much as after the picker; a pipe or CI gets the plain lines the
stream has always been, unchanged. The log condition is not incidental: while the screen owns the
terminal an Install Step's output has to have somewhere else to go, and the log is where
ADR-0012 sends it. A run whose log cannot be written already says so and carries on — now it
carries on as plain lines.

**While the screen is up, narration goes to the log alone.** `info`, `warn`, `error` and `step`
would tear the frame, so they are written to the log and not the terminal until the screen is
down. Inside an Install Step's section stdout *is* the log, and nothing changes there. Everything
said before the screen goes up — the plan, the stepless report, the base deps — and after it comes
down — the summary — reaches the terminal as before.

**Tails are read back off the log.** A failed Step's last three lines, and the last two lines of
the Step in flight, come from its section in the log, found by the section's own `[STEP OUTPUT]`
markers and not by where the reader happened to be when it noticed the Step start: a reader can
lag a Step that is over in a millisecond, and an offset taken then lands after the section. A dry
run has no sections, so it shows no tails.

**Live and finalised paints differ.** A live paint moves the cursor back to the first line of the
previous frame and rewrites every line, so the box stays where it is; the terminal size is asked
on every paint, so a resized terminal gets the next frame at its size. The finalised paint is
drawn the same way, then clears whatever is left below it, hands the cursor back and moves on to
a fresh line. The alternate screen buffer is never used, so the finalised frame is ordinary
scrollback (ADR-0007).

**The plan is resolved once, in `main`.** The reader is forked knowing every Install Step and its
label, so its first frame is the whole queue; the stream then only changes states. Resolution
moved out of `install_selected_tools` for that, and the stepless report moved with it — it is
said before the screen goes up, where a person can read it.

## Consequences

**A dependent Step is marked `skipped` lazily**, when its turn comes, which is what the runner has
done since ADR-0011 — ADR-0007 left the choice to this ticket and the frame is the same either
way. A cascade therefore appears on the screen one Step at a time rather than all at once when the
prerequisite fails.

**`install_base_deps` stays outside the screen.** ADR-0012 said it would join the sections when
the screen could show a failure itself. It does not yet: apt failing there kills the run, and a
screen that has to show that and then end the run is a change of its own. It runs before the
screen goes up, on the terminal, as it did.

**A terminal narrower than about 40 columns gets a frame that wraps.** The renderer clamps at 24
and the layout is clean from 40 down; below that the box is wider than the terminal.

**The reader is a second process reading the log while the run writes it.** Its reads are of a
bounded window and cost a fork or two per paint, four times a second. On a run that takes minutes
that is nothing; on a machine where it were not, the screen is the thing to turn off, and there is
no flag for that yet.

**The summary is printed twice, in two shapes.** The finalised frame carries its counts and failure
board inside the box, and `run_summary` prints its counts line and `Failed:` lines beneath it —
the same lines a piped run prints, so CI and a person read the same account. The duplication is
the price of one summary code path; the alternative was a second summary that only a terminal
ever saw.

## Considered and rejected

**Drawing from the run itself, after each transition.** Simpler, and it cannot animate: the run
is inside an installer for most of its life, and a spinner that only turns between Steps is a
spinner that reads as hung. The reader's timer is the whole reason it is a process.

**`exec 3> >(screen_reader)` instead of a named pipe.** Shorter, and `wait` on a process
substitution is unreliable across bash versions; the finalisation-before-stdin guarantee rests on
that `wait`.

**Sending the reader a snapshot over the pipe instead of the stream.** It would spare the reader
the log reads. It would also make the stream a second, richer protocol between two halves of one
script, when ADR-0011's point was that one stream feeds the pipe, the log, the tests and the
screen alike.

**A `--no-screen` flag.** Nothing asked for it yet; a pipe is the way to get plain lines, and it
is one `| cat` away.
