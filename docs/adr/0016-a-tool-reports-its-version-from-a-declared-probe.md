# A Tool reports its version from a declared probe

[ADR-0004](0004-install-step-is-the-unit-of-installation-work.md) made the Install Step the unit
that carries a result, and [ADR-0011](0011-the-lifecycle-is-a-plain-text-transition-stream.md) made
that result a transition with a free-text detail. This fills the detail in for the two terminal
states that are a claim about what is now on the machine: `done` and `already installed` report the
version of every Tool the Step delivered.

Until now the only place that reported a version was the trailing Verification block — a second
pass, after the run, re-probing a hand-written subset of the Toolset. It runs real commands under
`--dry-run` (#10) and spills escape sequences into the terminal and the log (#11). Eleven Tools had
no probe there at all, and the probes it did have were a third copy of ones already written inside
the installers' own skip-guards (`gh already installed: $(gh --version | head -n1)`).

## The probe is declared, per Tool, with a convention

`TOOL_VERSION` maps a Tool to the command that answers its version, exactly as `TOOL_PRESENT` maps
one to the command that answers whether it is there. A Tool absent from the table uses `<tool>
--version`, so the table holds only the Tools that disagree with the convention, and adding a Tool
needs no entry rather than needing one.

Declared rather than conventional throughout, because the convention is wrong for most of the
interesting Tools in three different ways: the binary is named something else (`pip3`, `rustc`,
`psql`), the flag is the tool's own (`go version`, `node -v`), or the binary is not on the run's
PATH at all. That last one is the reason a convention alone could never work here: `install_go`
lays Go down in `/usr/local/go/bin` and the shell that called it never picked that up, so the Tool
this run installed a minute ago cannot be reached by name until the next login shell.

The PATH case is the majority of the table, not an exception. Four Tools are `npm install -g`
under nvm, which puts a binary in a directory named after a Node version — `node` itself, and
`pnpm`, `biome` and `vite`, which the same nvm delivered. None is reachable without sourcing nvm,
so all four go through one `with_node` helper rather than four copies of the same incantation, and
none is left to the convention that would report `(unknown)` for a Tool the run had just installed.
Puppeteer's browser is the other shape of the same problem: it lives under a versioned directory in
a cache, so its probe globs, and takes the newest match rather than making the rest arguments to
the first.

Probing inside each installer instead was rejected. Twenty-two installers would each have to
report in the same shape, and the three that already print a version print it three different
ways; the shape would drift the first time one was edited. The table is also the only form in
which the *absence* of a probe is expressible — see below.

## The version is the word carrying the number

A probe answers whatever its author felt like: `gh version 2.63.2 (2024-12-05)`, `v22.11.0`,
`Docker version 24.0.7, build afdd53b`, `go version go1.23.4 linux/amd64`, and `eza`, which does
not mention a version until its second line. The reported version is the first whitespace-delimited
word holding a `<digits>.<digit>`, minus the punctuation around it.

The whole word, not the number inside it: `go1.23.4` and `v22.11.0` are how Go and Node name their
own versions, and trimming them to `1.23.4` and `22.11.0` would report something neither tool said.
Taking the first line instead was rejected because eza's first line is a sentence about eza, and
`head -n1` is exactly what the Verification block did with it.

A probe that answers with no version at all reports `(unknown)`. Falling back to the first line of
whatever it printed was rejected: text that is not a version, reported where a version goes, is the
fabrication this ADR exists to avoid, and it would arrive most often precisely when something is
wrong.

## A Tool with no version says so

Two Tools have no version to report. The Matt Pocock skills bundle is a count of files on disk, and
the Exa MCP entry is a registration in a config file rather than an executable. Both are declared
`none` and report `installed`, which is the whole of what is true about them.

Giving them something version-shaped anyway — the skill count, the MCP endpoint — was rejected.
A number in the version position is read as a version, and `pocock-skills · 48` invites exactly the
wrong conclusion. Leaving the detail empty was also rejected: a `done` cell with nothing after it
reads as a version that could not be found, which is a different fact, and one that has its own
answer already.

## A dry run reports without probing

`--dry-run` executes no probe and reports `(dry run)` per Tool. The dry run is a preview of the run
(ADR-0011) and it does run the *presence* probes — but a presence probe is one read-only command
this file declares, while a version probe is an arbitrary command line that may reach a container
(`docker exec qdrant`) or source a shell script (`nvm.sh`). #10 was open against the Verification
block for exactly this, and the replacement for it may not inherit the same fault.

Declared data needs no probe, so the two Tools with none still report `installed` in a dry run:
what the run would say is what the preview says, wherever the answer does not depend on the
machine.

## Consequences

The version rides out on the transition that was already being emitted, so it reaches the screen,
the log and a pipe by one route and there is no second account of it to disagree. The finalised
frame has room for it because ADR-0007 refused to cap that frame's height.

A Step delivering one Tool reports the version alone — the row is named for that Tool already — and
a Step delivering several labels each one: `pip 24.3.1 · eza v0.20.5`. The row cannot otherwise say
which number is whose, and many-to-one is the installer's shape (ADR-0004), not something the
report can flatten.

`settle_step` is where the two states are recognised, so a real run and a dry run cannot report the
same Step differently: neither driver decides, both merely say which state they reached. That is the
same argument `step_precondition` was written for — the dry run previews the run precisely because
there is one place either of them can answer from.

Probes run after the Step, in the run's own shell, with stdin closed so that one which reads rather
than answers cannot eat the input `gh auth login` waits for later. They cost one fork per Tool
delivered — including on an `already installed` Step, where reporting the version found is the whole
difference between a re-run and twenty suspiciously instant successes (ADR-0005, story 10 of #15).

The Verification block was a second version report, and a re-probe minutes later can legitimately
disagree with this one. #25 deleted it, and #10 (real commands under `--dry-run`) and #11 (raw
cursor escapes from `fastfetch`) closed with it: the fault was the second pass, not the probes it
happened to run, so the repair was removal. What a Step reports as it lands is the run's whole
account of a version — one report, by one route, to the screen, the log and a pipe alike.
