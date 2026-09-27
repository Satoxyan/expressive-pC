import QtQuick

// A damped spring integrated every frame. Material 3 Expressive specifies motion as stiffness + damping ratio
// rather than duration + curve, and that is what this takes. Changing `target` mid-flight keeps the current
// velocity, so a change of mind bends the motion instead of restarting it from a standstill (which is what reads
// as a jump). Only ticks while it is moving.
QtObject {
    id: spring

    property real target: 0
    property real value: 0
    property real velocity: 0
    property real stiffness: 380
    property real dampingRatio: 0.84
    // Close enough to call it settled, in the value's own unit (px for sizes, 0..1 for a progress)
    property real epsilon: 0.25
    readonly property bool moving: spring.ticker.running

    // Off while nothing is on screen: the value just follows the target, and no frame ticks for it
    property bool animated: true

    // Straight to the target, no motion (without touching a binding on `target`)
    function snap() {
        spring.ticker.stop()
        spring.value = spring.target
        spring.velocity = 0
    }

    Component.onCompleted: spring.value = spring.target
    onTargetChanged: {
        if (!spring.animated) spring.snap()
        else if (!spring.ticker.running) spring.ticker.start()
    }
    onAnimatedChanged: if (!spring.animated) spring.snap()

    property FrameAnimation ticker: FrameAnimation {
        onTriggered: {
            // A dropped frame must not become a huge step; small substeps keep a stiff spring stable
            const dt = Math.min(frameTime, 1 / 30)
            const steps = Math.max(1, Math.ceil(dt * 240))
            const h = dt / steps
            const k = spring.stiffness
            const c = 2 * spring.dampingRatio * Math.sqrt(k)
            let x = spring.value
            let v = spring.velocity
            for (let i = 0; i < steps; i++) {
                v += (-k * (x - spring.target) - c * v) * h
                x += v * h
            }
            if (Math.abs(x - spring.target) < spring.epsilon && Math.abs(v) < spring.epsilon * 12) {
                x = spring.target
                v = 0
                stop()
            }
            spring.value = x
            spring.velocity = v
        }
    }
}
