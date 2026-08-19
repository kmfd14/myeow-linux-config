#!/usr/bin/env bash
# Install myeow Linux dotfiles on Fedora, Arch Linux, or NixOS.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES="$REPO_ROOT/dotfiles"
BACKUP_DIR="${BACKUP_DIR:-$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)}"
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
NERD_FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"

SKIP_PACKAGES=0
SKIP_FONTS=0
SKIP_GRUB=0
DRY_RUN=0
OS_FAMILY=""
OS_PRETTY=""
GRUB_THEME_NAME="catppuccin-mocha-grub-theme"
GRUB_THEME_DEST="/usr/share/grub/themes/${GRUB_THEME_NAME}"
GRUB_THEME_FILE="${GRUB_THEME_DEST}/theme.txt"

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_BLUE=$'\033[34m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'
else
  C_RESET= C_BOLD= C_DIM= C_BLUE= C_GREEN= C_YELLOW= C_RED=
fi

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

Symlinks Kitty, zsh, and Cursor configs from this repo, then installs the
packages, toolchains (bun, npm/npx, Rust, fastfetch), Oh My Zsh plugins, and
Catppuccin Mocha GRUB theme those configs expect.

Supported systems: Fedora, Arch Linux, NixOS.

Options:
  -h, --help          Show this help
  --skip-packages     Do not install system packages or toolchains
  --skip-fonts        Do not install JetBrainsMono Nerd Font
  --skip-grub         Do not install the GRUB theme
  --dry-run           Print actions without changing the system
EOF
}

log()  { printf '%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()   { printf '%s  ✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s  !%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
die()  { printf '%serror:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

run() {
  if (( DRY_RUN )); then
    printf '%s  $%s %s\n' "$C_DIM" "$C_RESET" "$*"
    return 0
  fi
  "$@"
}

already_linked() {
  local src="$1" dest="$2"
  [[ -L "$dest" ]] || return 1
  [[ "$(readlink -f "$dest")" == "$(readlink -f "$src")" ]]
}

backup_existing() {
  local path="$1"
  [[ -e "$path" || -L "$path" ]] || return 0

  local rel="${path#"$HOME"/}"
  local target="$BACKUP_DIR/$rel"

  log "Backing up $path"
  if (( DRY_RUN )); then
    printf '%s  $%s mkdir -p %q && mv %q %q\n' "$C_DIM" "$C_RESET" "$(dirname "$target")" "$path" "$target"
    return 0
  fi
  mkdir -p "$(dirname "$target")"
  mv "$path" "$target"
  ok "Saved to $target"
}

symlink() {
  local src="$1" dest="$2"
  [[ -e "$src" || -L "$src" ]] || die "Missing source: $src"

  if already_linked "$src" "$dest"; then
    ok "Already linked $dest"
    return 0
  fi

  backup_existing "$dest"
  log "Linking $dest"
  run mkdir -p "$(dirname "$dest")"
  run ln -sfn "$src" "$dest"
  ok "$dest → $src"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

sudo_if_needed() {
  if [[ "$(id -u)" -eq 0 ]]; then
    run "$@"
  elif need_cmd sudo; then
    run sudo "$@"
  else
    die "Need root (or sudo) to install packages: $*"
  fi
}

os_release_val() {
  local key="$1"
  [[ -r /etc/os-release ]] || return 0
  awk -F= -v k="$key" '
    $1 == k {
      val = $2
      gsub(/^"/, "", val)
      gsub(/"$/, "", val)
      print val
      exit
    }
  ' /etc/os-release
}

detect_os() {
  local id="" id_like="" pretty="Linux"

  if [[ -r /etc/os-release ]]; then
    id="$(os_release_val ID)"
    id_like="$(os_release_val ID_LIKE)"
    pretty="$(os_release_val PRETTY_NAME)"
    [[ -n "$pretty" ]] || pretty="$(os_release_val NAME)"
  fi

  id="${id,,}"
  id_like="${id_like,,}"
  OS_PRETTY="${pretty:-Linux}"

  if [[ -e /etc/NIXOS || "$id" == nixos ]]; then
    OS_FAMILY=nixos
  elif [[ "$id" == fedora || " $id_like " == *" fedora "* ]]; then
    OS_FAMILY=fedora
  elif [[ "$id" == arch || " $id_like " == *" arch "* ]]; then
    OS_FAMILY=arch
  else
    OS_FAMILY=unsupported
  fi
}

require_supported_os() {
  detect_os

  case "$OS_FAMILY" in
    fedora|arch|nixos) ;;
    *)
      die "Unsupported system: ${OS_PRETTY}. This installer supports Fedora, Arch Linux, and NixOS."
      ;;
  esac
}

install_packages() {
  (( SKIP_PACKAGES )) && { warn "Skipping system packages"; return 0; }

  case "$OS_FAMILY" in
    fedora) install_packages_fedora ;;
    arch)   install_packages_arch ;;
    nixos)  install_packages_nixos ;;
  esac
}

FEDORA_PACKAGES=(zsh git curl kitty rbenv unzip fontconfig gcc nodejs nodejs-npm grub2-tools)
ARCH_PACKAGES=(zsh git curl kitty rbenv unzip fontconfig gcc nodejs npm grub)
NIXOS_PACKAGES=(zsh git curl kitty unzip fontconfig gcc nodejs bun rustup fastfetch rbenv)

install_packages_fedora() {
  log "Installing Fedora packages: ${FEDORA_PACKAGES[*]}"
  sudo_if_needed dnf install -y "${FEDORA_PACKAGES[@]}"
  confirm_node_tools
}

install_packages_arch() {
  log "Installing Arch packages: ${ARCH_PACKAGES[*]}"
  sudo_if_needed pacman -Sy --needed --noconfirm "${ARCH_PACKAGES[@]}"
  confirm_node_tools
}

install_packages_nixos() {
  log "NixOS detected — skipping imperative package installs"
  warn "Add these to environment.systemPackages or home.packages, then rebuild:"
  printf '  %s\n' "${NIXOS_PACKAGES[*]}"
  printf '\n  users.users.%s.shell = pkgs.zsh;\n' "${USER:-youruser}"
  printf '  fonts.packages = [ pkgs.nerd-fonts.jetbrains-mono ];\n\n'
  ok "Dotfiles will still be linked into $HOME"
}

confirm_node_tools() {
  if need_cmd npm && need_cmd npx; then
    ok "npm and npx ready"
  elif (( DRY_RUN )); then
    ok "Would install Node.js (npm, npx) on $OS_FAMILY"
  else
    warn "nodejs/npm installed but npm or npx is not on PATH yet"
  fi
}

skip_impure_on_nixos() {
  local name="$1"
  if [[ "$OS_FAMILY" == nixos ]]; then
    warn "On NixOS, install $name from nixpkgs instead of the upstream installer"
    return 0
  fi
  return 1
}

cmd_exists() {
  need_cmd "$1" && return 0
  [[ -x "$2" ]]
}

install_bun() {
  (( SKIP_PACKAGES )) && { warn "Skipping bun"; return 0; }
  skip_impure_on_nixos bun && return 0

  local bun_bin="$HOME/.bun/bin/bun"
  if cmd_exists bun "$bun_bin"; then
    ok "bun already installed"
    return 0
  fi

  log "Installing bun"
  if (( DRY_RUN )); then
    ok "Would run: curl -fsSL https://bun.sh/install | bash -s -- --no-modify-path"
    return 0
  fi

  curl -fsSL https://bun.sh/install | bash -s -- --no-modify-path
  ok "bun installed to $HOME/.bun"
}

install_rust() {
  (( SKIP_PACKAGES )) && { warn "Skipping Rust"; return 0; }
  skip_impure_on_nixos rustup && return 0

  local cargo_bin="$HOME/.cargo/bin/cargo"
  if cmd_exists cargo "$cargo_bin" && cmd_exists rustc "$HOME/.cargo/bin/rustc"; then
    ok "Rust already installed"
    return 0
  fi

  log "Installing Rust (rustup)"
  if (( DRY_RUN )); then
    ok "Would run: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path"
    return 0
  fi

  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
  ok "Rust installed to $HOME/.cargo"
}

install_fastfetch() {
  (( SKIP_PACKAGES )) && { warn "Skipping fastfetch"; return 0; }
  skip_impure_on_nixos fastfetch && return 0

  if cmd_exists fastfetch "$HOME/.local/bin/fastfetch"; then
    ok "fastfetch already installed"
    return 0
  fi

  log "Installing fastfetch"
  if (( DRY_RUN )); then
    ok "Would install fastfetch via package manager, or GitHub if the package is missing"
    return 0
  fi

  if install_fastfetch_pkg; then
    ok "fastfetch installed"
    return 0
  fi

  warn "Package not available; installing fastfetch from GitHub"
  install_fastfetch_github
}

install_fastfetch_pkg() {
  case "$OS_FAMILY" in
    fedora) sudo_if_needed dnf install -y fastfetch || return 1 ;;
    arch)   sudo_if_needed pacman -Sy --needed --noconfirm fastfetch || return 1 ;;
    *) return 1 ;;
  esac
}

install_fastfetch_github() {
  local arch tarball url tmp binary dest="$HOME/.local/bin"

  case "$(uname -m)" in
    x86_64) arch=amd64 ;;
    aarch64|arm64) arch=aarch64 ;;
    *) die "No GitHub fastfetch build for $(uname -m)" ;;
  esac

  tarball="fastfetch-linux-${arch}.tar.gz"
  url="https://github.com/fastfetch-cli/fastfetch/releases/latest/download/${tarball}"
  tmp="$(mktemp -d)"

  curl -fsSL "$url" -o "$tmp/$tarball"
  tar -xzf "$tmp/$tarball" -C "$tmp"
  binary="$(find "$tmp" -type f -name fastfetch | head -n 1)"
  [[ -n "$binary" ]] || die "fastfetch binary missing from $tarball"

  mkdir -p "$dest"
  install -m 755 "$binary" "$dest/fastfetch"
  rm -rf "$tmp"
  ok "fastfetch installed to $dest/fastfetch"
}

font_installed() {
  need_cmd fc-list || return 1
  fc-list : family | grep -qi 'JetBrainsMono Nerd Font'
}

install_nerd_font() {
  (( SKIP_FONTS )) && { warn "Skipping Nerd Font"; return 0; }

  if font_installed; then
    ok "JetBrainsMono Nerd Font already installed"
    return 0
  fi

  local font_dir="$HOME/.local/share/fonts/JetBrainsMonoNerdFont"
  local tmp zip

  log "Installing JetBrainsMono Nerd Font"
  if (( DRY_RUN )); then
    ok "Would download $NERD_FONT_URL → $font_dir"
    return 0
  fi

  tmp="$(mktemp -d)"
  zip="$tmp/JetBrainsMono.zip"
  curl -fsSL "$NERD_FONT_URL" -o "$zip"
  mkdir -p "$font_dir"
  unzip -qo "$zip" -d "$font_dir"
  rm -rf "$tmp"
  fc-cache -f "$HOME/.local/share/fonts" >/dev/null
  ok "Installed JetBrainsMono Nerd Font"
}

install_oh_my_zsh() {
  if [[ -d "$HOME/.oh-my-zsh" ]]; then
    ok "Oh My Zsh already installed"
    return 0
  fi

  log "Installing Oh My Zsh"
  if (( DRY_RUN )); then
    ok "Would install Oh My Zsh into $HOME/.oh-my-zsh"
    return 0
  fi

  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
  ok "Oh My Zsh installed"
}

clone_plugin() {
  local name="$1" url="$2"
  local dest="$ZSH_CUSTOM/plugins/$name"

  if [[ -d "$dest/.git" ]]; then
    ok "Plugin $name already installed"
    return 0
  fi

  log "Installing plugin $name"
  run mkdir -p "$ZSH_CUSTOM/plugins"
  if [[ -e "$dest" || -L "$dest" ]]; then
    backup_existing "$dest"
  fi
  run git clone --depth 1 "$url" "$dest"
  ok "Installed $name"
}

install_omz_plugins() {
  clone_plugin zsh-autosuggestions https://github.com/zsh-users/zsh-autosuggestions.git
  clone_plugin zsh-syntax-highlighting https://github.com/zsh-users/zsh-syntax-highlighting.git
  clone_plugin zsh-completions https://github.com/zsh-users/zsh-completions.git
}

install_catppuccin_theme() {
  local src="$DOTFILES/oh-my-zsh/catppuccin-zsh"
  local dest="$ZSH_CUSTOM/themes"

  [[ -f "$src/catppuccin.zsh-theme" ]] || die "Catppuccin theme missing at $src"

  log "Installing Catppuccin zsh theme"
  run mkdir -p "$dest/catppuccin-flavors"
  symlink "$src/catppuccin.zsh-theme" "$dest/catppuccin.zsh-theme"

  local flavor
  for flavor in "$src"/catppuccin-flavors/*.zsh; do
    symlink "$flavor" "$dest/catppuccin-flavors/$(basename "$flavor")"
  done
}

install_kitty() {
  local src="$DOTFILES/kitty"
  [[ -d "$src" ]] || die "Kitty config missing at $src"

  log "Installing Kitty config"
  run mkdir -p "$HOME/.config/kitty"
  symlink "$src/kitty.conf" "$HOME/.config/kitty/kitty.conf"
  [[ -f "$src/current-theme.conf" ]] && symlink "$src/current-theme.conf" "$HOME/.config/kitty/current-theme.conf"
  symlink "$src/themes" "$HOME/.config/kitty/themes"
}

install_zshrc() {
  [[ -f "$DOTFILES/oh-my-zsh/.zshrc" ]] || die "zshrc missing"
  log "Installing .zshrc"
  symlink "$DOTFILES/oh-my-zsh/.zshrc" "$HOME/.zshrc"
}

install_cursor() {
  local skills="$DOTFILES/cursor/skills"
  local agent_skills="$DOTFILES/cursor/agents/skills"

  [[ -d "$skills" ]] || die "Cursor skills missing at $skills"
  [[ -d "$agent_skills" ]] || die "Cursor agent skills missing at $agent_skills"

  log "Installing Cursor skills"
  run mkdir -p "$HOME/.cursor/agents"
  symlink "$skills" "$HOME/.cursor/skills"
  symlink "$agent_skills" "$HOME/.cursor/agents/skills"
}

ensure_grub_key() {
  local key="$1" value="$2" file="/etc/default/grub"

  if (( DRY_RUN )); then
    ok "Would set $key=$value in $file"
    return 0
  fi

  if [[ ! -f "$file" ]]; then
    warn "$file missing; skip GRUB key $key"
    return 0
  fi

  if sudo_if_needed grep -q "^${key}=" "$file"; then
    sudo_if_needed sed -i "s|^${key}=.*|${key}=${value}|" "$file"
  else
    printf '%s=%s\n' "$key" "$value" | sudo_if_needed tee -a "$file" >/dev/null
  fi
}

install_grub() {
  (( SKIP_GRUB )) && { warn "Skipping GRUB theme"; return 0; }

  local src="$DOTFILES/grub/$GRUB_THEME_NAME"
  [[ -f "$src/theme.txt" ]] || die "GRUB theme missing at $src"

  if [[ "$OS_FAMILY" == nixos ]]; then
    log "NixOS detected — skipping imperative GRUB theme install"
    warn "Set boot.loader.grub.theme to $src, then rebuild"
    return 0
  fi

  log "Installing Catppuccin Mocha GRUB theme"
  if [[ -f /etc/default/grub ]] && (( ! DRY_RUN )); then
    mkdir -p "$BACKUP_DIR/etc"
    cp -a /etc/default/grub "$BACKUP_DIR/etc/grub" 2>/dev/null || \
      sudo_if_needed cp -a /etc/default/grub "$BACKUP_DIR/etc/grub"
  fi

  sudo_if_needed mkdir -p "$GRUB_THEME_DEST"
  sudo_if_needed cp -a "$src/." "$GRUB_THEME_DEST/"

  ensure_grub_key GRUB_THEME "\"$GRUB_THEME_FILE\""
  ensure_grub_key GRUB_GFXMODE "1920x1200,1920x1080,auto"

  case "$OS_FAMILY" in
    fedora)
      if need_cmd grub2-mkconfig; then
        sudo_if_needed grub2-mkconfig -o /boot/grub2/grub.cfg
      else
        warn "grub2-mkconfig not found; theme copied, regenerate GRUB yourself"
      fi
      ;;
    arch)
      if need_cmd grub-mkconfig; then
        sudo_if_needed grub-mkconfig -o /boot/grub/grub.cfg
      else
        warn "grub-mkconfig not found; theme copied, regenerate GRUB yourself"
      fi
      ;;
  esac

  ok "GRUB theme $GRUB_THEME_NAME"
}

ensure_zsh_shell() {
  if [[ "$OS_FAMILY" == nixos ]]; then
    warn "On NixOS, set users.users.${USER:-youruser}.shell = pkgs.zsh; instead of chsh"
    return 0
  fi

  local zsh_path
  zsh_path="$(command -v zsh || true)"
  [[ -n "$zsh_path" ]] || { warn "zsh not on PATH; skip default-shell change"; return 0; }

  if [[ "${SHELL:-}" == "$zsh_path" ]]; then
    ok "Default shell is already zsh"
    return 0
  fi

  if ! grep -qx "$zsh_path" /etc/shells 2>/dev/null; then
    warn "$zsh_path is not listed in /etc/shells; skip chsh"
    return 0
  fi

  log "Setting default shell to $zsh_path"
  if (( DRY_RUN )); then
    ok "Would run chsh -s $zsh_path"
    return 0
  fi
  chsh -s "$zsh_path" || warn "chsh failed; set your login shell to zsh manually"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --skip-packages) SKIP_PACKAGES=1 ;;
      --skip-fonts) SKIP_FONTS=1 ;;
      --skip-grub) SKIP_GRUB=1 ;;
      --dry-run) DRY_RUN=1 ;;
      *) die "Unknown option: $1" ;;
    esac
    shift
  done
}

main() {
  parse_args "$@"

  [[ -d "$DOTFILES" ]] || die "Expected $DOTFILES — run this from the myeow-linux-config repo"
  require_supported_os

  printf '\n%smyeow linux config%s\n' "$C_BOLD" "$C_RESET"
  printf '  repo:    %s\n' "$REPO_ROOT"
  printf '  home:    %s\n' "$HOME"
  printf '  os:      %s (%s)\n' "$OS_PRETTY" "$OS_FAMILY"
  (( DRY_RUN )) && printf '  mode:    dry-run\n'
  printf '\n'

  log "Using $OS_FAMILY install flow"
  install_packages
  if [[ "$OS_FAMILY" != nixos ]]; then
    install_bun
    install_rust
    install_fastfetch
  fi
  install_nerd_font
  install_oh_my_zsh
  install_omz_plugins
  install_catppuccin_theme
  install_zshrc
  install_kitty
  install_cursor
  install_grub
  ensure_zsh_shell

  printf '\n%sDone.%s Open a new terminal (or run: exec zsh).\n' "$C_GREEN" "$C_RESET"
  if [[ -d "$BACKUP_DIR" ]]; then
    printf 'Backups: %s\n' "$BACKUP_DIR"
  fi
}

main "$@"
