import QtQuick
import QtTest
import "../../services/BooruPageCache.js" as PageCache

// Daftar response dipakai sebagai cache halaman: lompat ke halaman yang sudah
// pernah diambil, jangan query ulang.
TestCase {
    name: "BooruPageCache"

    readonly property var responses: [
        { "provider": "zerochan", "tags": ["Skirk"], "page": 1 },
        { "provider": "zerochan", "tags": ["Skirk"], "page": 2 },
        { "provider": "yandere", "tags": ["Skirk"], "page": 1 },
        { "provider": "zerochan", "tags": ["Frieren"], "page": 1 },
        { "provider": "system", "tags": [], "page": "" },
    ]

    function test_findsSameProviderTagAndPage() {
        compare(PageCache.indexOf(responses, "zerochan", ["Skirk"], 1), 0)
        compare(PageCache.indexOf(responses, "zerochan", ["Skirk"], 2), 1)
    }

    function test_pageIsComparedAsNumber() {
        compare(PageCache.indexOf(responses, "zerochan", ["Skirk"], "2"), 1)
    }

    function test_differentProviderOrTagsMiss() {
        compare(PageCache.indexOf(responses, "zerochan", ["Skirk"], 3), -1)
        compare(PageCache.indexOf(responses, "zerochan", ["Frieren"], 2), -1)
        compare(PageCache.indexOf(responses, "yandere", ["Skirk"], 2), -1)
        compare(PageCache.indexOf(responses, "zerochan", ["Kuda", "Izuna"], 1), -1)
    }

    function test_multiWordTagsMatchAsOneKey() {
        const list = [{ "provider": "zerochan", "tags": ["Kuda", "Izuna"], "page": 1 }]
        compare(PageCache.indexOf(list, "zerochan", ["Kuda", "Izuna"], 1), 0)
        compare(PageCache.indexOf(list, "zerochan", ["Kuda"], 1), -1)
    }

    function test_newestDuplicateWins() {
        const list = [
            { "provider": "zerochan", "tags": ["Skirk"], "page": 1 },
            { "provider": "zerochan", "tags": ["Skirk"], "page": 1 },
        ]
        compare(PageCache.indexOf(list, "zerochan", ["Skirk"], 1), 1)
    }

    function test_emptyList() {
        compare(PageCache.indexOf([], "zerochan", [], 1), -1)
        compare(PageCache.indexOf(undefined, "zerochan", [], 1), -1)
    }
}
