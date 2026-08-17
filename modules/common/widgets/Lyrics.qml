pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

Item {
    id: root

    // Never paint beyond the widget: when the active line grows to many
    // rows, the overflow is cut at the edge instead of overlapping the
    // info column.
    clip: true

    property color textColor: "white"
    property color activeColor: "white"
    property color dimColor: Qt.rgba(1, 1, 1, 0.35)
    property color indicatorColor: Appearance.colors.colPrimaryContainer
    property color indicatorShapeColor: Appearance.colors.colOnPrimaryContainer
    property int textAlignment: Text.AlignLeft

    property bool karaoke: true

    implicitWidth: 200
    implicitHeight: 200

    readonly property int activeFontSize: Appearance.font.pixelSize.normal
    readonly property int adjFontSize: Appearance.font.pixelSize.smaller
    readonly property int farFontSize: Appearance.font.pixelSize.smallest

    function fontSizeFor(dist) {
        // Big (active) to small (far) gradient, stepping every slot so the
        // past/future lines visibly shrink away from the highlighted one.
        return Math.max(root.farFontSize, root.activeFontSize - dist * 2)
    }
    function opacityFor(dist) {
        if (dist === 0) return 1.0
        if (dist === 1) return 0.6
        if (dist === 2) return 0.35
        return 0.15
    }

    // ── Apple Music-style karaoke word sweep ───────────────────────────────
    // One word: dim base text + active-color copy clipped to the sung
    // fraction (clip-sweep). The currently-sung word additionally gets a glow.

    component KaraokeWord: Item {
        id: wordItem
        required property string word
        required property int wordIndex
        required property real progress
        required property color sungColor
        required property color dimColor
        required property int fontSize

        readonly property bool current: wordItem.progress > 0 && wordItem.progress < 1

        // The sung color from the theme is a mid-tone that barely reads on
        // the artwork-blurred background, so brighten it toward white for
        // the swept fill and the glow.
        readonly property color brightSung: Qt.lighter(wordItem.sungColor, 1.6)

        // Glow fades in on the active word and stays on after the word is
        // passed (slightly dimmed) so sung words keep glowing.
        property real glowStrength: wordItem.progress > 0
            ? (wordItem.current ? 1 : 0.6)
            : 0
        Behavior on glowStrength { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

        implicitWidth: dimText.implicitWidth
        implicitHeight: dimText.implicitHeight

        // Dim base (future word)
        Text {
            id: dimText
            anchors.fill: parent
            font {
                family: Appearance.font.family.main
                pixelSize: wordItem.fontSize
                variableAxes: Appearance.font.variableAxes.main
            }
            color: wordItem.dimColor
            text: wordItem.word
            horizontalAlignment: Text.AlignLeft
            verticalAlignment: Text.AlignVCenter
        }

        // Active-color copy, clipped to the sung fraction
        Item {
            id: fillClip
            anchors {
                top: dimText.top
                bottom: dimText.bottom
                left: dimText.left
            }
            clip: true
            width: dimText.width * wordItem.progress

            Text {
                anchors.fill: parent
                font {
                    family: dimText.font.family
                    pixelSize: dimText.font.pixelSize
                    variableAxes: dimText.font.variableAxes
                }
                color: wordItem.brightSung
                text: wordItem.word
                horizontalAlignment: Text.AlignLeft
                verticalAlignment: Text.AlignVCenter
            }

            visible: wordItem.progress > 0
        }

        // Glow behind the currently-sung word. The layer turns on once the
        // word starts being sung and stays on for the rest of the line
        // (progress stays 1 after completion), so the fade-out never
        // toggles the layer and blinks.
        layer.enabled: wordItem.progress > 0
        layer.effect: Glow {
            radius: 10
            samples: 21
            spread: 0.25
            color: wordItem.brightSung
            opacity: 0.8 * wordItem.glowStrength
        }
    }

    // The slots column always fills the widget and is always visible.
    // The loading indicator overlays it instead of being a competing
    // layout child, so toggling status can never squeeze the slots away
    // (which piled all seven lines up at the top).
    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        Repeater {
            model: LyricsService.total
            delegate: Item {
                id: slotItem
                required property int index
                Layout.fillWidth: true
                // The active slot sizes to its wrapped line (karaoke rows,
                // or the fallback text broken onto two rows) via preferred
                // height instead of sharing the fill space, so over-long
                // lyrics are not clipped at the widget edge; the others
                // fill and share the remaining height equally.
                Layout.fillHeight: !slotItem.isActiveSlot
                Layout.preferredHeight: slotItem.isActiveSlot
                    ? slotItem.useKaraoke
                        ? Math.min(slotItem.karaokeContentHeight, Math.max(root.activeFontSize * 5, root.height - root.activeFontSize * 3))
                        : slotItem.fallbackContentHeight
                    : undefined

                readonly property int dist: Math.abs(index - LyricsService.before)
                readonly property bool isActiveSlot: index === LyricsService.before
                readonly property bool isNoteSlot: index === LyricsService.noteSlot
                    && LyricsService.noteSlot >= 0
                    && LyricsService.providedBy.length > 0
                readonly property bool useKaraoke: root.karaoke
                    && slotItem.isActiveSlot
                    && (LyricsService.activeLineWords?.length ?? 0) > 0

                // Per-word karaoke line. Rows are computed manually instead
                // of using a Flow, because a Flow fills the width and always
                // left-aligns its rows — wrapping there looks off-center in a
                // narrow widget. Each row below is a centered Row instead.
                readonly property var karaokeRows: slotItem.buildKaraokeRows()

                // Full height the wrapped karaoke line needs: every row plus
                // the spacing between them, so the active slot can grow to
                // fit instead of clipping the extra rows. The column's
                // implicit height is the real rendered height (font metrics
                // underestimate the line height slightly).
                readonly property real karaokeContentHeight: karaokeColumn.implicitHeight

                // Wrapped height of the active fallback text (songs without
                // per-word timestamps): one line if it fits the slot width,
                // otherwise two (the Text caps at two lines and elides the
                // rest). Measured with a real text instead of font metrics
                // because the rendered line height differs slightly from
                // QFontMetrics, which would clip the second line.
                readonly property real fallbackContentHeight:
                    fallbackMeter.height > 0 ? fallbackMeter.height : fallbackMetrics.height

                // Invisible meter: same width/font/wrapping as the active
                // line, so its height is exactly what the slot must reserve.
                StyledText {
                    id: fallbackMeter
                    opacity: 0
                    width: slotItem.width
                    font.pixelSize: root.fontSizeFor(0)
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    text: LyricsService.slots[slotItem.index] ?? ""
                }

                FontMetrics {
                    id: fallbackMetrics
                    font {
                        family: Appearance.font.family.main
                        pixelSize: root.fontSizeFor(0)
                        variableAxes: Appearance.font.variableAxes.main
                    }
                }

                function buildKaraokeRows() {
                    const words = LyricsService.activeLineWords ?? []
                    if (words.length === 0) return []
                    const spacing = karaokeColumn.spacing
                    const maxWidth = Math.max(1, slotItem.width)
                    // Some providers return the whole line as a single "word"
                    // (text with spaces). Split those into display words so the
                    // line can wrap instead of overflowing the slot; every piece
                    // keeps the original word index for the highlight sweep.
                    const pieces = []
                    for (let i = 0; i < words.length; i++) {
                        const parts = String(words[i].text ?? "").split(/\s+/).filter(s => s.length > 0)
                        for (const part of parts) pieces.push({ index: i, text: part })
                    }
                    if (pieces.length === 0) return []
                    const rows = []
                    let cur = [], curWidth = 0
                    for (let i = 0; i < pieces.length; i++) {
                        const w = karaokeMetrics.advanceWidth(pieces[i].text)
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
                    return rows
                }

                FontMetrics {
                    id: karaokeMetrics
                    font {
                        family: Appearance.font.family.main
                        pixelSize: root.fontSizeFor(0)
                        variableAxes: Appearance.font.variableAxes.main
                    }
                }

                Column {
                    id: karaokeColumn
                    anchors.fill: parent
                    spacing: 6
                    visible: slotItem.useKaraoke
                    // Anything that overflows the slot is clipped so it never
                    // touches the line above or below.
                    clip: true

                    Repeater {
                        model: slotItem.useKaraoke ? slotItem.karaokeRows : []
                        delegate: Row {
                            required property var modelData
                            spacing: karaokeColumn.spacing
                            // Center every row when the widget asks for centered
                            // lyrics; otherwise start at the left edge.
                            anchors.horizontalCenter: root.textAlignment === Text.AlignHCenter
                                ? parent.horizontalCenter : undefined
                            anchors.left: root.textAlignment === Text.AlignHCenter
                                ? undefined : parent.left

                            Repeater {
                                model: modelData
                                delegate: KaraokeWord {
                                    required property var modelData
                                    word: modelData.text
                                    wordIndex: modelData.index
                                    fontSize: root.fontSizeFor(0)
                                    sungColor: root.activeColor
                                    dimColor: root.dimColor
                                    progress: {
                                        const cur = LyricsService.activeWordIndex
                                        if (wordIndex < cur) return 1
                                        if (wordIndex === cur)
                                            return LyricsService.activeWordProgress
                                        return 0
                                    }
                                    Behavior on progress {
                                        // Short chase so the fill tracks the audio
                                        // closely instead of lagging/jumping per word.
                                        NumberAnimation { duration: 60; easing.type: Easing.Linear }
                                    }
                                }
                            }
                        }
                    }
                }

                // Fallback single-line (no karaoke, or non-active slots).
                // The active line wraps onto a second row when too long;
                // the others stay one row and are elided if needed.
                StyledText {
                    id: lyricSlot
                    anchors.fill: parent
                    horizontalAlignment: root.textAlignment
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: slotItem.isActiveSlot ? Text.WordWrap : Text.NoWrap
                    maximumLineCount: slotItem.isActiveSlot ? 2 : 1
                    elide: Text.ElideRight
                    text: LyricsService.slots[index] ?? ""
                    font.pixelSize: root.fontSizeFor(slotItem.dist)
                    opacity: root.opacityFor(slotItem.dist)
                    color: slotItem.dist === 0 ? root.activeColor : root.textColor
                    visible: !slotItem.useKaraoke && !slotItem.isNoteSlot
                    Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                }

                // Provider attribution: scrolls in as its own slot right
                // after the last lyric line, but stays small, dim and
                // centered — never part of the highlight.
                StyledText {
                    id: noteSlot
                    anchors.fill: parent
                    visible: slotItem.isNoteSlot
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: root.textColor
                    opacity: 0.4
                    text: "Lyrics provided by " + LyricsService.providedBy
                }
            }
        }
    }

    // Loading indicator overlay (stacked above the slots, not a layout child).
    Item {
        anchors.fill: parent
        visible: LyricsService.status !== "ok"
        z: 2

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 12

            Item {
                Layout.alignment: Qt.AlignHCenter
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