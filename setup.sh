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
exec > >(tee -a "$LOG_FILE") 2>&1

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
  [c-build]="C/C++ build tools (gcc, make, cmake)"
)

declare -A PROFILE_TOOLS=(
  [default]="gh fastfetch opencode node puppeteer chrome docker pip eza exa-mcp pocock-skills"
  [go]="go golangci-lint air"
  [rust]="rust"
  [fe]="bun pnpm biome vite"
  [be]="postgres-client redis-tools"
  [python-ai]="uv jupyter ollama"
  [ai-agents]="uv jupyter ollama qdrant exa-mcp opencode claude-code"
  [full-stack-web]="bun pnpm biome vite postgres-client redis-tools docker chrome node c-build"
)

ORDERED_TOOLS=(gh fastfetch opencode node puppeteer chrome docker pip eza exa-mcp pocock-skills go golangci-lint air rust bun pnpm biome vite uv ollama qdrant postgres-client redis-tools jupyter claude-code c-build)

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

No args launches interactive TUI (gum/fzf required, auto-installs gum if missing).

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

resolve_tools_from_profiles() {
  local -A seen=()
  local out=()
  for prof in "${SELECTED_PROFILES[@]}"; do
    local tools_str="${PROFILE_TOOLS[$prof]:-}"
    if [[ -z "$tools_str" ]]; then
      warn "Unknown profile: $prof (skip)"
      continue
    fi
    for tt in $tools_str; do
      if [[ -z "${seen[$tt]:-}" ]]; then
        seen[$tt]=1
        out+=("$tt")
      fi
    done
  done
  SELECTED_TOOLS=("${out[@]}")
}

ensure_gum() {
  if command -v gum >/dev/null 2>&1 || command -v fzf >/dev/null 2>&1; then
    return 0
  fi
  step "Installing gum (required for TUI) - no gum/fzf found"
  local ver="0.14.5"
  local url="https://github.com/charmbracelet/gum/releases/download/v${ver}/gum_${ver}_Linux_x86_64.tar.gz"
  local tmpdir
  tmpdir=$(mktemp -d)
  if curl -fsSL "$url" -o "$tmpdir/gum.tar.gz" && tar -xzf "$tmpdir/gum.tar.gz" -C "$tmpdir" 2>/dev/null; then
    local bin
    bin=$(find "$tmpdir" -name gum -type f | head -n1)
    if [[ -n "$bin" ]]; then
      install -m 0755 "$bin" /usr/local/bin/gum 2>/dev/null || install -m 0755 "$bin" /tmp/gum
      if command -v gum >/dev/null 2>&1 || [[ -x /tmp/gum ]]; then
        [[ -x /tmp/gum ]] && export PATH="/tmp:$PATH"
        info "gum $ver installed"
        rm -rf "$tmpdir"
        return 0
      fi
    fi
  fi
  rm -rf "$tmpdir"
  error "gum/fzf required for interactive mode. Install one: 'apt install fzf' or 'go install github.com/charmbracelet/gum@latest'. Aborting TUI."
  return 1
}
dry_run_guard() {
  if [[ "$DRY_RUN" == true ]]; then
    info "[DRY RUN] Would $*"
    return 0
  fi
  return 1
}



interactive_picker() {
  ensure_gum || exit 1
  # Prefer gum filter for horizontal tabs + [x]/[] (search bar at top) - fzf fallback
  local has_gum=false
  command -v gum >/dev/null 2>&1 && has_gum=true

  step "Interactive setup"

  # Build combined list: just names, tabs show category (horizontal tabs)
  local combined=()
  for prof in "${!PROFILE_TOOLS[@]}"; do
    combined+=("$prof")
  done
  for k in "${!TOOL_DESC[@]}"; do
    combined+=("$k")
  done
  # Sort
  local sorted_combined
  sorted_combined=$(printf "%s\n" "${combined[@]}" | sort)

  local chosen_combined=""
  if [[ "$has_gum" == true ]]; then
    # Single-screen gum filter with search bar at top, horizontal tabs header, [x]/[] markers
    local fzf_tmp
    fzf_tmp=$(mktemp)
    printf "%s\n" "${sorted_combined}" | gum filter --no-limit --prompt="Search> " --header=" All  Recommended  Languages  Profiles " --placeholder="Type to filter (e.g. C)" --selected-prefix="[x] " --unselected-prefix="[ ] " --height=15 >"$fzf_tmp" 2>&3 || true
    chosen_combined=$(cat "$fzf_tmp" 2>/dev/null || true)
    rm -f "$fzf_tmp"
  else
    # Fallback fzf
    local fzf_tmp
    fzf_tmp=$(mktemp)
    printf "%s\n" "${sorted_combined}" | fzf --multi --exact --prompt="Search> " --header=" All  Recommended  Languages  Profiles  AI/ML  Infra/DevOps  |  x selected • Tab to select" --height=60% --border --ansi --marker="x " --pointer=" " --query="" >"$fzf_tmp" 2>/dev/tty || true
    chosen_combined=$(cat "$fzf_tmp" 2>/dev/null || true)
    rm -f "$fzf_tmp"
  fi

  # Parse chosen_combined into profiles and tools
  if [[ -z "$chosen_combined" ]]; then
    warn "No selection - falling back to default"
    SELECTED_PROFILES=("default")
    resolve_tools_from_profiles
  else
    SELECTED_PROFILES=()
    SELECTED_TOOLS=()
    while IFS= read -r line; do
      if [[ " ${!PROFILE_TOOLS[*]} " == *" $line "* ]]; then
        SELECTED_PROFILES+=("$line")
      else
        SELECTED_TOOLS+=("$line")
      fi
    done <<< "$chosen_combined"
    if [[ ${#SELECTED_TOOLS[@]} -eq 0 ]] && [[ ${#SELECTED_PROFILES[@]} -gt 0 ]]; then
      resolve_tools_from_profiles
      info "Profiles chosen: ${SELECTED_PROFILES[*]} -> Tools: ${SELECTED_TOOLS[*]}"
    elif [[ ${#SELECTED_TOOLS[@]} -gt 0 ]] && [[ ${#SELECTED_PROFILES[@]} -eq 0 ]]; then
      info "Tools chosen directly: ${SELECTED_TOOLS[*]}"
    else
      if [[ ${#SELECTED_TOOLS[@]} -gt 0 ]]; then
        info "Profiles: ${SELECTED_PROFILES[*]} + Tools fine-tuned: ${SELECTED_TOOLS[*]}"
      fi
    fi
    if [[ ${#SELECTED_TOOLS[@]} -eq 0 ]]; then
      warn "No tools selected - using Default Toolset"
      SELECTED_PROFILES=("default")
      resolve_tools_from_profiles
    fi
  fi

  if command -v gum >/dev/null 2>&1; then
    if gum confirm "Include toolchain PATH setup in ~/.bashrc?"; then
      INCLUDE_TOOLCHAIN=true
    else
      INCLUDE_TOOLCHAIN=false
    fi
  else
    read -rp "Include toolchain PATH setup in ~/.bashrc? [y/N] " ans
    [[ "$ans" == y* ]] && INCLUDE_TOOLCHAIN=true || INCLUDE_TOOLCHAIN=false
  fi

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
  for tool in "${ORDERED_TOOLS[@]}"; do
    if [[ ! " ${SELECTED_TOOLS[*]} " == *" $tool "* ]]; then
      continue
    fi
    case "$tool" in
      gh) install_gh ;;
      fastfetch) install_fastfetch ;;
      opencode) install_opencode ;;
      node) install_node_and_puppeteer ;;
      puppeteer) install_node_and_puppeteer ;;
      chrome) install_chrome_stable ;;
      docker) install_docker ;;
      pip) install_pip_eza ;;
      eza) install_pip_eza ;;
      exa-mcp) install_exa_mcp ;;
      pocock-skills) install_pocock_skills ;;
      go) install_go ;;
      golangci-lint) install_go ;;
      air) install_go ;;
      rust) install_rust ;;
      bun) install_bun ;;
      pnpm) install_pnpm ;;
      biome) install_biome ;;
      vite) install_vite ;;
      uv) install_uv ;;
      jupyter) install_jupyter ;;
      ollama) install_ollama ;;
      qdrant) install_qdrant ;;
      postgres-client) install_postgres_client ;;
      redis-tools) install_redis_tools ;;
      *) warn "No installer for tool: $tool" ;;
    esac
  done
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
    info "[DRY RUN] Would install base deps and ${#SELECTED_TOOLS[@]} tools: ${SELECTED_TOOLS[*]}"
    for tool in "${SELECTED_TOOLS[@]}"; do
      info "[DRY RUN] Would install: $tool (${TOOL_CATEGORY[$tool]:-unknown} - ${TOOL_DESC[$tool]:-})"
    done
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

main "$@" 
