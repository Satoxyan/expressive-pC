import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects

ColumnLayout {
    id: xf
    required property Item di
    spacing: 10
    implicitWidth: xf.wantedWidth
    readonly property real wantedWidth: F1.sessionLive ? 480 : 532

    readonly property color flagColor: F1.flagColor(F1.flag)
    readonly property string hourFormat: DateTime.use12HourFormat ? "h AP" : "HH:mm"

    Component.onCompleted: {
        if (!F1.sessionLive) {
            F1.requestWeekend()
            F1.requestStandings()
        }
    }
    Connections {
        target: F1
        function onSessionLiveChanged() {
            if (!F1.sessionLive) {
                F1.requestWeekend()
                F1.requestStandings()
            }
        }
    }

    function formatLongCountdown(seconds) {
        if (seconds < 0) return ""
        const d = Math.floor(seconds / 86400)
        const h = Math.floor((seconds % 86400) / 3600)
        const m = Math.floor((seconds % 3600) / 60)
        if (d > 0) return `${d}d ${h}h`
        if (h > 0) return `${h}h ${m}min`
        return F1.formatCountdown(seconds)
    }

    // "Practice 1" -> "FP1" ("TL1" in pt_BR); short labels for the weekend agenda list
    function weekendShortLabel(name) {
        const practice = (name ?? "").match(/^Practice (\d)$/)
        if (practice) return Translation.tr("FP%1").arg(practice[1])
        switch (name) {
            case "Race": return Translation.tr("Race")
            case "Qualifying": return Translation.tr("Quali")
            case "Sprint": return "Sprint"
            case "Sprint Qualifying":
            case "Sprint Shootout": return Translation.tr("Sprint quali")
            default: return name ?? ""
        }
    }

    // OpenF1's circuit_short_name -> the matching layout in julesr0y/f1-circuits-svg (a plain outline,
    // one path, no fill) — picked to be the current-era layout for each track. Unlisted/renamed tracks
    // fall back to a first-guess slug, and the watermark just stays hidden if that 404s.
    readonly property var trackSlugs: ({
        sakhir: "bahrain-1", bahrain: "bahrain-1",
        melbourne: "melbourne-2",
        shanghai: "shanghai-1",
        suzuka: "suzuka-2",
        jeddah: "jeddah-1",
        miami: "miami-1", miamigardens: "miami-1",
        montreal: "montreal-6",
        monaco: "monaco-6", montecarlo: "monaco-6",
        barcelona: "catalunya-6", catalunya: "catalunya-6",
        spielberg: "spielberg-3",
        silverstone: "silverstone-8",
        spafrancorchamps: "spa-francorchamps-4",
        budapest: "hungaroring-3", hungaroring: "hungaroring-3",
        zandvoort: "zandvoort-5",
        monza: "monza-7",
        baku: "baku-1",
        kualalumpur: "sepang-1", sepang: "sepang-1",
        marinabay: "marina-bay-4", singapore: "marina-bay-4",
        austin: "austin-1",
        mexicocity: "mexico-city-3", mexico: "mexico-city-3",
        saopaulo: "interlagos-2", interlagos: "interlagos-2",
        lasvegas: "las-vegas-1",
        lusail: "lusail-1", losail: "lusail-1",
        yasmarina: "yas-marina-2", abudhabi: "yas-marina-2"
    })

    function trackSvgUrl(name) {
        const key = (name ?? "").toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[^a-z0-9]/g, "")
        if (!key) return ""
        const layout = xf.trackSlugs[key] ?? `${key}-1`
        return `https://raw.githubusercontent.com/julesr0y/f1-circuits-svg/main/circuits/minimal/white-outline/${layout}.svg`
    }

    component SectionLabel: StyledText {
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.weight: Font.DemiBold
        color: Appearance.colors.colOnLayer0
        opacity: 0.6
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Rectangle {
            implicitWidth: 34
            implicitHeight: 22
            radius: 6
            color: F1.sessionLive ? xf.flagColor : Appearance.colors.colLayer2

            Behavior on color {
                ColorAnimation { duration: IslandMotion.medium }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: F1.sessionLive ? "flag" : "sports_score"
                iconSize: 15
                fill: 1
                color: F1.sessionLive ? "#111111" : Appearance.colors.colOnLayer1
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: -2

            StyledText {
                Layout.fillWidth: true
                text: F1.sessionLive ? (F1.session?.meeting ?? "") : (F1.nextSession?.meeting ?? "Formula 1")
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer0
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                text: F1.sessionLive
                    ? `${F1.sessionLabel(F1.session?.name ?? "")} · ${F1.flagLabel(F1.flag)}${F1.mode === "replay" ? " · replay" : ""}`
                    : (F1.nextSession ? F1.sessionLabel(F1.nextSession.name) : Translation.tr("No upcoming session"))
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colOnLayer0
                opacity: 0.7
                elide: Text.ElideRight
            }
        }

        StyledText {
            visible: F1.sessionLive
            text: F1.totalLaps > 0 ? `${Translation.tr("Lap")} ${F1.lap}/${F1.totalLaps}` : F1.remaining
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
            color: Appearance.colors.colOnLayer0
        }
    }

    Item {
        id: grid
        Layout.fillWidth: true
        Layout.preferredHeight: grid.perColumn * grid.rowH
        visible: F1.sessionLive && driversModel.count > 0

        readonly property int perColumn: 5
        readonly property real rowH: 30
        readonly property real colGap: 10
        readonly property real colW: (grid.width - grid.colGap) / 2

        Repeater {
            model: ListModel { id: driversModel }

            delegate: Item {
                id: row
                required property string num
                required property int slot
                required property string tla
                required property string teamColor
                required property string gap
                required property string interval
                required property string best
                required property bool inPit
                required property bool retired
                required property string tyre

                readonly property bool shown: row.slot < grid.perColumn * 2
                readonly property int column: Math.min(1, Math.floor(row.slot / grid.perColumn))
                readonly property int line: row.shown ? row.slot % grid.perColumn : grid.perColumn - 1
                property int lastSlot: row.slot
                property int trend: 0
                property real lift: 0

                width: grid.colW
                height: grid.rowH - 3
                x: row.column * (grid.colW + grid.colGap)
                y: row.line * grid.rowH + (row.shown ? 0 : grid.rowH)
                z: row.trend > 0 ? 10 : (row.trend < 0 ? 5 : 1)
                opacity: row.shown ? 1 : 0
                scale: 1

                Behavior on x {
                    NumberAnimation { duration: 760; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial }
                }
                Behavior on y {
                    NumberAnimation { duration: 760; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial }
                }
                Behavior on opacity {
                    NumberAnimation { duration: IslandMotion.medium }
                }

                onSlotChanged: {
                    if (row.slot === row.lastSlot) return
                    row.trend = row.slot < row.lastSlot ? 1 : -1
                    row.lastSlot = row.slot
                    trendTimer.restart()
                }

                SequentialAnimation {
                    id: liftAnim
                    NumberAnimation { target: row; property: "lift"; to: 1; duration: IslandMotion.short; easing.type: Easing.OutCubic }
                    PauseAnimation { duration: 320 }
                    NumberAnimation { target: row; property: "lift"; to: 0; duration: IslandMotion.long; easing.type: Easing.OutBack; easing.overshoot: 2 }
                }

                Timer {
                    id: trendTimer
                    interval: 4500
                    onTriggered: row.trend = 0
                }

                StyledRectangularShadow {
                    target: rowBackground
                    opacity: row.lift
                    visible: row.lift > 0.01
                }

                Rectangle {
                    id: rowBackground
                    anchors.fill: parent
                    radius: 9
                    color: row.trend > 0 ? ColorUtils.mix(Appearance.colors.colLayer1, Appearance.m3colors.m3success, 0.72)
                        : row.trend < 0 ? ColorUtils.mix(Appearance.colors.colLayer1, Appearance.colors.colError, 0.82)
                        : row.tla === F1.favoriteDriver ? ColorUtils.mix(Appearance.colors.colLayer1, row.teamColor, 0.75)
                        : Appearance.colors.colLayer1
                    border.width: row.tla === F1.favoriteDriver ? 1 : 0
                    border.color: row.teamColor

                    Behavior on color {
                        ColorAnimation { duration: 600 }
                    }
                }

                RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: 8
                        rightMargin: 8
                    }
                    spacing: 6

                    StyledText {
                        Layout.preferredWidth: 16
                        horizontalAlignment: Text.AlignRight
                        text: row.slot + 1
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Bold
                        font.features: { "tnum": 1 }
                        color: Appearance.colors.colOnLayer1
                    }

                    Item {
                        implicitWidth: 12
                        implicitHeight: 16

                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: row.trend !== 0
                            text: row.trend > 0 ? "arrow_drop_up" : "arrow_drop_down"
                            iconSize: 20
                            fill: 1
                            color: row.trend > 0 ? Appearance.m3colors.m3success : Appearance.colors.colError
                            onVisibleChanged: if (visible) arrowIn.restart()

                            NumberAnimation on scale {
                                id: arrowIn
                                running: false
                                from: 0.2
                                to: 1
                                duration: IslandMotion.medium
                                easing.type: Easing.OutBack
                            }
                        }
                    }

                    Rectangle {
                        implicitWidth: 4
                        implicitHeight: 16
                        radius: 2
                        color: row.teamColor
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: row.tla
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        visible: row.tyre !== ""
                        implicitWidth: 14
                        implicitHeight: 14
                        radius: 7
                        color: "#1B1B1B"
                        border.width: 2
                        border.color: F1.tyreColor(row.tyre)

                        Behavior on border.color {
                            ColorAnimation { duration: IslandMotion.long }
                        }

                        StyledText {
                            anchors.centerIn: parent
                            text: F1.tyreLetter(row.tyre)
                            font.pixelSize: 7
                            font.weight: Font.Black
                            color: F1.tyreColor(row.tyre)
                        }
                    }

                    Rectangle {
                        visible: row.inPit || row.retired
                        implicitWidth: pitText.implicitWidth + 8
                        implicitHeight: 15
                        radius: 4
                        color: row.retired ? Appearance.colors.colError : Appearance.colors.colSecondaryContainer
                        StyledText {
                            id: pitText
                            anchors.centerIn: parent
                            text: row.retired ? "OUT" : Translation.tr("PIT")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.Bold
                            color: row.retired ? Appearance.colors.colOnError : Appearance.colors.colOnSecondaryContainer
                        }
                    }

                    StyledText {
                        text: F1.isRace ? (row.slot === 0 ? (F1.totalLaps > 0 ? `L${F1.lap}` : "") : (row.interval || row.gap)) : row.best
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.features: { "tnum": 1 }
                        color: Appearance.colors.colOnLayer1
                        opacity: 0.8
                    }
                }

                // A quick burst of speed lines sweeps through on an overtake, in the direction of the move —
                // the visual a car makes blowing past on the straight, not just the row sliding into place.
                Row {
                    id: streaks
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: 26
                        rightMargin: 26
                    }
                    spacing: (row.width - 52) / 5
                    opacity: 0
                    layoutDirection: row.trend < 0 ? Qt.RightToLeft : Qt.LeftToRight

                    Repeater {
                        model: 4
                        delegate: Rectangle {
                            required property int index
                            width: 14 - index * 2
                            height: 2
                            radius: 1
                            color: row.trend > 0 ? Appearance.m3colors.m3success : Appearance.colors.colError
                            opacity: 0.85 - index * 0.18
                        }
                    }

                    SequentialAnimation {
                        id: streakAnim
                        ParallelAnimation {
                            NumberAnimation { target: streaks; property: "opacity"; from: 0; to: 1; duration: 90 }
                            NumberAnimation {
                                target: streaks; property: "x"; from: row.trend < 0 ? 20 : -20; to: 0
                                duration: 260; easing.type: Easing.OutCubic
                            }
                        }
                        PauseAnimation { duration: 90 }
                        NumberAnimation { target: streaks; property: "opacity"; to: 0; duration: 220 }
                    }
                }

                onTrendChanged: if (row.trend !== 0) streakAnim.restart()
            }
        }

        function sync() {
            const top = F1.drivers.slice(0, 12)
            const keep = new Set(top.map(d => d.num))
            for (let k = driversModel.count - 1; k >= 0; k--) {
                if (!keep.has(driversModel.get(k).num)) driversModel.remove(k)
            }
            top.forEach((d, i) => {
                const entry = {
                    num: d.num, slot: i, tla: d.tla, teamColor: d.color,
                    gap: d.gap ?? "", interval: d.interval ?? "", best: d.best ?? "",
                    inPit: d.inPit ?? false, retired: d.retired ?? false, tyre: d.tyre ?? ""
                }
                let found = -1
                for (let k = 0; k < driversModel.count; k++) {
                    if (driversModel.get(k).num === d.num) {
                        found = k
                        break
                    }
                }
                if (found === -1) driversModel.append(entry)
                else driversModel.set(found, entry)
            })
        }

        Component.onCompleted: grid.sync()

        Connections {
            target: F1
            function onDriversChanged() { grid.sync() }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: F1.sessionLive && (F1.weather?.air ?? "") !== ""
        spacing: 14

        Repeater {
            model: [
                { icon: "thermostat", text: `${Translation.tr("Air")} ${F1.weather?.air ?? ""}°` },
                { icon: "add_road", text: `${Translation.tr("Track")} ${F1.weather?.track ?? ""}°` },
                { icon: (F1.weather?.rain ?? false) ? "rainy" : "water_drop", text: (F1.weather?.rain ?? false) ? Translation.tr("Raining") : `${F1.weather?.humidity ?? ""}%` }
            ]
            delegate: RowLayout {
                required property var modelData
                spacing: 3

                MaterialSymbol {
                    text: modelData.icon
                    iconSize: 14
                    fill: 1
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    text: modelData.text
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.features: { "tnum": 1 }
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.8
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: F1.sessionLive && F1.raceControl !== null
        spacing: 8

        MaterialSymbol {
            Layout.alignment: Qt.AlignTop
            text: "campaign"
            iconSize: 16
            fill: 1
            color: Appearance.colors.colPrimary
        }
        StyledText {
            Layout.fillWidth: true
            text: F1.raceControl?.message ?? ""
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colOnLayer0
            opacity: 0.85
            wrapMode: Text.Wrap
            maximumLineCount: 1
            elide: Text.ElideRight
        }
    }

    // Off-session: a countdown to the next session, the whole weekend's agenda, and the top of the
    // drivers' championship. Two columns, only shown between race weekends.
    Item {
        id: offSessionWrap
        Layout.fillWidth: true
        implicitHeight: offSession.implicitHeight
        visible: !F1.sessionLive

        // The upcoming circuit's real layout, faint behind the countdown and agenda — the actual track,
        // not an abstract shape, the same "load once, cache in Qt's image cache" pattern as album art.
        Image {
            id: trackWatermark
            anchors.fill: parent
            anchors.margins: -4
            source: xf.trackSvgUrl(offSession.next?.circuit ?? "")
            visible: false
            asynchronous: true
            fillMode: Image.PreserveAspectFit
            sourceSize.width: 400
            sourceSize.height: 400
        }
        ColorOverlay {
            anchors.fill: trackWatermark
            source: trackWatermark
            color: Appearance.colors.colOnLayer0
            opacity: trackWatermark.status === Image.Ready ? 0.1 : 0
            Behavior on opacity { NumberAnimation { duration: IslandMotion.long } }
        }

        RowLayout {
            id: offSession
            width: parent.width
            spacing: 20

            readonly property var next: F1.nextSession
            readonly property var upcomingWeekend: (F1.weekend ?? []).filter(s => Date.parse(s.end) > Date.now())
            readonly property string nextStart: offSession.upcomingWeekend.length > 0 ? offSession.upcomingWeekend[0].start : ""

            ColumnLayout {
                id: countdownCol
                Layout.fillWidth: false
                Layout.preferredWidth: 246
                Layout.maximumWidth: 246
                Layout.alignment: Qt.AlignTop
                spacing: 4

                RowLayout {
                    id: countdownHeader
                    Layout.fillWidth: true
                    spacing: 4
                    DiCascade { target: countdownHeader; index: 0 }

                    MaterialSymbol {
                        text: "location_on"
                        iconSize: 14
                        fill: 1
                        color: Appearance.colors.colOnLayer0
                        opacity: 0.6
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: offSession.next?.circuit ?? ""
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer0
                        opacity: 0.75
                        elide: Text.ElideRight
                    }
                }

                StyledText {
                    id: countdownNum
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    DiCascade { target: countdownNum; index: 1 }
                    text: offSession.next ? xf.formatLongCountdown(F1.secondsToNext) : "–"
                    font.pixelSize: 40
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                    color: Appearance.colors.colPrimary
                    elide: Text.ElideRight
                }

                ColumnLayout {
                    id: countdownCaption
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    spacing: 0
                    DiCascade { target: countdownCaption; index: 2 }
                    visible: offSession.next !== null

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("until %1").arg(offSession.next ? F1.sessionLabel(offSession.next.name) : "")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer0
                        opacity: 0.75
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: offSession.next ? Qt.locale().toString(new Date(offSession.next.start), "dddd, dd/MM · " + xf.hourFormat) : ""
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.features: { "tnum": 1 }
                        color: Appearance.colors.colOnLayer0
                        opacity: 0.6
                        elide: Text.ElideRight
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    visible: offSession.next === null
                    text: Translation.tr("No upcoming session")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.55
                }


                Item { Layout.fillHeight: true }

                SectionLabel {
                    id: standingsLabel
                    text: Translation.tr("Championship")
                    visible: F1.standings.length > 0
                    DiCascade { target: standingsLabel; index: 3 }
                }

                RowLayout {
                    id: standingsRow
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    spacing: 4
                    visible: F1.standings.length > 0
                    DiCascade { target: standingsRow; index: 4 }

                    Repeater {
                        model: F1.standings

                        delegate: Rectangle {
                            id: chip
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitHeight: 34
                            radius: 10
                            color: Appearance.colors.colLayer1

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: -1
                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: chip.modelData.code
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colOnLayer1
                                }
                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: chip.modelData.points
                                    font.pixelSize: 9
                                    font.features: { "tnum": 1 }
                                    color: Appearance.colors.colOnLayer1
                                    opacity: 0.6
                                }
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                id: agendaCol
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: 4

                SectionLabel {
                    id: agendaLabel
                    text: Translation.tr("Weekend")
                    DiCascade { target: agendaLabel; index: 0 }
                }

                StyledText {
                    visible: offSession.upcomingWeekend.length === 0
                    text: Translation.tr("Loading schedule…")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.5
                }

                Repeater {
                    model: offSession.upcomingWeekend

                    delegate: Rectangle {
                        id: agendaRow
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        implicitHeight: 24
                        radius: 8
                        readonly property bool isNext: agendaRow.index === 0
                        color: agendaRow.isNext ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.85) : "transparent"
                        DiCascade { target: agendaRow; index: agendaRow.index + 1; step: 24 }

                        RowLayout {
                            anchors {
                                fill: parent
                                leftMargin: 8
                                rightMargin: 8
                            }
                            spacing: 6

                            StyledText {
                                Layout.preferredWidth: 42
                                text: xf.weekendShortLabel(agendaRow.modelData.name)
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: agendaRow.isNext ? Font.DemiBold : Font.Medium
                                color: agendaRow.isNext ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                                opacity: agendaRow.isNext ? 1 : 0.75
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignRight
                                text: Qt.locale().toString(new Date(agendaRow.modelData.start), "ddd · " + xf.hourFormat)
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.features: { "tnum": 1 }
                                color: agendaRow.isNext ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                                opacity: agendaRow.isNext ? 1 : 0.6
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }
}
