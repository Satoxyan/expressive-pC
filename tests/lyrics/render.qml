import QtQuick
import QtQuick.Window
import qs.modules.common.widgets
import qs.services

// Visual smoke render (no test assertions): paints the karaoke widget
// mid-sweep so the word states can be inspected as a PNG.
//
//   QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qml -I tests/lyrics \
//     tests/lyrics/render.qml
//
// Both kinds of host are painted side by side, because the two settings that
// differ between them — which edge the words go to, and how big the break dots
// are — are only judgeable against each other.
//
// The glint band itself is a ShaderEffect and an offscreen grab renders it as
// nothing; the lit tail is a plain clip, so that part does show up.
Window {
    id: win
    visible: true
    width: 840
    height: 210
    color: "#141821"

    // The suffix is the image format QImageWriter picks, so the file has to be
    // saved under its real name.
    property string outPath: "/tmp/lyrics-render.png"
    property string breakPath: "/tmp/lyrics-render-break.png"

    Rectangle {
        anchors.fill: parent
        color: "#141821"
    }

    Component.onCompleted: {
        LyricsService.load([
            { text: "far behind the sweep", time: 0 },
            { text: "just behind the sweep", time: 1, bg: { text: "(answering back)", words: [] } },
            { text: "the line being sung beautifully right now with words in it", time: 2,
              words: "the line being sung beautifully right now with words in it".split(" ")
                  .map((w, i) => ({ text: w, time: 2 + i * 0.3 })),
              bg: { text: "(ooh, singing along)",
                    words: [{ text: "(ooh,", time: 3 }, { text: "singing", time: 3.4 },
                            { text: "along)", time: 3.8 }] } },
            { text: "just ahead of the sweep", time: 12 },
            { text: "far ahead of the sweep", time: 13 },
            { text: "even further ahead", time: 14 }
        ], "musixmatch")
        LyricsService.activate(2)
        LyricsService.activeWordIndex = 4
        LyricsService.activeWordProgress = 0.5
        // The echo is sung after the line it answers, so its own clock is well
        // behind the lead's at this moment.
        LyricsService.activeBgWordIndex = 1
        LyricsService.activeBgWordProgress = 0.4
        timer.restart()
    }

    Timer {
        id: timer
        interval: 900
        onTriggered: shot.grabToImage(function(result) {
            console.log("saved=" + result.saveToFile(win.outPath) + " to=" + win.outPath)
            // The same song a moment later, standing in the instrumental break
            // that opens when line 2 has finished being swept.
            LyricsService.activeWordIndex = 10
            LyricsService.activeWordProgress = 1
            LyricsService.activeBgWordIndex = 2
            LyricsService.activeBgWordProgress = 1
            LyricsService.activateGap(0, 0.55)
            breakTimer.restart()
        }, function(result) {
            console.log("grab failed: " + result.errorString)
            Qt.exit(1)
        })
    }

    Timer {
        id: breakTimer
        interval: 900
        onTriggered: shot.grabToImage(function(result) {
            console.log("saved=" + result.saveToFile(win.breakPath) + " to=" + win.breakPath)
            Qt.quit()
        }, function(result) {
            console.log("grab failed: " + result.errorString)
            Qt.exit(1)
        })
    }

    Rectangle {
        id: shot
        anchors.fill: parent
        color: "#141821"

        Repeater {
            // The media controls on the left, the sidebar / dashboard / media
            // widget on the right.
            model: [
                { name: "left",   align: Text.AlignLeft,   dots: 0.75 },
                { name: "centre", align: Text.AlignHCenter, dots: 1.0 }
            ]

            delegate: Lyrics {
                required property var modelData
                required property int index

                x: 20 + index * 420
                anchors.verticalCenter: parent.verticalCenter
                width: 400
                height: 150
                clipOverflowY: -1
                lineContext: 2
                textAlignment: modelData.align
                dotScale: modelData.dots
                activeColor: "#7ce0d8"
                textColor: "#d7dbe4"
                dimColor: "#6a7184"
                // The lit words sit behind a glow layer, and a layer is a
                // ShaderEffect: an offscreen grab renders it as nothing, so with
                // the glow on the whole active line disappears from the image.
                glowEnabled: false
            }
        }
    }
}
