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
    readonly property real widgetCenterX: root.x + root.width / 2
    readonly property real widgetCenterY: root.y + root.height / 2
    property color dominantColor: {
        if (root.colorGrid && root.gridCols > 0 && root.gridRows > 0
            && root.scaledScreenWidth > 0 && root.scaledScreenHeight > 0) {
            const col = Math.min(root.gridCols - 1, Math.max(0, Math.floor(widgetCenterX / root.scaledScreenWidth * root.gridCols)));
            const row = Math.min(root.gridRows - 1, Math.max(0, Math.floor(widgetCenterY / root.scaledScreenHeight * root.gridRows)));
            const hex = root.colorGrid[row * root.gridCols + col];
            if (hex) return hex;
        }
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
    Process {
        id: leastBusyRegionProc
        property string wallpaperPath: root.wallpaperPath
        // TODO: make these less arbitrary
        property int contentWidth: 300
        property int contentHeight: 300
        property int horizontalPadding: 200
        property int verticalPadding: 200
        property int gridCols: 8
        property int gridRows: 5
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
                root.scannedDominantColor = parsedContent.dominant_color || Appearance.colors.colPrimary;
                if (root.placementStrategy === "free") return;
                root.targetX = parsedContent.center_x * root.wallpaperScale - root.width / 2;
                root.targetY  = parsedContent.center_y * root.wallpaperScale - root.height / 2;
            }
        }
    }
}