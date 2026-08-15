import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick

Item {
    id: root
    signal clicked(event: var)

    property bool material: false
    property bool showTextOnHover: false
    property bool vertical: Config.options.bar.vertical

    property bool isRecording: Persistent.states.record.enable
    readonly property double recordStart: Persistent.states.record.start > 0
        ? Persistent.states.record.start / 1000 : 0
    property int elapsedSeconds: 0

    onIsRecordingChanged: {
        if (!isRecording) elapsedSeconds = 0
    }

    function formatTime(s) {
        return Math.floor(s / 60).toString().padStart(2, '0') + ":" + (s % 60).toString().padStart(2, '0')
    }

    Timer {
        interval: 250
        repeat: true
        running: root.isRecording
        onTriggered: root.elapsedSeconds = root.recordStart > 0
            ? Math.max(0, Math.floor(Date.now() / 1000 - root.recordStart)) : 0
    }

    readonly property bool hoveredState: mouseArea.containsMouse
    readonly property bool textVisible: !root.vertical && (root.isRecording || (root.showTextOnHover && hoveredState))

    implicitWidth: pill.implicitWidth
    implicitHeight: pill.implicitHeight

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        onClicked: (e) => root.clicked(e)
    }

    Rectangle {
        id: pill
        anchors.fill: parent
        implicitHeight: Math.max(26, layout.implicitHeight)
        implicitWidth: {
            if (root.textVisible) return layout.implicitWidth + 24
            if (root.material && root.isRecording) return layout.implicitWidth + 24
            if (root.material && root.hoveredState) return 54
            return Math.max(26, layout.implicitWidth)
        }

        radius: root.isRecording ? Appearance.rounding.normal : implicitHeight / 2
        color: {
            if (root.isRecording) {
                return root.material
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colPrimaryContainer
            }
            if (root.hoveredState) {
                return root.material
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colLayer1Hover
            }
            return root.material
                ? ColorUtils.transparentize(Appearance.colors.colLayer0, 0.8)
                : "transparent"
        }

        Behavior on color { ColorAnimation { duration: 200 } }
        Behavior on radius { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on implicitWidth { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        Row {
            id: layout
            anchors.centerIn: parent
            spacing: 6

            MaterialSymbol {
                id: symbol
                text: root.isRecording ? "stop_circle" : "screen_record"
                iconSize: Appearance.font.pixelSize.large
                color: root.isRecording || root.hoveredState
                    ? (root.material
                        ? Appearance.colors.colOnPrimary
                        : Appearance.colors.colPrimary)
                    : (root.material
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colOnLayer2)
                Behavior on color { ColorAnimation { duration: 200 } }
            }

            StyledText {
                id: textLabel
                visible: root.textVisible
                width: implicitWidth
                text: root.formatTime(root.elapsedSeconds)
                color: symbol.color
                font.pixelSize: Math.max(8, Math.round(Appearance.font.pixelSize.small))
                font.bold: true
                font.features: { "tnum": 1 }
                font.letterSpacing: -0.3
                transform: Translate { y: 3 }
                Component.onCompleted: width = implicitWidth
            }
        }
    }
}