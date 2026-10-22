#!/usr/bin/env bash
# Juice installer.
#
# Idempotent: safe to run repeatedly. Does three things:
#   1. validates the manifest and links/copies the plugin into the Omarchy
#      plugins directory (skipped when already installed there),
#   2. installs the user systemd unit that re-applies the saved charge target,
#   3. installs the udev rule that makes the charge thresholds writable — only
#      when the current user cannot already write them, so an existing rule
#      (or a previous run) short-circuits the privileged step.
#
# Usage:
#   ./install.sh                 install everything, enable the plugin
#   ./install.sh --no-enable     install but do not add it to the bar

set -euo pipefail

PLUGIN_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
UNIT_NAME="juice-charge-target.service"
UDEV_SRC="$PLUGIN_DIR/udev/99-juice-charge-thresholds.rules"
UDEV_DST="/etc/udev/rules.d/99-juice-charge-thresholds.rules"
POWER_SUPPLY="${JUICE_POWER_SUPPLY_PATH:-/sys/class/power_supply}"

ENABLE=1
for arg in "$@"; do
  case "$arg" in
    --no-enable) ENABLE=0 ;;
    -h | --help)
      sed -n '2,15p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *)
      printf 'install: unknown option %s\n' "$arg" >&2
      exit 1
      ;;
  esac
done

command -v jq >/dev/null 2>&1 || {
  printf 'install: jq is required\n' >&2
  exit 1
}

# Battery-usage metering is the only section that needs Python; the rest of the
# plugin works without it, so a missing interpreter is a notice, not a failure.
command -v python3 >/dev/null 2>&1 ||
  printf '  python3: not found — the battery-usage card will stay unavailable\n'

PLUGIN_ID="$(jq -r '.id' "$PLUGIN_DIR/manifest.json")"
TARGET="$PLUGINS_DIR/$PLUGIN_ID"

printf '\nJuice installer\n'
printf '  plugin: %s\n' "$PLUGIN_ID"

# --- 1. validate + place the plugin ------------------------------------------

if command -v omarchy-plugin-validate >/dev/null 2>&1; then
  omarchy-plugin-validate "$PLUGIN_DIR"
  printf '  manifest: valid\n'
else
  printf '  manifest: omarchy-plugin-validate not found, skipped\n'
fi

chmod +x "$PLUGIN_DIR"/scripts/juice-*

mkdir -p "$PLUGINS_DIR"
if [[ "$TARGET" == "$PLUGIN_DIR" ]]; then
  printf '  plugin dir: already installed at %s\n' "$TARGET"
elif [[ -L "$TARGET" && "$(readlink -f "$TARGET")" == "$PLUGIN_DIR" ]]; then
  printf '  plugin dir: symlink already in place (%s)\n' "$TARGET"
elif [[ -e "$TARGET" ]]; then
  printf '  plugin dir: %s already exists and is not this checkout — leaving it alone\n' "$TARGET" >&2
  printf '              remove it with: omarchy plugin remove %s\n' "$PLUGIN_ID" >&2
  exit 1
else
  ln -s "$PLUGIN_DIR" "$TARGET"
  printf '  plugin dir: linked %s -> %s\n' "$TARGET" "$PLUGIN_DIR"
fi

# --- 2. user unit that re-applies the saved target ---------------------------

mkdir -p "$UNIT_DIR"
sed "s|@PLUGIN_DIR@|$TARGET|g" "$PLUGIN_DIR/systemd/$UNIT_NAME" > "$UNIT_DIR/$UNIT_NAME"
systemctl --user daemon-reload
systemctl --user enable --now "$UNIT_NAME" >/dev/null 2>&1 || true
printf '  systemd user unit: %s installed and enabled\n' "$UNIT_NAME"

# --- 3. udev rule for threshold write access ---------------------------------

battery=""
for candidate in "$POWER_SUPPLY"/BAT*; do
  [[ -d "$candidate" && -e "$candidate/charge_control_end_threshold" ]] || continue
  battery="$candidate"
  break
done

end_attr="${battery:-/sys/class/power_supply/BAT0}/charge_control_end_threshold"

if [[ -n "$battery" && -w "$end_attr" ]]; then
  printf '  udev rule: %s is already writable, skipping the privileged step\n' "$end_attr"
else
  printf '  udev rule: installing %s (needs root)\n' "$UDEV_DST"
  if command -v sudo >/dev/null 2>&1; then
    sudo install -m 644 "$UDEV_SRC" "$UDEV_DST"
    sudo udevadm control --reload-rules
    sudo udevadm trigger --subsystem-match=power_supply
  else
    printf '  sudo not found — install it manually:\n' >&2
    printf '    install -m 644 %s %s\n' "$UDEV_SRC" "$UDEV_DST" >&2
    printf '    udevadm control --reload-rules && udevadm trigger --subsystem-match=power_supply\n' >&2
  fi
fi

# --- 4. enable the plugin in the bar ----------------------------------------

if (( ENABLE )); then
  if command -v omarchy-shell >/dev/null 2>&1 && command -v omarchy-plugin-list >/dev/null 2>&1; then
    omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
    if omarchy-plugin-list --json 2>/dev/null | jq -e --arg id "$PLUGIN_ID" 'any(.[]; .id == $id and .enabled == true)' >/dev/null; then
      printf '  bar widget: already enabled\n'
    else
      omarchy plugin enable "$PLUGIN_ID" --section right
    fi
  else
    printf '  bar widget: omarchy shell not available, enable it later with:\n'
    printf '              omarchy plugin enable %s --section right\n' "$PLUGIN_ID"
  fi
else
  printf '  bar widget: --no-enable given, skipped\n'
fi

# --- 5. report the live hardware state ---------------------------------------

printf '\nCurrent hardware state:\n'
bash "$PLUGIN_DIR/scripts/juice-stats" | sed 's/^/  /'
printf '\nDone. Open the bar widget and use "80%% Limit" / "100%% Full".\n'
