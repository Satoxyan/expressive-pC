// Zerochan's JSON list endpoint answers 500 with a JSON object glued to an HTML
// page, so JSON.parse never sees a whole document. The RSS variant (?xml) still
// serves the same entries with a 200, so the provider reads that instead and
// turns it into the shape Booru.qml expects.

function decodeEntities(text) {
    return String(text ?? "")
        .replace(/&lt;/g, "<")
        .replace(/&gt;/g, ">")
        .replace(/&quot;/g, "\"")
        .replace(/&#0?39;/g, "'")
        .replace(/&amp;/g, "&")
}

function attr(tag, name) {
    const match = String(tag).match(new RegExp(name + '="([^"]*)"'))
    return match ? decodeEntities(match[1]) : ""
}

function field(block, pattern) {
    const match = block.match(pattern)
    return match ? decodeEntities(match[1]).trim() : ""
}

function parse(text) {    return String(text ?? "").split("<item>").slice(1).map(block => {
        const thumbTag = (block.match(/<media:thumbnail[^>]*>/) || [""])[0]
        const contentTag = (block.match(/<media:content[^>]*>/) || [""])[0]
        const link = field(block, /<link>([^<]*)<\/link>/)
        const id = (link.match(/(\d+)\s*$/) || [])[1] || ""
        if (!id) return null

        const width = Number(attr(contentTag, "width")) || 1
        const height = Number(attr(contentTag, "height")) || 1
        const sample = attr(contentTag, "url")
        const preview = attr(thumbTag, "url") || sample
        const title = field(block, /<media:title>([^<]*)<\/media:title>/)
            || field(block, /<title>([^<]*)<\/title>/)
        const tags = field(block, /<media:keywords>([\s\S]*?)<\/media:keywords>/)
            .split(",").map(tag => tag.replace(/\s+/g, " ").trim()).filter(Boolean)

        return {
            "id": id,
            "width": width,
            "height": height,
            "aspect_ratio": width / height,
            "tags": tags.join(" "),
            "rating": "safe", // Zerochan doesn't have nsfw
            "is_nsfw": false,
            "md5": id,
            "preview_url": preview,
            "sample_url": sample || preview,
            "file_url": sample || preview,
            "file_ext": (sample || preview).split(".").pop() || "jpg",
            "source": link,
            "character": title,
        }
    }).filter(item => item !== null)
}

// /suggest?q= answers one tag per line as "Name|Type|Parent".
function parseTags(text) {
    return String(text ?? "").split("\n")
        .map(line => line.split("|")[0].trim())
        .filter(name => name.length > 0)
        .map(name => ({ "name": name }))
}
