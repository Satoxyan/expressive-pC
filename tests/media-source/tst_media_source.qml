import QtQuick
import QtTest
import "../../modules/common/functions/MediaSource.js" as MediaSource

TestCase {
    name: "MediaSource"

    function test_normalize() {
        compare(MediaSource.normalize("Firefox.Desktop"), "firefox")
        compare(MediaSource.normalize("spotify"), "spotify")
        compare(MediaSource.normalize(""), "")
        compare(MediaSource.normalize(undefined), "")
    }

    function test_matchesAppId() {
        verify(MediaSource.matches("firefox.desktop", "firefox", undefined))
        verify(MediaSource.matches("firefox.desktop", "FireFox", ""))
    }

    function test_matchesResolvedEntryId() {
        verify(MediaSource.matches("firefox.desktop", "Navigator", "firefox.desktop"))
    }

    function test_matchesEditionSuffix() {
        verify(MediaSource.matches("firefox", "firefox-developer-edition", undefined))
        verify(MediaSource.matches("firefox", "Firefox-Developer-Edition", undefined))
        verify(!MediaSource.matches("fire", "firefox-developer-edition", undefined))
    }

    function test_noMatch() {
        verify(!MediaSource.matches("firefox.desktop", "spotify", "spotify.desktop"))
        verify(!MediaSource.matches("", "firefox", "firefox.desktop"))
    }
}
