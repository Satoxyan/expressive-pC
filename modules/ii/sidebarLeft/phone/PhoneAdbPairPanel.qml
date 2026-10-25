pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "phone_cards.js" as PhoneCards

/**
 * What the Phone link page draws for its whole subject, and what the Android
 * Apps page draws when App Mode has no transport - which on Android 11+ is a
 * job rather than a paragraph.
 *
 * The page used to print a recipe - open a terminal, type `adb pair
 * host:port code`, then `adb connect host:port` - and the maintainer's
 * objection was the right one: the shell can run those. It does, as
 * constant argv through `PhoneDeps` (which owns every other adb fact the
 * tab has), and each step's line here is the one adb actually printed
 * rather than a sentence written for it.
 *
 * Three states, because "no phone on ADB" was three facts wearing one
 * message:
 *
 *   absent    - adb is not installed at all, which the old panel assumed
 *               away. Nothing on this page can work and no amount of
 *               fiddling with the phone changes it.
 *   broken    - adb is installed and cannot start. The dynamic loader's
 *               own missing library is what is drawn, because "is the app
 *               open on your phone" is the message that class of failure
 *               used to get (see PhoneDeps.parseLoaderFailure).
 *   noDevice  - adb works and lists nothing, which is the state the
 *               pairing form is for.
 *   ""        - nothing to complain about. `formAlwaysShown` is what makes
 *               that a state with a UI: the link page is about this job, not
 *               about being a consequence, and the second phone and the
 *               re-rolled port are both walked in here.
 *
 * What it still asks the user to read off the phone: the six-digit
 * pairing code, always - it is generated per pairing and advertised
 * nowhere - and both ports whenever avahi cannot see them. The host is
 * prefilled from the address KDE Connect already reaches the phone on, and
 * the connect port from the last address that answered, which is the only
 * port record there is between one re-roll and the next; the ports are
 * prefilled from `_adb-tls-pairing._tcp` / `_adb-tls-connect._tcp` when the
 * phone is advertising them and avahi is installed. Nothing here promises
 * more than that: with no avahi the discovery row is simply not drawn.
 */
ColumnLayout {
    id: root

    // "" while there is nothing to say. Read as a tri-state through
    // PhoneDeps.ready: every flag in that singleton starts false, so a plain
    // falsy test would draw this panel for the first frames of every session
    // (b591575c4's rule, one surface along).
    readonly property string mode: {
        if (!PhoneDeps.ready)
            return "";
        if (!PhoneDeps.adbPresent)
            return "absent";
        if (PhoneDeps.adbRunError.length > 0)
            return "broken";
        if (!PhoneDeps.adbDevice)
            return "noDevice";
        return "";
    }

    // The link page hosts this form on purpose, and a device already answering
    // is no reason to take the pair and connect fields away from it: that is
    // the state a second phone, or a phone whose port just re-rolled, is
    // walked into. The Apps page shows the panel as a REFUSAL and leaves this
    // at its default, where every binding below is what it always was.
    property bool formAlwaysShown: false

    readonly property bool shown: root.formAlwaysShown || root.mode.length > 0

    // The install command for this machine, so the absent state carries the
    // one thing that fixes it. `PhoneDeps.dependency` is the same table the
    // install guide draws, and `initialDistro` is the same fallback.
    readonly property var adbDependency: PhoneDeps.dependency("android-tools")
    readonly property string adbInstallCommand:
        PhoneCards.firstCommand(PhoneCards.commandFor(root.adbDependency,
                                                      PhoneCards.initialDistro(PhoneDeps.distro)))

    // The host half of both addresses, which is the part the shell honestly
    // knows: KDE Connect reports where it reaches the phone, and that is the
    // same LAN address wireless debugging listens on. The PORTS are not
    // knowable from it - Android re-rolls both every time the switch is
    // flipped - so a suggestion with no port is offered as a head start
    // rather than as an address, and the Pair button stays refused until the
    // port is there.
    readonly property string knownHost: PhoneDeps.preferredWirelessHost()

    // The other half of an address, from the last time this phone answered.
    // The host above is current and the port here is not, and neither alone
    // is an address the Connect button accepts, which is what
    // `reconnectAddress` is for.
    readonly property string lastWirelessAddress:
        Persistent.states.phone.adb.lastWirelessAddress

    // What was last put into each field on the shell's behalf. A suggestion
    // is an ASSIGNMENT and never a binding on `text`: a binding would be
    // destroyed by the first keystroke (#158's shape), and comparing against
    // what was last suggested is what stops a discovery landing after the
    // user has typed from taking their typing away.
    property string pairSuggested: ""
    property string connectSuggested: ""

    function offerPairAddress(next: string): void {
        if (next.length === 0)
            return;
        if (pairAddressField.text.length > 0 && pairAddressField.text !== root.pairSuggested)
            return;
        pairAddressField.text = next;
        root.pairSuggested = next;
    }

    function offerConnectAddress(next: string): void {
        if (next.length === 0)
            return;
        if (connectAddressField.text.length > 0 && connectAddressField.text !== root.connectSuggested)
            return;
        connectAddressField.text = next;
        root.connectSuggested = next;
    }

    function offerEverythingKnown(): void {
        // The PAIRING address is not offered the remembered one: pairing
        // listens on its own port, advertised only while the phone's pairing
        // screen is open, and it is never the port `connect` answered on last
        // time. The connect field is the one with a history worth reusing.
        root.offerPairAddress(PhoneDeps.mdnsPairingAddress.length > 0
                              ? PhoneDeps.mdnsPairingAddress : root.knownHost);
        root.offerConnectAddress(PhoneDeps.mdnsConnectAddress.length > 0
                                 ? PhoneDeps.mdnsConnectAddress
                                 : PhoneCards.reconnectAddress(root.knownHost,
                                                               root.lastWirelessAddress));
    }

    Component.onCompleted: root.offerEverythingKnown()
    onKnownHostChanged: root.offerEverythingKnown()
    // A connect that lands while this panel is open has taught the shell a
    // port it did not have at construction, and the same rule as the
    // discovery's answer applies: reach the field, unless the field is
    // carrying something the user typed.
    onLastWirelessAddressChanged: root.offerEverythingKnown()

    // An observation of the discovery results and of a connect landing, rather
    // than a poll or a binding on `text`: an answer that arrives while the
    // panel is open has to reach the fields, and one that arrives with nothing
    // must leave them exactly as they were.
    Connections {
        target: PhoneDeps

        function onMdnsPairingAddressChanged(): void {
            root.offerPairAddress(PhoneDeps.mdnsPairingAddress);
        }

        function onMdnsConnectAddressChanged(): void {
            root.offerConnectAddress(PhoneDeps.mdnsConnectAddress);
        }

        // The one thing worth remembering from a connect is the address that
        // ANSWERED, and only that: a failure is evidence about a port Android
        // has already thrown away. `wirelessAttemptAddress` rather than the
        // field, because the field is editable while adb is running.
        function onConnectStateChanged(): void {
            if (PhoneDeps.connectState === "ok")
                Persistent.states.phone.adb.lastWirelessAddress = PhoneDeps.wirelessAttemptAddress;
        }
    }

    Layout.fillWidth: true
    // A layout nested in a layout fills by default, which would take the
    // page's whole leftover and leave the app list nothing.
    Layout.fillHeight: false
    spacing: Appearance.spacing.space100

    // ---- what is wrong, and the route that needs no shell at all ----------
    NoticeBox {
        id: diagnosis

        // Nothing to complain about is nothing to show. The Apps page never
        // let this box answer for a healthy link because it set `visible` on
        // the PANEL, and a panel that is asked to stay open has to decide that
        // for each of its own parts.
        visible: root.mode.length > 0
        Layout.fillWidth: true
        colBg: Appearance.colors.colErrorContainer
        colFg: Appearance.colors.colOnErrorContainer
        materialIcon: root.mode === "broken" ? "warning" : "usb_off"
        text: {
            if (root.mode === "absent")
                return Translation.tr("App Mode starts each app over ADB, and adb is not installed on this machine.");
            if (root.mode === "broken")
                return Translation.tr("adb is installed and cannot start: the dynamic loader cannot find %1. The package was built against an older library than this system ships, so it needs rebuilding or reinstalling.").arg(PhoneDeps.adbRunError);
            return Translation.tr("App Mode starts each app over ADB, and no phone is on ADB. Pairing in KDE Connect does not do it: that link carries notifications and files, not debugging.");
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Appearance.spacing.space75

            StyledText {
                id: installCommandLabel
                Layout.fillWidth: true
                visible: (root.mode === "absent" || root.mode === "broken")
                    && root.adbInstallCommand.length > 0
                // A package manager command is not markup, and it is not this
                // repo's string either - it comes out of the dependency table.
                textFormat: Text.PlainText
                text: root.adbInstallCommand
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnErrorContainer
                wrapMode: Text.WrapAnywhere
            }

            StyledText {
                id: usbRouteTitle
                Layout.fillWidth: true
                visible: root.mode === "noDevice"
                text: Translation.tr("Over a USB cable")
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnErrorContainer
                wrapMode: Text.WordWrap
            }

            StyledText {
                id: usbRouteBody
                Layout.fillWidth: true
                visible: root.mode === "noDevice"
                text: Translation.tr("Settings → System → Developer options → USB debugging. Plug the cable in and accept the fingerprint the phone asks about.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnErrorContainer
                wrapMode: Text.WordWrap
            }
        }
    }

    // ---- ...and the route that is a job the shell can do ------------------
    ContentSubsection {
        id: wirelessSection

        // The form is a job the shell can do, so adb has to be installed AND
        // startable for it to be worth drawing, which is what `noDevice` and
        // the healthy `""` both mean. `formAlwaysShown` widens the refusal to
        // the healthy link - a second phone, or a port that just re-rolled -
        // and deliberately not to `absent` or `broken`: offering to pair from a
        // machine whose adb cannot start is the thing this panel exists to stop
        // doing.
        visible: root.mode === "noDevice" || (root.formAlwaysShown && root.mode === "")
        title: Translation.tr("Pair over Wi-Fi")

        StyledText {
            id: wirelessIntro
            Layout.fillWidth: true
            text: Translation.tr("On the phone: Developer options → Wireless debugging → Pair device with pairing code. That screen shows an address and a six-digit code; the main Wireless debugging screen shows a different port for the second step. Android picks new ports every time the switch is turned off and on.")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }

        Rectangle {
            id: formCard

            Layout.fillWidth: true
            Layout.topMargin: Appearance.spacing.space50
            implicitHeight: formColumn.implicitHeight + Appearance.spacing.space150 * 2
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2

            ColumnLayout {
                id: formColumn
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: Appearance.spacing.space150
                }
                spacing: Appearance.spacing.space75

                // ---- step one: pair ---------------------------------------
                StyledText {
                    id: pairStepLabel
                    Layout.fillWidth: true
                    text: Translation.tr("1 · Pairing address and code")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    // ToolbarTextField declares Layout.fillHeight of its own,
                    // which makes a row holding one unbounded and lets it eat
                    // the column (f29079c51).
                    Layout.fillHeight: false
                    spacing: Appearance.spacing.space75

                    ToolbarTextField {
                        id: pairAddressField
                        Layout.fillWidth: true
                        enabled: PhoneDeps.pairState !== "busy"
                        placeholderText: Translation.tr("192.168.1.42:37129")
                    }

                    ToolbarTextField {
                        id: pairCodeField
                        Layout.fillWidth: false
                        Layout.preferredWidth: Appearance.font.pixelSize.huge * 5
                        enabled: PhoneDeps.pairState !== "busy"
                        maximumLength: 6
                        inputMethodHints: Qt.ImhDigitsOnly
                        placeholderText: Translation.tr("123456")
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Appearance.spacing.space75

                    RippleButtonWithIcon {
                        id: pairButton
                        enabled: PhoneDeps.pairState !== "busy"
                            && PhoneDeps.pairInputsReady(pairAddressField.text, pairCodeField.text)
                        materialIcon: "link"
                        materialIconFill: false
                        colBackground: Appearance.colors.colLayer3
                        colBackgroundHover: Appearance.colors.colLayer3Hover
                        colRipple: Appearance.colors.colLayer3Active
                        mainText: PhoneDeps.pairState === "busy"
                            ? Translation.tr("Pairing…") : Translation.tr("Pair")
                        onClicked: PhoneDeps.pairWireless(pairAddressField.text, pairCodeField.text)
                    }

                    RippleButtonWithIcon {
                        id: discoverButton
                        // An absent avahi-browse is an ordinary absence: the
                        // row is simply not there, and both addresses are
                        // typed. Promising a lookup the machine cannot do is
                        // the thing this panel exists to stop doing.
                        visible: PhoneDeps.avahiBrowse
                        enabled: PhoneDeps.mdnsState !== "searching"
                        materialIcon: "wifi_find"
                        materialIconFill: false
                        colBackground: Appearance.colors.colLayer3
                        colBackgroundHover: Appearance.colors.colLayer3Hover
                        colRipple: Appearance.colors.colLayer3Active
                        mainText: PhoneDeps.mdnsState === "searching"
                            ? Translation.tr("Looking…") : Translation.tr("Find the ports")
                        onClicked: PhoneDeps.discoverWirelessPorts()

                        StyledToolTip {
                            text: Translation.tr("Ask the network which ports the phone is advertising")
                        }
                    }

                    Item { Layout.fillWidth: true }
                }

                StatusLine {
                    id: discoveryStatus
                    shownWhen: PhoneDeps.avahiBrowse && PhoneDeps.mdnsState !== "idle"
                    glyph: PhoneDeps.mdnsState === "searching" ? "search"
                        : (PhoneDeps.mdnsPairingAddress.length > 0
                           || PhoneDeps.mdnsConnectAddress.length > 0) ? "check_circle" : "info"
                    message: {
                        if (PhoneDeps.mdnsState === "searching")
                            return Translation.tr("Asking the network…");
                        if (PhoneDeps.mdnsPairingAddress.length === 0
                            && PhoneDeps.mdnsConnectAddress.length === 0)
                            return Translation.tr("Nothing is advertising wireless debugging. The pairing screen only advertises while it is open, so leave it on the phone and try again.");
                        if (PhoneDeps.mdnsPairingAddress.length === 0)
                            return Translation.tr("Found the connect port. The pairing one is only advertised while the pairing screen is open on the phone.");
                        return Translation.tr("Found both ports.");
                    }
                }

                StatusLine {
                    id: pairStatus
                    shownWhen: PhoneDeps.pairState === "ok" || PhoneDeps.pairState === "failed"
                    glyph: PhoneDeps.pairState === "ok" ? "check_circle" : "error"
                    // What adb printed, never a sentence written here: the
                    // whole point of running the command instead of quoting
                    // it is that its answer is the one the user gets.
                    message: PhoneDeps.pairMessage
                }

                // ---- step two: connect ------------------------------------
                StyledText {
                    id: connectStepLabel
                    Layout.fillWidth: true
                    Layout.topMargin: Appearance.spacing.space50
                    text: Translation.tr("2 · Connect address, from the Wireless debugging screen")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Appearance.spacing.space75

                    ToolbarTextField {
                        id: connectAddressField
                        Layout.fillWidth: true
                        enabled: PhoneDeps.connectState !== "busy"
                        placeholderText: Translation.tr("192.168.1.42:41235")
                    }

                    RippleButtonWithIcon {
                        id: connectButton
                        enabled: PhoneDeps.connectState !== "busy"
                            && PhoneDeps.connectInputReady(connectAddressField.text)
                        materialIcon: "power"
                        materialIconFill: false
                        colBackground: Appearance.colors.colLayer3
                        colBackgroundHover: Appearance.colors.colLayer3Hover
                        colRipple: Appearance.colors.colLayer3Active
                        mainText: PhoneDeps.connectState === "busy"
                            ? Translation.tr("Connecting…") : Translation.tr("Connect")
                        onClicked: PhoneDeps.connectWireless(connectAddressField.text)
                    }
                }

                StatusLine {
                    id: connectStatus
                    shownWhen: PhoneDeps.connectState === "ok" || PhoneDeps.connectState === "failed"
                    glyph: PhoneDeps.connectState === "ok" ? "check_circle" : "error"
                    message: PhoneDeps.connectMessage
                }

                StyledText {
                    id: closingNote
                    Layout.fillWidth: true
                    // A promise about this block going away, which is what the
                    // Apps page does with it and is not what the link page
                    // does: there the form is the point and it stays whether or
                    // not a device answers.
                    visible: !root.formAlwaysShown
                    text: Translation.tr("The tab keeps asking while it is open. As soon as a device answers, this goes and the app list is fetched on its own.")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    // One line of feedback: a glyph and whatever the step has to say. A
    // component rather than four copies, because the four differ only in
    // which property they read and a fourth hand-written copy is how three
    // come to disagree about their own spacing.
    component StatusLine: RowLayout {
        id: statusLine

        property bool shownWhen: false
        property string glyph: "info"
        property string message: ""

        Layout.fillWidth: true
        Layout.fillHeight: false
        visible: statusLine.shownWhen && statusLine.message.length > 0
        spacing: Appearance.spacing.space50

        MaterialSymbol {
            Layout.alignment: Qt.AlignTop
            text: statusLine.glyph
            iconSize: Appearance.font.pixelSize.normal
            color: statusLine.glyph === "error"
                ? Appearance.colors.colError : Appearance.colors.colSubtext
        }

        StyledText {
            Layout.fillWidth: true
            // adb writes this, so it is never markup.
            textFormat: Text.PlainText
            text: statusLine.message
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: statusLine.glyph === "error"
                ? Appearance.colors.colError : Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }
    }
}
