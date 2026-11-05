pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import qs.modules.common.models
import qs
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

Item {
    id: root
    property color contentColor: Appearance.colors.colOnSecondaryContainer
    property bool contentColorOverridden: false
    signal styleEditorRequested()
    
    property bool vertical: false
    property bool borderless: Config.options.bar.borderless
    property bool isMaterial: Config.options.bar.cornerStyle === 3 || Config.options.bar.cornerStyle === 4
    readonly property MprisPlayer activePlayer: MprisController.activePlayer

    readonly property string cleanedTitle: StringUtils.cleanMusicTitle(activePlayer?.trackTitle) || Translation.tr("No media")

    property var    artUrl:      activePlayer?.trackArtUrl ?? ""
    property string trackTitle:  activePlayer?.trackTitle  ?? ""
    property string trackArtist: activePlayer?.trackArtist ?? ""
    property bool   isPlaying:   activePlayer?.isPlaying   ?? false
    property bool   hasTrack:    trackTitle.length > 0

    property string artDownloadLocation: Directories.coverArt
    property string artFileName:         Qt.md5(artUrl)
    property string artFilePath:         `${artDownloadLocation}/${artFileName}`
    property bool   artDownloaded:       Boolean(root.artUrl && (root.artUrl.startsWith("data:") || root.artUrl.startsWith("file:/") || root.artUrl.startsWith("/")))

    property string displayedArtFilePath: {
        if (!root.artUrl || root.artUrl.length === 0) return ""
        if (root.artUrl.startsWith("data:")) return root.artUrl
        if (root.artUrl.startsWith("file:/")) return root.artUrl
        if (root.artUrl.startsWith("/")) return "file://" + root.artUrl
        if (!root.artDownloaded) return ""
        return Qt.resolvedUrl(artFilePath)
    }

    onArtFilePathChanged: {
        if (!root.artUrl || root.artUrl.length === 0) {
            root.artDownloaded = false
            return
        }
        if (root.artUrl.startsWith("data:") || root.artUrl.startsWith("file:/") || root.artUrl.startsWith("/")) {
            root.artDownloaded = true
            return
        }
        if (root.artUrl.startsWith("http://") || root.artUrl.startsWith("https://")) {
            artDownloader.targetFile  = root.artUrl
            artDownloader.artFilePath = root.artFilePath
            root.artDownloaded = false
            artDownloader.running = true
        } else {
            root.artDownloaded = true
        }
    }

    Process {
        id: artDownloader
        property string targetFile:  root.artUrl
        property string artFilePath: root.artFilePath
        command: ["bash", "-c",
            `[ -f ${artFilePath} ] || curl -sSL '${targetFile}' -o '${artFilePath}'`]
        onExited: { root.artDownloaded = true }
    }

    Layout.fillHeight: true
    implicitWidth: vertical 
        ? Appearance.sizes.verticalBarWidth 
        : (isMaterial 
            ? materialRow.implicitWidth 
            : Math.max(
                Config.options.bar.media.minWidth,
                Math.min(rowLayout.implicitWidth + 8, Config.options.bar.media.maxWidth)
            ))
    implicitHeight: vertical ? (isMaterial ? 32 : mediaCircProg.implicitHeight + 12) : Appearance.sizes.barHeight

    Timer {
        running: activePlayer?.playbackState == MprisPlaybackState.Playing
        interval: Config.options.resources.updateInterval
        repeat: true
        onTriggered: activePlayer.positionChanged()
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.MiddleButton | Qt.BackButton | Qt.ForwardButton | Qt.RightButton | Qt.LeftButton
        hoverEnabled: !Config.options.bar.tooltips.clickToShow
        onPressed: (event) => {
            if (event.button === Qt.MiddleButton)      activePlayer?.togglePlaying()
            else if (event.button === Qt.BackButton)   activePlayer?.previous()
            else if (event.button === Qt.ForwardButton) activePlayer?.next()
            else if (event.button === Qt.LeftButton) {
                // The popup stands where the thing that asked for it stands. The dock's card
                // says so when it is clicked, and nothing ever says it on the way out, so a
                // click from the bar has to ask for the bar's own place rather than inherit
                // wherever the last popup happened to be standing.
                GlobalStates.mediaControlsAboveDock = false
                // Where along the bar this widget is, so the card column runs to it. The bar
                // window spans the whole screen along its own edge, so the coordinate in that
                // edge's direction is already a screen one, and a bar that lies flat leaves
                // that direction free for the popup to stand in.
                const here = root.mapToItem(null, root.width / 2, root.height / 2)
                GlobalStates.mediaControlsAnchorX = here.x
                GlobalStates.mediaControlsAnchorY = here.y
                GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen
            }
        }
        onClicked: (event) => {
            if (event.button === Qt.RightButton) activePlayer?.next()
        }
        onPressAndHold: (event) => {
            if (event.button === Qt.RightButton) root.styleEditorRequested()
        }
    }

    // ── paging the players the bar can show ────────────────────────────────
    // The bar draws one player at a time, so a swipe here moves no row: it chooses
    // which bus the bar stands on, and everything that follows the bar's player —
    // the popup's order, the lyrics, the buttons above — comes along with it. The
    // list is the one worth paging over, every real bus carrying something, kept
    // narrow when the preferred-player setting names more than one of them.
    readonly property var pagePlayers: {
        const list = MprisController.pagedPlayers
        const preferred = MprisController.preferredPlayerName
        if (preferred.length === 0) return list
        const hit = list.filter(p => (p.identity ?? "").toLowerCase().includes(preferred)
            || (p.desktopEntry ?? "").toLowerCase().includes(preferred))
        return hit.length > 0 ? hit : list
    }
    readonly property string shownKey: LyricsService.playerKey(root.activePlayer)
    readonly property int pageIndex: {
        const list = root.pagePlayers
        for (let i = 0; i < list.length; i++) {
            if (LyricsService.playerKey(list[i]) === root.shownKey) return i
        }
        return 0
    }
    readonly property bool pagingEnabled: root.pagePlayers.length > 1

    // Which side the new words arrive from: the direction of the page that was last
    // turned, and forward for a change nobody turned (a track ending on its own).
    readonly property int enterDir: slideDir === 0 ? 1 : slideDir
    property int slideDir: 0

    function turnPage(dir) {
        const n = root.pagePlayers.length
        if (n < 2) return
        // Round the end rather than stop at it: nothing in a bar shows where the
        // list begins, so a page that runs off one side comes back on the other
        // instead of leaving a swipe with nothing to answer it.
        const to = (root.pageIndex + dir + n) % n
        if (to === root.pageIndex) return
        root.slideDir = dir
        MprisController.manualPlayer = root.pagePlayers[to]
    }

    // A wheel notch and a finger are told apart the way the dock does it: Qt turns a
    // notch into pixels itself, at eight angle units to the pixel, so a movement that
    // asks for no more screen than that conversion is a wheel.
    function isWheel(angle, pixel) {
        return angle !== 0 && Math.abs(pixel) * 8 <= Math.abs(angle)
    }

    property real accum: 0

    // A wheel's travel, told in whole pages: one notch is one page, and a wheel that
    // reports its clicks in fractions of one (a smooth-scrolling mouse, or Hyprland's
    // scroll multiplier) has to add up to a page before anything is turned.
    property real wheelTravel: 0

    // Whether the travel last arriving came from a wheel. It decides how long a pause
    // still counts as the same movement, which a wheel needs far more of than a finger
    // does.
    property bool wheelLast: false

    // Travel in the units the scroll settings work in; at the default touchpad
    // sensitivity a little under a centimetre of finger, which no palm graze reaches
    // and no flick on its way to something else carries.
    readonly property real trigger: 180

    // Whether this touchpad movement has already been given a page. A swipe reaches Qt
    // as a long stream of small deltas rather than as one movement, so travel past the
    // demand would keep turning: the bar, which rounds at its ends, would read as a
    // loop instead of as the one page the swipe asked for.
    property bool swipeSpent: false

    function handleWheel(event, horizontal) {
        const angle = horizontal ? event.angleDelta.x : event.angleDelta.y
        const pixel = horizontal ? event.pixelDelta.x : event.pixelDelta.y
        if (angle === 0 && pixel === 0) return
        const wheel = root.isWheel(angle, pixel)

        // Two fingers travelling across the bar's thickness are the thing under the
        // pointer moving, not a page asked for. A wheel is not bound by this: it has
        // no other direction to be asked in, and over a bar lying flat it is the only
        // way anyone will turn a page.
        if (!wheel && horizontal === root.vertical) return

        root.wheelLast = wheel

        // A wheel is counted in its own units: on Wayland the pixels attached to a notch
        // are Qt's conversion of the angle it carried, so counting them as travel would
        // make a click worth an eighth of a page. A positive angle asks for the earlier
        // page, so it is turned around here.
        if (wheel) {
            root.wheelTravel += (angle * -1) / 120
            accumResetTimer.restart()
            // Travel left over after a page is turned is kept rather than dropped, so
            // a fast wheel is pages in order and not clicks thrown away.
            while (Math.abs(root.wheelTravel) >= 1) {
                const dir = root.wheelTravel > 0 ? 1 : -1
                root.wheelTravel -= dir
                root.turnPage(dir)
            }
            event.accepted = true
            return
        }

        // A finger is asked the same way round: a positive delta means the earlier page,
        // so both are turned into travel towards the next one.
        const step = pixel * -1
        root.accum += step * Config.options.interactions.scrolling.touchpadSensitivity
        accumResetTimer.restart()
        // Travel still arriving after the page was given is the rest of the same swipe,
        // and the swipe that follows will have stopped long enough here for this to be
        // let go.
        if (root.swipeSpent) {
            event.accepted = true
            return
        }
        if (Math.abs(root.accum) < root.trigger) {
            event.accepted = true
            return
        }
        const dir = root.accum > 0 ? 1 : -1
        root.accum = 0
        root.swipeSpent = true
        root.turnPage(dir)
        event.accepted = true
    }

    // Travel that stops arriving was a finished gesture, not the first third of the
    // next one: a slow drag that only adds up to a page across two touches was never
    // a page asked for, and a wheel that was paused between two clicks was asked for
    // twice.
    Timer {
        id: accumResetTimer
        // Two clicks half a second apart are still one wheel being turned, so a fuse
        // short enough to call them two gestures would throw the first one away.
        interval: root.wheelLast ? 600 : 150
        onTriggered: {
            root.accum = 0
            root.wheelTravel = 0
            root.swipeSpent = false
        }
    }

    // Qt 6 gives a WheelHandler one orientation, not a mask, so a vertical mouse
    // wheel and a horizontal swipe need one handler each.
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

    // A choice is only worth keeping while the bus it names is still there: a player
    // that has gone would otherwise leave the bar showing nothing and refusing to
    // follow whoever starts playing, because the chosen player outranks the tracked
    // one. Handing the choice back is what the automatic tracking expects.
    Connections {
        target: MprisController
        function onPlayersChanged() {
            const p = MprisController.manualPlayer
            if (p && !MprisController.players.includes(p))
                MprisController.manualPlayer = null
        }
    }

    // Vertical default
    Loader {
        id: mediaCircProg
        active: root.vertical && !root.isMaterial
        visible: active
        anchors.centerIn: parent
        sourceComponent: ClippedFilledCircularProgress {
            implicitSize: 20
            lineWidth: Appearance.rounding.unsharpen
            value: root.activePlayer?.position / root.activePlayer?.length
            colPrimary: root.contentColor
            enableAnimation: false
            Item {
                anchors.centerIn: parent
                width: 20
                height: 20
                MaterialSymbol {
                    anchors.centerIn: parent
                    fill: 1
                    text: root.activePlayer?.isPlaying ? "pause" : "music_note"
                    iconSize: Appearance.font.pixelSize.normal
                    color: root.contentColor
                }
            }
        }
    }

    // Vertical Material
    Rectangle {
        visible: root.vertical && root.isMaterial
        anchors.centerIn: parent
        color: Appearance.colors.colSecondaryContainer
        radius: Appearance.rounding.full
        implicitWidth: 32
        implicitHeight: 32
        
        MaterialSymbol {
            anchors.centerIn: parent
            fill: 1
            text: root.activePlayer?.isPlaying ? "pause" : "music_note"
            iconSize: Appearance.font.pixelSize.normal
            color: root.contentColor
        }
    }

    // Horizontal default
    Loader {
        id: rowLayout
        active: !root.vertical && !root.isMaterial
        visible: active
        anchors.fill: parent
        sourceComponent: RowLayout {
            spacing: 4
            ClippedFilledCircularProgress {
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 3
                implicitSize: 20
                lineWidth: Appearance.rounding.unsharpen
                value: root.activePlayer?.position / root.activePlayer?.length
                colPrimary: root.contentColor
                enableAnimation: false
                Item {
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    MaterialSymbol {
                        anchors.centerIn: parent
                        fill: 1
                        text: root.activePlayer?.isPlaying ? "pause" : "music_note"
                        iconSize: Appearance.font.pixelSize.normal
                        color: root.contentColor
                    }
                }
            }
            StyledText {
                id: flatWords
                visible: Config.options.bar.verbose
                Layout.alignment: Qt.AlignVCenter
                Layout.fillWidth: true
                Layout.rightMargin: 0
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                color: root.contentColorOverridden ? root.contentColor : Appearance.colors.colOnLayer1
                text: Config.options.bar.media.onlyTitle ? root.cleanedTitle : `${root.cleanedTitle}${root.activePlayer?.trackArtist ? ' • ' + root.activePlayer.trackArtist : ''}`
                Behavior on text {
                    // The same turn the material style shows, told in the one line this
                    // style writes the two of them into.
                    SequentialAnimation {
                        ParallelAnimation {
                            NumberAnimation { target: flatWords; property: "x"; to: -flatWords.width * root.enterDir; duration: 150; easing.type: Easing.InQuad }
                            NumberAnimation { target: flatWords; property: "opacity"; to: 0; duration: 150; easing.type: Easing.InQuad }
                        }
                        PropertyAction { target: flatWords; property: "text" }
                        ParallelAnimation {
                            NumberAnimation { target: flatWords; property: "x"; from: flatWords.width * root.enterDir; to: 0; duration: 150; easing.type: Easing.OutQuad }
                            NumberAnimation { target: flatWords; property: "opacity"; from: 0; to: 1; duration: 150; easing.type: Easing.OutQuad }
                        }
                    }
                }
            }
        }
    }

    // Horizontal Material
    Loader {
        id: materialRow
        active: !root.vertical && root.isMaterial
        visible: active
        anchors.centerIn: parent
        sourceComponent: RowLayout {
            id: innerRow
            anchors.centerIn: parent
            spacing: 6

            // No platyer 
            Loader {
                active: !root.hasTrack
                visible: active
                Layout.alignment: Qt.AlignVCenter
                sourceComponent: RowLayout {
                    spacing: 6

                    // Avatar
                    UserAvatar {
                        implicitWidth: 26
                        implicitHeight: 26
                        Layout.alignment: Qt.AlignVCenter

                        Layout.leftMargin: -2
                        iconSize: Appearance.font.pixelSize.normal
                    }

                    ColumnLayout {
                        spacing: -3
                        Layout.alignment: Qt.AlignVCenter
                        Layout.topMargin: 2

                        StyledText {
                            text: Config.options.profile.displayName === "" ? SystemInfo.username : Config.options.profile.displayName
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: root.contentColor
                            elide: Text.ElideRight
                            Layout.maximumWidth: 120
                        }

                        StyledText {
                            id: distroLabel
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: root.contentColor
                            opacity: 0.7
                            elide: Text.ElideRight
                            Layout.rightMargin: 8
                            Layout.maximumWidth: 120
                            text: SystemInfo.distroName
                        }
                    }
                }
            }

            // Player
            Loader {
                active: root.hasTrack
                visible: active
                Layout.alignment: Qt.AlignVCenter
                sourceComponent: RowLayout {
                    spacing: 6

                    // Art
                    Rectangle {
                        id: artRect
                        implicitWidth: 26
                        implicitHeight: 26
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colSecondaryContainer
                        Layout.alignment: Qt.AlignVCenter
                        Layout.leftMargin: -2

                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: artRect.width
                                height: artRect.height
                                radius: artRect.radius
                            }
                        }

                        StyledImage {
                            anchors.fill: parent
                            source: root.displayedArtFilePath
                            fillMode: Image.PreserveAspectCrop
                            cache: false
                            antialiasing: true
                            sourceSize.width: artRect.width
                            sourceSize.height: artRect.height
                            visible: root.displayedArtFilePath !== ""
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            fill: 1
                            text: "music_note"
                            iconSize: Appearance.font.pixelSize.normal
                            color: root.contentColor
                            visible: root.displayedArtFilePath === ""
                        }
                    }

                    // Title + Artist
                    ColumnLayout {
                        id: shownLines
                        spacing: -4
                        Layout.alignment: Qt.AlignVCenter
                        Layout.topMargin: 2

                        // The two lines fade together while each slides on its own. The
                        // fade has to be asked of the pair rather than of a line, because
                        // one of them keeps its dimming as a binding and an animation
                        // would take it over when it finished.
                        property string shownWords: `${root.trackTitle} ${root.trackArtist}`
                        Behavior on shownWords {
                            SequentialAnimation {
                                NumberAnimation {
                                    target: shownLines; property: "opacity"; to: 0
                                    duration: 150; easing.type: Easing.InQuad
                                }
                                NumberAnimation {
                                    target: shownLines; property: "opacity"; from: 0; to: 1
                                    duration: 150; easing.type: Easing.OutQuad
                                }
                            }
                        }

                        StyledText {
                            id: artistText
                            text: root.trackArtist
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: root.contentColor
                            elide: Text.ElideRight
                            Layout.maximumWidth: 120
                            Behavior on text {
                                // Out to the side the page was turned from and back in, so
                                // a swipe reads as the next player arriving, not as new
                                // words appearing in the same place.
                                SequentialAnimation {
                                    NumberAnimation { target: artistText; property: "x"; to: -artistText.width * root.enterDir; duration: 150; easing.type: Easing.InQuad }
                                    PropertyAction { target: artistText; property: "text" }
                                    NumberAnimation { target: artistText; property: "x"; from: artistText.width * root.enterDir; to: 0; duration: 150; easing.type: Easing.OutQuad }
                                }
                            }
                        }
                        StyledText {
                            id: titleText
                            Layout.topMargin: (!root.activePlayer || root.trackArtist.length === 0) ? -13 : 0
                            text: StringUtils.cleanMusicTitle(root.trackTitle) || Translation.tr("No media")
                            font.pixelSize: Appearance.font.pixelSize.smallie
                            color: root.contentColor
                            elide: Text.ElideRight
                            opacity: 0.7
                            Layout.maximumWidth: 120
                            Behavior on text {
                                SequentialAnimation {
                                    NumberAnimation { target: titleText; property: "x"; to: -titleText.width * root.enterDir; duration: 150; easing.type: Easing.InQuad }
                                    PropertyAction { target: titleText; property: "text" }
                                    NumberAnimation { target: titleText; property: "x"; from: titleText.width * root.enterDir; to: 0; duration: 150; easing.type: Easing.OutQuad }
                                }
                            }
                        }
                    }

                    // Play/Pause
                    RippleButton {
                        implicitWidth: 40
                        implicitHeight: 23
                        buttonRadius: root.isPlaying ? Appearance.rounding.normal : 13
                        colBackground: root.isPlaying ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerLow
                        colBackgroundHover: root.isPlaying ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimaryContainerHover
                        colRipple: root.isPlaying ? Appearance.colors.colPrimaryActive : Appearance.colors.colPrimaryContainerActive
                        downAction: () => root.activePlayer?.togglePlaying()
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: root.isPlaying ? "pause" : "play_arrow"
                            iconSize: Appearance.font.pixelSize.large
                            fill: 1
                            color: root.isPlaying ? Appearance.colors.colOnPrimary : Appearance.colors.colOnPrimaryContainer
                        }
                    }

                    // Next
                    RippleButton {
                        implicitWidth: 26
                        implicitHeight: 26
                        Layout.leftMargin: -4
                        Layout.rightMargin: -2
                        buttonRadius: 13
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                        colRipple: Appearance.colors.colPrimaryContainerActive
                        downAction: () => root.activePlayer?.next()
                        altAction: () => root.activePlayer?.previous()
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: "skip_next"
                            iconSize: Appearance.font.pixelSize.large
                            fill: 1
                            color: root.contentColor
                        }
                    }
                }
            }
        }
    }
}
