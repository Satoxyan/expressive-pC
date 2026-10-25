pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.common

/**
 * App Mode's settings sub-page: the launch flags for every app window, on
 * a table of its own (`phone.scrcpy.appMode`) so nothing typed here reaches
 * the mirror.
 *
 * The rows are the shared `PhoneScrcpySettings`; what is App Mode's alone
 * is the default resolution. With a flex display the app renders on a
 * virtual display sized here, so that is the natural default; without one
 * the app is mirrored off the phone's own screen and the phone's size is.
 *
 * A change is the NEXT launch's flags: several app windows can be live at
 * once, and restarting them all to apply a codec would throw away their
 * state. `PhoneScrcpy.applyAppSetting` writes the table and nothing else.
 */
PhoneScrcpySettings {
    id: root

    title: Translation.tr("App Mode Settings")

    readonly property var appConfig: Config.options.phone?.scrcpy?.appMode

    // The virtual display's configured size, in the same WIDTHxHEIGHT form
    // the resolution field uses. It is the DEFAULT: a stored resolution
    // overrides it, and the field shows that value itself. Empty when flex
    // display is off: the app then runs on the phone's screen.
    readonly property string appDisplaySize: {
        if (!(root.appConfig?.flexDisplay ?? true)) return "";
        const width = Number(root.appConfig?.displayWidth) > 0 ? Number(root.appConfig.displayWidth) : 1280;
        const height = Number(root.appConfig?.displayHeight) > 0 ? Number(root.appConfig.displayHeight) : 960;
        return width + "x" + height;
    }

    scrcpyConfig: root.appConfig
    nativeResolution: root.appDisplaySize.length > 0 ? root.appDisplaySize : PhoneScrcpy.deviceScreenSize
    // Only a virtual display can turn with the app; without one the app is
    // mirrored off the phone's own screen.
    followOrientationAvailable: root.appDisplaySize.length > 0
        && (root.appConfig?.videoEnabled ?? true)

    introText: Translation.tr("These are scrcpy launch flags for App Mode. A change applies to the next app you start; an app that is already open keeps the flags it started with.")
    noAdbText: Translation.tr("No phone over ADB. App Mode cannot start an app until the link is up; the resolution default and the encoder list also need it.")
    videoInfoText: root.appDisplaySize.length > 0
        ? Translation.tr("scrcpy's picture of the app. Turning it off launches with --no-video: App Mode's virtual display needs video, so the app starts on the phone's screen instead and the session keeps running without a picture.")
        : Translation.tr("scrcpy's picture of the phone's screen. Turning it off launches with --no-video: the session keeps running, but the phone's screen is not forwarded.")
    resolutionDescription: root.appDisplaySize.length > 0
        ? Translation.tr("The starting size of the app window's virtual display. WIDTHxHEIGHT is used as typed; one number scales the long edge and keeps the display's shape. With Rotation on Auto the window may turn between portrait and landscape as the app needs; the size shown is the default, so clear the field to use it.")
        : Translation.tr("The phone's screen size is the default. scrcpy caps the long edge and keeps the phone's aspect ratio; clear the field to use the default.")
    installGuideTitle: Translation.tr("scrcpy App Mode — missing dependencies")

    onSettingChanged: (key, value) => PhoneScrcpy.applyAppSetting(key, value)
    onCodecSelected: codec => PhoneScrcpy.setAppCodec(codec)
}
