pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "phone_cards.js" as PhoneCards

/**
 * What a Phone feature is missing on this machine, and how to install it.
 *
 * `dependencies` is exactly what `PhoneDeps.missingFor(feature)` answers -
 * one row per missing dependency, each carrying a name, a description and the
 * per-distro command table - so this component knows nothing about scrcpy,
 * DroidCam or v4l2loopback and cannot drift from what the probes actually
 * found.
 *
 * The three distro pills preselect from `PhoneDeps.distro`; the arithmetic
 * (which pill, which command, which lines of a multi-line block are drawn) is
 * phone_cards.js, driven by tests/tst_phone_cards.qml.
 *
 * Copy is `wl-copy -- <text>` as a constant argv. The sibling fork spelled it
 * `bash -c "wl-copy '" + quote(text) + "'"`, which puts its own quoting helper
 * between an install command and a shell.
 */
Item {
    id: root

    // [{ key, name, description, commands: { arch, fedora, debian } }]
    property var dependencies: []
    property string detectedDistro: "unknown"
    property string headerTitle: Translation.tr("Missing dependencies")

    signal closeRequested
    signal recheckRequested
    // Launching anything is the host's decision: it is the host that knows
    // which feature asked for the guide, and therefore which script covers
    // these packages. This component stays a list of what is missing.
    signal installRequested
    property bool installerAvailable: false

    property string selectedDistro: PhoneCards.initialDistro(root.detectedDistro)

    onVisibleChanged: if (root.visible)
        root.selectedDistro = PhoneCards.initialDistro(root.detectedDistro);

    // A re-check that resolves the feature asks to be dismissed. A guide left
    // standing over an empty list reads as the install having failed, and the
    // list is the same binding the rows are drawn from, so nothing else has to
    // notice that the probes answered.
    onDependenciesChanged: if (root.visible && root.dependencies.length === 0)
        root.closeRequested();

    // A scrim that takes the click, so a click anywhere outside the card
    // dismisses the guide rather than reaching the cards behind it.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.closeRequested()

        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colScrim
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - Appearance.spacing.space200, 420)
        height: Math.min(parent.height - Appearance.spacing.space200,
                         cardColumn.implicitHeight + Appearance.spacing.space200 * 2)
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer2Base

        // The card is not the scrim. Without an area of its own every click
        // inside it falls through to the dismissal below.
        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            id: cardColumn
            anchors {
                fill: parent
                margins: Appearance.spacing.space200
            }
            spacing: Appearance.spacing.space150

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.spacing.space125

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: "build"
                    fill: 1
                    iconSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.headerTitle
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer2
                    elide: Text.ElideRight
                }

                IconButton {
                    buttonIcon: "close"
                    buttonSize: 32
                    // The tonal plate stays: this close sits ON the popup's
                    // layer2 header, so a flat one would have nothing to
                    // stand against.
                    colBackground: Appearance.colors.colLayer3
                    colBackgroundHover: Appearance.colors.colLayer3Hover
                    colRipple: Appearance.colors.colLayer3Active
                    colText: Appearance.colors.colOnLayer3
                    onClicked: root.closeRequested()
                }
            }

            StyledText {
                Layout.fillWidth: true
                // What the list is for, spelled out: the rows below are the
                // packages this machine is missing, and the feature stays off
                // until they are in. Without this line the guide reads as a
                // bare distro picker.
                text: Translation.tr("These packages are missing, so this feature cannot run yet. Pick your distribution, run the commands, then re-check.")
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.spacing.space50

                Repeater {
                    model: PhoneCards.distroPills()

                    // The shell's filter chip: one choice of many, drawn the
                    // way every other single-choice chip row in the shell is.
                    delegate: FilterChip {
                        id: pill
                        required property var modelData

                        // A distro's name is its own; nothing to translate.
                        label: pill.modelData.label
                        toggled: root.selectedDistro === pill.modelData.key
                        onClicked: root.selectedDistro = pill.modelData.key
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    visible: PhoneCards.knownDistro(root.detectedDistro)
                    text: Translation.tr("Detected: %1").arg(root.detectedDistro)
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
            }

            StyledFlickable {
                id: dependencyScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                // The card sizes itself off this column's implicit height, and
                // a Flickable reports 0 for its own: without a preferred height
                // here the fill wins against nothing, the list is laid out at
                // 0px and the guide shows only its header, the distro pills and
                // the Re-check button - every command and every description
                // present and invisible. This is the row list's real height, and
                // fillHeight still lets it shrink when the card hits the panel.
                Layout.preferredHeight: dependencyColumn.implicitHeight
                contentHeight: dependencyColumn.implicitHeight
                clip: true

                ColumnLayout {
                    id: dependencyColumn
                    width: dependencyScroll.width
                    spacing: Appearance.spacing.space100

                    // Nothing to show is a state the guide can be in: opened
                    // before the probes have answered, or re-checked into
                    // cleanliness. Saying so keeps the card from reading as an
                    // unlabelled distro picker.
                    StyledText {
                        Layout.fillWidth: true
                        visible: root.dependencies.length === 0
                        text: Translation.tr("Nothing is missing right now. The checks may still be running - re-check to see.")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.WordWrap
                    }

                    Repeater {
                        model: root.dependencies

                        delegate: Rectangle {
                            id: dependencyRow
                            required property var modelData

                            readonly property string command: PhoneCards.commandFor(dependencyRow.modelData, root.selectedDistro)

                            Layout.fillWidth: true
                            Layout.preferredHeight: dependencyBody.implicitHeight + Appearance.spacing.space125 * 2
                            radius: Appearance.rounding.normal
                            color: Appearance.colors.colLayer3

                            ColumnLayout {
                                id: dependencyBody
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: Appearance.spacing.space125
                                    rightMargin: Appearance.spacing.space125
                                }
                                spacing: Appearance.spacing.space75

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Appearance.spacing.space100

                                    MaterialSymbol {
                                        Layout.alignment: Qt.AlignTop
                                        text: "error"
                                        fill: 1
                                        iconSize: Appearance.font.pixelSize.large
                                        color: Appearance.colors.colError
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: Appearance.spacing.space25

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: dependencyRow.modelData.name
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.DemiBold
                                            color: Appearance.colors.colOnLayer3
                                            wrapMode: Text.WordWrap
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: dependencyRow.modelData.description
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: Appearance.colors.colSubtext
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: commandRow.implicitHeight + Appearance.spacing.space75 * 2
                                    visible: dependencyRow.command.length > 0
                                    radius: Appearance.rounding.small
                                    color: Appearance.colors.colLayer4

                                    RowLayout {
                                        id: commandRow
                                        anchors {
                                            left: parent.left
                                            right: parent.right
                                            verticalCenter: parent.verticalCenter
                                            leftMargin: Appearance.spacing.space100
                                            rightMargin: Appearance.spacing.space75
                                        }
                                        spacing: Appearance.spacing.space75

                                        // Every executable line, not just the
                                        // first: a block that installs, loads
                                        // and persists the module has to read
                                        // as three steps on screen, because
                                        // that is what the copy yields.
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: Appearance.spacing.space25

                                            Repeater {
                                                model: PhoneCards.commandLines(dependencyRow.command)

                                                delegate: StyledText {
                                                    required property string modelData

                                                    Layout.fillWidth: true
                                                    text: modelData
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    font.family: Appearance.font.family.monospace
                                                    color: Appearance.colors.colOnLayer4
                                                    elide: Text.ElideRight
                                                    maximumLineCount: 1
                                                }
                                            }
                                        }

                                        IconButton {
                                            id: copyButton
                                            property bool copied: false

                                            buttonIcon: copyButton.copied ? "check" : "content_copy"
                                            buttonSize: 32
                                            iconFill: 1
                                            colBackground: Appearance.colors.colSurfaceContainerHighest
                                            colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                                            colRipple: Appearance.colors.colSurfaceContainerHighestActive
                                            colText: copyButton.copied ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer4
                                            tooltip: Translation.tr("Copy the install command")
                                            onClicked: {
                                                Quickshell.execDetached(PhoneCards.copyArgv(dependencyRow.command));
                                                copyButton.copied = true;
                                                copiedTimer.restart();
                                            }

                                            Timer {
                                                id: copiedTimer
                                                interval: 1500
                                                onTriggered: copyButton.copied = false
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.spacing.space100

                StyledText {
                    Layout.fillWidth: true
                    text: root.installerAvailable
                        ? Translation.tr("Run the installer and answer the prompts in its terminal, then re-check.")
                        : Translation.tr("After installing, re-check to verify.")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                }

                RippleButton {
                    Layout.preferredHeight: Appearance.font.pixelSize.huge + Appearance.spacing.space100
                    visible: root.installerAvailable
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colRipple: Appearance.colors.colPrimaryActive
                    // The host runs it; this only asks. The terminal is not a
                    // formality: the script needs a password and prints a
                    // per-distro build's progress, so it has to be somewhere a
                    // person can read and answer.
                    onClicked: root.installRequested()

                    contentItem: RowLayout {
                        spacing: Appearance.spacing.space50

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: "terminal"
                            fill: 1
                            iconSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnPrimary
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            text: Translation.tr("Run installer")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                }

                RippleButton {
                    Layout.preferredHeight: Appearance.font.pixelSize.huge + Appearance.spacing.space100
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimaryContainer
                    colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                    colRipple: Appearance.colors.colPrimaryContainerActive
                    onClicked: root.recheckRequested()

                    contentItem: RowLayout {
                        spacing: Appearance.spacing.space50

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: "refresh"
                            fill: 1
                            iconSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            text: Translation.tr("Re-check")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                    }
                }
            }
        }
    }
}
