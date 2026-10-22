import QtQuick
import "Model.js" as Model

// The session keys are plain letters while the panel is open, so they never
// disturb Omarchy's Super+L / Super+S shortcuts. This transparent layer sits
// inside the shared PanelKeyCatcher with keyboard focus: keys it does not
// claim are left unaccepted and propagate to the parent exactly as before.
//
// H and L already mean left/right for the profile picker. A short tap keeps
// that behaviour; holding either past the tap threshold turns it into the
// session hold instead, so no existing keyboard path is lost.
Item {
  id: root

  property var actions: []

  // The action whose three-second hold is being tracked by the panel.
  signal holdStarted(string id)
  signal holdEnded(string id)
  // A quick H/L tap, preserving PanelKeyCatcher's vim-style movement.
  signal horizontalMove(int direction)

  readonly property int tapThreshold: 180

  property string pendingKey: ""
  property string pendingId: ""
  property string heldKey: ""
  property string heldId: ""

  function eventText(event) {
    if (event.text && event.text.length === 1) return event.text.toLowerCase()
    // Key releases may arrive without text; recover the letter or digit from
    // the key code so a release still cancels the hold that the press began.
    if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z)
      return String.fromCharCode(event.key).toLowerCase()
    if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9)
      return String.fromCharCode(event.key)
    return ""
  }

  function cancelTap() {
    tapTimer.stop()
    pendingKey = ""
    pendingId = ""
  }

  function cancelHold() {
    tapTimer.stop()
    pendingKey = ""
    pendingId = ""
    if (heldId !== "") {
      const id = heldId
      heldKey = ""
      heldId = ""
      root.holdEnded(id)
    }
  }

  function startHold(key, id) {
    cancelHold()
    heldKey = key
    heldId = id
    root.holdStarted(id)
  }

  focus: true
  Keys.priority: Keys.BeforeItem
  Keys.onPressed: function(event) {
    var key = eventText(event)
    if (key === "") return

    var action = Model.sessionActionForKey(key, root.actions)
    if (!action) {
      // Any unrelated key ends a pending/active hold, then continues to the
      // panel untouched (arrows, Enter, Tab, Escape, j/k).
      if (pendingId !== "" || heldId !== "") cancelHold()
      return
    }

    if (event.isAutoRepeat) {
      event.accepted = true
      return
    }

    event.accepted = true
    cancelTap()

    // H and L double as the horizontal movement keys. Delay those two letters
    // briefly so a tap still moves the cursor; S/R/Z and the number aliases
    // have no other role and begin their hold immediately.
    if (key === "h" || key === "l") {
      if (heldId !== "") cancelHold()
      pendingKey = key
      pendingId = action.id
      tapTimer.restart()
    } else {
      startHold(action.holdKey.toLowerCase(), action.id)
    }
  }

  Keys.onReleased: function(event) {
    // Auto-repeat synthesises release/press pairs. Treating the synthetic
    // release as a real one cancelled every hold a few hundred milliseconds
    // after it began, exactly when the keyboard started repeating.
    if (event.isAutoRepeat) {
      event.accepted = true
      return
    }

    var key = eventText(event)
    if (key === "") return

    if (pendingKey === key) {
      // Released inside the tap window: this was the existing H/L movement,
      // not a session hold.
      cancelTap()
      root.horizontalMove(key === "l" ? 1 : -1)
      event.accepted = true
      return
    }

    if (heldKey === key) {
      const id = heldId
      heldKey = ""
      heldId = ""
      root.holdEnded(id)
      event.accepted = true
    }
  }

  onActiveFocusChanged: if (!activeFocus) cancelHold()
  onActionsChanged: {
    if (heldId !== "" && !Model.sessionActionById(heldId)) cancelHold()
  }

  Timer {
    id: tapTimer
    interval: root.tapThreshold
    repeat: false
    onTriggered: {
      if (root.pendingId === "") return
      const key = root.pendingKey
      const id = root.pendingId
      root.pendingKey = ""
      root.pendingId = ""
      root.heldKey = key
      root.heldId = id
      root.holdStarted(id)
    }
  }
}
