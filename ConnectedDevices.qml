import QtQuick
import qs.Commons
import "Model.js" as Model

// CONNECTED DEVICES — one tappable row per battery the system reports, each
// opening a drop-down with every fact collected about it.
//
// Pure view: the panel owns the device list, the section header and which row
// is open, and passes this section primitives. Nothing here probes the system
// or stores state.
//
// The laptop pack is deliberately absent: it is not a connected device, and
// the hero already carries its level while BATTERY DETAIL carries its health,
// energy and vendor data. Listing it here printed the same charge a third time.
Column {
  id: section

  property var devices: []
  property string expandedId: ""
  property color foreground: "#ffffff"
  property string fontFamily: ""
  property color greenColor: "#30D158"
  property color redColor: "#FF453A"
  property int redBelow: 20
  signal toggled(string id)

  width: parent ? parent.width : 0
  spacing: 0

  Column {
    width: parent.width
    spacing: Style.space(4)

    Repeater {
      model: section.devices

      DeviceRow {
        required property var modelData
        width: parent ? parent.width : 0
        device: modelData
        expanded: section.expandedId === String(modelData.id)
        foreground: section.foreground
        fontFamily: section.fontFamily
        greenColor: section.greenColor
        redColor: section.redColor
        redBelow: section.redBelow
        onToggled: section.toggled(String(modelData.id))
      }
    }

    Text {
      textFormat: Text.PlainText
      width: parent.width
      visible: section.devices.length === 0
      text: "No battery-powered devices are connected"
      color: section.foreground
      opacity: 0.55
      font.family: section.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // One connected device: a tappable header plus the drop-down body holding
  // every battery fact the system reports for it. The open/closed decision
  // belongs to the panel (`expanded`), not to this row.
  component DeviceRow: Column {
    id: row

    property var device: ({})
    property bool expanded: false
    property color foreground: "#ffffff"
    property string fontFamily: ""
    property color greenColor: "#30D158"
    property color redColor: "#FF453A"
    property int redBelow: 20
    signal toggled()

    spacing: 0

    readonly property int level: Model.deviceLevel(device)
    readonly property color levelColor: Model.deviceLevelColor(
      device, row.foreground, row.greenColor, row.redColor, row.redBelow)

    Rectangle {
      width: row.width
      // A long product name wraps onto a second line rather than losing its
      // end, and the row grows to hold it.
      height: Math.max(Style.space(38), deviceText.implicitHeight + Style.space(10))
      radius: Style.cornerRadius > 0 ? Math.min(8, Style.cornerRadius) : 6
      color: Qt.rgba(row.foreground.r, row.foreground.g, row.foreground.b,
        row.expanded ? 0.07 : 0.03)
      border.width: 1
      border.color: Qt.rgba(row.foreground.r, row.foreground.g, row.foreground.b,
        row.expanded ? 0.18 : 0.08)

      Text {
        id: deviceIcon
        anchors.left: parent.left
        anchors.leftMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: Model.kindIcon(row.device.kind, row.device.bt ? row.device.bt.icon : "")
        color: row.levelColor
        font.family: row.fontFamily
        font.pixelSize: Style.font.title
      }

      Column {
        id: deviceText
        anchors.left: deviceIcon.right
        anchors.leftMargin: Style.space(8)
        // Stop where the level starts: the name wraps inside its own column
        // instead of being drawn underneath "Not reported".
        anchors.right: deviceLevel.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: row.device.name || ""
          color: row.foreground
          font.family: row.fontFamily
          font.pixelSize: Style.font.bodySmall
          // Two lines hold any real product name; beyond that the middle goes,
          // not the tail, so "...Device" and "...Pro" stay distinguishable.
          wrapMode: Text.WordWrap
          maximumLineCount: 2
          elide: Text.ElideMiddle
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: Model.deviceSubtitle(row.device)
          color: row.foreground
          opacity: 0.55
          font.family: row.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        id: deviceLevel
        anchors.right: deviceChevron.left
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        // A device that reports no level is listed and says so; it is never
        // dropped, never shown as 0%, and the laptop pack stays first.
        text: Model.deviceLevelLabel(row.device)
        color: row.level >= 0 ? row.levelColor : row.foreground
        opacity: row.level >= 0 ? 1 : 0.5
        font.family: row.fontFamily
        font.pixelSize: row.level >= 0 ? Style.font.bodySmall : Style.font.caption - 1
        font.bold: row.level >= 0
      }

      Text {
        id: deviceChevron
        anchors.right: parent.right
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: row.expanded ? "󰅃" : "󰅀"
        color: row.foreground
        opacity: 0.45
        font.family: row.fontFamily
        font.pixelSize: Style.font.caption
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: row.toggled()
      }
    }

    Item {
      width: row.width
      height: row.expanded ? detailBody.implicitHeight + Style.space(16) : 0
      visible: row.expanded

      Rectangle {
        anchors.fill: parent
        radius: Style.cornerRadius > 0 ? Math.min(6, Style.cornerRadius) : 6
        color: Qt.rgba(row.foreground.r, row.foreground.g, row.foreground.b, 0.02)
        border.width: 1
        border.color: Qt.rgba(row.foreground.r, row.foreground.g, row.foreground.b, 0.07)
      }

      Column {
        id: detailBody
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.space(8)
        spacing: Style.space(6)

        Repeater {
          model: Model.deviceDetailGroups(row.device)

          Column {
            required property var modelData
            width: parent ? parent.width : 0
            spacing: 0

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: modelData.title
              color: row.foreground
              opacity: 0.5
              font.family: row.fontFamily
              font.pixelSize: Style.font.caption - 1
              font.bold: true
              font.letterSpacing: 0.6
            }

            Repeater {
              model: modelData.rows

              DetailRow {
                required property var modelData
                label: modelData.label
                value: modelData.value
                showDivider: !modelData.last
                foreground: row.foreground
                fontFamily: row.fontFamily
              }
            }
          }
        }
      }
    }
  }
}
