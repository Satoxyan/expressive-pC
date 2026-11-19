.pragma library

// MPRIS reports the desktop entry a player belongs to ("firefox.desktop"),
// while a window reports its own app id ("firefox", "org.mozilla.firefox").
// Both sides are reduced to the same shape before comparing.
function normalize(id) {
    return String(id ?? "").toLowerCase().replace(/\.desktop$/, "")
}

function matches(desktopEntry, appId, resolvedEntryId) {
    const target = normalize(desktopEntry)
    if (!target) return false
    return matchesId(target, appId) || matchesId(target, resolvedEntryId)
}

// A browser integration can report the generic browser id ("firefox") while
// the window carries the edition id ("firefox-developer-edition"), and no
// "firefox.desktop" is installed on such a machine. A "-suffix" relation is
// the same application, so accept it.
function matchesId(target, candidate) {
    const id = normalize(candidate)
    if (!id) return false
    return id === target || id.startsWith(target + "-")
}
