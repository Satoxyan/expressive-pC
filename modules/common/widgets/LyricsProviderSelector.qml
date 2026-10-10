pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Pemilih provider lyric: pill (label provider aktif / "auto") + dropdown
// 4 baris terlihat + scroll + legenda badge (graphic_eq = per word,
// notes = per line). Dipakai PlayerContent (media controls, lock,
// sidebarRight, desktop widget), sidebarLeft SidebarPlayerControl, dan
// dashboard tab Media.
Item {
    id: root
    // Palet art-blended milik pemakai (Player.blendedColors dkk).
    required property var blendedColors
    // Pengali ukuran untuk wadah besar (mis. dashboard tab Media).
    property real sizeScale: 1
    // Lebar wadah untuk clamp menu; default = parent (langsung child wadah).
    readonly property real containerWidth: parent ? parent.width : width

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
        downAction: () => {
            LyricsService.probeProviders()
            // x/y Popup relatif parent (Item ini) — bebas window; dihitung
            // dari koordinat window justru membuat popup terlempar ratusan
            // px di sidebar/lock (parent jauh dari atas window). Align kanan:
            // sudut kanan popup sejajar sudut kanan pill, di-clamp dalam
            // wadah.
            providerPopup.x = Math.min(root.width, root.containerWidth - root.x - 8) - providerPopup.width
            providerPopup.open()
            providerPopup.y = -(providerPopup.height + 6)
        }
    }

    Popup {
        id: providerPopup
        padding: 6 * root.sizeScale
        closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape
        background: Rectangle {
            // Resep persis kartu player (lihat Player.qml): colLayer0 dengan
            // alpha dipaksa 1 — solid, tidak tembus pandang.
            color: ColorUtils.applyAlpha(root.blendedColors.colLayer0, 1)
            radius: Appearance.rounding.small
        }
        // 4 baris terlihat, sisanya scroll. Tinggi ditentukan konstanta
        // (bukan dari id child) supaya pengukuran Popup selalu valid.
        contentItem: Item {
            implicitWidth: 148 * root.sizeScale
            implicitHeight: (4 * 24 + 3 * 2 + 4 + 16) * root.sizeScale
            Flickable {
                id: providerFlick
                anchors.top: parent.top
                anchors.left: parent.left
                width: 148 * root.sizeScale
                height: (4 * 24 + 3 * 2) * root.sizeScale
                clip: true
                contentWidth: 148 * root.sizeScale
                contentHeight: providerColumn.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: providerColumn
                    width: 148 * root.sizeScale
                    spacing: 2 * root.sizeScale
                    Repeater {
                        model: ["auto"].concat(Config.options.lyrics.providers.split(",")
                            .map(s => s.trim()).filter(s => s.length > 0))
                        delegate: RippleButton {
                            required property string modelData
                            implicitWidth: 148 * root.sizeScale
                            implicitHeight: 24 * root.sizeScale
                            padding: 0
                            // Ripple dimatikan: popup menutup tepat saat tekan,
                            // ripple tak sempat fade dan meninggalkan highlight
                            // basi saat daftar dibuka lagi.
                            rippleEnabled: false
                            // Hasil probe track berjalan; null = belum ada data.
                            readonly property var capInfo: LyricsService.providerInfo[modelData] ?? null
                            // Provider tak punya lyric utk track ini: redupkan.
                            // Timeout ("unknown") dibiarkan normal — ketiadaan
                            // jawaban bukan bukti tak ada lyric.
                            opacity: (capInfo && !capInfo.ok && !capInfo.unknown) ? 0.4 : 1
                            colBackground: ColorUtils.transparentize(root.blendedColors.colLayer0, 1)
                            colBackgroundHover: root.blendedColors.colSecondaryContainerHover
                            colRipple: root.blendedColors.colSecondaryContainerActive
                            contentItem: RowLayout {
                                spacing: 6 * root.sizeScale
                                StyledText {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: modelData
                                    color: root.blendedColors.colOnLayer0
                                    font.pixelSize: Appearance.font.pixelSize.small * root.sizeScale
                                }
                                // Pengisi: mendorong badge & centang ke kanan.
                                Item { Layout.fillWidth: true }
                                // Badge sinkronisasi: graphic_eq = word-by-word,
                                // notes = per baris. Tak tampil bila tak ada data.
                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignVCenter
                                    iconSize: Appearance.font.pixelSize.smallest * root.sizeScale
                                    fill: 1
                                    visible: capInfo !== null && capInfo.ok === true
                                    text: (capInfo?.wordByWord ?? false) ? "graphic_eq" : "notes"
                                    color: ColorUtils.applyAlpha(root.blendedColors.colOnLayer0, 0.6)
                                }
                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignVCenter
                                    iconSize: Appearance.font.pixelSize.small * root.sizeScale
                                    fill: 1
                                    text: "check"
                                    color: root.blendedColors.colPrimary
                                    visible: LyricsService.preferredProvider === modelData
                                        || (modelData === "auto" && LyricsService.preferredProvider.length === 0)
                                }
                            }
                            downAction: () => {
                                LyricsService.preferredProvider = modelData === "auto" ? "" : modelData
                                LyricsService.restartLyrics()
                                providerPopup.close()
                            }
                        }
                    }
                }
            }
            // Indikator scroll subtle: hanya saat daftar bisa di-scroll.
            Rectangle {
                anchors.right: providerFlick.right
                anchors.rightMargin: 2 * root.sizeScale
                visible: providerFlick.contentHeight > providerFlick.height
                width: 5 * root.sizeScale
                radius: 2.5 * root.sizeScale
                height: Math.max(16 * root.sizeScale, providerFlick.height * providerFlick.visibleArea.ySize)
                y: (providerFlick.height - height) * providerFlick.visibleArea.position
                color: ColorUtils.applyAlpha(root.blendedColors.colOnLayer0, 0.35)
            }
            // Legenda badge: cara baca ikon di kanan tiap baris.
            RowLayout {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.leftMargin: 4 * root.sizeScale
                anchors.bottomMargin: 3 * root.sizeScale
                spacing: 4 * root.sizeScale
                MaterialSymbol {
                    iconSize: Appearance.font.pixelSize.smallest * root.sizeScale
                    fill: 1
                    text: "graphic_eq"
                    color: ColorUtils.applyAlpha(root.blendedColors.colOnLayer0, 0.6)
                }
                StyledText {
                    text: "per word"
                    font.pixelSize: Appearance.font.pixelSize.smallest * root.sizeScale
                    color: ColorUtils.applyAlpha(root.blendedColors.colOnLayer0, 0.6)
                }
                MaterialSymbol {
                    iconSize: Appearance.font.pixelSize.smallest * root.sizeScale
                    fill: 1
                    text: "notes"
                    color: ColorUtils.applyAlpha(root.blendedColors.colOnLayer0, 0.6)
                }
                StyledText {
                    text: "per line"
                    font.pixelSize: Appearance.font.pixelSize.smallest * root.sizeScale
                    color: ColorUtils.applyAlpha(root.blendedColors.colOnLayer0, 0.6)
                }
            }
        }
    }
}
