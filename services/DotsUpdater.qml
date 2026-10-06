pragma Singleton

import qs
import QtQuick
import Quickshell

Singleton {
    id: root

    function runSystemUpdate() {
        Quickshell.execDetached([
            "kitty", "--hold",
            "fish", "-i", "-l", "-c",
            "yay -Syu --combinedupgrade=false"
        ])
        Qt.callLater(() => GlobalStates.settingsOpen = false)
    }

    function runUpdateDots() {
        const updateScript = `
            set -e
            DIR="$HOME/.config/quickshell"

            rm -rf "$DIR/expressive-pC-tmp"
            git clone https://github.com/Satoxyan/expressive-pC.git "$DIR/expressive-pC-tmp"

            rm -rf "$DIR/expressive-pC-old"
            [ -d "$DIR/expressive-pC" ] && mv "$DIR/expressive-pC" "$DIR/expressive-pC-old"
            mv "$DIR/expressive-pC-tmp" "$DIR/expressive-pC"

            killall qs 2>/dev/null || true
            sleep 0.5
            setsid qs -c expressive-pC >/tmp/qs.log 2>&1 < /dev/null &
            disown

            rm -rf "$DIR/expressive-pC-old"
        `

        Quickshell.execDetached(["kitty", "--hold", "bash", "-c", updateScript])
        Qt.callLater(() => GlobalStates.settingsOpen = false)
    }
}
