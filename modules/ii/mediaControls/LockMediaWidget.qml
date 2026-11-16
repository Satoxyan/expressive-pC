pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.mediaControls

// Full media player on the lockscreen (same as desktop; compact mode removed).
Item {
    id: root

    required property MprisPlayer player
    required property real radius
    property list<real> visualizerPoints: []

    // The pages a swipe can reach. LockSurface passes the same list the dock uses;
    // with one player this is just that player and nothing moves.
    property var players: []

    readonly property var pageList: {
        const list = Array.from(root.players ?? [])
        if (list.length > 0) return list
        return root.player ? [root.player] : []
    }
    readonly property bool pagingEnabled: root.pageList.length > 1

    function keyOf(p) {
        return LyricsService.playerKey(p)
    }

    // Where the user left off is the shell's own choice: a swipe on the lock screen
    // selects the player the same way the bar does, so the small media row and this
    // card always show the same one.
    readonly property int currentIndex: {
        const list = root.pageList
        const key = root.keyOf(root.player)
        for (let i = 0; i < list.length; i++) {
            if (root.keyOf(list[i]) === key) return i
        }
        return 0
    }

    // The page actually drawn. It lags `currentIndex` for the length of a swap, so the
    // card in hand can leave before the new one is put in its place.
    property int displayIndex: 0
    property bool ready: false
    readonly property MprisPlayer currentPlayer: root.pageList[root.displayIndex] ?? root.player
    // The card is not rebuilt when the page changes, so the new song's lyrics have to
    // be asked for here; `Player` only does that when it is first made.
    onCurrentPlayerChanged: LyricsService.ensureFor(root.currentPlayer)

    // Exposed so LockSurface can still read dominant color for bg tinting, etc.
    readonly property color artDominantColor: mediaPlayer.artDominantColor
    readonly property string displayedArtFilePath: mediaPlayer.displayedArtFilePath

    // Sizes — must match what LockSurface passes in
    readonly property real fullWidth: Appearance.sizes.mediaControlsWidth
    readonly property real fullHeight: mediaPlayer.showLyrics ? 290 : Appearance.sizes.mediaControlsHeight

    implicitWidth: fullWidth
    implicitHeight: fullHeight
    width: implicitWidth
    height: implicitHeight

    // Animate the height snap when lyrics open/close
    Behavior on implicitHeight {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.OutExpo
        }
    }

    // ── sliding between pages ─────────────────────────────────────────────
    // The card in hand leaves first and the page asked for arrives after it, rather than
    // both crossing at once: the lockscreen has one card's worth of room, and swapping
    // the player at the invisible midpoint is what keeps the new artwork from flashing
    // in under the old one.
    property int pendingDir: 0
    property int pendingIndex: 0
    property real slideX: 0
    property real contentOpacity: 1

    function turn(dir) {
        if (!root.pagingEnabled || swapAnim.running) return
        const next = root.currentIndex + dir
        if (next < 0 || next >= root.pageList.length) return
        MprisController.manualPlayer = root.pageList[next]
    }

    // The active player changed underneath us (a swipe on the small media row, a bus
    // starting, or the current one dying): give it the same out-then-in, so the
    // lockscreen never swaps a card in place.
    function followActive() {
        if (swapAnim.running) return
        if (root.currentIndex === root.displayIndex) return
        root.pendingDir = root.currentIndex > root.displayIndex ? 1 : -1
        root.pendingIndex = root.currentIndex
        swapAnim.restart()
    }

    onCurrentIndexChanged: if (root.ready) root.followActive()
    onPageListChanged: {
        if (!root.ready) return
        if (root.displayIndex >= root.pageList.length)
            root.displayIndex = Math.max(0, root.pageList.length - 1)
        root.followActive()
    }
    Component.onCompleted: {
        root.displayIndex = root.currentIndex
        root.ready = true
    }

    SequentialAnimation {
        id: swapAnim
        // A request that arrived while the card was already moving is served after it
        // lands, so a quick second swipe is not lost.
        onFinished: Qt.callLater(root.followActive)
        // Keluar: kartu yang sedang dibaca bergeser ke arah geseran lalu memudar.
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "slideX"
                to: -root.pendingDir * root.width * 0.35
                duration: 160
                easing.type: Easing.InCubic
            }
            NumberAnimation {
                target: root
                property: "contentOpacity"
                to: 0
                duration: 120
                easing.type: Easing.InCubic
            }
        }
        ScriptAction {
            script: {
                root.displayIndex = root.pendingIndex
                root.slideX = root.pendingDir * root.width * 0.35
            }
        }
        // Masuk: halaman yang diminta menyusul dari sisi seberang.
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "slideX"
                to: 0
                duration: 300
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: root
                property: "contentOpacity"
                to: 1
                duration: 240
                easing.type: Easing.OutCubic
            }
        }
    }

    Item {
        id: content
        width: root.width
        height: root.height
        x: root.slideX
        opacity: root.contentOpacity

        Player {
            id: mediaPlayer
            width: parent.width
            height: parent.height
            player: root.currentPlayer
            visualizerPoints: root.visualizerPoints
            radius: root.radius
        }
    }

    // ── wheel & touchpad ───────────────────────────────────────────────────
    // Same needle as the dock and the sidebar: a mouse notch is an exact multiple of
    // 120 on the angle axis, a finger is everything else. The lockscreen has nothing
    // else to scroll, so either axis is allowed to ask for a page.
    property real accum: 0
    property real wheelTravel: 0
    property bool wheelLast: false
    readonly property real trigger: 180

    function isWheel(angle) {
        return angle !== 0 && Math.abs(angle) % 120 === 0
    }

    function handleWheel(event, horizontal) {
        const angle = horizontal ? event.angleDelta.x : event.angleDelta.y
        const pixel = horizontal ? event.pixelDelta.x : event.pixelDelta.y
        if (angle === 0 && pixel === 0) return
        const wheel = root.isWheel(angle)
        root.wheelLast = wheel
        accumResetTimer.restart()

        if (wheel) {
            root.wheelTravel += (angle * -1) / 120
            while (Math.abs(root.wheelTravel) >= 1) {
                const dir = root.wheelTravel > 0 ? 1 : -1
                root.wheelTravel -= dir
                root.turn(dir)
            }
            event.accepted = true
            return
        }

        root.accum += (pixel !== 0 ? pixel : angle) * -1
            * Config.options.interactions.scrolling.touchpadSensitivity
        if (Math.abs(root.accum) < root.trigger) {
            event.accepted = true
            return
        }
        const dir = root.accum > 0 ? 1 : -1
        root.accum = 0
        root.turn(dir)
        event.accepted = true
    }

    Timer {
        id: accumResetTimer
        // Two clicks half a second apart are still one wheel being turned.
        interval: root.wheelLast ? 600 : 150
        onTriggered: {
            root.accum = 0
            root.wheelTravel = 0
        }
    }

    WheelHandler {
        orientation: Qt.Horizontal
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        enabled: root.pagingEnabled
        onWheel: event => root.handleWheel(event, true)
    }

    WheelHandler {
        orientation: Qt.Vertical
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        enabled: root.pagingEnabled
        onWheel: event => root.handleWheel(event, false)
    }
}
