import qs.modules.common.widgets
import qs.modules.common
import QtQuick
import QtQuick.Layouts

RowLayout {
    id: root
    property string text: ""
    property string icon
    property alias value: spinBoxWidget.value
    property alias stepSize: spinBoxWidget.stepSize
    property alias from: spinBoxWidget.from
    property alias to: spinBoxWidget.to
    signal valueModified()
    // Colour slots; defaults keep the old hard-coded colours.
    property color colLabel: Appearance.colors.colOnSecondaryContainer
    property color spinBg: Appearance.colors.colLayer2
    property color spinFg: Appearance.colors.colOnLayer2
    property color spinBgHover: Appearance.colors.colLayer2Hover
    property color spinBgActive: Appearance.colors.colLayer2Active
    spacing: 10
    Layout.leftMargin: 8
    Layout.rightMargin: 8

    RowLayout {
        spacing: 10
        OptionalMaterialSymbol {
            icon: root.icon
            iconColor: root.colLabel
            opacity: root.enabled ? 1 : 0.4
        }
        StyledText {
            id: labelWidget
            Layout.fillWidth: true
            text: root.text
            color: root.colLabel
            opacity: root.enabled ? 1 : 0.4
        }
    }

    StyledSpinBox {
        id: spinBoxWidget
        Layout.fillWidth: false
        value: root.value
        colBg: root.spinBg
        colFg: root.spinFg
        colBgHover: root.spinBgHover
        colBgPressed: root.spinBgActive
        onValueModified: root.valueModified()
    }
}
