import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.settings.pages

// Hosts the shared Displays section (monitor canvas + per-monitor rows) inside
// a dashboard card. Scrolls internally only when the content is taller.
DashboardCard {
    id: root

    property string title: ""
    property string icon: "monitor"
    property var tileShape: MaterialShape.Shape.ClamShell

    tint: Appearance.colors.colTertiaryContainer

    // Natural content height (+12 = Flickable margins); lets the page grid
    // size this card's rows to fit — no empty space, no inner scrolling.
    readonly property real measuredHeight: col.implicitHeight + 12

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.margins: 6
        clip: true
        contentWidth: width
        contentHeight: col.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height + 2

        ScrollBar.vertical: StyledScrollBar {}

        ColumnLayout {
            id: col
            width: flick.width
            spacing: 0

            // Icon+title as the card chrome (like the other dashboard cards);
            // the Displays section below hides its own ContentSection header.
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Layout.topMargin: 8
                Layout.leftMargin: 8
                Layout.bottomMargin: 10

                MaterialShapeWrappedMaterialSymbol {
                    shape: root.tileShape
                    text: root.icon
                    iconSize: 24
                    fill: 1
                    padding: 10
                    color: Appearance.colors.colTertiary
                    colSymbol: Appearance.colors.colOnTertiary
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colTertiary
                    elide: Text.ElideRight
                }
            }

            DisplaysSection {
                Layout.fillWidth: true
                showHeader: false
                // Section header badge + glyph follow the tertiary family too.
                bgColor: Appearance.colors.colTertiaryContainer
                iconColor: Appearance.colors.colOnTertiaryContainer
                // M3 Expressive: the whole monitor block reads tertiary
                // (green) — solid canvas tile, green surfaces, labels and
                // controls, inside the dropdown too.
                accent: Appearance.colors.colTertiary
                accentHover: Appearance.colors.colTertiaryHover
                accentActive: Appearance.colors.colTertiaryActive
                accentContainer: Appearance.colors.colTertiaryContainer
                accentOn: Appearance.colors.colOnTertiary
                panelColor: Appearance.colors.colLayer1
                panelBorder: Appearance.colors.colTertiaryActive
                accentFill: Appearance.colors.colTertiary
                accentOnFill: Appearance.colors.colOnTertiary
                accentOnFillSub: Appearance.colors.colOnTertiary
                rowBg: Appearance.colors.colLayer1
                surfaceText: Appearance.colors.colOnTertiaryContainer
                chevronColor: Appearance.colors.colOnTertiaryContainer
                fieldBg: Appearance.colors.colTertiary
                fieldBgHover: Appearance.colors.colTertiaryHover
                fieldBgActive: Appearance.colors.colTertiaryActive
                fieldText: Appearance.colors.colOnTertiary
                spinBg: Appearance.colors.colTertiary
                spinFg: Appearance.colors.colOnTertiaryContainer
                spinFlat: true
                switchActive: Appearance.colors.colTertiary
                switchThumb: Appearance.colors.colOnTertiary
                spinBgHover: Appearance.colors.colTertiaryHover
                spinBgActive: Appearance.colors.colTertiaryActive
                noticeBg: Appearance.colors.colTertiary
                noticeFg: Appearance.colors.colOnTertiary
                titleColor: Appearance.colors.colOnTertiaryContainer
                colChip: Appearance.colors.colTertiaryActive
                colChipHover: Appearance.colors.colTertiaryHover
                colChipActive: Appearance.colors.colTertiaryHover
                colChipText: Appearance.colors.colOnTertiaryContainer
                colToggledText: Appearance.colors.colOnTertiary
                colPopup: Appearance.colors.colLayer1
                colPopupText: Appearance.colors.colOnTertiaryContainer
                colPopupHover: Appearance.colors.colTertiaryHover
                colPopupActive: Appearance.colors.colTertiaryHover
            }
        }
    }
}
