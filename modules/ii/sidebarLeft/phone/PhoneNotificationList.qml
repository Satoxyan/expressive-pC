import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * The phone's mirrored notifications, grouped by the app that posted them.
 *
 * This is a first-pass list: the shared NotificationListView in this fork
 * predates the controller seam the upstream Phone tab uses, so the cards are
 * drawn here from PhoneNotifications' card fields. Polish later.
 */
Item {
    id: root

    property real appear: 1

    readonly property int count: PhoneNotifications.count
    // Which of the four reasons there is nothing to draw, most specific
    // first. The phone-side one is last because it is the only one that
    // means the link itself is fine.
    readonly property string emptyTitle: {
        if (!PhoneConnect.installed) return Translation.tr("busctl was not found");
        if (!PhoneConnect.available) return Translation.tr("No phone daemon is running");
        if (PhoneConnect.devices.length === 0) return Translation.tr("No devices yet");
        return Translation.tr("No notifications");
    }
    readonly property string emptyDescription: {
        if (!PhoneConnect.installed) return Translation.tr("Phone Connect drives KDE Connect and Valent over D-Bus through busctl, which ships with systemd.");
        if (!PhoneConnect.available) return Translation.tr("Start KDE Connect or Valent to see your phone here.");
        if (PhoneConnect.devices.length === 0) return Translation.tr("Pair your phone from KDE Connect or Valent and it will appear here.");
        return Translation.tr("Make sure KDE Connect has Notification Access on your phone.");
    }

    PagePlaceholder {
        shown: root.count === 0
        icon: PhoneConnect.devices.length === 0 ? "mobile_off" : "notifications_off"
        shape: MaterialShape.Shape.Ghostish
        title: root.emptyTitle
        description: root.emptyDescription
        descriptionHorizontalAlignment: Text.AlignHCenter
    }

    ListView {
        anchors.fill: parent
        visible: root.count > 0
        clip: true
        spacing: Appearance.spacing.space75
        model: PhoneNotifications.notifications

        delegate: Rectangle {
            id: card
            required property var modelData
            required property int index

            width: ListView.view.width
            implicitHeight: cardColumn.implicitHeight + Appearance.spacing.space200
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2

            ColumnLayout {
                id: cardColumn
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: Appearance.spacing.space100
                }
                spacing: Appearance.spacing.space25

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Appearance.spacing.space50

                    StyledText {
                        Layout.fillWidth: true
                        text: card.modelData.appName ?? ""
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }

                    IconButton {
                        buttonSize: 26
                        buttonIcon: "close"
                        tooltip: Translation.tr("Dismiss")
                        onClicked: PhoneNotifications.dismiss(card.modelData.publicId)
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: card.modelData.title ?? ""
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: card.modelData.text ?? ""
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                }
            }
        }
    }
}
