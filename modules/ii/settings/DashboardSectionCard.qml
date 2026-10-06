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

            Loader {
                Layout.fillWidth: true
                sourceComponent: root.content
            }
        }
    }
}
