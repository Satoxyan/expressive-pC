pragma Singleton
import QtQuick

// Test stub: InertialScrollEngine only reads these scrolling knobs.
QtObject {
    property QtObject options: QtObject {
        property QtObject settings: QtObject {
            property string style: "default"
            property real animationSpeed: 1
        }
        property QtObject interactions: QtObject {
            property QtObject scrolling: QtObject {
                property real flingFriction: 0.002
                property real flingStopThreshold: 0.01
                property real touchpadScrollFactor: 1.0
                property real touchpadSensitivity: 3.5
                property real mouseScrollFactor: 1.0
                property int wheelScrollAmount: 100
                property int wheelDurationMin: 200
                property int wheelDurationMax: 400
                property bool fasterTouchpadScroll: true
            }
        }
    }
}
