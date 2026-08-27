# The install screen is a bordered grid of every Install Step

`--all` produces 22 Install Steps (`setup.sh:974`-`1005`, collapsed many-to-one per ADR-0004).
On 80×24 a one-row-per-Step list does not fit, and #21 said only that the screen must render
"coherently". Six layouts were prototyped against four frames a large Toolset actually produces —
a mid-run failure, an idempotent re-run, a skip cascade, and the finalised end-of-run frame. The
prototype is on branch `prototype/install-screen`.

The screen is therefore **a bordered box containing a multi-column grid with one cell per Install
Step**, followed by the Step in flight with its live output, then a failure board. Every Step is
visible at once at 80×24 — nothing is collapsed, scrolled or hidden behind a viewport. The layout
spends terminal *width*, which is spare, rather than *height*, which is not.

While the run is live the box is **padded to the full terminal height**, so its bottom edge does
not jump every time an Install Step completes. The alternate screen buffer is never used — the box
is painted in the normal buffer and repainted in place — so the finalised frame survives in
scrollback as ordinary output, and `gh auth login` prompts beneath it.

**Live and finalised frames are sized by different rules, and this is load-bearing.** A live frame
is repainted in place, so it is padded to exactly the terminal height. The finalised frame is
printed once and never repainted, so it is neither padded nor capped: it runs to its natural
length and scrolls. That is what buys room to put a version on every cell at the end — the
finalised frame at 80×24 is 27 lines, by design.

Capping the finalised frame at the terminal height instead is not a cosmetic choice. At 80×24 it
drops the entire failure board off the bottom — every failed and skipped Step disappears — which
is the same defect that disqualified the scrolling viewport below.

## Considered and rejected

**A scrolling viewport around the active row.** The intuitive answer, and it fails on the two
frames that matter most. On a re-run it is a wall of 19 near-identical `already installed` rows —
precisely the "twenty suspiciously instant successes" ADR-0005 says must not happen. And it cannot
finalise: at the end of a 22-Step run it still reads "↑ 7 more above", and the *first* of two
failed Steps never appears in the finalised frame. Making it finalise means reprinting every row
unclipped, which is a second layout, so #21's pure function would have to branch and be asserted
twice.

**A ledger that collapses terminal states into counters** — `done` and `already installed` become
one counter line each, while failures, skips and the active Step never collapse. Compact, correct,
and fits any Toolset size by construction. Rejected because collapsing `done` into "15 done"
discards exactly what #22 asks the finalised frame to keep: what installed and at what version.
The grid keeps per-Step identity at the same cost.

**A fixed-height dashboard** — census, active Step, pinned failure board, with the per-Step list
withheld until the end. Never overflows and has the best failure tail, but finalises to dead
scaffolding and never shows versions.

**A two-pane split mirroring the picker** (`setup.sh:455`-`463`). Visually the closest to the
picker, and the worst fit: 48% of the width goes to a detail pane, leaving the list 38 columns, so
labels truncate to `pocock-skil…` while the pane sits half empty. The picker affords the split
because its rows are short keys; these rows carry label, state and version.

**A full-bleed single column with no collapsing.** The best-looking frame of the six when it fits,
but it needs 29 rows mid-run and 36 to finalise, and 80×24 is the stated pressure case.

## Consequences

Because live frames are padded, a short Toolset renders a mostly empty box. That is the accepted
cost of a stable bottom edge; the alternative was a box that grows and shrinks under the cursor.

A grid cell is narrow, so during a run it carries a glyph and a label but not a reason. The
failure board beneath carries reasons, and on a cascade at 80×24 it may not fit them all — it then
counts what it dropped out loud rather than truncating silently, because a band that quietly stops
reads as "that is all of them", which is the one thing a cascade frame must not say.

`already installed` gets its own glyph and colour (`=`, blue) rather than a dimmer `done`, per
ADR-0005 — a re-run must read as "nothing to do", not as instant success. In grid form a re-run
reads as a field of blue with the one running Step standing out, which is the intended shape.

Rows truncate and never wrap. Column count falls as the terminal narrows; the layout is clean from
120 columns down to 40.

The screen no longer shows Install Steps in a single ordered column, which is the real cost: the
grid is filled column-major, so following execution order means reading down and then across.

Whether a dependent Step is marked `skipped` eagerly when its prerequisite fails, or lazily when
its turn arrives, is left to #22. The frame renders identically either way.
