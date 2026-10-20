import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Commons as Commons

Item {
  id: root

  property real level: 100
  property bool charging: false
  property bool holding: false
  property bool acOnline: false
  property color color: Commons.Color.foreground
  property real iconSize: Style.font.icon
  property real aspectRatio: 1.85
  property bool showBolt: true
  property bool pulseCharging: true

  width: Math.round(iconSize * aspectRatio)
  height: Math.round(iconSize)
  implicitWidth: width
  implicitHeight: height

  readonly property real terminalWidth: Math.max(2, Math.round(width * 0.08))
  readonly property real gap: Math.max(1, Math.round(width * 0.04))
  readonly property real shellWidth: width - terminalWidth - gap
  readonly property real shellHeight: height
  readonly property real shellRadius: Math.max(2.5, Math.round(shellHeight * 0.22))
  readonly property real shellBorderWidth: Math.max(1.2, Math.round(shellHeight * 0.09))

  readonly property real inset: shellBorderWidth + 1.2
  readonly property real innerMaxW: Math.max(0, shellWidth - inset * 2)
  readonly property real innerH: Math.max(0, shellHeight - inset * 2)
  readonly property real fillFraction: Math.max(0, Math.min(1, root.level / 100.0))
  readonly property real targetFillW: Math.max(0, Math.min(innerMaxW, innerMaxW * fillFraction))

  // Main battery shell
  Rectangle {
    id: shell
    x: 0
    y: 0
    width: root.shellWidth
    height: root.shellHeight
    radius: root.shellRadius
    color: "transparent"
    border.width: root.shellBorderWidth
    border.color: root.color

    Behavior on border.color { ColorAnimation { duration: 220 } }
  }

  // Battery terminal bump (positive pole)
  Rectangle {
    id: terminal
    x: shell.width + root.gap
    y: Math.round((shell.height - height) / 2)
    width: root.terminalWidth
    height: Math.max(4, Math.round(shell.height * 0.44))
    radius: Math.max(1, Math.round(width * 0.5))
    color: root.color
    opacity: 0.85

    Behavior on color { ColorAnimation { duration: 220 } }
  }

  // Inner level fill
  Rectangle {
    id: fill
    x: root.inset
    y: root.inset
    height: root.innerH
    width: root.targetFillW
    radius: Math.max(1, root.shellRadius - 1.2)
    color: root.color

    Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
    Behavior on color { ColorAnimation { duration: 220 } }

    SequentialAnimation on opacity {
      running: root.charging && root.pulseCharging
      loops: Animation.Infinite
      alwaysRunToEnd: true
      NumberAnimation { from: 1.0; to: 0.52; duration: 900; easing.type: Easing.InOutSine }
      NumberAnimation { from: 0.52; to: 1.0; duration: 900; easing.type: Easing.InOutSine }
    }
  }

  // Hardware limit marker line (e.g. 80% mark when holding)
  Rectangle {
    visible: root.holding && root.fillFraction >= 0.78
    x: Math.round(root.inset + root.innerMaxW * 0.8 - 0.5)
    y: root.inset
    width: 1
    height: root.innerH
    color: Commons.Color.background
    opacity: 0.85
  }

  // Vector lightning bolt when charging
  Shape {
    id: bolt
    visible: root.charging && root.showBolt
    anchors.fill: shell
    antialiasing: true
    layer.enabled: true
    layer.samples: 4

    readonly property real boltW: Math.max(5, Math.round(shell.width * 0.30))
    readonly property real boltH: Math.max(8, Math.round(shell.height * 0.70))
    readonly property real boltX: Math.round((shell.width - boltW) / 2)
    readonly property real boltY: Math.round((shell.height - boltH) / 2)

    ShapePath {
      // Invert color if fill covers the center so it acts as a cutout,
      // otherwise use primary color against dark background.
      fillColor: root.fillFraction >= 0.5 ? Commons.Color.background : root.color
      strokeWidth: 0
      startX: bolt.boltX + bolt.boltW * 0.56
      startY: bolt.boltY
      PathLine { x: bolt.boltX + bolt.boltW * 0.16; y: bolt.boltY + bolt.boltH * 0.54 }
      PathLine { x: bolt.boltX + bolt.boltW * 0.48; y: bolt.boltY + bolt.boltH * 0.54 }
      PathLine { x: bolt.boltX + bolt.boltW * 0.32; y: bolt.boltY + bolt.boltH }
      PathLine { x: bolt.boltX + bolt.boltW * 0.86; y: bolt.boltY + bolt.boltH * 0.44 }
      PathLine { x: bolt.boltX + bolt.boltW * 0.52; y: bolt.boltY + bolt.boltH * 0.44 }
      PathLine { x: bolt.boltX + bolt.boltW * 0.70; y: bolt.boltY }
      PathLine { x: bolt.boltX + bolt.boltW * 0.56; y: bolt.boltY }
    }
  }
}
