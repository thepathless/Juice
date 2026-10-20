import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// OmaBattery — battery bar widget and panel.
//
// This is a clone of Omarchy's built-in omarchy.power panel: the bar button,
// hero, charge bar, stats row, power-profile picker, keyboard handling, theming
// hooks (root.bar.foreground / root.bar.fontFamily / Commons.Color) and the
// omarchy-* commands it shells out to are all kept as-is. Two sections are
// added:
//
//   1. CHARGE LIMIT — writes the kernel charge thresholds (80% / 100%) through
//      scripts/omabattery-set-limit and always reports what the hardware
//      actually holds, never what we asked for.
//   2. BATTERY HEALTH — the detailed sysfs telemetry (health, cycles, capacity,
//      voltage, power, time estimates) rendered with the same InfoPair /
//      PanelSectionHeader / PanelSeparator primitives the rest of the panel
//      uses, so it reads as part of the theme rather than a new visual language.
Panel {
  id: root
  moduleName: "thepathless.omabattery"
  ipcTarget: "thepathless.omabattery"
  // manageIpc: false so this panel can own the single IpcHandler the target
  // permits — needed for the charge-target and togglePercentage methods below.
  manageIpc: false
  property var batteryInfo: ({})
  property var systemInfo: ({})
  property var profiles: []
  property string activeProfile: ""
  property int profileIndex: 0
  property bool cursorActive: false
  readonly property bool showPercentage: setting("showPercentage", false) === true
  // With the percentage shown the button paints a text block wider than an
  // icon, so the open-panel mark takes the painted width instead of the
  // icon-sized fraction of the slot the fallback assumes.
  readonly property real openPanelIndicatorWidth: showPercentage && !button.vertical ? button.width : 0
  readonly property bool batteryPresent: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent)
  }

  // ---- OmaBattery: sysfs telemetry, charge targets -------------------------
  //
  // statsInfo holds the last successful probe (see scripts/omabattery-stats).
  // It is the only source for the threshold and health numbers, so the panel
  // can never show an assumed value.
  property var statsInfo: ({})
  property bool limitApplying: false
  property string limitFeedback: ""
  property bool limitFeedbackError: false
  property int verifyAttempts: 0

  // ---- OmaBattery: bar presentation and options ---------------------------
  //
  // The bar glyph and its colour are pure functions of the UPower device (see
  // Model.batteryState), bound rather than polled, so the icon changes at the
  // same moment the compositor sees the state change.
  property color warningColor: Commons.Color.bar.active
  property color criticalColor: Commons.Color.urgent
  property bool autoSaverEngaged: false
  // Profile the user was running before the saver was engaged, so releasing
  // restores exactly that instead of guessing from stored preferences.
  property string saverRestoreProfile: "balanced"
  // Set by the power-supply uevent monitor; coalesced into a single probe.
  property bool statsDirty: false

  readonly property int batteryLevel: Model.batteryLevel(UPower.displayDevice)
  readonly property string batteryState: Model.batteryState(UPower.displayDevice, root.discharging, upowerStates(), root.statsInfo.status)
  readonly property string batteryStateText: Model.stateLabel(root.batteryState, root.batteryLevel)
  // Colour bands requested for this machine: the normal bar colour above 50%,
  // the theme's yellow from 50% down to 25%, and its red below 25%.
  readonly property int lowBatteryThreshold: 50
  readonly property int criticalBatteryThreshold: 25
  readonly property color barIconColor: Model.levelColor(
    root.batteryLevel, root.lowBatteryThreshold, root.criticalBatteryThreshold,
    root.warningColor, root.criticalColor,
    root.bar ? root.bar.barForeground : Commons.Color.foreground)
  readonly property int powerSaverThreshold: Model.powerSaverThreshold(setting("powerSaverThreshold", 50), 50)

  readonly property string statsScript: decodeURIComponent(
    Qt.resolvedUrl("scripts/omabattery-stats").toString().replace(/^file:\/\//, ""))
  readonly property string limitScript: decodeURIComponent(
    Qt.resolvedUrl("scripts/omabattery-set-limit").toString().replace(/^file:\/\//, ""))

  readonly property bool statsLoaded: statsInfo.capacity !== undefined
  readonly property int chargeLimitEnd: {
    var n = parseInt(root.statsInfo.threshold_end, 10)
    return isNaN(n) ? -1 : n
  }
  readonly property int chargeLimitStart: {
    var n = parseInt(root.statsInfo.threshold_start, 10)
    return isNaN(n) ? -1 : n
  }
  readonly property bool chargeLimitSupported: root.chargeLimitEnd >= 0
  readonly property bool acOnline: root.statsInfo.ac_online === "1"
  readonly property string hardwareStatus: root.statsInfo.status || ""
  readonly property string energyUnit: root.statsInfo.unit || "Wh"
  readonly property real healthPercent: Model.batteryHealth(root.statsInfo.energy_full, root.statsInfo.energy_full_design)
  readonly property real healthFraction: Model.healthFraction(root.statsInfo.energy_full, root.statsInfo.energy_full_design)
  readonly property string healthGrade: Model.healthGrade(root.healthPercent)
  // Live sentence built from the last probe: the truth about the hardware.
  readonly property string chargeStateText: Model.chargeStateLabel(root.hardwareStatus, root.chargeLimitEnd, root.acOnline)

  function upowerStates() {
    return {
      Charging: UPowerDeviceState.Charging,
      Discharging: UPowerDeviceState.Discharging,
      FullyCharged: UPowerDeviceState.FullyCharged,
      PendingCharge: UPowerDeviceState.PendingCharge
    }
  }

  function selectProfileByDelta(delta) {
    profileIndex = Model.selectProfileIndex(profileIndex, delta, profiles)
  }

  function activateSelectedProfile() {
    if (profileIndex < 0 || profileIndex >= profiles.length) return
    setProfile(profiles[profileIndex])
  }

  function batteryIcon() {
    var device = UPower.displayDevice
    return Model.batteryIcon(device, root.discharging, upowerStates(), root.statsInfo.status)
  }

  function modeLabel() {
    var device = UPower.displayDevice
    return Model.modeLabel(device, root.discharging, upowerStates())
  }

  function profileIcon(name) {
    return Model.profileIcon(name)
  }

  readonly property bool fullyCharged: {
    var device = UPower.displayDevice
    return device && device.isPresent && device.state === UPowerDeviceState.FullyCharged && !root.chargeThresholdActive
  }
  readonly property bool discharging: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent && UPower.onBattery)
  }
  readonly property bool chargeThresholdActive: {
    var device = UPower.displayDevice
    return Model.chargeThresholdActive(device, root.discharging, upowerStates())
  }
  readonly property bool batteryFull: fullyCharged || (!root.discharging && batteryFraction >= 1)
  readonly property bool batteryFlowIdle: batteryFull || chargeThresholdActive

  // 0..1 charge level, used by the visual progress bar.
  readonly property real batteryFraction: {
    var d = UPower.displayDevice
    return Model.batteryFraction(d)
  }

  readonly property bool charging: {
    var d = UPower.displayDevice
    return d && d.isPresent && !UPower.onBattery && !root.batteryFlowIdle
  }

  readonly property color batteryFillColor: {
    return root.bar ? root.bar.foreground : Commons.Color.foreground
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
    if (fullyCharged) return []
    if (charging) return chargingPhrases
    if (discharging) return onBatteryPhrases
    return []
  }
  readonly property bool rotatingPhrases: activePhrases.length > 0

  readonly property string heroStatusText: {
    if (fullyCharged) return "Fully charged"
    if (rotatingPhrases) return activePhrases[phraseIndex % activePhrases.length]
    return modeLabel()
  }

  function refresh() {
    if (!batteryPresent) return

    if (!batteryProc.running) batteryProc.running = true
    if (!profilesProc.running) profilesProc.running = true
    if (!systemProc.running) systemProc.running = true
  }

  function refreshStats() {
    if (!batteryPresent) return
    if (!statsProc.running) statsProc.running = true
  }

  function updateKeyValue(raw, targetName) {
    var next = Model.parseKeyValue(raw)
    // Keep last known good data if a refresh briefly returns nothing — happens
    // around AC plug/unplug events. Avoids the section collapsing mid-transition.
    if (Object.keys(next).length === 0) return
    if (targetName === "battery") batteryInfo = next
    else systemInfo = next
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
    actionProc.command = ["omarchy-powerprofiles-set", root.discharging ? "battery" : "ac", profile]
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

  // Bar-widget options live in this widget's inline shell.json entry — the same
  // place Omarchy stores every other bar setting. Writing the whole entry back
  // through the shell is what makes the choice survive a restart.
  function updateSetting(key, value) {
    var next = Object.assign({}, root.settings)
    next[key] = value
    root.settings = next
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, next)
  }

  // ---- OmaBattery: power-saver automation ---------------------------------

  // Engages power-saver when the battery drops to the configured level, and
  // releases it a few points above that so the profile does not flap at the
  // boundary. Called from UPower bindings, never from a timer.
  function evaluatePowerSaver() {
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

  onPowerSaverThresholdChanged: root.evaluatePowerSaver()

  // ---- OmaBattery: charge targets -----------------------------------------

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
    target: "thepathless.omabattery"

    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    function togglePercentage() { root.togglePercentage() }
    // IPC arguments arrive as literal strings (omarchy-shell <target> <method> <arg>).
    function setShowPercentage(on: string): string {
      var enabled = on === "true" || on === "1"
      root.updateSetting("showPercentage", enabled)
      return enabled ? "on" : "off"
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
        warning: String(root.warningColor),
        critical: String(root.criticalColor),
        limit: root.chargeLimitEnd,
        statsLoaded: root.statsLoaded,
        showPercentage: root.showPercentage,
        powerSaverThreshold: root.powerSaverThreshold,
        autoSaverEngaged: root.autoSaverEngaged
      })
    }

    function charge80() { root.applyChargeTarget(80) }
    function charge100() { root.applyChargeTarget(100) }
  }

  onOpenedChanged: {
    if (opened) {
      if (!batteryPresent) {
        close()
        return
      }

      refresh()
      refreshStats()
      root.evaluatePowerSaver()
      var idx = profiles.indexOf(activeProfile)
      profileIndex = idx >= 0 ? idx : 0
      cursorActive = false
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
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateKeyValue(text, "battery") }
  }

  Process {
    id: profilesProc
    command: ["omarchy-powerprofiles-list", "--active-state"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateProfiles(text) }
  }

  Process {
    id: systemProc
    command: ["omarchy-system-stats"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateKeyValue(text, "system") }
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

  // Probe once at startup so the charge-target section can show the truth even
  // before the panel is opened for the first time.
  Component.onCompleted: {
    root.refreshStats()
    root.applyThemeWarningColors("")
    root.evaluatePowerSaver()
  }

  // Low/critical colours come from the active theme's own palette — the same
  // colors.toml Commons/Color.qml reads — so the escalation stays on-theme
  // instead of hardcoding a yellow and a red. Falls back to the shell's alert
  // roles when a theme does not define them.
  function applyThemeWarningColors(raw) {
    var lines = String(raw || "").split("\n")
    var yellow = ""
    var red = ""
    for (var i = 0; i < lines.length; i++) {
      var match = lines[i].match(/^\s*(yellow|red)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (!match) continue
      if (match[1] === "yellow") yellow = match[2]
      else red = match[2]
    }
    root.warningColor = yellow !== "" ? yellow : Commons.Color.bar.active
    root.criticalColor = red !== "" ? red : Commons.Color.urgent
  }

  FileView {
    id: themeColors
    path: Commons.Color.currentThemePath + "/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.applyThemeWarningColors(text())
    onFileChanged: reload()
  }

  // A theme switch rewrites that file; reload when the shell's palette moves
  // so the warning colours follow the new theme immediately.
  Connections {
    target: Commons.Color
    function onForegroundChanged() { themeColors.reload() }
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
    labelText: root.showPercentage && !vertical && root.batteryLevel >= 0
      ? root.batteryLevel + "%"
      : ""
    slotSize: Style.bar.iconSlot * (root.showPercentage && !vertical ? 2 : 1)
    foreground: root.barIconColor
    tooltipText: root.batteryStateText
    iconComponent: Component {
      Item {
        BatteryIcon {
          x: Math.round((parent.width - width) / 2)
          y: Math.round((parent.height - height) / 2)
          iconSize: button.iconSize
          level: root.batteryLevel
          charging: root.charging
          holding: root.chargeThresholdActive
          acOnline: root.acOnline
          color: root.barIconColor
          pulseCharging: true
        }
      }
    }
    onPressed: function(b) {
      if (!root.batteryPresent) return
      if (b === Qt.RightButton) root.togglePercentage()
      else root.toggle()
    }
  }

  property bool showHardwareDetails: false

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && root.batteryPresent
    focusTarget: keyCatcher
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

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
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
                iconSize: Style.space(22)
                level: root.batteryLevel
                charging: root.charging
                holding: root.chargeThresholdActive
                acOnline: root.acOnline
                color: root.barIconColor
                pulseCharging: true
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
                color: root.batteryFillColor
                width: Math.max(parent.height, parent.width * root.batteryFraction)

                Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 220 } }
              }
            }
          }
        }

        // ---------- Charge Limit Segmented Control ----------
        Column {
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "CHARGE TARGET"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

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

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: root.statsLoaded ? root.chargeStateText : "Reading hardware state…"
            color: root.bar.foreground
            opacity: 0.6
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
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

        // ---------- Power Profile Switcher ----------
        Column {
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "POWER PROFILE"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

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

        // ---------- Hardware Telemetry (Bento Grid) ----------
        Column {
          visible: root.statsLoaded
          width: parent.width
          spacing: Style.space(6)

          Row {
            width: parent.width
            PanelSectionHeader {
              text: "HARDWARE TELEMETRY"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              width: parent.width - detailsToggle.implicitWidth
            }

            Text {
              id: detailsToggle
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.showHardwareDetails ? "Less ▴" : "More ▾"
              color: root.bar.foreground
              opacity: 0.6
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.showHardwareDetails = !root.showHardwareDetails
              }
            }
          }

          GridLayout {
            width: parent.width
            columns: 2
            rowSpacing: Style.space(6)
            columnSpacing: Style.space(6)

            MetricTile {
              Layout.fillWidth: true
              label: "HEALTH"
              value: root.healthPercent >= 0 ? root.healthPercent.toFixed(1) + "%" : "—"
              detail: root.healthGrade || "Good"
              accentValue: root.healthPercent < 70 ? Commons.Color.urgent : root.bar.foreground
            }

            MetricTile {
              Layout.fillWidth: true
              label: "CYCLES"
              value: Model.formatCount(root.statsInfo.cycle_count)
              detail: root.batteryInfo.size || Model.formatEnergy(root.statsInfo.energy_full, root.energyUnit)
            }

            MetricTile {
              Layout.fillWidth: true
              label: root.discharging ? "DRAIN" : "FLOW"
              value: Model.formatWatts(root.statsInfo.power_now)
              detail: root.acOnline ? "AC Online" : (root.batteryInfo.time || "Discharging")
            }

            MetricTile {
              Layout.fillWidth: true
              label: "TEMP / VOLTS"
              value: root.statsInfo.temp_c !== undefined ? Model.formatCelsius(root.statsInfo.temp_c) : Model.formatVolts(root.statsInfo.voltage_now)
              detail: Model.formatVolts(root.statsInfo.voltage_now)
            }
          }

          // Extended hardware specs disclosure
          Column {
            visible: root.showHardwareDetails
            width: parent.width
            spacing: Style.space(4)

            InfoPair { label: "Design Capacity"; value: Model.formatEnergy(root.statsInfo.energy_full_design, root.energyUnit) }
            InfoPair { label: "Cell Type"; value: root.statsInfo.technology || "Li-poly" }
            InfoPair { label: "Vendor / Model"; value: (root.statsInfo.manufacturer || "OEM") + " " + (root.statsInfo.model || "") }
            InfoPair { label: "Voltage Min"; value: Model.formatVolts(root.statsInfo.voltage_min_design) }
          }
        }

        // ---------- Options ----------
        Column {
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "OPTIONS"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Rectangle {
            width: parent.width
            height: Style.space(34)
            radius: Style.cornerRadius > 0 ? Math.min(8, Style.cornerRadius) : 6
            color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.03)
            border.width: 1
            border.color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.08)

            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              spacing: Style.space(8)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "Show percentage on bar"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                width: parent.width - toggleSwitch.width - Style.space(8)
              }

              ToggleSwitch {
                id: toggleSwitch
                anchors.verticalCenter: parent.verticalCenter
                checked: root.showPercentage
                foreground: root.bar.foreground
                accent: Commons.Color.accent
                onToggled: root.togglePercentage()
              }
            }
          }

          Rectangle {
            width: parent.width
            height: Style.space(34)
            radius: Style.cornerRadius > 0 ? Math.min(8, Style.cornerRadius) : 6
            color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.03)
            border.width: 1
            border.color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.08)

            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              spacing: Style.space(8)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "Auto power-saver at " + root.powerSaverThreshold + "%"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                width: parent.width - saverCycleBtn.width - Style.space(8)
              }

              Button {
                id: saverCycleBtn
                anchors.verticalCenter: parent.verticalCenter
                text: root.autoSaverEngaged ? "Active" : (root.powerSaverThreshold + "%")
                fontSize: Style.font.caption
                foreground: root.autoSaverEngaged ? Commons.Color.urgent : root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.space(8)
                verticalPadding: Style.space(2)
                bordered: true
                active: root.autoSaverEngaged
                onClicked: {
                  var next = root.powerSaverThreshold === 50 ? 30 : (root.powerSaverThreshold === 30 ? 20 : 50)
                  root.updateSetting("powerSaverThreshold", next)
                }
              }
            }
          }
        }
      }
    }
  }

  component MetricTile: Rectangle {
    property string label: ""
    property string value: ""
    property string detail: ""
    property color accentValue: root.bar.foreground

    height: Style.space(52)
    radius: Style.cornerRadius > 0 ? Math.min(8, Style.cornerRadius) : 6
    color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.04)
    border.width: 1
    border.color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.08)

    Column {
      anchors.fill: parent
      anchors.margins: Style.space(6)
      spacing: Style.space(2)

      Text {
        textFormat: Text.PlainText
        text: label
        color: Qt.darker(root.bar.foreground, 1.45)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption - 1
        font.bold: true
        font.letterSpacing: 0.5
      }

      Text {
        textFormat: Text.PlainText
        text: value
        color: accentValue
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Text {
        textFormat: Text.PlainText
        text: detail
        color: Qt.darker(root.bar.foreground, 1.3)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption - 1
        elide: Text.ElideRight
        width: parent.width
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    Text {
      textFormat: Text.PlainText
      color: root.bar.foreground
      opacity: 0.6
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.caption
      text: label
    }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    Text {
      textFormat: Text.PlainText
      color: root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.caption
      text: value
    }
  }
}
