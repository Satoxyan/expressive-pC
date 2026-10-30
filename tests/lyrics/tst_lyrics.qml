import QtQuick
import QtTest
import qs.modules.common
import qs.services
import qs.modules.common.widgets

// The karaoke view: line list, wrapped word rows, and the glide that carries
// the active line to the middle band.
TestCase {
    name: "LyricsKaraoke"
    when: windowShown
    width: 400
    height: 150

    id: subject

    Lyrics {
        id: lyrics
        anchors.fill: parent
    }

    // A widget with considerably more room than a window needs, so the window
    // itself — not the edge of the clip box — is what decides what is drawn.
    Lyrics {
        id: tallLyrics
        width: 400
        height: 300
        lineContext: 2
    }

    // The ListView lives inside the widget; reach it the way the widget's own
    // layout does, without exporting it as a public property.
    function list(widget) {
        const target = widget ?? lyrics
        for (let i = 0; i < target.children.length; i++) {
            const c = target.children[i]
            if (c.preferredHighlightBegin !== undefined)
                return c
        }
        return null
    }

    // A song of `count` lines, each with five word timings.
    function song(count) {
        const lines = []
        for (let i = 0; i < count; i++) {
            lines.push({
                text: "line " + i + " of the song",
                time: i * 3,
                words: [
                    { text: "line", time: i * 3 },
                    { text: String(i), time: i * 3 + 0.5 },
                    { text: "of", time: i * 3 + 1 },
                    { text: "the", time: i * 3 + 1.5 },
                    { text: "song", time: i * 3 + 2 }
                ]
            })
        }
        return lines
    }

    function init() {
        LyricsService.load([], "")
    }

    // The wrapped rows as laid out: the karaoke Column is the delegate's child
    // that has a spacing but no text, and its children are the word Rows.
    function wordRows(item) {
        for (const c of item.children) {
            if (c === undefined || c.text !== undefined || c.spacing === undefined)
                continue
            const rows = []
            for (const g of c.children)
                if (g.text === undefined && g.children.length > 0)
                    rows.push(g)
            if (rows.length > 0)
                return rows
        }
        return []
    }

    // ── model ───────────────────────────────────────────────────────────────
    function test_rows_are_lines_plus_attribution() {
        LyricsService.load(song(3), "musixmatch")
        compare(lyrics.lineRows.length, 4, "one trailing note row")
        verify(lyrics.lineRows[3].note, "last row is the note")
        verify(!lyrics.lineRows[0].note, "lyric rows are not notes")
    }

    function test_rows_without_provider_have_no_note() {
        LyricsService.load(song(3), "")
        compare(lyrics.lineRows.length, 3)
    }

    // ── word layout of the active line ─────────────────────────────────────
    function test_word_pieces_keep_their_word_index() {
        LyricsService.load(song(1), "")
        LyricsService.activate(0)
        LyricsService.activeWordIndex = 2
        LyricsService.activeWordProgress = 0.5
        const flat = rows_flat()
        compare(flat.length, 5, "five display words")
        for (let i = 0; i < flat.length; i++)
            compare(flat[i].index, i, "piece " + i + " keeps its word index")
    }

    function test_every_row_fits_the_widget() {
        LyricsService.load([{ text: "a very long line that cannot possibly fit in one row of a narrow widget and has to wrap several times over", time: 0,
                              words: "a very long line that cannot possibly fit in one row of a narrow widget and has to wrap several times over".split(" ")
                                  .map((w, i) => ({ text: w, time: i * 0.2 })) }], "")
        LyricsService.activate(0)
        wait(300)
        const maxWidth = lyrics.textWidth
        const rows = lyrics.hotRows
        verify(rows.length > 1, "long line wraps (rows=" + rows.length + ")")
        for (const row of rows) {
            let w = 0
            for (const p of row)
                w += p.w + lyrics.rowSpacing
            verify(w - lyrics.rowSpacing <= maxWidth + 1,
                "row width " + (w - lyrics.rowSpacing).toFixed(1) + " <= " + maxWidth)
        }
        // The height proves the wrapped rows were actually instantiated and
        // stacked, not just computed: one row would be a single line tall.
        const hot = list().currentItem
        verify(hot.height > rows.length * Appearance.font.pixelSize.smallest,
            "row heights stack in the widget (" + hot.height.toFixed(1) + " for "
            + rows.length + " rows)")
        // And no laid-out row may stick out of the widget: measuring words on
        // the font advance alone (without their side bearings) used to.
        const laid = wordRows(hot)
        compare(laid.length, rows.length, "every computed row exists")
        // The rows sit inside the clip edge, so the glow of the first word has
        // something other than a hard cut to run into. The rows themselves are
        // placed by the column, so it is the column that carries the inset.
        verify(laid[0].parent.x >= lyrics.contentInset - 1,
            "the word column starts at the inset (" + laid[0].parent.x.toFixed(1) + ")")
        for (const row of laid)
            verify(row.width <= maxWidth + 1,
                "rendered row " + row.width.toFixed(1) + " <= " + maxWidth)
    }

    function test_a_spaceless_run_is_split_so_it_cannot_overflow() {
        // Providers hand back whole CJK lines as one "word"; without splitting
        // them the row would run past the widget edge.
        const long = "一".repeat(200)
        LyricsService.load([{ text: long, time: 0, words: [{ text: long, time: 0 }] }], "")
        LyricsService.activate(0)
        const maxWidth = lyrics.textWidth
        for (const row of lyrics.hotRows)
            for (const p of row)
                verify(p.w <= maxWidth, "piece fits: " + p.w.toFixed(1) + " <= " + maxWidth)
    }

    function test_sentence_sweep_slices_the_line() {
        // No word timings: every piece is marked -1 and owns a slice of the
        // line's own progress, in reading order.
        LyricsService.load([{ text: "one two three four", time: 0 }], "")
        LyricsService.activate(0)
        const flat = rows_flat()
        compare(flat.length, 4)
        for (const p of flat) {
            compare(p.index, -1, "sentence sweep has no word index")
            verify(p.start >= 0 && p.end <= 1 && p.start < p.end,
                "slice in 0..1 (" + p.start + ", " + p.end + ")")
        }
        for (let i = 1; i < flat.length; i++)
            verify(flat[i].start > flat[i - 1].start, "slices go left to right")
    }

    function test_progress_is_never_nan() {
        LyricsService.load([{ text: "solo", time: 0, words: [{ text: "solo", time: 0 }] }], "")
        LyricsService.activate(0)
        LyricsService.activeWordIndex = 0
        LyricsService.activeWordProgress = 1
        const p = rows_flat()[0]
        verify(!Number.isNaN(p.start) && !Number.isNaN(p.end))
    }

    // ── entrance stagger ───────────────────────────────────────────────────
    function test_entrance_delay_is_clamped() {
        compare(lyrics.entranceDelay(0), 0)
        compare(lyrics.entranceDelay(3), 90)
        compare(lyrics.entranceDelay(12), 150, "long lines never stall the entrance")
        compare(lyrics.entranceDelay(80), 150)
    }

    // The word items of a laid-out row, in reading order. A Row also lists the
    // Repeater that made them among its children, so filter by the property
    // only a word carries.
    function wordsOf(row) {
        return row.children.filter(c => c.word !== undefined)
    }

    // The sung part of a word: the item that clips the white copy to the sweep.
    // It sits one level under the glow layer, because a clip on the layer itself
    // would trim the glow's spill back to the rectangle. The dim copy, the layer
    // and the entrance animation do not clip.
    function fillOf(word) {
        for (const c of word.children) {
            if (c.clip === true) return c
            const inner = (c.children ?? []).find(g => g.clip === true)
            if (inner) return inner
        }
        return null
    }

    // ── the sweep, and the rise on top of it ───────────────────────────────
    // Nothing here reads `visible`: offscreen the whole window reports false,
    // so the fill's own width is the measurable state.
    function test_light_grows_with_the_sweep_inside_a_word() {
        LyricsService.load(song(1), "")
        LyricsService.activate(0)
        wait(250) // the delegate for the active line has to materialise first
        const words = wordsOf(wordRows(list().currentItem)[0])
        compare(words.length, 5, "the line laid out as five words")
        // The middle word, so that there is one on each side of the sweep to
        // check against.
        const word = words[2]
        // The fill is a fraction of the word's own width, so a word that never
        // sized itself would make every assertion below pass at zero.
        verify(word.width > 10, "the word sized itself (" + word.width + ")")

        LyricsService.activeWordIndex = 2
        for (const p of [0.25, 0.5, 0.75]) {
            LyricsService.activeWordProgress = p
            wait(60)
            const fill = fillOf(word)
            verify(fill !== null, "the word has a lit fill")
            if (fill === null) return
            // A glow reads alpha, and the dim copy is opaque dark ink, so the
            // layer must sit on the lit copy alone — on the word it would halo
            // every letter the sweep has not reached yet.
            verify(word.layer?.enabled !== true, "the word itself carries no glow layer")
            verify(fill.parent.layer?.enabled === true, "the lit copy carries the glow layer")
            compare(Math.round(fill.width), Math.round(p * word.width),
                "lit to " + p + " of the word (" + fill.width.toFixed(1)
                + " of " + word.width.toFixed(1) + ")")
        }

        // The words the sweep left behind stay filled and keep glowing; the
        // ones ahead of it are still nothing but their dim copy.
        compare(fillOf(words[0]).width, words[0].width, "a finished word is filled")
        verify(words[0].glowStrength > 0, "and still glows")
        compare(fillOf(words[4]).width, 0, "an unsung word has nothing lit")

        // The ported motion: only the word being sung rises, and it is the one
        // word that does.
        wait(200)
        compare(words[2].scale, 1.06, "the current word is enlarged")
        compare(words[0].scale, 1.0, "a finished word sits back down")
    }

    // Where a row sits inside the viewport: the item's document y minus the
    // pan the list has applied.
    function viewTop(view, item) {
        return item.y - view.contentY
    }

    // ── the glide ──────────────────────────────────────────────────────────
    function test_line_change_glides_instead_of_teleporting() {
        const view = list()
        LyricsService.load(song(20), "")
        LyricsService.activate(0)
        wait(60)
        const from = view.contentY
        LyricsService.activate(6)
        wait(220)
        const mid = view.contentY
        wait(600)
        const to = view.contentY
        verify(to > from, "the list panned toward the line (" + from.toFixed(1) + " -> " + to.toFixed(1) + ")")
        verify(mid > from && mid < to,
            "it panned in steps, not at once (mid=" + mid.toFixed(1) + ")")
    }

    function test_active_line_rests_inside_the_highlight_band() {
        const view = list()
        verify(view.preferredHighlightBegin < view.preferredHighlightEnd,
            "band is " + view.preferredHighlightBegin + ".." + view.preferredHighlightEnd)
        LyricsService.load(song(20), "")
        LyricsService.activate(9)
        wait(700)
        const item = view.currentItem
        verify(item !== null, "current item materialised")
        if (item === null) return
        const top = viewTop(view, item)
        const bottom = top + item.height
        verify(top >= view.preferredHighlightBegin - 1 && bottom <= view.preferredHighlightEnd + 1,
            "line rests in the band (top=" + top.toFixed(1) + " bottom=" + bottom.toFixed(1)
            + " band=" + view.preferredHighlightBegin + ".." + view.preferredHighlightEnd + ")")
    }

    function test_the_clip_box_follows_the_host_overflow_setting() {
        const view = list()
        // Default: the widget edge is the bound, which is what the dashboard
        // and the sidebar need.
        compare(lyrics.clipOverflowY, 0, "no overflow unless the host asks")
        compare(view.height, lyrics.height, "the box is the widget")
        compare(view.y, 0, "flush with its top")

        lyrics.clipOverflowY = 24
        compare(view.height, lyrics.height + 48, "a host may grow it at both ends")
        compare(view.y, -24, "grown symmetrically")
        compare(view.height / 2 + view.y, lyrics.height / 2,
            "so its middle is still the widget's middle")
        verify(!lyrics.clip, "and the widget itself never clips")
        lyrics.clipOverflowY = 0

        // Negative is a mode, not an amount of room: the list keeps the widget's
        // box and the band it was given, and only stops cutting.
        lyrics.clipOverflowY = -1
        verify(!view.clip, "a host may take the clip out")
        compare(view.y, 0, "with no room grown out of the setting")
        compare(view.height, lyrics.height)
        compare(view.preferredHighlightBegin, lyrics.height / 2 - 40,
            "the band is still stated against the widget")
        compare(view.preferredHighlightEnd, lyrics.height / 2 + 40)
        compare(lyrics.overflowY, 0, "and the setting adds nothing to the geometry")
        lyrics.clipOverflowY = 0
    }

    function test_the_last_line_rests_inside_the_widget() {
        // The band is stated against the widget, not against the grown
        // viewport: at the ends of a song the list cannot pan far enough to
        // centre, and the line must not come to rest in the overflow.
        const view = list()
        lyrics.clipOverflowY = 24
        LyricsService.load(song(20), "")
        LyricsService.activate(19)
        wait(700)
        const item = view.currentItem
        verify(item !== null, "current item materialised")
        if (item === null) return
        const top = viewTop(view, item)
        const widgetTop = lyrics.overflowY
        verify(top >= widgetTop - 1 && top + item.height <= widgetTop + lyrics.height + 1,
            "the last line stays in the widget (top=" + top.toFixed(1)
            + " bottom=" + (top + item.height).toFixed(1) + ")")
        lyrics.clipOverflowY = 0
    }

    // ── the context window ─────────────────────────────────────────────────
    // The rows the list actually holds right now: a released row keeps its
    // last position but reports an index of -1, so the index is the filter.
    function liveRows(view) {
        const out = []
        for (let i = 0; i < view.count; i++) {
            const it = view.itemAtIndex(i)
            if (it !== null && it.index >= 0)
                out.push(it)
        }
        return out
    }

    function test_the_window_is_the_same_number_of_lines_on_each_side() {
        const view = list(tallLyrics)
        compare(lyrics.lineContext, -1, "a host that asks for nothing draws the whole list")
        LyricsService.load(song(20), "")
        LyricsService.activate(9)
        wait(900)
        verify(view.currentItem !== null, "the sung line exists")

        const shown = liveRows(view).filter(r => r.opacity > 0.99)
            .map(r => r.index).sort((a, b) => a - b)
        compare(shown.join(","), [7, 8, 9, 10, 11].join(","),
            "two lines on each side of the sung one, and no more")

        // Rows past the window must still be inside the clip box, or this would
        // only be proving that the edge of a widget hides them.
        for (const i of [7, 12]) {
            const row = view.itemAtIndex(i)
            verify(row !== null, "line " + i + " is instantiated")
            if (row === null) return
            const top = viewTop(view, row)
            verify(top >= -1 && top + row.height <= view.height + 1,
                "line " + i + " sits whole inside the clip box")
        }
        compare(view.itemAtIndex(12).within, false, "the window is what cuts it")
        compare(view.itemAtIndex(12).opacity, 0, "and it is really hidden")

        // And with a fixed block of text to show, the sung line is lifted so its
        // middle, not its top, is what reaches the middle of the widget: the
        // point band sits half a sung line above it, because the list lays the
        // line's top on the point it is given. Stating the middle as the top left
        // the whole block, and the lines behind it, a line too low to fit.
        const hot = view.currentItem
        compare(Math.round(viewTop(view, hot) + hot.height / 2),
            Math.round(view.widgetMiddle),
            "the windowed widget puts its sung line at the middle")
    }

    function test_an_unwindowed_widget_keeps_the_band_slack() {
        const view = list()
        compare(view.preferredHighlightBegin, Math.max(0, lyrics.height / 2 - 40),
            "the dashboard and the sidebar keep the band they always had")
        compare(view.preferredHighlightEnd, Math.min(lyrics.height, lyrics.height / 2 + 40))
    }

    function test_hot_line_is_taller_than_its_neighbours() {
        const view = list()
        LyricsService.load(song(20), "")
        LyricsService.activate(5)
        wait(500)
        const hot = view.itemAtIndex(5)
        const near = view.itemAtIndex(7)
        verify(hot !== null && near !== null, "both rows instantiated")
        if (hot === null || near === null) return
        verify(hot.height > near.height,
            "active row is taller than a neighbour (" + hot.height + " vs " + near.height + ")")
    }

    // Flatten the wrapped rows back into one list of pieces.
    function rows_flat() {
        const out = []
        for (const row of lyrics.hotRows)
            for (const p of row)
                out.push(p)
        return out
    }
}
