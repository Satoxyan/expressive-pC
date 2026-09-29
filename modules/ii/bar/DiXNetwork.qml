import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

// Network, in two columns. As "download": the speed right now over a live curve on the left; on the right the
// files arriving and who is pulling the traffic, or, when nothing is downloading, the latest downloads. As
// "zerotier": the network, its address and a switch on the left; the peers on the right.
ColumnLayout {
    id: xnet
    required property Item di
    spacing: 0
    implicitWidth: xnet.wantedWidth
    readonly property real wantedWidth: 532

    // Which of the two this instance is, fixed at creation: the island's id moves on while this one fades out
    property string openedAs: xnet.di.expandedId
    readonly property bool ztMode: xnet.openedAs === "zerotier"
    // While the ZeroTier page is up, keep its on/off state fresh (nothing polls it otherwise)
    Component.onCompleted: {
        xnet.openedAs = xnet.openedAs
        if (xnet.ztMode) IslandEvents.ztViewers++
    }
    Component.onDestruction: if (xnet.ztMode) IslandEvents.ztViewers = Math.max(0, IslandEvents.ztViewers - 1)

    component SectionLabel: StyledText {
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.weight: Font.DemiBold
        color: Appearance.colors.colOnLayer0
        opacity: 0.6
        elide: Text.ElideRight
    }

    component Chip: Rectangle {
        id: chip
        property string icon: ""
        property string value: ""
        property string label: ""
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: 40
        radius: 12
        color: Appearance.colors.colLayer1

        RowLayout {
            anchors {
                fill: parent
                leftMargin: 10
                rightMargin: 8
            }
            spacing: 8

            MaterialSymbol {
                text: chip.icon
                iconSize: 18
                fill: 1
                color: Appearance.colors.colPrimary
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: -1
                StyledText {
                    Layout.fillWidth: true
                    text: chip.value
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: chip.label
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnLayer1
                    opacity: 0.55
                    elide: Text.ElideRight
                }
            }
        }
    }

    component EmptyState: ColumnLayout {
        property string icon: ""
        property string title: ""
        property string hint: ""
        spacing: 2

        MaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            text: parent.icon
            iconSize: 30
            color: Appearance.colors.colOnLayer0
            opacity: 0.35
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: parent.title
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer0
            opacity: 0.6
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: 240
            horizontalAlignment: Text.AlignHCenter
            text: parent.hint
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colOnLayer0
            opacity: 0.45
            wrapMode: Text.Wrap
        }
    }

    // A row of a list: icon, two lines and a value on the right
    component ListRow: Rectangle {
        id: row
        property string icon: ""
        property string iconSource: ""
        property string title: ""
        property string subtitle: ""
        property string value: ""
        property bool strong: false
        property var onTap: null
        Layout.fillWidth: true
        implicitHeight: 36
        radius: 12
        color: rowMouse.containsMouse && row.onTap ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1

        Behavior on color {
            ColorAnimation { duration: IslandMotion.micro }
        }

        RowLayout {
            anchors {
                fill: parent
                leftMargin: 10
                rightMargin: 10
            }
            spacing: 8

            Item {
                implicitWidth: 18
                implicitHeight: 18

                Image {
                    id: rowImage
                    anchors.fill: parent
                    visible: row.iconSource !== "" && status === Image.Ready
                    source: row.iconSource
                    sourceSize.width: 36
                    sourceSize.height: 36
                    asynchronous: true
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: !rowImage.visible
                    text: row.icon
                    iconSize: 17
                    fill: 1
                    color: row.strong ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: -2
                StyledText {
                    Layout.fillWidth: true
                    text: row.title
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: row.subtitle !== ""
                    text: row.subtitle
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.features: { "tnum": 1 }
                    color: Appearance.colors.colOnLayer1
                    opacity: 0.55
                    elide: Text.ElideRight
                }
            }
            StyledText {
                visible: row.value !== ""
                text: row.value
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
                color: row.strong ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
            }
        }

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            enabled: row.onTap !== null
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: row.onTap()
        }
    }

    Loader {
        Layout.fillWidth: true
        active: !xnet.ztMode
        visible: active
        sourceComponent: downloadPage
    }
    Loader {
        Layout.fillWidth: true
        active: xnet.ztMode
        visible: active
        sourceComponent: zeroTierPage
    }

    // ───────────── Download / network activity ─────────────
    Component {
        id: downloadPage

        RowLayout {
            id: dl
            spacing: 20

            readonly property bool active: IslandEvents.downloadActive
            readonly property var sources: IslandEvents.downloadSources
            readonly property real maxRx: Math.max(1, ...dl.sources.map(s => s.rx))
            readonly property string topName: IslandEvents.downloadTop?.name ?? ""
            property double now: Date.now()

            // Speed samples taken while the view is open (the service reads the counters every second meanwhile),
            // started from what the service already kept of the current burst
            property var samples: IslandEvents.downloadHistory.map(v => ({ rx: v, tx: -1 }))
            readonly property int windowSize: 40
            readonly property real graphMax: Math.max(64 * 1024, ...dl.samples.map(s => Math.max(s.rx, s.tx)))

            function addSample() {
                dl.samples = [...dl.samples, { rx: IslandEvents.downloadRate, tx: IslandEvents.uploadRate }].slice(-dl.windowSize)
            }

            // The downloads that finished (files) and the traffic bursts, newest first
            readonly property var recent: {
                const files = (IslandEvents.eventLog ?? []).filter(e => e.kind === "download").map(e => ({
                    kind: "file", time: e.time, title: e.title, bytes: e.subtitle, path: e.action?.path ?? ""
                }))
                const bursts = (IslandEvents.recentDownloads ?? []).map(b => ({
                    kind: "burst", time: b.time, seconds: b.seconds, bytes: IslandEvents.formatBytes(b.bytes, false),
                    title: b.sources.map(s => s.label).join(", ") || Translation.tr("Traffic spike")
                }))
                return files.concat(bursts).sort((a, b) => b.time - a.time).slice(0, 3)
            }

            Binding {
                target: IslandEvents
                property: "downloadWatch"
                value: true
                restoreMode: Binding.RestoreValue
            }

            Connections {
                target: IslandEvents
                function onPrevNetTimeChanged() {
                    if (!IslandEvents.fakeNet) dl.addSample()
                }
                function onDownloadHistoryChanged() {
                    if (IslandEvents.fakeNet) dl.addSample()
                }
            }

            Timer {
                interval: 1000
                running: dl.active
                repeat: true
                onTriggered: dl.now = Date.now()
            }

            function duration(ms) {
                const s = Math.max(0, Math.round(ms / 1000))
                return s < 60 ? `${s} s` : `${Math.floor(s / 60)} min ${s % 60} s`
            }
            function splitRate(bytes) {
                const parts = IslandEvents.formatBytes(bytes, true).split(" ")
                return { number: parts[0], unit: parts[1] ?? "" }
            }

            // Left: now
            ColumnLayout {
                Layout.fillWidth: false
                Layout.preferredWidth: 236
                Layout.maximumWidth: 236
                Layout.alignment: Qt.AlignTop
                spacing: 0

                RowLayout {
                    id: headRow
                    Layout.fillWidth: true
                    spacing: 6
                    DiCascade { target: headRow; index: 0 }

                    SectionLabel {
                        Layout.fillWidth: true
                        text: dl.active
                            ? (IslandEvents.downloadSince > 0
                                ? Translation.tr("Downloading · %1").arg(dl.duration(dl.now - IslandEvents.downloadSince))
                                : Translation.tr("Downloading"))
                            : Translation.tr("Network now")
                        font.features: { "tnum": 1 }
                    }
                    // Log of every burst
                    Rectangle {
                        implicitWidth: 24
                        implicitHeight: 24
                        radius: 12
                        color: logMouse.containsMouse ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
                        Behavior on color {
                            ColorAnimation { duration: IslandMotion.micro }
                        }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "history"
                            iconSize: 14
                            color: Appearance.colors.colOnLayer1
                        }
                        MouseArea {
                            id: logMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Qt.openUrlExternally(`file://${IslandEvents.downloadLogPath}`)
                        }
                    }
                }

                RowLayout {
                    id: rateRow
                    Layout.topMargin: 2
                    spacing: 6
                    DiCascade { target: rateRow; index: 1 }

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: "arrow_downward"
                        iconSize: 22
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        text: dl.splitRate(IslandEvents.downloadRate).number
                        font.pixelSize: 38
                        font.weight: Font.DemiBold
                        font.features: { "tnum": 1 }
                        color: Appearance.colors.colOnLayer0
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignBaseline
                        text: dl.splitRate(IslandEvents.downloadRate).unit
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer0
                        opacity: 0.6
                    }
                }

                StyledText {
                    id: rateSub
                    Layout.fillWidth: true
                    Layout.topMargin: -2
                    text: [
                        `↑ ${IslandEvents.formatBytes(IslandEvents.uploadRate, true)}`,
                        dl.samples.length > 1 ? Translation.tr("peak %1").arg(IslandEvents.formatBytes(dl.graphMax, true)) : ""
                    ].filter(Boolean).join(" · ")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.features: { "tnum": 1 }
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.6
                    elide: Text.ElideRight
                    DiCascade { target: rateSub; index: 2 }
                }

                // Recent speed: download filled, upload as a thin line; drawn from the left as it opens
                Item {
                    id: graph
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    implicitHeight: 58
                    DiCascade { target: graph; index: 3 }

                    DiSpring {
                        id: graphReveal
                        stiffness: 50
                        dampingRatio: 1
                        epsilon: 0.002
                    }
                    Timer {
                        interval: 220
                        running: true
                        onTriggered: graphReveal.target = 1
                    }

                    readonly property real reveal: graphReveal.value
                    onRevealChanged: graphCanvas.requestPaint()
                    Connections {
                        target: dl
                        function onSamplesChanged() { graphCanvas.requestPaint() }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 12
                        color: Appearance.colors.colLayer1
                    }

                    Canvas {
                        id: graphCanvas
                        anchors {
                            fill: parent
                            topMargin: 8
                            bottomMargin: 2
                        }
                        readonly property color downColor: Appearance.colors.colPrimary
                        readonly property color upColor: Appearance.colors.colTertiary
                        onDownColorChanged: requestPaint()
                        onWidthChanged: requestPaint()

                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.reset()
                            const list = dl.samples
                            if (list.length < 2 || graph.reveal <= 0) return
                            // Spread over the width until the window fills, then it scrolls
                            const n = Math.max(12, list.length)
                            const dx = width / (n - 1)
                            const offset = 0
                            const yOf = v => height - Math.max(0, Math.min(1, v / dl.graphMax)) * (height - 2) - 1
                            ctx.save()
                            ctx.beginPath()
                            ctx.rect(0, 0, width * graph.reveal, height)
                            ctx.clip()

                            const path = key => {
                                ctx.beginPath()
                                let started = false
                                let lastX = 0
                                for (let i = 0; i < list.length; i++) {
                                    const v = list[i][key]
                                    if (v < 0) continue
                                    const x = (offset + i) * dx
                                    const y = yOf(v)
                                    if (!started) {
                                        ctx.moveTo(x, y)
                                        started = true
                                    } else {
                                        // Midpoint smoothing keeps spikes readable without sharp corners
                                        const px = (offset + i - 1) * dx
                                        const py = yOf(list[i - 1][key])
                                        ctx.quadraticCurveTo(px, py, (px + x) / 2, (py + y) / 2)
                                    }
                                    lastX = x
                                }
                                return started ? lastX : -1
                            }

                            const endX = path("rx")
                            if (endX >= 0) {
                                const lastY = yOf(list[list.length - 1].rx)
                                ctx.lineTo(endX, lastY)
                                ctx.strokeStyle = downColor
                                ctx.lineWidth = 2
                                ctx.lineCap = "round"
                                ctx.stroke()
                                ctx.lineTo(endX, height)
                                ctx.lineTo(offset * dx, height)
                                ctx.closePath()
                                const fill = ctx.createLinearGradient(0, 0, 0, height)
                                fill.addColorStop(0, Qt.rgba(downColor.r, downColor.g, downColor.b, 0.28))
                                fill.addColorStop(1, Qt.rgba(downColor.r, downColor.g, downColor.b, 0.02))
                                ctx.fillStyle = fill
                                ctx.fill()
                            }
                            if (path("tx") >= 0) {
                                ctx.strokeStyle = Qt.rgba(upColor.r, upColor.g, upColor.b, 0.8)
                                ctx.lineWidth = 1.5
                                ctx.stroke()
                            }
                            ctx.restore()
                        }
                    }

                    StyledText {
                        anchors.centerIn: parent
                        visible: dl.samples.length < 2
                        text: Translation.tr("Measuring…")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colOnLayer1
                        opacity: 0.5
                    }
                }

                SectionLabel {
                    id: chipsLabel
                    Layout.topMargin: 8
                    Layout.bottomMargin: 4
                    text: dl.active ? Translation.tr("This download") : Translation.tr("Since boot")
                    DiCascade { target: chipsLabel; index: 4 }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Chip {
                        id: chipA
                        DiCascade { target: chipA; index: 5 }
                        icon: dl.active ? "data_usage" : "download"
                        value: IslandEvents.formatBytes(dl.active ? IslandEvents.burstBytes : Math.max(0, IslandEvents.prevRx), false)
                        label: dl.active ? Translation.tr("Received") : Translation.tr("Received")
                    }
                    Chip {
                        id: chipB
                        DiCascade { target: chipB; index: 6 }
                        icon: dl.active ? "speed" : "upload"
                        value: dl.active ? IslandEvents.formatBytes(IslandEvents.downloadPeak, true)
                            : IslandEvents.formatBytes(Math.max(0, IslandEvents.prevTx), false)
                        label: dl.active ? Translation.tr("Peak") : Translation.tr("Sent")
                    }
                }
            }

            // Right: files and sources while downloading, the latest downloads otherwise
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.alignment: Qt.AlignTop
                spacing: 4

                SectionLabel {
                    id: filesLabel
                    visible: dl.active && IslandEvents.partialFiles.length > 0
                    text: Translation.tr("Files arriving")
                    DiCascade { target: filesLabel; index: 1 }
                }

                Repeater {
                    model: dl.active ? Math.min(1, IslandEvents.partialFiles.length) : 0

                    delegate: Rectangle {
                        id: fileRow
                        required property int index
                        readonly property var file: IslandEvents.partialFiles[fileRow.index] ?? ({ name: "", bytes: 0, total: 0, rate: 0 })
                        readonly property real progress: fileRow.file.total > 0 ? Math.max(0, Math.min(1, fileRow.file.bytes / fileRow.file.total)) : -1
                        Layout.fillWidth: true
                        Layout.bottomMargin: 6
                        implicitHeight: 52
                        radius: 12
                        color: Appearance.colors.colLayer1
                        clip: true
                        DiCascade { target: fileRow; index: 2 }

                        ColumnLayout {
                            anchors {
                                fill: parent
                                leftMargin: 10
                                rightMargin: 10
                                topMargin: 7
                                bottomMargin: 7
                            }
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                MaterialSymbol {
                                    text: "download"
                                    iconSize: 16
                                    fill: 1
                                    color: Appearance.colors.colPrimary
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: fileRow.file.name
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colOnLayer1
                                    elide: Text.ElideMiddle
                                }
                                StyledText {
                                    text: fileRow.progress >= 0 ? `${Math.round(fileRow.progress * 100)}%`
                                        : IslandEvents.formatBytes(fileRow.file.bytes, false)
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.DemiBold
                                    font.features: { "tnum": 1 }
                                    color: Appearance.colors.colPrimary
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 4
                                radius: 2
                                color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.85)

                                Rectangle {
                                    width: fileRow.progress >= 0 ? parent.width * fileRow.progress : parent.width * 0.3
                                    height: parent.height
                                    radius: 2
                                    color: Appearance.colors.colPrimary
                                    opacity: fileRow.progress >= 0 ? 1 : 0.5

                                    Behavior on width {
                                        NumberAnimation { duration: IslandMotion.medium; easing.type: Easing.OutCubic }
                                    }

                                    SequentialAnimation on x {
                                        running: fileRow.progress < 0
                                        loops: Animation.Infinite
                                        NumberAnimation { from: 0; to: fileRow.width * 0.6; duration: 1400; easing.type: Easing.InOutSine }
                                        NumberAnimation { to: 0; duration: 1400; easing.type: Easing.InOutSine }
                                    }
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: [
                                    fileRow.file.total > 0 ? `${IslandEvents.formatBytes(fileRow.file.bytes, false)} / ${IslandEvents.formatBytes(fileRow.file.total, false)}` : "",
                                    IslandEvents.formatBytes(fileRow.file.rate, true),
                                    fileRow.file.total > 0 && fileRow.file.rate > 1024
                                        ? IslandEvents.remainingTime((fileRow.file.total - fileRow.file.bytes) / fileRow.file.rate) : ""
                                ].filter(Boolean).join(" · ")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.features: { "tnum": 1 }
                                color: Appearance.colors.colOnLayer1
                                opacity: 0.6
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                // The connection itself, idle only
                ListRow {
                    id: connRow
                    Layout.bottomMargin: 4
                    visible: !dl.active
                    DiCascade { target: connRow; index: 0 }
                    icon: Network.materialSymbol
                    strong: true
                    title: Network.ethernet ? Translation.tr("Ethernet")
                        : Network.wifiStatus === "connected" ? Network.networkName : Translation.tr("Offline")
                    subtitle: [
                        Network.ethernet ? "" : (Network.wifiStatus === "connected" ? `Wi-Fi · ${Network.networkStrength}%` : ""),
                        Network.ipAddress
                    ].filter(Boolean).join(" · ")
                }

                // Latest downloads (only when idle)
                SectionLabel {
                    id: recentLabel
                    visible: !dl.active && dl.recent.length > 0
                    text: Translation.tr("Recent downloads")
                    DiCascade { target: recentLabel; index: 1 }
                }
                Repeater {
                    model: dl.active ? 0 : Math.min(dl.recent.length, dl.sources.length > 0 ? 2 : 3)

                    delegate: ListRow {
                        id: recentRow
                        required property int index
                        readonly property var entry: dl.recent[recentRow.index] ?? ({})
                        DiCascade { target: recentRow; index: 2 + recentRow.index }
                        icon: recentRow.entry.kind === "file" ? "download_done" : "swap_vert"
                        strong: recentRow.index === 0
                        title: recentRow.entry.title ?? ""
                        subtitle: [
                            Qt.formatTime(new Date(recentRow.entry.time ?? 0), "hh:mm"),
                            recentRow.entry.kind === "burst" ? dl.duration((recentRow.entry.seconds ?? 0) * 1000) : ""
                        ].filter(Boolean).join(" · ")
                        value: recentRow.entry.bytes ?? ""
                        onTap: recentRow.entry.kind === "file" && (recentRow.entry.path ?? "") !== ""
                            ? () => Qt.openUrlExternally(`file://${recentRow.entry.path.slice(0, recentRow.entry.path.lastIndexOf("/"))}`)
                            : null
                    }
                }

                // Who is using the network
                SectionLabel {
                    id: sourcesLabel
                    Layout.topMargin: (filesLabel.visible || recentLabel.visible) ? 4 : 0
                    visible: dl.active || dl.sources.length > 0
                    text: dl.active ? Translation.tr("Where it comes from") : Translation.tr("Using the network")
                    DiCascade { target: sourcesLabel; index: 3 }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: dl.active && (IslandEvents.downloadSourcesError !== "" || dl.sources.length === 0)
                    text: IslandEvents.downloadSourcesError === "missing" ? Translation.tr("Install nethogs to see where it comes from")
                        : IslandEvents.downloadSourcesError === "sudo" ? Translation.tr("nethogs needs passwordless sudo")
                        : IslandEvents.downloadSourcesError !== "" ? Translation.tr("Couldn't measure per process")
                        : Translation.tr("Identifying…")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.6
                    wrapMode: Text.Wrap
                }

                Repeater {
                    // Fewer rows when a file or the recent list already takes the room
                    model: IslandEvents.downloadSourcesError !== "" ? 0
                        : Math.min(dl.sources.length, dl.active ? (filesLabel.visible ? 2 : 3) : (dl.recent.length > 0 ? 1 : 2))

                    delegate: Item {
                        id: sourceItem
                        required property int index
                        readonly property var src: dl.sources[sourceItem.index] ?? ({ name: "unknown", rx: 0, tx: 0, pid: 0 })
                        readonly property bool unknown: sourceItem.src.name === "unknown"
                        readonly property string label: IslandEvents.sourceLabel(sourceItem.src)
                        readonly property real sessionBytes: IslandEvents.downloadTotals[sourceItem.label]?.bytes ?? 0
                        Layout.fillWidth: true
                        implicitHeight: 36
                        DiCascade { target: sourceItem; index: 4 + sourceItem.index }

                        Rectangle {
                            anchors.fill: parent
                            radius: 12
                            color: Appearance.colors.colLayer1
                            clip: true

                            // Share of the traffic as a soft fill behind the row
                            Rectangle {
                                anchors {
                                    left: parent.left
                                    top: parent.top
                                    bottom: parent.bottom
                                }
                                width: parent.width * Math.min(1, sourceItem.src.rx / dl.maxRx)
                                color: ColorUtils.transparentize(Appearance.colors.colPrimary, sourceItem.index === 0 ? 0.84 : 0.92)
                                Behavior on width {
                                    NumberAnimation { duration: IslandMotion.medium; easing.type: Easing.OutCubic }
                                }
                            }
                        }

                        RowLayout {
                            anchors {
                                fill: parent
                                leftMargin: 10
                                rightMargin: 10
                            }
                            spacing: 8

                            Item {
                                implicitWidth: 18
                                implicitHeight: 18

                                Image {
                                    id: sourceIcon
                                    anchors.fill: parent
                                    visible: !sourceItem.unknown && status === Image.Ready
                                    source: sourceItem.unknown ? "" : Quickshell.iconPath(sourceItem.src.icon ?? "", true)
                                    sourceSize.width: 36
                                    sourceSize.height: 36
                                    asynchronous: true
                                }
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    visible: !sourceIcon.visible
                                    text: sourceItem.unknown ? "lan" : "terminal"
                                    iconSize: 17
                                    color: Appearance.colors.colOnLayer1
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                spacing: -2
                                StyledText {
                                    Layout.fillWidth: true
                                    text: sourceItem.label
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colOnLayer1
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: [
                                        `↑ ${IslandEvents.formatBytes(sourceItem.src.tx, true)}`,
                                        sourceItem.sessionBytes > 0 ? `${IslandEvents.formatBytes(sourceItem.sessionBytes, false)} ${Translation.tr("downloaded")}` : "",
                                        sourceItem.src.pid > 0 ? `PID ${sourceItem.src.pid}` : ""
                                    ].filter(Boolean).join(" · ")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.features: { "tnum": 1 }
                                    color: Appearance.colors.colOnLayer1
                                    opacity: 0.55
                                    elide: Text.ElideRight
                                }
                            }
                            StyledText {
                                text: IslandEvents.formatBytes(sourceItem.src.rx, true)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                font.features: { "tnum": 1 }
                                color: sourceItem.index === 0 ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }

                // With people on the network the list above fills the column; a line is enough
                StyledText {
                    id: noRecent
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    visible: !dl.active && dl.recent.length === 0 && dl.sources.length > 0
                    text: Translation.tr("Finished downloads show up here")
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.45
                    elide: Text.ElideRight
                }

                // Browser hint, only when there is room for it
                Rectangle {
                    id: hint
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    visible: dl.active && !filesLabel.visible && hintText.text !== ""
                    implicitHeight: hintText.implicitHeight + 12
                    radius: 12
                    color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.88)
                    DiCascade { target: hint; index: 7 }

                    StyledText {
                        id: hintText
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: 10
                            rightMargin: 10
                        }
                        text: /^(chrome|chromium|brave|vesktop|code)$/.test(dl.topName)
                            ? Translation.tr("In the browser, Shift+Esc shows which tab is using the network")
                            : /^(firefox|zen|zen-bin)$/.test(dl.topName)
                                ? Translation.tr("In Firefox/Zen, about:processes shows which tab is using the network")
                                : ""
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colOnLayer0
                        wrapMode: Text.Wrap
                    }
                }

                // Nothing downloaded yet and nobody on the network
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: !dl.active && dl.recent.length === 0 && dl.sources.length === 0
                    implicitHeight: idleEmpty.implicitHeight

                    EmptyState {
                        id: idleEmpty
                        anchors.centerIn: parent
                        icon: "download_done"
                        title: Translation.tr("No downloads yet")
                        hint: Translation.tr("Finished downloads show up here")
                        DiCascade { target: idleEmpty; index: 2 }
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }
    }

    // ───────────── ZeroTier ─────────────
    Component {
        id: zeroTierPage

        RowLayout {
            id: zt
            spacing: 20

            readonly property bool up: IslandEvents.ztUp
            readonly property bool busy: IslandEvents.ztBusy
            readonly property bool risky: zt.up && IslandEvents.voiceCallActive
            readonly property color accent: zt.risky ? IslandEvents.colorAttention
                : zt.up ? IslandEvents.colorSuccess : Appearance.colors.colOnLayer0

            // What zerotier-cli reports, read while the view is open
            property var info: null
            property bool loaded: false
            readonly property bool ok: zt.info?.ok === true
            readonly property var network: (zt.info?.networks ?? [])[0] ?? null
            readonly property string address: {
                const addrs = zt.network?.addresses ?? []
                const v4 = addrs.find(a => a.indexOf(":") < 0) ?? addrs[0] ?? ""
                return v4 !== "" ? v4.split("/")[0] : IslandEvents.ztNetwork
            }
            readonly property string controller: (zt.network?.id ?? "").slice(0, 10)
            readonly property var leaves: (zt.info?.peers ?? []).filter(p => p.role === "LEAF")
                .sort((a, b) => (b.address === zt.controller) - (a.address === zt.controller) || a.latency - b.latency)
            readonly property var roots: (zt.info?.peers ?? []).filter(p => p.role !== "LEAF")
            readonly property var rootLatencies: zt.roots.map(p => p.latency).filter(l => l >= 0)

            Binding {
                target: IslandEvents
                property: "ztWatch"
                value: true
                restoreMode: Binding.RestoreValue
            }

            Process {
                id: ztRead
                command: ["python3", "-c", [
                    "import json, subprocess",
                    "def cli(*a):",
                    "    try:",
                    "        r = subprocess.run(['sudo', '-n', 'zerotier-cli', '-j', *a], capture_output=True, text=True, timeout=4)",
                    "        return json.loads(r.stdout) if r.returncode == 0 else None",
                    "    except Exception:",
                    "        return None",
                    "def stat(dev, key):",
                    "    try:",
                    "        return int(open(f'/sys/class/net/{dev}/statistics/{key}').read())",
                    "    except Exception:",
                    "        return -1",
                    "info = cli('info')",
                    "out = {'ok': info is not None, 'node': (info or {}).get('address', ''), 'version': (info or {}).get('version', ''),",
                    "       'online': (info or {}).get('online', False), 'networks': [], 'peers': []}",
                    "for n in (cli('listnetworks') or []) if info else []:",
                    "    dev = n.get('portDeviceName', '')",
                    "    out['networks'].append({'id': n.get('nwid', ''), 'name': n.get('name', ''), 'status': n.get('status', ''),",
                    "        'type': n.get('type', ''), 'addresses': n.get('assignedAddresses', []), 'rx': stat(dev, 'rx_bytes'), 'tx': stat(dev, 'tx_bytes')})",
                    "for p in (cli('listpeers') or []) if info else []:",
                    "    paths = [x for x in (p.get('paths') or []) if x.get('active')]",
                    "    best = next((x for x in paths if x.get('preferred')), paths[0] if paths else None)",
                    "    out['peers'].append({'address': p.get('address', ''), 'role': p.get('role', ''), 'latency': p.get('latency', -1),",
                    "        'version': p.get('version', ''), 'path': (best or {}).get('address', '')})",
                    "print(json.dumps(out))"
                ].join("\n")]
                stdout: StdioCollector {
                    id: ztReadOut
                    onStreamFinished: {
                        try {
                            zt.info = JSON.parse(ztReadOut.text)
                        } catch (e) {
                            zt.info = null
                        }
                        zt.loaded = true
                    }
                }
            }

            function refresh() {
                if (!ztRead.running) ztRead.running = true
            }
            Component.onCompleted: zt.refresh()
            onUpChanged: zt.refresh()

            Timer {
                interval: 5000
                running: true
                repeat: true
                onTriggered: zt.refresh()
            }

            function statusText() {
                if (zt.busy) return Translation.tr("Changing…")
                if (!zt.up) return Translation.tr("Off")
                const n = zt.network
                if (!n) return zt.info?.online ? Translation.tr("Online") : Translation.tr("Connected")
                const status = n.status === "OK" ? Translation.tr("Connected")
                    : n.status === "ACCESS_DENIED" ? Translation.tr("Not authorized")
                    : n.status === "REQUESTING_CONFIGURATION" ? Translation.tr("Joining…")
                    : n.status
                const kind = n.type === "PRIVATE" ? Translation.tr("Private") : n.type === "PUBLIC" ? Translation.tr("Public") : ""
                return [status, kind].filter(Boolean).join(" · ")
            }

            // Left: the network and the switch
            ColumnLayout {
                Layout.fillWidth: false
                Layout.preferredWidth: 236
                Layout.maximumWidth: 236
                Layout.fillHeight: true
                spacing: 0

                RowLayout {
                    id: ztHead
                    Layout.fillWidth: true
                    spacing: 10
                    DiCascade { target: ztHead; index: 0 }

                    MaterialShapeWrappedMaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        wrappedShape: zt.risky ? MaterialShape.Shape.Cookie4Sided : MaterialShape.Shape.Cookie9Sided
                        color: ColorUtils.transparentize(zt.accent, 0.78)
                        colSymbol: zt.accent
                        text: zt.busy ? "sync" : zt.up ? "vpn_lock" : "vpn_key_off"
                        iconSize: 18
                        fill: 1
                        padding: 7

                        RotationAnimator on rotation {
                            running: zt.busy
                            loops: Animation.Infinite
                            from: 0
                            to: 360
                            duration: 1200
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: -2
                        StyledText {
                            Layout.fillWidth: true
                            text: (zt.network?.name ?? "") !== "" ? zt.network.name : "ZeroTier"
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer0
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: zt.statusText()
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: zt.up && !zt.busy ? zt.accent : Appearance.colors.colOnLayer0
                            opacity: zt.up && !zt.busy ? 1 : 0.6
                            elide: Text.ElideRight
                        }
                    }
                }

                StyledText {
                    id: ipText
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    text: zt.up && zt.address !== "" ? zt.address : (zt.up ? "–" : Translation.tr("Off"))
                    font.pixelSize: 32
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: 18
                    color: zt.up ? Appearance.colors.colOnLayer0 : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.5)
                    elide: Text.ElideRight
                    DiCascade { target: ipText; index: 1 }
                }

                StyledText {
                    id: nodeText
                    Layout.fillWidth: true
                    Layout.topMargin: -2
                    text: [
                        (zt.info?.node ?? "") !== "" ? Translation.tr("Node %1").arg(zt.info.node) : "",
                        (zt.info?.version ?? "") !== "" ? `v${zt.info.version}` : ""
                    ].filter(Boolean).join(" · ") || (zt.loaded && !zt.up ? Translation.tr("Service stopped") : "")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.family: Appearance.font.family.monospace
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.55
                    elide: Text.ElideRight
                    DiCascade { target: nodeText; index: 2 }
                }

                Item { Layout.fillHeight: true; Layout.minimumHeight: 8 }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: zt.up

                    Chip {
                        id: ztRx
                        DiCascade { target: ztRx; index: 3 }
                        icon: "download"
                        value: (zt.network?.rx ?? -1) >= 0 ? IslandEvents.formatBytes(zt.network.rx, false) : "–"
                        label: Translation.tr("Received")
                    }
                    Chip {
                        id: ztTx
                        DiCascade { target: ztTx; index: 4 }
                        icon: "upload"
                        value: (zt.network?.tx ?? -1) >= 0 ? IslandEvents.formatBytes(zt.network.tx, false) : "–"
                        label: Translation.tr("Sent")
                    }
                }

                // The switch: the whole card toggles
                Rectangle {
                    id: ztSwitch
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    implicitHeight: 40
                    radius: 12
                    color: zt.risky ? ColorUtils.transparentize(IslandEvents.colorAttention, 0.8)
                        : switchMouse.containsMouse ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
                    DiCascade { target: ztSwitch; index: 5; pressed: switchMouse.pressed }

                    Behavior on color {
                        ColorAnimation { duration: IslandMotion.micro }
                    }

                    RowLayout {
                        anchors {
                            fill: parent
                            leftMargin: 12
                            rightMargin: 8
                        }
                        spacing: 8

                        MaterialSymbol {
                            text: zt.risky ? "warning" : "power_settings_new"
                            iconSize: 18
                            fill: 1
                            color: zt.risky ? IslandEvents.colorAttention : Appearance.colors.colOnLayer1
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: -2
                            StyledText {
                                Layout.fillWidth: true
                                text: zt.busy ? Translation.tr("Changing…") : zt.up ? Translation.tr("Turn off") : Translation.tr("Turn on")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer1
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                visible: zt.risky
                                text: Translation.tr("On during a call · can break the voice")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colOnLayer1
                                opacity: 0.7
                                elide: Text.ElideRight
                            }
                        }
                        StyledSwitch {
                            // Mirrors the state; the card on top takes the click
                            checked: zt.up
                            enabled: !zt.busy
                        }
                    }

                    MouseArea {
                        id: switchMouse
                        anchors.fill: parent
                        enabled: !zt.busy
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: IslandEvents.toggleZeroTier()
                    }
                }
            }

            // Right: peers
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.alignment: Qt.AlignTop
                spacing: 4

                SectionLabel {
                    id: peersLabel
                    visible: zt.up && zt.ok
                    text: zt.leaves.length > 0 ? Translation.tr("Peers · %1").arg(zt.leaves.length) : Translation.tr("Peers")
                    DiCascade { target: peersLabel; index: 1 }
                }

                Repeater {
                    model: zt.up && zt.ok ? Math.min(zt.leaves.length, zt.roots.length > 0 ? 3 : 4) : 0

                    delegate: ListRow {
                        id: peerRow
                        required property int index
                        readonly property var peer: zt.leaves[peerRow.index] ?? ({})
                        readonly property bool isController: peerRow.peer.address === zt.controller
                        readonly property bool direct: (peerRow.peer.path ?? "") !== ""
                        DiCascade { target: peerRow; index: 2 + peerRow.index }
                        icon: peerRow.isController ? "hub" : "computer"
                        strong: peerRow.direct && peerRow.peer.latency >= 0 && peerRow.peer.latency < 80
                        title: peerRow.isController ? Translation.tr("Network controller") : (peerRow.peer.address ?? "")
                        subtitle: [
                            peerRow.isController ? peerRow.peer.address : "",
                            peerRow.direct ? Translation.tr("Direct") : Translation.tr("Relayed"),
                            (peerRow.peer.version ?? "") !== "" && !peerRow.peer.version.startsWith("-") ? `v${peerRow.peer.version}` : ""
                        ].filter(Boolean).join(" · ")
                        value: peerRow.peer.latency >= 0 ? `${peerRow.peer.latency} ms` : "–"
                    }
                }

                ListRow {
                    id: rootsRow
                    visible: zt.up && zt.ok && zt.roots.length > 0
                    DiCascade { target: rootsRow; index: 7 }
                    icon: "public"
                    title: Translation.tr("%1 root servers").arg(zt.roots.length)
                    subtitle: zt.info?.online ? Translation.tr("Online") : Translation.tr("Offline")
                    value: zt.rootLatencies.length > 0
                        ? `${Math.min(...zt.rootLatencies)}–${Math.max(...zt.rootLatencies)} ms` : "–"
                }

                // The id to join from another machine, one tap to copy
                ListRow {
                    id: idRow
                    property bool copied: false
                    visible: zt.up && (zt.network?.id ?? "") !== ""
                    DiCascade { target: idRow; index: 8 }
                    icon: idRow.copied ? "check" : "content_copy"
                    title: Translation.tr("Network ID")
                    subtitle: zt.network?.id ?? ""
                    value: idRow.copied ? Translation.tr("Copied") : ""
                    onTap: () => {
                        Quickshell.clipboardText = zt.network.id
                        idRow.copied = true
                        copiedReset.restart()
                    }
                    Timer {
                        id: copiedReset
                        interval: 1600
                        onTriggered: idRow.copied = false
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: !zt.up || (zt.loaded && !zt.ok) || (zt.up && zt.ok && zt.leaves.length === 0 && zt.roots.length === 0)
                    implicitHeight: ztEmpty.implicitHeight

                    EmptyState {
                        id: ztEmpty
                        anchors.centerIn: parent
                        DiCascade { target: ztEmpty; index: 2 }
                        icon: !zt.up ? "vpn_key_off" : !zt.ok ? "error" : "group_off"
                        title: !zt.up ? Translation.tr("ZeroTier is off")
                            : !zt.ok ? Translation.tr("Couldn't read ZeroTier")
                            : Translation.tr("No peers yet")
                        hint: !zt.up ? Translation.tr("Turn it on to reach the network and see its peers")
                            : !zt.ok ? Translation.tr("zerotier-cli needs passwordless sudo")
                            : Translation.tr("Peers show up as they connect")
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }
    }
}
