import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "clock"

    implicitHeight: contentColumn.implicitHeight
    implicitWidth: contentColumn.implicitWidth

    readonly property string clockStyle: GlobalStates.screenLocked ? Config.options.background.widgets.clock.styleLocked : Config.options.background.widgets.clock.style
    readonly property bool forceCenter: (GlobalStates.screenLocked && Config.options.lock.centerClock)
    readonly property bool shouldShow: (!Config.options.background.widgets.clock.showOnlyWhenLocked || GlobalStates.screenLocked)
    readonly property string customClockColorKey: Config.options.background.widgets.clock.color ?? ""
    function paletteColor(key) {
        if (key === "") return root.colText;
        if (key === "adaptive")
            return ColorUtils.colorWithLightness(Appearance.colors.colPrimary, (root.dominantColorIsDark ? 0.8 : 0.12));
        const propName = "col" + key.charAt(0).toUpperCase() + key.slice(1);
        return Appearance.colors[propName] ?? root.colText;
    }
    readonly property color resolvedClockColor: paletteColor(customClockColorKey)
    readonly property bool effectiveVertical: GlobalStates.screenLocked ? Config.options.background.widgets.clock.digital.verticalLocked : Config.options.background.widgets.clock.digital.vertical
    readonly property string effectiveColorMode: GlobalStates.screenLocked ? Config.options.background.widgets.clock.digital.colorModeLocked : Config.options.background.widgets.clock.digital.colorMode
    property bool wallpaperSafetyTriggered: false
    needsColText: clockStyle === "digital"

    property real refWidth: 0
    property real refHeight: 0
    readonly property real centerX: root.refWidth > 0 ? (root.targetX + root.refWidth / 2) : (root.targetX + root.width / 2)
    readonly property real centerY: root.refHeight > 0 ? (root.targetY + root.refHeight / 2) : (root.targetY + root.height / 2)
    onTargetXChanged: root.refWidth = root.width
    onTargetYChanged: root.refHeight = root.height
    Component.onCompleted: {
        root.refWidth = root.width;
        root.refHeight = root.height;
    }

    x: forceCenter ? ((root.screenWidth - root.width) / 2) : (root.centerX - root.width / 2)
    y: forceCenter ? ((root.screenHeight - root.height) / 2) : (root.centerY - root.height / 2)
    visibleWhenLocked: true

    readonly property color effectiveColText: {
        if (effectiveColorMode === "auto")
            return paletteColor(Appearance.wallpaperIsDark ? Config.options.background.widgets.clock.digital.colorLight : Config.options.background.widgets.clock.digital.colorDark);
        if (effectiveColorMode === "light")
            return paletteColor(Config.options.background.widgets.clock.digital.colorLight);
        return paletteColor(Config.options.background.widgets.clock.digital.colorDark);
    }

    function restoreXYBinding() {
        root.x = Qt.binding(() => root.forceCenter ? ((root.screenWidth - root.width) / 2) : (root.centerX - root.width / 2));
        root.y = Qt.binding(() => root.forceCenter ? ((root.screenHeight - root.height) / 2) : (root.centerY - root.height / 2));
    }

    property var textHorizontalAlignment: {
        if (!Config.options.background.widgets.clock.digital.adaptiveAlignment || root.forceCenter || root.effectiveVertical) 
            return Text.AlignHCenter;
        if (root.x < root.scaledScreenWidth / 3)
            return Text.AlignLeft;
        if (root.x > root.scaledScreenWidth * 2 / 3)
            return Text.AlignRight;
        return Text.AlignHCenter;
    }

    Column {
        id: contentColumn
        anchors.centerIn: parent
        spacing: 10

        FadeLoader {
            id: cookieClockLoader
            anchors.horizontalCenter: parent.horizontalCenter
            shown: root.clockStyle === "cookie" && (root.shouldShow)
            fade: false
            sourceComponent: CookieClock {
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }

        FadeLoader {
            id: digitalClockLoader
            anchors.horizontalCenter: parent.horizontalCenter
            shown: root.clockStyle === "digital" && (root.shouldShow)
            fade: false
            sourceComponent: DigitalClock {
                locked: GlobalStates.screenLocked
                colText: root.effectiveColText
                textHorizontalAlignment: root.textHorizontalAlignment
            }
        }

        FadeLoader {
            id: pixelClockLoader
            anchors.horizontalCenter: parent.horizontalCenter
            shown: root.clockStyle === "pixel" && (root.shouldShow)
            fade: false
            sourceComponent: PixelClock {}
        }

        FadeLoader {
            id: pixelDateLoader
            anchors.horizontalCenter: parent.horizontalCenter
            shown: root.clockStyle === "pixel" && Config.options.background.widgets.clock.pixel.showDate && GlobalStates.screenLocked && root.shouldShow
            fade: false
            sourceComponent: ClockText {
                horizontalAlignment: Text.AlignHCenter
                font {
                    family: Config.options.background.widgets.clock.digital.font.family
                    weight: Config.options.background.widgets.clock.pixel.weight
                    pixelSize: Appearance.font.pixelSize.huge * Config.options.background.widgets.clock.pixel.size
                }
                text: DateTime.longDate
            }
        }

        FadeLoader {
            id: quoteLoader
            anchors.horizontalCenter: parent.horizontalCenter
            shown: Config.options.background.widgets.clock.quote.enable && (root.clockStyle === "pixel" || root.clockStyle === "cookie") && Config.options.background.widgets.clock.quote.text !== "" && root.shouldShow
            sourceComponent: CookieQuote {}
        }

        StatusRow {
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    component StatusRow: Item {
        id: statusText
        implicitHeight: statusTextBg.implicitHeight
        implicitWidth: statusTextBg.implicitWidth
        StyledRectangularShadow {
            target: statusTextBg
            visible: statusTextBg.visible && root.clockStyle === "cookie"
            opacity: statusTextBg.opacity
        }
        Rectangle {
            id: statusTextBg
            anchors.centerIn: parent
            clip: true
            opacity: (safetyStatusText.shown || lockStatusText.shown) ? 1 : 0
            visible: opacity > 0
            implicitHeight: statusTextRow.implicitHeight + 5 * 2
            implicitWidth: statusTextRow.implicitWidth + 5 * 2
            radius: Appearance.rounding.small
            color: ColorUtils.transparentize(Appearance.colors.colSecondaryContainer, root.clockStyle === "cookie" ? 0 : 1)

            Behavior on implicitWidth {
                animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
            }
            Behavior on implicitHeight {
                animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
            }
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            RowLayout {
                id: statusTextRow
                anchors.centerIn: parent
                spacing: 14
                Item {
                    Layout.fillWidth: root.textHorizontalAlignment !== Text.AlignLeft
                    implicitWidth: 1
                }
                ClockStatusText {
                    id: safetyStatusText
                    shown: root.wallpaperSafetyTriggered
                    statusIcon: "hide_image"
                    statusText: Translation.tr("Wallpaper safety enforced")
                }
                ClockStatusText {
                    id: lockStatusText
                    shown: GlobalStates.screenLocked && Config.options.lock.showLockedText
                    statusIcon: "lock"
                    statusText: Translation.tr("Locked")
                }
                Item {
                    Layout.fillWidth: root.textHorizontalAlignment !== Text.AlignRight
                    implicitWidth: 1
                }
            }
        }
    }

    component ClockStatusText: Row {
        id: statusTextRow
        property alias statusIcon: statusIconWidget.text
        property alias statusText: statusTextWidget.text
        property bool shown: true
        property color textColor: root.clockStyle === "cookie" ? Appearance.colors.colOnSecondaryContainer : root.effectiveColText
        opacity: shown ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        spacing: 4
        MaterialSymbol {
            id: statusIconWidget
            anchors.verticalCenter: statusTextRow.verticalCenter
            iconSize: Appearance.font.pixelSize.huge
            color: statusTextRow.textColor
            style: Text.Raised
            styleColor: Appearance.colors.colShadow
        }
        ClockText {
            id: statusTextWidget
            color: statusTextRow.textColor
            horizontalAlignment: root.textHorizontalAlignment
            anchors.verticalCenter: statusTextRow.verticalCenter
            font {
                pixelSize: Appearance.font.pixelSize.large
                weight: Font.Normal
            }
            style: Text.Raised
            styleColor: Appearance.colors.colShadow
        }
    }
}
