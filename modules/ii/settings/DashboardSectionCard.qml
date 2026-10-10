import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.settings.pages

// Generic dashboard card hosting an embedded settings section component.
// Scrolls internally only when the content is taller than the card.
DashboardCard {
    id: root

    property string title: ""
    property string icon: "monitor"
    property var tileShape: MaterialShape.Shape.ClamShell
    property Component content
    // Render icon+title as the card chrome (like the other dashboard cards);
    // the hosted section then hides its own ContentSection header.
    property bool showHeader: false

    tint: Appearance.colors.colLayer1

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

            RowLayout {
                visible: root.showHeader
                Layout.fillWidth: true
                spacing: 12
                Layout.topMargin: visible ? 8 : 0
                Layout.leftMargin: visible ? 8 : 0
                Layout.bottomMargin: visible ? 10 : 0

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

            Loader {
                Layout.fillWidth: true
                sourceComponent: root.content
            }
        }
    }
}
