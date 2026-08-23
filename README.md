# dev-environment-setup

Idempotent Ubuntu 24.04 (Noble) setup script for a fresh VPS. Installs everything from the last session in one go - logs to `setup.log`.

**What it installs (all idempotent, safe to re-run):**

| Tool | Version (tested) | Source |
|---|---|---|
| GitHub CLI `gh` | 2.98.0 | `cli.github.com/packages` apt repo |
| fastfetch | 2.67.0 | `ppa:zhangsongcui3371/fastfetch` |
| opencode | 1.18.21 | `curl -fsSL https://opencode.ai/install \| bash` → `~/.opencode/bin/opencode` |
| Node via nvm | `lts/*` → v24.19.0 (nvm 0.40.3) | `nvm-sh/nvm` + `nvm install --lts` |
| Puppeteer | 25.8.0 global + Chrome 152.0.7977.42 + chrome-headless-shell | `npm i -g puppeteer` + `npx puppeteer browsers install` |
| Google Chrome stable | 151.0.7922.173 | `dl.google.com/linux/chrome/deb` |
| Docker CE | 29.7.2 + compose v5.5.0 + buildx | `download.docker.com` noble |
| Exa web search MCP | hosted `https://mcp.exa.ai/mcp` (anonymous) | `opencode mcp add exa` |
| Matt Pocock skills | 48 skills in `~/.agents/skills` | `mattpocock/skills` + `fullheart/mattpocock-skills-opencode` via `npx skills` |
| pip + eza | pip 24.0 (py 3.12), eza 0.18.2 | `apt` universe |

Specs of the reference VPS (`fastfetch`):

```
OS: Ubuntu 24.04.4 LTS (Noble) x86_64
Host: KVM/QEMU pc-i440fx-9.0
Kernel: 6.8.0-138-generic
CPU: AMD EPYC (with IBPB) (4) @ 2.79 GHz
Memory: 7.76 GiB - Disk (/): 96G (94G free)
```

## Usage

```bash
# 1. Clone or curl
git clone https://github.com/<you>/dev-environment-setup.git
cd dev-environment-setup

# or one-liner (no clone):
curl -fsSL https://raw.githubusercontent.com/<you>/dev-environment-setup/main/setup.sh -o setup.sh
chmod +x setup.sh

# 2. Run as root (required for apt/docker)
sudo ./setup.sh
# logs to ./setup.log - tail in another terminal:
tail -f setup.log

# 3. Re-open shell after (nvm + opencode PATH)
source ~/.bashrc
export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

# 4. Verify
gh --version && fastfetch && opencode --version && node -v && google-chrome-stable --version && docker --version && opencode mcp list
```

### Notes

- **Idempotent:** every section checks `command -v <tool>` first and skips if present. Re-run anytime.
- **Logging:** `exec > >(tee -a setup.log) 2>&1` - both stdout and stderr go to console + file.
- **nvm:** installs to `~/.nvm`, adds `export NVM_DIR` + sourcing to `~/.bashrc`, sets `default -> lts/*`.
- **Puppeteer Chrome:** cached at `~/.cache/puppeteer/chrome/linux-*/chrome-linux64/chrome`. System Chrome at `/usr/bin/google-chrome-stable` also installed for non-puppeteer testing.
- **Docker:** enables `docker.service` via systemd; `docker run --rm hello-world` is the smoke test.
- **Exa MCP:** anonymous hosted endpoint (`rate-limited`). For higher limits add `?exaApiKey=YOUR_KEY` via `opencode mcp add exa --url "https://mcp.exa.ai/mcp?exaApiKey=..."` or `opencode mcp auth`.
- **Matt Pocock skills:** installed globally to `~/.agents/skills` for `opencode` agent (`npx skills --yes ... --global --agent opencode --all`). Some “Eve/PromptScript” warnings are expected and harmless.
- **gh auth:** interactive `gh auth login` is **last** so it doesn’t block apt installs. If already logged in it asks before re-authing.
- Tested on clean Ubuntu 24.04 - `bash -n setup.sh` passes, `shellcheck` info-level only.

## Manual tweaks

```bash
# Exa with API key (higher limits)
opencode mcp remove exa
opencode mcp add exa --url "https://mcp.exa.ai/mcp?exaApiKey=$EXA_API_KEY"

# Node version override
export NVM_DIR="$HOME/.nvm"; . "$NVM_DIR/nvm.sh"; nvm install 22; nvm alias default 22

# Only one section: comment out others in main() at bottom of setup.sh
```

## License

MIT - see [LICENSE](LICENSE).
