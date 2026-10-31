pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.modules.common
import qs.modules.common.functions
import "../modules/common/functions/lyric_gaps.js" as Gaps

Singleton {
    id: root

    readonly property MprisPlayer activePlayer: MprisController.activePlayer

    property var lyricsLines: []
    // Provider pilihan manual (dropdown di PlayerContent). Kosong = ikut
    // rantai Config.options.lyrics.providers; terisi = provider itu dicoba
    // dulu, baru jatuh ke rantai kalau gagal.
    property string preferredProvider: ""
    // Hasil probe semua provider untuk track berjalan: {ok, wordByWord,
    // duet} per nama provider — dipakai badge dropdown (per kata / per
    // baris, plus penanda baris suara kedua).
    property var providerInfo: ({})
    // The track those results belong to, so a provider change can keep them
    // and a track change cannot.
    property string providerInfoKey: ""
    property string probeKey: ""
    property real probeAt: 0
    property int activeIndex: -1
    property string status: "loading"
    property string providedBy: ""

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
    property int activeWordIndex: -1
    property real activeWordProgress: 0

    // Sentence-level sweep (0..1) across the active line, used when the
    // source only carries line timing: line start -> next line start, so
    // the sweep tracks the real song instead of guessed per-word times.
    property real activeLineProgress: 0

    // Word-level state of the background vocal of the active line: the echo
    // the source tags x-bg ("(can I?)" answering "can I get a kiss?"). It is
    // sung on its own timings, so it cannot ride the lead's index.
    property int activeBgWordIndex: -1
    property real activeBgWordProgress: 0

    // The instrumental stretches of this song as [{time, end}], worked out once
    // when the payload lands. A long enough one takes a row of the lyric list
    // of its own, so the widget counts down to the next line instead of
    // freezing on the last one sung.
    property var interludes: []
    property int activeInterludeIndex: -1
    property real activeInterludeProgress: 0

    // The same capping rules as updateActiveWords(), copied on purpose rather
    // than shared: that function is the production word path and nothing in
    // the suite exercises it (the QML tests run against a double), so pulling
    // its body out to reuse it here would move tested-by-nobody timing code
    // for no measurable gain. Change one, change both.
    function updateActiveBgWords() {
        const words = root.lyricsLines[root.activeIndex]?.bg?.words ?? []
        if (words.length === 0) {
            root.activeBgWordIndex = -1
            root.activeBgWordProgress = 0
            return
        }
        const pos = root.shiftedPos()
        let idx = -1
        for (let i = 0; i < words.length; i++) {
            if (words[i].time <= pos) idx = i
            else break
        }
        root.activeBgWordIndex = idx
        if (idx < 0) {
            root.activeBgWordProgress = 0
            return
        }
        // A background echo ends with the line, not with a next echo word, so
        // the last of them sweeps to the next line's start instead of snapping.
        const to = idx + 1 < words.length
            ? words[idx + 1].time
            : root.lyricsLines[root.activeIndex + 1]?.time ?? words[idx].time + root.maxWordSpan
        const span = Math.min(Math.max(0.001, to - words[idx].time), root.maxWordSpan)
        root.activeBgWordProgress = Math.min(1, Math.max(0, (pos - words[idx].time) / span))
    }

    function updateActiveWords() {
        const line = root.lyricsLines[root.activeIndex]
        const words = line?.words ?? []
        const pos = root.shiftedPos()
        // The sentence sweep always follows the real line span, so a source
        // with no word timings can still light the line over its own length.
        const lineEnd = root.lyricsLines[root.activeIndex + 1]?.time
        root.activeLineProgress = (line && lineEnd !== undefined && lineEnd > line.time)
            ? Math.min(1, Math.max(0, (pos - line.time) / (lineEnd - line.time)))
            : (line && pos >= line.time ? 1 : 0)
        if (!words || words.length === 0) {
            root.activeWordIndex = -1
            root.activeWordProgress = 0
            return
        }
        let idx = -1
        for (let i = 0; i < words.length; i++) {
            if (words[i].time <= pos) idx = i
            else break
        }
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
            // snap to 100% and only light up. Sweep it across the rest of the
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

    // Which break the cursor stands in, and how far through it. Asked on the
    // same shifted position as the line lookup, so the handover back to the
    // vocal happens on the tick the next line starts, not a frame apart from it.
    function updateInterlude() {
        const pos = root.shiftedPos()
        const gaps = root.interludes ?? []
        for (let i = 0; i < gaps.length; i++) {
            if (gaps[i].time <= pos && pos < gaps[i].end) {
                const span = Math.max(0.001, gaps[i].end - gaps[i].time)
                root.activeInterludeIndex = i
                root.activeInterludeProgress = Math.min(1, Math.max(0, (pos - gaps[i].time) / span))
                return
            }
        }
        root.activeInterludeIndex = -1
        root.activeInterludeProgress = 0
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
        // a large progress and the sweep looks choppy.
        interval: 50
        repeat: true
        running: root.synced
        onTriggered: {
            // Keep upstream's extrapolation base fresh, so currentPosition()
            // used by update() is never stale after a seek.
            root.basePosition = root.activePlayer?.position ?? 0
            root.baseTime = Date.now()
            const idx = root.indexAt(root.shiftedPos())
            root.activeIndex = idx
            root.updateActiveWords()
            root.updateActiveBgWords()
            root.updateInterlude()
        }
    }

    function update() {
        boundaryTimer.stop()
        if (!root.synced) return
        const idx = root.indexAt(root.currentPosition() + root.leadSeconds)
        root.activeIndex = idx
        root.updateInterlude()
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
                    // The echo of this line, on its own timings. Absent for
                    // every provider that does not mark one.
                    const bg = (line.b && String(line.b).trim()) ? {
                        text: String(line.b),
                        words: (line.bw || []).map(w => ({
                            time: parseFloat(w[0]),
                            text: String(w[1] ?? "")
                        })).filter(w => !isNaN(w.time))
                    } : null
                    lines.push({ time: t, text: txt, words, bg,
                                 align: line.a === "end" ? "end" : "start" })
                }

                if (lines.length === 0) { root.status = "not_found"; return }

                // Badge for the provider we just used comes for free from the
                // payload; no probe request needed.
                const info = Object.assign({}, root.providerInfo)
                info[payload.provider] = {
                    ok: true,
                    wordByWord: lines.some(l => l.words.length > 0),
                    duet: lines.some(l => l.align === "end"),
                    unknown: false
                }
                root.providerInfo = info

                // Worked out before the lines are published, so the list never
                // lays out a song and then has to grow rows under it.
                root.interludes = Gaps.findInterludes(lines, root.maxWordSpan)
                root.activeInterludeIndex = -1
                root.activeInterludeProgress = 0
                root.lyricsLines = lines
                root.activeIndex = -1
                root.status = "ok"
                root.resync()
            }
        }
    }

    Process {
        id: probeProc
        running: false
        stdout: SplitParser {
            onRead: data => {
                const trimmed = data.trim()
                let payload = null
                try {
                    payload = JSON.parse(trimmed)
                } catch (e) { return }
                if (payload?.ok === true && payload.results)
                    root.providerInfo = payload.results
            }
        }
    }

    // Probe provider sesuai rantai aktif (lyrics.py --probe) untuk track
    // berjalan. Hanya dipanggil saat dropdown provider dibuka; hasilnya
    // di-cache 12 jam di disk oleh lyrics.py.
    function probeProviders() {
        const title = root.activePlayer?.trackTitle ?? ""
        const artist = root.activePlayer?.trackArtist ?? ""
        if (!title || !artist) return
        const duration = Math.floor(root.activePlayer?.length ?? 0)
        const key = `${title}|${artist}|${duration}`
        if (key === root.probeKey && Date.now() - root.probeAt < 120000) return
        root.probeKey = key
        root.probeAt = Date.now()
        const chain = root.preferredProvider.length > 0
            ? `${root.preferredProvider},${Config.options.lyrics.providers}`
            : Config.options.lyrics.providers
        probeProc.running = false
        probeProc.command = [
            "python3",
            `${Directories.scriptPath}/lyrics/lyrics.py`,
            title, artist, String(duration),
            "--providers", chain,
            "--probe"
        ]
        probeProc.running = true
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
        root.interludes = []
        root.activeIndex = -1
        root.providedBy = ""
        root.activeWordIndex = -1
        root.activeWordProgress = 0
        root.activeBgWordIndex = -1
        root.activeBgWordProgress = 0
        root.activeInterludeIndex = -1
        root.activeInterludeProgress = 0
        root.activeLineProgress = 0
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
        // The badges say what each provider has for *this* track, so they only
        // go stale when the track does. Switching provider keeps them: the
        // probe that produced them is still the answer for every provider in
        // the list, and the payload that follows fills in the one line it can
        // say for itself.
        const infoKey = `${title}|${artist}|${Math.floor(duration)}`
        if (infoKey !== root.providerInfoKey) {
            root.providerInfoKey = infoKey
            root.providerInfo = ({})
        }
        lyricsProc.command = [
            "python3",
            `${Directories.scriptPath}/lyrics/lyrics.py`,
            title, artist, String(Math.floor(duration)),
            "--providers", root.preferredProvider.length > 0
                ? `${root.preferredProvider},${Config.options.lyrics.providers}`
                : Config.options.lyrics.providers
        ]
        lyricsProc.running = true
    }

    Timer {
        id: restartDebounce
        interval: 150
        onTriggered: root.restartLyrics()
    }

    onActivePlayerChanged: restartDebounce.restart()

    Connections {
        target: root.activePlayer
        function onTrackTitleChanged() { root.restartLyrics() }
        function onTrackArtistChanged() { restartDebounce.restart() }
        function onPlaybackStateChanged() { root.resync() }
    }

    Component.onCompleted: root.restartLyrics()
}