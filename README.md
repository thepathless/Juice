# OmaBattery

Battery bar widget and compact dashboard panel for [Omarchy](https://omarchy.org):

1. **Bespoke Animated Vector Battery** — a custom, GPU-accelerated QML battery component (`BatteryIcon.qml`) with smooth animated liquid fill, charging pulse animation, and hardware limit tick markers. Replaces generic font glyphs with optical scaling that never shrinks or distorts at 100% capacity.
2. **Compact Modern Dashboard UI** — a sleek 290px card designed in the Omarchy aesthetic: an integrated hero card with live wattage, segmented pill controls for charge limits and power profiles, and a 2x2 Bento grid for hardware telemetry.
3. **Hardware Charge Targets** — `Charge to 80%` and `Charge to 100%` write the kernel charge threshold directly via sysfs, so a laptop holding at a conservation limit resumes charging instantly.
4. **Rich Hardware Telemetry** — live health %, cycles, energy flow, temperature, voltage, and cell chemistry straight from `/sys/class/power_supply/`.
5. **Smart Automation & Escalation** — dynamic theme color escalation (theme yellow at 50%, urgent red below 25%), and automatic power-saver profile engagement with configurable threshold.

## Features

- **Zero-Glitch Optical Scaling**: Percentage labels use native font metrics beside the icon, eliminating the optical glyph shrinking bug at 100%.
- **Live Fluid Fill**: Liquid level changes transition smoothly with cubic easing.
- **Dynamic Energy Glow**: Subtle breathing animation visually confirms energy flowing in while charging.
- **ThinkPad & Modern Laptop Longevity**: Native support for `charge_control_end_threshold`.


## Requirements

- Omarchy with the Quickshell shell (bar widget plugin support)
- A battery that exposes `charge_control_end_threshold` / `charge_stop_threshold`
  for the charge-target buttons (ThinkPads, and most modern laptops). The health
  section works on any battery.
- `jq` for the installer

## Install

```bash
omarchy plugin add https://github.com/thepathless/OmaBattery.git
~/.config/omarchy/plugins/thepathless.omabattery/install.sh
```

Or from a local checkout:

```bash
cd OmaBattery
./install.sh
```

`install.sh` is idempotent and does four things:

| Step | What it does | Privilege |
| --- | --- | --- |
| validate | runs `omarchy plugin validate` on the manifest | user |
| place | links/copies the plugin into `~/.config/omarchy/plugins/thepathless.omabattery` | user |
| restore unit | installs and enables `omabattery-charge-target.service` (user unit) | user |
| udev rule | installs `99-omabattery-charge-thresholds.rules` so the thresholds are writable | root (skipped when already writable) |

Finally it enables the widget in the right bar section.

## How the charge targets work

Two layers, no privilege helper at runtime:

- **Privilege** — `udev/99-omabattery-charge-thresholds.rules` chmods
  `charge_control_start_threshold` / `charge_control_end_threshold` (and the
  older `charge_start_threshold` / `charge_stop_threshold` naming) to `0666` when
  the battery appears. The panel then writes the value directly; there is no
  `pkexec`, polkit policy or root-owned helper in the code path.
- **Persistence** — ThinkPad-class embedded controllers store the thresholds in
  NVRAM, so they already survive a reboot. For hardware that forgets, the
  chosen target is saved to `$XDG_STATE_HOME/omabattery/charge-target` and
  re-applied by the user unit at login.

Selecting a target writes start `0` (kernel ABI: `0` = no lower bound, i.e.
"threshold off") followed by the stop threshold. Setting the stop threshold back
to `100` is what un-clamps a machine currently holding at 80 — charging resumes
immediately, no reboot and no unplugging needed.

The panel never assumes the write landed: `scripts/omabattery-set-limit` reads
both attributes back from the controller, reports them, and the section shows
what the hardware actually holds along with its live charging state.

## Bar icon and options

The bar glyph comes from bindings on UPower plus a power-supply uevent monitor
(`udevadm monitor --subsystem-match=power_supply`), so it flips the moment the
hardware does instead of on a timer:

| State | Glyph | When |
| --- | --- | --- |
| Charging | charging battery for the level | current is flowing in |
| Plugged in, not charging | `󰚥` | on AC, holding at a charge limit |
| Full | `󰂅` | at 100% |
| Discharging | battery for the level | running on battery |

Colour escalates as the battery runs down: the active theme's **yellow** at 50%
and below, its **red** strictly below 25%, otherwise the normal bar colour. Both
are read from the theme's own `colors.toml` — the same file `Commons/Color.qml`
reads — so no palette is hardcoded and a theme switch re-colours the icon.

The sysfs `status` attribute is preferred over UPower's state, because UPower
only learns about a threshold being reached on its next poll; the kernel
attribute flips immediately.

Both options live in the panel's **OPTIONS** section and are stored in this
widget's inline `shell.json` entry — the mechanism every Omarchy bar setting uses
— so they survive a restart:

| Option | Default | Effect |
| --- | --- | --- |
| Show percentage | off | Level next to the icon, in the icon's own colour (also on right-click) |
| Power saver at (%) | 50 | On battery at or below this level, switch to the `power-saver` profile; release at +3% so it cannot flap |

```bash
omarchy-shell thepathless.omabattery setShowPercentage true
omarchy-shell thepathless.omabattery setPowerSaverThreshold 50
omarchy-shell thepathless.omabattery state    # what the bar is rendering right now
```

## Command line / IPC

```bash
omarchy-shell thepathless.omabattery charge100
omarchy-shell thepathless.omabattery charge80
bash ~/.config/omarchy/plugins/thepathless.omabattery/scripts/omabattery-set-limit 100
bash ~/.config/omarchy/plugins/thepathless.omabattery/scripts/omabattery-stats
```

## Uninstall

```bash
~/.config/omarchy/plugins/thepathless.omabattery/uninstall.sh
# or, for a git-managed checkout:
omarchy plugin remove thepathless.omabattery
```

`uninstall.sh` disables the widget, removes the user unit and the udev rule and
deletes the symlink when it points at this checkout. It leaves the battery's
current hardware threshold and the saved target file alone.

## Layout

```
OmaBattery/
├── manifest.json                              plugin manifest (schemaVersion 1)
├── Panel.qml                                  bar widget + panel
├── Model.js                                   stock helpers + health/limit formatting
├── scripts/omabattery-stats                   read-only sysfs probe
├── scripts/omabattery-set-limit               applies/restores a charge target
├── udev/99-omabattery-charge-thresholds.rules threshold write access
├── systemd/omabattery-charge-target.service   login restore unit
├── install.sh / uninstall.sh
```

## License

MIT — see [LICENSE](LICENSE).
