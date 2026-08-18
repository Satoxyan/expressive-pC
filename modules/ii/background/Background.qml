pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.common.functions as CF
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

import qs.modules.ii.background.widgets
import qs.modules.ii.background.widgets.clock
import qs.modules.ii.background.widgets.weather
import qs.modules.ii.background.widgets.media
import qs.modules.ii.background.widgets.images
import qs.modules.ii.background.widgets.resources
import qs.modules.ii.background.widgets.visualizer
import qs.modules.ii.background.widgets.calendar
import qs.modules.ii.background.widgets.worldclock
import qs.modules.ii.background.widgets.usercard
import qs.modules.ii.background.widgets.notes

Variants {
    id: root
    model: Quickshell.screens

    function getShapeFromName(name) {
        switch (name) {
            case "Circle":        return MaterialShape.Shape.Circle
            case "Square":        return MaterialShape.Shape.Square
            case "Slanted":       return MaterialShape.Shape.Slanted
            case "Arch":          return MaterialShape.Shape.Arch
            case "Fan":           return MaterialShape.Shape.Fan
            case "Arrow":         return MaterialShape.Shape.Arrow
            case "SemiCircle":    return MaterialShape.Shape.SemiCircle
            case "Oval":          return MaterialShape.Shape.Oval
            case "Pill":          return MaterialShape.Shape.Pill
            case "Triangle":      return MaterialShape.Shape.Triangle
            case "Diamond":       return MaterialShape.Shape.Diamond
            case "ClamShell":     return MaterialShape.Shape.ClamShell
            case "Pentagon":      return MaterialShape.Shape.Pentagon
            case "Gem":           return MaterialShape.Shape.Gem
            case "Sunny":         return MaterialShape.Shape.Sunny
            case "VerySunny":     return MaterialShape.Shape.VerySunny
            case "Cookie4Sided":  return MaterialShape.Shape.Cookie4Sided
            case "Cookie6Sided":  return MaterialShape.Shape.Cookie6Sided
            case "Cookie7Sided":  return MaterialShape.Shape.Cookie7Sided
            case "Cookie9Sided":  return MaterialShape.Shape.Cookie9Sided
            case "Cookie12Sided": return MaterialShape.Shape.Cookie12Sided
            case "Ghostish":      return MaterialShape.Shape.Ghostish
            case "Clover4Leaf":   return MaterialShape.Shape.Clover4Leaf
            case "Clover8Leaf":   return MaterialShape.Shape.Clover8Leaf
            case "Burst":         return MaterialShape.Shape.Burst
            case "SoftBurst":     return MaterialShape.Shape.SoftBurst
            case "Boom":          return MaterialShape.Shape.Boom
            case "SoftBoom":      return MaterialShape.Shape.SoftBoom
            case "Flower":        return MaterialShape.Shape.Flower
            case "Puffy":         return MaterialShape.Shape.Puffy
            case "PuffyDiamond":  return MaterialShape.Shape.PuffyDiamond
            case "PixelCircle":   return MaterialShape.Shape.PixelCircle
            case "PixelTriangle": return MaterialShape.Shape.PixelTriangle
            case "Bun":           return MaterialShape.Shape.Bun
            case "Heart":         return MaterialShape.Shape.Heart
            default:              return MaterialShape.Shape.Cookie7Sided
        }
    }

    function getColorFromName(name) {
        switch (name) {
            case "primary":            return Appearance.colors.colPrimary
            case "secondary":          return Appearance.colors.colSecondary
            case "tertiary":           return Appearance.colors.colTertiary
            case "primaryContainer":   return Appearance.colors.colPrimaryContainer
            case "secondaryContainer": return Appearance.colors.colSecondaryContainer
            case "tertiaryContainer":  return Appearance.colors.colTertiaryContainer
            case "layer0":             return Appearance.colors.colLayer0
            case "layer1":             return Appearance.colors.colLayer1
            default:                  return Appearance.colors.colPrimaryContainer
        }
    }

    PanelWindow {
        id: bgRoot

        required property var modelData
        property string currentWallpaperSource: Config.options.background.wallpaperPath
        property string previousWallpaperSource: Config.options.background.wallpaperPath
        property bool videoRevealed: false

        //centered Wallpaper
        property bool centeredWallpaperEnabled: Config.options.background.centeredWallpaper
        property bool centeredOnlyWhenLocked: Config.options.background.centeredWallpaperOnlyWhenLocked
        property int centeredWallpaperShape: getShapeFromName(Config.options.background.centeredWallpaperShape)
        property int centeredWallpaperSize: Config.options.background.centeredWallpaperSize
        property color centeredWallpaperColor: root.getColorFromName(Config.options.background.centeredWallpaperColor)
        onCenteredOnlyWhenLockedChanged: {
            bgRoot.setCenteredProgress(GlobalStates.screenLocked ? 0 : (bgRoot.centeredOnlyWhenLocked ? 1 : 0))
        }

        // Size the shape (with the wallpaper inside) must reach so its masked
        // area fully covers the screen; the shape then leaves the screen.
        // The shape item is rendered at this fixed size and only transformed
        // (scaled) during the transition, so the 2D canvas + mask are painted
        // once instead of re-rasterized every frame at a changing size.
        property real centeredShapeMax: Math.max(1, Math.ceil(
            Math.hypot(bgRoot.screen.width / 2, bgRoot.screen.height / 2)
            / bgRoot.centeredShapeMinBoundaryRadius(bgRoot.centeredWallpaperShape) * 1.02))
        // Pixel size the shape item/layer is rendered at. Kept at roughly the
        // screen diagonal instead of centeredShapeMax (which can be 2.5x that)
        // so the layer + OpacityMask + 2D canvases are ~6x cheaper per frame;
        // the scale below compensates, so the silhouette and the picture inside
        // stay identical (edges soften only while the shape outgrows the layer).
        property real centeredShapeRenderSize: Math.max(1, Math.ceil(
            Math.hypot(bgRoot.screen.width, bgRoot.screen.height)))

        // Smallest normalized distance from the polygon's center to its boundary
        // for each supported shape, precomputed by sampling the geometry.
        // Used to derive the size at which the shape covers the whole screen
        // (every screen point is within the cover radius of the center, and the
        // shape contains that disk). A static table keeps the result exact and
        // independent of when the shape item has finished resolving.
        function centeredShapeMinBoundaryRadius(shape) {
            switch (shape) {
                case MaterialShape.Shape.Circle:        return 0.4898
                case MaterialShape.Shape.Square:        return 0.5000
                case MaterialShape.Shape.Slanted:       return 0.4610
                case MaterialShape.Shape.Arch:          return 0.5000
                case MaterialShape.Shape.Fan:           return 0.3710
                case MaterialShape.Shape.Arrow:         return 0.2992
                case MaterialShape.Shape.SemiCircle:    return 0.3125
                case MaterialShape.Shape.Oval:          return 0.3697
                case MaterialShape.Shape.Pill:          return 0.4157
                case MaterialShape.Shape.Triangle:      return 0.2665
                case MaterialShape.Shape.Diamond:       return 0.3593
                case MaterialShape.Shape.ClamShell:     return 0.3373
                case MaterialShape.Shape.Pentagon:      return 0.3999
                case MaterialShape.Shape.Gem:           return 0.4498
                case MaterialShape.Shape.Sunny:         return 0.4185
                case MaterialShape.Shape.VerySunny:     return 0.3818
                case MaterialShape.Shape.Cookie4Sided:  return 0.3841
                case MaterialShape.Shape.Cookie6Sided:  return 0.4312
                case MaterialShape.Shape.Cookie7Sided:  return 0.4202
                case MaterialShape.Shape.Cookie9Sided:  return 0.4370
                case MaterialShape.Shape.Cookie12Sided: return 0.4463
                case MaterialShape.Shape.Ghostish:      return 0.3637
                case MaterialShape.Shape.Clover4Leaf:   return 0.4019
                case MaterialShape.Shape.Clover8Leaf:   return 0.4287
                case MaterialShape.Shape.Burst:         return 0.3562
                case MaterialShape.Shape.SoftBurst:     return 0.3873
                case MaterialShape.Shape.Boom:          return 0.2175
                case MaterialShape.Shape.SoftBoom:      return 0.2385
                case MaterialShape.Shape.Flower:        return 0.3396
                case MaterialShape.Shape.Puffy:         return 0.3297
                case MaterialShape.Shape.PuffyDiamond:  return 0.3487
                case MaterialShape.Shape.PixelCircle:   return 0.4723
                case MaterialShape.Shape.PixelTriangle: return 0.2352
                case MaterialShape.Shape.Bun:           return 0.2960
                case MaterialShape.Shape.Heart:         return 0.2141
                default:                                return 0.4202
            }
        }

        // 0 = locked (wallpaper rests centered inside the shape), 1 = unlocked
        // (wallpaper fills the screen). This is the only animated driver: the
        // mappings below derive every size/opacity from it, so no secondary
        // animations fight and the transition cannot blink.
        // Driven by explicit assignment (onCompleted + lock-state handler)
        // rather than a binding, so the Behavior never animates the initial
        // set (which would play a grow-in effect on every startup while the
        // config asynchronously loads). The Behavior stays off until both the
        // config is loaded and the initial value has been synced.
        property bool centeredAnimationReady: false
        property bool centeredAnimating: false
        property real centeredProgress: 0

        // Unlock is slower (0.8s) than lock (0.65s); the helper picks the
        // animation by direction. It also skips the animation while the config
        // is still loading, so the initial set never plays a grow-in on startup.
        function setCenteredProgress(value) {
            if (!bgRoot.centeredWallpaperEnabled || !bgRoot.centeredAnimationReady || !Config.ready) {
                bgRoot.centeredProgress = value
                return
            }
            if (value === bgRoot.centeredProgress) return
            const anim = value > bgRoot.centeredProgress ? centeredUnlockAnim : centeredLockAnim
            anim.to = value
            anim.restart()
        }
        NumberAnimation {
            id: centeredLockAnim
            target: bgRoot
            property: "centeredProgress"
            duration: 650
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
            onRunningChanged: bgRoot.centeredAnimating = running
        }
        NumberAnimation {
            id: centeredUnlockAnim
            target: bgRoot
            property: "centeredProgress"
            duration: 800
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
            onRunningChanged: bgRoot.centeredAnimating = running
        }

        // The centered shape is actually shown on screen only while the
        // progress has not reached the desktop end (locked state + transitions).
        // The wallpaper-change shader transition is hidden only then, so it
        // keeps working normally on the desktop.
        // Note: "animating" must be part of the condition because the easing
        // overshoots above 1 mid-animation; gating on progress alone would
        // hide/show/hide the shape during the overshoot tail (layer rebuild
        // stutter at the end of the unlock).
        readonly property bool centeredShapeActive: bgRoot.centeredWallpaperEnabled
            && (bgRoot.centeredProgress < 1 || bgRoot.centeredAnimating)

        // The full-screen wallpaper must stay rendered while it is visible
        // (fading in/out, desktop); only turn it off once fully transparent.
        readonly property bool centeredHidesFullWallpaper: bgRoot.centeredWallpaperEnabled
            && bgRoot.centeredFullWallpaperOpacity() <= 0

        // Fraction of the transition used for the tiny handover at the desktop
        // end: the shape (covering the whole screen) hands off to the full
        // wallpaper image while the solid background fades away underneath.
        // Both are hidden behind the opaque shape for almost the whole
        // transition, so the handover only ever shows if a shape silhouette
        // does not yet cover a screen corner — the fade keeps that smooth too.
        property real centeredFade: 0.05

        // Size of the centered shape: grows from centeredWallpaperSize to
        // centeredShapeMax as the progress goes 0 (locked) -> 1 (unlocked).
        function centeredShapeSize() {
            if (!bgRoot.centeredWallpaperEnabled) return 1
            return bgRoot.centeredWallpaperSize
                + bgRoot.centeredProgress * (bgRoot.centeredShapeMax - bgRoot.centeredWallpaperSize)
        }
        // Zoom level of the wallpaper inside the shape. The shape item is
        // rendered at a fixed size (centeredShapeRenderSize) and scaled, so the
        // picture inside must apply the inverse zoom to stay exactly as before
        // on screen: it fills the shape while the shape is smaller than the
        // screen, then stops growing once it would cover the whole screen.
        // Scaling relative to the actual item size keeps the visible wallpaper
        // framing identical regardless of the render size.
        // A small overscan (1.08) keeps the wallpaper's own edge behind the
        // shape tips during the click pulse (which grows the shape to 1.06x);
        // it eases out as the shape approaches full screen so the lock/unlock
        // handover to the full wallpaper stays unzoomed.
        function centeredImageScale() {
            if (!bgRoot.centeredWallpaperEnabled) return 1
            const minDim = Math.min(bgRoot.screen.width, bgRoot.screen.height)
            const size = bgRoot.centeredShapeSize()
            const overscan = size >= minDim ? 1
                : 1.08 - 0.08 * (size - bgRoot.centeredWallpaperSize) / (minDim - bgRoot.centeredWallpaperSize)
            return overscan * bgRoot.centeredShapeRenderSize
                / Math.max(size, minDim)
        }
        function centeredFullWallpaperOpacity() {
            if (!bgRoot.centeredWallpaperEnabled) return 1
            return Math.max(0, Math.min(1,
                (bgRoot.centeredProgress - (1 - bgRoot.centeredFade)) / bgRoot.centeredFade))
        }
        function centeredBgOpacity() {
            if (!bgRoot.centeredWallpaperEnabled) return 0
            return Math.max(0, Math.min(1, (1 - bgRoot.centeredProgress) / bgRoot.centeredFade))
        }

        property var shaderList: ["circlePit", "circleSelect", "magic", "Doom", "Peel", "transition", "pixelate", "stripes", "crt", "dissolve", "glitch", "ripple", "shatter"]
        property string currentShader: "pixelate"
        property string wallpaperAnimation: Config.options.background.wallpaperAnimation ?? "random"

        property list<HyprlandWorkspace> workspacesForMonitor: Hyprland.workspaces.values.filter(workspace => workspace.monitor && workspace.monitor.name == monitor.name)
        property var activeWorkspaceWithFullscreen: workspacesForMonitor.filter(workspace => ((workspace.toplevels.values.filter(window => window.wayland?.fullscreen)[0] != undefined) && workspace.active))[0]
        visible: GlobalStates.screenLocked || (!(activeWorkspaceWithFullscreen != undefined)) || !Config?.options.background.hideWhenFullscreen

        readonly property bool visualizerHidden: {
            if (GlobalStates.screenLocked) return false;
            const viz = Config.options.background.widgets.visualizer;
            if (!(viz.hideWhenCovered ?? true) && !(viz.hideWhenFullscreen ?? true)) return false;

            const activeWs = bgRoot.monitor?.activeWorkspace?.id;
            if (activeWs == null) return false;

            let coveringCount = 0;
            let hasFullscreen = false;
            HyprlandData.windowList.forEach(win => {
                const winWsId = win.workspace?.id ?? win.workspace;
                if (win.monitor != bgRoot.monitor?.id || winWsId != activeWs) return;
                const isMax = (win.maximized || win.wayland?.maximized);
                const isFS = (win.fullscreen || win.wayland?.fullscreen);
                if (win.floating === false || isMax || isFS) coveringCount++;
                if (isFS) hasFullscreen = true;
            });
            if ((viz.hideWhenCovered ?? true) && coveringCount > 0) return true;
            if ((viz.hideWhenFullscreen ?? true) && hasFullscreen) return true;
            return false;
        }

        property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)

        property string effectiveWallpaperPath: {
            if (GlobalStates.screenLocked && Config.options.background.lockWall !== "")
                return Config.options.background.lockWall;
            return Wallpapers.previewPath || Wallpapers.confirmedPath || Config.options.background.wallpaperPath;
        }

        property bool wallpaperIsVideo: bgRoot.effectiveWallpaperPath.endsWith(".mp4") || bgRoot.effectiveWallpaperPath.endsWith(".webm") || bgRoot.effectiveWallpaperPath.endsWith(".mkv") || bgRoot.effectiveWallpaperPath.endsWith(".avi") || bgRoot.effectiveWallpaperPath.endsWith(".mov")
        property string wallpaperPath: wallpaperIsVideo ? Config.options.background.thumbnailPath : bgRoot.effectiveWallpaperPath
        property bool wallpaperSafetyTriggered: {
            const enabled = Config.options.workSafety.enable.wallpaper;
            const sensitiveWallpaper = (CF.StringUtils.stringListContainsSubstring(wallpaperPath.toLowerCase(), Config.options.workSafety.triggerCondition.fileKeywords));
            const sensitiveNetwork = (CF.StringUtils.stringListContainsSubstring(Network.networkName.toLowerCase(), Config.options.workSafety.triggerCondition.networkNameKeywords));
            return enabled && sensitiveWallpaper && sensitiveNetwork;
        }

        property bool shouldBlur: (GlobalStates.screenLocked && Config.options.lock.blur.enable)
        property color dominantColor: Appearance.colors.colPrimary
        property bool dominantColorIsDark: dominantColor.hslLightness < 0.5
        property color colText: {
            if (wallpaperSafetyTriggered)
                return CF.ColorUtils.mix(Appearance.colors.colOnLayer0, Appearance.colors.colPrimary, 0.75);
            return (GlobalStates.screenLocked && shouldBlur) ? Appearance.colors.colOnLayer0 : CF.ColorUtils.colorWithLightness(Appearance.colors.colPrimary, (dominantColorIsDark ? 0.8 : 0.12));
        }
        Behavior on colText {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        property real transitionProgress: 1.0

        screen: modelData
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: (GlobalStates.screenLocked && !scaleAnim.running) ? WlrLayer.Overlay : WlrLayer.Bottom
        WlrLayershell.namespace: "quickshell:background"
        WlrLayershell.keyboardFocus: GlobalStates.desktopWidgetKeyboardFocus
            ? WlrKeyboardFocus.OnDemand
            : WlrKeyboardFocus.None
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: {
            if (!bgRoot.wallpaperSafetyTriggered || bgRoot.wallpaperIsVideo)
                return "transparent";
            return CF.ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colPrimary, 0.75);
        }
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        Component.onCompleted: {
            bgRoot.setCenteredProgress(GlobalStates.screenLocked ? 0 : (bgRoot.centeredOnlyWhenLocked ? 1 : 0))
            if (Config.ready)
                bgRoot.centeredAnimationReady = true
            previousWallpaper.source = ""
            wallpaper.source = bgRoot.wallpaperSafetyTriggered ? "" : bgRoot.wallpaperPath
            bgRoot.currentWallpaperSource = bgRoot.wallpaperPath
            bgRoot.previousWallpaperSource = ""
            bgRoot.transitionProgress = 1.0
            if (bgRoot.wallpaperAnimation !== "") {
                bgRoot.currentShader = bgRoot.wallpaperAnimation === "random"
                    ? bgRoot.shaderList[Math.floor(Math.random() * bgRoot.shaderList.length)]
                    : bgRoot.wallpaperAnimation
            }
            bgRoot.videoRevealed = bgRoot.wallpaperIsVideo
        }

        onWallpaperPathChanged: {
            bgRoot.videoRevealed = false
            if (wallpaperSafetyTriggered) {
                previousWallpaper.source = ""
                wallpaper.source = ""
                bgRoot.transitionProgress = 1.0
                return
            }
            if (bgRoot.wallpaperAnimation === "") {
                wallpaper.source = wallpaperPath
                bgRoot.currentWallpaperSource = wallpaperPath
                if (!bgRoot.wallpaperIsVideo) return
                bgRoot.videoRevealed = true
                return
            }

            previousWallpaper.source = bgRoot.currentWallpaperSource
            wallpaper.source = wallpaperPath
            bgRoot.currentWallpaperSource = wallpaperPath
            if (bgRoot.wallpaperAnimation === "random") {
                bgRoot.currentShader = bgRoot.shaderList[Math.floor(Math.random() * bgRoot.shaderList.length)]
            } else {
                bgRoot.currentShader = bgRoot.wallpaperAnimation
            }
            bgRoot.transitionProgress = 0.0
        }

        NumberAnimation {
            id: transitionAnim
            target: bgRoot
            property: "transitionProgress"
            from: 0.0
            to: 1.0
            duration: 1200
            easing.type: Easing.InOutCubic
            onFinished: {
                previousWallpaper.source = ""
                bgRoot.previousWallpaperSource = ""
                bgRoot.transitionProgress = 1.0
                bgRoot.videoRevealed = bgRoot.wallpaperIsVideo
            }
        }

        Timer {
            id: wallpaperChangeTimer
            interval: Config.options.wallpaperSelector.changeInterval
            running: Config.options.wallpaperSelector.changeInterval > 0
            repeat: true
            onTriggered: {
                if (Wallpapers.folderModel.count > 0) {
                    Wallpapers.randomFromCurrentFolder()
                }
            }
        }

        Connections {
            target: Config
            function onReadyChanged() {
                if (!Config.ready) return
                bgRoot.setCenteredProgress(GlobalStates.screenLocked ? 0 : (bgRoot.centeredOnlyWhenLocked ? 1 : 0))
                bgRoot.centeredAnimationReady = true
            }
        }

        Connections {
            target: GlobalStates
            function onScreenLockedChanged() {
                bgRoot.setCenteredProgress(GlobalStates.screenLocked ? 0 : (bgRoot.centeredOnlyWhenLocked ? 1 : 0))
                if (!GlobalStates.screenLocked) {
                    bgRoot.videoRevealed = bgRoot.wallpaperIsVideo
                }
            }
        }

        Item {
            anchors.fill: parent

            Image {
                id: previousWallpaper
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                cache: true
                smooth: true
                asynchronous: true
                layer.enabled: true
                visible: false
            }

            StyledImage {
                id: wallpaper
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                cache: true
                smooth: true
                asynchronous: true
                layer.enabled: true
                visible: !blurLoader.active && !bgRoot.videoRevealed
                    && (bgRoot.wallpaperAnimation === "" || bgRoot.transitionProgress >= 1.0)
                    && !bgRoot.centeredHidesFullWallpaper
                opacity: bgRoot.centeredFullWallpaperOpacity()
                onStatusChanged: {
                    if (status === Image.Ready && bgRoot.transitionProgress === 0.0) {
                        transitionAnim.restart()
                    }
                }
            }

            ShaderEffect {
                id: transitionEffect
                anchors.fill: parent
                visible: !blurLoader.active && bgRoot.wallpaperAnimation !== "" && !bgRoot.centeredShapeActive && !bgRoot.videoRevealed
                    && bgRoot.transitionProgress < 1.0

                property var fromImage: previousWallpaper
                property var toImage: wallpaper
                property var source1: previousWallpaper
                property var source2: wallpaper
                property real time: 0.0
                property real progress: bgRoot.transitionProgress
                property real aspectX: width / height
                property real aspectY: 1.0
                property vector2d aspectRatio: Qt.vector2d(aspectX, aspectY)
                property vector2d origin: Qt.vector2d(0.5, 0.5)

                fragmentShader: bgRoot.wallpaperAnimation !== ""
                    ? Qt.resolvedUrl(`shaders/${bgRoot.currentShader}.frag.qsb`)
                    : ""

                Timer {
                    interval: 16
                    repeat: true
                    running: transitionEffect.visible
                    onTriggered: transitionEffect.time += interval / 1000.0
                }
                onVisibleChanged: if (!visible) transitionEffect.time = 0.0
            }

            Loader {
                id: blurLoader
                // The blur is invisible while the centered wallpaper is active
                // (opaque shape + solid background cover it), so skip it to
                // save the expensive multi-sample blur pass on lock/unlock.
                active: Config.options.lock.blur.enable && !bgRoot.centeredWallpaperEnabled
                    && (GlobalStates.screenLocked || scaleAnim.running)
                anchors.fill: parent
                scale: GlobalStates.screenLocked ? Config.options.lock.blur.extraZoom : 1
                layer.enabled: active
                layer.textureMirroring: ShaderEffect.NoMirroring
                Behavior on scale {
                    NumberAnimation {
                        id: scaleAnim
                        duration: 400
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
                    }
                }
                sourceComponent: GaussianBlur {
                    source: bgRoot.wallpaperAnimation === "" || bgRoot.transitionProgress >= 1.0 ? wallpaper : transitionEffect
                    radius: GlobalStates.screenLocked ? Config.options.lock.blur.radius : 0
                    samples: radius * 2 + 1
                    cached: true
                    Rectangle {
                        opacity: GlobalStates.screenLocked ? 1 : 0
                        anchors.fill: parent
                        color: CF.ColorUtils.transparentize(Appearance.colors.colLayer0, 0.7)
                    }
                }
            }

            // Dim overlay - only dims wallpaper, not widgets
            Rectangle {
                anchors.fill: parent
                color: "black"
                opacity: (GlobalStates.screenLocked && Config.options.lock.dim.enable) ? (Config.options.lock.dim.strength / 100) : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: 400
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
                    }
                }
            }

            Rectangle {
                id: centeredWallpaperBg
                anchors.fill: parent
                color: bgRoot.centeredWallpaperColor
                opacity: bgRoot.centeredBgOpacity()
                visible: opacity > 0
            }

            MaterialShape {
                id: centeredWallpaperShapeItem
                anchors.centerIn: parent
                width: bgRoot.centeredShapeRenderSize
                height: bgRoot.centeredShapeRenderSize
                color: bgRoot.centeredWallpaperColor
                shape: bgRoot.centeredWallpaperShape
                transformOrigin: Item.Center
                // Base scale (lock/unlock) multiplied by the click pulse.
                property real shapeZoom: 1
                scale: (bgRoot.centeredShapeSize() / bgRoot.centeredShapeRenderSize) * shapeZoom
                visible: bgRoot.centeredWallpaperEnabled
                    && (bgRoot.centeredProgress < 1 || bgRoot.centeredAnimating)

                // Slow single zoom-in/out on click (0.8s total). The wallpaper inside stays
                // put during the shape pulse (compensated by 1/shapeZoom) and only
                // starts its own zoom 200ms later for a follow-up effect.
                // Guarded by "running" so a rapid click never restarts mid-way.
                SequentialAnimation {
                    id: shapeZoomAnim
                    NumberAnimation { target: centeredWallpaperShapeItem; property: "shapeZoom"; to: 1.06; duration: 300; easing.type: Easing.OutQuad }
                    NumberAnimation { target: centeredWallpaperShapeItem; property: "shapeZoom"; to: 1.0;  duration: 500; easing.type: Easing.InOutQuad }
                }
                SequentialAnimation {
                    id: imageFollowAnim
                    PauseAnimation { duration: 200 }
                    NumberAnimation { target: centeredWallpaperImage; property: "imageZoom"; to: 1.08; duration: 250; easing.type: Easing.OutQuad }
                    NumberAnimation { target: centeredWallpaperImage; property: "imageZoom"; to: 1.0;  duration: 350; easing.type: Easing.InOutQuad }
                }
                function thump() {
                    if (shapeZoomAnim.running || imageFollowAnim.running) return
                    shapeZoomAnim.restart()
                    imageFollowAnim.restart()
                }

                Connections {
                    target: GlobalStates
                    function onCenteredWallpaperThumpRequested() {
                        centeredWallpaperShapeItem.thump()
                    }
                }

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: MaterialShape {
                        width: centeredWallpaperShapeItem.width
                        height: centeredWallpaperShapeItem.height
                        shape: bgRoot.centeredWallpaperShape
                    }
                }

                StyledImage {
                    id: centeredWallpaperImage
                    width: bgRoot.width
                    height: bgRoot.height
                    anchors.centerIn: parent
                    source: bgRoot.wallpaperPath
                    fillMode: Image.PreserveAspectCrop
                    cache: false
                    antialiasing: true
                    sourceSize.width: bgRoot.width
                    sourceSize.height: bgRoot.height
                    // Inverse lock/unlock zoom, multiplied by the delayed pulse.
                    // Dividing by shapeZoom keeps the picture visually still while
                    // the shape zooms, until imageZoom's follow-up kicks in.
                    property real imageZoom: 1
                    scale: bgRoot.centeredImageScale() * (1 / centeredWallpaperShapeItem.shapeZoom) * imageZoom
                }

                MouseArea {
                    anchors.fill: parent
                    z: 1
                    acceptedButtons: Qt.LeftButton
                        onClicked: centeredWallpaperShapeItem.thump()
                }
            }

            DropArea {
                id: wallpaperDropArea
                anchors.fill: parent
                keys: ["text/uri-list"]

                property var currentUrls: []

                onEntered: (drag) => {
                    drag.accepted = drag.hasUrls
                    wallpaperDropArea.currentUrls = drag.hasUrls ? drag.urls : []
                }

                onExited: {
                    wallpaperDropArea.currentUrls = []
                }

                onDropped: (drop) => {
                    if (!drop.hasUrls) {
                        drop.accepted = false
                        wallpaperDropArea.currentUrls = []
                        return
                    }

                    if (drop.urls.length === 1) {
                        const path = CF.FileUtils.trimFileProtocol(decodeURIComponent(drop.urls[0].toString()))
                        const validExt = /\.(png|jpe?g|webp|bmp|gif)$/i.test(path)
                        if (validExt) {
                            Wallpapers.select(path, Appearance.m3colors.darkmode)
                        } else {
                            const globalPos = wallpaperDropArea.mapToGlobal(drop.x, drop.y)
                            DropShelf.show(drop.urls, globalPos.x, globalPos.y)
                        }
                    } else {
                        const globalPos = wallpaperDropArea.mapToGlobal(drop.x, drop.y)
                        DropShelf.show(drop.urls, globalPos.x, globalPos.y)
                    }
                    drop.accept()
                    wallpaperDropArea.currentUrls = []
                }

                Rectangle {
                    id: dropOverlay
                    anchors.fill: parent
                    visible: wallpaperDropArea.containsDrag
                    color: CF.ColorUtils.transparentize(Appearance.colors.colPrimary, 0.6)

                    property bool isSingleImage: wallpaperDropArea.currentUrls.length === 1
                        && /\.(png|jpe?g|webp|bmp|gif)$/i.test(
                            CF.FileUtils.trimFileProtocol(wallpaperDropArea.currentUrls[0].toString())
                        )

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 8
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            text: dropOverlay.isSingleImage ? "wallpaper" : "stacks"
                            iconSize: 64
                            color: Appearance.colors.colOnPrimary
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: dropOverlay.isSingleImage
                                ? Translation.tr("Drop to set as wallpaper")
                                : Translation.tr("Drop to add to shelf")
                            font.pixelSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                }
            }

            WidgetCanvas {
                id: widgetCanvas
                anchors.fill: parent

                transitions: Transition {
                    PropertyAnimation {
                        properties: "width,height"
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                    AnchorAnimation {
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.visualizer.enable
                        && !bgRoot.visualizerHidden
                        && (Config.options.background.screenList.length === 0
                            || Config.options.background.screenList.includes(bgRoot.screen.name))
                    sourceComponent: VisualizerWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.customImage.enable
                        && (Config.options.background.screenList.length === 0
                            || Config.options.background.screenList.includes(bgRoot.screen.name))
                    sourceComponent: CustomImage {
                        screenWidth:        bgRoot.screen.width
                        screenHeight:       bgRoot.screen.height
                        scaledScreenWidth:  bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale:     1
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.calendar.enable
                        && (Config.options.background.screenList.length === 0
                            || Config.options.background.screenList.includes(bgRoot.screen.name))
                    sourceComponent: CalendarWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.weather.enable
                        && (Config.options.background.screenList.length === 0
                            || Config.options.background.screenList.includes(bgRoot.screen.name))
                    sourceComponent: WeatherWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.clock.enable
                        && (GlobalStates.screenLocked
                            || Config.options.background.screenList.length === 0
                            || Config.options.background.screenList.includes(bgRoot.screen.name))
                    sourceComponent: ClockWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                        wallpaperSafetyTriggered: bgRoot.wallpaperSafetyTriggered
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.notes.enable
                        && (Config.options.background.screenList.length === 0
                            || Config.options.background.screenList.includes(bgRoot.screen.name))
                    sourceComponent: NotesWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                    }
                }
                FadeLoader {
                    id: mediaLoader
                    property bool enableLoading: true
                    shown: Config.options.background.widgets.media.enable && enableLoading
                        && (Config.options.background.screenList.length === 0
                            || Config.options.background.screenList.includes(bgRoot.screen.name))
                    sourceComponent: MediaWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                    }
                    onLoaded: {
                        if (item && item.requestReset) {
                            item.requestReset.connect(() => {
                                mediaLoader.enableLoading = false
                                mediaTimer.running = true
                            })
                        }
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.images.enable
                        && (Config.options.background.screenList.length === 0
                            || Config.options.background.screenList.includes(bgRoot.screen.name))
                    sourceComponent: ImageConverterWidget {
                        screenWidth:        bgRoot.screen.width
                        screenHeight:       bgRoot.screen.height
                        scaledScreenWidth:  bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale:     1
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.resources.enable
                        && (Config.options.background.screenList.length === 0
                            || Config.options.background.screenList.includes(bgRoot.screen.name))
                    sourceComponent: ResourcesWidget {
                        screenWidth:        bgRoot.screen.width
                        screenHeight:       bgRoot.screen.height
                        scaledScreenWidth:  bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale:     1
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.worldClock.enable
                        && (Config.options.background.screenList.length === 0
                            || Config.options.background.screenList.includes(bgRoot.screen.name))
                    sourceComponent: WorldClockWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.userCard.enable
                        && (Config.options.background.screenList.length === 0
                            || Config.options.background.screenList.includes(bgRoot.screen.name))
                    sourceComponent: UserCardWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                    }
                }
            }

            MouseArea {
                id: centeredDesktopThumpArea
                z: 2
                width: Math.max(1, bgRoot.centeredShapeSize())
                height: width
                anchors.centerIn: parent
                visible: bgRoot.centeredWallpaperEnabled
                    && !GlobalStates.screenLocked
                    && (bgRoot.centeredProgress < 1 || bgRoot.centeredAnimating)
                acceptedButtons: Qt.LeftButton
                onClicked: GlobalStates.centeredWallpaperThumpRequested()
            }

            MouseArea {
                id: desktopRightClickArea
                anchors.fill: parent
                z: -2
                acceptedButtons: Qt.RightButton
                onClicked: (mouse) => {
                    GlobalStates.desktopMenuScreen = bgRoot.screen
                    GlobalStates.desktopMenuX = mouse.x
                    GlobalStates.desktopMenuY = mouse.y
                    GlobalStates.desktopMenuOpen = true
                }
            }
        }
    }
}
