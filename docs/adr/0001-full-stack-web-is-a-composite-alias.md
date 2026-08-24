# `full-stack-web` is a composite alias, not a distinct Profile

Every other Profile owns a literal Tool list, so giving `full-stack-web` one of its own means restating the contents of `fe`, `be`, `docker`, `chrome` and `node` — and drifting from them the moment any of those changes. The decision is that `full-stack-web` resolves to those Profiles at selection time, deduplicated into one Toolset, leaving the composed Profiles as the single source of truth.

## Status

Decided, **not yet implemented**. `setup.sh:101` currently hardcodes the literal list `bun pnpm biome vite postgres-client redis-tools docker chrome node c-build` — the duplication this ADR exists to remove. Until that is replaced with resolution, adding a Tool to `fe` or `be` will silently not reach `full-stack-web`.

## Consequences

The alias has no Tool list of its own to display. The TUI must resolve it before rendering, so selecting it pre-checks the union of the underlying Tools — which the user can then uncheck individually, exactly like any other Profile (see "Profiles are presets, not locks" in `CONTEXT.md`).

## Open: does `c-build` belong?

The hardcoded list includes `c-build`; `docs/spec-interactive.md:25` defines the alias as `fe + be + docker + chrome + node`, which excludes it. Native-module builds under `node` are the plausible reason it was added. Resolve this when implementing — either `c-build` becomes a dependency of `node`, or it drops out of the alias.
