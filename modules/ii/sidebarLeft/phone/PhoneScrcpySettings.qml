pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The scrcpy launch flags, shared by the mirror's settings page and App
 * Mode's.
 *
 * The two features keep SEPARATE config tables - `phone.scrcpy` and its
 * `appMode` child - so a value typed on one page never reaches the other.
 * This body owns the rows and reads whichever table its page hands it;
 * every write is raised as a signal rather than touching the config, and
 * the page decides what follows from it (the mirror restarts, App Mode
 * waits for the next launch).
 *
 * The page reads two facts from the phone through the supervisor: its real
 * display size, which the mirror's resolution row defaults to (App Mode's
 * defaults to its own virtual display), and its video encoders, which the
 * encoder row offers. Both are asked when the page opens; they are cached
 * by the service for the life of the device.
 */
PhoneSubPage {
    id: root

    // The table this page edits. Both are JsonObjects whose properties
    // notify, so the rows follow a config write without a second copy.
    property var scrcpyConfig: null
    // What the resolution row shows while the stored value is empty: the
    // phone's screen for a mirror, the virtual display's for App Mode.
    // Empty until the fact is known.
    property string nativeResolution: PhoneScrcpy.deviceScreenSize

    property string introText: ""
    property string noAdbText: ""
    property string resolutionDescription: ""
    property string videoInfoText: Translation.tr("scrcpy's picture of the phone's screen. Turning it off launches with --no-video: the session keeps running, but the phone's screen is not forwarded.")
    property string dependencyFeature: "mirror"
    property string installGuideTitle: Translation.tr("scrcpy — missing dependencies")

    // Auto needs a display whose turn the supervisor can watch: App Mode's
    // virtual display, or the phone's own screen for the mirror. Only App
    // Mode without a virtual display lacks one.
    property bool followOrientationAvailable: false
    // Whose turn the hint describes: the mirror follows the phone's screen,
    // App Mode follows its app's virtual display.
    property bool followPhoneOrientation: false

    // The service owns the write and whatever follows from it, so the page
    // never touches the config itself.
    signal settingChanged(string key, var value)
    // Not `codecChanged`: that is the change signal of the `codec` property
    // above, and QML refuses a second signal with the same name.
    signal codecSelected(string codec)

    readonly property string codec: String(root.scrcpyConfig?.videoCodec ?? "h264")

    // A stored -1 is Auto only where Auto exists; a page that does not offer
    // it reads a carried-over value as 0°.
    readonly property int orientationValue: {
        const value = Number(root.scrcpyConfig?.captureOrientation ?? 0);
        return (!root.followOrientationAvailable && value < 0) ? 0 : value;
    }

    readonly property string missingDependencies: PhoneDeps.missingFor(root.dependencyFeature)
        .map(dependency => dependency.name).join(", ")

    // "Auto" plus the encoders the phone reported for the selected codec.
    // The supervisor drops MediaCodec aliases, so each entry is a real
    // encoder rather than a second name for one already listed.
    readonly property var encoderOptions: {
        const options = [{ displayName: Translation.tr("Auto"), value: "" }];
        for (const entry of PhoneScrcpy.encoders ?? []) {
            if (String(entry.codec) !== root.codec) continue;
            options.push({
                displayName: String(entry.label ?? entry.name ?? ""),
                value: String(entry.name ?? "")
            });
        }
        return options;
    }

    readonly property string encoderHint: {
        if (!PhoneScrcpy.available) return "";
        if (PhoneScrcpy.encodersLoading) return Translation.tr("Reading the phone's encoders…");
        if (PhoneScrcpy.encodersError.length > 0) return PhoneScrcpy.encodersError;
        if (root.encoderOptions.length <= 1)
            return Translation.tr("The phone has not reported an encoder for this codec. Auto is used.");
        return Translation.tr("The phone's own MediaCodec encoder for this codec. Auto lets scrcpy choose.");
    }

    // Native is the absence of the flag: storing today's exact size would
    // pin the session to one phone's (or one display's) shape. The field
    // still shows the real size, which is what "default" means here.
    function resolutionText(): string {
        const stored = String(root.scrcpyConfig?.resolution ?? "").trim();
        return stored.length > 0 ? stored : root.nativeResolution;
    }

    function commitResolution(): void {
        resolutionCommit.stop();
        const parsed = PhoneScrcpy.parseResolution(resolutionField.value);
        if (!parsed.ok) {
            resolutionField.value = root.resolutionText();
            return;
        }
        const detected = root.nativeResolution;
        const value = parsed.text.length > 0 && parsed.text !== detected ? parsed.text : "";
        const display = value.length > 0 ? value : (detected.length > 0 ? detected : parsed.text);
        if (resolutionField.value !== display)
            resolutionField.value = display;
        root.settingChanged("resolution", value);
    }

    onVisibleChanged: if (root.visible) PhoneScrcpy.ensureDeviceFacts()
    Component.onCompleted: {
        resolutionField.value = root.resolutionText();
        if (root.visible) PhoneScrcpy.ensureDeviceFacts();
    }

    // A page opened before the startup probes have answered would otherwise
    // never ask: ensureDeviceFacts() no-ops while unavailable.
    Connections {
        target: PhoneScrcpy

        function onAvailableChanged(): void {
            if (root.visible && PhoneScrcpy.available) PhoneScrcpy.ensureDeviceFacts();
        }

        function onDeviceScreenSizeChanged(): void {
            // The service clears the size when the device changes; ask the
            // new phone rather than keeping the old one's answer.
            if (PhoneScrcpy.deviceScreenSize.length === 0 && root.visible)
                PhoneScrcpy.ensureDeviceFacts();
        }

        function onEncodersChanged(): void {
            // An empty list is a failed or still-absent query, not evidence
            // that the saved encoder is gone; only a real answer may clear it.
            if (PhoneScrcpy.encoders.length === 0) return;
            const encoder = String(root.scrcpyConfig?.videoEncoder ?? "").trim();
            if (encoder.length === 0) return;
            if (!PhoneScrcpy.encoderForCodec(root.codec, encoder))
                root.settingChanged("videoEncoder", "");
        }
    }

    // The default can arrive late (device facts) or change (a different
    // phone, another virtual display). Follow it only while the stored
    // value is empty and nobody is typing.
    onNativeResolutionChanged: {
        const stored = String(root.scrcpyConfig?.resolution ?? "").trim();
        if (root.nativeResolution.length === 0) {
            if (!resolutionField.textArea.activeFocus && stored.length === 0)
                resolutionField.value = "";
            return;
        }
        if (stored.length > 0) return;
        if (!resolutionField.textArea.activeFocus)
            resolutionField.value = root.nativeResolution;
    }

    // Typing a valid size should not require Enter; losing focus and the
    // confirm button commit immediately, and the timer covers a page popped
    // while the field had focus.
    Timer {
        id: resolutionCommit
        interval: 900
        onTriggered: root.commitResolution()
    }

    // Clicking straight to another row should keep a typed size rather than
    // discard it; Enter and the check button are the explicit routes.
    Connections {
        target: resolutionField.textArea
        function onActiveFocusChanged(): void {
            if (!resolutionField.textArea.activeFocus) root.commitResolution();
        }
    }

    ContentPage {
        id: page

        Layout.fillWidth: true
        Layout.fillHeight: true
        // ContentPage centres at `max(baseWidth, implicitWidth)` and its
        // default base is the settings window's 600; this panel is narrower,
        // so the column has to take the width it is really given.
        forceWidth: true
        baseWidth: Math.max(0, page.width - Appearance.spacing.space200)
        bottomContentPadding: Appearance.spacing.space400

        NoticeBox {
            Layout.fillWidth: true
            Layout.maximumWidth: page.baseWidth
            visible: !PhoneScrcpy.available
            materialIcon: "download"
            text: Translation.tr("scrcpy is not set up on this machine. %1 is missing.")
                .arg(root.missingDependencies)

            DialogButton {
                Layout.alignment: Qt.AlignRight
                buttonText: Translation.tr("How to install")
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                colText: Appearance.colors.colOnPrimary
                onClicked: root.openInstallGuideRequested(root.dependencyFeature,
                    root.installGuideTitle)
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            Layout.maximumWidth: page.baseWidth
            visible: PhoneScrcpy.available && PhoneDeps.ready && !PhoneDeps.adbDevice
            materialIcon: "phonelink_off"
            text: root.noAdbText

            DialogButton {
                Layout.alignment: Qt.AlignRight
                buttonText: Translation.tr("Fix the phone link (ADB)")
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                colText: Appearance.colors.colOnPrimary
                onClicked: root.openAdbPageRequested()
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.maximumWidth: page.baseWidth
            text: root.introText
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            wrapMode: Text.Wrap
        }

        ContentSection {
            icon: "smart_display"
            shape: MaterialShape.Shape.Cookie9Sided
            title: Translation.tr("Video")

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "videocam"
                    text: Translation.tr("Video forwarding")
                    infoText: root.videoInfoText
                    checked: root.scrcpyConfig?.videoEnabled ?? true
                    selfToggle: false
                    onToggleRequested: root.settingChanged(
                        "videoEnabled", !(root.scrcpyConfig?.videoEnabled ?? true))
                }

                ConfigSpinBox {
                    icon: "speed"
                    text: Translation.tr("Frame rate")
                    infoText: Translation.tr("The most frames per second scrcpy captures. 0 leaves it unlimited.")
                    value: Number(root.scrcpyConfig?.maxFps ?? 60)
                    from: 0
                    to: 240
                    stepSize: 1
                    onValueChanged: {
                        if (value === Number(root.scrcpyConfig?.maxFps ?? 60)) return;
                        root.settingChanged("maxFps", value);
                    }
                }

                ConfigSpinBox {
                    icon: "timer"
                    text: Translation.tr("Video buffer (ms)")
                    infoText: Translation.tr("How much video scrcpy buffers before playing it. A larger buffer trades latency for smoothness; 0 disables it.")
                    value: Number(root.scrcpyConfig?.videoBuffer ?? 0)
                    from: 0
                    to: 5000
                    stepSize: 10
                    onValueChanged: {
                        if (value === Number(root.scrcpyConfig?.videoBuffer ?? 0)) return;
                        root.settingChanged("videoBuffer", value);
                    }
                }

                ConfigSpinBox {
                    icon: "network_check"
                    text: Translation.tr("Video bit rate (Mbps)")
                    infoText: Translation.tr("scrcpy's own default is 8 Mbps. Higher keeps fast motion cleaner and needs more of the link; lower saves it.")
                    value: PhoneScrcpy.bitRateMbps(root.scrcpyConfig?.bitRate ?? "8M")
                    from: 1
                    to: 200
                    stepSize: 1
                    onValueChanged: {
                        if (value === PhoneScrcpy.bitRateMbps(root.scrcpyConfig?.bitRate ?? "8M")) return;
                        root.settingChanged("bitRate", value + "M");
                    }
                }

                ConfigTextArea {
                    id: resolutionField
                    text: Translation.tr("Resolution")
                    description: root.resolutionDescription
                    buttonIcon: "aspect_ratio"
                    fieldWidth: 160
                    placeholderText: root.nativeResolution
                    confirmButtonVisible: true
                    onConfirmClicked: root.commitResolution()
                    onValueChanged: resolutionCommit.restart()
                }
            }
        }

        ContentSection {
            icon: "video_settings"
            shape: MaterialShape.Shape.Clover4Leaf
            title: Translation.tr("Codec")

            GroupedList {
                ConfigComboBox {
                    text: Translation.tr("Video codec")
                    buttonIcon: "memory"
                    description: Translation.tr("The video codec scrcpy asks the phone for. H.264 is scrcpy's default and the safest choice.")
                    model: [
                        { displayName: "H.264", value: "h264" },
                        { displayName: "H.265", value: "h265" },
                        { displayName: "AV1", value: "av1" },
                        { displayName: "VP8", value: "vp8" },
                        { displayName: "VP9", value: "vp9" }
                    ]
                    currentValue: root.codec
                    onSelected: value => root.codecSelected(value)
                }

                ConfigComboBox {
                    text: Translation.tr("Encoder")
                    buttonIcon: "developer_board"
                    description: root.encoderHint
                    model: root.encoderOptions
                    currentValue: String(root.scrcpyConfig?.videoEncoder ?? "")
                    onSelected: value => root.settingChanged("videoEncoder", value)
                }
            }
        }

        ContentSection {
            icon: "screen_rotation"
            shape: MaterialShape.Shape.Pill
            title: Translation.tr("Orientation")

            GroupedList {
                PhoneConfigSelectionArray {
                    text: Translation.tr("Rotation")
                    icon: "screen_rotation"
                    infoText: root.followOrientationAvailable
                        ? (root.followPhoneOrientation
                            ? Translation.tr("Auto turns the scrcpy window between portrait and landscape to match the phone's screen. A fixed value rotates the picture and holds the window still.")
                            : Translation.tr("Auto turns the scrcpy window between portrait and landscape to match the app; Resolution sets its starting shape. A fixed value rotates the picture and holds the window still."))
                        : Translation.tr("Clockwise rotation scrcpy applies to the picture. 0° mirrors the phone as it stands.")
                    currentValue: root.orientationValue
                    onSelected: value => root.settingChanged("captureOrientation", Number(value))
                    options: {
                        const fixed = [
                            { displayName: "0°", value: 0, icon: "screen_rotation" },
                            { displayName: "90°", value: 90, icon: "screen_rotation" },
                            { displayName: "180°", value: 180, icon: "screen_rotation" },
                            { displayName: "270°", value: 270, icon: "screen_rotation" }
                        ];
                        return root.followOrientationAvailable
                            ? [{ displayName: Translation.tr("Auto"), value: -1, icon: "autorenew" }].concat(fixed)
                            : fixed;
                    }
                }
            }
        }
    }
}
