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
    return normalize(appId) === target || normalize(resolvedEntryId) === target
}
