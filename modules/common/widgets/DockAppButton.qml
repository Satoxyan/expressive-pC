import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell

DockButton {
    id: root
    property var appToplevel
    property var appListRoot
    property int lastFocused: -1
    property real iconSize: DockStyle.iconSize
    property bool appIsActive: appToplevel.toplevels.find(t => (t.activated == true)) !== undefined

    readonly property bool isSeparator: appToplevel.appId === "SEPARATOR"
    property var desktopEntry: DesktopEntries.heuristicLookup(appToplevel.appId)
    enabled: !isSeparator
    implicitWidth: isSeparator ? 1 : naturalWidth

    Connections {
        target: DesktopEntries

        function onApplicationsChanged() {
            root.desktopEntry = DesktopEntries.heuristicLookup(appToplevel.appId);
        }
    }

    Loader {
        active: isSeparator
        anchors {
            fill: parent
            topMargin: DockStyle.separatorInset
            bottomMargin: DockStyle.separatorInset
        }
        sourceComponent: DockSeparator {}
    }

    Loader {
        anchors.fill: parent
        active: appToplevel.toplevels.length > 0
        sourceComponent: MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onEntered: {
                appListRoot.lastHoveredButton = root
                appListRoot.buttonHovered = true
                lastFocused = appToplevel.toplevels.length - 1
            }
            onExited: {
                if (appListRoot.lastHoveredButton === root) {
                    appListRoot.buttonHovered = false
                }
            }
        }
    }

    onClicked: {
        launchAnims.play(Config.options.dock.launchAnimation);
        if (appToplevel.toplevels.length === 0) {
            if (root.desktopEntry) Quickshell.execDetached(["gtk-launch", root.desktopEntry.id]);
            return;
        }
        lastFocused = (lastFocused + 1) % appToplevel.toplevels.length
        appToplevel.toplevels[lastFocused].activate()
    }

    middleClickAction: () => {
        if (root.desktopEntry) Quickshell.execDetached(["gtk-launch", root.desktopEntry.id]);
    }

    altAction: () => {
        TaskbarApps.togglePin(appToplevel.appId);
    }

    contentItem: Loader {
        active: !isSeparator
        sourceComponent: DockAppIcon {
            anchors.centerIn: parent
            scale: launchAnims.scale
            rotation: launchAnims.rot
            transformOrigin: Item.Center
            iconSource: SystemAppearance.iconPath(AppSearch.guessIcon(appToplevel.appId), "image-missing")
            iconSize: root.iconSize
            windowCount: appToplevel.toplevels.length
            active: root.appIsActive
        }
    }

    DockLaunchAnimations {
        id: launchAnims
    }
}
