pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root

    readonly property MprisPlayer activePlayer: MprisController.activePlayer

    property var lyricsLines: []
    property int activeIndex: -1
    property string status: "loading"
    property string providedBy: ""
    property var slots: ["", "", "", "", ""]

    // Slot index (0..total-1) where the "Lyrics provided by …" note sits,
    // right after the last lyric line once it scrolls into the window.
    // -1 = not visible yet.
    property int noteSlot: -1

    readonly property int before: 2
    readonly property int after:  2
    readonly property int total:  5

    // Fixed lyric sync offset (ms). Negative = words/lines light up EARLIER,
    // positive = later. Hardcoded so it can't disturb the lyric logic.
    readonly property int lyricOffsetMs: -200

    // Longest a word may take to fill (s). Provider word timings can place a
    // big pause after a short word (e.g. musixmatch richsync "The" → 1.5s);
    // capping the fill span stops the highlight from crawling through pauses.
    readonly property real maxWordSpan: 1.2

    // Player position shifted by the offset, used for both the active line
    // and the word sweep so they stay in sync with each other.
    //
    // Derived from upstream's currentPosition() instead of reading
    // activePlayer.position directly so this line lookup and update()'s
    // indexAt(currentPosition() + leadSeconds) are bit-identical — any gap
    // between the two would make activeIndex flip-flop at every line
    // boundary. A QML binding on position() would also only re-evaluate when
    // positionChanged fires (often ~1/s) and make the word sweep step.
    // syncTimer refreshes basePosition each tick, so the extrapolation never
    // goes stale after a seek.
    function shiftedPos() {
        return Math.max(0, root.currentPosition() - root.lyricOffsetMs / 1000.0)
    }

    // Word-level karaoke state for the active line
    property var activeLineWords: []
    property int activeWordIndex: -1
    property real activeWordProgress: 0

    function buildSlots(idx) {
        let result = []
        for (let i = 0; i < root.total; i++) {
            let lineIdx = idx - root.before + i
            if (lineIdx >= 0 && lineIdx < root.lyricsLines.length)
                result.push(root.lyricsLines[lineIdx].text || "♪")
            else
                result.push("")
        }
        // Note sits one slot after the last lyric line once that line is
        // inside the window, and scrolls up with it toward the end.
        const lastSlot = root.lyricsLines.length - 1 - idx + root.before
        root.noteSlot = (root.lyricsLines.length > 0 && lastSlot >= 0 && lastSlot <= root.total - 2)
            ? lastSlot + 1 : -1
        return result
    }

    function updateActiveWords() {
        const line = root.lyricsLines[root.activeIndex]
        const words = line?.words ?? []
        if (!words || words.length === 0) {
            root.activeLineWords = []
            root.activeWordIndex = -1
            root.activeWordProgress = 0
            return
        }
        const pos = root.shiftedPos()
        let idx = -1
        for (let i = 0; i < words.length; i++) {
            if (words[i].time <= pos) idx = i
            else break
        }
        root.activeLineWords = words
        root.activeWordIndex = idx
        if (idx >= 0 && idx + 1 < words.length) {
            // Fill the word from its start toward the next word's start, but
            // cap the span so a long gap (some providers put a big pause after
            // a short word) never makes the highlight crawl. Reaching 100%
            // early keeps the sweep stuck on the last word actually sung
            // instead of stretching it out across the pause.
            const span = Math.min(
                Math.max(0.001, words[idx + 1].time - words[idx].time),
                root.maxWordSpan
            )
            root.activeWordProgress = Math.min(1, Math.max(0, (pos - words[idx].time) / span))
        } else if (idx >= 0) {
            // Last word of the line: there is no next word, so it used to
            // snap to 100% and only glow. Sweep it across the rest of the
            // line up to the next line's start instead, still capped so a
            // long pause before the next line can't make it crawl.
            const lineEnd = root.lyricsLines[root.activeIndex + 1]?.time
            if (lineEnd !== undefined) {
                const span = Math.min(
                    Math.max(0.001, lineEnd - words[idx].time),
                    root.maxWordSpan
                )
                root.activeWordProgress = Math.min(1, Math.max(0, (pos - words[idx].time) / span))
            } else {
                root.activeWordProgress = 1
            }
        } else {
            root.activeWordProgress = 0
        }
    }

    readonly property bool playing: root.activePlayer?.isPlaying ?? false
    readonly property bool synced: root.status === "ok" && root.lyricsLines.length > 0
    // Derived from lyricOffsetMs: update()'s line lookup and syncTimer's word
    // sweep must use the exact same offset or activeIndex flips back and forth
    // for a tick at every line boundary.
    readonly property real leadSeconds: -root.lyricOffsetMs / 1000

    property real basePosition: 0
    property real baseTime: Date.now()

    function currentPosition() {
        return root.playing ? root.basePosition + (Date.now() - root.baseTime) / 1000 : root.basePosition
    }

    function resync() {
        if (!root.activePlayer) return
        root.activePlayer.positionChanged()
        readPositionTimer.restart()
    }

    function indexAt(pos) {
        const lines = root.lyricsLines
        let low = 0
        let high = lines.length - 1
        let result = -1
        while (low <= high) {
            const mid = (low + high) >> 1
            if (lines[mid].time <= pos) {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }

    Timer {
        id: syncTimer
        // 50ms so the word sweep tracks the audio smoothly even for fast
        // real word timings; at 200ms a newly active word jumps straight to
        // a large progress and the glow looks choppy.
        interval: 50
        repeat: true
        running: root.synced
        onTriggered: {
            // Keep upstream's extrapolation base fresh, so currentPosition()
            // used by update() is never stale after a seek.
            root.basePosition = root.activePlayer?.position ?? 0
            root.baseTime = Date.now()
            const idx = root.indexAt(root.shiftedPos())
            if (idx !== root.activeIndex) {
                root.activeIndex = idx
                root.slots = root.buildSlots(idx)
            }
            root.updateActiveWords()
        }
    }

    function update() {
        boundaryTimer.stop()
        if (!root.synced) return
        const idx = root.indexAt(root.currentPosition() + root.leadSeconds)
        if (idx !== root.activeIndex) {
            root.activeIndex = idx
            root.slots = root.buildSlots(idx)
        }
        const next = root.lyricsLines[idx + 1]
        if (!root.playing || !next) return
        const delay = (next.time - root.leadSeconds - root.currentPosition()) * 1000
        boundaryTimer.interval = Math.max(1, Math.ceil(delay))
        boundaryTimer.start()
    }

    Timer {
        id: readPositionTimer
        interval: 80
        onTriggered: {
            root.basePosition = root.activePlayer?.position ?? 0
            root.baseTime = Date.now()
            root.update()
        }
    }

    Timer {
        id: boundaryTimer
        onTriggered: root.update()
    }

    Timer {
        id: driftTimer
        interval: 4000
        repeat: true
        running: root.synced && root.playing
        onTriggered: root.resync()
    }

    Process {
        id: lyricsProc
        running: false
        stdout: SplitParser {
            onRead: data => {
                const trimmed = data.trim()
                if (trimmed === "not_found") { root.status = "not_found"; return }
                if (trimmed === "no_info")   { root.status = "no_info";   return }

                let payload = null
                try {
                    payload = JSON.parse(trimmed)
                } catch (e) {}
                if (!payload || payload.ok !== true || !Array.isArray(payload.lines)) return

                root.providedBy = payload.provider || ""

                let lines = []
                for (const line of payload.lines) {
                    const t = parseFloat(line.t)
                    const txt = line.x || ""
                    if (isNaN(t) || !txt) continue
                    const words = (line.w || []).map(w => ({
                        time: parseFloat(w[0]),
                        text: String(w[1] ?? "")
                    })).filter(w => !isNaN(w.time))
                    lines.push({ time: t, text: txt, words })
                }

                if (lines.length === 0) { root.status = "not_found"; return }

                root.lyricsLines = lines
                root.activeIndex = -1
                root.slots = root.buildSlots(-1)
                root.status = "ok"
                root.resync()
            }
        }
    }

    Timer {
        id: retryTimer
        interval: 200
        repeat: true
        running: false
        property int attempts: 0
        onTriggered: {
            const ap = root.activePlayer
            if (ap?.trackTitle && ap?.trackArtist) {
                retryTimer.running = false
                root.restartLyrics()
            } else if (++retryTimer.attempts > 15) {
                retryTimer.running = false
                root.status = "no_info"
            }
        }
    }

    function restartLyrics() {
        lyricsProc.running = false
        boundaryTimer.stop()
        root.lyricsLines = []
        root.activeIndex = -1
        root.providedBy = ""
        root.slots = ["", "", "", "", ""]
        root.noteSlot = -1
        root.activeLineWords = []
        root.activeWordIndex = -1
        root.activeWordProgress = 0
        root.status = "loading"

        const title    = root.activePlayer?.trackTitle  ?? ""
        const artist   = root.activePlayer?.trackArtist ?? ""
        const duration = root.activePlayer?.length       ?? 0

        if (!title || !artist) {
            // Metadata may arrive in pieces (title first, artist later) or the
            // player may not be the active one yet. Wait briefly and retry.
            retryTimer.attempts = 0
            retryTimer.running = true
            return
        }

        retryTimer.running = false
        lyricsProc.command = [
            "python3",
            `${Directories.scriptPath}/lyrics/lyrics.py`,
            title, artist, String(Math.floor(duration)),
            "--providers", Config.options.lyrics.providers
        ]
        lyricsProc.running = true
    }

    onActivePlayerChanged: root.restartLyrics()

    Connections {
        target: root.activePlayer
        function onTrackTitleChanged() { root.restartLyrics() }
        function onTrackArtistChanged() { root.restartLyrics() }
        function onPlaybackStateChanged() { root.resync() }
    }

    Component.onCompleted: root.restartLyrics()
}