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
    readonly property real maxOverscroll: 56
    readonly property real touchpadScrollFactor: Config?.options.interactions.scrolling.touchpadScrollFactor ?? 1.0
    // Same knob semantics as TouchpadScrollArea: legacy absolute factors normalize to 1.0.
    property real touchpadSensitivity: (Config?.options.interactions.scrolling.touchpadSensitivity ?? 3.5)
                                       * (touchpadScrollFactor > 10 ? touchpadScrollFactor / 450 : Math.max(0, touchpadScrollFactor))

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

    // True while physics are writing the scroll position — hosts disable
    // their own position Behaviors during this so the two don't fight.
    readonly property bool active: physicsLoop.running || wheelAnim.running || liftTimer.running
                                   || bounceTimer.running || bounceAnim.running

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
                // Keep a rubber-band overscroll at the edge so the spring-back is visible.
                if (next < 0) {
                    next = Math.max(-root.maxOverscroll, next)
                    root._velocity = 0
                    bounceTimer.interval = 90
                    bounceTimer.restart()
                } else if (next > maxPos) {
                    next = Math.min(maxPos + root.maxOverscroll, next)
                    root._velocity = 0
                    bounceTimer.interval = 90
                    bounceTimer.restart()
                }
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

    Timer {
        id: bounceTimer
        interval: 90
        onTriggered: root._startBounce()
    }

    NumberAnimation {
        id: bounceAnim
        target: root.flickable
        property: root._posProp
        duration: 360
        // One small overshoot; OutElastic wobbles too much.
        easing.type: Easing.OutBack
        easing.overshoot: 1.3
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
        if (root._max <= 0) return
        bounceAnim.stop()
        bounceTimer.stop()
        if (wheelAnim.running) { wheelAnim.stop(); root._wheelTargetY = root._pos }
        physicsLoop.running = false
        // Restart lift BEFORE writing: active() must be true at write time or
        // the host Behavior animates this first write and that running
        // animation fights every direct write after it (stutter).
        liftTimer.restart()
        // Same units as TouchpadScrollArea: pixelDelta is already pixels; the angle
        // fallback converts at this compositor's 12-units-per-pixel ratio.
        var deltaPx = -(px !== 0 ? px : d / 12) * root.touchpadSensitivity
        var now = Date.now()
        var dt = now - root._lastEventTime
        if (dt > 0 && dt < 150) {
            root._velocitySamples.push(deltaPx / dt)
            if (root._velocitySamples.length > 6) root._velocitySamples.shift()
        } else if (dt >= 150) {
            root._velocitySamples = []
        }
        root._lastEventTime = now
        var raw = root._pos + deltaPx
        var top = deltaPx < 0 && raw < 0
        var bottom = deltaPx > 0 && raw > root._max
        var next = raw
        if (top || bottom) {
            // Rubber band: each additional px of pull moves the content less
            // until it stops at maxOverscroll.
            var edge = top ? 0 : root._max
            var current = top ? Math.max(0, -root._pos) : Math.max(0, root._pos - root._max)
            var gap = top ? Math.max(0, root._pos) : Math.max(0, root._max - root._pos)
            var room = Math.max(0, 1 - current / root.maxOverscroll)
            var step = Math.max(0, Math.abs(deltaPx) - gap) * room
            next = edge + (top ? -1 : 1) * Math.min(root.maxOverscroll, current + step)
        } else if (root._pos < 0) {
            next = Math.min(raw, root._max)
        } else if (root._pos > root._max) {
            next = Math.max(raw, 0)
        } else {
            next = Math.max(0, Math.min(raw, root._max))
        }
        root.flickable[root._posProp] = next
        if (next < 0 || next > root._max) {
            liftTimer.stop()
            root._velocity = 0
            root._velocitySamples = []
            bounceTimer.interval = 90
            bounceTimer.restart()
        }
    }

    function _computeAndStartFling() {
        if (root._velocitySamples.length === 0) { root._velocity = 0; return }
        var total = 0, weightSum = 0
        for (var i = 0; i < root._velocitySamples.length; i++) {
            var w = i + 1; total += root._velocitySamples[i] * w; weightSum += w
        }
        root._velocity = total / weightSum
        root._velocitySamples = []
        if (Math.abs(root._velocity) >= root.flingMinVelocity) { physicsLoop.running = true }
        else { root._velocity = 0 }
    }

    function _handleMouseWheel(event) {
        if (root._max <= 0) return
        bounceAnim.stop()
        bounceTimer.stop()
        physicsLoop.running = false; liftTimer.stop(); root._velocity = 0; root._velocitySamples = []
        var delta = horizontal ? event.angleDelta.x : event.angleDelta.y
        var direction = delta > 0 ? -1 : 1
        var base = wheelAnim.running ? root._wheelTargetY : root._pos
        var raw = base + direction * root.wheelScrollAmount
        var top = direction < 0 && raw < 0
        var bottom = direction > 0 && raw > root._max
        if (top || bottom) {
            // Mouse wheel gets the same rubber band, at half pull strength.
            var edge = top ? 0 : root._max
            var current = top ? Math.max(0, -base) : Math.max(0, base - root._max)
            var gap = top ? Math.max(0, base) : Math.max(0, root._max - base)
            var room = Math.max(0, 1 - current / root.maxOverscroll)
            var step = Math.max(0, Math.abs(root.wheelScrollAmount) - gap) * 0.5 * room
            root._wheelTargetY = edge + (top ? -1 : 1) * Math.min(root.maxOverscroll, current + step)
        } else if (base > root._max && direction < 0) {
            // Releasing the bottom overscroll: follow the notch inward.
            root._wheelTargetY = Math.max(raw, 0)
        } else if (base < 0 && direction > 0) {
            root._wheelTargetY = Math.min(raw, root._max)
        } else {
            root._wheelTargetY = Math.max(0, Math.min(raw, root._max))
        }
        var distance = Math.abs(root._wheelTargetY - root._pos)
        var duration = Math.max(root.wheelDurationMin, Math.min(root.wheelDurationMax, distance * 2))
        wheelAnim.stop(); wheelAnim.from = root._pos
        wheelAnim.to = root._wheelTargetY; wheelAnim.duration = duration; wheelAnim.start()
        if (root._wheelTargetY < 0 || root._wheelTargetY > root._max) {
            bounceTimer.interval = duration + 80
            bounceTimer.restart()
        }
    }

    function _startBounce() {
        if (root._pos >= 0 && root._pos <= root._max) return
        wheelAnim.stop()
        physicsLoop.running = false
        liftTimer.stop()
        root._velocity = 0
        bounceAnim.stop()
        bounceAnim.from = root._pos
        bounceAnim.to = root._pos < 0 ? 0 : root._max
        bounceAnim.start()
    }
}
