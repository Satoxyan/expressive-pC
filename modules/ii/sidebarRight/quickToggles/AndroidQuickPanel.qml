import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Bluetooth

import qs.modules.ii.sidebarRight.quickToggles.androidStyle

AbstractQuickPanel {
    id: root
    property bool editMode: false
    property bool limitRows: false
    Layout.fillWidth: true

    visible: root.editMode || root.toggles.length > 0

    readonly property int maxRows: root.limitRows ? 2 : 99
    implicitHeight: (editMode ? contentItem.implicitHeight : usedGrid.implicitHeight) + root.padding * 2
    clip: root.limitRows
    Behavior on implicitHeight {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    property real spacing: 6
    property real padding: 6
    readonly property real baseCellWidth: {
        const availableWidth = root.width - (root.padding * 2) - (root.spacing * (root.columns))
        return availableWidth / root.columns
    }
    readonly property real baseCellHeight: 56

    readonly property list<string> availableToggleTypes: {
        const base = ["network", "bluetooth", "idleInhibitor", "easyEffects", "nightLight", "darkMode", "cloudflareWarp", "gameMode", "screenSnip", "colorPicker", "onScreenKeyboard", "mic", "audio", "notifications", "powerProfile","musicRecognition", "antiFlashbang"]
        return WM.compositor === "hyprland" ? base : base.filter(t => t !== "gameMode")
    }
    readonly property int columns: Config.options.sidebar.quickToggles.android.columns
    readonly property list<var> toggles: {
        if (!Config.ready) return []
        const raw = Config.options.sidebar.quickToggles.android.toggles
        return WM.compositor === "hyprland" ? raw : raw.filter(t => !t || t.type !== "gameMode")
    }
    readonly property list<var> toggleRows: toggleRowsForList(displayToggles)
    readonly property list<var> unusedToggles: {
        const types = availableToggleTypes.filter(type => !toggles.some(toggle => (toggle && toggle.type === type)))
        return types.map(type => { return { type: type, size: 1 } })
    }
    readonly property list<var> unusedToggleRows: toggleRowsForList(unusedToggles)

    // ponytail: live reflow tombol saat di-drag — satu Repeater key-by-type, x/y dihitung sendiri.
    // Posisi datang dari usedLayout, jadi tombol yang pindah BAWAH baris ikut meluncur (bukan pop),
    // dan celahnya otomatis ikut ukuran tombol karena packing pakai `size`.
    property string draggingType: ""
    property int hoverIndex: -1
    property point dragPos
    readonly property var draggedToggle: toggles.find(t => t && t.type === draggingType)
    readonly property list<var> displayToggles: {
        if (draggingType === "" || hoverIndex < 0) return toggles;
        const dragged = draggedToggle;
        if (!dragged) return toggles;
        const rest = toggles.filter(t => t && t.type !== draggingType);
        const at = Math.max(0, Math.min(hoverIndex, rest.length));
        rest.splice(at, 0, dragged);
        return rest;
    }
    readonly property int usedRowCount: Math.min(toggleRows.length, maxRows)
    readonly property list<var> usedToggles: {
        let out = [];
        for (let i = 0; i < usedRowCount; i++) out = out.concat(toggleRows[i]);
        return out;
    }
    readonly property var usedLayout: {
        const out = [];
        let row = 0, col = 0;
        for (const t of usedToggles) {
            if (col + t.size > columns) { row++; col = 0; }
            out.push({ x: col * (baseCellWidth + spacing), y: row * (baseCellHeight + spacing) });
            col += t.size;
        }
        return out;
    }
    readonly property int usedGridHeight: usedRowCount > 0 ? usedRowCount * (baseCellHeight + spacing) - spacing : 0

    function toggleRowsForList(togglesList) {
        var rows = [];
        var row = [];
        var totalSize = 0;
        for (var i = 0; i < togglesList.length; i++) {
            if (!togglesList[i]) continue;
            if (totalSize + togglesList[i].size > columns) {
                rows.push(row);
                row = [];
                totalSize = 0;
            }
            row.push(togglesList[i]);
            totalSize += togglesList[i].size;
        }
        if (row.length > 0) rows.push(row);
        return rows;
    }

    Column {
        id: contentItem
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: 12

        Item {
            id: usedGrid
            width: parent.width
            implicitHeight: root.usedGridHeight

            Repeater {
                model: ScriptModel {
                    values: root.usedToggles
                    objectProp: "type"
                }
                delegate: Item {
                    id: slot
                    x: root.usedLayout[index].x
                    y: root.usedLayout[index].y
                    width: root.baseCellWidth * modelData.size + root.spacing * (modelData.size - 1)
                    height: root.baseCellHeight
                    // slot ditinggal kosong — tombolnya sendiri ada di dragGhost, nempel di kursor
                    opacity: root.draggingType !== "" && root.draggingType === modelData.type ? 0 : 1

                    Behavior on x {
                        enabled: root.draggingType !== ""
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    Behavior on y {
                        enabled: root.draggingType !== ""
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }

                    // DelegateChooser harus jadi delegate Repeater langsung: kalau dibungkus Item,
                    // pilihannya tidak pernah cocok dan tombolnya tidak jadi. Repeater 1-item ini
                    // yang bikin tombol ter-parent ke slot, jadi slot-lah yang memposisikan.
                    Repeater {
                        model: ScriptModel { values: [modelData]; objectProp: "type" }
                        delegate: AndroidToggleDelegateChooser {
                            startingIndex: 0
                            editMode: root.editMode
                            gridRef: usedGrid
                            panelRef: root
                            isUnused: false
                            baseCellWidth: root.baseCellWidth
                            baseCellHeight: root.baseCellHeight
                            spacing: root.spacing
                            onOpenAudioOutputDialog: root.openAudioOutputDialog()
                            onOpenAudioInputDialog: root.openAudioInputDialog()
                            onOpenBluetoothDialog: root.openBluetoothDialog()
                            onOpenNightLightDialog: root.openNightLightDialog()
                            onOpenWifiDialog: root.openWifiDialog()
                        }
                    }
                }
            }

            Item {
                id: dragGhost
                visible: root.draggingType !== "" && !!root.draggedToggle
                z: 999
                x: root.dragPos.x - width / 2
                y: root.dragPos.y - height / 2
                scale: 1.08
                readonly property int gsize: root.draggedToggle ? root.draggedToggle.size : 1
                width: root.baseCellWidth * gsize + root.spacing * (gsize - 1)
                height: root.baseCellHeight

                // ponytail: tanpa Behavior x/y — ghost harus nempel 1:1 di kursor
                Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }

                layer.enabled: true
                layer.effect: DropShadow {
                    horizontalOffset: 0
                    verticalOffset: 6
                    radius: 16
                    color: Qt.rgba(0, 0, 0, 0.3)
                    samples: 33
                }

                Repeater {
                    model: ScriptModel {
                        values: root.draggedToggle ? [root.draggedToggle] : []
                        objectProp: "type"
                    }
                    delegate: AndroidToggleDelegateChooser {
                        startingIndex: 0
                        editMode: false
                        isUnused: false
                        baseCellWidth: root.baseCellWidth
                        baseCellHeight: root.baseCellHeight
                        spacing: root.spacing
                    }
                }
            }
        }

        FadeLoader {
            shown: root.editMode
            anchors {
                left: parent.left
                right: parent.right
                leftMargin: root.baseCellHeight / 2
                rightMargin: root.baseCellHeight / 2
            }
            sourceComponent: Rectangle {
                implicitHeight: 1
                color: Appearance.colors.colOutlineVariant
            }
        }

        FadeLoader {
            shown: root.editMode
            sourceComponent: Column {
                id: unusedRows
                spacing: root.spacing

                Repeater {
                    model: ScriptModel {
                        values: Array(root.unusedToggleRows.length)
                    }
                    delegate: ButtonGroup {
                        id: unusedToggleRow
                        required property int index
                        property var modelData: root.unusedToggleRows[index]
                        spacing: root.spacing

                        Repeater {
                            model: ScriptModel {
                                values: unusedToggleRow?.modelData ?? []
                                objectProp: "type"
                            }
                            delegate: AndroidToggleDelegateChooser {
                                startingIndex: -1
                                editMode: root.editMode
                                isUnused: true
                                baseCellWidth: root.baseCellWidth
                                baseCellHeight: root.baseCellHeight
                                spacing: root.spacing
                            }
                        }
                    }
                }
            }
        }

        ConfigSpinBox {
            visible: root.editMode
            width: parent.width 
            enabled: Config.options.sidebar.quickToggles.style === "android"
            icon: "add_column_left"
            text: Translation.tr("Columns")
            value: Config.options.sidebar.quickToggles.android.columns
            from: 1
            to: 8
            stepSize: 1
            onValueChanged: {
                Config.options.sidebar.quickToggles.android.columns = value;
            }
        }
    }
}