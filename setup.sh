#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# dev-environment-setup - Ubuntu 24.04 (Noble) VPS dev setup
# Installs: GitHub CLI, fastfetch, opencode, Node (nvm LTS) + Puppeteer,
#           Chrome stable + headless, Docker CE + compose, Exa MCP,
#           Matt Pocock skills, pip + eza
# Idempotent - safe to re-run. Logs to setup.log.
# Repo: https://github.com/<you>/dev-environment-setup
# ==============================================================================
LOG_FILE="${LOG_FILE:-./setup.log}"
# Save TTY status before exec (exec pipes stdout to tee, breaking -t 1)
IS_TTY=false
if [[ -t 0 ]] && [[ -t 1 ]]; then
  IS_TTY=true
fi
# fzf callbacks (__tui_*) must write to fzf, not the log, so they skip this.
case "${1:-}" in
  __tui_*) ;;
  *) exec > >(tee -a "$LOG_FILE") 2>&1 ;;
esac

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
step()  { echo -e "\n${GREEN}==>${NC} $*"; }

# ------------------------------------------------------------------------------
# Tool registry + profiles (CONTEXT.md vocabulary)
# ------------------------------------------------------------------------------
declare -A TOOL_CATEGORY=(
  [gh]="Infra/DevOps"
  [fastfetch]="Infra/DevOps"
  [opencode]="AI/ML"
  [node]="Languages"
  [puppeteer]="Frontend"
  [chrome]="Frontend"
  [docker]="Infra/DevOps"
  [pip]="Languages"
  [eza]="Infra/DevOps"
  [exa-mcp]="AI/ML"
  [pocock-skills]="AI/ML"
  [go]="Languages"
  [golangci-lint]="Languages"
  [air]="Languages"
  [rust]="Languages"
  [bun]="Frontend"
  [pnpm]="Frontend"
  [biome]="Frontend"
  [vite]="Frontend"
  [uv]="AI/ML"
  [ollama]="AI/ML"
  [qdrant]="AI/ML"
  [postgres-client]="Backend/DB"
  [redis-tools]="Backend/DB"
  [jupyter]="AI/ML"
  [claude-code]="AI/ML"
  [c-build]="Languages"
)

declare -A TOOL_DESC=(
  [gh]="GitHub CLI"
  [fastfetch]="System info (fastfetch)"
  [opencode]="OpenCode AI agent"
  [node]="Node.js LTS via nvm"
  [puppeteer]="Puppeteer + Chrome for Testing"
  [chrome]="Google Chrome stable (headless)"
  [docker]="Docker Engine + compose + buildx"
  [pip]="pip (python3-pip)"
  [eza]="eza (ls replacement)"
  [exa-mcp]="Exa web-search MCP (anonymous)"
  [pocock-skills]="Matt Pocock skills (48)"
  [go]="Go 1.23 LTS"
  [golangci-lint]="golangci-lint"
  [air]="Air (Go live reload)"
  [rust]="Rust stable via rustup"
  [bun]="Bun"
  [pnpm]="pnpm"
  [biome]="Biome"
  [vite]="Vite"
  [uv]="uv (Python package manager)"
  [ollama]="Ollama (local LLMs)"
  [qdrant]="Qdrant (vector DB, docker)"
  [postgres-client]="PostgreSQL client"
  [redis-tools]="Redis tools"
  [jupyter]="Jupyter"
  [claude-code]="Claude Code (AI CLI)"
  [c-build]="C/C++ build extras (cmake, pkg-config)"
)

declare -A PROFILE_TOOLS=(
  [default]="gh fastfetch opencode node puppeteer chrome docker pip eza exa-mcp pocock-skills"
  [go]="go golangci-lint air"
  [rust]="rust"
  [fe]="bun pnpm biome vite"
  [be]="postgres-client redis-tools"
  [python-ai]="uv jupyter ollama"
  [ai-agents]="uv jupyter ollama qdrant exa-mcp opencode claude-code"
  [full-stack-web]="docker chrome node"
)

# `full-stack-web` owns no Tool list of its own: it is `fe` + `be` plus the
# extras declared above, deduplicated, so those Profiles stay the single source
# of truth and a Tool added to either reaches the alias without anyone editing
# it. Overwrites the target in place, so every reader downstream -- the CLI, the
# TUI list, the preview -- just sees a Profile with a Tool list.
#
# One literal call, deliberately, not a registry: composition is this alias's
# mechanism, not a general one, and `ai-agents` restates `python-ai` rather than
# composing it. See ADR-0001.
compose_profile() {
  local target="$1"; shift
  local source tool
  local -A seen=()
  local out=()
  # The target's own extras come last, so composed Tools keep their source
  # Profile's order.
  for source in "$@" "$target"; do
    for tool in ${PROFILE_TOOLS[$source]}; do
      if [[ -z "${seen[$tool]:-}" ]]; then
        seen[$tool]=1
        out+=("$tool")
      fi
    done
  done
  PROFILE_TOOLS[$target]="${out[*]}"
}

compose_profile full-stack-web fe be

ORDERED_TOOLS=(gh fastfetch opencode node puppeteer chrome docker pip eza exa-mcp pocock-skills go golangci-lint air rust bun pnpm biome vite uv ollama qdrant postgres-client redis-tools jupyter claude-code c-build)

# The Install Step that delivers each Tool. Many-to-one on purpose: `install_go`
# delivers three Tools and `install_node_and_puppeteer` two, so the picker's
# unit (Tool) and the installer's unit (Install Step) are not the same thing.
# See ADR-0004.
#
# A Tool absent from this map has no Install Step at all. That is a real state,
# not a typo to be silently swallowed -- `claude-code` sits in the `ai-agents`
# Profile with nothing to install it -- so resolution collects those Tools and
# reports them by name.
declare -A TOOL_INSTALL_STEP=(
  [gh]=install_gh
  [fastfetch]=install_fastfetch
  [opencode]=install_opencode
  [node]=install_node_and_puppeteer
  [puppeteer]=install_node_and_puppeteer
  [chrome]=install_chrome_stable
  [docker]=install_docker
  [pip]=install_pip_eza
  [eza]=install_pip_eza
  [exa-mcp]=install_exa_mcp
  [pocock-skills]=install_pocock_skills
  [go]=install_go
  [golangci-lint]=install_go
  [air]=install_go
  [rust]=install_rust
  [bun]=install_bun
  [pnpm]=install_pnpm
  [biome]=install_biome
  [vite]=install_vite
  [uv]=install_uv
  [ollama]=install_ollama
  [qdrant]=install_qdrant
  [postgres-client]=install_postgres_client
  [redis-tools]=install_redis_tools
  [jupyter]=install_jupyter
  [c-build]=install_c_build
)

# Resolution output, filled by `resolve_install_steps` and read by everything
# that plans or reports a run:
#   RESOLVED_STEPS       Install Step function names, deduplicated, in order
#   RESOLVED_STEP_TOOLS  same index: the selected Tools that step delivers
#   RESOLVED_STEPLESS    selected Tools that no Install Step delivers
RESOLVED_STEPS=()
RESOLVED_STEP_TOOLS=()
RESOLVED_STEPLESS=()

# Turn the selected Toolset into the ordered list of Install Steps that
# delivers it. Pure: it reads SELECTED_TOOLS and writes the three arrays above,
# and installs nothing -- which is what lets `--dry-run` report the real plan
# rather than a second guess at it.
#
# Order comes from ORDERED_TOOLS, and a step lands at the position of the first
# selected Tool that pulls it in, so the same Toolset always plans the same run.
# A step's label is the Tools *the user selected* that route to it: picking
# `node` alone shows one Tool even though the step also lays down Puppeteer,
# because the label exists to connect what was picked to what is running.
resolve_install_steps() {
  RESOLVED_STEPS=()
  RESOLVED_STEP_TOOLS=()
  RESOLVED_STEPLESS=()
  local tool step idx
  local -A step_index=()
  for tool in "${ORDERED_TOOLS[@]}"; do
    [[ " ${SELECTED_TOOLS[*]:-} " == *" $tool "* ]] || continue
    step="${TOOL_INSTALL_STEP[$tool]:-}"
    if [[ -z "$step" ]]; then
      RESOLVED_STEPLESS+=("$tool")
      continue
    fi
    idx="${step_index[$step]:-}"
    if [[ -z "$idx" ]]; then
      idx=${#RESOLVED_STEPS[@]}
      step_index[$step]="$idx"
      RESOLVED_STEPS+=("$step")
      RESOLVED_STEP_TOOLS+=("$tool")
    else
      RESOLVED_STEP_TOOLS[idx]+=" $tool"
    fi
  done
}

# One line per Install Step, labelled by the Tools it delivers.
print_install_steps() {
  local prefix="${1:-}" i
  for i in "${!RESOLVED_STEPS[@]}"; do
    info "${prefix}Install Step: ${RESOLVED_STEPS[$i]} -> ${RESOLVED_STEP_TOOLS[$i]// /, }"
  done
}

# Selected Tools nothing installs. Named one by one: a Toolset that quietly
# delivers less than it lists is the failure this exists to make loud.
report_stepless_tools() {
  local prefix="${1:-}" tool
  for tool in "${RESOLVED_STEPLESS[@]}"; do
    warn "${prefix}No Install Step for tool: $tool - nothing installs it"
  done
}

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/dev-setup"
CONFIG_FILE="$CONFIG_DIR/config.json"

SELECTED_PROFILES=()
SELECTED_TOOLS=()
SKIP_AUTH=false
DRY_RUN=false
DO_YES=false
DO_ALL=false
DO_REPLAY=false
SEARCH_QUERY=""
LIST_PROFILES=false
LIST_TOOLS=false
INCLUDE_TOOLCHAIN=false

require_root() {
  if [[ "$DRY_RUN" == true ]]; then
    info "[DRY RUN] Would require root - skipping root check"
    return
  fi
  if [[ $EUID -ne 0 ]]; then
    error "Please run as root (sudo ./setup.sh)"
    exit 1
  fi
}

check_os() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    info "OS: $PRETTY_NAME ($VERSION_CODENAME)"
    if [[ "$VERSION_CODENAME" != "noble" ]]; then
      warn "Script tested on Ubuntu 24.04 noble - you have $VERSION_CODENAME, continuing anyway"
    fi
  fi
}

usage() {
  cat <<'USAGE'
Usage: sudo ./setup.sh [OPTIONS]

No args launches interactive TUI (fzf >= 0.60 required, auto-installs if missing).

Options:
  --profile=LIST     Comma-separated profiles: default,go,rust,fe,be,python-ai,ai-agents,full-stack-web
  --all              Install every tool
  --yes              Non-interactive, Default Toolset only (implies --no-auth prompt skipped? use --no-auth for CI)
  --search=QUERY     Install single tool matching fuzzy query (e.g. --search=postgres)
  --replay           Reuse last picks from ~/.config/dev-setup/config.json
  --dry-run          Simulate without installing (no apt/npm/docker, no config write, no root required)
  --no-auth          Skip final gh auth login
  --list-profiles    Print profiles and exit
  --list-tools       Print tool registry and exit
  --help             Show this help

Examples:
  sudo ./setup.sh
  sudo ./setup.sh --profile=go,rust --no-auth
  sudo ./setup.sh --profile=full-stack-web
  sudo ./setup.sh --all --no-auth
  sudo ./setup.sh --yes --no-auth
  sudo ./setup.sh --replay
  sudo ./setup.sh --dry-run --profile=go  # test without installing
USAGE
}

list_profiles() {
  echo "Profiles:"
  for k in "${!PROFILE_TOOLS[@]}"; do
    printf "  %-16s %s\n" "$k" "${PROFILE_TOOLS[$k]}"
  done | sort
}

list_tools() {
  echo "Tools (key | category | description):"
  for k in "${!TOOL_DESC[@]}"; do
    printf "  %-18s %-14s %s\n" "$k" "${TOOL_CATEGORY[$k]}" "${TOOL_DESC[$k]}"
  done | sort
}

save_config() {
  if [[ "$DRY_RUN" == true ]]; then
    info "[DRY RUN] Would save picks to $CONFIG_FILE (profiles: ${SELECTED_PROFILES[*]:-none}, tools: ${SELECTED_TOOLS[*]:-none})"
    return
  fi
  mkdir -p "$CONFIG_DIR"
  local profiles_json tools_json
  if [[ ${#SELECTED_PROFILES[@]} -eq 0 ]]; then
    profiles_json=""
  else
    profiles_json=$(printf '"%s",' "${SELECTED_PROFILES[@]}" | sed 's/,$//')
  fi
  if [[ ${#SELECTED_TOOLS[@]} -eq 0 ]]; then
    tools_json=""
  else
    tools_json=$(printf '"%s",' "${SELECTED_TOOLS[@]}" | sed 's/,$//')
  fi
  cat > "$CONFIG_FILE" <<JSON
{
  "profiles": [${profiles_json}],
  "tools": [${tools_json}],
  "toolchain": ${INCLUDE_TOOLCHAIN:-false},
  "updated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  info "Saved picks to $CONFIG_FILE"
}

load_config() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    error "No saved config at $CONFIG_FILE - run interactive picker first"
    exit 1
  fi
  if command -v jq >/dev/null 2>&1; then
    mapfile -t SELECTED_TOOLS < <(jq -r '.tools[]' "$CONFIG_FILE")
    mapfile -t SELECTED_PROFILES < <(jq -r '.profiles[]' "$CONFIG_FILE" 2>/dev/null || true)
    INCLUDE_TOOLCHAIN=$(jq -r '.toolchain // false' "$CONFIG_FILE")
  else
    mapfile -t SELECTED_TOOLS < <(grep -o '"tools"[^]]*]' "$CONFIG_FILE" | grep -o '"[^"]*"' | grep -v tools | tr -d '"')
    mapfile -t SELECTED_PROFILES < <(grep -o '"profiles"[^]]*]' "$CONFIG_FILE" | grep -o '"[^"]*"' | grep -v profiles | tr -d '"')
  fi
  info "Loaded ${#SELECTED_TOOLS[@]} tools from $CONFIG_FILE"
}

# The one place a Profile's Tool list is expanded, so the CLI (--profile=) and
# the picker's ENTER cannot drift apart. Appends, skipping Tools already in
# SELECTED_TOOLS - the picker needs to union an expansion onto Tools the user
# checked by hand.
append_profile_tools() {
  local p t
  for p in "$@"; do
    if [[ -z "${PROFILE_TOOLS[$p]:-}" ]]; then
      warn "Unknown profile: $p (skip)"
      continue
    fi
    for t in ${PROFILE_TOOLS[$p]}; do
      if [[ " ${SELECTED_TOOLS[*]:-} " != *" $t "* ]]; then SELECTED_TOOLS+=("$t"); fi
    done
  done
}

resolve_tools_from_profiles() {
  SELECTED_TOOLS=()
  append_profile_tools ${SELECTED_PROFILES[@]+"${SELECTED_PROFILES[@]}"}
}

# fzf >= 0.60 is required: --input-border and click-header do not exist in
# older builds. apt ships 0.44.1, so an existence check is NOT enough --
# it would silently accept a build that renders the TUI wrong. See ADR-0002.
FZF_VER="0.74.3"
FZF_BIN="fzf"
FZF_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/dev-setup"

fzf_capable() {
  local b="$1"
  command -v "$b" >/dev/null 2>&1 || [[ -x "$b" ]] || return 1
  grep -q -- --input-border <<<"$("$b" --help 2>&1)" || return 1
  echo x | "$b" --bind 'click-header:ignore' --filter=x >/dev/null 2>&1 || return 1
  return 0
}

ensure_fzf() {
  if fzf_capable "$FZF_BIN"; then return 0; fi
  if fzf_capable /usr/local/bin/fzf; then FZF_BIN=/usr/local/bin/fzf; return 0; fi
  if fzf_capable "$FZF_CACHE/fzf"; then FZF_BIN="$FZF_CACHE/fzf"; return 0; fi

  local have="none"
  command -v fzf >/dev/null 2>&1 && have=$(fzf --version 2>/dev/null | awk '{print $1}') || true

  # fzf is the picker's own dependency, not part of the Toolset being installed,
  # so --dry-run still fetches it - otherwise you could never dry-run the TUI.
  # It goes to the user cache, so "no root required" still holds.
  local dest="/usr/local/bin/fzf" where="system"
  if [[ "$DRY_RUN" == true || $EUID -ne 0 ]]; then
    mkdir -p "$FZF_CACHE"; dest="$FZF_CACHE/fzf"; where="user cache"
  fi
  step "Installing fzf $FZF_VER to $where (required for TUI) - found: $have"

  local url="https://github.com/junegunn/fzf/releases/download/v${FZF_VER}/fzf-${FZF_VER}-linux_amd64.tar.gz"
  local tmpdir; tmpdir=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf '$tmpdir'" RETURN
  if curl -fsSL "$url" -o "$tmpdir/fzf.tar.gz" && tar -xzf "$tmpdir/fzf.tar.gz" -C "$tmpdir" 2>/dev/null; then
    if install -m 0755 "$tmpdir/fzf" "$dest" 2>/dev/null && fzf_capable "$dest"; then
      FZF_BIN="$dest"; info "fzf $FZF_VER installed at $dest"; return 0
    fi
    # last resort: fall back to the cache even if the system path was intended
    mkdir -p "$FZF_CACHE"
    if install -m 0755 "$tmpdir/fzf" "$FZF_CACHE/fzf" 2>/dev/null && fzf_capable "$FZF_CACHE/fzf"; then
      FZF_BIN="$FZF_CACHE/fzf"; info "fzf $FZF_VER installed at $FZF_BIN"; return 0
    fi
  fi
  error "fzf >= 0.60 required for interactive mode and could not be installed."
  error "Install one manually: https://github.com/junegunn/fzf/releases"
  return 1
}
dry_run_guard() {
  if [[ "$DRY_RUN" == true ]]; then
    info "[DRY RUN] Would $*"
    return 0
  fi
  return 1
}



# ------------------------------------------------------------------------------
# TUI (fzf). A check lives in TUI_STATE and `tui_list` paints it; fzf's own
# selection goes unused, because a `reload` clears it and the Category tab
# strip reloads on every switch. Item type is carried by the MARKER GLYPH, not
# the key: `go` and `rust` are each both a Profile key and a Tool key, so a
# name lookup mistypes them. See ADR-0010 and ADR-0003.
# ------------------------------------------------------------------------------
# `set -u` kills a command substitution before its `2>/dev/null || echo 0`
# fallback can fire, so TUI_STATE needs a real default, not a guarded read.
TUI_STATE="${TUI_STATE:-}"
tui_tab_index() {
  if [[ -n "$TUI_STATE" && -r "$TUI_STATE/tab" ]]; then cat "$TUI_STATE/tab"; else echo 0; fi
}

# The picker exports TUI_STATE; a callback run by hand has no state dir, and an
# unguarded "$TUI_STATE/tab" is then "/tab" — which as root creates a file at the
# filesystem root instead of failing. Callbacks that only render degrade to the
# defaults (see tui_tab_index, tui_header); callbacks that exist to mutate state
# have nothing to mutate, so they say so and stop.
tui_state_required() {
  if [[ -z "$TUI_STATE" || ! -d "$TUI_STATE" ]]; then
    echo "TUI_STATE is unset or not a directory - $1 is an fzf callback, not a standalone command" >&2
    exit 1
  fi
}

# The state is two sets, one key per line: `checked` holds the Tools that will
# install, `profiles` holds the Profile keys the user toggled. The Profile keys
# are provenance for config.json and --replay, and are ignored at resolution.
# These five and tui_seed_defaults, which starts both sets empty, are the only
# things that touch the files, so the on-disk format is one edit rather than a
# dozen. See ADR-0010.
tui_state_lines() {
  # Blank lines are stripped here rather than at four call sites, and by `sed`
  # reading the file rather than `cat` piped into one, so it stays one fork.
  if [[ -n "$TUI_STATE" && -r "$TUI_STATE/$1" ]]; then sed '/^$/d' "$TUI_STATE/$1"; fi
}
# Membership in a newline-bracketed blob, so a whole-line match is a plain
# substring test. Callers that already hold the blob use it directly: a
# function call costs no fork, and tui_list runs this once per row.
tui_set_has() { [[ "$1" == *$'\n'"$2"$'\n'* ]]; }
# The brackets are concatenated onto the substitution rather than printf'd
# through one: `$(...)` strips trailing newlines, and the last key in the set
# would then never match.
tui_state_has() { tui_set_has $'\n'"$(tui_state_lines "$1")"$'\n' "$2"; }
tui_state_add() { tui_state_has "$1" "$2" || printf '%s\n' "$2" >>"$TUI_STATE/$1"; }
tui_state_remove() {
  local f="$TUI_STATE/$1" rc=0
  [[ -r "$f" ]] || return 0
  # grep exits 1 when it removes the only line, which is a success here. Its
  # exit 2 is not: writing a truncated .tmp over the state would silently drop
  # every other check.
  grep -vxF -- "$2" "$f" >"$f.tmp" || rc=$?
  if (( rc > 1 )); then
    rm -f "$f.tmp"
    echo "tui_state_remove: grep failed on $f - state left alone" >&2
    return 1
  fi
  mv "$f.tmp" "$f"
}

TUI_MARK_PROFILE="◆"
TUI_MARK_TOOL="·"
# The check reads as a checkbox to someone who has never seen the picker, and
# sits in FRONT of the type glyph, so ADR-0003's rule survives one field right.
TUI_CHECK_ON=$'\033[32m[x]\033[0m'
TUI_CHECK_OFF=$'\033[90m[ ]\033[0m'
TUI_TABS=(All Languages Frontend "Backend/DB" AI/ML Infra/DevOps)

tui_row_profile() { printf '%s \033[35m%s %-16s\033[0m \033[90m%s\033[0m\n' "$1" "$TUI_MARK_PROFILE" "$2" "$3"; }
tui_row_tool()    { printf '%s \033[36m%s %-16s\033[0m \033[90m%-14s %s\033[0m\n' "$1" "$TUI_MARK_TOOL" "$2" "$3" "$4"; }

# The check marker is a fixed four-character prefix, stripped by width rather
# than as a field, because `[ ] ` holds a space of its own.
tui_plain() { sed -E 's/\x1b\[[0-9;]*m//g; s/^\[.\] //' <<<"$1"; }
tui_key()  { sed -E 's/\x1b\[[0-9;]*m//g; s/^\[.\] //; s/^[^ ]+ +//; s/ .*//' <<<"$1"; }
tui_type() { case "$(tui_plain "$1")" in "$TUI_MARK_PROFILE"*) echo profile ;; *) echo tool ;; esac; }

# Profiles head the All tab and appear on no other. A Profile row is a macro
# that checks its member Tools, so it can only live on a list that holds them;
# the old Profiles tab listed Profile rows and no Tool rows, which is the one
# place the macro could never fire. See ADR-0009.
#
# The state is read once into a blob, not once per row: the fork is the read,
# and this is the one function the picker re-runs on every keystroke.
tui_list() {
  local tab="${TUI_TABS[$(tui_tab_index)]}"
  local checked profiles p k mark
  checked=$'\n'"$(tui_state_lines checked)"$'\n'
  profiles=$'\n'"$(tui_state_lines profiles)"$'\n'
  if [[ "$tab" == "All" ]]; then
    while IFS= read -r p; do
      if tui_set_has "$profiles" "$p"; then mark="$TUI_CHECK_ON"; else mark="$TUI_CHECK_OFF"; fi
      tui_row_profile "$mark" "$p" "${PROFILE_TOOLS[$p]}"
    done < <(printf '%s\n' "${!PROFILE_TOOLS[@]}" | sort)
  fi
  for k in "${ORDERED_TOOLS[@]}"; do
    [[ -z "${TOOL_DESC[$k]:-}" ]] && continue
    [[ "$tab" != "All" && "${TOOL_CATEGORY[$k]}" != "$tab" ]] && continue
    if tui_set_has "$checked" "$k"; then mark="$TUI_CHECK_ON"; else mark="$TUI_CHECK_OFF"; fi
    tui_row_tool "$mark" "$k" "${TOOL_CATEGORY[$k]}" "${TOOL_DESC[$k]}"
  done
}

tui_header() {
  local idx col=0 label line="" cols=/dev/null
  idx=$(tui_tab_index)
  # The column map only exists for tui_tab_click to read back; with no state dir
  # there is nobody to read it, and the header still has to render.
  [[ -n "$TUI_STATE" && -d "$TUI_STATE" ]] && cols="$TUI_STATE/cols"
  : >"$cols"
  for i in "${!TUI_TABS[@]}"; do
    label=" ${TUI_TABS[$i]} "
    echo "$col $((col + ${#label})) $i" >>"$cols"
    if [[ "$i" == "$idx" ]]; then line+=$'\033[7;36m'"$label"$'\033[0m'
    else line+=$'\033[90m'"$label"$'\033[0m'; fi
    col=$((col + ${#label}))
  done
  printf '%s\n' "$line"
  printf '\033[90m  ←/→ or click a tab · TAB checks (◆ checks its Tools) · ENTER installs · ESC cancels\033[0m\n'
}

tui_preview() {
  local cur="$1"
  local key type
  key=$(tui_key "$cur"); type=$(tui_type "$cur")

  if [[ "$type" == profile && -n "${PROFILE_TOOLS[$key]:-}" ]]; then
    local exp="${PROFILE_TOOLS[$key]}"
    printf '\033[35mPROFILE\033[0m  %s\n\n\033[90m%s tools:\033[0m\n' "$key" "$(wc -w <<<"$exp")"
    for t in $exp; do printf '  \033[36m·\033[0m %s\n' "$t"; done
    # The macro is one-way: it only ever adds, so the blurb has to say that
    # turning the label off is not an uninstall. See ADR-0009.
    if tui_state_has profiles "$key"; then
      printf '\n\033[90mIts Tools are checked in the list - uncheck any and\nit sticks. TAB again drops the label, not the Tools.\033[0m\n'
    else
      printf '\n\033[90mTAB checks these Tools - presets, not locks, so you\ncan uncheck any of them.\033[0m\n'
    fi
  elif [[ -n "${TOOL_DESC[$key]:-}" ]]; then
    printf '\033[36mTOOL\033[0m     %s\n\n  category: %s\n  %s\n' "$key" "${TOOL_CATEGORY[$key]}" "${TOOL_DESC[$key]}"
    printf '\n\033[90mIn profiles:\033[0m\n'
    for p in "${!PROFILE_TOOLS[@]}"; do
      for t in ${PROFILE_TOOLS[$p]}; do if [[ "$t" == "$key" ]]; then printf '  ◆ %s\n' "$p"; break; fi; done
    done | sort
  fi

  # The live Toolset, read from the state rather than from fzf's selection:
  # what is on the screen and what will install are the same thing, read from
  # one place. It does not depend on the row being hovered. See ADR-0010.
  # Sorted and deduplicated once, at read time, so the count and the list below
  # it are the same array and cannot disagree.
  local profs=() tools=() n=0
  mapfile -t profs < <(tui_state_lines profiles)
  mapfile -t tools < <(tui_state_lines checked | sort -u)
  n=${#tools[@]}
  local w inner edge sep
  w=${FZF_PREVIEW_COLUMNS:-52}; (( w < 24 )) && w=24 || true; inner=$((w - 2))
  edge=$(printf '%*s' "$inner" '' | sed 's/ /─/g')
  sep=$(printf '%*s' $((inner - 2)) '' | sed 's/ /─/g')
  printf '\n\033[90m╭─\033[0m \033[1mSelected Toolset\033[0m \033[90m%s╮\033[0m\n' \
    "$(printf '%*s' $((inner - 20)) '' | sed 's/ /─/g')"
  # The Profile labels print even with nothing checked: they go to config.json
  # either way, and a panel that hides them disagrees with what --replay saves.
  if (( ${#profs[@]} )); then printf '\033[90m│\033[0m \033[35mprofiles:\033[0m %s\n' "${profs[*]}"; fi
  if (( n == 0 )); then
    printf '\033[90m│\033[0m \033[90mnothing checked yet - TAB to check a row\033[0m\n'
  else
    printf '\033[90m│\033[0m \033[90m%s\033[0m\n' "$sep"
    printf '\033[90m│\033[0m \033[1m%s tools will install:\033[0m\n' "$n"
    printf '%s\n' "${tools[@]}" | paste -d' ' - - - 2>/dev/null | while read -r l; do
      if [[ -n "$l" ]]; then printf '\033[90m│\033[0m   \033[32m%s\033[0m\n' "$l"; fi
    done
  fi
  printf '\033[90m╰%s╯\033[0m\n' "$edge"
}

tui_tab_shift() {
  tui_state_required __tui_tab
  local idx n; idx=$(tui_tab_index); n=${#TUI_TABS[@]}
  [[ "$1" == next ]] && idx=$(( (idx+1) % n )) || idx=$(( (idx-1+n) % n ))
  echo "$idx" >"$TUI_STATE/tab"
}

tui_tab_click() {
  tui_state_required __tui_click
  local c=${FZF_CLICK_HEADER_COLUMN:-0} s e i
  while read -r s e i; do
    if (( c > s && c <= e )); then echo "$i" >"$TUI_STATE/tab"; return; fi
  done <"$TUI_STATE/cols"
}

# TAB. Records the toggle into the state; the picker's `reload` then redraws
# the marker from it. Not a `transform` any more, because nothing about the
# action chain depends on the list: no position is computed, so there is no
# query to guard against and no complete-or-label rule to apply. See ADR-0010.
tui_toggle() {
  tui_state_required __tui_toggle
  local cur="$1" key type t
  key=$(tui_key "$cur"); type=$(tui_type "$cur")
  [[ -z "$key" ]] && return 0

  # Only a Profile row is a macro. Type comes from the glyph: the Tool `go` and
  # the Profile `go` are different rows with the same key (ADR-0003).
  if [[ "$type" == profile && -n "${PROFILE_TOOLS[$key]:-}" ]]; then
    if tui_state_has profiles "$key"; then
      # One-way: un-toggling removes the label and nothing else. The
      # alternative needs per-Tool provenance ("was `air` checked by the macro,
      # or by you?") to answer a question nobody asked. See ADR-0009.
      tui_state_remove profiles "$key"
    else
      tui_state_add profiles "$key"
      for t in ${PROFILE_TOOLS[$key]}; do tui_state_add checked "$t"; done
    fi
    return 0
  fi

  if tui_state_has checked "$key"; then tui_state_remove checked "$key"
  else tui_state_add checked "$key"; fi
}

# The Default Toolset is seeded into the state once, before the picker opens,
# and never reapplied - "presets, not locks" is false if the preset reapplies
# itself behind the user. It replaces the `start:` binding of pos(N)+select
# pairs, which fired before fzf had finished reading the piped list and so
# preselected nothing on one run in three (#33). See ADR-0010.
tui_seed_defaults() {
  tui_state_required __tui_seed
  local t
  # The one place that writes the files without going through tui_state_add:
  # it establishes both sets from nothing, which "add if absent" cannot do.
  : >"$TUI_STATE/checked"
  : >"$TUI_STATE/profiles"
  for t in ${PROFILE_TOOLS[default]}; do tui_state_add checked "$t"; done
}

# ENTER. The state is the answer: the checked Tools install, and the Profile
# keys are provenance only. Nothing is expanded here, so a member the user
# unchecked stays unchecked instead of being resurrected. See ADR-0010.
tui_resolve_toolset() {
  tui_state_required __tui_resolve
  mapfile -t SELECTED_PROFILES < <(tui_state_lines profiles)
  mapfile -t SELECTED_TOOLS < <(tui_state_lines checked)
}

interactive_picker() {
  ensure_fzf || exit 1
  step "Interactive setup"

  TUI_STATE=$(mktemp -d); export TUI_STATE
  # shellcheck disable=SC2064
  trap "rm -rf '$TUI_STATE'" RETURN
  echo 0 >"$TUI_STATE/tab"
  tui_seed_defaults

  # fzf's exit status is the whole answer now that the picker prints nothing we
  # read. Measured against 0.74.3 through a pty: ENTER on a matching list is 0,
  # ENTER on a query that matches NOTHING is 1, and ESC or ctrl-c is 130. So 1
  # is an accept, not a cancel - the state set does not care what the query was
  # filtering when ENTER landed, and treating it as a cancel would throw away
  # every check the user had made.
  local self rc=0
  self=$(readlink -f "${BASH_SOURCE[0]}")
  tui_list | "$FZF_BIN" --ansi \
    --border=rounded --border-label=' Interactive setup ' \
    --input-border=rounded --input-label=' Search ' \
    --header-border=rounded --padding=1 --margin=1 \
    --prompt='  ' --ghost='type to filter…' \
    --pointer='▶' --height=100% --header-first \
    --header="$(tui_header)" \
    --preview="'$self' __tui_preview {}" \
    --preview-window='right,48%,border-rounded' --preview-label=' details ' \
    --bind "left:execute-silent(\"$self\" __tui_tab prev)+clear-query+transform-header(\"$self\" __tui_header)+reload(\"$self\" __tui_list)+refresh-preview" \
    --bind "right:execute-silent(\"$self\" __tui_tab next)+clear-query+transform-header(\"$self\" __tui_header)+reload(\"$self\" __tui_list)+refresh-preview" \
    --bind "click-header:execute-silent(\"$self\" __tui_click)+clear-query+transform-header(\"$self\" __tui_header)+reload(\"$self\" __tui_list)+refresh-preview" \
    --bind "tab:execute-silent(\"$self\" __tui_toggle {})+reload(\"$self\" __tui_list)+refresh-preview" \
    >/dev/null || rc=$?

  SELECTED_PROFILES=(); SELECTED_TOOLS=()
  case "$rc" in
    0|1) ;;
    130) info "Cancelled."; return 0 ;;
    *)   error "Picker exited with status $rc - treating it as a cancel."; return 0 ;;
  esac

  tui_resolve_toolset
  # An empty set installs nothing, and says so. A picker where cancelling
  # installs eleven packages is a bug wearing a fallback's clothes; --yes stays
  # the deliberate way to ask for the Default Toolset. See ADR-0010.
  if (( ${#SELECTED_TOOLS[@]} == 0 )); then
    warn "Nothing checked - run with --yes if you want the Default Toolset."
    return 0
  fi

  if (( ${#SELECTED_PROFILES[@]} )); then
    info "Profiles: ${SELECTED_PROFILES[*]} -> ${#SELECTED_TOOLS[@]} tools"
  else
    info "Tools chosen directly: ${SELECTED_TOOLS[*]}"
  fi

  read -rp "Include toolchain PATH setup in ~/.bashrc? [y/N] " ans
  [[ "$ans" == [yY]* ]] && INCLUDE_TOOLCHAIN=true || INCLUDE_TOOLCHAIN=false

  info "Tools chosen: ${SELECTED_TOOLS[*]}"
  save_config
}


parse_args() {
  for arg in "$@"; do
    case "$arg" in
      --help|-h) usage; exit 0 ;;
      --yes) DO_YES=true ;;
      --all) DO_ALL=true ;;
      --dry-run) DRY_RUN=true ;;
      --no-auth) SKIP_AUTH=true ;;
      --replay) DO_REPLAY=true ;;
      --list-profiles) LIST_PROFILES=true ;;
      --list-tools) LIST_TOOLS=true ;;
      --profile=*) IFS=',' read -ra SELECTED_PROFILES <<< "${arg#--profile=}" ;;
      --search=*) SEARCH_QUERY="${arg#--search=}" ;;
      --no-toolchain) INCLUDE_TOOLCHAIN=false ;;
      *) warn "Unknown arg: $arg"; usage; exit 1 ;;
    esac
  done
}

# ------------------------------------------------------------------------------
# 0. System update + base deps
# ------------------------------------------------------------------------------
install_base_deps() {
  step "Updating apt + installing base dependencies"
  apt-get update -y
  apt-get install -y \
    ca-certificates curl wget gnupg lsb-release \
    apt-transport-https software-properties-common \
    unzip build-essential
  # upgrade is optional - uncomment if you want full upgrade
  # apt-get upgrade -y
}

# ------------------------------------------------------------------------------
# 1. GitHub CLI
# ------------------------------------------------------------------------------
install_gh() {
  step "Installing GitHub CLI"
  if command -v gh >/dev/null 2>&1; then
    info "gh already installed: $(gh --version | head -n1) - skipping"
    return
  fi
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg status=none
  chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list
  apt-get update -y
  apt-get install -y gh
  info "gh installed: $(gh --version | head -n1)"
}

# ------------------------------------------------------------------------------
# 2. fastfetch
# ------------------------------------------------------------------------------
install_fastfetch() {
  step "Installing fastfetch"
  if command -v fastfetch >/dev/null 2>&1; then
    info "fastfetch already installed: $(fastfetch --version 2>&1 | head -n1) - skipping"
    return
  fi
  add-apt-repository -y ppa:zhangsongcui3371/fastfetch
  apt-get update -y
  apt-get install -y fastfetch
  info "fastfetch installed: $(fastfetch --version 2>&1 | head -n1)"
}

# ------------------------------------------------------------------------------
# 3. opencode (via official installer)
# ------------------------------------------------------------------------------
install_opencode() {
  step "Installing opencode"
  if command -v opencode >/dev/null 2>&1; then
    info "opencode already installed: $(opencode --version 2>&1 | head -n1) - skipping"
    return
  fi
  curl -fsSL https://opencode.ai/install | bash
  # installer puts binary in ~/.opencode/bin or /root/.opencode/bin
  export PATH="$HOME/.opencode/bin:$PATH"
  if ! command -v opencode >/dev/null 2>&1 && [[ -x "$HOME/.opencode/bin/opencode" ]]; then
    ln -sf "$HOME/.opencode/bin/opencode" /usr/local/bin/opencode 2>/dev/null || true
  fi
  # ensure PATH for future shells
  if ! grep -q '.opencode/bin' ~/.bashrc 2>/dev/null; then
    echo 'export PATH="$HOME/.opencode/bin:$PATH"' >> ~/.bashrc
  fi
  info "opencode installed: $(opencode --version 2>&1 | head -n1)"
  # ensure config exists
  mkdir -p ~/.config/opencode
  if [[ ! -f ~/.config/opencode/opencode.jsonc ]]; then
    echo '{ "$schema": "https://opencode.ai/config.json" }' > ~/.config/opencode/opencode.jsonc
  fi
}

# ------------------------------------------------------------------------------
# 4. Node via nvm (LTS) + Puppeteer + Chrome for Testing
# ------------------------------------------------------------------------------
install_node_and_puppeteer() {
  step "Installing Node LTS via nvm + Puppeteer"
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

  if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
    info "Installing nvm 0.40.3"
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
  else
    info "nvm already installed at $NVM_DIR - skipping install"
  fi

  # shellcheck disable=SC1091
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
  [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

  # install LTS if not present
  if ! nvm ls | grep -q "lts"; then
    nvm install --lts
  else
    info "Node LTS already present: $(nvm ls 2>&1 | grep -E 'lts/\*|v[0-9]' | head -n1)"
    nvm install --lts  # ensures latest LTS
  fi
  nvm alias default 'lts/*' >/dev/null 2>&1 || true
  nvm use --lts

  info "Node: $(node -v)  npm: $(npm -v)  npx: $(npx -v)"

  # Puppeteer global
  if npm list -g puppeteer >/dev/null 2>&1; then
    info "puppeteer already installed globally - updating"
  fi
  npm install -g puppeteer

  # Chrome for Testing via puppeteer (needs unzip - already in base deps)
  # clear broken cache if any, then install
  if [[ -d "$HOME/.cache/puppeteer" ]]; then
    # check if binary missing but folder exists (previous partial install)
    if ! ls "$HOME/.cache/puppeteer/chrome/linux-"*/chrome-linux64/chrome >/dev/null 2>&1; then
      warn "Clearing incomplete puppeteer cache"
      rm -rf "$HOME/.cache/puppeteer"
    fi
  fi
  # install chrome + headless shell
  if ! ls "$HOME/.cache/puppeteer/chrome/linux-"*/chrome-linux64/chrome >/dev/null 2>&1; then
    npx --yes puppeteer browsers install chrome
  else
    info "puppeteer chrome already cached - skipping"
  fi
  if ! ls "$HOME/.cache/puppeteer/chrome-headless-shell/linux-"*/chrome-headless-shell-linux64/chrome-headless-shell >/dev/null 2>&1; then
    npx --yes puppeteer browsers install chrome-headless-shell
  fi
  # ensure system deps for headless chrome
  npx --yes puppeteer browsers install chrome --install-deps 2>&1 | tail -n 20 || \
    apt-get install -y libatk1.0-0 libatk-bridge2.0-0 libcups2 libdbus-1-3 libdrm2 libgbm1 libgtk-3-0 libnspr4 libnss3 libxcomposite1 libxdamage1 libxfixes3 libxrandr2 libxss1 libxtst6 libasound2t64

  # smoke test
  info "Verifying puppeteer can launch (headless --no-sandbox)"
  NODE_PATH="$(npm root -g)" node -e "
    const puppeteer = require('puppeteer');
    (async () => {
      const browser = await puppeteer.launch({headless: true, args: ['--no-sandbox','--disable-setuid-sandbox']});
      const page = await browser.newPage();
      await page.goto('https://example.com', {waitUntil: 'domcontentloaded'});
      console.log('  puppeteer title:', await page.title());
      await browser.close();
      console.log('  puppeteer OK');
    })();
  "
}

# ------------------------------------------------------------------------------
# 5. Google Chrome stable (system, for frontend testing outside puppeteer)
# ------------------------------------------------------------------------------
install_chrome_stable() {
  step "Installing Google Chrome stable"
  if command -v google-chrome-stable >/dev/null 2>&1; then
    info "google-chrome-stable already installed: $(google-chrome-stable --version) - skipping"
    return
  fi
  mkdir -p /etc/apt/keyrings
  # Google signing key
  if [[ ! -f /usr/share/keyrings/google-chrome.gpg ]]; then
    wget -q -O /tmp/google-chrome.gpg https://dl.google.com/linux/linux_signing_key.pub
    gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg /tmp/google-chrome.gpg
    rm -f /tmp/google-chrome.gpg
  fi
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" \
    > /etc/apt/sources.list.d/google-chrome.list
  apt-get update -y
  apt-get install -y google-chrome-stable
  info "Chrome installed: $(google-chrome-stable --version)"
  # verify headless
  google-chrome-stable --headless --disable-gpu --no-sandbox --dump-dom https://example.com 2>&1 | head -n 5 | grep -q "Example Domain" && info "Chrome headless OK" || warn "Chrome headless check failed"
}

# ------------------------------------------------------------------------------
# 6. Docker Engine + compose plugin
# ------------------------------------------------------------------------------
install_docker() {
  step "Installing Docker Engine + compose"
  if command -v docker >/dev/null 2>&1; then
    info "docker already installed: $(docker --version) - skipping"
    return
  fi
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
  info "Docker installed: $(docker --version) + $(docker compose version)"
  # verify
  docker run --rm hello-world 2>&1 | grep -q "Hello from Docker" && info "Docker hello-world OK" || warn "Docker hello-world failed - check daemon"
}

# ------------------------------------------------------------------------------
# 7. pip + eza
# ------------------------------------------------------------------------------
install_pip_eza() {
  step "Installing pip + eza"
  if command -v pip3 >/dev/null 2>&1; then
    info "pip3 already installed: $(pip3 --version) - skipping"
  else
    apt-get install -y python3-pip
    info "pip3 installed: $(pip3 --version)"
  fi
  if command -v eza >/dev/null 2>&1; then
    info "eza already installed: $(eza --version | head -n1) - skipping"
  else
    apt-get install -y eza
    info "eza installed: $(eza --version | head -n1)"
  fi
}

# ------------------------------------------------------------------------------
# 8. Exa MCP (anonymous hosted)
# ------------------------------------------------------------------------------
install_exa_mcp() {
  step "Configuring Exa web-search MCP (anonymous)"
  export PATH="$HOME/.opencode/bin:$PATH"
  if opencode mcp list 2>&1 | grep -q "exa.*connected"; then
    info "Exa MCP already connected - skipping"
    opencode mcp list
    return
  fi
  # remove stale local config if present in repo .opencode
  if [[ -f .opencode/opencode.json ]]; then
    warn "Found local .opencode/opencode.json - leaving untouched, configuring global"
  fi
  # add remote hosted MCP (anonymous, rate-limited). For API key: --url "https://mcp.exa.ai/mcp?exaApiKey=YOUR_KEY"
  opencode mcp add exa --url "https://mcp.exa.ai/mcp" 2>&1 || {
    # if already exists, try to show status
    warn "opencode mcp add exa failed - maybe already configured"
  }
  opencode mcp list || true
  info "Exa MCP configured at ~/.config/opencode/opencode.jsonc - add ?exaApiKey=... for higher limits"
}

# ------------------------------------------------------------------------------
# 9. Matt Pocock skills (opencode agent)
# ------------------------------------------------------------------------------
install_pocock_skills() {
  step "Installing Matt Pocock skills (opencode)"
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  # shellcheck disable=SC1091
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
  if ! command -v node >/dev/null 2>&1; then
    error "node not found - nvm step must run first"
    return 1
  fi
  # skills CLI is npx - no global install needed
  # Primary: mattpocock/skills (36 skills) + opencode fork for extra coverage
  npx --yes skills add mattpocock/skills --global --agent opencode --all -y || warn "mattpocock/skills install had warnings (some agents like Eve unsupported - OK for opencode)"
  npx --yes skills add fullheart/mattpocock-skills-opencode --global --agent opencode --all -y || warn "opencode fork install had warnings - OK"
  info "Skills installed: $(ls -1 ~/.agents/skills 2>/dev/null | wc -l) in ~/.agents/skills"
  npx --yes skills list -g 2>&1 | head -n 40 || true
  # Create slash commands so skills appear on "/" in TUI
  mkdir -p ~/.config/opencode/commands
  for skill in ~/.agents/skills/*; do
    skill=$(basename "$skill")
    [[ ! -d ~/.agents/skills/"$skill" ]] && continue
    if [[ ! -f ~/.config/opencode/commands/$skill.md ]]; then
      desc=$(grep -m1 "^description:" ~/.agents/skills/$skill/SKILL.md 2>/dev/null | sed 's/description:\s*//' | head -c 120)
      cat > ~/.config/opencode/commands/$skill.md <<CMDEOF
---
description: $desc
---
Use the skill "$skill" - load it via the skill tool. Follow its SKILL.md instructions exactly.
CMDEOF
    fi
  done
  info "Slash commands created: $(ls ~/.config/opencode/commands | wc -l) in ~/.config/opencode/commands"
}

# ------------------------------------------------------------------------------
# 10a. Go LTS
# ------------------------------------------------------------------------------
install_go() {
  step "Installing Go LTS"
  if command -v go >/dev/null 2>&1; then
    info "go already installed: $(go version) - skipping"
    return
  fi
  local ver="1.23.5"
  local arch
  arch=$(dpkg --print-architecture)
  if [[ "$arch" == "amd64" ]]; then arch="amd64"; else arch="arm64"; fi
  curl -fsSL "https://go.dev/dl/go${ver}.linux-${arch}.tar.gz" -o /tmp/go.tar.gz
  rm -rf /usr/local/go
  tar -C /usr/local -xzf /tmp/go.tar.gz
  rm /tmp/go.tar.gz
  if ! grep -q "/usr/local/go/bin" ~/.bashrc 2>/dev/null; then
    echo 'export PATH="/usr/local/go/bin:$PATH"' >> ~/.bashrc
  fi
  export PATH="/usr/local/go/bin:$PATH"
  info "go installed: $(go version)"
  # golangci-lint + air (optional)
  if ! command -v golangci-lint >/dev/null 2>&1; then
    curl -fsSL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b /usr/local/bin 2>&1 | tail -n 5 || warn "golangci-lint install failed"
  fi
  if ! command -v air >/dev/null 2>&1; then
    go install github.com/air-verse/air@latest 2>&1 | tail -n 5 || warn "air install failed"
    export PATH="$HOME/go/bin:$PATH"
  fi
}

# ------------------------------------------------------------------------------
# 10b. Rust stable
# ------------------------------------------------------------------------------
install_rust() {
  step "Installing Rust stable via rustup"
  if command -v rustc >/dev/null 2>&1; then
    info "rustc already installed: $(rustc --version) - skipping"
    return
  fi
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
  # shellcheck disable=SC1091
  [ -s "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
  info "rust installed: $(rustc --version 2>&1 | head -n1 || true)"
}

# ------------------------------------------------------------------------------
# 10c. Bun / pnpm / Biome / Vite via npm
# ------------------------------------------------------------------------------
install_bun() {
  step "Installing Bun"
  if command -v bun >/dev/null 2>&1; then
    info "bun already installed: $(bun --version) - skipping"
    return
  fi
  curl -fsSL https://bun.sh/install | bash
  export PATH="$HOME/.bun/bin:$PATH"
  info "bun installed: $(bun --version 2>&1 | head -n1 || true)"
}

install_pnpm() {
  step "Installing pnpm"
  if command -v pnpm >/dev/null 2>&1; then
    info "pnpm already installed: $(pnpm --version) - skipping"
    return
  fi
  export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  npm install -g pnpm
  info "pnpm installed: $(pnpm --version)"
}

install_biome() {
  step "Installing Biome"
  export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  npm install -g @biomejs/biome 2>&1 | tail -n 5 || warn "biome install via npm failed"
}

install_vite() {
  step "Installing Vite"
  export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  npm install -g vite 2>&1 | tail -n 5 || warn "vite install via npm failed"
}

# ------------------------------------------------------------------------------
# 10d. uv / Jupyter / Ollama / Qdrant
# ------------------------------------------------------------------------------
install_uv() {
  step "Installing uv"
  if command -v uv >/dev/null 2>&1; then
    info "uv already installed: $(uv --version) - skipping"
    return
  fi
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
  info "uv installed: $(uv --version 2>&1 | head -n1 || true)"
}

install_jupyter() {
  step "Installing Jupyter"
  if command -v jupyter >/dev/null 2>&1; then
    info "jupyter already installed - skipping"
    return
  fi
  pip3 install --no-cache-dir jupyter 2>&1 | tail -n 5 || warn "jupyter pip install failed"
}

install_ollama() {
  step "Installing Ollama"
  if command -v ollama >/dev/null 2>&1; then
    info "ollama already installed: $(ollama --version 2>&1 | head -n1 || true) - skipping"
    return
  fi
  curl -fsSL https://ollama.com/install.sh | sh
  info "ollama installed"
}

install_qdrant() {
  step "Installing Qdrant (docker)"
  if docker ps -a 2>&1 | grep -q qdrant; then
    info "qdrant container already exists - skipping"
    return
  fi
  docker pull qdrant/qdrant 2>&1 | tail -n 5
  docker run -d --name qdrant -p 6333:6333 -p 6334:6334 qdrant/qdrant 2>&1 | tail -n 5 || warn "qdrant container start failed"
}

install_postgres_client() {
  step "Installing PostgreSQL client"
  if command -v psql >/dev/null 2>&1; then
    info "psql already installed: $(psql --version) - skipping"
    return
  fi
  apt-get install -y postgresql-client
}

install_redis_tools() {
  step "Installing Redis tools"
  if command -v redis-cli >/dev/null 2>&1; then
    info "redis-cli already installed - skipping"
    return
  fi
  apt-get install -y redis-tools
}

# gcc and make arrive with build-essential in install_base_deps on every run,
# whatever the Toolset. cmake and pkg-config are what this Tool uniquely adds,
# and all it installs. See ADR-0001.
install_c_build() {
  step "Installing C/C++ build extras"
  if command -v cmake >/dev/null 2>&1 && command -v pkg-config >/dev/null 2>&1; then
    info "cmake and pkg-config already installed - skipping"
    return
  fi
  apt-get install -y cmake pkg-config
}

# ------------------------------------------------------------------------------
# 10. GitHub auth (interactive - last so it doesn't block)
# ------------------------------------------------------------------------------
github_auth() {
  step "GitHub CLI auth (interactive)"
  if gh auth status 2>&1 | grep -q "Logged in"; then
    info "Already logged in:"
    gh auth status 2>&1 | sed 's/^/  /'
    read -rp "Re-authenticate? [y/N] " ans
    if [[ "$ans" != "y" && "$ans" != "Y" ]]; then
      return
    fi
  fi
  echo "Launching 'gh auth login' - follow prompts (browser or token)"
  echo "If running over SSH without browser, choose: GitHub.com -> HTTPS -> Paste token"
  gh auth login || warn "gh auth login cancelled/failed - run 'gh auth login' manually later"
  gh auth status || true
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
install_selected_tools() {
  resolve_install_steps
  local i
  for i in "${!RESOLVED_STEPS[@]}"; do
    "${RESOLVED_STEPS[$i]}"
  done
  report_stepless_tools
}

main() {
  parse_args "$@"

  if [[ "$LIST_PROFILES" == true ]]; then
    list_profiles; exit 0
  fi
  if [[ "$LIST_TOOLS" == true ]]; then
    list_tools; exit 0
  fi

  require_root
  check_os
  info "Logging to $LOG_FILE"

  if [[ -n "$SEARCH_QUERY" ]]; then
    local found=""
    for k in "${!TOOL_DESC[@]}"; do
      if [[ "$k" == *"$SEARCH_QUERY"* ]] || [[ "${TOOL_DESC[$k],,}" == *"${SEARCH_QUERY,,}"* ]] || [[ "${TOOL_CATEGORY[$k],,}" == *"${SEARCH_QUERY,,}"* ]]; then
        found="$k"
        break
      fi
    done
    if [[ -z "$found" ]]; then
      error "No tool matching search: $SEARCH_QUERY"
      list_tools; exit 1
    fi
    SELECTED_TOOLS=("$found")
    info "Search '$SEARCH_QUERY' matched tool: $found"
    save_config
  elif [[ "$DO_REPLAY" == true ]]; then
    load_config
  elif [[ "$DO_ALL" == true ]]; then
    SELECTED_TOOLS=("${!TOOL_DESC[@]}")
    SELECTED_PROFILES=("all")
    save_config
  elif [[ "$DO_YES" == true ]]; then
    SELECTED_PROFILES=("default")
    resolve_tools_from_profiles
    save_config
  elif [[ ${#SELECTED_PROFILES[@]} -gt 0 ]]; then
    resolve_tools_from_profiles
    save_config
  else
    if [[ "$IS_TTY" != true ]]; then
      warn "No TTY detected and no flags - defaulting to Default Toolset (use --help for options)"
      SELECTED_PROFILES=("default")
      resolve_tools_from_profiles
      save_config
    else
      interactive_picker
    fi
  fi

  if [[ ${#SELECTED_TOOLS[@]} -eq 0 ]]; then
    warn "No tools selected - nothing to install"
    exit 0
  fi

  info "Toolset: ${SELECTED_TOOLS[*]}"
  if [[ "$DRY_RUN" == true ]]; then
    # One row per Install Step, not per Tool: the dry run reports the run that
    # would happen, and the run's unit is the Install Step (ADR-0004).
    resolve_install_steps
    local plural="install steps"
    if [[ ${#RESOLVED_STEPS[@]} -eq 1 ]]; then plural="install step"; fi
    info "[DRY RUN] Would install base deps and ${#SELECTED_TOOLS[@]} tools in ${#RESOLVED_STEPS[@]} $plural: ${SELECTED_TOOLS[*]}"
    print_install_steps "[DRY RUN] "
    report_stepless_tools "[DRY RUN] "
    info "[DRY RUN] Skipping all apt/npm/docker/brew installs, no config write, no bashrc mods"
  else
    install_base_deps
    install_selected_tools
  fi

  if [[ "$INCLUDE_TOOLCHAIN" == true ]]; then
    info "Toolchain PATH setup requested - ensured in ~/.bashrc by installers"
  fi

  step "Verification"
  echo "--- Versions ---"
  gh --version 2>&1 | head -n1 || true
  fastfetch --version 2>&1 | head -n1 || true
  opencode --version 2>&1 | head -n1 || true
  bash -c 'export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"; node -v; npm -v' 2>&1 | sed 's/^/  /' || true
  google-chrome-stable --version 2>&1 | sed 's/^/  /' || true
  # shellcheck disable=SC2211  # the versioned puppeteer path is the command
  ls "$HOME/.cache/puppeteer/chrome/linux-"*/chrome-linux64/chrome >/dev/null 2>&1 && "$HOME"/.cache/puppeteer/chrome/linux-*/chrome-linux64/chrome --version 2>&1 | sed 's/^/  /' || true
  docker --version 2>&1 | sed 's/^/  /' || true
  docker compose version 2>&1 | sed 's/^/  /' || true
  pip3 --version 2>&1 | sed 's/^/  /' || true
  eza --version 2>&1 | head -n1 | sed 's/^/  /' || true
  opencode mcp list 2>&1 | sed 's/^/  /' || true
  echo "  skills: $(ls -1 ~/.agents/skills 2>/dev/null | wc -l) in ~/.agents/skills"
  echo "  selected tools: ${SELECTED_TOOLS[*]}"
  echo ""
  fastfetch 2>&1 | tail -n 20 || true
  df -h 2>&1 | grep -E "Filesystem|/dev/sda1" | sed 's/^/  /' || true

  if [[ "$DRY_RUN" == true ]]; then
    info "[DRY RUN] Would run gh auth login (skipped)"
  elif [[ "$SKIP_AUTH" == true ]]; then
    info "Skipping gh auth (--no-auth)"
  else
    github_auth
  fi

  step "Done! Log saved to $LOG_FILE"
  info "Re-open shell or: source ~/.bashrc && export NVM_DIR=\"$HOME/.nvm\" && [ -s \"$NVM_DIR/nvm.sh\" ] && . \"$NVM_DIR/nvm.sh\""
  info "Replay last picks: sudo ./setup.sh --replay"
}

# fzf re-enters this script for tab/list/preview callbacks. These must run
# before parse_args (which would reject them) and before any install work.
case "${1:-}" in
  __tui_list)    tui_list; exit 0 ;;
  __tui_header)  tui_header; exit 0 ;;
  __tui_preview) shift; tui_preview "$@"; exit 0 ;;
  __tui_tab)     tui_tab_shift "${2:-next}"; exit 0 ;;
  __tui_click)   tui_tab_click; exit 0 ;;
  __tui_toggle)  shift; tui_toggle "$@"; exit 0 ;;
  # Not fzf callbacks: the two ends of the picker's run, seeding and ENTER.
  # They live under the same __tui_ prefix, and so skip the same log redirect,
  # because they are the only way bats can drive either - the picker itself
  # needs a tty (ADR-0008), and the state set is a file, which is more testable
  # than fzf's selection ever was (ADR-0010).
  __tui_seed)    tui_seed_defaults; exit 0 ;;
  __tui_resolve)
    tui_resolve_toolset
    printf 'profiles: %s\ntools: %s\n' "${SELECTED_PROFILES[*]:-}" "${SELECTED_TOOLS[*]:-}"
    exit 0 ;;
esac

main "$@" 
