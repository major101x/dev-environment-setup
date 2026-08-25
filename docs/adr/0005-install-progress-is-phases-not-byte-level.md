# Install progress is reported as phases, not byte-level bars

An install screen implies progress bars, but almost nothing here can produce one. Across the 27
Tools in `TOOL_DESC`:

| download shape | count | examples |
|---|---|---|
| measurable discrete download | **2** | `go` (tarball via `curl -o`), `qdrant` (`docker pull`) |
| semi-measurable | 1 | `puppeteer` (Chrome-for-Testing via `npx`) |
| apt-fused — no separable download | 8 | `gh`, `chrome`, `docker`, `pip` |
| opaque `curl \| bash`, `npm -g`, `pip` | 14 | `rust`, `bun`, `pnpm`, `biome`, `uv`, `ollama` |

Real bars would need a separate output parser per mechanism — `apt-get` status-fd, `curl`, `npm`,
`tar` — each of which breaks whenever that tool changes its output format, and would still leave
24 of 27 rows with nothing to show.

An Install Step therefore reports **phases**: `queued → downloading → installing → done (vX)`,
plus `already installed (vX)`, `skipped — unmet dependency` and `failed`. A spinner and elapsed
time carry liveness. This is uniform across every install mechanism.

## Considered and rejected

**A hybrid** — real bars where a discrete download exists, phases elsewhere. Rejected because two
rows out of twenty-seven behaving differently, for reasons invisible to the user, reads as broken
rather than as extra fidelity.

## Consequences

`already installed` and `skipped — unmet dependency` are not edge cases and must be first-class:
the script is idempotent, so a re-run legitimately puts most rows in the first state, and
dependency failures cascade (`pocock-skills` without `node`, `qdrant` without `docker`), so
without the second a single miss looks like several unexplained failures.

If byte-level progress is ever wanted, it is additive — the phase model stays and `downloading`
gains a percentage where one is available.
