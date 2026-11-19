import qs.modules.common
import qs.modules.common.functions
import "../functions/MediaSource.js" as MediaSource
import qs.services
import Qt5Compat.GraphicalEffects
import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Wayland
import Quickshell.Widgets

// The application a media card belongs to: a monochrome source icon in the
// card's own colors, click to bring that application forward. Mounted once in
// PlayerContent.qml, so every host (sidebar, mediaControls, lock screen) gets it.
RippleButton {
    id: root
    required property MprisPlayer player
    required property QtObject blendedColors

    // Resolved the same way as DockAppButton: the player's entry, and a refresh
    // when either the player or the desktop-entry list changes.
    property var desktopEntry: null
    // Usually the entry names the icon. A browser integration can report an id
    // with no installed .desktop file ("firefox" on an edition-only install),
    // and the icon theme still carries that name, so try it directly.
    readonly property string iconName: root.desktopEntry?.icon
        || MediaSource.normalize(root.player?.desktopEntry ?? "")
    readonly property string iconSource: root.iconName
        ? SystemAppearance.iconPath(root.iconName, "") : ""
    readonly property bool known: root.iconSource !== ""

    function resolveEntry() {
        const id = MediaSource.normalize(root.player?.desktopEntry ?? "")
        root.desktopEntry = (id ? DesktopEntries.byId(id) : null)
            ?? (id ? DesktopEntries.heuristicLookup(id) : null)
            ?? DesktopEntries.heuristicLookup(root.player?.identity ?? "")
    }

    // MPRIS identifies the app, not the tab or playlist inside it.
    function activateSource() {
        const wins = ToplevelManager.toplevels.values.filter(t =>
            MediaSource.matches(root.player?.desktopEntry ?? "", t.appId,
                DesktopEntries.heuristicLookup(t.appId)?.id))
        if (wins.find(w => w.activated)) return

        if (wins.length > 0) wins[wins.length - 1].activate()
        else root.desktopEntry?.execute()
    }

    onPlayerChanged: root.resolveEntry()
    Component.onCompleted: root.resolveEntry()

    Connections {
        target: DesktopEntries
        function onApplicationsChanged() {
            root.resolveEntry()
        }
    }

    visible: root.known
    implicitWidth: 28
    implicitHeight: 28
    // Flat at rest; on hover it takes the same surface as the lyric button
    // beside it, and the glyph uses the same on-secondary-container colour.
    // Transparent *of the hover colour*, not plain transparent: animating from
    // #00000000 makes Qt interpolate through black and flash dark on hover.
    colBackground: ColorUtils.transparentize(root.blendedColors.colSecondaryContainer, 1)
    colBackgroundHover: root.blendedColors.colSecondaryContainerHover
    colBackgroundToggled: "transparent"
    colRipple: root.blendedColors.colSecondaryContainerActive
    colRippleToggled: root.blendedColors.colSecondaryContainerActive
    onClicked: root.activateSource()

    contentItem: Item {
        IconImage {
            id: iconImage
            anchors.centerIn: parent
            source: root.iconSource
            implicitSize: 16
        }
        ColorOverlay {
            anchors.fill: iconImage
            source: iconImage
            color: root.blendedColors.colOnSecondaryContainer
        }
    }
}
