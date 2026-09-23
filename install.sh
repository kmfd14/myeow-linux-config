#!/usr/bin/env bash
# Install myeow Linux dotfiles on Fedora or Arch Linux.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES="$REPO_ROOT/dotfiles"
BACKUP_DIR="${BACKUP_DIR:-$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)}"
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
NERD_FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"
LOCAL_SHARE="${XDG_DATA_HOME:-$HOME/.local/share}"

SKIP_PACKAGES=0
SKIP_FONTS=0
SKIP_GRUB=0
SKIP_DESKTOP=0
DRY_RUN=0
OS_FAMILY=""
OS_PRETTY=""
GRUB_THEME_NAME="catppuccin-mocha-grub-theme"
GRUB_THEME_DEST="/usr/share/grub/themes/${GRUB_THEME_NAME}"
GRUB_THEME_FILE="${GRUB_THEME_DEST}/theme.txt"

# Desktop choices (empty until menus / flags resolve)
COMPOSITOR=""
DESKTOP_SHELL=""
ENABLE_SDDM=1

STEP_CURRENT=0
STEP_TOTAL=0
SPINNER_PID=""

# Catppuccin Frappé (truecolor when the terminal supports it)
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_MAUVE=$'\033[38;2;202;158;230m'
  C_PINK=$'\033[38;2;244;184;228m'
  C_BLUE=$'\033[38;2;140;170;238m'
  C_TEAL=$'\033[38;2;129;200;190m'
  C_GREEN=$'\033[38;2;166;209;137m'
  C_YELLOW=$'\033[38;2;229;200;144m'
  C_PEACH=$'\033[38;2;239;159;118m'
  C_RED=$'\033[38;2;231;130;132m'
  C_LAVENDER=$'\033[38;2;186;187;241m'
  C_TEXT=$'\033[38;2;198;208;245m'
  C_SUB=$'\033[38;2;165;173;206m'
else
  C_RESET= C_BOLD= C_DIM= C_MAUVE= C_PINK= C_BLUE= C_TEAL=
  C_GREEN= C_YELLOW= C_PEACH= C_RED= C_LAVENDER= C_TEXT= C_SUB=
fi

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

Symlinks Kitty, zsh, and Cursor configs from this repo, then installs the
packages, toolchains (bun, npm/npx, Rust, fastfetch, oh-my-posh), Oh My Zsh
plugins, and Catppuccin Mocha GRUB theme those configs expect.

Optionally installs a Wayland compositor (Sway, Niri, Hyprland), an optional
desktop shell (Noctalia, DankMaterial, Caelestia), New Wave Rofi, and
Catppuccin Mocha SDDM.

Supported systems: Fedora, Arch Linux.

Options:
  -h, --help                 Show this help
  --skip-packages            Do not install system packages or toolchains
  --skip-fonts               Do not install JetBrainsMono Nerd Font
  --skip-grub                Do not install the GRUB theme
  --skip-desktop             Terminal-only install (no compositor/shell/SDDM)
  --compositor sway|niri|hyprland
                             Skip compositor menu
  --shell noctalia|material|celestial|none
                             Skip shell menu
  --no-sddm                  Install desktop pieces but do not enable SDDM
  --dry-run                  Print actions without changing the system
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

  if [[ "$id" == fedora || " $id_like " == *" fedora "* ]]; then
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
    fedora|arch) ;;
    *)
      die "Unsupported system: ${OS_PRETTY}. This installer supports Fedora and Arch Linux."
      ;;
  esac
}

# --- Spinner / progress -------------------------------------------------------

stop_spinner() {
  if [[ -n "${SPINNER_PID:-}" ]] && kill -0 "$SPINNER_PID" 2>/dev/null; then
    kill "$SPINNER_PID" 2>/dev/null || true
    wait "$SPINNER_PID" 2>/dev/null || true
  fi
  SPINNER_PID=""
  if [[ -t 1 ]]; then
    printf '\r\033[K'
  fi
}

trap 'stop_spinner' EXIT

spinner_loop() {
  local label="$1" counter="$2"
  local frames=('[=     ]' '[==    ]' '[===   ]' '[====  ]' '[=====>]' '[ =====]' '[  ====]' '[   ===]' '[    ==]' '[     =]')
  local i=0
  while true; do
    printf '\r%s%s%s %s%s%s %s' \
      "$C_MAUVE" "${frames[i]}" "$C_RESET" \
      "$C_SUB" "$counter" "$C_RESET" \
      "$label"
    i=$(( (i + 1) % ${#frames[@]} ))
    sleep 0.12
  done
}

with_spinner() {
  local label="$1"
  shift
  STEP_CURRENT=$((STEP_CURRENT + 1))
  local counter="${STEP_CURRENT}/${STEP_TOTAL}"

  if (( DRY_RUN )) || [[ ! -t 1 ]]; then
    log "[${counter}] $label"
    "$@"
    return $?
  fi

  spinner_loop "$label" "$counter" &
  SPINNER_PID=$!
  local rc=0
  "$@" || rc=$?
  stop_spinner
  if (( rc == 0 )); then
    ok "[${counter}] $label"
  else
    warn "[${counter}] $label failed (exit $rc)"
  fi
  return "$rc"
}

# --- Desktop menus ------------------------------------------------------------

print_desktop_banner() {
  printf '\n'
  printf '%s╭──────────────────────────────────────────────╮%s\n' "$C_MAUVE" "$C_RESET"
  printf '%s│%s  %smyeow%s · %swayland rice%s                      %s│%s\n' \
    "$C_MAUVE" "$C_RESET" "$C_PINK" "$C_RESET" "$C_LAVENDER" "$C_RESET" "$C_MAUVE" "$C_RESET"
  printf '%s│%s  %spick a compositor, then a desktop shell%s   %s│%s\n' \
    "$C_MAUVE" "$C_RESET" "$C_SUB" "$C_RESET" "$C_MAUVE" "$C_RESET"
  printf '%s╰──────────────────────────────────────────────╯%s\n\n' "$C_MAUVE" "$C_RESET"
}

prompt_choice() {
  # prompt_choice VAR prompt default_num "label1" "label2" ...
  local __var="$1" __prompt="$2" __default="$3"
  shift 3
  local -a __opts=("$@")
  local i choice

  printf '%s%s%s\n' "$C_TEAL" "$__prompt" "$C_RESET"
  for i in "${!__opts[@]}"; do
    local n=$((i + 1))
    if (( n == __default )); then
      printf '  %s%s)%s %s %s(default)%s\n' "$C_MAUVE" "$n" "$C_RESET" "${__opts[i]}" "$C_DIM" "$C_RESET"
    else
      printf '  %s%s)%s %s\n' "$C_BLUE" "$n" "$C_RESET" "${__opts[i]}"
    fi
  done
  printf '%sChoice [%s]: %s' "$C_TEXT" "$__default" "$C_RESET"
  if (( DRY_RUN )) || [[ ! -t 0 ]]; then
    choice="$__default"
    printf '%s\n' "$choice"
  else
    read -r choice || choice="$__default"
    [[ -z "$choice" ]] && choice="$__default"
  fi
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#__opts[@]} )); then
    warn "Invalid choice; using default (${__default})"
    choice="$__default"
  fi
  printf -v "$__var" '%s' "$choice"
}

resolve_desktop_choices() {
  if (( SKIP_DESKTOP )); then
    COMPOSITOR=""
    DESKTOP_SHELL=""
    ENABLE_SDDM=0
    return 0
  fi

  local need_menu=0
  [[ -z "$COMPOSITOR" || -z "$DESKTOP_SHELL" ]] && need_menu=1

  if (( need_menu )); then
    print_desktop_banner

    if [[ -z "$COMPOSITOR" ]]; then
      local c_num
      prompt_choice c_num "Compositor" 1 "Sway" "Niri" "Hyprland"
      case "$c_num" in
        1) COMPOSITOR=sway ;;
        2) COMPOSITOR=niri ;;
        3) COMPOSITOR=hyprland ;;
      esac
    fi

    if [[ -z "$DESKTOP_SHELL" ]]; then
      local s_num
      prompt_choice s_num "Desktop shell" 4 "Noctalia" "Material (DankMaterialShell)" "Celestial (Caelestia)" "None"
      case "$s_num" in
        1) DESKTOP_SHELL=noctalia ;;
        2) DESKTOP_SHELL=material ;;
        3) DESKTOP_SHELL=celestial ;;
        4) DESKTOP_SHELL=none ;;
      esac
    fi

    if [[ -t 0 ]] && (( ! DRY_RUN )); then
      local sddm_ans=y
      printf '%sEnable SDDM login manager? [Y/n]: %s' "$C_TEXT" "$C_RESET"
      read -r sddm_ans || sddm_ans=y
      case "${sddm_ans:-y}" in
        [nN]|[nN][oO]) ENABLE_SDDM=0 ;;
        *) ENABLE_SDDM=1 ;;
      esac
    fi
  fi

  case "$COMPOSITOR" in
    sway|niri|hyprland) ;;
    *) die "Invalid --compositor: ${COMPOSITOR:-empty} (use sway|niri|hyprland)" ;;
  esac
  case "$DESKTOP_SHELL" in
    noctalia|material|celestial|none) ;;
    *) die "Invalid --shell: ${DESKTOP_SHELL:-empty} (use noctalia|material|celestial|none)" ;;
  esac

  printf '\n%sConfirm%s  compositor=%s%s%s  shell=%s%s%s  sddm=%s%s%s\n\n' \
    "$C_BOLD" "$C_RESET" \
    "$C_MAUVE" "$COMPOSITOR" "$C_RESET" \
    "$C_PINK" "$DESKTOP_SHELL" "$C_RESET" \
    "$C_TEAL" "$( (( ENABLE_SDDM )) && echo yes || echo no )" "$C_RESET"
}

shell_exec_cmd() {
  case "$DESKTOP_SHELL" in
    noctalia)  printf '%s' "noctalia" ;;
    material)  printf '%s' "dms run" ;;
    celestial) printf '%s' "caelestia shell -d" ;;
    none|"")   printf '%s' "" ;;
  esac
}

write_shell_autostart() {
  local cmd
  cmd="$(shell_exec_cmd)"

  case "$COMPOSITOR" in
    sway)
      local dest="$HOME/.config/sway/shell.conf"
      run mkdir -p "$(dirname "$dest")"
      if (( DRY_RUN )); then
        ok "Would write $dest (shell=$DESKTOP_SHELL)"
        return 0
      fi
      if [[ -n "$cmd" ]]; then
        printf '# Generated by myeow install.sh\nexec %s\n' "$cmd" >"$dest"
      else
        printf '# Generated by myeow install.sh — no desktop shell\n' >"$dest"
      fi
      ok "Wrote $dest"
      ;;
    niri)
      local dest="$HOME/.config/niri/shell.kdl"
      run mkdir -p "$(dirname "$dest")"
      if (( DRY_RUN )); then
        ok "Would write $dest (shell=$DESKTOP_SHELL)"
        return 0
      fi
      if [[ -n "$cmd" ]]; then
        printf '// Generated by myeow install.sh\nspawn-at-startup "sh" "-c" "%s"\n' "$cmd" >"$dest"
      else
        printf '// Generated by myeow install.sh — no desktop shell\n' >"$dest"
      fi
      ok "Wrote $dest"
      ;;
    hyprland)
      local dest="$HOME/.config/hypr/shell.conf"
      run mkdir -p "$(dirname "$dest")"
      if (( DRY_RUN )); then
        ok "Would write $dest (shell=$DESKTOP_SHELL)"
        return 0
      fi
      if [[ -n "$cmd" ]]; then
        printf '# Generated by myeow install.sh\nexec-once = %s\n' "$cmd" >"$dest"
      else
        printf '# Generated by myeow install.sh — no desktop shell\n' >"$dest"
      fi
      ok "Wrote $dest"
      ;;
  esac
}

# --- Packages -----------------------------------------------------------------

try_pkg_install() {
  # try_pkg_install pkg1 pkg2 ... — returns 0 if all installed, non-zero if any missing
  local pkgs=("$@")
  (( ${#pkgs[@]} )) || return 0

  case "$OS_FAMILY" in
    fedora)
      if ! sudo_if_needed dnf install -y "${pkgs[@]}"; then
        warn "dnf could not install: ${pkgs[*]} — continuing"
        return 1
      fi
      ;;
    arch)
      if ! sudo_if_needed pacman -Sy --needed --noconfirm "${pkgs[@]}"; then
        warn "pacman could not install: ${pkgs[*]} — continuing"
        return 1
      fi
      ;;
  esac
  return 0
}

install_packages() {
  (( SKIP_PACKAGES )) && { warn "Skipping system packages"; return 0; }

  case "$OS_FAMILY" in
    fedora) install_packages_fedora ;;
    arch)   install_packages_arch ;;
  esac
}

FEDORA_PACKAGES=(zsh git curl kitty rbenv unzip fontconfig gcc nodejs nodejs-npm grub2-tools)
ARCH_PACKAGES=(zsh git curl kitty rbenv unzip fontconfig gcc nodejs npm grub)

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

confirm_node_tools() {
  if need_cmd npm && need_cmd npx; then
    ok "npm and npx ready"
  elif (( DRY_RUN )); then
    ok "Would install Node.js (npm, npx) on $OS_FAMILY"
  else
    warn "nodejs/npm installed but npm or npx is not on PATH yet"
  fi
}

install_desktop_packages() {
  (( SKIP_DESKTOP )) && return 0
  (( SKIP_PACKAGES )) && { warn "Skipping desktop packages"; return 0; }

  local common=(sddm grim slurp wl-clipboard)
  local portal=()
  local comp_pkgs=()
  local shell_pkgs=()
  local rofi_pkg=""

  case "$OS_FAMILY" in
    fedora)
      portal=(xdg-desktop-portal-wlr)
      rofi_pkg=rofi-wayland
      case "$COMPOSITOR" in
        sway)     comp_pkgs=(sway swaybg swayidle swaylock) ;;
        niri)     comp_pkgs=(niri) ;;
        hyprland) comp_pkgs=(hyprland) ;;
      esac
      case "$DESKTOP_SHELL" in
        noctalia)  shell_pkgs=(noctalia) ;;
        material)  shell_pkgs=(quickshell qt6-qtbase qt6-qtdeclarative qt6-qtwayland) ;;
        celestial) shell_pkgs=(quickshell qt6-qtbase qt6-qtdeclarative qt6-qtwayland qt6-qtmultimedia cmake ninja) ;;
        none)      ;;
      esac
      ;;
    arch)
      portal=(xdg-desktop-portal-wlr)
      rofi_pkg=rofi
      case "$COMPOSITOR" in
        sway)     comp_pkgs=(sway swaybg swayidle swaylock) ;;
        niri)     comp_pkgs=(niri) ;;
        hyprland) comp_pkgs=(hyprland) ;;
      esac
      case "$DESKTOP_SHELL" in
        noctalia)  shell_pkgs=(noctalia) ;;
        material)  shell_pkgs=(quickshell qt6-base qt6-declarative qt6-wayland) ;;
        celestial) shell_pkgs=(quickshell qt6-base qt6-declarative qt6-wayland qt6-multimedia cmake ninja) ;;
        none)      ;;
      esac
      ;;
  esac

  log "Installing desktop packages"
  try_pkg_install "${common[@]}" "$rofi_pkg" "${portal[@]}" || true
  try_pkg_install "${comp_pkgs[@]}" || true
  if (( ${#shell_pkgs[@]} )); then
    try_pkg_install "${shell_pkgs[@]}" || true
  fi
}

cmd_exists() {
  need_cmd "$1" && return 0
  [[ -x "$2" ]]
}

install_bun() {
  (( SKIP_PACKAGES )) && { warn "Skipping bun"; return 0; }

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

install_oh_my_posh() {
  local omp_bin="$HOME/.local/bin/oh-my-posh"
  local theme_src="$DOTFILES/oh-my-posh/themes/catppuccin.omp.json"
  local theme_dest="$HOME/.oh-my-posh/themes/catppuccin.omp.json"

  [[ -f "$theme_src" ]] || die "Oh My Posh theme missing at $theme_src"

  if (( SKIP_PACKAGES )); then
    warn "Skipping oh-my-posh binary install"
  elif cmd_exists oh-my-posh "$omp_bin"; then
    ok "oh-my-posh already installed"
  else
    log "Installing oh-my-posh"
    if (( DRY_RUN )); then
      ok "Would run: curl -s https://ohmyposh.dev/install.sh | bash -s -- -d $HOME/.local/bin"
    else
      mkdir -p "$HOME/.local/bin"
      curl -s https://ohmyposh.dev/install.sh | bash -s -- -d "$HOME/.local/bin"
      ok "oh-my-posh installed to $HOME/.local/bin"
    fi
  fi

  log "Linking Oh My Posh theme"
  run mkdir -p "$HOME/.oh-my-posh/themes"
  symlink "$theme_src" "$theme_dest"
}

install_rust() {
  (( SKIP_PACKAGES )) && { warn "Skipping Rust"; return 0; }

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

  log "Installing Cursor skills"
  run mkdir -p "$HOME/.cursor/agents"
  symlink "$skills" "$HOME/.cursor/skills"
  if [[ -d "$agent_skills" ]]; then
    symlink "$agent_skills" "$HOME/.cursor/agents/skills"
  else
    warn "Cursor agent skills missing at $agent_skills — skipped"
  fi
}

install_dotfile_links() {
  install_catppuccin_theme
  install_zshrc
  install_kitty
  install_cursor
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

# --- Desktop configs & shells -------------------------------------------------

install_desktop_configs() {
  (( SKIP_DESKTOP )) && return 0

  log "Linking Wayland desktop configs"

  case "$COMPOSITOR" in
    sway)
      [[ -f "$DOTFILES/sway/config" ]] || die "Missing $DOTFILES/sway/config"
      run mkdir -p "$HOME/.config/sway"
      symlink "$DOTFILES/sway/config" "$HOME/.config/sway/config"
      ;;
    niri)
      [[ -f "$DOTFILES/niri/config.kdl" ]] || die "Missing $DOTFILES/niri/config.kdl"
      run mkdir -p "$HOME/.config/niri"
      symlink "$DOTFILES/niri/config.kdl" "$HOME/.config/niri/config.kdl"
      ;;
    hyprland)
      [[ -f "$DOTFILES/hypr/hyprland.conf" ]] || die "Missing $DOTFILES/hypr/hyprland.conf"
      run mkdir -p "$HOME/.config/hypr"
      symlink "$DOTFILES/hypr/hyprland.conf" "$HOME/.config/hypr/hyprland.conf"
      ;;
  esac

  if [[ -d "$DOTFILES/rofi" ]]; then
    symlink "$DOTFILES/rofi" "$HOME/.config/rofi"
  else
    warn "Rofi config missing at $DOTFILES/rofi"
  fi

  write_shell_autostart
}

install_sddm_theme() {
  (( SKIP_DESKTOP )) && return 0
  (( ! ENABLE_SDDM )) && { warn "Skipping SDDM theme / enable"; return 0; }

  local src="$DOTFILES/sddm/catppuccin-mocha"
  local conf_src="$DOTFILES/sddm/sddm.conf.d/10-catppuccin.conf"
  local dest="/usr/share/sddm/themes/catppuccin-mocha"
  local conf_dest="/etc/sddm.conf.d/10-catppuccin.conf"

  [[ -d "$src" ]] || die "SDDM theme missing at $src"
  [[ -f "$conf_src" ]] || die "SDDM conf missing at $conf_src"

  log "Installing Catppuccin Mocha SDDM theme"
  sudo_if_needed mkdir -p /usr/share/sddm/themes /etc/sddm.conf.d
  sudo_if_needed cp -a "$src" "$dest"
  sudo_if_needed cp -a "$conf_src" "$conf_dest"

  if (( DRY_RUN )); then
    ok "Would enable sddm.service"
  else
    sudo_if_needed systemctl enable sddm.service || warn "Could not enable sddm"
  fi
  ok "SDDM theme catppuccin-mocha"
}

clone_into_share() {
  local name="$1" url="$2"
  local dest="$LOCAL_SHARE/$name"

  CLONE_DEST="$dest"

  if [[ -d "$dest/.git" ]]; then
    ok "$name already cloned at $dest"
    return 0
  fi

  if (( DRY_RUN )); then
    ok "Would git clone $url → $dest"
    return 0
  fi

  mkdir -p "$LOCAL_SHARE"
  if [[ -e "$dest" ]]; then
    backup_existing "$dest"
  fi
  git clone --depth 1 "$url" "$dest"
  ok "Cloned $name → $dest"
}

install_shell_noctalia() {
  if need_cmd noctalia; then
    ok "noctalia already on PATH"
    return 0
  fi

  if (( SKIP_PACKAGES )); then
    warn "noctalia not on PATH and --skip-packages set"
    return 0
  fi

  # Retry distro package once more, then build from source into ~/.local
  try_pkg_install noctalia || true
  if need_cmd noctalia; then
    ok "noctalia installed from package"
    return 0
  fi

  warn "noctalia package missing; building from source into ~/.local"
  if (( DRY_RUN )); then
    ok "Would clone noctalia-dev/noctalia and just configure/build/install to ~/.local"
    return 0
  fi

  clone_into_share noctalia https://github.com/noctalia-dev/noctalia.git
  local dest="$CLONE_DEST"
  if ! need_cmd just || ! need_cmd meson; then
    try_pkg_install just meson gcc-c++ 2>/dev/null || try_pkg_install just meson gcc || true
  fi
  (
    cd "$dest"
    just configure release "$HOME/.local"
    just build release
    just install release
  ) || warn "noctalia source build failed — install manually from https://docs.noctalia.dev"
}

install_shell_material() {
  if need_cmd dms; then
    ok "dms already on PATH"
    return 0
  fi

  if (( SKIP_PACKAGES )); then
    warn "dms not on PATH and --skip-packages set"
    return 0
  fi

  log "Installing DankMaterialShell (danklinux installer)"
  if (( DRY_RUN )); then
    ok "Would run: curl -fsSL https://install.danklinux.com | sh"
    return 0
  fi

  if curl -fsSL https://install.danklinux.com | sh; then
    ok "DankMaterialShell installed"
    return 0
  fi

  warn "danklinux installer failed; cloning repo for manual setup"
  clone_into_share DankMaterialShell https://github.com/AvengeMedia/DankMaterialShell.git >/dev/null || true
  warn "Run quickshell against $LOCAL_SHARE/DankMaterialShell/quickshell/ or retry install.danklinux.com"
}

install_shell_celestial() {
  local qs_dir="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell"
  local dest="$qs_dir/caelestia"

  if need_cmd caelestia || [[ -d "$dest" ]]; then
    ok "Caelestia shell present"
    return 0
  fi

  if (( SKIP_PACKAGES )); then
    warn "Caelestia not installed and --skip-packages set"
    return 0
  fi

  # Arch may have AUR package — try pacman name quietly
  if [[ "$OS_FAMILY" == arch ]]; then
    try_pkg_install caelestia-shell || true
    if need_cmd caelestia; then
      ok "caelestia-shell installed"
      return 0
    fi
  fi

  warn "Cloning Caelestia shell into $dest (manual CMake install may still be required)"
  if (( DRY_RUN )); then
    ok "Would clone caelestia-dots/shell → $dest and run cmake"
    return 0
  fi

  mkdir -p "$qs_dir"
  if [[ -e "$dest" ]]; then
    backup_existing "$dest"
  fi
  git clone --depth 1 --recurse-submodules https://github.com/caelestia-dots/shell.git "$dest"
  (
    cd "$dest"
    cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/ \
      -DINSTALL_QSCONFDIR="$dest" || true
    cmake --build build || true
    sudo_if_needed cmake --install build || true
  ) || warn "Caelestia CMake steps incomplete — see https://github.com/caelestia-dots/shell"
  ok "Caelestia sources at $dest (start with: caelestia shell -d)"
}

install_desktop_shell() {
  (( SKIP_DESKTOP )) && return 0
  case "$DESKTOP_SHELL" in
    noctalia)  install_shell_noctalia ;;
    material)  install_shell_material ;;
    celestial) install_shell_celestial ;;
    none)      ok "No desktop shell selected" ;;
  esac
}

# --- Args / main --------------------------------------------------------------

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --skip-packages) SKIP_PACKAGES=1 ;;
      --skip-fonts) SKIP_FONTS=1 ;;
      --skip-grub) SKIP_GRUB=1 ;;
      --skip-desktop) SKIP_DESKTOP=1 ;;
      --no-sddm) ENABLE_SDDM=0 ;;
      --compositor)
        shift
        [[ $# -gt 0 ]] || die "--compositor needs a value"
        COMPOSITOR="${1,,}"
        ;;
      --compositor=*)
        COMPOSITOR="${1#*=}"
        COMPOSITOR="${COMPOSITOR,,}"
        ;;
      --shell)
        shift
        [[ $# -gt 0 ]] || die "--shell needs a value"
        DESKTOP_SHELL="${1,,}"
        ;;
      --shell=*)
        DESKTOP_SHELL="${1#*=}"
        DESKTOP_SHELL="${DESKTOP_SHELL,,}"
        ;;
      --dry-run) DRY_RUN=1 ;;
      *) die "Unknown option: $1" ;;
    esac
    shift
  done
}

count_install_steps() {
  # packages bun rust fastfetch omp font omz plugins links grub (+ optional desktop)
  local n=10
  if (( ! SKIP_DESKTOP )); then
    n=$((n + 4))
  fi
  STEP_TOTAL=$n
  STEP_CURRENT=0
}

main() {
  parse_args "$@"

  [[ -d "$DOTFILES" ]] || die "Expected $DOTFILES — run this from the myeow-linux-config repo"
  require_supported_os
  resolve_desktop_choices
  count_install_steps

  printf '\n%smyeow linux config%s\n' "$C_BOLD" "$C_RESET"
  printf '  repo:    %s\n' "$REPO_ROOT"
  printf '  home:    %s\n' "$HOME"
  printf '  os:      %s (%s)\n' "$OS_PRETTY" "$OS_FAMILY"
  if (( ! SKIP_DESKTOP )); then
    printf '  desk:    %s + %s (sddm=%s)\n' "$COMPOSITOR" "$DESKTOP_SHELL" \
      "$( (( ENABLE_SDDM )) && echo yes || echo no )"
  else
    printf '  desk:    skipped (--skip-desktop)\n'
  fi
  (( DRY_RUN )) && printf '  mode:    dry-run\n'
  printf '\n'

  log "Using $OS_FAMILY install flow"

  with_spinner "Installing base packages" install_packages || true
  with_spinner "Installing bun" install_bun || true
  with_spinner "Installing Rust" install_rust || true
  with_spinner "Installing fastfetch" install_fastfetch || true
  with_spinner "Installing oh-my-posh" install_oh_my_posh || true
  with_spinner "Installing Nerd Font" install_nerd_font || true
  with_spinner "Installing Oh My Zsh" install_oh_my_zsh || true
  with_spinner "Installing zsh plugins" install_omz_plugins || true
  with_spinner "Linking themes & dotfiles" install_dotfile_links || true
  with_spinner "Installing GRUB theme" install_grub || true

  if (( ! SKIP_DESKTOP )); then
    with_spinner "Installing desktop packages" install_desktop_packages || true
    with_spinner "Linking desktop configs" install_desktop_configs || true
    with_spinner "Installing desktop shell ($DESKTOP_SHELL)" install_desktop_shell || true
    with_spinner "Installing SDDM theme" install_sddm_theme || true
  fi

  ensure_zsh_shell

  printf '\n%sDone.%s Open a new terminal (or run: exec zsh).\n' "$C_GREEN" "$C_RESET"
  if (( ! SKIP_DESKTOP )); then
    printf 'Desktop: start a %s session from SDDM (or your login manager).\n' "$COMPOSITOR"
  fi
  if [[ -d "$BACKUP_DIR" ]]; then
    printf 'Backups: %s\n' "$BACKUP_DIR"
  fi
}

main "$@"
