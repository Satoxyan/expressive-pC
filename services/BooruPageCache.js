// Daftar response sekaligus jadi cache halaman: kalau halaman yang dituju
// sudah pernah diambil dengan provider + tag yang sama, viewer loncat ke situ
// dan tidak query ulang.

function indexOf(responses, provider, tags, page) {
    const key = (tags || []).join(" ")
    const list = responses || []
    for (let i = list.length - 1; i >= 0; --i) {
        const response = list[i]
        if (response.provider !== provider) continue
        if (Number(response.page) !== Number(page)) continue
        if ((response.tags || []).join(" ") !== key) continue
        return i
    }
    return -1
}
