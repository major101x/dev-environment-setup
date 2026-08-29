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

The Tools column holds Tool keys and nothing else, so it can be checked against
`./setup.sh --list-profiles`; anything that is not a key belongs in Notes. `+` appears in
exactly one row, because composition is that one alias's mechanism — see ADR-0001.

| Profile | Tools (keys) | Notes |
|---|---|---|
| `default` | gh, fastfetch, opencode, node, puppeteer, chrome, docker, pip, eza, exa-mcp, pocock-skills | the Default Toolset, pre-checked when no Profile is chosen |
| `go` | go, golangci-lint, air | Go 1.23 LTS |
| `rust` | rust | stable toolchain, installed via `rustup`; `cargo` comes with it |
| `fe` | bun, pnpm, biome, vite | |
| `be` | postgres-client, redis-tools | |
| `python-ai` | uv, jupyter, ollama | |
| `ai-agents` | uv, jupyter, ollama, qdrant, exa-mcp, opencode, claude-code | restates `python-ai`'s Tools rather than composing them, on purpose (ADR-0001). `qdrant` runs as a docker image. `claude-code` has no Install Step, so the Profile delivers nothing for it — resolution says so by name rather than dropping it, and the open question in `CONTEXT.md` is still whether it should get one |
| `full-stack-web` | fe + be + docker + chrome + node | the one composite alias: resolved from `fe` and `be` rather than owning a Tool list, deduplicated, so a Tool added to either reaches it — see [ADR-0001](adr/0001-full-stack-web-is-a-composite-alias.md) |

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
| `postgres-client` | Backend/DB | `apt` | |
| `redis-tools` | Backend/DB | `apt` | |
| `c-build` | Languages | `apt install cmake pkg-config` | gcc/make already come from base deps — see ADR-0001 |

Existing tools keep their current install functions; new tools add `install_<key>()` functions.

## Install Steps

The selected Toolset resolves into an ordered list of **Install Steps** before any
installing happens. `TOOL_INSTALL_STEP` maps each Tool to the function that delivers it,
many-to-one (ADR-0004): `install_go` delivers `go`, `golangci-lint` and `air`;
`install_node_and_puppeteer` delivers `node` and `puppeteer`; `install_pip_eza` delivers
`pip` and `eza`. Everything that runs or reports a run reads that one resolution, so the
plan a dry run prints is the plan a real run executes.

- **Order** is the Tool registry's order (`ORDERED_TOOLS`, the picker's order too). A step
  lands at the position of the first selected Tool that pulls it in, and is not repeated.
- **Label** is the Tools *the user selected* that route to that step, comma-separated.
  Selecting `node` alone labels the step `node` even though it also lays down Puppeteer:
  the label connects what was picked to what is running.
- **Tools with no Install Step** (`claude-code`) are not silently dropped. They resolve to
  no step and are reported by name — `No Install Step for tool: claude-code`.

`--dry-run` prints the resolution and stops: one `Install Step: <fn> -> <tools>` line per
step, in run order, then any stepless Tools. That is what makes resolution inspectable
without installing anything.

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
   [ADR-0003](adr/0003-tui-item-type-comes-from-the-marker-glyph.md). A check marker
   sits in front of it — `[x] ◆ go`, `[ ] · air` — painted from `TUI_STATE`, which
   holds the checked Tools and the toggled Profile keys. fzf's own selection goes
   unused: a `reload` clears it and the tab strip reloads. The glyph still types the
   row, one field to the right. See
   [ADR-0010](adr/0010-the-list-is-the-source-of-truth-for-a-check.md).
3. Horizontal tab strip over Categories: `All · Languages · Frontend · Backend/DB ·
   AI/ML · Infra/DevOps`. Profiles head the All tab and appear on no other: a Profile
   row is a macro that checks its member Tools (step 6), so it can only sit on a list
   that holds them — see [ADR-0009](adr/0009-a-profile-row-is-a-macro-that-stamps-its-tools.md).
   The active tab is highlighted. `←`/`→` and
   `click-header` switch tabs, each clearing the query and rebuilding the strip
   (`transform-header`) and the list (`reload`) via `setup.sh __tui_*` callbacks.
   Checks survive the switch, because nothing depends on fzf holding them.
4. Search input sits below the list with `--input-border=rounded` and padding.
   `TAB` records the toggle into `TUI_STATE` (`execute-silent`) and redraws the list
   (`reload`); the cursor does not move. `ENTER` installs exactly the checked set, an
   empty set installs nothing and says so, and `ESC` cancels — `--yes` is the
   deliberate way to ask for the Default Toolset. There is no `--multi` and no
   check-everything key: fzf's marker has nothing to mark, and one keystroke that
   checks every row is an unbounded blast radius with no undo. The Default Toolset is
   seeded into the state once, before fzf starts, and never reapplied, so every
   pre-checked Tool stays individually uncheckable.
5. Preview pane shows the row's detail (a Profile's expansion, or a Tool's category
   and which Profiles contain it) above a live **Selected Toolset** panel — the
   checked install list, refreshed on every toggle. It reads `TUI_STATE`, so what is
   on the screen and what will install are the same thing read from one place.
   This panel replaces HEAD's step 5 (`gum style` count + `gum confirm "Install X tools?"`):
   a live summary that is always visible is strictly more informative than a count shown
   once at the end, and ENTER on the picker is the confirm.
6. Toggling a `◆` row checks its member Tools in the state, and the checked Tools
   are the only thing that resolves to an install; the Profile key itself is recorded
   as a label, written to `config.json` for provenance and ignored by resolution.
   Nothing is expanded at ENTER, so a member the user unchecked stays unchecked. The
   macro is one-way: toggling the row again drops the label and not the Tools, because
   the alternative needs per-Tool provenance to answer a question nobody asked. It
   fires the same way with a query active — no position is computed, so there is
   nothing to index against a filtered list. See
   [ADR-0009](adr/0009-a-profile-row-is-a-macro-that-stamps-its-tools.md) and
   [ADR-0010](adr/0010-the-list-is-the-source-of-truth-for-a-check.md).
7. Prompt `Include toolchain PATH setup in ~/.bashrc?` (per grill #6), plain `read`.
8. Persist: write `~/.config/dev-setup/config.json` (`{profiles:[], tools:[], toolchain:bool}`).
9. Execute install functions in dependency order (base → node-dependent → docker-dependent).

CI flags skip steps 1-8 and go straight to 9.

### Callback re-entrancy

fzf re-invokes `setup.sh` for `__tui_list`, `__tui_header`, `__tui_preview`,
`__tui_tab`, `__tui_click` and `__tui_toggle`. `__tui_seed` and `__tui_resolve` are
not fzf callbacks — they are the two ends of a picker run, and carry the same prefix
so bats can drive what the picker itself cannot be driven through (ADR-0008). All of
them are dispatched before `parse_args`, and they
**must skip the `exec > >(tee -a "$LOG_FILE")` redirect** at the top of the script —
otherwise their stdout goes to the log instead of back to fzf and the TUI renders
empty.

They also split on whether they need `TUI_STATE`, the state directory the picker
exports. The three render callbacks degrade to defaults without it — a bare
`setup.sh __tui_list` or `__tui_header` still prints tab 0. `__tui_tab`,
`__tui_click`, `__tui_toggle`, `__tui_seed` and `__tui_resolve` exist to *write* or
*read* that directory, so with no `TUI_STATE` they say so on stderr and exit 1 rather
than resolving `"$TUI_STATE/tab"` to `/tab`, which as root writes a file at the
filesystem root.

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
  `config.json`, and never reaches `gh auth login`. Resolution into Install Steps
  is asserted here too, through that same `--dry-run` boundary rather than by
  calling shell functions: step count, per-step labels, run order, and the named
  report for a Tool no step delivers.
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
  emit no stderr and write nothing to `/`, while `__tui_tab`, `__tui_click` and
  `__tui_toggle` exit non-zero naming `TUI_STATE`. A `[x]`/`[ ]` marker in front
  of the type glyph does not stop it typing the row: the **Profile** `go` row
  still previews as a Profile and the **Tool** `go` row as a Tool (ADR-0003).
  `__tui_tab` and `__tui_click` move the tab, and `__tui_list` follows it.

  For ADR-0010: `__tui_seed` checks exactly the 11 Tools of the Default Toolset
  and leaves no Profile label; a seeded Tool unchecks and stays unchecked;
  `__tui_toggle` checks and unchecks a Tool row, fires a `◆` row's members, and
  drops only the label when un-toggled; the same toggle records the same check
  with a query active. Checks survive both tab-switch paths — the bug the
  decision exists to kill. The Selected Toolset panel counts `TUI_STATE`
  rather than the hovered row, says "nothing checked yet" when the checked set
  is empty, and still names the Profile labels there. `__tui_resolve` returns
  exactly the state set, expands nothing, and resolves an empty state to no
  Tools at all. Three assertions read `setup.sh` with its comments stripped,
  because the deletions are the decision: no `pos(`, no `--multi`, `ctrl-a` or
  `toggle-all`, no `+down` or `transform` on the `TAB` binding, `clear-query` on
  all three tab bindings, and no Default Toolset fallback left on the
  interactive path.

Not covered by the harness, because fzf reads `/dev/tty` and cannot be driven by
piped stdin: the picker itself. Interactive smoke stays manual — capable fzf
present → picker returns non-empty, saved config exists. A `script -qec` pty
wrapper could reach a little further if that ever proves worth it. See
[ADR-0008](adr/0008-the-fzf-callbacks-are-the-test-seam.md) for why the
callbacks are the seam, and why each assertion was checked against a mutated
`setup.sh` that reintroduces the bug it guards.
