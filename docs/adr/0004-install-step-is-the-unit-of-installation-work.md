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

## A Tool with no Install Step is a state, and nothing is in it

Naming the relationship made visible that two Tools had no Install Step at all — `c-build` and
`claude-code` — and that the run said nothing useful about either. `c-build` was answered first:
[ADR-0001](0001-full-stack-web-is-a-composite-alias.md) narrowed it to `cmake` + `pkg-config` and
gave it an installer. `claude-code` is answered here (#53), the same way and for the same reason.
A Profile that lists a Tool nothing delivers is a Profile that quietly delivers less than it
lists, and `ai-agents` — a Profile whose whole subject is AI CLIs — listed one.

It installs from Claude Code's own installer rather than the npm package. The npm route would put
`node` between this Step and its Tool, for a binary that needs none: `STEP_REQUIRES` would have
to declare it, declining `node` would strand `claude-code` on `skipped`, and the version probe
would have to reach through `with_node` the way `pnpm`, `biome` and `vite` do (ADR-0016). The
native installer lands a self-updating binary in `$HOME/.local/bin`, which is where `install_uv`
already puts one. Both of its probes name `claude` rather than `claude-code`: the binary is not
named after the Tool, so the convention would ask a command that does not exist.

Removing it from the registry was the other real option, and it is what an honest answer would
have been if Claude Code could not be installed unattended. It can, so removing it would have
narrowed the Toolset to spare the installer. The third — a first-class "declared non-Install"
state — buys vocabulary no second Tool wants; if one ever does, it can be reopened then.

The stepless state itself stays. `TOOL_INSTALL_STEP` has no entry missing today, and the report
that names one is now a guard rather than a description: a Tool added to a Profile without an
installer is still named before the run starts rather than dropped, and `test/cli.bats` reaches
that state by splicing a Tool in, since the registry no longer supplies one.

## Consequences

Naming the real relationship is what makes the screen honest, but it means the picker and the
installer speak different units, and something has to translate.
