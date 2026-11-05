pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

// Pemilih provider lyric yang sama persis dengan yang ada di kartu Media
// dashboard: kotaknya bening sampai disentuh atau dibuka, tiap baris membawa
// penanda bentuk lirik yang bisa diberikan provider itu untuk lagu ini, dan di
// paling bawah ada keterangan cara membaca penanda tersebut.
//
// Semua permukaan (kartu player, sidebarLeft, widget desktop, dashboard) memakai
// komponen ini supaya jawabannya hanya ditulis satu kali.
StyledComboBoxSearch {
    id: root

    // Palet tempat pemilih ini duduk. Kartu yang warnanya ikut art mengirim
    // blendedColors-nya; sisanya cukup pakai palet global.
    property var colors: Appearance.colors
    // Warna teks saat kotaknya bening: pemilih ini berdiri di atas art yang sama
    // dengan liriknya, jadi ia ikut foreground kartu, bukan teks container yang
    // baru benar kalau kotaknya ikut tampil.
    property color fg: colors.colOnLayer0
    // Lagu yang pemilih ini baca. Tiap player punya track sendiri, jadi label
    // "auto · <provider>" dan penanda tiap baris tidak boleh ikut track yang
    // kebetulan sedang dilihat shell.
    property var track: LyricsService.active

    readonly property var providerNames: ["auto"].concat(
        Config.options.lyrics.providers.split(",")
            .map(s => s.trim())
            .filter(s => s.length > 0))
    readonly property int activeIndex: {
        const wanted = LyricsService.preferredProvider.length > 0
            ? LyricsService.preferredProvider
            : "auto";
        const at = providerNames.findIndex(name => name === wanted);
        return at >= 0 ? at : 0;
    }
    readonly property var caps: root.track?.providerInfo ?? ({})
    // Popup memakai lapisan warna yang solid: colLayer1 palet blended punya
    // alpha, dan daftar yang tembus pandang membuat barisnya tidak terbaca.
    readonly property color solid: Qt.rgba(root.colors.colLayer1.r, root.colors.colLayer1.g, root.colors.colLayer1.b, 1)

    textRole: "displayName"
    popupAbove: true
    splitIndicator: true
    // Provider yang tahu dirinya tidak punya apa-apa untuk lagu ini diredupkan,
    // tapi tetap ada di daftar — persis seperti menu provider yang lama. Timeout
    // ("unknown") dibiarkan normal: tidak menjawab bukan bukti tidak ada lyric.
    model: root.providerNames.map(name => {
        const cap = root.caps[name] ?? null;
        const trailing = [];
        if (cap?.ok === true) {
            if (cap.duet === true) trailing.push("music_note_2");
            trailing.push(cap.wordByWord ? "graphic_eq" : "notes");
        }
        return {
            displayName: name === "auto" ? Translation.tr("Auto") : name,
            icon: name === "auto" ? "auto_awesome" : "lyrics",
            trailing: trailing,
            dim: cap !== null && cap.ok === false && cap.unknown !== true
        };
    })
    popupLegend: [
        { icon: "music_note_2", label: "duet" },
        { icon: "graphic_eq", label: "word" },
        { icon: "notes", label: "line" }
    ]

    // Pill yang lama selalu menyebut provider mana yang benar-benar melayani
    // lagu ini. Saat mode auto, namanya ditempel di belakang "Auto".
    displayText: {
        const label = root.currentIndex >= 0
            ? (root.model[root.currentIndex]?.displayName ?? "")
            : "";
        const served = root.track?.providedBy ?? "";
        if (LyricsService.preferredProvider.length === 0 && served.length > 0)
            return `${label} · ${served}`;
        return label;
    }

    Connections {
        target: root.popup
        function onOpened() { root.track?.probeProviders() }
    }
    onActivated: index => {
        const name = root.providerNames[index];
        LyricsService.preferredProvider = name === "auto" ? "" : name;
        root.track?.probeProviders();
        root.track?.restartLyrics();
    }

    function syncIndex() {
        root.currentIndex = root.activeIndex;
    }
    onActiveIndexChanged: Qt.callLater(syncIndex)
    onModelChanged: Qt.callLater(syncIndex)
    onCountChanged: Qt.callLater(syncIndex)
    onTrackChanged: Qt.callLater(syncIndex)
    Component.onCompleted: syncIndex()

    // Kotaknya baru ada saat disentuh atau saat daftarnya terbuka. Di luar itu
    // yang tersisa hanya teks dan ikonnya, jadi pemilih ini terbaca sebagai
    // bagian dari kartu, bukan sebagai tombol.
    colBackground: root.popup.visible
        ? root.colors.colSecondaryContainer
        : "transparent"
    colBackgroundHover: root.colors.colSecondaryContainerHover
    colBackgroundActive: root.colors.colSecondaryContainerActive
    colText: root.fg
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
