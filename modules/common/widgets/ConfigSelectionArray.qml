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
    property bool textOnlyWhenActive: false

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
        Layout.preferredWidth: root.textOnlyWhenActive ? singleRowWidth() : implicitWidth
        Layout.minimumWidth: root.textOnlyWhenActive ? Layout.preferredWidth : 0
        Layout.preferredHeight: root.textOnlyWhenActive ? singleRowHeight() : implicitHeight
        Layout.maximumHeight: root.textOnlyWhenActive ? Layout.preferredHeight : Number.POSITIVE_INFINITY
        clip: root.textOnlyWhenActive

        // buttonsFlow = Column; anaknya bisa Repeater atau baris (Flow), dan
        // tombolnya ada di tingkat dalam (delegate tiap baris). Kumpulkan dulu
        // jadi daftar baris → daftar tombol, biar ukuran di bawah ikut struktur
        // perRow, bukan asumsi satu baris datar.
        function buttonRows() {
            const rows = [];
            for (let i = 0; i < children.length; i++) {
                const kids = children[i].children;
                if (kids === undefined) continue;
                const btns = [];
                for (let j = 0; j < kids.length; j++) {
                    if (kids[j].count !== undefined) continue; // Repeater, bukan tombol
                    btns.push(kids[j]);
                }
                if (btns.length > 0) rows.push(btns);
            }
            return rows;
        }

        function singleRowHeight() {
            const rows = buttonRows();
            let h = 0;
            for (let i = 0; i < rows.length; i++) {
                let rh = 0;
                for (let j = 0; j < rows[i].length; j++)
                    rh = Math.max(rh, rows[i][j].implicitHeight);
                h += rh;
            }
            return h + Math.max(0, rows.length - 1) * spacing;
        }

        function singleRowWidth() {
            let widest = 0;
            for (const r of buttonRows()) {
                let w = 0;
                for (const b of r) w += b.implicitWidth;
                if (r.length > 1) w += (r.length - 1) * spacing;
                widest = Math.max(widest, w);
            }
            return widest;
        }

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
                        enableImplicitWidthAnimation: !root.textOnlyWhenActive
                        Behavior on implicitWidth {
                            enabled: root.textOnlyWhenActive
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Appearance.animation.elementMoveFast.type
                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                            }
                        }
                        baseWidth: root.textOnlyWhenActive
                            ? contentItem.children[0].implicitWidth + (buttonText.length > 0 ? contentItem.spacing + contentItem.children[1].children[0].implicitWidth : 0) + horizontalPadding * 2
                            : contentItem.implicitWidth + horizontalPadding * 2
                        leftmost: index === 0
                        rightmost: index === row.end - row.start - 1
                        buttonIcon: root.options[gindex].icon || ""
                        buttonText: (!root.textOnlyWhenActive || toggled || hovered) ? root.options[gindex].displayName : ""
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