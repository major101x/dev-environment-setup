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
- **Label** is every Tool that step delivers, comma-separated — a property of the
  installer, not of the checkboxes. Selecting `eza` alone still labels its step
  `pip, eza`, because `install_pip_eza` lays down both either way; a label naming only
  the picked Tool would understate what lands on the machine.
- **Tools with no Install Step** (`claude-code`) are not silently dropped. They resolve to
  no step and are reported by name — `No Install Step for tool: claude-code`.

`--dry-run` prints the resolution and stops: any stepless Tools first, then one
`Install Step: <fn> -> <tools>` line per step in run order. That is what makes
resolution inspectable without installing anything. The stepless report comes first on
both paths, so it is named before the run rather than among its failures. The headline
counts Install Steps, not Tools: a selected Tool with no step is not a Tool that would be
installed.

### Lifecycle

An Install Step reports every state change as one plain-text transition on stdout:

```
[STEP] <install step> | <state>[ | <detail>]
```

The states are ADR-0005's seven. `queued` → `downloading` → `installing` → `done` on the way
through, plus `already installed`, `skipped` and `failed`. Fields are `|`-separated because two
of the states contain a space; the state field is one of exactly seven strings, and anything
that varies per run — the unmet dependency a skip names, the exit status a failure carries — is
detail. See [ADR-0011](adr/0011-the-lifecycle-is-a-plain-text-transition-stream.md).

- **Every planned Step is `queued`** before the first one runs, so "how much is left" has an
  answer from the start.
- **`downloading` is not universal.** Only the three Install Steps with a separable download
  open in it — Go's tarball, Qdrant's image pull, Puppeteer's browser fetch. The other Tools are
  apt-fused or `curl | bash`, where the download is not a phase anyone can point at.
- **`already installed`** is decided before the Step runs, by a table of read-only presence
  probes — one per Tool, no network, nothing a `--dry-run` may not do. A Step is already
  installed only when *every* Tool it delivers is: `install_pip_eza` with `pip` present and
  `eza` missing still has work. The Step is still called (it is idempotent and skips its own
  work); its phases are muted so the stream cannot contradict the state.
- **`skipped`** names the prerequisite that will not be there: `unmet dependency: node`. A
  prerequisite is met when the Tool is on the machine already, or when the Step that delivers it
  has run and landed — so a failure cascades into skips rather than into several unexplained
  failures. Prerequisites are declared per Step (`STEP_REQUIRES`), and resolution closes the
  Toolset over them: a prerequisite that is neither picked nor already on the machine is added,
  and announced on its own line naming the pick that pulled it in. So a skip is what is left when
  that cannot work — a prerequisite that was planned and failed, or one no Install Step delivers.
  A cyclic declaration is rejected by name before anything is planned. See ADR-0014.
- **`failed`** carries the exit status. The Step runs as `set +e; ( set -e; "$step" ); set -e`,
  so errexit still applies inside it and it stops at its own first failing command. The *run*
  does not stop: the Step is marked `failed` and the next one starts (ADR-0006), because the
  Steps are independent and one broken apt repository should not cost the rest of the Toolset.

`--dry-run` drives this same state machine against Install Steps that do nothing — the same
probes, the same dependency gate, the same emitter, with a sleep where the installer's runtime
would be (`DEV_SETUP_SIM_DELAY` overrides it; it is zero when stdout is not a TTY, because there
is no screen to animate). The one thing a dry run cannot find out is what would break, so
`--simulate-fail=<step>[,<step>]` supplies it, and is refused outside `--dry-run`. A dry run past
an injected failure shows exactly what a real run does past a real one: the remaining Steps, the
skips cascading from it, the same summary, and the same non-zero exit status.

### The end of the run

A run that carries on past a failure has scrolled its errors away by the time it ends, so the two
things that make ADR-0006 safe come last: after the run's work — including the trailing
Verification block, which #25 deletes — and before anything reads stdin, because nothing may push
the summary off the screen and `gh auth login` is where the run starts reading stdin:

- **A summary.** One counts line — `9 install steps: 6 done, 1 already installed, 1 skipped, 1
  failed` — then one line per failed Step, labelled with the Tools it delivers and the detail its
  `failed` transition carried: `Failed: install_go (go, golangci-lint, air) - exit 2`.
- **An exit status.** A run holding any failed Install Step exits 1; a run of nothing but `done`,
  `already installed` and `skipped` exits 0. A skip is not a failure — nothing broke, and the
  Step's own line already names the prerequisite. CI reads the status and nothing else, so this
  is the consequence ADR-0006 turns on.

Colour is emitted only when stdout is a TTY. A consumer reading the transition stream off a pipe
does not have to strip escape sequences to read a field, and the log stops carrying them for
nobody.

### The install screen's renderer

One frame of the install screen is a pure function of a **snapshot** and a terminal size —
`setup.sh __render WIDTH HEIGHT < snapshot` writes exactly one frame to stdout and does nothing
else: no run, no log, no clock, no terminal. The live screen (#22) fills the same snapshot in
from the transition stream and calls the same function; the subcommand is how the tests assert an
exact frame with no timing in it (#21). It is dispatched before `main`, like the fzf callbacks,
so it cannot open the log.

A snapshot is one `<kind> | <fields>` line per item, delimited the way the stream is:

```
elapsed | 1:47                         how long the run has been going
active | 0:12                          how long the Step in flight has
tick | 2                               which spinner glyph to show
final                                  the finalised frame, not a live one
step | <label> | <state>[ | <detail>]  one Install Step, in run order
tail | <line>                          a line the Step above said
```

A line the renderer does not understand is refused with an exit status, not skipped: a frame
that quietly dropped a line would look complete.

The layout is [ADR-0007](adr/0007-the-install-screen-is-a-grid-of-every-install-step.md)'s: a
bordered box holding a counts line, a column-major grid with one cell per Install Step, the Step
in flight with a spinner, its elapsed time and the last two lines it said, then a failure board —
every failed Step with the tail of its output, then every skipped Step with what it needed. Each
of the seven states has a glyph and a colour of its own (`·` queued, a braille spinner in flight,
`✔` done, `=` already installed in blue, `⊘` skipped, `✘` failed). Rows truncate with `…` and
never wrap; the column count falls as the terminal narrows. A live frame is padded to exactly the
terminal height, because it is repainted in place; the finalised frame is neither padded nor
capped, so every cell has room for its detail — a version, once #19 reports one — and the failure
board is never cut off. A live board that runs out of room counts what it dropped rather than
stopping quietly.

### The install screen

On a terminal the run draws the screen live, from the first Install Step to the last (#22). The
screen is a reader on the other end of the transition stream, in a process of its own: the run's
fd 3 is moved onto a pipe to it, it keeps a snapshot, repaints on every transition and on a timer
for the spinner, and finalises when the run says the stream is over. The run waits for that before
it prints the summary beneath the frame and before anything reads stdin — `gh auth login` cannot
share a terminal with a repaint loop. See
[ADR-0013](adr/0013-the-install-screen-reads-the-stream.md).

- **Up when stdout is a terminal** — under `--profile=go` on a laptop as much as after the picker
  — and only when the log is open, because an Install Step's output has to have somewhere else to
  go. Piped, in CI, or without a log, the run is the plain lines above, unchanged.
- **While it is up, narration goes to the log alone.** The plan, the stepless report and the base
  deps are said before it goes up; the summary after it comes down.
- **Tails are read off the log.** The Step in flight shows its last two lines; a failed Step keeps
  its last three on the board. Both come from the Step's section in the log, found by the
  section's own markers. A dry run has no sections and shows no tails.
- **`--dry-run` draws the real screen** against simulated Install Steps and installs nothing.
- **The finalised frame stays in scrollback**, as ordinary output: no alternate screen buffer.



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
./setup.sh --simulate-fail=install_go  # with --dry-run: report that Step failed, exit 1
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
them are dispatched before `parse_args` — and so before `main`, which is the only
thing that opens the log. That is what keeps their stdout going back to fzf: under
the old blanket `exec > >(tee -a "$LOG_FILE")` redirect a callback that did not opt
out by hand wrote its render to the log instead, and the TUI came up empty with no
error (ADR-0012).

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

- `test/lifecycle.bats` — the Install Step lifecycle through the `--dry-run` process
  boundary: the queue announced before the first Step runs, the happy path, `downloading` only
  where a Step has one, `already installed` off the presence probes, `skipped` naming its unmet
  dependency, `failed` and the cascade of skips it causes, all seven states reachable in one dry
  run, and a dry run that emits no escape sequences and runs no verification commands. Presence
  is forced per Tool in a patched copy of the script, so a test never depends on what happens to
  be installed on the machine running it.
- `test/failure.bats` — what a failure costs the run (ADR-0006), through the same boundary: a
  failing Step does not stop the ones after it and every planned Step still reaches a terminal
  state, several failures in one run all report, the summary names each failed Step with its
  Tools and reason, its counts cover every terminal state and add up to the plan, and the exit
  status is non-zero for one failure or many while a run of `done`, `already installed` and
  `skipped` exits 0.
- `test/log.bats` — the log (ADR-0012). Through `--dry-run` for what a run writes about
  itself: its narration and every transition reach the log, in stream order, in plain text
  and once each. Through a *real* run for capture, because a dry run calls no installer and
  so has no output to capture: an Install Step's stdout and stderr land in a section that
  names the Step and its exit status, a successful Step's output is kept as well as a
  failing one's, a phase the Step reports lands in its section *and* in the stream, a
  subcommand still returns its output to its caller, each Step gets its own section in run
  order, a `skipped` Step gets none, and none of it reaches the terminal. One assertion
  runs under a pty (`script -qec`), the only way to make the run believe it has a terminal
  and colour what it prints: the log stays plain even then, and the pty's own output is
  checked for colour so the assertion cannot pass for want of any. A run whose log cannot
  be written warns and installs anyway. The real run is a patched copy: the root check, the
  apt base deps, verification and every Install Step are stubbed — blanket, so a Step name
  left unstubbed by an oversight cannot curl an installer onto the machine running the
  suite — and the test overrides the one Step it is about. How a Step is *run* is not
  patched, which is the part under test.
- `test/render.bats` — the renderer (#21), through `__render`: one frame per snapshot, byte-
  identical however the environment is set, with nothing written to the log; a line that is
  not a snapshot line, a state outside the seven, or a size that is not a size all refused;
  every lifecycle state with its own glyph and colour; the active row's spinner turning with
  the tick and carrying its elapsed time; rows truncated and never wrapped, with every box
  line exactly a column narrower than the terminal at 40, 52, 80 and 120; a live frame
  padded to the terminal; all 22 Install Steps of `--all` on screen at 80×24; a failed
  Step's tail and a skipped Step's reason on the board, and a board out of room counting
  what it dropped; the finalised frame running past the terminal with its counts, every
  failure named and its exit-status line present only when something failed. The frames
  under `test/fixtures/render/` are asserted exactly, colour stripped: a layout change is a
  fixture change, made on purpose.
- `test/screen.bats` — the live screen (#22), under a pseudo-terminal (`script -qec`, size
  pinned through `COLUMNS`/`LINES`), asserting only the finalised state: a dry run and a real
  run on a terminal draw the screen, and a piped run prints plain lines; a dry run draws the
  real screen and writes nothing; the screen finalises in place with its counts and the summary
  is printed beneath its bottom border; the finalised frame is what is left after the last
  repaint; one end-to-end smoke test drives `--dry-run --simulate-fail` under the pty and
  checks the finalised box against the pure renderer's frame for the same snapshot, elapsed
  time masked; a failed Step's last three lines are on the board; narration during the run
  reaches the log and not the terminal, and still reaches a piped run's output; every
  transition reaches the log while the screen is up; a stubbed `gh auth login` reading stdin
  through the pty runs beneath the finalised frame, after the cursor is handed back, with no
  frame painted after it; and a run whose log cannot be written stays plain even on a terminal.
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
  half is the real guard on the redirect regression — `tee` forwarded to the
  original stdout too, so non-emptiness alone can pass while the TUI renders
  empty; the redirect is gone per ADR-0012, and the assertion now guards the
  rule that replaced it — only a run opens the log). Every `__tui_preview`
  assertion requires the Selected Toolset panel to
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
