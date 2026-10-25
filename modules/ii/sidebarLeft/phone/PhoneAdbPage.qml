pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The Phone tab's Phone link (ADB) sub-page: the whole adb link, on purpose.
 *
 * It exists because the shell already had the job and had buried it.
 * `PhoneAdbPairPanel` pairs, connects and looks the ports up over avahi, and
 * before this page it was drawn by exactly one surface - the Android Apps
 * page - under `visible: appModeSupported && panel.shown`, which is a
 * REFUSAL: it hides as soon as adb lists any device at all. So a phone whose
 * wireless debugging had died, whose DHCP address had moved and whose port
 * had re-rolled left the user with three cards saying "offline", clicks that
 * went nowhere, and no way to the one form that fixes it. The header's adb
 * button opens this page, and this page hands the panel
 * `formAlwaysShown: true`, which is the difference between the form being an
 * apology and being a feature.
 *
 * What is decided HERE is only the framing and the re-check. The panel owns
 * every adb sentence it prints, including the three failure states, and this
 * page does not write a second copy of any of them - `diagnosis` covers
 * "not installed" and "cannot start", and the healthy line below appears
 * only when the panel has nothing to complain about.
 */
PhoneSubPage {
    id: root

    title: Translation.tr("Phone link (ADB)")

    // The healthy case has to be waited for rather than assumed, because
    // every PhoneDeps flag starts false: `adbDevice` falsy is "no phone on
    // adb" only once the probes have ANSWERED, and an "all good" line that
    // drew during the first seconds of a session would be the same lie the
    // cards wear today, pointing the other way.
    readonly property bool linkUp: PhoneDeps.ready && PhoneDeps.adb && PhoneDeps.adbDevice

    // The same shape PhoneFeatureCards runs: a re-ask, only while this page is
    // on screen and adb has still seen nothing, so it stops the moment it has
    // an answer to give. The cards' copy cannot serve a user waiting here - it
    // is behind the sub-page that just slid over it.
    Timer {
        interval: 5000
        repeat: true
        running: root.visible && !root.linkUp && PhoneDeps.adb
        onTriggered: PhoneDeps.refreshAdbDevices()
    }

    ContentPage {
        id: page

        Layout.fillWidth: true
        Layout.fillHeight: true
        // ContentPage centres its content column at
        // `Math.max(baseWidth, implicitWidth)` and `baseWidth` defaults to the
        // settings window's 600; the panel hands this page 440, so an
        // uncapped column draws its left half outside the card. See
        // PhoneWebcamPage for the same three lines and the measurement behind
        // them.
        forceWidth: true
        baseWidth: Math.max(0, page.width - Appearance.spacing.space200)
        bottomContentPadding: Appearance.spacing.space400

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("The mirror, the webcam, the microphone and App Mode all drive the phone over adb. A phone paired to KDE Connect is reachable over its own link and carries notifications and files; that pairing does not set adb up, which is why a card can say the phone is right here and still have nothing to start.")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: root.linkUp
            materialIcon: "usb"
            text: Translation.tr("A device answers over adb. Everything on this tab that needs the phone has what it needs.")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.space75

            RippleButtonWithIcon {
                id: rescanButton
                // A machine whose adb is not installed, or cannot start, has
                // no probe to run, so the row it belongs to is not drawn.
                visible: PhoneDeps.adb
                materialIcon: "refresh"
                materialIconFill: false
                colBackground: Appearance.colors.colLayer3
                colBackgroundHover: Appearance.colors.colLayer3Hover
                colRipple: Appearance.colors.colLayer3Active
                mainText: Translation.tr("Check again")
                onClicked: PhoneDeps.refreshAdbDevices()

                StyledToolTip {
                    text: Translation.tr("Ask `adb devices` once more")
                }
            }

            Item {
                Layout.fillWidth: true
            }
        }

        PhoneAdbPairPanel {
            id: adbPanel

            Layout.fillWidth: true
            formAlwaysShown: true
        }
    }
}
