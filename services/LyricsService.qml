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
    property var slots: ["", "", "", "", "", "", ""]

    readonly property int before: 2
    readonly property int after:  3
    readonly property int total:  6

    // Fixed lyric sync offset (ms). Negative = words/lines light up EARLIER,
    // positive = later. Hardcoded so it can't disturb the lyric logic.
    readonly property int lyricOffsetMs: -200

    // Player position shifted by the offset, used for both the active line
    // and the word sweep so they stay in sync with each other.
    //
    // This is a FUNCTION on purpose: Quickshell's MprisPlayer.position() is
    // computed continuously (last DBus position + real elapsed time), but a
    // QML binding on it would only re-evaluate when positionChanged fires
    // (player DBus updates, often ~1/s). Reading a cached binding makes the
    // word sweep jump in steps instead of gliding.
    function shiftedPos() {
        return Math.max(0, (root.activePlayer?.position ?? 0) - root.lyricOffsetMs / 1000.0)
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
            const span = Math.max(0.001, words[idx + 1].time - words[idx].time)
            root.activeWordProgress = Math.min(1, Math.max(0, (pos - words[idx].time) / span))
        } else {
            root.activeWordProgress = idx >= 0 ? 1 : 0
        }
    }

    Timer {
        id: syncTimer
        // 50ms so the word sweep tracks the audio smoothly even for fast
        // real word timings; at 200ms a newly active word jumps straight to
        // a large progress and the glow looks choppy.
        interval: 50
        repeat: true
        running: root.status === "ok" && root.lyricsLines.length > 0
        onTriggered: {
            const pos = root.shiftedPos()
            let idx = -1
            for (let i = 0; i < root.lyricsLines.length; i++) {
                if (root.lyricsLines[i].time <= pos) idx = i
                else break
            }
            if (idx !== root.activeIndex) {
                root.activeIndex = idx
                root.slots = root.buildSlots(idx)
            }
            root.updateActiveWords()
        }
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
        root.lyricsLines = []
        root.activeIndex = -1
        root.providedBy = ""
        root.slots = ["", "", "", "", "", "", ""]
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
    }

    Component.onCompleted: root.restartLyrics()
}