import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * The frame every Phone sub-page is rooted on: a title bar with a back
 * affordance and whatever the page puts under it.
 *
 * The page does not own its own lifetime. `Phone.qml` hosts exactly one of
 * these at a time in an overlay Loader keyed on a string id, slides it in,
 * and pops it on `back()` or on Escape - so a page is a plain Item that
 * says what it is called and raises one signal, and nothing about the
 * overlay, the travel or the key handling is spelled a second time per
 * page.
 */
Item {
    id: root

    property string title: ""
    // Raised by the back affordance; Phone.qml pops the overlay. Escape is
    // the host's, not the page's - a page that handled it would have to be
    // focused, and the pages are not all focusable.
    signal back()
    // Raised by a page whose feature has unmet dependencies. Phone.qml owns
    // the guide and fills the tab with it; a page that drew its own would
    // have to reach outside its own column to be readable.
    signal openInstallGuideRequested(string feature, string title)
    // Raised by a page whose feature is missing the adb half of the link -
    // which is a different page from the one asking, and the asking page has
    // no business knowing what the tab does with it.
    signal openAdbPageRequested()

    default property alias content: contentHolder.data
    // A page's own trailing header controls, in a row after the title. The
    // alias is to `data`, so a page assigns them as children of that row.
    property alias headerActions: headerTrailing.data

    ColumnLayout {
        anchors.fill: parent
        spacing: Appearance.spacing.space100

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.space100

            IconButton {
                id: backButton
                buttonIcon: "arrow_back"
                buttonSize: 40
                colText: Appearance.colors.colOnLayer2
                tooltip: Translation.tr("Back")
                onClicked: root.back()
            }

            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.title
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnLayer2
            }

            RowLayout {
                id: headerTrailing
                Layout.alignment: Qt.AlignVCenter
                spacing: Appearance.spacing.space50
            }
        }

        // The content slot is a LAYOUT, because every page states its size
        // with Layout.* - its own header says so - and those attached
        // properties are inert in anything that is not one. As a plain Item
        // this slot left each page's root column at its IMPLICIT height:
        // measured on the Contacts page at 73px inside an 836px slot, so the
        // region under the search row was handed 0 and the list drew nothing
        // while reporting 2 rows and 110px of content.
        ColumnLayout {
            id: contentHolder
            Layout.fillWidth: true
            Layout.fillHeight: true
            // The page owns the rhythm between its own rows; this adds none.
            spacing: 0
        }
    }
}
