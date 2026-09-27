import QtQuick
import qs.modules.common
import qs.services

// One of the two layers DiExpandedContent crossfades between. It holds a single view, centred vertically in the
// frame the island gives it (the island's height comes in steps, so there is usually a little room around it),
// and scrolls inside itself only when the view is taller than the island can ever get.
Item {
    id: slot
    required property Item host
    property string contentId: ""
    readonly property Item view: loader.item
    readonly property real padding: 14

    readonly property real naturalHeight: (loader.item?.implicitHeight ?? 60) + slot.padding * 2
    readonly property real naturalWidth: Math.max(loader.item?.implicitWidth ?? 280, loader.item?.wantedWidth ?? 0) + slot.padding * 2
    readonly property bool scrollable: slot.naturalHeight > slot.host.maxHeight + 1

    // Entrance/exit, all small: a few px along the direction of travel, a hair of scale, and the fade
    property real shift: 0

    // Past the end of its own scroll the view stretches like a rubber band; pulled far enough, it hands the gesture
    // to the island and the next one comes in, as if the list simply carried on into it. `pull` is the raw
    // overscroll (positive past the top, negative past the bottom); `stretch` is what is drawn, with resistance.
    signal overscrolled(int direction)
    property real pull: 0
    property double shownAt: 0
    readonly property real pullToSwitch: 110
    readonly property real stretch: {
        const reach = 48
        const x = Math.abs(slot.pull)
        return Math.sign(slot.pull) * (1 - 1 / (x * 0.55 / reach + 1)) * reach
    }

    width: slot.host.width
    height: Math.min(slot.naturalHeight, slot.host.maxHeight)
    y: (slot.host.height - slot.height) / 2 + slot.shift
    opacity: 0
    visible: slot.contentId !== ""
    transformOrigin: Item.Center

    function show(id, direction, instant) {
        leaving.stop()
        entering.stop()
        slot.contentId = id
        flick.contentY = 0
        pullBack.stop()
        slot.pull = 0
        slot.shownAt = Date.now()
        if (instant) {
            slot.opacity = 1
            slot.scale = 1
            slot.shift = 0
            return
        }
        slot.opacity = 0
        slot.scale = 0.975
        slot.shift = 14 * direction
        entering.start()
    }

    function leave(direction) {
        entering.stop()
        leaving.travel = -10 * direction
        leaving.start()
    }

    SequentialAnimation {
        id: entering
        // Lets the outgoing layer start moving first, so the two read as one handover rather than a blink
        PauseAnimation { duration: 60 }
        ParallelAnimation {
            NumberAnimation { target: slot; property: "opacity"; to: 1; duration: IslandMotion.medium; easing.type: Easing.OutCubic }
            NumberAnimation { target: slot; property: "scale"; to: 1; duration: IslandMotion.long; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial }
            NumberAnimation { target: slot; property: "shift"; to: 0; duration: IslandMotion.long; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial }
        }
    }

    SequentialAnimation {
        id: leaving
        property real travel: 0
        ParallelAnimation {
            NumberAnimation { target: slot; property: "opacity"; to: 0; duration: IslandMotion.short - 60; easing.type: Easing.InCubic }
            NumberAnimation { target: slot; property: "scale"; to: 0.965; duration: IslandMotion.short; easing.type: Easing.OutCubic }
            NumberAnimation { target: slot; property: "shift"; to: leaving.travel; duration: IslandMotion.short; easing.type: Easing.OutCubic }
        }
        // Unloaded once gone: a view that is not on screen should not keep its timers and bindings alive
        ScriptAction { script: slot.contentId = "" }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        clip: slot.scrollable
        interactive: slot.scrollable
        contentWidth: width
        contentHeight: slot.naturalHeight
        boundsBehavior: Flickable.StopAtBounds

        MouseArea {
            parent: flick
            anchors.fill: parent
            z: 10
            enabled: slot.scrollable
            acceptedButtons: Qt.NoButton
            onWheel: wheel => {
                wheel.accepted = true
                const step = wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y : wheel.angleDelta.y / 120 * 48
                const atTop = flick.contentY <= 0.5
                const atBottom = flick.contentY >= flick.contentHeight - flick.height - 0.5
                if ((step > 0 && atTop) || (step < 0 && atBottom)) {
                    // A fresh view ignores the tail of the gesture that brought it (touchpad momentum), and a view on
                    // its way out ignores everything
                    if (slot.host.currentSlot !== slot || Date.now() - slot.shownAt < 350) return
                    pullBack.stop()
                    slot.pull += step
                    pullRelease.restart()
                    if (Math.abs(slot.pull) >= slot.pullToSwitch) {
                        const direction = slot.pull < 0 ? 1 : -1
                        pullBack.start()
                        slot.overscrolled(direction)
                    }
                    return
                }
                if (slot.pull !== 0) pullBack.start()
                flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY - step))
            }
        }

        Loader {
            id: loader
            x: slot.padding
            y: slot.padding + slot.stretch
            width: flick.width - slot.padding * 2
            height: loader.item?.implicitHeight ?? 60
            sourceComponent: slot.contentId === "" ? null : slot.host.componentFor(slot.contentId)
        }
    }

    // Let go (no wheel for a moment) and the stretch springs back
    Timer {
        id: pullRelease
        interval: 140
        onTriggered: pullBack.start()
    }
    NumberAnimation {
        id: pullBack
        target: slot
        property: "pull"
        to: 0
        duration: IslandMotion.medium
        easing.type: Easing.OutCubic
    }

    Rectangle {
        visible: slot.scrollable
        anchors.right: parent.right
        anchors.rightMargin: 4
        y: slot.padding + (slot.height - slot.padding * 2 - height) * (flick.contentY / Math.max(1, flick.contentHeight - flick.height))
        width: 3
        height: Math.max(24, (slot.height - slot.padding * 2) * flick.height / Math.max(1, flick.contentHeight))
        radius: 1.5
        color: Appearance.colors.colOnLayer0
        opacity: flick.moving ? 0.5 : 0.2

        Behavior on opacity {
            NumberAnimation { duration: IslandMotion.short }
        }
    }
}
