# Install Step is the unit of installation work, not Tool

The user selects **Tools**, but `install_selected_tools` (`setup.sh:979`-`1005`) dispatches to
install functions many-to-one: `install_go` delivers `go`, `golangci-lint` and `air`;
`install_node_and_puppeteer` delivers `node` and `puppeteer` (plus nvm, npm, Chrome-for-Testing,
headless-shell and apt libs); `install_pip_eza` delivers two unrelated Tools. `CONTEXT.md`
previously claimed each Tool maps to its own install function, which was simply untrue.

This never mattered until the install progress screen needed a row per *something*. A row per Tool
would show three bars moving in lockstep for one operation, and `golangci-lint` and `air` have no
independent install step and no version of their own to report.

So **Install Step** enters the glossary as the unit that carries progress, a lifecycle state and a
result. The screen shows one row per Install Step, labelled by the Tools it delivers.

## Considered and rejected

**Split every installer 1:1 with Tools.** Most honest, and still open for individual Tools later.
Rejected as the general answer because the coupling is partly irreducible — `node` and `puppeteer`
are one npm-driven sequence, and forcing them apart would mean re-entering nvm for each.

**Show Tools and attribute the shared installer's progress to all of them.** Cheapest, and it
lies: identical progress on three rows for one operation, and invented versions for Tools that
were never separately installed.

## Consequences

Naming the real relationship is what makes the screen honest, but it means the picker and the
installer speak different units, and something has to translate. It also makes visible that two
Tools — `claude-code` and `c-build` — have no Install Step at all and fall through to
`warn "No installer for tool"`, despite `c-build` being part of the `full-stack-web` Profile.
