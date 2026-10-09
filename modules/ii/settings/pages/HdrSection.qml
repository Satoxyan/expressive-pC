import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// "HDR & Color Management" controls for one monitor. Instantiated inside
// each monitor's dropdown by the shared Displays section (default settings
// page and dashboard Displays card alike); flat so it continues the
// dropdown's plain rows without segment pills.
ContentSubsection {
    id: root

    // The MonitorConfigOption to drive, and which monitor this copy edits.
    property var monConfig
    property int monitorIndex: 0
    // Accent for the selected chip; default keeps the primary accent.
    property color colToggled: Appearance.colors.colPrimary
    property color colToggledHover: Appearance.colors.colPrimaryHover
    property color colToggledActive: Appearance.colors.colPrimaryActive
    // Labels and controls; defaults keep the old hard-coded colours.
    property color surfaceText: Appearance.colors.colOnSecondaryContainer
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
    // Unselected chips and combobox popup; defaults keep the old greys.
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

    readonly property var mon: root.monConfig?.monitors[root.monitorIndex]
    readonly property bool hdrActive: root.mon?.cm === "hdr" || root.mon?.cm === "hdredid"

    title: Translation.tr("HDR & Color Management")

    NoticeBox {
        Layout.fillWidth: true
        visible: root.mon?.hdrSupported === null
        colBg: root.noticeBg
        colFg: root.noticeFg
        text: Translation.tr("Couldn't confirm this display's HDR capability from its EDID. Options are shown but may not do anything.")
    }

    NoticeBox {
        Layout.fillWidth: true
        visible: root.mon?.hdrSupported === false
        colBg: root.noticeBg
        colFg: root.noticeFg
        text: Translation.tr("This display's EDID does not report HDR support, so HDR options are disabled here. Open an issue in GitHub if you think this is a mistake.")
    }

    GroupedList {
        // flat: continues the dropdown's plain rows — no segment pills.
        flat: true
        // breathing room above the first row (Bit depth).
        Layout.topMargin: 10
        ConfigSelectionArray {
            text: Translation.tr("Bit depth")
            icon: "gradient"
            colLabel: root.surfaceText
            colChip: root.colChip
            colChipHover: root.colChipHover
            colChipActive: root.colChipActive
            colChipText: root.colChipText
            colToggled: root.colToggled
            colToggledText: root.colToggledText
            colToggledHover: root.colToggledHover
            colToggledActive: root.colToggledActive
            currentValue: root.mon?.bitdepth ?? (root.mon?.maxBpc ?? 8)
            onSelected: newValue => {
                root.monConfig.updateMonitor(root.monitorIndex, { bitdepth: newValue })
                root.monConfig.saveHdr(root.monitorIndex)
            }
            options: (() => {
                const maxBpc = root.mon?.maxBpc ?? 8
                return [
                    { displayName: "8-bit",  icon: "filter_8", value: 8  },
                    { displayName: "10-bit", icon: "palette",   value: 10 },
                    { displayName: "12-bit", icon: "hdr_on",   value: 12 },
                ].filter(o => o.value <= maxBpc)
            })()
        }

        ConfigComboBox {
            Layout.fillWidth: true
            buttonIcon: "palette"
            text: Translation.tr("Color management")
            colLabel: root.surfaceText
            fieldBg: root.fieldBg
            fieldBgHover: root.fieldBgHover
            fieldBgActive: root.fieldBgActive
            fieldText: root.fieldText
            colPopup: root.colPopup
            colPopupText: root.colPopupText
            colPopupHover: root.colPopupHover
            colPopupActive: root.colPopupActive
            enabled: root.mon?.hdrSupported !== false
            model: [
                { displayName: Translation.tr("Auto"),       icon: "auto_awesome",  value: "auto"    },
                { displayName: "sRGB",                       icon: "light_mode",    value: "srgb"    },
                { displayName: Translation.tr("Wide (P3)"),  icon: "wb_iridescent", value: "wide"    },
                { displayName: "HDR",                        icon: "hdr_on",        value: "hdr"     },
                { displayName: Translation.tr("HDR (EDID)"), icon: "hdr_auto",      value: "hdredid" },
            ]
            currentValue: root.mon?.cm ?? "auto"
            onSelected: newValue => {
                root.monConfig.updateMonitor(root.monitorIndex, { cm: newValue })
                root.monConfig.saveHdr(root.monitorIndex)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            ConfigSpinBox {
                Layout.fillWidth: true
                enabled: root.hdrActive
                icon: "brightness_6"
                text: Translation.tr("SDR brightness")
                colLabel: root.surfaceText
                spinBg: root.spinBg
                spinFg: root.spinFg
                spinBgHover: root.spinBgHover
                spinBgActive: root.spinBgActive
                value: Math.round((root.mon?.sdrBrightness ?? 1.0) * 100)
                from: 10; to: 300; stepSize: 5
                onValueChanged: {
                    const newVal = value / 100.0
                    if (newVal === (root.mon?.sdrBrightness ?? 1.0)) return
                    root.monConfig.updateMonitor(root.monitorIndex, { sdrBrightness: newVal })
                    root.monConfig.saveHdr(root.monitorIndex)
                }
            }

            ConfigSpinBox {
                Layout.fillWidth: true
                enabled: root.hdrActive
                icon: "contrast"
                text: Translation.tr("SDR saturation")
                colLabel: root.surfaceText
                spinBg: root.spinBg
                spinFg: root.spinFg
                spinBgHover: root.spinBgHover
                spinBgActive: root.spinBgActive
                value: Math.round((root.mon?.sdrSaturation ?? 1.0) * 100)
                from: 10; to: 200; stepSize: 5
                onValueChanged: {
                    const newVal = value / 100.0
                    if (newVal === (root.mon?.sdrSaturation ?? 1.0)) return
                    root.monConfig.updateMonitor(root.monitorIndex, { sdrSaturation: newVal })
                    root.monConfig.saveHdr(root.monitorIndex)
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            ConfigSpinBox {
                Layout.fillWidth: true
                enabled: root.hdrActive
                icon: "wb_twilight"
                text: Translation.tr("SDR min (nits)")
                colLabel: root.surfaceText
                spinBg: root.spinBg
                spinFg: root.spinFg
                spinBgHover: root.spinBgHover
                spinBgActive: root.spinBgActive
                value: root.mon?.sdrMinLuminance ?? 0
                from: 0; to: 100; stepSize: 1
                onValueChanged: {
                    if (value === (root.mon?.sdrMinLuminance ?? 0)) return
                    root.monConfig.updateMonitor(root.monitorIndex, { sdrMinLuminance: value })
                    root.monConfig.saveHdr(root.monitorIndex)
                }
            }

            ConfigSpinBox {
                Layout.fillWidth: true
                enabled: root.hdrActive
                icon: "wb_sunny"
                text: Translation.tr("SDR max (nits)")
                colLabel: root.surfaceText
                spinBg: root.spinBg
                spinFg: root.spinFg
                spinBgHover: root.spinBgHover
                spinBgActive: root.spinBgActive
                value: root.mon?.sdrMaxLuminance ?? 250
                from: 50; to: 2000; stepSize: 10
                onValueChanged: {
                    if (value === (root.mon?.sdrMaxLuminance ?? 250)) return
                    root.monConfig.updateMonitor(root.monitorIndex, { sdrMaxLuminance: value })
                    root.monConfig.saveHdr(root.monitorIndex)
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            ConfigSpinBox {
                Layout.fillWidth: true
                enabled: root.hdrActive
                icon: "nightlight"
                text: Translation.tr("HDR min (nits)")
                colLabel: root.surfaceText
                spinBg: root.spinBg
                spinFg: root.spinFg
                spinBgHover: root.spinBgHover
                spinBgActive: root.spinBgActive
                value: root.mon?.minLuminance ?? 0
                from: 0; to: 100; stepSize: 1
                onValueChanged: {
                    if (value === (root.mon?.minLuminance ?? 0)) return
                    root.monConfig.updateMonitor(root.monitorIndex, { minLuminance: value })
                    root.monConfig.saveHdr(root.monitorIndex)
                }
            }

            ConfigSpinBox {
                Layout.fillWidth: true
                enabled: root.hdrActive
                icon: "hdr_strong"
                text: Translation.tr("HDR peak (nits)")
                colLabel: root.surfaceText
                spinBg: root.spinBg
                spinFg: root.spinFg
                spinBgHover: root.spinBgHover
                spinBgActive: root.spinBgActive
                value: root.mon?.maxLuminance ?? 1000
                from: 100; to: 10000; stepSize: 50
                onValueChanged: {
                    if (value === (root.mon?.maxLuminance ?? 1000)) return
                    root.monConfig.updateMonitor(root.monitorIndex, { maxLuminance: value })
                    root.monConfig.saveHdr(root.monitorIndex)
                }
            }
        }

        ConfigSpinBox {
            enabled: root.hdrActive
            icon: "hdr_weak"
            text: Translation.tr("HDR max average luminance (nits)")
            colLabel: root.surfaceText
            spinBg: root.spinBg
            spinFg: root.spinFg
            spinBgHover: root.spinBgHover
            spinBgActive: root.spinBgActive
            value: root.mon?.maxAvgLuminance ?? 250
            from: 50; to: 5000; stepSize: 10
            onValueChanged: {
                if (value === (root.mon?.maxAvgLuminance ?? 250)) return
                root.monConfig.updateMonitor(root.monitorIndex, { maxAvgLuminance: value })
                root.monConfig.saveHdr(root.monitorIndex)
            }
        }
    }
}
