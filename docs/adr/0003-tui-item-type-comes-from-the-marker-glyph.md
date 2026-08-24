# TUI item type comes from the marker glyph, not the key

`go` and `rust` are each **both** a Profile key and a Tool key. The picker shows
Profiles and Tools in one list, so when a selected row comes back it has to be
typed — and typing it by name is ambiguous for exactly those two.

The previous parser resolved by name lookup with Profile winning:

```bash
if [[ " ${!PROFILE_TOOLS[*]} " == *" $line "* ]]; then
  SELECTED_PROFILES+=("$line")
else
  SELECTED_TOOLS+=("$line")
fi
```

Picking the **Tool** `go` therefore registered the **Profile** `go` and silently
installed `go golangci-lint air`; picking the Tool `rust` hit the same path. The
user got tools they never selected, with no warning.

Each row is now rendered with a marker — `◆` for Profile, `·` for Tool — and
`tui_type()` reads that glyph to type the row. The marker is both the visual
distinction the user sees and the parser's source of truth, so the two cannot
drift apart.

## Considered and rejected

Renaming the colliding keys (`go-lang` vs the `go` Profile) was the alternative.
Rejected because the collision is legitimate — a Profile named after its primary
Tool is good naming, not an accident — and renaming would break `--profile=go`
and any saved `~/.config/dev-setup/config.json`.
