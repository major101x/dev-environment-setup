#!/usr/bin/env bash
# Run the bats suite.
#
# Uses `bats` from PATH when present (CI installs it with apt). Otherwise it
# fetches a pinned bats-core into .cache/bats, which is gitignored — a fresh
# clone needs nothing installed to run the tests.
set -euo pipefail

BATS_PIN="v1.11.1"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if command -v bats >/dev/null 2>&1; then
  BATS_BIN="bats"
else
  BATS_BIN="$ROOT/.cache/bats/bin/bats"
  if [[ ! -x "$BATS_BIN" ]]; then
    echo "bats not on PATH - fetching bats-core $BATS_PIN into .cache/bats" >&2
    rm -rf "$ROOT/.cache/bats"
    git clone --quiet --depth 1 --branch "$BATS_PIN" \
      https://github.com/bats-core/bats-core.git "$ROOT/.cache/bats"
  fi
fi

if [[ $# -gt 0 ]]; then
  exec "$BATS_BIN" "$@"
fi
exec "$BATS_BIN" "$ROOT/test"
