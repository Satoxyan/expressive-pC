pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * ConfigSelectionArray for the Phone tab's narrow settings pages: the
 * label and its hint keep the top line, and the chips move to their own
 * line below, right-aligned, wrapping only when they no longer fit.
 */
ColumnLayout {
    id: root

    property string text: ""
    property string icon: ""
    property string infoText: ""
    property var options: []
    property var currentValue: null
    // The page fades this row out and stops the chips from taking input while
    // another control (Auto rotation) owns the value; the hint stays readable.
    property bool dimmed: false

    signal selected(var newValue)

    Layout.fillWidth: true
    Layout.leftMargin: 8
    Layout.rightMargin: 8
    spacing: 8

    RowLayout {
        Layout.fillWidth: true
        spacing: 10
        visible: root.text !== ""

        OptionalMaterialSymbol {
            icon: root.icon
            iconColor: Appearance.colors.colOnSecondaryContainer
            opacity: (root.enabled && !root.dimmed) ? 1 : 0.4
        }

        StyledText {
            text: root.text
            color: Appearance.colors.colOnSecondaryContainer
            opacity: (root.enabled && !root.dimmed) ? 1 : 0.4
        }

        InfoTooltipIcon {
            visible: root.infoText !== ""
            tooltipText: root.infoText
            opacity: root.dimmed ? 0.4 : 1
        }

        // Keeps the hint right beside the title instead of at the far edge.
        Item {
            Layout.fillWidth: true
        }
    }

    // Chips keep their order and each row is right-aligned; a chip only moves
    // to a new row when it would run past the right edge.
    Item {
        id: chipsHost
        Layout.fillWidth: true
        implicitHeight: totalHeight
        opacity: root.dimmed ? 0.4 : 1

        property real totalHeight: 0
        property real chipSpacing: 2
        property real rowSpacing: 6

        function relayout() {
            if (chipsHost.width <= 0) {
                chipsHost.totalHeight = 0;
                return;
            }

            let y = 0;
            let row = [];
            let rowWidth = 0;

            function placeRow() {
                if (row.length === 0) return;
                let rowHeight = 0;
                for (const chip of row)
                    rowHeight = Math.max(rowHeight, chip.implicitHeight);
                let x = chipsHost.width - rowWidth;
                for (let i = 0; i < row.length; i++) {
                    const chip = row[i];
                    chip.x = x;
                    chip.y = y + (rowHeight - chip.implicitHeight) / 2;
                    chip.leftmost = i === 0;
                    chip.rightmost = i === row.length - 1;
                    x += chip.implicitWidth + chipsHost.chipSpacing;
                }
                y += rowHeight + chipsHost.rowSpacing;
                row = [];
                rowWidth = 0;
            }

            for (let i = 0; i < chipRepeater.count; i++) {
                const chip = chipRepeater.itemAt(i);
                if (!chip) continue;
                const step = chip.implicitWidth + chipsHost.chipSpacing;
                if (row.length > 0 && rowWidth + step > chipsHost.width)
                    placeRow();
                rowWidth = row.length === 0 ? chip.implicitWidth : rowWidth + step;
                row.push(chip);
            }
            placeRow();
            chipsHost.totalHeight = Math.max(0, y - chipsHost.rowSpacing);
        }

        onWidthChanged: Qt.callLater(relayout)

        Repeater {
            id: chipRepeater
            model: root.options
            onItemAdded: Qt.callLater(chipsHost.relayout)
            onItemRemoved: Qt.callLater(chipsHost.relayout)

            delegate: SelectionGroupButton {
                id: chip
                required property var modelData

                buttonIcon: modelData.icon || ""
                buttonText: modelData.displayName ?? ""
                toggled: root.currentValue == modelData.value
                enabled: !root.dimmed
                leftmost: false
                rightmost: false
                baseWidth: contentItem.implicitWidth + horizontalPadding * 2
                enableImplicitWidthAnimation: true

                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colBackgroundActive: Appearance.colors.colSecondaryContainerActive
                colTextInactive: Appearance.colors.colOnSecondaryContainer
                colTextActive: Appearance.colors.colOnPrimary
                colBackgroundToggled: Appearance.colors.colPrimary
                colBackgroundToggledHover: Appearance.colors.colPrimaryHover
                colBackgroundToggledActive: Appearance.colors.colPrimaryActive

                onImplicitWidthChanged: Qt.callLater(chipsHost.relayout)
                onImplicitHeightChanged: Qt.callLater(chipsHost.relayout)
                onClicked: root.selected(modelData.value)
            }
        }
    }
}
