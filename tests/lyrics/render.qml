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
// The glint band itself is a ShaderEffect and an offscreen grab renders it as
// nothing; the lit tail is a plain clip, so that part does show up.
Window {
    id: win
    visible: true
    width: 420
    height: 210
    color: "#141821"

    // The suffix is the image format QImageWriter picks, so the file has to be
    // saved under its real name.
    property string outPath: "/tmp/lyrics-render.png"

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
            { text: "just ahead of the sweep", time: 6 },
            { text: "far ahead of the sweep", time: 7 },
            { text: "even further ahead", time: 8 }
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

        Lyrics {
            id: lyrics
            // A host-sized box with room around it, and the two settings the
            // media widget asks for: a window of two lines on each side and no
            // vertical cut at all.
            anchors.centerIn: parent
            width: 400
            height: 150
            clipOverflowY: -1
            lineContext: 2
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
