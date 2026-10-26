import qs.modules.common.widgets
import qs.modules.common
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

RowLayout {
    id: root

    property string text: ""
    property string description: ""
    property string buttonIcon: ""
    property alias placeholderText: textArea.placeholderText
    property alias value: textArea.text
    property alias textArea: textArea
    property bool filled: true
    property bool floatingLabel: false // label stays in the row in this fork
    property bool showBorder: !filled
    property bool rounded: false
    property bool multiline: false
    // Stacked puts the field under the title and its description instead of
    // beside them: the shape a long description needs in a narrow panel.
    property bool stacked: false
    property real fieldWidth: 220
    property real fieldHeight: 40
    property color colBackground: filled ? Appearance.colors.colLayer1 : "transparent"
    property color colBackgroundFocused: filled ? Appearance.colors.colLayer2 : "transparent"
    property color colBorder: Appearance.colors.colOutlineVariant
    property color colBorderFocused: Appearance.colors.colPrimary
    property color colOnBackground: Appearance.colors.colOnLayer1
    property color colLabel: Appearance.colors.colOnSecondaryContainer
    property real cornerRadius: rounded ? Appearance.rounding.large : Appearance.rounding.small

    property bool confirmButtonVisible: false
    property string confirmButtonIcon: "check"
    property color colConfirmBackground: Appearance.colors.colPrimaryContainer
    property color colConfirmBackgroundHover: Appearance.colors.colPrimaryContainerHover
    property color colConfirmBackgroundActive: Appearance.colors.colPrimaryContainerActive
    property color colOnConfirmBackground: Appearance.colors.colOnPrimaryContainer
    signal confirmClicked()

    spacing: 10
    Layout.leftMargin: 8
    Layout.rightMargin: 8

    OptionalMaterialSymbol {
        icon: root.buttonIcon
        iconSize: Appearance.font.pixelSize.larger
        opacity: root.enabled ? 1 : 0.4
        // Stacked: the title has a line of its own and this icon's box is
        // 0-tall, so the box grows to that line and pins to the top. That
        // keeps the glyph level with the title instead of with the whole row,
        // and the icon stays the row's first item.
        Layout.alignment: root.stacked ? Qt.AlignTop : Qt.AlignVCenter
        Layout.preferredHeight: root.stacked ? titleRow.implicitHeight : 0
    }

    ColumnLayout {
        id: labelColumn
        Layout.fillWidth: true
        spacing: root.stacked ? 6 : 0
        // The title's own line when the row is stacked, so its left edge and
        // baseline match the titled rows above and below it.
        RowLayout {
            id: titleRow
            visible: root.stacked
            Layout.fillWidth: true
        }
        StyledText {
            parent: root.stacked ? titleRow : labelColumn
            Layout.fillWidth: true
            Layout.maximumWidth: root.floatingLabel ? root.width * 0.45 : Number.POSITIVE_INFINITY
            text: root.text
            color: root.colLabel
            opacity: root.enabled ? 1 : 0.4
            wrapMode: Text.Wrap
        }
        StyledText {
            Layout.fillWidth: true
            visible: root.description.length > 0
            text: root.description
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            wrapMode: Text.Wrap
            opacity: root.enabled ? 1 : 0.4
        }
        // The field's line when the row is stacked. `fieldBg` and
        // `confirmBtn` reparent into this, so the plain row keeps its shape.
        RowLayout {
            id: fieldRow
            visible: root.stacked
            Layout.fillWidth: true
            spacing: 10
        }
    }

    Rectangle {
        id: fieldBg
        parent: root.stacked ? fieldRow : root
        Layout.fillWidth: root.stacked
        Layout.preferredWidth: root.stacked ? 40 : root.fieldWidth
        Layout.preferredHeight: root.fieldHeight
        Layout.alignment: Qt.AlignVCenter
        radius: root.cornerRadius
        clip: true
        color: textArea.activeFocus ? root.colBackgroundFocused : root.colBackground
        border.width: (hoverHandler.hovered || textArea.activeFocus) ? (textArea.activeFocus ? 2 : 1) : 0
        border.color: textArea.activeFocus ? root.colBorderFocused : root.colBorder

        Behavior on color {
            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
        }
        Behavior on border.color {
            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
        }
        Behavior on border.width {
            NumberAnimation { duration: Appearance.animation.elementMoveFast.duration }
        }

        HoverHandler {
            id: hoverHandler
        }

        TextArea {
            id: textArea
            ContextMenu.menu: StyledTextEditMenu { editor: textArea }
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            enabled: root.enabled
            wrapMode: TextArea.Wrap
            verticalAlignment: root.multiline ? TextEdit.AlignTop : TextEdit.AlignVCenter
            topPadding: root.multiline ? 10 : 0
            bottomPadding: root.multiline ? 10 : 0
            selectByMouse: true
            placeholderTextColor: Appearance.colors.colSubtext
            color: root.colOnBackground
            selectedTextColor: Appearance.colors.colOnSecondaryContainer
            selectionColor: Appearance.colors.colSecondaryContainer
            renderType: Text.NativeRendering
            background: null
            padding: 0
            font {
                family: Appearance.font.family.main
                pixelSize: Appearance.font.pixelSize.small
                hintingPreference: Font.PreferFullHinting
                variableAxes: Appearance.font.variableAxes.main
            }

            Keys.onReturnPressed: function(event) {
                if (root.multiline && !(event.modifiers & Qt.ControlModifier)) {
                    event.accepted = false
                    return
                }
                event.accepted = true
                root.confirmClicked()
            }
            Keys.onEnterPressed: function(event) {
                if (root.multiline && !(event.modifiers & Qt.ControlModifier)) {
                    event.accepted = false
                    return
                }
                event.accepted = true
                root.confirmClicked()
            }
        }
    }

    Rectangle {
        id: confirmBtn
        visible: root.confirmButtonVisible
        parent: root.stacked ? fieldRow : root
        Layout.preferredWidth: 40
        Layout.preferredHeight: 40
        Layout.alignment: Qt.AlignVCenter
        radius: Appearance.rounding.small
        color: confirmMouseArea.pressed
            ? root.colConfirmBackgroundActive
            : (confirmMouseArea.containsMouse ? root.colConfirmBackgroundHover : root.colConfirmBackground)

        Behavior on color {
            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: root.confirmButtonIcon
            iconSize: Appearance.font.pixelSize.large
            color: root.colOnConfirmBackground
        }

        MouseArea {
            id: confirmMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.confirmClicked()
        }
    }
}