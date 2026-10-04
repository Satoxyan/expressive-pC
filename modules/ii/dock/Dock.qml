import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell.Io
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland

Scope {
    id: root
    property bool pinned: Config.options?.dock.pinnedOnStartup ?? false
    property bool barState: false
    property bool ready: false

    Component.onCompleted: {
        DockStyle.position = Config.options.dock.position
        barSettleTimer.start()
    }

    Timer {
        id: barSettleTimer
        interval: 300
        onTriggered: {
            root.barState = GlobalStates.barOpen
            DockStyle.position = Config.options.dock.position
            root.ready = true
        }
    }

    Connections {
        target: Config.options.dock
        function onPositionChanged() {
            root.ready = false
            barSettleTimer.restart()
        }
    }

    Connections {
        target: GlobalStates
        function onBarOpenChanged() { barSettleTimer.restart() }
    }

    Variants {
        model: !root.ready ? [] : Quickshell.screens.map(screen => ({
            screen: screen,
            position: DockStyle.position,
            layout: `${DockStyle.position}|${Config.options.dock.style}|${Config.options.dock.height}|${root.barState}`
        }))

        PanelWindow {
            id: dockRoot
            required property var modelData
            screen: modelData.screen
            visible: !GlobalStates.screenLocked

            readonly property bool hug: Config.options.dock.style === "hug"
            readonly property string position: modelData.position
            readonly property bool vertical: position !== "bottom"
            readonly property real gap: Appearance.sizes.hyprlandGapsOut
            readonly property real shadowMargin: Appearance.sizes.elevationMargin
            readonly property color backgroundColor: (hug && Config.options.dock.followFrameColor && Config.options.bar.showFrame)
                ? Appearance.getColorFromName(Config.options.bar.frameColor)
                : Appearance.getColorFromName(Config.options.dock.backgroundColor)
            readonly property real borderWidth: (Config.options.dock.showBackground && Config.options.dock.showBorder && !hug) ? Config.options.dock.borderWidth : 0

            property var monitor: WM.monitorFor(modelData.screen)
            property bool fullscreenOnThisMonitor: WM.fullscreenOnMonitor(monitor?.name)

            // Keep the dock revealed for a grace period after the media
            // controls close, so it doesn't vanish instantly
            property bool mediaControlsHeld: GlobalStates.mediaControlsOpen && GlobalStates.mediaControlsAboveDock
            property bool mediaHoldActive: mediaControlsHeld
            onMediaControlsHeldChanged: {
                if (mediaControlsHeld) {
                    mediaHoldTimer.stop()
                    mediaHoldActive = true
                } else {
                    mediaHoldTimer.restart()
                }
            }
            Timer {
                id: mediaHoldTimer
                interval: 600
                onTriggered: dockRoot.mediaHoldActive = false
            }

            property bool reveal: {
                // Keep the dock visible while the media controls it opened
                // are showing, even over a fullscreen window
                if (mediaHoldActive)
                    return true
                if (fullscreenOnThisMonitor)
                    return Config.options?.dock.hoverToReveal && dockMouseArea.containsMouse
                return root.pinned
                    || (Config.options?.dock.hoverToReveal && (dockMouseArea.containsMouse || GlobalStates.isFrameHovered(dockRoot.screen?.name, dockRoot.position)))
                    || activeApps.requestDockShow
                    || dragSlots.requestDockShow
                    || (!ToplevelManager.activeToplevel?.activated)
            }

            exclusiveZone: (root.pinned && !fullscreenOnThisMonitor)
                ? DockStyle.zone
                : 0

            anchors {
                top: dockRoot.vertical
                bottom: true
                left: dockRoot.position !== "right"
                right: dockRoot.position !== "left"
            }
            margins {
                bottom: dockRoot.hug && dockRoot.position === "bottom" ? -dockRoot.gap : 0
                left: dockRoot.hug && dockRoot.position === "left" ? -dockRoot.gap : 0
                right: dockRoot.hug && dockRoot.position === "right" ? -dockRoot.gap : 0
            }
            implicitWidth: dockRoot.vertical ? DockStyle.thickness : dockBackground.implicitWidth
            implicitHeight: dockRoot.vertical ? dockBackground.implicitHeight : DockStyle.thickness
            WlrLayershell.namespace: "quickshell:dock"
            color: "transparent"

            mask: Region { item: dockMouseArea }

            MouseArea {
                id: dockMouseArea
                hoverEnabled: true
                width: dockRoot.vertical ? parent.width : implicitWidth
                height: dockRoot.vertical ? implicitHeight : parent.height
                implicitWidth: dockHoverRegion.implicitWidth + dockRoot.shadowMargin * 2
                implicitHeight: dockHoverRegion.implicitHeight + dockRoot.shadowMargin * 2

                readonly property real hiddenOffset: Config.options?.dock.hoverToReveal
                    ? (DockStyle.thickness - Config.options.dock.hoverRegionHeight)
                    : (DockStyle.thickness + 1)
                property real offset: dockRoot.reveal ? 0 : hiddenOffset

                Behavior on offset {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                anchors {
                    top: dockRoot.vertical ? undefined : parent.top
                    topMargin: dockMouseArea.offset
                    horizontalCenter: dockRoot.vertical ? undefined : parent.horizontalCenter
                    verticalCenter: dockRoot.vertical ? parent.verticalCenter : undefined
                    left: dockRoot.position === "left" ? parent.left : undefined
                    leftMargin: -dockMouseArea.offset
                    right: dockRoot.position === "right" ? parent.right : undefined
                    rightMargin: -dockMouseArea.offset
                }

                Item {
                    id: dockHoverRegion
                    anchors.fill: parent
                    implicitWidth: dockBackground.implicitWidth
                    implicitHeight: dockBackground.implicitHeight

                    Item {
                        id: dockBackground
                        anchors {
                            top: dockRoot.vertical ? undefined : parent.top
                            bottom: dockRoot.vertical ? undefined : parent.bottom
                            left: dockRoot.vertical ? parent.left : undefined
                            right: dockRoot.vertical ? parent.right : undefined
                            horizontalCenter: dockRoot.vertical ? undefined : parent.horizontalCenter
                            verticalCenter: dockRoot.vertical ? parent.verticalCenter : undefined
                        }
                        implicitWidth: dockRow.implicitWidth + DockStyle.backgroundPadding * 2
                        implicitHeight: dockRow.implicitHeight + DockStyle.backgroundPadding * 2

                        StyledRectangularShadow {
                            target: dockVisualBackground
                            visible: false
                        }

                        Rectangle {
                            id: dockVisualBackground
                            anchors.fill: parent
                            anchors.topMargin: dockRoot.position === "bottom" ? dockRoot.shadowMargin : 0
                            anchors.bottomMargin: dockRoot.position === "bottom" ? dockRoot.gap : 0
                            anchors.leftMargin: dockRoot.position === "left" ? dockRoot.gap : dockRoot.position === "right" ? dockRoot.shadowMargin : 0
                            anchors.rightMargin: dockRoot.position === "right" ? dockRoot.gap : dockRoot.position === "left" ? dockRoot.shadowMargin : 0
                            color: Config.options.dock.showBackground ? dockRoot.backgroundColor : "transparent"
                            border.width: dockRoot.borderWidth
                            border.color: Appearance.getColorFromName(Config.options.dock.borderColor)
                            radius: Config.options.dock.radius
                            topLeftRadius: dockRoot.hug && dockRoot.position === "left" ? 0 : radius
                            bottomLeftRadius: dockRoot.hug && (dockRoot.position === "left" || dockRoot.position === "bottom") ? 0 : radius
                            topRightRadius: dockRoot.hug && dockRoot.position === "right" ? 0 : radius
                            bottomRightRadius: dockRoot.hug && (dockRoot.position === "right" || dockRoot.position === "bottom") ? 0 : radius
                        }

                        RoundCorner {
                            visible: dockRoot.hug && Config.options.dock.showBackground
                            anchors.right: dockRoot.vertical ? (dockRoot.position === "right" ? dockVisualBackground.right : undefined) : dockVisualBackground.left
                            anchors.bottom: dockRoot.vertical ? dockVisualBackground.top : dockVisualBackground.bottom
                            anchors.left: dockRoot.position === "left" ? dockVisualBackground.left : undefined
                            implicitSize: Appearance.rounding.screenRounding
                            color: dockRoot.backgroundColor
                            corner: dockRoot.position === "left" ? RoundCorner.CornerEnum.BottomLeft : RoundCorner.CornerEnum.BottomRight
                        }

                        RoundCorner {
                            visible: dockRoot.hug && Config.options.dock.showBackground
                            anchors.left: dockRoot.vertical ? (dockRoot.position === "left" ? dockVisualBackground.left : undefined) : dockVisualBackground.right
                            anchors.bottom: dockRoot.vertical ? undefined : dockVisualBackground.bottom
                            anchors.top: dockRoot.vertical ? dockVisualBackground.bottom : undefined
                            anchors.right: dockRoot.position === "right" ? dockVisualBackground.right : undefined
                            implicitSize: Appearance.rounding.screenRounding
                            color: dockRoot.backgroundColor
                            corner: dockRoot.position === "left" ? RoundCorner.CornerEnum.TopLeft
                                : dockRoot.position === "right" ? RoundCorner.CornerEnum.TopRight
                                : RoundCorner.CornerEnum.BottomLeft
                        }

                        GridLayout {
                            id: dockRow
                            anchors.top: dockRoot.vertical ? undefined : parent.top
                            anchors.bottom: dockRoot.vertical ? undefined : parent.bottom
                            anchors.left: dockRoot.vertical ? parent.left : undefined
                            anchors.right: dockRoot.vertical ? parent.right : undefined
                            anchors.horizontalCenter: dockRoot.vertical ? undefined : parent.horizontalCenter
                            anchors.verticalCenter: dockRoot.vertical ? parent.verticalCenter : undefined
                            columns: dockRoot.vertical ? 1 : -1
                            rowSpacing: DockStyle.spacing
                            columnSpacing: DockStyle.spacing
                            property bool hasPinnedApps: (Config.options?.dock.pinnedApps?.length ?? 0) > 0

                            DockPinButton {
                                pinned: root.pinned
                                onToggled: root.pinned = !root.pinned
                            }

                            DockSeparator {
                                visible: Config.options.dock.showPinButton
                                    && (dockRow.hasPinnedApps
                                        || !(Config.options.dock.showMedia && activeApps.media.hasTrack))
                            }

                            DragApps {
                                id: dragSlots
                                visible: dockRow.hasPinnedApps
                                Layout.topMargin: DockStyle.mTop(DockStyle.pinnedInnerMargin, 0)
                                Layout.leftMargin: DockStyle.mLeft(DockStyle.pinnedInnerMargin, 0)
                                pinnedApps: Config.options?.dock.pinnedApps ?? []
                            }

                            DockSeparator {
                                visible: dockRow.hasPinnedApps
                                    && (activeApps.activeUnpinned.length > 0
                                        || (Config.options.dock.showMedia && MprisController.activePlayer !== null))
                            }

                            DockActiveApps {
                                id: activeApps
                            }

                            DockSeparator {
                                visible: Config.options.dock.showAppsButton
                            }

                            DockAppsButton {
                                onClicked: GlobalStates.overviewOpen = !GlobalStates.overviewOpen
                            }
                        }
                    }
                }
            }
        }
    }
}
