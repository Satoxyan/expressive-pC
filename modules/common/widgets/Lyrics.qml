pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Qt5Compat.GraphicalEffects
import QtQuick

Item {
    id: root

    // How much taller than the widget the list's clip box is, on each of the
    // two ends. A line on its way in or out is sliced in half by the widget's
    // edge, which reads as a broken glyph rather than as a fading line, so a
    // host with spare room around the widget can move the cut down the list —
    // where the opacity ladder has already taken the words to near-invisible.
    // Zero by default: the dashboard and the sidebar give the lyrics every
    // pixel they have, and for them the widget edge is the right bound.
    // Negative takes the cut out altogether: the list keeps its size, its pan
    // and which lines it decides to draw, but stops clipping, so nothing is
    // ever sliced at the widget's edge even when it sits past the edge.
    property real clipOverflowY: 0
    // A negative value is a mode, not an amount of room, so it adds nothing.
    readonly property real overflowY: Math.max(0, clipOverflowY)

    property color textColor: "white"
    property color activeColor: "white"
    property color dimColor: Qt.rgba(1, 1, 1, 0.35)
    property color indicatorColor: Appearance.colors.colPrimaryContainer
    property color indicatorShapeColor: Appearance.colors.colOnPrimaryContainer
    property int textAlignment: Text.AlignLeft
    property real fontScale: 1.0
    property bool karaoke: true
    // Air between the lines of the list. Hosts that show the lyrics big ask
    // for more (the dashboard uses 28); the default is one Material spacing
    // step, which reads tight enough for a sidebar or a media card.
    property real lineSpacing: Appearance.spacing.space100

    // How many lines the widget keeps on each side of the one being sung.
    // Negative, the default: the whole list stays drawn and the opacity ladder
    // carries the distance, which is what the dashboard and the sidebar want —
    // the lyrics are the only thing in their space, so empty room around a
    // short line would read as a hole. A host that asks for a window gets a
    // fixed block of text instead: the same number of lines on each side of
    // the sung one, and the leftover room left empty rather than filled with
    // dead lines.
    property int lineContext: -1

    // Not a Config option: this exists for the offscreen render probe. A word
    // behind a glow layer is a ShaderEffect, and those do not appear in a
    // grabbed image at all, so with the glow on the sweep cannot be measured.
    property bool glowEnabled: true

    // Air kept between the text and the widget's own clip edge. The word being
    // sung rises, grows and glows a few pixels past its ink, and the leftmost
    // word of a row sits right on that edge, so its glow used to be sliced
    // flat. Eight is a hair more than the glow's radius (7), which is how far
    // the light reaches past the word. Insetting the text inside the widget
    // moves the problem away without any host having to resize its cover canvas
    // or re-anchor the widget.
    property real contentInset: 8
    // The width the text may actually use, once that air is kept on both sides
    // so a centered line stays centered.
    readonly property real textWidth: Math.max(1, width - 2 * contentInset)

    implicitWidth: 200
    implicitHeight: 200

    readonly property int activeFontSize: Appearance.font.pixelSize.normal
    readonly property int farFontSize: Appearance.font.pixelSize.smallest

    function fontSizeFor(dist) {
        // Big (active) to small (far) gradient, stepping every line so the
        // past/future lines visibly shrink away from the highlighted one;
        // the whole gradient scales with fontScale (dashboard asks 1.8).
        return Math.max(root.farFontSize, root.activeFontSize - dist * 2) * root.fontScale
    }
    function opacityFor(dist) {
        if (dist === 0) return 1.0
        if (dist === 1) return 0.6
        if (dist === 2) return 0.35
        return 0.15
    }

    readonly property int motionDuration: 320
    readonly property real rowSpacing: 4

    // The list is every lyric line plus the provider attribution trailing the
    // last one, so the note scrolls up with the end of the song instead of
    // being pinned inside the widget.
    readonly property var lineRows: {
        const lines = LyricsService.lyricsLines ?? []
        const rows = []
        for (let i = 0; i < lines.length; i++)
            rows.push({ text: lines[i].text || "♪", note: false,
                        otherVoice: lines[i].align === "end",
                        bgText: lines[i].bg?.text ?? "" })
        if (lines.length > 0 && LyricsService.providedBy.length > 0)
            rows.push({ text: "Lyrics provided by " + LyricsService.providedBy, note: true })
        return rows
    }

    // A song with more than one voice says so by putting lines on the far edge.
    // Then the lead keeps the near edge and the other voice the far one, which
    // is the whole point of the marking, so it overrides whatever alignment the
    // host asked for. With one voice there is nothing to tell apart and the
    // host's own alignment stands.
    readonly property bool duet: (LyricsService.lyricsLines ?? [])
        .some(l => l.align === "end")

    // ── Karaoke word layout for the active line ────────────────────────────
    // Only the active line needs per-word items; the neighbours stay one plain
    // text each, so a widget showing seven lines pays one wrapped word layout
    // instead of seven.

    FontMetrics {
        id: hotMetrics
        font {
            family: Appearance.font.family.main
            pixelSize: root.fontSizeFor(0)
            variableAxes: Appearance.font.variableAxes.main
        }
    }

    // How many steps down the ladder the background vocal sits: it answers the
    // line above it, so it is smaller and further back, but still readable.
    readonly property int subLineOffset: 3

    FontMetrics {
        id: subMetrics
        font {
            family: Appearance.font.family.main
            pixelSize: root.fontSizeFor(root.subLineOffset)
            variableAxes: Appearance.font.variableAxes.main
        }
    }

    readonly property var hotRows: root.buildHotRows()
    readonly property var subRows: root.buildSubRows()
    // One list of rows for the sung line, lead first then its echo: the two
    // share the column, the spacing and which edge they belong to, and packing
    // them into a single Repeater is what keeps that true. Each row carries the
    // flag its words are measured against.
    readonly property var sungRows: root.hotRows.concat(root.subRows)

    // FontMetrics reports the ink advance, but a Text lays itself out on its
    // bounding box, which is a couple of pixels wider (side bearings). Packing
    // rows on the bare advance lets a long line outgrow the widget and get cut
    // at the right edge, so every measurement here carries that slack.
    function pieceWidth(text, metrics) {
        return Math.ceil(metrics.advanceWidth(text)) + 3
    }

    // Lay `source` out in rows that fit the widget, measured with `metrics`.
    // sentence: the source has no word timings, so index -1 marks every piece
    // and each owns a slice of the line's own progress — the light then wipes
    // left to right instead of every word filling at once.
    function buildRows(source, sentence, metrics, orderBase, isSub) {
        const spacing = root.rowSpacing
        const maxWidth = root.textWidth
        // Some providers return the whole line as a single "word" (text with
        // spaces). Split those into display words so the line can wrap instead
        // of overflowing; every piece keeps the original word index.
        const pieces = []
        // Manual row packing never breaks a piece — a piece without spaces (a
        // run of CJK characters, or a provider that sends the whole line as one
        // "word") would widen past the row and get cut at the right edge. Break
        // it into pieces that fit, per character if needed.
        const fitChunks = (text, idx) => {
            if (root.pieceWidth(text, metrics) <= maxWidth)
                return [{ index: idx, text: text }]
            const out = []
            let cur = ""
            for (const ch of String(text)) {
                if (cur !== "" && root.pieceWidth(cur + ch, metrics) > maxWidth) {
                    out.push({ index: idx, text: cur })
                    cur = ch
                } else {
                    cur += ch
                }
            }
            if (cur !== "") out.push({ index: idx, text: cur })
            return out
        }
        for (let i = 0; i < source.length; i++) {
            const parts = String(source[i].text ?? "").split(/\s+/).filter(s => s.length > 0)
            for (const part of parts)
                pieces.push(...fitChunks(part, sentence ? -1 : i))
        }
        if (pieces.length === 0) return []
        let cum = 0
        for (const p of pieces) {
            p.w = root.pieceWidth(p.text, metrics)
            p.start = cum
            cum += p.w + spacing
        }
        for (let i = 0; i < pieces.length; i++) {
            const p = pieces[i]
            const s = p.start
            p.order = orderBase + i
            p.start = cum > 0 ? s / cum : 0
            p.end = cum > 0 ? (s + p.w) / cum : 1
        }
        // Rows are packed by hand instead of with a Flow, because a Flow fills
        // the width and always left-aligns its rows — wrapping there looks
        // off-center in a narrow widget. Each row below is a centered Row.
        const rows = []
        let cur = [], curWidth = 0
        for (let i = 0; i < pieces.length; i++) {
            const w = pieces[i].w
            const need = cur.length === 0 ? w : curWidth + spacing + w
            if (cur.length > 0 && need > maxWidth) {
                rows.push(cur)
                cur = []
                curWidth = 0
            }
            cur.push(pieces[i])
            curWidth = cur.length === 1 ? w : curWidth + spacing + w
        }
        if (cur.length > 0) rows.push(cur)
        // The flag rides on the pieces, not on the row: a row is a list, and a
        // property added to a list does not survive the trip into a delegate's
        // modelData, while a property on an object does.
        for (const p of pieces)
            p.isSub = isSub
        return rows
    }

    function buildHotRows() {
        const line = (LyricsService.lyricsLines ?? [])[LyricsService.activeIndex]
        if (!line) return []
        // The words come off the line itself, not off a service property: the
        // service rewrites its word state every 50ms sync tick, and a row layout
        // rebuilt on that would throw away every word item 20 times a second.
        const words = line.words ?? []
        return root.buildRows(words.length > 0 ? words : [{ text: line.text || "" }],
            words.length === 0, hotMetrics, 0, false)
    }

    // The echo of the line being sung. Its entrance waits out the lead's
    // stagger, so the two never arrive in the same breath.
    function buildSubRows() {
        const bg = (LyricsService.lyricsLines ?? [])[LyricsService.activeIndex]?.bg
        if (!bg || !bg.text) return []
        const words = bg.words ?? []
        let leadPieces = 0
        for (const row of root.hotRows)
            leadPieces += row.length
        return root.buildRows(words.length > 0 ? words : [{ text: bg.text }],
            words.length === 0, subMetrics, leadPieces, true)
    }

    // How far through its own sweep a piece of the sung line stands. The echo
    // is sung on its own timings, so it is asked on its own index and progress
    // rather than riding the lead's.
    function wordProgress(piece, sweepIndex, sweepProgress) {
        if (piece.index < 0) {
            // Sentence-level source: one sweep across the whole line, each
            // piece taking its own slice of it.
            const p = LyricsService.activeLineProgress
            const span = Math.max(1e-4, piece.end - piece.start)
            return Math.min(1, Math.max(0, (p - piece.start) / span))
        }
        if (piece.index < sweepIndex) return 1
        if (piece.index === sweepIndex) return sweepProgress
        return 0
    }

    function entranceDelay(order) {
        // A 12-word line at 30ms per word would take 330ms, and the last words
        // would arrive after the line had already moved on in a fast song.
        return Math.min(order * 30, 150)
    }

    // About how tall the sung line is, read from the data instead of from the
    // item: asking `currentItem` for its height closes a binding loop, because
    // the band this feeds is what lays the item out. The karaoke column is the
    // only thing that wraps here, so its row count is the whole story.
    readonly property real hotLineGuess: {
        if (!root.karaoke) return hotMetrics.height
        const lead = root.hotRows.length > 0 ? root.hotRows.length : 1
        const sub = root.subRows.length
        const subH = sub > 0
            ? rowSpacing + sub * subMetrics.height + (sub - 1) * rowSpacing
            : 0
        return lead * hotMetrics.height + Math.max(0, lead - 1) * rowSpacing + subH
    }

    // One karaoke word: the base look this widget already had — a dim copy with
    // a pure white copy clipped to the fraction the karaoke has crossed, the
    // pair behind a glow — plus the two motions taken from the reference: the
    // word being sung rises a little and grows, and the words of a new line
    // come in one after another.
    component KaraokeWord: Item {
        id: wordItem

        required property string word
        required property int wordIndex
        required property real progress
        required property int order
        // A word of the echo rather than of the lead: smaller, dimmer, and it
        // does not rise or grow — the second voice answers from behind, and a
        // word of it jumping to the foreground would sing over the lead.
        property bool sub: false

        readonly property bool current: wordItem.progress > 0 && wordItem.progress < 1

        // Words that have been sung (or are being sung) are pure white, the
        // maximum brightness. Future words stay dim so the karaoke progress is
        // clearly visible. The echo sits a step further back on both counts.
        readonly property color litColor:
            wordItem.sub ? Qt.rgba(1, 1, 1, 0.8) : "#ffffff"
        readonly property color dimColor:
            wordItem.sub ? Qt.rgba(1, 1, 1, 0.2) : root.dimColor

        // Glow fades in on the active word and stays on after the word is
        // passed (slightly dimmed) so sung words keep glowing. The value is
        // driven from onProgressChanged instead of a binding so it can start at
        // 0 and animate up: every new line recreates the word items, and a
        // bound property would take its full value immediately, making the glow
        // pop in bright on the first word of each line.
        property real glowStrength: 0
        property bool glowReady: false
        onProgressChanged: {
            if (!wordItem.glowReady) return
            const target = wordItem.progress > 0
                ? (wordItem.current ? 1 : 0.6)
                : 0
            if (target !== wordItem.glowStrength) wordItem.glowStrength = target
        }
        Behavior on glowStrength { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

        // Entrance state; flipped true once the staggered pause for this word
        // ends. A short host gets no entrance at all (an 8px rise inside a
        // 40px-tall line just clips), so the words start already arrived.
        readonly property bool entranceAllowed: root.height >= 90
        property bool entered: !wordItem.entranceAllowed

        // Explicitly sized, not merely implicit: a Row lays out a zero-width
        // child by its implicit width and leaves the width itself at 0, and the
        // fill below is a fraction of that width — so a word that never fills.
        implicitWidth: dimText.implicitWidth
        implicitHeight: dimText.implicitHeight
        width: implicitWidth
        height: implicitHeight

        function replayEntrance() {
            if (!wordItem.entranceAllowed) return
            wordItem.entered = false
            entrance.restart()
        }
        Component.onCompleted: {
            wordItem.glowReady = true
            wordItem.replayEntrance()
        }

        SequentialAnimation {
            id: entrance
            PauseAnimation { duration: root.entranceDelay(wordItem.order) }
            PropertyAction { target: wordItem; property: "entered"; value: true }
        }

        StyledText {
            id: dimText
            anchors.fill: parent
            font.pixelSize: root.fontSizeFor(wordItem.sub ? root.subLineOffset : 0)
            color: wordItem.dimColor
            text: wordItem.word
        }

        // The sung part: the same text in white, clipped to the fraction the
        // sweep has crossed, so the light grows from the left of the word
        // instead of the whole word lighting at once.
        //
        // The glow layer sits on this item and not on the word: the word also
        // holds the dim copy, whose glyphs are opaque dark, and a glow reads
        // alpha — so a layer on the word haloed every letter of the word from
        // the first pixel of progress. Here the source is only what has been
        // sung, so the light follows the sweep.
        Item {
            id: litWord
            anchors {
                top: dimText.top
                bottom: dimText.bottom
                left: dimText.left
            }
            width: dimText.width
            height: dimText.height
            visible: wordItem.progress > 0

            // The layer stays on from the moment any part of the word is lit until
            // the line is replaced, so the fade never toggles it and blinks.
            layer.enabled: root.glowEnabled && wordItem.progress > 0
            layer.effect: Glow {
                radius: 7
                samples: 15
                spread: 0.15
                color: wordItem.litColor
                opacity: wordItem.glowStrength
                // Without this the layer is exactly the lit rectangle, and the
                // glow — which reaches about a radius past the ink — is cut flat
                // at every edge instead of spilling past the sweep line.
                transparentBorder: true
            }

            // The cut lives on an item of its own: `clip` would trim the glow
            // back to this rectangle and take the spill with it.
            Item {
                clip: true
                width: litWord.width * wordItem.progress
                height: litWord.height

                StyledText {
                    anchors.fill: parent
                    font: dimText.font
                    color: wordItem.litColor
                    text: wordItem.word
                }
            }
        }

        // Two separate Translate objects on purpose: the entrance rise and the
        // "sung word sits a little higher" lift have different triggers and
        // different clocks, and one property driven by both would fight its own
        // binding. Position (x/y) is never animated — that breaks layout.
        transform: [
            Translate {
                y: wordItem.entered ? 0 : 8
                Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
            },
            Translate {
                y: wordItem.current && !wordItem.sub ? -2 : 0
                Behavior on y { NumberAnimation {
                    duration: Appearance.animation.elementMoveSmall.duration
                    easing.type: Appearance.animation.elementMoveSmall.type
                    easing.bezierCurve: Appearance.animation.elementMoveSmall.bezierCurve
                } }
            }
        ]

        opacity: wordItem.entered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        // The source grows the word with font.pixelSize; a scale does the same
        // job without re-wrapping the row it sits in.
        scale: wordItem.current && !wordItem.sub ? 1.06 : 1.0
        Behavior on scale { NumberAnimation {
            duration: Appearance.animation.elementMoveSmall.duration
            easing.type: Appearance.animation.elementMoveSmall.type
            easing.bezierCurve: Appearance.animation.elementMoveSmall.bezierCurve
        } }
    }

    // The line list itself. The loading indicator overlays it instead of being
    // a competing child, so toggling status can never squeeze the lines away.
    // Its box is of the widget's width and grown by `overflowY` at both ends, so
    // the cut — when there is one — stays centred on the widget, and the
    // highlight band, which is stated against the widget, does not drift with
    // the extra room.
    ListView {
        id: lineList
        x: 0
        width: root.width
        y: -root.overflowY
        height: Math.max(0, root.height + 2 * root.overflowY)
        clip: root.clipOverflowY >= 0
        model: root.lineRows
        spacing: root.lineSpacing
        boundsBehavior: Flickable.StopAtBounds
        interactive: false

        currentIndex: LyricsService.activeIndex
        // The glide to the next line comes from the highlight: the list pans so
        // that the current item stays inside the band around the middle, and it
        // pans over motionDuration instead of jumping. The band is stated
        // against the widget rather than the grown viewport, so the first and
        // last line of a song — where the list cannot pan far enough to centre
        // — come to rest inside the widget instead of in the overflow.
        //
        // A windowed host gets the exact middle instead of the ±40 slack: its
        // block of lines is a fixed size, so there is nothing for the line to
        // drift toward, and the slack only ever pulled it to the bottom edge of
        // it — a sung line with two dead lines under it, hanging in the lower
        // half of a card that had nothing left to show. The band is a single
        // point, which is the edge the list lays the incoming line on, and it
        // sits half a sung line above the middle so that the line's *middle* is
        // what lands there: stating the middle as the line's top left the whole
        // block, and the two lines behind it, a line too low to fit.
        readonly property real widgetMiddle: root.overflowY + root.height / 2
        readonly property real sungPoint: Math.max(0, widgetMiddle - root.hotLineGuess / 2)
        highlightFollowsCurrentItem: true
        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: root.lineContext < 0
            ? root.overflowY + Math.max(0, root.height / 2 - 40)
            : sungPoint
        preferredHighlightEnd: root.lineContext < 0
            ? root.overflowY + Math.min(root.height, root.height / 2 + 40)
            : sungPoint
        highlightMoveDuration: root.motionDuration
        highlightResizeDuration: root.motionDuration
        // Only the anchor the glide works from; drawing a box behind the line
        // would fight the karaoke colours.
        highlight: Item {}

        delegate: Item {
            id: lineRow
            required property int index
            required property var modelData

            readonly property bool isNote: modelData.note
            readonly property bool isHot: index === LyricsService.activeIndex
            readonly property int dist: Math.abs(index - LyricsService.activeIndex)
            // Sung by a voice other than the lead: this line goes to the far
            // edge of the text area instead of the near one.
            readonly property bool otherVoice: modelData.otherVoice === true
            // The note row carries no echo, so the field is not always there.
            readonly property string bgText: modelData.bgText ?? ""
            // The window: the same number of lines on each side, and nothing
            // beyond it. A line three steps away says nothing about the moment
            // the song is in, however much room the host has for it.
            readonly property bool within: root.lineContext < 0
                || lineRow.dist <= root.lineContext
            readonly property bool useKaraoke: root.karaoke
                && lineRow.isHot
                && !lineRow.isNote
                && root.hotRows.length > 0

            opacity: lineRow.within ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

            width: lineList.width
            implicitHeight: lineRow.isNote ? noteRow.implicitHeight
                : (lineRow.useKaraoke ? hotColumn.implicitHeight : plainColumn.implicitHeight)
            height: implicitHeight

            // Provider attribution: small, dim, centered, never highlighted.
            StyledText {
                id: noteRow
                width: lineRow.width
                height: implicitHeight
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: root.textColor
                opacity: 0.4
                text: lineRow.modelData.text
                visible: lineRow.isNote
            }

            Column {
                id: hotColumn
                x: root.contentInset
                width: root.textWidth
                spacing: root.rowSpacing
                visible: lineRow.useKaraoke
                anchors.verticalCenter: lineRow.verticalCenter
                // Which edge the sung line belongs to. The column only ever
                // holds the active line, so it can carry that one flag for the
                // rows inside it to read.
                readonly property bool far: lineRow.otherVoice

                Repeater {
                    model: lineRow.useKaraoke ? root.sungRows : []
                    delegate: Row {
                        id: wordRow
                        required property var modelData
                        // Lead row or echo row, read off the pieces it holds: a
                        // flag put on the row itself would not survive the trip
                        // into modelData, one put on an object does.
                        readonly property bool isSub: wordRow.modelData[0]?.isSub === true
                        spacing: hotColumn.spacing
                        // Centered when the widget asks for centered lyrics,
                        // otherwise flush with the inset left edge. Centering on
                        // the column rather than the row keeps the line in the
                        // middle of the text area, not of the clipped widget.
                        // A song with two voices overrides the host: the far
                        // voice reads as the far voice only if it sits there.
                        anchors.horizontalCenter: !root.duet
                            && root.textAlignment === Text.AlignHCenter
                            ? hotColumn.horizontalCenter : undefined
                        anchors.left: !hotColumn.far
                            && (root.duet || root.textAlignment !== Text.AlignHCenter)
                            ? hotColumn.left : undefined
                        anchors.right: hotColumn.far ? hotColumn.right : undefined

                        Repeater {
                            model: wordRow.modelData
                            delegate: KaraokeWord {
                                required property var modelData
                                sub: wordRow.isSub
                                word: modelData.text
                                wordIndex: modelData.index
                                order: modelData.order
                                progress: root.wordProgress(modelData,
                                    wordRow.isSub
                                        ? LyricsService.activeBgWordIndex
                                        : LyricsService.activeWordIndex,
                                    wordRow.isSub
                                        ? LyricsService.activeBgWordProgress
                                        : LyricsService.activeWordProgress)
                                // No Behavior on progress: the service pushes a
                                // new value every 50ms and an animation would
                                // only lag behind it, so the sweep would crawl
                                // after the audio instead of tracking it.
                            }
                        }
                    }
                }
            }

            // Which edge this line's text belongs to, shared by the line and by
            // the echo under it: a background vocal answers the voice above it,
            // so it goes to the same side rather than picking a side of its own.
            readonly property int textHAlign: root.duet
                ? (lineRow.otherVoice ? Text.AlignRight : Text.AlignLeft)
                : root.textAlignment

            // Everything that is not a karaoke line: the past/future lines and
            // a widget with karaoke off. The active line wraps, the others stay
            // one line and are elided. The font ladder already carries the
            // distance, so no extra scale on the neighbours.
            Column {
                id: plainColumn
                x: root.contentInset
                width: root.textWidth
                anchors.verticalCenter: lineRow.verticalCenter
                spacing: root.rowSpacing
                visible: !lineRow.isNote && !lineRow.useKaraoke

                StyledText {
                    id: plainRow
                    width: plainColumn.width
                    height: implicitHeight
                    horizontalAlignment: lineRow.textHAlign
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: lineRow.isHot ? Text.WrapAtWordBoundaryOrAnywhere : Text.NoWrap
                    maximumLineCount: lineRow.isHot ? 3 : 1
                    elide: Text.ElideRight
                    text: lineRow.modelData.text
                    font.pixelSize: root.fontSizeFor(lineRow.dist)
                    opacity: root.opacityFor(lineRow.dist)
                    color: lineRow.isHot ? root.activeColor : root.textColor
                    Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                }

                // The echo of a line that is not being sung. It has no per-word
                // sweep — the service only tracks the words of the active line —
                // so it arrives as text, stepped down the font ladder past its
                // lead and dimmer than it, which is what a voice from the back
                // of the room looks like.
                StyledText {
                    id: plainSub
                    width: plainColumn.width
                    height: implicitHeight
                    horizontalAlignment: lineRow.textHAlign
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: plainRow.wrapMode
                    maximumLineCount: plainRow.maximumLineCount
                    elide: Text.ElideRight
                    visible: lineRow.bgText.length > 0
                    text: lineRow.bgText
                    font.pixelSize: root.fontSizeFor(lineRow.dist + root.subLineOffset)
                    opacity: root.opacityFor(lineRow.dist) * 0.75
                    color: lineRow.isHot ? root.activeColor : root.textColor
                    Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                }
            }
        }
    }

    // Loading indicator overlay (stacked above the lines, not a list row).
    Item {
        anchors.fill: parent
        visible: LyricsService.status !== "ok"
        z: 2

        Column {
            anchors.centerIn: parent
            spacing: 12

            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                implicitWidth: 48
                implicitHeight: 48

                MaterialLoadingIndicator {
                    anchors.fill: parent
                    loading: LyricsService.status === "loading"
                    colBg: root.indicatorColor
                    colShape: root.indicatorShapeColor
                    implicitSize: 48
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: LyricsService.restartLyrics()
                }
            }
        }
    }
}
