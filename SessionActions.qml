pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Commons as Commons

// The five session actions, as one compact strip. This file is a view: it
// knows nothing about timers or commands. Pressing a tile starts a hold in the
// panel; releasing it ends that hold. The panel decides whether the hold has
// lasted long enough to run anything.
Item {
  id: root

  property var actions: []
  // The panel owns the timer; the countdown follows the same duration.
  property int holdMs: 3000
  property string holdingId: ""
  property real holdProgress: 0
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family
  property color accentColor: Commons.Color.accent
  property color urgentColor: Commons.Color.urgent

  signal holdStarted(string id)
  signal holdEnded(string id)

  readonly property int gap: Style.space(4)
  readonly property int tileHeight: Style.space(62)

  implicitHeight: strip.height
  height: implicitHeight

  Row {
    id: strip
    width: parent.width
    spacing: root.gap

    Repeater {
      model: root.actions

      Rectangle {
        id: tile
        required property var modelData
        required property int index

        readonly property string actionId: modelData.id
        readonly property bool holding: root.holdingId === actionId
        readonly property int secondsLeft: Math.max(1, Math.ceil((1 - root.holdProgress) * root.holdMs / 1000))

        width: (strip.width - root.gap * Math.max(0, root.actions.length - 1)) / Math.max(1, root.actions.length)
        height: root.tileHeight
        radius: Style.cornerRadius > 0 ? Math.min(8, Style.cornerRadius) : 6
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b,
          holding ? 0.10 : (tileArea.containsMouse ? 0.07 : 0.03))
        border.width: 1
        border.color: holding
          ? (modelData.destructive ? root.urgentColor : root.accentColor)
          : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b,
            tileArea.containsMouse ? 0.18 : 0.08)

        Column {
          anchors.centerIn: parent
          width: parent.width - Style.space(4)
          spacing: Style.space(2)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: modelData.icon
            horizontalAlignment: Text.AlignHCenter
            color: holding ? (modelData.destructive ? root.urgentColor : root.accentColor) : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: modelData.label
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            color: root.foreground
            opacity: holding ? 1.0 : 0.82
            font.family: root.fontFamily
            // Five tiles across 338 px leave roughly 60 px each. At the
            // caption size the longest labels ellipsize ("Hibern.…",
            // "Shut d.…"); three steps smaller keeps both whole while leaving
            // the 20 px glyph as the visual anchor.
            font.pixelSize: Style.font.caption - 3
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            // The letter is the hold key; the number is the equally valid
            // shortcut. Both stay on the tile, so no footer is needed.
            text: holding ? secondsLeft + "s" : modelData.holdKey + " · " + (index + 1)
            horizontalAlignment: Text.AlignHCenter
            color: holding ? (modelData.destructive ? root.urgentColor : root.accentColor) : root.foreground
            opacity: holding ? 1.0 : 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption - 1
          }
        }

        // The fill is the hold clock made visible. It resets to zero on every
        // early release, so there is never a half-applied action.
        Rectangle {
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          anchors.margins: Style.space(2)
          width: Math.max(0, (parent.width - Style.space(4)) * (holding ? root.holdProgress : 0))
          height: Style.space(2)
          radius: height / 2
          color: modelData.destructive ? root.urgentColor : root.accentColor
        }

        MouseArea {
          id: tileArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onPressed: root.holdStarted(tile.actionId)
          onReleased: root.holdEnded(tile.actionId)
          onCanceled: root.holdEnded(tile.actionId)
          onExited: if (pressed) root.holdEnded(tile.actionId)
        }
      }
    }
  }

}
