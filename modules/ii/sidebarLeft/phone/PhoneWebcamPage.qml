pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "phone_cards.js" as PhoneCards

/**
 * The Phone tab's Phone Webcam sub-page: the scrcpy camera stream's toggle and
 * its settings.
 *
 * Rooted on `PhoneSubPage` (W5a's; the interface is pinned by the stub at
 * tests/imports/qs/modules/imi/sidebarLeft/phone/PhoneSubPage.qml), with a
 * `ContentPage` inside it so the sections scroll and read as the rest of the
 * shell's settings do.
 *
 * Every row here writes a key `Config.qml` already declares under
 * `phone.webcam`, read with optional chaining. The connection rows the
 * DroidCam engine needed - over which transport, which address, which port -
 * are gone: scrcpy writes the phone's camera through adb, so there is no
 * address or port to choose and the transport is whatever adb already has.
 * What a row here sets is a scrcpy flag, so nothing writes the config
 * directly: every row calls `PhoneCamera.applySetting`, which restarts the
 * stream for a value that changed and does nothing for the one already
 * active.
 */
PhoneSubPage {
    id: root

    title: Translation.tr("Phone Webcam")

    readonly property var webcamConfig: Config.options.phone?.webcam
    readonly property bool deviceReachable: PhoneConnect.activeDevice?.reachable === true
    readonly property bool canStart: PhoneCamera.available && root.deviceReachable
    // The tallest preview window this panel can honestly promise. mpv's window is
    // floating and Hyprland does NOT clamp it - measured, a 720x1280 window came
    // up 720x1280 on a 1080-tall monitor, its bottom off-screen - so a Portrait
    // 16:9 stream has to be told what fits on this side of the desktop. The
    // window the page is drawn in is that bound; 0.88 leaves room for its title
    // bar and the gap the shell keeps from the screen edge.
    //
    // The height is the binding's own dependency, so it goes through a property:
    // referencing a window attached property from inside an onClicked handler
    // makes no binding exist at all, and the cap would quietly stay 0 - which is
    // the same as not passing one, the bug being fixed.
    readonly property real ownWindowHeight: Window.window?.height ?? 0
    readonly property int previewCapHeight: Math.round(root.ownWindowHeight * 0.88)

    ContentPage {
        id: page

        Layout.fillWidth: true
        Layout.fillHeight: true
        // ContentPage centres its content column at
        // `Math.max(baseWidth, implicitWidth)`, and `baseWidth` defaults to
        // 600 - the settings window's number. The panel hands this page 440,
        // so the column was drawn from -80 to 520 and every row was clipped
        // at the panel's left edge while the page rendered perfectly and
        // logged nothing (measured in PhoneSubPageWidthRuntimeTest.qml). The
        // column takes the width it is really given, less the lane the scroll
        // bar overlays.
        forceWidth: true
        baseWidth: Math.max(0, page.width - Appearance.spacing.space200)
        bottomContentPadding: Appearance.spacing.space400

        // A NoticeBox reports its string's UNWRAPPED width as its implicit
        // width, so one long service error asks the column for more room than
        // the panel has, which is what `Math.max(baseWidth, implicitWidth)`
        // above was widening on. Capped, the banner wraps inside itself
        // instead of moving the page.
        NoticeBox {
            Layout.fillWidth: true
            Layout.maximumWidth: page.baseWidth
            visible: !PhoneCamera.available
            materialIcon: "download"
            text: Translation.tr("The camera stream is not set up on this machine. %1 is missing.")
                .arg(PhoneDeps.missingFor("webcam").map(dependency => dependency.name).join(", "))

            DialogButton {
                Layout.alignment: Qt.AlignRight
                buttonText: Translation.tr("How to install")
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                colText: Appearance.colors.colOnPrimary
                onClicked: root.openInstallGuideRequested("webcam",
                    Translation.tr("Phone Webcam — missing dependencies"))
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            Layout.maximumWidth: page.baseWidth
            visible: PhoneCamera.available && !root.deviceReachable
            materialIcon: "phonelink_off"
            text: Translation.tr("No phone is reachable. Connect one over USB or with adb over the network.")
        }

        NoticeBox {
            Layout.fillWidth: true
            Layout.maximumWidth: page.baseWidth
            visible: PhoneCamera.lastError.length > 0
            materialIcon: "error"
            text: PhoneCamera.lastError

            // The webcam's only backend is scrcpy and scrcpy drives the phone
            // over adb, so a good share of what can land in `lastError` is a
            // link that is down rather than a camera that is broken - and the
            // string that says so comes out of the process, which cannot also
            // say where the fix is. Offered whenever adb has answered and
            // listed nothing, which is the same tri-state the cards read.
            DialogButton {
                Layout.alignment: Qt.AlignRight
                visible: PhoneDeps.ready && !PhoneDeps.adbDevice
                buttonText: Translation.tr("Fix the phone link (ADB)")
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                colText: Appearance.colors.colOnPrimary
                onClicked: root.openAdbPageRequested()
            }
        }

        ContentSection {
            icon: "videocam"
            shape: MaterialShape.Shape.Cookie7Sided
            title: Translation.tr("Camera")

            RippleButton {
                Layout.fillWidth: true
                Layout.preferredHeight: Appearance.font.pixelSize.huge * 2 + Appearance.spacing.space150
                enabled: root.canStart || PhoneCamera.active || PhoneCamera.connecting
                buttonRadius: Appearance.rounding.normal
                colBackground: PhoneCamera.active ? Appearance.colors.colErrorContainer : Appearance.colors.colPrimaryContainer
                colBackgroundHover: PhoneCamera.active ? Appearance.colors.colErrorContainerHover : Appearance.colors.colPrimaryContainerHover
                colRipple: PhoneCamera.active ? Appearance.colors.colErrorContainerActive : Appearance.colors.colPrimaryContainerActive
                onClicked: PhoneCamera.toggle()

                contentItem: RowLayout {
                    spacing: Appearance.spacing.space125

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: PhoneCamera.active ? "stop_circle" : "play_circle"
                        fill: PhoneCamera.active ? 1 : 0
                        iconSize: Appearance.font.pixelSize.hugeass
                        color: PhoneCamera.active ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnPrimaryContainer
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: PhoneCamera.connecting ? Translation.tr("Connecting…")
                            : PhoneCamera.active ? Translation.tr("Stop the camera")
                            : Translation.tr("Start the camera")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: PhoneCamera.active ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnPrimaryContainer
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        visible: PhoneCamera.active && PhoneCamera.device.length > 0
                        text: PhoneCamera.device
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.family: Appearance.font.family.monospace
                        color: Appearance.colors.colOnErrorContainer
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: Appearance.spacing.space100
                visible: PhoneCamera.active
                // There is no address and no port to show any more: the stream
                // is scrcpy over whatever transport adb already settled on,
                // and the node the button already names is the other fact.
                //
                // The number is the size the NODE has, not the size the camera
                // was asked for: the crop and the Portrait turn both change it,
                // so quoting `resolution` here used to describe a shape the
                // webcam did not have. "as launched" because an adopted
                // session's truth comes from the settings the launcher read,
                // not from a measurement of the running stream.
                text: Translation.tr("Running for %1 · %2 as launched · %3 lens")
                    .arg(PhoneCards.formatElapsed(PhoneCards.elapsedMs(PhoneCamera.startedAt, clock.nowMs)))
                    .arg(PhoneCamera.streamWidth + "x" + PhoneCamera.streamHeight)
                    .arg(root.webcamConfig?.cameraFacing ?? "front")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.spacing.space100

                RippleButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Appearance.font.pixelSize.huge + Appearance.spacing.space250
                    buttonRadius: Appearance.rounding.normal
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colRipple: Appearance.colors.colLayer2Active
                    // scrcpy picks the lens with --camera-facing, and the
                    // stream is one process that reads it at startup, so the
                    // service restarts it rather than trying to re-open a
                    // camera mid-stream.
                    onClicked: PhoneCamera.flip()

                    contentItem: RowLayout {
                        spacing: Appearance.spacing.space75

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: "cameraswitch"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            text: Translation.tr("Flip camera")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer2
                        }
                    }
                }

                RippleButton {
                    id: previewButton
                    Layout.fillWidth: true
                    Layout.preferredHeight: Appearance.font.pixelSize.huge + Appearance.spacing.space250
                    // A preview that is up stays closable whatever the stream
                    // is doing. The service already closes it with the session,
                    // so this row only has to cover the one ending the shell
                    // cannot see coming - the user changing their mind.
                    enabled: PhoneCamera.previewRunning
                        || (PhoneCamera.active && PhoneCamera.device.length > 0)
                    buttonRadius: Appearance.rounding.normal
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colRipple: Appearance.colors.colLayer2Active
                    onClicked: {
                        if (PhoneCamera.previewRunning)
                            PhoneCamera.closePreview();
                        else
                            PhoneCamera.openPreview(root.previewCapHeight);
                    }

                    contentItem: RowLayout {
                        spacing: Appearance.spacing.space75

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: PhoneCamera.previewRunning ? "visibility_off" : "preview"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            text: PhoneCamera.previewRunning
                                ? Translation.tr("Close preview")
                                : Translation.tr("Preview")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer2
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "video_settings"
            shape: MaterialShape.Shape.Clover4Leaf
            title: Translation.tr("Camera settings")

            GroupedList {
                PhoneConfigSelectionArray {
                    text: Translation.tr("Camera")
                    icon: "photo_camera"
                    infoText: Translation.tr("Which lens scrcpy asks the phone for. A running stream is restarted to apply it - the choice is made when the stream starts and cannot be changed mid-flight.")
                    currentValue: root.webcamConfig?.cameraFacing ?? "front"
                    onSelected: value => PhoneCamera.applySetting("cameraFacing", value)
                    options: [
                        { displayName: Translation.tr("Front"), value: "front", icon: "camera_front" },
                        { displayName: Translation.tr("Back"), value: "back", icon: "camera_rear" }
                    ]
                }

                PhoneConfigSelectionArray {
                    text: Translation.tr("Resolution")
                    icon: "aspect_ratio"
                    // The node's grip on the old size is what used to make this
                    // row a lie: a 1080p stream on a node left at 720p started,
                    // stayed alive and wrote nothing. `PhoneCamera.prepareNode`
                    // clears `keep_format` before every launch, so the row can
                    // promise the change lands instead of only asking for it.
                    infoText: Translation.tr("The size scrcpy asks the CAMERA for, landscape as the phone reports it: Portrait below turns this picture rather than asking for a taller one, and Aspect ratio cuts a box out of it. The loopback node holds the size its last writer negotiated, so the stream's launch resets it first - without that a new size attaches and produces no frames.")
                    currentValue: root.webcamConfig?.resolution ?? "1280x720"
                    onSelected: value => PhoneCamera.applySetting("resolution", value)
                    options: [
                        { displayName: Translation.tr("480p"), value: "640x480", icon: "sd" },
                        { displayName: Translation.tr("720p"), value: "1280x720", icon: "hd" },
                        { displayName: Translation.tr("1080p"), value: "1920x1080", icon: "high_quality" }
                    ]
                }

                PhoneConfigSelectionArray {
                    text: Translation.tr("Aspect ratio")
                    icon: "crop_free"
                    // The three numbers are the shape of the PICTURE, so they
                    // read the same way in both orientations: "3:4" is 720x960
                    // in Portrait and 960x720 in Landscape, because the crop is
                    // computed on the capture and then turned with it.
                    infoText: Translation.tr("Crops the STREAM to this shape, centred, so the webcam itself becomes that size and OBS or a call see the cropped picture rather than a bar-padded one. 1:1 on a 720p capture therefore throws away the sides. The numbers follow the orientation: 3:4 is 720x960 in Portrait and 960x720 in Landscape. Full frame passes no crop at all.")
                    currentValue: root.webcamConfig?.aspectRatio ?? "full"
                    onSelected: value => PhoneCamera.applySetting("aspectRatio", value)
                    options: [
                        { displayName: Translation.tr("1:1"), value: "1:1", icon: "crop_square" },
                        { displayName: Translation.tr("3:4"), value: "3:4", icon: "crop_portrait" },
                        { displayName: Translation.tr("16:9"), value: "16:9", icon: "crop_16_9" },
                        { displayName: Translation.tr("Full frame"), value: "full", icon: "fullscreen" }
                    ]
                }

                PhoneConfigSelectionArray {
                    text: Translation.tr("Orientation")
                    icon: "screen_rotation"
                    infoText: Translation.tr("Portrait turns the picture a quarter turn, and the turn that reads upright is different for the two lenses, so the lens in use picks it. The crop is computed before the turn, so a 4:3 capture in Portrait is a 3:4 webcam. The node ends up tall rather than wide: 1280x720 in Portrait is a 720x1280 webcam.")
                    currentValue: root.webcamConfig?.orientation ?? "landscape"
                    onSelected: value => PhoneCamera.applySetting("orientation", value)
                    options: [
                        { displayName: Translation.tr("Landscape"), value: "landscape", icon: "mobile_landscape" },
                        { displayName: Translation.tr("Portrait"), value: "portrait", icon: "mobile" }
                    ]
                }

                ConfigSwitch {
                    buttonIcon: "flip"
                    text: Translation.tr("Mirror horizontally")
                    // Through the service, not straight into the config: the
                    // mirror is a scrcpy flag rather than a control on the
                    // node, so applying it means restarting the stream, and
                    // only the service knows when one is running.
                    //
                    // The flag it sets is NOT the turn's own number with `flip`
                    // in front of it: scrcpy applies the flip before the
                    // rotation, so that mirrored a Portrait stream up and down.
                    // See PhoneCamera.captureOrientation.
                    infoText: Translation.tr("Left becomes right in the picture applications receive - in Portrait as well as Landscape.")
                    checked: root.webcamConfig?.mirrorHorizontally ?? false
                    selfToggle: false
                    onToggleRequested: PhoneCamera.mirror(!(root.webcamConfig?.mirrorHorizontally ?? false))
                }
            }
        }
    }

    // The elapsed clock, running only while the stream is up.
    QtObject {
        id: clock
        property real nowMs: Date.now()
    }

    Timer {
        interval: 1000
        repeat: true
        running: PhoneCamera.active && root.visible
        onTriggered: clock.nowMs = Date.now()
    }
}
