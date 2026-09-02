# Resolution adds a missing prerequisite to the Toolset

Some Install Steps cannot do anything until another Tool is on the machine: `install_pocock_skills`
shells out to npx, `install_qdrant` to docker, `install_jupyter` to pip, `install_exa_mcp` to the
opencode binary. Nothing stopped a user selecting a dependent without its prerequisite, so
`--search=jupyter` reliably installed nothing useful — it planned one Install Step and skipped it,
correctly and uselessly, for want of pip.

The prerequisites are **declared data** (`STEP_REQUIRES`, keyed by Install Step because that is the
unit that runs — ADR-0004), and **resolution closes the Toolset over them**. A Tool whose
prerequisite is neither picked nor already on the machine gets that prerequisite added, and each
addition is announced on its own line naming the pick that pulled it in: a Tool the user did not
ask for must never appear without an explanation.

Resolution is the single place both the picker's ENTER and every non-interactive flag arrive at, so
interactive and non-interactive runs cannot resolve the same selection differently.

## Missing is the whole of it

A prerequisite already on the machine is **not** added. The run would not have skipped anything for
it, and adding it would drag its Install Step — and every other Tool that Step delivers — into a
Toolset nobody asked for: adding `pip` also delivers `eza`. So the rule is exactly complementary to
the gate that reads the same table at run time — resolution adds a prerequisite precisely when the
run would otherwise have skipped its dependent for want of it.

The cost is that the plan depends on the machine. That is already true of `already installed`
(ADR-0005), and the tests force the presence probes for the same reason they always did.

## Considered and rejected

**Add every declared prerequisite regardless of presence.** Machine-independent and simpler to
reason about, but it installs Tools nobody asked for on the common re-run, where the prerequisite is
already there.

**Encode prerequisites as installer ordering only** — the previous state. Ordering cannot say *why*
a Step was skipped, and a table that only exists as an order is one nothing can read.

**Leave it to the run-time gate.** The gate is still there and still right; it just answers a
question the user could not act on until after the run. Being told at the end that jupyter was
skipped is not the same as getting jupyter.

## Consequences

`skipped — unmet dependency` narrows to what it was always for: a prerequisite that was planned and
did not land, so a failure still cascades into skips rather than into several unexplained failures.
A prerequisite nothing can deliver — a Tool with no Install Step — reaches the same state, which is
the only remaining skip that is not downstream of a failure.

A declaration that cannot be resolved is rejected by name before anything is planned, whatever this
run selected — a run that picked around one would install happily and leave the next one to find it.
There are two such declarations. A **cycle**, including a self-reference, has no order to close
towards. And a prerequisite the registry orders **after** the Tool that needs it would be added to
the Toolset and then delivered too late to meet anything, leaving the dependent skipped for a reason
the declaration had already answered; plan order is the registry's (ADR-0004) and a Step lands at
the first selected Tool that pulls it in, so the bar is the earliest Tool the declaring Step
delivers.

That second check is what keeps the declaration from being ordering in disguise: the registry order
answers to the declared data, rather than the data quietly relying on the order. Reordering the plan
topologically instead was rejected — ADR-0004 makes the plan the picker's order on purpose, so that
what a person read down the list in is what the run works through.

An addition names not only the prerequisite but whatever else its Install Step delivers: many-to-one
is the installer's shape (ADR-0004), so adding `pip` puts `eza` on the machine too, and a line
naming pip alone would leave eza as unexplained as it was before.

`config.json` stores what the user picked, not the closure — resolution re-runs on `--replay`, so a
prerequisite installed by the first run is simply present by the second.

Unchecking an auto-added prerequisite in the picker is deliberately not answered here; Profiles are
presets and not locks (ADR-0009), and making that visible before confirming is #24.
