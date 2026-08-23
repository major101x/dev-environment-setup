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
exec > >(tee -a "$LOG_FILE") 2>&1

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
step()  { echo -e "\n${GREEN}==>${NC} $*"; }

require_root() {
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
  for skill in $(ls ~/.agents/skills 2>/dev/null); do
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
main() {
  require_root
  check_os
  info "Logging to $LOG_FILE"
  install_base_deps
  install_gh
  install_fastfetch
  install_opencode
  install_node_and_puppeteer
  install_chrome_stable
  install_docker
  install_pip_eza
  install_exa_mcp
  install_pocock_skills

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
  echo ""
  fastfetch 2>&1 | tail -n 20 || true
  df -h 2>&1 | grep -E "Filesystem|/dev/sda1" | sed 's/^/  /' || true

  # interactive auth last
  github_auth

  step "Done! Log saved to $LOG_FILE"
  info "Re-open shell or: source ~/.bashrc && export NVM_DIR=\"\$HOME/.nvm\" && [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\""
}

main "$@"
