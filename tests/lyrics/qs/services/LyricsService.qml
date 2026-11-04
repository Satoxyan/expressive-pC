pragma Singleton
import QtQuick
import "../../../../modules/common/functions/lyric_gaps.js" as Gaps

// Test double for qs.services.LyricsService. The real service is a timer and
// Mpris machine around the same members; Lyrics only reads them, so the test
// pushes values in directly.
QtObject {
    id: root

    // The partner of the real service's maxWordSpan. Duplicated rather than
    // shared, like the real one's word rules are: if the two drift apart the
    // gap tests fail loudly instead of quietly finding no gaps at all.
    readonly property real maxWordSpan: 1.2

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
    // The instrumental breaks, worked out by the same rules the real service
    // runs over its payload.
    property var interludes: []
    property int activeInterludeIndex: -1
    property real activeInterludeProgress: 0

    // The loading overlay's tap target calls this; no test clicks it, so it
    // only has to exist.
    function restartLyrics() {}

    // Load a song: lines = [{text, time, words?, bg?}], and make one of them active.
    function load(lines, provided) {
        root.lyricsLines = lines
        root.providedBy = provided ?? ""
        root.status = "ok"
        root.activeIndex = -1
        root.interludes = Gaps.findInterludes(lines, root.maxWordSpan)
        root.activeInterludeIndex = -1
        root.activeInterludeProgress = 0
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
        // The real service never has a line and a break lit at the same time.
        root.activeInterludeIndex = -1
        root.activeInterludeProgress = 0
    }

    // Stand in an instrumental break: the line before it stays the active line
    // — that is where the cursor still is — while the dots take over the row
    // the list is centred on.
    function activateGap(index, progress) {
        root.activeInterludeIndex = index
        root.activeInterludeProgress = progress
    }
}
