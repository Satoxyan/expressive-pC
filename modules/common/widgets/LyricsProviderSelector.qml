pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Pemilih provider lyric: pill (label provider aktif / "auto") + menu
// LyricsProviderMenu di atasnya. Dipakai PlayerContent (media controls,
// lock, sidebarRight, desktop widget) dan dashboard tab Media.
// SidebarLeft memakai menunya saja, lewat klik kanan tombol toggle lirik.
Item {
    id: root
    // Palet art-blended milik pemakai (Player.blendedColors dkk).
    required property var blendedColors
    // Pengali ukuran untuk wadah besar (mis. dashboard tab Media).
    property real sizeScale: 1

    implicitWidth: pillRow.implicitWidth + 16 * sizeScale
    implicitHeight: 20 * sizeScale

    readonly property string providerLabel: LyricsService.providedBy.length > 0
        ? LyricsService.providedBy
        : (LyricsService.preferredProvider.length > 0 ? LyricsService.preferredProvider : "auto")

    RippleButton {
        id: providerButton
        anchors.fill: parent
        padding: 0
        buttonRadius: height / 2
        colBackground: ColorUtils.transparentize(root.blendedColors.colSecondaryContainer, 1)
        colBackgroundHover: root.blendedColors.colSecondaryContainerHover
        colRipple: root.blendedColors.colSecondaryContainerActive
        contentItem: Item {
            implicitWidth: pillRow.implicitWidth
            implicitHeight: pillRow.implicitHeight
            RowLayout {
                id: pillRow
                anchors.centerIn: parent
                spacing: 3 * root.sizeScale
                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: root.providerLabel
                    font.pixelSize: (Appearance.font.pixelSize.smallest + 2) * root.sizeScale
                    color: root.blendedColors.colOnSecondaryContainer
                }
                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    iconSize: Appearance.font.pixelSize.smallest * root.sizeScale
                    fill: 1
                    text: "expand_more"
                    color: root.blendedColors.colOnSecondaryContainer
                }
            }
        }
        downAction: () => providerMenu.show(root)
    }

    LyricsProviderMenu {
        id: providerMenu
        blendedColors: root.blendedColors
        sizeScale: root.sizeScale
    }
}
