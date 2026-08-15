import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Quickshell.Hyprland


ContentPage {
    id: page
    forceWidth: true

    function goTo(term) {
        const t = term.toLowerCase().trim()

        function findTarget(rootItem) {
            for (let i = 0; i < rootItem.children.length; i++) {
                let child = rootItem.children[i]
                if (child.title && child.title.toLowerCase().includes(t)) {
                    return child
                }
            }

            for (let i = 0; i < rootItem.children.length; i++) {
                let found = findTarget(rootItem.children[i])
                if (found) return found
            }
            return null
        }

        let target = findTarget(mainLayout)
        if (target) {
            let pos = target.mapToItem(mainLayout, 0, 0)
            page.contentY = Math.max(0, pos.y - 0)
        }
    }

    function displayPathFor(path) {
        return /\.(mp4|webm|mkv|avi|mov)$/i.test(path)
            ? Config.options.background.thumbnailPath
            : path
    }

    ColumnLayout {
        id: mainLayout 
        Layout.fillWidth: true   
        Layout.fillHeight: true
        spacing: 20
            
        ContentSection {
            icon: "panorama"
            title: Translation.tr("Wallpaper")
            shape: MaterialShape.Shape.Clover4Leaf

            Rectangle {
                Layout.fillWidth: true
                visible: WM.compositor !== "niri"
                implicitHeight: wrapperCol.implicitHeight + 16
                topLeftRadius: Appearance.rounding.verylarge
                topRightRadius: Appearance.rounding.verylarge
                bottomLeftRadius: Appearance.rounding.normal
                bottomRightRadius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1

                ColumnLayout {
                    id: wrapperCol
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8

                    Carousel {
                        Layout.fillWidth: true
                        implicitHeight: 280
                        largeItemWidthRatio: 0.5
                        mediumItemWidthRatio: 0.485
                        itemSpacing: 8
                        model: [
                            page.displayPathFor(Config.options.background.wallpaperPath),
                            page.displayPathFor(
                                Config.options.background.lockWall !== ""
                                    ? Config.options.background.lockWall
                                    : Config.options.background.wallpaperPath
                            )
                        ]
                        wheelEnabled: false
                        dragEnabled: false
                        clickAction: (index, modelData) => {
                            GlobalStates.wallpaperSelectorTarget = index === 1 ? "lockWall" : "wallpaper"
                            GlobalStates.wallpaperSelectorOpen = true
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 24
                            radius: Appearance.rounding.normal
                            color: "transparent"

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 8
                                MaterialSymbol {
                                    text: "desktop_windows"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colPrimary
                                }
                                StyledText {
                                    text: Translation.tr("Desktop")
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colOnLayer1
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 24
                            radius: Appearance.rounding.normal
                            color: "transparent"

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 8
                                MaterialSymbol {
                                    text: "lock"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colPrimary
                                }
                                StyledText {
                                    text: Translation.tr("Lockscreen")
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colOnLayer1
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                visible: WM.compositor === "niri"
                implicitHeight: niriWrapperCol.implicitHeight + 16
                topLeftRadius: Appearance.rounding.verylarge
                topRightRadius: Appearance.rounding.verylarge
                bottomLeftRadius: Appearance.rounding.normal
                bottomRightRadius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1

                ColumnLayout {
                    id: niriWrapperCol
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8

                    Carousel {
                        Layout.fillWidth: true
                        implicitHeight: 280
                        largeItemWidthRatio: 1
                        mediumItemWidthRatio: 0
                        itemSpacing: 8
                        model: [page.displayPathFor(Config.options.background.wallpaperPath)]
                        wheelEnabled: false
                        dragEnabled: false
                        clickAction: (index, modelData) => {
                            GlobalStates.wallpaperSelectorTarget = "wallpaper"
                            GlobalStates.wallpaperSelectorOpen = true
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 24
                        radius: Appearance.rounding.normal
                        color: "transparent"

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 8
                            MaterialSymbol {
                                text: "image"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colPrimary
                            }
                            StyledText {
                                text: Config.options.background.wallpaperPath.split("/").pop()
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnLayer1
                                elide: Text.ElideMiddle
                            }
                        }
                    }
                }
            }

            GroupedList {
                Layout.topMargin: -2

                ConfigSwitch {
                    id: syncWallpaperSwitch
                    buttonIcon: "sync"
                    text: Translation.tr("Use same wallpaper for both")
                    checked: Config.options.background.lockWall === ""
                    onCheckedChanged: {
                        if (checked) {
                            Config.options.background.lockWall = "";
                        }
                    }
                }

                ConfigSwitch {
                    buttonIcon: "preview"
                    text: Translation.tr("Preview wallpaper")
                    checked: Config.options.background.enableWallpaperPreview
                    onCheckedChanged: {
                        Config.options.background.enableWallpaperPreview = checked;
                    }
                }

                ConfigSpinBox {
                    icon: "timer"
                    text: Translation.tr("Wallpaper change interval (min)")
                    value: Config.options.wallpaperSelector.changeInterval / 60000
                    from: 0
                    to: 1440
                    stepSize: 5
                    onValueChanged: {
                        Config.options.wallpaperSelector.changeInterval = value * 60000;
                    }
                }

                ConfigComboBox {
                    Layout.fillWidth: true
                    buttonIcon: "texture"
                    text: Translation.tr("Transitions")
                    fieldWidth: 50
                    model: [
                        { displayName: Translation.tr("None"), icon: "block", value: "" },
                        { displayName: Translation.tr("Circle"), icon: "circle", value: "circleSelect" },
                        { displayName: Translation.tr("Circle Pit"), icon: "blur_circular", value: "circlePit" },
                        { displayName: Translation.tr("Magic"), icon: "auto_awesome", value: "magic" },
                        { displayName: Translation.tr("Doom"), icon: "whatshot", value: "Doom" },
                        { displayName: Translation.tr("Peel"), icon: "layers", value: "Peel" },
                        { displayName: Translation.tr("Fade"), icon: "gradient", value: "transition" },
                        { displayName: Translation.tr("Pixelate"), icon: "grain", value: "pixelate" },
                        { displayName: Translation.tr("Stripes"), icon: "texture_minus", value: "stripes" },
                        { displayName: Translation.tr("Random"), icon: "shuffle", value: "random" },
                    ]
                    currentValue: Config.options.background.wallpaperAnimation
                    onSelected: newValue => {
                        Config.options.background.wallpaperAnimation = newValue;
                    }
                }
            }

            Connections {
                target: Config.options.background
                function onLockWallChanged() {
                    syncWallpaperSwitch.checked = Qt.binding(() => Config.options.background.lockWall === "")
                }
            }
        
            ContentSubsection {
                title: Translation.tr("Centered wallpaper")
                Layout.fillWidth: true

                GroupedList {
                    ConfigSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "check"
                        text: Translation.tr("Enable")
                        checked: Config.options.background.centeredWallpaper
                        onClicked: {
                            Config.options.background.centeredWallpaper = !Config.options.background.centeredWallpaper;
                        }
                    }
                    ConfigSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "lock"
                        text: Translation.tr("Show only when locked")
                        checked: Config.options.background.centeredWallpaperOnlyWhenLocked
                        onCheckedChanged: {
                            Config.options.background.centeredWallpaperOnlyWhenLocked = checked;
                        }
                        enabled: Config.options.background.centeredWallpaper && WM.compositor !== "niri"
                    }
                }

                GroupedList {
                    Layout.topMargin: 0
                    visible: Config.options.background.centeredWallpaper
                    ConfigSelectionShapeArray {
                        currentValue: Config.options.background.centeredWallpaperShape
                        shapeColor: Appearance.colors.colPrimary
                        backgroundColor: Appearance.colors.colPrimaryContainer
                        options: [
                            "Circle", "Square", "Slanted", "Arch", "Arrow", "SemiCircle", "Oval", "Pill",
                            "Triangle", "Diamond", "ClamShell", "Pentagon", "Gem", "Sunny", "VerySunny",
                            "Cookie4Sided", "Cookie6Sided", "Cookie7Sided", "Cookie9Sided", "Cookie12Sided",
                            "Ghostish", "Clover4Leaf", "Clover8Leaf", "Burst", "SoftBurst", "Flower",
                            "Puffy", "PuffyDiamond", "PixelCircle", "Bun", "Heart"
                        ]
                        onSelected: newValue => {
                            Config.options.background.centeredWallpaperShape = newValue
                        }
                    }
                    ColorSelectionArray {
                        visible: Config.options.background.centeredWallpaper
                        icon: "palette"
                        text: Translation.tr("Background Color")
                        currentValue: Config.options.background.centeredWallpaperColor
                        onSelected: newValue => {
                            Config.options.background.centeredWallpaperColor = newValue
                        }
                    }
                    ConfigSlider {
                        visible: Config.options.background.centeredWallpaper
                        text: Translation.tr("Size")
                        value: Config.options.background.centeredWallpaperSize
                        usePercentTooltip: false
                        buttonIcon: "aspect_ratio"
                        from: 400
                        to: 800
                        stopIndicatorValues: [400]
                        onValueChanged: {
                            Config.options.background.centeredWallpaperSize = value;
                        }
                    }
                }
            }
        }

        ContentSection {
            id: settingsClock
            icon: "clock_loader_40"
            shape: MaterialShape.Shape.Bun
            title: Translation.tr("Clock")

            function stylePresent(styleName) {
                if (!Config.options.background.widgets.clock.showOnlyWhenLocked && Config.options.background.widgets.clock.style === styleName) {
                    return true;
                }
                if (Config.options.background.widgets.clock.styleLocked === styleName) {
                    return true;
                }
                return false;
            }

            readonly property bool digitalPresent: stylePresent("digital")
            readonly property bool cookiePresent: stylePresent("cookie")

            GroupedList {
                ConfigSwitch {
                    Layout.fillWidth: false
                    buttonIcon: "check"
                    text: Translation.tr("Enable")
                    checked: Config.options.background.widgets.clock.enable
                    onCheckedChanged: {
                        Config.options.background.widgets.clock.enable = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "lock_clock"
                    text: Translation.tr("Show only when locked")
                    enabled: WM.compositor !== "niri"
                    checked: Config.options.background.widgets.clock.showOnlyWhenLocked
                    onCheckedChanged: {
                        Config.options.background.widgets.clock.showOnlyWhenLocked = checked;
                    }
                }
                ConfigSelectionArray {
                    text: Translation.tr("Placement strategy")
                    icon: "move"
                    Layout.fillWidth: false
                    currentValue: Config.options.background.widgets.clock.placementStrategy
                    onSelected: newValue => {
                        Config.options.background.widgets.clock.placementStrategy = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Draggable"),
                            icon: "drag_pan",
                            value: "free"
                        },
                        {
                            displayName: Translation.tr("Least busy"),
                            icon: "category",
                            value: "leastBusy"
                        },
                        {
                            displayName: Translation.tr("Most busy"),
                            icon: "shapes",
                            value: "mostBusy"
                        },
                    ]
                }
                ConfigSelectionArray {
                    text: Translation.tr("Clock style")
                    icon: "nest_clock_farsight_analog"
                    currentValue: Config.options.background.widgets.clock.style
                    onSelected: newValue => {
                        Config.options.background.widgets.clock.style = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Digital"),
                            icon: "timer_10",
                            value: "digital"
                        },
                        {
                            displayName: Translation.tr("Cookie"),
                            icon: "cookie",
                            value: "cookie"
                        },
                        {
                            displayName: Translation.tr("Pixel"),
                            icon: "grid_view",
                            value: "pixel"
                        }
                    ]
                }
                ConfigSelectionArray {
                    text: Translation.tr("Clock style (locked)")
                    icon: "shield_watch"
                    currentValue: Config.options.background.widgets.clock.styleLocked
                    onSelected: newValue => {
                        Config.options.background.widgets.clock.styleLocked = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Digital"),
                            icon: "timer_10",
                            value: "digital"
                        },
                        {
                            displayName: Translation.tr("Cookie"),
                            icon: "cookie",
                            value: "cookie"
                        },
                        {
                            displayName: Translation.tr("Pixel"),
                            icon: "grid_view",
                            value: "pixel"
                        }
                    ]
                }
            }

            ContentSubsection {
                visible: settingsClock.digitalPresent
                title: Translation.tr("Digital clock settings")

                ConfigRow {
                    uniform: true

                    GroupedList {
                        ConfigSwitch {
                            buttonIcon: "vertical_distribute"
                            text: Translation.tr("Vertical")
                            checked: Config.options.background.widgets.clock.digital.vertical
                            onCheckedChanged: { Config.options.background.widgets.clock.digital.vertical = checked }
                        }
                        ConfigSwitch {
                            buttonIcon: "vertical_distribute"
                            text: Translation.tr("Vertical (lock)")
                            checked: Config.options.background.widgets.clock.digital.verticalLocked
                            onCheckedChanged: { Config.options.background.widgets.clock.digital.verticalLocked = checked }
                        }
                        ConfigSwitch {
                            buttonIcon: "date_range"
                            text: Translation.tr("Show date")
                            checked: Config.options.background.widgets.clock.digital.showDate
                            onCheckedChanged: { Config.options.background.widgets.clock.digital.showDate = checked }
                        }
                    }

                    GroupedList {
                        ConfigSwitch {
                            buttonIcon: "animation"
                            text: Translation.tr("Animate time change")
                            checked: Config.options.background.widgets.clock.digital.animateChange
                            onCheckedChanged: { Config.options.background.widgets.clock.digital.animateChange = checked }
                        }
                        ConfigSwitch {
                            buttonIcon: "activity_zone"
                            text: Translation.tr("Use adaptive alignment")
                            checked: Config.options.background.widgets.clock.digital.adaptiveAlignment
                            onCheckedChanged: { Config.options.background.widgets.clock.digital.adaptiveAlignment = checked }
                        }
                    }
                }

                GroupedList {
                    ConfigSwitch {
                        id: autoColorSwitch
                        buttonIcon: "auto_awesome"
                        text: Translation.tr("Automatic colors")
                        checked: Config.options.background.widgets.clock.color === ""
                        onCheckedChanged: {
                            if (checked) {
                                Config.options.background.widgets.clock.color = ""
                            }
                        }
                    }

                    ColorSelectionArray {
                        icon: "palette"
                        text: Translation.tr("Color")
                        currentValue: Config.options.background.widgets.clock.color
                        onSelected: newValue => {
                            Config.options.background.widgets.clock.color = newValue
                            autoColorSwitch.checked = false
                        }
                    }
                }

                GroupedList {
                    ConfigSelectionArray {
                        text: Translation.tr("Clock color")
                        icon: "light_mode"
                        currentValue: Config.options.background.widgets.clock.digital.colorMode
                        onSelected: newValue => {
                            Config.options.background.widgets.clock.digital.colorMode = newValue;
                        }
                        options: [
                            {
                                displayName: Translation.tr("Auto"),
                                icon: "auto_fix_high",
                                value: "auto"
                            },
                            {
                                displayName: Translation.tr("Light"),
                                icon: "light_mode",
                                value: "light"
                            },
                            {
                                displayName: Translation.tr("Dark"),
                                icon: "dark_mode",
                                value: "dark"
                            }
                        ]
                    }

                    ConfigSelectionArray {
                        text: Translation.tr("Clock color (locked)")
                        icon: "dark_mode"
                        currentValue: Config.options.background.widgets.clock.digital.colorModeLocked
                        onSelected: newValue => {
                            Config.options.background.widgets.clock.digital.colorModeLocked = newValue;
                        }
                        options: [
                            {
                                displayName: Translation.tr("Auto"),
                                icon: "auto_fix_high",
                                value: "auto"
                            },
                            {
                                displayName: Translation.tr("Light"),
                                icon: "light_mode",
                                value: "light"
                            },
                            {
                                displayName: Translation.tr("Dark"),
                                icon: "dark_mode",
                                value: "dark"
                            }
                        ]
                    }
                }

                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Font family")
                    text: Config.options.background.widgets.clock.digital.font.family
                    wrapMode: TextEdit.Wrap

                    Timer {
                        id: debounceTimer
                        interval: 500
                        repeat: false
                        onTriggered: {
                            Config.options.background.widgets.clock.digital.font.family = parent.text
                        }
                    }

                    onTextChanged: {
                        debounceTimer.restart()
                    }
                }
                GroupedList {
                    Layout.topMargin: 10
                    ConfigSlider {
                        text: Translation.tr("Font weight")
                        value: Config.options.background.widgets.clock.digital.font.weight
                        usePercentTooltip: false
                        buttonIcon: "format_bold"
                        from: 1
                        to: 1000
                        stopIndicatorValues: [350]
                        onValueChanged: {
                            Config.options.background.widgets.clock.digital.font.weight = value;
                        }
                    }

                    ConfigSlider {
                        text: Translation.tr("Font size")
                        value: Config.options.background.widgets.clock.digital.font.size
                        usePercentTooltip: false
                        buttonIcon: "format_size"
                        from: 50
                        to: 700
                        stopIndicatorValues: [90]
                        onValueChanged: {
                            Config.options.background.widgets.clock.digital.font.size = value;
                        }
                    }

                    ConfigSlider {
                        text: Translation.tr("Font width")
                        value: Config.options.background.widgets.clock.digital.font.width
                        usePercentTooltip: false
                        buttonIcon: "fit_width"
                        from: 25
                        to: 125
                        stopIndicatorValues: [100]
                        onValueChanged: {
                            Config.options.background.widgets.clock.digital.font.width = value;
                        }
                    }
                    ConfigSlider {
                        text: Translation.tr("Font roundness")
                        value: Config.options.background.widgets.clock.digital.font.roundness
                        usePercentTooltip: false
                        buttonIcon: "line_curve"
                        from: 0
                        to: 100
                        onValueChanged: {
                            Config.options.background.widgets.clock.digital.font.roundness = value;
                        }
                    }
                }
            }

            ContentSubsection {
                visible: settingsClock.cookiePresent
                title: Translation.tr("Cookie clock settings")
                GroupedList {   
                    ConfigSwitch {  
                        buttonIcon: "wand_stars"
                        text: Translation.tr("Auto styling with Gemini")
                        checked: Config.options.background.widgets.clock.cookie.aiStyling
                        onCheckedChanged: {
                            Config.options.background.widgets.clock.cookie.aiStyling = checked;
                        }
                    }

                    ConfigSwitch {
                        buttonIcon: "airwave"
                        text: Translation.tr("Use old sine wave cookie implementation")
                        checked: Config.options.background.widgets.clock.cookie.useSineCookie
                        onCheckedChanged: {
                            Config.options.background.widgets.clock.cookie.useSineCookie = checked;
                        }
                    }

                    ConfigSpinBox {
                        icon: "add_triangle"
                        text: Translation.tr("Sides")
                        value: Config.options.background.widgets.clock.cookie.sides
                        from: 0
                        to: 40
                        stepSize: 1
                        onValueChanged: {
                            Config.options.background.widgets.clock.cookie.sides = value;
                        }
                    }

                    ConfigSwitch {
                        buttonIcon: "autoplay"
                        text: Translation.tr("Constantly rotate")
                        checked: Config.options.background.widgets.clock.cookie.constantlyRotate
                        onCheckedChanged: {
                            Config.options.background.widgets.clock.cookie.constantlyRotate = checked;
                        }
                    }

                    ConfigRow {

                        ConfigSwitch {
                            enabled: Config.options.background.widgets.clock.cookie.dialNumberStyle === "dots" || Config.options.background.widgets.clock.cookie.dialNumberStyle === "full"
                            buttonIcon: "brightness_7"
                            text: Translation.tr("Hour marks")
                            checked: Config.options.background.widgets.clock.cookie.hourMarks
                            onEnabledChanged: {
                                checked = Config.options.background.widgets.clock.cookie.hourMarks;
                            }
                            onCheckedChanged: {
                                Config.options.background.widgets.clock.cookie.hourMarks = checked;
                            }
                        }

                        ConfigSwitch {
                            enabled: Config.options.background.widgets.clock.cookie.dialNumberStyle !== "numbers"
                            buttonIcon: "timer_10"
                            text: Translation.tr("Digits in the middle")
                            checked: Config.options.background.widgets.clock.cookie.timeIndicators
                            onEnabledChanged: {
                                checked = Config.options.background.widgets.clock.cookie.timeIndicators;
                            }
                            onCheckedChanged: {
                                Config.options.background.widgets.clock.cookie.timeIndicators = checked;
                            }
                        }
                    }
                }
            }

            GroupedList {
                Layout.topMargin: 10
                visible: settingsClock.cookiePresent
                ConfigSelectionArray {
                    text: "Dial Style"
                    icon: "graph_6"
                    currentValue: Config.options.background.widgets.clock.cookie.dialNumberStyle
                    onSelected: newValue => {
                        Config.options.background.widgets.clock.cookie.dialNumberStyle = newValue;
                        if (newValue !== "dots" && newValue !== "full") {
                            Config.options.background.widgets.clock.cookie.hourMarks = false;
                        }
                        if (newValue === "numbers") {
                            Config.options.background.widgets.clock.cookie.timeIndicators = false;
                        }
                    }
                    options: [
                        {
                            displayName: "",
                            icon: "block",
                            value: "none"
                        },
                        {
                            displayName: Translation.tr("Dots"),
                            icon: "graph_6",
                            value: "dots"
                        },
                        {
                            displayName: Translation.tr("Full"),
                            icon: "history_toggle_off",
                            value: "full"
                        },
                        {
                            displayName: Translation.tr("Numbers"),
                            icon: "counter_1",
                            value: "numbers"
                        }
                    ]
                }
                ConfigSelectionArray {
                    icon: "highlighter_size_2"
                    text: Translation.tr("Hour hand")
                    currentValue: Config.options.background.widgets.clock.cookie.hourHandStyle
                    onSelected: newValue => {
                        Config.options.background.widgets.clock.cookie.hourHandStyle = newValue;
                    }
                    options: [
                        {
                            displayName: "",
                            icon: "block",
                            value: "hide"
                        },
                        {
                            displayName: Translation.tr("Classic"),
                            icon: "radio",
                            value: "classic"
                        },
                        {
                            displayName: Translation.tr("Hollow"),
                            icon: "circle",
                            value: "hollow"
                        },
                        {
                            displayName: Translation.tr("Fill"),
                            icon: "eraser_size_5",
                            value: "fill"
                        },
                    ]
                }
                ConfigSelectionArray {
                    text: Translation.tr("Minute hand")
                    icon: "eraser_size_1" 
                    currentValue: Config.options.background.widgets.clock.cookie.minuteHandStyle
                    onSelected: newValue => {
                        Config.options.background.widgets.clock.cookie.minuteHandStyle = newValue;
                    }
                    options: [
                        {
                            displayName: "",
                            icon: "block",
                            value: "hide"
                        },
                        {
                            displayName: Translation.tr("Classic"),
                            icon: "radio",
                            value: "classic"
                        },
                        {
                            displayName: Translation.tr("Thin"),
                            icon: "line_end",
                            value: "thin"
                        },
                        {
                            displayName: Translation.tr("Medium"),
                            icon: "eraser_size_2",
                            value: "medium"
                        },
                        {
                            displayName: Translation.tr("Bold"),
                            icon: "eraser_size_4",
                            value: "bold"
                        },
                    ]
                }
                ConfigSelectionArray {
                    text: Translation.tr("Second hand")
                    icon: "pen_size_1"
                    currentValue: Config.options.background.widgets.clock.cookie.secondHandStyle
                    onSelected: newValue => {
                        Config.options.background.widgets.clock.cookie.secondHandStyle = newValue;
                    }
                    options: [
                        {
                            displayName: "",
                            icon: "block",
                            value: "hide"
                        },
                        {
                            displayName: Translation.tr("Classic"),
                            icon: "radio",
                            value: "classic"
                        },
                        {
                            displayName: Translation.tr("Line"),
                            icon: "line_end",
                            value: "line"
                        },
                        {
                            displayName: Translation.tr("Dot"),
                            icon: "adjust",
                            value: "dot"
                        },
                    ]
                }
                ConfigSelectionArray {
                    text: Translation.tr("Date style")
                    icon: "date_range"
                    currentValue: Config.options.background.widgets.clock.cookie.dateStyle
                    onSelected: newValue => {
                        Config.options.background.widgets.clock.cookie.dateStyle = newValue;
                    }
                    options: [
                        {
                            displayName: "",
                            icon: "block",
                            value: "hide"
                        },
                        {
                            displayName: Translation.tr("Bubble"),
                            icon: "bubble_chart",
                            value: "bubble"
                        },
                        {
                            displayName: Translation.tr("Border"),
                            icon: "rotate_right",
                            value: "border"
                        },
                        {
                            displayName: Translation.tr("Rect"),
                            icon: "rectangle",
                            value: "rect"
                        }
                    ]
                }
            }
            
            ContentSubsection {
                visible: Config.options.background.widgets.clock.style === "pixel"
                title: Translation.tr("Pixel Clock Settings")
                GroupedList {
                    visible: Config.options.background.widgets.clock.style === "pixel"
                    ConfigSelectionArray {
                        text: Translation.tr("Pixel clock orientation")
                        visible: Config.options.background.widgets.clock.style === "pixel"
                        icon: "screen_rotation"
                        currentValue: Config.options.background.widgets.clock.pixel.orientation
                        onSelected: newValue => {
                            Config.options.background.widgets.clock.pixel.orientation = newValue;
                        }
                        options: [
                            {
                                displayName: Translation.tr("Horizontal"),
                                icon: "swap_horiz",
                                value: "horizontal"
                            },
                            {
                                displayName: Translation.tr("Vertical"),
                                icon: "swap_vert",
                                value: "vertical"
                            }
                        ]
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Quote")
                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "check"
                        text: Translation.tr("Enable")
                        checked: Config.options.background.widgets.clock.quote.enable
                        onCheckedChanged: {
                            Config.options.background.widgets.clock.quote.enable = checked;
                        }
                    }
                    ConfigSwitch {
                        buttonIcon: "font_download"
                        text: Translation.tr("Follow Clock Font")
                        enabled: Config.options.background.widgets.clock.style !== "pixel"
                        checked: Config.options.background.widgets.clock.quote.followClock
                        onCheckedChanged: {
                            Config.options.background.widgets.clock.quote.followClock = checked;
                        }
                    }
                    ConfigTextArea {
                        id: quoteField
                        Layout.fillWidth: true
                        fieldWidth: 300
                        buttonIcon: "format_quote"
                        text: Translation.tr("Quote")
                        placeholderText: Translation.tr("Quote")
                        value: Config.options.background.widgets.clock.quote.text
                        onValueChanged: {
                            quoteDebounceTimer.restart();
                        }

                        Timer {
                            id: quoteDebounceTimer
                            interval: 600
                            repeat: false
                            onTriggered: {
                                Config.options.background.widgets.clock.quote.text = quoteField.value;
                            }
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "panorama"
            shape: MaterialShape.Shape.SoftBoom 
            title: Translation.tr("Custom Image")
            GroupedList {
                ConfigSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "check"
                    text: Translation.tr("Enable")
                    checked: Config.options.background.widgets.customImage.enable
                    onCheckedChanged: {
                        Config.options.background.widgets.customImage.enable = checked;
                    }
                }
                ConfigSelectionShapeArray {
                    currentValue: Config.options.background.widgets.customImage.shape
                    shapeColor: Appearance.colors.colPrimary
                    backgroundColor: Appearance.colors.colPrimaryContainer
                    options: [
                        "Circle", "Square", "Slanted", "Arch", "Arrow", "SemiCircle", "Oval", "Pill",
                        "Triangle", "Diamond", "ClamShell", "Pentagon", "Gem", "Sunny", "VerySunny",
                        "Cookie4Sided", "Cookie6Sided", "Cookie7Sided", "Cookie9Sided", "Cookie12Sided",
                        "Ghostish", "Clover4Leaf", "Clover8Leaf", "Burst", "SoftBurst", "Flower",
                        "Puffy", "PuffyDiamond", "PixelCircle", "Bun", "Heart"
                    ]
                    onSelected: newValue => {
                        Config.options.background.widgets.customImage.shape = newValue
                    }
                }
            }
        }

        ContentSection {
            icon: "widgets"
            shape: MaterialShape.Shape.Pill
            title: Translation.tr("Widgets")

            ContentSubsection {
                title: Translation.tr("Show widgets on")
                visible: Hyprland.monitors.values.length > 1
                Layout.bottomMargin: 10

                WidgetsMonitorSelector {
                    configEntry: Config.options.background
                }
            }
            
            GridLayout {
                Layout.fillWidth: true
                columns: 3
                rowSpacing: 8
                columnSpacing: 8
                Repeater {
                    model: [
                        {
                            icon: "weather_mix",
                            name: Translation.tr("Weather"),
                            enabled: Config.options.background.widgets.weather.enable
                        },
                        {
                            icon: "image",
                            name: Translation.tr("Image converter"),
                            enabled: Config.options.background.widgets.images.enable
                        },
                        {
                            icon: "music_note",
                            name: Translation.tr("Media Player"),
                            enabled: Config.options.background.widgets.media.enable
                        },
                        {
                            icon: "memory",
                            name: Translation.tr("Resources"),
                            enabled: Config.options.background.widgets.resources.enable
                        },
                        {
                            icon: "graphic_eq",
                            name: Translation.tr("Visualizer"),
                            enabled: Config.options.background.widgets.visualizer.enable
                        },
                        {
                            icon: "calendar_month",
                            name: Translation.tr("Calendar"),
                            enabled: Config.options.background.widgets.calendar.enable
                        },
                        {
                            icon: "public",
                            name: Translation.tr("World Clock"),
                            enabled: Config.options.background.widgets.worldClock.enable
                        },
                        {
                            icon: "person",
                            name: Translation.tr("User Card"),
                            enabled: Config.options.background.widgets.userCard.enable
                        },
                        {
                            icon: "note_stack_add",
                            name: Translation.tr("Notes"),
                            enabled: Config.options.background.widgets.notes.enable
                        }
                    ]
                    delegate: Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 105
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colLayer1
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border
                        ColumnLayout {
                            anchors {
                                top: parent.top
                                left: parent.left
                                right: parent.right
                                margins: 12
                            }
                            spacing: 0
                            RowLayout {
                                Layout.fillWidth: true
                                MaterialSymbol {
                                    text: modelData.icon
                                    iconSize: Appearance.font.pixelSize.normal + 5
                                    color: Appearance.colors.colPrimary
                                }
                                Item { Layout.fillWidth: true }
                                ConfigSwitch {
                                    Layout.fillWidth: false
                                    checked: modelData.enabled
                                    onCheckedChanged: {
                                        if (modelData.icon === "weather_mix")
                                            Config.options.background.widgets.weather.enable = checked
                                        else if (modelData.icon === "image")
                                            Config.options.background.widgets.images.enable = checked
                                        else if (modelData.icon === "music_note")
                                            Config.options.background.widgets.media.enable = checked
                                        else if (modelData.icon === "memory")
                                            Config.options.background.widgets.resources.enable = checked
                                        else if (modelData.icon === "graphic_eq")
                                            Config.options.background.widgets.visualizer.enable = checked
                                        else if (modelData.icon === "calendar_month")
                                            Config.options.background.widgets.calendar.enable = checked
                                        else if (modelData.icon === "public")
                                            Config.options.background.widgets.worldClock.enable = checked
                                        else if (modelData.icon === "person")
                                            Config.options.background.widgets.userCard.enable = checked
                                        else if (modelData.icon === "note_stack_add")
                                            Config.options.background.widgets.notes.enable = checked
                                    }
                                }
                            }
                            StyledText {
                                text: modelData.name
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                text: modelData.enabled ? Translation.tr("Enabled") : Translation.tr("Disabled")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }
                }
            }
            ContentSubsection {
                title: Translation.tr("Canvas")
                Layout.bottomMargin: 10

                GroupedList {
                    ConfigSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "grid_4x4"
                        text: Translation.tr("Show alignment grid while dragging")
                        checked: Config.options.background.showGrid
                        onCheckedChanged: {
                            Config.options.background.showGrid = checked;
                        }
                    }
                    ConfigSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "align_horizontal_center"
                        text: Translation.tr("Show snap lines when dropping")
                        checked: Config.options.background.showSnapLines
                        onCheckedChanged: {
                            Config.options.background.showSnapLines = checked;
                        }
                    }
                }
            }
        }

        ContentSection {
            id: visualizerSection
            icon: "graphic_eq"
            shape: MaterialShape.Shape.Pill
            title: Translation.tr("Visualizer")
            visible: Config.options.background.widgets.visualizer.enable

            readonly property bool isWave: Config.options.background.widgets.visualizer.mode === "wave"
            readonly property bool isDefault: Config.options.background.widgets.visualizer.mode === "default"

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 16

                ConfigRow {
                    Layout.fillWidth: true

                    GroupedList {
                        ConfigSelectionArray {
                            Layout.fillWidth: false
                            currentValue: Config.options.background.widgets.visualizer.mode
                            onSelected: newValue => {
                                Config.options.background.widgets.visualizer.mode = newValue;
                            }
                            options: [
                                { displayName: Translation.tr("Default"), icon: "equalizer", value: "default" },
                                { displayName: Translation.tr("Bars"), icon: "equalizer", value: "bars" },
                                { displayName: Translation.tr("Wave"), icon: "airwave", value: "wave" }
                            ]
                        }
                    }
                }

                ContentSubsection {
                    title: Translation.tr("Visibility")

                    GroupedList {
                        ConfigSwitch {
                            buttonIcon: "crop_free"
                            text: Translation.tr("Hide when fullscreen/maximized")
                            checked: Config.options.background.widgets.visualizer.hideWhenFullscreen
                            onCheckedChanged: {
                                Config.options.background.widgets.visualizer.hideWhenFullscreen = checked
                                if (!checked) {
                                    Config.options.background.widgets.visualizer.hideWhenCovered = false
                                }
                            }
                        }
                        ConfigSwitch {
                            id: hideWhenCoveredSwitch
                            buttonIcon: "lock"
                            visible: Config.options.background.widgets.visualizer.hideWhenFullscreen
                            text: Translation.tr("Also hide when covered")
                            checked: Config.options.background.widgets.visualizer.hideWhenCovered
                            onCheckedChanged: {
                                Config.options.background.widgets.visualizer.hideWhenCovered = checked
                            }
                        }
                    }

                    // Ensure that "hide when covered" is visibly off when hide when fullscreen is turned off
                    Binding {
                        target: hideWhenCoveredSwitch
                        property: "checked"
                        value: Config.options.background.widgets.visualizer.hideWhenCovered
                        when: !hideWhenCoveredSwitch.pressed
                    }
                }

                ContentSubsection {
                    visible: visualizerSection.isWave
                    title: Translation.tr("Performance mode")
                    tooltip: Translation.tr("Note: Auto mode requires 'power-profiles-daemon' (Arch) package")

                    GroupedList {
                        ConfigSelectionArray {
                            currentValue: Config.options.background.widgets.visualizer.renderEveryXFrames
                            onSelected: newValue => {
                                Config.options.background.widgets.visualizer.renderEveryXFrames = newValue;
                            }
                            options: [
                                {
                                    displayName: Translation.tr("Auto"),
                                    icon: "auto_fix_high",
                                    value: -1,
                                },
                                {
                                    displayName: Translation.tr("Smooth mode"),
                                    icon: "speed",
                                    value: 1
                                },
                                {
                                    displayName: Translation.tr("Balanced mode"),
                                    icon: "balance",
                                    value: 2
                                },
                                {
                                    displayName: Translation.tr("Efficiency mode"),
                                    icon: "energy_savings_leaf",
                                    value: 4
                                }
                            ]
                        }
                    }
                }

                ContentSubsection {
                    title: Translation.tr("Behavior & Processing")

                    ConfigRow {
                        uniform: true
                        GroupedList {
                            ConfigSwitch {
                                buttonIcon: "lock"
                                text: Translation.tr("Show when locked")
                                checked: Config.options.background.widgets.visualizer.showWhenLocked
                                onCheckedChanged: {
                                    Config.options.background.widgets.visualizer.showWhenLocked = checked
                                }
                            }
                        }
                        GroupedList {
                            ConfigSwitch {
                                buttonIcon: "flip"
                                text: Translation.tr("Mono / Mirrored")
                                checked: Config.options.background.widgets.visualizer.mono
                                onCheckedChanged: {
                                    Config.options.background.widgets.visualizer.mono = checked
                                }
                            }
                        }
                    }

                    GroupedList {
                        ConfigSlider {
                            buttonIcon: "waves"
                            text: Translation.tr("Data Averaging")
                            value: (Config.options.background.widgets.visualizer.dataSmoothing ?? 0.5) * 100
                            from: 0; to: 100
                            stopIndicatorValues: [50]
                            onValueChanged: {
                                Config.options.background.widgets.visualizer.dataSmoothing = value / 100
                            }
                        }
                    }
                }

                ContentSubsection {
                    title: Translation.tr("Sizing & Resolution")

                    ConfigRow {
                        uniform: true
                        GroupedList {
                            ConfigSpinBox {
                                icon: "height"
                                text: Translation.tr("Max Height")
                                value: Config.options.background.widgets.visualizer.height
                                from: 60; to: 1080; stepSize: 10
                                onValueChanged: {
                                    Config.options.background.widgets.visualizer.height = value
                                }
                            }
                        }
                        GroupedList {
                            visible: !visualizerSection.isDefault
                            ConfigSpinBox {
                                icon: "view_column"
                                text: visualizerSection.isWave ? Translation.tr("Point Width") : Translation.tr("Bar Width")
                                value: Config.options.background.widgets.visualizer.targetBarWidth
                                from: 1; to: 200
                                onValueChanged: {
                                    Config.options.background.widgets.visualizer.targetBarWidth = value
                                }
                            }
                        }
                    }

                    ConfigRow {
                        uniform: true
                        GroupedList {
                            visible: !visualizerSection.isDefault
                            ConfigSpinBox {
                                icon: "space_bar"
                                text: visualizerSection.isWave ? Translation.tr("Point Gap") : Translation.tr("Bar Gap")
                                value: Config.options.background.widgets.visualizer.barSpacing
                                from: 0; to: 100
                                onValueChanged: {
                                    Config.options.background.widgets.visualizer.barSpacing = value
                                }
                            }
                        }
                        GroupedList {
                            visible: !visualizerSection.isDefault
                            ConfigSpinBox {
                                icon: "line_weight"
                                text: visualizerSection.isWave ? Translation.tr("Line Thickness") : Translation.tr("Border Width")
                                value: Config.options.background.widgets.visualizer.waveBorderWidth
                                from: 0; to: 20
                                onValueChanged: {
                                    Config.options.background.widgets.visualizer.waveBorderWidth = value
                                }
                            }
                        }
                    }
                }

                ContentSubsection {
                    title: Translation.tr("Appearance")

                    ConfigRow {
                        uniform: true
                        GroupedList {
                            ConfigSlider {
                                buttonIcon: "opacity"
                                text: Translation.tr("Master Opacity")
                                value: Config.options.background.widgets.visualizer.opacity * 100
                                from: 0; to: 100
                                stopIndicatorValues: [50]
                                onValueChanged: {
                                    Config.options.background.widgets.visualizer.opacity = value / 100
                                }
                            }
                        }
                        GroupedList {
                            ConfigSlider {
                                buttonIcon: "speed"
                                text: Translation.tr("Smoothing")
                                value: Config.options.background.widgets.visualizer.smoothing * 100
                                from: 0; to: 20
                                stopIndicatorValues: [5]
                                onValueChanged: {
                                    Config.options.background.widgets.visualizer.smoothing = value / 100
                                }
                            }
                        }
                    }
                    GroupedList {
                        visible: visualizerSection.isWave
                        ConfigSlider {
                            buttonIcon: "format_color_fill"
                            text: Translation.tr("Fill Opacity")
                            value: Config.options.background.widgets.visualizer.waveFillOpacity * 100
                            from: 0; to: 100
                            stopIndicatorValues: [50]
                            onValueChanged: {
                                Config.options.background.widgets.visualizer.waveFillOpacity = value / 100
                            }
                        }
                    }
                    GroupedList {
                        visible: !visualizerSection.isWave && !visualizerSection.isDefault
                        ConfigSlider {
                            buttonIcon: "format_color_reset"
                            text: Translation.tr("Border Opacity")
                            value: Config.options.background.widgets.visualizer.waveFillOpacity * 100
                            from: 0; to: 100
                            stopIndicatorValues: [50]
                            onValueChanged: {
                                Config.options.background.widgets.visualizer.waveFillOpacity = value / 100
                            }
                        }
                    }
                    GroupedList {
                        visible: !visualizerSection.isWave && !visualizerSection.isDefault
                        ConfigSlider {
                            buttonIcon: "rounded_corner"
                            text: Translation.tr("Bar Roundness")
                            value: Config.options.background.widgets.visualizer.barRounding * 100
                            from: 0; to: 50
                            stopIndicatorValues: [25]
                            onValueChanged: {
                                Config.options.background.widgets.visualizer.barRounding = value / 100
                            }
                        }
                    }
                }
            }
        }
    }
}
