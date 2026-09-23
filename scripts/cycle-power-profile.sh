#!/usr/bin/env bash
# Cycle power-profiles-daemon profiles: power-saver → balanced → performance → …
set -euo pipefail

if ! command -v powerprofilesctl >/dev/null 2>&1; then
  echo "powerprofilesctl not found" >&2
  exit 1
fi

mapfile -t profiles < <(powerprofilesctl list 2>/dev/null | sed -n 's/^[* ] \([^ ]*\):.*/\1/p')
if (( ${#profiles[@]} == 0 )); then
  profiles=(power-saver balanced performance)
fi

current="$(powerprofilesctl get 2>/dev/null || true)"
next="${profiles[0]}"
for i in "${!profiles[@]}"; do
  if [[ "${profiles[$i]}" == "$current" ]]; then
    next="${profiles[$(( (i + 1) % ${#profiles[@]} ))]}"
    break
  fi
done

powerprofilesctl set "$next"
if command -v notify-send >/dev/null 2>&1; then
  notify-send -a myeow "Power profile" "$next" -t 2000 || true
fi
printf '%s\n' "$next"
