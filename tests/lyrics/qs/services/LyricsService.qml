pragma Singleton
import QtQuick

// Test double for qs.services.LyricsService. The real service is a timer and
// Mpris machine around the same members; Lyrics only reads them, so the test
// pushes values in directly.
QtObject {
    id: root

    property var lyricsLines: []
    property int activeIndex: -1
    property string status: "ok"
    property string providedBy: ""
    property int activeWordIndex: -1
    property real activeWordProgress: 0
    property real activeLineProgress: 0
    // The line being sung can have an echo answering it, sung on its own
    // timings, so it sweeps on its own clock.
    property int activeBgWordIndex: -1
    property real activeBgWordProgress: 0

    // The loading overlay's tap target calls this; no test clicks it, so it
    // only has to exist.
    function restartLyrics() {}

    // Load a song: lines = [{text, time, words?, bg?}], and make one of them active.
    function load(lines, provided) {
        root.lyricsLines = lines
        root.providedBy = provided ?? ""
        root.status = "ok"
        root.activeIndex = -1
        root.activeBgWordIndex = -1
        root.activeBgWordProgress = 0
    }

    function activate(index) {
        root.activeIndex = index
        const words = root.lyricsLines[index]?.words ?? []
        root.activeWordIndex = words.length > 0 ? 0 : -1
        root.activeWordProgress = 0
        root.activeLineProgress = 0
        const bgWords = root.lyricsLines[index]?.bg?.words ?? []
        root.activeBgWordIndex = bgWords.length > 0 ? 0 : -1
        root.activeBgWordProgress = 0
    }
}
