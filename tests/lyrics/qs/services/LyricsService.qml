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

oder    // The loading overlay's tap target calls this; no test clicks it, so it
    // only has to exist.
    function restartLyrics() {}

    // Load a song: lines = [{text, time, words?}], and make one of them active.
    function load(lines, provided) {
        root.lyricsLines = lines
        root.providedBy = provided ?? ""
        root.status = "ok"
        root.activeIndex = -1
    }

    function activate(index) {
        root.activeIndex = index
        const words = root.lyricsLines[index]?.words ?? []
        root.activeWordIndex = words.length > 0 ? 0 : -1
        root.activeWordProgress = 0
        root.activeLineProgress = 0
    }
}
