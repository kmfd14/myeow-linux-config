#!/usr/bin/env bash
# Open Kitty with btop, cava, and fastfetch after a graphical session is up.
# Autostarted on desktop login (Sway / Niri / Hyprland) via install.sh.
set -euo pipefail

SESSION="${XDG_CONFIG_HOME:-$HOME/.config}/kitty/dashboard.session"
KITTY_BIN="$(command -v kitty || true)"

if [[ -z "$KITTY_BIN" ]]; then
  echo "startup-dashboard: kitty not on PATH" >&2
  exit 1
fi

if [[ ! -f "$SESSION" ]]; then
  echo "startup-dashboard: missing session file $SESSION" >&2
  exit 1
fi

# Wait until a display is available (compositor just started)
for _ in $(seq 1 80); do
  if [[ -n "${WAYLAND_DISPLAY:-}" || -n "${DISPLAY:-}" ]]; then
    break
  fi
  sleep 0.25
done

if [[ -z "${WAYLAND_DISPLAY:-}" && -z "${DISPLAY:-}" ]]; then
  echo "startup-dashboard: no WAYLAND_DISPLAY/DISPLAY after wait" >&2
  exit 1
fi

# Brief settle so PipeWire / shell applets are up for cava
sleep 1

exec "$KITTY_BIN" --session "$SESSION"
