import QtQuick
import QtTest
import qs.modules.common.widgets

// The shared scroll containers must run through the same inertial engine as the
// settings pages. (Wheel routing itself needs a real compositor.)
TestCase {
    name: "InertialContainers"
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

    // Grids don't populate while hidden under the offscreen harness, so only the
    // engine's presence is checked here; behaviour is covered by the list above.
    StyledGridView {
        id: grid
        anchors.fill: parent
        visible: false
        cellWidth: 100
        cellHeight: 100
        model: 40
    }

    function engineOf(item) {
        for (let i = 0; i < item.data.length; i++) {
            const child = item.data[i]
            if (typeof child.handleWheel === "function") return child
        }
        return null
    }

    function test_listEngineInstalled() {
        verify(engineOf(view) !== null, "inertial engine present inside the list")
    }

    function test_listMouseWheelAnimates() {
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

    function test_listTouchpadFlingContinues() {
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

    function test_gridEngineInstalled() {
        verify(engineOf(grid) !== null, "inertial engine present inside the grid")
    }

}
