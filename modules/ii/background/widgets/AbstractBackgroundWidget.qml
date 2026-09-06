import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets.widgetCanvas

AbstractWidget {
    id: root

    required property string configEntryName
    required property int screenWidth
    required property int screenHeight
    required property int scaledScreenWidth
    required property int scaledScreenHeight
    required property real wallpaperScale
    property bool visibleWhenLocked: Config.options.lock.showWidgets
    property var configEntry: Config.options.background.widgets[configEntryName]
    property string placementStrategy: configEntry.placementStrategy
    property real targetX: Math.max(0, Math.min(configEntry.x, scaledScreenWidth - width))
    property real targetY : Math.max(0, Math.min(configEntry.y, scaledScreenHeight - height))
    x: targetX
    y: targetY
    visible: opacity > 0
    opacity: (GlobalStates.screenLocked && !visibleWhenLocked) ? 0 : 1
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    scale: (draggable && containsPress) ? 1.05 : 1
    Behavior on scale {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }

    draggable: !Config.options.background.widgetsLocked
    function restoreXYBinding() {
        root.x = Qt.binding(() => root.targetX);
        root.y = Qt.binding(() => root.targetY);
    }

    onDragFinished: {
        if (root.configEntry.placementStrategy !== "free")
            root.configEntry.placementStrategy = "free"
    }

    onReleased: {
        configEntry.x = root.x;
        configEntry.y = root.y;
        root.targetX = Qt.binding(() => Math.max(0, Math.min(configEntry.x, scaledScreenWidth - width)));
        root.targetY = Qt.binding(() => Math.max(0, Math.min(configEntry.y, scaledScreenHeight - height)));
        root.restoreXYBinding();
    }

    property bool needsColText: false
    // Text widgets (e.g. digital lock clock with cookie desktop clock) flip this
    // when the style changes; rescan so the color grid exists for the new style.
    onNeedsColTextChanged: refreshPlacementIfNeeded()
    // Dominant colors of a grid tiling the screen (one script run per wallpaper);
    // picking the cell under the widget is instant, so text color follows movement live.
    property var colorGrid: null
    property int gridCols: 0
    property int gridRows: 0
    property color scannedDominantColor: Appearance.colors.colPrimary
    property color sampledColor: Appearance.colors.colPrimary
    readonly property real widgetCenterX: root.x + root.width / 2
    readonly property real widgetCenterY: root.y + root.height / 2
    // ponytail: bbox ketat 0.85x + halo 12% — pas dengan teks tampil, bukan widget bounds
    property color dominantColor: {
        if (root.colorGrid && root.gridCols > 0 && root.gridRows > 0
            && root.scaledScreenWidth > 0 && root.scaledScreenHeight > 0) {
            const pad = Math.round(Math.min(root.width, root.height) * 0.12)
            const tightW = root.width * 0.85
            const tightH = root.height * 0.85
            const x1 = widgetCenterX - tightW / 2 - pad
            const y1 = widgetCenterY - tightH / 2 - pad
            const x2 = widgetCenterX + tightW / 2 + pad
            const y2 = widgetCenterY + tightH / 2 + pad
            const colStart = Math.max(0, Math.floor(x1 / root.scaledScreenWidth * root.gridCols))
            const colEnd = Math.min(root.gridCols - 1, Math.floor(x2 / root.scaledScreenWidth * root.gridCols))
            const rowStart = Math.max(0, Math.floor(y1 / root.scaledScreenHeight * root.gridRows))
            const rowEnd = Math.min(root.gridRows - 1, Math.floor(y2 / root.scaledScreenHeight * root.gridRows))
            let sumR = 0, sumG = 0, sumB = 0, cnt = 0;
            for (let r = rowStart; r <= rowEnd; r++) {
                for (let c = colStart; c <= colEnd; c++) {
                    const hex = root.colorGrid[r * root.gridCols + c];
                    if (!hex) continue;
                    const col = Qt.color(hex);
                    sumR += col.r; sumG += col.g; sumB += col.b; cnt++;
                }
            }
            if (cnt > 0) return Qt.rgba(sumR / cnt, sumG / cnt, sumB / cnt, 1);
            // fallback ke 3x3 sekitar center jika bbox di luar grid
            const col = Math.min(root.gridCols - 1, Math.max(0, Math.floor(widgetCenterX / root.scaledScreenWidth * root.gridCols)));
            const row = Math.min(root.gridRows - 1, Math.max(0, Math.floor(widgetCenterY / root.scaledScreenHeight * root.gridRows)));
            const hex = root.colorGrid[row * root.gridCols + col];
            if (hex) return hex;
        }
        if (root.sampledColor != Appearance.colors.colPrimary) return root.sampledColor;
        return root.scannedDominantColor;
    }
    // Weighted luminance (Rec. 601) — matches perceived brightness better than HSL lightness
    property bool dominantColorIsDark: (0.299 * dominantColor.r + 0.587 * dominantColor.g + 0.114 * dominantColor.b) < 0.5
    property color colText: {
        const onNormalBackground = (GlobalStates.screenLocked && Config.options.lock.blur.enable)
        const adaptiveColor = ColorUtils.colorWithLightness(Appearance.colors.colPrimary, (dominantColorIsDark ? 0.8 : 0.12))
        return onNormalBackground ? Appearance.colors.colBackground : adaptiveColor;
    }

    property bool wallpaperIsVideo: Config.options.background.wallpaperPath.endsWith(".mp4") || Config.options.background.wallpaperPath.endsWith(".webm") || Config.options.background.wallpaperPath.endsWith(".mkv") || Config.options.background.wallpaperPath.endsWith(".avi") || Config.options.background.wallpaperPath.endsWith(".mov")
    property string wallpaperPath: wallpaperIsVideo ? Config.options.background.thumbnailPath : Config.options.background.wallpaperPath
    
    onWallpaperPathChanged: refreshPlacementIfNeeded()
    onPlacementStrategyChanged: refreshPlacementIfNeeded()
    Connections {
        target: Config
        function onReadyChanged() { refreshPlacementIfNeeded() }
    }
    property bool pendingPlacementRefresh: false
    property string activePlacementStrategy: ""
    function leastBusyRegionCommand() {
        // Text widgets get a dominant-color grid over the whole screen so the color
        // can follow widget movement instantly; placement scan only for non-free strategies.
        const skipScan = root.placementStrategy === "free";
        return [Quickshell.shellPath("scripts/images/least-busy-region-venv.sh")
            , "--screen-width", Math.round(root.scaledScreenWidth)
            , "--screen-height", Math.round(root.scaledScreenHeight)
            , "--width", leastBusyRegionProc.contentWidth
            , "--height", leastBusyRegionProc.contentHeight
            , ...(skipScan ? ["--skip-scan"] : [])
            , ...(root.needsColText ? ["--color-grid-cols", leastBusyRegionProc.gridCols
                , "--color-grid-rows", leastBusyRegionProc.gridRows] : [])
            , "--horizontal-padding", leastBusyRegionProc.horizontalPadding
            , "--vertical-padding", leastBusyRegionProc.verticalPadding
            , root.wallpaperPath
            , ...(root.placementStrategy === "mostBusy" ? ["--busiest"] : [])
        ];
    }
    function startLeastBusyRegionProc() {
        root.activePlacementStrategy = root.placementStrategy;
        leastBusyRegionProc.command = root.leastBusyRegionCommand();
        leastBusyRegionProc.running = true;
    }
    function refreshPlacementIfNeeded() {
        if (!Config.ready) return;
        if (root.placementStrategy === "free" && !root.needsColText) return;
        leastBusyRegionProc.wallpaperPath = root.wallpaperPath;
        if (leastBusyRegionProc.running) {
            root.pendingPlacementRefresh = true;
            leastBusyRegionProc.running = false;
        } else {
            root.startLeastBusyRegionProc();
        }
    }
    // ponytail: debug overlay — set true untuk lihat grid 8x5 + 3x3 aktif; matikan setelah verifikasi
    property bool debugGrid: false

    Process {
        id: leastBusyRegionProc
        property string wallpaperPath: root.wallpaperPath
        // TODO: make these less arbitrary
        property int contentWidth: 300
        property int contentHeight: 300
        property int horizontalPadding: 200
        property int verticalPadding: 200
        property int gridCols: 36
        property int gridRows: 18
        onRunningChanged: {
            if (!leastBusyRegionProc.running && root.pendingPlacementRefresh) {
                root.pendingPlacementRefresh = false;
                root.startLeastBusyRegionProc();
            }
        }
        stdout: StdioCollector {
            id: leastBusyRegionOutputCollector
            onStreamFinished: {
                const output = leastBusyRegionOutputCollector.text;
                // console.log("[Background] Least busy region output:", output)
                if (output === "") return;
                if (root.activePlacementStrategy !== root.placementStrategy) return;
                const parsedContent = JSON.parse(output);
                if (parsedContent.colors) {
                    root.colorGrid = parsedContent.colors;
                    root.gridCols = parsedContent.grid_cols;
                    root.gridRows = parsedContent.grid_rows;
                }
                if (parsedContent.sampled_color) root.sampledColor = parsedContent.sampled_color;
                root.scannedDominantColor = parsedContent.dominant_color || Appearance.colors.colPrimary;
                if (root.placementStrategy === "free") return;
                root.targetX = parsedContent.center_x * root.wallpaperScale - root.width / 2;
                root.targetY  = parsedContent.center_y * root.wallpaperScale - root.height / 2;
            }
        }
    }

    // ponytail: overlay debug — full-screen grid di atas wallpaper, tidak ganggu drag (enabled: false)
    Item {
        id: debugGridOverlay
        visible: root.debugGrid && root.colorGrid && root.gridCols > 0 && root.gridRows > 0
        // cover scaled screen dari koordinat lokal widget
        x: -root.x
        y: -root.y
        width: root.scaledScreenWidth
        height: root.scaledScreenHeight
        z: 999
        enabled: false

        // ponytail: bbox ketat 0.85x + halo 12% — highlight tile yang intersect teks tampil
        readonly property int pad: Math.round(Math.min(root.width, root.height) * 0.12)
        readonly property real tightW: root.width * 0.85
        readonly property real tightH: root.height * 0.85
        readonly property int activeCol: Math.min(root.gridCols - 1, Math.max(0, Math.floor(root.widgetCenterX / root.scaledScreenWidth * root.gridCols)))
        readonly property int activeRow: Math.min(root.gridRows - 1, Math.max(0, Math.floor(root.widgetCenterY / root.scaledScreenHeight * root.gridRows)))
        readonly property int colStart: Math.max(0, Math.floor((root.widgetCenterX - tightW/2 - pad) / root.scaledScreenWidth * root.gridCols))
        readonly property int colEnd: Math.min(root.gridCols - 1, Math.floor((root.widgetCenterX + tightW/2 + pad) / root.scaledScreenWidth * root.gridCols))
        readonly property int rowStart: Math.max(0, Math.floor((root.widgetCenterY - tightH/2 - pad) / root.scaledScreenHeight * root.gridRows))
        readonly property int rowEnd: Math.min(root.gridRows - 1, Math.floor((root.widgetCenterY + tightH/2 + pad) / root.scaledScreenHeight * root.gridRows))

        Repeater {
            model: root.gridCols * root.gridRows
            delegate: Rectangle {
                required property int index
                readonly property int col: index % root.gridCols
                readonly property int row: Math.floor(index / root.gridCols)
                readonly property bool isActive: col >= debugGridOverlay.colStart && col <= debugGridOverlay.colEnd && row >= debugGridOverlay.rowStart && row <= debugGridOverlay.rowEnd
                readonly property bool isCenter: col === debugGridOverlay.activeCol && row === debugGridOverlay.activeRow
                x: col * root.scaledScreenWidth / root.gridCols
                y: row * root.scaledScreenHeight / root.gridRows
                width: root.scaledScreenWidth / root.gridCols
                height: root.scaledScreenHeight / root.gridRows
                color: {
                    const hex = root.colorGrid[index];
                    if (!hex) return "transparent";
                    const c = Qt.color(hex);
                    return Qt.rgba(c.r, c.g, c.b, isActive ? 0.45 : 0.18);
                }
                border.width: isCenter ? 3 : isActive ? 2 : 1
                border.color: isCenter ? "#00FF00" : isActive ? "#FFFF00" : "#FFFFFF88"
                Text {
                    anchors.centerIn: parent
                    text: parent.col + "," + parent.row + (parent.isCenter ? " ★" : "")
                    font.pixelSize: 11
                    color: "#FFFFFF"
                    style: Text.Outline
                    styleColor: "#000000"
                    visible: root.scaledScreenWidth > 800 // hide text on small preview
                }
            }
        }

        // bbox ketat jam + halo (presisi)
        Rectangle {
            x: root.widgetCenterX - debugGridOverlay.tightW/2 - debugGridOverlay.pad
            y: root.widgetCenterY - debugGridOverlay.tightH/2 - debugGridOverlay.pad
            width: debugGridOverlay.tightW + 2*debugGridOverlay.pad
            height: debugGridOverlay.tightH + 2*debugGridOverlay.pad
            color: "transparent"
            border.width: 2
            border.color: "#00FFFF"
            radius: 4
        }
        // crosshair pusat widget
        Rectangle {
            x: root.widgetCenterX - 12
            y: root.widgetCenterY - 1
            width: 24; height: 2; color: "#FF0000"; radius: 1
        }
        Rectangle {
            x: root.widgetCenterX - 1
            y: root.widgetCenterY - 12
            width: 2; height: 24; color: "#FF0000"; radius: 1
        }

        // label info
        Rectangle {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: 8
            radius: 8
            color: "#000000AA"
            implicitWidth: debugInfo.implicitWidth + 16
            implicitHeight: debugInfo.implicitHeight + 10
            Text {
                id: debugInfo
                anchors.centerIn: parent
                text: "GRID " + root.gridCols + "x" + root.gridRows
                    + " | bbox " + debugGridOverlay.colStart + "-" + debugGridOverlay.colEnd + "," + debugGridOverlay.rowStart + "-" + debugGridOverlay.rowEnd
                    + " (kuning=" + ((debugGridOverlay.colEnd-debugGridOverlay.colStart+1)*(debugGridOverlay.rowEnd-debugGridOverlay.rowStart+1)) + " tile) ★=" + debugGridOverlay.activeCol + "," + debugGridOverlay.activeRow
                    + " | " + (root.dominantColorIsDark ? "GELAP→0.8" : "TERANG→0.12")
                    + " lum " + (0.299*root.dominantColor.r + 0.587*root.dominantColor.g + 0.114*root.dominantColor.b).toFixed(2)
                    + " | size " + Math.round(root.width) + "x" + Math.round(root.height)
                font.pixelSize: 12
                color: "#FFFFFF"
            }
        }
    }
}