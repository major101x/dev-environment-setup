# dev-environment-setup

Set up a fresh Ubuntu 24.04 machine for development — VPS or desktop — by picking what you want from a list.

Safe to re-run: anything already installed is left alone. Everything it does is written to `setup.log`.

```bash
git clone https://github.com/major101x/dev-environment-setup.git
cd dev-environment-setup
sudo ./setup.sh
```

That opens a picker. Choose your tools, press `Enter`, and watch it install. Then log out and back in so the new `PATH` takes effect.

## What you can install

| Tool | Version tested | Where it comes from |
|---|---|---|
| GitHub CLI `gh` | 2.98.0 | `cli.github.com` apt repo |
| fastfetch | 2.67.0 | `ppa:zhangsongcui3371/fastfetch` |
| opencode | 1.18.21 | opencode.ai installer |
| Node via nvm | `lts/*` → v24.19.0 | nvm 0.40.3 |
| Puppeteer | 25.8.0 + Chrome 152 | npm, global |
| Google Chrome | 151.0.7922.173 | `dl.google.com` |
| Docker CE | 29.7.2 + compose v5.5.0 | `download.docker.com` |
| Exa web search (MCP) | hosted | registered with opencode |
| Matt Pocock skills | 48 skills + slash commands | `mattpocock/skills` |
| pip, eza | 24.0, 0.18.2 | apt |
| Go, Rust, Bun, pnpm, uv, Ollama, Qdrant, Claude Code | Go 1.23, Rust stable, rest latest | see profiles below |
| VS Code, Cursor | whatever the vendor ships | Microsoft and Cursor apt repos |

Tested on Ubuntu 24.04.4 LTS, 4-core AMD EPYC, 7.8 GiB RAM, KVM.

## Using the picker

Type to search. `←` and `→` move between categories, or click a tab. `TAB` checks the row you're on. `Enter` installs what's checked; `Esc` cancels.

Eleven tools are checked when you start — the sensible default set. Uncheck anything you don't want.

**Profiles** are shortcuts, shown with a `◆`. Checking one checks its tools, and you can still uncheck any of them individually.

| Profile | Gets you |
|---|---|
| `default` | the eleven pre-checked tools |
| `go` | go, golangci-lint, air |
| `rust` | rust via rustup |
| `fe` | bun, pnpm, biome, vite |
| `be` | postgres-client, redis-tools |
| `python-ai` | uv, jupyter, ollama |
| `ai-agents` | opencode, claude-code |
| `full-stack-web` | fe + be + docker + chrome + node |

**Some tools need others.** Check `jupyter` and you'll see `pip` appear with a `[+]` — it's being added because jupyter needs it, and the panel tells you so. You can `TAB` that row to decline it, and jupyter will be skipped rather than installed broken. Your decision is saved, so `--replay` won't quietly add it back later.

Your picks are saved to `~/.config/dev-setup/config.json`. Re-run with `--replay` to install the same set again.

## What it does to your machine

Two things happen without asking, so they're worth knowing up front.

**Your `PATH` changes.** The script writes `/etc/profile.d/dev-setup.sh` with the entries it owns — Go, Go-installed binaries like `air`, and opencode. Tools with their own installers (Node via nvm, bun, uv, rust) add their own lines to your `~/.bashrc`. Either way you need a new login shell before the tools are on your `PATH`.

**Picking `docker` adds you to the `docker` group.** That group is effectively root — anyone in it can start a container that mounts your whole filesystem. The run says so when it does it, and it takes effect at your next login.

Nothing is ever uninstalled. Unchecking a tool you already have does not remove it.

## Command line

```bash
sudo ./setup.sh --yes --no-auth                   # the default eleven
sudo ./setup.sh --profile=go,rust --no-auth       # one or more profiles
sudo ./setup.sh --all --no-auth                   # everything
sudo ./setup.sh --search=postgres --no-auth       # one tool by name
sudo ./setup.sh --replay --no-auth                # whatever you picked last time
sudo ./setup.sh --dry-run --profile=go            # show me, don't install
sudo ./setup.sh --list-profiles
sudo ./setup.sh --list-tools
sudo ./setup.sh --help
```

`--no-auth` skips the `gh auth login` prompt at the end. That prompt only appears if you picked `gh`, and it always runs last so it can't block anything.

`--dry-run` installs nothing and needs no root. It runs the real picker and draws the real progress screen against simulated work, so you can see exactly what a run would do first.

## While it runs

On a terminal you get a live screen: one cell per install step, a spinner on whichever is running, and its last couple of lines of output. Everything else goes to `setup.log` rather than scrolling past you.

**One failure doesn't stop the run.** A broken apt repository costs you that tool, not the other twenty. At the end you get a summary like `10 install steps: 7 done, 1 already installed, 1 skipped, 1 failed`, with a line explaining each failure. The script exits non-zero if anything failed, so CI won't mistake a half-installed machine for a good one.

Piped or in CI there's no screen — just plain lines you can grep:

```bash
grep '^\[STEP\]' setup.log
```

## Handy afterwards

```bash
# Exa with your own API key, for higher limits
opencode mcp remove exa
opencode mcp add exa --url "https://mcp.exa.ai/mcp?exaApiKey=$EXA_API_KEY"

# A different Node version
export NVM_DIR="$HOME/.nvm"; . "$NVM_DIR/nvm.sh"; nvm install 22; nvm alias default 22

# See what you picked last time
cat ~/.config/dev-setup/config.json
```

## Tests

```bash
./test/run.sh                 # everything
./test/run.sh test/tui.bats   # one file
```

Uses [bats](https://github.com/bats-core/bats-core) from your `PATH` if you have it, otherwise it clones a pinned copy into `.cache/` on first run. Nothing to install beyond git. CI runs the same script plus `bash -n` and `shellcheck`.

## How it works

If you want to know why the script is built the way it is — what an Install Step is, why the progress screen reads a plain-text stream, why a declined prerequisite is treated as a choice — that's written down separately:

- [`CONTEXT.md`](CONTEXT.md) — the vocabulary, and the decisions behind it
- [`docs/adr/`](docs/adr/) — one file per architectural decision, with the alternatives that were rejected
- [`docs/spec-interactive.md`](docs/spec-interactive.md) — the picker's specification

## License

MIT — see [LICENSE](LICENSE).
