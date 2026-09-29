import qs
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Qt5Compat.GraphicalEffects


Item {
    id: root

    readonly property string quoteText: Config.options.background.widgets.clock.quote.text

    property Item wallpaperItem: null
    property real originX: 0
    property real originY: 0
    readonly property bool blurOn: wallpaperItem !== null && GlobalStates.clockBlur

    implicitWidth: quoteBox.implicitWidth
    implicitHeight: quoteBox.implicitHeight

    DropShadow {
        source: quoteBox 
        anchors.fill: quoteBox
        horizontalOffset: 0
        verticalOffset: 2
        radius: 12
        samples: radius * 2 + 1
        color: Appearance.colors.colShadow
        transparentBorder: true
    }
    
    Rectangle {
        id: quoteBox
        y: Config.options.background.widgets.clock.style === "pixel" && Config.options.background.widgets.clock.pixel.orientation === "horizontal" ? -26 : 0
        x: Config.options.background.widgets.clock.style === "pixel" && Config.options.background.widgets.clock.pixel.orientation === "horizontal" ? -20 : 0
        implicitWidth: quoteRow.implicitWidth + 8 * 2
        implicitHeight: quoteRow.implicitHeight + 4 * 2
        radius: Appearance.rounding.small
        color: Appearance.colors.colSecondaryContainer

        Row {
            id: quoteRow
            anchors.centerIn: parent
            spacing: 4
            
            MaterialSymbol {
                id: quoteIcon
                anchors.top: parent.top
                iconSize: Appearance.font.pixelSize.huge
                text: "format_quote"
                color: Appearance.colors.colOnSecondaryContainer
            }
            StyledText {
                id: quoteStyledText
                horizontalAlignment: Text.AlignLeft
                text: Config.options.background.widgets.clock.quote.text
                color: Appearance.colors.colOnSecondaryContainer
                font {
                    family: Config.options.background.widgets.clock.quote.followClock ? Config.options.background.widgets.clock.digital.font.family : Appearance.font.family.reading 
                    pixelSize: Appearance.font.pixelSize.large
                    weight: Font.Normal
                }
            }
        }

        // Blurred wallpaper clipped to the quote text, tinted with the text's own colour.
        FastBlurred {
            id: quoteBlur
            anchors.fill: quoteRow
            blurSource: root.wallpaperItem
            cardRadius: 0
            tint: Appearance.colors.colOnSecondaryContainer
            tintOpacity: 0.55
            tintEnabled: GlobalStates.clockTintBlur
            // Same refresh trigger as the other FastBlurred users: sourceRect can't track mapToItem().
            trackX: root.originX + root.x
            trackY: root.originY + root.y
            visible: false
        }
        OpacityMask {
            anchors.fill: quoteRow
            source: quoteBlur
            maskSource: quoteRow
            visible: root.blurOn
        }
    }
}
