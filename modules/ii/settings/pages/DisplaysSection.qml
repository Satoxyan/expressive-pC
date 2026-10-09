import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell
import qs.modules.common.functions
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.models.hyprland

// Displays section: monitor canvas + one dropdown row per monitor.
// Shared by the default Hyprland settings page and the dashboard Displays card.
ContentSection {
    id: root
    icon: "monitor"
    shape: MaterialShape.Shape.ClamShell
    title: Translation.tr("Displays")
    // The monitor canvas is the point of this section; keep it always open.
    collapsible: false
    visible: monitorConfig.monitors.length > 0

    // Dropdown menus tracked per monitor name, so several can be open at
    // once and a hotplug reorder doesn't shuffle them.
    property var openMonitors: ({})

    // Accent family (primary by default). The dashboard Displays card passes
    // the tertiary family so the canvas, rows and dropdown read M3 Expressive.
    property color accent: Appearance.colors.colPrimary
    property color accentHover: Appearance.colors.colPrimaryHover
    property color accentActive: Appearance.colors.colPrimaryActive
    property color accentContainer: Appearance.colors.colPrimaryContainer
    property color accentOn: Appearance.colors.colOnPrimary
    // Canvas: panel surface + selected rectangle fill + its label.
    property color panelColor: Appearance.colors.colLayer1
    property color accentFill: Appearance.colors.colPrimaryContainer
    property color accentOnFill: Appearance.colors.colOnPrimaryContainer
    property color accentOnFillSub: Appearance.colors.colSubtext
    // Surfaces, labels and controls. Defaults are the old hard-coded
    // colours; the dashboard passes the tertiary family so rows, the
    // dropdown and everything inside it read M3 Expressive too.
    property color rowBg: Appearance.colors.colLayer1
    property color surfaceText: Appearance.colors.colOnSecondaryContainer
    property color chevronColor: Appearance.colors.colOnLayer1
    property color fieldBg: Appearance.colors.colSecondaryContainer
    property color fieldBgHover: Appearance.colors.colSecondaryContainerHover
    property color fieldBgActive: Appearance.colors.colSecondaryContainerActive
    property color fieldText: Appearance.colors.colOnSecondaryContainer
    property color spinBg: Appearance.colors.colLayer2
    property color spinFg: Appearance.colors.colOnLayer2
    property color spinBgHover: Appearance.colors.colLayer2Hover
    property color spinBgActive: Appearance.colors.colLayer2Active
    property color noticeBg: Appearance.colors.colPrimaryContainer
    property color noticeFg: Appearance.colors.colOnPrimaryContainer
    property color titleColor: Appearance.colors.colSubtext
    // Unselected chips and combobox popups; defaults keep the old greys.
    property color colChip: Appearance.colors.colSecondaryContainer
    property color colChipHover: Appearance.colors.colSecondaryContainerHover
    property color colChipActive: Appearance.colors.colSecondaryContainerActive
    property color colChipText: Appearance.colors.colOnSecondaryContainer
    // Selected chip label; default keeps the old value.
    property color colToggledText: Appearance.colors.colOnPrimary
    property color colPopup: Appearance.m3colors.m3surfaceContainerHigh
    property color colPopupText: Appearance.colors.colOnLayer3
    property color colPopupHover: Appearance.colors.colLayer3Hover
    property color colPopupActive: Appearance.colors.colLayer3Active

    function toggleAdvanced(monName) {
        const next = Object.assign({}, root.openMonitors)
        next[monName] = !next[monName]
        root.openMonitors = next
    }

    MonitorConfigOption { id: monitorConfig }

        MonitorCanvas {
            id: monitorCanvas
            Layout.fillWidth: true
            monitorConfig: monitorConfig
            accent: root.accent
            panelColor: root.panelColor
            accentFill: root.accentFill
            accentOnFill: root.accentOnFill
            accentOnFillSub: root.accentOnFillSub
        }

        // One dropdown row per connected monitor. The chevron selects that
        // monitor on the canvas and expands its options directly under the
        // row, so several menus can be open at the same time.
        Repeater {
            model: monitorConfig.monitors
            delegate: ColumnLayout {
                id: monCol
                required property int index
                Layout.fillWidth: true
                spacing: 0

                readonly property string monName: monitorConfig.monitors[index]?.name ?? ""
                readonly property bool open: root.openMonitors[monName] === true
                // The last display still showing the desktop can never be
                // switched off, so there is always something to look at.
                readonly property bool monOn: !(monitorConfig.monitors[index]?.disabled ?? false)
                readonly property bool canTurnOff: monitorConfig.monitors
                    .some((m, i) => i !== index && !(m.disabled ?? false))

                // Lets ContentPage.goTo (settings search) expand this
                // dropdown when a result points inside it.
                readonly property bool collapsed: !open
                function toggleCollapsed() { root.toggleAdvanced(monCol.monName) }

                GroupedList {
                    bgcolor: root.rowBg
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        // The label row opens this monitor's options; only
                        // the switch changes the monitor's state.
                        RippleButton {
                            id: monRow
                            Layout.fillWidth: true
                            Layout.bottomMargin: 6
                            implicitHeight: contentItem.implicitHeight + 8
                            font.pixelSize: Appearance.font.pixelSize.small
                            colBackgroundHover: "transparent"
                            onClicked: {
                                monitorCanvas.selectedIndex = index
                                root.toggleAdvanced(monCol.monName)
                            }
                            contentItem: RowLayout {
                                spacing: 10
                                MaterialSymbol {
                                    text: "tv_off"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: root.surfaceText
                                    opacity: monCol.monOn ? 1 : 0.4
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: (monitorConfig.monitors[index]?.name ?? "")
                                        + (monitorConfig.monitors[index]?.description ? " \u00b7 " + monitorConfig.monitors[index]?.description : "")
                                    font: monRow.font
                                    color: root.surfaceText
                                }
                            }
                        }
                        // The pin marks the one monitor every Mirror
                        // display copies. Only one can hold it.
                        RippleButton {
                            implicitWidth: 36; implicitHeight: 36
                            buttonRadius: Appearance.rounding.full
                            colBackground: "transparent"
                            onClicked: monitorConfig.pinSource(monCol.monName)
                            StyledToolTip { text: Translation.tr("set as main monitor") }
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "keep"
                                iconSize: 20
                                // Filled when pinned, outline otherwise — same colour either way.
                                fill: monCol.monName === monitorConfig.mirrorSource ? 1 : 0
                                color: root.accent
                            }
                        }
                        StyledSwitch {
                            checked: monCol.monOn
                            enabled: !monCol.monOn || monCol.canTurnOff
                            activeColor: root.accentContainer
                            thumbColor: root.accent
                            onClicked: {
                                if (!checked && !monCol.canTurnOff) return
                                if (checked === monCol.monOn) return
                                monitorConfig.updateMonitor(index, { disabled: !checked })
                                monitorConfig.applyAndSave(index)
                            }
                        }
                        RippleButton {
                            implicitWidth: 36; implicitHeight: 36
                            buttonRadius: Appearance.rounding.full
                            colBackground: "transparent"
                            onClicked: {
                                monitorCanvas.selectedIndex = index
                                root.toggleAdvanced(monCol.monName)
                            }
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: monCol.open ? "expand_less" : "expand_more"
                                iconSize: 20
                                color: root.chevronColor
                            }
                        }
                    }
                }

                // Advanced options for this monitor, right under its row.
                // Scroll-down animation, no empty column when collapsed.
                GroupedList {
                    bgcolor: root.rowBg
                    visible: monCol.open || implicitHeight > 0
                    Layout.topMargin: 1
                    Layout.bottomMargin: monCol.open ? 24 : 0
                    implicitHeight: monCol.open ? advancedCol.implicitHeight : 0
                    opacity: monCol.open ? 1 : 0
                    clip: false
                    Behavior on implicitHeight { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Behavior on Layout.bottomMargin { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                    ColumnLayout {
                        id: advancedCol
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 8

                        ConfigComboBox {
                            Layout.fillWidth: true
                            buttonIcon: "aspect_ratio"
                            text: Translation.tr("Resolution & Refresh Rate")
                            colLabel: root.surfaceText
                            fieldBg: root.fieldBg
                            fieldBgHover: root.fieldBgHover
                            fieldBgActive: root.fieldBgActive
                            fieldText: root.fieldText
                            colPopup: root.colPopup
                            colPopupText: root.colPopupText
                            colPopupHover: root.colPopupHover
                            colPopupActive: root.colPopupActive
                            textRole: "display"
                            model: (monitorConfig.monitors[index]?.availableModes ?? [])
                                .map(mode => ({ display: mode, value: mode }))
                            currentValue: monitorConfig.monitors[index]?.currentMode ?? ""
                            onSelected: newValue => {
                                const mode = newValue
                                const parts = mode.match(/(\d+)x(\d+)@([\d.]+)Hz/)
                                monitorConfig.updateMonitor(index, {
                                    currentMode: mode,
                                    width: parseInt(parts[1]),
                                    height: parseInt(parts[2]),
                                    refreshRate: parseFloat(parts[3])
                                })
                                monitorConfig.applyAndSave(index)
                            }
                        }

                        ConfigSelectionArray {
                            visible: monitorConfig.monitors.length > 1
                            text: Translation.tr("Display mode")
                            icon: "screenshot_monitor"
                            colLabel: root.surfaceText
                            colChip: root.colChip
                            colChipHover: root.colChipHover
                            colChipActive: root.colChipActive
                            colChipText: root.colChipText
                            colToggled: root.accent
                            colToggledText: root.colToggledText
                            colToggledHover: root.accentHover
                            colToggledActive: root.accentActive
                            currentValue: (monitorConfig.monitors[index]?.mirror ?? "") !== "" ? "mirror" : "extended"
                            onSelected: newValue => {
                                monitorConfig.setMirroring(index, newValue === "mirror")
                                monitorConfig.applyAndSave(index)
                            }
                            options: [
                                { displayName: Translation.tr("Mirror"),   icon: "screenshot_monitor", value: "mirror" },
                                { displayName: Translation.tr("Extended"), icon: "desktop_windows",   value: "extended" },
                            ]
                        }

                        ConfigSelectionArray {
                            text: Translation.tr("Orientation")
                            icon: "mobile_rotate"
                            colLabel: root.surfaceText
                            colChip: root.colChip
                            colChipHover: root.colChipHover
                            colChipActive: root.colChipActive
                            colChipText: root.colChipText
                            colToggled: root.accent
                            colToggledText: root.colToggledText
                            colToggledHover: root.accentHover
                            colToggledActive: root.accentActive
                            currentValue: monitorConfig.monitors[index]?.transform ?? 0
                            onSelected: newValue => {
                                monitorConfig.updateMonitor(index, { transform: newValue })
                                monitorConfig.applyAndSave(index)
                            }
                            options: [
                                { displayName: Translation.tr("Normal"), icon: "screen_rotation_alt", value: 0 },
                                { displayName: "90\u00b0",                    icon: "rotate_90_degrees_cw",  value: 1 },
                                { displayName: "180\u00b0",                   icon: "screen_rotation",       value: 2 },
                                { displayName: "270\u00b0",                   icon: "rotate_90_degrees_ccw", value: 3 },
                            ]
                        }

                        ConfigSpinBox {
                            icon: "zoom_in"
                            text: Translation.tr("Scale")
                            colLabel: root.surfaceText
                            spinBg: root.spinBg
                            spinFg: root.spinFg
                            spinBgHover: root.spinBgHover
                            spinBgActive: root.spinBgActive
                            value: Math.round((monitorConfig.monitors[index]?.scale ?? 1.0) * 100)
                            from: 50; to: 300; stepSize: 25
                            onValueChanged: {
                                const newVal = value / 100.0
                                if (newVal === (monitorConfig.monitors[index]?.scale ?? 1.0)) return
                                monitorConfig.updateMonitor(index, { scale: newVal })
                                monitorConfig.applyAndSave(index)
                            }
                        }

                        ConfigSpinBox {
                            icon: "swap_horiz"
                            text: Translation.tr("Position X")
                            colLabel: root.surfaceText
                            spinBg: root.spinBg
                            spinFg: root.spinFg
                            spinBgHover: root.spinBgHover
                            spinBgActive: root.spinBgActive
                            value: monitorConfig.monitors[index]?.x ?? 0
                            from: 0; to: 65535; stepSize: 1
                            onValueChanged: {
                                if (value === (monitorConfig.monitors[index]?.x ?? 0)) return
                                monitorConfig.updateMonitor(index, { x: value })
                                monitorConfig.applyAndSave(index)
                            }
                        }

                        ConfigSpinBox {
                            icon: "swap_vert"
                            text: Translation.tr("Position Y")
                            colLabel: root.surfaceText
                            spinBg: root.spinBg
                            spinFg: root.spinFg
                            spinBgHover: root.spinBgHover
                            spinBgActive: root.spinBgActive
                            value: monitorConfig.monitors[index]?.y ?? 0
                            from: 0; to: 65535; stepSize: 1
                            onValueChanged: {
                                if (value === (monitorConfig.monitors[index]?.y ?? 0)) return
                                monitorConfig.updateMonitor(index, { y: value })
                                monitorConfig.applyAndSave(index)
                            }
                        }

                        // HDR & color management for this monitor, inside
                        // its own dropdown (flat: continues the rows above
                        // without segment pills).
                        HdrSection {
                            monConfig: monitorConfig
                            monitorIndex: index
                            colToggled: root.accent
                            colToggledHover: root.accentHover
                            colToggledActive: root.accentActive
                            colTitle: root.titleColor
                            surfaceText: root.surfaceText
                            fieldBg: root.fieldBg
                            fieldBgHover: root.fieldBgHover
                            fieldBgActive: root.fieldBgActive
                            fieldText: root.fieldText
                            spinBg: root.spinBg
                            spinFg: root.spinFg
                            spinBgHover: root.spinBgHover
                            spinBgActive: root.spinBgActive
                            noticeBg: root.noticeBg
                            noticeFg: root.noticeFg
                            colChip: root.colChip
                            colChipHover: root.colChipHover
                            colChipActive: root.colChipActive
                            colChipText: root.colChipText
                            colToggledText: root.colToggledText
                            colPopup: root.colPopup
                            colPopupText: root.colPopupText
                            colPopupHover: root.colPopupHover
                            colPopupActive: root.colPopupActive
                        }
                    }
                }
            }
        }

        // Staged edits only: sits right under the monitor rows and
        // vanishes once reverted or applied so the section tightens again.
        RippleButton {
            visible: monitorConfig.dirty
            Layout.fillWidth: true
            Layout.topMargin: 4
            Layout.preferredHeight: monitorConfig.dirty ? 44 : 0
            buttonText: Translation.tr("Apply")
            buttonRadius: Appearance.rounding.full
            colBackground: root.accent
            colBackgroundHover: root.accentHover
            colRipple: root.accentActive
            downAction: () => monitorConfig.applyAll()
            contentItem: StyledText {
                text: parent.buttonText
                horizontalAlignment: Text.AlignHCenter
                color: root.accentOn
            }
        }

    }
