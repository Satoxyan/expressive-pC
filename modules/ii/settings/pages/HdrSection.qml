import QtQuick
import QtQuick.Layouts
import qs.services
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

    readonly property var mon: root.monConfig?.monitors[root.monitorIndex]
    readonly property bool hdrActive: root.mon?.cm === "hdr" || root.mon?.cm === "hdredid"

    title: Translation.tr("HDR & Color Management")

    NoticeBox {
        Layout.fillWidth: true
        visible: root.mon?.hdrSupported === null
        text: Translation.tr("Couldn't confirm this display's HDR capability from its EDID. Options are shown but may not do anything.")
    }

    NoticeBox {
        Layout.fillWidth: true
        visible: root.mon?.hdrSupported === false
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
