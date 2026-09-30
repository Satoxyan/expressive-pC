import QtQuick
import qs.modules.common

Rectangle {
    id: root
    required property var widget
    property bool blurred: Config.options.background.widgets.blurWidgets
    property bool shadowed: Config.options.background.widgets.shadow
    property bool tintEnabled: true
    property color tint: Appearance.colors.colPrimaryContainer
    property real tintOpacity: 0.55

    radius: Appearance.rounding?.verylarge ?? 30
    color: Appearance.colors.colPrimaryContainer

    StyledRectangularShadow {
        target: root
        z: -2
        visible: root.shadowed
    }

    FastBlurred {
        anchors.fill: parent
        blurSource: root.widget.wallpaperItem
        cardRadius: root.radius
        tint: root.tint
        tintOpacity: root.tintOpacity
        tintEnabled: root.tintEnabled
        trackX: root.widget.x + root.x
        trackY: root.widget.y + root.y
        visible: root.blurred
    }
}
