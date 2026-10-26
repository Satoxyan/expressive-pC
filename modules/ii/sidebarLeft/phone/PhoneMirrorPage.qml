pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.common

/**
 * The Phone tab's scrcpy mirror settings sub-page.
 *
 * The rows live in `PhoneScrcpySettings`; this page supplies the mirror's
 * own config table and what is true of a mirror: a change restarts it, its
 * resolution defaults to the phone's real screen, and Rotation's Auto
 * follows that screen.
 */
PhoneScrcpySettings {
    id: root

    title: Translation.tr("scrcpy Mirror")

    scrcpyConfig: Config.options.phone?.scrcpy
    // The mirror's display is the phone's own, so Auto follows display 0.
    followOrientationAvailable: true
    followPhoneOrientation: true

    introText: Translation.tr("These are scrcpy launch flags. Changing one while the mirror is running restarts it.")
    noAdbText: Translation.tr("No phone over ADB. The resolution default and the encoder list need one; every other row still applies.")
    resolutionDescription: Translation.tr("The real screen size is the default. scrcpy caps the long edge and keeps the phone's aspect ratio, so the short edge follows the phone. Clear the field for the phone's native size.")
    installGuideTitle: Translation.tr("scrcpy Mirror — missing dependencies")

    onSettingChanged: (key, value) => PhoneScrcpy.applyMirrorSetting(key, value)
    onCodecSelected: codec => PhoneScrcpy.setMirrorCodec(codec)
    onAudioSourceSelected: source => PhoneScrcpy.setMirrorAudioSource(source)
}
