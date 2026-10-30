pragma Singleton
import QtQuick

// Test stub: only the members Lyrics/StyledText read.
QtObject {
    property QtObject spacing: QtObject {
        property int space100: 8
    }
    property QtObject colors: QtObject {
        property color colPrimaryContainer: "#334455"
        property color colOnPrimaryContainer: "#eeddcc"
        property color colSubtext: "#888888"
        property color colOnLayer1: "#eeeeee"
    }
    property QtObject m3colors: QtObject {
        property color m3onBackground: "#000000"
        property color m3primary: "#0000ff"
    }
    property QtObject font: QtObject {
        property QtObject pixelSize: QtObject {
            property int smallest: 10
            property int smaller: 12
            property int small: 15
            property int normal: 16
            property int larger: 19
        }
        property QtObject family: QtObject {
            property string main: "Sans"
            property string numbers: "Sans"
        }
        property QtObject variableAxes: QtObject {
            property var main: ({})
        }
    }
    property QtObject animation: QtObject {
        property QtObject elementMoveFast: QtObject {
            property int duration: 150
            property int type: Easing.OutCubic
            property var bezierCurve: [0.2, 0, 0, 1]
        }
        property QtObject elementMoveSmall: QtObject {
            property int duration: 150
            property int type: Easing.OutCubic
            property var bezierCurve: [0.2, 0, 0, 1]
        }
        property QtObject elementResize: QtObject {
            property int duration: 300
            property int type: Easing.OutCubic
            property var bezierCurve: [0.2, 0, 0, 1]
        }
    }
}
