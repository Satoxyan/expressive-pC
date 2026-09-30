pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Hyprland
import qs
import qs.services
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
    property real liveSize: -1
    property real currentWidgetRotation: root.stickerRotation
    property bool coveredByWindow: false

    Connections {
        target: HyprlandData
        function onWindowListChanged() { root.updateCovered() }
        function onActiveWorkspaceChanged() { root.updateCovered() }
    }
    Component.onCompleted: {
        updateCovered();
        if (root.imagePath !== "") _gifDelay.start();
    }

    property bool _gifStarted: false

    Timer {
        id: _gifDelay
        interval: 100
        onTriggered: root._gifStarted = true
    }

    function updateCovered() {
        const wl = HyprlandData.windowList;
        if (!wl || wl.length === 0) { coveredByWindow = false; return; }
        const aw = HyprlandData.activeWorkspace;
        if (!aw) { coveredByWindow = false; return; }
        for (let i = 0; i < wl.length; i++) {
            const win = wl[i];
            if (win.workspace?.id !== aw.id) continue;
            const isMax = (win.maximized || win.wayland?.maximized);
            const isFS = (win.fullscreen || win.wayland?.fullscreen);
            if (win.floating === false || isMax || isFS) { coveredByWindow = true; return; }
        }
        coveredByWindow = false;
    }

    onDoubleClicked: (mouse) => {
        if (mouse.button !== Qt.LeftButton) return
        root.widgetRotation = 0
        Config.options.background.widgets.sticker.rotation = 0
    }

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
        function onClicked(mouse) {
            // Only open the picker in edit mode (widgets unlocked / draggable)
            if (mouse.button === Qt.LeftButton && !Config.options.background.widgetsLocked)
                FilePicker.pickImage(path => Config.updateSticker(root.stickerIndex, { path }))
        }
    }

    Item {
        id: contentItem
        implicitWidth: root.liveSize > 0 ? root.liveSize : root.stickerSize
        implicitHeight: root.liveSize > 0 ? root.liveSize : root.stickerSize
        rotation: root.currentWidgetRotation

        Behavior on implicitWidth {
            enabled: root.liveSize < 0
            animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
        }
        Behavior on implicitHeight {
            enabled: root.liveSize < 0
            animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
        }

        AnimatedImage {
            id: stickerImage
            anchors.fill: parent
            source: root.imagePath !== "" ? root.imagePath : ""
            fillMode: Image.PreserveAspectFit
            cache: false
            antialiasing: true
            playing: root._gifStarted && root.imagePath !== "" && root.visible && !root.coveredByWindow
            // sourceSize dibekukan ke nilai tersimpan, BUKAN ukuran live saat drag.
            // Tiap perubahan sourceSize membuat Qt baca + decode ulang file di GUI thread
            // (terukur: 2,4 CPU-detik per 3 detik drag, file dibaca 651 MiB) => patah-patah.
            // Imbas: preview sedikit blur waktu membesar, tajam lagi begitu resize selesai.
            sourceSize.width: root.stickerSize * 2
            sourceSize.height: root.stickerSize * 2
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

        // Remove button (top-left area), positioned inward to stay in hover area
        MaterialShapeWrappedMaterialSymbol {
            anchors {
                top: parent.top
                left: parent.left
                topMargin: parent.height * 0.15
                leftMargin: parent.width * 0.15
            }
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
                root.currentWidgetRotation = newAngle
            }
            onRotateFinished: {
                Config.updateSticker(root.stickerIndex, { rotation: root.currentWidgetRotation })
            }
        }
    }
}
