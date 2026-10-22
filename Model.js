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

// Colour for the bar glyph, in Apple's precedence: Low Power Mode (yellow) is
// a mode indicator and outranks everything, then the low-battery red, then
// green while power flows in, then the bar's own colour. The threshold is
// inclusive, matching "20% or lower". `full` counts as charged, exactly as
// the reference widget treats it, so a topped-up battery on AC is green.
function iconColor(state, level, saverActive, redBelow, normalColor, greenColor, yellowColor, redColor) {
  var pct = number(level)
  if (state === "absent") return normalColor
  if (saverActive === true) return yellowColor
  if (pct >= 0 && pct <= number(redBelow)) return redColor
  if (state === "charging" || state === "full") return greenColor
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

// "2h 14m" / "48m" / "" for an unknown estimate.
function formatDuration(seconds) {
  var s = number(seconds)
  if (!(s > 0)) return ""
  var minutes = Math.round(s / 60)
  if (minutes < 1) return "<1m"
  var hours = Math.floor(minutes / 60)
  var rest = minutes % 60
  if (hours === 0) return rest + "m"
  if (rest === 0) return hours + "h"
  return hours + "h " + rest + "m"
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

// Current is not always exposed directly; power and voltage usually are.
function currentFromPower(microWatts, microVolts) {
  var p = number(microWatts)
  var v = number(microVolts)
  if (p < 0 || v <= 0) return -1
  return (p / v) * 1000000
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

function healthFraction(full, design) {
  var pct = batteryHealth(full, design)
  if (pct < 0) return 0
  return Math.max(0, Math.min(1, pct / 100))
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

// Live sentence under the buttons: always built from the last probe, never from
// what we asked the hardware to do.

if (typeof module !== "undefined") {
  module.exports = {
    clampIndex: clampIndex,
    selectProfileIndex: selectProfileIndex,
    parseKeyValue: parseKeyValue,
    parseProfiles: parseProfiles,
    profileIcon: profileIcon,
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
    currentFromPower: currentFromPower,
    batteryHealth: batteryHealth,
    healthFraction: healthFraction,
    healthGrade: healthGrade,
    wear: wear,
    limitModeLabel: limitModeLabel,
    limitStartLabel: limitStartLabel,
    pathBase: pathBase
  }
}
