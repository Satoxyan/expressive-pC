pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.services
import QtQuick

// Several players, side by side in the dock.
//
// The card used to be bound to MprisController.activePlayer, so the dock could only ever
// show and drive whichever bus the shell happened to be tracking — a song next to a browser
// video meant the play button under one cover stopping the other. Now every bus worth a page
// gets its own card, and what is on screen is what its buttons act on.
//
// The crossing is the one the sidebar's pager already makes: two cards stand in a row, the
// row slides by exactly one card, the fingers lean it before it commits, and the indicator
// grows out of the dot in hand and is let go on the one it reached. The numbers are the
// sidebar's numbers so the two never feel different, and it is a copy rather than a shared
// component because the dock's cards are a different shape and the sidebar is not about to
// be rebuilt to prove a point.
//
// The page is kept here, not in MprisController: which media the dock is looking at is not
// the same decision as which media the whole shell follows, and the popup this card opens
// already shows one card per player.
Item {
    id: root

    readonly property var players: MprisController.pagedPlayers

    // Where the user left off, held as the bus's key rather than the object. The list this
    // indexes is rebuilt about once a second, because every player reports its position and
    // that is enough to re-evaluate the filter it came from. An index would point past the
    // end the moment a bus died; a key no longer in the list just falls back.
    property string parkedKey: ""
    readonly property int currentIndex: {
        const list = root.players
        let key = root.parkedKey
        if (key.length === 0)
            key = LyricsService.playerKey(MprisController.activePlayer)
        if (key.length > 0) {
            for (let i = 0; i < list.length; i++) {
                if (LyricsService.playerKey(list[i]) === key) return i
            }
        }
        // The parked bus is gone, or nothing was ever picked: land on the player the shell is
        // on rather than on the first page, so a death does not move the dock to a media
        // nobody asked for.
        const activeKey = LyricsService.playerKey(MprisController.activePlayer)
        for (let i = 0; i < list.length; i++) {
            if (LyricsService.playerKey(list[i]) === activeKey) return i
        }
        return 0
    }
    readonly property var currentPlayer: players[root.currentIndex] ?? null

    // The page the row stands on, or the one it is on its way to. The popup above the dock
    // turns its cards over on this the moment a swipe asks for a page, rather than after the
    // dock's card has landed, so the two frames move as one movement. A lean that stops short
    // never names a page — `pendingDir` is only written once a crossing really started.
    readonly property string pagedKey: root.settling && root.pendingDir !== 0
        ? root.keyAt(root.currentIndex + root.pendingDir)
        : LyricsService.playerKey(root.currentPlayer)

    // Whether the popup this dock opened is showing. Only that popup is being fed, so a dock
    // on another screen cannot steer the one this dock is not holding.
    readonly property bool holdsPopup: GlobalStates.mediaControlsOpen
        && GlobalStates.mediaControlsAboveDock
    onPagedKeyChanged: if (root.holdsPopup) GlobalStates.dockMediaKey = root.pagedKey

    // What Dock.qml and DockActiveApps.qml ask the card: whether there is a page worth
    // showing. A bus that carries nothing is never in the list, so this is the old
    // `trackTitle.length > 0` test read off the page in hand.
    readonly property bool hasTrack: {
        const p = root.currentPlayer
        return p !== null && (((p.trackTitle ?? "") !== "") || p.isPlaying)
    }
    readonly property bool pagingEnabled: players.length > 1

    // ── the row of cards ───────────────────────────────────────────────────
    // The slot is as long as one card; a plate is that plus the band of drop shadow on either
    // end, so two plates standing end to end are `pitch` apart and never overlap. `pageShift`
    // is how far the row has come from its resting place, measured along the dock's own axis:
    // across a dock along the bottom, down a dock running up the side.
    readonly property real bleed: Appearance.sizes.elevationMargin
    readonly property real gap: Appearance.sizes.hyprlandGapsOut
    readonly property real slotLength: DockStyle.vertical
        ? Math.max(plateA.contentLength, plateB.contentLength) + root.gap * 2
        : DockStyle.mediaLength
    readonly property real pitch: root.slotLength + root.bleed * 2

    property real pageShift: 0

    // How far the row has come into its page: 0 resting on the page it stands on, 1 with the
    // next one landed under it. The indicator reads its shape off this one number, so a lean
    // handed over to a crossing carries on from wherever it got to instead of restarting, and
    // the two can never disagree.
    readonly property real progress: Math.min(1, Math.abs(root.pageShift) / root.pitch)

    // Which way the indicator reaches, written by the lean and by the crossing. The end it
    // reaches for is always the dot one step over, so one step of the row is the whole
    // distance and no page needs naming.
    property int tailDir: 0
    property int pendingDir: 0

    // Whether that stretch is on screen at all. The dots and the stretch read this one answer
    // between them: while it is open it is the only thing lit.
    readonly property bool stretching: progress > 0.002 && tailDir !== 0
        && hasNeighbour(tailDir)

    // A crossing is running: while it is, the row's place on the page is decided, so nothing
    // else may re-point a card behind the animation.
    readonly property bool settling: crossAnim.running

    function keyAt(index) {
        if (index < 0 || index >= root.players.length) return ""
        return LyricsService.playerKey(root.players[index])
    }

    function hasNeighbour(dir) {
        return root.keyAt(root.currentIndex + dir).length > 0
    }

    function platePlayer(key) {
        if (key.length === 0) return null
        const list = root.players
        for (let i = 0; i < list.length; i++) {
            if (LyricsService.playerKey(list[i]) === key) return list[i]
        }
        return null
    }

    // The card on screen and the one waiting off to a side. Which object is which exchanges
    // at every page change, so the card you are looking at is never rebuilt — only the one
    // nobody can see is re-pointed at another player.
    function shownPlate() {
        return plateA.home === 0 ? plateA : plateB
    }

    function parkedPlate() {
        return plateA.home === 0 ? plateB : plateA
    }

    // Stand the waiting card up on the side the next page comes from, holding that page. Safe
    // whenever the row is not mid-crossing: a card that is fully off the stage can be moved
    // and re-pointed without anyone seeing it happen.
    function park(dir) {
        const key = root.keyAt(root.currentIndex + dir)
        if (key.length === 0) return false
        const plate = root.parkedPlate()
        if (plate.home !== dir || plate.key !== key) {
            plate.home = dir
            plate.key = key
        }
        return true
    }

    // Land the card that has just arrived and lift the one that has just left, which is
    // exactly where both already are at the animation's last frame: the arriving card reaches
    // home 0 and the leaving one reaches home -dir by the same assignment, so committing is
    // bookkeeping rather than a jump.
    function commit() {
        const dir = root.pendingDir
        const shown = root.shownPlate()
        const parked = root.parkedPlate()
        shown.home = -dir
        parked.home = 0
        root.pageShift = 0
        root.pendingDir = 0
        // The travelling pill is let go at the end of its trip, where it sits on exactly the
        // dot that has just become the current one, so releasing it is not a move — and it is
        // read off pageShift, so zeroing the row closes it.
        root.tailDir = 0
        root.parkedKey = parked.key
        // The second of grace is counted from the landing, not from the request that
        // started the trip: the page you have just arrived on is the one worth reading.
        root.pokeDots()
    }

    // Whether anything is holding the row: a crossing, a spring-back, or the lean of a finger
    // that has not stopped moving yet. The player list changes constantly, and the answer to
    // that has to wait for the row to be free, or a drag would be snapped out from under the
    // fingers.
    readonly property bool rowIdle: !settling && !backAnim.running
        && Math.abs(pageShift) < 0.5

    // Re-point the resting card and stand the waiting one up on the side the next page comes
    // from.
    function repoint() {
        const shown = root.shownPlate()
        shown.home = 0
        shown.key = root.keyAt(root.currentIndex)
        const parked = root.parkedPlate()
        const dir = root.hasNeighbour(1) ? 1 : (root.hasNeighbour(-1) ? -1 : 0)
        parked.home = dir === 0 ? 1 : dir
        parked.key = dir === 0 ? "" : root.keyAt(root.currentIndex + dir)
    }

    function refocus() {
        if (!root.rowIdle) return
        root.repoint()
    }

    // Put the row back on a whole page and re-point both cards no matter who was holding it:
    // the pager's own grounds changed underneath it, so there is nothing to be polite about.
    function settleRow() {
        crossAnim.stop()
        backAnim.stop()
        accumResetTimer.stop()
        root.accum = 0
        root.pendingDir = 0
        root.tailDir = 0
        root.pageShift = 0
        root.repoint()
    }

    // ── crossing a page ────────────────────────────────────────────────────
    // The whole row travels one card on the interface's standard spatial curve, which gathers
    // speed over the first sixth of the movement and gives it back over the last third, so the
    // two cards are on screen together for the middle of it. A second request before the row
    // has landed is not dropped: the crossing in flight is landed at once and the new one
    // starts from rest.
    readonly property real crossDuration: 420

    function cross(dir) {
        if (!root.pagingEnabled) return
        if (root.settling) {
            crossAnim.stop()
            root.commit()
        }
        if (!root.park(dir)) return
        backAnim.stop()
        // Whatever a lean already travelled is not paid for twice: the trip is timed off the
        // distance that is left, so a swipe and a wheel notch both arrive at roughly the same
        // unhurried speed.
        const done = Math.max(0, Math.min(root.pitch, -dir * root.pageShift))
        crossAnim.duration = Math.round(crossDuration * (1 - done / root.pitch))
        root.tailDir = dir
        root.pendingDir = dir
        crossAnim.to = -dir * root.pitch
        root.pokeDots()
        crossAnim.restart()
    }

    NumberAnimation {
        id: crossAnim
        target: root
        property: "pageShift"
        duration: 420
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animationCurves.standard
        onFinished: root.commit()
    }

    // ── leaning with the fingers ───────────────────────────────────────────
    // A touchpad drag does not have to wait for the trigger in silence: the row leans towards
    // the page it is being pulled to, up to a fraction of a card, so both frames are already on
    // screen while the fingers are still moving. A gesture that reaches the trigger hands over
    // to the crossing from wherever the row already is, without a jump, and one that stops
    // short springs back through the same distance. Nothing ever rests between pages.
    readonly property real lean: 0.22
    readonly property real leanDistance: lean * pitch

    function leanRow() {
        // Out of the run of a crossing or a spring-back: those have the row.
        if (root.settling) return
        backAnim.stop()
        const dir = root.accum > 0 ? 1 : -1
        // The end of the list does not lean, and the card on that side is stood up before it is
        // shown: pulling the row towards a side with nothing parked on it would slide a gap in
        // instead of a page.
        if (!root.park(dir)) {
            root.pageShift = 0
            root.tailDir = 0
            return
        }
        // Square of the way to the trigger, so the first touch of the finger barely stirs the
        // row — a graze should not look like a page being asked for — while a swipe that is
        // about to flip is already well on its way. The dot reads its own stretch off this same
        // place, so it leans exactly as far as the card.
        const t = Math.min(1, Math.abs(root.accum) / root.trigger)
        root.pageShift = -dir * t * t * root.leanDistance
        root.tailDir = dir
        root.pokeDots()
    }

    NumberAnimation {
        id: backAnim
        target: root
        property: "pageShift"
        to: 0
        duration: 240
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animationCurves.standard
        onFinished: root.refocus()
    }

    // ── the two cards ──────────────────────────────────────────────────────
    // The stage is the slot grown by the shadow band around it, and it is clipped: a card
    // cannot get out of it, and growing it by exactly the shadow's reach is what keeps a
    // resting card from losing its drop shadow to the cut.
    Item {
        id: stage
        anchors.fill: parent
        anchors.margins: -root.bleed
        clip: true

        DockMediaCard {
            id: plateA
            property string key: ""
            property int home: 0

            player: root.platePlayer(key)
            interactive: home === 0 && !root.settling
            // Only the axis the pages are crossed on is grown by the shadow band, because
            // that band is part of the pitch. The other one stays exactly the size of the
            // dock's slot, so the card is as tall as it was before there were two of them —
            // the row's own edge, not this clip, is what ends its shadow.
            x: DockStyle.vertical ? root.bleed : home * root.pitch + root.pageShift
            y: DockStyle.vertical ? home * root.pitch + root.pageShift : root.bleed
            width: DockStyle.vertical ? root.width : root.pitch
            height: DockStyle.vertical ? root.pitch : root.height
            // An invisible card draws nothing, so the one waiting off the side costs no artwork
            // decode, no quantizer and no blur until it is wanted.
            visible: key.length > 0 && (home === 0 || Math.abs(root.pageShift) > 0.5)
        }

        DockMediaCard {
            id: plateB
            property string key: ""
            property int home: 1

            player: root.platePlayer(key)
            interactive: home === 0 && !root.settling
            x: DockStyle.vertical ? root.bleed : home * root.pitch + root.pageShift
            y: DockStyle.vertical ? home * root.pitch + root.pageShift : root.bleed
            width: DockStyle.vertical ? root.width : root.pitch
            height: DockStyle.vertical ? root.pitch : root.height
            visible: key.length > 0 && (home === 0 || Math.abs(root.pageShift) > 0.5)
        }
    }

    // ── how long the indicator is worth showing ────────────────────────────
    // The dots only answer "which of these did I just move to", so they come up when a
    // request arrives and are given back a second after the row last moved: long enough to
    // read after a crossing, short enough that a dock nobody is scrolling looks like a dock
    // with one player. A row still travelling holds them up by itself, so a crossing that
    // outlasts the timer cannot fade its own tail.
    property bool dotsLive: false

    readonly property bool dotsMoving: root.settling || backAnim.running
        || Math.abs(root.pageShift) > 0.5
    readonly property bool dotsShown: root.pagingEnabled && (root.dotsLive || root.dotsMoving)

    function pokeDots() {
        root.dotsLive = true
        dotsIdleTimer.restart()
    }

    Timer {
        id: dotsIdleTimer
        interval: 1000
        onTriggered: root.dotsLive = false
    }

    // ── the pages ──────────────────────────────────────────────────────────
    // The dots belong to the pager and not to a card, so they stay put while the row of
    // cards slides past them, in the strip along the inner edge of the card in hand.
    //
    // A dot, not a capsule. The dock's own window-count pips are 10x4 because they stand in
    // a row's thickness, but this indicator says *which page*, which is what the sidebar's
    // dots say too — so it is sized off those, and only the tail that travels between two of
    // them is allowed to stretch.
    readonly property real pipSize: 5
    readonly property real step: pipSize * 2

    // The pips are stacked along the axis the cards are crossed on and sit on the edge of
    // the card that faces away from the screen border, so they never hide behind the strip
    // of dock that was cut off by the screen.
    readonly property bool dotsAlongDock: DockStyle.vertical
    readonly property bool dotsAtBottom: DockStyle.position !== "left"
        && DockStyle.position !== "right"

    Item {
        id: dotRow
        visible: root.pagingEnabled
        opacity: root.dotsShown ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: 350
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }
        // The group reaches from the first dot's edge to the last one's, which is one dot
        // plus a step for every further page, stacked along the axis of the crossing.
        width: root.dotsAlongDock ? root.pipSize
            : root.pipSize + Math.max(0, root.players.length - 1) * root.step
        height: root.dotsAlongDock
            ? root.pipSize + Math.max(0, root.players.length - 1) * root.step
            : root.pipSize
        anchors.horizontalCenter: root.dotsAtBottom ? parent.horizontalCenter : undefined
        anchors.verticalCenter: root.dotsAtBottom ? undefined : parent.verticalCenter
        anchors.bottom: root.dotsAtBottom ? parent.bottom : undefined
        anchors.bottomMargin: root.dotsAtBottom ? root.gap + 3 : 0
        anchors.right: !root.dotsAtBottom && DockStyle.position !== "right" ? parent.right : undefined
        anchors.rightMargin: !root.dotsAtBottom && DockStyle.position !== "right" ? root.gap + 3 : 0
        anchors.left: !root.dotsAtBottom && DockStyle.position === "right" ? parent.left : undefined
        anchors.leftMargin: !root.dotsAtBottom && DockStyle.position === "right" ? root.gap + 3 : 0
        z: 4

        Repeater {
            model: root.players.length
            delegate: Rectangle {
                required property int index

                // The dots themselves never move or change size: the step from one to the next
                // is one card, a page is always one step away, and the tail on top of them is
                // the only thing that stretches.
                width: root.pipSize
                height: root.pipSize
                x: root.dotsAlongDock ? 0 : index * root.step
                y: root.dotsAlongDock ? index * root.step : 0
                radius: Appearance.rounding.full
                // Whichever page the highlight belongs to at this moment. The one in hand
                // stands down from the first move of the row, and the one arriving takes the
                // colour on at the half — while the pill is still lying right over it, so none
                // of that fading is something anyone sees. By the time the row lands the dot
                // underneath it is already lit, and handing the highlight over costs no frame.
                readonly property bool arriving: root.stretching && root.progress > 0.5
                    && index === root.currentIndex + root.tailDir
                readonly property bool lit: arriving
                    || (index === root.currentIndex && !root.stretching)

                color: lit ? Appearance.colors.colPrimary
                    : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.4)

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }
        }

        // The tail: the dot in hand stretched towards the one it is going to, drawn over the
        // row. It goes out over the first half of the movement and comes back over the second,
        // and the two halves hold a different edge — the edge it starts from stays put while
        // the front one reaches the next dot's far side, then the front one stays put while the
        // other is drawn up to it. So the pill grows out of where the indicator stands and is
        // let go on the dot the new page is counted from, and at both ends of that it is the
        // size of a dot, which is why nothing shifts when one opens or is handed over.
        Rectangle {
            id: tailPill

            readonly property real extend: Math.min(1, root.progress * 2)
            readonly property real retract: Math.max(0, (root.progress - 0.5) * 2)
            readonly property real along: root.pipSize
                + (tailPill.extend - tailPill.retract) * root.step
            readonly property real reach: root.tailDir > 0
                ? root.currentIndex * root.step + tailPill.retract * root.step
                : root.currentIndex * root.step - tailPill.extend * root.step

            width: root.dotsAlongDock ? root.pipSize : tailPill.along
            height: root.dotsAlongDock ? tailPill.along : root.pipSize
            x: root.dotsAlongDock ? 0 : tailPill.reach
            y: root.dotsAlongDock ? tailPill.reach : 0
            radius: Appearance.rounding.full
            visible: root.stretching
            color: Appearance.colors.colPrimary
        }
    }

    // ── sizes ──────────────────────────────────────────────────────────────
    visible: root.hasTrack
    implicitWidth: DockStyle.vertical ? (parent?.width ?? 46)
        : (root.hasTrack ? root.slotLength : 0)
    implicitHeight: DockStyle.vertical ? (root.hasTrack ? root.slotLength : 0)
        : (parent?.height ?? 46)

    // The row has to draw over the icons next to it while it is moving, or a card on its way to
    // the far side would disappear behind its own neighbour.
    z: (root.settling || Math.abs(root.pageShift) > 0.5) ? 1 : 0

    Behavior on implicitWidth {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    Behavior on implicitHeight {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    // ── wheel & touchpad ───────────────────────────────────────────────────
    // Qt 6 gives a WheelHandler one orientation, not a mask, so a vertical mouse wheel and a
    // horizontal swipe need one handler each. Both are read out of the same travel: a wheel
    // and a finger lean the row and are answered together when the travel has asked for a
    // page. A touchpad still has to be asked for, because the pad sends pixels for things that
    // are not gestures at all — a palm grazing it, a jolt of the desk — and switching the media
    // player is not something to have happen by accident.
    property real accum: 0

    // Whether the travel last arriving came from a wheel. It decides how long a pause still
    // counts as the same movement, which a wheel needs far more of than a finger does.
    property bool wheelLast: false

    // Travel in the units the scroll settings work in: at the default touchpad sensitivity this
    // is a little under a centimetre of finger, which no graze reaches and no deliberate swipe
    // fails to pass.
    readonly property real trigger: 80

    // One click of a wheel, told in those units: a quarter under the trigger, so the first
    // click rolls the row onto the edge of the next page and the next one sends it over. A
    // wheel that answered here like a switch would never lean at all, and the row would look
    // like it was being teleported rather than being turned through.
    readonly property real notch: 60

    // Two readings of the same needle. Qt converts a wheel itself, at eight angle units to the
    // pixel, so a wheel is a turn whose pixels are no more than that conversion; a finger
    // pushes more screen than that for the angle it reports. High-resolution wheels arrive as
    // fractions of a hundred and twenty and are counted as fractions of a click, which is why
    // nothing here asks for an exact notch.
    function isWheel(angle, pixel) {
        return angle !== 0 && Math.abs(pixel) * 8 <= Math.abs(angle)
    }

    function handleWheel(event, horizontal) {
        const angle = horizontal ? event.angleDelta.x : event.angleDelta.y
        const pixel = horizontal ? event.pixelDelta.x : event.pixelDelta.y
        if (angle === 0 && pixel === 0) return
        const wheel = root.isWheel(angle, pixel)

        // Two fingers travelling across the screen are left alone on purpose: the dock is a thin
        // strip at the edge of the screen, and a scroll that happens to end over it was never a
        // page asked for. A wheel is not bound by this — turning it has no other direction, and
        // on a dock along the bottom it is the only way anyone will ask.
        if (!wheel && horizontal === DockStyle.vertical) return

        // Travel towards the next page, in trigger units. A positive delta means the scroll
        // engine is asking for earlier content on either axis, so both of them turn around here.
        // The touchpad sensitivity belongs to the finger, and a wheel is left in its own units:
        // the clicks of a wheel are counted by the wheel, not by how far a finger happens to
        // throw a swipe, and one setting is not allowed to make the other unreadable.
        const travel = wheel ? root.notch * (Math.abs(angle) / 120)
            : Math.abs(pixel) * Config.options.interactions.scrolling.touchpadSensitivity
        const dir = (pixel !== 0 ? pixel : angle) > 0 ? -1 : 1
        root.wheelLast = wheel
        root.accum += dir * travel
        accumResetTimer.restart()
        if (Math.abs(root.accum) < root.trigger) {
            root.leanRow()
            event.accepted = true
            return
        }
        const flip = root.accum > 0 ? 1 : -1
        root.accum = 0
        // The travel that keeps arriving after the flip was decided belongs to the same swipe,
        // and one swipe is one page asked for. A click of the wheel is its own ask, so it is
        // not made to wait for the row to land: `cross` settles the crossing in flight and
        // starts this one from rest.
        if (wheel || !root.settling) root.cross(flip)
        event.accepted = true
    }

    // Travel that stops arriving was a finished gesture, not the start of the next one: a slow
    // drag which only adds up to a page across two touches was never a page asked for, and a
    // row left leaning is given back.
    Timer {
        id: accumResetTimer
        // Two clicks half a second apart are still one wheel being turned, and a fuse short
        // enough to call them two gestures would lean the row and give it back on every click
        // that was taken deliberately.
        interval: root.wheelLast ? 600 : 150
        onTriggered: {
            root.accum = 0
            if (root.settling) return
            if (Math.abs(root.pageShift) > 0.5) backAnim.restart()
        }
    }

    WheelHandler {
        orientation: Qt.Horizontal
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        enabled: root.pagingEnabled
        // The band of shadow around the card is part of the plate and answers a click, so it
        // answers a wheel too.
        margin: root.bleed
        onWheel: event => root.handleWheel(event, true)
    }

    WheelHandler {
        orientation: Qt.Vertical
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        enabled: root.pagingEnabled
        margin: root.bleed
        onWheel: event => root.handleWheel(event, false)
    }

    // ── keeping the row honest ─────────────────────────────────────────────
    onPlayersChanged: {
        // With one page left there is nothing to be parked on, so the dock goes back to
        // following whichever player the shell is on.
        if (root.players.length <= 1) root.parkedKey = ""
        root.refocus()
    }
    onCurrentIndexChanged: root.refocus()
    onPagingEnabledChanged: root.settleRow()
    Component.onCompleted: root.settleRow()
}
