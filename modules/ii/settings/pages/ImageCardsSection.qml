import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

// Image cards section: per-card enable/image/layout rows + add button.
// Shared by the default Desktop settings page and the dashboard Image cards card.
ContentSection {
    icon: "photo_size_select_large"
    shape: MaterialShape.Shape.ClamShell
    title: Translation.tr("Image cards")
    Repeater {
        model: Config.imageCards.length
        delegate: GroupedList {
            required property int index
            readonly property var modelData: Config.imageCards[index]
            Layout.fillWidth: true

            RowLayout {
                Layout.fillWidth: true
                MaterialSymbol {
                    iconSize: Appearance.font.pixelSize.large
                    text: "photo_size_select_large"
                    color: Appearance.colors.colOnSurfaceVariant
                }
                StyledText {
                    text: Translation.tr("Card %1").arg(index + 1)
                    font.pixelSize: Appearance.font.pixelSize.large
                    Layout.fillWidth: true
                }
                RippleButtonWithIcon {
                    materialIcon: "delete"
                    mainText: Translation.tr("Remove")
                    onClicked: {
                        Config.removeImageCard(index)
                    }
                }
            }

            ConfigSwitch {
                Layout.fillWidth: true
                buttonIcon: "check"
                text: Translation.tr("Enable")
                checked: modelData.enable
                onCheckedChanged: {
                    Config.updateImageCard(index, { enable: checked });
                }
            }
            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "image"
                mainText: Translation.tr("Choose image")
                onClicked: {
                    FilePicker.pickImage(path => Config.updateImageCard(index, { path }))
                }
            }
            ConfigSelectionArray {
                enabled: modelData.enable
                text: Translation.tr("Image card layout")
                icon: "grid_view"
                currentValue: modelData.sizeMode ?? "1x2"
                options: [
                    { displayName: "1x1", icon: "crop_square", value: "1x1" },
                    { displayName: "1x2", icon: "crop_landscape", value: "1x2" },
                    { displayName: "1x3", icon: "crop_16_9", value: "1x3" },
                    { displayName: "2x2", icon: "grid_view", value: "2x2" },
                    { displayName: "2x3", icon: "view_module", value: "2x3" }
                ]
                onSelected: newValue => {
                    Config.updateImageCard(index, { sizeMode: newValue })
                }
            }
        }
    }
    GroupedList {
        RippleButtonWithIcon {
            Layout.fillWidth: true
            materialIcon: "add"
            mainText: Translation.tr("Add Image Card")
            onClicked: {
                Config.addImageCard()
            }
        }
    }
}
