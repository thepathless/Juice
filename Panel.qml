import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Juice — battery bar widget and panel.
//
// Built on Omarchy's omarchy.power panel: the bar button, keyboard handling,
// theming hooks (root.bar.foreground / root.bar.fontFamily / Commons.Color) and
// the omarchy-* commands it shells out to are kept as-is. The panel opens as a
// hero card — level, state, time left and live wattage — followed by the
// sections that are worth having permanently in view:
//
//   1. CHARGE TARGET — writes the kernel charge thresholds (80% / 100%) through
//      scripts/juice-set-limit and always reports what the hardware actually
//      holds, never what we asked for.
//   2. POWER PROFILE — the power-profiles picker.
//   3. SESSION — hold Lock / Sleep / Hibernate / Reboot / Shut down for three
//      seconds. Plain letters only while this panel has focus, so Omarchy's
//      own Super shortcuts are untouched.
//
// BATTERY DETAIL, CONNECTED DEVICES, BATTERY USAGE, USAGE BY APP and OPTIONS
// disclose in place; every open starts with those five closed and the usage
// card on today. OPTIONS stays closed so the settings never crowd the live
// controls.
//
// The card scrolls when its permanent sections make it taller than the space
// under the bar.
Panel {
  id: root
  moduleName: "thepathless.juice"
  ipcTarget: "thepathless.juice"
  // manageIpc: false so this panel can own the single IpcHandler the target
  // permits — needed for the charge-target and togglePercentage methods below.
  manageIpc: false
  property var batteryInfo: ({})
  property var profiles: []
  property string activeProfile: ""
  property int profileIndex: 0
  property bool cursorActive: false
  readonly property bool showPercentage: Model.boolSetting(setting("showPercentage", false), false)
  readonly property bool batteryPresent: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent)
  }

  // ---- Juice: sysfs telemetry, charge targets ------------------------------
  //
  // statsInfo holds the last successful probe (see scripts/juice-stats).
  // It is the only source for the threshold and health numbers, so the panel
  // can never show an assumed value.
  property var statsInfo: ({})
  property bool limitApplying: false
  property string limitFeedback: ""
  property bool limitFeedbackError: false
  property int verifyAttempts: 0

  // ---- Juice: bar presentation and options --------------------------------
  //
  // The bar glyph and its colour are pure functions of the UPower device (see
  // Model.batteryState), bound rather than polled, so the icon changes at the
  // same moment the compositor sees the state change.
  //
  // Apple's system colours, dark appearance values. They are fixed rather than
  // read from colors.toml because the theme's red/yellow/green are often
  // grayscale (this one is), which made every "warning" colour the same grey.
  readonly property color appleGreen: "#30D158"
  readonly property color appleYellow: "#FFD60A"
  readonly property color appleRed: "#FF453A"
  readonly property color appleBlue: "#0A84FF"
  property bool autoSaverEngaged: false
  // Profile the user was running before the saver was engaged, so releasing
  // restores exactly that instead of guessing from stored preferences.
  property string saverRestoreProfile: "balanced"
  // Set by the power-supply uevent monitor; coalesced into a single probe.
  property bool statsDirty: false

  readonly property int batteryLevel: Model.batteryLevel(UPower.displayDevice)
  readonly property string batteryState: Model.batteryState(UPower.displayDevice, root.onBattery, root.chargeLimitEnd)
  readonly property string batteryStateText: Model.stateLabel(root.batteryState, root.batteryLevel)
  // Apple's rules, with charging first: green while current flows in even
  // below the low threshold or in power-saver, yellow while Low Power Mode
  // (power-saver) is the active profile, red under the low threshold, theme
  // foreground the rest of the time. The threshold is user-tunable.
  readonly property int redBatteryThreshold: Model.redThreshold(setting("redThreshold", 20), 20)
  readonly property bool powerSaverActive: PowerProfiles.profile === PowerProfile.PowerSaver
  readonly property color barIconColor: Model.iconColor(
    root.batteryState, root.batteryLevel, root.powerSaverActive, root.redBatteryThreshold,
    root.bar ? root.bar.barForeground : Commons.Color.foreground,
    root.appleGreen, root.appleYellow, root.appleRed)
  // Body height in logical pixels; every other glyph dimension comes from
  // BatteryIcon's own Apple-derived ratios, so the slot never restates them.
  readonly property int barIconHeight: Model.iconHeight(setting("iconSize", 13), 13)
  // iOS 27's capsule is opt-in: it is a different body, not a tweak, so the
  // bordered glyph stays the default.
  readonly property bool borderlessStyle: Model.boolSetting(setting("borderless", false), false)
  readonly property real barGlyphHeight: Style.spaceReal(root.barIconHeight)
  readonly property real barGlyphWidth: barGlyph.implicitWidth
  // The hole in the fill is painted in the surface the bar puts behind the
  // battery. A plugin only sees `bar.background` (the theme's base colour,
  // and always opaque) plus `bar.transparent`; a glassy bar exposes no flag,
  // and its 35 % tint of that same colour stays within a few levels of it on
  // this palette, so the base colour is the closest the facade offers. A
  // clear bar has no surface to punch out of at all, and the digits take the
  // theme background rather than painting the fill away.
  readonly property color barCutoutColor: root.bar && root.bar.transparent !== true
    ? root.bar.background
    : Commons.Color.background
  readonly property string timeRemainingText: Model.timeRemainingLabel(
    root.batteryState, UPower.displayDevice ? UPower.displayDevice.timeToEmpty : 0,
    UPower.displayDevice ? UPower.displayDevice.timeToFull : 0)
  readonly property bool autoPowerSaver: Model.boolSetting(setting("autoPowerSaver", true), true)
  readonly property int powerSaverThreshold: Model.powerSaverThreshold(setting("powerSaverThreshold", 50), 50)

  readonly property string statsScript: decodeURIComponent(
    Qt.resolvedUrl("scripts/juice-stats").toString().replace(/^file:\/\//, ""))
  readonly property string limitScript: decodeURIComponent(
    Qt.resolvedUrl("scripts/juice-set-limit").toString().replace(/^file:\/\//, ""))
  readonly property string devicesScript: decodeURIComponent(
    Qt.resolvedUrl("scripts/juice-devices").toString().replace(/^file:\/\//, ""))
  readonly property string usageScript: decodeURIComponent(
    Qt.resolvedUrl("scripts/juice-usage").toString().replace(/^file:\/\//, ""))

  // ---- Juice: connected devices and battery usage ------------------------
  //
  // Every row below is a device the system itself reports a battery for, and
  // every usage number is metered from sysfs, Hyprland and UPower history by
  // scripts/juice-usage. The panel only formats what those two probes found.
  property var deviceList: []
  property string expandedDevice: ""
  property var usageInfo: ({})
  property bool usageUnavailable: false

  // ---- Juice: session power actions ---------------------------------------
  //
  // The five actions are plain-key holds inside the focused panel. No
  // compositor binding is involved, so Super+L and Super+S keep their Omarchy
  // meanings everywhere; only HoldKeys.qml sees these keys.
  property var sessionAvailable: ({ suspend: true, hibernate: false })
  readonly property var sessionActions: Model.sessionActions(root.sessionAvailable)
  readonly property int sessionHoldMs: 3000
  property string sessionHoldId: ""
  property real sessionHoldProgress: 0
  readonly property var sessionHoldAction: Model.sessionActionById(root.sessionHoldId)

  // ---- Juice: section disclosure -------------------------------------------
  //
  // The data-heavy sections and OPTIONS disclose. CHARGE TARGET, POWER
  // PROFILE and SESSION stay permanent, so the live controls are always
  // visible and only the secondary material folds away.
  property bool detailOpen: false
  property bool devicesOpen: false
  property bool usageOpen: false
  property bool appsOpen: false
  property bool optionsOpen: false

  // The headers summarise a closed section, so a glance still answers the
  // question without opening anything. Each is built from the same live state
  // the body renders, never from a cached copy.
  readonly property string activeProfileLabel: root.activeProfile === "" ? ""
    : (root.activeProfile === "power-saver" ? "Saver"
    : (root.activeProfile === "performance" ? "Performance" : "Balanced"))
  readonly property string usageSummary: {
    // A closed section still says which day is open, so the panel never hides
    // that the card below is showing Tuesday rather than today.
    if (root.showingPastDay) {
      var day = root.selectedUsageDay
      return Model.usageShortDate(day.date) + " · " + Model.usagePercentLabel(day, null)
    }
    var today = root.usageInfo.today
    if (!today || today.usedPct === undefined) return ""
    // Same formatter the card's own heading uses, so summary and body agree.
    return Model.usagePercentLabel(null, today) + " today"
  }

  function collapseSections() {
    root.detailOpen = false
    root.devicesOpen = false
    root.usageOpen = false
    root.appsOpen = false
    root.optionsOpen = false
    // A device drop-down left open last time would spring open under an
    // otherwise minimal panel; every open starts from one closed row.
    root.expandedDevice = ""
    // The usage card always opens on today, never on the day last inspected.
    root.usageDay = ""
  }

  readonly property var usageApps: Array.isArray(root.usageInfo.apps) ? root.usageInfo.apps.slice(0, 8) : []
  readonly property bool usageReady: Array.isArray(root.usageInfo.daily) && root.usageInfo.daily.length > 0

  // ---- Juice: which usage day is open --------------------------------------
  //
  // "" is the live/today view. Tapping a bar in the card sets an ISO date; the
  // card then draws that day's own curve and totals, and the app section below
  // shows that day's rows or says plainly that none were recorded.
  property string usageDay: ""
  readonly property var selectedUsageDay: Model.usageDay(root.usageInfo, root.usageDay)
  readonly property bool showingPastDay: root.usageDay !== ""
    && root.selectedUsageDay !== null && !root.selectedUsageDay.today
  readonly property var usageAppList: root.showingPastDay
    ? (Array.isArray(root.selectedUsageDay.apps) ? root.selectedUsageDay.apps.slice(0, 8) : [])
    : root.usageApps
  readonly property string usageAppsNote: root.showingPastDay
    ? Model.usageDayAppsNote(root.selectedUsageDay)
    : (root.usageInfo.appsNote || "")

  function selectUsageDay(date) {
    root.usageDay = (date === undefined || date === null) ? "" : String(date)
  }

  function refreshDevices() {
    if (devicesProc.running) return
    devicesProc.running = true
  }

  function refreshUsage() {
    if (usageProc.running) return
    usageProc.running = true
  }


  readonly property bool statsLoaded: statsInfo.capacity !== undefined
  readonly property int chargeLimitEnd: {
    var n = parseInt(root.statsInfo.threshold_end, 10)
    return isNaN(n) ? -1 : n
  }
  readonly property bool chargeLimitSupported: root.chargeLimitEnd >= 0
  readonly property bool acOnline: root.statsInfo.ac_online === "1"
  readonly property string energyUnit: root.statsInfo.unit || "Wh"
  readonly property real healthPercent: Model.batteryHealth(root.statsInfo.energy_full, root.statsInfo.energy_full_design)
  readonly property string healthGrade: Model.healthGrade(root.healthPercent)
  // The subtitle under the charge bar, built from the same derived state and
  // limit the glyph uses, so the sentence can never contradict the icon.
  readonly property string chargeStateText: Model.stateDetailLabel(
    root.batteryState, root.batteryLevel, root.chargeLimitEnd)
  // The sentence the card has no room for; the bar tooltip does.
  readonly property string stateExplanation: Model.stateExplanation(
    root.batteryState, root.chargeLimitEnd)

  function selectProfileByDelta(delta) {
    profileIndex = Model.selectProfileIndex(profileIndex, delta, profiles)
  }

  function activateSelectedProfile() {
    if (profileIndex < 0 || profileIndex >= profiles.length) return
    setProfile(profiles[profileIndex])
  }

  function batteryIcon() {
    var device = UPower.displayDevice
    return Model.batteryIcon(device, root.onBattery, root.chargeLimitEnd)
  }

  function profileIcon(name) {
    return Model.profileIcon(name)
  }

  // Raw input only: the pack is the power source. Every state-dependent
  // boolean below is read off `batteryState`, so the Model stays the single
  // owner of charging / plugged / full / discharging.
  readonly property bool onBattery: UPower.onBattery
  readonly property bool charging: root.batteryState === "charging"
  readonly property string flowKind: Model.flowKind(root.batteryState)

  // 0..1 charge level, used by the visual progress bar.
  readonly property real batteryFraction: {
    var d = UPower.displayDevice
    return Model.batteryFraction(d)
  }

  // Cute agent-flavored phrases shown in the hero status line, rotated on a
  // timer so the panel feels alive when current is flowing (either direction).
  readonly property var chargingPhrases: [
    "Pumping power",
    "Injecting electrons",
    "Pouring juice",
    "Amassing watts",
    "Hoarding joules",
    "Sucking volts",
    "Topping reserves",
    "Soaking amps",
    "Inhaling kilowatts"
  ]
  readonly property var onBatteryPhrases: [
    "Slurping power",
    "Spending joules",
    "Draining watts",
    "Burning electrons",
    "Sipping juice",
    "Spending coulombs",
    "Bleeding amps",
    "Guzzling volts",
    "Munching reserves"
  ]
  property int phraseIndex: 0

  // Whichever list is "active" given the current power state.
  readonly property var activePhrases: {
    if (root.flowKind === "in") return chargingPhrases
    if (root.flowKind === "out") return onBatteryPhrases
    return []
  }
  readonly property bool rotatingPhrases: activePhrases.length > 0

  readonly property string heroStatusText: rotatingPhrases
    ? activePhrases[phraseIndex % activePhrases.length]
    : Model.stateLabel(root.batteryState, root.batteryLevel)

  function refresh() {
    if (!batteryPresent) return

    if (!batteryProc.running) batteryProc.running = true
    if (!profilesProc.running) profilesProc.running = true
  }

  function refreshStats() {
    if (!batteryPresent) return
    if (!statsProc.running) statsProc.running = true
  }

  function updateBattery(raw) {
    var next = Model.parseKeyValue(raw)
    // Keep last known good data if a refresh briefly returns nothing — happens
    // around AC plug/unplug events. Avoids the section collapsing mid-transition.
    if (Object.keys(next).length === 0) return
    batteryInfo = next
  }

  function updateProfiles(raw) {
    var parsed = Model.parseProfiles(raw, profileIndex)
    // Same guard as battery: preserve the last known profile list across
    // transient empty payloads so the buttons don't blink out.
    if (parsed.profiles.length === 0) return
    profiles = parsed.profiles
    activeProfile = parsed.activeProfile
    profileIndex = parsed.profileIndex
    if (opened && !cursorActive) {
      var idx = profiles.indexOf(activeProfile)
      if (idx >= 0) profileIndex = idx
    }
  }

  function setProfile(profile) {
    if (!profile || actionProc.running) return
    actionProc.command = ["omarchy-powerprofiles-set", root.onBattery ? "battery" : "ac", profile]
    actionProc.running = true
  }

  // Automation changes the live profile only. `omarchy-powerprofiles-set` is
  // Omarchy's "remember this per power source" command, so using it here would
  // overwrite the user's own pick the first time the saver engaged.
  function setRuntimeProfile(profile) {
    if (!profile || actionProc.running) return
    actionProc.command = ["powerprofilesctl", "set", profile]
    actionProc.running = true
  }

  function togglePercentage() {
    root.updateSetting("showPercentage", !root.showPercentage)
  }

  // Numbers commit on Return and hand the keyboard back to the panel, so
  // Escape, the arrow-key profile picker and the session holds keep working
  // afterwards. HoldKeys is the layer that owns plain-letter holds.
  function releaseFieldFocus() {
    if (holdKeys) holdKeys.forceActiveFocus()
  }

  // ---- Juice: session hold -------------------------------------------------

  function refreshSession() {
    if (sessionProbe.running) return
    sessionProbe.running = true
  }

  function beginSessionHold(id) {
    var action = Model.sessionActionById(String(id === undefined || id === null ? "" : id))
    if (!action || !Model.sessionActionAvailable(action, root.sessionAvailable)) return
    if (root.sessionHoldId !== "") root.cancelSessionHold()
    root.sessionHoldId = action.id
    root.sessionHoldProgress = 0
    sessionHoldFill.restart()
    sessionHoldTimer.restart()
  }

  // The id is optional: keyboard focus loss cancels whatever is active, while
  // a tile release must only cancel its own hold.
  function cancelSessionHold(id) {
    if (id !== undefined && id !== null && String(id) !== root.sessionHoldId) return
    sessionHoldTimer.stop()
    sessionHoldFill.stop()
    root.sessionHoldProgress = 0
    root.sessionHoldId = ""
  }

  function completeSessionHold() {
    var action = root.sessionHoldAction
    root.cancelSessionHold()
    if (!action) return
    root.close()
    Quickshell.execDetached(["bash", "-lc", action.command])
  }

  // A short H/L tap goes through the same profile cursor the arrow keys use.
  function moveProfileHorizontal(direction) {
    if (direction === 0) return
    if (!root.cursorActive) { root.cursorActive = true; return }
    root.selectProfileByDelta(direction)
  }

  // Bar-widget options live in this widget's inline shell.json entry — the same
  // place Omarchy stores every other bar setting. Writing the whole entry back
  // through the shell is what makes the choice survive a restart.
  function updateSetting(key, value) {
    var next = Object.assign({}, root.settings)
    next[key] = value
    root.settings = next
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, next)
  }

  // ---- Juice: power-saver automation --------------------------------------

  // Engages power-saver when the battery drops to the configured level, and
  // releases it a few points above that so the profile does not flap at the
  // boundary. The OPTIONS switch disables both directions and releases a
  // profile the automation already engaged. Called from UPower bindings, never
  // from a timer.
  function evaluatePowerSaver() {
    // Turning automation off also releases a profile it engaged earlier, so
    // the switch cannot leave the machine stranded in power-saver.
    if (!root.autoPowerSaver) {
      if (root.autoSaverEngaged) {
        root.autoSaverEngaged = false
        root.setRuntimeProfile(root.saverRestoreProfile)
      }
      return
    }

    var device = UPower.displayDevice
    if (!device || !device.isPresent) return

    var level = Model.batteryLevel(device)
    var onBattery = UPower.onBattery

    if (!root.autoSaverEngaged) {
      if (Model.wantPowerSaver(onBattery, level, root.powerSaverThreshold)) {
        root.saverRestoreProfile = root.activeProfile || "balanced"
        root.autoSaverEngaged = true
        root.setRuntimeProfile("power-saver")
      }
      return
    }

    if (Model.wantPowerSaverRelease(onBattery, level, root.powerSaverThreshold, 3)) {
      root.autoSaverEngaged = false
      root.setRuntimeProfile(root.saverRestoreProfile)
    }
  }

  onAutoPowerSaverChanged: root.evaluatePowerSaver()
  onPowerSaverThresholdChanged: root.evaluatePowerSaver()

  // ---- Juice: charge targets ----------------------------------------------

  function notify(headline, body) {
    Quickshell.execDetached(["omarchy-notification-send", "-g", "󰂅", headline, body])
  }

  function applyChargeTarget(pct) {
    // Deliberately not gated on the probe having run: the script validates the
    // hardware itself and reports back, so an IPC/menu call works even before
    // the panel has ever been opened.
    if (!root.batteryPresent || root.limitApplying) return
    root.limitApplying = true
    root.limitFeedbackError = false
    root.limitFeedback = "Applying " + pct + "%…"
    targetProc.command = ["bash", root.limitScript, String(pct)]
    targetProc.running = true
  }

  function handleTargetResult(code) {
    root.limitApplying = false
    var result = Model.parseKeyValue(targetOutput.text)
    var ok = code === 0 && result.status === "ok"

    if (ok) {
      root.limitFeedbackError = false
      root.limitFeedback = Number(result.target) === 100
        ? "Hardware limit raised to 100% — charging resumes now"
        : "Hardware limit set to " + result.end + "% (start " + Model.limitStartLabel(result.start) + ")"
      // Give UPower/sysfs a few refreshes to settle, then trust the probe.
      root.verifyAttempts = 3
      verifyTimer.restart()
      root.notify(Number(result.target) === 100 ? "Charging to 100%" : "Charge limit " + result.end + "%",
        Number(result.target) === 100 ? "Full capacity requested" : "Charging capped at " + result.end + "%")
    } else {
      root.limitFeedbackError = true
      root.limitFeedback = result.message || ("Could not set the charge limit (exit " + code + ")")
      root.notify("Charge limit failed", root.limitFeedback)
    }

    root.refresh()
    root.refreshStats()
  }

  IpcHandler {
    target: "thepathless.juice"

    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    function togglePercentage() { root.togglePercentage() }
    // IPC arguments arrive as literal strings (omarchy-shell <target> <method> <arg>).
    function setShowPercentage(on: string): string {
      var enabled = Model.boolSetting(on, false)
      root.updateSetting("showPercentage", enabled)
      return enabled ? "on" : "off"
    }

    function setRedThreshold(value: string): string {
      var next = Model.redThreshold(value, root.redBatteryThreshold)
      root.updateSetting("redThreshold", next)
      return String(next)
    }

    function setPowerSaverThreshold(value: string): string {
      var next = Model.powerSaverThreshold(value, root.powerSaverThreshold)
      root.updateSetting("powerSaverThreshold", next)
      return String(next)
    }
    function state(): string {
      return JSON.stringify({
        level: root.batteryLevel,
        state: root.batteryState,
        icon: root.batteryIcon(),
        color: String(root.barIconColor),

        green: String(root.appleGreen),
        yellow: String(root.appleYellow),
        red: String(root.appleRed),
        redBelow: root.redBatteryThreshold,
        iconSize: root.barIconHeight,
        powerSaver: root.powerSaverActive,
        limit: root.chargeLimitEnd,
        statsLoaded: root.statsLoaded,
        showPercentage: root.showPercentage,
        borderless: root.borderlessStyle,
        autoPowerSaver: root.autoPowerSaver,
        powerSaverThreshold: root.powerSaverThreshold,
        autoSaverEngaged: root.autoSaverEngaged
      })
    }

    function charge80() { root.applyChargeTarget(80) }
    function charge100() { root.applyChargeTarget(100) }

    // Scriptable views of the two new surfaces, for keybinds and for checking
    // the live data without a screenshot.
    function devices(): string { return JSON.stringify(root.deviceList) }
    function usage(): string { return JSON.stringify(root.usageInfo) }

    // The open card's screen rectangle, so a capture can be cropped to it
    // exactly (the popup lives inside a full-screen layer surface, which the
    // compositor reports at monitor size rather than at the card's).
    function card(): string {
      return JSON.stringify({
        x: Math.round(panel.cardOrigin.x), y: Math.round(panel.cardOrigin.y),
        width: Math.round(panel.contentWidth), height: Math.round(panel.contentHeight)
      })
    }
  }

  onOpenedChanged: {
    if (opened) {
      // A reopened panel always starts on HEALTH; switching tabs inside one
      // open session still persists.
      detailTab = 0
      // Only the four disclosures reset; the permanent sections stay put.
      root.collapseSections()
      root.cancelSessionHold()

      if (!batteryPresent) {
        close()
        return
      }

      refresh()
      refreshStats()
      root.refreshDevices()
      root.refreshUsage()
      root.refreshSession()
      root.evaluatePowerSaver()
      var idx = profiles.indexOf(activeProfile)
      profileIndex = idx >= 0 ? idx : 0
      cursorActive = false
    } else {
      root.cancelSessionHold()
    }
  }

  onBatteryPresentChanged: {
    if (!batteryPresent) {
      close()
      return
    }
    // UPower can populate after this widget loads; probe as soon as a battery
    // exists so the charge-limit section and IPC calls are not stuck empty.
    refreshStats()
  }

  visible: batteryPresent
  implicitWidth: batteryPresent ? button.implicitWidth : 0
  implicitHeight: batteryPresent ? button.implicitHeight : 0

  Process {
    id: batteryProc
    command: ["omarchy-battery-status", "--shell"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateBattery(text) }
  }

  Process {
    id: profilesProc
    command: ["omarchy-powerprofiles-list", "--active-state"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateProfiles(text) }
  }

  // Session capability probe. Matches the conditions Omarchy's own system
  // menu uses: sleep disappears while suspend-off or sleep-disabled is set,
  // and hibernate only appears where the hibernation helper succeeds.
  Process {
    id: sessionProbe
    command: ["bash", "-lc",
      'sleep_disabled=0; omarchy-sleep-disabled >/dev/null 2>&1 && sleep_disabled=1; ' +
      'suspend=true; [ "$sleep_disabled" -eq 0 ] || suspend=false; ' +
      'omarchy-toggle-enabled suspend-off >/dev/null 2>&1 && suspend=false; ' +
      'hibernate=false; [ "$sleep_disabled" -eq 0 ] && omarchy-hibernation-available >/dev/null 2>&1 && hibernate=true; ' +
      'printf \'{"suspend":%s,"hibernate":%s}\\n\' "$suspend" "$hibernate"']
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.sessionAvailable = Model.parseSessionProbe(text)
    }
  }

  // Battery telemetry straight from sysfs. Read-only, bounded, and only while
  // the panel is open (plus once for the initial paint of the sections).
  Process {
    id: statsProc
    command: ["bash", root.statsScript]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = Model.parseKeyValue(text.slice(0, 4096))
        if (Object.keys(next).length > 0) root.statsInfo = next
      }
    }
  }

  // Applies a charge target. Output is parsed rather than trusted: the script
  // reads the thresholds back from the controller and reports what it found.
  Process {
    id: targetProc
    stdout: StdioCollector { id: targetOutput; waitForEnd: true }
    onExited: function(code) { root.handleTargetResult(code) }
  }

  Process {
    id: actionProc
    onExited: root.refresh()
  }

  // Power-supply uevents are emitted by the kernel as soon as the EC changes
  // status/charge, so this is the event edge that makes the bar icon move the
  // moment the hardware does. Each event only sets a flag; the timer below
  // collapses bursts into at most one probe every 2s.
  Process {
    id: ueventMonitor
    command: ["udevadm", "monitor", "--subsystem-match=power_supply", "--property"]
    running: root.batteryPresent
    stdout: SplitParser { onRead: function(line) { root.statsDirty = true } }
  }

  Timer {
    id: statsCoalesce
    interval: 2000
    repeat: true
    running: root.statsDirty
    onTriggered: {
      root.statsDirty = false
      root.refreshStats()
    }
  }

  Timer { interval: 5000; running: root.opened; repeat: true; onTriggered: root.refresh() }

  // Charge changes need a moment to appear in sysfs/UPower; refresh a few times
  // so the section settles on the real value.
  Timer {
    id: verifyTimer
    interval: 1500
    repeat: true
    running: root.verifyAttempts > 0
    onTriggered: {
      root.verifyAttempts -= 1
      root.refresh()
      root.refreshStats()
    }
  }

  // The tile fill is visual only; the timer is the source of truth. Both are
  // reset together by cancelSessionHold(), so a released key can never leave a
  // half-filled tile or fire later from the background.
  Timer {
    id: sessionHoldTimer
    interval: root.sessionHoldMs
    repeat: false
    onTriggered: root.completeSessionHold()
  }

  NumberAnimation {
    id: sessionHoldFill
    target: root
    property: "sessionHoldProgress"
    from: 0
    to: 1
    duration: root.sessionHoldMs
    easing.type: Easing.Linear
  }

  // Connected devices: UPower's own dump plus BlueZ and sysfs detail. Polled
  // only while the panel is open (and once at startup so IPC has data).
  Process {
    id: devicesProc
    command: ["bash", root.devicesScript]
    stdout: StdioCollector {
      waitForEnd: true
      // A failed probe leaves the last good list on screen rather than
      // blanking the section on a transient UPower hiccup.
      onStreamFinished: {
        var list = Model.parseDevices(text)
        if (list) root.deviceList = list
      }
    }
  }

  // Battery usage: the sampler runs for as long as the shell does, so the day's
  // history is continuous even while this panel is closed.
  Process {
    id: usageSampler
    command: ["python3", root.usageScript, "--daemon"]
    running: true
    onExited: function(code) { root.usageUnavailable = code !== 0 }
  }

  Process {
    id: usageProc
    command: ["python3", root.usageScript, "--report"]
    stdout: StdioCollector {
      waitForEnd: true
      // Keep the previous report; the usage card stays readable.
      onStreamFinished: {
        var report = Model.parseUsageReport(text)
        if (report) {
          root.usageInfo = report
          root.usageUnavailable = false
        }
      }
    }
    onExited: function(code) {
      if (code !== 0) root.usageUnavailable = true
    }
  }

  Timer {
    interval: 15000
    running: root.opened
    repeat: true
    onTriggered: root.refreshDevices()
  }

  Timer {
    interval: 60000
    running: root.opened && root.usageReady
    repeat: true
    onTriggered: root.refreshUsage()
  }

  // Probe once at startup so the charge-target section can show the truth even
  // before the panel is opened for the first time, and so the session strip
  // never offers a sleep state this machine cannot enter.
  Component.onCompleted: {
    root.refreshStats()
    root.refreshDevices()
    root.refreshUsage()
    root.refreshSession()
    root.evaluatePowerSaver()
  }

  // Power-saver automation is driven by UPower notifications, not a poll.
  Connections {
    target: UPower.displayDevice
    function onPercentageChanged() { root.evaluatePowerSaver() }
    function onStateChanged() { root.evaluatePowerSaver() }
  }

  Connections {
    target: UPower
    function onOnBatteryChanged() {
      // AC transitions are immediate signals: re-read sysfs right away instead
      // of waiting for the next kernel uevent.
      root.statsDirty = true
      root.evaluatePowerSaver()
    }
  }

  // Rotate the status phrase while the panel is open and we're in a
  // rotating state (charging or on battery). The text swap is wrapped in a
  // fade so the changeover reads as one organism rather than a hard cut.
  Timer {
    id: phraseTimer
    interval: 2800
    running: root.opened && root.rotatingPhrases
    repeat: true
    triggeredOnStart: false
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: heroStatus; property: "opacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: {
        var n = root.activePhrases.length
        if (n > 0) root.phraseIndex = (root.phraseIndex + 1) % n
      }
    }
    PropertyAnimation {
      target: heroStatus; property: "opacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  // If we leave a rotating state mid-swap, halt the animation and snap back
  // to full opacity so "FULLY CHARGED" is legible immediately rather than
  // appearing dimmed.
  Connections {
    target: root
    function onRotatingPhrasesChanged() {
      if (!root.rotatingPhrases) {
        phraseSwap.stop()
        heroStatus.opacity = 1.0
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    slotSize: button.vertical ? root.barGlyphWidth + Style.space(4) : root.barGlyphWidth + Style.space(6)
    foreground: root.barIconColor
    tooltipText: root.batteryStateText
      + (root.showPercentage || root.batteryLevel < 0 ? "" : " · " + root.batteryLevel + "%")
      + (root.stateExplanation === "" ? "" : " · " + root.stateExplanation)
    // BarIconContent scales every iconComponent into Style.bar.iconSize (12px
    // on this shell), which is exactly why the old glyph looked tiny. The empty
    // item keeps the button's "has visual content" true while the real glyph,
    // a child below, is drawn at its own size and only the slot reserves room.
    iconComponent: Component { Item {} }
    onPressed: function(b) {
      if (!root.batteryPresent) return
      if (b === Qt.RightButton) root.togglePercentage()
      else root.toggle()
    }

    Item {
      id: barGlyph
      anchors.centerIn: parent
      // A horizontal battery in a vertical bar is turned on its side so it
      // still fits the bar's width.
      implicitWidth: icon.implicitWidth
      implicitHeight: icon.implicitHeight
      width: button.vertical ? root.barGlyphHeight : root.barGlyphWidth
      height: button.vertical ? root.barGlyphWidth : root.barGlyphHeight

      BatteryIcon {
        id: icon
        anchors.centerIn: parent
        rotation: button.vertical ? 90 : 0
        iconSize: root.barGlyphHeight
        fontFamily: root.bar ? root.bar.fontFamily : ""
        level: root.batteryLevel
        charging: root.charging
        color: root.barIconColor
        contentColor: root.bar ? root.bar.barForeground : Commons.Color.foreground
        cutoutColor: root.barCutoutColor
        showPercentage: root.showPercentage
        borderless: root.borderlessStyle
        knockoutText: Model.knockoutText(
          root.batteryState, root.batteryLevel, root.powerSaverActive, root.redBatteryThreshold)
        // Apple never prints the percent sign inside the pill: only the digits.
        percentageText: root.batteryLevel >= 0 ? String(root.batteryLevel) : ""
      }
    }
  }

  // Which detail tab is showing; the card keeps one fixed height so switching
  // never reflows the rest of the dashboard.
  property int detailTab: 0

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && root.batteryPresent
    focusTarget: holdKeys
    contentWidth: panel.fittedContentWidth(Style.space(290))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dx !== 0) root.selectProfileByDelta(dx)
        else if (dy !== 0) root.selectProfileByDelta(dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateSelectedProfile()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      // The card is capped to the space under the bar, and opening a tall
      // disclosure can exceed that on a 1080p screen: without a scroll
      // container the last rows fall off the card and can't be clicked.
      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        // A fitted card can still be a fraction of a pixel taller than its
        // rounded interior. Counting that as overflow flicked a scrollbar on
        // for a view that fits and stole 17 px from every row beneath it, so
        // only a whole pixel of overflow makes the card scroll.
        readonly property bool overflows: contentHeight > height + 1
        interactive: overflows
        ScrollBar.vertical: ScrollBar {
          id: panelScroll
          policy: panelFlick.overflows ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        }
      }

      // Declared next to the Flickable rather than nested inside it so the
      // dashboard body keeps its own indentation; `parent` still makes it
      // the scroll content.
      Column {
        id: column
        parent: panelFlick.contentItem
        // A scrolling panel needs its own strip for the bar rather than
        // laying it over the right-aligned value chips.
        width: panelFlick.width - (panelFlick.interactive ? panelScroll.width + Style.space(6) : 0)
        spacing: Style.space(12)

        // ---------- Hero: Bespoke Battery Card ----------
        Rectangle {
          width: parent.width
          radius: Style.cornerRadius > 0 ? Style.cornerRadius : 10
          color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.04)
          border.width: 1
          border.color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
          implicitHeight: heroLayout.implicitHeight + Style.space(20)

          Column {
            id: heroLayout
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(10)
            spacing: Style.space(10)

            RowLayout {
              width: parent.width
              spacing: Style.space(10)

              BatteryIcon {
                id: heroIconVisual
                Layout.alignment: Qt.AlignVCenter
                iconSize: Style.space(30)
                fontFamily: root.bar.fontFamily
                level: root.batteryLevel
                charging: root.charging
                color: root.barIconColor
                contentColor: root.bar.foreground
                cutoutColor: Commons.Color.popups.background
                borderless: root.borderlessStyle
              }

              ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: Style.space(1)

                Text {
                  textFormat: Text.PlainText
                  text: root.batteryInfo.percentage || (root.batteryLevel >= 0 ? root.batteryLevel + "%" : "—")
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.title + 2
                  font.bold: true
                }

                Text {
                  id: heroStatus
                  textFormat: Text.PlainText
                  text: root.heroStatusText.toUpperCase()
                  color: Qt.darker(root.bar.foreground, 1.35)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 0.8
                  elide: Text.ElideRight
                  Layout.fillWidth: true
                }

                // UPower's own estimate; Omarchy's `time` string is the
                // fallback in the FLOW tile when UPower has nothing to say.
                Text {
                  textFormat: Text.PlainText
                  visible: root.timeRemainingText !== ""
                  text: root.timeRemainingText
                  color: Qt.darker(root.bar.foreground, 1.3)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  Layout.fillWidth: true
                }
              }

              // Power / State Badge
              Rectangle {
                id: powerBadge
                Layout.alignment: Qt.AlignVCenter
                radius: 6
                color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.08)
                border.width: 1
                border.color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
                implicitWidth: powerBadgeText.implicitWidth + Style.space(10)
                implicitHeight: Style.space(22)

                Text {
                  id: powerBadgeText
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: root.statsLoaded && root.statsInfo.power_now
                    ? Model.formatWatts(root.statsInfo.power_now)
                    : (root.acOnline ? "AC" : "BAT")
                  color: root.charging ? Commons.Color.bar.active : root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }
            }

            // Sleek embedded level bar
            Item {
              width: parent.width
              implicitHeight: Style.space(4)

              Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
              }

              Rectangle {
                height: parent.height
                radius: height / 2
                color: root.barIconColor
                width: Math.max(parent.height, parent.width * root.batteryFraction)

                Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 220 } }
              }
            }
          }
        }

        SectionCard {
          width: parent.width
          title: "CHARGE TARGET"
          summary: root.chargeLimitSupported ? "Limit " + root.chargeLimitEnd + "%" : "Unsupported"
          collapsible: false
          expanded: true
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily

          Column {
            width: parent.width
            spacing: Style.space(6)

            RowLayout {
              id: limitRow
              width: parent.width
              spacing: Style.space(6)

              Button {
                Layout.fillWidth: true
                iconText: "󰂊"
                iconSize: Style.font.title
                text: "80% Limit"
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY
                bordered: true
                active: root.chargeLimitEnd === 80
                enabled: root.chargeLimitSupported && !root.limitApplying
                opacity: enabled ? 1.0 : 0.45
                onClicked: root.applyChargeTarget(80)
              }

              Button {
                Layout.fillWidth: true
                iconText: "󰂅"
                iconSize: Style.font.title
                text: "100% Full"
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY
                bordered: true
                active: root.chargeLimitEnd === 100
                enabled: root.chargeLimitSupported && !root.limitApplying
                opacity: enabled ? 1.0 : 0.45
                onClicked: root.applyChargeTarget(100)
              }
            }

            // No elide: every sentence this label can hold is short enough for
            // the card, so a missing tail would only ever hide a real bug.
            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: root.statsLoaded ? root.chargeStateText : "Reading hardware state…"
              color: root.bar.foreground
              opacity: 0.6
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              visible: root.limitFeedback !== ""
              text: root.limitFeedback
              color: root.limitFeedbackError ? Commons.Color.urgent : root.bar.foreground
              opacity: root.limitFeedbackError ? 1.0 : 0.7
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }
        }

        SectionCard {
          width: parent.width
          title: "POWER PROFILE"
          summary: root.activeProfileLabel
          collapsible: false
          expanded: true
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily

          Column {
            width: parent.width
            spacing: Style.space(6)

            RowLayout {
              id: profileRow
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.profiles
                Button {
                  required property var modelData
                  required property int index
                  Layout.fillWidth: true
                  iconText: root.profileIcon(String(modelData))
                  iconSize: Style.font.title
                  text: String(modelData) === "power-saver" ? "Saver" : (String(modelData) === "performance" ? "Perf" : "Balanced")
                  fontSize: Style.font.bodySmall
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  horizontalPadding: Style.space(6)
                  verticalPadding: Style.spacing.controlPaddingY
                  bordered: true
                  active: root.activeProfile === modelData
                  hasCursor: root.cursorActive && root.profileIndex === index
                  onClicked: {
                    root.autoSaverEngaged = false
                    root.setProfile(modelData)
                  }
                  onHovered: function(h) {
                    if (h) {
                      root.cursorActive = true
                      root.profileIndex = index
                    }
                  }
                }
              }
            }
          }
        }

        SectionCard {
          width: parent.width
          title: "SESSION"
          collapsible: false
          expanded: true
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily

          SessionActions {
            width: parent.width
            actions: root.sessionActions
            holdMs: root.sessionHoldMs
            holdingId: root.sessionHoldId
            holdProgress: root.sessionHoldProgress
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            accentColor: Commons.Color.accent
            urgentColor: Commons.Color.urgent
            onHoldStarted: function(id) { root.beginSessionHold(id) }
            onHoldEnded: function(id) { root.cancelSessionHold(id) }
          }
        }

        SectionCard {
          width: parent.width
          title: "BATTERY DETAIL"
          summary: root.statsLoaded ? Math.round(root.healthPercent) + "% health" : ""
          visible: root.statsLoaded
          expanded: root.detailOpen
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          onToggled: root.detailOpen = !root.detailOpen

          Column {
            visible: root.statsLoaded
            width: parent.width
            spacing: Style.space(6)

            Rectangle {
              width: parent.width
              height: detailTabs.height + detailBody.height + Style.space(27)
              // Inset-grouped corner radius: 10 pt at 17 pt body, 0.588 here.
              radius: Style.cornerRadius > 0 ? Math.min(6, Style.cornerRadius) : 6
              color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.03)
              border.width: 1
              border.color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.08)

              Column {
                anchors.fill: parent
                anchors.margins: Style.space(9)
                spacing: Style.space(9)

                DetailTabs {
                  id: detailTabs
                  width: parent.width
                  current: root.detailTab
                  onSelected: function(index) { root.detailTab = index }
                }

                // Every tab holds six rows, so the card height is fixed and
                // switching tabs never moves anything else on the page.
                Item {
                  id: detailBody
                  width: parent.width
                  height: detailHealth.implicitHeight

                  Column {
                    id: detailHealth
                    anchors.fill: parent
                    visible: root.detailTab === 0
                    spacing: 0

                    DetailRow { foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; label: "Maximum capacity"; value: root.healthPercent >= 0 ? root.healthPercent.toFixed(1) + "%" : "—" }
                    DetailRow { foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; label: "Condition"; value: root.healthGrade !== "" ? root.healthGrade : "—" }
                    DetailRow { foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; label: "Wear"; value: Model.formatEnergy(Model.wear(root.statsInfo.energy_full, root.statsInfo.energy_full_design), root.energyUnit) }
                    DetailRow { foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; label: "Cycle count"; value: Model.formatCount(root.statsInfo.cycle_count) }
                    DetailRow { foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; label: "Kernel health"; value: root.statsInfo.health || "—" }
                    DetailRow { foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; label: "Capacity level"; value: root.statsInfo.capacity_level || "—"; showDivider: false }
                  }

                  Column {
                    id: detailPower
                    anchors.fill: parent
                    visible: root.detailTab === 1
                    spacing: 0

                    DetailRow { foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; label: "Energy now"; value: Model.formatEnergy(root.statsInfo.energy_now, root.energyUnit) }
                    DetailRow { foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; label: "Charge rate"; value: Model.formatWatts(root.statsInfo.power_now) }
                    DetailRow { foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; label: "Current"; value: Model.formatAmps(root.statsInfo.current_now) }
                    DetailRow { foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; label: "Voltage"; value: Model.formatVolts(root.statsInfo.voltage_now) }
                    DetailRow { foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; label: "Temperature"; value: Model.formatCelsius(root.statsInfo.temp_c) }
                    DetailRow { foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; label: "Time left"; value: root.timeRemainingText !== "" ? root.timeRemainingText : "—"; showDivider: false }
                  }

                  Column {
                    id: detailSpecs
                    anchors.fill: parent
                    visible: root.detailTab === 2
                    spacing: 0

                    DetailRow { foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; label: "Vendor / model"; value: Model.deviceName(root.statsInfo.manufacturer, root.statsInfo.model) }
                    DetailRow { foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; label: "Cell type"; value: root.statsInfo.technology || "—" }
                    DetailRow { foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; label: "Serial"; value: root.statsInfo.serial || "—" }
                    DetailRow { foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; label: "Design capacity"; value: Model.formatEnergy(root.statsInfo.energy_full_design, root.energyUnit) }
                    DetailRow { foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; label: "Charge threshold"; value: Model.limitModeLabel(root.statsInfo.threshold_start, root.statsInfo.threshold_end) }
                    DetailRow { foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; label: "sysfs"; value: Model.pathBase(root.statsInfo.path); showDivider: false }
                  }
                }
              }
            }
          }
        }

        SectionCard {
          width: parent.width
          title: "CONNECTED DEVICES"
          summary: root.deviceList.length === 0 ? "None"
            : root.deviceList.length + (root.deviceList.length === 1 ? " device" : " devices")
          expanded: root.devicesOpen
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          onToggled: root.devicesOpen = !root.devicesOpen

          ConnectedDevices {
            width: parent.width
            devices: root.deviceList
            expandedId: root.expandedDevice
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            greenColor: root.appleGreen
            redColor: root.appleRed
            redBelow: root.redBatteryThreshold
            onToggled: function(id) {
              root.expandedDevice = root.expandedDevice === id ? "" : id
            }
          }
        }

        SectionCard {
          width: parent.width
          title: "BATTERY USAGE"
          summary: root.usageSummary
          expanded: root.usageOpen
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          onToggled: root.usageOpen = !root.usageOpen

          UsageCard {
            width: parent.width
            report: root.usageInfo
            unavailable: root.usageUnavailable
            selectedDate: root.usageDay
            onDaySelected: function(date) { root.selectUsageDay(date) }
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            accentColor: root.appleBlue
            greenColor: root.appleGreen
            yellowColor: root.appleYellow
            redColor: root.appleRed
          }
        }

        SectionCard {
          width: parent.width
          title: "USAGE BY APP"
          summary: root.usageAppList.length > 0 ? root.usageAppList.length + " apps"
            : (root.showingPastDay ? "Not recorded" : "")
          // No rows and no explanation means there is nothing to open.
          visible: root.usageAppList.length > 0 || root.usageAppsNote !== ""
          expanded: root.appsOpen
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          onToggled: root.appsOpen = !root.appsOpen

          UsageAppList {
            width: parent.width
            apps: root.usageAppList
            note: root.usageAppsNote
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }
        }

        SectionCard {
          width: parent.width
          title: "OPTIONS"
          expanded: root.optionsOpen
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          onToggled: root.optionsOpen = !root.optionsOpen

          Column {
            width: parent.width
            spacing: Style.space(6)

            OptionRow {
              label: "Percentage inside battery"
              Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)

                ToggleSwitch {
                  anchors.verticalCenter: parent.verticalCenter
                  checked: root.showPercentage
                  foreground: root.bar.foreground
                  accent: Commons.Color.accent
                  onToggled: root.togglePercentage()
                }
              }
            }

            OptionRow {
              label: "iOS 27 borderless body"
              Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)

                ToggleSwitch {
                  anchors.verticalCenter: parent.verticalCenter
                  checked: root.borderlessStyle
                  foreground: root.bar.foreground
                  accent: Commons.Color.accent
                  onToggled: root.updateSetting("borderless", !root.borderlessStyle)
                }
              }
            }

            OptionRow {
              label: "Icon height"
              Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)

                Button {
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.barIconHeight + "px"
                  fontSize: Style.font.caption
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  horizontalPadding: Style.space(8)
                  verticalPadding: Style.space(2)
                  bordered: true
                  onClicked: root.updateSetting("iconSize", Model.cycleSetting("iconSize", root.barIconHeight))
                }
              }
            }

            OptionRow {
              label: "Turn red below"
              Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)

                NumberField {
                  anchors.verticalCenter: parent.verticalCenter
                  settingKey: "redThreshold"
                  value: root.redBatteryThreshold
                  minimum: Model.settingRange("redThreshold").min
                  maximum: Model.settingRange("redThreshold").max
                  onCommitted: function(next) { root.updateSetting("redThreshold", next) }
                }
              }
            }

            OptionRow {
              label: "Auto power-saver"
              Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)

                ToggleSwitch {
                  anchors.verticalCenter: parent.verticalCenter
                  checked: root.autoPowerSaver
                  foreground: root.bar.foreground
                  accent: Commons.Color.accent
                  onToggled: root.updateSetting("autoPowerSaver", !root.autoPowerSaver)
                }
              }
            }

            OptionRow {
              label: "Auto power-saver at"
              enabled: root.autoPowerSaver
              opacity: root.autoPowerSaver ? 1.0 : 0.45
              Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)

                NumberField {
                  anchors.verticalCenter: parent.verticalCenter
                  settingKey: "powerSaverThreshold"
                  value: root.powerSaverThreshold
                  minimum: Model.settingRange("powerSaverThreshold").min
                  maximum: Model.settingRange("powerSaverThreshold").max
                  alert: root.autoSaverEngaged
                  onCommitted: function(next) { root.updateSetting("powerSaverThreshold", next) }
                }
              }
            }
          }
        }
      }

      // Transparent key layer above the dashboard. It claims only the session
      // hold keys; every other key falls through to PanelKeyCatcher above.
      HoldKeys {
        id: holdKeys
        anchors.fill: parent
        actions: root.sessionActions
        onHoldStarted: function(id) { root.beginSessionHold(id) }
        onHoldEnded: function(id) { root.cancelSessionHold(id) }
        onHorizontalMove: function(direction) { root.moveProfileHorizontal(direction) }
      }
    }
  }

  // One settings row: a label on the left, whatever control is declared
  // inside on the right.
  component OptionRow: Rectangle {
    property string label: ""
    default property alias controls: controlSlot.data

    width: parent ? parent.width : 0
    height: Style.space(34)
    radius: Style.cornerRadius > 0 ? Math.min(8, Style.cornerRadius) : 6
    color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.03)
    border.width: 1
    border.color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.08)

    Text {
      id: optionLabel
      anchors.left: parent.left
      anchors.leftMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(0, parent.width - controlSlot.width - Style.space(22))
      textFormat: Text.PlainText
      text: parent.label
      color: root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }

    // Controls arrive as a Row written by the caller, so a row can hold one
    // chip or several; this slot only pins that Row to the right edge.
    Item {
      id: controlSlot
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      // Width comes from the controls; the height is the row's, so a child
      // centring itself on this item cannot feed back into its size.
      width: childrenRect.width
    }
  }

  // Direct numeric entry for a bounded setting. The validator only admits
  // integers inside the manifest range, Enter or leaving the field commits,
  // and unparseable text falls back to the live value instead of writing NaN.
  component NumberField: Rectangle {
    id: numberField
    property string settingKey: ""
    property int value: 0
    property int minimum: 0
    property int maximum: 100
    property bool alert: false
    signal committed(int value)

    readonly property color textColor: alert ? Commons.Color.urgent : root.bar.foreground

    implicitWidth: Style.space(40)
    implicitHeight: Style.space(22)
    radius: Style.cornerRadius > 0 ? Math.min(8, Style.cornerRadius) : 6
    color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.06)
    border.width: 1
    border.color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b,
      input.activeFocus ? 0.35 : 0.12)

    // Set while abandoning an edit: the blur that closing causes must not
    // commit, so Escape can never write the value it was meant to discard.
    property bool reverting: false
    property int focusValue: value

    function commit() {
      if (reverting) return
      var next = Model.clampSetting(settingKey, input.text, value)
      input.text = String(next)
      // Keep the value selected after a commit so the next keystroke replaces
      // it instead of appending to digits the user has already accepted.
      if (input.activeFocus) input.selectAll()
      if (next !== value) numberField.committed(next)
    }

    function cancel() {
      reverting = true
      input.text = String(focusValue)
      root.close()
    }

    Row {
      anchors.centerIn: parent
      spacing: Style.space(1)

      TextInput {
        id: input
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(18)
        text: String(numberField.value)
        horizontalAlignment: TextInput.AlignHCenter
        color: numberField.textColor
        selectionColor: Commons.Color.accent
        selectedTextColor: Commons.Color.background
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        selectByMouse: true
        validator: IntValidator { bottom: numberField.minimum; top: numberField.maximum }
        inputMethodHints: Qt.ImhDigitsOnly
        // Return commits even when the typed value is outside the range, so
        // the clamp is visible immediately instead of waiting for a blur.
        Keys.onReturnPressed: { numberField.commit(); root.releaseFieldFocus() }
        Keys.onEnterPressed: { numberField.commit(); root.releaseFieldFocus() }
        Keys.onEscapePressed: numberField.cancel()
        onEditingFinished: numberField.commit()
        onActiveFocusChanged: {
          if (activeFocus) {
            numberField.focusValue = numberField.value
            numberField.reverting = false
            selectAll()
          } else {
            numberField.commit()
          }
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "%"
        textFormat: Text.PlainText
        color: numberField.textColor
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    onValueChanged: if (!input.activeFocus) input.text = String(value)
  }

  // iOS-style segmented control: one gray track, one raised pill for the
  // selected tab, three equal segments so the card height never changes.
  component DetailTabs: Rectangle {
    id: tabs
    property int current: 0
    signal selected(int index)

    // UIKit's inset segmented control: 32 pt tall with an 8 pt corner at a
    // 17 pt body size, scaled to this card's 10 px caption (0.588).
    implicitHeight: Style.space(19)
    radius: Style.cornerRadius > 0 ? Math.min(5, Style.cornerRadius) : 5
    color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.06)

    Row {
      anchors.fill: parent
      anchors.margins: Style.space(2)
      spacing: Style.space(2)

      Repeater {
        model: ["HEALTH", "POWER", "SPECS"]

        Rectangle {
          required property int index
          required property string modelData

          width: (tabs.width - Style.space(8)) / 3
          height: parent.height
          radius: Style.cornerRadius > 0 ? Math.min(5, Style.cornerRadius) : 5
          color: index === tabs.current
            ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.16)
            : "transparent"

          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: modelData
            color: root.bar.foreground
            opacity: index === tabs.current ? 1 : 0.55
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption - 2
            font.bold: index === tabs.current
            font.letterSpacing: 0.6
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: tabs.selected(index)
          }
        }
      }
    }
  }
}
