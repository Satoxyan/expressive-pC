import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

DashboardCard {
    id: root

    property string controlKey: ""
    property string title: ""
    property string icon: "tune"
    property var tileShape: MaterialShape.Shape.Pentagon

    property var override: null
    // >0: split option chips into two rows after this index (e.g. visualizer style: 3 + rest)
    property int splitAfter: 0
    readonly property var control: override ?? SettingsQuickControls.controls[controlKey] ?? null
    readonly property var currentValue: control ? control.get() : null

    readonly property var optionRows: {
        const opts = control?.options ?? [];
        if (splitAfter <= 0 || opts.length <= splitAfter) return [opts];
        return [opts.slice(0, splitAfter), opts.slice(splitAfter)];
    }
    // natural height for grid row fitting (e.g. split option rows exceed default row height)
    readonly property real measuredHeight: col.implicitHeight + 28

    tint: Appearance.colors.colTertiaryContainer

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            MaterialShapeWrappedMaterialSymbol {
                shape: root.tileShape
                text: root.icon
                iconSize: 24
                fill: 1
                padding: 10
                color: Appearance.colors.colTertiary
                colSymbol: Appearance.colors.colOnTertiary
            }

            StyledText {
                Layout.fillWidth: true
                text: root.title
                font.pixelSize: Appearance.font.pixelSize.larger
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnTertiaryContainer
                elide: Text.ElideRight
            }
        }

        Item { Layout.fillHeight: true }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: root.optionRows

                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 8

                    Repeater {
                        model: modelData

                        delegate: RippleButton {
                            id: option
                            required property var modelData

                            readonly property bool selected: root.currentValue === modelData.value

                            Layout.fillWidth: true
                            Layout.preferredWidth: implicitWidth
                            implicitHeight: 44
                            horizontalPadding: 20
                            buttonRadius: 22
                            colBackground: selected ? Appearance.colors.colTertiary : Qt.rgba(1, 1, 1, 0.12)
                            colBackgroundHover: selected ? Appearance.colors.colTertiary : Qt.rgba(1, 1, 1, 0.22)
                            colRipple: Qt.rgba(1, 1, 1, 0.3)
                            downAction: () => {
                                const value = modelData.value;
                                Qt.callLater(() => root.control.set(value));
                            }

                            contentItem: Item {
                                implicitWidth: optionRow.implicitWidth
                                implicitHeight: optionRow.implicitHeight

                                RowLayout {
                                    id: optionRow
                                    anchors.centerIn: parent
                                    spacing: 6

                                    MaterialSymbol {
                                        text: option.modelData.icon ?? ""
                                        iconSize: 18
                                        fill: option.selected ? 1 : 0
                                        color: option.selected ? Appearance.colors.colOnTertiary : Appearance.colors.colOnTertiaryContainer
                                    }
                                    StyledText {
                                        text: option.modelData.displayName
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.Medium
                                        color: option.selected ? Appearance.colors.colOnTertiary : Appearance.colors.colOnTertiaryContainer
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
