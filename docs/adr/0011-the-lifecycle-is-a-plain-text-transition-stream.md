# The Install Step lifecycle is a plain-text transition stream

The install screen (#15) needs to know what every Install Step is doing. So do CI logs, the
tests, and anyone piping a run into a file. Rendering is the *last* thing that should decide
that: a screen that computes its own state has no way to be tested except by screenshotting it,
and a log that is a transcript of a screen is neither readable nor parseable.

So the run emits its state, and rendering reads it. One line per state change, on stdout:

```
[STEP] <install step> | <state>[ | <detail>]
```

The states are ADR-0005's seven — `queued`, `downloading`, `installing`, `done`, and the three
terminal states that carry what the happy path cannot: `already installed`, `skipped` (whose
detail names the unmet dependency) and `failed` (whose detail says why).

Fields are `|`-separated because two of the states contain a space, so whitespace cannot
delimit them. The state field holds one of exactly seven strings and nothing else; anything that
varies per run — a version, a dependency name, an exit status — is detail. ADR-0005 writes the
skip state as `skipped — unmet dependency`; that is one state with one reason today, and the
reason is detail rather than part of the state's name so that a second reason does not need a
new state to be added to the seven.

## Who emits what

The runner drives the machine: it announces every planned Step `queued` before the first one
runs, decides the terminal state, and emits it. An installer function reports only what the
runner cannot see from outside — `phase installing`, once its download has landed. Only the
three Steps ADR-0005 counts as having a separable download open in `downloading`; for the other
24 Tools the download is fused into apt or into `curl | bash`, and a `downloading` line there
would be a phase invented for symmetry.

Deciding the terminal state *before* the Step runs is what makes `already installed` and
`skipped` real rather than reconstructed: a table of read-only presence probes answers "is this
Step's work already on the machine", and a declared prerequisite that is neither present nor
delivered by an earlier Step in the plan answers "can this Step run at all".

## `--dry-run` drives the same machine

The dry run is the state machine against Install Steps that do nothing. It is not a second
description of a run: the same probes, the same dependency gate, the same emitter, with a sleep
where the installer's runtime would be. That is what makes it a preview rather than a guess, and
it is why the tests can assert the whole lifecycle through the process boundary with no installs,
no network and no root.

The one thing a dry run cannot find out is what would break, so `--simulate-fail=<step>` supplies
it. Without it `failed` — and the dependency skips that cascade from it — would be reachable only
on a machine where something is genuinely broken, which is to say untestable and undemonstrable.
It is refused outside `--dry-run`: it simulates a lifecycle, it does not break a real install.

It is also the one place the simulation shows something a run today would not do. A real run still
stops at its first failed Install Step, so the cascade of skips a failure causes cannot happen yet;
the simulation carries on past the injected failure, because a cascade nobody can see is a cascade
nobody can check. The dry run says so on the line above the stream, and ADR-0006 is where a real
run learns to continue (#18).

## Consequences

Colour is gone from a non-TTY run. A consumer of the stream would otherwise have to strip escape
sequences before it could read a field, and the log would carry them for nobody.

Capturing a Step's exit status means the call cannot sit under `set -e`, so it runs as
`set +e; ( set -e; "$step" ); set -e` — errexit still applies *inside* the Step, so it stops at
its own first failing command instead of running on and reporting whatever its last line
returned. A failure is now reported before it stops the run; ADR-0006's "mark failed and
continue" is #18.

An already-installed Step is still called. It is idempotent and skips its own work, and skipping
the call outright would drop the PATH and config lines several installers keep doing after the
binary exists. Its phases are muted, so the stream says `already installed` and not a
contradiction of it.
