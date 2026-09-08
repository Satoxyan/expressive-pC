pragma Singleton
import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// Owns "Auto" genre-follow: watching for track-artist changes, looking up
// genre tags, and switching the EQ preset to match. This used to live
// inside EqualizerView.qml, but that view is only instantiated while the
// equalizer popup is open (see the Loader in EqualizerPopup.qml gated on
// GlobalStates.equalizerOpen) - so the Connections/Process chain that makes
// Auto actually follow the currently playing track only existed while you
// had the popup open, and died the moment you closed it. Living here
// instead means Auto keeps following track changes in the background
// regardless of whether the popup is open, same as any other always-on
// service singleton (MprisController, etc).
//
// EqualizerView.qml should now just read/display root.autoEnabled and call
// root.toggleAuto()/root.maybeLookupGenre() rather than owning any of this
// state itself.
Singleton {
    id: root

    readonly property MprisPlayer player: MprisController.activePlayer

    property bool autoEnabled: false
    // Avoids re-querying (network + cache read) on every metadata blip for
    // the same artist - only look up again once the artist actually changes.
    property string lastGenreArtist: ""
    // Mirrors the preset currently applied, so a genre lookup that resolves
    // to the preset that's already active is a no-op instead of reloading
    // EasyEffects redundantly. Seeded from the backend on startup and kept
    // in sync whenever this service applies a preset itself; a preset
    // change made manually in the UI while the popup is open is picked up
    // next time refresh() runs (see EqualizerView.qml's refresh()/applyPreset()).
    property string currentPresetName: "Flat"

    // Genre-aware Auto EQ: neither Spotify nor a browser exposes genre over
    // MPRIS, so equalizer.sh looks up the current artist's tags via
    // Last.fm instead (see genre_tags in that script). This maps those
    // (messy, crowdsourced) tags to one of our 8 presets by substring -
    // checked in this order, first match wins, so put more specific
    // genres before broad ones that might also appear as a tag together.
    readonly property var genreTagPresetMap: ({
        "metal": "Rock", "punk": "Rock", "grunge": "Rock", "rock": "Rock",
        "classical": "Classic", "orchestra": "Classic", "opera": "Classic", "baroque": "Classic",
        "jazz": "Jazz", "blues": "Jazz", "swing": "Jazz",
        "hip hop": "Bass", "hip-hop": "Bass", "rap": "Bass", "trap": "Bass",
        "edm": "Bass", "electronic": "Bass", "house": "Bass", "techno": "Bass", "dubstep": "Bass", "bass": "Bass",
        "acoustic": "Vocal", "folk": "Vocal", "singer-songwriter": "Vocal", "a cappella": "Vocal", "vocal": "Vocal",
        "pop": "Pop"
    })

    function refresh() {
        eqGetProc.running = false
        eqGetProc.running = true
    }

    function refreshAuto() {
        eqGetAutoProc.running = false
        eqGetAutoProc.running = true
    }

    function toggleAuto() {
        const next = !root.autoEnabled
        root.autoEnabled = next
        Quickshell.execDetached(["bash", Directories.eqScriptPath, Directories.eqStateDir, "set_auto", next ? "true" : "false"])
        if (next) {
            // Force a fresh lookup rather than skipping it because the
            // artist "hasn't changed" since last time Auto happened to be on.
            root.lastGenreArtist = ""
            root.maybeLookupGenre()
        }
    }

    // Called whenever the current artist might have changed (track change,
    // Auto just got switched on, a Last.fm key just got saved).
    function maybeLookupGenre() {
        if (!root.autoEnabled) return
        const artist = root.player?.trackArtist ?? ""
        if (!artist || artist === root.lastGenreArtist) return
        root.lastGenreArtist = artist
        genreTagsProc.artist = artist
        genreTagsProc.running = false
        genreTagsProc.running = true
    }

    // First tag that matches a key in genreTagPresetMap wins; no match
    // (including an empty tag list - unset API key, unknown artist, no
    // network) just leaves the current preset alone.
    function presetForTags(tags) {
        if (!Array.isArray(tags)) return null
        for (const tag of tags) {
            const lower = String(tag).toLowerCase()
            for (const key in root.genreTagPresetMap) {
                if (lower.includes(key)) return root.genreTagPresetMap[key]
            }
        }
        return null
    }

    function applyAutoPreset(name) {
        root.currentPresetName = name
        Quickshell.execDetached(["bash", Directories.eqScriptPath, Directories.eqStateDir, "preset", name])
    }

    Component.onCompleted: {
        root.refresh()
        root.refreshAuto()
    }

    Connections {
        target: root.player
        function onTrackArtistChanged() { root.maybeLookupGenre() }
    }

    Process {
        id: eqGetProc
        command: ["bash", Directories.eqScriptPath, Directories.eqStateDir, "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text)
                    root.currentPresetName = data.preset ?? "Custom"
                } catch (e) {
                    // Leave previous value if the state file isn't ready yet
                }
            }
        }
    }

    Process {
        id: eqGetAutoProc
        command: ["bash", Directories.eqScriptPath, Directories.eqStateDir, "get_auto"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim()
                root.autoEnabled = (t === "true" || t === "1")
                if (root.autoEnabled) root.maybeLookupGenre()
            }
        }
    }

    Process {
        id: genreTagsProc
        property string artist: ""
        // "true" is a harmless no-op command for when artist is still
        // empty (e.g. before the first real onTrackArtistChanged fires).
        command: artist.length > 0
            ? ["bash", Directories.eqScriptPath, Directories.eqStateDir, "genre_tags", artist]
            : ["true"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const tags = JSON.parse(text)
                    const preset = root.presetForTags(tags)
                    if (preset && root.autoEnabled && preset !== root.currentPresetName) {
                        root.applyAutoPreset(preset)
                    }
                } catch (e) {
                    // No tags / API key not set up / network hiccup - leave
                    // the current preset alone rather than erroring.
                }
            }
        }
    }
}
