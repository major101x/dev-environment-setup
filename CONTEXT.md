# CONTEXT.md

## Glossary

| Term | Definition | Avoid |
|---|---|---|
| **Profile** | Named preset that pre-checks a set of tools (e.g. `default`, `go`, `rust`, `fe`, `be`, `python-ai`, `ai-agents`, `full-stack-web`). Selecting a profile does not lock choices — user can still uncheck individual tools. | Bundle, preset (use Profile) |
| **Tool** | Installable unit the user selects: an apt package, a language toolchain, a binary, or a service (e.g. `gh`, `fastfetch`, `opencode`, `node`, `puppeteer`, `docker`, `exa-mcp`, `pocock-skills`, `pip`). A Tool is what appears in the picker and in a Profile. It is **not** the unit of installation work — see Install Step. | App, library, package |
| **Install Step** | The unit of installation work: one idempotent function that delivers one or more Tools. The mapping is many-to-one — `install_go` delivers `go`, `golangci-lint` and `air`; `install_node_and_puppeteer` delivers `node` and `puppeteer`. An Install Step is what carries progress, a lifecycle state and a result, and so what gets a row on the install screen, labelled by the Tools it delivers. | Job, task, package, install function |
| **Category** | UI grouping for Tools: `Languages`, `Frontend`, `Backend/DB`, `AI/ML`, `Infra/DevOps`. Categories are collapsible and searchable but do not affect install logic. | Group, section |
| **Toolset** | Concrete set of Tools resolved from selected Profiles + manual toggles. Saved to persistence. | Stack |
| **Default Toolset** | The 9 tools shipped originally and pre-checked when no Profile is chosen: `gh`, `fastfetch`, `opencode`, `nvm LTS + puppeteer + chrome-headless`, `google-chrome-stable`, `docker+compose`, `exa`, `pocock-skills`, `pip`. | Base, minimal |
| **Persistence** | File `~/.config/dev-setup/config.json` that stores last Toolset and flags for `--replay`. | Cache, state |
| **TUI** | Interactive picker built on `fzf` >= 0.60 (needs `--input-border` and `click-header`). Tabbed by Category, with a live Selected Toolset panel. Auto-installed if absent or too old; apt's 0.44.1 does not qualify. Not a hand-rolled bash `select`, and no longer `gum`. | UI, wizard |

## Decisions

- **Decision: Single-context repo** — per `docs/agents/domain.md`, this repo uses one `CONTEXT.md` at root + `docs/adr/` for ADRs.
- **Decision: Interactive by default** — `./setup.sh` with no args launches TUI; flags `--yes`, `--profile=`, `--all`, `--no-auth`, `--search=`, `--replay` enable non-interactive/CI use. `gh auth login` stays last and is skipped with `--no-auth`.
- **Decision: Profiles are presets, not locks** — checked items from a Profile remain uncheckable (user can customize even with recommended).
- **Decision: LTS everywhere** — language toolchains use `lts/*` (node via nvm, go latest, rust stable, python 3.12). Toolchain `PATH`/`~/.bashrc` mods are offered as opt-in prompt inside TUI.
- **Decision: fzf is the TUI, gum removed** — `gum filter` has no `--border`, `--padding` or key-binding flags, so its "tabs" were a static header string that could never show an active state. fzf provides `--input-border`, `--bind left/right/click-header` and `transform-header`. `ensure_fzf` capability-checks (apt ships 0.44.1, which lacks them) and installs 0.74.3 otherwise. Supersedes the earlier "gum primary, fzf fallback" decision. See [ADR-0002](docs/adr/0002-fzf-with-a-version-floor-replaces-gum.md).
- **Decision: TUI rows are typed by marker glyph** — `◆` Profile / `·` Tool, because `go` and `rust` are each both a Profile key and a Tool key and name lookup mistyped them. See [ADR-0003](docs/adr/0003-tui-item-type-comes-from-the-marker-glyph.md).
- **Decision: Persistence opt-in automatic** — every interactive run writes `~/.config/dev-setup/config.json`; `--replay` reuses it.
- **Decision: `full-stack-web` is a composite alias** — should resolve to `fe + be + docker + chrome + node`, deduplicated, rather than owning its own Tool list. Not yet implemented (`setup.sh:101` hardcodes a literal). See [ADR-0001](docs/adr/0001-full-stack-web-is-a-composite-alias.md).

- **Decision: Install Step is the unit of installation work** — the user picks Tools, but installers are many-to-one, so progress, state and results attach to Install Steps. See [ADR-0004](docs/adr/0004-install-step-is-the-unit-of-installation-work.md).
- **Decision: install progress is phases, not byte-level bars** — only 2 of 27 Tools have a measurable discrete download. See [ADR-0005](docs/adr/0005-install-progress-is-phases-not-byte-level.md).
- **Decision: a failed Install Step does not abort the run** — mark failed, continue, summarise at the end. See [ADR-0006](docs/adr/0006-a-failed-install-step-does-not-abort-the-run.md).
- **Decision: the install screen is a bordered grid of every Install Step** — a content-height box with one grid cell per Step, then the Step in flight, then a failure board. Nothing is collapsed or scrolled; it spends terminal width rather than height. Live frames are capped at the terminal because they are repainted in place; the finalised frame is printed once, so it may run taller and scroll, which is what buys a version on every cell. See [ADR-0007](docs/adr/0007-the-install-screen-collapses-completed-steps.md).

## Open Questions

- **ADR-0001: does `c-build` belong in `full-stack-web`?** The code includes it; `docs/spec-interactive.md` and issue #1 story 1 define the alias as `fe + be + docker + chrome + node`, which excludes it. Resolve when the alias is actually implemented.
- **Do `claude-code` and `c-build` need Install Steps?** Neither has an installer; both fall through to `warn "No installer for tool"`. `--all` selects both, and `c-build` is part of the `full-stack-web` Profile, so that Profile silently delivers nothing for it. Related to ADR-0001.
- **Do Profiles pre-check their Tools inside the TUI?** The Default Toolset now pre-checks and stays individually uncheckable, but toggling a Profile row does not yet check its member Tools, so a Tool cannot be unchecked out of a Profile without leaving the picker. Issue #1 stories 2 and 8 ask for this.
