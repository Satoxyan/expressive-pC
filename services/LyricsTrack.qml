pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.modules.common
import qs.modules.common.functions
import "../modules/common/functions/lyric_gaps.js" as Gaps

// The lyric of one player: the song it is standing on, how far through it the
// cursor is, and the lookup that filled it in. The media popup shows a card for
// every player at once, so this cannot live in a singleton any more — a second
// app pausing or starting used to wipe the song the first one was being shown
// with, because there was only ever one song and it followed whichever bus last
// changed state.
//
// The registry (LyricsService) makes one of these per MPRIS player and hands it
// to the widgets that draw it.
//
// An Item rather than a QtObject: this holds Timers, a Process and a Connections
// as children, and QtObject has no default property to put them in. Nothing here
// is drawn, so the item stays outside every window.
Item {
    id: root

    // The player this song belongs to. Nothing in here asks about any other.
    property MprisPlayer player: null
    // What a widget matches a player against. `dbusName` never changes for a
    // bus, `uniqueId` can; a bus without a name is still better keyed by its
    // id than by nothing.
    readonly property string key: root.player?.dbusName?.length > 0
        ? root.player.dbusName : `uid:${root.player?.uniqueId ?? 0}`

    // Whether the card of this player shows its words or only its title. Per
    // player on purpose: it used to be one setting every card read, so opening
    // the lyrics on one media card opened them on all of them. The registry
    // binds the configured value in as the starting point, and the first toggle
    // breaks that binding for the rest of this player's life.
    property bool lyricsOpen: false
    // The song the shell itself is standing on — the bar, the desktop widget,
    // the whole-screen lyric. It is the one that gets looked up without anyone
    // asking, because something is always drawing it.
    property bool foreground: false
    // Whether some card has ever been shown for this player. A bus that exists
    // but that nobody looks at is not worth a search through ten providers.
    property bool watched: false
    readonly property bool eligible: (root.player?.isPlaying ?? false)
        || root.foreground || root.watched

    property var lyricsLines: []
    // Provider pilihan manual (dropdown di PlayerContent). Kosong = ikut
    // rantai Config.options.lyrics.providers; terisi = provider itu dicoba
    // dulu, baru jatuh ke rantai kalau gagal. The choice is the user's and
    // stands for every player; the registry holds it and binds it in here.
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

    // Line window around the active line, for widgets that draw a fixed number
    // of rows instead of the word-level timeline.
    readonly property int before: 3
    readonly property int after: 3
    readonly property int total: 7
    readonly property var slots: root.buildSlots(root.activeIndex)

    function buildSlots(idx) {
        const result = []
        for (let i = 0; i < root.total; i++) {
            const lineIdx = idx - root.before + i
            if (lineIdx >= 0 && lineIdx < root.lyricsLines.length)
                result.push(root.lyricsLines[lineIdx].text || "♪")
            else
                result.push("")
        }
        return result
    }

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
    // root.player.position directly so this line lookup and update()'s
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
    // source only carries line timing: the line's own start to the instant it
    // stops being heard, so the sweep tracks the real song instead of guessed
    // per-word times — and finishes with its last character exactly where the
    // gap rules say the silence after it opens, which is where a break row
    // takes the foreground. The latin reading of a line has no timings of its
    // own and rides this, so its light and the words above it go out together.
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

    // How far through the span from `start` to `end` the cursor stands. An end
    // that is not known reaches to the end of time, so the light is simply on
    // once the start has come.
    function progressOver(start, end, pos) {
        if (end != null && end > start)
            return Math.min(1, Math.max(0, (pos - start) / (end - start)))
        return pos >= start ? 1 : 0
    }

    function updateActiveWords() {
        const line = root.lyricsLines[root.activeIndex]
        const words = line?.words ?? []
        const pos = root.shiftedPos()
        // The sentence sweep runs over the line's own length, which is where the
        // gap rules say it stops being heard: a break row must never arrive on a
        // half-swept line, or the last characters lose their glow to the dots.
        const lineEnd = root.lyricsLines[root.activeIndex + 1]?.time
        root.activeLineProgress = line
            ? root.progressOver(line.time,
                Gaps.lineSpanEnd(line, lineEnd, root.maxWordSpan), pos)
            : 0
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

    readonly property bool playing: root.player?.isPlaying ?? false
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
        if (!root.player) return
        root.player.positionChanged()
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
        // Only a song that is actually being sung is worth twenty ticks a
        // second: there is now one of these per media player instead of one for
        // the whole shell. Paused, currentPosition() stands still anyway, and a
        // seek goes through resync().
        running: root.synced && root.playing
        onTriggered: {
            // Keep upstream's extrapolation base fresh, so currentPosition()
            // used by update() is never stale after a seek.
            root.basePosition = root.player?.position ?? 0
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
            root.basePosition = root.player?.position ?? 0
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
                if (trimmed === "error")     { root.status = "error"; root.scheduleRetry(); return }

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
                                 reading: String(line.r || ""),
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
        const title = root.player?.trackTitle ?? ""
        const artist = root.player?.trackArtist ?? ""
        if (!title || !artist) return
        const duration = Math.floor(root.player?.length ?? 0)
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

    // The search is worth repeating for the same track when a provider never
    // answered: the scripts report "error" when every provider timed out.
    readonly property list<int> retryDelays: [20000, 60000, 180000]
    property int retryCount: 0

    function scheduleRetry() {
        if (root.retryCount >= root.retryDelays.length) return
        lookupRetry.interval = root.retryDelays[root.retryCount]
        root.retryCount++
        lookupRetry.restart()
    }

    Timer {
        id: retryTimer
        interval: 200
        repeat: true
        running: false
        property int attempts: 0
        onTriggered: {
            if (root.player?.trackTitle && root.player?.trackArtist) {
                retryTimer.running = false
                root.restartLyrics()
            } else if (++retryTimer.attempts > 15) {
                retryTimer.running = false
                root.status = "no_info"
            }
        }
    }

    Timer {
        id: lookupRetry
        onTriggered: root.restartLyrics(true)
    }

    // The song the payload (or the search in flight) belongs to, and the song
    // this player is on now. Two strings rather than a flag: a player can be
    // paused, un-shown, and moved on to another track before anything asks for
    // its lyric, and the answer to "do we need a search?" is then whether these
    // two still agree.
    property string lookedUp: ""
    readonly property string trackKey: root.player ? `${root.player.trackTitle ?? ""}|`
        + `${root.player.trackArtist ?? ""}|${Math.floor(root.player?.length ?? 0)}` : ""

    // Look the song up if it is not already in hand and there is somebody to
    // look it for. This is the only way a search starts on its own: the shell
    // would otherwise run a provider chain for every media bus that exists,
    // including the ones nothing is showing.
    function ensure() {
        if (!root.eligible || root.trackKey.length === 0) return
        if (root.lookedUp === root.trackKey && (root.status === "ok"
                || root.status === "loading" || root.status === "no_info")) return
        root.restartLyrics()
    }

    // A new track or a manual refresh starts a new round of retries
    function restartLyrics(isRetry) {
        if (!isRetry) root.retryCount = 0
        retryTimer.stop()
        lookupRetry.stop()
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
        root.lookedUp = root.trackKey

        const title    = root.player?.trackTitle  ?? ""
        const artist   = root.player?.trackArtist ?? ""
        const duration = root.player?.length       ?? 0

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

    // Everything that starts or stops a search for this song: its own player's
    // metadata, and this player becoming worth a search at all. Which player
    // the shell happens to be looking at is none of its business — that used to
    // be the trigger, and it is why another app's pause erased this song.
    onEligibleChanged: root.ensure()

    Connections {
        target: root.player
        function onTrackTitleChanged() { root.ensure() }
        function onTrackArtistChanged() { root.ensure() }
        function onPlaybackStateChanged() {
            root.resync()
            root.ensure()
        }
    }

    Component.onCompleted: root.ensure()
}
