# An Install Step may deliver no Tool, and base dependencies is the first

Every Install Step until now delivered at least one Tool, and most of the machinery took that for
granted: a Step is labelled by the Tools it delivers, gated by their presence probes, reported in
the Summary with the Tools it owed, and reached at all only because a selected Tool maps to it.

`install_base_deps` fits none of that. It installs `ca-certificates`, `curl`, `wget`, `gnupg`,
`build-essential` and the rest that the other Steps reach for, and it delivers nothing anybody
picked. So it sat outside the whole model: called directly from `main`, before `screen_start`,
writing apt's account of every source on the machine straight to the terminal.

ADR-0012 said it would join the log sections "when the screen could show a failure itself".
ADR-0013 deferred that, naming the blocker in its own Consequences: *apt failing there kills the
run, and a screen that has to show that and then end the run is a change of its own.* #68 is that
change, and this is what it decided.

## Decision

**An Install Step delivers zero or more Tools.** The glossary said "one or more"; it now says zero
or more, and `install_base_deps` is the only Step that delivers none. It is planned like any other
Step, runs inside the install screen, reports `downloading` while `apt-get update` fetches and
`installing` while `apt-get install` unpacks, and its output goes to a `[STEP OUTPUT]` section
like every other Step's.

**It is not a Tool.** A Tool is what appears in the picker and in a Profile, and base dependencies
is not something a person can decline — a Toolset without it installs nothing at all. Making it a
Tool would have put an unticking-able row in the picker, or else required a Tool the picker never
shows, which is a worse lie than the one being fixed.

**Its label is declared, not derived.** Every other row is labelled by the Tools it delivers,
comma-joined, which is the honest answer whenever there is one. A Step that delivers none carries
a `STEP_LABEL` instead — `base dependencies` — and `step_label` is the one place that chooses
between the two, so the plan, the screen and the Summary cannot disagree about what to call the
same row.

**Its failure is everything else's unmet dependency.** Not a new lifecycle state: the seven states
are closed, `read_snapshot` refuses anything outside them and `test/render.bats` asserts the
refusal, so a fatal state would have opened a vocabulary that was deliberately shut and dragged
every fixture and golden through with it. Instead the Steps after it settle `skipped | unmet
dependency: base dependencies`, which the renderer already draws and ADR-0011's stream already
carries. The run still exits non-zero, and it still reaches a Summary — which the old abort did
not: base dependencies ran at the top level under `set -euo pipefail` with no trap, so apt failing
killed the run where it stood, with no counts and nothing said about what was owed.

**Said as a rule, not as a prerequisite edge.** `STEP_REQUIRES` relates a Step to the *Tools* it
needs, and base dependencies delivers none, so no edge can express it. It is one line in
`step_precondition` instead, below the already-installed check like every other prerequisite —
ADR-0005 asks `already installed` first, so a Step with nothing left to do is not skipped for want
of one, and base dependencies failing does not retroactively uninstall anything.

## Consequences

**No run is ever entirely `already installed` any more.** Base dependencies has no Tools, so no
presence probe can answer for it and it refreshes the apt cache on every run. That is the point of
it — a cache is stale whether or not the Tools are there — but it does mean a re-run against a
fully provisioned machine now reports one `done` among the `already installed` rows.

**The registry's Step count and the plan's differ by one.** The registry maps Tools to Steps and
cannot name this one. `test/cli.bats` says both numbers and the relation between them rather than
absorbing one into the other, so neither can drift into the other.

**`registry_install_steps` reads `BASE_DEPS_STEP` as well as the registry.** It is what `runnable`
stubs, and base dependencies left off that list is `apt-get update` running for real on the machine
under test — which is the exact accident the blanket stub exists to prevent. The floor check caught
it the first time, which is the only reason it is written down here rather than discovered later.

**`--simulate-fail` accepts it.** It is the one Step whose failure is worth rehearsing, since it
skips every Step after it, and the registry cannot name it for the validation to find.

## Considered and rejected

**A `base` Tool in the registry.** Everything would have worked unmodified — resolution, ordering,
the label, the cascade through `STEP_REQUIRES`, the counter's noun. And the picker would have shown
a row a person could untick, which is precisely what base dependencies is not. Hiding it means a
Tool that never appears in the picker, and the glossary's definition of Tool is that it does.

**A fatal lifecycle state.** Honest about what a base-dependency failure means, and it costs the
closed state vocabulary, the refusal `read_snapshot` is tested on, and a new terminal outcome in
every counter and Summary. The cascade says the same thing with states that already exist.

**Leaving it outside the registry with a hand-seeded row.** No glossary change, and the cascade
logic would have belonged to nothing — a special case in the runner for a thing the model had no
word for. Widening "one or more" to "zero or more" is one word, and it describes what was already
true.

**Silencing it instead — `apt-get update -qq` before the screen.** It would have got the same
screenshot for a fraction of the work. It also buys silence by throwing the signal away: the fetch
takes ten seconds or more against a machine with many sources, and under this you would watch a
bare terminal for all of it.
