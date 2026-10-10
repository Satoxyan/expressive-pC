import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

// Stickers section: per-sticker enable/image/outline rows + add button.
// Shared by the default Desktop settings page and the dashboard Stickers card.
ContentSection {
    id: root
    icon: "sticker"
    shape: MaterialShape.Shape.Cookie6Sided
    title: Translation.tr("Stickers")

    // M3 Expressive follow-through: the dashboard passes the tertiary family
    // here; defaults equal the old hard-coded colors so default mode stays
    // pixel-identical.
    property color accent: Appearance.colors.colPrimary
    property color accentContainer: Appearance.colors.colPrimaryContainer
    property color switchActive: Appearance.colors.colPrimaryContainer
    property color switchThumb: Appearance.colors.colPrimary
    property color accentOn: Appearance.colors.colOnPrimary
    property color surfaceBg: Appearance.colors.colSecondaryContainer
    property color rowBg: Appearance.colors.colLayer1
    property color rowTitle: Appearance?.m3colors.m3onBackground ?? "black"
    property color mutedText: Appearance.colors.colOnSurfaceVariant
    property color surfaceText: Appearance.colors.colOnSecondaryContainer

    Repeater {
        model: Config.stickers.length
        delegate: GroupedList {
            required property int index
            readonly property var modelData: Config.stickers[index]
            Layout.fillWidth: true
            bgcolor: root.rowBg

            RowLayout {
                Layout.fillWidth: true
                MaterialSymbol {
                    iconSize: Appearance.font.pixelSize.large
                    text: "sticker"
                    color: root.mutedText
                }
                StyledText {
                    text: Translation.tr("Sticker %1").arg(index + 1)
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: root.rowTitle
                    Layout.fillWidth: true
                }
                RippleButtonWithIcon {
                    materialIcon: "delete"
                    mainText: Translation.tr("Remove")
                    colText: root.surfaceText
                    colIcon: root.surfaceText
                    onClicked: {
                        Config.removeSticker(index)
                    }
                }
            }

            ConfigSwitch {
                Layout.fillWidth: true
                buttonIcon: "check"
                text: Translation.tr("Enable")
                colText: root.surfaceText
                colIcon: root.surfaceText
                switchActiveColor: root.switchActive
                switchThumbColor: root.switchThumb
                checked: modelData.enable
                onCheckedChanged: {
                    // Skip the initial binding write — it cascades into a
                    // Repeater model binding loop that kills row rendering.
                    if (checked !== modelData.enable)
                        Config.updateSticker(index, { enable: checked });
                }
            }
            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "image"
                mainText: Translation.tr("Choose image")
                colText: root.surfaceText
                colIcon: root.surfaceText
                onClicked: {
                    FilePicker.pickImage(path => Config.updateSticker(index, { path }))
                }
            }
            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    text: Translation.tr("Outline color")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: root.mutedText
                    Layout.fillWidth: true
                }
                Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: 8
                    color: modelData.outlineColor ?? "#ffffff"
                    border.width: 1
                    border.color: Appearance.colors.colOutline
                }
            }
            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    text: Translation.tr("Outline width")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: root.mutedText
                    Layout.fillWidth: true
                }
                StyledSlider {
                    Layout.preferredWidth: 150
                    highlightColor: root.accent
                    trackColor: root.surfaceBg
                    handleColor: root.accent
                    dotColor: root.surfaceText
                    dotColorHighlighted: root.accentOn
                    from: 0
                    to: 24
                    value: modelData.outlineWidth ?? 8
                    onMoved: Config.updateSticker(index, { outlineWidth: value })
                }
            }
        }
    }
    GroupedList {
        bgcolor: root.rowBg
        RippleButtonWithIcon {
            Layout.fillWidth: true
            materialIcon: "add"
            mainText: Translation.tr("Add Sticker")
            colText: root.surfaceText
            colIcon: root.surfaceText
            onClicked: {
                Config.addSticker()
            }
        }
    }
}
