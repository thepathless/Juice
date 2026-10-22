import QtQuick
import qs.Commons
import "Model.js" as Model

// USAGE BY APP — the iOS battery screen's per-app rows. Each row names the app,
// states whether its percentage is a share of battery used or CPU activity, and
// shows the focused time it could measure. A zero or absent focus measurement
// prints an em dash; it never masquerades as "0m of use".
//
// Pure view: ordering, thresholds and the basis wording come from the report;
// the panel decides how many rows to pass and owns the section header.
Column {
  id: section

  property var apps: []
  property string note: ""
  property color foreground: "#ffffff"
  property string fontFamily: ""

  width: parent ? parent.width : 0
  spacing: Style.space(6)
  visible: apps.length > 0 || note !== ""

  Text {
    textFormat: Text.PlainText
    width: parent.width
    visible: section.note !== ""
    text: section.note
    color: section.foreground
    opacity: 0.55
    font.family: section.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Rectangle {
    visible: section.apps.length > 0
    width: parent.width
    radius: Style.cornerRadius > 0 ? Math.min(6, Style.cornerRadius) : 6
    color: Qt.rgba(section.foreground.r, section.foreground.g, section.foreground.b, 0.03)
    border.width: 1
    border.color: Qt.rgba(section.foreground.r, section.foreground.g, section.foreground.b, 0.08)
    implicitHeight: appColumn.implicitHeight + Style.space(12)

    Column {
      id: appColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(6)
      spacing: 0

      Repeater {
        model: section.apps

        Item {
          required property var modelData
          required property int index
          width: parent ? parent.width : 0
          height: Style.space(40)

          Column {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(4)
            anchors.right: appRight.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: Model.appLabel(modelData.name)
              color: section.foreground
              font.family: section.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            // Every percentage is a share of something specific; the row says
            // which measurement it came from instead of relying on a caption.
            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: modelData.basis || ""
              color: section.foreground
              opacity: 0.5
              font.family: section.fontFamily
              font.pixelSize: Style.font.caption - 1
              elide: Text.ElideRight
            }
          }

          Row {
            id: appRight
            anchors.right: parent.right
            anchors.rightMargin: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Text {
              textFormat: Text.PlainText
              // Focus time is unmeasured, not zero use, when no window held
              // focus long enough to record it.
              text: modelData.seconds > 0 ? Model.formatSpan(modelData.seconds) : "—"
              color: section.foreground
              opacity: 0.5
              font.family: section.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              textFormat: Text.PlainText
              text: Model.formatPercent(modelData.pct)
              color: section.foreground
              font.family: section.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          Rectangle {
            visible: index < section.apps.length - 1
            anchors.left: parent.left
            anchors.leftMargin: Style.space(4)
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: Qt.rgba(section.foreground.r, section.foreground.g, section.foreground.b, 0.08)
          }
        }
      }
    }
  }
}
