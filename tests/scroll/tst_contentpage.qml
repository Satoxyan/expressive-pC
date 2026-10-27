import QtQuick
import QtTest
import qs.modules.common.widgets

// Up/Down in the default Settings style must animate, not teleport.
TestCase {
    name: "ContentPageKeyboard"
    when: windowShown
    width: 400
    height: 300

    ContentPage {
        id: page
        anchors.fill: parent
        Rectangle {
            implicitWidth: 500
            implicitHeight: 2000
        }
    }

    function flickable() {
        for (let i = 0; i < page.children.length; i++) {
            const child = page.children[i]
            if (child.contentHeight !== undefined && child.contentY !== undefined)
                return child
        }
        return null
    }

    function test_keyboardStepAnimates() {
        wait(150)
        const flick = flickable()
        verify(flick !== null, "flickable found")
        compare(flick.contentY, 0)
        page.scrollBy(60)
        wait(40)
        verify(flick.contentY > 1, "scroll started (y=" + flick.contentY.toFixed(1) + ")")
        verify(flick.contentY < 59, "not an instant jump (y=" + flick.contentY.toFixed(1) + ")")
        wait(300)
        compare(flick.contentY, 60, 1)
    }
}
