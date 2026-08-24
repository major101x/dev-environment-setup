# fzf with a version floor replaces gum for the TUI

The TUI needs a tab strip that shows which tab is active, left/right arrow and
mouse navigation between tabs, and a bordered, padded search input. `gum filter`
can express none of these: it has no `--border`, no `--padding`, and no
key-binding flag at all. Its `--header` is a static string, which is why the
"tabs" in the previous implementation could never highlight, respond to arrows,
or be clicked — they were a printed label, not a widget. fzf supports all three
(`--input-border`, `--bind left/right/click-header`, `transform-header` +
`reload`), so fzf becomes the TUI, and gum is removed entirely.

This supersedes the earlier "`gum`/`fzf` required — gum primary, fzf fallback"
decision, which is recorded as falsified in `CONTEXT.md`.

## The version floor is the load-bearing part

`--input-border` and the `click-header` binding do not exist in older fzf.
Ubuntu 24.04's `apt install fzf` gives **0.44.1**, which has neither — verified
directly against both binaries:

| | 0.44.1 (apt) | 0.74.3 |
|---|---|---|
| `--input-border` | missing | present |
| `--header-border` | missing | present |
| `click-header` bind | rejected | accepted |

So `ensure_fzf` **capability-checks rather than existence-checks**: it probes for
`--input-border` and attempts a `click-header` bind before accepting a binary,
and installs 0.74.3 from GitHub releases otherwise. The previous `ensure_gum`
did `command -v fzf >/dev/null && return 0`, which would accept 0.44.1 and hand
the user the broken UI with no error. An existence check is the bug here, not a
simplification of the version check.

## Consequences

`apt install fzf` alone is not sufficient to run the TUI, so the installer
carries its own pinned fzf. It lands in `/usr/local/bin` when running as root,
and in `${XDG_CACHE_HOME:-~/.cache}/dev-setup/fzf` otherwise — cached, so
repeat runs do not re-download.

`--dry-run` fetches fzf too. fzf is the *picker's own dependency*, not one of
the Tools being simulated, so guarding it behind the dry-run check made
`--dry-run` unable to show the TUI — the main thing you would dry-run to see.
Because the dry-run copy goes to the user cache and never a system path, the
documented "no root required" property is preserved.

`--placeholder` is a gum flag with no fzf counterpart; fzf's equivalent is
`--ghost`. A mechanical flag-for-flag port would fail at runtime.
