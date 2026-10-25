import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    property bool shown: true
    property real minIconHeight: 0
    property alias icon: shapeWidget.text
    property alias title: widgetNameText.text
    property alias description: widgetDescriptionText.text
    property alias shape: shapeWidget.shape
    property alias descriptionHorizontalAlignment: widgetDescriptionText.horizontalAlignment
    property real descriptionMaximumWidth: -1
    property bool dropIconWhenCramped: false // no-op; kept for upstream call sites

    opacity: shown ? 1 : 0
    visible: opacity > 0
    anchors {
        fill: parent
        topMargin: -30 * (1 - opacity)
        bottomMargin: 30 * (1 - opacity)
    }

    Behavior on opacity {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }

    ColumnLayout {
        anchors.centerIn: parent
        // The column has to be given a width for the description's
        // Layout.fillWidth to mean anything: sized only by its contents it
        // measured itself to the sentence's UNWRAPPED length, so a description
        // longer than the widget ran off both sides of it and the clipping cut
        // the words in half at the edges.
        width: root.descriptionMaximumWidth > 0
            ? Math.min(root.width, root.descriptionMaximumWidth)
            : root.width
        spacing: 5

        MaterialShapeWrappedMaterialSymbol {
            id: shapeWidget
            visible: root.height >= root.minIconHeight
            Layout.alignment: Qt.AlignHCenter
            padding: 12
            iconSize: 56
            rotation: -30 * (1 - root.opacity)
        }
        StyledText {
            id: widgetNameText
            visible: title !== ""
            Layout.alignment: Qt.AlignHCenter
            font {
                family: Appearance.font.family.title
                pixelSize: Appearance.font.pixelSize.larger
                variableAxes: Appearance.font.variableAxes.title
            }
            color: Appearance.m3colors.m3outline
            horizontalAlignment: Text.AlignHCenter
        }
        StyledText {
            id: widgetDescriptionText
            visible: description !== ""
            Layout.fillWidth: true
            Layout.maximumWidth: root.descriptionMaximumWidth > 0 ? root.descriptionMaximumWidth : Infinity
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.m3colors.m3outline
            horizontalAlignment: Text.AlignLeft
            wrapMode: Text.Wrap
        }
    }
}
