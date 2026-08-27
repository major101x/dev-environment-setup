# Spec: Interactive setup TUI

## Context
Repo `dev-environment-setup` currently runs a fixed `setup.sh` that installs the Default Toolset (9 tools). Grill answers (2026-08-23) require it to become interactive: any dev type (full-stack, fe, be, Go, Rust, Python AI, AI agents) can pick exactly what they need, with search, categories, recommended Profiles, and persistence.

## Goal
`./setup.sh` with no args launches a TUI that:
- shows Categories (`Languages`, `Frontend`, `Backend/DB`, `AI/ML`, `Infra/DevOps`) with collapsible multi-select
- supports live fuzzy search across name/description/category (`fzf`)
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
| `c-build` | Languages | `apt install cmake pkg-config` | gcc/make already come from base deps — see ADR-0001 |

Existing tools keep their current install functions; new tools add `install_<key>()` functions.

## Flags (non-interactive)

```
./setup.sh                          # interactive TUI (requires fzf >= 0.60, auto-installs if missing/too old)
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

## TUI flow (fzf)

Single screen, not a wizard. See [ADR-0002](adr/0002-fzf-with-a-version-floor-replaces-gum.md).

1. `ensure_fzf()` — **capability-check, not existence-check**: probe the binary for
   `--input-border` and attempt a `click-header` bind. `apt install fzf` gives 0.44.1,
   which has neither, so `command -v fzf` is not a sufficient test. If the check fails,
   download fzf 0.74.3 from GitHub releases to `/usr/local/bin/fzf` when root, else to
   `${XDG_CACHE_HOME:-~/.cache}/dev-setup/fzf` (cached across runs). `--dry-run` fetches
   it too — fzf is the picker's dependency, not a simulated Tool, and the cache path keeps
   "no root required" true. Never fall back to a hand-rolled bash TUI.
2. One list holds both Profiles and Tools, each row carrying a marker: `◆` Profile,
   `·` Tool. The marker is the parser's source of truth for the row's type — see
   [ADR-0003](adr/0003-tui-item-type-comes-from-the-marker-glyph.md).
3. Horizontal tab strip over Categories: `All · Languages · Frontend · Backend/DB ·
   AI/ML · Infra/DevOps`. Profiles head the All tab and appear on no other: a Profile
   row is a macro that stamps its member Tools (step 6), so it can only sit on a list
   that holds them — see [ADR-0009](adr/0009-a-profile-row-is-a-macro-that-stamps-its-tools.md).
   The active tab is highlighted. `←`/`→` and
   `click-header` switch tabs, each rebuilding the strip (`transform-header`) and the
   list (`reload`) via `setup.sh __tui_*` callbacks.
4. Search input sits below the list with `--input-border=rounded` and padding.
   `TAB` toggles a row — bound to a `transform` so a `◆` row can stamp (step 6) —
   `ctrl-a` toggles all, `ENTER` confirms. The Default Toolset is
   pre-checked at startup via a `start:` binding of `pos(N)+select` pairs built from the
   unfiltered list, and every pre-checked Tool stays individually uncheckable.
5. Preview pane shows the row's detail (a Profile's expansion, or a Tool's category
   and which Profiles contain it) above a live **Selected Toolset** panel — the
   resolved, deduplicated install list, refreshed on every toggle. It reads
   `FZF_SELECT_COUNT` to decide whether anything is selected — `{+}` alone cannot tell,
   because fzf falls back to the *current* item when the selection is empty.
   This panel replaces HEAD's step 5 (`gum style` count + `gum confirm "Install X tools?"`):
   a live summary that is always visible is strictly more informative than a count shown
   once at the end, and ENTER on the picker is the confirm.
6. Toggling a `◆` row stamps its member Tools into the selection, and the checked
   Tools are the only thing that resolves to an install; the Profile row itself stays
   selected as a label, written to `config.json` for provenance and ignored by
   resolution. The stamp is one-way, and fires only when it can fire completely —
   empty query, and the current list holds every member — because `pos(N)` indexes the
   *matched* list and clamps silently. A Profile that did not stamp is still expanded
   at ENTER; a stamped one is not, or it would resurrect what the user unchecked.
   Empty selection falls back to the Default Toolset. See
   [ADR-0009](adr/0009-a-profile-row-is-a-macro-that-stamps-its-tools.md).
7. Prompt `Include toolchain PATH setup in ~/.bashrc?` (per grill #6), plain `read`.
8. Persist: write `~/.config/dev-setup/config.json` (`{profiles:[], tools:[], toolchain:bool}`).
9. Execute install functions in dependency order (base → node-dependent → docker-dependent).

CI flags skip steps 1-8 and go straight to 9.

### Callback re-entrancy

fzf re-invokes `setup.sh` for `__tui_list`, `__tui_header`, `__tui_preview`,
`__tui_tab` and `__tui_click`. These are dispatched before `parse_args`, and they
**must skip the `exec > >(tee -a "$LOG_FILE")` redirect** at the top of the script —
otherwise their stdout goes to the log instead of back to fzf and the TUI renders
empty.

They also split on whether they need `TUI_STATE`, the state directory the picker
exports. The three render callbacks degrade to defaults without it — a bare
`setup.sh __tui_list` or `__tui_header` still prints tab 0. `__tui_tab` and
`__tui_click` exist to *write* that directory, so with no `TUI_STATE` they say so
on stderr and exit 1 rather than resolving `"$TUI_STATE/tab"` to `/tab`, which as
root writes a file at the filesystem root.

## Persistence

- Path `~/.config/dev-setup/config.json` (XDG). Auto-created on every interactive run.
- `--replay` loads it; if missing error.
- `setup.sh --yes` also writes it (so replay reflects last CI run).

## Non-goals

- No uninstall on un-check (idempotent only adds).
- No custom bash TUI if fzf is missing or cannot be installed.
- No version pinning beyond LTS (user can edit config.json for pin).

## Verification

Run `./test/run.sh`. It uses `bats` from `PATH` and otherwise fetches the
bats-core version it pins into `.cache/` (gitignored) with `git clone`, so a
fresh clone needs no test tooling installed beyond git and one-off network
access. `.github/workflows/ci.yml` runs the same script on every push to `main`
and every PR — deliberately without an apt `bats`, so CI exercises the same
pinned fetch a fresh clone does — plus `bash -n` on each shell file and
`shellcheck -S warning`, which is this section's long-standing "shellcheck
info-level only" bar expressed as a gate: warnings and errors fail, info and
style findings do not.

- `test/cli.bats` — the non-interactive surface. `--help`, `--list-profiles`,
  `--list-tools`, `--yes`, `--profile=`, `--all`, `--search=` and a bare
  no-TTY run all exit 0 and resolve the Toolset the registry says they should;
  `--search` with no match, `--replay` with no saved config, and an unknown flag
  all exit 1. `--dry-run` writes nothing to `/usr/local/bin`, writes no
  `config.json`, and never reaches `gh auth login`.
- `test/tui.bats` — the fzf callbacks, which are the only part of the picker
  testable without a tty. `__tui_list`, `__tui_header` and `__tui_preview`
  return non-empty on stdout **and write nothing to the log file** (the second
  half is the real guard on the tee-redirect regression — `tee` forwards to the
  original stdout too, so non-emptiness alone can pass while the TUI renders
  empty). Every `__tui_preview` assertion requires the Selected Toolset panel to
  reach its closing border, which is the guard on a bare `(( ))` aborting a
  callback mid-render under `set -e` — note *bare*: bash exempts a false `(( ))`
  that is the non-final command of an `&&` list, so `(( w < 24 )) && w=24` is
  not the hazard. A preview width below the panel's 24-column floor is covered
  as its own branch. With `TUI_STATE` unset, `__tui_list` and `__tui_header`
  emit no stderr and write nothing to `/`, while `__tui_tab` and `__tui_click`
  exit non-zero naming `TUI_STATE`. The
  **Profile** `go` row resolves to 3 tools and the **Tool** `go` row to 1, and
  that 1 is `go` itself (ADR-0003). The panel says
  "nothing selected" at `FZF_SELECT_COUNT=0`. `__tui_tab` and `__tui_click`
  move the tab, and `__tui_list` follows it.

Not covered by the harness, because fzf reads `/dev/tty` and cannot be driven by
piped stdin: the picker itself. Interactive smoke stays manual — capable fzf
present → picker returns non-empty, saved config exists. A `script -qec` pty
wrapper could reach a little further if that ever proves worth it. See
[ADR-0008](adr/0008-the-fzf-callbacks-are-the-test-seam.md) for why the
callbacks are the seam, and why each assertion was checked against a mutated
`setup.sh` that reintroduces the bug it guards.
