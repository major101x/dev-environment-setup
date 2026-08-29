# A Profile row is a macro that stamps its Tools

> **Superseded in part by [ADR-0010](0010-the-list-is-the-source-of-truth-for-a-check.md).** The
> mechanism below — fzf's selection as the source of truth, stamped by `pos(N)+select` — is replaced
> by a state set the picker paints from. Two of the three rules go with it: "fires only when it can
> fire completely" and the stamped/unstamped distinction were both scaffolding for `pos(N)`. What
> survives: a Profile row is a macro, the stamp is one-way, and the Profile label is kept for
> `config.json` provenance. Nothing here is edited — the measurements are why ADR-0010 is believable.


`CONTEXT.md` says "Profiles are presets, not locks" — pick the `go` Profile, then uncheck `air` if
you do not want live reload. That is not what the picker does. Profiles are expanded *after* ENTER,
so unchecking `air` inside the picker has no effect: the Profile re-expands to `air` on the way out.
The preset is a lock.

The fix is to decide what selecting a Profile row **means**, and the answer is that it is a **macro**:
toggling it stamps its member Tools into the selection, and the checked **Tools** are the only thing
that resolves to an install. The Profile row itself stays selected as a **label** — recorded in
`config.json` so `--replay` and the saved config stay honest about what was picked — but resolution
ignores it. Nothing re-expands behind the user's back, so unchecking a stamped Tool sticks.

Three rules fall out of that, and they are not obvious:

**The stamp is one-way.** Un-toggling a Profile unstamps nothing. A macro that only ever adds is one
you can reason about; the alternative needs per-Tool provenance ("was `air` stamped, or did you check
it yourself?") to answer a question nobody asked.

**The stamp fires only when it can fire completely**, which is when the query is empty and the current
tab's list holds every member. Otherwise the row is a plain label.

**An unstamped Profile in the result expands at ENTER; a stamped one does not.** This is the rule that
makes the whole thing safe. A stamped Profile's Tools are already checked and carry the user's edits,
so expanding it again would resurrect what they unchecked. An unstamped Profile has no edits to
preserve, so expanding it is exactly right — and it keeps working the paths where stamping cannot
happen, including the most ordinary fzf interaction there is: type `go`, press ENTER, never toggle
anything.

## Why "only when it can fire completely"

Measured against fzf 0.74.3, not assumed:

- `pos(N)` indexes the **matched** list and clamps silently. With query `t` over `one two three four`,
  `pos(4)+select` selects `three`. A position computed against the unfiltered list checks the **wrong
  row** rather than failing.
- Only matched items can be selected at all: under query `t`, `select-all` yields `two three`.
- `change-query()` does **not** re-filter within an action chain — `change-query()+pos(4)+select`
  still stamps against the stale list.
- `reload(...)` behaves the same, deferring to the `result` event included.
- ~~Selections **do** survive a `reload`, even one whose list no longer contains them, so switching
  Category tabs loses no checks.~~ **Wrong, corrected on implementation.** A `reload` *clears* the
  selection, even when it reloads a byte-identical list: `FZF_SELECT_COUNT` reads 0 straight after,
  and `{+}` falls back to the current item. Both tab bindings reload, so a tab switch drops every
  check on screen. See "The stamp does not outlive its checks" below.
- A `transform` binding can branch on `FZF_QUERY` and the current row, so "can this stamp fire?" is
  answerable at toggle time.

Together those say: you cannot clear the query, switch the list, and stamp positions in one
interaction. So the picker does not try. It stamps when the list in front of the user already
contains everything the macro needs, and otherwise leaves a label that ENTER expands.

## The stamp does not outlive its checks

Because a `reload` clears the selection, a tab switch destroys exactly what a stamp put there. The
record of the stamp therefore cannot survive it: `tui_forget_stamps` truncates the record on both
tab bindings, and the Profile goes back to being an unstamped label that ENTER expands. Leaving the
record standing suppresses the expansion of a Profile that is no longer holding anything, and ENTER
then sees a label with no Tools under it and fires the "no tools selected" fallback — silently
installing the *Default Toolset*, the precise failure this ADR rejected "refusing the toggle" for.

The same measurement says something this ADR did not set out to decide: **a tab switch already
wiped the Default Toolset preselect**, and every check the user had made by hand, before any of
this existed. Making a check survive a `reload` needs the list itself to become the source of truth
— the option this ADR passed over as "keep a selection set in `TUI_STATE` and re-render markers on
`reload`" — and it is a bigger change than the macro. It is not fixed here.

## Consequences

**The Profiles tab is removed.** It listed Profile rows and no Tool rows, so the macro could never
fire on the one tab built for picking Profiles. Profiles still head the All tab. The strip becomes
`All · Languages · Frontend · Backend/DB · AI/ML · Infra/DevOps`.

**A Profile expands at two different moments** — pick time in the TUI, parse time for `--profile=`.
Same Tools, different moment; the CLI has no picker to stamp into.

**Unchecking a member is not available on the query path.** Type `go`, toggle the Profile, clear the
query, uncheck `air`, press ENTER — `air` still installs, because `go` never stamped and therefore
expands. The Selected Toolset panel shows this honestly (it lists `go` under profiles and resolves to
three Tools), so it is visible rather than silent. Clearing the query first and then toggling stamps,
and unchecking works.

## Considered and rejected

**Refusing the toggle while a query is active.** The first shape of this decision. It leaves a
keystroke that appears to do nothing, and — before the ENTER rule above existed — it silently
installed the *Default Toolset*: TAB refused, so ENTER saw an empty selection, returned the current
item, resolution ignored the Profile label, and the "no tools selected" fallback fired.

**A two-event dance** — record a pending stamp in `TUI_STATE`, clear the query, stamp on the next
`result` event, restore the query. Correct in every case and the most moving parts, all of them
async and none of them testable through the callback seam ([ADR-0008](0008-the-fzf-callbacks-are-the-test-seam.md)).
Still the way forward if the complete-or-label rule grates in practice.

**Stamping whatever is currently visible.** Silently partial: toggle `go` under a query that hides
`air` and you get two Tools of three, with nothing to tell you. This is the class of silent-wrong
result the harness in ADR-0008 exists to catch.

**Two screens — pick Profiles, then refine** (variant C on `prototype/tui-picker`). Worth noting the
prototype never implemented it: its `[x]` markers were painted glyphs with no `select` binding behind
them, so stage 2 returned only what the user hand-toggled. This is "build it", not "restore it", and
it gives up the single screen and the live Selected Toolset panel to do it.
