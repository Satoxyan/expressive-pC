import qs.modules.common
import qs.modules.common.widgets
import QtQuick

Item {
    id: root
    property bool vertical: false
    readonly property bool isMaterial: Config.options.bar.cornerStyle === 3 || Config.options.bar.cornerStyle === 4

    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : avatar.width + (root.isMaterial ? 0 : 8)
    implicitHeight: vertical ? avatar.height + 8 : Appearance.sizes.barHeight

    UserAvatar {
        id: avatar
        anchors.centerIn: parent
        width: root.isMaterial ? 32 : 24
        height: root.isMaterial ? 32 : 24
        iconSize: Appearance.font.pixelSize.larger
    }
}
