pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ComboBox {
    id: root

    property string buttonIcon: ""
    property real buttonRadius: height / 2
    property color colBackground: Appearance.colors.colSecondaryContainer
    property color colBackgroundHover: Appearance.colors.colSecondaryContainerHover
    property color colBackgroundActive: Appearance.colors.colSecondaryContainerActive
    property color colText: Appearance.colors.colOnSecondaryContainer
    property color colAccent: Appearance.colors.colPrimary
    property color colOnAccent: Appearance.colors.colOnPrimary
    property color colPopup: Appearance.m3colors.m3surfaceContainerHigh
    property color colSelected: Appearance.colors.colSecondaryContainer
    property color colSelectedHover: Appearance.colors.colSecondaryContainerHover
    property color colSelectedActive: Appearance.colors.colSecondaryContainerActive
    property color colOnSelected: Appearance.colors.colOnSecondaryContainer
    property color colItemHover: Appearance.colors.colLayer3Hover
    property color colItemActive: Appearance.colors.colLayer3Active
    property color colOnItem: Appearance.colors.colOnLayer3
    property color colSearch: Appearance.colors.colLayer2
    property color colOnSearch: Appearance.colors.colOnLayer1
    property color colSearchHint: Appearance.colors.colSubtext
    property bool popupAbove: false
    property string searchText: ""
    property bool splitIndicator: false
    // Baris penjelasan di paling bawah popup: pasangan ikon dan kata, dibaca
    // sebagai keterangan ikon `trailing` milik tiap baris. Kosong = tidak ada.
    property var popupLegend: []

    // Pengali seluruh metrik, untuk tempat yang lebih sempit dari halaman
    // setting (kartu lyric di sidebar/lock/widget: 0.6 bikin kotaknya setinggi
    // kontrol di sekitarnya). Setiap angka dikalikan per-metrik, bukan lewat
    // `transform: Scale`, supaya teks tetap tajam dan area klik tetap benar.
    // Default 1 = persis seperti dulu, jadi call site settings tidak berubah.
    property real sizeScale: 1
    readonly property real rowHeight: 42 * root.sizeScale
    // Satu batas untuk dua pemakai (tinggi popup dan tinggi list): kalau keduanya
    // boleh berbeda, list terpotong atau popup kebablasan.
    readonly property real maxPopupHeight: Math.max(150, 320 * root.sizeScale)
    // Teks dan glyph tidak dikurangi sekasar kotaknya: di skala 0.6 angka mentah
    // 15px jadi 9px dan tidak lagi terbaca. Skala huruf diredam setengah, jadi
    // kotak 24px masih memuat label 12px seperti pill lyric yang dulu.
    readonly property real fontScale: 0.5 + 0.5 * root.sizeScale

    onSizeScaleChanged: if (popup.visible) popup.close()

    // A row may carry two extras besides its label: `trailing`, the symbols to
    // read at the right end, and `dim`, which says the entry is there but is not
    // offering anything. Both ride along the filter so a searched list keeps them.
    readonly property var filteredItems: {
        const query = root.searchText.toLowerCase()
        const source = root.model ?? []
        const result = []
        for (let i = 0; i < source.length; i++) {
            const item = source[i]
            const isObject = typeof item === "object"
            const label = isObject ? (item[root.textRole] ?? "") : String(item)
            if (query.length === 0 || label.toLowerCase().includes(query))
                result.push({
                    realIndex: i,
                    label: label,
                    icon: isObject ? (item.icon ?? "") : "",
                    trailing: isObject ? (item.trailing ?? []) : [],
                    dim: isObject ? (item.dim === true) : false
                })
        }
        return result
    }
    readonly property int visibleCount: root.filteredItems.length

    // Popup dulu meniru lebar tombolnya persis. Begitu tombol boleh memeluk
    // teksnya sendiri (kartu player), tiruan itu jadi terlalu sempit untuk baris
    // terpanjang, jadi daftar diukur lebih dulu dan popup tidak boleh kurang
    // selebar itu.
    TextMetrics {
        id: labelMetrics
        font.family: Appearance.font.family.main
        font.pixelSize: Appearance.font.pixelSize.small * root.fontScale
    }
    readonly property real popupNeededWidth: {
        const iconW = Appearance.font.pixelSize.larger * root.fontScale
        const trailW = Appearance.font.pixelSize.normal * root.fontScale
        const items = root.filteredItems
        let best = 0
        for (let i = 0; i < items.length; i++) {
            labelMetrics.text = items[i].label
            let w = labelMetrics.advanceWidth + 24 * root.sizeScale
            if (items[i].icon.length > 0) w += iconW + 8 * root.sizeScale
            const n = items[i].trailing.length
            if (n > 0) w += 8 * root.sizeScale + n * trailW + (n - 1) * 6 * root.sizeScale
            if (w > best) best = w
        }
        return Math.round(best + 16 * root.sizeScale)
    }

    function pick(realIndex) {
        root.activated(realIndex)
        root.popup.close()
    }

    implicitHeight: 40 * root.sizeScale
    // ComboBox mengurut implicitWidth dari popup juga, padahal popup meniru lebar
    // tombol: tanpa baris ini, tombol yang sedang memeluk teksnya akan melebar
    // begitu popup pertama kali terbuka lalu terkunci selebar baris terpanjang.
    implicitWidth: buttonContent.implicitWidth + leftPadding + rightPadding
    Layout.fillWidth: true

    background: Rectangle {
        anchors.fill: parent
        anchors.rightMargin: root.splitIndicator ? root.indicator.width + 2 * root.sizeScale : 0
        topLeftRadius: root.buttonRadius
        bottomLeftRadius: root.buttonRadius
        topRightRadius: root.splitIndicator ? Appearance.rounding.unsharpenmore : root.buttonRadius
        bottomRightRadius: topRightRadius
        color: (root.down && !root.popup.visible) ? root.colBackgroundActive : root.hovered ? root.colBackgroundHover : root.colBackground

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            cursorShape: Qt.PointingHandCursor
        }
    }

    indicator: Item {
        x: root.width - width
        width: root.splitIndicator ? badge.width : chevron.width + 32 * root.sizeScale
        height: root.height

        ComboChevronBadge {
            id: badge
            visible: root.splitIndicator
            iconSize: Appearance.font.pixelSize.larger * root.fontScale
            anchors.right: parent.right
            height: parent.height
            open: root.popup.visible
            colClosed: (root.down && !root.popup.visible) ? root.colBackgroundActive : root.hovered ? root.colBackgroundHover : root.colBackground
            colOpen: root.colAccent
            colIconClosed: root.colText
            colIconOpen: root.colOnAccent
        }

        MaterialSymbol {
            id: chevron
            visible: !root.splitIndicator
            x: parent.width - width - 16 * root.sizeScale
            y: parent.height / 2 - height / 2
            text: "keyboard_arrow_down"
            iconSize: Appearance.font.pixelSize.larger * root.fontScale
            color: root.colText

            rotation: root.popup.visible ? 180 : 0
            Behavior on rotation {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }

    contentItem: Item {
        id: buttonContent
        // Implicit size RowLayout tidak menghitung margin anchors-nya sendiri,
        // jadi margin kiri-kanan baris ditambahkan manual; kalau tidak, teks
        // kepotong persis sebesar margin itu.
        implicitWidth: buttonLayout.implicitWidth + buttonLayout.anchors.leftMargin + buttonLayout.anchors.rightMargin
        implicitHeight: buttonLayout.implicitHeight

        RowLayout {
            id: buttonLayout
            anchors.fill: parent
            spacing: 8 * root.sizeScale
            anchors.leftMargin: 16 * root.sizeScale
            // The style already takes the indicator out of the content item's
            // width (`rightPadding: padding + indicator.width + spacing`, Basic
            // ComboBox.qml:22), so this row sits right against the badge and only
            // owes it a gap. Naming the indicator's width here again would spend
            // the same 48px twice and leave a dead strip at the label's right.
            anchors.rightMargin: (root.splitIndicator ? 12 : 16) * root.sizeScale

            Loader {
                Layout.alignment: Qt.AlignVCenter
                active: root.buttonIcon.length > 0 || !!(root.currentIndex >= 0 && typeof root.model[root.currentIndex] === 'object' && root.model[root.currentIndex]?.icon)
                visible: active
                sourceComponent: MaterialSymbol {
                    text: {
                        if (root.currentIndex >= 0 && typeof root.model[root.currentIndex] === 'object' && root.model[root.currentIndex]?.icon) {
                            return root.model[root.currentIndex].icon;
                        }
                        return root.buttonIcon;
                    }
                    iconSize: Appearance.font.pixelSize.larger * root.fontScale
                    color: root.colText
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                color: root.colText
                font.pixelSize: Appearance.font.pixelSize.small * root.fontScale
                text: root.displayText
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    Component {
        id: entryDelegate

        ItemDelegate {
            id: itemDelegate
            required property var modelData
            required property int index
            readonly property bool selected: root.currentIndex === itemDelegate.modelData.realIndex

            width: ListView.view ? ListView.view.width : root.width
            implicitHeight: root.rowHeight
            onClicked: root.pick(itemDelegate.modelData.realIndex)

            property color color: {
                if (itemDelegate.selected) {
                    if (itemDelegate.down) return root.colSelectedActive;
                    if (itemDelegate.hovered) return root.colSelectedHover;
                    return root.colSelected;
                } else {
                    if (itemDelegate.down) return root.colItemActive;
                    if (itemDelegate.hovered) return root.colItemHover;
                    return ColorUtils.transparentize(Appearance.colors.colLayer3);
                }
            }
            property color colText: itemDelegate.selected ? root.colOnSelected : root.colOnItem

            // An entry that has nothing to give is kept in the list and pushed
            // back, the way the lyric provider menu did it: the row is still
            // there to be read, it just does not look like a choice.
            opacity: itemDelegate.modelData.dim ? 0.4 : 1

            background: Rectangle {
                anchors.fill: parent
                anchors.bottomMargin: 2 * root.sizeScale
                // Highlight baris dibaca sebagai blok, bukan pil: radius 12 pada
                // kotak setinggi 40 membuat tiap baris terlihat seperti tombol
                // terpisah, bukan sebagai salah satu baris daftar. 8 masih
                // melunakkan sudutnya tanpa mem bulat-bulatkan barisnya.
                radius: Appearance.rounding.verysmall * root.sizeScale
                color: itemDelegate.color
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    cursorShape: Qt.PointingHandCursor
                }
            }

            // Kotak highlight menggantung 2px di atas baris berikutnya, jadi
            // tengahnya bukan tengah slot baris. Isi digeser ke atas dengan
            // padding atas lebih kecil daripada bawah, supaya teks duduk di
            // tengah kotaknya sendiri, bukan setengah baris ke bawah.
            topPadding: 4 * root.sizeScale
            bottomPadding: 6 * root.sizeScale

            contentItem: RowLayout {
                spacing: 8 * root.sizeScale
                anchors.leftMargin: 12 * root.sizeScale
                anchors.rightMargin: 12 * root.sizeScale

                Loader {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredHeight: Appearance.font.pixelSize.larger * root.fontScale
                    active: itemDelegate.modelData.icon.length > 0
                    visible: active
                    sourceComponent: Item {
                        implicitWidth: icon.implicitWidth
                        implicitHeight: Appearance.font.pixelSize.larger * root.fontScale
                        MaterialSymbol {
                            id: icon
                            anchors.centerIn: parent
                            text: itemDelegate.modelData.icon
                            iconSize: Appearance.font.pixelSize.larger * root.fontScale
                            color: itemDelegate.colText
                        }
                    }
                }

                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.small * root.fontScale
                    Layout.fillWidth: true
                    Layout.preferredHeight: Appearance.font.pixelSize.larger * root.fontScale
                    color: itemDelegate.colText
                    text: itemDelegate.modelData.label
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }

                // What the entry offers, read as symbols at the right end. They
                // sit next to a label of pixelSize.small, so they are drawn a
                // step larger: symbols read lighter than glyphs of the same size.
                RowLayout {
                    spacing: 6 * root.sizeScale
                    Repeater {
                        model: itemDelegate.modelData.trailing
                        delegate: MaterialSymbol {
                            required property var modelData
                            Layout.alignment: Qt.AlignVCenter
                            text: modelData
                            iconSize: Appearance.font.pixelSize.normal * root.fontScale
                            fill: 1
                            color: ColorUtils.applyAlpha(itemDelegate.colText, 0.6)
                        }
                    }
                }
            }
        }
    }

    popup: Popup {
        y: root.popupAbove ? -height - 4 * root.sizeScale : root.height + 4 * root.sizeScale
        width: Math.max(root.width, root.popupNeededWidth)
        // Combo yang memeluk teks duduk di sisi kanan, jadi popup yang lebih
        // lebar darinya tumbuh ke kiri, bukan keluar layar. Saat lebarnya sama,
        // hasil rumus ini 0 — persis seperti dulu.
        x: root.popupAbove ? root.width - width : 0
        clip: true
        // Tinggi legenda dihitung sebagai konstanta, bukan dari id child, supaya
        // pengukuran Popup sudah benar sejak pertama kali dibuka.
        readonly property real legendHeight: root.popupLegend.length > 0 ? 24 * root.sizeScale : 0
        height: Math.round(Math.min(
            searchField.implicitHeight + 12 * root.sizeScale + (root.visibleCount * root.rowHeight) + legendHeight + topPadding + bottomPadding,
            root.maxPopupHeight
        ))
        padding: 8 * root.sizeScale

        onVisibleChanged: {
            if (visible) {
                searchField.forceActiveFocus()
                Qt.callLater(() => {
                    const position = root.filteredItems.findIndex(entry => entry.realIndex === root.currentIndex)
                    if (position < 0) return
                    // Yang di paling atas atau paling bawah tidak perlu
                    // disengah: ListView.Center untuk item pertama malah
                    // meninggalkan offset setengah baris begitu tinggi list
                    // berubah (mis. saat baris legenda ikut tampil), jadi baris
                    // pertama terpotong.
                    if (position === 0) listView.positionViewAtBeginning()
                    else if (position === root.filteredItems.length - 1) listView.positionViewAtEnd()
                    else listView.positionViewAtIndex(position, ListView.Center)
                })
            } else {
                root.searchText = ""
                searchField.text = ""
            }
        }

        enter: Transition {
            PropertyAnimation {
                properties: "opacity"; to: 1
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }
        exit: Transition {
            PropertyAnimation {
                properties: "opacity"; to: 0
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        background: Item {
            StyledRectangularShadow { target: popupBackground }
            Rectangle {
                id: popupBackground
                anchors.fill: parent
                radius: Appearance.rounding.normal
                color: root.colPopup
            }
        }

        contentItem: ColumnLayout {
            spacing: 4 * root.sizeScale

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: searchField.implicitHeight + 8 * root.sizeScale
                radius: Appearance.rounding.small
                color: root.colSearch

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 4 * root.sizeScale
                    spacing: 6 * root.sizeScale

                    MaterialSymbol {
                        Layout.leftMargin: 6 * root.sizeScale
                        text: "search"
                        iconSize: Appearance.font.pixelSize.larger * root.fontScale
                        color: root.colSearchHint
                    }

                    TextField {
                        id: searchField
                        ContextMenu.menu: StyledTextEditMenu { editor: searchField }
                        Layout.fillWidth: true
                        placeholderText: "Search..."
                        placeholderTextColor: root.colSearchHint
                        color: root.colOnSearch
                        background: null
                        font.family: Appearance.font.family.main
                        font.pixelSize: Appearance.font.pixelSize.normal * root.fontScale
                        onTextChanged: root.searchText = text
                        Keys.onDownPressed: listView.incrementCurrentIndex()
                        Keys.onUpPressed: listView.decrementCurrentIndex()
                        Keys.onReturnPressed: {
                            const entry = root.filteredItems[Math.max(listView.currentIndex, 0)]
                            if (entry) root.pick(entry.realIndex)
                        }
                    }

                    MaterialSymbol {
                        visible: searchField.text.length > 0
                        text: "close"
                        iconSize: Appearance.font.pixelSize.normal * root.fontScale
                        color: root.colSearchHint
                        Layout.rightMargin: 6 * root.sizeScale
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                searchField.text = ""
                                searchField.forceActiveFocus()
                            }
                        }
                    }
                }
            }

            StyledListView {
                id: listView
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, root.maxPopupHeight - root.popup.topPadding - root.popup.bottomPadding - searchField.implicitHeight - 12 * root.sizeScale - root.popup.legendHeight)
                clip: true
                spacing: 0
                popin: false
                animateAppearance: false
                model: root.popup.visible ? root.filteredItems : null
                delegate: entryDelegate
            }

            // Keterangan ikon di paling bawah popup: tiap pasangan dibaca
            // "ikon ini artinya kata ini". Sedikit di bawah teks baris supaya
            // tetap terbaca sebagai keterangan, bukan sebagai pilihan, dan
            // ditempatkan di tengah agar tidak menempel ke salah satu tepi.
            RowLayout {
                visible: root.popupLegend.length > 0
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredHeight: visible ? root.popup.legendHeight : 0
                spacing: 10 * root.sizeScale
                Repeater {
                    model: root.popupLegend
                    delegate: RowLayout {
                        required property var modelData
                        spacing: 4 * root.sizeScale
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: modelData.icon
                            iconSize: Appearance.font.pixelSize.small * root.fontScale
                            fill: 1
                            color: ColorUtils.applyAlpha(root.colOnItem, 0.6)
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            text: modelData.label
                            font.pixelSize: Appearance.font.pixelSize.smallie * root.fontScale
                            color: ColorUtils.applyAlpha(root.colOnItem, 0.6)
                        }
                    }
                }
            }
        }
    }
}