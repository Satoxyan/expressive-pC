import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.ii.background.widgets
import qs.modules.common.models.hyprland
import Quickshell.Services.UPower

AbstractBackgroundWidget {
    id: root

    configEntryName: "visualizer"

    readonly property string style: configEntry.style ?? "bars"
    readonly property bool shaderStyle: ["aurora", "ring", "dots", "mirror"].includes(style)
    readonly property bool isRing: style === "ring"
    readonly property bool useCoverColors: (configEntry.colorSource ?? "theme") === "cover"

    readonly property var currentPowerProfile: PowerProfiles.profile
    readonly property int autoRenderEveryXFrames: {
        switch (PowerProfiles.profile) {
        case 2: return 1
        case 1: return 2
        case 0: return 4
        default: return 2
        }
    }

    property real ringSizeOverride: -1
    readonly property real ringSize: ringSizeOverride > 0 ? ringSizeOverride : (configEntry.ringSize ?? 380)
    readonly property real bandHeight: configEntry.height ?? 260
    readonly property real barsHeight: 240

    readonly property real barSpacing: configEntry.barSpacing ?? 10
    readonly property real barRounding: configEntry.barRounding ?? 0.5
    readonly property real smoothing: configEntry.smoothing ?? 0.18
    readonly property real dataSmoothing: configEntry.dataSmoothing ?? 0.5
    readonly property real canvasOpacity: configEntry.opacity ?? 1.0
    readonly property bool mono: configEntry.mono ?? true
    readonly property real waveFillOpacity: configEntry.waveFillOpacity ?? 0.5
    readonly property int waveBorderWidth: configEntry.waveBorderWidth ?? 3
    readonly property int targetBarWidth: configEntry.targetBarWidth ?? 50

    property bool isCovered: false
    property real coverageOpacity: isCovered ? 0 : 1
    Behavior on coverageOpacity { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }

    implicitWidth: isRing ? ringSize : screenWidth
    implicitHeight: isRing ? ringSize : shaderStyle ? bandHeight : barsHeight
    x: isRing ? targetX : 0
    y: isRing ? targetY : screenHeight - implicitHeight
    draggable: isRing && placementStrategy === "free" && !Config.options.background.widgetsLocked
    hoverEnabled: isRing
    visibleWhenLocked: configEntry?.showWhenLocked ?? false

    function restoreXYBinding() {
        root.x = Qt.binding(() => root.isRing ? root.targetX : 0);
        root.y = Qt.binding(() => root.isRing ? root.targetY : root.screenHeight - root.implicitHeight);
        root.z = Qt.binding(() => root.targetZ);
    }

    // --- Points ---
    readonly property list<real> points: GlobalStates.visualizerPoints
    readonly property color primaryColor: Appearance.colors.colPrimary

    // --- Cover palette (works for ALL modes now) ---
    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property string artUrl: activePlayer?.trackArtUrl ?? ""
    readonly property bool needsCover: useCoverColors || isRing
    readonly property string artFilePath: `${Directories.coverArt}/${Qt.md5(artUrl)}`
    property bool coverDownloaded: false
    readonly property string coverUrl: {
        if (!needsCover || artUrl.length === 0) return ""
        if (artUrl.startsWith("file://")) return artUrl
        return coverDownloaded ? Qt.resolvedUrl(artFilePath) : ""
    }

    onArtFilePathChanged: fetchCover()
    onNeedsCoverChanged: fetchCover()
    function fetchCover() {
        coverDownloaded = false
        if (!needsCover || artUrl.length === 0 || artUrl.startsWith("file://")) return
        coverDownloader.command = ["bash", "-c", '[ -f "$1" ] || curl -sSL "$2" -o "$1"', "_", artFilePath, artUrl]
        coverDownloader.running = true
    }
    Process {
        id: coverDownloader
        onExited: root.coverDownloaded = true
    }
    ColorQuantizer {
        id: coverQuantizer
        source: root.useCoverColors ? root.coverUrl : ""
        depth: 2
        rescaleSize: 64
    }

    // --- Derived cover color for canvas modes ---
    readonly property color coverColor: {
        if (!useCoverColors) return primaryColor
        const colors = Array.from(coverQuantizer.colors).sort((a, b) => b.hslSaturation - a.hslSaturation)
        if (colors.length < 1) return primaryColor
        const c = colors[0]
        return Qt.hsla(Math.max(c.hslHue, 0), Math.max(c.hslSaturation, 0.45), Math.min(Math.max(c.hslLightness, 0.55), 0.75), 1)
    }

    readonly property color canvasColor: useCoverColors ? coverColor : primaryColor
    readonly property color canvasAccentColor: {
        if (!useCoverColors) return Appearance.colors.colPrimaryContainer
        const colors = Array.from(coverQuantizer.colors).sort((a, b) => b.hslSaturation - a.hslSaturation)
        if (colors.length < 2) return Appearance.colors.colPrimaryContainer
        const c = colors[1]
        return Qt.hsla(Math.max(c.hslHue, 0), Math.max(c.hslSaturation, 0.35), Math.min(Math.max(c.hslLightness, 0.6), 0.85), 1)
    }

    readonly property color waveFillColor: Qt.rgba(canvasColor.r, canvasColor.g, canvasColor.b, root.waveFillOpacity)

    // --- Shader palettes ---
    readonly property var themePalette: {
        const c = Appearance.m3colors
        switch (style) {
        case "aurora": return [c.m3primary, c.m3tertiary, c.m3secondary]
        case "ring": return [c.m3primary, c.m3tertiary, c.m3primaryContainer]
        case "dots": return [c.m3onBackground, c.m3primary, c.m3error]
        default: return [c.m3primary, c.m3primaryContainer, c.m3tertiary]
        }
    }
    readonly property var coverPalette: {
        const colors = Array.from(coverQuantizer.colors).sort((a, b) => b.hslSaturation - a.hslSaturation)
        if (colors.length < 3) return null
        const lifted = colors.map(c => Qt.hsla(Math.max(c.hslHue, 0), Math.max(c.hslSaturation, 0.45), Math.min(Math.max(c.hslLightness, 0.62), 0.85), 1))
        return style === "dots" ? [themePalette[0], lifted[0], lifted[1]] : lifted.slice(0, 3)
    }
    readonly property var visualizerColors: (useCoverColors && coverPalette) ? coverPalette : themePalette

    // --- Canvas render state ---
    property var renderedPoints: []
    property var pixelHeights: []
    property real activityOpacity: 0
    Behavior on activityOpacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }

    readonly property bool effectsEnabled: enableAnimations.value ?? true

    // Bar counts per mode
    readonly property int defaultBarCount: Math.max(1, Math.floor(screenWidth / 12))
    readonly property int canvasBarCount: Math.max(1, Math.floor(screenWidth / (root.targetBarWidth + root.barSpacing)))
    // Wave uses same point count as bars — bezier curves smooth the fewer points
    readonly property int wavePointCount: Math.max(2, canvasBarCount)
    readonly property real defaultMaxBarHeight: Math.min(root.height, 220)
    readonly property real defaultBarWidth: 4
    readonly property real defaultBarSpacing: 8
    readonly property real canvasExactWidth: (screenWidth - (root.barSpacing * (canvasBarCount - 1))) / canvasBarCount

    // Map raw points to count with mono + dataSmoothing
    function mapPoints(raw, count, useMono) {
        if (!raw || raw.length === 0) return Array(count).fill(0)
        let mapped = new Array(count)
        let rawLenM1 = raw.length - 1
        for (let i = 0; i < count; i++) {
            let progress = i / (count - 1 || 1)
            let relPos = useMono ? (Math.abs(progress - 0.5) * 2) * rawLenM1 : progress * rawLenM1
            let low = Math.floor(relPos), high = Math.ceil(relPos), mix = relPos - low
            mapped[i] = (raw[low] * (1 - mix)) + (raw[high] * (high < raw.length ? mix : 0))
        }
        if (dataSmoothing <= 0) return mapped
        let smoothed = new Array(count)
        let sW = dataSmoothing * 0.25
        for (let j = 0; j < count; j++) {
            let p = mapped[Math.max(0, j - 1)]
            let n = mapped[Math.min(count - 1, j + 1)]
            smoothed[j] = (p * sW) + (mapped[j] * (1.0 - 2 * sW)) + (n * sW)
        }
        return smoothed
    }

    function getTargetPoints() {
        let count, useMono
        switch (style) {
        case "default": count = defaultBarCount; useMono = false; break
        case "bars": count = canvasBarCount; useMono = mono; break
        case "wave": count = wavePointCount; useMono = mono; break
        default: return []
        }
        return mapPoints(points, count, useMono)
    }

    function toPixels(targetPoints) {
        let h = root.height
        return targetPoints.map(p => (p / 1000) * h)
    }

    // --- Engine (shader modes) ---
    VisualizerEngine {
        id: levelEngine
        active: root.shaderStyle && !root.isCovered
        sensitivity: root.configEntry.sensitivity ?? 1
    }

    // --- Default mode: centered row bars ---
    Row {
        id: defaultRow
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: root.defaultBarSpacing
        opacity: 0
        visible: opacity > 0

        Repeater {
            model: root.defaultBarCount
            Rectangle {
                required property int index
                width: root.defaultBarWidth
                height: Math.max(2, (root.renderedPoints[index] ?? 0) / 1000 * root.defaultMaxBarHeight)
                anchors.bottom: parent.bottom
                topLeftRadius: width / 2
                topRightRadius: width / 2
                bottomLeftRadius: 0
                bottomRightRadius: 0

                property real intensity: (root.renderedPoints[index] ?? 0) / 1000
                color: Qt.rgba(
                    root.canvasColor.r * intensity + root.canvasAccentColor.r * (1 - intensity),
                    root.canvasColor.g * intensity + root.canvasAccentColor.g * (1 - intensity),
                    root.canvasColor.b * intensity + root.canvasAccentColor.b * (1 - intensity),
                    1
                )
            }
        }
    }

    // --- Bars mode: fill width ---
    Row {
        id: canvasBarsRow
        anchors.fill: parent
        spacing: root.barSpacing
        opacity: 0
        visible: opacity > 0

        Repeater {
            model: root.canvasBarCount
            Rectangle {
                required property int index
                width: root.canvasExactWidth
                height: Math.max(2, (root.renderedPoints[index] ?? 0) / 1000 * root.height)
                anchors.bottom: parent.bottom
                topLeftRadius: width * root.barRounding
                topRightRadius: width * root.barRounding
                bottomLeftRadius: 0
                bottomRightRadius: 0
                color: root.canvasColor
                border.width: root.waveBorderWidth
                border.color: root.waveFillColor
            }
        }
    }

    // --- Wave mode: canvas bezier ---
    Canvas {
        id: waveCanvas
        anchors.fill: parent
        opacity: 0
        visible: opacity > 0

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d")
            var ph = root.pixelHeights
            if (!ph || ph.length < 2) return

            ctx.reset()
            let w = width, h = height
            if (w <= 0 || h <= 0) return

            let step = w / (ph.length - 1)
            ctx.beginPath()
            ctx.moveTo(0, h)
            ctx.lineTo(0, h - ph[0])
            for (let i = 0; i < ph.length - 1; i++) {
                let x1 = i * step, x2 = (i + 1) * step
                let y1 = h - ph[i], y2 = h - ph[i + 1]
                let cx = (x1 + x2) / 2
                ctx.bezierCurveTo(cx, y1, cx, y2, x2, y2)
            }
            ctx.lineTo(w, h)
            ctx.closePath()
            ctx.fillStyle = root.waveFillColor
            ctx.fill()

            if (root.waveBorderWidth > 0) {
                ctx.beginPath()
                ctx.moveTo(0, h - ph[0])
                for (let i = 0; i < ph.length - 1; i++) {
                    let x1 = i * step, x2 = (i + 1) * step
                    let y1 = h - ph[i], y2 = h - ph[i + 1]
                    let cx = (x1 + x2) / 2
                    ctx.bezierCurveTo(cx, y1, cx, y2, x2, y2)
                }
                ctx.strokeStyle = root.canvasColor
                ctx.lineWidth = root.waveBorderWidth
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                ctx.stroke()
            }
        }
    }

    // --- Unified render loop for ALL canvas modes ---
    FrameAnimation {
        id: canvasRenderLoop
        running: !root.isCovered && !root.shaderStyle && (root.activityOpacity > 0 || canvasSilenceTimer.running)
        onTriggered: {
            let target = root.getTargetPoints()
            let targetPixels = root.toPixels(target)
            let current = root.renderedPoints
            let h = root.height
            let count = target.length

            if (count === 0) return

            if (current.length !== count) {
                root.renderedPoints = target.slice()
                root.pixelHeights = targetPixels.slice()
                waveCanvas.requestPaint()
                return
            }

            let lerpFactor = Math.min(1.0, (frameTime * 1000) / Math.max(1, root.smoothing * 1000))
            let nextPoints = new Array(count)
            let nextPixels = new Array(count)
            for (let i = 0; i < count; i++) {
                let val = current[i] + (target[i] - current[i]) * lerpFactor
                nextPoints[i] = val
                nextPixels[i] = (val / 1000) * h
            }
            root.renderedPoints = nextPoints
            root.pixelHeights = nextPixels
            waveCanvas.requestPaint()
        }
    }

    Timer {
        id: canvasSilenceTimer
        interval: 1000
        onTriggered: root.activityOpacity = 0
    }

    onPointsChanged: {
        if (points.some(p => p > 0)) {
            root.activityOpacity = 1.0
            canvasSilenceTimer.restart()
        }
    }

    // --- Shader loader ---
    Loader {
        anchors.fill: parent
        active: root.shaderStyle && root.activityOpacity > 0
        opacity: root.coverageOpacity
        Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }
        sourceComponent: Item {
            Item {
                id: coverItem
                width: 512
                height: 512
                visible: root.isRing
                Image {
                    id: coverImage
                    anchors.fill: parent
                    source: root.isRing ? root.coverUrl : ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(512, 512)
                    asynchronous: true
                    smooth: true
                }
            }
            ShaderEffectSource {
                id: coverTexture
                sourceItem: coverItem
                hideSource: true
                visible: false
            }

            VisualizerShader {
                anchors.fill: parent
                style: root.style
                engine: levelEngine
                color1: root.visualizerColors[0]
                color2: root.visualizerColors[1]
                color3: root.visualizerColors[2]
                cover: coverTexture
                hasCover: coverImage.status === Image.Ready ? 1 : 0
            }
        }
    }

    // --- Ring resize ---
    ResizeHandler {
        anchorItem: root
        hoverActive: root.containsMouse
        locked: Config.options.background.widgetsLocked || !root.isRing
        currentWidth: root.ringSize
        resizeMode: "diagonal"
        onResized: newValue => ringSizeOverride = Math.round(Math.min(Math.max(newValue, 200), 900))
        onResizeFinished: {
            if (ringSizeOverride > 0) root.configEntry.ringSize = ringSizeOverride
            ringSizeOverride = -1
        }
    }

    // --- State machine ---
    states: [
        State {
            name: "canvasDefault"
            when: style === "default"
            PropertyChanges { target: defaultRow; opacity: canvasOpacity * activityOpacity * coverageOpacity * (effectsEnabled ? 1 : 0) }
        },
        State {
            name: "canvasBars"
            when: style === "bars"
            PropertyChanges { target: canvasBarsRow; opacity: canvasOpacity * activityOpacity * coverageOpacity * (effectsEnabled ? 1 : 0) }
        },
        State {
            name: "canvasWave"
            when: style === "wave"
            PropertyChanges { target: waveCanvas; opacity: canvasOpacity * activityOpacity * coverageOpacity * (effectsEnabled ? 1 : 0) }
        }
    ]

    transitions: Transition {
        NumberAnimation { properties: "opacity"; duration: 400; easing.type: Easing.InOutQuad }
    }

    HyprlandConfigOption {
        id: enableAnimations
        key: "animations:enabled"
    }
}
