pragma Singleton
import QtQuick

// Test stub: only the members ContentPage/StyledScrollBar read.
QtObject {
    property QtObject rounding: QtObject {
        property real small: 4
        property real normal: 8
    }
    property QtObject colors: QtObject {
        property color colPrimary: "#ff0000"
        property color colOnSurfaceVariant: "#888888"
    }
    property QtObject animation: QtObject {
        property QtObject elementMoveFast: QtObject {
            property int type: Easing.OutCubic
            property var bezierCurve: [0.2, 0, 0, 1]
        }
    }
}
