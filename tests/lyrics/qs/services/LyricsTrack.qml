import QtQuick
import "../../../../modules/common/functions/lyric_gaps.js" as Gaps

// Test double for qs.services.LyricsTrack: the lyric state of one player. The
// real thing is a timer and Mpris machine around the same members; the widget
// only reads them, so a test loads a song into a track and pushes the values it
// wants by hand. The service double is one of these, standing for the track of
// whichever player the shell is standing on.
QtObject {
    id: track

    // The partner of the real service's maxWordSpan. Duplicated rather than
    // shared, like the real one's word rules are: if the two drift apart the
    // gap tests fail loudly instead of quietly finding no gaps at all.
    readonly property real maxWordSpan: 1.2

    // Whether the host shows this song's words or only its title line. A card
    // of its own per player, so a per-player flag lives on the song, not on a
    // setting every card reads.
    property bool lyricsOpen: false

    property var lyricsLines: []
    // The provider the user picked for every player. The real track is handed
    // this by the registry; a test never changes it, and the widget does not
    // read it, but the type owns the name either way.
    property string preferredProvider: ""
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
        track.lyricsLines = lines
        track.providedBy = provided ?? ""
        track.status = "ok"
        track.activeIndex = -1
        track.interludes = Gaps.findInterludes(lines, track.maxWordSpan)
        track.activeInterludeIndex = -1
        track.activeInterludeProgress = 0
    }

    function activate(index) {
        track.activeIndex = index
        const words = track.lyricsLines[index]?.words ?? []
        track.activeWordIndex = words.length > 0 ? 0 : -1
        track.activeWordProgress = 0
        track.activeLineProgress = 0
        const bgWords = track.lyricsLines[index]?.bg?.words ?? []
        track.activeBgWordIndex = bgWords.length > 0 ? 0 : -1
        track.activeBgWordProgress = 0
        // The real service never has a line and a break lit at the same time.
        track.activeInterludeIndex = -1
        track.activeInterludeProgress = 0
    }

    // Stand in an instrumental break: the line before it stays the active line
    // — that is where the cursor still is — while the dots take over the row
    // the list is centred on.
    function activateGap(index, progress) {
        track.activeInterludeIndex = index
        track.activeInterludeProgress = progress
    }
}
