import QtQuick
import QtQuick.Controls
import qs.modules.common

/** A Flickable with standard styling and the shared inertial scrolling. */
Flickable {
    id: root

    maximumFlickVelocity: 3500
    boundsBehavior: Flickable.DragOverBounds

    ScrollBar.vertical: StyledScrollBar {}

    InertialScrollEngine {
        id: scrollEngine
        flickable: root
    }

    // Runs before the Flickable's own C++ wheel handling in Qt 6. Disabled
    // when there is nothing to scroll vertically, so horizontal strips and
    // short content keep native behavior.
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        enabled: root.contentHeight > root.height
        onWheel: event => {
            event.accepted = false
            scrollEngine.handleWheel(event)
        }
    }

    onDraggingChanged: if (dragging) scrollEngine.stop()

    // Keyboard scroll steps animate; wheel, drag and fling stay instant.
    Behavior on contentY {
        enabled: !root.moving && !root.dragging && !scrollEngine.active
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }
}
