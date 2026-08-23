# Spec: Interactive setup TUI

## Context
Repo `dev-environment-setup` currently runs a fixed `setup.sh` that installs the Default Toolset (9 tools). Grill answers (2026-08-23) require it to become interactive: any dev type (full-stack, fe, be, Go, Rust, Python AI, AI agents) can pick exactly what they need, with search, categories, recommended Profiles, and persistence.

## Goal
`./setup.sh` with no args launches a TUI that:
- shows Categories (`Languages`, `Frontend`, `Backend/DB`, `AI/ML`, `Infra/DevOps`) with collapsible multi-select
- supports live fuzzy search across name/description/category (`gum filter` / `fzf`)
- offers Profiles that pre-check their Toolset but remain individually uncheckable for fine-tuning
- pre-checks Default Toolset; saves last picks to `~/.config/dev-setup/config.json` for `--replay`
- remains idempotent; non-interactive flags bypass TUI for CI

## Profiles (preset Toolsets)

| Profile | Tools (keys) |
|---|---|
| `default` | gh, fastfetch, opencode, node, puppeteer, chrome, docker, exa-mcp, pocock-skills, pip, eza |
| `go` | go (1.23 LTS), golangci-lint, air |
| `rust` | rustup (stable + cargo) |
| `fe` | bun, pnpm, biome, vite |
| `be` | postgresql-client, redis-tools |
| `python-ai` | uv, python3.12-venv, jupyter, torch-deps, ollama |
| `ai-agents` | python-ai + qdrant (docker) + exa-mcp + opencode |
| `full-stack-web` | alias for `fe + be + docker + chrome + node` (no duplicate installs) |

Selecting multiple profiles unions their tools; duplicates are deduped.

## Tool registry (additions to existing)

| Tool key | Category | Install method (LTS) | Notes |
|---|---|---|---|
| `go` | Languages | `snap` or tarball 1.23 LTS | adds `go` to PATH, `GOPATH` |
| `rust` | Languages | `rustup` stable | `cargo` |
| `bun` | Frontend | `curl https://bun.sh/install` | |
| `pnpm` | Frontend | `npm i -g pnpm` (after node) | |
| `uv` | AI/ML | `curl https://astral.sh/uv/install.sh` | |
| `ollama` | AI/ML | `curl https://ollama.com/install.sh` | |
| `qdrant` | AI/ML | docker image | |
| `postgresql-client` | Backend/DB | `apt` | |
| `redis-tools` | Backend/DB | `apt` | |

Existing tools keep their current install functions; new tools add `install_<key>()` functions.

## Flags (non-interactive)

```
./setup.sh                          # interactive TUI (requires gum/fzf, auto-installs gum if missing)
./setup.sh --yes                    # non-interactive, Default Toolset only
./setup.sh --profile=go,rust        # profiles union + default
./setup.sh --profile=full-stack-web # alias
./setup.sh --all                    # every tool
./setup.sh --search=postgres        # fuzzy search single install
./setup.sh --replay                 # reuse ~/.config/dev-setup/config.json
./setup.sh --no-auth                # skip final gh auth login (CI)
./setup.sh --list-profiles          # print profiles and exit
./setup.sh --list-tools             # print tool registry and exit
./setup.sh --help
```

Interactive also supports `--no-auth` passthrough.

## TUI flow (gum primary, fzf fallback)

1. `ensure_gum()` — if neither `gum` nor `fzf` found, download `gum` binary from charmbracelet releases to `/usr/local/bin/gum` (or `/tmp/gum` if not root). If download fails, error with install instructions; do not fall back to hand-rolled bash TUI.
2. Profile picker: `gum choose --no-limit --header="Profiles (Space to select, Enter confirm)" --selected="default"` — multi-select. Full list above.
3. Expand profiles to Toolset; prompt `gum confirm "Include toolchain PATH setup in ~/.bashrc?"` (per grill #6).
4. Tool picker: for each Category, show its tools with pre-checked items (`gum choose --no-limit --selected="<pre>"` per category, then `gum filter` for search). Alternatively single `gum choose --no-limit` over flat list grouped by `Category | Tool - Description`.
5. Summary: `gum style` shows chosen tools count; `gum confirm "Install X tools?"`.
6. Persist: write `~/.config/dev-setup/config.json` (`{profiles:[], tools:[], toolchain:bool}`).
7. Execute install functions for chosen tools in dependency order (base → node-dependent → docker-dependent).

CI flags skip steps 1-5 and go straight to 7.

## Persistence

- Path `~/.config/dev-setup/config.json` (XDG). Auto-created on every interactive run.
- `--replay` loads it; if missing error.
- `setup.sh --yes` also writes it (so replay reflects last CI run).

## Non-goals

- No uninstall on un-check (idempotent only adds).
- No custom bash TUI if gum/fzf missing.
- No version pinning beyond LTS (user can edit config.json for pin).

## Verification

- `bash -n setup.sh` passes, `shellcheck` info-level only.
- `setup.sh --list-profiles` and `--list-tools` output matches registry.
- `setup.sh --yes --no-auth` still installs Default Toolset idempotently (dry run on VPS with tools already present skips).
- `setup.sh --profile=go --no-auth` installs go without prompting.
- Interactive smoke: `gum` present → profile + tool picker returns non-empty; saved config exists.
