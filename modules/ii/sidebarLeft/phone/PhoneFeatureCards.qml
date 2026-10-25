pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.phone
import "phone_cards.js" as PhoneCards

/**
 * The Phone tab's bottom card stack: the scrcpy mirror, the phone webcam, the
 * phone microphone, and one pairing card per peer that has asked to pair.
 *
 * This is the ONE place a card's click becomes a service call, which is what
 * makes "a button whose call no service answers is a fake action" checkable:
 * tests/test_phone_tab_surface_contract.py resolves every `PhoneX.member` in
 * this directory against what the services declare. Two of the sibling fork's
 * chips are deliberately absent for that reason - it offers "phone
 * screenshot", "toggle phone power" and "hear yourself", and PhoneScrcpy and
 * PhoneMic answer none of the three.
 *
 * The stack is one Item the tab places last in its column. It reads nothing
 * from the tab and announces what it cannot do itself: `openPage(id)` with
 * "webcam", "mic" or "adb" - the last of the three because a card that knows
 * before the click that its service has no transport should hand over the
 * route rather than wait to be refused.
 *
 * `showPeripheralCards` hides the three FEATURE cards only. A pairing request
 * is a question a peer asked, not a peripheral, and dropping it because the
 * cards are off would leave no way to answer it.
 */
Item {
    id: root

    signal openPage(string id)
    // The guide belongs to the tab, not to this stack: see Phone.qml.
    signal openInstallGuideRequested(string feature, string title)

    implicitHeight: stack.implicitHeight

    readonly property bool showCards: Config.options.phone?.showPeripheralCards ?? true
    readonly property var activeDevice: PhoneConnect.activeDevice
    readonly property bool deviceReachable: PhoneConnect.activeDevice?.reachable === true
    // `undefined` while the probes are still running, never `false`: every
    // PhoneDeps flag starts false, and phone_cards.js reads `false` as a
    // refusal to draw. One derivation, because two cards ask it.
    readonly property var adbDevice: PhoneDeps.ready ? PhoneDeps.adbDevice : undefined
    // The cap this card's preview chip hands the player, for the same reason the
    // webcam page computes one: an over-tall floating window is not clamped by
    // the compositor, and the action below is not a binding, so the window's
    // height has to be read here for the expression to depend on it.
    readonly property real ownWindowHeight: Window.window?.height ?? 0
    readonly property int previewCapHeight: Math.round(root.ownWindowHeight * 0.88)

    // The elapsed clock for whichever cards are running. A Timer rather than
    // DateTime's own: that clock ticks per MINUTE unless the user asked for
    // seconds, and this line counts in them. It runs only while something is
    // active, so an idle tab costs no frames.
    property real nowMs: Date.now()
    readonly property bool anyActive: PhoneScrcpy.mirrorRunning || PhoneCamera.active || PhoneMic.active

    Timer {
        interval: 1000
        repeat: true
        running: root.anyActive && root.visible
        onTriggered: root.nowMs = Date.now()
    }

    onAnyActiveChanged: root.nowMs = Date.now()

    // Whether adb can see the phone is live state, but polling it was not the
    // way to read it: every run dropped `ready`, and the cards' subtitles
    // blinked with it. The re-ask happens once whenever this stack is shown,
    // not on a timer; the Phone link page's "Check again" is the manual path,
    // and a connect already triggers its own refresh.
    onVisibleChanged: if (root.visible && PhoneDeps.adb && !PhoneDeps.adbDevice)
        PhoneDeps.refreshAdbDevices()

    // PhoneScrcpy's session rows carry `startedAt` in milliseconds (Date.now()
    // at the moment the supervisor reported the window), where PhoneCamera and
    // PhoneMic carry whole UNIX seconds off their session script's state file.
    // The two are converted at their own call sites rather than by pretending
    // one of them is the other.
    readonly property real mirrorStartedAtMs: {
        // sessionCount is read to make this a binding: a ListModel is not a
        // property, so nothing here would re-evaluate on an append without it.
        const count = PhoneScrcpy.sessionCount;
        if (count === 0)
            return 0;
        const index = PhoneScrcpy.sessionIndex("mirror");
        return index >= 0 ? Number(PhoneScrcpy.sessions.get(index).startedAt) : 0;
    }

    ColumnLayout {
        id: stack
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        spacing: Appearance.spacing.space100

        // ---- 1. the scrcpy mirror ----
        PhoneFeatureCard {
            id: mirrorCard
            Layout.fillWidth: true
            visible: root.showCards

            readonly property var flags: ({
                available: PhoneScrcpy.available,
                reachable: root.deviceReachable,
                running: PhoneScrcpy.mirrorRunning,
                launching: PhoneScrcpy.mirrorLaunching,
                adbDevice: root.adbDevice,
                // The MIRROR's own failure, not the service-wide lastError:
                // that one is written by any session's exit and by the
                // supervisor's ladder, so a failed app launch used to put its
                // message on this card.
                error: PhoneScrcpy.mirrorError
            })

            iconName: "smart_display"
            iconShape: MaterialShape.Shape.Cookie9Sided
            cardState: PhoneCards.mirrorState(mirrorCard.flags)
            title: {
                switch (PhoneCards.mirrorTitleKey(mirrorCard.flags)) {
                case "install":
                    return Translation.tr("Install scrcpy");
                case "running":
                    return Translation.tr("scrcpy Mirror");
                case "connecting":
                    return Translation.tr("Connecting scrcpy…");
                default:
                    return Translation.tr("Open scrcpy Mirror");
                }
            }
            subtitle: {
                switch (PhoneCards.mirrorSubtitleKey(mirrorCard.flags)) {
                case "install":
                    return Translation.tr("Click to see missing dependencies and install guide");
                case "offline":
                    return Translation.tr("Pair a reachable device to mirror its screen");
                case "noDevice":
                    return Translation.tr("No device over ADB · open Phone link to pair or reconnect");
                case "error":
                    return PhoneCards.errorHeadline(PhoneScrcpy.mirrorError);
                case "running":
                    return Translation.tr("Mirror is running · click to focus its window");
                case "launching":
                    return Translation.tr("Launching scrcpy…");
                default:
                    return Translation.tr("Opens a floating window for the active phone");
                }
            }
            detailLine: PhoneScrcpy.mirrorRunning && root.mirrorStartedAtMs > 0
                ? Translation.tr("Active for %1").arg(PhoneCards.formatElapsed(root.nowMs - root.mirrorStartedAtMs))
                : ""
            // A running mirror's own launch error is over; what is in
            // `lastError` by then belongs to some other session (see
            // phone_cards.js on why the subtitle asks running first).
            lastError: ""
            inlineActions: [
                {
                    icon: "center_focus_strong",
                    label: Translation.tr("Focus the mirror window"),
                    action: () => PhoneScrcpy.focusMirror()
                }
            ]
            // Sharing a file with the phone is KDE Connect's, not scrcpy's -
            // the mirror card is simply where a file dropped on a running
            // phone session naturally lands.
            dropEnabled: root.deviceReachable && PhoneConnect.canShare
            onFilesDropped: urls => PhoneConnect.shareUrls(root.activeDevice, urls)

            onClicked: {
                if (!PhoneScrcpy.available) {
                    root.openInstallGuideRequested("mirror", Translation.tr("scrcpy Mirror — missing dependencies"));
                    return;
                }
                if (PhoneScrcpy.mirrorLaunching)
                    return;
                // scrcpy with nothing on adb is a LINK question, and asking
                // scrcpy turns it into a stack trace: the click flashed the
                // card and left it saying exactly what it said before, which
                // is the whole reason this branch exists. The tri-state flag
                // and not `cardState` - the state folds an adb gap into
                // "offline", and `undefined` (probes still running) must not
                // send a click off to another page. A running mirror is asked
                // first, because its click is a focus, not a launch.
                if (!PhoneScrcpy.mirrorRunning && root.adbDevice === false) {
                    root.openPage("adb");
                    return;
                }
                // launchMirror() focuses an already-running mirror itself, so
                // there is one call here rather than a second copy of that
                // decision.
                PhoneScrcpy.launchMirror();
            }
            onStopClicked: PhoneScrcpy.stopMirror()
        }

        // ---- 2. the phone as a webcam ----
        PhoneFeatureCard {
            id: webcamCard
            Layout.fillWidth: true
            visible: root.showCards

            readonly property var flags: ({
                available: PhoneCamera.available,
                reachable: root.deviceReachable,
                connecting: PhoneCamera.connecting,
                active: PhoneCamera.active,
                device: PhoneCamera.device,
                // The webcam is scrcpy now, and scrcpy has nothing to attach
                // to when `adb devices` is empty — unlike the DroidCam engine
                // it replaced, which reached the phone over Wi-Fi.
                adbDevice: root.adbDevice,
                error: PhoneCamera.lastError
            })

            iconName: "videocam"
            iconShape: MaterialShape.Shape.Cookie7Sided
            hasSettings: true
            cardState: PhoneCamera.state
            title: PhoneCards.webcamTitleKey(PhoneCamera.available) === "install"
                ? Translation.tr("Install scrcpy")
                : Translation.tr("Phone Webcam")
            subtitle: {
                switch (PhoneCards.webcamSubtitleKey(webcamCard.flags)) {
                case "install":
                    return Translation.tr("Click to see missing dependencies and install guide");
                case "offline":
                    return Translation.tr("Pair a reachable device to use its camera");
                case "connecting":
                    return Translation.tr("Connecting to the phone's camera…");
                case "device":
                    return PhoneCamera.device;
                case "running":
                    return Translation.tr("Streaming from the phone's camera");
                case "noDevice":
                    return Translation.tr("No device over ADB · open Phone link to pair or reconnect");
                case "error":
                    return PhoneCards.errorHeadline(PhoneCamera.lastError);
                default:
                    return Translation.tr("Tap to start · settings to configure");
                }
            }
            detailLine: {
                if (!PhoneCamera.active)
                    return "";
                const elapsed = PhoneCards.formatElapsed(PhoneCards.elapsedMs(PhoneCamera.startedAt, root.nowMs));
                return Translation.tr("Active for %1 · %2")
                    .arg(elapsed).arg(PhoneCamera.device || "—");
            }
            lastError: PhoneCamera.lastError
            inlineActions: [
                // Only while there is something to preview. The webcam page
                // gates its button the same way; a chip that is drawn on an
                // idle card can only ever fail, and used to fail with a
                // complaint about mpv.
                ...((PhoneCamera.previewRunning
                        || (PhoneCamera.active && PhoneCamera.device.length > 0))
                    ? [{
                        icon: PhoneCamera.previewRunning ? "visibility_off" : "preview",
                        label: PhoneCamera.previewRunning
                            ? Translation.tr("Close the preview window")
                            : Translation.tr("Open a preview window"),
                        action: () => PhoneCamera.previewRunning
                            ? PhoneCamera.closePreview()
                            : PhoneCamera.openPreview(root.previewCapHeight)
                    }] : []),
                {
                    icon: "cameraswitch",
                    label: Translation.tr("Switch the camera the app uses"),
                    action: () => PhoneCamera.flip()
                }
            ]

            onClicked: {
                if (!PhoneCamera.available) {
                    root.openInstallGuideRequested("webcam", Translation.tr("Phone Webcam — missing dependencies"));
                    return;
                }
                // scrcpy is the only thing that writes this card's video node,
                // so with nothing on adb there is no stream to start and the
                // link page is the answer. Stopping a running stream is still
                // what the click does.
                if (!PhoneCamera.active && root.adbDevice === false) {
                    root.openPage("adb");
                    return;
                }
                PhoneCamera.toggle();
            }
            onSettingsClicked: root.openPage("webcam")
            onStopClicked: PhoneCamera.stop()
        }

        // ---- 3. the phone as a microphone ----
        PhoneFeatureCard {
            id: micCard
            Layout.fillWidth: true
            visible: root.showCards

            readonly property var flags: ({
                available: PhoneMic.available,
                reachable: root.deviceReachable,
                connecting: PhoneMic.connecting,
                active: PhoneMic.active,
                muted: PhoneMic.muted,
                // scrcpy drives the phone over ADB; droidcam-cli reaches it
                // over Wi-Fi, so only the preferred backend decides whether
                // an empty `adb devices` is a refusal.
                needsAdbDevice: PhoneMic.preferredBackend === "scrcpy",
                adbDevice: root.adbDevice,
                error: PhoneMic.lastError
            })

            iconName: "mic"
            iconShape: MaterialShape.Shape.Sunny
            hasSettings: true
            cardState: PhoneCards.micState(micCard.flags)
            title: PhoneCards.micTitleKey(PhoneMic.available) === "install"
                ? Translation.tr("Install scrcpy or DroidCam")
                : Translation.tr("Phone Microphone")
            subtitle: {
                switch (PhoneCards.micSubtitleKey(micCard.flags)) {
                case "install":
                    return Translation.tr("Click to see missing dependencies and install guide");
                case "offline":
                    return Translation.tr("Pair a reachable device to use its microphone");
                case "connecting":
                    return Translation.tr("Setting up audio routing…");
                case "muted":
                    return Translation.tr("Muted · click to unmute");
                case "active":
                    return Translation.tr("Active · click to mute");
                case "noDevice":
                    return Translation.tr("No device over ADB · open Phone link to pair or reconnect");
                case "error":
                    return PhoneCards.errorHeadline(PhoneMic.lastError);
                default:
                    return Translation.tr("Tap to start · uses scrcpy or DroidCam");
                }
            }
            detailLine: {
                if (!PhoneMic.active)
                    return "";
                const elapsed = PhoneCards.formatElapsed(PhoneCards.elapsedMs(PhoneMic.startedAt, root.nowMs));
                const suffix = PhoneMic.isDefaultInput ? Translation.tr("default input") : PhoneMic.backend;
                return Translation.tr("Active for %1 · %2% · %3")
                    .arg(elapsed).arg(PhoneMic.gain).arg(suffix);
            }
            lastError: PhoneMic.lastError
            inlineActions: [
                {
                    icon: PhoneMic.muted ? "mic_off" : "mic",
                    label: PhoneMic.muted ? Translation.tr("Unmute") : Translation.tr("Mute"),
                    action: () => PhoneMic.toggleMute()
                },
                {
                    icon: "tune",
                    // The gain cycle is the sibling fork's: 100 -> 150 -> 200
                    // -> 50 -> 100, so one chip reaches every useful level
                    // without a slider on a 68px card.
                    label: Translation.tr("Gain: %1%").arg(PhoneMic.gain),
                    action: () => {
                        const gain = PhoneMic.gain;
                        PhoneMic.setGain(gain < 100 ? 100 : gain < 150 ? 150 : gain < 200 ? 200 : 50);
                    }
                },
                {
                    icon: PhoneMic.isDefaultInput ? "star" : "star_border",
                    label: PhoneMic.isDefaultInput
                        ? Translation.tr("Restore the previous default input")
                        : Translation.tr("Set as the default input"),
                    action: () => {
                        if (PhoneMic.isDefaultInput)
                            PhoneMic.restoreDefaultInput();
                        else
                            PhoneMic.setAsDefaultInput();
                    }
                }
            ]

            onClicked: {
                if (!PhoneMic.available) {
                    root.openInstallGuideRequested("microphone", Translation.tr("Phone Microphone — missing dependencies"));
                    return;
                }
                // A running microphone's primary click mutes rather than
                // stops: muting is the thing wanted in a hurry, and the Stop
                // button is right there for the other one.
                if (PhoneMic.active) {
                    PhoneMic.toggleMute();
                    return;
                }
                // Only the scrcpy backend drives the phone over adb. The
                // DroidCam CLI reaches it over Wi-Fi and needs nothing from
                // this page, so the refusal is asked for rather than assumed
                // - which is the same distinction phone_cards.js's `micState`
                // draws, and the reason the check is not on `cardState`.
                if (PhoneMic.preferredBackend === "scrcpy" && root.adbDevice === false) {
                    root.openPage("adb");
                    return;
                }
                PhoneMic.toggle();
            }
            onSettingsClicked: root.openPage("mic")
            onStopClicked: PhoneMic.stop()
        }

        // No pairing cards here, though the spec groups them into this stack:
        // Phone.qml draws them itself, because answering a request is the only
        // way an unpaired phone gets into the shell and this file is loaded by
        // URL - a stack that failed to load would take pairing with it. The
        // type also moved to qs.modules.imi.phone as PhonePairingCard; the
        // name that used to be here was the dialog's.
    }
}
