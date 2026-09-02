# The picker shows the closure, and a decline is a pick

Amends [ADR-0010](0010-the-list-is-the-source-of-truth-for-a-check.md) in one particular: the
state is three sets rather than two, and a row has four markers rather than two. Everything else
there stands, and this is an instance of it — the closure is painted from the state like every
other check, not held in fzf.

[ADR-0014](0014-resolution-adds-a-missing-prerequisite-to-the-toolset.md) made resolution close the
Toolset over the declared prerequisites: a Tool whose prerequisite is neither picked nor on the
machine gets that prerequisite added. Resolution runs *after* the picker closes, so the first a
person heard of an addition was a line printed by a run that had already started — an explanation
arriving after the only moment it could have been acted on.

The picker now shows the closure **before** ENTER, and an auto-added prerequisite may be unchecked
there. Unchecking one is a **decline**: a pick like any other, carried out of the picker with the
checks, saved beside them, and honoured by resolution.

## The closure is derived, not stamped

The picker does not write its additions into the checked set. `tui_closure` reads the state, hands
`SELECTED_TOOLS` and `DECLINED_TOOLS` to the same `add_missing_prerequisites` the run calls, and
redraws from the result — so the panel is live by construction, and what it promises is what ENTER
resolves to, in the same sentence (`prerequisite_addition`, written once and read twice).

Stamping the additions into `checked` instead was rejected. It makes `checked` mean two things at
once, and a decline then becomes indistinguishable from a Tool that was never checked — so the next
redraw would add it straight back and TAB on that row would do nothing at all. Keeping `checked` as
*what the user picked* is what leaves room for a third set to mean *what the user refused*.

Working the additions out in the panel, separately from resolution, was rejected for the reason
ADR-0014 gives for having one resolution at all: a second implementation is free to disagree, and
the disagreement would be between a promise and a run.

## A decline is allowed, and it changes one row

Profiles are presets, not locks (ADR-0009), and an addition nobody asked for is no more a lock than
a Profile is. So TAB on a row that will install always means *not that one*, whether the check came
from the user or from the closure.

Unchecking a prerequisite deliberately does **not** uncheck its dependent. Touching one row must not
change two, and the dependent is a Tool the user did ask for. It stays checked and is marked
unsatisfiable in the panel, naming the prerequisite that will not be there, in the vocabulary of the
state it predicts — the run reports exactly those as `skipped — unmet dependency`. The consequence
is spelled out while it can still be undone, rather than discovered at install time.

A row therefore has four markers rather than two: `[x]` picked, `[+]` added by the closure, `[-]`
declined while something checked still needs it, `[ ]` neither. `[+]` exists because the list is the
source of truth for a check (ADR-0010) and a row that will install cannot read `[ ]`; `[-]` because a
decline still in force is not the same as never having checked the row.

## Consequences

`config.json` gains a `declined` array, because `--replay` reuses the last picks and a replay that
dropped the decline would install, one run later, the Tool the user unchecked. A config written
before this ADR has no such key and replays as it always did.

`find_unsatisfied_prerequisites` runs after the closure in `resolve_install_steps`, so the run says
`Will be skipped: jupyter - unmet dependency: pip` before it starts — the same sentence the panel
gave, for the run that was replayed rather than picked. Nothing else can reach it: after the closure
the only prerequisite still missing is a declined one.

A decline is not a lock either. TAB on a declined row checks the Tool outright, and checking a
Profile that contains it does the same, because both are positive picks of that Tool. It does
survive the dependent being unchecked and checked again — the user's answer stands until they give
another one — and `tui_seed_defaults` clears it, because a decline carried into a fresh picker would
be a lock that run never agreed to.

The decline is about the **Tool**, not about the pair. Decline node for `pocock-skills`, then check
`vite`, and the panel says `vite` will be skipped for want of node before ENTER — the answer already
given is applied to the new pick rather than silently reversed for it. Scoping a decline to the
dependent that pulled it in was rejected: it needs per-pair provenance to answer "you said no to node
for that one, do you mean this one too?", which is the question ADR-0009 refused to invent for the
Profile stamp, and it makes the same Tool both installed and refused in one Toolset. The cost is that
a decline outlives what caused it; it is visible on the row, said in the panel, and one TAB undoes
it.

Unsatisfiable is measured against the plan, not against the checked set. An Install Step is
many-to-one (ADR-0004), so `install_pip_eza` delivers pip whichever of pip and eza was picked: a
decline of pip with `eza` still checked does not take pip off the machine, and the dependent is not
stuck. `prerequisite_met_by_plan` asks the run-time gate's question of the plan — selected, or
delivered by a Step some other pick already put in it, or on the machine — so the panel promises a
skip exactly where the run performs one. It asks in the gate's order too: `already installed` comes
first (ADR-0005), and a Step with nothing left to do is not skipped for want of a Tool it will never
use, so a dependent that is already on the machine is not marked unsatisfiable. A panel that promised
a skip the run would not perform would be worse than the silence it replaced.

The other half of many-to-one is *not* answered here: declining pip while `eza` is checked installs
pip anyway, and the pip row still reads `[ ]`. That is the same gap as checking `eza` alone and
getting pip — the picker's unit is the Tool and the installer's is the Step — and it is as true of a
Tool picked directly as of one declined. The addition's line names what else its Step delivers,
which is as far as this ADR takes it.
