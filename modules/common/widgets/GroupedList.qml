import qs.modules.common
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    default property list<Item> items
    property real bigRadius: Appearance.rounding.normal
    property real smallRadius: Appearance.rounding.unsharpenmore
    property color bgcolor: Appearance.colors.colLayer1
    property real itemVerticalPadding: 24
    // flat: skip the per-item segment pills — children sit directly like
    // plain page rows (HDR dropdown so it merges with the rows above it).
    property bool flat: false
    Layout.fillWidth: true
    implicitHeight: root.flat ? plainCol.implicitHeight : col.implicitHeight

    ColumnLayout {
        id: col
        anchors.fill: parent
        spacing: 2

        Repeater {
            model: root.flat ? 0 : root.items.length
            delegate: Rectangle {
                required property int index
                readonly property bool isFirst: index === 0
                readonly property bool isLast: index === root.items.length - 1
                Layout.fillWidth: true
                implicitHeight: (root.items[index]?.implicitHeight ?? 0) + root.itemVerticalPadding
                color: root.bgcolor
                topLeftRadius:     isFirst ? root.bigRadius : root.smallRadius
                topRightRadius:    isFirst ? root.bigRadius : root.smallRadius
                bottomLeftRadius:  isLast  ? root.bigRadius : root.smallRadius
                bottomRightRadius: isLast  ? root.bigRadius : root.smallRadius

                Component.onCompleted: {
                    const child = root.items[index]
                    if (child) {
                        child.parent = contentArea
                        child.Layout.fillWidth = true
                    }
                }

                ColumnLayout {
                    id: contentArea
                    anchors { fill: parent; margins: 8 }
                    spacing: 0
                }
            }
        }
    }

    // flat host: children are moved here once, at creation, laid out
    // directly with no pill, margin or extra padding.
    ColumnLayout {
        id: plainCol
        visible: root.flat
        anchors.fill: parent
        spacing: 8
    }

    Component.onCompleted: {
        if (!root.flat) return;
        for (const child of root.items) {
            child.parent = plainCol;
            child.Layout.fillWidth = true;
        }
    }
}