import qs.modules.common.widgets
import qs.modules.common
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

RippleButton {
    id: root
    property string buttonIcon
    property alias iconSize: iconWidget.iconSize
    // Optional recolor hooks — defaults match the old hard-coded colors,
    // so callers opt in (e.g. dashboard tertiary pass-through).
    property color colText: Appearance.colors.colOnSecondaryContainer
    property color colIcon: Appearance.colors.colOnSecondaryContainer
    property color switchActiveColor: Appearance.colors.colPrimaryContainer
    property color switchThumbColor: Appearance.colors.colPrimary
    colBackgroundHover: "transparent"

    Layout.fillWidth: true
    Layout.bottomMargin: 6 //Visually it works and I don't know why this should be handled by the parent.
    implicitHeight: contentItem.implicitHeight + 8 
    font.pixelSize: Appearance.font.pixelSize.small
    
    onClicked: checked = !checked

    contentItem: RowLayout {
        spacing: 10
        OptionalMaterialSymbol {
            id: iconWidget
            icon: root.buttonIcon
            iconColor: root.colIcon
            opacity: root.enabled ? 1 : 0.4
            iconSize: Appearance.font.pixelSize.larger
        }
        StyledText {
            id: labelWidget
            Layout.fillWidth: true
            text: root.text
            font: root.font
            color: root.colText
            opacity: root.enabled ? 1 : 0.4
        }
        StyledSwitch {
            id: switchWidget
            down: root.down
            Layout.fillWidth: false
            checked: root.checked
            activeColor: root.switchActiveColor
            thumbColor: root.switchThumbColor
            onClicked: root.clicked()
        }
    }
}
