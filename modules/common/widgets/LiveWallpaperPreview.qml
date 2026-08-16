import QtQuick
import Qt5Compat.GraphicalEffects
import qs.modules.common.widgets

Item {
    id: root

    required property url source
    property url thumbnail: ""
    property bool active: true
    property real radius: 0

    readonly property bool isVideo: /\.(mp4|webm|mkv|avi|mov)$/i.test(root.source)
    readonly property bool videoShown: videoLoader.active && videoLoader.item && videoLoader.item.videoReady && !videoLoader.item.videoFailed

    layer.enabled: true
    layer.effect: OpacityMask {
        maskSource: Rectangle {
            width: root.width
            height: root.height
            radius: root.radius
        }
    }

    StyledImage {
        id: staticPreview
        anchors.fill: parent
        source: root.isVideo ? root.thumbnail : root.source
        sourceSize.width: parent.width * 2
        sourceSize.height: parent.height * 2
        fillMode: Image.PreserveAspectCrop
        cache: false
        visible: !root.videoShown
    }

    Loader {
        id: videoLoader
        anchors.fill: parent
        active: root.isVideo && root.active && root.visible
        sourceComponent: LiveWallpaperVideo {
            anchors.fill: parent
            source: root.source
        }
    }
}