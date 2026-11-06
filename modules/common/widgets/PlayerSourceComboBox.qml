pragma ComponentBehavior: Bound
import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions

// Pemilih sumber media: daftar bus Mpris yang benar-benar hidup, dan memilih
// salah satunya berarti menyuruh shell membaca bus itu. Bentuknya sama dengan
// pemilih provider lyric supaya keduanya boleh duduk sebaris.
StyledComboBoxSearch {
    id: root

    // Palet tempat pemilih ini duduk; kartu yang warnanya ikut art mengirim
    // punya sendiri.
    property var colors: Appearance.colors
    property color fg: colors.colOnLayer0
    // Judul lagu di belakang nama player berguna di kartu Media dashboard, yang
    // hanya menampilkan lyric. Di tempat judul itu sudah terbaca besar (kartu
    // player, sidebarLeft) ia cuma memakan tempat, jadi call site boleh melepasnya.
    property bool showTrackTitle: true
    // Defaultnya kotak ini bening sampai disentuh: di kartu yang menampilkan art
    // ia harus terbaca sebagai bagian dari kartu, bukan sebagai tombol. Baris
    // kontrol sidebarLeft bukan tempat itu — di sana pemilih ini berdiri di
    // samping tombol volume dan harus terlihat sebagai kotak yang sama, jadi
    // call site boleh memintanya selalu ada.
    property bool solidBox: false

    readonly property var players: Array.from(MprisController.players)
    readonly property int activeIndex: players.findIndex(p => p === MprisController.activePlayer)
    readonly property color solid: Qt.rgba(root.colors.colLayer1.r, root.colors.colLayer1.g, root.colors.colLayer1.b, 1)

    visible: players.length > 1
    popupAbove: true
    // Badge chevron yang terpisah cuma masuk selama kotaknya bening: ia satu-
    // satunya bagian yang boleh berubah warna saat ditekan. Begitu solidBox
    // mewarnai chip-nya, badge dengan warna yang sama cuma memecah tombol jadi
    // dua segmen, jadi kotak ini kembali jadi satu pill seperti tombol volume.
    splitIndicator: !root.solidBox
    textRole: "displayName"
    model: players.map(p => ({
        displayName: root.showTrackTitle
            ? `${p.identity ?? p.desktopEntry ?? Translation.tr("Unknown")} · ${p.trackTitle || "—"}`
            : `${p.identity ?? p.desktopEntry ?? Translation.tr("Unknown")}`,
        icon: "music_note"
    }))

    function syncIndex() {
        root.currentIndex = root.activeIndex;
    }
    onActiveIndexChanged: Qt.callLater(syncIndex)
    onModelChanged: Qt.callLater(syncIndex)
    onCountChanged: Qt.callLater(syncIndex)
    Component.onCompleted: syncIndex()

    // Kotaknya baru ada saat disentuh atau saat daftarnya terbuka. Di luar itu
    // yang tersisa hanya teks dan ikonnya, jadi pemilih ini terbaca sebagai
    // bagian dari kartu, bukan sebagai tombol. Kecuali kalau solidBox diminta.
    colBackground: root.solidBox
        ? ColorUtils.transparentize(root.colors.colSecondaryContainer, 0.7)
        : (root.popup.visible ? root.colors.colSecondaryContainer : "transparent")
    colBackgroundHover: root.colors.colSecondaryContainerHover
    colBackgroundActive: root.colors.colSecondaryContainerActive
    // Teksnya tinggal di kartu yang tembus pandang, di atas art yang sama dengan
    // lirik, jadi ia ikut warna foreground kartu — bukan warna teks container
    // yang cuma benar saat kotaknya ikut tampil.
    colText: root.solidBox ? root.colors.colOnSecondaryContainer : root.fg
    colAccent: root.colors.colPrimary
    colOnAccent: root.colors.colOnPrimary
    colPopup: root.solid
    colSelected: root.colors.colSecondaryContainer
    colSelectedHover: root.colors.colSecondaryContainerHover
    colSelectedActive: root.colors.colSecondaryContainerActive
    colOnSelected: root.colors.colOnSecondaryContainer
    colItemHover: root.colors.colSecondaryContainerHover
    colItemActive: root.colors.colSecondaryContainerActive
    colOnItem: root.colors.colOnLayer1
    colSearch: root.colors.colLayer0
    colOnSearch: root.colors.colOnLayer1
    colSearchHint: root.colors.colSubtext
}
