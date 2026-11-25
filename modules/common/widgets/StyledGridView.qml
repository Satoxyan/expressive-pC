import QtQuick
import qs.modules.common

/** A GridView with the shared inertial scrolling. */
GridView {
    id: root

    InertialScrollEngine {
        id: scrollEngine
        flickable: root
    }

    // Runs before the GridView's own C++ wheel handling in Qt 6. Disabled when
    // there is nothing to scroll vertically, so short grids keep native input.
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        enabled: root.contentHeight > root.height
        onWheel: event => {
            event.accepted = false
            scrollEngine.handleWheel(event)
        }
    }

    onDraggingChanged: if (dragging) scrollEngine.stop()

    // Keyboard and programmatic scroll steps animate; wheel, drag and fling
    // stay instant.
    Behavior on contentY {
        enabled: !root.moving && !root.dragging && !scrollEngine.active
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }
}
