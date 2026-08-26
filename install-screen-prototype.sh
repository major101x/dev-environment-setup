#!/usr/bin/env bash
# ============================================================================
# PROTOTYPE — THROWAWAY CODE. NOT PART OF setup.sh. DELETE ME.
#
# Question it answers: what should the install screen look like when a large
# Toolset does not fit on 80x24?
#
# Three variants, switchable via `./install-screen-prototype.sh <A|B|C> [frame]`.
# They disagree about OVERFLOW, and everything else falls out of that:
#
#   A  Viewport   — keep the per-Step list, scroll a window around the active row
#   B  Ledger     — collapse terminal states into counters; group by state, not order
#   C  Dashboard  — don't render the list live at all; census + active Step + failures
#
# Frames (default: all five, in order):
#   legend   the 7 lifecycle states side by side       <- answers question 2
#   midrun   step 10 of 22, one failure already logged <- answers question 3
#   rerun    idempotent re-run, most rows `already installed`
#   cascade  one failed prerequisite, five skips
#   final    the finalised end-of-run frame + summary beneath
#
# Honest density: the 22 Install Steps below are transcribed from setup.sh's
# REAL dispatch table (`install_selected_tools`, setup.sh:974-1005) collapsed
# many-to-one per ADR-0004, in ORDERED_TOOLS order (setup.sh:104), for `--all`.
# Nothing here shells out to setup.sh — the snapshot is fake ON PURPOSE, which
# is exactly what #21's purity seam exists for, so this is blocked by nothing.
#
# Reference, do not re-litigate: ADR-0004 (row == Install Step), ADR-0005 (no
# progress bars; `already installed` and `skipped` are first-class), ADR-0006
# (a failure does not abort the run).
#
# Options:  --width N   (default 80)  test truncation: --width 52
#           --height N  (default 24)
#           --raw       frame only, with ANSI  (this is how fixtures are made)
#           --plain     frame only, SGR stripped
#
# ---------------------------------------------------------------------------
# VERDICT: B wins. See ADR-0007 and the comment on #21.
#
#   A dies on three of the four frames. `rerun` is a wall of 19 near-identical
#     `already installed` rows — exactly the "twenty suspiciously instant
#     successes" ADR-0005 says must not happen. `cascade` scatters the five
#     skips through the list and scrolls the failure that caused them out of
#     the viewport. And `final` still says "↑ 7 more above": the FIRST of two
#     failures never appears in the finalised frame at all. A viewport cannot
#     finalise without becoming a second, different layout.
#   C never overflows and has the best failure tail, but its finalised frame is
#     dead scaffolding ("no Install Step in flight", "next: ") and it never
#     shows what installed at what version — which #22 requires on screen.
#   B collapses terminal successes into counters and never collapses failures,
#     skips or the active Step. It fits by construction at any Toolset size,
#     puts a failure adjacent to every skip it caused, and its finalised frame
#     is the live frame with the in-flight block gone — one layout, not two.
#
# Grafted from C into the winner: the `›` live-output lines under the active
# Step. Not grafted: C's census line (B's counters already carry it).
#
# Known, deliberately unfixed: variants A and C still overflow below 52
# columns. They lost; polishing them is not the job. B is clean from 80 down
# to ~30 columns, which is the layout's floor.
# ============================================================================
set -uo pipefail

WIDTH=80; HEIGHT=24; RAW=0; PLAIN=0
ARGS=()
while (($#)); do
  case "$1" in
    --width)  WIDTH=$2;  shift 2 ;;
    --height) HEIGHT=$2; shift 2 ;;
    --raw)    RAW=1; shift ;;
    --plain)  RAW=1; PLAIN=1; shift ;;
    -h|--help) sed -n '2,36p' "$0"; exit 0 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
VARIANT=${ARGS[0]:-A}
FRAME=${ARGS[1]:-all}

R=$'\e[0m'; B=$'\e[1m'; DIM=$'\e[90m'
if ((PLAIN)); then R=''; B=''; DIM=''; fi
GRN=$'\e[32m'; RED=$'\e[31m'; YEL=$'\e[33m'; CYN=$'\e[36m'; BLU=$'\e[34m'
if ((PLAIN)); then GRN=''; RED=''; YEL=''; CYN=''; BLU=''; fi

SPIN=(⣾ ⣽ ⣻ ⢿ ⡿ ⣟ ⣯ ⣷)

# --------------------------------------------------------------- helpers ----
# Truncate, never wrap (constraint). Pads to exactly n when short.
fit()  { local s="$1" n="$2"; ((n<1)) && return
         if ((${#s}>n)); then printf '%s…' "${s:0:n-1}"; else printf '%-*s' "$n" "$s"; fi; }
cut()  { local s="$1" n="$2"; ((n<1)) && return
         if ((${#s}>n)); then printf '%s…' "${s:0:n-1}"; else printf '%s' "$s"; fi; }
rule() { local c=${1:-─}; printf '%*s' "$WIDTH" '' | sed "s/ /$c/g"; }

# Title line: name on the left, elapsed right-aligned, exactly WIDTH visible cols.
hdr() {
  local l="dev-environment-setup · $TITLE" r="$ELAPSED elapsed" pad
  l=$(cut "$l" $((WIDTH - ${#r} - 2)))
  pad=$((WIDTH - ${#l} - ${#r})); ((pad < 1)) && pad=1
  printf '%s%s%s%s%s%s%*s%s%s%s' \
    "$B" "${l:0:21}" "$R" "$DIM" "${l:21}" "$R" "$pad" '' "$DIM" "$r" "$R"
}

# Label column width. The row layout has a floor: below it the label column
# would eat the status column, so it shrinks with the terminal instead of
# overflowing. Prefix is 5 cols, trailing gap 1 => status gets WIDTH-LBW-6.
set_lbw() { LBW=$((WIDTH - 24)); ((LBW > 22)) && LBW=22; ((LBW < 8)) && LBW=8; }

# Row emitters collect into FRAME_BUF so the frame can be measured against HEIGHT.
FRAME_BUF=()
out() { FRAME_BUF+=("$1"); }

# ---------------------------------------------------------- state vocab -----
# glyph + colour + word per lifecycle state. Variants override the glyphs to
# disagree; the seven states themselves are fixed by ADR-0005.
glyph() { case "$1" in
    queued)      printf '%s' "·" ;;
    downloading) printf '%s' "${SPIN[$((TICK % 8))]}" ;;
    installing)  printf '%s' "${SPIN[$((TICK % 8))]}" ;;
    done)        printf '%s' "✔" ;;
    already)     printf '%s' "=" ;;
    skipped)     printf '%s' "⊘" ;;
    failed)      printf '%s' "✘" ;;
  esac; }
colr()  { case "$1" in
    queued) printf '%s' "$DIM" ;; downloading|installing) printf '%s' "$CYN" ;;
    done) printf '%s' "$GRN" ;;  already) printf '%s' "$BLU" ;;
    skipped) printf '%s' "$YEL" ;; failed) printf '%s' "$RED" ;;
  esac; }
word()  { case "$1" in
    queued) printf 'queued' ;; downloading) printf 'downloading' ;;
    installing) printf 'installing' ;; done) printf 'done' ;;
    already) printf 'already installed' ;; skipped) printf 'skipped' ;;
    failed) printf 'failed' ;;
  esac; }

# ================================================================ data ======
# state|label|detail|tail (tail lines separated by ¦)
# Labels are the Tools an Install Step delivers (ADR-0004). 22 steps for --all.

snap_legend() { cat <<'EOF'
queued|redis-tools||
downloading|go, golangci-lint, air|go1.23.4.linux-amd64.tar.gz|
installing|pocock-skills|cloning 48 skills|
done|gh|2.63.2|
already|bun|1.1.38|
skipped|qdrant|needs docker|
failed|docker|apt-get exit 100|E: Unable to locate package docker-ce-cli¦E: Sub-process /usr/bin/dpkg returned an error code (100)
EOF
}

snap_midrun() { cat <<'EOF'
done|base deps|build-essential, curl, git|
done|gh|2.63.2|
done|fastfetch|2.30.1|
done|opencode|0.4.45|
done|node, puppeteer|node v22.11.0 · puppeteer 23.9.0|
done|chrome|131.0.6778.85|
failed|docker|apt-get exit 100|E: Unable to locate package docker-ce-cli¦E: Sub-process /usr/bin/dpkg returned an error code (100)¦N: See apt-secure(8) for repository creation
done|pip, eza|pip 24.3.1 · eza 0.20.5|
done|exa-mcp|registered, anonymous|
installing|pocock-skills|cloning 48 skills|Cloning into '/home/major/.claude/skills/mattpocock'…¦Receiving objects:  71% (34/48)
queued|go, golangci-lint, air||
queued|rust||
queued|bun||
queued|pnpm||
queued|biome||
queued|vite||
queued|uv||
queued|ollama||
skipped|qdrant|needs docker|
queued|postgres-client||
queued|redis-tools||
queued|jupyter||
EOF
}

snap_rerun() { cat <<'EOF'
already|base deps|nothing to do|
already|gh|2.63.2|
already|fastfetch|2.30.1|
already|opencode|0.4.45|
already|node, puppeteer|node v22.11.0 · puppeteer 23.9.0|
already|chrome|131.0.6778.85|
already|docker|27.3.1|
already|pip, eza|pip 24.3.1 · eza 0.20.5|
already|exa-mcp|registered, anonymous|
already|pocock-skills|48 skills present|
downloading|go, golangci-lint, air|1.23.2 → 1.23.4 · go1.23.4.linux-amd64.tar.gz|  % Total    % Received  Xferd  Average Speed¦100  67.0M  100  67.0M    0     0  11.4M
already|rust|1.83.0|
already|bun|1.1.38|
already|pnpm|9.14.4|
already|biome|1.9.4|
already|vite|6.0.3|
already|uv|0.5.7|
queued|ollama||
already|qdrant|v1.12.4|
already|postgres-client|16.6|
already|redis-tools|7.0.15|
queued|jupyter||
EOF
}

snap_cascade() { cat <<'EOF'
done|base deps|build-essential, curl, git|
done|gh|2.63.2|
done|fastfetch|2.30.1|
done|opencode|0.4.45|
failed|node, puppeteer|nvm install --lts exit 1|curl: (7) Failed to connect to raw.githubusercontent.com port 443¦nvm: install v22.11.0 failed¦npm: command not found
done|chrome|131.0.6778.85|
done|docker|27.3.1|
done|pip, eza|pip 24.3.1 · eza 0.20.5|
skipped|exa-mcp|needs node|
skipped|pocock-skills|needs node|
done|go, golangci-lint, air|go1.23.4 · golangci-lint 1.62.2 · air 1.61.5|
installing|rust|rustup-init · stable-x86_64|info: downloading component 'rust-std'¦info: installing component 'rustc'
queued|bun||
skipped|pnpm|needs node|
skipped|biome|needs node|
skipped|vite|needs node|
queued|uv||
queued|ollama||
queued|qdrant||
queued|postgres-client||
queued|redis-tools||
queued|jupyter||
EOF
}

snap_final() { cat <<'EOF'
done|base deps|build-essential, curl, git|
done|gh|2.63.2|
already|fastfetch|2.30.1|
done|opencode|0.4.45|
done|node, puppeteer|node v22.11.0 · puppeteer 23.9.0|
done|chrome|131.0.6778.85|
failed|docker|apt-get exit 100|E: Unable to locate package docker-ce-cli¦E: Sub-process /usr/bin/dpkg returned an error code (100)¦N: See apt-secure(8) for repository creation
done|pip, eza|pip 24.3.1 · eza 0.20.5|
done|exa-mcp|registered, anonymous|
done|pocock-skills|48 skills|
done|go, golangci-lint, air|go1.23.4 · golangci-lint 1.62.2 · air 1.61.5|
done|rust|1.83.0|
already|bun|1.1.38|
done|pnpm|9.14.4|
done|biome|1.9.4|
done|vite|6.0.3|
done|uv|0.5.7|
failed|ollama|install.sh exit 1|curl: (28) Operation timed out after 30001 ms¦ollama: no release asset for this platform
already|qdrant|v1.12.4|
skipped|postgres-client|needs docker|
already|redis-tools|7.0.15|
done|jupyter|7.3.1|
EOF
}

# Snapshot metadata — set in the PARENT shell, since the row data is read
# through a process substitution that cannot export back.
meta() { case "$1" in
  legend)  TITLE="lifecycle states";                ELAPSED="0:31"; TICK=3; FINAL=0 ;;
  midrun)  TITLE="--all · 22 Install Steps";        ELAPSED="1:47"; TICK=2; FINAL=0 ;;
  rerun)   TITLE="--all · 22 Steps (re-run)";       ELAPSED="0:09"; TICK=6; FINAL=0 ;;
  cascade) TITLE="--all · 22 Install Steps";        ELAPSED="2:38"; TICK=5; FINAL=0 ;;
  final)   TITLE="--all · 22 Install Steps";        ELAPSED="6:12"; TICK=0; FINAL=1 ;;
esac; }

# Load a snapshot into parallel arrays ST/LB/DT/TL.
load() { meta "$1"; ST=(); LB=(); DT=(); TL=()
  local _s _l _d _t
  while IFS='|' read -r _s _l _d _t; do
    [[ -z "$_s" ]] && continue
    ST+=("$_s"); LB+=("$_l"); DT+=("$_d"); TL+=("$_t")
  done < <("snap_$1")
  N=${#ST[@]}
  ACTIVE=-1
  for i in "${!ST[@]}"; do
    [[ ${ST[$i]} == installing || ${ST[$i]} == downloading ]] && { ACTIVE=$i; break; }
  done
}
count() { local w=$1 n=0; for s in "${ST[@]}"; do [[ $s == "$w" ]] && ((n++)); done; echo "$n"; }
labels_of() { local w=$1 out=""; for i in "${!ST[@]}"; do
    [[ ${ST[$i]} == "$w" ]] && out+="${LB[$i]}, "; done; echo "${out%, }"; }

# ====================================================== VARIANT A ===========
# Viewport. Keeps the ordered per-Install-Step list — the thing the user picked,
# in the order it runs — and scrolls a window around the active row. Terminal
# states stay individually visible. Failure tail is a pinned 3-line panel.
render_A() {
  local head=2 foot=2 fpanel=0
  local nf; nf=$(count failed)
  ((nf > 0)) && fpanel=5
  local view=$((HEIGHT - head - foot - fpanel))
  ((view < 3)) && view=3

  out "$(hdr)"
  out "${DIM}$(rule)${R}"

  # window around the active row, clamped
  local rows=$view start=0 a=$ACTIVE
  ((a < 0)) && a=$((N - 1))
  if ((N > rows)); then
    start=$((a - rows / 2)); ((start < 0)) && start=0
    ((start > N - rows)) && start=$((N - rows))
  fi
  local end=$((start + rows)); ((end > N)) && end=$N

  if ((start > 0)); then
    out "  ${DIM}↑ $start more above${R}"; ((start++))
  fi
  local tailroom=0
  ((end < N)) && tailroom=1 && ((end--))

  local i
  for ((i = start; i < end; i++)); do
    local st=${ST[$i]} c; c=$(colr "$st")
    local marker="  "; ((i == ACTIVE)) && marker="${CYN}▶${R} "
    local status; status="$(word "$st")"
    [[ -n ${DT[$i]} ]] && status+=" · ${DT[$i]}"
    if [[ $st == installing || $st == downloading ]]; then
      status="$(word "$st") · ${ELAPSED} · ${DT[$i]}"
    fi
    out "${marker}${c}$(glyph "$st")${R}  $(fit "${LB[$i]}" $LBW) ${c}$(cut "$status" $((WIDTH - LBW - 7)))${R}"
  done
  ((tailroom)) && out "  ${DIM}↓ $((N - end)) more below${R}"

  if ((nf > 0)); then
    local fi=-1
    for i in "${!ST[@]}"; do [[ ${ST[$i]} == failed ]] && fi=$i; done
    out "${DIM}$(rule)${R}"
    out "  ${RED}✘ ${LB[$fi]}${R} ${DIM}failed · last 3 lines of output${R}"
    local shown=0
    IFS='¦' read -ra lines <<<"${TL[$fi]}"
    for l in "${lines[@]}"; do
      ((shown >= 3)) && break
      out "    ${DIM}$(cut "$l" $((WIDTH - 4)))${R}"; ((shown++))
    done
    while ((shown < 3)); do out ""; ((shown++)); done
  fi

  out "${DIM}$(rule)${R}"
  out "  ${GRN}$(count done) done${R} ${DIM}·${R} ${BLU}$(count already) already${R} ${DIM}·${R} ${YEL}$(count skipped) skipped${R} ${DIM}·${R} ${RED}$(count failed) failed${R} ${DIM}·${R} $(( $(count queued) )) queued"
}

# ====================================================== VARIANT B ===========
# Ledger. Groups by STATE, not by execution order. Terminal successes collapse
# into one counter line each; failures, skips and the active Step never
# collapse. Fits any Toolset size on 24 rows by construction.
render_B() {
  local nd na nq nf nk i
  nd=$(count done); na=$(count already); nq=$(count queued)
  nf=$(count failed); nk=$(count skipped)

  # The failure board is pinned to the bottom and never collapses, so its size
  # is fixed first — whatever is left over is slack the collapsed section can use.
  local FB=()
  if ((nf > 0 || nk > 0)); then
    FB+=("") FB+=("${DIM}$(rule)${R}")
    for i in "${!ST[@]}"; do
      [[ ${ST[$i]} == failed ]] || continue
      FB+=("  ${RED}✘${R}  ${B}$(fit "${LB[$i]}" $LBW)${R} ${RED}$(cut "failed · ${DT[$i]}" $((WIDTH - LBW - 6)))${R}")
      local s2=0; IFS='¦' read -ra lines <<<"${TL[$i]}"
      for l in "${lines[@]}"; do ((s2 >= 2)) && break
        FB+=("       ${DIM}$(cut "$l" $((WIDTH - 7)))${R}"); ((s2++)); done
    done
    for i in "${!ST[@]}"; do
      [[ ${ST[$i]} == skipped ]] || continue
      FB+=("  ${YEL}⊘${R}  $(fit "${LB[$i]}" $LBW) ${YEL}$(cut "skipped · ${DT[$i]}" $((WIDTH - LBW - 6)))${R}")
    done
  fi

  out "$(hdr)"
  out "${DIM}$(rule)${R}"

  # --- in flight, individually, always ---
  local shown=0
  for i in "${!ST[@]}"; do
    case ${ST[$i]} in installing|downloading)
      out "  ${CYN}$(glyph "${ST[$i]}")${R}  ${B}$(fit "${LB[$i]}" $LBW)${R} ${CYN}$(cut "$(word "${ST[$i]}") · $ELAPSED" $((WIDTH - LBW - 6)))${R}"
      out "       ${DIM}$(cut "${DT[$i]}" $((WIDTH - 7)))${R}"; ((shown++)) ;;
    esac
  done
  ((shown)) && out ""

  # --- terminal successes collapse into one counter line each ---
  ((nd > 0)) && out "  ${GRN}✔${R}  $(fit "$nd done" $LBW) ${DIM}$(cut "$(labels_of done)" $((WIDTH - LBW - 6)))${R}"
  ((na > 0)) && out "  ${BLU}=${R}  $(fit "$na already installed" $LBW) ${DIM}$(cut "$(labels_of already)" $((WIDTH - LBW - 6)))${R}"
  # --- queued is the one group that gets the leftover room: it collapses to a
  #     counter, and expands into individual Steps only as far as slack allows.
  #     Bounded by the pinned failure board, so this can never overflow. ---
  if ((nq > 0)); then
    local slack=$((HEIGHT - ${#FRAME_BUF[@]} - ${#FB[@]} - 1))
    if ((slack >= 2)); then
      out "  ${DIM}·${R}  ${DIM}$nq queued${R}"
      local shown3=0
      for i in "${!ST[@]}"; do
        [[ ${ST[$i]} == queued ]] || continue
        ((shown3 >= slack - 1)) && { out "      ${DIM}… and $((nq - shown3)) more${R}"; break; }
        out "      ${DIM}$(cut "${LB[$i]}" $((WIDTH - 6)))${R}"; ((shown3++))
      done
    else
      out "  ${DIM}·${R}  ${DIM}$(fit "$nq queued" $LBW) $(cut "$(labels_of queued)" $((WIDTH - LBW - 6)))${R}"
    fi
  fi

  for l in "${FB[@]}"; do out "$l"; done
}

# ====================================================== VARIANT C ===========
# Dashboard. Says the per-Step list is the wrong thing to show LIVE. Fixed
# height regardless of Toolset size: census, the active Step with real output,
# a pinned failure board. The full list appears only after finalisation.
render_C() {
  local nd na nq nf nk ni done_n
  nd=$(count done); na=$(count already); nq=$(count queued)
  nf=$(count failed); nk=$(count skipped)
  ni=$((N - nd - na - nq - nf - nk))
  done_n=$((nd + na + nf + nk))

  out "$(hdr)"
  out "${DIM}$(rule ═)${R}"
  out "  ${B}$(fit "$done_n of $N Install Steps" 26)${R}${GRN}✔ $nd${R}   ${BLU}= $na${R}   ${YEL}⊘ $nk${R}   ${RED}✘ $nf${R}   ${CYN}$(glyph installing) $ni${R}   ${DIM}· $nq${R}"
  out "${DIM}$(rule ═)${R}"

  # --- the active Install Step, with room to breathe ---
  if ((ACTIVE >= 0)); then
    local a=$ACTIVE
    out "  ${CYN}$(glyph "${ST[$a]}")${R}  ${B}$(cut "${LB[$a]}" $((WIDTH - 26)))${R}${CYN}$(fit "$(word "${ST[$a]}")" 13)${R}${DIM}$ELAPSED${R}"
    out "       ${DIM}$(cut "${DT[$a]}" $((WIDTH - 7)))${R}"
    local s=0; IFS='¦' read -ra lines <<<"${TL[$a]}"
    for l in "${lines[@]}"; do ((s >= 3)) && break
      out "       ${DIM}› $(cut "$l" $((WIDTH - 9)))${R}"; ((s++)); done
    while ((s < 3)); do out ""; ((s++)); done
  else
    out ""; out "  ${DIM}no Install Step in flight${R}"; out ""; out ""; out ""
  fi
  out "${DIM}$(rule)${R}"

  # --- pinned failure board: every failure, generous tail ---
  out "  ${B}failures${R} ${DIM}($nf failed, $nk skipped)${R}"
  local i printed=0 budget=$((HEIGHT - 13))
  for i in "${!ST[@]}"; do
    [[ ${ST[$i]} == failed ]] || continue
    ((printed >= budget)) && break
    out "  ${RED}✘ $(cut "${LB[$i]} · ${DT[$i]}" $((WIDTH - 4)))${R}"; ((printed++))
    local s=0; IFS='¦' read -ra lines <<<"${TL[$i]}"
    for l in "${lines[@]}"; do ((s >= 3 || printed >= budget)) && break
      out "      ${DIM}$(cut "$l" $((WIDTH - 6)))${R}"; ((s++)); ((printed++)); done
  done
  for i in "${!ST[@]}"; do
    [[ ${ST[$i]} == skipped ]] || continue
    ((printed >= budget)) && break
    out "  ${YEL}⊘ $(cut "${LB[$i]} · skipped, ${DT[$i]}" $((WIDTH - 4)))${R}"; ((printed++))
  done
  ((nf == 0 && nk == 0)) && { out "  ${DIM}none${R}"; ((printed++)); }
  while ((printed < budget)); do out ""; ((printed++)); done

  out "${DIM}$(rule)${R}"
  out "  ${DIM}next: $(cut "$(labels_of queued)" $((WIDTH - 9)))${R}"
}

# ================================================== finalisation ============
# Printed BENEATH the finalised frame. Must survive in scrollback, and must
# land before anything reads stdin (`gh auth login`).
summary() {
  local nd na nf nk i
  nd=$(count done); na=$(count already); nf=$(count failed); nk=$(count skipped)
  echo
  echo "${DIM}$(rule)${R}"
  # The counts line has its own width floor — it splits rather than truncating,
  # because a truncated summary silently drops failure counts.
  local plain="Done in ${ELAPSED}.  $nd installed · $na already · $nk skipped · $nf failed"
  if ((${#plain} + 2 <= WIDTH)); then
    echo "  ${B}Done in ${ELAPSED}.${R}  ${GRN}$nd installed${R} ${DIM}·${R} ${BLU}$na already${R} ${DIM}·${R} ${YEL}$nk skipped${R} ${DIM}·${R} ${RED}$nf failed${R}"
  else
    echo "  ${B}Done in ${ELAPSED}.${R}"
    echo "  ${GRN}$nd installed${R} ${DIM}·${R} ${BLU}$na already${R}"
    echo "  ${YEL}$nk skipped${R} ${DIM}·${R} ${RED}$nf failed${R}"
  fi
  echo
  for i in "${!ST[@]}"; do
    [[ ${ST[$i]} == failed ]] || continue
    echo "  ${RED}✘ $(cut "${LB[$i]}" $LBW)${R} ${DIM}$(cut "— ${DT[$i]}" $((WIDTH - LBW - 5)))${R}"
  done
  for i in "${!ST[@]}"; do
    [[ ${ST[$i]} == skipped ]] || continue
    echo "  ${YEL}⊘ $(cut "${LB[$i]}" $LBW)${R} ${DIM}$(cut "— ${DT[$i]}" $((WIDTH - LBW - 5)))${R}"
  done
  ((nf > 0)) && echo "  ${DIM}$(cut "re-run to retry the failures. exit status: 1" $((WIDTH - 2)))${R}"
  echo
  return 0
}

# ================================================== frame driver ============
show() { # show <variant> <snapshot>
  local v=$1 s=$2
  load "$s"
  set_lbw
  FRAME_BUF=()
  "render_$v"

  # --raw emits the frame alone — these are the fixtures #21 asserts against.
  if ((RAW)); then
    local j
    for ((j = 0; j < ${#FRAME_BUF[@]}; j++)); do printf '%s\n' "${FRAME_BUF[$j]}"; done
    if ((FINAL)); then summary; fi
    return 0
  fi
  printf '\n%s%s  %s / %s  ·  %sx%s  %s%s\n' "$B" "▛▀▀" "variant $v" "$s" "$WIDTH" "$HEIGHT" "▀▀▜" "$R"
  local n=${#FRAME_BUF[@]}
  # Pad or report. A live frame MUST be exactly HEIGHT lines; the finalised
  # frame is allowed to exceed it, because it scrolls into scrollback.
  local i
  for ((i = 0; i < n && i < HEIGHT; i++)); do printf '%s\n' "${FRAME_BUF[$i]}"; done
  if ((n < HEIGHT)); then
    for ((i = n; i < HEIGHT; i++)); do echo; done
  fi
  if ((n > HEIGHT)); then
    printf '%s▙▄▄ OVERFLOW: frame is %s lines, budget is %s — %s lines lost ▄▄▟%s\n' \
      "$RED" "$n" "$HEIGHT" "$((n - HEIGHT))" "$R"
  else
    printf '%s▙▄▄ frame fits: %s of %s lines used ▄▄▟%s\n' "$DIM" "$n" "$HEIGHT" "$R"
  fi
  if ((FINAL)); then summary; fi
  return 0
}

case "$VARIANT" in A|B|C) ;; *) echo "usage: $0 [A|B|C] [legend|midrun|rerun|cascade|final] [--width N] [--height N]"; exit 1 ;; esac

if [[ $FRAME == all ]]; then
  for f in legend midrun rerun cascade final; do show "$VARIANT" "$f"; done
else
  show "$VARIANT" "$FRAME"
fi
