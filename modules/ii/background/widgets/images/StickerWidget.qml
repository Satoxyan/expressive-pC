pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    required property int stickerIndex
    required property string imagePath
    required property real stickerSize
    required property real stickerRotation
    required property string outlineColor
    required property real outlineWidth

    configEntryName: "stickers"
    configEntry: Config.stickers[root.stickerIndex]
    hoverEnabled: true

    property bool dropHover: false

    implicitWidth: contentItem.implicitWidth
    implicitHeight: contentItem.implicitHeight

    Connections {
        target: root
        function onReleased() {
            Config.saveStickerProps(root.stickerIndex, { x: root.x, y: root.y })
        }
        function onDragFinished() {
            if (root.configEntry)
                Config.saveStickerProps(root.stickerIndex, { placementStrategy: root.configEntry.placementStrategy })
        }
    }

    Item {
        id: contentItem
        implicitWidth: root.stickerSize
        implicitHeight: root.stickerSize
        rotation: root.stickerRotation

        Behavior on implicitWidth {
            animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
        }
        Behavior on implicitHeight {
            animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
        }

        AnimatedImage {
            id: stickerImage
            anchors.fill: parent
            source: root.imagePath !== "" ? root.imagePath : ""
            fillMode: Image.PreserveAspectFit
            cache: false
            antialiasing: true
            playing: root.imagePath !== "" && root.visible
            sourceSize.width: parent.width * 2
            sourceSize.height: parent.height * 2
            visible: root.imagePath !== ""

            layer.enabled: true
            layer.effect: DropShadow {
                horizontalOffset: 0
                verticalOffset: 0
                radius: 4
                spread: root.outlineWidth / 24 
                samples: 24
                color: root.outlineColor !== "" ? root.outlineColor : "#ffffff"
                transparentBorder: true
            }
        }

        MaterialSymbol {
            anchors.centerIn: parent
            iconSize: contentItem.implicitWidth / 3
            text: root.dropHover ? "download" : "sticker"
            fill: root.dropHover ? 1 : 0
            color: root.dropHover
                ? Appearance.colors.colPrimary
                : Appearance.colors.colOnPrimaryContainer
            visible: root.imagePath === ""
            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
        }

        DropArea {
            anchors.fill: parent
            keys: ["text/uri-list"]
            onEntered: (drag) => {
                drag.accept(Qt.CopyAction)
                root.dropHover = true
            }
            onExited: {
                root.dropHover = false
            }
            onDropped: (drop) => {
                if (drop.hasUrls && drop.urls.length > 0) {
                    var cleanPath = drop.urls[0].toString().replace(/^file:\/\//, "")
                    var ext = cleanPath.split(".").pop().toLowerCase()
                    var accepted = ["png", "svg", "webp", "gif"] 
                    if (accepted.indexOf(ext) !== -1) {
                        Config.updateSticker(root.stickerIndex, { path: cleanPath })
                    }
                }
                root.dropHover = false
            }
        }

        // Remove button (top-left), visible on hover in edit mode
        MaterialShapeWrappedMaterialSymbol {
            anchors { top: parent.top; left: parent.left; margins: 8 }
            visible: root.containsMouse && !Config.options.background.widgetsLocked
            wrappedShape: MaterialShape.Shape.Circle
            color: Appearance.colors.colError ?? Appearance.colors.colPrimary
            colSymbol: Appearance.colors.colOnError ?? Appearance.colors.colOnPrimary
            text: "close"
            iconSize: 16
            fill: 1
            padding: 6
            implicitWidth: 30
            implicitHeight: 30
            z: 2

            ButtonMouseArea {
                anchors.fill: parent
                onClicked: Config.removeSticker(root.stickerIndex)
            }
        }

        ResizeHandler {
            anchorItem: stickerImage
            hoverActive: root.containsMouse
            locked: Config.options.background.widgetsLocked
            currentWidth: root.stickerSize
            resizeMode: "diagonal"
            rotatable: true
            currentRotation: root.stickerRotation
            z: 1
            onResized: (newValue) => {
                root.liveSize = Math.max(60, newValue)
            }
            onResizeFinished: {
                if (root.liveSize > 0)
                    Config.updateSticker(root.stickerIndex, { size: root.liveSize })
                root.liveSize = -1
            }
            onRotated: (newAngle) => {
                root.widgetRotation = newAngle
            }
            onRotateFinished: {
                Config.updateSticker(root.stickerIndex, { rotation: root.widgetRotation })
            }
        }
    }
}
