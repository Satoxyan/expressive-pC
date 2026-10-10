import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

// Custom images section: per-image enable/image/shape rows + add button.
// Shared by the default Desktop settings page and the dashboard Custom images card.
ContentSection {
    id: root
    icon: "panorama"
    shape: MaterialShape.Shape.SoftBoom
    title: Translation.tr("Custom Images")

    // M3 Expressive follow-through: the dashboard passes the tertiary family
    // here; defaults equal the old hard-coded colors so default mode stays
    // pixel-identical.
    property color accent: Appearance.colors.colPrimary
    property color accentHover: Appearance.colors.colPrimaryHover
    property color accentActive: Appearance.colors.colPrimaryActive
    property color accentContainer: Appearance.colors.colPrimaryContainer
    property color switchActive: Appearance.colors.colPrimaryContainer
    property color switchThumb: Appearance.colors.colPrimary
    property color accentOn: Appearance.colors.colOnPrimary
    property color rowBg: Appearance.colors.colLayer1
    property color rowTitle: Appearance?.m3colors.m3onBackground ?? "black"
    property color mutedText: Appearance.colors.colOnSurfaceVariant
    property color surfaceText: Appearance.colors.colOnSecondaryContainer
    property color colChip: Appearance.colors.colSecondaryContainer
    property color colChipHover: Appearance.colors.colSecondaryContainerHover
    property color colChipActive: Appearance.colors.colSecondaryContainerActive

    Repeater {
        model: Config.customImages.length
        delegate: GroupedList {
            required property int index
            readonly property var modelData: Config.customImages[index]
            Layout.fillWidth: true
            bgcolor: root.rowBg

            RowLayout {
                Layout.fillWidth: true
                MaterialSymbol {
                    iconSize: Appearance.font.pixelSize.large
                    text: "image"
                    color: root.mutedText
                }
                StyledText {
                    text: Translation.tr("Image %1").arg(index + 1)
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
                        Config.removeCustomImage(index)
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
                        Config.updateCustomImage(index, { enable: checked });
                }
            }
            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "image"
                mainText: Translation.tr("Choose image")
                colText: root.surfaceText
                colIcon: root.surfaceText
                onClicked: {
                    FilePicker.pickImage(path => Config.updateCustomImage(index, { path }))
                }
            }
            ConfigSelectionShapeArray {
                currentValue: modelData.shape
                shapeColor: root.accent
                backgroundColor: root.accentContainer
                colBackground: root.colChip
                colBackgroundHover: root.colChipHover
                colBackgroundActive: root.colChipActive
                colToggled: root.accent
                colToggledHover: root.accentHover
                colToggledActive: root.accentActive
                colToggledSymbol: root.accentOn
                options: [
                    "Circle", "Square", "Slanted", "Arch", "Arrow", "SemiCircle", "Oval", "Pill",
                    "Triangle", "Diamond", "ClamShell", "Pentagon", "Gem", "Sunny", "VerySunny",
                    "Cookie4Sided", "Cookie6Sided", "Cookie7Sided", "Cookie9Sided", "Cookie12Sided",
                    "Ghostish", "Clover4Leaf", "Clover8Leaf", "Burst", "SoftBurst", "Flower",
                    "Puffy", "PuffyDiamond", "PixelCircle", "Bun", "Heart"
                ]
                onSelected: newValue => {
                    Config.updateCustomImage(index, { shape: newValue })
                }
            }
        }
    }
    GroupedList {
        bgcolor: root.rowBg
        RippleButtonWithIcon {
            Layout.fillWidth: true
            materialIcon: "add"
            mainText: Translation.tr("Add Image")
            colText: root.surfaceText
            colIcon: root.surfaceText
            onClicked: {
                Config.addCustomImage()
            }
        }
    }
}
