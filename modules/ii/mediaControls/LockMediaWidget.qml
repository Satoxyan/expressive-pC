pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Services.Mpris
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.mediaControls
import qs

// Wraps PlayerControl with:
//  - hover overlay on the cover art (dark scrim + zoom icon)
//  - click to toggle between full and compact view
//  - smooth crossfade + resize transition between the two states
Item {
    id: root

    required property MprisPlayer player
    required property real radius
    property list<real> visualizerPoints: []

    // Exposed so LockSurface can still read dominant color for bg tinting, etc.
    readonly property color artDominantColor: mediaPlayer.artDominantColor
    readonly property string displayedArtFilePath: mediaPlayer.displayedArtFilePath

    readonly property bool compactMode: GlobalStates.lockMediaCompact

    // Sizes — must match what LockSurface passes in
    readonly property real fullWidth:    Appearance.sizes.mediaControlsWidth
    readonly property real fullHeight:   mediaPlayer.showLyrics ? 290 : Appearance.sizes.mediaControlsHeight
    readonly property real compactHeight: 81
    readonly property real compactWidth:  fullWidth * 0.8

    // committedCompact only flips AFTER the exit animation finishes (via ScriptAction)
    // so the container size never changes while the outgoing element is still visible.
    // Initialised to compactMode so the correct view renders on the very first frame.
    property bool committedCompact: compactMode

    // Skip transition animation on first load — just snap to the persisted state.
    property bool initialised: false
    Component.onCompleted: {
        committedCompact = compactMode
        if (compactMode) {
            mediaPlayer.animScale   = 1.0
            mediaPlayer.animOpacity = 0.0
            compactView.animScale     = 1.0
            compactView.animOpacity   = 1.0
        }
        initialised = true
    }

    implicitWidth:  committedCompact ? compactWidth : fullWidth
    implicitHeight: committedCompact ? compactHeight : fullHeight
    width: implicitWidth
    height: implicitHeight

    Behavior on implicitWidth {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.OutExpo
        }
    }
    Behavior on implicitHeight {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.OutExpo
        }
    }

    // ── Transition animations ────────────────────────────────────────────────
    // full → compact: mediaPlayer bounces out THEN size shrinks THEN compactView bounces in
    // compact → full: compactView bounces out THEN size grows THEN mediaPlayer bounces in

    onCompactModeChanged: {
        if (!initialised) return
        if (compactMode) {
            toFullInAnim.stop()
            toCompactOutAnim.restart()
        } else {
            toCompactInAnim.stop()
            toFullOutAnim.restart()
        }
    }

    // full → compact step 1: mediaPlayer exits, then commits size, then brings in compact
    SequentialAnimation {
        id: toCompactOutAnim
        ParallelAnimation {
            NumberAnimation {
                target: mediaPlayer; property: "animScale"
                to: 0.85
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.InBack; easing.overshoot: 1.2
            }
            NumberAnimation {
                target: mediaPlayer; property: "animOpacity"
                to: 0.0
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.InCubic
            }
        }
        // Flip committed size AFTER exit — triggers Behavior on implicitWidth/Height
        ScriptAction { script: root.committedCompact = true }
        // Small pause for size Behavior to start before entrance begins
        PauseAnimation { duration: 16 }
        ScriptAction {
            script: {
                compactView.animScale   = 0.85
                compactView.animOpacity = 0.0
                toCompactInAnim.restart()
            }
        }
    }

    ParallelAnimation {
        id: toCompactInAnim
        NumberAnimation {
            target: compactView; property: "animScale"
            to: 1.0
            duration: Appearance.animation.elementMove.duration * 1.1
            easing.type: Easing.OutBack; easing.overshoot: 1.2
        }
        NumberAnimation {
            target: compactView; property: "animOpacity"
            to: 1.0
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.OutCubic
        }
    }

    // compact → full step 1: compactView exits, then commits size, then brings in full
    SequentialAnimation {
        id: toFullOutAnim
        ParallelAnimation {
            NumberAnimation {
                target: compactView; property: "animScale"
                to: 0.85
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.InBack; easing.overshoot: 1.2
            }
            NumberAnimation {
                target: compactView; property: "animOpacity"
                to: 0.0
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.InCubic
            }
        }
        ScriptAction { script: root.committedCompact = false }
        PauseAnimation { duration: 16 }
        ScriptAction {
            script: {
                mediaPlayer.animScale   = 0.85
                mediaPlayer.animOpacity = 0.0
                toFullInAnim.restart()
            }
        }
    }

    ParallelAnimation {
        id: toFullInAnim
        NumberAnimation {
            target: mediaPlayer; property: "animScale"
            to: 1.0
            duration: Appearance.animation.elementMove.duration * 1.1
            easing.type: Easing.OutBack; easing.overshoot: 1.2
        }
        NumberAnimation {
            target: mediaPlayer; property: "animOpacity"
            to: 1.0
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.OutCubic
        }
    }

    // ── Full media player (repo's Player widget, includes lyrics) ─────────────
    Player {
        id: mediaPlayer
        width: root.fullWidth
        height: root.fullHeight
        player: root.player
        visualizerPoints: root.visualizerPoints
        radius: root.radius

        property real animScale:   1.0
        property real animOpacity: 1.0

        scale:   animScale
        opacity: animOpacity
        visible: animOpacity > 0

        // ── Hover overlay on cover art ────────────────────────────────────
        // Positioned over the art square inside PlayerControl.
        // The art square sits in a RowLayout with margins=13, spacing=15.
        // Its width equals its height (square), height = fullHeight - 2*13 margins - 2*elevationMargin.
        readonly property real artSize: fullHeight
            - 2 * 13                                        // RowLayout margins
            - 2 * Appearance.sizes.elevationMargin          // background margins

        Rectangle {
            id: coverHoverOverlay
            visible: !mediaPlayer.showLyrics

            // Match art area: left offset = elevationMargin + 13 (RowLayout margin)
            x: Appearance.sizes.elevationMargin + 13
            y: Appearance.sizes.elevationMargin + 13
            width:  mediaPlayer.artSize
            height: mediaPlayer.artSize
            radius: Appearance.rounding.verysmall

            color: "transparent"

            // Scrim darkens on hover
            Rectangle {
                id: scrim
                anchors.fill: parent
                radius: parent.radius
                color: Qt.rgba(0, 0, 0, 0.55)
                opacity: coverHoverMouse.containsMouse ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.OutCubic
                    }
                }

                // Zoom icon centered on scrim
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "zoom_in_map"
                    iconSize: 28
                    fill: 1
                    color: "white"
                    opacity: parent.opacity
                }
            }

            MouseArea {
                id: coverHoverMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                // Prevent click from bubbling to LockSurface (focus steal)
                onClicked: {
                    GlobalStates.lockMediaCompact = true
                }
            }
        }
    }

    // ── Compact pill shadow ──────────────────────────────────────────────────
    StyledRectangularShadow {
        target: compactView
        opacity: compactView.opacity
        visible: opacity > 0
    }

    // ── Compact pill ─────────────────────────────────────────────────────────
    Rectangle {
        id: compactView
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.compactWidth
        height: root.compactHeight
        radius: root.compactHeight / 2
        color: mediaPlayer.blendedColors?.colLayer0 ?? Appearance.colors.colLayer0

        property real animScale:   0.85
        property real animOpacity: 0.0

        scale:   animScale
        opacity: animOpacity
        visible: animOpacity > 0

        // Blurred art background (clipped to the pill shape)
        Item {
            anchors.fill: parent

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: compactView.width
                    height: compactView.height
                    radius: compactView.radius
                }
            }

            StyledImage {
                id: compactBlurredArt
                anchors.fill: parent
                source: root.displayedArtFilePath
                fillMode: Image.PreserveAspectCrop
                cache: false
                asynchronous: true

                layer.enabled: true
                layer.effect: StyledBlurEffect {
                    source: compactBlurredArt
                }
            }

            Rectangle {
                anchors.fill: parent
                color: ColorUtils.transparentize(
                    mediaPlayer.blendedColors?.colLayer0 ?? Appearance.colors.colLayer0,
                    0.35
                )
                radius: compactView.radius
            }
        }

        // Main layout containing all visual controls
        RowLayout {
            anchors {
                fill: parent
                // leftMargin matches pill radius so art thumbnail sits flush
                // at the curved edge without being clipped
                leftMargin: 10
                rightMargin: 16
                topMargin: 10
                bottomMargin: 10
            }
            spacing: 12

            // Round cover art thumbnail — clicking expands back to full view
            Rectangle {
                id: compactArt
                Layout.fillHeight: true
                Layout.preferredWidth: height
                Layout.alignment: Qt.AlignVCenter
                radius: height / 2
                color: ColorUtils.transparentize(
                    mediaPlayer.blendedColors?.colLayer1 ?? Appearance.colors.colLayer1,
                    0.5
                )

                StyledImage {
                    anchors.fill: parent
                    source: root.displayedArtFilePath
                    fillMode: Image.PreserveAspectCrop
                    cache: false
                    asynchronous: true
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: compactArt.width
                            height: compactArt.height
                            radius: compactArt.radius
                        }
                    }
                }

                // Hover overlay on compact art — expand back
                Rectangle {
                    id: compactArtScrim
                    anchors.fill: parent
                    radius: parent.radius
                    color: Qt.rgba(0, 0, 0, 0.55)
                    opacity: compactArtMouse.containsMouse ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Easing.OutCubic
                        }
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "zoom_out_map"
                        iconSize: 20
                        fill: 1
                        color: "white"
                        opacity: parent.opacity
                    }
                }

                MouseArea {
                    id: compactArtMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: GlobalStates.lockMediaCompact = false
                }
            }

            // Track info
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: mediaPlayer.blendedColors?.colOnLayer0 ?? Appearance.colors.colOnLayer0
                    elide: Text.ElideRight
                    text: StringUtils.cleanMusicTitle(root.player?.trackTitle) || "Untitled"
                    animateChange: true
                }
                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: mediaPlayer.blendedColors?.colSubtext ?? Appearance.colors.colSubtext
                    elide: Text.ElideRight
                    text: root.player?.trackArtist ?? ""
                    animateChange: true
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.topMargin: 3
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: mediaPlayer.blendedColors?.colSubtext ?? Appearance.colors.colSubtext
                    text: `${StringUtils.friendlyTimeForSeconds(root.player?.position)} / ${StringUtils.friendlyTimeForSeconds(root.player?.length)}`
                }
            }

            // Playback controls
            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                spacing: 4

                RippleButton {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 36
                    implicitHeight: 36
                    buttonRadius: height / 2
                    colBackground: ColorUtils.transparentize(
                        mediaPlayer.blendedColors?.colSecondaryContainer ?? Appearance.colors.colSecondaryContainer, 1)
                    colBackgroundHover: mediaPlayer.blendedColors?.colSecondaryContainerHover ?? Appearance.colors.colSecondaryContainerHover
                    colRipple: mediaPlayer.blendedColors?.colSecondaryContainerActive ?? Appearance.colors.colSecondaryContainerActive
                    onClicked: root.player?.previous()
                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        iconSize: 20
                        fill: 1
                        text: "skip_previous"
                        color: mediaPlayer.blendedColors?.colOnSecondaryContainer ?? Appearance.colors.colOnSecondaryContainer
                    }
                }

                RippleButton {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 48
                    implicitHeight: 48
                    buttonRadius: height / 2
                    colBackground: mediaPlayer.blendedColors?.colSecondaryContainer ?? Appearance.colors.colSecondaryContainer
                    colBackgroundHover: mediaPlayer.blendedColors?.colSecondaryContainerHover ?? Appearance.colors.colSecondaryContainerHover
                    colRipple: mediaPlayer.blendedColors?.colSecondaryContainerActive ?? Appearance.colors.colSecondaryContainerActive
                    onClicked: root.player?.togglePlaying()
                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        iconSize: 24
                        fill: 1
                        text: (root.player?.playbackState === MprisPlaybackState.Playing) ? "pause" : "play_arrow"
                        color: mediaPlayer.blendedColors?.colOnSecondaryContainer ?? Appearance.colors.colOnSecondaryContainer
                        Behavior on text {
                            enabled: false  // icon swap is instant
                        }
                    }
                }

                RippleButton {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 36
                    implicitHeight: 36
                    buttonRadius: height / 2
                    colBackground: ColorUtils.transparentize(
                        mediaPlayer.blendedColors?.colSecondaryContainer ?? Appearance.colors.colSecondaryContainer, 1)
                    colBackgroundHover: mediaPlayer.blendedColors?.colSecondaryContainerHover ?? Appearance.colors.colSecondaryContainerHover
                    colRipple: mediaPlayer.blendedColors?.colSecondaryContainerActive ?? Appearance.colors.colSecondaryContainerActive
                    onClicked: root.player?.next()
                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        iconSize: 20
                        fill: 1
                        text: "skip_next"
                        color: mediaPlayer.blendedColors?.colOnSecondaryContainer ?? Appearance.colors.colOnSecondaryContainer
                    }
                }
            }
        }
    }
}
