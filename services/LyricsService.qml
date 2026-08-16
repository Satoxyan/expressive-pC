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

    readonly property int before: 3
    readonly property int after:  3
    readonly property int total:  7

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

    Timer {
        id: syncTimer
        interval: 300
        repeat: true
        running: root.status === "ok" && root.lyricsLines.length > 0
        onTriggered: {
            const pos = root.activePlayer?.position ?? 0
            let idx = -1
            for (let i = 0; i < root.lyricsLines.length; i++) {
                if (root.lyricsLines[i].time <= pos) idx = i
                else break
            }
            if (idx !== root.activeIndex) {
                root.activeIndex = idx
                root.slots = root.buildSlots(idx)
            }
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

                const parts = trimmed.split("§")
                if (parts.length < 4) return
                if (parts[parts.length - 2].trim() !== "ok") return

                root.providedBy = parts[parts.length - 1]

                let lines = []
                for (let i = 0; i < parts.length - 2; i += 2) {
                    const t = parseFloat(parts[i])
                    const txt = parts[i + 1] || ""
                    if (!isNaN(t)) lines.push({ time: t, text: txt })
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