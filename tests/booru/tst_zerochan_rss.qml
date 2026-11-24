import QtQuick
import QtTest
import "../../services/BooruZerochan.js" as Zerochan

// Zerochan's RSS feed is the only list endpoint that still answers 200, so the
// provider has to read it. These pin the field mapping the rest of the booru
// viewer expects.
TestCase {
    name: "ZerochanRss"

    readonly property string feed: `<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"><channel>
  <item>
    <title>Skirk</title>
    <link>http://www.zerochan.net/4735599</link>
    <summary type="xhtml">&lt;img src=&quot;x&quot; /&gt;</summary>
    <guid>http://www.zerochan.net/4735599</guid>
    <media:title>Skirk</media:title>
    <media:thumbnail url="https://s3.zerochan.net/240/49/11/4735599.avif" />
    <media:content url="https://s1.zerochan.net/600/49/11/4735599.jpg" width="2700" height="5699" expression="sample" />
    <media:keywords>
    	Female, Fanart, Long Hair,
	Pixiv ID 77386380, Genshin Impact, Skirk
    </media:keywords>
  </item>
  <item>
    <title>Tom &amp; Jerry</title>
    <link>http://www.zerochan.net/42</link>
    <media:title>Tom &amp; Jerry</media:title>
    <media:thumbnail url="https://s3.zerochan.net/240/42.avif" />
    <media:content url="https://s1.zerochan.net/600/42.jpg" width="100" height="200" expression="sample" />
    <media:keywords>Comedy</media:keywords>
  </item>
  <item>
    <title>No id at all</title>
  </item>
</channel></rss>`

    function test_mapsEveryItem() {
        const items = Zerochan.parse(feed)
        compare(items.length, 2)
        compare(items[0].id, "4735599")
        compare(items[0].width, 2700)
        compare(items[0].height, 5699)
        compare(items[0].aspect_ratio, 2700 / 5699)
    }

    function test_previewAndSample() {
        const item = Zerochan.parse(feed)[0]
        compare(item.preview_url, "https://s3.zerochan.net/240/49/11/4735599.avif")
        compare(item.sample_url, "https://s1.zerochan.net/600/49/11/4735599.jpg")
        compare(item.file_url, item.sample_url)
        compare(item.file_ext, "jpg")
        compare(item.source, "http://www.zerochan.net/4735599")
    }

    function test_keywordsBecomeTags() {
        const item = Zerochan.parse(feed)[0]
        verify(item.tags.startsWith("Female Fanart Long Hair Pixiv ID 77386380"))
        verify(item.tags.endsWith("Genshin Impact Skirk"))
        verify(!item.tags.includes("\n"))
        verify(!item.tags.includes("  "))
    }

    function test_entitiesAreDecoded() {
        const item = Zerochan.parse(feed)[1]
        compare(item.character, "Tom & Jerry")
    }

    function test_itemWithoutIdIsDropped() {
        compare(Zerochan.parse(feed).length, 2)
    }

    function test_emptyInput() {
        compare(Zerochan.parse("").length, 0)
        compare(Zerochan.parse(undefined).length, 0)
    }
}
