# CONTEXT.md

## Glossary

| Term | Definition | Avoid |
|---|---|---|
| **Profile** | Named preset that pre-checks a set of tools (e.g. `default`, `go`, `rust`, `fe`, `be`, `python-ai`, `ai-agents`, `full-stack-web`). Selecting a profile does not lock choices — user can still uncheck individual tools. | Bundle, preset (use Profile) |
| **Tool** | Installable unit: an apt package, a language toolchain, a binary, or a service (e.g. `gh`, `fastfetch`, `opencode`, `nvm/LTS node`, `puppeteer+chrome`, `docker`, `exa`, `pocock-skills`, `pip`). Each Tool maps to an idempotent install function in `setup.sh`. | App, library |
| **Category** | UI grouping for Tools: `Languages`, `Frontend`, `Backend/DB`, `AI/ML`, `Infra/DevOps`. Categories are collapsible and searchable but do not affect install logic. | Group, section |
| **Toolset** | Concrete set of Tools resolved from selected Profiles + manual toggles. Saved to persistence. | Stack |
| **Default Toolset** | The 9 tools shipped originally and pre-checked when no Profile is chosen: `gh`, `fastfetch`, `opencode`, `nvm LTS + puppeteer + chrome-headless`, `google-chrome-stable`, `docker+compose`, `exa`, `pocock-skills`, `pip`. | Base, minimal |
| **Persistence** | File `~/.config/dev-setup/config.json` that stores last Toolset and flags for `--replay`. | Cache, state |
| **TUI** | Interactive picker built on `gum` (primary) with `fzf` fallback. Requires one of them; if missing, auto-install `gum` binary or error. Not a hand-rolled bash `select`. | UI, wizard |

## Decisions

- **Decision: Single-context repo** — per `docs/agents/domain.md`, this repo uses one `CONTEXT.md` at root + `docs/adr/` for ADRs.
- **Decision: Interactive by default** — `./setup.sh` with no args launches TUI; flags `--yes`, `--profile=`, `--all`, `--no-auth`, `--search=`, `--replay` enable non-interactive/CI use. `gh auth login` stays last and is skipped with `--no-auth`.
- **Decision: Profiles are presets, not locks** — checked items from a Profile remain uncheckable (user can customize even with recommended).
- **Decision: LTS everywhere** — language toolchains use `lts/*` (node via nvm, go latest, rust stable, python 3.12). Toolchain `PATH`/`~/.bashrc` mods are offered as opt-in prompt inside TUI.
- **Decision: `gum`/`fzf` required** — TUI uses `gum choose --no-limit` + `gum filter` for search/multi-select; `fzf --multi` is fallback. If neither present, auto-install `gum` from GitHub releases or exit with instruction (do not fall back to custom bash TUI).
- **Decision: Persistence opt-in automatic** — every interactive run writes `~/.config/dev-setup/config.json`; `--replay` reuses it.

## Open Questions

- ADR-0001: Whether `full-stack-web` should be a distinct Profile or just `fe + be + docker + chrome` composite alias (choose composite alias to avoid duplication).
