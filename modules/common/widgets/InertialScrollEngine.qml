import QtQuick
import qs.modules.common

/**
 * Inertial scroll engine.
 *
 * ARCHITECTURE: This item is placed INSIDE the Flickable (as a child).
 * It does NOT handle events itself — instead, it exposes handleWheel()
 * which is called by a WheelHandler dynamically created on the Flickable's
 * parent (an ancestor). Ancestor WheelHandlers intercept events BEFORE
 * the Flickable's C++ wheelEvent handler in Qt 6.
 *
 * Implements two scrolling paths:
 * 1. TOUCHPAD: Direct delta tracking + exponential decay fling after lift.
 * 2. MOUSE WHEEL: Animated target using an OutCubic curve.
 */
Item {
    id: root

    required property var flickable

    // Scroll axis: false = vertical (contentY), true = horizontal (contentX)
    property bool horizontal: false
    readonly property string _posProp: horizontal ? "contentX" : "contentY"
    readonly property real _pos: horizontal ? flickable.contentX : flickable.contentY
    readonly property real _max: horizontal
        ? Math.max(0, flickable.contentWidth - flickable.width)
        : Math.max(0, flickable.contentHeight - flickable.height)

    // === Touchpad physics ===
    property real flingFriction: Config?.options.interactions.scrolling.flingFriction ?? 0.002
    property real flingStopThreshold: Config?.options.interactions.scrolling.flingStopThreshold ?? 0.01
    readonly property real flingMinVelocity: 0.0625 // px/ms — ContentPage's |v*16| >= 1 gate; 0.5 killed gentle swipes at lift
    property real touchpadSensitivity: (Config?.options.interactions.scrolling.touchpadSensitivity ?? 3.5)
                                       * (Config?.options.interactions.scrolling.touchpadScrollFactor ?? 1.0)

    // === Mouse wheel physics ===
    property int wheelScrollAmount: Math.round(
        (Config?.options.interactions.scrolling.wheelScrollAmount ?? 100)
        * (Config?.options.interactions.scrolling.mouseScrollFactor ?? 1.0))
    property int wheelDurationMin: Config?.options.interactions.scrolling.wheelDurationMin ?? 200
    property int wheelDurationMax: Config?.options.interactions.scrolling.wheelDurationMax ?? 400
    property int mouseScrollDeltaThreshold: Config?.options.interactions.scrolling.mouseScrollDeltaThreshold ?? 120

    // === Internal state ===
    property real _velocity: 0
    property real _wheelTargetY: 0
    property real _lastEventTime: 0
    property var  _velocitySamples: []

    // True while physics are writing the scroll position — hosts disable
    // their own position Behaviors during this so the two don't fight.
    readonly property bool active: physicsLoop.running || wheelAnim.running || liftTimer.running

    Timer {
        id: liftTimer
        interval: 80
        repeat: false
        onTriggered: root._computeAndStartFling()
    }

    FrameAnimation {
        id: physicsLoop
        running: false
        onTriggered: {
            var dt = frameTime * 1000
            if (dt <= 0) dt = 16.67
            root._velocity *= Math.pow(1.0 - root.flingFriction, dt)
            var maxPos = root._max
            var next = root._pos + root._velocity * dt // samples are d(pos)/dt — continue the finger's direction
            if (maxPos > 0) {
                // Stop dead at the edge — no bounce-back (reversing the
                // velocity here made flings glide back the wrong way)
                if (next < 0) { next = 0; root._velocity = 0 }
                else if (next > maxPos) { next = maxPos; root._velocity = 0 }
            } else { next = 0 }
            root.flickable[root._posProp] = next
            if (Math.abs(root._velocity) < root.flingStopThreshold) { root._velocity = 0; running = false }
        }
    }

    NumberAnimation {
        id: wheelAnim
        target: root.flickable
        property: root._posProp
        easing.type: Easing.OutCubic
    }

    // =========================================================
    // Public API: called by MouseArea.onWheel in ContentPage/other wrappers
    //
    // Device distinction:
    //   Mouse wheel  → angleDelta.y is an exact non-zero multiple of 120
    //   Touchpad     → angleDelta.y is NOT a multiple of 120 (high-res inertia)
    //   Phase end    → angleDelta.y == 0  (Wayland scroll phase separator)
    // =========================================================
    function handleWheel(event) {
        var d = horizontal ? event.angleDelta.x : event.angleDelta.y
        var p = horizontal ? event.pixelDelta.x : event.pixelDelta.y
        if (d === 0 && p === 0) return
        var enabled = Config?.options?.interactions?.scrolling?.fasterTouchpadScroll
        if (enabled === false) return
        // Mouse wheel: exact multiples of 120. Touchpad: non-multiples or
        // pixelDelta-only (high-res Wayland scroll).
        var isMouseWheel = d !== 0 && (Math.abs(d) % 120 === 0)
        if (isMouseWheel && p !== 0) console.log("[ISE] wheel-with-px d=" + d + " px=" + p + " h=" + horizontal)
        if (isMouseWheel) {
            root._handleMouseWheel(event)
        } else {
            root._handleTouchpad(event)
        }
        event.accepted = true
    }

    function _handleTouchpad(event) {
        var d = horizontal ? event.angleDelta.x : event.angleDelta.y
        var px = horizontal ? event.pixelDelta.x : event.pixelDelta.y
        if (d === 0 && px === 0) return
        if (wheelAnim.running) { wheelAnim.stop(); root._wheelTargetY = root._pos }
        physicsLoop.running = false
        // Restart lift BEFORE writing: active() must be true at write time or
        // the host Behavior animates this first write and that running
        // animation fights every direct write after it (stutter).
        liftTimer.restart()
        // Prefer pixelDelta; fallback converts angleDelta at this compositor's native
        // ratio (wheel pair d=-240 ↔ px=-20 → 12 units = 1px; slow scrolls arrive px=0
        // with fine d). touchpadSensitivity is a relative knob: 3.5 = native, so
        // touchpadScrollFactor overrides (×1.4) still scale it.
        var deltaPx = (px !== 0) ? -px : -d / 12 * (root.touchpadSensitivity / 3.5)
        if (px === 0 && d !== 0) console.log("[ISE] angle-fallback d=" + d + " -> " + deltaPx.toFixed(1) + "px h=" + horizontal)
        var now = Date.now()
        var dt = now - root._lastEventTime
        if (dt > 0 && dt < 150) {
            root._velocitySamples.push(deltaPx / dt)
            if (root._velocitySamples.length > 6) root._velocitySamples.shift()
        } else if (dt >= 150) {
            root._velocitySamples = []
        }
        root._lastEventTime = now
        var next = Math.max(0, Math.min(root._pos + deltaPx, root._max))
        root.flickable[root._posProp] = next
    }

    function _computeAndStartFling() {
        if (root._velocitySamples.length === 0) { root._velocity = 0; return }
        var total = 0, weightSum = 0
        for (var i = 0; i < root._velocitySamples.length; i++) {
            var w = i + 1; total += root._velocitySamples[i] * w; weightSum += w
        }
        root._velocity = total / weightSum
        console.log("[ISE-FLING] v=" + root._velocity.toFixed(3) + " n=" + root._velocitySamples.length
            + " gap=" + (Date.now() - root._lastEventTime) + " h=" + root.horizontal)
        root._velocitySamples = []
        if (Math.abs(root._velocity) >= root.flingMinVelocity) { physicsLoop.running = true }
        else { root._velocity = 0 }
    }

    function _handleMouseWheel(event) {
        physicsLoop.running = false; liftTimer.stop(); root._velocity = 0; root._velocitySamples = []
        var delta = horizontal ? event.angleDelta.x : event.angleDelta.y
        var direction = delta > 0 ? -1 : 1
        var base = wheelAnim.running ? root._wheelTargetY : root._pos
        root._wheelTargetY = Math.max(0, Math.min(base + direction * root.wheelScrollAmount, root._max))
        var distance = Math.abs(root._wheelTargetY - root._pos)
        var duration = Math.max(root.wheelDurationMin, Math.min(root.wheelDurationMax, distance * 2))
        wheelAnim.stop(); wheelAnim.from = root._pos
        wheelAnim.to = root._wheelTargetY; wheelAnim.duration = duration; wheelAnim.start()
    }
}
