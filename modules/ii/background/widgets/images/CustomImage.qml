pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "customImages"
    configEntry: Config.options.background.widgets.customImages[root.imageIndex]
    hoverEnabled: true

    required property int imageIndex
    required property string imagePath
    required property string imageShape
    required property real imageSize

    property bool dropHover: false
    property real liveSize: -1 // during resize gesture, before persisting
    readonly property real effectiveSize: liveSize > 0 ? liveSize : imageSize

    readonly property var shapeList: [
        "Circle", "Square", "Slanted", "Arch", "Arrow", "SemiCircle", "Oval", "Pill",
        "Triangle", "Diamond", "ClamShell", "Pentagon", "Gem", "Sunny", "VerySunny",
        "Cookie4Sided", "Cookie6Sided", "Cookie7Sided", "Cookie9Sided", "Cookie12Sided",
        "Ghostish", "Clover4Leaf", "Clover8Leaf", "Burst", "SoftBurst", "Flower",
        "Puffy", "PuffyDiamond", "PixelCircle", "Bun", "Heart"
    ]

    function cycleShape() {
        const i = root.shapeList.indexOf(root.imageShape)
        const next = root.shapeList[(i + 1) % root.shapeList.length]
        Config.updateCustomImage(root.imageIndex, { shape: next })
    }

    // Base class writes configEntry.x/y in-memory; persist without replacing
    // the array (a full array replace here would rebuild this widget mid-drop)
    Connections {
        target: root
        function onReleased() {
            Config.saveCustomImageProps(root.imageIndex, { x: root.x, y: root.y })
        }
        function onDragFinished() {
            Config.saveCustomImageProps(root.imageIndex, { placementStrategy: root.configEntry.placementStrategy })
        }
        function onClicked(mouse) {
            // Only open the picker in edit mode (widgets unlocked / draggable)
            if (mouse.button === Qt.LeftButton && !Config.options.background.widgetsLocked)
                FilePicker.pickImage(path => Config.updateCustomImage(root.imageIndex, { path }))
        }
    }

    implicitWidth: contentItem.implicitWidth
    implicitHeight: contentItem.implicitHeight

    function getShape(name) {
        switch (name) {
            case "Circle":        return MaterialShape.Shape.Circle
            case "Square":        return MaterialShape.Shape.Square
            case "Slanted":       return MaterialShape.Shape.Slanted
            case "Arch":          return MaterialShape.Shape.Arch
            case "Fan":           return MaterialShape.Shape.Fan
            case "Arrow":         return MaterialShape.Shape.Arrow
            case "SemiCircle":    return MaterialShape.Shape.SemiCircle
            case "Oval":          return MaterialShape.Shape.Oval
            case "Pill":          return MaterialShape.Shape.Pill
            case "Triangle":      return MaterialShape.Shape.Triangle
            case "Diamond":       return MaterialShape.Shape.Diamond
            case "ClamShell":     return MaterialShape.Shape.ClamShell
            case "Pentagon":      return MaterialShape.Shape.Pentagon
            case "Gem":           return MaterialShape.Shape.Gem
            case "Sunny":         return MaterialShape.Shape.Sunny
            case "VerySunny":     return MaterialShape.Shape.VerySunny
            case "Cookie4Sided":  return MaterialShape.Shape.Cookie4Sided
            case "Cookie6Sided":  return MaterialShape.Shape.Cookie6Sided
            case "Cookie7Sided":  return MaterialShape.Shape.Cookie7Sided
            case "Cookie9Sided":  return MaterialShape.Shape.Cookie9Sided
            case "Cookie12Sided": return MaterialShape.Shape.Cookie12Sided
            case "Ghostish":      return MaterialShape.Shape.Ghostish
            case "Clover4Leaf":   return MaterialShape.Shape.Clover4Leaf
            case "Clover8Leaf":   return MaterialShape.Shape.Clover8Leaf
            case "Burst":         return MaterialShape.Shape.Burst
            case "SoftBurst":     return MaterialShape.Shape.SoftBurst
            case "Boom":          return MaterialShape.Shape.Boom
            case "SoftBoom":      return MaterialShape.Shape.SoftBoom
            case "Flower":        return MaterialShape.Shape.Flower
            case "Puffy":         return MaterialShape.Shape.Puffy
            case "PuffyDiamond":  return MaterialShape.Shape.PuffyDiamond
            case "PixelCircle":   return MaterialShape.Shape.PixelCircle
            case "PixelTriangle": return MaterialShape.Shape.PixelTriangle
            case "Bun":           return MaterialShape.Shape.Bun
            case "Heart":         return MaterialShape.Shape.Heart
            default:              return MaterialShape.Shape.Cookie4Sided
        }
    }

    Item {
        id: contentItem
        implicitWidth: root.effectiveSize
        implicitHeight: root.effectiveSize

        Behavior on implicitWidth {
            animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
        }
        Behavior on implicitHeight {
            animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
        }

        MaterialShape {
            id: shadowShape
            anchors.fill: parent
            color: Appearance.colors.colPrimaryContainer
            shape: getShape(root.imageShape)
            visible: false
        }

        StyledDropShadow {
            target: shadowShape
            z: -1
        }

        MaterialShape {
            id: imageShape
            anchors.fill: parent
            z: 0
            color: Appearance.colors.colPrimaryContainer
            shape: getShape(root.imageShape)

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: MaterialShape {
                    width: imageShape.width
                    height: imageShape.height
                    shape: getShape(root.imageShape)
                }
            }

            StyledImage {
                anchors.fill: parent
                source: root.imagePath !== "" ? root.imagePath : ""
                fillMode: Image.PreserveAspectCrop
                cache: false
                antialiasing: true
                sourceSize.width: parent.width
                sourceSize.height: parent.height
                visible: root.imagePath !== ""
            }

            // Placeholder + hover hint
            MaterialSymbol {
                anchors.centerIn: parent
                iconSize: contentItem.implicitWidth / 3
                text: root.dropHover ? "download" : "image"
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
                        var accepted = ["png","jpg","jpeg","webp","avif","bmp","gif","tiff","tif"]
                        if (accepted.indexOf(ext) !== -1) {
                            Config.updateCustomImage(root.imageIndex, { path: cleanPath })
                        }
                    }
                    root.dropHover = false
                }
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
                onClicked: Config.removeCustomImage(root.imageIndex)
            }
        }

        // Shape cycle button (top-right), visible on hover in edit mode
        MaterialShapeWrappedMaterialSymbol {
            anchors { top: parent.top; right: parent.right; margins: 8 }
            visible: root.containsMouse && !Config.options.background.widgetsLocked
            wrappedShape: MaterialShape.Shape.Circle
            color: Appearance.colors.colPrimary
            colSymbol: Appearance.colors.colOnPrimary
            text: "category"
            iconSize: 16
            fill: 1
            padding: 6
            implicitWidth: 30
            implicitHeight: 30
            z: 2

            Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }

            ButtonMouseArea {
                anchors.fill: parent
                onClicked: root.cycleShape()
            }
        }

        ResizeHandler{
            anchorItem: imageShape
            hoverActive: root.containsMouse
            locked: Config.options.background.widgetsLocked
            currentWidth: root.effectiveSize
            resizeMode: "diagonal"
            z: 1
            onResized: (newValue) => {
                root.liveSize = Math.max(80, newValue)
            }
            onResizeFinished: {
                // resizeFinished also fires on plain clicks (no drag) where liveSize
                // was never set; don't persist the sentinel value
                if (root.liveSize > 0)
                    Config.updateCustomImage(root.imageIndex, { size: root.liveSize })
                root.liveSize = -1
            }
        }
    }
}
