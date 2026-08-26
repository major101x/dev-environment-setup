# The install screen collapses completed Install Steps instead of scrolling them

`--all` produces 22 Install Steps (`setup.sh:974`-`1005`, collapsed many-to-one per ADR-0004).
On 80×24 they do not fit, and #21 said only that the screen must render "coherently". Three
layouts were prototyped against four frames that a large Toolset actually produces — a mid-run
failure, an idempotent re-run, a skip cascade, and the finalised end-of-run frame. The prototype
is on branch `prototype/install-screen`.

The screen therefore **groups Install Steps by lifecycle state rather than by execution order, and
collapses the terminal success states — `done` and `already installed` — into one counter line
each**. `failed`, `skipped — unmet dependency` and the Install Step in flight are never collapsed.
Queued Steps collapse to a counter that expands into individual rows only as far as the leftover
rows allow, bounded by the pinned failure block, so the frame fits at any Toolset size by
construction rather than by clipping.

Finalisation is then the same layout with the in-flight block gone, and the summary prints beneath
it. One renderer, one layout, live and final.

## Considered and rejected

**A scrolling viewport around the active row.** Keeps the ordered list the user picked, which is
the intuitive answer. It fails on the two frames that matter most. On a re-run it is a wall of 19
near-identical `already installed` rows — precisely the "twenty suspiciously instant successes"
ADR-0005 says must not happen. And it cannot finalise: at the end of a 22-Step run the viewport
still reads "↑ 7 more above", and the *first* of two failed Steps never appears in the finalised
frame at all. Making it finalise means reprinting every row unclipped, which is a second layout —
so #21's pure function would have to branch on a `final` flag and be asserted twice.

**A fixed-height dashboard** — a state census, the active Install Step with its live output, and a
pinned failure board, with the per-Step list withheld until the end. It never overflows and it has
the best failure tail. Rejected because its finalised frame is dead scaffolding, and because it
never puts what installed and at what version on screen, which #22 requires.

## Consequences

The screen no longer shows Install Steps in the order they run, which is the real cost: during a
long run the user cannot watch their position advance down a list. The counter lines and the
active Step carry that instead.

`already installed` gets its own glyph and colour (`=`, blue) rather than a dimmer `done`, so a
re-run reads as "nothing to do here" instead of as instant success. A `skipped` row carries the
prerequisite that caused it on the row itself, so a five-deep cascade from one failed Step reads
as one cause and five consequences rather than six unexplained problems.

Rows truncate and never wrap. The layout has a width floor of about 30 columns, below which the
summary's counts line no longer fits on one line and splits.

A failed Step shows the last 2 lines of its output inline, beneath the row, and every failure
stays on screen to the end — the failure block is pinned and sized before the collapsible section,
so it can never be pushed off by a long Toolset.

Whether a dependent Step is marked `skipped` eagerly when its prerequisite fails, or lazily when
its turn arrives, is left to #22. The frame renders identically either way; only the moment the
row changes differs.
