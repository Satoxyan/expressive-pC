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
    icon: "sticker"
    shape: MaterialShape.Shape.Cookie6Sided
    title: Translation.tr("Stickers")
    Repeater {
        model: Config.stickers.length
        delegate: GroupedList {
            required property int index
            readonly property var modelData: Config.stickers[index]
            Layout.fillWidth: true
            
            RowLayout {
                Layout.fillWidth: true
                MaterialSymbol {
                    iconSize: Appearance.font.pixelSize.large
                    text: "sticker"
                    color: Appearance.colors.colOnSurfaceVariant
                }
                StyledText {
                    text: Translation.tr("Sticker %1").arg(index + 1)
                    font.pixelSize: Appearance.font.pixelSize.large
                    Layout.fillWidth: true
                }
                RippleButtonWithIcon {
                    materialIcon: "delete"
                    mainText: Translation.tr("Remove")
                    onClicked: {
                        Config.removeSticker(index)
                    }
                }
            }
            
            ConfigSwitch {
                Layout.fillWidth: true
                buttonIcon: "check"
                text: Translation.tr("Enable")
                checked: modelData.enable
                onCheckedChanged: {
                    Config.updateSticker(index, { enable: checked });
                }
            }
            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "image"
                mainText: Translation.tr("Choose image")
                onClicked: {
                    FilePicker.pickImage(path => Config.updateSticker(index, { path }))
                }
            }
            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    text: Translation.tr("Outline color")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnSurfaceVariant
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
                    color: Appearance.colors.colOnSurfaceVariant
                    Layout.fillWidth: true
                }
                StyledSlider {
                    Layout.preferredWidth: 150
                    from: 0
                    to: 24
                    value: modelData.outlineWidth ?? 8
                    onMoved: Config.updateSticker(index, { outlineWidth: value })
                }
            }
        }
    }
    GroupedList {
        RippleButtonWithIcon {
            Layout.fillWidth: true
            materialIcon: "add"
            mainText: Translation.tr("Add Sticker")
            onClicked: {
                Config.addSticker()
            }
        }
    }
}
