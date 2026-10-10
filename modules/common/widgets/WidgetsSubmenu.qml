pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    implicitHeight: col.implicitHeight + 16

    readonly property var widgetList: DesktopWidgets.menuItems

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colUiBackground
    }

    ColumnLayout {
        id: col
        anchors { fill: parent; margins: 8 }
        spacing: 2

        ConfigSwitch {
            Layout.fillWidth: true
            buttonIcon: "lock"
            text: Translation.tr("Lock widget positions")
            checked: Config.options.background.widgetsLocked
            onCheckedChanged: Config.options.background.widgetsLocked = checked
        }
        ConfigSwitch {
            Layout.fillWidth: true
            buttonIcon: "shadow"
            text: Translation.tr("Shadow")
            checked: Config.options.background.widgets.shadow 
            onCheckedChanged: Config.options.background.widgets.shadow = checked
        }
        ConfigSwitch {
            Layout.fillWidth: true
            buttonIcon: "blur_on"
            text: Translation.tr("Blur all widgets")
            checked: Config.options.background.widgets.blurWidgets
            onCheckedChanged: {
                Config.options.background.widgets.blurWidgets = checked
                const keys = ["weather","clock","images","media","resources","calendar","worldClock","userCard","notes","todo","timers"]
                keys.forEach(k => { Config.options.background.widgets[k].blur = checked })
            }
        }

        ConfigSwitch {
            Layout.fillWidth: true
            buttonIcon: "palette"
            text: Translation.tr("Tint all widgets")
            visible: Config.options.background.widgets.blurWidgets
            checked: Config.options.background.widgets.tintBlur
            onCheckedChanged: {
                Config.options.background.widgets.tintBlur = checked
                const keys = ["weather","clock","images","media","resources","calendar","worldClock","userCard","notes","todo","timers"]
                keys.forEach(k => { Config.options.background.widgets[k].tintBlur = checked })
            }
        }

        ConfigSlider {
            Layout.fillWidth: true
            showLabel: false
            visible: Config.options.background.widgets.blurWidgets
            value: Config.options.background.widgets.blurRadius ?? 32
            usePercentTooltip: false
            buttonIcon: "aspect_ratio"
            from: 1
            to: 64
            stopIndicatorValues: [32]
            onValueChanged: Config.options.background.widgets.blurRadius = value
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 4
            Layout.bottomMargin: 4
            implicitHeight: 1
            color: Appearance.colors.colOutlineVariant
            opacity: 0.4
        }

        Repeater {
            model: root.widgetList
            delegate: Loader {
                id: entry

                required property var modelData
                Layout.fillWidth: true
                Layout.bottomMargin: 6 // ConfigSwitch normally carries this; it's lost inside a Loader
                sourceComponent: ["customImage", "sticker", "imageCard"].includes(entry.modelData.key) ? addRow : toggleSwitch

                function add() {
                    if (entry.modelData.key === "sticker") Config.addSticker();
                    else if (entry.modelData.key === "imageCard") Config.addImageCard();
                    else Config.addCustomImage();
                }

                Component {
                    id: toggleSwitch
                    ConfigSwitch {
                        buttonIcon: entry.modelData.icon
                        text: entry.modelData.name
                        checked: Config.options.background.widgets[entry.modelData.key].enable
                        onCheckedChanged: Config.options.background.widgets[entry.modelData.key].enable = checked
                    }
                }

                // Custom Image / Sticker / Image Card: mirrors ConfigSwitch structure exactly, "+" instead of the switch
                Component {
                    id: addRow
                    RippleButton {
                        id: addBtn

                        colBackgroundHover: "transparent"
                        implicitHeight: contentItem.implicitHeight + 8
                        font.pixelSize: Appearance.font.pixelSize.small
                        onClicked: entry.add()

                        contentItem: RowLayout {
                            spacing: 10
                            OptionalMaterialSymbol {
                                icon: entry.modelData.icon
                                iconSize: Appearance.font.pixelSize.larger
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: entry.modelData.name
                                font: addBtn.font
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                            MaterialShapeWrappedMaterialSymbol {
                                wrappedShape: MaterialShape.Shape.Circle
                                color: Appearance.colors.colPrimary
                                colSymbol: Appearance.colors.colOnPrimary
                                text: "add"
                                iconSize: 18
                                fill: 1
                                padding: 6

                                ButtonMouseArea {
                                    anchors.fill: parent
                                    onClicked: entry.add()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}