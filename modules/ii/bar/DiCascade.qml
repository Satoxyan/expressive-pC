import QtQuick

// Entrance for one item of a list or grid: after `delay + index × step` ms it fades in while rising a few px and
// growing from 0.96, on a spring. Consecutive indexes give the cascade. Only opacity, scale and a Translate move,
// so the Layout the target sits in never re-runs for it.
QtObject {
    id: cascade
    required property Item target
    property int index: 0
    property int step: 30
    property int delay: 60
    property real rise: 8
    // The cascade owns the target's scale, so a press is folded in here too, on a quick spring
    property bool pressed: false
    property real pressedScale: 0.95

    property DiSpring spring: DiSpring {
        stiffness: 240
        dampingRatio: 0.78
        epsilon: 0.002
    }
    property DiSpring press: DiSpring {
        target: cascade.pressed ? cascade.pressedScale : 1
        value: 1
        stiffness: 700
        dampingRatio: 0.6
        epsilon: 0.001
    }
    property Translate shift: Translate {
        y: (1 - cascade.spring.value) * cascade.rise
    }
    property Timer starter: Timer {
        interval: cascade.delay + cascade.index * cascade.step
        running: true
        onTriggered: cascade.spring.target = 1
    }

    Component.onCompleted: {
        cascade.target.transform = [cascade.shift]
        cascade.target.opacity = Qt.binding(() => Math.max(0, Math.min(1, cascade.spring.value)))
        cascade.target.scale = Qt.binding(() => (0.96 + 0.04 * cascade.spring.value) * cascade.press.value)
    }
}
