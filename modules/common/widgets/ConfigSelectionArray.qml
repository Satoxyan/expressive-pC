import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

RowLayout {
    id: root
    property string text: ""
    property string icon: ""
    property list<var> options: [
        {
            "displayName": "Option 1",
            "icon": "check",
            "value": 1
        },
        {
            "displayName": "Option 2",
            "icon": "close",
            "value": 2
        },
    ]
    property var currentValue: null
    // >0 = pecah opsi jadi baris sepanjang itu (3 → dua baris). 0 = satu baris.
    property int perRow: 0

    signal selected(var newValue)

    spacing: 10
    Layout.leftMargin: 8
    Layout.rightMargin: 8

    RowLayout {
        spacing: 10
        visible: root.text !== ""
        OptionalMaterialSymbol {
            icon: root.icon
            opacity: root.enabled ? 1 : 0.4
        }
        StyledText {
            id: labelWidget
            Layout.fillWidth: true
            text: root.text
            color: Appearance.colors.colOnSecondaryContainer
            opacity: root.enabled ? 1 : 0.4
        }
    }

    Column {
        id: buttonsFlow
        Layout.fillWidth: !root.text
        Layout.alignment: Qt.AlignRight
        spacing: 2

        Repeater {
            model: root.perRow > 0 ? Math.ceil(root.options.length / root.perRow) : 1
            delegate: Flow {
                id: row
                required property int index
                readonly property int start: root.perRow > 0 ? index * root.perRow : 0
                readonly property int end: root.perRow > 0
                    ? Math.min(start + root.perRow, root.options.length)
                    : root.options.length
                spacing: 2

                Repeater {
                    model: row.end - row.start
                    delegate: SelectionGroupButton {
                        id: paletteButton
                        required property int index
                        readonly property int gindex: row.start + index
                        leftmost: index === 0
                        rightmost: index === row.end - row.start - 1
                        buttonIcon: root.options[gindex].icon || ""
                        buttonText: root.options[gindex].displayName
                        toggled: root.currentValue == root.options[gindex].value
                        onClicked: {
                            root.selected(root.options[gindex].value);
                        }
                    }
                }
            }
        }
    }
}