# The log is written per Install Step, not by a blanket redirect

`setup.sh` opened with `exec > >(tee -a "$LOG_FILE") 2>&1`: every byte the script produced went
to the terminal and to `setup.log`. One line, and it made the log free. It also made two problems
that no amount of care inside the script could fix.

**A subcommand's stdout went to the log instead of to its caller.** The script re-enters itself —
fzf runs `setup.sh __tui_list` for every render — and an inherited redirect sends that render to
`setup.log`. The picker comes up empty, with no error and nothing on stderr, because `tee` still
forwards to the original stdout so the call *looks* like it printed something. The guard was a
`case` at the top of the file that each new re-entrant subcommand had to remember to join; it has
been forgotten once already (ADR-0008, issue #13).

**Installer chatter owned the terminal.** The install screen (#15) has to own it instead. A screen
that repaints in place cannot share stdout with `apt-get`.

## Decision

There is no blanket redirect. The run writes the log itself:

- its own narration — `info`, `warn`, `error`, `step` — in plain text, with no escape sequences,
  whether or not the terminal is getting a coloured copy;
- every transition, the same line the stream carries (ADR-0011);
- each Install Step's output, stdout and stderr together, inside a section that names the Step:

```
[STEP OUTPUT] install_go | begin
…everything the installer said, and the phases it reported while saying it…
[STEP OUTPUT] install_go | end | exit 0
```

A Step's output goes to the log and *not* to the terminal — including this script's own `step`
and `info` lines from inside an installer, which are part of what the Step said. What the terminal
keeps of a Step is its transitions, which say the same thing in one line each. They go to both:
they are written to fd 3, the run's stdout held aside before any of this, so a phase a Step
reports about itself still reaches a reader watching the stream while stdout is the log.

Colour is dropped for the duration of a Step. The installer's own commands work that out for
themselves from stdout not being a terminal; `info` and `step` decided at startup, when it still
was one, so the Step is called with the colour variables emptied. Otherwise the log's only copy of
a narration line inside a section is the escaped one, and ADR-0011's "nothing should have to strip
escapes to read a field" would hold everywhere but the sections.

The log is opened by `main`, and nothing else. A re-entrant subcommand never reaches `main`, so it
cannot write to the log — or create it — however carelessly it is added. That is the `case`
statement's job done by structure rather than by memory, and `test/tui.bats` still asserts the
outcome the old guard was for: a callback writes nothing to the log.

Only a Step that runs gets a section. A `skipped` Step never runs, and an empty section would
claim it ran and said nothing.

## Consequences

**The terminal is quiet during a real install, before there is a screen to fill it.** Between this
and #22 a run shows the narration from outside its Install Steps, and the transition stream, and
nothing else — where it used to show every line an installer printed. That is the
interim state the ordering buys: the screen cannot be built over a terminal something else is
writing to.

**A failure's detail is in the log, not on the terminal.** The run still says which Step failed
and with what status, and the end-of-run summary still names it (ADR-0006); *why* it failed is in
that Step's section. The failure board of #22 is what closes this back up.

**Output that is not an Install Step's stays on the terminal, and leaves the log.** Two blocks are
affected. `install_base_deps` is deliberately not a section: it is not an Install Step, and apt
failing there kills the run, so capturing it would leave the person with a dead terminal and the
reason in a file. `verify_versions` is the trailing Verification block that #15 deletes outright —
giving it a section now would be work on something already condemned. Both were in the log under
the redirect and are not now; base deps joins the sections when the screen can show a failure
itself (#22), and verification goes away.

**A log that cannot be written no longer takes the run with it.** `tee` failing at startup killed
the run loudly; a `printf` failing at the end of `info` would kill it silently under `set -e`, and
an Install Step redirected into an unwritable path would report `failed` for a reason that has
nothing to do with the Step. So the log is opened once, up front, and a run that cannot open it
says so and carries on with the Step output going where it used to — the terminal.

**The log no longer holds the script's stderr in general.** `2>&1` used to sweep up everything,
including a bash error the script never saw coming. Inside an Install Step that is still true;
outside one, an unexpected message now goes to the terminal only.

## Considered and rejected

**A `tee` per Install Step, so the output goes to the terminal *and* the log.** It keeps the
interim run looking exactly as it does today, which is the one thing this ticket gives up. But it
keeps the terminal spoken for, which is what #22 needs it not to be, and it keeps a redirect
around subcommands, which is the trap this ADR exists to remove. Deferring the cost to the ticket
that cannot pay it is not deferring it.

**Buffering a Step's output to a temp file and appending the section when it ends.** Tidier
interleaving — the section could not be split by anything else writing to the log. Rejected
because a run killed mid-Step, which is exactly when someone wants the log, would have nothing in
it for the Step that was running. Appending as the Step speaks costs an interleaving that the
`[STEP OUTPUT]` delimiters already make legible.

**Keeping the redirect and having the install screen draw on `/dev/tty` instead.** The screen would
own a terminal the log never sees, and the log would become a transcript of a screen: repainted
frames, spinner ticks, escape sequences. ADR-0011 chose the opposite direction on purpose — the run
emits, the screen reads — and this is the same choice for output.
