import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Qt5Compat.GraphicalEffects

Rectangle {
    id: root

    property real iconSize: 32
    property color iconColor: Appearance.colors.colOnPrimaryContainer
    readonly property alias status: avatarImage.status
    // Avatar singleton: explicitly picked picture -> first image in the avatar folder.
    // Falls back to ~/.face so a plain ~/.face file still shows.
    readonly property string picturePath: Avatar.effectiveAvatarSource !== ""
        ? Avatar.effectiveAvatarSource
        : `file://${FileUtils.trimFileProtocol(Directories.home)}/.face`

    implicitWidth: 48
    implicitHeight: 48
    radius: width / 2
    color: avatarImage.status !== Image.Ready ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1

    Image {
        id: avatarImage
        anchors.fill: parent
        anchors.margins: root.border.width
        source: root.picturePath
        sourceSize.width: width * 2
        sourceSize.height: height * 2
        fillMode: Image.PreserveAspectCrop
        cache: false
        visible: status === Image.Ready
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: avatarImage.width
                height: avatarImage.height
                radius: Math.max(0, root.radius - root.border.width)
            }
        }
    }

    MaterialSymbol {
        anchors.centerIn: parent
        text: "account_circle"
        iconSize: root.iconSize
        color: root.iconColor
        visible: avatarImage.status !== Image.Ready
    }
}
