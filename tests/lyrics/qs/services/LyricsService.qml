pragma Singleton

import QtQuick

// Test double for qs.services.LyricsService, the registry: the songs the widget
// draws are handed out per player, and every test that existed before this was
// one player's song, so the registry is a single track that answers for them
// all. `active` is what a widget with no player of its own binds to.
LyricsTrack {
    id: registry

    readonly property var active: registry

    // The registry looks a song up by the player it belongs to. The tests only
    // ever have one, and the widget under test is told which song to draw.
    function trackFor(player) { return registry }

    // What the hosts call when they show a player's card, so a paused player
    // still gets its lyric looked up. Nothing here looks anything up.
    function ensureFor(player) {}
}
