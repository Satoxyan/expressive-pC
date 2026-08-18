import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell.Services.UPower
import Quickshell.Services.Mpris
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.panels.lock
import qs.modules.ii.bar as Bar
import qs.modules.ii.mediaControls
import Quickshell
import Quickshell.Services.SystemTray

MouseArea {
    id: root
    required property LockContext context
    property bool active: false
    property bool showInputField: active || context.currentText.length > 0
    readonly property bool requirePasswordToPower: Config.options.lock.security.requirePasswordToPower

    property var pendingAction: null
    property bool showConfirmDialog: false

    readonly property MprisPlayer activePlayer: {
        const preferred = Config.options.bar.media.preferredPlayer.trim().toLowerCase()
        if (preferred.length === 0) return MprisController.activePlayer
        const _ = MprisController.players.count
        for (const p of MprisController.players) {
            if ((p.identity ?? "").toLowerCase().includes(preferred) ||
                (p.desktopEntry ?? "").toLowerCase().includes(preferred))
                return p
        }
        return MprisController.activePlayer
    }

    property var    artUrl:      activePlayer?.trackArtUrl ?? ""

    // Media controller state. Hidden by default; shown on demand when the
    // media info component in the left toolbar is pressed.
    readonly property bool mediaPlayerAvailable: MprisController.activePlayer !== null && MprisController.activePlayer.trackTitle
    property bool mediaLoaderActive: false

    Connections {
        target: GlobalStates
        function onLockMediaOpenChanged() {
            if (GlobalStates.lockMediaOpen) {
                if (root.mediaPlayerAvailable) {
                    root.mediaLoaderActive = true
                    if (lockscreenMediaController.item) {
                        mediaExitAnim.stop()
                        lockscreenMediaController.mediaScale = 0.85
                        lockscreenMediaController.mediaOpacity = 0.0
                        entryAnim.restart()
                    }
                } else {
                    GlobalStates.lockMediaOpen = false
                }
            } else {
                if (lockscreenMediaController.item) {
                    entryAnim.stop()
                    mediaExitAnim.restart()
                } else {
                    root.mediaLoaderActive = false
                }
            }
        }
    }

    onMediaPlayerAvailableChanged: {
        if (!root.mediaPlayerAvailable && GlobalStates.lockMediaOpen) {
            if (lockscreenMediaController.item) {
                entryAnim.stop()
                mediaExitAnim.restart()
            } else {
                root.mediaLoaderActive = false
                GlobalStates.lockMediaOpen = false
            }
        }
    }

    // Force focus on entry
    function forceFieldFocus() {
        passwordBox.forceActiveFocus();
    }
    Connections {
        target: context
        function onShouldReFocus() {
            forceFieldFocus();
        }
    }
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    onPressed: mouse => {
        forceFieldFocus();
    }
    onPositionChanged: mouse => {
        forceFieldFocus();
    }

    // Toolbar appearing animation
    property real toolbarScale: 0.9
    property real toolbarOpacity: 0
    Behavior on toolbarScale {
        NumberAnimation {
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
        }
    }
    Behavior on toolbarOpacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    // Shake the whole toolbar row (left island + main island + right island) on wrong password.
    // Soft & minimal: 3 alternating left-right-left nudges of 15px, settling back to 0, over 1s total.
    property real rowShakeX: 0

    SequentialAnimation {
        id: wrongPasswordRowShakeAnim
        NumberAnimation { target: root; property: "rowShakeX"; to: -15; duration: 120; easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "rowShakeX"; to: 15;  duration: 120; easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "rowShakeX"; to: -15; duration: 120; easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "rowShakeX"; to: 0;   duration: 120; easing.type: Easing.InOutSine }
    }
    Connections {
        target: GlobalStates
        function onScreenUnlockFailedChanged() {
            if (GlobalStates.screenUnlockFailed) wrongPasswordRowShakeAnim.restart();
        }
    }

    // Init
    Component.onCompleted: {
        forceFieldFocus();
        toolbarScale = 1;
        toolbarOpacity = 1;
        GlobalStates.lockMediaOpen = false;
    }

    // Key presses
    property bool ctrlHeld: false
    Keys.onPressed: event => {
        root.context.resetClearTimer();
        if (event.key === Qt.Key_Control) {
            root.ctrlHeld = true;
        }
        if (event.key === Qt.Key_Escape) { // Esc to clear
            root.context.currentText = "";
        } 
        forceFieldFocus();
    }
    Keys.onReleased: event => {
        if (event.key === Qt.Key_Control) {
            root.ctrlHeld = false;
        }
        forceFieldFocus();
    }

    // RippleButton {
    //     anchors {
    //         top: parent.top
    //         left: parent.left
    //         leftMargin: 10
    //         topMargin: 10
    //     }
    //     implicitHeight: 40
    //     colBackground: Appearance.colors.colLayer2
    //     onClicked: {
    //         context.unlocked(LockContext.ActionEnum.Unlock);
    //         GlobalStates.screenLocked = false;
    //     }
    //     contentItem: StyledText {
    //         text: "[[ DEBUG BYPASS ]]"
    //     }
    // }

    Loader {
        anchors.fill: parent
        z: -1
        active: WM.compositor === "niri"

        sourceComponent: Item {
            anchors.fill: parent

            Image {
                id: lockBgSource
                anchors.fill: parent
                source: Config.options.background.wallpaperPath
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                visible: false
            }
            FastBlur {
                anchors.fill: parent
                source: lockBgSource
                radius: 0 // fixme
            }
        }
    }

    // Clicking the centered wallpaper (a square around the screen center
    // matching its locked size) plays the heartbeat thump on the background.
    // Keeps the password field focused like any other lock-screen press.
    MouseArea {
        id: centeredWallpaperThumpArea
        z: 1
        width: Math.max(1, Config.options.background.centeredWallpaperSize)
        height: width
        anchors.centerIn: parent
        visible: Config.options.background.centeredWallpaper
        onClicked: {
            root.forceFieldFocus()
            GlobalStates.centeredWallpaperThumpRequested()
        }
    }

    // Media controller (LockMediaWidget), shown on demand above the main toolbar
    Loader {
        id: lockscreenMediaController
        active: root.mediaLoaderActive

        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: mainIsland.top
            bottomMargin: 15
        }

        property real mediaScale: 0.85
        property real mediaOpacity: 0.0

        scale: mediaScale * root.toolbarScale
        opacity: mediaOpacity * root.toolbarOpacity

        onLoaded: {
            mediaScale = 0.85
            mediaOpacity = 0.0
            entryAnim.restart()
        }

        ParallelAnimation {
            id: entryAnim
            NumberAnimation {
                target: lockscreenMediaController
                property: "mediaScale"
                to: 1.0
                duration: Appearance.animation.elementMove.duration
                easing.type: Easing.OutBack
                easing.overshoot: 1.5
            }
            NumberAnimation {
                target: lockscreenMediaController
                property: "mediaOpacity"
                to: 1.0
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.InCubic
            }
        }

        SequentialAnimation {
            id: mediaExitAnim
            ParallelAnimation {
                NumberAnimation {
                    target: lockscreenMediaController
                    property: "mediaScale"
                    to: 0.85
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.InBack
                    easing.overshoot: 1.2
                }
                NumberAnimation {
                    target: lockscreenMediaController
                    property: "mediaOpacity"
                    to: 0.0
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.InCubic
                }
            }
            ScriptAction {
                script: {
                    root.mediaLoaderActive = false
                    GlobalStates.lockMediaOpen = false
                }
            }
        }

        sourceComponent: LockMediaWidget {
            player: MprisController.activePlayer
            visualizerPoints: GlobalStates.visualizerPoints
            radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1
        }
    }

    // Main toolbar: password box
    Toolbar {
        id: mainIsland
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: 20
        }
        Behavior on anchors.bottomMargin {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        scale: root.toolbarScale
        opacity: root.toolbarOpacity
        transform: Translate { x: root.rowShakeX }

        // Fingerprint
        Loader {
            Layout.leftMargin: 10
            Layout.rightMargin: 6
            Layout.alignment: Qt.AlignVCenter
            active: root.context.fingerprintsConfigured
            visible: active

            sourceComponent: MaterialSymbol {
                id: fingerprintIcon
                fill: 1
                text: "fingerprint"
                iconSize: Appearance.font.pixelSize.hugeass
                color: Appearance.colors.colOnSurfaceVariant
            }
        }

        ToolbarTextField {
            id: passwordBox
            Layout.rightMargin: -Layout.leftMargin
            placeholderText: GlobalStates.screenUnlockFailed ? Translation.tr("Incorrect password") : Translation.tr("Enter password")

            // Style
            clip: true
            font.pixelSize: Appearance.font.pixelSize.small
            selectedTextColor: materialShapeChars ? "transparent" : Appearance.colors.colOnSecondaryContainer
            selectionColor: materialShapeChars ? "transparent" : Appearance.colors.colSecondaryContainer

            // Password
            enabled: !root.context.unlockInProgress
            echoMode: TextInput.Password
            inputMethodHints: Qt.ImhSensitiveData

            // Synchronizing (across monitors) and unlocking
            onTextChanged: root.context.currentText = this.text
            onAccepted: {
                root.context.tryUnlock(ctrlHeld);
            }
            Connections {
                target: root.context
                function onCurrentTextChanged() {
                    passwordBox.text = root.context.currentText;
                }
            }

            Keys.onPressed: event => {
                root.context.resetClearTimer();
            }
            
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: passwordBox.width - 8
                    height: passwordBox.height
                    radius: height / 2
                }
            }

            // We're drawing dots manually
            property bool materialShapeChars: Config.options.lock.materialShapeChars
            color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, materialShapeChars ? 1 : 0)
            Loader {
                active: passwordBox.materialShapeChars
                anchors {
                    fill: parent
                    leftMargin: passwordBox.padding
                    rightMargin: passwordBox.padding
                }
                sourceComponent: PasswordChars {
                    length: root.context.currentText.length
                    selectionStart: passwordBox.selectionStart
                    selectionEnd: passwordBox.selectionEnd
                    cursorPosition: passwordBox.cursorPosition
                }
            }
        }

        ToolbarButton {
            id: confirmButton
            implicitWidth: height
            toggled: true
            enabled: !root.context.unlockInProgress
            colBackgroundToggled: Appearance.colors.colPrimary

            onClicked: root.context.tryUnlock()

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                iconSize: 24
                text: {
                    if (root.context.targetAction === LockContext.ActionEnum.Unlock) {
                        return root.ctrlHeld ? "coffee" : "arrow_right_alt";
                    } else if (root.context.targetAction === LockContext.ActionEnum.Poweroff) {
                        return "power_settings_new";
                    } else if (root.context.targetAction === LockContext.ActionEnum.Reboot) {
                        return "restart_alt";
                    }
                }
                color: confirmButton.enabled ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
            }
        }
    }

    // Left toolbar
    Toolbar {
        id: leftIsland
        visible: Config.options.lock.showToolbars
        anchors {
            right: mainIsland.left
            top: mainIsland.top
            bottom: mainIsland.bottom
            rightMargin: 10
        }
        scale: root.toolbarScale
        opacity: root.toolbarOpacity
        transform: Translate { x: root.rowShakeX }

        // Username
        IconAndTextPair {
            Layout.leftMargin: 8
            icon: "account_circle"
            visible: !Config.options.lock.showMedia || MprisController.activePlayer === null
            text: SystemInfo.username
        }

        // Media player info 
        Loader {
            Layout.leftMargin: 2
            Layout.rightMargin: 2
            Layout.alignment: Qt.AlignVCenter
            active: MprisController.activePlayer !== null
            visible: active && Config.options.lock.showMedia
            
            sourceComponent: Item {
                implicitWidth: mediaRow.implicitWidth
                implicitHeight: mediaRow.implicitHeight
                
                readonly property MprisPlayer activePlayer: MprisController.activePlayer
                readonly property string cleanedTitle: StringUtils.cleanMusicTitle(activePlayer?.trackTitle) || ""
                
                Timer {
                    running: activePlayer?.playbackState == MprisPlaybackState.Playing
                    interval: Config.options.resources.updateInterval
                    repeat: true
                    onTriggered: activePlayer.positionChanged()
                }
                
                RowLayout {
                    id: mediaRow
                    spacing: 8
                    anchors.centerIn: parent
                    
                    Rectangle {
                        id: artRect
                        implicitWidth: 40
                        implicitHeight: 40
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colPrimaryContainer
                        Layout.alignment: Qt.AlignVCenter
                        clip: true 

                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: artRect.width
                                height: artRect.height
                                radius: artRect.radius
                            }
                        }

                        StyledImage {
                            anchors.centerIn: parent
                            width: artRect.width
                            height: artRect.height
                            source: root.artUrl
                            fillMode: Image.PreserveAspectCrop
                            cache: false
                            antialiasing: true
                            sourceSize.width: artRect.width * 2
                            sourceSize.height: artRect.height * 2
                            visible: root.artUrl !== ""
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            fill: 1
                            text: "music_note"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnSecondaryContainer
                            visible: root.artUrl === ""
                        }
                    }
                    
                    Column {
                        Layout.alignment: Qt.AlignVCenter
                        spacing: -2
                        
                        StyledText {
                            horizontalAlignment: Text.AlignLeft
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            width: Math.min(implicitWidth, 180) 
                            color: Appearance.colors.colOnSurfaceVariant
                            text: {
                                var artist = activePlayer?.trackArtist || " ";
                                return artist.length > 25 ? artist.substring(0, 25) + "..." : artist;
                            }
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                        
                        StyledText {
                            horizontalAlignment: Text.AlignLeft
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            width: Math.min(implicitWidth, 180) 
                            color: Appearance.colors.colOnSurfaceVariant
                            text: {
                                var title = cleanedTitle;
                                return title.length > 30 ? title.substring(0, 30) + "..." : title;
                            }
                            font.weight: Font.Medium
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }
                    
                    ClippedFilledCircularProgress {
                        id: mediaCircProg
                        Layout.alignment: Qt.AlignVCenter
                        lineWidth: Appearance.rounding.unsharpen
                        value: activePlayer?.position / activePlayer?.length
                        implicitSize: 24
                        colPrimary: Appearance.colors.colOnSurfaceVariant
                        enableAnimation: false
                        
                        Item {
                            anchors.centerIn: parent
                            width: mediaCircProg.implicitSize
                            height: mediaCircProg.implicitSize
                            
                            MaterialSymbol {
                                anchors.centerIn: parent
                                fill: 1
                                text: "music_note"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.forceFieldFocus()
                        GlobalStates.lockMediaOpen = !GlobalStates.lockMediaOpen
                    }
                }
            }
        }

        // Keyboard layout (Xkb)
        Loader {
            Layout.rightMargin: 8
            Layout.fillHeight: true
            visible: !Config.options.lock.showMedia || MprisController.activePlayer === null

            sourceComponent: Row {
                spacing: 8

                MaterialSymbol {
                    id: keyboardIcon
                    anchors.verticalCenter: parent.verticalCenter
                    fill: 1
                    text: "keyboard_alt"
                    iconSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colOnSurfaceVariant
                }
                Loader {
                    anchors.verticalCenter: parent.verticalCenter
                    sourceComponent: StyledText {
                        text: HyprlandXkb.currentLayoutCode
                        color: Appearance.colors.colOnSurfaceVariant
                        animateChange: true
                    }
                }
            }
        }

        // Keyboard layout (Fcitx)
        Bar.SysTray {
            Layout.rightMargin: 10
            Layout.alignment: Qt.AlignVCenter
            showSeparator: false
            showOverflowMenu: false
            pinnedItems: SystemTray.items.values.filter(i => i.id == "Fcitx")
            visible: pinnedItems.length > 0
        }
    }

    // Right toolbar
    Toolbar {
        id: rightIsland
        visible: Config.options.lock.showToolbars
        anchors {
            left: mainIsland.right
            top: mainIsland.top
            bottom: mainIsland.bottom
            leftMargin: 10
        }

        scale: root.toolbarScale
        opacity: root.toolbarOpacity
        transform: Translate { x: root.rowShakeX }

        IconAndTextPair {
            visible: Battery.available
            icon: Battery.isCharging ? "bolt" : "battery_android_full"
            text: Math.round(Battery.percentage * 100)
            color: (Battery.isLow && !Battery.isCharging) ? Appearance.colors.colError : Appearance.colors.colOnSurfaceVariant
        }

        IconToolbarButton {
            id: sleepButton
            onClicked: Session.suspend()
            text: "dark_mode"
        }

        PasswordGuardedIconToolbarButton {
            id: powerButton
            text: "power_settings_new"
            targetAction: LockContext.ActionEnum.Poweroff
        }

        PasswordGuardedIconToolbarButton {
            id: rebootButton
            text: "restart_alt"
            targetAction: LockContext.ActionEnum.Reboot
        }
    }

    component PasswordGuardedIconToolbarButton: IconToolbarButton {
        id: guardedBtn
        required property var targetAction

        toggled: root.context.targetAction === guardedBtn.targetAction

        onClicked: {
            if (!root.requirePasswordToPower) {
                root.pendingAction = guardedBtn.targetAction;
                root.showConfirmDialog = true;
                return;
            }
            if (root.context.targetAction === guardedBtn.targetAction) {
                root.context.resetTargetAction();
            } else {
                root.context.targetAction = guardedBtn.targetAction;
                root.context.shouldReFocus();
            }
        }
    }

    component IconAndTextPair: Row {
        id: pair
        required property string icon
        required property string text
        property color color: Appearance.colors.colOnSurfaceVariant

        spacing: 4
        Layout.fillHeight: true
        Layout.leftMargin: 10
        Layout.rightMargin: 10
        

        MaterialSymbol {
            anchors.verticalCenter: parent.verticalCenter
            fill: 1
            text: pair.icon
            iconSize: Appearance.font.pixelSize.huge
            animateChange: true
            color: pair.color
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: pair.text
            color: pair.color
        }
    }

    // Confirmation popup — close animation
    property bool confirmExecuteOnClose: false

    function closeConfirmPopup(execute) {
        confirmPopup.confirmExecuteOnClose = execute;
        closePopupAnim.restart();
    }

    SequentialAnimation {
        id: closePopupAnim
        ParallelAnimation {
            NumberAnimation {
                target: confirmPopup
                property: "scale"
                to: 0
                duration: 250
                easing.type: Easing.InBack
                easing.overshoot: 1.4
            }
            NumberAnimation {
                target: confirmPopup
                property: "opacity"
                to: 0
                duration: 250
                easing.type: Easing.InBack
            }
        }
        ScriptAction {
            script: {
                if (confirmPopup.confirmExecuteOnClose) {
                    root.context.unlocked(root.pendingAction);
                }
                root.showConfirmDialog = false;
                root.pendingAction = null;
            }
        }
    }

    // Transparent scrim to catch outside clicks and dismiss the popup
    MouseArea {
        anchors.fill: parent
        z: 998
        visible: root.showConfirmDialog
        enabled: root.showConfirmDialog
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onClicked: root.closeConfirmPopup(false)
    }

    // Confirmation popup — inline, positioned above the right toolbar
    Rectangle {
        id: confirmPopup
        z: 999
        anchors {
            bottom: rightIsland.top
            bottomMargin: 8
            right: rightIsland.right
        }

        visible: root.showConfirmDialog
        width: Math.max(textColumn.implicitWidth, popupButtons.width) + 32
        height: textColumn.implicitHeight + popupButtons.height + 40
        radius: Appearance.rounding.large
        color: Appearance.m3colors.m3surfaceContainerHigh

        property bool confirmExecuteOnClose: root.confirmExecuteOnClose

        transformOrigin: Item.BottomRight
        scale: root.showConfirmDialog ? 1 : 0
        opacity: root.showConfirmDialog ? 1 : 0

        Behavior on scale {
            NumberAnimation {
                duration: 350
                easing.type: Easing.OutBack
                easing.overshoot: 1.8
            }
        }
        Behavior on opacity {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutCubic
            }
        }

        StyledRectangularShadow {
            target: confirmPopup
        }

        Column {
            id: textColumn
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: 16
            }
            spacing: 6

            StyledText {
                width: parent.width
                text: root.pendingAction === LockContext.ActionEnum.Poweroff
                    ? Translation.tr("Shutdown now?")
                    : Translation.tr("Restart now?")
                color: Appearance.m3colors.m3onSurface
                font.pixelSize: Appearance.font.pixelSize.small
                wrapMode: Text.Wrap
            }

            StyledText {
                width: parent.width
                text: Translation.tr("You and any other people using this PC could lose unsaved work.")
                color: Appearance.m3colors.m3onSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.smaller
                wrapMode: Text.Wrap
            }
        }

        Row {
            id: popupButtons
            anchors {
                bottom: parent.bottom
                right: parent.right
                margins: 12
            }
            spacing: 15

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: Translation.tr("Cancel")
                color: Appearance.colors.colOnSurface
                font.pixelSize: Appearance.font.pixelSize.small

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.closeConfirmPopup(false)
                }
            }

            // Confirm button (filled primary)
            Rectangle {
                width: confirmText.implicitWidth + 20
                height: 32
                radius: Appearance.rounding.full
                color: Appearance.colors.colPrimary

                StyledText {
                    id: confirmText
                    anchors.centerIn: parent
                    text: root.pendingAction === LockContext.ActionEnum.Poweroff
                        ? Translation.tr("Shutdown")
                        : Translation.tr("Restart")
                    color: Appearance.colors.colOnPrimary
                    font.pixelSize: Appearance.font.pixelSize.small
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.closeConfirmPopup(true)
                }
            }
        }
    }
}
