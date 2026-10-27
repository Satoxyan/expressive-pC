import QtQuick
import qs.modules.common

// Programmatic scroll (section chip, group switch, search) must stop a fling.
Window {
    id: win
    width: 400; height: 300; visible: true
    property int failures: 0
    function check(ok, msg) { console.log((ok ? "PASS " : "FAIL ") + msg); if (!ok) win.failures++ }
    function ev(px, phase) {
        eng.handleWheel({ angleDelta: { x: 0, y: px }, pixelDelta: { x: 0, y: px }, phase: phase, accepted: false })
    }
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
            win.ev(-40, Qt.ScrollBegin)
            win.ev(-40, Qt.ScrollUpdate)
            step2.start()
        }
    }
    Timer {
        id: step2; interval: 20
        onTriggered: {
            win.ev(-40, Qt.ScrollUpdate)
            win.ev(-40, Qt.ScrollUpdate)
            win.ev(0, Qt.ScrollEnd)
            win.check(eng.active, "fling active")
            win.check(typeof eng.stop === "function", "engine exposes stop()")
            if (typeof eng.stop === "function") eng.stop()
            flick.contentY = 0
            win.check(Math.abs(flick.contentY) < 0.001, "jump applied")
            driftTimer.start()
        }
    }
    Timer {
        id: driftTimer; interval: 200
        onTriggered: {
            win.check(Math.abs(flick.contentY) < 0.5, "fling stopped after jump (y=" + flick.contentY.toFixed(1) + ")")
            console.log("failures:", win.failures)
            Qt.exit(win.failures === 0 ? 0 : 1)
        }
    }
}
