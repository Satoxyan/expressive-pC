import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Loader {
    id: root
    required property string icon
    property real iconSize: Appearance.font.pixelSize.larger
    property bool toggled: false
    // Icon colour when not toggled; default keeps the old hard-coded value.
    property color iconColor: Appearance.colors.colOnSecondaryContainer
    Layout.alignment: Qt.AlignVCenter

    active: root.icon && root.icon.length > 0
    visible: active

    sourceComponent: Item {
        implicitWidth: materialSymbol.implicitWidth

        MaterialSymbol {
            id: materialSymbol
            anchors.centerIn: parent

            iconSize: root.iconSize
            color: root.toggled ? Appearance.colors.colOnPrimary : root.iconColor
            text: root.icon
        }
    }
}
