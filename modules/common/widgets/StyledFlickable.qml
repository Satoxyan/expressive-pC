import QtQuick
import QtQuick.Controls
import qs.modules.common

/** A Flickable with standard styling and touchpad sensitivity. */
Flickable {
    id: root

    maximumFlickVelocity: 3500
    boundsBehavior: Flickable.DragOverBounds

    ScrollBar.vertical: StyledScrollBar {}

    TouchpadScrollArea {
        id: touchpadScroll
        flickable: root
    }
}
