# dev-environment-setup

Idempotent Ubuntu 24.04 (Noble) setup script for a fresh VPS. Interactive by default — pick exactly what you need — logs to `setup.log`.

**What it installs (all idempotent, safe to re-run):**

| Tool | Version (tested) | Source |
|---|---|---|
| GitHub CLI `gh` | 2.98.0 | `cli.github.com/packages` apt repo |
| fastfetch | 2.67.0 | `ppa:zhangsongcui3371/fastfetch` |
| opencode | 1.18.21 | `curl -fsSL https://opencode.ai/install \| bash` |
| Node via nvm | `lts/*` → v24.19.0 (nvm 0.40.3) | `nvm-sh/nvm` |
| Puppeteer | 25.8.0 + Chrome 152.0.7977.42 | `npm i -g puppeteer` |
| Google Chrome stable | 151.0.7922.173 | `dl.google.com/linux/chrome/deb` |
| Docker CE | 29.7.2 + compose v5.5.0 | `download.docker.com` |
| Exa web search MCP | hosted `https://mcp.exa.ai/mcp` | `opencode mcp add exa` |
| Matt Pocock skills | 48 skills in `~/.agents/skills` + slash commands | `mattpocock/skills` |
| pip + eza | pip 24.0, eza 0.18.2 | `apt` |
| Go / Rust / Bun / pnpm / uv / Ollama / Qdrant | LTS (Go 1.23, Rust stable, Bun latest) | per-profile (see below) |

Specs of the reference VPS (`fastfetch`):

```
OS: Ubuntu 24.04.4 LTS (Noble) x86_64
Host: KVM/QEMU pc-i440fx-9.0
Kernel: 6.8.0-138-generic
CPU: AMD EPYC (with IBPB) (4) @ 2.79 GHz
Memory: 7.76 GiB - Disk (/): 96G (94G free)
```

## Interactive TUI (recommended)

`./setup.sh` with no args launches a picker. Works for any dev type — full-stack, fe, be, Go, Rust, Python AI, AI agents.

- **fzf >= 0.60 required** — auto-installs fzf 0.74.3 to `/usr/local/bin/fzf` if missing or too old. Note `apt install fzf` gives 0.44.1, which lacks `--input-border` and `click-header`. No hand-rolled bash TUI.
- **Categories:** `Languages`, `Frontend`, `Backend/DB`, `AI/ML`, `Infra/DevOps` — horizontal tabs (←/→ or click), plus type-to-search. A live **Selected Toolset** panel shows the resolved install list as you pick.
- **Profiles** expand to their Toolset on confirm, and any Tool stays uncheckable for fine-tuning:
  `default` (the 9 tools above) · `go` (go + golangci-lint + air) · `rust` (rustup) · `fe` (bun/pnpm/biome/vite) · `be` (postgres-client/redis-tools) · `python-ai` (uv/jupyter/ollama) · `ai-agents` (python-ai + qdrant + exa + opencode) · `full-stack-web` (fe + be + docker + chrome + node; currently also pulls `c-build` — see ADR-0001)
- **Default Toolset** pre-checked at startup and individually uncheckable; `TAB` toggles a row, `ctrl-a` toggles all, `Enter` confirms.
- **Toolchain PATH** prompt: `Include toolchain PATH setup in ~/.bashrc?` (per your answer #6).
- **Persistence:** saves to `~/.config/dev-setup/config.json` — replay with `--replay`.

```bash
# Interactive (default)
sudo ./setup.sh
# logs to ./setup.log - tail in another terminal:
tail -f setup.log
```

## Non-interactive (CI)

```bash
sudo ./setup.sh --yes --no-auth                    # Default Toolset only
sudo ./setup.sh --profile=go,rust --no-auth        # Go + Rust (+ default if you add default)
sudo ./setup.sh --profile=full-stack-web --no-auth
sudo ./setup.sh --all --no-auth                    # every tool
sudo ./setup.sh --search=postgres --no-auth        # single tool fuzzy search
sudo ./setup.sh --replay --no-auth                 # reuse last interactive picks
sudo ./setup.sh --dry-run --yes --no-auth          # dry run Default Toolset
sudo ./setup.sh --list-profiles                    # print profiles
sudo ./setup.sh --list-tools                       # print registry
sudo ./setup.sh --dry-run --profile=go --no-auth  # simulate without installing
sudo ./setup.sh --help
```

`--no-auth` skips the final `gh auth login` (which is always last so it does not block installs).

## Usage (full)

```bash
# 1. Clone or curl
git clone https://github.com/major101x/dev-environment-setup.git
cd dev-environment-setup

# or one-liner:
curl -fsSL https://raw.githubusercontent.com/major101x/dev-environment-setup/main/setup.sh -o setup.sh
chmod +x setup.sh

# 2. Run as root (required for apt/docker)
sudo ./setup.sh                # interactive
# or sudo ./setup.sh --profile=python-ai --no-auth

# 3. Re-open shell after (nvm + opencode PATH + go/rust if chosen)
source ~/.bashrc
export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

# 4. Verify
gh --version && fastfetch && opencode --version && node -v && google-chrome-stable --version && docker --version && opencode mcp list
# replay:
sudo ./setup.sh --replay
```

### Notes

- **Idempotent:** every install checks `command -v <tool>` first and skips if present. Un-checking a tool does not uninstall.
- **Logging:** `exec > >(tee -a setup.log) 2>&1` - both stdout and stderr go to console + file.
- **LTS:** language toolchains use `lts/*` (node via nvm, go 1.23 LTS, rust stable, python 3.12). See `TOOL_DESC` in `setup.sh`.
- **Dry run:** `--dry-run` simulates without touching system: no `apt`/`npm`/`docker`, no `~/.config/dev-setup/config.json` write, no `~/.bashrc` mods, no root required. It *does* fetch fzf if none capable is present — fzf is the picker's own dependency, not part of the Toolset, and without it you could never dry-run the TUI. It goes to `~/.cache/dev-setup/fzf`, never a system path, so no root is still needed. Use to test `Toolset: ...` and `Would install: ...` output before real run. Combines with any profile/flag (e.g. `--dry-run --profile=go`).
- **fzf:** `ensure_fzf()` capability-checks the binary (probes `--input-border` and a `click-header` bind) rather than merely checking it exists, then installs from GitHub releases if it falls short.

## Manual tweaks

```bash
# Exa with API key (higher limits)
opencode mcp remove exa
opencode mcp add exa --url "https://mcp.exa.ai/mcp?exaApiKey=$EXA_API_KEY"

# Node version override
export NVM_DIR="$HOME/.nvm"; . "$NVM_DIR/nvm.sh"; nvm install 22; nvm alias default 22

# Edit last picks directly
cat ~/.config/dev-setup/config.json
# or re-run picker to change
```

## Tests

```bash
./test/run.sh                 # whole suite
./test/run.sh test/tui.bats   # one file
```

[bats](https://github.com/bats-core/bats-core) from `PATH` if you have it,
otherwise the pinned version is `git clone`d into `.cache/` (gitignored) on
first run — no test tooling to install, just git and network the first time.
CI runs the same script, plus `bash -n` on each shell file and
`shellcheck -S warning`.

The suite covers the non-interactive flags under `--dry-run` and the fzf
callbacks (`__tui_list`, `__tui_header`, `__tui_preview`, `__tui_tab`,
`__tui_click`) that fzf re-enters `setup.sh` for. The picker itself is not
covered — fzf reads `/dev/tty` and cannot be driven by piped stdin. See the
Verification section of [docs/spec-interactive.md](docs/spec-interactive.md).

## License

MIT - see [LICENSE](LICENSE).
