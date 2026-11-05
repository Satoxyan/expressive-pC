pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property bool visible: false
    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property var realPlayers: MprisController.players
    readonly property var meaningfulPlayers: {
        const preferred = Config.options.bar.media.preferredPlayer.trim().toLowerCase()
        if (preferred.length === 0) return filterDuplicatePlayers(realPlayers)
        const filtered = realPlayers.filter(p =>
            (p.identity ?? "").toLowerCase().includes(preferred) ||
            (p.desktopEntry ?? "").toLowerCase().includes(preferred)
        )
        if (filtered.length === 0) return filterDuplicatePlayers(realPlayers)
        return filterDuplicatePlayers(filtered)
    }

    readonly property real lyricsCardHeight: 290
    readonly property real colSpacing: -Appearance.sizes.elevationMargin
    // Only the popup standing above the dock reorders its cards. That one has an edge the
    // dock is against, and the card resting on that edge is the media the dock is looking at;
    // a popup the bar opened keeps the order its players came in.
    readonly property bool followsDock: GlobalStates.mediaControlsAboveDock && !root.barVertical
    readonly property real osdWidth: Appearance.sizes.osdWidth
    readonly property real widgetWidth: Appearance.sizes.mediaControlsWidth
    readonly property real widgetHeight: Appearance.sizes.mediaControlsHeight
    property real popupRounding: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

    readonly property string mediaPosition: {
        if (Config.options.bar.layouts.leftLayout.includes("media")) return "left"
        if (Config.options.bar.layouts.middleLayout.includes("media")) return "center"
        if (Config.options.bar.layouts.rightLayout.includes("media")) return "right"
        return "center"
    }

    readonly property bool barVertical: Config.options.bar.vertical
    readonly property string growFrom: {
        if (barEdge === "bottom") return "bottom"
        if (barEdge === "top") return "top"
        if (mediaPosition === "left") return "top"
        if (mediaPosition === "right") return "bottom"
        return "center"
    }
    readonly property string barEdge: {
        if (!barVertical) return Config.options.bar.bottom ? "bottom" : "top"
        return Config.options.bar.bottom ? "right" : "left"
    }
    // Tepi window mana yang dijadikan patokan kolom (atas/tengah/bawah), supaya
    // posisi kartu tetap sama walau tinggi kartu beranimasi. Cabangnya harus
    // sama persis dengan urutan perhitungan margins.top di PanelWindow.
    readonly property string vAnchor: {
        if (GlobalStates.mediaControlsAboveDock && !barVertical) return "bottom"
        if (barEdge === "top") return "top"
        if (barEdge === "bottom") return "bottom"
        if (mediaPosition === "left") return "top"
        if (mediaPosition === "right") return "bottom"
        return "center"
    }
    readonly property real gap: Config.options.bar.cornerStyle === 3 ? Appearance.sizes.hyprlandGapsOut : 0
    readonly property real barThickness: barVertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.barHeight

    function filterDuplicatePlayers(players) {
        let filtered = [];
        let used = new Set();

        for (let i = 0; i < players.length; ++i) {
            if (used.has(i))
                continue;
            let p1 = players[i];
            let group = [i];

            // Find duplicates by trackTitle prefix
            for (let j = i + 1; j < players.length; ++j) {
                let p2 = players[j];
                if (p1.trackTitle && p2.trackTitle && (p1.trackTitle.includes(p2.trackTitle) || p2.trackTitle.includes(p1.trackTitle)) || (Math.abs(p1.position - p2.position) <= 2 && Math.abs(p1.length - p2.length) <= 2)) {
                    group.push(j);
                }
            }

            // Pick the one with non-empty trackArtUrl, or fallback to the first
            let chosenIdx = group.find(idx => players[idx].trackArtUrl && players[idx].trackArtUrl.length > 0);
            if (chosenIdx === undefined)
                chosenIdx = group[0];

            filtered.push(players[chosenIdx]);
            group.forEach(idx => used.add(idx));
        }
        return filtered;
    }

    // How tall a player's card wants to be, which is the whole of what stacking needs to
    // know: a card is one height or the other, and the card itself asks for them in exactly
    // this way.
    function heightFor(player) {
        return (LyricsService.trackFor(player)?.lyricsOpen ?? false)
            ? root.lyricsCardHeight : root.widgetHeight
    }

    readonly property var orderedPlayers: {
        const list = root.meaningfulPlayers
        const key = GlobalStates.dockMediaKey
        if (!root.followsDock || list.length < 2 || key.length === 0) return list
        let hit = null
        for (const p of list) {
            if (LyricsService.playerKey(p) === key) hit = p
        }
        // A bus the duplicate filter folded away, or the preferred-player setting hid, has no
        // card here at all: then nothing may move.
        if (!hit) return list
        // Last of the list is the bottom of the stack, which is the end the dock stands at.
        return list.filter(p => LyricsService.playerKey(p) !== key).concat([hit])
    }

    function rankOf(player, naturalIndex) {
        const key = LyricsService.playerKey(player)
        const list = root.orderedPlayers
        for (let i = 0; i < list.length; i++) {
            if (LyricsService.playerKey(list[i]) === key) return i
        }
        return naturalIndex
    }

    // Where a card would rest if the stack were laid out in `list`.
    function yAt(list, index) {
        let y = 0
        for (let i = 0; i < index; i++) {
            y += root.heightFor(list[i]) + root.colSpacing
        }
        return y
    }

     Process {
        id: cavaProc
        // Pemicu: overlay/panel yang butuh visualizer.
        readonly property bool trigger: GlobalStates.mediaControlsOpen ||
            GlobalStates.lockMediaOpen ||
            GlobalStates.sidebarRightOpen ||
            (GlobalStates.sidebarLeftOpen && !GlobalStates.mediaLyricsVisible) ||
            GlobalStates.equalizerOpen ||
            Config.options.bar.layouts.leftLayout.includes("visualizer") ||
            Config.options.bar.layouts.middleLayout.includes("visualizer") ||
            (Config.options.bar.layouts.middleLayout.includes("dynamicIsland") &&
                (Config.options.bar.dynamicIsland.visualizerStyle === "wave" ||
                (Config.options.bar.dynamicIsland.visualizerStyle === "dots" && !Config.options.bar.dynamicIsland.showMediaControls))) ||
            Config.options.bar.layouts.rightLayout.includes("visualizer") ||
            Config.options.background.widgets.visualizer.enable
        readonly property bool playing: MprisController.activePlayer?.isPlaying ?? false
        // Tahan cava beberapa detik setelah pemicu terakhir mati, supaya
        // spam toggle panel kanan tidak spawn/kill cava berulang (storm
        // proses + buka/tutup device audio yang memperlambat UI).
        onTriggerChanged: if (trigger && playing) holdTimer.restart()
        onPlayingChanged: if (trigger && playing) holdTimer.restart()
        running: playing && (trigger || holdTimer.running)
        onRunningChanged: {
            if (!cavaProc.running) {
                GlobalStates.visualizerPoints = [];
            }
        }
        command: ["cava", "-p", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/cava/raw_output_config.txt`]
        stdout: SplitParser {
            onRead: data => {
                let points = data.split(";").map(p => parseFloat(p.trim())).filter(p => !isNaN(p));
                GlobalStates.visualizerPoints = points;
            }
        }
    }

    // Sibling cavaProc (Process tidak boleh punya child object).
    Timer { id: holdTimer; interval: 4000 }

    Loader {
        id: mediaControlsLoader
        active: GlobalStates.mediaControlsOpen
        onActiveChanged: {
            if (!mediaControlsLoader.active && root.realPlayers.length === 0) {
                GlobalStates.mediaControlsOpen = false;
            }
        }

        sourceComponent: PanelWindow {
            id: panelWindow
            visible: true

            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            implicitWidth: root.widgetWidth
            // Tinggi window dipegang konstan: N kartu × tinggi lyrics maksimum.
            // Selama toggle lirik yang bergerak cuma kartu di dalamnya — window
            // tidak pernah di-resize, jadi tak ada set_size+set_margin yang datang
            // terpisah (itu penyebab popup "fling" lalu balik lagi).
            implicitHeight: root.meaningfulPlayers.length > 0
                ? root.meaningfulPlayers.length * root.lyricsCardHeight
                : playerColumnLayout.implicitHeight
            color: "transparent"
            WlrLayershell.namespace: "quickshell:mediaControls"

            anchors {
                top: true
                left: true
            }
            readonly property real cardMargin: Appearance.sizes.elevationMargin
            readonly property real inset: Config.options.hyprland.general.gapsOut
            readonly property var reserved: {
                const monitor = HyprlandData.monitors.find(m => m.name === panelWindow.screen.name)
                if (monitor?.reserved) return monitor.reserved
                const bar = root.barThickness
                return [root.barEdge === "left" ? bar : 0, root.barEdge === "top" ? bar : 0, root.barEdge === "right" ? bar : 0, root.barEdge === "bottom" ? bar : 0]
            }
            readonly property real minX: reserved[0] + inset - cardMargin
            readonly property real maxX: panelWindow.screen.width - reserved[2] - inset - root.widgetWidth + cardMargin
            readonly property real minY: reserved[1] + inset - cardMargin
            // maxY pakai tinggi window (bukan playerColumnLayout): tinggi window
            // kita dipegang konstan N×290, margins harus menempel ke tepi window.
            readonly property real maxY: panelWindow.screen.height - reserved[3] - inset - panelWindow.implicitHeight + cardMargin

            margins {
                top: {
                    if (GlobalStates.mediaControlsAboveDock && !root.barVertical) {
                        const dockHeight = (Config.options?.dock.height ?? 70)
                            + Appearance.sizes.elevationMargin + Appearance.sizes.hyprlandGapsOut
                        return panelWindow.screen.height - dockHeight - panelWindow.implicitHeight
                    }
                    if (root.barEdge === "top") return panelWindow.minY
                    if (root.barEdge === "bottom") return panelWindow.maxY
                    if (root.mediaPosition === "left") return panelWindow.minY
                    if (root.mediaPosition === "right") return panelWindow.maxY
                    return (panelWindow.minY + panelWindow.maxY) / 2
                }
                left: {
                    if (GlobalStates.mediaControlsAboveDock && !root.barVertical) {
                        return Math.max(root.gap, Math.min(
                            GlobalStates.mediaControlsAnchorX - root.widgetWidth / 2,
                            panelWindow.screen.width - root.widgetWidth - root.gap))
                    }
                    if (root.barEdge === "left") return panelWindow.minX
                    if (root.barEdge === "right") return panelWindow.maxX
                    if (root.mediaPosition === "left") return panelWindow.minX
                    if (root.mediaPosition === "right") return panelWindow.maxX
                    return (panelWindow.minX + panelWindow.maxX) / 2
                }
            }

            mask: Region {
                item: root.meaningfulPlayers.length === 1 && playerColumnLayout.firstCard ? playerColumnLayout.firstCard : playerColumnLayout
            }

            Component.onCompleted: {
                HyprlandData.updateMonitors()
                if (!Config.options.bar.media.alwaysVisible)
                    GlobalFocusGrab.addDismissable(panelWindow);
            }
            Component.onDestruction: {
                if (!Config.options.bar.media.alwaysVisible)
                    GlobalFocusGrab.removeDismissable(panelWindow);
            }
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    if (!Config.options.bar.media.alwaysVisible)
                        GlobalStates.mediaControlsOpen = false;
                }
            }

            ColumnLayout {
                id: playerColumnLayout
                property Item firstCard: null
                // Lebar ikut window, tinggi ikut isi (kartu). Tinggi yang mengikuti
                // kartu bikin mask input cuma menutupi kartu — band transparan
                // di atas window yang selalu tinggi itu tetap klik-tembus.
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: root.vAnchor === "top" ? parent.top : undefined
                anchors.bottom: root.vAnchor === "bottom" ? parent.bottom : undefined
                anchors.verticalCenter: root.vAnchor === "center" ? parent.verticalCenter : undefined
                spacing: root.colSpacing // Shadow overlap okay

                Repeater {
                    id: playersRepeater
                    onItemAdded: playerColumnLayout.firstCard = playersRepeater.itemAt(0)?.cardItem ?? null
                    onItemRemoved: playerColumnLayout.firstCard = playersRepeater.itemAt(0)?.cardItem ?? null
                    model: ScriptModel {
                        values: root.meaningfulPlayers
                    }
                    delegate: Item {
                        id: playerSlot
                        required property MprisPlayer modelData
                        required property int index
                        // This card's own lyric flag: two players, two cards, and opening one
                        // lyric leaves the other at its title line.
                        readonly property real targetHeight: root.heightFor(modelData)
                        // The slot the dock wants this card in, told as the distance from the
                        // place the layout already gave it. The layout goes on stacking by
                        // itself and only the shuffle is animated here, so a card opening its
                        // lyrics never fights with a card moving down to the dock.
                        readonly property int rank: root.rankOf(modelData, playerSlot.index)
                        property real reorderOffset: root.yAt(root.orderedPlayers, playerSlot.rank)
                            - root.yAt(root.meaningfulPlayers, playerSlot.index)
                        implicitWidth: root.widgetWidth
                        // tinggi slot = tinggi kartu (beranimasi) → tinggi kolom dan
                        // mask input ikut, sementara tinggi window tetap konstan
                        implicitHeight: card.height
                        // The order cards are drawn in follows the order they end up standing
                        // in, so a card crossing the stack passes over the ones it is not
                        // landing behind.
                        z: playerSlot.rank

                        transform: Translate { y: playerSlot.reorderOffset }

                        Behavior on reorderOffset {
                            // The dock's own crossing: the two cards are on their way at the
                            // same time and arrive on the same frame.
                            NumberAnimation { duration: 420; easing.type: Easing.BezierSpline
                                easing.bezierCurve: Appearance.animationCurves.standard }
                        }

                        Item {
                            id: card
                            width: parent.width
                            height: playerSlot.targetHeight
                            Behavior on height {
                                NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                            }
                            Player {
                                anchors.fill: parent
                                player: playerSlot.modelData
                                visualizerPoints: GlobalStates.visualizerPoints
                                radius: root.popupRounding
                            }
                        }
                    }
                }

                Item {
                    // No player placeholder
                    Layout.alignment: {
                        if (panelWindow.anchors.left)
                            return Qt.AlignLeft;
                        if (panelWindow.anchors.right)
                            return Qt.AlignRight;
                        return Qt.AlignHCenter;
                    }
                    Layout.leftMargin: Appearance.sizes.hyprlandGapsOut
                    Layout.rightMargin: Appearance.sizes.hyprlandGapsOut
                    visible: root.meaningfulPlayers.length === 0
                    implicitWidth: placeholderBackground.implicitWidth + Appearance.sizes.elevationMargin
                    implicitHeight: placeholderBackground.implicitHeight + Appearance.sizes.elevationMargin

                    StyledRectangularShadow {
                        target: placeholderBackground
                    }

                    Rectangle {
                        id: placeholderBackground
                        anchors.centerIn: parent
                        color: Appearance.colors.colLayer0
                        radius: root.popupRounding
                        property real padding: 20
                        implicitWidth: placeholderLayout.implicitWidth + padding * 2
                        implicitHeight: placeholderLayout.implicitHeight + padding * 2

                        ColumnLayout {
                            id: placeholderLayout
                            anchors.centerIn: parent

                            StyledText {
                                text: Translation.tr("No active player")
                                font.pixelSize: Appearance.font.pixelSize.large
                            }
                            StyledText {
                                color: Appearance.colors.colSubtext
                                text: Translation.tr("Make sure your player has MPRIS support\nor try turning off duplicate player filtering")
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "mediaControls"

        function toggle(): void {
            GlobalStates.mediaControlsAboveDock = false;
            mediaControlsLoader.active = !mediaControlsLoader.active;
            if (mediaControlsLoader.active)
                Notifications.timeoutAll();
        }

        function close(): void {
            GlobalStates.mediaControlsAboveDock = false;
            mediaControlsLoader.active = false;
        }

        function open(): void {
            GlobalStates.mediaControlsAboveDock = false;
            mediaControlsLoader.active = true;
            Notifications.timeoutAll();
        }
    }

    CompositorGlobalShortcut {
        name: "mediaControlsToggle"
        description: "Toggles media controls on press"

        onPressed: {
            GlobalStates.mediaControlsAboveDock = false;
            GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen;
        }
    }
    CompositorGlobalShortcut {
        name: "mediaControlsOpen"
        description: "Opens media controls on press"

        onPressed: {
            GlobalStates.mediaControlsAboveDock = false;
            GlobalStates.mediaControlsOpen = true;
        }
    }
    CompositorGlobalShortcut {
        name: "mediaControlsClose"
        description: "Closes media controls on press"

        onPressed: {
            GlobalStates.mediaControlsAboveDock = false;
            GlobalStates.mediaControlsOpen = false;
        }
    }
}
