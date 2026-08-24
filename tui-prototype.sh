#!/usr/bin/env bash
# ============================================================================
# PROTOTYPE — THROWAWAY CODE. NOT PART OF setup.sh. DELETE ME.
#
# Question it answers: what should the Toolset picker look like?
#
# Three variants of the picker, switchable via `./tui-prototype.sh <A|B|C>`,
# running against setup.sh's REAL registry (--list-tools / --list-profiles)
# so density and naming are honest.
#
#   A  Tabbed      — the literal ask: active tab strip, arrow keys, clickable
#   B  Flat+typed  — no tabs at all; Profile vs Tool made visible instead
#   C  Two-stage   — Profiles first, then refine Tools
#
# All three fix the same underlying bug: setup.sh:290-297 flattens Profiles
# and Tools into one alphabetical list, so you cannot tell them apart.
# They disagree about HOW to fix it. That's the point.
# ============================================================================
set -uo pipefail

SELF=$(readlink -f "$0")
REPO=$(dirname "$SELF")
FZF=${FZF_BIN:-fzf}
STATE=${PROTO_STATE:-}

# ---------------------------------------------------------------- data ------
load_tools() {   # key<TAB>category<TAB>description
  "$REPO/setup.sh" --list-tools 2>/dev/null | tail -n +2 \
    | sed -E 's/^  ([^ ]+) +([^ ]+(\/[^ ]+)?) +(.*)$/\1\t\2\t\4/'
}
load_profiles() { # key<TAB>tools
  "$REPO/setup.sh" --list-profiles 2>/dev/null | tail -n +2 \
    | sed -E 's/^  ([^ ]+) +(.*)$/\1\t\2/'
}

TABS=(All Profiles Languages Frontend "Backend/DB" AI/ML Infra/DevOps)

# ------------------------------------------------------------ callbacks -----
case "${1:-}" in
  __header)
    idx=$(cat "$STATE/tab" 2>/dev/null || echo 0)
    line=""; col=0; : >"$STATE/cols"
    for i in "${!TABS[@]}"; do
      label=" ${TABS[$i]} "
      echo "$col $((col + ${#label})) $i" >>"$STATE/cols"
      if [[ "$i" == "$idx" ]]; then line+=$'\e[7;36m'"$label"$'\e[0m'; else line+=$'\e[90m'"$label"$'\e[0m'; fi
      col=$((col + ${#label}))
    done
    printf '%s\n' "$line"
    printf '\e[90m  ←/→ or click a tab · TAB selects · ENTER confirms\e[0m\n'
    exit 0 ;;
  __list)
    idx=$(cat "$STATE/tab" 2>/dev/null || echo 0)
    tab="${TABS[$idx]}"
    if [[ "$tab" == "Profiles" ]]; then
      load_profiles | while IFS=$'\t' read -r k v; do printf '\e[35m◆ %-16s\e[0m \e[90m%s\e[0m\n' "$k" "$v"; done
    elif [[ "$tab" == "All" ]]; then
      load_profiles | while IFS=$'\t' read -r k v; do printf '\e[35m◆ %-16s\e[0m \e[90m%s\e[0m\n' "$k" "$v"; done
      load_tools    | while IFS=$'\t' read -r k c d; do printf '\e[36m· %-16s\e[0m \e[90m%-14s %s\e[0m\n' "$k" "$c" "$d"; done
    else
      load_tools | awk -F'\t' -v t="$tab" '$2==t' | while IFS=$'\t' read -r k c d; do
        printf '\e[36m· %-16s\e[0m \e[90m%-14s %s\e[0m\n' "$k" "$c" "$d"; done
    fi
    exit 0 ;;
  __tab)
    idx=$(cat "$STATE/tab" 2>/dev/null || echo 0); n=${#TABS[@]}
    [[ "${2:-}" == next ]] && idx=$(( (idx+1) % n )) || idx=$(( (idx-1+n) % n ))
    echo "$idx" >"$STATE/tab"; exit 0 ;;
  __click)
    c=${FZF_CLICK_HEADER_COLUMN:-0}
    while read -r s e i; do [[ $c -gt $s && $c -le $e ]] && echo "$i" >"$STATE/tab" && break; done <"$STATE/cols"
    exit 0 ;;
  __preview)
    cur="${2:-}"; shift 2 2>/dev/null || shift $#
    key=$(sed -E 's/\x1b\[[0-9;]*m//g; s/^[◆·] +//; s/ .*//' <<<"$cur")

    # ---- top: detail for the item under the cursor ----
    prof=$(load_profiles | awk -F'\t' -v k="$key" '$1==k{print $2}')
    if [[ -n "$prof" ]]; then
      printf '\e[35mPROFILE\e[0m  %s\n\n\e[90mexpands to %s tools:\e[0m\n' "$key" "$(wc -w <<<"$prof")"
      for t in $prof; do printf '  \e[36m·\e[0m %s\n' "$t"; done
      printf '\n\e[90mProfiles are presets, not locks — you can still\nuncheck anything they pre-check.\e[0m\n'
    elif [[ -n "$key" ]]; then
      load_tools | awk -F'\t' -v k="$key" '$1==k{printf "\033[36mTOOL\033[0m     %s\n\n  category: %s\n  %s\n", $1, $2, $3}'
      printf '\n\e[90mIn profiles:\e[0m\n'
      load_profiles | awk -F'\t' -v k="$key" '{n=split($2,a," "); for(i=1;i<=n;i++) if(a[i]==k) print "  ◆ " $1}'
    fi

    # ---- bottom: the resolved Toolset, live ----
    picked_profiles=(); picked_tools=(); resolved=""
    for raw in "$@"; do
      plain=$(sed -E 's/\x1b\[[0-9;]*m//g' <<<"$raw")
      k=$(sed -E 's/^[◆·] +//; s/ .*//' <<<"$plain")
      [[ -z "$k" ]] && continue
      # type comes from the marker, NOT a name lookup: `go` and `rust` are
      # each both a Profile key and a Tool key (setup.sh:325 gets this wrong)
      if [[ "$plain" == ◆* ]]; then
        picked_profiles+=("$k")
        resolved+="$(load_profiles | awk -F'\t' -v k="$k" '$1==k{print $2}') "
      else
        picked_tools+=("$k"); resolved+="$k "
      fi
    done
    uniq_tools=$(tr ' ' '\n' <<<"$resolved" | sed '/^$/d' | sort -u)
    n=$(grep -c . <<<"$uniq_tools" 2>/dev/null || echo 0); [[ -z "$uniq_tools" ]] && n=0

    w=${FZF_PREVIEW_COLUMNS:-52}; (( w < 24 )) && w=24
    inner=$((w - 2))
    bar()  { printf '%*s' "$inner" '' | sed 's/ /─/g'; }        # bottom edge
    sep()  { printf '%*s' $((inner - 2)) '' | sed 's/ /─/g'; }  # inner rule
    printf '\n\e[90m╭─\e[0m \e[1mSelected Toolset\e[0m \e[90m%s╮\e[0m\n' "$(printf '%*s' $((inner - 20)) '' | sed 's/ /─/g')"
    if (( n == 0 )); then
      printf '\e[90m│\e[0m \e[90mnothing selected yet — TAB to select\e[0m\n'
    else
      if (( ${#picked_profiles[@]} )); then
        printf '\e[90m│\e[0m \e[35mprofiles:\e[0m %s\n' "${picked_profiles[*]}"
      fi
      if (( ${#picked_tools[@]} )); then
        printf '\e[90m│\e[0m \e[36mextra:\e[0m %s\n' "${picked_tools[*]}"
      fi
      printf '\e[90m│\e[0m \e[90m%s\e[0m\n' "$(sep)"
      printf '\e[90m│\e[0m \e[1m%s tools will install:\e[0m\n' "$n"
      # 3 tools per line so a long toolset stays readable
      printf '%s\n' "$uniq_tools" | paste -d' ' - - - 2>/dev/null | while read -r line; do
        [[ -n "$line" ]] && printf '\e[90m│\e[0m   \e[32m%s\e[0m\n' "$line"
      done
    fi
    printf '\e[90m╰%s╯\e[0m\n' "$(bar)"
    exit 0 ;;
esac

# ----------------------------------------------------- ensure_fzf (proto) ---
# Prototyping the bootstrap too: apt ships 0.44.1, which lacks --input-border
# and click-header. So this VERSION-checks rather than existence-checks --
# the bug ensure_gum has at setup.sh:246 (`command -v fzf` and return 0).
FZF_MIN="0.60.0"
PROTO_FZF="$REPO/.fzf-proto/fzf"

fzf_ok() {  # $1 = binary
  command -v "$1" >/dev/null 2>&1 || [[ -x "$1" ]] || return 1
  "$1" --help 2>&1 | grep -q -- --input-border || return 1
  echo x | "$1" --bind 'click-header:ignore' --filter=x >/dev/null 2>&1 || return 1
  return 0
}

if ! fzf_ok "$FZF"; then
  if fzf_ok "$PROTO_FZF"; then
    FZF="$PROTO_FZF"
  else
    have=$(command -v fzf >/dev/null 2>&1 && fzf --version | awk '{print $1}' || echo "none")
    echo "fzf on PATH: $have  — needs >= $FZF_MIN for --input-border / click-header."
    read -rp "Download fzf into $REPO/.fzf-proto/ (throwaway, gitignored)? [y/N] " a
    [[ "$a" == [yY]* ]] || { echo "Aborted. Or point at your own: FZF_BIN=/path/to/fzf $0 ${1:-A}"; exit 1; }
    mkdir -p "$REPO/.fzf-proto"
    url="https://github.com/junegunn/fzf/releases/download/v0.74.3/fzf-0.74.3-linux_amd64.tar.gz"
    curl -fsSL "$url" | tar -xz -C "$REPO/.fzf-proto" || { echo "download failed"; exit 1; }
    fzf_ok "$PROTO_FZF" || { echo "downloaded fzf still fails capability check"; exit 1; }
    FZF="$PROTO_FZF"
    echo "using $("$FZF" --version)"
  fi
fi

STATE=$(mktemp -d); export PROTO_STATE="$STATE"; trap 'rm -rf "$STATE"' EXIT
echo 0 >"$STATE/tab"

show_result() {
  printf '\n\e[1m── selected ──\e[0m\n'
  if [[ -z "${1:-}" ]]; then printf '\e[90m(nothing)\e[0m\n'; return; fi
  sed -E 's/^[◆·] +//; s/ +$//' <<<"$1" | awk '{print "  " $1}'
  printf '\n\e[90mprofiles resolve to their tools at install time.\e[0m\n'
}

variant=${1:-A}
case "$variant" in

# --- A: tabbed. the literal ask. --------------------------------------------
A)
  out=$("$SELF" __list | "$FZF" --ansi --multi \
    --border=rounded --border-label=' Interactive setup ' \
    --input-border=rounded --input-label=' Search ' \
    --header-border=rounded --padding=1 --margin=1 \
    --prompt='  ' --ghost='type to filter…' \
    --marker='●' --pointer='▶' --height=100% \
    --header-first \
    --header="$("$SELF" __header)" \
    --preview="$SELF __preview {} {+}" --preview-window='right,48%,border-rounded' \
    --preview-label=' details ' \
    --bind "left:execute-silent($SELF __tab prev)+transform-header($SELF __header)+reload($SELF __list)" \
    --bind "right:execute-silent($SELF __tab next)+transform-header($SELF __header)+reload($SELF __list)" \
    --bind "click-header:execute-silent($SELF __click)+transform-header($SELF __header)+reload($SELF __list)" \
    --bind 'tab:toggle+down+refresh-preview' \
    --bind 'ctrl-a:toggle-all+refresh-preview' )
  show_result "$out" ;;

# --- B: no tabs. make the TYPE visible instead. ------------------------------
B)
  out=$( { load_profiles | while IFS=$'\t' read -r k v; do
             printf '\e[35m PROFILE \e[0m %-18s \e[90m%s\e[0m\n' "$k" "$v"; done
           load_tools | while IFS=$'\t' read -r k c d; do
             printf '\e[46;30m %-7s \e[0m %-18s \e[90m%s\e[0m\n' "${c%%/*}" "$k" "$d"; done
         } | "$FZF" --ansi --multi \
    --border=rounded --border-label=' Interactive setup ' \
    --input-border=rounded --input-label=' Search ' --padding=1 --margin=1 \
    --prompt='  ' --ghost='search everything — profiles and tools…' \
    --marker='●' --pointer='▶' --height=100% --header-first \
    --header=$'\e[90mNo tabs. One list, but Profile and Tool are visibly different types.\nTAB selects · ENTER confirms\e[0m' \
    --preview="$SELF __preview {2}" --preview-window='right,45%,border-rounded' \
    --bind 'tab:toggle+down' )
  show_result "$(sed -E 's/^ *(PROFILE|[A-Za-z]+) +//' <<<"$out")" ;;

# --- C: two stages. profiles first, then refine. -----------------------------
C)
  picked=$(load_profiles | while IFS=$'\t' read -r k v; do
      printf '\e[35m◆\e[0m %-16s \e[90m%s\e[0m\n' "$k" "$v"; done \
    | "$FZF" --ansi --multi \
      --border=rounded --border-label=' Step 1 of 2 — pick your Profiles ' \
      --input-border=rounded --input-label=' Search ' --padding=1 --margin=1 \
      --prompt='  ' --ghost='e.g. full-stack-web…' \
      --marker='●' --pointer='▶' --height=100% --header-first \
      --header=$'\e[90mProfiles pre-check tools. You refine them next.\nTAB selects · ENTER continues\e[0m' \
      --preview="$SELF __preview {2}" --preview-window='right,45%,border-rounded')
  pre=$(sed -E 's/^◆ +//; s/ .*//' <<<"$picked" | while read -r p; do
          [[ -n "$p" ]] && load_profiles | awk -F'\t' -v k="$p" '$1==k{print $2}'; done | tr ' ' '\n' | sort -u)
  out=$(load_tools | while IFS=$'\t' read -r k c d; do
      if grep -qx "$k" <<<"$pre"; then printf '\e[32m[x]\e[0m %-16s \e[90m%-14s %s\e[0m\n' "$k" "$c" "$d"
      else printf '\e[90m[ ] %-16s %-14s %s\e[0m\n' "$k" "$c" "$d"; fi; done \
    | "$FZF" --ansi --multi \
      --border=rounded --border-label=' Step 2 of 2 — refine your Toolset ' \
      --input-border=rounded --input-label=' Search ' --padding=1 --margin=1 \
      --prompt='  ' --ghost='add or remove individual tools…' \
      --marker='●' --pointer='▶' --height=100% --header-first \
      --header=$'\e[90m[x] = pre-checked by a Profile. Uncheck freely — presets, not locks.\nTAB selects · ENTER confirms\e[0m' \
      --preview="$SELF __preview {2}" --preview-window='right,45%,border-rounded')
  show_result "$(sed -E 's/^\[.\] +//' <<<"$out")" ;;

*) echo "usage: $0 [A|B|C]"; exit 1 ;;
esac
