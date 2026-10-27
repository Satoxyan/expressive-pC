import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.phone
import QtQuick
import QtQuick.Layouts

/**
 * ONE row of seven round actions, in the fork's order: ring, ping, send the
 * clipboard, send a file, share the clipboard as a link or as text, browse
 * the phone's storage, and hand this machine's pointer to the phone.
 *
 * Each button is enabled by two things and not one: the device has to be
 * reachable, and the BACKEND has to answer that action. Valent's action
 * names beyond findmyphone.ring were never verifiable against a live
 * daemon, so `canPing` / `canSendClipboard` / `canShare` / `canBrowseFiles`
 * are all kdeconnect-only and a Valent user gets a row where only Ring
 * lights up - which is honest, where a row of live buttons that do nothing
 * is not. The seventh is the same rule with one extra condition: remote input
 * travels over KDE Connect's `remotecontrol` interface, and it is offered only
 * while the daemon has that plugin loaded for this phone, which the service
 * reads as `PhoneConnect.remoteInputSupported`.
 *
 * Nothing in this checkout enforces the pairing of a button to a declared
 * service call - `tests/test_phone_connect_contract.py` is cited by older
 * comments and does not exist - so the rule is kept by hand: a button appears
 * here once the service behind it answers. The seventh answers to
 * `PhoneConnect.setRemoteInputActive`, which starts the bridge that holds this
 * machine's pointer devices: `scripts/phone/kdeconnect_input_bridge.py`.
 */
Item {
    id: root

    // The device the tab is about; the row asks the service about it.
    property var device: null
    readonly property bool online: root.device !== null
        && root.device.paired && root.device.reachable

    property real appear: 1

    // Pointer sharing is a switch whose state lives in the daemon, not in
    // anything the shell watches, so opening the row asks once. The service's
    // own refresh covers every change after that.
    Component.onCompleted: PhoneConnect.refreshRemoteInput(root.device)

    implicitHeight: actionRow.implicitHeight

    RowLayout {
        id: actionRow
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        spacing: Appearance.spacing.space100

        PhoneActionButton {
            id: ringButton
            glyph: "phone_in_talk"
            label: Translation.tr("Ring phone")
            enabled: root.online
            onClicked: PhoneConnect.ring(root.device)
        }
        PhoneActionButton {
            id: pingButton
            glyph: "notifications_active"
            label: Translation.tr("Send a ping")
            enabled: root.online && PhoneConnect.canPing
            onClicked: PhoneConnect.ping(root.device)
        }
        PhoneActionButton {
            id: clipboardButton
            glyph: "content_paste"
            label: Translation.tr("Send clipboard to phone")
            enabled: root.online && PhoneConnect.canSendClipboard
            onClicked: PhoneConnect.sendClipboard(root.device)
        }
        PhoneActionButton {
            id: sendFileButton
            glyph: "file_upload"
            label: Translation.tr("Send file…")
            enabled: root.online && PhoneConnect.canShare
            onClicked: PhoneConnect.pickAndSendFiles(root.device)
        }
        PhoneActionButton {
            id: shareClipboardButton
            glyph: "link"
            label: Translation.tr("Share clipboard as a link or text")
            enabled: root.online && PhoneConnect.canShare
            onClicked: PhoneConnect.shareClipboard(root.device)
        }
        PhoneActionButton {
            id: browseFilesButton
            glyph: "folder_shared"
            label: Translation.tr("Browse phone files")
            enabled: root.online && PhoneConnect.canBrowseFiles
            onClicked: PhoneConnect.browseFiles(root.device)
        }
        PhoneActionButton {
            id: remoteInputButton
            glyph: "mouse"
            // The label doubles as the tooltip, and the two states say
            // different things: one is an offer, the other has to name the way
            // out, because a screen that eats the mouse says nothing else.
            label: PhoneConnect.remoteInputActive
                ? Translation.tr(
                    "Remote input is on — Alt+X or both mouse buttons give the mouse back")
                : Translation.tr("Remote input")
            toggled: PhoneConnect.remoteInputActive
            // KDE Connect's remote-control interface has to be loaded for this
            // phone, and the pointer has to be somewhere to take it from.
            enabled: root.online && PhoneConnect.canRemoteInput
                && PhoneConnect.remoteInputSupported
            onClicked: PhoneConnect.setRemoteInputActive(
                !PhoneConnect.remoteInputActive)
        }
    }
}
