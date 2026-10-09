import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

GroupButton {
    id: root
    bounce: false
    property string buttonIcon
    property bool leftmost: false
    property bool rightmost: false

    property bool isDragging: false
    readonly property bool showToggled: root.toggled && root.enabled
    // Chip label colours; defaults keep the old hard-coded values.
    property color colTextInactive: Appearance.colors.colOnSecondaryContainer
    property color colTextActive: Appearance.colors.colOnPrimary
    property color colText: root.showToggled ? root.colTextActive : root.colTextInactive

    leftRadius: (showToggled || leftmost) ? (height / 2) : Appearance.rounding.unsharpenmore
    rightRadius: (showToggled || rightmost) ? (height / 2) : Appearance.rounding.unsharpenmore

    horizontalPadding: 12
    verticalPadding: 8 

    colBackground: Appearance.colors.colSecondaryContainer
    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
    colBackgroundActive: Appearance.colors.colSecondaryContainerActive

    contentItem: RowLayout {
        spacing: 4 * (root.buttonText?.length > 0)

        Loader {
            Layout.alignment: Qt.AlignVCenter
            active: root.buttonIcon && root.buttonIcon.length > 0
            visible: active
            sourceComponent: Item {
                implicitWidth: materialSymbol.implicitWidth
                MaterialSymbol {
                    id: materialSymbol
                    anchors.centerIn: parent
                    text: root.buttonIcon
                    iconSize: Appearance.font.pixelSize.larger
                    color: root.colText

                    Behavior on color { ColorAnimation { duration: 180 } }
                }
            }
        }

        Item {
            implicitWidth: root.buttonText?.length > 0 ? textItem.implicitWidth : 0
            implicitHeight: textMetrics.height
            TextMetrics {
                id: textMetrics
                font.family: Appearance.font.family.main
                text: "Abc"
            }
            StyledText {
                id: textItem
                anchors.centerIn: parent
                color: root.colText
                text: root.buttonText

                Behavior on color { ColorAnimation { duration: 180 } }
            }
        }
    }
}
