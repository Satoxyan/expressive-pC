import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * The two cards that lead out of the tab: Contacts and Android Apps.
 *
 * Each says what it holds rather than only what it is - the contacts count
 * as the vCard monitor reports it, and whether this machine's scrcpy is new
 * enough for App Mode - because "Contacts >" tells the user nothing they
 * did not already know, and a card that opens onto an empty page is a
 * wasted trip. While the monitor has not answered, the subtitle says so
 * rather than claiming zero.
 *
 * The Apps card answers that second problem twice: it says when nothing is on
 * ADB, and opens the page that can put something there instead of the page
 * that can only report it.
 *
 * The pages themselves are the other half of the Phone tab's split (see
 * Phone.qml's interface note); the card only names the id.
 */
Item {
    id: root

    property real appear: 1

    // The id Phone.qml resolves into an overlay page.
    signal openPage(string id)

    component NavCard: RippleButton {
        id: card
        property string glyph
        property string title
        property string subtitle
        property color colGlyphBackground: Appearance.colors.colPrimaryContainer
        property color colGlyph: Appearance.colors.colOnPrimaryContainer

        // Both cards get half the row, whatever their text happens to say. A
        // fillWidth item's share is still computed from its PREFERRED width,
        // which for these is the implicit width of the longest title and
        // subtitle - so one long description quietly grew its own box and left
        // the other one short. `preferredWidth: 0` is the same cure the
        // equalizer's chip row uses.
        Layout.fillWidth: true
        Layout.preferredWidth: 0

        implicitHeight: 58
        buttonRadius: Appearance.rounding.normal
        colBackground: Appearance.colors.colLayer3
        colBackgroundHover: Appearance.colors.colLayer3Hover
        colRipple: Appearance.colors.colLayer3Active

        // The shell's catalogue row shape. The leading visual is a glyph on
        // a tonal disc rather than a bare symbol, so it goes through
        // `iconComponent`; the title's ink is stated because these cards sit
        // on layer 3.
        contentItem: CatalogueRow {
            anchors {
                fill: parent
                leftMargin: Appearance.spacing.space150
                rightMargin: Appearance.spacing.space100
            }
            rowSpacing: Appearance.spacing.space125

            iconComponent: Component {
                Rectangle {
                    implicitWidth: 34
                    implicitHeight: 34
                    radius: Appearance.rounding.full
                    color: card.colGlyphBackground

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: card.glyph
                        iconSize: Appearance.font.pixelSize.larger
                        color: card.colGlyph
                    }
                }
            }

            title: card.title
            titleFont.pixelSize: Appearance.font.pixelSize.small
            titleColor: Appearance.colors.colOnLayer3
            titleFillsWidth: true
            titleElides: true
            description: card.subtitle
            descriptionWraps: false

            affordance: [
                MaterialSymbol {
                    text: "chevron_right"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colSubtext
                }
            ]
        }
    }

    implicitHeight: cardRow.implicitHeight

    RowLayout {
        id: cardRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Appearance.spacing.space100

        NavCard {
            id: contactsCard
            glyph: "contacts"
            colGlyphBackground: Appearance.colors.colPrimaryContainer
            colGlyph: Appearance.colors.colOnPrimaryContainer
            title: Translation.tr("Contacts")
            subtitle: {
                if (!PhoneContacts.ready) return Translation.tr("Syncing…");
                const count = PhoneContacts.count;
                return count === 1
                    ? Translation.tr("1 contact")
                    : Translation.tr("%1 contacts").arg(String(count));
            }
            onClicked: root.openPage("contacts")
        }

        NavCard {
            id: appsCard
            glyph: "apps"
            colGlyphBackground: Appearance.colors.colSecondaryContainer
            colGlyph: Appearance.colors.colOnSecondaryContainer
            title: Translation.tr("Android Apps")
            // App Mode has exactly one way to fail before it starts, and it is
            // not on this page: nothing on ADB is a list that cannot be read.
            // So the card says which link is down and opens the page that owns
            // the fix, rather than a page whose whole content is a notice
            // pointing at it. `PhoneDeps.ready` is waited for because every
            // flag there starts false - a trip in the first frames of a session
            // must not be read as a refusal.
            readonly property bool linkDown: PhoneScrcpy.appModeSupported
                && PhoneDeps.ready && !PhoneDeps.adbDevice
            subtitle: {
                if (!PhoneScrcpy.available) return Translation.tr("scrcpy is not installed");
                if (!PhoneScrcpy.appModeSupported) return Translation.tr("Requires scrcpy 4.0+");
                if (appsCard.linkDown) return Translation.tr("No device on ADB");
                return Translation.tr("scrcpy App Mode");
            }
            onClicked: root.openPage(appsCard.linkDown ? "adb" : "apps")
        }
    }
}
