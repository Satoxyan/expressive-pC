pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import qs.modules.common.models
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// One player, one card.
//
// This used to be the whole of DockMedia, bound to MprisController.activePlayer, so the
// dock could only ever show and drive whichever bus the shell happened to be tracking.
// Now the pager around it decides which player this card is stood up for, and its buttons
// act on that player alone — a song and a browser video can no longer share one set of
// controls.
//
// The card is inset from the edges it is sized by rather than filling them: the band of
// drop shadow needs room to be drawn in, and along the axis the pages are crossed on that
// band is part of the pitch, so a card that slid past another one would otherwise overlap
// it.
Item {
    id: root

    required property MprisPlayer player

    // Whether this card is the one standing in the slot. A card parked off the side is
    // on screen for part of a crossing, and it must not take the click that opens the
    // media controls popup.
    property bool interactive: true

    property real artMargin: 5

    // How tall the content wants to be, which is what decides the slot's length when the
    // dock runs along the side of the screen.
    readonly property real contentLength: mediaGrid.implicitHeight

    readonly property real bleed: Appearance.sizes.elevationMargin
    readonly property real gap: Appearance.sizes.hyprlandGapsOut
    // The paging axis carries the shadow band as well as the gap; the other one does not.
    readonly property real lengthInset: gap + (DockStyle.vertical ? 0 : bleed)
    readonly property real crossInset: gap + (DockStyle.vertical ? bleed : 0)

    property var artUrl: player?.trackArtUrl ?? ""
    property bool isPlaying: player?.isPlaying ?? false

    property string artDownloadLocation: Directories.coverArt
    property string artFileName: Qt.md5(artUrl)
    property string artFilePath: `${artDownloadLocation}/${artFileName}`
    property bool artDownloaded: Boolean(root.artUrl && (root.artUrl.startsWith("data:") || root.artUrl.startsWith("file:/") || root.artUrl.startsWith("/")))

    property string displayedArtFilePath: {
        if (!root.artUrl || root.artUrl.length === 0) return ""
        if (root.artUrl.startsWith("data:")) return root.artUrl
        if (root.artUrl.startsWith("file:/")) return root.artUrl
        if (root.artUrl.startsWith("/")) return "file://" + root.artUrl
        if (!root.artDownloaded) return ""
        return Qt.resolvedUrl(artFilePath)
    }

    property color artDominantColor: ColorUtils.mix(
        colorQuantizer?.colors[0] ?? Appearance.colors.colPrimary,
        Appearance.colors.colPrimaryContainer,
        0.8)

    property QtObject blendedColors: AdaptedMaterialScheme {
        color: root.artDominantColor
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
            artDownloader.targetFile = root.artUrl
            artDownloader.artFilePath = root.artFilePath
            root.artDownloaded = false
            artDownloader.running = true
        } else {
            root.artDownloaded = true
        }
    }

    Process {
        id: artDownloader
        property string targetFile: root.artUrl
        property string artFilePath: root.artFilePath
        command: ["bash", "-c",
            `[ -f ${artFilePath} ] || curl -sSL '${targetFile}' -o '${artFilePath}'`]
        onExited: { root.artDownloaded = true }
    }

    ColorQuantizer {
        id: colorQuantizer
        source: root.displayedArtFilePath
        depth: 0
        rescaleSize: 1
    }

    StyledRectangularShadow {
        target: card
        visible: root.visible
    }

    Rectangle {
        id: card
        anchors.fill: parent
        anchors.topMargin: root.crossInset
        anchors.bottomMargin: root.crossInset
        anchors.leftMargin: root.lengthInset
        anchors.rightMargin: root.lengthInset - (DockStyle.vertical ? 0 : 2)
        radius: Appearance.rounding.normal
        color: "transparent"

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: card.width
                height: card.height
                radius: card.radius
            }
        }

        Rectangle {
            anchors.fill: parent
            color: ColorUtils.applyAlpha(root.blendedColors.colLayer0, 1)
            z: 0
        }

        // Blur art
        Image {
            id: blurredArt
            anchors.fill: parent
            source: root.displayedArtFilePath
            fillMode: Image.PreserveAspectCrop
            cache: false
            antialiasing: true
            asynchronous: true
            z: 1
            layer.enabled: true
            layer.effect: StyledBlurEffect {
                source: blurredArt
            }
        }

        // Overlay
        Rectangle {
            anchors.fill: parent
            color: ColorUtils.transparentize(root.blendedColors.colLayer0, 0.3)
            z: 2
        }

        // Click the card to show the existing media controls right above it
        MouseArea {
            anchors.fill: parent
            z: 2
            enabled: root.interactive
            onClicked: {
                const globalPos = root.mapToItem(null, root.width / 2, 0)
                GlobalStates.mediaControlsAnchorX = globalPos.x
                GlobalStates.mediaControlsAboveDock = true
                GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen
            }
        }

        GridLayout {
            id: mediaGrid
            width: card.width
            height: card.height
            clip: true
            columns: DockStyle.vertical ? 1 : -1
            rowSpacing: 8
            columnSpacing: 8
            z: 3

            // Art
            Rectangle {
                id: artRect
                Layout.alignment: DockStyle.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
                Layout.leftMargin: DockStyle.vertical ? 0 : root.artMargin + 2
                Layout.topMargin: DockStyle.vertical ? root.artMargin + 2 : 0
                implicitWidth: 36
                implicitHeight: 36
                color: ColorUtils.transparentize(root.blendedColors.colLayer1, 0.5)
                radius: Appearance.rounding.small

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
                }
            }

            // Artist + Title
            ColumnLayout {
                visible: !DockStyle.vertical
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: -2

                Item { Layout.fillHeight: true }

                StyledText {
                    Layout.fillWidth: true
                    text: root.player?.trackArtist ?? ""
                    font.pixelSize: Appearance.font.pixelSize.small - 2
                    color: root.blendedColors.colSubtext
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: StringUtils.cleanMusicTitle(root.player?.trackTitle ?? "") || "Untitled"
                    font.pixelSize: Appearance.font.pixelSize.normal - 4
                    color: root.blendedColors.colOnLayer0
                    elide: Text.ElideRight
                    opacity: 0.7
                }

                Item { Layout.fillHeight: true }
            }

            // Buttons
            GridLayout {
                Layout.rightMargin: DockStyle.vertical ? 0 : 4
                Layout.alignment: DockStyle.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
                Layout.bottomMargin: DockStyle.vertical ? 4 : 0
                columns: DockStyle.vertical ? 1 : -1
                rowSpacing: 3
                columnSpacing: 3

                // Play / Pause
                RippleButton {
                    implicitWidth: 26
                    implicitHeight: 26
                    buttonRadius: root.isPlaying
                        ? Appearance.rounding.normal
                        : implicitWidth / 2
                    colBackground: root.isPlaying
                        ? root.blendedColors.colPrimary
                        : root.blendedColors.colSecondaryContainer
                    colBackgroundHover: root.isPlaying
                        ? root.blendedColors.colPrimaryHover
                        : root.blendedColors.colSecondaryContainerHover
                    colRipple: root.isPlaying
                        ? root.blendedColors.colPrimaryActive
                        : root.blendedColors.colSecondaryContainerActive
                    downAction: () => root.player?.togglePlaying()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: root.isPlaying ? "pause" : "play_arrow"
                        iconSize: Appearance.font.pixelSize.large
                        fill: 1
                        color: root.isPlaying
                            ? root.blendedColors.colOnPrimary
                            : root.blendedColors.colOnSecondaryContainer
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                    }
                }

                // Next
                RippleButton {
                    implicitWidth: 28
                    implicitHeight: 28
                    colBackground: ColorUtils.transparentize(root.blendedColors.colSecondaryContainer, 1)
                    colBackgroundHover: root.blendedColors.colSecondaryContainerHover
                    colRipple: root.blendedColors.colSecondaryContainerActive
                    downAction: () => root.player?.next()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "skip_next"
                        iconSize: Appearance.font.pixelSize.large
                        fill: 1
                        color: root.blendedColors.colOnSecondaryContainer
                    }
                }
            }
        }
    }
}
