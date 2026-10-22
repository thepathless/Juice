import QtQuick
import qs.Commons

// SECTION CARD — one collapsed-or-open section of the panel.
//
// Every top-level section of the dashboard is one of these: a header carrying
// the section's name and its most useful number on the right, with the
// section's own content underneath. Collapsible cards add a chevron and unfold
// in place; fixed cards (`collapsible: false`) always show their body and drop
// the toggle affordance entirely.
//
// Pure view: the open/closed decision belongs to the caller, which also owns
// the state the summary is built from. This file stores nothing.
Item {
  id: section

  property string title: ""
  // The number the section is worth opening for ("80%", "84% health", "3
  // devices"). Empty means the header carries only its title.
  property string summary: ""
  property bool expanded: false
  // A fixed section is always open and looks nothing like a disclosure row:
  // no chevron, no hover tint and no tap target. The caller still owns the
  // body, so a fixed card is just the same frame with the toggle removed.
  property bool collapsible: true
  property color foreground: "#ffffff"
  property string fontFamily: ""

  // Content declared inside this card lands in the body column.
  default property alias content: bodyColumn.data

  signal toggled()

  width: parent ? parent.width : 0
  implicitHeight: header.height + body.height
  height: implicitHeight

  Rectangle {
    id: header

    width: section.width
    // OptionRow's height: the collapsed panel is a stack of identical rows.
    height: Style.space(34)
    radius: Style.cornerRadius > 0 ? Math.min(8, Style.cornerRadius) : 6
    // An open section reads as the active one, the way a device row does.
    color: Qt.rgba(section.foreground.r, section.foreground.g, section.foreground.b,
      section.expanded ? 0.07 : (section.collapsible && headerArea.containsMouse ? 0.05 : 0.03))
    border.width: 1
    border.color: Qt.rgba(section.foreground.r, section.foreground.g, section.foreground.b,
      section.expanded ? 0.18 : 0.08)

    Text {
      id: headerTitle
      anchors.left: parent.left
      anchors.leftMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      // Leave the summary its room: a long section name goes to the middle
      // rather than drawing under the value it summarises.
      anchors.right: headerSummary.left
      anchors.rightMargin: Style.space(8)
      textFormat: Text.PlainText
      text: section.title
      color: section.foreground
      opacity: section.expanded ? 1.0 : 0.8
      font.family: section.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 0.6
      elide: Text.ElideRight
    }

    Text {
      id: headerSummary
      anchors.right: section.collapsible ? headerChevron.left : parent.right
      anchors.rightMargin: section.collapsible ? Style.space(6) : Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      visible: section.summary !== ""
      text: section.summary
      color: section.foreground
      opacity: 0.55
      font.family: section.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    Text {
      id: headerChevron
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: section.expanded ? "󰅃" : "󰅀"
      visible: section.collapsible
      color: section.foreground
      opacity: 0.45
      font.family: section.fontFamily
      font.pixelSize: Style.font.caption
    }

    MouseArea {
      id: headerArea
      anchors.fill: parent
      enabled: section.collapsible
      hoverEnabled: section.collapsible
      cursorShape: section.collapsible ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: section.toggled()
    }
  }

  Item {
    id: body

    anchors.top: header.bottom
    width: section.width
    // Collapsed is a real zero: the section takes no vertical space, and the
    // dashboards below move up instead of leaving a gap.
    height: section.expanded ? bodyColumn.implicitHeight + Style.space(8) : 0
    clip: true
    opacity: section.expanded ? 1.0 : 0.0

    Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }

    Column {
      id: bodyColumn
      anchors.top: parent.top
      anchors.topMargin: Style.space(8)
      width: parent.width
      spacing: Style.space(8)
    }
  }
}
