#!/usr/bin/env bash
# install.sh — install occ-fetch-secret + occ-store-secret on macOS or Linux.
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/OITApps/occ-secrets-cli/v1.0.0/install.sh | bash
#
# Or, if you've already cloned the repo:
#   bash install.sh

set -euo pipefail

REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/OITApps/occ-secrets-cli/v1.0.0}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
PYTHON_MIN_MAJOR=3
PYTHON_MIN_MINOR=8

# Refuse user-overridden INSTALL_DIR with shell metachars or whitespace — those bytes
# would be appended verbatim into ~/.bashrc / ~/.zshrc by ensure_path.
if [[ ! "$INSTALL_DIR" =~ ^/[A-Za-z0-9._/-]+$ ]]; then
  printf "fail: INSTALL_DIR must be an absolute path of [A-Za-z0-9._/-] only, got: %q\n" "$INSTALL_DIR" >&2
  exit 1
fi

# refuse_non_regular: write target must be absent or a plain file — never a symlink/socket/etc.
# Skip for shell rc files (~/.bashrc, ~/.zshrc) which are legitimately symlinked into dotfiles.
refuse_non_regular() {
  local path="$1"
  if [[ -e "$path" && ! -f "$path" ]] || [[ -L "$path" ]]; then
    printf "fail: refusing to overwrite non-regular file (symlink/special) at %s\n" "$path" >&2
    exit 1
  fi
}

color() { printf "\033[%sm%s\033[0m\n" "$1" "$2"; }
info()  { color "1;34" "info: $*" >&2; }
ok()    { color "1;32" "ok:   $*" >&2; }
warn()  { color "1;33" "warn: $*" >&2; }
fail()  { color "1;31" "fail: $*" >&2; exit 1; }

prompt_yn() {
  # $1 = question, returns 0 for yes, 1 for no. Default = no.
  local reply=""
  printf "%s [y/N]: " "$1" >&2
  read -r reply < /dev/tty || reply=""
  [[ "${reply,,}" == "y" || "${reply,,}" == "yes" ]]
}

ensure_brew_on_mac() {
  if command -v brew >/dev/null 2>&1; then
    return 0
  fi
  warn "Homebrew not found. Install? (recommended for prereqs)"
  if prompt_yn "Run the Homebrew install script?"; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [[ -x /opt/homebrew/bin/brew ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
      eval "$(/usr/local/bin/brew shellenv)"
    fi
  else
    fail "Homebrew required for automatic prereq install on macOS. Aborting."
  fi
}

install_python_mac() {
  ensure_brew_on_mac
  brew install python@3.12
}

install_python_linux() {
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update && sudo apt-get install -y python3 python3-pip
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y python3 python3-pip
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -Sy --noconfirm python python-pip
  else
    fail "no supported package manager found (apt-get/dnf/pacman). Install python3.${PYTHON_MIN_MINOR}+ manually."
  fi
}

install_az_mac() {
  ensure_brew_on_mac
  brew update && brew install azure-cli
}

install_az_linux() {
  if command -v apt-get >/dev/null 2>&1; then
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
  elif command -v dnf >/dev/null 2>&1; then
    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
    sudo dnf install -y https://packages.microsoft.com/config/rhel/9/packages-microsoft-prod.rpm 2>/dev/null || true
    sudo dnf install -y azure-cli
  elif command -v zypper >/dev/null 2>&1; then
    sudo zypper install -y --from https://packages.microsoft.com/yumrepos/azure-cli azure-cli
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -Sy --noconfirm azure-cli
  else
    fail "no supported package manager found. See https://learn.microsoft.com/cli/azure/install-azure-cli-linux"
  fi
}

check_python() {
  if ! command -v python3 >/dev/null 2>&1; then
    warn "python3 not found."
    if prompt_yn "Install Python 3?"; then
      case "$(uname -s)" in
        Darwin) install_python_mac ;;
        Linux)  install_python_linux ;;
        *)      fail "unsupported OS for auto-install: $(uname -s)" ;;
      esac
    else
      fail "python3 required."
    fi
  fi
  local v
  v=$(python3 -c 'import sys; print(f"{sys.version_info[0]}.{sys.version_info[1]}")')
  ok "python3 found: $v"
  local major minor
  major=$(echo "$v" | cut -d. -f1)
  minor=$(echo "$v" | cut -d. -f2)
  if (( major < PYTHON_MIN_MAJOR )) || (( major == PYTHON_MIN_MAJOR && minor < PYTHON_MIN_MINOR )); then
    fail "python3 too old. Need >= ${PYTHON_MIN_MAJOR}.${PYTHON_MIN_MINOR}; have $v."
  fi
}

check_az() {
  if ! command -v az >/dev/null 2>&1; then
    warn "az CLI not found."
    if prompt_yn "Install Azure CLI?"; then
      case "$(uname -s)" in
        Darwin) install_az_mac ;;
        Linux)  install_az_linux ;;
        *)      fail "unsupported OS for auto-install: $(uname -s)" ;;
      esac
    else
      fail "az CLI required."
    fi
  fi
  ok "az CLI found: $(az --version 2>/dev/null | head -1)"
}

install_scripts() {
  mkdir -p "$INSTALL_DIR"
  for name in occ-fetch-secret occ-store-secret; do
    local target="$INSTALL_DIR/$name"
    info "downloading $name → $target"
    refuse_non_regular "$target"
    local tmp
    tmp=$(mktemp "${target}.XXXXXX")
    if [[ -f "$(dirname "${BASH_SOURCE[0]:-$0}")/$name" ]]; then
      # local mode (repo cloned)
      cp "$(dirname "${BASH_SOURCE[0]:-$0}")/$name" "$tmp"
    else
      # remote mode (curl|bash one-liner)
      curl -fsSL "$REPO_BASE/$name" -o "$tmp"
    fi
    chmod +x "$tmp"
    mv -f "$tmp" "$target"
  done
}

ensure_path() {
  case ":$PATH:" in
    *":$INSTALL_DIR:"*) ok "$INSTALL_DIR already on PATH" ;;
    *)
      warn "$INSTALL_DIR is NOT on PATH."
      local rc
      if [[ -n "${ZSH_VERSION:-}" ]] || [[ "$SHELL" == */zsh ]]; then
        rc="$HOME/.zshrc"
      else
        rc="$HOME/.bashrc"
      fi
      if prompt_yn "Append 'export PATH=\"$INSTALL_DIR:\$PATH\"' to $rc?"; then
        echo "" >> "$rc"
        echo "# Added by occ-secrets-cli installer" >> "$rc"
        echo "export PATH=\"$INSTALL_DIR:\$PATH\"" >> "$rc"
        ok "updated $rc — restart your shell or run: source $rc"
      else
        warn "Skipped. You'll need to invoke the scripts by full path or add $INSTALL_DIR to PATH manually."
      fi
      ;;
  esac
}

seed_config() {
  local cfg="$HOME/.claude/.occ-vault.json"
  if [[ -f "$cfg" ]]; then
    ok "vault config already exists at $cfg"
    return
  fi
  refuse_non_regular "$cfg"
  mkdir -p "$HOME/.claude"
  local upn user_vault
  upn=$(az account show --query user.name -o tsv 2>/dev/null || true)
  if [[ -n "$upn" && "$upn" == *"@"* ]]; then
    user_vault="occ-secrets-${upn%%@*}"
    local tmp
    tmp=$(mktemp "${cfg}.XXXXXX")
    printf '{"userVault": "%s"}\n' "$user_vault" > "$tmp"
    mv -f "$tmp" "$cfg"
    ok "wrote $cfg with userVault: $user_vault"
  else
    warn "az not logged in — vault config not seeded. Run 'az login' then re-run, or set OCC_USER_VAULT env var."
  fi
}

main() {
  info "occ-secrets-cli installer (macOS/Linux)"
  check_python
  check_az
  install_scripts
  ensure_path
  seed_config
  echo
  ok "Done. Try:  occ-fetch-secret --help"
  ok "Then:      occ-fetch-secret --vault company --list"
}

main "$@"
