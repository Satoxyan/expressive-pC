import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io

MouseArea {
    id: root
    property int columns: Config.options.wallpaperSelector.columns || 4
    property real previewCellAspectRatio: 4 / 3
    property bool useDarkMode: Appearance.m3colors.darkmode
    property bool showControls: false
    property string source: "local"
    property string selectedResolution: "1080p"
    property bool toolbarVisible: showControls || Config.options.wallpaperSelector.showSearchbar
    property bool filterFieldFocused: false

    property var quickDirs: [
        { icon: "home",       name: "Home   ",       path: `${Directories.home}`,                alwaysVisible: Config.options.wallpaperSelector.showHomePath },
        { icon: "wallpaper",  name: "Wallpapers   ", path: `${Directories.pictures}/Wallpapers`, alwaysVisible: true },
        { icon: "imagesmode", name: "Homework   ",   path: `${Directories.pictures}/homework`,   alwaysVisible: Config.options.policies.weeb },
        { icon: "casino",     name: "Random   ",     path: `${Directories.pictures}/Random`,     alwaysVisible: true },
        { 
            icon: "image",     
            name: Config.options.wallpaperSelector.userPath?.trim().length > 0 
                ? Config.options.wallpaperSelector.userPath.split("/").filter(s => s.length > 0).pop() + "   "
                : "Custom   ",
            path: Config.options.wallpaperSelector.userPath, 
            alwaysVisible: Config.options.wallpaperSelector.userPath?.trim().length > 0 
        }
    ]

    function updateThumbnails() {
        const item = gridLoader.item;
        const totalImageMargin = (Appearance.sizes.wallpaperSelectorItemMargins + Appearance.sizes.wallpaperSelectorItemPadding) * 2;
        const cellW = item?.cellWidth ?? (wallpaperGridBackground.width / root.columns);
        const cellH = item?.cellHeight ?? (cellW / root.previewCellAspectRatio);
        const thumbnailSizeName = Images.thumbnailSizeNameForDimensions(cellW - totalImageMargin, cellH - totalImageMargin);
        Wallpapers.setDirectory(`${Directories.pictures}/Wallpapers`);
        Qt.callLater(() => Wallpapers.generateThumbnail(thumbnailSizeName));
    }

    function handleFilePasting(event) {
        const currentClipboardEntry = Cliphist.entries[0];
        if (/^\d+\tfile:\/\/\S+/.test(currentClipboardEntry)) {
            const url = StringUtils.cleanCliphistEntry(currentClipboardEntry);
            Wallpapers.setDirectory(FileUtils.trimFileProtocol(decodeURIComponent(url)));
            event.accepted = true;
        } else {
            event.accepted = false;
        }
    }

    function selectWallpaperPath(filePath) {
        if (filePath && filePath.length > 0) {
            if (GlobalStates.wallpaperSelectorTarget === "lockWall") {
                Wallpapers.select(filePath, root.useDarkMode, finalPath => {
                    Config.options.background.lockWall = finalPath;
                    GlobalStates.wallpaperSelectorTarget = "wallpaper";
                    GlobalStates.wallpaperSelectorOpen = false;
                });
            } else {
                // Stop preview FIRST so wallpaperPath reverts to the old wallpaper,
                // then select() sets confirmedPath to the new one — this causes
                // onWallpaperPathChanged to fire with the real transition animation.
                if (Config.options.background.enableWallpaperPreview)
                    Wallpapers.stopPreview();
                Wallpapers.select(filePath, root.useDarkMode);
            }
        }
    }

    acceptedButtons: Qt.BackButton | Qt.ForwardButton
    onPressed: event => {
        if (event.button === Qt.BackButton) {
            Wallpapers.navigateBack();
        } else if (event.button === Qt.ForwardButton) {
            Wallpapers.navigateForward();
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            Wallpapers.stopPreview();
            GlobalStates.wallpaperSelectorOpen = false;
            event.accepted = true;
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
            root.handleFilePasting(event);
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_F) {
            if (Config.options.wallpaperSelector.showSearchbar) {
                Config.options.wallpaperSelector.showSearchbar = false
                showControls = false
            } else {
                showControls = !showControls
            }
            event.accepted = true;
        } else if (event.modifiers & Qt.AltModifier && event.key === Qt.Key_Up) {
            Wallpapers.navigateUp();
            event.accepted = true;
        } else if (event.modifiers & Qt.AltModifier && event.key === Qt.Key_Left) {
            Wallpapers.navigateBack();
            event.accepted = true;
        } else if (event.modifiers & Qt.AltModifier && event.key === Qt.Key_Right) {
            Wallpapers.navigateForward();
            event.accepted = true;
        } else if (event.key === Qt.Key_Left) {
            if (!root.filterFieldFocused) gridLoader.item?.moveSelection(-1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Right) {
            if (!root.filterFieldFocused) gridLoader.item?.moveSelection(1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Up) {
            if (!root.filterFieldFocused) gridLoader.item?.moveSelection(-root.columns);
            event.accepted = true;
        } else if (event.key === Qt.Key_Down) {
            if (!root.filterFieldFocused) gridLoader.item?.moveSelection(root.columns);
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (!root.filterFieldFocused) gridLoader.item?.activateCurrent();
            event.accepted = true;
        } else if (event.key === Qt.Key_Backspace) {
            if (!root.filterFieldFocused) {
                filterField.forceActiveFocus();
            }
            event.accepted = true;
        } else if (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_L) {
            addressBar.focusBreadcrumb();
            event.accepted = true;
        } else if (event.key === Qt.Key_Slash) {
            filterField.forceActiveFocus();
            event.accepted = true;
        } else {
            if (event.text.length > 0 && !root.filterFieldFocused) {
                filterField.text += event.text;
                filterField.cursorPosition = filterField.text.length;
                filterField.forceActiveFocus();
            }
            event.accepted = true;
        }
    }

    implicitHeight: mainLayout.implicitHeight
    implicitWidth: mainLayout.implicitWidth

    StyledRectangularShadow {
        target: wallpaperGridBackground
    }

    Rectangle {
        id: wallpaperGridBackground
        anchors {
            fill: parent
            margins: Appearance.sizes.elevationMargin
        }
        focus: true
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        color: Appearance.colors.colLayer0
        radius: Appearance.rounding.screenRounding + 5

        implicitWidth: gridColumnLayout.implicitWidth
        implicitHeight: gridColumnLayout.implicitHeight

        Item {
            anchors { fill: parent; margins: 8 }
            z: 0

            Rectangle {
                anchors.fill: parent
                radius: wallpaperGridBackground.radius - 4
                color: Appearance.colors.colLayer2
                visible: !Config.options.wallpaperSelector.showBlurBackground
            }

            StyledImage {
                id: wallpaperBgImage
                anchors.fill: parent
                visible: Config.options.wallpaperSelector.showBlurBackground
                fillMode: Image.PreserveAspectCrop
                source: Config.options.background.wallpaperPath
                cache: false
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: wallpaperGridBackground.width - 16
                        height: wallpaperGridBackground.height - 16
                        radius: wallpaperGridBackground.radius - 4
                    }
                }
            }

            FastBlur {
                anchors.fill: parent
                z: 0
                visible: Config.options.wallpaperSelector.showBlurBackground
                source: wallpaperBgImage
                radius: 48
                layer.enabled: visible
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: wallpaperGridBackground.width - 16
                        height: wallpaperGridBackground.height - 16
                        radius: wallpaperGridBackground.radius - 4
                    }
                }
            }
        }

        RowLayout {
            id: mainLayout
            anchors.fill: parent
            anchors.topMargin: 0
            anchors.bottomMargin: 8
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: -4
            z: 1

            ColumnLayout {
                id: gridColumnLayout
                Layout.fillWidth: true
                Layout.fillHeight: true

                Item {
                    id: topBar
                    Layout.fillWidth: true
                    Layout.margins: 16
                    Layout.leftMargin: 20
                    implicitHeight: 56

                    RowLayout {
                        anchors {
                            left: parent.left
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 8

                        MaterialShapeWrappedMaterialSymbol {
                            wrappedShape: MaterialShape.Shape.Gem
                            text: "image"
                            iconSize: Appearance.font.pixelSize.larger
                        }

                        StyledText {
                            text: Translation.tr("Wallpaper Selector")
                            font.pixelSize: Appearance.font.pixelSize.large
                        }
                    }

                    Toolbar {
                        anchors.centerIn: parent
                        visible: root.source !== "wallhaven"

                        Loader {
                            active: root.source === "local"
                            visible: active
                            sourceComponent: RowLayout {
                                spacing: 4
                                Repeater {
                                    model: root.quickDirs
                                    delegate: RippleButton {
                                        id: dirBtn
                                        required property var modelData
                                        implicitHeight: 38
                                        buttonRadius: height / 2
                                        visible: modelData.alwaysVisible
                                        toggled: Wallpapers.directory === Qt.resolvedUrl(modelData.path)
                                        colBackgroundToggled: Appearance.colors.colSecondaryContainer
                                        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                                        colRippleToggled: Appearance.colors.colSecondaryContainerActive
                                        onClicked: Wallpapers.setDirectory(modelData.path)
                                        contentItem: RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            spacing: 6
                                            MaterialSymbol {
                                                text: dirBtn.modelData.icon
                                                iconSize: Appearance.font.pixelSize.larger
                                                color: dirBtn.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                                fill: dirBtn.toggled ? 1 : 0
                                            }
                                            StyledText {
                                                text: dirBtn.modelData.name
                                                color: dirBtn.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Loader {
                            active: root.source === "unsplash" || root.source === "pexels"
                            visible: active
                            sourceComponent: RowLayout {
                                spacing: 4
                                Repeater {
                                    model: ["1080p", "2K", "4K"]
                                    delegate: RippleButton {
                                        required property string modelData
                                        implicitHeight: 38
                                        buttonRadius: height / 2
                                        toggled: root.selectedResolution === modelData
                                        colBackgroundToggled: Appearance.colors.colSecondaryContainer
                                        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                                        colRippleToggled: Appearance.colors.colSecondaryContainerActive
                                        onClicked: root.selectedResolution = modelData
                                        contentItem: StyledText {
                                            anchors.centerIn: parent
                                            text: modelData
                                            color: parent.toggled
                                                ? Appearance.colors.colOnSecondaryContainer
                                                : Appearance.colors.colOnLayer2
                                        }
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        anchors {
                            right: parent.right
                            rightMargin: 8
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 6

                        StyledComboBox {
                            id: sourceCombo
                            implicitWidth: 120
                            model: [
                                { value: "local",     displayName: Translation.tr("Local") },
                                { value: "wallhaven", displayName: Translation.tr("Wallhaven") },
                                { value: "unsplash",  displayName: Translation.tr("Unsplash") },
                                { value: "pexels",    displayName: Translation.tr("Pexels") },
                            ]
                            textRole: "displayName"
                            onCurrentIndexChanged: {
                                root.source = model[currentIndex].value
                                root.forceActiveFocus()
                            }
                        }

                        RippleButton {
                            implicitWidth: 36
                            implicitHeight: 36
                            buttonRadius: height / 2
                            toggled: root.toolbarVisible
                            colBackground: Appearance.colors.colSecondaryContainer
                            onClicked: {
                                if (Config.options.wallpaperSelector.showSearchbar) {
                                    Config.options.wallpaperSelector.showSearchbar = false
                                    showControls = false
                                } else {
                                    showControls = !showControls
                                }
                            }
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: "search"
                                iconSize: Appearance.font.pixelSize.larger
                                color: root.toolbarVisible
                                    ? Appearance.colors.colOnPrimary
                                    : Appearance.colors.colOnSecondaryContainer
                            }
                            StyledToolTip {
                                text: Translation.tr("Toggle search toolbar (Ctrl+F)")
                            }
                        }
                    }
                }

                Item {
                    id: gridDisplayRegion
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Loader {
                        id: gridLoader
                        anchors.fill: parent
                        sourceComponent: root.source === "local" ? localGridComponent
                            : root.source === "wallhaven" ? wallhavenGridComponent
                            : onlineGridComponent
                    }

                    Component {
                        id: localGridComponent
                        LocalWallpaperGrid {
                            columns: root.columns
                            previewCellAspectRatio: root.previewCellAspectRatio
                            onWallpaperSelected: path => root.selectWallpaperPath(path)
                        }
                    }

                    Component {
                        id: wallhavenGridComponent
                        WallhavenSearchGrid {
                            columns: root.columns
                            previewCellAspectRatio: root.previewCellAspectRatio
                            useDarkMode: root.useDarkMode
                            onWallpaperApplied: {
                                if (Config.options.wallpaperSelector.closeAfterSelection)
                                    GlobalStates.wallpaperSelectorOpen = false;
                            }
                        }
                    }

                    Component {
                        id: onlineGridComponent
                        OnlineWallpaperGrid {
                            provider: root.source
                            resolution: root.selectedResolution
                            onWallpaperSelected: path => root.selectWallpaperPath(path)
                            onUpdateThumbnailsRequested: root.updateThumbnails()
                        }
                    }

                    RowLayout {
                        id: extraOptions
                        anchors {
                            bottom: parent.bottom
                            horizontalCenter: parent.horizontalCenter
                            bottomMargin: 8
                        }
                        spacing: 6
                        z: root.toolbarVisible ? 2 : -1
                        opacity: root.toolbarVisible ? 1 : 0
                        transform: Translate {
                            y: root.toolbarVisible ? 0 : 20
                            Behavior on y {
                                NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                            }
                        }
                        Behavior on opacity {
                            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                        }

                        Loader {
                            active: root.source === "local"
                            visible: active
                            sourceComponent: Toolbar {
                                IconToolbarButton {
                                    implicitWidth: height
                                    onClicked: {
                                        Wallpapers.openFallbackPicker(root.useDarkMode);
                                        GlobalStates.wallpaperSelectorOpen = false;
                                    }
                                    altAction: () => {
                                        Wallpapers.openFallbackPicker(root.useDarkMode);
                                        GlobalStates.wallpaperSelectorOpen = false;
                                        Config.options.wallpaperSelector.useSystemFileDialog = true;
                                    }
                                    text: "open_in_new"
                                    StyledToolTip {
                                        text: Translation.tr("Use the system file picker instead\nRight-click to make this the default behavior")
                                    }
                                }
                                IconToolbarButton {
                                    implicitWidth: height
                                    onClicked: Wallpapers.randomFromCurrentFolder()
                                    text: "ifl"
                                    StyledToolTip {
                                        text: Translation.tr("Random wallpaper from current folder")
                                    }
                                }
                                IconToolbarButton {
                                    implicitWidth: height
                                    onClicked: root.useDarkMode = !root.useDarkMode
                                    text: root.useDarkMode ? "dark_mode" : "light_mode"
                                    StyledToolTip {
                                        text: root.useDarkMode
                                            ? Translation.tr("Switch to light mode")
                                            : Translation.tr("Switch to dark mode")
                                    }
                                }
                                IconToolbarButton {
                                    implicitWidth: height
                                    onClicked: root.updateThumbnails()
                                    text: "reset_image"
                                    StyledToolTip {
                                        text: Translation.tr("Update thumbnails")
                                    }
                                }
                                ToolbarTextField {
                                    id: filterField
                                    placeholderText: focus
                                        ? Translation.tr("Search wallpapers")
                                        : Translation.tr("Search wallpapers")
                                    clip: true
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    onTextChanged: Wallpapers.searchQuery = text
                                    onActiveFocusChanged: root.filterFieldFocused = activeFocus
                                    Keys.onPressed: event => {
                                        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
                                            root.handleFilePasting(event);
                                            event.accepted = true;
                                            return;
                                        }
                                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                            event.accepted = true;
                                            return;
                                        }
                                        if (text.length !== 0) {
                                            if (event.key === Qt.Key_Down) { event.accepted = true; return; }
                                            if (event.key === Qt.Key_Up)   { event.accepted = true; return; }
                                        }
                                        event.accepted = false;
                                    }
                                }
                            }
                        }

                        Loader {
                            active: root.source === "unsplash" || root.source === "pexels"
                            visible: active
                            sourceComponent: Toolbar {
                                ToolbarTextField {
                                    id: onlineSearchField
                                    placeholderText: Translation.tr("Search online wallpapers")
                                    clip: true
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    onTextChanged: OnlineWallpapers.query = text
                                    onAccepted: OnlineWallpapers.fetch()
                                    onActiveFocusChanged: root.filterFieldFocused = activeFocus
                                    Connections {
                                        target: GlobalStates
                                        function onWallpaperSelectorOpenChanged() {
                                            if (!GlobalStates.wallpaperSelectorOpen) onlineSearchField.text = ""
                                        }
                                    }
                                    Keys.onPressed: event => {
                                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                            event.accepted = true;
                                            return;
                                        }
                                        event.accepted = false;
                                    }
                                }
                                IconToolbarButton {
                                    implicitWidth: height
                                    text: "refresh"
                                    onClicked: OnlineWallpapers.fetch()
                                }
                            }
                        }

                        Loader {
                            active: root.source === "wallhaven"
                            visible: active
                            sourceComponent: Toolbar {
                                id: wallhavenToolbar

                                // Broad color families. Each ORs several wallhaven palette colors (the API
                                // accepts a comma-separated list) so one swatch = a wide range of wallpapers.
                                // `hex` is the display swatch; `q` is the comma-joined wallhaven colors value.
                                readonly property var colorGroups: [
                                    { hex: "cc0000", q: "660000,990000,cc0000,cc3333" },        // Red
                                    { hex: "ff6600", q: "ffcc33,ff9900,ff6600" },               // Orange
                                    { hex: "cccc33", q: "666600,999900,cccc33,ffff00" },        // Yellow
                                    { hex: "669900", q: "77cc33,669900,336600" },               // Green
                                    { hex: "66cccc", q: "66cccc,0099cc" },                      // Teal
                                    { hex: "0066cc", q: "0066cc,0099cc,333399" },               // Blue
                                    { hex: "663399", q: "ea4c88,993399,663399,333399" },        // Purple / pink
                                    { hex: "996633", q: "cc6633,996633,663300" },               // Brown
                                    { hex: "999999", q: "000000,999999,cccccc,ffffff,424153" }  // Neutral
                                ]

                                // Display hex of the currently-active family ("" if none) — drives the button color
                                readonly property string activeHex: {
                                    for (let i = 0; i < colorGroups.length; i++)
                                        if (colorGroups[i].q === WallhavenSearch.colors) return colorGroups[i].hex
                                    return ""
                                }

                                // Black/white that reads on a given hex (relative luminance)
                                function contrastColor(hex) {
                                    if (!hex || hex.length < 6) return Appearance.colors.colOnLayer1
                                    const r = parseInt(hex.substr(0, 2), 16)
                                    const g = parseInt(hex.substr(2, 2), 16)
                                    const b = parseInt(hex.substr(4, 2), 16)
                                    return (0.299 * r + 0.587 * g + 0.114 * b) > 140 ? "#000000" : "#ffffff"
                                }

                                Timer {
                                    id: searchDebounce
                                    interval: 500
                                    onTriggered: WallhavenSearch.search(wallhavenSearchField.text, 1)
                                }

                                ToolbarTextField {
                                    id: wallhavenSearchField
                                    text: WallhavenSearch.currentQuery
                                    placeholderText: Translation.tr("Search Wallhaven...")
                                    Layout.preferredWidth: 220
                                    onTextChanged: searchDebounce.restart()
                                    onAccepted: {
                                        searchDebounce.stop()
                                        WallhavenSearch.search(text, 1)
                                    }
                                    onActiveFocusChanged: root.filterFieldFocused = activeFocus
                                    Keys.onPressed: event => {
                                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                            event.accepted = true
                                            return
                                        }
                                        event.accepted = false
                                    }
                                }

                                // Pagination
                                RowLayout {
                                    visible: WallhavenSearch.currentResults.length > 0
                                    spacing: 4

                                    IconToolbarButton {
                                        implicitWidth: height
                                        text: "navigate_before"
                                        enabled: !WallhavenSearch.fetching && WallhavenSearch.currentPage > 1
                                        onClicked: WallhavenSearch.previousPage()
                                    }

                                    ToolbarTextField {
                                        id: pageField
                                        implicitWidth: 44
                                        Layout.preferredWidth: 44
                                        Layout.fillWidth: false
                                        horizontalAlignment: Text.AlignHCenter
                                        text: WallhavenSearch.currentPage
                                        inputMethodHints: Qt.ImhDigitsOnly
                                        onAccepted: WallhavenSearch.goToPage(text)
                                        Connections {
                                            target: WallhavenSearch
                                            function onCurrentPageChanged() {
                                                pageField.text = WallhavenSearch.currentPage
                                            }
                                        }
                                    }

                                    StyledText {
                                        text: " / " + WallhavenSearch.lastPage
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colOnLayer1
                                    }

                                    IconToolbarButton {
                                        implicitWidth: height
                                        text: "navigate_next"
                                        enabled: !WallhavenSearch.fetching && WallhavenSearch.currentPage < WallhavenSearch.lastPage
                                        onClicked: WallhavenSearch.nextPage()
                                    }
                                }

                                IconToolbarButton {
                                    id: paletteButton
                                    implicitWidth: height
                                    text: "palette"
                                    toggled: colorMenu.visible || WallhavenSearch.colors.length > 0
                                    // Reflect the active color family on the button itself
                                    colBackgroundToggled: wallhavenToolbar.activeHex.length > 0 ? ("#" + wallhavenToolbar.activeHex) : Appearance.colors.colSecondaryContainer
                                    colBackgroundToggledHover: wallhavenToolbar.activeHex.length > 0 ? ("#" + wallhavenToolbar.activeHex) : Appearance.colors.colSecondaryContainerHover
                                    colText: wallhavenToolbar.activeHex.length > 0
                                        ? wallhavenToolbar.contrastColor(wallhavenToolbar.activeHex)
                                        : (toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant)
                                    onClicked: colorMenu.visible ? colorMenu.close() : colorMenu.open()
                                    StyledToolTip {
                                        text: Translation.tr("Filter by color")
                                    }

                                    // Drop-down color grid (opens upward since the toolbar sits at the bottom)
                                    Popup {
                                        id: colorMenu
                                        y: -height - 6
                                        x: paletteButton.width - width
                                        padding: 10
                                        modal: false
                                        focus: true
                                        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

                                        enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 100 } }
                                        exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 100 } }

                                        background: Rectangle {
                                            // m3 token is opaque (colLayer1 is alpha-blended → looked see-through)
                                            color: Appearance.m3colors.m3surfaceContainerHigh
                                            radius: Appearance.rounding.normal
                                            border.width: 1
                                            border.color: Appearance.colors.colLayer0Border
                                        }

                                        contentItem: ColumnLayout {
                                            spacing: 8

                                            RowLayout {
                                                Layout.fillWidth: true
                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: Translation.tr("Filter by color")
                                                    font.pixelSize: Appearance.font.pixelSize.small
                                                    color: Appearance.colors.colSubtext
                                                }
                                                // Clear / any-color
                                                RippleButton {
                                                    visible: WallhavenSearch.colors.length > 0
                                                    implicitHeight: 24
                                                    leftPadding: 8
                                                    rightPadding: 8
                                                    buttonRadius: height / 2
                                                    onClicked: { WallhavenSearch.setColor(""); colorMenu.close() }
                                                    contentItem: StyledText {
                                                        text: Translation.tr("Clear")
                                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                                        color: Appearance.colors.colOnLayer1
                                                    }
                                                }
                                            }

                                            Grid {
                                                columns: 3
                                                spacing: 8
                                                Repeater {
                                                    model: wallhavenToolbar.colorGroups
                                                    delegate: Rectangle {
                                                        required property var modelData
                                                        width: 44; height: 44; radius: Appearance.rounding.small
                                                        color: "#" + modelData.hex
                                                        border.width: WallhavenSearch.colors === modelData.q ? 3 : 1
                                                        border.color: WallhavenSearch.colors === modelData.q ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
                                                        MouseArea {
                                                            anchors.fill: parent
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: { WallhavenSearch.setColor(parent.modelData.q); colorMenu.close() }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                IconToolbarButton {
                                    implicitWidth: height
                                    text: "tune"
                                    toggled: gridLoader.item?.showSettings
                                    onClicked: { if (gridLoader.item) gridLoader.item.toggleSettings() }
                                    StyledToolTip {
                                        text: Translation.tr("Wallhaven search settings")
                                    }
                                }

                                IconToolbarButton {
                                    implicitWidth: height
                                    text: root.useDarkMode ? "dark_mode" : "light_mode"
                                    onClicked: root.useDarkMode = !root.useDarkMode
                                    StyledToolTip {
                                        text: Translation.tr("Toggle light/dark mode for applied wallpaper")
                                    }
                                }

                                IconToolbarButton {
                                    implicitWidth: height
                                    text: "refresh"
                                    onClicked: WallhavenSearch.search(WallhavenSearch.currentQuery, 1)
                                    StyledToolTip {
                                        text: Translation.tr("Refresh search results")
                                    }
                                }
                            }
                        }

                        ToolbarPairedFab {
                            iconText: "close"
                            onClicked: {
                                Wallpapers.stopPreview();
                                GlobalStates.wallpaperSelectorOpen = false;
                            }
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: GlobalStates
        function onWallpaperSelectorOpenChanged() {
            if (GlobalStates.wallpaperSelectorOpen && monitorIsFocused) {
                if (root.source === "local")
                    filterField.forceActiveFocus()
                else
                    root.forceActiveFocus()
            } else if (!GlobalStates.wallpaperSelectorOpen) {
                Wallpapers.stopPreview();
            }
        }
    }

    Connections {
        target: Wallpapers
        function onChanged() {
            if (Config.options.wallpaperSelector.closeAfterSelection)
                GlobalStates.wallpaperSelectorOpen = false;
        }
    }
}