import QtQuick
import qs.Commons

// One real row of an inset card: label left, value right, hairline separator
// underneath. Fixed height keeps tabbed cards interchangeable, and a missing
// hardware attribute is printed as "—" by the caller instead of collapsing the
// row. Colours and family are explicit because the bar theme, not this file,
// decides them.
Item {
  id: row

  property string label: ""
  property string value: ""
  property bool showDivider: true
  property color foreground: "#ffffff"
  property string fontFamily: ""

  width: parent ? parent.width : 0
  // UITableView's default 44 pt row at this card's 0.588 scale.
  height: Style.space(26)

  // The label takes exactly the width its glyphs need and is never elided:
  // a caption cut to "Charge thresho…" is a defect, not a layout trade-off.
  Text {
    id: rowLabel
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: implicitWidth
    textFormat: Text.PlainText
    text: row.label
    color: row.foreground
    opacity: 0.62
    font.family: row.fontFamily
    font.pixelSize: Style.font.caption
    elide: Text.ElideNone
  }

  // The value gets the rest of the row and is never elided either; the strings
  // these cards hold are short enough to fit that width whole.
  Text {
    id: rowValue
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: Math.max(0, parent.width - rowLabel.width - Style.space(8))
    textFormat: Text.PlainText
    text: row.value
    horizontalAlignment: Text.AlignRight
    elide: Text.ElideNone
    color: row.foreground
    font.family: row.fontFamily
    font.pixelSize: Style.font.caption
  }

  Rectangle {
    visible: row.showDivider
    // UIKit starts a list separator at the text's leading edge (16 pt at
    // 17 pt body, 9 pt here), not at the card edge.
    anchors.left: parent.left
    anchors.leftMargin: Style.space(9)
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: 1
    color: Qt.rgba(row.foreground.r, row.foreground.g, row.foreground.b, 0.08)
  }
}
