import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls

/**
 * Material 3 styled SpinBox component.
 */
SpinBox {
    id: root

    property real baseHeight: 35
    property real radius: Appearance.rounding.small
    property real innerButtonRadius: Appearance.rounding.unsharpen
    // Colour slots; defaults keep the old hard-coded layer colours.
    property color colBg: Appearance.colors.colLayer2
    property color colFg: Appearance.colors.colOnLayer2
    property color colBgHover: Appearance.colors.colLayer2Hover
    property color colBgPressed: Appearance.colors.colLayer2Active
    // Flat "Sides" style: value sits on the parent background, minus/plus
    // become translucent circles at both ends.
    property bool flat: false
    editable: true

    opacity: root.enabled ? 1 : 0.4

    background: Rectangle {
        color: root.flat ? "transparent" : root.colBg
        radius: root.radius
    }

    contentItem: Item {
        implicitHeight: root.baseHeight
        implicitWidth: Math.max(labelText.implicitWidth, 40)

        StyledTextInput {
            id: labelText
            anchors.centerIn: parent
            text: root.value // displayText would make the numbers weird like 1,000 instead of 1000
            color: root.colFg
            font.family: Appearance.font.family.numbers
            font.variableAxes: Appearance.font.variableAxes.numbers
            font.pixelSize: Appearance.font.pixelSize.small
            validator: root.validator
            onTextChanged: {
                root.value = parseFloat(text);
            }
        }
    }

    down.indicator: Rectangle {
        anchors {
            verticalCenter: parent.verticalCenter
            left: parent.left
        }
        implicitHeight: root.baseHeight
        implicitWidth: root.baseHeight
        topLeftRadius: root.flat ? height / 2 : root.radius
        bottomLeftRadius: root.flat ? height / 2 : root.radius
        topRightRadius: root.flat ? height / 2 : root.innerButtonRadius
        bottomRightRadius: root.flat ? height / 2 : root.innerButtonRadius

        color: root.flat ? (root.down.pressed ? Qt.rgba(1, 1, 1, 0.35) :
            root.down.hovered ? Qt.rgba(1, 1, 1, 0.26) : Qt.rgba(1, 1, 1, 0.14)) :
            root.down.pressed ? root.colBgPressed :
            root.down.hovered ? root.colBgHover :
            ColorUtils.transparentize(root.colBg)
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: "remove"
            iconSize: 20
            color: root.colFg
        }
    }

    up.indicator: Rectangle {
        anchors {
            verticalCenter: parent.verticalCenter
            right: parent.right
        }
        implicitHeight: root.baseHeight
        implicitWidth: root.baseHeight
        topRightRadius: root.flat ? height / 2 : root.radius
        bottomRightRadius: root.flat ? height / 2 : root.radius
        topLeftRadius: root.flat ? height / 2 : root.innerButtonRadius
        bottomLeftRadius: root.flat ? height / 2 : root.innerButtonRadius

        color: root.flat ? (root.up.pressed ? Qt.rgba(1, 1, 1, 0.35) :
            root.up.hovered ? Qt.rgba(1, 1, 1, 0.26) : Qt.rgba(1, 1, 1, 0.14)) :
            root.up.pressed ? root.colBgPressed :
            root.up.hovered ? root.colBgHover :
            ColorUtils.transparentize(root.colBg)
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: "add"
            iconSize: 20
            color: root.colFg
        }
    }
}
