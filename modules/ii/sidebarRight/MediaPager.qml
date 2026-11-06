import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Effects

// Several players, side by side. The sidebar used to show `activePlayer` only, so
// a second bus — a browser video next to a song — could not be reached at all.
// Here the pages are laid out in a row and a flip slides the whole row by exactly a
// page, so for the length of the animation both cards are on screen, each standing
// in its own frame with its own shadow.
//
// Two cards is still a fixed cost rather than one per player — one more artwork
// download, one more quantizer, one more blur — and the card parked off the side is
// invisible until the row actually starts moving, so it draws nothing until it is
// wanted.
//
// The pages are ordered by the host's player list and each keeps its own lyric
// open/closed state, because that flag lives in the player's LyricsTrack, not here.
Item {
    id: root

    property var players: []
    property bool editMode: false
    property bool sidebarOpen: true

    // Where the user left off, kept as the bus name rather than the object: the
    // lyric registry already identifies a player by its dbus name because a player
    // handed through a model is not guaranteed to arrive as the same JS wrapper it
    // went in as. Empty means follow the player the bar is on, which is what the
    // section did before there was more than one page; the first flip sets it, and
    // closing the sidebar drops it again. The index is read out of it rather than
    // stored, so a bus dying cannot leave the pager pointing past the end of the list.
    property string parkedKey: ""
    readonly property int currentIndex: {
        const key = root.parkedKey.length > 0
            ? root.parkedKey
            : LyricsService.playerKey(MprisController.activePlayer)
        if (key.length === 0) return 0
        const list = root.players
        for (let i = 0; i < list.length; i++) {
            if (LyricsService.playerKey(list[i]) === key) return i
        }
        return 0
    }
    readonly property bool pagingEnabled: players.length > 1 && !editMode
    readonly property var currentPlayer: players[root.currentIndex] ?? null

    // Height of the row this pager sits in, off the page currently shown.
    readonly property var lyricsTrack: LyricsService.trackFor(currentPlayer)
    implicitHeight: (lyricsTrack?.lyricsOpen ?? false)
        ? 290 : (160 - Appearance.sizes.elevationMargin * 2)
    Behavior on implicitHeight {
        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
    }

    // ── the row of cards ───────────────────────────────────────────────────
    // A card is one slot wide plus the band of shadow that belongs to it, so two of
    // them standing end to end are `pitch` apart and never overlap. `pageX` is how
    // far the row has been pulled from its resting place: 0 except while a page is
    // being crossed, and both cards move by the same amount.
    readonly property real bleed: Appearance.sizes.elevationMargin
    readonly property real pitch: width + bleed * 2

    property real pageX: 0
    property int pendingDir: 0

    // How far the row has come into its page: 0 resting on the page it stands on, 1
    // with the next one landed under it. The indicator reads its whole shape off this
    // one number, so a lean handed over to a crossing carries on from wherever it
    // already got to instead of restarting, and the two can never disagree.
    readonly property real progress: Math.min(1, Math.abs(root.pageX) / root.pitch)

    // Which way the indicator reaches, written by the lean and by the crossing. The
    // end it reaches for is always the dot one step over, so one step of the row is
    // the whole distance and no page needs naming.
    property int tailDir: 0

    // Whether that stretch is on screen at all. The dots and the stretch read this
    // one answer between them: while it is open it is the only thing lit, and the dot
    // it grew out of stands down from the first move rather than waiting to be
    // relieved when the new page is landed.
    readonly property bool stretching: progress > 0.002 && tailDir !== 0
        && hasNeighbour(tailDir)

    // A crossing is running: while it is, the row's place on the page is decided, so
    // nothing else may re-point a card behind the animation.
    readonly property bool settling: crossAnim.running

    function keyAt(index) {
        if (index < 0 || index >= root.players.length) return ""
        return LyricsService.playerKey(root.players[index])
    }

    function hasNeighbour(dir) {
        return root.keyAt(root.currentIndex + dir).length > 0
    }

    // The card on screen and the one waiting off to a side. Which object is which
    // exchanges at every page change, so the card you are looking at is never
    // rebuilt — only the one nobody can see is re-pointed at another player.
    function shownPlate() {
        return plateA.home === 0 ? plateA : plateB
    }

    function parkedPlate() {
        return plateA.home === 0 ? plateB : plateA
    }

    // Stand the waiting card up on the side the next page comes from, holding that
    // page. Safe whenever the row is not mid-crossing: a card that is fully off the
    // stage can be moved and re-pointed without anyone seeing it happen.
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

    // Land the card that has just arrived and lift the one that has just left, which
    // is exactly where both already are at the animation's last frame: the arriving
    // card reaches home 0 and the leaving one reaches home -dir by the same
    // assignment, so committing is bookkeeping rather than a jump.
    function commit() {
        const dir = root.pendingDir
        const shown = root.shownPlate()
        const parked = root.parkedPlate()
        shown.home = -dir
        parked.home = 0
        root.pageX = 0
        root.pendingDir = 0
        // The travelling dot is let go at the end of its trip, where it sits on
        // exactly the dot that has just become the current one, so releasing it is
        // not a move — and it is read off pageX, so zeroing the row closes it.
        root.tailDir = 0
        root.parkedKey = parked.key
    }

    // Whether anything is holding the row: a crossing, a spring-back, or the lean of
    // a finger that has not stopped moving yet. The player list changes constantly —
    // every bus reports its position once a second, which rebuilds it — and the
    // answer to that has to wait for the row to be free, or a drag would be snapped
    // out from under the fingers.
    readonly property bool rowIdle: !settling && !backAnim.running
        && Math.abs(pageX) < 0.5

    // Re-point the resting card and stand the waiting one up on the side the next
    // page comes from.
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

    // Put the row back on a whole page and re-point both cards no matter who was
    // holding it: the pager's own grounds changed underneath it, so there is nothing
    // to be polite about.
    function settleRow() {
        crossAnim.stop()
        backAnim.stop()
        accumResetTimer.stop()
        root.accum = 0
        root.pendingDir = 0
        root.tailDir = 0
        root.pageX = 0
        root.repoint()
    }

    // ── crossing a page ────────────────────────────────────────────────────
    // The whole row travels one card width on the interface's standard spatial
    // curve, which gathers speed over the first sixth of the movement and gives it
    // back over the last third, so the two frames are on screen together for the
    // middle of it. A second request before the row has landed is not dropped: the
    // wheel does not know how long an animation takes, so the crossing in flight is
    // landed at once and the new one starts from rest.
    readonly property real crossDuration: 420

    function cross(dir) {
        if (!root.pagingEnabled) return
        if (root.settling) {
            crossAnim.stop()
            root.commit()
        }
        if (!root.park(dir)) return
        backAnim.stop()
        // Whatever a lean already travelled is not paid for twice: the trip is timed
        // off the distance that is left, so a swipe and a wheel notch both arrive at
        // roughly the same unhurried speed.
        const done = Math.max(0, Math.min(root.pitch, -dir * root.pageX))
        crossAnim.duration = Math.round(crossDuration * (1 - done / root.pitch))
        root.tailDir = dir
        root.pendingDir = dir
        crossAnim.to = -dir * root.pitch
        crossAnim.restart()
    }

    NumberAnimation {
        id: crossAnim
        target: root
        property: "pageX"
        duration: 420
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animationCurves.standard
        onFinished: root.commit()
    }

    // ── leaning with the fingers ───────────────────────────────────────────
    // A touchpad drag does not have to wait for the trigger in silence: the row
    // leans towards the page it is being pulled to, up to a fraction of a width, so
    // both frames are already on screen while the fingers are still moving. The lean
    // is measured off the same accumulated travel that decides the flip, which means
    // a gesture that reaches the trigger hands over to the crossing animation from
    // wherever the row already is, without a jump, and one that stops short springs
    // back through the same distance. Nothing ever rests between two pages.
    readonly property real lean: 0.22
    readonly property real leanDistance: lean * pitch

    function leanRow() {
        // Out of the run of a crossing or a spring-back: those have the row.
        if (root.settling) return
        backAnim.stop()
        const dir = root.accum > 0 ? 1 : -1
        // The end of the list does not lean, and the card on that side is stood up
        // before it is shown: pulling the row towards a side with nothing parked on
        // it would slide a gap in instead of a page.
        if (!root.park(dir)) {
            root.pageX = 0
            root.tailDir = 0
            return
        }
        // Square of the way to the trigger, so the first touch of the finger barely
        // stirs the row — a graze should not look like a page being asked for — while
        // a swipe that is about to flip is already well on its way. The dot reads its
        // own stretch off this same place, so it leans exactly as far as the card.
        const t = Math.min(1, Math.abs(root.accum) / root.trigger)
        root.pageX = -dir * t * t * root.leanDistance
        root.tailDir = dir
    }

    NumberAnimation {
        id: backAnim
        target: root
        property: "pageX"
        to: 0
        duration: 240
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animationCurves.standard
        onFinished: root.refocus()
    }

    // ── the two cards ──────────────────────────────────────────────────────
    // The stage is the slot grown by the shadow band around it, and it is clipped: a
    // card cannot get out of it, and it sits inside the sidebar, so nothing ever
    // crosses the panel's border. Growing it by exactly the shadow's reach is what
    // keeps a resting card from losing its drop shadow to the cut.
    //
    // While the row is moving a second, tighter cut is laid over that: `slideWindow`
    // is the card's own box, so the side a card disappears behind is rounded exactly
    // like the corner it shows at rest instead of being sliced by a flat edge. It is
    // only there while the row travels, because a window that hugs the card cannot
    // carry the card's shadow, and a resting card should keep it.
    readonly property rect slideWindow: plateA.paintedBox

    // The mask is drawn at the stage's own size and the window is placed inside it,
    // because an effect mask is stretched over whatever it is applied to.
    Item {
        id: slideMask
        width: stage.width
        height: stage.height
        visible: false
        layer.enabled: true

        Rectangle {
            x: root.slideWindow.x
            y: root.slideWindow.y
            width: root.slideWindow.width
            height: root.slideWindow.height
            radius: plateA.paintedRadius
            color: "white"
        }
    }

    Item {
        id: stage
        anchors.fill: parent
        anchors.margins: -root.bleed
        clip: true
        layer.enabled: Math.abs(root.pageX) > 0.5
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: slideMask
        }

        Player {
            id: plateA
            property string key: ""
            property int home: 0

            x: home * root.pitch + root.pageX
            y: 0
            width: stage.width
            height: stage.height
            // An invisible card draws nothing, so the one waiting off the side costs
            // no blur and no visualizer until it is wanted.
            visible: key.length > 0 && (home === 0 || Math.abs(root.pageX) > 0.5)
            player: {
                const list = root.players
                for (let i = 0; i < list.length; i++) {
                    if (LyricsService.playerKey(list[i]) === key) return list[i]
                }
                return null
            }
            visualizerPoints: GlobalStates.visualizerPoints
            radius: Appearance.rounding.normal
        }

        Player {
            id: plateB
            property string key: ""
            property int home: 1

            x: home * root.pitch + root.pageX
            y: 0
            width: stage.width
            height: stage.height
            visible: key.length > 0 && (home === 0 || Math.abs(root.pageX) > 0.5)
            player: {
                const list = root.players
                for (let i = 0; i < list.length; i++) {
                    if (LyricsService.playerKey(list[i]) === key) return list[i]
                }
                return null
            }
            visualizerPoints: GlobalStates.visualizerPoints
            radius: Appearance.rounding.normal
        }
    }

    // Player asks for its song's lyrics once, when it is made; a page reached only by
    // crossing would otherwise never be searched for.
    onCurrentPlayerChanged: LyricsService.ensureFor(currentPlayer)

    onPlayersChanged: root.refocus()
    onCurrentIndexChanged: root.refocus()
    onPagingEnabledChanged: root.settleRow()
    Component.onCompleted: root.settleRow()

    onSidebarOpenChanged: if (!sidebarOpen) {
        root.parkedKey = ""
        root.settleRow()
    }

    // ── wheel & touchpad ───────────────────────────────────────────────────
    // Qt 6 gives a WheelHandler one orientation, not a mask, so a vertical mouse
    // wheel and a horizontal swipe need one handler each. Both turn their event into
    // pixels of travel before anything else, so a diagonal swipe adds up instead of
    // cancelling out.
    //
    // The row is never parked halfway between two pages: a request crosses a whole
    // page or nothing. A touchpad still has to be asked for, because the pad sends
    // pixels for things that are not gestures at all — a palm grazing it, a jolt of
    // the desk, the first third of a scroll down the sidebar — and switching the
    // media player is not something to have happen by accident.
    property real accum: 0

    // Travel in the units the scroll settings work in: at the default touchpad
    // sensitivity this is a little under a centimetre of finger, which no graze
    // reaches and no deliberate swipe fails to pass.
    readonly property real trigger: 80

    function handleWheel(event, horizontal) {
        const angle = horizontal ? event.angleDelta.x : event.angleDelta.y
        const pixel = horizontal ? event.pixelDelta.x : event.pixelDelta.y
        if (angle === 0 && pixel === 0) {
            // The end of a gesture is nothing special here: the row is either on a
            // page or already on its way to the next one.
            return
        }

        // A positive delta means the scroll engine is asking for earlier content on
        // either axis — the finger went right, or the wheel went up — so both axes
        // turn into the same number here: pixels of travel towards the next page.
        const step = (pixel !== 0 ? pixel : angle) * -1

        // A wheel notch arrives as an exact multiple of 120 with no pixels attached;
        // a touchpad does not. Same test the scroll engines use.
        if (angle !== 0 && pixel === 0 && Math.abs(angle) % 120 === 0) {
            root.cross(step > 0 ? 1 : -1)
            event.accepted = true
            return
        }

        root.accum += step * Config.options.interactions.scrolling.touchpadSensitivity
        accumResetTimer.restart()
        if (Math.abs(root.accum) < root.trigger) {
            root.leanRow()
            event.accepted = true
            return
        }
        const dir = root.accum > 0 ? 1 : -1
        root.accum = 0
        // One page per gesture: the travel that keeps arriving after the flip was
        // decided belongs to the same swipe, and a swipe is one page asked for.
        if (!root.settling) root.cross(dir)
        event.accepted = true
    }

    // Travel that stops arriving was a finished gesture, not the start of the next
    // one: a slow drag which only adds up to a page across two touches was never a
    // page asked for, and a row left leaning is given back.
    Timer {
        id: accumResetTimer
        interval: 150
        onTriggered: {
            root.accum = 0
            if (root.settling) return
            if (Math.abs(root.pageX) > 0.5) backAnim.restart()
        }
    }

    WheelHandler {
        orientation: Qt.Vertical
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        enabled: root.pagingEnabled
        margin: Appearance.sizes.elevationMargin
        onWheel: event => root.handleWheel(event, false)
    }

    WheelHandler {
        orientation: Qt.Horizontal
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        enabled: root.pagingEnabled
        margin: Appearance.sizes.elevationMargin
        onWheel: event => root.handleWheel(event, true)
    }

    // ── how many pages there are ───────────────────────────────────────────
    // Centred along the bottom, in the strip under the controls row that holds
    // nothing else. With the lyric open that row runs the full width of the card and
    // the dots would sit on the seek bar — and there the song's own text already says
    // whose card this is. The dots belong to the pager and not to a card, so they
    // stay put while the row of cards slides past them.
    //
    // Placed rather than laid out by a Row: the positioner left every delegate at x 0
    // and itself 0 wide, so three dots printed as one.
    Item {
        id: dotRow
        visible: root.pagingEnabled && !(root.lyricsTrack?.lyricsOpen ?? false)
        width: root.players.length * 5 + Math.max(0, root.players.length - 1) * 5
        height: 5
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 5

        Repeater {
            model: root.players.length
            delegate: Rectangle {
                required property int index

                // The dots themselves never move or change size: the step from one to
                // the next is ten, a page is always one step away, and the tail on top
                // of them is the only thing that stretches.
                width: 5
                height: 5
                x: index * 10
                radius: height / 2
                // Whichever page the highlight belongs to at this moment. The one in
                // hand stands down from the first move of the row, and the one arriving
                // takes the colour on at the half — while the pill is still lying right
                // over it, so none of that fading is something anyone sees. By the time
                // the row lands the dot underneath it is already lit, and handing the
                // highlight over costs no frame at all: the pill goes away and the dot
                // it was sitting on does not change.
                readonly property bool arriving: root.stretching && root.progress > 0.5
                    && index === root.currentIndex + root.tailDir
                readonly property bool lit: arriving
                    || (index === root.currentIndex && !root.stretching)

                color: lit ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                opacity: lit ? 1 : 0.45

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }
        }

        // The tail: the dot in hand stretched towards the one it is going to, drawn
        // over the row. It goes out over the first half of the movement and comes back
        // over the second, and the two halves hold a different edge — the edge it
        // starts from stays put while the front one reaches the next dot's far side,
        // then the front one stays put while the other is drawn up to it. So the pill
        // grows out of where the indicator stands and is let go on the dot the new page
        // is counted from, and at both ends of that it is the size of a dot, which is
        // why nothing shifts when one opens or is handed over.
        Rectangle {
            id: tailPill

            readonly property real extend: Math.min(1, root.progress * 2)
            readonly property real retract: Math.max(0, (root.progress - 0.5) * 2)

            width: 5 + (tailPill.extend - tailPill.retract) * 10
            height: 5
            x: root.tailDir > 0
                ? root.currentIndex * 10 + tailPill.retract * 10
                : root.currentIndex * 10 - tailPill.extend * 10
            radius: height / 2
            visible: root.stretching
            color: Appearance.colors.colPrimary
        }
    }
}
