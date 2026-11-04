pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import qs.modules.common

// Which song a widget draws. The state of a song — its lines, where the cursor
// stands in them, which provider answered, whether its card is open — belongs to
// the player singing it and lives in a LyricsTrack of its own, one per MPRIS
// bus. This file keeps those, points at the one the shell is standing on, and
// answers for the handful of hosts that only ever show that one.
//
// It used to hold the single song itself, which is why two players at once
// showed one lyric and why pausing an app that was merely *not* being looked at
// wiped the lyric of the one that was.
Singleton {
    id: root

    readonly property MprisPlayer activePlayer: MprisController.activePlayer

    // Provider pilihan manual (dropdown di kartu media). Kosong = ikut rantai
    // Config.options.lyrics.providers. One choice for every player — it is what
    // the user asked for, not what a given track happens to carry — bound into
    // each track below.
    property string preferredProvider: ""

    // Only here so that trackFor() has something to depend on: a song appears or
    // disappears with its bus, and the count is the one signal that says so. A
    // binding that asks for a player's track therefore asks again after the list
    // of players changed, which is what it has to do.
    readonly property int trackCount: tracks.count

    // The song the shell is standing on, and the answer for every host that
    // shows one player instead of a card per player.
    readonly property var active: root.trackFor(root.activePlayer)

    function playerKey(player) {
        if (!player) return ""
        const name = player.dbusName ?? ""
        return name.length > 0 ? name : `uid:${player.uniqueId ?? 0}`
    }

    // The tracks are few — one per media bus, and the duplicates are already
    // filtered out by MprisController — so they are looked for by asking each
    // one whether it is the player in question rather than by keeping a map
    // that has to be corrected every time a bus comes and goes.
    function trackFor(player) {
        const _ = root.trackCount
        const key = root.playerKey(player)
        if (key.length === 0) return null
        for (let i = 0; i < tracks.count; i++) {
            const t = tracks.objectAt(i)
            if (t?.key === key) return t
        }
        return null
    }

    // A host about to show a player's card asks here, so a paused player whose
    // lyrics someone opened still gets a search, while a bus that nothing ever
    // displays costs none.
    function ensureFor(player) {
        const t = root.trackFor(player)
        if (t) t.watched = true
        return t
    }

    Instantiator {
        id: tracks
        // `.slice()` because `players` is a list property, not an array: handing
        // the list itself to ScriptModel is an assignment it refuses, and the
        // registry would silently end up with no track for anybody.
        model: ScriptModel {
            values: MprisController.players.slice()
            objectProp: "dbusName"
        }
        delegate: LyricsTrack {
            id: track
            required property var modelData

            player: modelData
            // The song the shell draws is the one looked up without being asked.
            foreground: root.active === track
            preferredProvider: root.preferredProvider
            // A card starts on its title line and keeps its own flag from
            // there. Nothing reads or writes Config for it: what a card was
            // doing before a restart is not worth restoring, and a stored
            // answer used to reopen every card on every start.
        }
    }

    // ── what the shell is standing on ──────────────────────────────────────
    // Read straight off the active track, for the bar, the desktop widgets, the
    // whole-screen lyric and the provider dropdown's label. A widget that draws
    // a particular player asks for its track instead and never comes through
    // here.
    readonly property var lyricsLines: root.active?.lyricsLines ?? []
    readonly property int activeIndex: root.active?.activeIndex ?? -1
    readonly property var slots: root.active?.slots ?? []
    readonly property int before: 3
    readonly property string providedBy: root.active?.providedBy ?? ""
    readonly property bool synced: root.active?.synced ?? false
    readonly property bool playing: root.activePlayer?.isPlaying ?? false
    readonly property var providerInfo: root.active?.providerInfo ?? ({})
    // No track at all is not a song being looked up: it is nothing playing, so
    // the widget says so the way it did when a search came back empty.
    readonly property string status: root.active?.status
        ?? (root.playing ? "loading" : "no_info")

    function resync() { root.active?.resync() }
    function restartLyrics() { root.active?.restartLyrics() }
    function probeProviders() { root.active?.probeProviders() }
}
