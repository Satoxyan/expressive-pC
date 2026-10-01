import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Widgets
import Quickshell.Io
import qs
import qs.services
import qs.modules.common

Item {
    id: root

    property var screen: null

    readonly property var result: Collage.layout(root.width, root.height, Collage.barInsets(root.screen?.name ?? ""))
    property alias backdropSource: backdropImage.source

    Item {
        id: backdropBox
        width: 256
        height: Math.max(1, 256 * root.height / Math.max(1, root.width))
        scale: root.width / 256
        transformOrigin: Item.TopLeft

        Image {
            id: backdropImage
            anchors.fill: parent
            source: Collage.primaryImage
            sourceSize.width: 256
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: false
        }

        FastBlur {
            anchors.fill: parent
            source: backdropImage
            radius: 24
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.22)
    }

    Repeater {
        model: ScriptModel {
            values: root.result.leaves
            objectProp: "id"
        }

        delegate: ClippingRectangle {
            id: tile
            required property var modelData

            readonly property int decodeStep: 512
            property int decodeWidth: 0

            function requiredDecodeWidth() {
                const needed = Math.max(tile.modelData.w, tile.modelData.h * 2.4)
                return Math.ceil(needed / tile.decodeStep) * tile.decodeStep
            }

            function growDecode() {
                if (Collage.dragging) return
                const needed = tile.requiredDecodeWidth()
                if (needed > tile.decodeWidth) tile.decodeWidth = needed
            }

            onModelDataChanged: tile.growDecode()
            Component.onCompleted: tile.growDecode()

            x: modelData.x
            y: modelData.y
            width: modelData.w
            height: modelData.h
            radius: Collage.radius
            color: Qt.rgba(0, 0, 0, 0.3)

            Behavior on x { enabled: !Collage.dragging; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on y { enabled: !Collage.dragging; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on width { enabled: !Collage.dragging; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on height { enabled: !Collage.dragging; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

            Image {
                anchors.fill: parent
                source: tile.decodeWidth > 0 ? tile.modelData.src : ""
                sourceSize.width: tile.decodeWidth
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
            }
        }
    }
}
