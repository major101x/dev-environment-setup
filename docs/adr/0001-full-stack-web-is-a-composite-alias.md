# `full-stack-web` is a composite alias, not a distinct Profile

Every other Profile owns a literal Tool list, so giving `full-stack-web` one of its own means restating the contents of `fe`, `be`, `docker`, `chrome` and `node` — and drifting from them the moment any of those changes. The decision is that `full-stack-web` resolves to those Profiles at selection time, deduplicated into one Toolset, leaving the composed Profiles as the single source of truth.

## Status

Decided, **not yet implemented**. `setup.sh:101` currently hardcodes the literal list `bun pnpm biome vite postgres-client redis-tools docker chrome node c-build` — the duplication this ADR exists to remove. Until that is replaced with resolution, adding a Tool to `fe` or `be` will silently not reach `full-stack-web`.

The open question below is now **closed**, and resolution stays a mechanism this one alias uses rather than a new kind of thing in the model — there is no "composite Profile" in the glossary, and `full-stack-web` is still just a Profile.

## Consequences

The alias has no Tool list of its own to display. The TUI must resolve it before rendering, so selecting it pre-checks the union of the underlying Tools — which the user can then uncheck individually, exactly like any other Profile (see "Profiles are presets, not locks" in `CONTEXT.md`).

## Closed: `c-build` does not belong

The hardcoded list includes `c-build`; `docs/spec-interactive.md:25` defines the alias as `fe + be + docker + chrome + node`, which excludes it. Native-module builds under `node` were the plausible reason it was added.

It drops out of the alias, and it does **not** become a declared dependency of `node` either — because the premise behind both options was wrong. `install_base_deps` already runs `apt-get install -y … build-essential` unconditionally, on every non-dry-run install, whatever the Toolset. Native modules have had gcc and make all along, from base deps, with `c-build` unselected. Declaring it a prerequisite of `node` would declare a prerequisite that is already satisfied before any Tool is considered.

`c-build` remains a Tool, narrowed to what it uniquely adds on top of base deps — `cmake` and `pkg-config` — with a real Install Step. Until this ADR is implemented it has no installer at all and falls through to `warn "No installer for tool"`, so `full-stack-web` today prints a warning and delivers nothing for it.

## The alias is the exception, not the rule

`ai-agents` restates all of `python-ai` (`uv jupyter ollama`) plus its own extras, which is the same drift this ADR was written to prevent. It keeps its literal list anyway: composition is not a general mechanism in this model, and one alias earning it does not make it a pattern. If `python-ai` gains a Tool, `ai-agents` will silently not get it — accepted, and recorded here so the next person does not read it as an oversight.
