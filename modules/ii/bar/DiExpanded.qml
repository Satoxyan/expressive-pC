import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

// Click-to-open state of the island. The overlay starts exactly on the island's visible surface and grows out of
// it; closing shrinks it back into that same shape, so it reads as the island changing size, not a second window.
// While the pointer rests on it the island leans in a touch; when the pointer leaves it eases back and a thin fuse
// shows how long until it closes by itself. Clicking anywhere else closes it right away.
//
// Size and motion: the height comes in a few fixed steps rather than following each view (so moving between
// islands mostly keeps the same height), the width adapts between clear bounds, and every change of shape runs
// on a spring (DiSpring) that keeps its velocity when the target moves mid-flight. Input is separate from the
// visuals: the window's input region is a hitbox that only shrinks once a gesture is over, so an island that
// gets smaller while you scroll never slides out from under the pointer.
Scope {
    id: scope
    required property Item di
    required property Item pillItem

    // 0 closed → 1 open. Opening carries a hair of overshoot; closing settles without one
    property DiSpring openSpring: DiSpring {
        target: scope.di.expanded ? 1 : 0
        stiffness: scope.di.expanded ? IslandMotion.springOpen.stiffness : IslandMotion.springClose.stiffness
        dampingRatio: scope.di.expanded ? IslandMotion.springOpen.dampingRatio : IslandMotion.springClose.dampingRatio
        epsilon: 0.0008
    }
    readonly property real progress: scope.openSpring.value
    readonly property bool closing: !scope.di.expanded

    LazyLoader {
        active: scope.di.visible

        component: PanelWindow {
            id: win

            readonly property bool bottomBar: Config.options.bar.bottom
            readonly property real barMargin: Config.options.bar.cornerStyle === 3 ? 5 : 0
            readonly property real barWindowHeight: Appearance.sizes.barHeight + Appearance.rounding.screenRounding
            readonly property Item surface: scope.di.surfaceItem
            readonly property rect surfaceRect: {
                win.surface.width
                win.surface.height
                scope.pillItem.width
                scope.di.implicitWidth
                const s = scope.di.QsWindow.mapFromItem(win.surface, 0, 0)
                const q = scope.di.QsWindow.mapFromItem(scope.pillItem, 0, 0)
                const left = Math.min(s.x, q.x)
                const top = Math.min(s.y, q.y)
                const right = Math.max(s.x + win.surface.width, q.x + scope.pillItem.width)
                const bottom = Math.max(s.y + win.surface.height, q.y + scope.pillItem.height)
                return Qt.rect(left, top, right - left, bottom - top)
            }

            screen: scope.di.QsWindow.window?.screen ?? null
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:dynamicIsland"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: scope.di.wantsKeyboard ? WlrKeyboardFocus.Exclusive
                : (scope.di.expanded && scope.di.replyReady ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None)

            anchors {
                top: !win.bottomBar
                bottom: win.bottomBar
                left: true
                right: true
            }
            margins {
                top: win.bottomBar ? 0 : win.barMargin
                bottom: win.bottomBar ? win.barMargin : 0
            }
            implicitHeight: 700
            mask: Region { item: scope.progress > 0.002 ? hitbox : noInput }

            Item {
                id: noInput
                width: 0
                height: 0
            }

            HyprlandFocusGrab {
                windows: [win]
                active: scope.di.expanded
                onCleared: if (scope.di.expanded) scope.di.collapse()
            }

            // Everything interactive hangs off this full-window item. The window only takes input inside `hitbox`
            // (see the mask), so "the pointer is in the window" means "the pointer is on the island or on the ground it
            // covered a moment ago" — hover and the wheel live here instead of on the visual shape.
            Item {
                id: stage
                anchors.fill: parent

                HoverHandler {
                    id: stageHover
                    onHoveredChanged: {
                        scope.di.cardHovered = stageHover.hovered
                        if (stageHover.hovered) hitbox.engage()
                        else hitbox.release()
                    }
                }

                WheelHandler {
                    id: wheel
                    target: null
                    enabled: scope.di.expanded
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    property bool coolingDown: false
                    onWheel: event => {
                        hitbox.engage()
                        if (wheel.coolingDown) return
                        wheel.coolingDown = true
                        wheelCooldown.restart()
                        const direction = event.angleDelta.y < 0 ? 1 : -1
                        detail.direction = direction
                        scope.di.cycleIsland(direction)
                    }
                }

                Timer {
                    id: wheelCooldown
                    interval: 280
                    onTriggered: wheel.coolingDown = false
                }

                // The hitbox's margin outside the visual island is still "outside": a click there closes, as it would
                // anywhere else on the screen
                TapHandler {
                    enabled: scope.di.expanded
                    onTapped: point => {
                        const p = point.position
                        if (p.x < island.x || p.x > island.x + island.width || p.y < island.y || p.y > island.y + island.height)
                            scope.di.collapse()
                    }
                }

                // The input region. At rest it is exactly the visual island; while the pointer is on it, it becomes
                // the union of every shape the island has taken since, so the island can shrink (scrolling to a smaller
                // one) without the region leaving the pointer behind. Once the gesture is over and the shape has
                // settled, it relaxes back to the island — from then on, a pointer left outside really is outside.
                Item {
                    id: hitbox
                    property bool engaged: false
                    property real ex: 0
                    property real ey: 0
                    property real ew: 0
                    property real eh: 0
                    x: hitbox.engaged ? hitbox.ex : island.x
                    y: hitbox.engaged ? hitbox.ey : island.y
                    width: hitbox.engaged ? hitbox.ew : island.width
                    height: hitbox.engaged ? hitbox.eh : island.height

                    function engage() {
                        if (!hitbox.engaged) {
                            hitbox.ex = island.x
                            hitbox.ey = island.y
                            hitbox.ew = island.width
                            hitbox.eh = island.height
                            hitbox.engaged = true
                        } else {
                            const right = Math.max(hitbox.ex + hitbox.ew, island.x + island.width)
                            const bottom = Math.max(hitbox.ey + hitbox.eh, island.y + island.height)
                            hitbox.ex = Math.min(hitbox.ex, island.x)
                            hitbox.ey = Math.min(hitbox.ey, island.y)
                            hitbox.ew = right - hitbox.ex
                            hitbox.eh = bottom - hitbox.ey
                        }
                        relaxTimer.restart()
                    }
                    function release() {
                        relaxTimer.stop()
                        hitbox.engaged = false
                    }

                    Timer {
                        id: relaxTimer
                        interval: 700
                        onTriggered: {
                            if (island.resizing || wheel.coolingDown) relaxTimer.restart()
                            else hitbox.engaged = false
                        }
                    }

                    Connections {
                        target: island
                        enabled: hitbox.engaged
                        function onXChanged() { hitbox.engage() }
                        function onYChanged() { hitbox.engage() }
                        function onWidthChanged() { hitbox.engage() }
                        function onHeightChanged() { hitbox.engage() }
                    }
                }

                StyledRectangularShadow {
                    target: island
                    opacity: Math.max(0, Math.min(1, scope.progress)) * (1 + 0.25 * island.leanValue)
                    visible: scope.progress > 0.05
                }

                Rectangle {
                    id: island

                    readonly property real p: Math.max(0, scope.progress)
                    readonly property real pc: Math.min(1, island.p)
                    readonly property bool settled: scope.di.expanded && island.p > 0.95

                    readonly property real startW: win.surfaceRect.width + 3
                    readonly property real startH: win.surfaceRect.height + 2
                    readonly property real maxH: Math.min(win.height - 24, (win.screen?.height ?? 1080) * 0.55)
                    readonly property real maxW: win.width - 24
                    readonly property bool splitActive: scope.di.splitId !== "" && scope.di.splitId !== scope.di.expandedId
                        && scope.di.hasDetails(scope.di.splitId)

                    readonly property real bottomReserve: 18 + (scope.di.splitArmed ? splitPicker.implicitHeight + 10 : 0)

                    // Height in steps: compact, standard (most live islands: media, home, downloads, IMDb), large and
                    // tall. A view sits centred in its step; anything taller than the last one scrolls inside it.
                    readonly property var heightSteps: [152, 280, 384, 464]
                    readonly property real tallest: Math.min(island.maxH, island.heightSteps[island.heightSteps.length - 1])
                    function stepFor(need) {
                        for (const step of island.heightSteps)
                            if (need <= step) return Math.min(step, island.maxH)
                        return island.tallest
                    }
                    readonly property real contentNeed: Math.max(detail.naturalHeight, island.splitActive ? splitDetail.naturalHeight : 0)
                        + island.bottomReserve

                    // Width follows the view, between a floor (never narrower than the pill it grew out of) and a ceiling
                    // (only split view, two views side by side, may go past it)
                    readonly property real minW: Math.min(island.maxW, Math.max(island.startW, 340))
                    readonly property real maxSingleW: Math.min(island.maxW, 520)
                    readonly property real wantedW: Math.max(island.minW, Math.min(island.splitActive ? island.maxW : island.maxSingleW,
                        detail.implicitWidth + (island.splitActive ? 12 + splitDetail.implicitWidth : 0)))
                    readonly property real wantedH: Math.max(island.startH, island.stepFor(island.contentNeed))

                    DiSpring {
                        id: sizeW
                        target: island.wantedW
                        stiffness: IslandMotion.springResize.stiffness
                        dampingRatio: IslandMotion.springResize.dampingRatio
                        animated: island.shown
                    }
                    DiSpring {
                        id: sizeH
                        target: island.wantedH
                        stiffness: IslandMotion.springResize.stiffness
                        dampingRatio: IslandMotion.springResize.dampingRatio
                        animated: island.shown
                    }
                    readonly property bool resizing: sizeW.moving || sizeH.moving || scope.openSpring.moving

                    readonly property bool shown: scope.progress > 0.02
                    readonly property bool coversPill: scope.progress > 0.2
                    onCoversPillChanged: scope.di.overlayShown = island.coversPill
                    Component.onDestruction: {
                        scope.di.overlayShown = false
                        scope.di.cardHovered = false
                    }

                    readonly property bool pointerIn: scope.di.cardHovered
                    readonly property real lean: island.settled ? (island.pointerIn ? 1 : -1) : 0
                    property real leanValue: island.lean

                    Behavior on leanValue {
                        SpringAnimation { spring: 3.4; damping: 0.3; epsilon: 0.002 }
                    }

                    transform: Scale {
                        origin.x: island.width / 2
                        origin.y: win.bottomBar ? island.height : 0
                        xScale: 1 + 0.012 * Math.max(-0.6, island.leanValue)
                        yScale: 1 + 0.018 * Math.max(-0.6, island.leanValue)
                    }

                    readonly property real pw: Math.min(1, island.p * 2.2)
                    width: island.startW + (sizeW.value - island.startW) * island.pw
                    height: island.startH + (sizeH.value - island.startH) * island.p
                    x: Math.max(8, Math.min(win.width - island.width - 8, win.surfaceRect.x - 1.5 + island.startW / 2 - island.width / 2))
                    y: win.bottomBar
                        ? win.height - (win.barWindowHeight - win.surfaceRect.y - island.startH) - island.height + 1
                        : win.surfaceRect.y - 1
                    radius: Math.min(island.height / 2, island.startH / 2 + 12 * island.pc)
                    color: scope.di.surfaceColor
                    border.width: 1
                    border.color: ColorUtils.transparentize(Appearance.colors.colLayer0Border, 1 - island.pc * (island.pointerIn ? 1 : 0.6))
                    clip: true
                    visible: scope.progress > 0.002

                    Behavior on border.color {
                        ColorAnimation { duration: 220 }
                    }

                    TapHandler {
                        acceptedButtons: Qt.MiddleButton
                        onTapped: scope.di.collapse()
                    }

                    Item {
                        id: compactGhost
                        x: (island.width - island.startW) / 2 + 1.5
                        y: win.bottomBar ? island.height - island.startH : 1
                        width: island.startW - 3
                        height: island.startH - 2
                        opacity: scope.closing
                            ? Math.max(0, Math.min(1, (0.5 - island.p) / 0.4))
                            : Math.max(0, 1 - island.pc * 3)
                        visible: scope.progress > 0.002

                        Item {
                            x: win.surfaceRect.width > 0 ? (scope.di.QsWindow.mapFromItem(scope.pillItem, 0, 0).x - win.surfaceRect.x) : 0
                            anchors.verticalCenter: parent.verticalCenter
                            width: scope.pillItem.width
                            height: scope.di.pillHeight

                            Loader {
                                id: compactLoader
                                anchors.fill: parent
                                sourceComponent: scope.di.componentFor(scope.di.primaryId)
                            }
                        }
                    }

                    readonly property real pairW: island.splitActive ? detail.width + 12 + splitDetail.width : detail.width

                    DiExpandedContent {
                        id: detail
                        di: scope.di
                        onOverscrolled: direction => {
                            hitbox.engage()
                            if (wheel.coolingDown) return
                            wheel.coolingDown = true
                            wheelCooldown.restart()
                            detail.direction = direction
                            scope.di.cycleIsland(direction)
                        }
                        contentId: scope.di.expandedId
                        maxHeight: island.tallest - island.bottomReserve
                        x: (island.width - island.pairW) / 2
                        // The frame the view is centred in: the island minus the strip kept for the pager
                        y: win.bottomBar ? island.bottomReserve : 0
                        width: island.splitActive ? Math.min(island.maxW, implicitWidth)
                            : Math.min(island.maxW, Math.max(island.width, implicitWidth))
                        height: Math.max(0, island.height - island.bottomReserve)
                        opacity: (scope.closing
                            ? Math.max(0, Math.min(1, (island.p - 0.5) / 0.5))
                            : Math.max(0, Math.min(1, (island.p - 0.35) / 0.5)))
                            * (1 - 0.04 * Math.max(0, Math.min(1, -island.leanValue)))
                        visible: island.shown
                    }

                    Rectangle {
                        id: splitDivider
                        visible: island.splitActive && island.shown
                        x: detail.x + detail.width + 5
                        width: 1
                        height: Math.max(0, Math.min(detail.implicitHeight, splitDetail.implicitHeight) - 16)
                        y: detail.y + (detail.height - height) / 2
                        color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.85)
                        opacity: detail.opacity
                    }

                    DiExpandedContent {
                        id: splitDetail
                        di: scope.di
                        contentId: island.splitActive ? scope.di.splitId : ""
                        maxHeight: island.tallest - island.bottomReserve
                        x: detail.x + detail.width + 12
                        y: detail.y
                        width: Math.min(island.maxW, implicitWidth)
                        height: detail.height
                        opacity: island.splitActive ? detail.opacity : 0
                        visible: island.splitActive && island.shown
                    }

                    readonly property var compactHero: compactLoader.item?.hero ?? null
                    readonly property var fullHero: detail.viewItem?.hero ?? null
                    readonly property bool heroActive: island.compactHero !== null && island.fullHero !== null
                        && island.compactHero.key === island.fullHero.key && !!island.compactHero.item && !!island.fullHero.item
                        && island.p > 0.001 && island.p < 0.999
                    property rect heroFrom: Qt.rect(0, 0, 0, 0)
                    property rect heroTo: Qt.rect(0, 0, 0, 0)

                    function measureHeroes() {
                        if (!island.heroActive) return
                        const c = island.compactHero.item
                        const f = island.fullHero.item
                        const a = island.mapFromItem(c, 0, 0)
                        const b = island.mapFromItem(f, 0, 0)
                        island.heroFrom = Qt.rect(a.x, a.y, c.width, c.height)
                        island.heroTo = Qt.rect(b.x, b.y, f.width, f.height)
                    }
                    onPChanged: island.measureHeroes()
                    onHeroActiveChanged: island.measureHeroes()

                    Item {
                        id: heroFlight
                        readonly property real t: island.pc
                        visible: island.heroActive
                        z: 10
                        x: island.heroFrom.x + (island.heroTo.x - island.heroFrom.x) * heroFlight.t
                        y: island.heroFrom.y + (island.heroTo.y - island.heroFrom.y) * heroFlight.t
                        width: island.heroFrom.width + (island.heroTo.width - island.heroFrom.width) * heroFlight.t
                        height: island.heroFrom.height + (island.heroTo.height - island.heroFrom.height) * heroFlight.t

                        ShaderEffectSource {
                            anchors.fill: parent
                            sourceItem: island.heroActive ? island.compactHero.item : null
                            hideSource: heroFlight.visible
                            live: true
                            smooth: true
                            opacity: 1 - Math.min(1, heroFlight.t * 1.6)
                        }
                        ShaderEffectSource {
                            anchors.fill: parent
                            sourceItem: island.heroActive ? island.fullHero.item : null
                            hideSource: heroFlight.visible
                            live: true
                            smooth: true
                            opacity: Math.min(1, heroFlight.t * 1.6)
                        }
                    }

                    Row {
                        id: pager
                        visible: scope.di.switcherIds.length > 1
                        height: 14
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: win.bottomBar ? 2 : island.height - height - 3
                        spacing: 5
                        opacity: Math.max(0, Math.min(1, (island.p - 0.6) / 0.4))

                        Repeater {
                            model: scope.di.switcherIds
                            delegate: Rectangle {
                                required property string modelData
                                readonly property bool current: modelData === scope.di.expandedId
                                readonly property bool splitPartner: modelData === scope.di.splitId
                                anchors.verticalCenter: parent.verticalCenter
                                width: (current || splitPartner) ? 16 : 6
                                height: 6
                                radius: 3
                                color: current ? Appearance.colors.colPrimary
                                    : splitPartner ? Appearance.colors.colSecondary
                                    : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.7)

                                Behavior on width {
                                    NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: scope.di.selectForSplit(parent.modelData)
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: splitButton
                        readonly property bool lit: scope.di.splitArmed || scope.di.splitId !== ""
                        x: island.width - width - Math.max(12, island.radius * 0.75)
                        y: win.bottomBar ? 5 : island.height - height - 5
                        width: 22
                        height: 14
                        radius: 7
                        color: splitButton.lit ? Appearance.colors.colPrimary
                            : (splitButtonMouse.containsMouse ? Appearance.colors.colLayer2 : "transparent")
                        opacity: Math.max(0, Math.min(1, (island.p - 0.6) / 0.4))

                        Behavior on color {
                            ColorAnimation { duration: 160 }
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: scope.di.splitId !== "" ? "close" : "splitscreen_right"
                            iconSize: 11
                            fill: 1
                            color: splitButton.lit ? Appearance.colors.colOnPrimary
                                : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.35)
                        }

                        MouseArea {
                            id: splitButtonMouse
                            anchors.fill: parent
                            anchors.margins: -5
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: scope.di.toggleSplitArm()
                        }
                    }

                    Flow {
                        id: splitPicker
                        visible: scope.di.splitArmed
                        x: 14
                        width: island.width - 28
                        y: win.bottomBar ? 22 : island.height - 18 - height - 6
                        spacing: 6
                        opacity: scope.di.splitArmed ? 1 : 0

                        Behavior on opacity {
                            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                        }

                        Repeater {
                            model: scope.di.splitArmed ? scope.di.splitCandidates : []
                            delegate: Rectangle {
                                id: pickChip
                                required property string modelData
                                required property int index
                                implicitWidth: pickRow.implicitWidth + 18
                                implicitHeight: 28
                                radius: 14
                                color: pickMouse.containsMouse ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1
                                scale: 0.4
                                opacity: 0
                                transformOrigin: Item.Right

                                Behavior on color {
                                    ColorAnimation { duration: 140 }
                                }

                                SequentialAnimation {
                                    running: true
                                    PauseAnimation { duration: pickChip.index * 32 }
                                    ParallelAnimation {
                                        NumberAnimation { target: pickChip; property: "scale"; to: 1; duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.5 }
                                        NumberAnimation { target: pickChip; property: "opacity"; to: 1; duration: 200; easing.type: Easing.OutCubic }
                                    }
                                }

                                RowLayout {
                                    id: pickRow
                                    anchors.centerIn: parent
                                    spacing: 6

                                    DiClaudeIcon {
                                        visible: ["claude", "codex", "gemini"].includes(scope.di.iconForId(pickChip.modelData))
                                        agent: scope.di.iconForId(pickChip.modelData)
                                        size: 14
                                    }
                                    MaterialSymbol {
                                        visible: !["claude", "codex", "gemini"].includes(scope.di.iconForId(pickChip.modelData))
                                        text: scope.di.iconForId(pickChip.modelData)
                                        iconSize: 15
                                        fill: 1
                                        color: pickMouse.containsMouse ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                                    }
                                    StyledText {
                                        text: scope.di.nameForId(pickChip.modelData)
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: pickMouse.containsMouse ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                                    }
                                }

                                MouseArea {
                                    id: pickMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: scope.di.chooseSplit(pickChip.modelData)
                                }
                            }
                        }
                    }

                    Item {
                        id: fuseTrack
                        property real remaining: 1
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: win.bottomBar ? 1 : island.height - 3
                        width: Math.min(120, island.width * 0.4)
                        height: 2
                        opacity: fuse.running ? 1 : 0

                        Behavior on opacity {
                            NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 1
                            color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.88)
                        }
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width * fuseTrack.remaining
                            height: parent.height
                            radius: 1
                            color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.25)
                        }

                        NumberAnimation {
                            id: fuse
                            target: fuseTrack
                            property: "remaining"
                            from: 1
                            to: 0
                            duration: scope.di.collapseDelay
                            running: island.settled && !island.pointerIn
                            onFinished: {
                                if (!scope.di.cardHovered && !(scope.di.wantsKeyboard && scope.di.replyHasText) && !scope.di.dragging)
                                    scope.di.collapse()
                            }
                        }
                    }
                }
            }
        }
    }
}
