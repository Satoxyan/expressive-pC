import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import Quickshell.Services.SystemTray
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.bar as Bar

Item {
    id: root
    implicitWidth: Appearance.sizes.verticalBarWidth
    height: parent.height

    readonly property real barPadding: 0
    readonly property bool isMaterial: Config.options.bar.cornerStyle === 3 || Config.options.bar.cornerStyle === 4
    readonly property bool isMaterialHug: Config.options.bar.cornerStyle === 4
    readonly property color materialPillBgColor: (Config.options.bar.followFrameColor && Config.options.bar.frameColor)
        ? Appearance.getColorFromName(Config.options.bar.frameColor)
        : Appearance.colors.colLayer0
    readonly property bool trayHasItems: SystemTray.items.values.length > 0

    function filterLayout(layout) {
        if (trayHasItems) return layout
        return layout.filter(name => name !== "sysTray")
    }

    readonly property var effectiveLeftLayout:   filterLayout(Config.options.bar.layouts.leftLayout)
    readonly property var effectiveMiddleLayout: filterLayout(Config.options.bar.layouts.middleLayout)
    readonly property var effectiveRightLayout:  filterLayout(Config.options.bar.layouts.rightLayout)

    readonly property bool centerOnly: !root.isMaterial
        && root.effectiveLeftLayout.length === 0
        && root.effectiveRightLayout.length === 0
    readonly property real centerPillY: centerPill.y
    readonly property real centerPillHeight: centerPill.height

    function shouldPaintMaterialPill(name) {
        if (!root.isMaterial) return false;
        const blacklist = ["workspaces", "divisor", "powerButton", "media", "docktoPanel", "leftSidebarButton", "dynamicIsland"];
        if (blacklist.includes(name)) {
            return false;
        }
        return true;
    }

    function getMaterialPillColor(name) {
        if (!root.isMaterial) return Appearance.colors.colPrimaryContainer;
        switch(name) {
            case "media":
            case "sysTray":
                return Appearance.colors.colSecondaryContainer;
            case "resources":
                return Appearance.colors.colTertiaryContainer;
            case "systemIcons":
                return Appearance.colors.colPrimary; 
            default:
                return Appearance.colors.colPrimaryContainer;
        }
    }

    function getWidgetUrl(name) {
        if (!name) return "";
        let formattedName = name.charAt(0).toUpperCase() + name.slice(1);
        return Qt.resolvedUrl("../bar/" + formattedName + ".qml");
    }

    function getMirroredForIndex(layout, idx) {
        const prevCount = layout.slice(0, idx).filter(w => w === "visualizer").length
        return prevCount % 2 === 1
    }

    property var screen: root.QsWindow.window?.screen

    Rectangle {
        id: barBackground
        anchors {
            fill: parent
            margins: Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0
        }
        color: (!centerOnly && Config.options.bar.showBackground && Config.options.bar.cornerStyle !== 2 && !root.isMaterial)
            ? (Config.options.bar.followFrameColor
                ? Appearance.getColorFromName(Config.options.bar.frameColor)
                : Appearance.colors.colLayer0)
            : "transparent"
        radius: Config.options.bar.cornerStyle === 1 ? Appearance.rounding.windowRounding : 0
        border.width: (!root.centerOnly && Config.options.bar.cornerStyle === 1) ? 1 : 0
        border.color: Config.options.bar.showBackground ? Appearance.colors.colLayer0Border : "transparent"
    }

    // centerOnly
    Rectangle {
        id: centerPill
        visible: root.centerOnly && Config.options.bar.showBackground && Config.options.bar.cornerStyle !== 2
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        height: middleCol.implicitHeight + 7
        width: parent.width - (Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut * 2 : 0)
        color: Config.options.bar.followFrameColor
            ? Appearance.getColorFromName(Config.options.bar.frameColor)
            : Appearance.colors.colLayer0
        radius: Config.options.bar.cornerStyle === 1 ? Appearance.rounding.windowRounding : 0
        border.width: Config.options.bar.cornerStyle === 1 ? 1 : 0
        border.color: Appearance.colors.colLayer0Border

        bottomRightRadius: Config.options.bar.cornerStyle === 0 && !Config.options.bar.bottom ? Appearance.rounding.screenRounding : radius
        topRightRadius:    Config.options.bar.cornerStyle === 0 && !Config.options.bar.bottom ? Appearance.rounding.screenRounding : radius
        bottomLeftRadius:  Config.options.bar.cornerStyle === 0 && Config.options.bar.bottom  ? Appearance.rounding.screenRounding : radius
        topLeftRadius:     Config.options.bar.cornerStyle === 0 && Config.options.bar.bottom  ? Appearance.rounding.screenRounding : radius
    }

    Item {
        id: contentContainer
        anchors.fill: barBackground
        anchors.margins: root.barPadding

        // Top
        Item {
            id: topItem
            anchors.top: parent.top
            anchors.topMargin: root.isMaterialHug ? 0 : (root.isMaterial ? (Appearance.sizes.hyprlandGapsOut || 5) : (Config.options.bar.cornerStyle === 1 ? 4 : 10))
            anchors.left: parent.left
            anchors.right: parent.right
            height: root.isMaterial
                ? (root.effectiveLeftLayout.length > 0 ? (topMaterialPill.height + (root.isMaterialHug ? topBottomOutwardCorner.implicitSize : 0)) : 0)
                : topCol.implicitHeight

            // Material pill wrapper
            Rectangle {
                id: topMaterialPill
                visible: root.isMaterial && root.effectiveLeftLayout.length > 0
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: root.effectiveLeftLayout.length > 0
                    ? (root.isMaterialHug ? (topMaterialCol.implicitHeight + 16) : (topMaterialCol.implicitHeight + 10))
                    : 0
                radius: root.isMaterialHug ? 0 : Appearance.rounding.full
                color: root.materialPillBgColor

                topLeftRadius: 0
                topRightRadius: 0
                bottomLeftRadius: (root.isMaterialHug && Config.options.bar.bottom) ? Appearance.rounding.screenRounding : (root.isMaterialHug ? 0 : radius)
                bottomRightRadius: (root.isMaterialHug && !Config.options.bar.bottom) ? Appearance.rounding.screenRounding : (root.isMaterialHug ? 0 : radius)

                ColumnLayout {
                    id: topMaterialCol
                    anchors.centerIn: parent
                    spacing: 3

                    Repeater {
                        model: root.effectiveLeftLayout
                        delegate: topMaterialGroupDelegate
                    }

                    Component {
                        id: topMaterialGroupDelegate
                        Bar.BarGroup {
                            Layout.fillWidth: true
                            vertical: true
                            currentIndex: index
                            totalCount: root.effectiveLeftLayout.length
                            paintMaterialPill: root.shouldPaintMaterialPill(modelData)
                            bgColor: root.getMaterialPillColor(modelData)
                            Loader {
                                Layout.fillWidth: true
                                source: root.getWidgetUrl(modelData)
                                onLoaded: {
                                    if (item && "vertical" in item) item.vertical = true
                                    if (item && item.hasOwnProperty("mirrored"))
                                        item.mirrored = root.getMirroredForIndex(root.effectiveLeftLayout, index)
                                }
                            }
                        }
                    }
                }
            }

            RoundCorner {
                id: topBottomOutwardCorner
                visible: root.isMaterialHug && root.effectiveLeftLayout.length > 0
                anchors.top: topMaterialPill.bottom
                anchors.left: !Config.options.bar.bottom ? parent.left : undefined
                anchors.right: Config.options.bar.bottom ? parent.right : undefined
                implicitSize: Appearance.rounding.screenRounding
                width: implicitSize
                height: implicitSize
                color: root.materialPillBgColor
                corner: !Config.options.bar.bottom ? RoundCorner.CornerEnum.TopLeft : RoundCorner.CornerEnum.TopRight
            }

            ColumnLayout {
                id: topCol
                anchors.fill: parent
                visible: !root.isMaterial
                spacing: Config.options.bar.borderless === "transparent" ? -4 : Config.options?.bar.borderless === "segmented" ? -2 : 2

                Repeater {
                    model: root.effectiveLeftLayout
                    delegate: Bar.BarGroup {
                        Layout.fillWidth: true
                        vertical: true
                        currentIndex: index
                        totalCount: root.effectiveLeftLayout.length
                        Loader {
                            Layout.fillWidth: true
                            source: root.getWidgetUrl(modelData)
                            onLoaded: {
                                if (item && "vertical" in item) item.vertical = true
                                if (item && item.hasOwnProperty("mirrored"))
                                    item.mirrored = root.getMirroredForIndex(root.effectiveLeftLayout, index)
                            }
                        }
                    }
                }
            }
        }

        // Center
        Item {
            id: absoluteCenter
            anchors.centerIn: parent
            width: parent.width
            height: root.isMaterial
                ? (root.effectiveMiddleLayout.length > 0 ? (centerMaterialPill.height + (root.isMaterialHug ? (centerTopOutwardCorner.implicitSize + centerBottomOutwardCorner.implicitSize) : 0)) : 0)
                : middleCol.implicitHeight

            RoundCorner {
                id: centerTopOutwardCorner
                visible: root.isMaterialHug && root.effectiveMiddleLayout.length > 0
                anchors.bottom: centerMaterialPill.top
                anchors.left: !Config.options.bar.bottom ? parent.left : undefined
                anchors.right: Config.options.bar.bottom ? parent.right : undefined
                implicitSize: Appearance.rounding.screenRounding
                width: implicitSize
                height: implicitSize
                color: root.materialPillBgColor
                corner: !Config.options.bar.bottom ? RoundCorner.CornerEnum.BottomLeft : RoundCorner.CornerEnum.BottomRight
            }

            // Material pill wrapper
            Rectangle {
                id: centerMaterialPill
                visible: root.isMaterial && root.effectiveMiddleLayout.length > 0
                anchors.centerIn: parent
                anchors.left: parent.left
                anchors.right: parent.right
                height: root.effectiveMiddleLayout.length > 0
                    ? (root.isMaterialHug ? (centerMaterialCol.implicitHeight + 16) : (centerMaterialCol.implicitHeight + 10))
                    : 0
                radius: root.isMaterialHug ? 0 : Appearance.rounding.full
                color: root.materialPillBgColor

                topLeftRadius: (root.isMaterialHug && Config.options.bar.bottom) ? Appearance.rounding.screenRounding : (root.isMaterialHug ? 0 : radius)
                bottomLeftRadius: (root.isMaterialHug && Config.options.bar.bottom) ? Appearance.rounding.screenRounding : (root.isMaterialHug ? 0 : radius)
                topRightRadius: (root.isMaterialHug && !Config.options.bar.bottom) ? Appearance.rounding.screenRounding : (root.isMaterialHug ? 0 : radius)
                bottomRightRadius: (root.isMaterialHug && !Config.options.bar.bottom) ? Appearance.rounding.screenRounding : (root.isMaterialHug ? 0 : radius)

                ColumnLayout {
                    id: centerMaterialCol
                    anchors.centerIn: parent
                    spacing: 3

                    Repeater {
                        model: root.effectiveMiddleLayout
                        delegate: centerMaterialGroupDelegate
                    }

                    Component {
                        id: centerMaterialGroupDelegate
                        Bar.BarGroup {
                            Layout.fillWidth: true
                            vertical: true
                            currentIndex: index
                            paintBackground: modelData !== "dynamicIsland"
                            totalCount: root.effectiveMiddleLayout.length
                            paintMaterialPill: root.shouldPaintMaterialPill(modelData)
                            bgColor: root.getMaterialPillColor(modelData)
                            Loader {
                                Layout.fillWidth: true
                                source: root.getWidgetUrl(modelData)
                                onLoaded: {
                                    if (item && "vertical" in item) item.vertical = true
                                    if (item && item.hasOwnProperty("mirrored"))
                                        item.mirrored = root.getMirroredForIndex(root.effectiveMiddleLayout, index)
                                }
                            }
                        }
                    }
                }
            }

            RoundCorner {
                id: centerBottomOutwardCorner
                visible: root.isMaterialHug && root.effectiveMiddleLayout.length > 0
                anchors.top: centerMaterialPill.bottom
                anchors.left: !Config.options.bar.bottom ? parent.left : undefined
                anchors.right: Config.options.bar.bottom ? parent.right : undefined
                implicitSize: Appearance.rounding.screenRounding
                width: implicitSize
                height: implicitSize
                color: root.materialPillBgColor
                corner: !Config.options.bar.bottom ? RoundCorner.CornerEnum.TopLeft : RoundCorner.CornerEnum.TopRight
            }

            ColumnLayout {
                id: middleCol
                anchors.fill: parent
                visible: !root.isMaterial
                spacing: Config.options.bar.borderless === "transparent" ? -4 : Config.options?.bar.borderless === "segmented" ? -2 : 2

                Repeater {
                    model: root.effectiveMiddleLayout
                    delegate: Bar.BarGroup {
                        Layout.fillWidth: true
                        vertical: true
                        currentIndex: index
                        paintBackground: modelData !== "dynamicIsland"
                        totalCount: root.effectiveMiddleLayout.length
                        Loader {
                            Layout.fillWidth: true
                            source: root.getWidgetUrl(modelData)
                            onLoaded: {
                                if (item && "vertical" in item) item.vertical = true
                                if (item && item.hasOwnProperty("mirrored"))
                                    item.mirrored = root.getMirroredForIndex(root.effectiveMiddleLayout, index)
                            }
                        }
                    }
                }
            }
        }

        // Bottom
        Item {
            id: bottomItem
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.isMaterialHug ? 0 : (root.isMaterial ? (Appearance.sizes.hyprlandGapsOut || 5) : (Config.options.bar.cornerStyle === 1 ? 4 : 10))
            anchors.left: parent.left
            anchors.right: parent.right
            height: root.isMaterial
                ? (root.effectiveRightLayout.length > 0 ? (bottomMaterialPill.height + (root.isMaterialHug ? bottomTopOutwardCorner.implicitSize : 0)) : 0)
                : bottomCol.implicitHeight

            RoundCorner {
                id: bottomTopOutwardCorner
                visible: root.isMaterialHug && root.effectiveRightLayout.length > 0
                anchors.bottom: bottomMaterialPill.top
                anchors.left: !Config.options.bar.bottom ? parent.left : undefined
                anchors.right: Config.options.bar.bottom ? parent.right : undefined
                implicitSize: Appearance.rounding.screenRounding
                width: implicitSize
                height: implicitSize
                color: root.materialPillBgColor
                corner: !Config.options.bar.bottom ? RoundCorner.CornerEnum.BottomLeft : RoundCorner.CornerEnum.BottomRight
            }

            // Material pill wrapper
            Rectangle {
                id: bottomMaterialPill
                visible: root.isMaterial && root.effectiveRightLayout.length > 0
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: root.effectiveRightLayout.length > 0
                    ? (root.isMaterialHug ? (bottomMaterialCol.implicitHeight + 16) : (bottomMaterialCol.implicitHeight + 10))
                    : 0
                radius: root.isMaterialHug ? 0 : Appearance.rounding.full
                color: root.materialPillBgColor

                bottomLeftRadius: 0
                bottomRightRadius: 0
                topLeftRadius: (root.isMaterialHug && Config.options.bar.bottom) ? Appearance.rounding.screenRounding : (root.isMaterialHug ? 0 : radius)
                topRightRadius: (root.isMaterialHug && !Config.options.bar.bottom) ? Appearance.rounding.screenRounding : (root.isMaterialHug ? 0 : radius)

                ColumnLayout {
                    id: bottomMaterialCol
                    anchors.centerIn: parent
                    spacing: 3

                    Repeater {
                        model: root.effectiveRightLayout
                        delegate: bottomMaterialGroupDelegate
                    }

                    Component {
                        id: bottomMaterialGroupDelegate
                        Bar.BarGroup {
                            Layout.fillWidth: true
                            vertical: true
                            currentIndex: index
                            totalCount: root.effectiveRightLayout.length
                            paintMaterialPill: root.shouldPaintMaterialPill(modelData)
                            bgColor: root.getMaterialPillColor(modelData)
                            Loader {
                                Layout.fillWidth: true
                                source: root.getWidgetUrl(modelData)
                                onLoaded: {
                                    if (item && "vertical" in item) item.vertical = true
                                    if (item && item.hasOwnProperty("mirrored"))
                                        item.mirrored = root.getMirroredForIndex(root.effectiveRightLayout, index)
                                }
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                id: bottomCol
                anchors.fill: parent
                visible: !root.isMaterial
                spacing: Config.options.bar.borderless === "transparent" ? -4 : Config.options?.bar.borderless === "segmented" ? -2 : 2

                Repeater {
                    model: root.effectiveRightLayout
                    delegate: Bar.BarGroup {
                        Layout.fillWidth: true
                        vertical: true
                        currentIndex: index
                        totalCount: root.effectiveRightLayout.length
                        Loader {
                            Layout.fillWidth: true
                            source: root.getWidgetUrl(modelData)
                            onLoaded: {
                                if (item && "vertical" in item) item.vertical = true
                                if (item && item.hasOwnProperty("mirrored"))
                                    item.mirrored = root.getMirroredForIndex(root.effectiveRightLayout, index)
                            }
                        }
                    }
                }
            }
        }
    }
}