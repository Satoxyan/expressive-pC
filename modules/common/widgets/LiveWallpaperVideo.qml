import QtQuick
import QtMultimedia

Item {
    id: root

    property url source: ""
    property int fillMode: VideoOutput.PreserveAspectCrop

    readonly property bool videoReady: player.hasVideo
    readonly property bool videoFailed: player.error !== MediaPlayer.NoError

    MediaPlayer {
        id: player
        source: root.source
        videoOutput: videoOutputItem
        audioOutput: AudioOutput {
            muted: true
        }
        loops: MediaPlayer.Infinite
        autoPlay: true
    }

    VideoOutput {
        id: videoOutputItem
        anchors.fill: parent
        fillMode: root.fillMode
    }
}