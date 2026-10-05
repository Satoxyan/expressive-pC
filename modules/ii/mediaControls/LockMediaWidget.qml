pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.mediaControls
import qs

// Full media player on the lockscreen (same as desktop; compact mode removed).
Item {
    id: root

    required property MprisPlayer player
    required property real radius
    property list<real> visualizerPoints: []

    // Exposed so LockSurface can still read dominant color for bg tinting, etc.
    readonly property color artDominantColor: mediaPlayer.artDominantColor
    readonly property string displayedArtFilePath: mediaPlayer.displayedArtFilePath

    // Sizes — must match what LockSurface passes in
    readonly property real fullWidth:  Appearance.sizes.mediaControlsWidth
    readonly property real fullHeight: mediaPlayer.showLyrics ? 290 : Appearance.sizes.mediaControlsHeight

    implicitWidth: fullWidth
    implicitHeight: fullHeight
    width: implicitWidth
    height: implicitHeight

    // Animate the height snap when lyrics open/close
    Behavior on implicitHeight {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.OutExpo
        }
    }

    // ── Full media player (repo's Player widget, includes lyrics) ─────────────
    Player {
        id: mediaPlayer
        width: root.fullWidth
        height: root.height
        player: root.player
        visualizerPoints: root.visualizerPoints
        radius: root.radius
    }
}
