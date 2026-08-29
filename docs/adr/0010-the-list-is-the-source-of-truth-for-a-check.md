# The list is the source of truth for a check

Supersedes [ADR-0009](0009-a-profile-row-is-a-macro-that-stamps-its-tools.md) in part.

A check in the picker means "install this Tool". It lives, today, in fzf's selection — and fzf's
selection is not ours to keep. A `reload` clears it, and the Category tab strip reloads on every
switch. So checking six Tools and clicking `Frontend` throws all six away, silently, and `ENTER`
then falls through to the Default Toolset.

ADR-0009 built the Profile stamp on the belief that selections survive a reload. They do not, and
that ADR now carries the correction struck through. Patching around it has already cost two
mechanisms — `tui_forget_stamps`, and the complete-or-label rule — that exist only because fzf's
selection is both authoritative and out of our hands.

**So it stops being authoritative.** `TUI_STATE` holds the checked Tools; `tui_list` paints the
marker; fzf's selection goes unused. Every interaction records into the state and redraws from it.
What is on the screen and what will be installed are the same thing, read from one place.

## What this deletes

The point of the decision is subtraction, not addition:

- **All `pos(N)` arithmetic.** No matched-list indexing, no silent clamping, no positions computed
  against a list the user has since filtered. The class of bug ADR-0009 spent its length reasoning
  about stops existing.
- **The complete-or-label rule**, and with it ADR-0009's known trade-off: unchecking a member of a
  Profile now works while a query is active, which it could not before.
- **The stamped/unstamped distinction**, and `tui_forget_stamps` with it. Every toggle of a `◆` row
  fires, so there is no unstamped Profile in the state to expand at ENTER.
- **The startup race.** The Default Toolset is seeded into the state before fzf starts, rather than
  raced in by a `start:` binding that fires before the list is read.
- **`--multi` and `ctrl-a`.** fzf's marker has nothing left to mark, and a single keystroke that
  checks every row is an unbounded blast radius with no undo — worse as the Tool registry grows.
- **The `"No tools selected - using Default Toolset"` fallback, on the interactive path.** It has
  produced a silent wrong install twice.

## The rules

**A check is a line in `TUI_STATE`.** Two sets: the checked Tools, and the Profile keys the user
toggled. The Tools resolve to installs. The Profile keys are provenance, written to `config.json` so
`--replay` stays honest, and ignored at resolution — unchanged from ADR-0009.

**Every interaction is record-then-reload.** `TAB` records and redraws. A tab switch clears the
query, records nothing, and redraws. Checks survive both, because nothing depends on fzf holding
them.

**The cursor does not move on `TAB`.** This is also how the picker stops walking backwards: the old
`tab:toggle+down` never advanced, because `down` in fzf's default layout moves toward row 1 and
clamps there. Removing the movement removes the bug, and no layout change is needed.

**The Default Toolset is seeded once**, before the picker opens, and never reapplied. "Presets, not
locks" is false if the preset reapplies itself behind the user.

**A Profile row is still a macro, and still one-way.** Toggling it adds its members to the state.
Un-toggling removes the label and nothing else — the alternative needs per-Tool provenance ("was
`air` stamped, or did you check it yourself?") to answer a question nobody asked. That reasoning is
ADR-0009's and survives intact.

**`ENTER` installs exactly the state set. An empty set installs nothing. `ESC` cancels.** A picker
where cancelling installs eleven packages is a bug wearing a fallback's clothes. `--yes` remains the
way to ask for the Default Toolset on purpose.

**The marker goes in front of the type glyph**: `[x] ◆ go`. [ADR-0003](0003-tui-item-type-comes-from-the-marker-glyph.md)
survives untouched — the glyph still types the row, one field to the right — and the row reads as a
checkbox list to someone who has never seen it.

## Measured, fzf 0.74.3

Each of these was driven through a pty rather than assumed:

- A `reload` **clears** the selection, even reloading a byte-identical list: `FZF_SELECT_COUNT` reads
  0 immediately after, and `{+}` falls back to the current item.
- A check **survives filtering**. Select a row, type a query that hides it, clear the query: still
  selected, `FZF_SELECT_COUNT=1` throughout. Filtering and reloading are not the same operation.
- `load` fires after the list is read, **and again on every reload** — so it cannot carry a one-time
  preselect while the tab strip reloads.
- The cursor **survives a reload**: `pos` reads 3 before and after.
- `down` moves toward row 1 and clamps; `up` is the action that advances. Two `up` presses moved
  `pos` from 1 to 3.
- There is no `search`, `change-nth`, `transform-nth` or `reload-sync` action in this version, so
  nothing can change what is on screen without either a reload or writing into the user's query.
- A full list render costs ~35 ms for 35 rows, so a reload per keystroke is imperceptible.

## Considered and rejected

**Re-applying the selection after every reload.** Keep fzf authoritative; record checks in
`TUI_STATE` and replay them as `pos(N)+select` on `load`. It works only with an empty query — `load`
fires with whatever the user has typed still in the box, and `pos(N)` indexes the matched list — so
it forces the tab switch to clear the query and keeps every piece of position arithmetic this
decision exists to delete.

**Tabs as a query rather than a reload.** Give each row a hidden category token, scope search with
`--nth`, and have the tab strip write the token into the query. Selection then survives natively.
But the token sits visibly in the user's search box, their typing appends to it, and clearing the box
silently drops the tab. With no `search` action in 0.74.3 there is no way to do it out of band.

**Dropping the Category tabs.** The cheapest fix by far: the tab strip is the only thing that
reloads, so deleting it deletes the bug and leaves fzf's selection correct for free. Rejected because
[ADR-0002](0002-fzf-with-a-version-floor-replaces-gum.md) chose fzf over gum specifically for a tab
strip with an active state, and 35 rows is a lot to scroll blind.

**Leaving it alone and documenting the reset.** "Switching tabs clears your picks" is a sentence that
can be written in the header. It is also a picker that cannot be used for the thing tabs are for.
