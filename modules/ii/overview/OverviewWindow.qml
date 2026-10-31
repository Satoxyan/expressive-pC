pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

Item { // Window
    id: root
    property var toplevel
    property var windowAddresses: HyprlandData.addresses
    property var windowByAddress: HyprlandData.windowByAddress
    property var windowData
    property var monitorData
    property var scale
    property bool restrictToWorkspace: true
    property real widthRatio: {
        const widgetWidth = widgetMonitor.transform & 1 ? widgetMonitor.height : widgetMonitor.width;
        const monitorWidth = monitorData.transform & 1 ? monitorData.height : monitorData.width;
        return (widgetWidth * monitorData.scale) / (monitorWidth * widgetMonitor.scale);
    }
    property real heightRatio: {
        const widgetHeight = widgetMonitor.transform & 1 ? widgetMonitor.width : widgetMonitor.height;
        const monitorHeight = monitorData.transform & 1 ? monitorData.width : monitorData.height;
        return (widgetHeight * monitorData.scale) / (monitorHeight * widgetMonitor.scale);
    }
    property real initX: {
        if (singleTiled) return xOffset;
        return (windowData?.at[0] - (monitorData?.x ?? 0) - monitorData?.reserved[0]) * widthRatio * root.scale + xOffset;
    }

    property real initY: {
        if (singleTiled) return yOffset;
        return (windowData?.at[1] - (monitorData?.y ?? 0) - monitorData?.reserved[1]) * heightRatio * root.scale + yOffset;
    }
    property real xOffset: 0
    property real yOffset: 0
    property var widgetMonitor
    property int widgetMonitorId: widgetMonitor.id
    property real workspaceWidth: 0
    property real workspaceHeight: 0

    property real tiledCount: {
        if (!windowData || windowData.floating || windowData.fullscreen) return 0;
        const wsId = windowData.workspace?.id;
        if (!wsId) return 0;
        let count = 0;
        for (const addr of root.windowAddresses) {
            const w = root.windowByAddress[addr];
            if (w && w.workspace?.id === wsId && !w.floating && !w.fullscreen) count++;
        }
        return count;
    }
    property bool singleTiled: tiledCount === 1

    property var targetWindowWidth: {
        if (singleTiled && root.workspaceWidth > 0) {
            return root.workspaceWidth;
        }
        return windowData?.size[0] * scale * widthRatio;
    }
    property var targetWindowHeight: {
        if (singleTiled && root.workspaceHeight > 0) {
            return root.workspaceHeight;
        }
        return windowData?.size[1] * scale * heightRatio;
    }
    property bool hovered: false
    property bool pressed: false
    property bool dragging: false

    property bool centerIcons: Config.options.overview.centerIcons
    property real iconGapRatio: 0.06
    property real iconToWindowRatio: centerIcons ? 0.35 : 0.15
    property real xwaylandIndicatorToIconRatio: 0.35
    property real iconToWindowRatioCompact: 0.6
    property string iconPath: SystemAppearance.iconPath(AppSearch.guessIcon(windowData?.class), "image-missing")
    property bool compactMode: Appearance.font.pixelSize.smaller * 4 > targetWindowHeight || Appearance.font.pixelSize.smaller * 4 > targetWindowWidth

    property bool indicateXWayland: windowData?.xwayland ?? false

    x: initX
    y: initY
    width: targetWindowWidth
    height: targetWindowHeight
    opacity: windowData.monitor == widgetMonitorId ? 1 : 0.4

    property real topLeftRadius
    property real topRightRadius
    property real bottomLeftRadius
    property real bottomRightRadius

    layer.enabled: true
    layer.effect: OpacityMask {
        maskSource: Rectangle {
            width: root.width
            height: root.height
            topLeftRadius: root.topLeftRadius
            topRightRadius: root.topRightRadius
            bottomRightRadius: root.bottomRightRadius
            bottomLeftRadius: root.bottomLeftRadius
        }
    }

    Behavior on x {
        enabled: !window.Drag.active && !window.dragging
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }
    Behavior on y {
        enabled: !window.Drag.active && !window.dragging
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }
    Behavior on width {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }
    Behavior on height {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }

    // The grabbed frame, and the object it came from. The grab is served from
    // a URL that only answers while that object is alive, so the result has to
    // be held, not just its url.
    property url snapshotUrl
    property var snapshotResult

    // Copies of every tile cannot be taken in the same frame, so each tile
    // starts from a phase worked out from its own address.
    readonly property int snapshotPhase: {
        const addr = (root.windowData?.address ?? "").toString();
        let h = 0;
        for (let i = 0; i < addr.length; i++)
            h = (h * 31 + addr.charCodeAt(i)) & 0xffff;
        return h % 5;
    }

    function grabSnapshot() {
        if (!windowPreview.hasContent) return
        windowPreview.grabToImage(function(result) {
            if (!result) return
            root.snapshotResult = result
            root.snapshotUrl = result.url
        })
    }

    // Refreshed while the stream is healthy, so what covers a gap is the most
    // recent picture rather than whatever the tile happened to show a minute ago.
    Timer {
        id: snapshotTick
        interval: 1000 + root.snapshotPhase * 100
        repeat: true
        triggeredOnStart: true
        running: GlobalStates.overviewOpen && windowPreview.hasContent
        onTriggered: root.grabSnapshot()
    }

    ScreencopyView {
        id: windowPreview

        // Attaching the stream twice in a row is what brings the preview back:
        // a frame Hyprland rejects while the window animates ends the recording
        // and clears the picture, and the view only rebuilds it when the source
        // is handed over again. So the source is detached for one tick and
        // reattached, until a frame survives or the tries run out.
        property bool detached: false
        property int rearmTries: 0
        anchors.fill: parent
        captureSource: GlobalStates.overviewOpen && !windowPreview.detached
            ? root.toplevel : null
        live: true

        onHasContentChanged: {
            if (windowPreview.hasContent) {
                windowPreview.rearmTries = 0
                rearmTick.stop()
                return
            }
            if (!GlobalStates.overviewOpen || root.toplevel === null) return
            windowPreview.rearmTries = 0
            rearmTick.restart()
        }

        Timer {
            id: rearmTick
            interval: 16
            repeat: true
            onTriggered: {
                if (windowPreview.hasContent || !GlobalStates.overviewOpen
                        || root.toplevel === null) {
                    windowPreview.rearmTries = 0
                    windowPreview.detached = false
                    rearmTick.stop()
                    return
                }
                // Stop after about a second and a half. An animation is over
                // long before that, and past it the source is not going to
                // answer — while every reattach costs a round trip to the
                // compositor.
                if (windowPreview.rearmTries++ >= 90) {
                    windowPreview.detached = false
                    rearmTick.stop()
                    return
                }
                // One detach-and-reattach per tick: the view only builds a fresh
                // capture context when the source it is given changes, and the
                // picture can stay empty without ever signalling again.
                windowPreview.detached = true
                windowPreview.detached = false
            }
        }

        // The frame the view last had, painted over the tile while the stream is
        // down. Reattaching takes as long as the compositor's own window
        // animation — around a quarter of a second, no matter how often the
        // retry runs — and a tile that goes empty for that long reads as broken
        // even though nothing is wrong. A slightly stale picture does not.
        Image {
            id: windowSnapshot
            anchors.fill: parent
            anchors.margins: 1   // the tile's border stays on top of it
            visible: !windowPreview.hasContent && windowSnapshot.status === Image.Ready
            fillMode: Image.PreserveAspectFit
            source: root.snapshotUrl
            cache: false
        }

        // Color overlay for interactions
        Rectangle {
            anchors.fill: parent
            topLeftRadius: root.topLeftRadius
            topRightRadius: root.topRightRadius
            bottomRightRadius: root.bottomRightRadius
            bottomLeftRadius: root.bottomLeftRadius
            color: pressed ? ColorUtils.transparentize(Appearance.colors.colLayer2Active, 0.5) : 
                hovered ? ColorUtils.transparentize(Appearance.colors.colLayer2Hover, 0.7) : 
                ColorUtils.transparentize(Appearance.colors.colLayer2)
            border.color : ColorUtils.transparentize(Appearance.m3colors.m3outline, 0.88)
            border.width : 1
        }

        Image {
            id: windowIcon
            property real baseSize: Math.min(root.targetWindowWidth, root.targetWindowHeight)
            anchors {
                top: root.centerIcons ? undefined : parent.top
                left: root.centerIcons ? undefined : parent.left
                centerIn: root.centerIcons ? parent : undefined
                margins: baseSize * root.iconGapRatio
            }
            property var iconSize: {
                // console.log("-=-=-", root.toplevel.title, "-=-=-")
                // console.log("Target window size:", targetWindowWidth, targetWindowHeight)
                // console.log("Icon ratio:", root.compactMode ? root.iconToWindowRatioCompact : root.iconToWindowRatio)
                // console.log("Scale:", root.monitorData.scale)
                // console.log("Final:", Math.min(targetWindowWidth, targetWindowHeight) * (root.compactMode ? root.iconToWindowRatioCompact : root.iconToWindowRatio) / root.monitorData.scale)
                return baseSize * (root.compactMode ? root.iconToWindowRatioCompact : root.iconToWindowRatio);
            }
            // mipmap: true
            Layout.alignment: Qt.AlignHCenter
            source: root.iconPath
            width: iconSize
            height: iconSize
            sourceSize: Qt.size(iconSize, iconSize)

            Behavior on width {
                animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
            }
            Behavior on height {
                animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
            }
        }
    }
}