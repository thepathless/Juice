// Model helpers for OmaBattery.
//
// The first half is the stock omarchy.power Model.js (profile picking, icon
// selection, threshold detection) kept byte-for-byte in behaviour so the panel
// looks and behaves exactly like the built-in one. The second half adds the
// formatting used by the charge-target controls and the battery health section.

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

function chargeThresholdActive(device, onBattery, states) {
  var d = device || {}
  var s = states || {}
  if (!(d && d.isPresent && !onBattery)) return false

  var fraction = batteryFraction(d)
  if (d.state === s.Discharging) return false
  if (d.state === s.PendingCharge) return true
  if (d.state === s.FullyCharged && fraction < 0.99) return true
  if (d.state !== s.Charging || fraction >= 0.99) return false

  return Number(d.changeRate || 0) <= 0.2 || Number(d.timeToFull || 0) >= 8 * 60 * 60
}

function batteryIcon(device, onBattery, states, sysfsStatus) {
  return batteryIconForState(batteryState(device, onBattery, states, sysfsStatus), batteryLevel(device), onBattery)
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
// but not charging (holding at a charge threshold, or waiting to top up), and
// "discharging" when the battery is the source. "absent" on desktops.
function batteryState(device, onBattery, states, sysfsStatus) {
  var d = device || {}
  var s = states || {}
  if (!d.isPresent) return "absent"

  var level = batteryLevel(d)

  // The kernel attribute flips the instant the embedded controller changes what
  // it is doing, while UPower only learns about it on its next poll. Prefer the
  // sysfs status whenever the probe has one, so the bar cannot show "charging"
  // for half a minute after the EC stopped.
  var status = trim(sysfsStatus).toLowerCase()
  if (status === "charging") return "charging"
  if (status === "full" || status === "fully charged") return "full"
  if (status === "not charging") return level >= 100 ? "full" : "plugged"
  if (status === "discharging") return "discharging"

  if (!onBattery) {
    if (d.state === s.Charging) return "charging"
    if (d.state === s.FullyCharged) return "full"
    if (level >= 100) return "full"
    return "plugged"
  }
  if (d.state === s.FullyCharged) return "full"
  return "discharging"
}

function stateLabel(state, level) {
  if (state === "charging") return "Charging"
  if (state === "full") return "Fully charged"
  if (state === "plugged") return "Plugged in, not charging"
  if (state === "discharging") return level >= 0 ? "On battery, " + level + "%" : "On battery"
  return ""
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

// Two-step escalation for the bar: the theme's yellow from `low` down to the
// critical band, its red strictly below `critical`, and the normal bar colour
// otherwise. `critical` is exclusive so 25 with low=50/critical=25 is still
// yellow and the red band begins at 24.
function levelColor(level, low, critical, lowColor, criticalColor, normalColor) {
  if (level < 0) return normalColor
  if (level < critical) return criticalColor
  if (level <= low) return lowColor
  return normalColor
}

// Percentage at which the power-saver profile should engage, clamped to a
// range where it is meaningful, falling back to 50.
function powerSaverThreshold(raw, fallback) {
  var n = parseInt(raw, 10)
  if (isNaN(n)) n = fallback
  return Math.max(5, Math.min(95, n))
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

function modeLabel(device, onBattery, states) {
  var d = device || {}
  if (!d.isPresent) return ""

  var percentage = d.isPresent ? d.percentage : 0
  if (chargeThresholdActive(d, onBattery, states)) return "Threshold"
  if (onBattery) return "On battery"
  if (!onBattery && percentage >= 1) return "Fully charged"
  return "Charging"
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
function limitModeLabel(start, end) {
  var e = number(end)
  if (e < 0) return "Charge threshold not exposed"
  var s = number(start)
  if (s > 0 && s !== e) return "Charging between " + s + "% and " + e + "%"
  if (e >= 100) return "Full charge, stops at 100%"
  return "Charging capped at " + e + "%"
}

function limitStartLabel(start) {
  var s = number(start)
  if (s <= 0) return "off"
  return s + "%"
}

// Live sentence under the buttons: always built from the last probe, never from
// what we asked the hardware to do.
function chargeStateLabel(status, end, onAc) {
  var state = trim(status)
  var e = number(end)
  var limit = e >= 0 ? e + "%" : "unknown"
  if (state === "") return onAc ? "On AC · limit " + limit : "On battery · limit " + limit
  if (state === "Not charging") return "Holding at the " + limit + " limit (EC bypasses to AC)"
  if (state === "Full" || state === "Fully charged") return "Fully charged · limit " + limit
  return state.charAt(0).toUpperCase() + state.slice(1) + " · limit " + limit
}

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
    batteryIconForState: batteryIconForState,
    levelColor: levelColor,
    powerSaverThreshold: powerSaverThreshold,
    wantPowerSaver: wantPowerSaver,
    wantPowerSaverRelease: wantPowerSaverRelease,
    modeLabel: modeLabel,
    number: number,
    trim: trim,
    formatEnergy: formatEnergy,
    formatWatts: formatWatts,
    formatAmps: formatAmps,
    formatVolts: formatVolts,
    formatCelsius: formatCelsius,
    formatCount: formatCount,
    currentFromPower: currentFromPower,
    batteryHealth: batteryHealth,
    healthFraction: healthFraction,
    healthGrade: healthGrade,
    wear: wear,
    limitModeLabel: limitModeLabel,
    limitStartLabel: limitStartLabel,
    chargeStateLabel: chargeStateLabel
  }
}
