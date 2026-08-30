import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Quickshell.Services.Mpris
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland

import qs.modules.ii.sidebarRight.quickToggles
import qs.modules.ii.sidebarRight.quickToggles.classicStyle
import qs.modules.ii.sidebarRight.bluetoothDevices
import qs.modules.ii.sidebarRight.nightLight
import qs.modules.ii.sidebarRight.volumeMixer
import qs.modules.ii.sidebarRight.wifiNetworks
import qs.modules.ii.sidebarRight.iconPicker

Item {
    id: root
    property int sidebarWidth: Appearance.sizes.sidebarWidth
    property int sidebarPadding: 10
    property bool showAudioOutputDialog: false
    property bool showAudioInputDialog: false
    property bool showBluetoothDialog: false
    property bool showNightLightDialog: false
    property bool showWifiDialog: false
    property bool editMode: false
    property bool showIconPickerDialog: false
    property int draggingSlot: -1
    property point dragPosition

    readonly property bool animatedEntrance: WM.compositor !== "hyprland"
    readonly property bool sidebarOpen: GlobalStates.sidebarRightOpen

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

    Connections {
        target: GlobalStates
        function onRequestBluetoothDialog() {
            if (!BluetoothStatus.available) return;
            root.showBluetoothDialog = true;
            GlobalStates.sidebarRightOpen = true;
        }

        function onSidebarRightOpenChanged() {
            if (!GlobalStates.sidebarRightOpen) {
                root.showWifiDialog = false;
                root.showBluetoothDialog = false;
                root.showAudioOutputDialog = false;
                root.showAudioInputDialog = false;
                root.editMode = false;
            }
        }
    }

    Process {
        id: fileChooser
        command: ["kdialog", "--getopenfilename", Quickshell.env("HOME") + "/Pictures", "image/png image/jpg image/jpeg image/webp"]
        
        stdout: StdioCollector {
            id: fileChooserOutput
        }
        
        onExited: (code) => {
            if (code === 0) {
                const path = fileChooserOutput.text.trim()
                if (path !== "") {
                    Config.options.sidebar.bannerImage = path
                }
            }
        }
    }

    implicitHeight: sidebarRightBackground.implicitHeight
    implicitWidth: sidebarRightBackground.implicitWidth

    StyledRectangularShadow {
        target: sidebarRightBackground
    }
    Rectangle {
        id: sidebarRightBackground

        anchors.fill: parent
        implicitHeight: parent.height - Appearance.sizes.hyprlandGapsOut * 2
        implicitWidth: sidebarWidth - Appearance.sizes.hyprlandGapsOut * 2
        color: Appearance.colors.colLayer0
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 5

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: sidebarPadding
            spacing: sidebarPadding

            // Banner
            Loader {
                Layout.fillWidth: true
                Layout.fillHeight: false
                sourceComponent: Config.options.sidebar.banner ? bannerComponent : normalComponent

                Component {
                    id: bannerComponent
                    Item {
                        implicitHeight: 180
                        implicitWidth: parent?.width ?? 0

                        Rectangle {
                            id: sysRect
                            anchors.fill: parent
                            radius: Config.options.hyprland.decoration.rounding - 2
                            color: Appearance.colors.colLayer1

                            Rectangle {
                                id: wallpaperRect
                                anchors {
                                    top: parent.top
                                    left: parent.left
                                    right: parent.right
                                    topMargin: 2
                                    leftMargin: 2
                                    rightMargin: 2
                                }
                                height: 120
                                radius: sysRect.radius
                                color: "transparent"

                                LiveWallpaperPreview {
                                    anchors.fill: parent
                                    source: Config.options.sidebar.bannerImage !== "" 
                                        ? Config.options.sidebar.bannerImage 
                                        : Config.options.background.wallpaperPath
                                    thumbnail: Config.options.background.thumbnailPath
                                    radius: wallpaperRect.radius
                                    active: true
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: (event) => {
                                        if (event.button === Qt.LeftButton) {
                                            fileChooser.running = true
                                            GlobalStates.sidebarRightOpen = false
                                        } else if (event.button === Qt.RightButton) {
                                            Config.options.sidebar.bannerImage = ""
                                        }
                                    }
                                }
                            }

                            Column {
                                anchors {
                                    left: parent.left
                                    bottom: parent.bottom
                                    leftMargin: 13
                                    bottomMargin: 8
                                }
                                spacing: 1

                                Rectangle {
                                    id: avatarRect
                                    width: 48; height: 48; radius: width / 2
                                    color: Appearance.colors.colPrimaryContainer

                                    Image {
                                        id: avatarImage
                                        anchors.fill: parent
                                        source: Avatar.effectiveAvatarSource
                                        sourceSize.width: avatarImage.width * 2
                                        sourceSize.height: avatarImage.height * 2
                                        fillMode: Image.PreserveAspectCrop
                                        layer.enabled: true
                                        layer.effect: OpacityMask {
                                            maskSource: Rectangle {
                                                width: avatarRect.width
                                                height: avatarRect.height
                                                radius: avatarRect.radius
                                            }
                                        }
                                        onStatusChanged: {
                                            if (status === Image.Error) visible = false
                                        }
                                    }

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "account_circle"
                                        iconSize: 32
                                        color: Appearance.colors.colOnPrimaryContainer
                                        visible: avatarImage.status === Image.Error
                                    }
                                }

                                StyledText {
                                    text: (Config.options.profile.displayName === "" ? SystemInfo.username : Config.options.profile.displayName) + "@" + SystemInfo.hostname
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colOnLayer1
                                }

                                StyledText {
                                    text: Translation.tr("Up • %1").arg(DateTime.uptime)
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnLayer1
                                    opacity: 0.6
                                }
                            }

                            ButtonGroup {
                                anchors {
                                    right: parent.right
                                    bottom: parent.bottom
                                    margins: 4
                                }
                                color: "transparent"
                                padding: 4

                                QuickToggleButton {
                                    toggled: root.editMode
                                    visible: Config.options.sidebar.quickToggles.style === "android"
                                    buttonIcon: "edit"
                                    onClicked: root.editMode = !root.editMode
                                    StyledToolTip {
                                        text: Translation.tr("Edit quick toggles") + (root.editMode ? Translation.tr("\nLMB to enable/disable\nRMB to toggle size\nScroll to swap position") : "")
                                    }
                                }
                                QuickToggleButton {
                                    toggled: false
                                    buttonIcon: "restart_alt"
                                    onClicked: {
                                        Quickshell.execDetached(["hyprctl", "reload"])
                                        Quickshell.reload(true);
                                    }
                                    StyledToolTip {
                                        text: Translation.tr("Reload Hyprland & Quickshell")
                                    }
                                }
                                QuickToggleButton {
                                    toggled: GlobalStates.settingsOpen
                                    buttonIcon: "settings"
                                    onClicked: {
                                        GlobalStates.sidebarRightOpen = false;
                                        GlobalStates.settingsOpen = !GlobalStates.settingsOpen
                                    }
                                    StyledToolTip {
                                        text: Translation.tr("Settings")
                                    }
                                }
                                QuickToggleButton {
                                    toggled: false
                                    buttonIcon: "mode_off_on"
                                    onClicked: GlobalStates.sessionOpen = true
                                    StyledToolTip {
                                        text: Translation.tr("Session")
                                    }
                                }
                            }
                        }
                    }
                }

                Component {
                    id: normalComponent
                    SystemButtonRow {}
                }
            }

            // ponytail: 3 reorderable panels — drag handle swaps Config panelOrder
            Item {
                Layout.fillWidth: true
                implicitHeight: panelSlots.implicitHeight

                Rectangle {
                    id: panelDropIndicator
                    visible: false
                    z: 99
                    width: parent.width
                    height: 3
                    radius: 2
                    color: Appearance.colors.colPrimary
                }

                ColumnLayout {
                    id: panelSlots
                    width: parent.width
                    spacing: root.editMode ? 8 : sidebarPadding

                    function panelSource(type) {
                        if (type === "quickToggles") return quickTogglesPanel
                        if (type === "sliders") return slidersPanel
                        if (type === "media") return mediaPanel
                        return null
                    }
                    function panelVisible(type) {
                        if (type === "quickToggles") return true
                        if (type === "sliders") {
                            const c = Config.options.sidebar.quickSliders
                            return c.enable && (c.showMic || c.showVolume || c.showBrightness)
                        }
                        if (type === "media") return Config.options.sidebar.mediaPlayer && (root.activePlayer !== null || root.editMode)
                        return false
                    }
                    function swapPanels(fromType, toType) {
                        const order = [...Config.options.sidebar.panelOrder]
                        const fi = order.indexOf(fromType)
                        const ti = order.indexOf(toType)
                        if (fi === -1 || ti === -1 || fi === ti) return
                        const item = order.splice(fi, 1)[0]
                        order.splice(ti, 0, item)
                        Config.options.sidebar.panelOrder = order
                    }

                    // Slot 0
                    Item {
                        Layout.fillWidth: true
                        Layout.leftMargin: slot0Loader.panelType === "media" ? -8 : 0
                        Layout.rightMargin: slot0Loader.panelType === "media" ? -8 : 0
                        Layout.topMargin: slot0Loader.panelType === "media" ? -4 : 0
                        Layout.bottomMargin: slot0Loader.panelType === "media" ? -4 : 0
                        implicitHeight: slot0Column.implicitHeight
                        visible: (slot0Loader.panelType === "media" || slot0Loader.panelType === "sliders") ? panelSlots.panelVisible(slot0Loader.panelType) : (root.editMode || panelSlots.panelVisible(slot0Loader.panelType))
                        opacity: dragHandler0.active ? 0 : (root.editMode && !panelSlots.panelVisible(slot0Loader.panelType) ? 0.4 : 1)

                        ColumnLayout {
                            id: slot0Column
                            anchors.fill: parent
                            spacing: 0
                            visible: (slot0Loader.panelType === "media" || slot0Loader.panelType === "sliders") ? panelSlots.panelVisible(slot0Loader.panelType) : (root.editMode || panelSlots.panelVisible(slot0Loader.panelType))
                            ReorderDragHandle { id: dragHandler0; panelType: slot0Loader.panelType; order: 0 }
                            Loader {
                                id: slot0Loader
                                Layout.fillWidth: true
                                active: panelSlots.panelVisible(slot0Loader.panelType) || (root.editMode && slot0Loader.panelType !== "sliders" && slot0Loader.panelType !== "media")
                                asynchronous: true
                                property string panelType: {
                                    const o = Config.options.sidebar.panelOrder
                                    return (o && o.length === 3) ? String(o[0]) : "quickToggles"
                                }
                                sourceComponent: panelSlots.panelSource(panelType)
                            }
                        }
                    }
                    // Slot 1
                    Item {
                        Layout.fillWidth: true
                        Layout.leftMargin: slot1Loader.panelType === "media" ? -8 : 0
                        Layout.rightMargin: slot1Loader.panelType === "media" ? -8 : 0
                        Layout.topMargin: slot1Loader.panelType === "media" ? -4 : 0
                        Layout.bottomMargin: slot1Loader.panelType === "media" ? -4 : 0
                        implicitHeight: slot1Column.implicitHeight
                        visible: (slot1Loader.panelType === "media" || slot1Loader.panelType === "sliders") ? panelSlots.panelVisible(slot1Loader.panelType) : (root.editMode || panelSlots.panelVisible(slot1Loader.panelType))
                        opacity: dragHandler1.active ? 0 : (root.editMode && !panelSlots.panelVisible(slot1Loader.panelType) ? 0.4 : 1)

                        ColumnLayout {
                            id: slot1Column
                            anchors.fill: parent
                            spacing: 0
                            visible: (slot1Loader.panelType === "media" || slot1Loader.panelType === "sliders") ? panelSlots.panelVisible(slot1Loader.panelType) : (root.editMode || panelSlots.panelVisible(slot1Loader.panelType))
                            ReorderDragHandle { id: dragHandler1; panelType: slot1Loader.panelType; order: 1 }
                            Loader {
                                id: slot1Loader
                                Layout.fillWidth: true
                                active: panelSlots.panelVisible(slot1Loader.panelType)
                                asynchronous: true
                                property string panelType: {
                                    const o = Config.options.sidebar.panelOrder
                                    return (o && o.length === 3) ? String(o[1]) : "sliders"
                                }
                                sourceComponent: panelSlots.panelSource(panelType)
                            }
                        }
                    }
                    // Slot 2
                    Item {
                        Layout.fillWidth: true
                        Layout.leftMargin: slot2Loader.panelType === "media" ? -8 : 0
                        Layout.rightMargin: slot2Loader.panelType === "media" ? -8 : 0
                        Layout.topMargin: slot2Loader.panelType === "media" ? -4 : 0
                        Layout.bottomMargin: slot2Loader.panelType === "media" ? -4 : 0
                        implicitHeight: slot2Column.implicitHeight
                        visible: (slot2Loader.panelType === "media" || slot2Loader.panelType === "sliders") ? panelSlots.panelVisible(slot2Loader.panelType) : (root.editMode || panelSlots.panelVisible(slot2Loader.panelType))
                        opacity: dragHandler2.active ? 0 : (root.editMode && !panelSlots.panelVisible(slot2Loader.panelType) ? 0.4 : 1)

                        ColumnLayout {
                            id: slot2Column
                            anchors.fill: parent
                            spacing: 0
                            visible: (slot2Loader.panelType === "media" || slot2Loader.panelType === "sliders") ? panelSlots.panelVisible(slot2Loader.panelType) : (root.editMode || panelSlots.panelVisible(slot2Loader.panelType))
                            ReorderDragHandle { id: dragHandler2; panelType: slot2Loader.panelType; order: 2 }
                            Loader {
                                id: slot2Loader
                                Layout.fillWidth: true
                                active: panelSlots.panelVisible(slot2Loader.panelType)
                                asynchronous: true
                                property string panelType: {
                                    const o = Config.options.sidebar.panelOrder
                                    return (o && o.length === 3) ? String(o[2]) : "media"
                                }
                                sourceComponent: panelSlots.panelSource(panelType)
                            }
                        }
                    }
                }
            }

            CenterWidgetGroup {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: true
                Layout.fillWidth: true
                Layout.minimumHeight: 47 // ponytail: bottom bar (ring/count/clean) height, not shrink through
            }

            BottomWidgetGroup {
                visible: Config.options.sidebar.bottomGroup
                id: bottomWidgetGroup
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: false
                Layout.fillWidth: true
            }
        }
    }

    ToggleDialog {
        shownPropertyString: "showAudioOutputDialog"
        dialog: VolumeDialog {
            isSink: true
        }
    }

    ToggleDialog {
        shownPropertyString: "showAudioInputDialog"
        dialog: VolumeDialog {
            isSink: false
        }
    }

    ToggleDialog {
        shownPropertyString: "showBluetoothDialog"
        dialog: BluetoothDialog {}
        onShownChanged: {
            const adapter = Bluetooth.defaultAdapter;
            if (!adapter) return;
            if (!shown) {
                adapter.discovering = false;
            } else {
                adapter.enabled = true;
                adapter.discovering = true;
            }
        }
    }

    ToggleDialog {
        shownPropertyString: "showNightLightDialog"
        dialog: NightLightDialog {}
    }

    ToggleDialog {
        shownPropertyString: "showWifiDialog"
        dialog: WifiDialog {}
        onShownChanged: {
            if (!shown) return;
            Network.enableWifi();
            Network.rescanWifi();
        }
    }

    ToggleDialog {
        shownPropertyString: "showIconPickerDialog"
        dialog: IconPickerDialog {}
    }

    // Drag ghost — hidden per request (only drop indicator shows)
    Item {
        id: dragGhost
        visible: false
        z: 999
        width: sidebarWidth + 30
        height: dragGhostContent.implicitHeight + 16
        x: root.dragPosition.x - width / 2
        y: root.dragPosition.y - 40

        Behavior on x { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
        Behavior on y { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
        Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }

        layer.enabled: true
        layer.effect: DropShadow {
            horizontalOffset: 0
            verticalOffset: 8
            radius: 24
            color: Qt.rgba(0, 0, 0, 0.35)
            samples: 33
        }

        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
        }

        ColumnLayout {
            id: dragGhostContent
            anchors.fill: parent
            anchors.margins: 8
            spacing: 0
            Loader {
                id: dragGhostLoader
                Layout.fillWidth: true
                active: root.draggingSlot >= 0
                property string panelType: {
                    if (root.draggingSlot < 0) return ""
                    const o = Config.options.sidebar.panelOrder
                    if (!o || o.length !== 3) return ""
                    return String(o[root.draggingSlot])
                }
                sourceComponent: panelSlots.panelSource(panelType)
            }
        }
    }

    // ponytail: reorder drag handle for panel slots
    component ReorderDragHandle: Rectangle {
        id: reorderHandle
        visible: root.editMode && !(reorderHandle.panelType === "media" && !Config.options.sidebar.mediaPlayer)
        Layout.fillWidth: true
        implicitHeight: 28
        radius: Appearance.rounding.small
        color: reorderDragHandler.active ? Appearance.colors.colLayer1Active : Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        property string panelType: ""
        property int order: 0
        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 8
            MaterialSymbol { text: "drag_indicator"; iconSize: 18; color: Appearance.colors.colSubtext }
            StyledText {
                Layout.fillWidth: true
                text: reorderHandle.panelType === "quickToggles" ? Translation.tr("Quick toggles")
                    : reorderHandle.panelType === "sliders" ? Translation.tr("Sliders")
                    : reorderHandle.panelType === "media" ? Translation.tr("Media")
                    : reorderHandle.panelType
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer1
            }
            MaterialSymbol { text: "drag_indicator"; iconSize: 18; color: Appearance.colors.colSubtext }
        }

        DragHandler {
            id: reorderDragHandler
            target: null
            acceptedButtons: Qt.LeftButton
            onActiveChanged: {
                if (active) {
                    root.draggingSlot = reorderHandle.order
                } else {
                    panelDropIndicator.visible = false
                    root.draggingSlot = -1
                    const sc = centroid.scenePosition
                    const slots = [slot0Column.parent, slot1Column.parent, slot2Column.parent]
                    const types = [
                        (Config.options.sidebar.panelOrder && Config.options.sidebar.panelOrder.length === 3) ? String(Config.options.sidebar.panelOrder[0]) : "quickToggles",
                        (Config.options.sidebar.panelOrder && Config.options.sidebar.panelOrder.length === 3) ? String(Config.options.sidebar.panelOrder[1]) : "sliders",
                        (Config.options.sidebar.panelOrder && Config.options.sidebar.panelOrder.length === 3) ? String(Config.options.sidebar.panelOrder[2]) : "media"
                    ]
                    let nearestIdx = -1
                    let minDist = Infinity
                    for (let i = 0; i < slots.length; i++) {
                        const center = slots[i].mapToItem(null, slots[i].width / 2, slots[i].height / 2)
                        const d = Math.sqrt(Math.pow(sc.x - center.x, 2) + Math.pow(sc.y - center.y, 2))
                        if (d < minDist) { minDist = d; nearestIdx = i }
                    }
                    if (nearestIdx !== -1 && nearestIdx !== reorderHandle.order) {
                        panelSlots.swapPanels(reorderHandle.panelType, types[nearestIdx])
                    }
                }
            }
            onCentroidChanged: {
                if (!active) return
                const sc = centroid.scenePosition
                const localPos = root.mapFromItem(null, sc.x, sc.y)
                root.dragPosition = Qt.point(localPos.x, localPos.y)
                const slots = [slot0Column.parent, slot1Column.parent, slot2Column.parent]
                let nearestIdx = -1
                let minDist = Infinity
                for (let i = 0; i < slots.length; i++) {
                    const center = slots[i].mapToItem(null, slots[i].width / 2, slots[i].height / 2)
                    const d = Math.sqrt(Math.pow(sc.x - center.x, 2) + Math.pow(sc.y - center.y, 2))
                    if (d < minDist) { minDist = d; nearestIdx = i }
                }
                if (nearestIdx !== -1 && nearestIdx !== reorderHandle.order) {
                    const target = slots[nearestIdx]
                    const self = slots[reorderHandle.order]
                    const after = target.y > self.y
                    const indicatorPos = target.mapToItem(panelDropIndicator.parent, 0, after ? target.height : 0)
                    panelDropIndicator.y = indicatorPos.y - 2
                    panelDropIndicator.visible = true
                } else {
                    panelDropIndicator.visible = false
                }
            }
        }
        HoverHandler { cursorShape: reorderDragHandler.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor }
    }

    Component {
        id: quickTogglesPanel
        ColumnLayout {
            spacing: 0
            Loader {
                id: classicQuickLoader
                Layout.fillWidth: true
                active: Config.options.sidebar.quickToggles.style === "classic"
                visible: active
                sourceComponent: ClassicQuickPanel {}
            }
            Loader {
                id: androidQuickLoader
                Layout.fillWidth: true
                active: Config.options.sidebar.quickToggles.style === "android"
                visible: active
                sourceComponent: AndroidQuickPanel { editMode: root.editMode }
            }
            Connections { target: classicQuickLoader.item; function onOpenAudioOutputDialog() { root.showAudioOutputDialog = true } function onOpenAudioInputDialog() { root.showAudioInputDialog = true } function onOpenBluetoothDialog() { root.showBluetoothDialog = true } function onOpenNightLightDialog() { root.showNightLightDialog = true } function onOpenWifiDialog() { root.showWifiDialog = true } }
            Connections { target: androidQuickLoader.item; function onOpenAudioOutputDialog() { root.showAudioOutputDialog = true } function onOpenAudioInputDialog() { root.showAudioInputDialog = true } function onOpenBluetoothDialog() { root.showBluetoothDialog = true } function onOpenNightLightDialog() { root.showNightLightDialog = true } function onOpenWifiDialog() { root.showWifiDialog = true } }
        }
    }
    Component {
        id: slidersPanel
        QuickSliders {}
    }
    Component {
        id: mediaPanel
        Item {
            implicitHeight: root.activePlayer !== null ? 160 : 80
            Loader {
                anchors.fill: parent
                active: root.activePlayer !== null
                sourceComponent: Player {
                    player: root.activePlayer
                    visualizerPoints: GlobalStates.visualizerPoints
                    implicitHeight: 160
                    radius: Appearance.rounding.normal
                }
            }
            ColumnLayout {
                anchors.fill: parent
                visible: root.activePlayer === null
                spacing: 8
                Item { Layout.fillHeight: true }
                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "music_note"
                    iconSize: 32
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("No media playing")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
                Item { Layout.fillHeight: true }
            }
        }
    }

    component ToggleDialog: Loader {
        id: toggleDialogLoader
        required property string shownPropertyString
        property alias dialog: toggleDialogLoader.sourceComponent
        readonly property bool shown: root[shownPropertyString]
        anchors.fill: parent

        onShownChanged: if (shown) toggleDialogLoader.active = true;
        active: shown
        onActiveChanged: {
            if (active) {
                item.show = true;
                item.forceActiveFocus();
            }
        }
        Connections {
            target: toggleDialogLoader.item
            function onDismiss() {
                toggleDialogLoader.item.show = false
                root[toggleDialogLoader.shownPropertyString] = false;
            }
            function onVisibleChanged() {
                if (toggleDialogLoader.item && !toggleDialogLoader.item.visible && !root[toggleDialogLoader.shownPropertyString])
                    toggleDialogLoader.active = false;
            }
        }
    }

    component LoaderedQuickPanelImplementation: Loader {
        id: quickPanelImplLoader
        required property string styleName
        Layout.alignment: item?.Layout.alignment ?? Qt.AlignHCenter
        Layout.fillWidth: item?.Layout.fillWidth ?? false
        visible: active
        active: Config.options.sidebar.quickToggles.style === styleName
        Connections {
            target: quickPanelImplLoader.item
            function onOpenAudioOutputDialog() { root.showAudioOutputDialog = true; }
            function onOpenAudioInputDialog() { root.showAudioInputDialog = true; }
            function onOpenBluetoothDialog() { root.showBluetoothDialog = true; }
            function onOpenNightLightDialog() { root.showNightLightDialog = true; }
            function onOpenWifiDialog() { root.showWifiDialog = true; }
        }
    }

    component SystemButtonRow: Item {
        implicitHeight: Math.max(uptimeContainer.implicitHeight, systemButtonsRow.implicitHeight)

        Rectangle {
            id: uptimeContainer
            anchors {
                top: parent.top
                bottom: parent.bottom
                left: parent.left
            }
            color: Appearance.colors.colLayer1
            radius: Appearance.rounding.normal
            implicitWidth: uptimeRow.implicitWidth + 24
            implicitHeight: uptimeRow.implicitHeight + 8

            Row {
                id: uptimeRow
                anchors.centerIn: parent
                spacing: 8
                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 25
                    height: 25

                    CustomIcon {
                        id: distroIcon
                        anchors.fill: parent
                        source: Config.options.custom.distroIcon || SystemInfo.distroIcon
                        colorize: Config.options.custom.colorizeIcon
                        color: Appearance.colors.colOnLayer0
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.showIconPickerDialog = true
                    }
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer0
                    text: Translation.tr("Up • %1").arg(DateTime.uptime)
                    textFormat: Text.MarkdownText
                }
            }
        }

        ButtonGroup {
            id: systemButtonsRow
            anchors {
                top: parent.top
                bottom: parent.bottom
                right: parent.right
            }
            color: Appearance.colors.colLayer1
            padding: 4

            QuickToggleButton {
                toggled: root.editMode
                visible: Config.options.sidebar.quickToggles.style === "android"
                buttonIcon: "edit"
                onClicked: root.editMode = !root.editMode
                StyledToolTip {
                    text: Translation.tr("Edit quick toggles") + (root.editMode ? Translation.tr("\nLMB to enable/disable\nRMB to toggle size\nScroll to swap position") : "")
                }
            }
            QuickToggleButton {
                toggled: false
                buttonIcon: "restart_alt"
                onClicked: {
                    if (WM.compositor === "niri") {
                        Quickshell.execDetached(["niri", "msg", "action", "reload-config"]);
                    } else {
                        Quickshell.execDetached(["hyprctl", "reload"]);
                    }
                    Quickshell.reload(true);
                }
                StyledToolTip {
                    text: WM.compositor === "niri"
                        ? Translation.tr("Reload Niri & Quickshell")
                        : Translation.tr("Reload Hyprland & Quickshell")
                }
            }
            QuickToggleButton {
                toggled: GlobalStates.settingsOpen
                buttonIcon: "settings"
                onClicked: {
                    GlobalStates.sidebarRightOpen = false;
                    GlobalStates.settingsOpen = !GlobalStates.settingsOpen
                }
                StyledToolTip {
                    text: Translation.tr("Settings")
                }
            }
            QuickToggleButton {
                toggled: false
                buttonIcon: "mode_off_on"
                onClicked: GlobalStates.sessionOpen = true
                StyledToolTip {
                    text: Translation.tr("Session")
                }
            }
        }
    }
}
