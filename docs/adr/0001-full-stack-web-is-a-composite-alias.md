# `full-stack-web` is a composite alias, not a distinct Profile

Every other Profile owns a literal Tool list, so giving `full-stack-web` one of its own means restating the contents of `fe`, `be`, `docker`, `chrome` and `node` — and drifting from them the moment any of those changes. The decision is that `full-stack-web` resolves to those Profiles at selection time, deduplicated into one Toolset, leaving the composed Profiles as the single source of truth.

## Status

**Implemented.** `PROFILE_TOOLS[full-stack-web]` is *declared* holding only the alias's own extras (`docker chrome node`); the single call `compose_profile full-stack-web fe be`, at startup and before anything reads the registry, overwrites it with the deduplicated union of `fe`, `be` and those extras. By the time any consumer looks — `--list-profiles`, the CLI's `resolve_tools_from_profiles`, the TUI's list and preview — the entry is an ordinary resolved Tool list, so nothing downstream knows composition exists. The literal `bun pnpm biome vite postgres-client redis-tools docker chrome node c-build` it replaced is gone.

`compose_profile` takes its target and sources as arguments and is called once, by name. There is deliberately no registry of composable Profiles to add a second row to — see "The alias is the exception, not the rule" below.

Resolution stays a mechanism this one alias uses rather than a new kind of thing in the model — there is no "composite Profile" in the glossary, and `full-stack-web` is still just a Profile.

## Consequences

The alias has no Tool list of its own to declare, so something has to resolve one before it can be displayed or installed. Doing that once at startup, in place, is what keeps the cost to a single call site: the TUI resolves nothing itself, and selecting the alias pre-checks the union of the underlying Tools — which the user can then uncheck individually, exactly like any other Profile (see "Profiles are presets, not locks" in `CONTEXT.md`).

## Closed: `c-build` does not belong

The hardcoded list included `c-build`; `docs/spec-interactive.md:25` defines the alias as `fe + be + docker + chrome + node`, which excludes it. Native-module builds under `node` were the plausible reason it was added.

It drops out of the alias, and it does **not** become a declared dependency of `node` either — because the premise behind both options was wrong. `install_base_deps` already runs `apt-get install -y … build-essential` unconditionally, on every non-dry-run install, whatever the Toolset. Native modules have had gcc and make all along, from base deps, with `c-build` unselected. Declaring it a prerequisite of `node` would declare a prerequisite that is already satisfied before any Tool is considered.

`c-build` remains a Tool, narrowed to what it uniquely adds on top of base deps — `cmake` and `pkg-config` — with a real Install Step (`install_c_build`). Before this it had no installer at all and fell through to `warn "No installer for tool"`, so `full-stack-web` printed a warning and delivered nothing for it.

## The alias is the exception, not the rule

`ai-agents` restates all of `python-ai` (`uv jupyter ollama`) plus its own extras, which is the same drift this ADR was written to prevent. It keeps its literal list anyway: composition is not a general mechanism in this model, and one alias earning it does not make it a pattern. If `python-ai` gains a Tool, `ai-agents` will silently not get it — accepted, and recorded here so the next person does not read it as an oversight.

## Guarded by

`test/cli.bats` asserts the expansion is nine Tools with no `c-build` in it, and — the assertion that tells resolution from a literal that happens to agree with it — patches a Tool into `fe` in a copy of `setup.sh` and asserts it comes out of `full-stack-web` with the alias untouched.
