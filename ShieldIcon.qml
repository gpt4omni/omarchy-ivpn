import QtQuick
import QtQuick.Shapes
import qs.Commons

Item {
  id: root
  property real iconSize: Style.font.icon
  property color color: Color.foreground
  property color indicatorColor: Color.foreground
  property color dimColor: Util.alpha(indicatorColor, 0.55)
  property color badgeColor: Color.urgent
  property color backgroundColor: Color.popups.background
  property string fontFamily: Style.font.family
  // connected | disconnected | connecting | paused | urgent
  property string status: "disconnected"
  property bool pulse: false
  readonly property string visualStatus: ["connected", "disconnected", "connecting", "paused", "urgent"].indexOf(status) !== -1
    ? status : "urgent"
  readonly property real statusSize: Math.max(7, root.iconSize * 0.44)

  width: iconSize * 1.12
  height: iconSize
  implicitWidth: width
  implicitHeight: height

  // Code-native crisp shield mark: zero icon-font or proprietary asset dependency.
  Shape {
    id: shieldMark
    anchors.fill: parent
    antialiasing: true
    layer.enabled: true
    layer.samples: 4

    ShapePath {
      fillColor: root.color
      strokeWidth: 0
      startX: root.width * 0.50
      startY: root.height * 0.08
      PathLine { x: root.width * 0.88; y: root.height * 0.22 }
      PathLine { x: root.width * 0.88; y: root.height * 0.48 }
      PathCubic {
        x: root.width * 0.50; y: root.height * 0.92
        control1X: root.width * 0.88; control1Y: root.height * 0.72
        control2X: root.width * 0.68; control2Y: root.height * 0.86
      }
      PathCubic {
        x: root.width * 0.12; y: root.height * 0.48
        control1X: root.width * 0.32; control1Y: root.height * 0.86
        control2X: root.width * 0.12; control2Y: root.height * 0.72
      }
      PathLine { x: root.width * 0.12; y: root.height * 0.22 }
      PathLine { x: root.width * 0.50; y: root.height * 0.08 }
    }

    ShapePath {
      fillColor: "transparent"
      strokeColor: root.backgroundColor
      strokeWidth: Math.max(1.1, root.iconSize * 0.085)
      capStyle: ShapePath.RoundCap
      startX: root.width * 0.50
      startY: root.height * 0.30
      PathLine { x: root.width * 0.50; y: root.height * 0.66 }
    }

    SequentialAnimation on opacity {
      running: root.pulse
      loops: Animation.Infinite
      alwaysRunToEnd: true
      NumberAnimation { from: 1.0; to: 0.45; duration: 650; easing.type: Easing.InOutSine }
      NumberAnimation { from: 0.45; to: 1.0; duration: 650; easing.type: Easing.InOutSine }
    }
  }

  Rectangle {
    id: statusBadge
    width: root.statusSize
    height: width
    radius: width / 2
    color: {
      if (root.visualStatus === "connected") return root.indicatorColor
      if (root.visualStatus === "urgent") return root.badgeColor
      return root.backgroundColor
    }
    border.width: Math.max(1, Math.round(width * 0.11))
    border.color: {
      if (root.visualStatus === "disconnected") return root.dimColor
      if (root.visualStatus === "connecting" || root.visualStatus === "paused") return root.indicatorColor
      return root.backgroundColor
    }
    anchors.right: parent.right
    anchors.bottom: parent.bottom

    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
      visible: root.visualStatus === "connected" || root.visualStatus === "urgent"
      anchors.centerIn: parent
      text: root.visualStatus === "connected" ? "✓" : "!"
      color: root.backgroundColor
      font.family: root.fontFamily
      font.pixelSize: Math.max(6, parent.height * 0.74)
      font.bold: true
    }

    Rectangle {
      visible: root.visualStatus === "disconnected"
      width: parent.width * 0.48
      height: Math.max(1, Math.round(parent.height * 0.14))
      radius: height / 2
      color: root.dimColor
      anchors.centerIn: parent
    }

    Row {
      visible: root.visualStatus === "paused"
      anchors.centerIn: parent
      spacing: Math.max(1, Math.round(parent.width * 0.14))
      Rectangle {
        width: Math.max(1, Math.round(statusBadge.width * 0.14))
        height: Math.max(3, Math.round(statusBadge.height * 0.46))
        color: root.indicatorColor
      }
      Rectangle {
        width: Math.max(1, Math.round(statusBadge.width * 0.14))
        height: Math.max(3, Math.round(statusBadge.height * 0.46))
        color: root.indicatorColor
      }
    }

    Rectangle {
      visible: root.visualStatus === "connecting"
      width: Math.max(2, parent.width * 0.28)
      height: width
      radius: width / 2
      color: root.indicatorColor
      anchors.centerIn: parent
    }
  }
}
