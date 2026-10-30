// The instrumental stretches in a lyric list, and the rows they take.
// Ported from Mixtapes' find_interludes (src/ui/widgets/lyric_rows.rs).

// A stretch shorter than this is a breath between two lines, not a break.
var MIN_GAP_S = 5.0
// How many dots a break counts out.
var DOTS = 3

// When a line stops being sung. Providers give a word's start and never its
// end, so the last word plus the longest span the sweep may run is as far as
// anything can know; a line without word timings has no knowable end, and
// marking a break after it would have the countdown and the sweep of the same
// line running at once.
function sweepEnd(line, maxWordSpan) {
    const words = line?.words ?? []
    if (words.length === 0) return null
    const last = Number(words[words.length - 1]?.time)
    if (isNaN(last)) return null
    return last + maxWordSpan
}

// The breaks of a song as [{time, end}], in the same seconds the lines use.
function findInterludes(lines, maxWordSpan) {
    const out = []
    const sung = []
    for (const line of lines ?? []) {
        const t = Number(line?.time)
        if (!isNaN(t) && String(line.text ?? "").trim() !== "")
            sung.push({ time: t, words: line.words ?? [] })
    }
    if (sung.length === 0) return out
    // A long lead-in before the first word is a break too, and the only one a
    // line-synced source can ever have: there is no previous line to end.
    if (sung[0].time >= MIN_GAP_S) out.push({ time: 0, end: sung[0].time })
    for (let i = 1; i < sung.length; i++) {
        const start = sweepEnd(sung[i - 1], maxWordSpan)
        if (start === null) continue
        const end = sung[i].time
        if (end - start >= MIN_GAP_S) out.push({ time: start, end: end })
    }
    return out
}

// How far through its own slice of the break dot i stands: the first third
// fills the first dot, the last third the last one.
function dotFill(progress, i) {
    return Math.min(1, Math.max(0, (progress - i / DOTS) * DOTS))
}

// The list the widget shows: every lyric line, with a break row put in
// wherever one ends. A break is keyed off its own row, so the list stops being
// addressable by line index — hence the two maps back to row positions.
function mergeRows(lines, interludes, noteText) {
    const rows = []
    const lineAt = []
    const gapAt = []
    const gaps = interludes ?? []
    let next = 0
    const addGap = (i) => {
        gapAt[i] = rows.length
        rows.push({ lineIndex: -1, gapIndex: i, note: false, interlude: true, text: "" })
    }
    for (let i = 0; i < (lines ?? []).length; i++) {
        // Ordered by the end of the break, not its start: a break that starts
        // at the very time of the line it follows would otherwise be filed
        // after it.
        while (next < gaps.length && Number(gaps[next].end) <= Number(lines[i].time))
            addGap(next++)
        lineAt[i] = rows.length
        rows.push({
            lineIndex: i,
            gapIndex: -1,
            note: false,
            interlude: false,
            text: lines[i].text || "♪",
            otherVoice: lines[i].align === "end",
            bgText: lines[i].bg?.text ?? ""
        })
    }
    while (next < gaps.length)
        addGap(next++)
    if (rows.length > 0 && noteText)
        rows.push({ lineIndex: -1, gapIndex: -1, note: true, interlude: false, text: noteText })
    return { rows: rows, lineAt: lineAt, gapAt: gapAt }
}
