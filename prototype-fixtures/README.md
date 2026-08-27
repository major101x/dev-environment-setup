# Frame fixtures for #21

Exact output of the **winning variant, F** — a bordered, content-height box with
a multi-column grid of every Install Step. Produced by
`../install-screen-prototype.sh`, which is throwaway and read-only against
`setup.sh`. See ADR-0007.

    ./install-screen-prototype.sh F <frame> --raw    # exact bytes, with ANSI  -> *.ansi
    ./install-screen-prototype.sh F <frame> --plain  # SGR stripped, reviewable -> *.txt

| fixture   | what it pins |
|-----------|--------------|
| `legend`  | all 7 lifecycle states have a distinct appearance |
| `midrun`  | 22 Install Steps (`--all`), one failure logged, one Step in flight |
| `rerun`   | idempotent re-run — 19 of 22 `already installed` |
| `cascade` | one failed prerequisite (`node, puppeteer`) producing five `skipped` |
| `final`   | the finalised frame: every Step with its version, summary, every failure |

`midrun.120x40` pins that a **live** frame fills the terminal — the box is
padded to the full height so its bottom edge does not jump as Steps complete.
`midrun.52x24` and `midrun.40x24` pin truncate-never-wrap and the column count
dropping as the terminal narrows.

**The live/final asymmetry matters and is asserted by these fixtures.** A live
frame is repainted in place, so it is padded to exactly the terminal height —
`midrun.80x24` is 24 lines, `midrun.120x40` is 40. The final frame is printed
once and never repainted, so it is neither padded nor capped: it runs to its
natural length and scrolls. That is what buys room for a version on every cell,
which #22 requires to survive in scrollback. `final.80x24` is 27 lines by design.

Capping the final frame at the terminal is not a cosmetic choice — it silently
drops the failure board off the bottom. `losing-variants/F-final.content-height.txt`
keeps the rejected unpadded alternative for comparison.

`losing-variants/` keeps one mid-run and one final frame from A, B, C, D and E
as the primary source behind ADR-0007's "considered and rejected".

The snapshot is fake on purpose — that is what #21's purity seam is for. The 22
Install Steps are transcribed from `setup.sh`'s real dispatch table collapsed
many-to-one per ADR-0004, so the density is honest.
