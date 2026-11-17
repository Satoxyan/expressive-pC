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
// Player.qml, so every host (sidebar, mediaControls, lock screen) gets it.
RippleButton {
    id: root
    required property MprisPlayer player
    required property QtObject blendedColors

    // Resolved the same way as DockAppButton: the player's entry, and a refresh
    // when either the player or the desktop-entry list changes.
    property var desktopEntry: null
    readonly property string iconSource: root.desktopEntry?.icon
        ? SystemAppearance.iconPath(root.desktopEntry.icon, "") : ""
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
    buttonRadius: Appearance.rounding.full
    colBackground: ColorUtils.transparentize(root.blendedColors.colLayer0, 0.3)
    colBackgroundHover: ColorUtils.transparentize(root.blendedColors.colLayer0, 0.15)
    colRipple: ColorUtils.transparentize(root.blendedColors.colPrimary, 0.5)
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
            color: root.blendedColors.colOnLayer0
        }
    }
}
