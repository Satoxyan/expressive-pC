pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    readonly property string currentDots: {
        const url = Quickshell.shellPath(".")
        const path = url.startsWith("file://") ? url.slice("file://".length) : url
        const parts = path.split("/").filter(part => part.length > 0)
        return parts.length > 0 ? parts[parts.length - 1] : ""
    }

    readonly property var dotsList: ["ii", "expressive-pC"]

    property bool switcherOpen: false

    readonly property string variablesLuaPath: FileUtils.trimFileProtocol(`${Directories.home}/.config/hypr/hyprland/variables.lua`)

    readonly property real shadowPad: Appearance.sizes.elevationMargin
    readonly property real cardPad: 20

    readonly property string focusedScreenName: Hyprland.focusedMonitor?.name ?? ""

    property var focusedScreen: Quickshell.screens.find(s => s.name === root.focusedScreenName)
        ?? Quickshell.screens[0]

    function switchTo(dotsName) {
        root.switcherOpen = false
        if (dotsName === root.currentDots) return

        const script = `
sed -i 's/hl.env("qsConfig", "[^"]*")/hl.env("qsConfig", "${dotsName}")/' "${root.variablesLuaPath}"
sleep 0.5
killall ydotool qs quickshell 2>/dev/null || true
(setsid qs -c ${dotsName} &)
`
        Quickshell.execDetached(["bash", "-c", script])
    }

    Loader {
        id: switcherLoader
        active: root.switcherOpen

        sourceComponent: PanelWindow {
            id: window
            screen: root.focusedScreen
            visible: switcherLoader.active

            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:dotsSwitcher"
            WlrLayershell.layer: WlrLayer.Overlay
            color: "transparent"

            implicitWidth: cardLayout.implicitWidth + root.cardPad * 2 + root.shadowPad * 2
            implicitHeight: cardLayout.implicitHeight + root.cardPad * 2 + root.shadowPad * 2

            anchors {
                top: true
                left: true
            }
            margins {
                top: ((window.screen?.height ?? 0) - window.implicitHeight) / 2
                left: ((window.screen?.width ?? 0) - window.implicitWidth) / 2
            }

            Component.onCompleted: GlobalFocusGrab.addDismissable(window)
            Component.onDestruction: GlobalFocusGrab.removeDismissable(window)
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    root.switcherOpen = false
                }
            }

            Item {
                id: cardWrapper
                anchors.fill: parent
                opacity: 0.85
                scale: 0.95
                focus: true
                activeFocusOnTab: true

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        root.switcherOpen = false
                    }
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveEnter.duration
                        easing.type: Appearance.animation.elementMoveEnter.type
                        easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
                    }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                }

                Component.onCompleted: {
                    cardWrapper.opacity = 1
                    cardWrapper.scale = 1
                }

                StyledRectangularShadow {
                    target: cardContainer
                }

                Rectangle {
                    id: cardContainer
                    anchors.fill: parent
                    anchors.margins: root.shadowPad
                    radius: Appearance.rounding.large
                    color: ColorUtils.applyAlpha(Appearance.colors.colLayer0, 1)
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border

                    ColumnLayout {
                        id: cardLayout
                        anchors.fill: parent
                        anchors.margins: root.cardPad
                        spacing: 18

                        ColumnLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 4

                            RowLayout {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 8

                                MaterialSymbol {
                                    iconSize: 30
                                    color: Appearance.colors.colPrimary
                                    text: "widgets"
                                }

                                StyledText {
                                    font {
                                        family: Appearance.font.family.title
                                        pixelSize: Appearance.font.pixelSize.title
                                        variableAxes: Appearance.font.variableAxes.title
                                    }
                                    text: Translation.tr("Dots")
                                }
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                horizontalAlignment: Text.AlignHCenter
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colSubtext
                                text: Translation.tr("Switch between dots presets\nEsc or click outside to close")
                            }
                        }

                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 12

                            DotsOptionCard {
                                dotsName: "ii"
                            }
                            DotsOptionCard {
                                dotsName: "expressive-pC"
                            }
                        }
                    }
                }
            }
        }
    }

    component DotsOptionCard: RippleButton {
        required property string dotsName
        readonly property bool isActive: dotsName === root.currentDots

        Layout.preferredWidth: 190
        Layout.preferredHeight: 120
        buttonRadius: Appearance.rounding.normal
        colBackground: isActive ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
        colBackgroundHover: isActive ? Appearance.colors.colPrimaryHover : Appearance.colors.colSecondaryContainerHover
        colRipple: isActive ? Appearance.colors.colPrimaryActive : Appearance.colors.colSecondaryContainerActive

        property color textColor: isActive ? Appearance.m3colors.m3onPrimary : Appearance.m3colors.m3onSecondaryContainer

        onClicked: root.switchTo(dotsName)

        contentItem: Item {
            anchors.fill: parent

            MaterialSymbol {
                id: cardIcon
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 14
                iconSize: 36
                color: textColor
                text: "view_quilt"
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: cardIcon.bottom
                anchors.topMargin: 6
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.DemiBold
                color: textColor
                text: dotsName
            }

            MaterialSymbol {
                visible: isActive
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: 8
                anchors.rightMargin: 8
                iconSize: 20
                color: textColor
                text: "check_circle"
            }
        }
    }

    IpcHandler {
        target: "dotsSwitcher"

        function toggle(): void {
            root.switcherOpen = !root.switcherOpen
        }

        function close(): void {
            root.switcherOpen = false
        }

        function open(): void {
            root.switcherOpen = true
        }
    }

    GlobalShortcut {
        name: "dotsSwitcherToggle"
        description: "Toggles dots switcher on press"

        onPressed: {
            root.switcherOpen = !root.switcherOpen
        }
    }

    GlobalShortcut {
        name: "dotsSwitcherOpen"
        description: "Opens dots switcher on press"

        onPressed: {
            root.switcherOpen = true
        }
    }

    GlobalShortcut {
        name: "dotsSwitcherClose"
        description: "Closes dots switcher on press"

        onPressed: {
            root.switcherOpen = false
        }
    }
}