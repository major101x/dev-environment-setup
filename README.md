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
- **Profiles** are macros: toggling a `◆` row checks its Tools right there in the list, and any of them stays uncheckable for fine-tuning — with or without a search query active. Toggling it again drops the label, not the Tools (see ADR-0009, ADR-0010).
  Profiles: `default` (the 11 tools above) · `go` (go + golangci-lint + air) · `rust` (rust, via rustup) · `fe` (bun/pnpm/biome/vite) · `be` (postgres-client/redis-tools) · `python-ai` (uv/jupyter/ollama) · `ai-agents` (uv/jupyter/ollama/qdrant/exa-mcp/opencode/claude-code) · `full-stack-web` (fe + be + docker + chrome + node, resolved from those Profiles — see ADR-0001)
- **A check lives in the list, not in fzf.** Rows read `[x] ◆ go` / `[ ] · air`, and the marker is painted from the picker's own state — so checks survive a Category tab switch, which fzf's selection did not (see ADR-0010).
- **Prerequisites show up before you confirm.** Check `jupyter` and the `pip` row reads `[+]` — the prerequisite resolution will add — and the panel names it next to the pick that pulled it in: `+ pip - required by jupyter (its install step also delivers eza)`. `TAB` on a `[+]` row is allowed and *declines* it: the row reads `[-]`, nothing else changes check, and the dependent is listed under `will be skipped: ! jupyter - unmet dependency: pip`, which is exactly the state the run then reports. A decline is saved with your picks, so `--replay` does not quietly install it next time. See [ADR-0015](docs/adr/0015-the-picker-shows-the-closure-and-a-decline-is-a-pick.md).
- **Default Toolset** pre-checked at startup, every run, and individually uncheckable; `TAB` checks the row under the cursor and leaves it there, `Enter` installs exactly what is checked, `Esc` cancels. Nothing checked installs nothing — `--yes` is the deliberate way to ask for the defaults.
- **Toolchain PATH** prompt: `Include toolchain PATH setup in ~/.bashrc?` (per your answer #6).
- **Persistence:** saves to `~/.config/dev-setup/config.json` — the checked Tools, the Profile labels and any declined prerequisites — replay with `--replay`.

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
sudo ./setup.sh --dry-run --profile=go --no-auth  # simulate without installing (draws the install screen on a terminal)
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
- **Logging:** the run writes `setup.log` itself — its narration and every Install Step transition in plain text, plus everything an Install Step said while it ran — stdout and stderr, installer chatter and this script's own lines from inside it — inside a section that names the Step and its exit status: `[STEP OUTPUT] install_go | begin` … `| end | exit 0`. A Step's output goes to the log and not to the terminal, which is what frees the terminal for the install screen. There is no blanket `tee` redirect any more. See [ADR-0012](docs/adr/0012-the-log-is-written-per-install-step.md).
- **LTS:** language toolchains use `lts/*` (node via nvm, go 1.23 LTS, rust stable, python 3.12). See `TOOL_DESC` in `setup.sh`.
- **Dry run:** `--dry-run` simulates without touching system: no `apt`/`npm`/`docker`, no `~/.config/dev-setup/config.json` write, no `~/.bashrc` mods, no root required. It *does* fetch fzf if none capable is present — fzf is the picker's own dependency, not part of the Toolset, and without it you could never dry-run the TUI. It goes to `~/.cache/dev-setup/fzf`, never a system path, so no root is still needed. Use to inspect the resolved plan before a real run — `Toolset: ...` then one `Install Step: <fn> -> <tools>` line per Install Step, which is the unit the run actually works in (ADR-0004), plus a named line for any Tool no Install Step delivers. It then drives the real lifecycle against simulated Install Steps, so the plan is followed by the run it would have. Combines with any profile/flag (e.g. `--dry-run --profile=go`).
- **Prerequisites:** some Install Steps need another Tool on the machine first — `install_jupyter` needs `pip`, `install_qdrant` needs `docker`, the npx-based Steps need `node`. Those are declared, and resolution adds one that is neither picked nor already present to the Toolset, saying so on its own line: `Added prerequisite: pip - required by jupyter (its install step also delivers eza)`. So `--search=jupyter` installs jupyter rather than planning one Step and skipping it. Nothing is added silently — the line names everything the addition puts on the machine — and a prerequisite you already have is not added at all. A declaration that is circular, or that names a prerequisite the registry orders *after* the Tool needing it, is rejected by name before anything is planned. In the picker the addition is visible before you confirm, and can be unchecked — the dependent is then reported `Will be skipped: jupyter - unmet dependency: pip` before the run starts, and reaches `skipped` on the screen. See [ADR-0014](docs/adr/0014-resolution-adds-a-missing-prerequisite-to-the-toolset.md) and [ADR-0015](docs/adr/0015-the-picker-shows-the-closure-and-a-decline-is-a-pick.md).
- **Install screen:** on a terminal — after the picker, or under `--profile=go` on your own machine — the run draws a live screen from the first Install Step to the last: a bordered grid with one cell per Install Step showing its state, the Step in flight with a spinner, its elapsed time and the last two lines it said, and a failure board with every failed Step's last lines and every skipped Step's reason. It finalises in place when the run ends, the summary is printed beneath it, and both stay in scrollback; the screen is down before `gh auth login` prompts. Piped or in CI there is no screen, only the plain transition lines below. `--dry-run` draws the real screen against simulated Install Steps. See [ADR-0007](docs/adr/0007-the-install-screen-is-a-grid-of-every-install-step.md) and [ADR-0013](docs/adr/0013-the-install-screen-reads-the-stream.md).
- **Install Step lifecycle:** every Install Step reports its state changes as plain text on stdout — `[STEP] <install step> | <state>[ | <detail>]`. The states are `queued`, `downloading`, `installing`, `done`, `already installed`, `skipped` (detail names the unmet dependency) and `failed` (ADR-0005). `--dry-run --simulate-fail=install_node_and_puppeteer` reports that Step failed and shows the dependency skips it cascades into, which is the only way to see a failure without one. Colour is emitted only to a terminal, so a piped run is free of escape sequences. See [ADR-0011](docs/adr/0011-the-lifecycle-is-a-plain-text-transition-stream.md).
- **A failed Install Step does not stop the run:** it is marked `failed` and the next Step starts, so one broken apt repository does not cost you every remaining Tool ([ADR-0006](docs/adr/0006-a-failed-install-step-does-not-abort-the-run.md)). The run then ends with a summary — `9 install steps: 6 done, 1 already installed, 1 skipped, 1 failed`, followed by one line per failure naming the Tools it delivered and why it failed — and **exits 1 if any Step failed**, so CI never reads a half-installed machine as success. A `skipped` Step is not a failure and does not change the exit status. `--dry-run --simulate-fail=<step>` exercises all of it without installing anything.
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

The suite covers the non-interactive flags under `--dry-run`, the Install Step
lifecycle transitions a dry run emits, the install screen's renderer through
`__render` against exact frame fixtures, the live screen under a
pseudo-terminal, and the fzf
callbacks (`__tui_list`, `__tui_header`, `__tui_preview`, `__tui_tab`,
`__tui_click`, `__tui_toggle`) that fzf re-enters `setup.sh` for, plus the two
ends of a picker run — `__tui_seed` and `__tui_resolve`. The picker itself is
not covered — fzf reads `/dev/tty` and cannot be driven by piped stdin. See the
Verification section of [docs/spec-interactive.md](docs/spec-interactive.md).

## License

MIT - see [LICENSE](LICENSE).
