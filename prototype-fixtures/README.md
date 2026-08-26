# Frame fixtures for #21

Exact output of the **winning prototype variant (B, "ledger")**, produced by
`../install-screen-prototype.sh`. These are handed to #21 as its exact-frame
test fixtures so it does not have to invent them.

    ./install-screen-prototype.sh B <frame> --raw    # exact bytes, with ANSI  -> *.ansi
    ./install-screen-prototype.sh B <frame> --plain  # SGR stripped, reviewable -> *.txt

| fixture   | what it pins |
|-----------|--------------|
| `legend`  | all 7 lifecycle states have a distinct appearance |
| `midrun`  | 22 Install Steps (`--all`), one failure already logged, one Step in flight |
| `rerun`   | idempotent re-run — 19 of 22 `already installed` |
| `cascade` | one failed prerequisite (`node, puppeteer`) producing five `skipped` |
| `final`   | the finalised frame plus the summary printed beneath it |

`midrun.52x24` and `midrun.34x24` pin the truncate-never-wrap rule. The layout's
width floor is ~30 columns; below that the summary's counts line overflows.

The snapshot is fake on purpose — that is what #21's purity seam is for. The 22
Install Steps are transcribed from `setup.sh`'s real dispatch table collapsed
many-to-one per ADR-0004, so the density is honest.
