# Juice architecture

Four layers, one direction. Each layer can be understood and tested without the
one above it.

```
read-only system sources
  scripts/juice-stats     sysfs battery telemetry (tab-separated)
  scripts/juice-devices   every battery device, UPower + BlueZ + sysfs (JSON)
  scripts/juice-usage     metering sampler and report (JSON, own state file)
        │
        ▼
policy — Model.js
  parsing, thresholds, ordering, labels, formatting; pure functions, no state
        │
        ▼
views — QML components
  BatteryIcon         the glyph
  SectionCard         section frame: fixed body or disclosure with summary
  DetailRow           shared label/value row (battery card + device dropdown)
  ConnectedDevices    device list and its drop-down body
  UsageCard           iOS Daily Usage card, chart grid and both charts
  UsageAppList        per-app rows
  SessionActions      the five hold-to-run tiles
  HoldKeys            focused key layer for plain-letter session holds
  OptionRow, NumberField, DetailTabs (inline components in Panel)
        │  props down, signals up
        ▼
orchestration — Panel.qml
  bar button, panel shell, Processes, timers, IPC, all live state
```

## Panel surface

The panel is one permanent hero — level, state, time left, live wattage — plus
three permanent `SectionCard`s and five disclosures. CHARGE TARGET, POWER
PROFILE and SESSION are always open (`collapsible: false`); BATTERY DETAIL,
CONNECTED DEVICES, BATTERY USAGE, USAGE BY APP and OPTIONS are closed on every
open. The data disclosures carry their most useful number in the header; all
five open independently. The card scrolls when the permanent sections and any
open body exceed the space under the bar, and `collapseSections()` resets the
five disclosures, the open device and `usageDay` on every open.

SESSION is five tiles — Lock, Sleep, Hibernate, Reboot, Shut down — using
Omarchy's own commands. A tile runs only after a three-second hold with the mouse
or with the letter printed on it; `SessionActions` owns press/release, while
`Panel.qml` owns the timer, progress and the guarded `execDetached`. `HoldKeys`
claims only the session letters while the panel has focus, so Omarchy's `Super`
bindings are never involved. Sleep and Hibernate are omitted when the capability
probe says the machine cannot enter them.

`usageDay` drives the drill-down. Selecting a bar makes `UsageCard` render that
day's own curve, percentage, measured energy and Screen On/Off totals, and
switches USAGE BY APP to that day's rows. A day with no measurement is an empty
grid, `—` and `No measurements were recorded for this day`; a past day with holes
in its hourly buckets names how many hours were observed before quoting its
percentage, so a partial reading is never presented as a whole-day total. A
measured day whose app rows were never recorded says
`App breakdown wasn't recorded for this day`.
The closed BATTERY USAGE header names the selected day (`21 Oct · 88%`), and
`‹ Today` clears the selection.

A wireless peripheral whose hardware exposes no battery channel is still listed
with `Not reported`; the level is absent because the hardware has none to read
— for a 2.4 GHz receiver, no `power_supply` node or `hidpp_battery` device
exists — not because the probe failed.

## State ownership

| State | Owner | Notes |
| --- | --- | --- |
| Live battery/profile/sysfs data | `Panel.qml` | Process output, refreshed on udev/open |
| `deviceList`, `expandedDevice` | `Panel.qml` | passed to `ConnectedDevices`; taps come back as `toggled(id)` |
| Section open flags | `Panel.qml` | `detailOpen`, `devicesOpen`, `usageOpen`, `appsOpen`, `optionsOpen`, reset by `collapseSections()` on every open; cards receive one bool and emit `toggled()` |
| Session hold id/progress, capability probe | `Panel.qml` | one hold at a time; `SessionActions`/`HoldKeys` emit start/end and render the fill, the panel owns the 3 s timer and command |
| `usageInfo`, `usageUnavailable` | `Panel.qml` | report JSON from `juice-usage --report` |
| `usageDay` (selected bar), app rows/note for it | `Panel.qml` | `""` is today, reset by `collapseSections()`; `UsageCard` emits `daySelected(date)` |
| Detail tab index, keyboard profile cursor, option settings | `Panel.qml` | tab selection; the six OPTIONS values persist through the widget's inline `shell.json` entry |
| Metered history (35 days) | `scripts/juice-usage` | `~/.local/state/juice/usage.json`; the only persisted state |
| Everything else | nobody | `juice-devices` and `Model.js` are stateless |

Components carry no probes, timers or persistence. Their only local state is
presentation detail such as hover and animation progress.

## Data flow

**Read path.** A `Process` in `Panel.qml` runs a script, `Model.parseDevices` /
`Model.parseUsageReport` validate the payload (returning `null` rather than
throwing), and the result is bound into props on a view component. A view never
formats a number that Model did not produce, and a malformed payload leaves the
last good data on screen.

**Write path.** Buttons and IPC call `Panel.qml`, which runs the writer script
and then reads the hardware back. The UI never assumes a write succeeded.

**Power-saver automation.** `Auto power-saver` is a persisted boolean, default
on. When it is on, `evaluatePowerSaver()` follows the battery level and the
threshold; when it is switched off, the handler releases any profile the
automation engaged and restores the profile that preceded it.

**Usage metering.** The sampler daemon runs for the shell's lifetime and is the
only writer of `usage.json`; the report command only reads it. Backfilling from
UPower history happens before the first sample of a day, so charts are populated
from the first launch. CPU deltas and focused time are sampled regardless of
power source; the app list merges today's battery rows with today's activity
rows (activity first on AC), and each row carries the `basis` text naming its
window. `appsNote` is empty when rows exist and carries the empty-state message
when nothing was measured.

## Rules for later passes

- No system probing inside component QML. Add a read-only script that emits
  JSON, parse it in `Model.js`, poll it from `Panel.qml`.
- Any new label, threshold, sort or formatting rule belongs in `Model.js` with
  a case in `tests/color`, `tests/devices`, `tests/session` or `tests/usage`.
- Components receive colours and font family as properties; they never reach
  into `root.bar`.
- `Panel.qml` stays the single state owner: pass primitives down, emit signals
  up. Do not create a second owner for the same fact.
- The battery card's internals (`DetailTabs`, the HEALTH/POWER/SPECS tab
  content) are a deliberate scope boundary from the connected-devices work;
  changing them is a separate task.
