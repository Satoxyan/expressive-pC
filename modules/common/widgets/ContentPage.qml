import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common

/**
 * Scrollable page container for settings panels.
 *
 * Uses a MouseArea overlay (z=1) to intercept wheel events before the
 * inner Flickable's C++ handler. Inertial scroll physics are implemented
 * inline using a NumberAnimation + Timer to avoid cross-component issues.
 */
Item {
    id: root
    clip: true

    property real baseWidth: 600
    property bool forceWidth: false
    property real bottomContentPadding: Config.options.settings.style === "minimal" ? 40 : 90

    // Children placed in ContentPage appear inside the ColumnLayout
    default property alias data: contentColumn.data

    implicitWidth: contentColumn.implicitWidth

    // =========================================================
    // Inner Flickable
    // =========================================================
    Flickable {
        id: flickable
        anchors.fill: parent
        contentHeight: contentColumn.implicitHeight + root.bottomContentPadding
        boundsBehavior: Flickable.DragOverBounds
        maximumFlickVelocity: 3500

        ScrollBar.vertical: StyledScrollBar {}

        ColumnLayout {
            id: contentColumn
            width: root.forceWidth ? root.baseWidth : Math.max(root.baseWidth, implicitWidth)
            anchors {
                top: parent.top
                horizontalCenter: parent.horizontalCenter
                margins: 20
            }
            spacing: 30
        }
    }

    // =========================================================
    // Scroll physics — inline, no external engine component
    // =========================================================
    property real _targetY: 0
    property real _flingVelocity: 0
    property var  _samples: []
    property real _lastT: 0

    // Mouse wheel: smooth Bezier animation to target
    NumberAnimation {
        id: _wheelAnim
        target: flickable
        property: "contentY"
        duration: 200
        easing.type: Easing.OutCubic
    }

    // Touchpad fling & overscroll spring: physics loop
    Timer {
        id: _flingTimer
        interval: 16
        repeat: true
        onTriggered: {
            var maxY = Math.max(0, flickable.contentHeight - flickable.height)
            var y = flickable.contentY
            var step = 0
            
            if (y < 0) {
                if (root._flingVelocity < -0.1) {
                    root._flingVelocity *= 0.65       // Stop quickly when pushing out
                    step = root._flingVelocity * 16
                } else {
                    root._flingVelocity = 0
                    step = (0 - y) * 0.2              // Smooth glide back to 0
                }
            } else if (y > maxY) {
                if (root._flingVelocity > 0.1) {
                    root._flingVelocity *= 0.65       // Stop quickly when pushing out
                    step = root._flingVelocity * 16
                } else {
                    root._flingVelocity = 0
                    step = (maxY - y) * 0.2           // Smooth glide back to maxY
                }
            } else {
                root._flingVelocity *= 0.96           // Normal friction inside bounds
                step = root._flingVelocity * 16
            }
            
            flickable.contentY = y + step
            
            // Stop condition: low velocity AND we are safely inside/at bounds
            if (Math.abs(step) < 0.5) {
                var finalY = flickable.contentY
                if (finalY < 0.5 && finalY > -0.5) flickable.contentY = 0
                else if (finalY > maxY - 0.5 && finalY < maxY + 0.5) flickable.contentY = maxY
                
                if (flickable.contentY >= 0 && flickable.contentY <= maxY) {
                    _flingTimer.stop()
                    root._flingVelocity = 0
                }
            }
        }
    }

    // Lift detection: finger-lift → start fling
    Timer {
        id: _liftTimer
        interval: 80
        onTriggered: {
            if (root._samples.length > 0) {
                var total = 0, ws = 0
                for (var i = 0; i < root._samples.length; i++) {
                    var w = i + 1; total += root._samples[i] * w; ws += w
                }
                root._flingVelocity = total / ws  // result in px/ms
                root._samples = []
            }
            
            var maxY = Math.max(0, flickable.contentHeight - flickable.height)
            var outOfBounds = (flickable.contentY < 0 || flickable.contentY > maxY)
            
            if (Math.abs(root._flingVelocity * 16) >= 1.0 || outOfBounds) {
                _flingTimer.restart()
            }
        }
    }

    function _clampY(y) {
        return Math.max(0, Math.min(y, Math.max(0, flickable.contentHeight - flickable.height)))
    }

    function _handleTouchpad(dy) {
        if (dy === 0) return
        _wheelAnim.stop()
        _flingTimer.stop()
        var deltaPx = -dy * 1.2          // 1.2 px per angleDelta unit (touchpad feels natural)
        var maxY = Math.max(0, flickable.contentHeight - flickable.height)
        
        // Resistance when dragging out of bounds
        if (flickable.contentY < 0 && deltaPx < 0) deltaPx *= 0.3
        if (flickable.contentY > maxY && deltaPx > 0) deltaPx *= 0.3
        
        var now = Date.now()
        var dt = now - root._lastT
        if (dt > 0 && dt < 150) {
            root._samples.push(deltaPx / dt)
            if (root._samples.length > 6) root._samples.shift()
        } else if (dt >= 150) {
            root._samples = []
        }
        root._lastT = now
        flickable.contentY = flickable.contentY + deltaPx
        _liftTimer.restart()
    }

    function _handleMouseWheel(dy) {
        _flingTimer.stop()
        _liftTimer.stop()
        root._samples = []
        var dir = dy > 0 ? -1 : 1
        var base = _wheelAnim.running ? root._targetY : flickable.contentY
        root._targetY = _clampY(base + dir * 120)    // 120 px per wheel click
        var dist = Math.abs(root._targetY - flickable.contentY)
        _wheelAnim.stop()
        _wheelAnim.from = flickable.contentY
        _wheelAnim.to   = root._targetY
        _wheelAnim.duration = Math.max(80, Math.min(200, dist * 1.5))
        _wheelAnim.start()
    }

    // =========================================================
    // MouseArea overlay — intercepts wheel before Flickable
    // acceptedButtons: Qt.NoButton → press/drag pass through to Flickable
    // =========================================================
    MouseArea {
        anchors.fill: parent
        z: 1
        acceptedButtons: Qt.NoButton
        onWheel: function(wheel) {
            var dy = wheel.angleDelta.y
            if (dy === 0) { wheel.accepted = true; return }
            // Mouse wheel: exact multiples of 120
            // Touchpad: non-multiples (high-res Wayland scroll)
            if (Math.abs(dy) % 120 === 0) {
                root._handleMouseWheel(dy)
            } else {
                root._handleTouchpad(dy)
            }
            wheel.accepted = true
        }
    }
}
