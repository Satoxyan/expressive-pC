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
    property bool glass: false
    // Model-driven spelling: a group whose rows are only known at runtime.
    property var model: null
    property Component rowDelegate: null
    readonly property bool modelDriven: root.rowDelegate !== null
    Layout.fillWidth: true
    implicitHeight: root.flat ? plainCol.implicitHeight : col.implicitHeight

    ColumnLayout {
        id: col
        anchors.fill: parent
        spacing: 2

        Repeater {
            model: root.flat ? 0 : (root.modelDriven ? root.model : root.items.length)
            delegate: Rectangle {
                id: plate
                required property int index
                required property var modelData
                readonly property bool isFirst: index === 0
                readonly property bool isLast: index === (root.modelDriven ? (root.model?.length ?? 0) : root.items.length) - 1
                Layout.fillWidth: true
                implicitHeight: (root.modelDriven
                    ? (rowLoader.item?.implicitHeight ?? 0)
                    : (root.items[index]?.implicitHeight ?? 0)) + root.itemVerticalPadding
                color: root.bgcolor

                WindowGlass {
                    anchors.fill: parent
                    glassEnabled: root?.glass ?? false
                    topLeftRadius: parent.topLeftRadius
                    topRightRadius: parent.topRightRadius
                    bottomLeftRadius: parent.bottomLeftRadius
                    bottomRightRadius: parent.bottomRightRadius
                    tint: root?.bgcolor ?? "transparent"
                }
                topLeftRadius:     isFirst ? root.bigRadius : root.smallRadius
                topRightRadius:    isFirst ? root.bigRadius : root.smallRadius
                bottomLeftRadius:  isLast  ? root.bigRadius : root.smallRadius
                bottomRightRadius: isLast  ? root.bigRadius : root.smallRadius

                Component.onCompleted: {
                    if (root.modelDriven) return;
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

                    Loader {
                        id: rowLoader
                        active: root.modelDriven
                        Layout.fillWidth: true
                        sourceComponent: root.rowDelegate
                    }
                }

                Binding {
                    target: rowLoader.item
                    property: "modelData"
                    value: plate.modelData
                    when: rowLoader.item !== null
                }
                Binding {
                    target: rowLoader.item
                    property: "cornerTopLeft"
                    value: plate.topLeftRadius
                    when: rowLoader.item?.cornerTopLeft !== undefined
                }
                Binding {
                    target: rowLoader.item
                    property: "cornerTopRight"
                    value: plate.topRightRadius
                    when: rowLoader.item?.cornerTopRight !== undefined
                }
                Binding {
                    target: rowLoader.item
                    property: "cornerBottomLeft"
                    value: plate.bottomLeftRadius
                    when: rowLoader.item?.cornerBottomLeft !== undefined
                }
                Binding {
                    target: rowLoader.item
                    property: "cornerBottomRight"
                    value: plate.bottomRightRadius
                    when: rowLoader.item?.cornerBottomRight !== undefined
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