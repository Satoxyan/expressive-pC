import QtQuick
import qs.modules.common

// fasterTouchpadScroll only drops the shared sensitivity; scrolling must still work.
Window {
    id: win
    width: 400; height: 300; visible: true
    property int failures: 0
    function check(ok, msg) { console.log((ok ? "PASS " : "FAIL ") + msg); if (!ok) win.failures++ }
    Component.onCompleted: Config.options.interactions.scrolling.fasterTouchpadScroll = false
    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: 2000
        boundsBehavior: Flickable.StopAtBounds
        InertialScrollEngine { id: eng; flickable: flick }
    }
    Timer { id: watchdog; interval: 8000; running: true; onTriggered: Qt.exit(99) }

    Timer {
        interval: 50; running: true
        onTriggered: {
            eng.handleWheel({ angleDelta: { x: 0, y: -120 }, pixelDelta: { x: 0, y: 0 }, phase: Qt.NoScrollPhase, accepted: false })
            afterWheel.start()
        }
    }
    Timer {
        id: afterWheel; interval: 150
        onTriggered: {
            win.check(flick.contentY > 0, "mouse wheel scrolls when fasterTouchpadScroll=false (y=" + flick.contentY.toFixed(1) + ")")
            eng.stop()
            flick.contentY = 0
            touchpadCheck.start()
        }
    }
    Timer {
        id: touchpadCheck; interval: 50
        onTriggered: {
            eng.handleWheel({ angleDelta: { x: 0, y: -20 }, pixelDelta: { x: 0, y: -20 }, phase: Qt.ScrollUpdate, accepted: false })
            win.check(flick.contentY > 0, "touchpad still scrolls when fasterTouchpadScroll=false (y=" + flick.contentY.toFixed(1) + ")")
            console.log("failures:", win.failures)
            Qt.exit(win.failures === 0 ? 0 : 1)
        }
    }
}
