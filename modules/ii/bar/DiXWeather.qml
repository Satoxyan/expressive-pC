import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Weather in two columns: now and the sun's path through the day on the left; the next 24 h as a temperature
// curve and the conditions that matter (UV, humidity, wind, pressure) on the right. Everything cascades in.
RowLayout {
    id: xw
    required property Item di
    spacing: 20
    implicitWidth: xw.wantedWidth
    readonly property real wantedWidth: 532

    Component.onCompleted: Weather.requestForecast()

    readonly property bool hasData: (Weather.data?.temp ?? "") !== ""
    readonly property int tempNow: parseInt(Weather.data?.temp ?? "0") || 0
    readonly property int feelsNow: parseInt(Weather.data?.tempFeelsLike ?? "0") || 0
    readonly property real nowTs: DateTime.clock.date.getTime() / 1000
    readonly property string hourFormat: DateTime.use12HourFormat ? "h AP" : "HH:mm"

    // "Now" first, then the forecast in 3 h steps
    readonly property var steps: {
        const first = { dt: 0, temp: xw.tempNow, wCode: Weather.data?.wCode ?? 800, night: Weather.data?.night, pop: 0, isNow: true }
        return [first].concat(Weather.forecast ?? [])
    }
    readonly property int low: Math.min(...xw.steps.map(s => s.temp))
    readonly property int high: Math.max(...xw.steps.map(s => s.temp))

    function timeOf(ts) {
        return Qt.locale().toString(new Date(ts * 1000), xw.hourFormat)
    }
    function capitalized(text) {
        const s = (text ?? "").toString()
        return s.charAt(0).toUpperCase() + s.slice(1)
    }
    function uvLevel(uv) {
        if (uv < 3) return Translation.tr("Low")
        if (uv < 6) return Translation.tr("Moderate")
        if (uv < 8) return Translation.tr("High")
        if (uv < 11) return Translation.tr("Very high")
        return Translation.tr("Extreme")
    }
    // Where the wind comes from, as a compass point
    function compass(deg) {
        const points = Translation.tr("N NE E SE S SW W NW").split(" ")
        return points[Math.round(((deg % 360) + 360) % 360 / 45) % 8] ?? ""
    }
    function windText() {
        const speed = Weather.data?.windSpeed ?? 0
        return Weather.useUSCS ? `${Math.round(speed)} mph` : `${Math.round(speed * 3.6)} km/h`
    }

    component SectionLabel: StyledText {
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.weight: Font.DemiBold
        color: Appearance.colors.colOnLayer0
        opacity: 0.6
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

    // Left: now
    ColumnLayout {
        // Children filling the width would otherwise make this column fill the row too
        Layout.fillWidth: false
        Layout.preferredWidth: 180
        Layout.maximumWidth: 180
        Layout.fillHeight: true
        spacing: 0

        RowLayout {
            id: cityRow
            spacing: 4
            DiCascade { target: cityRow; index: 0 }

            MaterialSymbol {
                text: "location_on"
                iconSize: 15
                fill: 1
                color: Appearance.colors.colOnLayer0
                opacity: 0.6
            }
            StyledText {
                Layout.maximumWidth: 160
                text: Weather.data?.city ?? ""
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer0
                opacity: 0.75
                elide: Text.ElideRight
            }
        }

        RowLayout {
            id: nowRow
            Layout.topMargin: 6
            spacing: 10
            DiCascade { target: nowRow; index: 1 }

            MaterialSymbol {
                text: IslandEvents.weatherSymbol(Weather.data?.wCode ?? 800, Weather.data?.night)
                iconSize: 50
                fill: 1
                color: Appearance.colors.colPrimary
            }
            StyledText {
                text: xw.hasData ? `${xw.tempNow}°` : "–"
                font.pixelSize: 46
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
                color: Appearance.colors.colOnLayer0
            }
        }

        ColumnLayout {
            id: nowText
            Layout.fillWidth: true
            spacing: 1
            DiCascade { target: nowText; index: 2 }

            StyledText {
                Layout.fillWidth: true
                text: xw.capitalized(Weather.data?.description)
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer0
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                text: `${Translation.tr("Feels like")} ${xw.feelsNow}° · ${Translation.tr("Low %1 · High %2").arg(xw.low + "°").arg(xw.high + "°")}`
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.features: { "tnum": 1 }
                color: Appearance.colors.colOnLayer0
                opacity: 0.6
                elide: Text.ElideRight
            }
        }

        Item { Layout.fillHeight: true }

        // The sun's path from sunrise to sunset, with where it is now
        Item {
            id: sunArc
            Layout.fillWidth: true
            implicitHeight: 84
            DiCascade { target: sunArc; index: 3 }

            readonly property real rise: Weather.data?.sunriseTs ?? 0
            readonly property real set: Weather.data?.sunsetTs ?? 0
            readonly property bool isDay: xw.nowTs >= sunArc.rise && xw.nowTs < sunArc.set
            readonly property real progress: sunArc.set > sunArc.rise
                ? Math.max(0, Math.min(1, (xw.nowTs - sunArc.rise) / (sunArc.set - sunArc.rise))) : 0
            // After sunset the next sunrise is about a day after today's
            readonly property real nextRise: xw.nowTs < sunArc.rise ? sunArc.rise : sunArc.rise + 86400

            onProgressChanged: arcCanvas.requestPaint()

            Canvas {
                id: arcCanvas
                width: parent.width
                height: 58
                readonly property color lineColor: Appearance.colors.colOnLayer0
                readonly property color sunColor: Appearance.colors.colPrimary
                onLineColorChanged: requestPaint()
                onSunColorChanged: requestPaint()
                onWidthChanged: requestPaint()

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    const cx = width / 2, cy = height - 3
                    const rx = width / 2 - 8, ry = height - 10
                    const point = t => [cx - rx * Math.cos(t * Math.PI), cy - ry * Math.sin(t * Math.PI)]
                    const trace = (from, to) => {
                        ctx.beginPath()
                        for (let i = 0; i <= 48; i++) {
                            const [x, y] = point(from + (to - from) * i / 48)
                            if (i === 0) ctx.moveTo(x, y)
                            else ctx.lineTo(x, y)
                        }
                        ctx.stroke()
                    }

                    // Horizon
                    ctx.strokeStyle = Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.15)
                    ctx.lineWidth = 1
                    ctx.beginPath()
                    ctx.moveTo(0, cy)
                    ctx.lineTo(width, cy)
                    ctx.stroke()

                    // The whole day, dashed, then the part already travelled
                    ctx.setLineDash([3, 4])
                    ctx.strokeStyle = Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.25)
                    ctx.lineWidth = 1.5
                    trace(0, 1)
                    ctx.setLineDash([])
                    if (sunArc.isDay) {
                        ctx.strokeStyle = sunColor
                        ctx.lineWidth = 2
                        ctx.lineCap = "round"
                        trace(0, sunArc.progress)

                        const [sx, sy] = point(sunArc.progress)
                        ctx.fillStyle = Qt.rgba(sunColor.r, sunColor.g, sunColor.b, 0.25)
                        ctx.beginPath()
                        ctx.arc(sx, sy, 8, 0, Math.PI * 2)
                        ctx.fill()
                        ctx.fillStyle = sunColor
                        ctx.beginPath()
                        ctx.arc(sx, sy, 4.5, 0, Math.PI * 2)
                        ctx.fill()
                    }
                }
            }

            StyledText {
                anchors.centerIn: arcCanvas
                anchors.verticalCenterOffset: 8
                visible: !sunArc.isDay && sunArc.rise > 0
                text: Translation.tr("Sunrise in %1").arg(xw.di.formatDuration(sunArc.nextRise - xw.nowTs))
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colOnLayer0
                opacity: 0.6
            }
            StyledText {
                anchors.centerIn: arcCanvas
                anchors.verticalCenterOffset: 8
                visible: sunArc.isDay
                text: Translation.tr("Sunset in %1").arg(xw.di.formatDuration(sunArc.set - xw.nowTs))
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colOnLayer0
                opacity: 0.6
            }

            RowLayout {
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }
                spacing: 4
                visible: sunArc.rise > 0

                MaterialSymbol {
                    text: "wb_twilight"
                    iconSize: 14
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.55
                }
                StyledText {
                    Layout.fillWidth: true
                    text: xw.timeOf(sunArc.rise)
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.features: { "tnum": 1 }
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.7
                }
                StyledText {
                    text: xw.timeOf(sunArc.set)
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.features: { "tnum": 1 }
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.7
                }
                MaterialSymbol {
                    text: "nights_stay"
                    iconSize: 14
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.55
                }
            }
        }
    }

    // Right: the next hours and the conditions
    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.alignment: Qt.AlignTop
        spacing: 6

        SectionLabel {
            id: hoursLabel
            text: Translation.tr("Next hours")
            DiCascade { target: hoursLabel; index: 0 }
        }

        Item {
            id: strip
            Layout.fillWidth: true
            implicitHeight: 100

            readonly property var steps: xw.steps
            readonly property real colW: strip.width / Math.max(1, strip.steps.length)
            // The curve lives between these two lines; the warmest step sits on top
            readonly property real curveTop: 58
            readonly property real curveBottom: 82
            function yFor(temp) {
                const span = Math.max(1, xw.high - xw.low)
                return strip.curveBottom - (temp - xw.low) / span * (strip.curveBottom - strip.curveTop)
            }

            onStepsChanged: curve.requestPaint()
            onWidthChanged: curve.requestPaint()

            StyledText {
                anchors.centerIn: parent
                visible: (Weather.forecast ?? []).length === 0
                text: Translation.tr("Loading forecast…")
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colOnLayer0
                opacity: 0.5
            }

            Canvas {
                id: curve
                anchors.fill: parent
                visible: strip.steps.length > 1
                readonly property color lineColor: Appearance.colors.colPrimary
                onLineColorChanged: requestPaint()
                DiCascade { target: curve; index: 2; rise: 0 }

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    const pts = strip.steps.map((s, i) => [(i + 0.5) * strip.colW, strip.yFor(s.temp)])
                    if (pts.length < 2) return
                    // Through the midpoints, so the line is smooth and still passes over every dot
                    const path = () => {
                        ctx.beginPath()
                        ctx.moveTo(pts[0][0], pts[0][1])
                        for (let i = 1; i < pts.length - 1; i++) {
                            const mx = (pts[i][0] + pts[i + 1][0]) / 2
                            const my = (pts[i][1] + pts[i + 1][1]) / 2
                            ctx.quadraticCurveTo(pts[i][0], pts[i][1], mx, my)
                        }
                        ctx.lineTo(pts[pts.length - 1][0], pts[pts.length - 1][1])
                    }

                    path()
                    ctx.lineTo(pts[pts.length - 1][0], strip.curveBottom + 6)
                    ctx.lineTo(pts[0][0], strip.curveBottom + 6)
                    ctx.closePath()
                    const fill = ctx.createLinearGradient(0, strip.curveTop, 0, strip.curveBottom + 6)
                    fill.addColorStop(0, Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.18))
                    fill.addColorStop(1, Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0))
                    ctx.fillStyle = fill
                    ctx.fill()

                    path()
                    ctx.strokeStyle = Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.7)
                    ctx.lineWidth = 2
                    ctx.lineCap = "round"
                    ctx.stroke()
                }
            }

            Repeater {
                // By count, so a new reading of "now" updates the delegates instead of rebuilding (and re-cascading) them
                model: strip.steps.length

                Item {
                    id: hour
                    required property int index
                    readonly property var modelData: strip.steps[hour.index] ?? ({})
                    x: hour.index * strip.colW
                    width: strip.colW
                    height: strip.height
                    DiCascade { target: hour; index: hour.index + 1; step: 28 }

                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: hour.modelData.isNow ? Translation.tr("Now") : xw.timeOf(hour.modelData.dt)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: hour.modelData.isNow ? Font.DemiBold : Font.Normal
                        font.features: { "tnum": 1 }
                        color: Appearance.colors.colOnLayer0
                        opacity: hour.modelData.isNow ? 0.9 : 0.55
                    }
                    MaterialSymbol {
                        y: 18
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: IslandEvents.weatherSymbol(hour.modelData.wCode, hour.modelData.night)
                        iconSize: 20
                        fill: 1
                        color: Appearance.colors.colOnLayer0
                        opacity: 0.85
                    }
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: strip.yFor(hour.modelData.temp) - 19
                        text: `${hour.modelData.temp}°`
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        font.features: { "tnum": 1 }
                        color: Appearance.colors.colOnLayer0
                    }
                    Rectangle {
                        x: (parent.width - width) / 2
                        y: strip.yFor(hour.modelData.temp) - height / 2
                        width: hour.modelData.isNow ? 8 : 6
                        height: width
                        radius: width / 2
                        color: Appearance.colors.colPrimary
                        border.width: hour.modelData.isNow ? 2 : 0
                        border.color: Appearance.colors.colOnPrimary
                    }
                    // Chance of rain, only when it is worth reading
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        visible: hour.modelData.pop >= 0.2
                        text: `${Math.round(hour.modelData.pop * 100)}%`
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.features: { "tnum": 1 }
                        color: Appearance.colors.colPrimary
                    }
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            columns: 2
            rowSpacing: 6
            columnSpacing: 6

            Chip {
                id: uvChip
                DiCascade { target: uvChip; index: 4 }
                icon: "light_mode"
                value: Weather.uvNow >= 0 ? `${Math.round(Weather.uvNow)} · ${xw.uvLevel(Weather.uvNow)}` : "–"
                label: Weather.uvMax >= 0 ? Translation.tr("UV · peak %1").arg(Math.round(Weather.uvMax)) : Translation.tr("UV index")
            }
            Chip {
                id: humidityChip
                DiCascade { target: humidityChip; index: 5 }
                icon: "water_drop"
                value: Weather.data?.humidity ?? "–"
                label: Translation.tr("Humidity")
            }
            Chip {
                id: windChip
                DiCascade { target: windChip; index: 6 }
                icon: "air"
                value: xw.windText()
                label: `${Translation.tr("Wind")} · ${xw.compass(Weather.data?.windDir ?? 0)}`
            }
            Chip {
                id: pressureChip
                DiCascade { target: pressureChip; index: 7 }
                icon: "compress"
                value: Weather.data?.press ?? "–"
                label: Translation.tr("Pressure")
            }
        }
    }
}
