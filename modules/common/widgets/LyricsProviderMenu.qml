pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Menu pemilih provider lyric. Satu tempat untuk pill LyricsProviderSelector
// dan klik-kanan tombol toggle lirik di sidebarLeft.
Popup {
    id: root
    required property var blendedColors
    property real sizeScale: 1
    // true: tepi kiri menu sejajar tepi kiri anchor (default: kanan).
    property bool alignLeft: false
    // Kapan popup terakhir tertutup; lihat toggle di show().
    property real closedAt: 0
    onVisibleChanged: if (!visible) root.closedAt = Date.now()

    // Tampil di atas `anchor`: kanan sejajar (di-clamp ke lebar wadah),
    // atau kiri sejajar bila alignLeft.
    function show(anchor) {
        // Tombol pemilih ditekan lagi = tutup.
        if (root.visible) { root.close(); return }
        // CloseOnPressOutside sudah menutup popup tepat sebelum downAction
        // tombol pemilih jalan, jadi `visible` pasti false di jalur itu:
        // yang menandai toggle adalah penutupan yang baru terjadi. Jejaknya
        // dihapus supaya klik berikutnya langsung membuka lagi.
        if (root.closedAt > 0 && Date.now() - root.closedAt < 300) {
            root.closedAt = 0
            return
        }

        LyricsService.probeProviders()
        // Posisi dihitung relatif parent popup, bukan koordinat window:
        // di layer surface (sidebar/lock) koordinat window bikin menu
        // terlempar jauh dari tombolnya.
        const p = root.parent
        const tl = anchor.mapToItem(p, 0, 0)
        const box = anchor.parent
        if (root.alignLeft) {
            root.x = tl.x
        } else {
            const right = tl.x + anchor.width
            const boxRight = box ? box.mapToItem(p, box.width, 0).x : right
            root.x = Math.min(right, boxRight - 8) - root.width
        }
        root.open()
        root.y = tl.y - root.height - 6
    }

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
                        // Highlight baris (hover dan saat ditekan) nyaris
                        // kotak: tingginya 24px, radius 12 membuat pilnya
                        // lepas dari bentuk baris.
                        buttonRadius: 4 * root.sizeScale
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
                            // Lencana duo: provider ini punya baris suara
                            // kedua (align "end"). Duduk tepat di depan
                            // lencana sinkronisasi, sehingga keduanya terbaca
                            // satu keterangan: duo + per kata / per baris.
                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter
                                iconSize: Appearance.font.pixelSize.smallest * root.sizeScale
                                fill: 1
                                visible: capInfo !== null && capInfo.ok === true
                                    && capInfo.duet === true
                                text: "music_note_2"
                                color: ColorUtils.applyAlpha(root.blendedColors.colOnLayer0, 0.6)
                            }
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
                            root.close()
                            // Tutup karena memilih, bukan karena toggle:
                            // jangan tinggalkan jejak penutupan, supaya klik
                            // berikutnya langsung membuka daftar lagi.
                            root.closedAt = 0
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
                text: "music_note_2"
                color: ColorUtils.applyAlpha(root.blendedColors.colOnLayer0, 0.6)
            }
            StyledText {
                text: "duet"
                font.pixelSize: Appearance.font.pixelSize.smallest * root.sizeScale
                color: ColorUtils.applyAlpha(root.blendedColors.colOnLayer0, 0.6)
            }
            MaterialSymbol {
                iconSize: Appearance.font.pixelSize.smallest * root.sizeScale
                fill: 1
                text: "graphic_eq"
                color: ColorUtils.applyAlpha(root.blendedColors.colOnLayer0, 0.6)
            }
            StyledText {
                text: "word"
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
                text: "line"
                font.pixelSize: Appearance.font.pixelSize.smallest * root.sizeScale
                color: ColorUtils.applyAlpha(root.blendedColors.colOnLayer0, 0.6)
            }
        }
    }
}
