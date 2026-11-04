// The instrumental stretches in a lyric list, and the rows they take.
// Ported from Mixtapes' find_interludes (src/ui/widgets/lyric_rows.rs).

// A stretch shorter than this is a breath between two lines, not a break.
var MIN_GAP_S = 5.0
// How many dots a break counts out.
var DOTS = 3
// How long one syllable of an un-timed line takes to sing, and the least a
// line is heard for whatever it says. A pop line runs three syllables a second
// or so; the rate sits on the high side of that, because a countdown that
// opens while something is still being sung is worse than a silence that goes
// unmarked.
var SYLLABLE_S = 0.35
var MIN_SUNG_S = 1.6

// Roughly how many syllables a line carries. An east-asian character is one on
// its own; latin letters run about two apiece.
function syllables(text) {
    const chars = String(text ?? "").replace(/\s+/g, "")
    if (chars.length === 0) return 0
    const wide = chars.split("").filter(ch => ch.codePointAt(0) > 0x2E7F).length
    return wide + (chars.length - wide) / 2
}

// When a line stops being sung. Providers give a word's start and never its
// end, so the last word of either voice plus the longest span the sweep may run
// is as far as anything can know. A line with no word timings is timed to the
// second it starts and says a known number of syllables, so its end is worked
// out from the text.
function sweepEnd(line, maxWordSpan) {
    const start = Number(line?.time)
    if (isNaN(start)) return null
    const words = line?.words ?? []
    if (words.length === 0)
        return start + Math.max(MIN_SUNG_S, syllables(line?.text) * SYLLABLE_S)
    let last = Number(words[words.length - 1]?.time)
    // The backstage answers after the lead has stopped, so the line is not done
    // being heard when its own last word is: silence starts at the last sound.
    const echo = line?.bg?.words ?? []
    if (echo.length > 0)
        last = Math.max(last, Number(echo[echo.length - 1]?.time))
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
            // The echo travels with the line it answers: the sweep of this line
            // ends on its last sound, and that sound can be backstage's. The
            // text goes along for the same reason — an un-timed line's end is
            // read out of how much of it there is to sing.
            sung.push({ time: t, text: line.text, words: line.words ?? [],
                        bg: line.bg ?? null })
    }
    if (sung.length === 0) return out
    // A long lead-in before the first word is a break too: nothing precedes it
    // to end, so its own length is the whole of the silence.
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
            bgText: lines[i].bg?.text ?? "",
            reading: lines[i].reading ?? ""
        })
    }
    while (next < gaps.length)
        addGap(next++)
    if (rows.length > 0 && noteText)
        rows.push({ lineIndex: -1, gapIndex: -1, note: true, interlude: false, text: noteText })
    return { rows: rows, lineAt: lineAt, gapAt: gapAt }
}
