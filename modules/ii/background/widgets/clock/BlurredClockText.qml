pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts

// ClockText whose glyphs are filled with blurred wallpaper when clock.blur is on.
// The tint reuses the face's own colour, so the hue is identical to the unblurred state.
Item {
    id: root

    property Item blurSource: null
    property real originX: 0
    property real originY: 0

    Layout.fillWidth: true

    readonly property bool blurOn: blurSource !== null && Config.options.background.widgets.clock.blur

    implicitWidth: face.implicitWidth
    implicitHeight: face.implicitHeight

    property alias text: face.text
    property alias color: face.color
    property alias font: face.font
    property alias horizontalAlignment: face.horizontalAlignment
    property alias animateChange: face.animateChange

    ClockText {
        id: face
        width: root.width
    }

    FastBlurred {
        id: blurItem
        anchors.fill: parent
        blurSource: root.blurSource
        cardRadius: 0
        tint: face.color
        tintOpacity: 0.55
        tintEnabled: Config.options.background.widgets.clock.tintBlur
        // mapToItem() inside FastBlurred is invisible to QML binding tracking, so the
        // sampled wallpaper region only refreshes when these two change.
        trackX: root.originX + root.x
        trackY: root.originY + root.y
        visible: false
    }
    OpacityMask {
        anchors.fill: parent
        source: blurItem
        maskSource: face
        visible: root.blurOn
    }
}
