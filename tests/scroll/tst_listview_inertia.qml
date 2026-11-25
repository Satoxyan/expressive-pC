import QtQuick
import QtTest
import qs.modules.common.widgets

// StyledListView must scroll through the shared inertial engine, i.e. the same
// feel as the settings pages. (Wheel routing itself needs a real compositor.)
TestCase {
    name: "StyledListViewInertia"
    when: windowShown
    width: 400
    height: 300

    StyledListView {
        id: view
        anchors.fill: parent
        model: 40
        delegate: Item { width: view.width; height: 50 }
        animateAppearance: false
        popin: false
    }

    function childOf(item, predicate) {
        for (let i = 0; i < item.data.length; i++) {
            const child = item.data[i]
            if (predicate(child)) return child
        }
        return null
    }

    function engineOf(item) {
        return childOf(item, child => typeof child.handleWheel === "function")
    }

    function test_engineInstalled() {
        verify(engineOf(view) !== null, "inertial engine present inside the list")
    }

    function test_mouseWheelAnimates() {
        wait(50)
        verify(view.contentHeight > view.height, "list overflows")
        const engine = engineOf(view)
        engine.stop()
        view.contentY = 0
        engine.handleWheel({
            angleDelta: { x: 0, y: -120 }, pixelDelta: { x: 0, y: 0 },
            phase: Qt.NoScrollPhase, accepted: false
        })
        wait(40)
        verify(view.contentY > 1, "wheel started scrolling (y=" + view.contentY.toFixed(1) + ")")
        verify(view.contentY < 90, "wheel animated instead of teleporting")
        wait(450)
        verify(view.contentY > 90, "wheel animation completed (y=" + view.contentY.toFixed(1) + ")")
    }

    function test_touchpadFlingContinues() {
        const engine = engineOf(view)
        engine.stop()
        view.contentY = 0
        const event = {
            angleDelta: { x: 0, y: -20 }, pixelDelta: { x: 0, y: -20 },
            phase: Qt.ScrollUpdate, accepted: false
        }
        engine.handleWheel(event)
        wait(16)
        engine.handleWheel(event)
        const atRelease = view.contentY
        verify(atRelease > 0, "touchpad scrolling moved the list")
        engine.handleWheel({
            angleDelta: { x: 0, y: 0 }, pixelDelta: { x: 0, y: 0 },
            phase: Qt.ScrollEnd, accepted: false
        })
        wait(250)
        verify(view.contentY > atRelease, "movement continued after the gesture (inertia)")
    }
}
