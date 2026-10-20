#!/usr/bin/env bash
# OmaBattery uninstaller.
#
# Removes what install.sh added: the user systemd unit, the plugin symlink (only
# when it points at this checkout) and, with root, the udev rule. It never
# touches the battery's current charge threshold — the hardware keeps its last
# value — and it leaves the saved state file in place.
#
# Usage:
#   ./uninstall.sh                remove unit + symlink + udev rule
#   ./uninstall.sh --keep-udev    keep the charge-threshold udev rule

set -euo pipefail

PLUGIN_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
UNIT_NAME="omabattery-charge-target.service"
UDEV_DST="/etc/udev/rules.d/99-omabattery-charge-thresholds.rules"

KEEP_UDEV=0
for arg in "$@"; do
  case "$arg" in
    --keep-udev) KEEP_UDEV=1 ;;
    -h | --help)
      sed -n '2,14p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *)
      printf 'uninstall: unknown option %s\n' "$arg" >&2
      exit 1
      ;;
  esac
done

command -v jq >/dev/null 2>&1 || {
  printf 'uninstall: jq is required\n' >&2
  exit 1
}

PLUGIN_ID="$(jq -r '.id' "$PLUGIN_DIR/manifest.json")"
TARGET="$PLUGINS_DIR/$PLUGIN_ID"

printf '\nOmaBattery uninstaller\n'

# --- 1. disable the plugin in the bar ---------------------------------------

if command -v omarchy-plugin-disable >/dev/null 2>&1; then
  if omarchy-plugin-list --json 2>/dev/null | jq -e --arg id "$PLUGIN_ID" 'any(.[]; .id == $id and .enabled == true)' >/dev/null; then
    omarchy plugin disable "$PLUGIN_ID"
    printf '  bar widget: disabled\n'
  else
    printf '  bar widget: not enabled\n'
  fi
else
  printf '  bar widget: omarchy commands unavailable, disable manually\n'
fi

# --- 2. user systemd unit ----------------------------------------------------

if [[ -e "$UNIT_DIR/$UNIT_NAME" ]]; then
  systemctl --user disable --now "$UNIT_NAME" >/dev/null 2>&1 || true
  rm -f "$UNIT_DIR/$UNIT_NAME"
  systemctl --user daemon-reload
  printf '  systemd user unit: removed\n'
else
  printf '  systemd user unit: not installed\n'
fi

# --- 3. plugin directory -----------------------------------------------------

if [[ -L "$TARGET" && "$(readlink -f "$TARGET" 2>/dev/null)" == "$PLUGIN_DIR" ]]; then
  rm -f "$TARGET"
  printf '  plugin dir: removed symlink %s\n' "$TARGET"
elif [[ -d "$TARGET" ]]; then
  printf '  plugin dir: %s is a real checkout — remove it with: omarchy plugin remove %s\n' "$TARGET" "$PLUGIN_ID"
else
  printf '  plugin dir: nothing to remove\n'
fi

# --- 4. udev rule (privileged) ----------------------------------------------

if (( KEEP_UDEV )); then
  printf '  udev rule: kept (--keep-udev)\n'
elif [[ -e "$UDEV_DST" ]]; then
  if command -v sudo >/dev/null 2>&1; then
    sudo rm -f "$UDEV_DST"
    sudo udevadm control --reload-rules
    printf '  udev rule: removed (charge thresholds revert to root-only on next boot)\n'
  else
    printf '  udev rule: remove it manually:\n' >&2
    printf '    rm -f %s && udevadm control --reload-rules\n' "$UDEV_DST" >&2
  fi
else
  printf '  udev rule: not installed\n'
fi

printf '\nThe battery keeps its last hardware threshold; the saved target file is left in place.\n'
