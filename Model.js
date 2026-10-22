// Model helpers for Juice.
//
// The first half is the stock omarchy.power Model.js (profile picking, icon
// selection); its charge-threshold heuristic is replaced by the exact on-AC /
// limit boundary below. The second half adds the formatting used by the
// charge-target controls and the battery health section.

function clampIndex(index, length) {
  if (length <= 0) return 0
  return Math.max(0, Math.min(length - 1, index))
}

function selectProfileIndex(index, delta, profiles) {
  var values = Array.isArray(profiles) ? profiles : []
  if (values.length === 0) return 0
  return clampIndex(index + delta, values.length)
}

function parseKeyValue(raw) {
  var next = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var idx = lines[i].indexOf("\t")
    if (idx <= 0) continue
    next[lines[i].substring(0, idx)] = lines[i].substring(idx + 1).trim()
  }
  return next
}

function parseProfiles(raw, previousIndex) {
  var lines = String(raw || "").split("\n")
  var list = []
  var active = ""
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    var parts = line.split("\t")
    list.push(parts[0])
    if (parts[1] === "1") active = parts[0]
  }
  return {
    profiles: list,
    activeProfile: active,
    profileIndex: clampIndex(previousIndex || 0, list.length)
  }
}

function profileIcon(name) {
  if (name === "power-saver") return "󰌪"
  if (name === "balanced") return "󰊚"
  if (name === "performance") return "󰓅"
  return "󰂄"
}

// ---- Session power actions -------------------------------------------------
//
// The five actions the panel offers below the power profile. Their commands
// and glyphs are the ones Omarchy's own system menu uses, so Juice inherits
// the session scripts' shutdown flow, sleep helpers and translations instead
// of forking them. `holdKey` is the plain letter held inside the open panel:
// no compositor shortcut is involved, so Super+L and Super+S stay exactly as
// Omarchy ships them.
var SESSION_ACTIONS = [
  {
    id: "lock",
    label: "Lock",
    icon: "",
    holdKey: "L",
    command: "omarchy-system-lock"
  },
  {
    id: "suspend",
    label: "Sleep",
    icon: "󰒲",
    holdKey: "Z",
    command: "systemctl suspend",
    requires: "suspend"
  },
  {
    id: "hibernate",
    label: "Hibernate",
    icon: "󰤁",
    holdKey: "H",
    command: "systemctl hibernate",
    requires: "hibernate"
  },
  {
    id: "reboot",
    label: "Reboot",
    icon: "󰜉",
    holdKey: "R",
    command: "omarchy-system reboot",
    destructive: true
  },
  {
    id: "shutdown",
    label: "Shut down",
    icon: "󰐥",
    holdKey: "S",
    command: "omarchy-system shutdown",
    destructive: true
  }
]

function sessionActionAvailable(action, available) {
  if (!action || !action.requires) return !!action
  return !!(available && available[action.requires])
}

// Only available actions are offered, so the 1-5 numbering always names a row
// the user can actually see. The hold letters stay stable either way.
function sessionActions(available) {
  var list = []
  for (var i = 0; i < SESSION_ACTIONS.length; i++) {
    if (sessionActionAvailable(SESSION_ACTIONS[i], available)) list.push(SESSION_ACTIONS[i])
  }
  return list
}

function sessionActionById(id) {
  for (var i = 0; i < SESSION_ACTIONS.length; i++) {
    if (SESSION_ACTIONS[i].id === id) return SESSION_ACTIONS[i]
  }
  return null
}

// A letter or digit typed in the open panel. The caller passes the filtered
// list, so a number always means the row shown at that position.
function sessionActionForKey(text, actions) {
  var key = String(text === undefined || text === null ? "" : text).toLowerCase()
  if (key === "") return null
  var list = Array.isArray(actions) ? actions : []
  for (var i = 0; i < list.length; i++) {
    if (list[i].holdKey.toLowerCase() === key) return list[i]
  }
  if (/^[1-9]$/.test(key)) {
    var index = parseInt(key, 10) - 1
    if (index >= 0 && index < list.length) return list[index]
  }
  return null
}

function parseSessionProbe(raw) {
  try {
    var json = JSON.parse(String(raw || "").trim() || "{}")
    return {
      suspend: json.suspend !== false,
      hibernate: json.hibernate === true
    }
  } catch (e) {
    // A failed probe must not invent a working hibernate path on a desktop
    // that has no swap. Suspend is the common case and stays available.
    return { suspend: true, hibernate: false }
  }
}

function batteryFraction(device) {
  return device && device.isPresent ? Math.max(0, Math.min(1, device.percentage)) : 0
}

// A charge limit is only holding when the machine is on AC and the pack has
// actually reached limit - 1 (the EC counts in whole percent, so the boundary
// can report one below the limit). Nothing about time-to-full or the charge
// rate takes part: below the limit the current is still flowing and the state
// must say so.
function chargeThresholdActive(device, onBattery, chargeLimit) {
  var d = device || {}
  if (!(d && d.isPresent) || onBattery) return false

  var limit = Number(chargeLimit)
  if (!isFinite(limit) || limit <= 0 || limit >= 100) return false

  return batteryLevel(d) >= limit - 1
}

function batteryIcon(device, onBattery, chargeLimit) {
  return batteryIconForState(batteryState(device, onBattery, chargeLimit), batteryLevel(device), onBattery)
}

// ------------------------------------------------------------- bar state ---
//
// The bar icon has to say four different things at a glance, and it has to
// flip the instant the hardware does. Everything below is a pure function of
// the UPower device, so the panel can drive it from bindings (event-driven)
// instead of polling.

function batteryLevel(device) {
  var d = device || {}
  if (!d || !d.isPresent) return -1
  var pct = Number(d.percentage)
  if (!isFinite(pct)) return -1
  return Math.round(Math.max(0, Math.min(1, pct)) * 100)
}

// "charging" while current flows in, "full" at the top, "plugged" when on AC
// holding at the charge limit, and "discharging" when the battery is the
// source. "absent" on desktops. The limit only matters on AC: off AC the pack
// is the source no matter where it sits relative to the limit.
function batteryState(device, onBattery, chargeLimit) {
  var d = device || {}
  if (!d.isPresent) return "absent"

  if (onBattery) return "discharging"
  if (batteryLevel(d) >= 100) return "full"
  if (chargeThresholdActive(d, onBattery, chargeLimit)) return "plugged"
  return "charging"
}

function stateLabel(state, level) {
  if (state === "charging") return "Charging"
  if (state === "full") return "Fully charged"
  if (state === "plugged") return "Plugged in"
  if (state === "discharging") return level >= 0 ? "On battery, " + level + "%" : "On battery"
  return ""
}

// The sentence under the charge bar: the same state, spelled out with the
// charge limit when the hardware exposes one. It reads nothing but the derived
// state, so an unknown or stale kernel status can never contradict the glyph.
function stateDetailLabel(state, level, limit) {
  var cap = number(limit)
  var hasLimit = cap >= 0
  var suffix = hasLimit ? " · limit " + cap + "%" : ""
  if (state === "charging") return "Charging" + suffix
  if (state === "plugged") return hasLimit ? "Holding at the " + cap + "% limit" : "Plugged in"
  if (state === "full") return "Fully charged" + suffix
  if (state === "discharging") return "Discharging" + suffix
  return ""
}

// The long form of the same fact, for the bar tooltip: the card is 290 px and
// already says the short version, the explanation needs room of its own.
function stateExplanation(state, limit) {
  var cap = number(limit)
  if (state !== "plugged" || cap < 0) return ""
  return "The embedded controller passes AC through while held at " + cap + "%"
}

// Which phrase set the hero may rotate: current flowing in, flowing out, or
// neither (full, holding at the limit, no battery).
function flowKind(state) {
  if (state === "charging") return "in"
  if (state === "discharging") return "out"
  return "idle"
}

function batteryIconForState(state, level, onBattery) {
  var chargingIcons = ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
  var defaultIcons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]

  if (state === "absent") return ""
  if (state === "full") return onBattery ? "󰁹" : "󰂅"
  // One plug glyph for "on AC, current not flowing": distinct from both the
  // charging ladder and the level glyphs, so holding at a charge limit is
  // visible from the bar alone.
  if (state === "plugged") return "󰚥"

  var index = level < 0 ? 0 : Math.max(0, Math.min(9, Math.floor(level / 10)))
  if (state === "charging") return chargingIcons[index]
  return defaultIcons[index]
}

// Colour for the bar glyph. Green while power flows in is the strongest
// signal: a charging pack is green even below the red threshold and even while
// Low Power Mode is active, so the user never mistakes a recovering battery for
// a critical one. Otherwise Low Power Mode is yellow, the low-battery red is
// next (inclusive, matching "20% or lower"), then the bar's own colour. `full`
// counts as charged, exactly as the reference widget treats it.
function iconColor(state, level, saverActive, redBelow, normalColor, greenColor, yellowColor, redColor) {
  var pct = number(level)
  if (state === "absent") return normalColor
  if (state === "charging" || state === "full") return greenColor
  if (saverActive === true) return yellowColor
  if (pct >= 0 && pct <= number(redBelow)) return redColor
  return normalColor
}

// True while the percentage should be punched through the fill. Apple drops
// the cut-out for charging, critical and power-saver states because a hole is
// unreadable over green/red/yellow; those states draw solid digits instead.
function knockoutText(state, level, saverActive, redBelow) {
  var pct = number(level)
  if (state === "charging" || state === "full" || state === "absent") return false
  if (saverActive === true) return false
  return pct > number(redBelow)
}

// ---- settings ranges ------------------------------------------------------
// One table for the values each setting may take. The manifest declares the
// same bounds for the plugin's settings dialog and the bar clamps to them, so a
// panel row can enumerate exactly what the schema allows instead of keeping its
// own shortlist that silently drifts from it.
var settingRanges = {
  iconSize: { min: 11, max: 18, step: 1, fallback: 13 },
  redThreshold: { min: 5, max: 50, step: 5, fallback: 20 },
  powerSaverThreshold: { min: 5, max: 95, step: 5, fallback: 50 }
}

function settingRange(key) {
  return settingRanges[key] || { min: 0, max: 0, step: 1, fallback: 0 }
}

function clampSetting(key, raw, fallback) {
  var range = settingRange(key)
  var n = parseInt(raw, 10)
  if (isNaN(n)) n = fallback === undefined ? range.fallback : fallback
  return Math.max(range.min, Math.min(range.max, n))
}

// Every value the range admits, ascending: the panel's cycle ring.
function rangeSteps(key) {
  var range = settingRange(key)
  var steps = []
  if (!(range.step > 0)) return [range.min]
  for (var v = range.min; v <= range.max; v += range.step) steps.push(v)
  return steps
}

function cycleSetting(key, current) {
  return nextStep(rangeSteps(key), current)
}

// Settings arrive as JSON values from the panel but as strings from
// `omarchy bar set`, so one parser has to read both or the two writes disagree.
function boolSetting(raw, fallback) {
  if (raw === true || raw === false) return raw
  if (raw === undefined || raw === null) return fallback
  var s = String(raw).trim().toLowerCase()
  if (s === "true" || s === "1" || s === "on" || s === "yes") return true
  if (s === "false" || s === "0" || s === "off" || s === "no") return false
  return fallback
}

// Low-battery threshold in percent, clamped to the range the schema declares.
function redThreshold(raw, fallback) {
  return clampSetting("redThreshold", raw, fallback)
}

// Body height of the bar glyph in logical pixels: below 11 the digits have no
// room, above 18 it stops looking like a status bar icon.
function iconHeight(raw, fallback) {
  return clampSetting("iconSize", raw, fallback)
}

// Next value in a ring, used by the panel's cycling controls.
function nextStep(steps, current) {
  var list = Array.isArray(steps) ? steps : []
  if (list.length === 0) return current
  var index = list.indexOf(Number(current))
  return list[(index + 1) % list.length]
}

// Percentage at which the power-saver profile should engage.
function powerSaverThreshold(raw, fallback) {
  return clampSetting("powerSaverThreshold", raw, fallback)
}

// Only escalate when the battery is actually the power source, and step back
// up a few points above the threshold so a level hovering at the boundary does
// not flap between profiles.
function wantPowerSaver(onBattery, level, threshold) {
  if (!onBattery || level < 0) return false
  return level <= threshold
}

function wantPowerSaverRelease(onBattery, level, threshold, hysteresis) {
  if (!onBattery) return true
  if (level < 0) return false
  return level > threshold + (hysteresis || 0)
}


// ---------------------------------------------------------------- numbers ---

// sysfs values arrive as strings (or undefined when a file is absent).
// -1 marks "not available" so callers can hide rows instead of printing NaN.
function number(value) {
  if (value === undefined || value === null || value === "") return -1
  var n = Number(value)
  return isFinite(n) ? n : -1
}

function trim(value) {
  return String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
}

// ----------------------------------------------------------------- energy ---

// energy_* attributes are µWh, charge_* attributes are µAh. The probe reports
// which family the hardware uses so the same formatter can print both.
function formatEnergy(microValue, unit) {
  var n = number(microValue)
  if (n < 0) return "—"
  if (unit === "Ah") return (n / 1000000).toFixed(2) + " Ah"
  return (n / 1000000).toFixed(2) + " Wh"
}

function formatWatts(microWatts) {
  var n = number(microWatts)
  if (n < 0) return "—"
  var w = n / 1000000
  return (w >= 10 ? w.toFixed(1) : w.toFixed(2)) + " W"
}

function formatAmps(microAmps) {
  var n = number(microAmps)
  if (n < 0) return "—"
  return (n / 1000000).toFixed(2) + " A"
}

function formatVolts(microVolts) {
  var n = number(microVolts)
  if (n < 0) return "—"
  return (n / 1000000).toFixed(2) + " V"
}

function formatCelsius(value) {
  var n = number(value)
  if (n < 0) return "—"
  return n.toFixed(1) + " °C"
}

function formatCount(value) {
  var n = number(value)
  if (n < 0) return "—"
  return String(Math.round(n))
}

// "2h 14m" / "48m" / "<1m" from a second count. Battery estimates, screen
// time and app time all round to the same clock; only their unknown cases
// differ, and those live in the two wrappers below.
function clockSpan(seconds) {
  var minutes = Math.round(number(seconds) / 60)
  if (minutes < 1) return "<1m"
  var hours = Math.floor(minutes / 60)
  var rest = minutes % 60
  if (hours === 0) return rest + "m"
  if (rest === 0) return hours + "h"
  return hours + "h " + rest + "m"
}

// "2h 14m" / "48m" / "" for an unknown estimate.
function formatDuration(seconds) {
  return number(seconds) > 0 ? clockSpan(seconds) : ""
}

// UPower's own estimate, as the sentence the panel prints under the level.
function timeRemainingLabel(state, toEmpty, toFull) {
  if (state === "charging") {
    var full = formatDuration(toFull)
    return full === "" ? "" : full + " to full"
  }
  if (state === "discharging") {
    var left = formatDuration(toEmpty)
    return left === "" ? "" : left + " left"
  }
  return ""
}

// "LGC 5B10W13931" — or an em dash when the firmware exposes neither.
function deviceName(manufacturer, model) {
  var parts = [trim(manufacturer), trim(model)].filter(function(part) { return part !== "" })
  return parts.length > 0 ? parts.join(" ") : "—"
}

// ----------------------------------------------------------------- health ---

// Percentage of design capacity the battery still holds. UPower rounds this to
// "capacity"; we compute it from the same raw sysfs values so the number always
// matches what the hardware reports.
function batteryHealth(full, design) {
  var f = number(full)
  var d = number(design)
  if (f <= 0 || d <= 0) return -1
  return (f / d) * 100
}

function healthGrade(pct) {
  var n = number(pct)
  if (n < 0) return ""
  if (n >= 90) return "Like new"
  if (n >= 80) return "Good"
  if (n >= 60) return "Moderate wear"
  return "Degraded"
}

function wear(microFull, microDesign) {
  var f = number(microFull)
  var d = number(microDesign)
  if (f < 0 || d < 0 || d === 0) return -1
  return Math.max(0, d - f)
}

// ---------------------------------------------------------- charge limit ---

// start 0 means "no lower bound" on thinkpad_acpi (kernel docs: 0 = threshold
// off), so it is shown as "off" rather than as a 0% start.
// Kept to a card-width value: the row it sits in is 280 px wide, so the long
// prose versions overflowed the label before they were ever read.
function limitModeLabel(start, end) {
  var e = number(end)
  if (e < 0) return "Not exposed"
  var s = number(start)
  if (s > 0 && s !== e) return s + "–" + e + "%"
  if (e >= 100) return "Up to 100%"
  return "Capped at " + e + "%"
}

// The controller node's basename: a full path is 30 characters of noise in a
// 280 px row, and "BAT0" is the part anyone recognises.
function pathBase(path) {
  var parts = String(path === undefined || path === null ? "" : path).split("/")
  var last = parts.length > 0 ? parts[parts.length - 1] : ""
  return last !== "" ? last : "—"
}

function limitStartLabel(start) {
  var s = number(start)
  if (s <= 0) return "off"
  return s + "%"
}

// ------------------------------------------------- connected devices ---
//
// scripts/juice-devices emits the raw system picture (UPower values, BlueZ
// properties, kernel power_supply attributes). Everything below only labels and
// orders that picture for the panel; no number is invented and every missing
// attribute stays missing instead of becoming a plausible-looking zero.

var deviceKindOrder = { battery: 0, headset: 1, headphone: 2, mouse: 3, keyboard: 4, touchpad: 5, "gaming-input": 6, phone: 7, ups: 8, receiver: 9 }

function kindLabel(kind) {
  var value = trim(kind)
  if (value === "battery") return "Built-in battery"
  if (value === "headset" || value === "headphone") return "Headset"
  if (value === "gaming-input") return "Gamepad"
  if (value === "touchpad") return "Touchpad"
  if (value === "mouse") return "Mouse"
  if (value === "keyboard") return "Keyboard"
  if (value === "phone") return "Phone"
  if (value === "ups") return "UPS"
  if (value === "receiver") return "Wireless receiver"
  return "Battery device"
}

function kindIcon(kind, bluetoothIcon) {
  var icon = trim(bluetoothIcon)
  if (icon === "audio-headset" || icon === "audio-headphones") return "󰋋"
  if (icon === "input-mouse") return "󰍽"
  if (icon === "input-keyboard") return "󰌌"
  if (icon === "input-gaming") return "󰊗"
  if (icon === "phone") return "󰏲"
  var value = trim(kind)
  if (value === "battery") return "󰂅"
  if (value === "headset" || value === "headphone") return "󰋋"
  if (value === "mouse") return "󰍽"
  if (value === "keyboard") return "󰌌"
  if (value === "touchpad") return "󰟸"
  if (value === "gaming-input") return "󰊗"
  if (value === "phone") return "󰏲"
  if (value === "ups") return "󰚥"
  return "󰂑"
}

// The bus a device sits on. UPower already knows the Bluetooth ones by their
// BlueZ object path; HID packs report a scope and a udev bus instead.
function connectionLabel(device) {
  if (!device) return ""
  var bt = device.bt || {}
  if (trim(bt.address) !== "") return "Bluetooth"
  var native = trim(device.native)
  if (trim(device.kind) === "battery" && native.indexOf("BAT") === 0) return "Built in"
  var sys = device.sys || {}
  if (trim(sys.bus) === "usb" || trim(sys.type) === "USB") return "USB"
  if (trim(sys.scope) === "Device") return "Wireless receiver"
  return "Connected"
}

function deviceSubtitle(device) {
  if (!device) return ""
  var connection = connectionLabel(device)
  var kind = kindLabel(device.kind)
  // "Built in · Built-in battery" says the same thing twice and overflows the
  // row; the pack's kind already carries its connection.
  return connection === "Built in" ? kind : connection + " · " + kind
}

// Level, or -1 when the system has not reported one. The probe already folds
// BlueZ's Battery1 into `level` for devices UPower cannot poll, so this only
// clamps what arrived.
function deviceLevel(device) {
  if (!device) return -1
  var level = number(device.level)
  if (level < 0) return -1
  return Math.max(0, Math.min(100, Math.round(level)))
}

// UPower's state words differ between battery and peripheral blocks; the sysfs
// status is the same vocabulary in the opposite direction.
function deviceState(device) {
  if (!device) return ""
  var state = trim(device.state)
  var status = trim((device.sys || {}).status)
  // UPower prints "pending-charge"; sysfs prints "Not charging". One lowercase
  // vocabulary keeps both spellings from falling through to "Connected".
  var raw = (state !== "" ? state : status).toLowerCase()
  if (raw === "charging") return "charging"
  if (raw === "discharging") return "discharging"
  if (raw === "fully-charged" || raw === "full") return "full"
  if (raw === "pending-charge") return "pending"
  if (raw === "not charging") return "idle"
  return ""
}

function deviceStateLabel(device) {
  var state = deviceState(device)
  if (state === "charging") return "Charging"
  if (state === "discharging") return "On battery"
  if (state === "full") return "Full"
  if (state === "pending") return "Holding at limit"
  if (state === "idle") return "Not charging"
  // No state reported is no state invented: the row is absent from the
  // drop-down rather than claiming the device is "Connected".
  return ""
}

// The one owner of how a level is written: the row header and the drop-down
// both print this string, so "Not reported" cannot drift between them.
function deviceLevelLabel(device) {
  var level = deviceLevel(device)
  return level >= 0 ? level + "%" : "Not reported"
}

// Apple's threshold colours, same ones the pack uses. Charging is green, low is
// red, the low-power yellow is a profile badge and has no per-device meaning.
function deviceLevelColor(device, normalColor, greenColor, redColor, redBelow) {
  var level = deviceLevel(device)
  var state = deviceState(device)
  if (state === "charging" || state === "full") return greenColor
  if (level >= 0 && level <= number(redBelow)) return redColor
  return normalColor
}

function sortDevices(list) {
  var rows = Array.isArray(list) ? list.slice() : []
  rows.sort(function(a, b) {
    var ka = deviceKindOrder[trim(a && a.kind)]
    var kb = deviceKindOrder[trim(b && b.kind)]
    if (ka === undefined) ka = 20
    if (kb === undefined) kb = 20
    if (ka !== kb) return ka - kb
    var na = trim(a && a.name)
    var nb = trim(b && b.name)
    return na < nb ? -1 : na > nb ? 1 : 0
  })
  return rows
}

// The probe's JSON contract is enforced here so the panel only ever assigns a
// validated list: a malformed or truncated dump returns null and the caller
// keeps the last good one on screen.
function parseDevices(text) {
  try {
    var list = JSON.parse(text)
    return Array.isArray(list) ? sortDevices(list) : null
  } catch (error) {
    return null
  }
}

// Same contract for the usage report: an object carrying a daily array, or
// null when the sampler has not written one yet.
function parseUsageReport(text) {
  try {
    var report = JSON.parse(text)
    return report && typeof report === "object" && Array.isArray(report.daily) ? report : null
  } catch (error) {
    return null
  }
}

function formatAge(seconds) {
  var value = number(seconds)
  if (value < 0) return "—"
  if (value < 5) return "just now"
  if (value < 60) return Math.round(value) + "s ago"
  if (value < 3600) return Math.round(value / 60) + "m ago"
  if (value < 86400) return Math.round(value / 3600) + "h ago"
  return Math.round(value / 86400) + "d ago"
}

function formatSignal(rssi) {
  var value = number(rssi)
  // -1 is the probe's "not reported" marker; a real reading is always negative.
  if (value === 0 || value === -1) return ""
  return value + " dBm"
}

// Bluetooth baseband device class: bits 12–8 are the major class, 7–2 the minor.
var bluetoothMajor = {
  0x01: "Computer", 0x02: "Phone", 0x03: "LAN access", 0x04: "Audio / video",
  0x05: "Peripheral", 0x06: "Imaging", 0x07: "Wearable", 0x08: "Toy", 0x09: "Health"
}
var bluetoothMinor = {
  0x01: "Wearable headset", 0x02: "Hands-free", 0x04: "Headset", 0x06: "Headphones",
  0x07: "Portable audio", 0x08: "Car audio"
}
var bluetoothPeripheralMinor = {
  0x01: "Keyboard", 0x02: "Pointing device", 0x03: "Combo keyboard / pointer", 0x05: "Digitizer"
}

function bluetoothClassLabel(classValue) {
  var raw = trim(classValue)
  if (raw === "") return ""
  var value = /^0x/i.test(raw) ? parseInt(raw, 16) : parseInt(raw, 10)
  if (!isFinite(value) || value <= 0) return ""
  var major = (value >> 8) & 0x1f
  var minor = (value >> 2) & 0x3f
  var name = bluetoothMajor[major] || ""
  var detail = major === 0x05 ? bluetoothPeripheralMinor[minor] : bluetoothMinor[minor]
  if (!detail) return name
  return name + " · " + detail
}

function formatEnergyWh(value) {
  var n = number(value)
  if (n < 0 || n === 0) return ""
  return n.toFixed(1) + " Wh"
}

// The dropdown's grouped body, written in display order: a group exists only
// when it has something to say, so a device that reports only a level shows one
// honest row rather than seven em dashes.
function deviceDetailGroups(device) {
  if (!device) return []
  var groups = []
  var open = null
  function add(title, label, value) {
    var text = trim(value)
    if (text === "") return
    if (!open || open.title !== title) {
      open = { title: title, rows: [] }
      groups.push(open)
    }
    open.rows.push({ label: label, value: text, last: false })
  }

  var warning = trim(device.warning)
  var bt = device.bt || {}
  var sys = device.sys || {}

  add("BATTERY", "Level", deviceLevelLabel(device))
  add("BATTERY", "State", deviceStateLabel(device))
  if (number(device.capacity) >= 0) add("BATTERY", "Health", number(device.capacity).toFixed(1) + "%")
  if (number(device.cycles) >= 0) add("BATTERY", "Cycle count", String(Math.round(number(device.cycles))))
  add("BATTERY", "Technology", trim(device.technology))
  if (number(device.temperature) > 0) add("BATTERY", "Temperature", number(device.temperature).toFixed(1) + " °C")
  if (warning !== "" && warning !== "none") add("BATTERY", "Warning level", warning)
  if (number(device.timeToEmpty) > 0) add("BATTERY", "Time to empty", formatDuration(number(device.timeToEmpty)))
  if (number(device.timeToFull) > 0) add("BATTERY", "Time to full", formatDuration(number(device.timeToFull)))
  add("BATTERY", "Rechargeable", device.rechargeable === true ? "Yes" : (device.rechargeable === false ? "No" : ""))
  add("BATTERY", "Reported", number(device.updatedAge) >= 0 ? formatAge(device.updatedAge) : "")

  add("ENERGY", "Energy", formatEnergyWh(device.energy))
  add("ENERGY", "Full charge", formatEnergyWh(device.energyFull))
  add("ENERGY", "Design capacity", formatEnergyWh(device.energyFullDesign))
  if (number(device.energyRate) > 0) add("ENERGY", "Reported rate", formatWatts(device.energyRate * 1000000))
  if (number(device.voltage) > 0) add("ENERGY", "Voltage", number(device.voltage).toFixed(2) + " V")

  add("CONNECTION", "Connection", connectionLabel(device))
  add("CONNECTION", "Kind", kindLabel(device.kind))
  add("CONNECTION", "Address", trim(bt.address))
  add("CONNECTION", "Bluetooth class", bluetoothClassLabel(bt.class))
  add("CONNECTION", "Signal", formatSignal(bt.rssi))
  add("CONNECTION", "Paired", bt.paired === true ? "Yes" : (bt.paired === false ? "No" : ""))
  add("CONNECTION", "Trusted", bt.trusted === true ? "Yes" : (bt.trusted === false ? "No" : ""))
  add("CONNECTION", "Modalias", trim(bt.modalias))
  add("CONNECTION", "USB bus", trim(sys.bus))

  add("DEVICE", "Vendor", trim(device.vendor))
  add("DEVICE", "Model", trim(device.model))
  add("DEVICE", "Serial", trim(device.serial))

  if (trim(device.native) !== "") add("SYSTEM", "UPower node", pathBase(device.native))
  add("SYSTEM", "sysfs", trim(sys.path))
  add("SYSTEM", "History", device.hasHistory === true ? "Recorded" : "")

  groups.forEach(function(entry) { entry.rows[entry.rows.length - 1].last = true })
  return groups
}

// ------------------------------------------------------ battery usage ---

// "47%" / "<1%" / "—" — one percent format for the card label and app rows.
function formatPercent(value) {
  var n = number(value)
  if (n < 0) return "—"
  if (n > 0 && n < 1) return "<1%"
  return Math.round(n) + "%"
}

var monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

// "2026-10-22" -> "22 Oct 2026", the date iOS prints under the live bar.
// Deliberately locale-free: the card's typography is fixed and a C-locale month
// abbreviation is what the reference shows.
function formatUsageDate(iso) {
  var value = trim(iso)
  if (value === "") return ""
  var parts = value.split("-")
  if (parts.length !== 3) return ""
  var year = parseInt(parts[0], 10)
  var month = parseInt(parts[1], 10)
  var day = parseInt(parts[2], 10)
  if (!isFinite(year) || !isFinite(month) || !isFinite(day) || month < 1 || month > 12) return ""
  return day + " " + monthNames[month - 1] + " " + year
}

// "2h 49m", "48m", "0m" — the Screen On/Off footer always prints a value.
function formatSpan(seconds) {
  var value = number(seconds)
  if (value < 0) return "—"
  return value > 0 ? clockSpan(value) : "0m"
}

// iOS' comparison sentence, built only from measured days. With fewer than two
// prior days there is nothing honest to compare against, so the card says when
// tracking started instead of implying a trend.
function usageSentence(report) {
  if (!report || !report.today || !report.comparison) return "Measuring battery usage…"
  var today = number(report.today.usedPct)
  var average = report.comparison.averageByNow
  var days = number(report.comparison.days)
  var clock = (report.now && report.now.clock) ? report.now.clock : ""
  if (average === null || average === undefined || days < 1) {
    return "Tracking battery usage from today — the week fills in as it runs"
  }
  var mean = number(average)
  if (mean <= 0) return "Tracking battery usage from today — the week fills in as it runs"
  var ratio = today / mean
  if (ratio >= 0.85 && ratio <= 1.15) return "You're using a similar amount of battery today as you usually do by " + clock
  if (ratio > 1.15) return "You're using more battery than usual by " + clock
  return "You're using less battery than usual by " + clock
}

// One day of the usage report, by its ISO date. A selected date that the latest
// report no longer contains (midnight rollover) resolves to null, so the card
// falls back to the live view instead of pinning a day that no longer exists.
function usageDay(report, date) {
  var key = trim(date)
  if (key === "" || !report || !Array.isArray(report.daily)) return null
  for (var i = 0; i < report.daily.length; i++) {
    if (String(report.daily[i].date || "") === key) return report.daily[i]
  }
  return null
}

// How many of a day's hourly level buckets actually hold an observation. A
// backfilled day can have holes where UPower had no point; a sampler day can
// have holes where the shell was not running. Neither is a zero reading.
function usageDayCoveredHours(day) {
  var hours = day && Array.isArray(day.hours) ? day.hours : []
  var covered = 0
  for (var i = 0; i < hours.length; i++) {
    var level = hours[i] ? hours[i].level : null
    if (level !== null && level !== undefined) covered++
  }
  return covered
}

// A past day whose twenty-four buckets are not all observed is a partial
// reading: the percentage is what was measured, not a whole-day total. Today
// is excluded because it is still being written.
function usageDayIsPartial(day) {
  if (!day || day.measured !== true || day.today === true) return false
  var hours = Array.isArray(day.hours) ? day.hours : []
  if (hours.length === 0) return false
  var covered = usageDayCoveredHours(day)
  return covered > 0 && covered < hours.length
}

// The sentence a past day shows where the live comparison sits. A day the meter
// never saw says so; it never prints 0% as though the pack had been idle. A
// day with holes says how much of it was observed, so a partial percentage is
// never read as a whole-day total.
function usageDaySentence(day) {
  if (!day || day.measured !== true) return "No measurements were recorded for this day"
  var covered = usageDayCoveredHours(day)
  if (usageDayIsPartial(day)) {
    var unit = covered === 1 ? " hour" : " hours"
    var verb = covered === 1 ? " was " : " were "
    var pronoun = covered === 1 ? "it" : "them"
    if (day.used === null || day.used === undefined)
      return "Only " + covered + unit + " of this day" + verb + "measured, so battery use could not be totalled"
    var partialUsed = number(day.used)
    if (partialUsed <= 0)
      return "Only " + covered + unit + " of this day" + verb + "measured, and no battery discharge was recorded in " + pronoun
    return "Only " + covered + unit + " of this day" + verb + "measured — you used " + formatPercent(partialUsed) + " of the battery in " + pronoun
  }
  if (day.used === null || day.used === undefined) return "Battery use was recorded for this day"
  var used = number(day.used)
  if (used <= 0) return "No battery discharge was recorded that day"
  return "You used " + formatPercent(used) + " of the battery that day"
}

// The percentage the usage card prints — for the selected day, or for today
// when no day is selected. A day the meter never saw is an em dash, never 0%,
// and the section header summary and the card itself both read this one
// function so the two can never disagree.
function usagePercentLabel(day, today) {
  if (day) {
    if (day.measured !== true) return "—"
    if (day.used === null || day.used === undefined) return "—"
    return formatPercent(day.used)
  }
  if (!today || today.usedPct === null || today.usedPct === undefined) return "—"
  return formatPercent(today.usedPct)
}

// App attribution only exists for days the sampler itself ran. A day backfilled
// from UPower's history carries an empty list, and this note stands in for it.
function usageDayAppsNote(day) {
  if (!day) return "No app activity was recorded for this day"
  if (Array.isArray(day.apps) && day.apps.length > 0) return ""
  return "App breakdown wasn't recorded for this day"
}

// "21 Oct" — a selected day's short date, for a section header summary.
function usageShortDate(iso) {
  return formatUsageDate(iso).replace(/ \d{4}$/, "")
}

// The daily chart's top gridline: the screenshot's scale tops out at 200% of a
// full pack because charging during the day legitimately exceeds one charge.
function usageTopScale(daily) {
  var top = 100
  var list = Array.isArray(daily) ? daily : []
  for (var i = 0; i < list.length; i++) {
    var used = number(list[i].used)
    if (used > top) top = used
  }
  if (top <= 100) return 100
  if (top <= 200) return 200
  return 300
}

function usageLevelColor(level, greenColor, yellowColor, redColor) {
  var value = number(level)
  if (value < 0) return redColor
  if (value >= 50) return greenColor
  if (value >= 20) return yellowColor
  return redColor
}

function appLabel(name) {
  var value = trim(name)
  if (value === "") return "Unknown"
  value = trim(value.replace(/-Default$/, "").replace(/[-_]+/g, " ").replace(/\s+/g, " "))
  return value.charAt(0).toUpperCase() + value.slice(1)
}

// Hour axis labels in the iOS shape: midnight, 6 AM, noon, 6 PM.
function hourLabel(hour) {
  var value = number(hour)
  if (value === 0) return "12A"
  if (value === 6) return "6"
  if (value === 12) return "12P"
  if (value === 18) return "6"
  return ""
}

if (typeof module !== "undefined") {
  module.exports = {
    clampIndex: clampIndex,
    selectProfileIndex: selectProfileIndex,
    parseKeyValue: parseKeyValue,
    parseProfiles: parseProfiles,
    profileIcon: profileIcon,
    sessionActions: sessionActions,
    sessionActionById: sessionActionById,
    sessionActionForKey: sessionActionForKey,
    sessionActionAvailable: sessionActionAvailable,
    parseSessionProbe: parseSessionProbe,
    batteryFraction: batteryFraction,
    chargeThresholdActive: chargeThresholdActive,
    batteryIcon: batteryIcon,
    batteryLevel: batteryLevel,
    batteryState: batteryState,
    stateLabel: stateLabel,
    stateDetailLabel: stateDetailLabel,
    stateExplanation: stateExplanation,
    flowKind: flowKind,
    batteryIconForState: batteryIconForState,
    iconColor: iconColor,
    knockoutText: knockoutText,
    redThreshold: redThreshold,
    iconHeight: iconHeight,
    settingRange: settingRange,
    rangeSteps: rangeSteps,
    cycleSetting: cycleSetting,
    boolSetting: boolSetting,
    nextStep: nextStep,
    powerSaverThreshold: powerSaverThreshold,
    wantPowerSaver: wantPowerSaver,
    wantPowerSaverRelease: wantPowerSaverRelease,
    number: number,
    trim: trim,
    formatEnergy: formatEnergy,
    formatWatts: formatWatts,
    formatAmps: formatAmps,
    formatVolts: formatVolts,
    formatCelsius: formatCelsius,
    formatCount: formatCount,
    formatDuration: formatDuration,
    timeRemainingLabel: timeRemainingLabel,
    deviceName: deviceName,
    batteryHealth: batteryHealth,
    healthGrade: healthGrade,
    wear: wear,
    limitModeLabel: limitModeLabel,
    limitStartLabel: limitStartLabel,
    pathBase: pathBase,
    kindLabel: kindLabel,
    kindIcon: kindIcon,
    connectionLabel: connectionLabel,
    deviceSubtitle: deviceSubtitle,
    deviceLevel: deviceLevel,
    deviceLevelLabel: deviceLevelLabel,
    deviceState: deviceState,
    deviceStateLabel: deviceStateLabel,
    deviceLevelColor: deviceLevelColor,
    sortDevices: sortDevices,
    formatAge: formatAge,
    formatSignal: formatSignal,
    bluetoothClassLabel: bluetoothClassLabel,
    formatEnergyWh: formatEnergyWh,
    deviceDetailGroups: deviceDetailGroups,
    formatPercent: formatPercent,
    formatUsageDate: formatUsageDate,
    formatSpan: formatSpan,
    parseDevices: parseDevices,
    parseUsageReport: parseUsageReport,
    usageSentence: usageSentence,
    usageDay: usageDay,
    usageDaySentence: usageDaySentence,
    usageDayCoveredHours: usageDayCoveredHours,
    usageDayIsPartial: usageDayIsPartial,
    usageDayAppsNote: usageDayAppsNote,
    usageShortDate: usageShortDate,
    usagePercentLabel: usagePercentLabel,
    usageTopScale: usageTopScale,
    usageLevelColor: usageLevelColor,
    appLabel: appLabel,
    hourLabel: hourLabel
  }
}
