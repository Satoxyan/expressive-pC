import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarLeft.phone
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

Item {
    id: root
    required property var scopeRoot
    property int sidebarPadding: 10
    anchors.fill: parent
    property bool aiChatEnabled: Config.options.policies.ai !== 0
    property bool translatorEnabled: Config.options.sidebar.translator.enable
    property bool animeEnabled: Config.options.policies.weeb !== 0
    property bool animeCloset: Config.options.policies.weeb === 2
    property bool mediaEnabled: Config.options.sidebar.media.enable
    property bool footballEnabled: Config.options.sidebar.football.enable
    property bool phoneEnabled: Config.options.sidebar.phone.enable

    readonly property var featurePages: [
        ...(root.aiChatEnabled ? [{"key": "ai", "icon": "neurology", "name": Translation.tr("Intelligence")}] : []),
        ...(root.translatorEnabled ? [{"key": "translator", "icon": "translate", "name": Translation.tr("Translator")}] : []),
        ...(root.mediaEnabled ? [{"key": "media", "icon": "music_note", "name": Translation.tr("Media")}] : []),
        ...(root.footballEnabled ? [{"key": "sports", "icon": "sports", "name": Translation.tr("Sports")}] : []),
        ...(root.phoneEnabled ? [{"key": "phone", "icon": "smartphone", "name": Translation.tr("Phone")}] : []),
        ...((root.animeEnabled && !root.animeCloset) ? [{"key": "anime", "icon": "bookmark_heart", "name": Translation.tr("Anime")}] : [])
    ]
    readonly property var pageKeys: ["home", ...root.featurePages.map(page => page.key)]
    property string currentKey: "home"
    // Jeda sebelum halaman tujuan bounce-in, dihitung saat pindah halaman.
    property int nextDelay: 0
    readonly property int currentIndex: Math.max(0, root.pageKeys.indexOf(root.currentKey))
    readonly property var currentPage: root.featurePages.find(page => page.key === root.currentKey) ?? null
    property bool restored: false

    // Header "kertas dari printer": isinya memakai headerKey yang tertinggal
    // sebentar dari currentKey, supaya header lama sempat slide keluar dulu
    // sebelum diganti header baru yang slide masuk.
    property string headerKey: "home"
    property real headerOffset: 0
    property real headerOpacity: 1
    readonly property var headerPage: root.featurePages.find(page => page.key === root.headerKey) ?? null
    readonly property real animSpeed: Math.max(0.5, Config.options.settings.animationSpeed ?? 1)

    // Lama animasi keluar sebuah halaman, untuk menyelaraskan jeda masuk.
    function pageOutMs(key) {
        const slot = pageStack.children.find(child => child.pageKey === key)
        return slot ? slot.outMs : 0
    }

    function goTo(key) {
        if (root.pageKeys.indexOf(key) < 0) key = "home"
        if (key !== root.currentKey) {
            // Dihitung sekarang, saat nilainya masih segar (contentExitMs home
            // bergantung pada jumlah kartu yang bisa berubah).
            root.nextDelay = root.pageOutMs(root.currentKey) + 30
        }
        root.currentKey = key
        if (Config.options.sidebar.leftRememberPage) Config.options.sidebar.leftLastPage = key
    }

    function step(delta) {
        const next = (root.currentIndex + delta + root.pageKeys.length) % root.pageKeys.length
        root.goTo(root.pageKeys[next])
    }

    function focusActiveItem() {
        const slot = pageStack.children.find(child => child.current === true)
        slot?.item?.forceActiveFocus()
    }

    Component.onCompleted: {
        const saved = Config.options.sidebar.leftLastPage
        if (Config.options.sidebar.leftRememberPage && root.pageKeys.indexOf(saved) >= 0) root.currentKey = saved
        root.restored = true
    }

    onPageKeysChanged: {
        if (root.restored && root.pageKeys.indexOf(root.currentKey) < 0) root.currentKey = "home"
    }

    onCurrentKeyChanged: headerAnim.restart()

    SequentialAnimation {
        id: headerAnim
        // Keluar: lembaran lama naik masuk ke celah.
        NumberAnimation {
            target: root; property: "headerOffset"
            to: -40; duration: 120 / root.animSpeed; easing.type: Easing.InCubic
        }
        NumberAnimation { target: root; property: "headerOpacity"; to: 0; duration: 60 / root.animSpeed }
        // Ganti isi saat tak terlihat, lalu lembaran baru turun keluar celah.
        ScriptAction { script: root.headerKey = root.currentKey }
        ParallelAnimation {
            NumberAnimation {
                target: root; property: "headerOffset"
                to: 0; duration: 300 / root.animSpeed; easing.type: Easing.OutCubic
            }
            NumberAnimation { target: root; property: "headerOpacity"; to: 1; duration: 200 / root.animSpeed }
        }
    }

    Keys.onPressed: (event) => {
        if (event.modifiers === Qt.ControlModifier) {
            if (event.key === Qt.Key_PageDown) {
                root.step(1)
                event.accepted = true;
            }
            else if (event.key === Qt.Key_PageUp) {
                root.step(-1)
                event.accepted = true;
            }
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: sidebarPadding
        }
        spacing: 6

        // Slot header: clip supaya judul/tombol seolah keluar dari celah.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            clip: true
            visible: root.headerKey !== "home"

            RowLayout {
                width: parent.width
                height: parent.height
                y: root.headerOffset
                opacity: root.headerOpacity
                spacing: 8

                RippleButton {
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    colRipple: Appearance.colors.colSecondaryContainerActive
                    onClicked: root.goTo("home")
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "arrow_back"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }

                MaterialSymbol {
                    text: root.headerPage?.icon ?? ""
                    fill: 1
                    iconSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.headerPage?.name ?? ""
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer0
                    elide: Text.ElideRight
                }

                Repeater {
                    model: root.featurePages.filter(page => page.key !== root.headerKey)
                    delegate: RippleButton {
                        required property var modelData
                        implicitWidth: 36
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.full
                        onClicked: root.goTo(modelData.key)
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData.icon
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colSubtext
                        }
                        StyledToolTip { text: modelData.name }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1

            Item { // Content pages
                id: pageStack
                anchors.fill: parent
                clip: true
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: pageStack.width
                        height: pageStack.height
                        radius: Appearance.rounding.normal
                    }
                }

                component PageSlot: SidebarPop {
                    id: slot
                    required property string pageKey
                    property bool enabledPage: true
                    property Component page: null
                    property bool lingering: false
                    readonly property bool current: root.currentKey === pageKey
                    readonly property bool isHome: pageKey === "home"
                    readonly property alias item: loader.item
                    // Lama bounce-out halaman ini, dipakai halaman berikutnya
                    // untuk menunda bounce-in. Home keluar lewat kartu-kartunya.
                    readonly property int outMs: isHome
                        ? (slot.item?.contentExitMs ?? 600)
                        : slot.exitMs

                    anchors.fill: parent
                    active: current
                    // Halaman lama tetap tampil selama bounce-out-nya; halaman
                    // baru disembunyikan (waiting) sampai animasi itu selesai,
                    // jadi keduanya tidak pernah tampil bersamaan.
                    visible: (current && !waiting) || lingering
                    enterDelay: root.nextDelay
                    minScale: isHome ? 1 : 0.9
                    travelX: 0
                    travelY: isHome ? 0 : 36
                    fade: !isHome
                    // Tanpa stagger: keluarnya halaman lama dan masuknya yang
                    // baru sudah diurutkan lewat enterDelay.
                    animIndex: 0

                    onCurrentChanged: {
                        if (!current) {
                            lingering = true
                            lingerTimer.restart()
                        }
                    }

                    Timer {
                        id: lingerTimer
                        interval: slot.outMs + 30
                        onTriggered: slot.lingering = false
                    }

                    Loader {
                        id: loader
                        anchors.fill: parent
                        active: slot.enabledPage
                        sourceComponent: slot.page
                        // Kartu home menunggu halaman benar-benar tampil, jadi
                        // animasinya tidak habis di balik `waiting`.
                        onLoaded: if (slot.isHome) item.active = Qt.binding(() => slot.current && !slot.waiting)
                    }
                }

                PageSlot { pageKey: "home"; page: home }
                PageSlot { pageKey: "ai"; enabledPage: root.aiChatEnabled; page: aiChat }
                PageSlot { pageKey: "translator"; enabledPage: root.translatorEnabled; page: translator }
                PageSlot { pageKey: "media"; enabledPage: root.mediaEnabled; page: media }
                PageSlot { pageKey: "sports"; enabledPage: root.footballEnabled; page: football }
                PageSlot { pageKey: "phone"; enabledPage: root.phoneEnabled; page: phone }
                PageSlot { pageKey: "anime"; enabledPage: root.animeEnabled && !root.animeCloset; page: anime }
            }
        }

        Component {
            id: home
            SidebarHomePage {
                pages: root.featurePages
                onPageRequested: key => root.goTo(key)
            }
        }
        Component {
            id: aiChat
            AiChat {}
        }
        Component {
            id: translator
            Translator {}
        }
        Component {
            id: media
            SidebarPlayerControl {}
        }
        Component {
            id: football
            FootballPage {}
        }
        Component {
            id: phone
            Phone {}
        }
        Component {
            id: anime
            Anime {}
        }
    }
}
