// Bound component behaviour so the inline Digits/Bolt components can read the
// glyph's own properties (root.*) instead of re-plumbing every one of them.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Commons as Commons

// Apple's battery indicator in two silhouettes — outlined and iOS 27
// borderless — each of which changes shape when the percentage moves inside
// the body. The `silhouette` record holds the resolved geometry; the drawing
// code reads it and never re-derives a style or a mode.
//
//   outlined, no digits   SF Symbols body 1.947 H, 0.330 H corner, 0.135 H
//                         stroke, level inset 0.181 H
//   outlined, digits      the same body with the stroke dropped and the fill
//                         flush to the edge, because the digits sit in the fill
//   borderless            reference body 1.829 H with the digits, 1.923 H
//                         without, one 12 px corner, no stroke
//
// The terminal is a 0.401 H circle (outlined) or 15 px circle (borderless)
// behind a narrow clipped window. The charging bolt is 0.95 H tall in the
// body and 0.70 H beside the digits, knocked out of the fill by a 0.072 H
// halo in the first case. Digits are drawn in plain ink while charging, full
// or in power-saver mode, and twice otherwise — bar ink over the empty track,
// cut-out ink over the fill, each copy clipped to its own side of the fill's
// leading edge.
Item {
  id: root

  property real level: 100
  property bool charging: false
  // iOS 27 style: no stroke, the body itself is the track.
  property bool borderless: false
  property color color: Commons.Color.foreground
  property color contentColor: Commons.Color.foreground
  property color cutoutColor: Commons.Color.background
  property real iconSize: Style.font.icon
  property bool showPercentage: false
  // Digits are a hole in the icon only while discharging normally; charging,
  // critical and power-saver states draw solid digits instead.
  property bool knockoutText: false
  property string percentageText: level >= 0 ? String(Math.round(level)) : ""
  property string fontFamily: ""

  readonly property bool percentMode: showPercentage && percentageText !== ""
  readonly property bool isFull: level >= 100

  // ---- silhouette ---------------------------------------------------------
  readonly property real bodyHeight: Math.max(8, iconSize)
  // One table, one decision: style x mode is resolved here and nowhere else.
  // Every consumer — body path, stroke, inset, fill, terminal, digits — reads
  // this record, so the four combinations cannot drift apart.
  //
  // Outlined ratios are measured from Apple's SF Symbols exports
  // (battery.0/25/50/75/100percent): 1.947 H body, 0.330 H corner, 0.135 H
  // stroke centred on its path, the level inset 0.181 H, and a 0.401 H
  // terminal behind a 0.163 H window 0.057 H clear of the body.
  //
  // Borderless ratios come from the reference widget
  // (runoob-coder/ios_battery_indicator 2.0.1): 75 x 41 with the percentage and
  // 75 x 39 without, one 12 px corner (0.293 / 0.308 H), no stroke, the body
  // itself carrying the translucent track, and a 15 px terminal behind a 6 px
  // window 2 px clear of the body (0.366 / 0.146 / 0.049 H with the
  // percentage, 0.385 / 0.154 / 0.051 H without). The mission's "27 x 13.5"
  // note implies a 2.0 aspect, but the reference is the implementation this
  // style is copied from, so its numbers win.
  readonly property var silhouette: {
    var h = bodyHeight
    var shape
    if (borderless) {
      shape = percentMode
        ? { width: 1.829, radius: 0.293, stroke: 0, inset: 0, pole: 0.366, gap: 0.049, window: 0.146 }
        : { width: 1.923, radius: 0.308, stroke: 0, inset: 0, pole: 0.385, gap: 0.051, window: 0.154 }
    } else if (percentMode) {
      shape = { width: 1.947, radius: 0.330, stroke: 0, inset: 0, pole: 0.401, gap: 0.057, window: 0.163 }
    } else {
      shape = { width: 1.947, radius: 0.330, stroke: 0.135, inset: 0.181, pole: 0.401, gap: 0.057, window: 0.163 }
    }
    var width = shape.width * h
    var radius = shape.radius * h
    var stroke = shape.stroke > 0 ? Math.max(1, shape.stroke * h) : 0
    var inset = shape.inset * h
    var steps = Math.max(8, Math.min(32, Math.round(radius * 3)))
    // The stroke is centred on its path, so the painted outline is inset by
    // half a stroke: it then ends exactly on width x height, the way Apple's
    // glyph measures.
    var body = stroke > 0
      ? root.superellipsePoints(width - stroke, h - stroke,
          Math.max(1, radius - stroke / 2), steps, stroke / 2, stroke / 2)
      : root.superellipsePoints(width, h, radius, steps)
    var filled = percentMode || borderless
    return {
      width: width,
      height: h,
      stroke: stroke,
      inset: inset,
      pole: shape.pole * h,
      poleGap: shape.gap * h,
      poleVisible: shape.window * h,
      filled: filled,
      bodyPoints: body,
      fillPoints: filled
        ? body
        : root.superellipsePoints(
            Math.max(0.5, width - inset * 2), Math.max(0.5, h - inset * 2),
            Math.max(1, radius - stroke), steps, inset, inset)
    }
  }

  readonly property real fraction: Math.max(0, Math.min(1, level / 100))
  // Apple's 0 % symbol is empty; anything above it keeps a whole pixel so a
  // 1 % reading cannot disappear into antialiasing.
  readonly property real fillWidth: level <= 0
    ? 0
    : Math.max(1, (silhouette.filled ? silhouette.width : silhouette.width - silhouette.inset * 2) * fraction)

  // Dark appearance values: the track is the bar foreground at 40 %, the level
  // is the solid state colour.
  readonly property color trackColor: Qt.rgba(contentColor.r, contentColor.g, contentColor.b, 0.4)
  // The terminal follows the track while the body is filled and the state
  // colour on the outlined glyph, which paints the terminal with the fill. A
  // full pill keeps the state colour here; the reference greys it out.
  readonly property color poleColor: silhouette.filled
    ? (isFull ? color : trackColor)
    : color
  // Solid digits need ink that contrasts with the fill, and Apple's yellow is
  // light enough to need black.
  readonly property color plainTextColor: {
    var luma = 0.299 * root.color.r + 0.587 * root.color.g + 0.114 * root.color.b
    return luma > 0.72 ? "#000000" : root.contentColor
  }

  implicitWidth: Math.round(silhouette.width + silhouette.poleGap + silhouette.poleVisible)
  implicitHeight: Math.round(bodyHeight)

  // ---- geometry -----------------------------------------------------------
  // Points of a rounded rectangle whose corners are quarter superellipses
  // (|x|^n + |y|^n = r^n). Fitting Apple's exported glyph at three depths below
  // the top edge gives n = 2.25 (a circle fits 8 px worse, a n = 4 squircle
  // 20 px worse), which is the continuous corner iOS 26+ draws.
  function superellipsePoints(width, height, radius, steps, dx, dy) {
    var n = 2.25
    var ox = dx === undefined ? 0 : dx
    var oy = dy === undefined ? 0 : dy
    var r = Math.max(0.5, Math.min(radius, Math.min(width, height) / 2))
    var pts = []
    // Perimeter order, and each corner sweeps from the edge it enters to the
    // edge it leaves: TL (left -> top), TR (top -> right), BR (right ->
    // bottom), BL (bottom -> left). Sweeping all four the same way instead
    // draws the four corner arcs joined by diagonals — a star, not a box.
    var corners = [
      { cx: r, cy: r, sx: -1, sy: -1, from: 0, to: 1 },
      { cx: width - r, cy: r, sx: 1, sy: -1, from: 1, to: 0 },
      { cx: width - r, cy: height - r, sx: 1, sy: 1, from: 0, to: 1 },
      { cx: r, cy: height - r, sx: -1, sy: 1, from: 1, to: 0 }
    ]
    for (var c = 0; c < 4; c++) {
      var k = corners[c]
      for (var i = 0; i <= steps; i++) {
        var t = (k.from + (k.to - k.from) * (i / steps)) * Math.PI / 2
        // Qt.point, not {x, y}: a bare object array does not convert to a
        // point list, and PathPolyline then silently draws nothing.
        pts.push(Qt.point(
          ox + k.cx + k.sx * r * Math.pow(Math.cos(t), 2 / n),
          oy + k.cy + k.sy * r * Math.pow(Math.sin(t), 2 / n)))
      }
    }
    // The four corners run left→top→right→bottom→left, so the last point is
    // already home; repeating it makes the left edge an explicit segment. An
    // unclosed PathPolyline still fills (fills close implicitly) but its
    // stroke stops at the bottom-left corner, leaving the outline open along
    // the whole left side.
    if (pts.length > 0) pts.push(pts[0])
    return pts
  }

  // ---- terminal -----------------------------------------------------------
  // Apple draws the terminal as a circle of which only the protruding slice
  // shows: a 0.401 H circle clipped to 0.163 H is 0.401 H tall, which is what
  // the exported glyph measures.
  Item {
    x: root.silhouette.width + root.silhouette.poleGap
    width: root.silhouette.poleVisible
    height: root.bodyHeight
    clip: true

    Rectangle {
      x: -(root.silhouette.pole - root.silhouette.poleVisible)
      y: Math.round((root.bodyHeight - height) / 2)
      width: root.silhouette.pole
      height: root.silhouette.pole
      radius: root.silhouette.pole / 2
      color: root.poleColor

      Behavior on color { ColorAnimation { duration: 220 } }
    }
  }

  // ---- body / track -------------------------------------------------------
  Shape {
    width: root.silhouette.width
    height: root.silhouette.height
    antialiasing: true
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeWidth: root.silhouette.stroke
      // The glyph is one colour: while charging Apple paints the outline green
      // with the fill, so the stroke follows the state colour, not the theme
      // foreground.
      strokeColor: root.silhouette.stroke > 0 ? root.color : "transparent"
      fillColor: root.silhouette.filled ? root.trackColor : "transparent"
      PathPolyline { path: root.silhouette.bodyPoints }

      Behavior on fillColor { ColorAnimation { duration: 220 } }
      Behavior on strokeColor { ColorAnimation { duration: 220 } }
    }
  }

  // ---- level fill ---------------------------------------------------------
  // A rectangular clip does the cutting, so the fill's leading edge is always
  // straight and no vertex is ever collapsed onto another.
  Item {
    id: fillClip
    width: Math.min(root.silhouette.width, root.silhouette.inset + root.fillWidth)
    height: root.bodyHeight
    clip: true
    // A zero-width clip can still leave a sliver of the shape it clips, and an
    // empty battery must paint no fill at all (Apple's battery.0percent).
    visible: root.fillWidth > 0

    Shape {
      width: root.silhouette.width
      height: root.silhouette.height
      antialiasing: true
      preferredRendererType: Shape.CurveRenderer

      ShapePath {
        strokeWidth: 0
        fillColor: root.color
        PathPolyline { path: root.silhouette.fillPoints }

        Behavior on fillColor { ColorAnimation { duration: 220 } }
      }
    }

    // The reference tweens the level with easeOutCubic over 80 % of its
    // 250 ms animation duration.
    Behavior on width {
      NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
    }
  }

  // ---- contents ----------------------------------------------------------
  readonly property bool boltInPercent: root.percentMode && root.charging && !root.isFull
  readonly property bool boltInGlyph: !root.percentMode && root.charging && !root.isFull
  // Apple's charging symbol runs the bolt taller than the body and lets it
  // break the top and bottom edges by 0.017 H each (measured from
  // battery.100percent.bolt.svg: bolt 37.86 units against a 36.54 unit body),
  // with a halo knocked out of the fill. The percentage style draws a smaller
  // bolt beside the digits instead.
  readonly property real boltHeight: Math.round(root.bodyHeight * (root.percentMode ? 0.70 : 1.034))
  readonly property real boltWidth: Math.round(root.boltHeight * 10 / 16)
  readonly property real boltGap: Math.max(1, Math.round(root.bodyHeight * 0.06))
  readonly property real boltHalo: root.percentMode ? 0 : Math.max(1, Math.round(root.bodyHeight * 0.072))

  // One set of digits, drawn twice: once in the bar's own ink for the empty
  // track, once in the colour a hole in the fill would reveal. Both copies
  // sit at the same position and each is clipped to its own side of the
  // fill's leading edge, so a digit that straddles the edge is half hole,
  // half ink — how iOS renders the percentage. A single flat colour cannot
  // do that: at most levels the fill edge lands inside a glyph, and whichever
  // ink is picked is wrong for the other half of it.
  component Digits: Item {
    id: digitsRoot
    property color ink: "#ffffff"

    width: root.silhouette.width
    height: root.silhouette.height

    Text {
      id: label
      x: 0
      y: 0
      height: root.bodyHeight
      // Reserve the bolt's column while charging so the digits stay optically
      // centred as a pair instead of sliding under the bolt.
      width: root.silhouette.width - (root.boltInPercent ? root.boltWidth + root.boltGap : 0)
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      textFormat: Text.PlainText
      text: root.percentageText
      wrapMode: Text.NoWrap
      // Shrink the font instead of scaling the item: a real pixel size keeps
      // the glyphs hinted, a transform on the text turns them to mush.
      fontSizeMode: Text.HorizontalFit
      minimumPixelSize: 6
      // A monospaced digit is 0.6 em wide where SF Pro's is 0.556 em, so the
      // reference's "font size == body height" ratio is scaled by that factor
      // to keep three digits inside the pill at the same optical weight.
      font.pixelSize: Math.max(6, Math.round(root.bodyHeight * 0.9))
      font.bold: true
      font.family: root.fontFamily
      color: digitsRoot.ink

      Behavior on color { ColorAnimation { duration: 160 } }
    }

    Bolt {
      visible: root.boltInPercent
      x: label.width + root.boltGap
      anchors.verticalCenter: parent.verticalCenter
      boltHeight: root.boltHeight
      haloWidth: 0
      color: digitsRoot.ink
    }
  }

  // Plain style — charging, critical, power-saver: solid ink over the whole
  // body, because a hole in a green/red/yellow pill would not read.
  Digits {
    visible: root.percentMode && !root.knockoutText
    ink: root.plainTextColor
  }

  // Cutout style: the same digits, split at the fill's leading edge.
  Item {
    visible: root.percentMode && root.knockoutText
    x: root.fillWidth
    width: Math.max(0, root.silhouette.width - root.fillWidth)
    height: root.silhouette.height
    clip: true

    Digits { x: -root.fillWidth; ink: root.contentColor }
  }

  Item {
    visible: root.percentMode && root.knockoutText
    width: root.fillWidth
    height: root.silhouette.height
    clip: true

    Digits { ink: root.cutoutColor }
  }

  Bolt {
    visible: root.boltInGlyph
    anchors.centerIn: parent
    boltHeight: root.boltHeight
    haloWidth: root.boltHalo
    haloColor: root.cutoutColor
    color: root.color
  }

  // Apple's bolt glyph: the 10 x 16 path the reference implementation ships,
  // which is the shape inside SF Symbols' battery.100percent.bolt.
  component Bolt: Item {
    id: boltRoot
    property real boltHeight: 16
    property color color: "#ffffff"
    // A halo in the background colour reproduces Apple knocking the bolt out
    // of the fill. The bolt and the digits are fully opaque: no breathing
    // animation, so the charging readout stays steady at a glance.
    property real haloWidth: 0
    property color haloColor: "transparent"

    width: Math.round(boltHeight * 10 / 16)
    height: boltHeight

    Shape {
      width: 10
      height: 16
      antialiasing: true
      transform: Scale {
        origin.x: 0
        origin.y: 0
        xScale: boltRoot.width / 10
        yScale: boltRoot.height / 16
      }

      ShapePath {
        strokeWidth: boltRoot.haloWidth / (boltRoot.width / 10)
        strokeColor: boltRoot.haloColor
        fillColor: boltRoot.color
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        startX: 0
        startY: 8.92
        PathCubic { control1X: 0; control1Y: 9.15; control2X: 0.18; control2Y: 9.33; x: 0.45; y: 9.33 }
        PathLine { x: 4.59; y: 9.33 }
        PathLine { x: 2.40; y: 15.27 }
        PathCubic { control1X: 2.15; control1Y: 15.92; control2X: 2.82; control2Y: 16.26; x: 3.25; y: 15.73 }
        PathLine { x: 9.84; y: 7.49 }
        PathCubic { control1X: 9.95; control1Y: 7.35; control2X: 10.01; control2Y: 7.22; x: 10.01; y: 7.07 }
        PathCubic { control1X: 10.01; control1Y: 6.84; control2X: 9.84; control2Y: 6.65; x: 9.57; y: 6.65 }
        PathLine { x: 5.43; y: 6.65 }
        PathLine { x: 7.61; y: 0.73 }
        PathCubic { control1X: 7.86; control1Y: 0.07; control2X: 7.19; control2Y: -0.27; x: 6.76; y: 0.27 }
        PathLine { x: 0.17; y: 8.50 }
        PathCubic { control1X: 0.06; control1Y: 8.64; control2X: 0; control2Y: 8.77; x: 0; y: 8.92 }
      }
    }
  }
}
