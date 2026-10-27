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
    readonly property real flingMinVelocity: 0.0625 // px/ms — 0.5 killed gentle swipes at lift
    // Firefox asymptotes at composition length; viewport is the closest QML analogue.
    readonly property real maxOverscroll: Math.max(1, horizontal ? flickable.width : flickable.height)
    readonly property real touchpadScrollFactor: Config?.options.interactions.scrolling.touchpadScrollFactor ?? 1.0
    // Same knob semantics as TouchpadScrollArea: legacy absolute factors normalize to 1.0.
    property real touchpadSensitivity: {
        const sc = Config?.options?.interactions?.scrolling
        if (sc?.fasterTouchpadScroll === false) return 1
        return (sc?.touchpadSensitivity ?? 3.5)
            * (touchpadScrollFactor > 10 ? touchpadScrollFactor / 450 : Math.max(0, touchpadScrollFactor))
    }

    // === Mouse wheel physics ===
    // Legacy configs store pixels per notch (120); new configs store a 1.0 multiplier.
    readonly property real mouseScrollFactor: {
        const f = Config?.options.interactions.scrolling.mouseScrollFactor ?? 1.0
        return f > 10 ? f / 120 : Math.max(0, f)
    }
    property int wheelScrollAmount: Math.round(
        (Config?.options.interactions.scrolling.wheelScrollAmount ?? 100) * mouseScrollFactor)
    property int wheelDurationMin: Config?.options.interactions.scrolling.wheelDurationMin ?? 200
    property int wheelDurationMax: Config?.options.interactions.scrolling.wheelDurationMax ?? 400

    // === Internal state ===
    property real _velocity: 0
    property real _wheelTargetY: 0
    property real _lastEventTime: 0
    property var  _velocitySamples: []
    // True between ScrollBegin and ScrollEnd; an idle timer cannot fake a lift.
    property bool _phaseGesture: false

    // === Overscroll spring (Firefox AxisPhysicsMSDModel: unit mass, k=200, zeta=1.1) ===
    readonly property real _springStiffness: 200
    readonly property real _springDampingRatio: 1.1
    readonly property real _springDamping: 2 * _springDampingRatio * Math.sqrt(_springStiffness)
    readonly property real _springStep: 1 / 120
    property real _springOverscroll: 0
    property real _springVelocity: 0 // px/s
    property real _springEdge: 0
    property int _springSign: -1
    property real _springAccumulator: 0

    // True while physics are writing the scroll position — hosts disable
    // their own position Behaviors during this so the two don't fight.
    readonly property bool active: physicsLoop.running || wheelAnim.running || liftTimer.running
                                   || overscrollLoop.running

    // Stop every animation without moving the view; the caller writes the target.
    function stop() {
        root.flickable.cancelFlick()
        physicsLoop.running = false
        wheelAnim.stop()
        liftTimer.stop()
        root._stopOverscrollSpring()
        root._velocity = 0
        root._velocitySamples = []
        root._phaseGesture = false
        root._wheelTargetY = root._pos
    }

    Timer {
        id: liftTimer
        interval: 80
        repeat: false
        onTriggered: {
            // Phase-aware input releases on ScrollEnd, not on idle.
            if (!root._phaseGesture) root._computeAndStartFling()
        }
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
                // Enter the overscroll spring at the edge with the fling's velocity.
                if (next < 0 || next > maxPos) {
                    running = false
                    root._startOverscrollSpring(next < 0 ? -1 : 1, root._velocity)
                    return
                }
            } else { next = 0 }
            root.flickable[root._posProp] = next
            if (Math.abs(root._velocity) < root.flingStopThreshold) { root._velocity = 0; running = false }
        }
    }

    // shortcut: fixed 120 Hz without interpolation; add interpolation if 144+ Hz looks steppy.
    FrameAnimation {
        id: overscrollLoop
        running: false
        onTriggered: root._stepOverscroll(frameTime)
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
        if (d === 0 && p === 0) {
            // Wayland sends a final zero-delta event; release the gesture now.
            if (event.phase === Qt.ScrollEnd) root._handleScrollEnd()
            return
        }
        // Mouse wheel: exact multiples of 120. Touchpad: non-multiples or
        // pixelDelta-only (high-res Wayland scroll).
        var isMouseWheel = d !== 0 && (Math.abs(d) % 120 === 0)
        if (isMouseWheel) {
            root._handleMouseWheel(event)
        } else {
            root._handleTouchpad(event)
        }
        event.accepted = true
    }

    function _handleTouchpad(event) {
        root._phaseGesture = event.phase === Qt.ScrollBegin || event.phase === Qt.ScrollUpdate
        var d = horizontal ? event.angleDelta.x : event.angleDelta.y
        var px = horizontal ? event.pixelDelta.x : event.pixelDelta.y
        if (d === 0 && px === 0) {
            if (event.phase === Qt.ScrollEnd) root._handleScrollEnd()
            return
        }
        if (root._max <= 0) return
        root._stopOverscrollSpring()
        if (wheelAnim.running) { wheelAnim.stop(); root._wheelTargetY = root._pos }
        physicsLoop.running = false
        // Restart lift BEFORE writing: active() must be true at write time or
        // the host Behavior animates this first write and that running
        // animation fights every direct write after it (stutter).
        liftTimer.restart()
        // Same units as TouchpadScrollArea: pixelDelta is already pixels; the angle
        // fallback converts at this compositor's 12-units-per-pixel ratio.
        var deltaPx = -(px !== 0 ? px : d / 12) * root.touchpadSensitivity
        var prev = root._pos
        var raw = prev + deltaPx
        var top = deltaPx < 0 && raw < 0
        var bottom = deltaPx > 0 && raw > root._max
        var next = raw
        if (top || bottom) {
            // Firefox Axis::ApplyResistance: 1/16 at the edge, 0 at viewport length,
            // max 8 px added per event.
            var edge = top ? 0 : root._max
            var current = top ? Math.max(0, -prev) : Math.max(0, prev - root._max)
            var gap = top ? Math.max(0, prev) : Math.max(0, root._max - prev)
            var room = Math.max(0, 1 - current / root.maxOverscroll)
            var step = Math.min(8, Math.max(0, Math.abs(deltaPx) - gap) * room / 16)
            next = edge + (top ? -1 : 1) * Math.min(root.maxOverscroll, current + step)
        } else if (prev < 0) {
            next = Math.min(raw, root._max)
        } else if (prev > root._max) {
            next = Math.max(raw, 0)
        } else {
            next = Math.max(0, Math.min(raw, root._max))
        }
        root.flickable[root._posProp] = next

        // Firefox tracks velocity after resistance, not the raw finger delta.
        var now = Date.now()
        var dt = now - root._lastEventTime
        var visual = next - prev
        if (dt > 0 && dt < 150) {
            root._velocitySamples.push(visual / dt)
            if (root._velocitySamples.length > 6) root._velocitySamples.shift()
        } else if (dt >= 150) {
            root._velocitySamples = []
        }
        root._lastEventTime = now
        if (event.phase === Qt.ScrollEnd) root._handleScrollEnd()
    }

    function _weightedVelocity() {
        // Samples older than the 150 ms window mean a pause, not a moving finger.
        if (Date.now() - root._lastEventTime > 150) { root._velocitySamples = []; return 0 }
        var total = 0, weightSum = 0
        for (var i = 0; i < root._velocitySamples.length; i++) {
            var w = i + 1; total += root._velocitySamples[i] * w; weightSum += w
        }
        return weightSum > 0 ? total / weightSum : 0
    }

    function _computeAndStartFling() {
        if (root._pos < 0 || root._pos > root._max) { root._startBounce(); return }
        root._velocity = root._weightedVelocity()
        root._velocitySamples = []
        if (Math.abs(root._velocity) >= root.flingMinVelocity) { physicsLoop.running = true }
        else { root._velocity = 0 }
    }

    function _handleMouseWheel(event) {
        if (root._max <= 0) return
        var base = Math.max(0, Math.min(root._max, wheelAnim.running ? root._wheelTargetY : root._pos))
        root._stopOverscrollSpring()
        physicsLoop.running = false; liftTimer.stop(); root._velocity = 0; root._velocitySamples = []
        var delta = horizontal ? event.angleDelta.x : event.angleDelta.y
        var direction = delta > 0 ? -1 : 1
        // Firefox only applies the elastic effect to touchpad/touchscreen input.
        root._wheelTargetY = Math.max(0, Math.min(root._max, base + direction * root.wheelScrollAmount))
        var distance = Math.abs(root._wheelTargetY - root._pos)
        var duration = Math.max(root.wheelDurationMin, Math.min(root.wheelDurationMax, distance * 2))
        wheelAnim.stop(); wheelAnim.from = root._pos
        wheelAnim.to = root._wheelTargetY; wheelAnim.duration = duration; wheelAnim.start()
    }

    function _handleScrollEnd() {
        if (overscrollLoop.running || physicsLoop.running) return
        if (root._pos < 0 || root._pos > root._max) { root._startBounce(); return }
        // Phase end is the real release: don't wait for the fallback timer.
        if (liftTimer.running) {
            liftTimer.stop()
            root._computeAndStartFling()
        }
    }

    function _startBounce() {
        if (overscrollLoop.running) return
        if (root._pos >= 0 && root._pos <= root._max) return
        var velocity = root._weightedVelocity()
        root._velocitySamples = []
        liftTimer.stop()
        root._startOverscrollSpring(root._pos < 0 ? -1 : 1, velocity)
    }

    function _stopOverscrollSpring() {
        if (!overscrollLoop.running) return
        overscrollLoop.running = false
        root._springAccumulator = 0
        root._springVelocity = 0
    }

    function _startOverscrollSpring(side, velocityPxPerMs) {
        var edge = side < 0 ? 0 : root._max
        // A fling colliding from inside counts as zero overscroll, not as invalid input.
        var current = side < 0 ? Math.min(0, root._pos) : Math.max(0, root._pos - root._max)
        var outward = side < 0 ? velocityPxPerMs < 0 : velocityPxPerMs > 0
        if (Math.abs(current) < 0.01 && !outward) return

        var limit = root.maxOverscroll
        root._springEdge = edge
        root._springSign = side
        root._springOverscroll = Math.max(-limit, Math.min(limit, current))
        // Firefox halves the release velocity and clamps it to 10 ParentLayer px/ms.
        root._springVelocity = Math.max(-10, Math.min(10, (Number(velocityPxPerMs) || 0) / 2)) * 1000
        root._springAccumulator = 0
        root._velocity = 0
        root._velocitySamples = []
        physicsLoop.running = false
        wheelAnim.stop()
        liftTimer.stop()
        // Start the loop before writing: active must be true or the host's
        // Behavior animates this write and then fights every spring frame.
        overscrollLoop.running = true
        root.flickable[root._posProp] = edge + root._springOverscroll
    }

    function _finishOverscroll() {
        root.flickable[root._posProp] = root._springEdge
        root._springOverscroll = 0
        root._springVelocity = 0
        root._springAccumulator = 0
        overscrollLoop.running = false
    }

    function _stepOverscroll(dt) {
        if (!overscrollLoop.running || !(dt > 0)) return
        var h = root._springStep
        var k = root._springStiffness
        var c = root._springDamping
        var limit = root.maxOverscroll
        root._springAccumulator += Math.min(dt, 0.05)

        while (root._springAccumulator >= h) {
            root._springAccumulator -= h
            var o = root._springOverscroll
            var v = root._springVelocity

            // RK4 for o'' = -k*o - c*v, unit mass.
            var a1 = -k * o - c * v
            var v1 = v
            var o2 = o + v1 * h / 2
            var v2 = v + a1 * h / 2
            var a2 = -k * o2 - c * v2
            var o3 = o + v2 * h / 2
            var v3 = v + a2 * h / 2
            var a3 = -k * o3 - c * v3
            var o4 = o + v3 * h
            var v4 = v + a3 * h
            var a4 = -k * o4 - c * v4
            var nextO = o + h * (v1 + 2 * v2 + 2 * v3 + v4) / 6
            var nextV = v + h * (a1 + 2 * a2 + 2 * a3 + a4) / 6

            if (nextO < -limit) {
                nextO = -limit
                if (nextV < 0) nextV = 0
            } else if (nextO > limit) {
                nextO = limit
                if (nextV > 0) nextV = 0
            }
            root._springOverscroll = nextO
            root._springVelocity = nextV

            // Firefox stops as soon as the spring would cross the edge.
            if (root._springSign < 0 ? nextO >= 0 : nextO <= 0) {
                root._finishOverscroll()
                return
            }
            if (Math.abs(nextO) < 1 && Math.abs(nextV) < 2) {
                root._finishOverscroll()
                return
            }
        }

        root.flickable[root._posProp] = root._springEdge + root._springOverscroll
    }
}
