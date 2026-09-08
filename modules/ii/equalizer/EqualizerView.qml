pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Qt5Compat.GraphicalEffects

// A 10-band live equalizer. Talks to EasyEffects through scripts/eq/equalizer.sh
// (all of that plumbing - refresh/setBand/applyPending/applyPreset/eqGetProc -
// is unchanged from before, only the UI built on top of it is new).
//
// The layout is split the way a lot of Material 3 Expressive surfaces are:
// a ratio-sized rail on the left carrying the "who/what" (now playing +
// presets, ~32% of the body width), and an open area on the right - roughly
// two thirds of the popup - that is the actual instrument: 10 horizontal
// StyledSliders in a 2-column stack.
//
// Each band is a real StyledSlider (the same slider component the seek bar
// below uses, and the one the old vertical version rotated -90deg to stand
// upright) - kept flat/horizontal here instead, since that's the layout
// that's staying. Frequency label on the left, live dB readout on the
// right, native slider fill/handle/tooltip in between. Color is put to
// work too: each slider's hue drifts from the tinted primary (bass) to the
// tinted secondary (treble) so the whole cluster reads as one continuous
// gradient instead of ten identical bars.
Item {
    id: root

    // Passed in by EqualizerPopup.qml - a scheme tinted off the currently
    // playing track's art (or plain Appearance.colors as a standalone fallback).
    property QtObject blendedColors: Appearance.colors
    // Optional - only present when something is actually playing. Everything
    // below reads through "?." so a null player just hides the transport row.
    property MprisPlayer player: null
    property string displayedArtFilePath: ""
    signal closeRequested()

    // b1..b10 gains in dB, mirrors eq_state.json written by equalizer.sh
    property var bands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    property string presetName: "Flat"
    property bool pending: false
    readonly property var bandLabels: ["32", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
    readonly property real bandRange: 12 // -12dB .. +12dB, matches equalizer.sh clamp expectations
    // Master gain on top of the 10 bands (maps to the equalizer block's
    // own output-gain) - independent of preset/curve, so it survives
    // switching presets rather than resetting with them.
    property real preamp: 0
    readonly property real preampRange: 12

    // Mirrors equalizer.sh's save_preset() calls exactly, so tapping a
    // preset chip moves the blobs immediately instead of waiting on a
    // shell round-trip to read the state file back.
    readonly property var presetValues: ({
        "Flat":    [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        "Bass":    [5, 7, 5, 2, 1, 0, 0, 0, 1, 2],
        "Treble":  [-2, -1, 0, 1, 2, 3, 4, 5, 6, 6],
        "Vocal":   [-2, -1, 1, 3, 5, 5, 4, 2, 1, 0],
        "Pop":     [2, 4, 2, 0, 1, 2, 4, 2, 1, 2],
        "Rock":    [5, 4, 2, -1, -2, -1, 2, 4, 5, 6],
        "Jazz":    [3, 3, 1, 1, 1, 1, 2, 1, 2, 3],
        "Classic": [0, 1, 2, 2, 2, 2, 1, 2, 3, 4]
    })
    readonly property var presetIcons: ({
        "Flat": "horizontal_rule", "Bass": "graphic_eq", "Treble": "trending_up",
        "Vocal": "mic", "Pop": "star", "Rock": "bolt", "Jazz": "piano", "Classic": "music_note"
    })

    // Auto EQ (genre-follow) now lives in EqualizerAutoService so it keeps
    // running whether or not this view/popup is open - see that file for
    // why. root.autoEnabled below just mirrors the service's state for
    // display; toggleAuto()/maybeLookupGenre() below delegate to it too.
    readonly property bool autoEnabled: EqualizerAutoService.autoEnabled

    // Mirrors equalizer.sh's custom preset store (get_custom/save_custom/
    // delete_custom) - already implemented backend-side, just not exposed
    // in the UI before.
    property string lastfmKey: ""
    property bool showLastfmKeyDialog: false
    property bool lastfmKeyRevealed: false
    // Set when equalizer.sh refused to touch a preset that's never been
    // explicitly saved in EasyEffects (see get_needs_save) - applying an
    // EQ change in that state would otherwise silently wipe any live,
    // unsaved effects (Crystalizer, compressor, etc.) you have running.
    property bool needsManualSave: false
    // name -> [b1..b10], kept in sync with custom_presets.json
    property var customPresets: ({})
    property bool showSaveDialog: false
    onShowSaveDialogChanged: {
        if (root.showSaveDialog) {
            newPresetNameField.text = ""
            newPresetNameField.forceActiveFocus()
        } else {
            newPresetNameField.focus = false
        }
    }
    // Toggles preset chips between "tap to apply" and "tap to delete".
    property bool customEditMode: false

    // Low bands lean tinted-primary, high bands lean tinted-secondary - a
    // cheap continuous gradient across the cluster instead of one flat color.
    function bandAccentColor(index) {
        const t = root.bandLabels.length > 1 ? index / (root.bandLabels.length - 1) : 0
        return ColorUtils.mix(root.blendedColors.colPrimary, root.blendedColors.colSecondary, t)
    }

    function refresh() {
        eqGetProc.running = false
        eqGetProc.running = true
    }

    function setBand(index, value) {
        root.bands[index] = value
        root.bandsChanged()
        root.presetName = "Custom"
        // Keep EqualizerAutoService's mirror of the active preset in sync -
        // otherwise a later genre lookup that resolves back to whatever
        // preset was active before this edit sees no change and skips
        // re-applying it, even though the real active preset is now Custom.
        EqualizerAutoService.currentPresetName = "Custom"
        root.pending = true
        Quickshell.execDetached(["bash", Directories.eqScriptPath, Directories.eqStateDir, "set_band", String(index + 1), String(Math.round(value))])
    }

    // Doesn't touch presetName - preamp is a master gain layered on top
    // of whichever curve is active, not part of the curve's identity, so
    // adjusting it shouldn't make the preset display flip to "Custom".
    function setPreamp(value) {
        root.preamp = value
        root.pending = true
        Quickshell.execDetached(["bash", Directories.eqScriptPath, Directories.eqStateDir, "set_preamp", String(Math.round(value))])
    }

    function applyPending() {
        Quickshell.execDetached(["bash", Directories.eqScriptPath, Directories.eqStateDir, "apply"])
        root.pending = false
        needsSaveRecheckTimer.restart()
    }

    function applyPreset(name) {
        // Update the blobs instantly from the known preset values...
        const vals = root.presetValues[name]
        if (vals) root.bands = vals.slice()
        root.presetName = name
        // See setBand() above - keeps Auto's stale-preset check honest.
        EqualizerAutoService.currentPresetName = name
        root.pending = false
        // ...while the backend writes + loads the matching EasyEffects preset.
        Quickshell.execDetached(["bash", Directories.eqScriptPath, Directories.eqStateDir, "preset", name])
        needsSaveRecheckTimer.restart()
    }

    function refreshNeedsSave() {
        eqGetNeedsSaveProc.running = false
        eqGetNeedsSaveProc.running = true
    }

    function refreshLastfmKey() {
        eqGetLastfmKeyProc.running = false
        eqGetLastfmKeyProc.running = true
    }

    function saveLastfmKey(key) {
        const trimmed = key.trim()
        root.lastfmKey = trimmed
        Quickshell.execDetached(["bash", Directories.eqScriptPath, Directories.eqStateDir, "set_lastfm_key", trimmed])
        root.showLastfmKeyDialog = false
        // A key just got set (or cleared) - re-run the current artist's
        // lookup instead of waiting for the next track change.
        EqualizerAutoService.lastGenreArtist = ""
        EqualizerAutoService.maybeLookupGenre()
    }

    function toggleAuto() {
        const goingOn = !EqualizerAutoService.autoEnabled
        EqualizerAutoService.toggleAuto()
        // Auto can't do anything without a key to look genres up with -
        // open the paste field right away instead of letting it silently
        // no-op every track change.
        if (goingOn && root.lastfmKey.length === 0) root.showLastfmKeyDialog = true
    }

    function refreshCustomPresets() {
        eqGetCustomProc.running = false
        eqGetCustomProc.running = true
    }

    // Same instant-update-then-backend-catches-up pattern as applyPreset(),
    // just routed at "preset" NAME, which equalizer.sh falls through to
    // apply_custom_preset() for anything that isn't one of the 8 built-ins.
    function applyCustomPreset(name) {
        const vals = root.customPresets[name]
        if (vals) root.bands = vals.slice()
        root.presetName = name
        // See setBand() above - keeps Auto's stale-preset check honest.
        EqualizerAutoService.currentPresetName = name
        root.pending = false
        Quickshell.execDetached(["bash", Directories.eqScriptPath, Directories.eqStateDir, "preset", name])
        needsSaveRecheckTimer.restart()
    }

    function saveCustomPreset(name) {
        const trimmed = name.trim()
        if (!trimmed) return
        const args = ["bash", Directories.eqScriptPath, Directories.eqStateDir, "save_custom", trimmed]
        for (const v of root.bands) args.push(String(Math.round(v)))
        Quickshell.execDetached(args)
        const updated = Object.assign({}, root.customPresets)
        updated[trimmed] = root.bands.slice()
        root.customPresets = updated
        root.presetName = trimmed
        // See setBand() above - keeps Auto's stale-preset check honest.
        EqualizerAutoService.currentPresetName = trimmed
        root.showSaveDialog = false
        needsSaveRecheckTimer.restart()
    }

    function deleteCustomPreset(name) {
        Quickshell.execDetached(["bash", Directories.eqScriptPath, Directories.eqStateDir, "delete_custom", name])
        const updated = Object.assign({}, root.customPresets)
        delete updated[name]
        root.customPresets = updated
        if (root.presetName === name) {
            root.presetName = "Custom"
            // See setBand() above - keeps Auto's stale-preset check honest.
            EqualizerAutoService.currentPresetName = "Custom"
        }
    }

    // A short one-shot delay before polling get_needs_save after any
    // action that runs apply_eq() on the backend (execDetached is
    // fire-and-forget, so there's no direct completion signal to hook -
    // this just gives the detached bash process a moment to finish its
    // file write before we ask about the result).
    Timer {
        id: needsSaveRecheckTimer
        interval: 350
        onTriggered: root.refreshNeedsSave()
    }

    // EqualizerAutoService runs in the background independent of this view,
    // so a genre-triggered preset switch can happen while the popup is
    // already open (or was open before the track changed). Without this,
    // the sliders/preset chip only ever reflected whatever was on disk at
    // Component.onCompleted - i.e. Auto looked like it "worked" only if you
    // closed and reopened the popup. Mirror the service's applied preset
    // straight into the view's own display, the same way applyPreset()
    // already does for a manual tap - all of Auto's targets (Rock, Classic,
    // Jazz, Bass, Vocal, Pop) are built-ins with known values, so no disk
    // read (and no race with the backend's own async write) is needed.
    Connections {
        target: EqualizerAutoService
        function onCurrentPresetNameChanged() {
            const name = EqualizerAutoService.currentPresetName
            const vals = root.presetValues[name]
            if (vals) {
                root.bands = vals.slice()
                root.presetName = name
                root.pending = false
                needsSaveRecheckTimer.restart()
            }
        }
    }

    Component.onCompleted: {
        root.refresh()
        root.refreshLastfmKey()
        root.refreshCustomPresets()
        root.refreshNeedsSave()
    }

    // MPRIS doesn't push continuous position updates on its own - most
    // players only actually notify every few seconds. Forcing
    // positionChanged() on a fast cadence while playing re-evaluates the
    // seek slider's value binding often enough for it to crawl smoothly
    // instead of jumping every few seconds.
    Timer {
        running: root.player?.playbackState == MprisPlaybackState.Playing
        interval: Config.options.resources.updateInterval
        repeat: true
        onTriggered: root.player.positionChanged()
    }

    Process {
        id: eqGetProc
        command: ["bash", Directories.eqScriptPath, Directories.eqStateDir, "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text)
                    root.bands = [
                        Number(data.b1), Number(data.b2), Number(data.b3), Number(data.b4), Number(data.b5),
                        Number(data.b6), Number(data.b7), Number(data.b8), Number(data.b9), Number(data.b10)
                    ]
                    root.presetName = data.preset ?? "Custom"
                    // Safety net alongside the explicit syncs in setBand()/
                    // applyPreset()/etc. - if anything else ever writes the
                    // state file, Auto's mirror still gets corrected here.
                    EqualizerAutoService.currentPresetName = root.presetName
                    root.pending = !!data.pending
                    root.preamp = Number(data.preamp) || 0
                } catch (e) {
                    // Leave previous values if the state file isn't ready yet
                }
            }
        }
    }

    Process {
        id: eqGetLastfmKeyProc
        command: ["bash", Directories.eqScriptPath, Directories.eqStateDir, "get_lastfm_key"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.lastfmKey = text.trim()
            }
        }
    }

    Process {
        id: eqGetNeedsSaveProc
        command: ["bash", Directories.eqScriptPath, Directories.eqStateDir, "get_needs_save"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim()
                root.needsManualSave = (t === "true" || t === "1")
            }
        }
    }

    Process {
        id: eqGetCustomProc
        command: ["bash", Directories.eqScriptPath, Directories.eqStateDir, "get_custom"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text)
                    const parsed = {}
                    for (const name in data) {
                        const b = data[name]
                        parsed[name] = [b.b1, b.b2, b.b3, b.b4, b.b5, b.b6, b.b7, b.b8, b.b9, b.b10].map(Number)
                    }
                    root.customPresets = parsed
                } catch (e) {
                    // Leave previous values if custom_presets.json isn't ready yet
                }
            }
        }
    }

    // A fully-rounded, translucent chip - used for the header's icon
    // buttons and the rail's preset list. colLayer1Hover/Active aren't part
    // of the blended (art-tinted) color set, so the hover/active tones are
    // derived locally the same way Appearance.colors itself derives them.
    component PillChip: RippleButton {
        id: chip
        property bool chipToggled: false
        buttonRadius: Appearance.rounding.full
        colBackground: ColorUtils.transparentize(root.blendedColors.colLayer1, chipToggled ? 1 : 0.35)
        colBackgroundHover: ColorUtils.mix(root.blendedColors.colLayer1, root.blendedColors.colOnLayer1, 0.92)
        colBackgroundToggled: root.blendedColors.colPrimary
        colBackgroundToggledHover: root.blendedColors.colPrimaryHover
        colRipple: ColorUtils.mix(root.blendedColors.colLayer1, root.blendedColors.colOnLayer1, 0.85)
        colRippleToggled: root.blendedColors.colPrimaryActive
        toggled: chipToggled
    }

    // Compact transport icon button for the rail's prev/next controls.
    component TransportButton: RippleButton {
        implicitWidth: 24
        implicitHeight: 24
        property var iconName
        colBackground: ColorUtils.transparentize(root.blendedColors.colSecondaryContainer, 1)
        colBackgroundHover: root.blendedColors.colSecondaryContainerHover
        colRipple: root.blendedColors.colSecondaryContainerActive
        contentItem: MaterialSymbol {
            iconSize: Appearance.font.pixelSize.huge
            fill: 1
            horizontalAlignment: Text.AlignHCenter
            color: root.blendedColors.colOnSecondaryContainer
            text: iconName
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }

    // One band, built on the shell's own StyledSlider - the same real
    // slider component the old vertical version used (there just rotated
    // -90deg to stand upright). Kept flat/horizontal here since that's the
    // layout that's staying: frequency label on the left, the slider filling
    // the middle, live dB readout on the right.
    component BandCell: RowLayout {
        id: cell
        required property int index
        spacing: 8

        readonly property color accent: root.bandAccentColor(cell.index)

        StyledText {
            Layout.preferredWidth: 26
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.features: { "tnum": 1 }
            color: root.blendedColors.colSubtext
            text: root.bandLabels[cell.index]
        }

        StyledSlider {
            id: bandSlider
            Layout.fillWidth: true
            Layout.fillHeight: true
            configuration: StyledSlider.Configuration.M
            from: -root.bandRange
            to: root.bandRange
            value: root.bands[cell.index] ?? 0
            highlightColor: cell.accent
            trackColor: ColorUtils.transparentize(cell.accent, 0.85)
            handleColor: cell.accent
            usePercentTooltip: false
            tooltipContent: `${Math.round(value) > 0 ? "+" : ""}${Math.round(value)} dB`
            onMoved: root.setBand(cell.index, value)

            Behavior on value {
                enabled: !bandSlider.pressed
                NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
            }
        }

        StyledText {
            Layout.preferredWidth: 28
            horizontalAlignment: Text.AlignRight
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.features: { "tnum": 1 }
            color: cell.accent
            text: `${Math.round(root.bands[cell.index] ?? 0) > 0 ? "+" : ""}${Math.round(root.bands[cell.index] ?? 0)}`
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 22
        spacing: 16

        // Header - icon, title/preset, reset, close.
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            MaterialShapeWrappedMaterialSymbol {
                wrappedShape: MaterialShape.Shape.Cookie6Sided
                text: "equalizer"
                fill: 1
                iconSize: Appearance.font.pixelSize.huge
                padding: 12
                color: ColorUtils.transparentize(root.blendedColors.colPrimary, 0.85)
                colSymbol: root.blendedColors.colPrimary
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.title
                    font.bold: true
                    color: root.blendedColors.colOnLayer0
                    elide: Text.ElideRight
                    text: Translation.tr("Equalizer")
                }
                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: root.blendedColors.colSubtext
                    elide: Text.ElideRight
                    text: `${Translation.tr("Preset")}: ${root.presetName}`
                }
            }

            PillChip {
                implicitHeight: 40
                Layout.preferredWidth: autoLabel.implicitWidth + 56
                chipToggled: root.autoEnabled
                downAction: () => root.toggleAuto()
                contentItem: Item {
                    anchors.fill: parent
                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 4
                        MaterialSymbol {
                            iconSize: Appearance.font.pixelSize.normal
                            fill: root.autoEnabled ? 1 : 0
                            text: "auto_awesome"
                            color: root.autoEnabled ? root.blendedColors.colOnPrimary : root.blendedColors.colOnLayer1
                        }
                        StyledText {
                            id: autoLabel
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            text: Translation.tr("Auto")
                            color: root.autoEnabled ? root.blendedColors.colOnPrimary : root.blendedColors.colOnLayer1
                        }
                    }
                }
            }

            PillChip {
                implicitWidth: 40
                implicitHeight: 40
                chipToggled: root.showLastfmKeyDialog
                downAction: () => root.showLastfmKeyDialog = !root.showLastfmKeyDialog
                contentItem: Item {
                    anchors.fill: parent
                    MaterialSymbol {
                        anchors.centerIn: parent
                        iconSize: Appearance.font.pixelSize.huge
                        // Filled key = a key is already saved; outline = not set up yet.
                        fill: root.lastfmKey.length > 0 ? 1 : 0
                        horizontalAlignment: Text.AlignHCenter
                        color: root.showLastfmKeyDialog ? root.blendedColors.colOnPrimary : root.blendedColors.colOnLayer1
                        text: "key"
                    }
                }
            }

            PillChip {
                implicitWidth: 40
                implicitHeight: 40
                downAction: () => root.applyPreset("Flat")
                contentItem: MaterialSymbol {
                    iconSize: Appearance.font.pixelSize.huge
                    fill: 0
                    horizontalAlignment: Text.AlignHCenter
                    color: root.blendedColors.colOnLayer1
                    text: "refresh"
                }
            }

            PillChip {
                implicitWidth: 40
                implicitHeight: 40
                downAction: () => root.closeRequested()
                contentItem: MaterialSymbol {
                    iconSize: Appearance.font.pixelSize.huge
                    fill: 1
                    horizontalAlignment: Text.AlignHCenter
                    color: root.blendedColors.colOnLayer1
                    text: "close"
                }
            }
        }

        // Nudges toward setting a key whenever Auto is on but there's
        // nothing for genre_tags to look up with - stays visible (not just
        // a one-off toast) since the underlying problem persists until a
        // key is actually saved.
        Rectangle {
            Layout.fillWidth: false
            visible: root.autoEnabled && root.lastfmKey.length === 0
            implicitWidth: lastfmHintRow.implicitWidth + 16
            implicitHeight: lastfmHintRow.implicitHeight + 16
            radius: Appearance.rounding.normal
            color: ColorUtils.transparentize(root.blendedColors.colPrimary, 0.85)

            RowLayout {
                id: lastfmHintRow
                anchors.centerIn: parent
                spacing: 6

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    iconSize: Appearance.font.pixelSize.normal
                    fill: 0
                    text: "info"
                    color: root.blendedColors.colPrimary
                }
                StyledText {
                    id: lastfmHintText
                    Layout.alignment: Qt.AlignVCenter
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: root.blendedColors.colOnLayer1
                    text: Translation.tr("Auto needs a Last.fm API key to look up genres. Get one free and paste it in the key field above.")
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.showLastfmKeyDialog = true
            }
        }

        // Inline "paste your Last.fm API key" row, toggled by the key chip
        // above. Pre-filled with whatever's already saved so it doubles as
        // an editor, not just a first-time setup field. Never shipped with
        // a real key baked in - each user drops their own free key
        // (https://www.last.fm/api/account/create) in here once.
        RowLayout {
            Layout.fillWidth: true
            visible: root.showLastfmKeyDialog
            spacing: 6

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 32
                radius: Appearance.rounding.normal
                color: ColorUtils.transparentize(root.blendedColors.colLayer1, 0.35)
                border.width: lastfmKeyField.activeFocus ? 1 : 0
                border.color: root.blendedColors.colPrimary

                TextInput {
                    id: lastfmKeyField
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 34
                    verticalAlignment: TextInput.AlignVCenter
                    color: root.blendedColors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    clip: true
                    echoMode: root.lastfmKeyRevealed ? TextInput.Normal : TextInput.Password
                    text: root.lastfmKey
                    onAccepted: root.saveLastfmKey(text)
                    Keys.onEscapePressed: { root.showLastfmKeyDialog = false }

                    StyledText {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        visible: lastfmKeyField.text.length === 0
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: root.blendedColors.colSubtext
                        text: Translation.tr("Paste Last.fm API key\u2026")
                    }
                }

                MaterialSymbol {
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    iconSize: Appearance.font.pixelSize.normal
                    fill: root.lastfmKeyRevealed ? 1 : 0
                    text: root.lastfmKeyRevealed ? "visibility_off" : "visibility"
                    color: root.blendedColors.colSubtext

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.lastfmKeyRevealed = !root.lastfmKeyRevealed
                    }
                }
            }
            PillChip {
                implicitWidth: 32
                implicitHeight: 32
                chipToggled: true
                downAction: () => root.saveLastfmKey(lastfmKeyField.text)
                contentItem: MaterialSymbol {
                    iconSize: Appearance.font.pixelSize.normal
                    fill: 1
                    horizontalAlignment: Text.AlignHCenter
                    text: "check"
                    color: root.blendedColors.colOnPrimary
                }
            }
            PillChip {
                implicitWidth: 32
                implicitHeight: 32
                visible: root.lastfmKey.length > 0
                downAction: () => { lastfmKeyField.text = ""; root.saveLastfmKey("") }
                contentItem: MaterialSymbol {
                    iconSize: Appearance.font.pixelSize.normal
                    fill: 0
                    horizontalAlignment: Text.AlignHCenter
                    text: "delete"
                    color: root.blendedColors.colOnLayer1
                }
            }
        }

        // Body - a rail (now playing + presets) beside the open band
        // cluster. The rail is sized as a ratio of the body's width rather
        // than a fixed pixel count, so it keeps to roughly a third of the
        // popup and leaves the remaining ~65-70% for the band sliders.
        RowLayout {
            id: bodyRow
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 14

            ColumnLayout {
                Layout.fillWidth: false
                Layout.preferredWidth: Math.round(bodyRow.width * 0.32)
                Layout.fillHeight: true
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    visible: root.player !== null

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Rectangle {
                            id: nowPlayingArt
                            Layout.preferredWidth: 46
                            Layout.preferredHeight: 46
                            color: ColorUtils.transparentize(root.blendedColors.colLayer1, 0.5)

                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: MaterialShape {
                                    shape: MaterialShape.Shape.Bun
                                    implicitSize: nowPlayingArt.width
                                }
                            }

                            StyledImage {
                                anchors.fill: parent
                                source: root.displayedArtFilePath
                                fillMode: Image.PreserveAspectCrop
                                cache: false
                                antialiasing: true
                                visible: root.displayedArtFilePath.length > 0
                            }
                            MaterialSymbol {
                                anchors.centerIn: parent
                                iconSize: Appearance.font.pixelSize.huge
                                fill: 1
                                text: "music_note"
                                color: root.blendedColors.colOnLayer1
                                visible: root.displayedArtFilePath.length === 0
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            StyledText {
                                Layout.fillWidth: true
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.bold: true
                                color: root.blendedColors.colOnLayer0
                                elide: Text.ElideRight
                                text: StringUtils.cleanMusicTitle(root.player?.trackTitle) || Translation.tr("Untitled")
                            }
                            StyledText {
                                Layout.fillWidth: true
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: root.blendedColors.colSubtext
                                elide: Text.ElideRight
                                text: root.player?.trackArtist ?? ""
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        TransportButton {
                            iconName: "skip_previous"
                            downAction: () => root.player?.previous()
                        }

                        RippleButton {
                            id: playPauseButton
                            Layout.fillWidth: true
                            implicitHeight: 32
                            downAction: () => root.player?.togglePlaying()
                            buttonRadius: (root.player?.isPlaying ?? false) ? Appearance.rounding.normal : Appearance.rounding.full
                            colBackground: (root.player?.isPlaying ?? false) ? root.blendedColors.colPrimary : root.blendedColors.colSecondaryContainer
                            colBackgroundHover: (root.player?.isPlaying ?? false) ? root.blendedColors.colPrimaryHover : root.blendedColors.colSecondaryContainerHover
                            colRipple: (root.player?.isPlaying ?? false) ? root.blendedColors.colPrimaryActive : root.blendedColors.colSecondaryContainerActive
                            contentItem: MaterialSymbol {
                                iconSize: Appearance.font.pixelSize.large
                                fill: 1
                                horizontalAlignment: Text.AlignHCenter
                                color: (root.player?.isPlaying ?? false) ? root.blendedColors.colOnPrimary : root.blendedColors.colOnSecondaryContainer
                                text: (root.player?.isPlaying ?? false) ? "pause" : "play_arrow"
                            }
                        }

                        TransportButton {
                            iconName: "skip_next"
                            downAction: () => root.player?.next()
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        implicitHeight: 16

                        Loader {
                            anchors.fill: parent
                            active: root.player?.canSeek ?? false
                            sourceComponent: StyledSlider {
                                configuration: StyledSlider.Configuration.Wavy
                                highlightColor: root.blendedColors.colPrimary
                                trackColor: root.blendedColors.colSecondaryContainer
                                handleColor: root.blendedColors.colPrimary
                                value: (root.player?.length > 0) ? root.player.position / root.player.length : 0
                                onPressedChanged: if (!pressed) root.player.position = value * root.player.length
                            }
                        }
                        Loader {
                            anchors.fill: parent
                            active: !(root.player?.canSeek ?? false)
                            sourceComponent: StyledProgressBar {
                                wavy: root.player?.isPlaying ?? false
                                highlightColor: root.blendedColors.colPrimary
                                trackColor: root.blendedColors.colSecondaryContainer
                                value: (root.player?.length > 0) ? root.player.position / root.player.length : 0
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.features: { "tnum": 1 }
                        color: root.blendedColors.colSubtext
                        text: `${StringUtils.friendlyTimeForSeconds(root.player?.position)} / ${StringUtils.friendlyTimeForSeconds(root.player?.length)}`
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    implicitHeight: 1
                    color: ColorUtils.transparentize(root.blendedColors.colSubtext, 0.85)
                }

                // Shown when equalizer.sh detects it's never been saved to
                // this EasyEffects preset before - applying an EQ change
                // right now would replace your entire live pipeline with
                // an equalizer-only one, silently dropping any other
                // effects (Crystalizer, compressor, etc.) you've set up
                // but not yet saved. The backend already refused to touch
                // anything; this just tells you why nothing happened.
                Rectangle {
                    Layout.fillWidth: true
                    visible: root.needsManualSave
                    Layout.minimumHeight: implicitHeight
                    radius: Appearance.rounding.normal
                    color: ColorUtils.transparentize(root.blendedColors.colPrimary, 0.85)
                    implicitHeight: warningText.implicitHeight + 16

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 6

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignTop
                            iconSize: Appearance.font.pixelSize.normal
                            fill: 0
                            text: "info"
                            color: root.blendedColors.colPrimary
                        }
                        StyledText {
                            id: warningText
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: root.blendedColors.colOnLayer1
                            text: Translation.tr("Save your current EasyEffects setup first (Presets tab \u2192 Save), or other effects won't be kept when you use this equalizer.")
                        }
                    }
                }

                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.bold: true
                    color: root.blendedColors.colSubtext
                    text: Translation.tr("Presets")
                }

                // 2 columns x 4 rows so all 8 presets sit beside each other
                // without needing to scroll (5 already fit in one column;
                // this just gives the other 3 a partner column instead of
                // hiding them below a Flickable).
                GridLayout {
                    Layout.fillWidth: true
                    // Without this, adding custom presets grows the content
                    // below and the ColumnLayout compresses ALL children
                    // (including this grid) to make it fit, since nothing
                    // was pinned to a floor size - that's what was squishing
                    // Flat/Bass/etc. Pinning this to its own natural height
                    // means the custom section (which already scrolls) is
                    // the one that gives up space instead.
                    Layout.minimumHeight: implicitHeight
                    columns: 2
                    columnSpacing: 6
                    rowSpacing: 6

                    Repeater {
                        model: Object.keys(root.presetValues)

                        delegate: PillChip {
                            id: presetBtn
                            required property string modelData
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.preferredWidth: 0
                            chipToggled: root.presetName === modelData
                            downAction: () => root.applyPreset(modelData)
                            contentItem: RowLayout {
                                spacing: 4
                                Item { implicitWidth: 4 }
                                MaterialSymbol {
                                    iconSize: Appearance.font.pixelSize.normal
                                    fill: 0
                                    text: root.presetIcons[presetBtn.modelData] ?? "tune"
                                    color: presetBtn.chipToggled ? root.blendedColors.colOnPrimary : root.blendedColors.colOnLayer1
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    text: Translation.tr(presetBtn.modelData)
                                    color: presetBtn.chipToggled ? root.blendedColors.colOnPrimary : root.blendedColors.colOnLayer1
                                }
                            }
                        }
                    }
                }

                // Custom presets - save the current 10-band curve under a
                // name via save_custom, list/apply saved ones via
                // get_custom, remove via delete_custom. All three already
                // existed in equalizer.sh; this is the first UI for them.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    Layout.minimumHeight: implicitHeight
                    StyledText {
                        Layout.fillWidth: true
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.bold: true
                        color: root.blendedColors.colSubtext
                        text: Translation.tr("Custom")
                    }
                    PillChip {
                        implicitWidth: 26
                        implicitHeight: 26
                        visible: Object.keys(root.customPresets).length > 0
                        chipToggled: root.customEditMode
                        downAction: () => root.customEditMode = !root.customEditMode
                        contentItem: MaterialSymbol {
                            iconSize: Appearance.font.pixelSize.normal
                            fill: 0
                            horizontalAlignment: Text.AlignHCenter
                            text: root.customEditMode ? "check" : "edit"
                            color: root.customEditMode ? root.blendedColors.colOnPrimary : root.blendedColors.colOnLayer1
                        }
                    }
                    PillChip {
                        implicitWidth: 26
                        implicitHeight: 26
                        downAction: () => root.showSaveDialog = !root.showSaveDialog
                        contentItem: MaterialSymbol {
                            iconSize: Appearance.font.pixelSize.normal
                            fill: 0
                            horizontalAlignment: Text.AlignHCenter
                            text: "add"
                            color: root.blendedColors.colOnLayer1
                        }
                    }
                }

                // Inline "save current curve as..." row, shown by the "+" above.
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.showSaveDialog
                    spacing: 6

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 32
                        radius: Appearance.rounding.normal
                        color: ColorUtils.transparentize(root.blendedColors.colLayer1, 0.35)
                        border.width: newPresetNameField.activeFocus ? 1 : 0
                        border.color: root.blendedColors.colPrimary

                        TextInput {
                            id: newPresetNameField
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            verticalAlignment: TextInput.AlignVCenter
                            color: root.blendedColors.colOnLayer1
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            clip: true
                            onAccepted: root.saveCustomPreset(text)
                            Keys.onEscapePressed: { root.showSaveDialog = false }
                        }
                    }
                    PillChip {
                        implicitWidth: 32
                        implicitHeight: 32
                        chipToggled: true
                        downAction: () => root.saveCustomPreset(newPresetNameField.text)
                        contentItem: MaterialSymbol {
                            iconSize: Appearance.font.pixelSize.normal
                            fill: 1
                            horizontalAlignment: Text.AlignHCenter
                            text: "check"
                            color: root.blendedColors.colOnPrimary
                        }
                    }
                    PillChip {
                        implicitWidth: 32
                        implicitHeight: 32
                        downAction: () => { root.showSaveDialog = false; newPresetNameField.text = "" }
                        contentItem: MaterialSymbol {
                            iconSize: Appearance.font.pixelSize.normal
                            fill: 0
                            horizontalAlignment: Text.AlignHCenter
                            text: "close"
                            color: root.blendedColors.colOnLayer1
                        }
                    }
                }

                // Height-capped and scrollable, unlike the built-in preset
                // grid above - that one is always exactly 8 items, but this
                // list grows every time you hit "+". Fixed at exactly one
                // row (2 buttons) rather than growing with content - if this
                // grew, the rail's total height would grow too and Apply
                // would eventually get squeezed/pushed out again. Locking it
                // to a constant means the rail's total height never changes
                // no matter how many presets are saved; more than 2 just
                // scroll inside this same fixed box.
                Flickable {
                    id: customPresetsFlick
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    Layout.minimumHeight: 40
                    Layout.maximumHeight: 40
                    visible: Object.keys(root.customPresets).length > 0
                    clip: true
                    contentWidth: width
                    contentHeight: customPresetsGrid.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    GridLayout {
                        id: customPresetsGrid
                        width: customPresetsFlick.width
                        columns: 2
                        columnSpacing: 6
                        rowSpacing: 6

                        Repeater {
                            model: Object.keys(root.customPresets)

                            delegate: PillChip {
                                id: customBtn
                                required property string modelData
                                // Explicit fixed size instead of Layout.fillWidth
                                // stretching - inside a Flickable (not a Layout
                                // parent) that stretch was recomputing per
                                // rebuild and shrinking the chips/squeezing the
                                // text. This always matches a clean 2-column
                                // split of the grid's own width, same visual
                                // size as the built-in preset chips above.
                                Layout.preferredWidth: (customPresetsGrid.width - customPresetsGrid.columnSpacing) / 2
                                Layout.preferredHeight: 34
                                clip: true
                                chipToggled: root.presetName === modelData
                                downAction: () => root.customEditMode ? root.deleteCustomPreset(modelData) : root.applyCustomPreset(modelData)
                                contentItem: RowLayout {
                                    spacing: 4
                                    Item { implicitWidth: 4 }
                                    MaterialSymbol {
                                        iconSize: Appearance.font.pixelSize.normal
                                        fill: 0
                                        text: root.customEditMode ? "delete" : "tune"
                                        color: customBtn.chipToggled ? root.blendedColors.colOnPrimary : root.blendedColors.colOnLayer1
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        text: customBtn.modelData
                                        color: customBtn.chipToggled ? root.blendedColors.colOnPrimary : root.blendedColors.colOnLayer1
                                    }
                                }
                            }
                        }
                    }

                    // Thin translucent scroll indicator - only shows once
                    // content actually overflows the capped height.
                    Rectangle {
                        visible: customPresetsFlick.contentHeight > customPresetsFlick.height
                        anchors.right: parent.right
                        anchors.rightMargin: 1
                        y: customPresetsFlick.visibleArea.yPosition * customPresetsFlick.height
                        width: 3
                        radius: 1.5
                        height: customPresetsFlick.visibleArea.heightRatio * customPresetsFlick.height
                        color: ColorUtils.transparentize(root.blendedColors.colSubtext, 0.6)
                    }
                }

                // Apply - the rail's primary action, not a full-width bar
                // spanning the whole popup. Pinned to its natural size for
                // the same reason as the built-in preset grid above: without
                // this floor, a long custom-preset list left this button as
                // the next thing the Layout engine squeezed/pushed out once
                // the custom Flickable's own 120px cap wasn't enough slack.
                PillChip {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    Layout.minimumHeight: implicitHeight
                    implicitHeight: 46
                    enabled: root.pending
                    chipToggled: true
                    colBackgroundToggled: root.pending ? root.blendedColors.colPrimary : ColorUtils.transparentize(root.blendedColors.colLayer1, 0.35)
                    colBackgroundToggledHover: root.pending ? root.blendedColors.colPrimaryHover : ColorUtils.mix(root.blendedColors.colLayer1, root.blendedColors.colOnLayer1, 0.92)
                    downAction: () => root.applyPending()
                    contentItem: RowLayout {
                        spacing: 6
                        Item { Layout.fillWidth: true }
                        MaterialSymbol {
                            iconSize: Appearance.font.pixelSize.large
                            fill: 1
                            text: root.pending ? "check" : "check_circle"
                            color: root.pending ? root.blendedColors.colOnPrimary : root.blendedColors.colSubtext
                        }
                        StyledText {
                            font.bold: true
                            text: root.pending ? Translation.tr("Apply") : Translation.tr("Applied")
                            color: root.pending ? root.blendedColors.colOnPrimary : root.blendedColors.colSubtext
                        }
                        Item { Layout.fillWidth: true }
                    }
                }
            }

            // Band cluster + preamp, stacked vertically: 2 columns of
            // horizontal StyledSliders (5 rows) for the 10 bands, plus one
            // full-width master gain slider underneath.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10

                GridLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    columns: 2
                    columnSpacing: 14
                    rowSpacing: 10

                    Repeater {
                        model: root.bandLabels.length
                        delegate: BandCell {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.preferredWidth: 0
                            Layout.minimumHeight: 34
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.minimumHeight: implicitHeight
                    implicitHeight: 1
                    color: ColorUtils.transparentize(root.blendedColors.colSubtext, 0.85)
                }

                // Preamp / output gain - one master control under the ten
                // individual bands rather than an 11th band. Compensates
                // for headroom lost when several bands are boosted,
                // instead of the mix just clipping. Maps to the
                // equalizer block's own output-gain, independent of
                // whichever curve/preset is active.
                RowLayout {
                    id: preampRow
                    Layout.fillWidth: true
                    Layout.minimumHeight: implicitHeight
                    spacing: 8

                    StyledText {
                        Layout.preferredWidth: 26
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.features: { "tnum": 1 }
                        color: root.blendedColors.colSubtext
                        text: Translation.tr("Pre")
                    }

                    StyledSlider {
                        id: preampSlider
                        Layout.fillWidth: true
                        configuration: StyledSlider.Configuration.M
                        from: -root.preampRange
                        to: root.preampRange
                        value: root.preamp
                        highlightColor: root.blendedColors.colPrimary
                        trackColor: ColorUtils.transparentize(root.blendedColors.colPrimary, 0.85)
                        handleColor: root.blendedColors.colPrimary
                        usePercentTooltip: false
                        tooltipContent: `${Math.round(value) > 0 ? "+" : ""}${Math.round(value)} dB`
                        onMoved: root.setPreamp(value)

                        Behavior on value {
                            enabled: !preampSlider.pressed
                            NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                        }
                    }

                    StyledText {
                        Layout.preferredWidth: 28
                        horizontalAlignment: Text.AlignRight
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.features: { "tnum": 1 }
                        color: root.blendedColors.colPrimary
                        text: `${Math.round(root.preamp) > 0 ? "+" : ""}${Math.round(root.preamp)}`
                    }
                }
            }
        }
    }
}
