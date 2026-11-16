import QtQuick
import QtTest
import qs.modules.common.widgets

// A touchpad announces the start and end of a scroll gesture with wheel
// events that carry no delta at all. Those used to be read as "scroll down"
// and dragged the volume backwards; a gesture with real deltas must still
// move it, including pixel-only (high resolution) events.
TestCase {
    name: "MaterialDialWheel"
    when: windowShown

    MaterialDial {
        id: dial
        value: 0.5
    }

    function test_zeroDeltaIsNotScroll() {
        dial.value = 0.5
        dial.scrollBy(dial.wheelDelta(0, 0))
        fuzzyCompare(dial.value, 0.5, 1e-6)
    }

    function test_pixelOnlyDeltaScrolls() {
        dial.value = 0.5
        dial.scrollBy(dial.wheelDelta(0, -40))
        fuzzyCompare(dial.value, 0.5 - 0.05 * 40 / 120, 1e-6)
    }

    function test_touchpadEventMovesLessThanANotch() {
        dial.value = 0.5
        dial.scrollBy(-22)
        fuzzyCompare(dial.value, 0.5 - 0.05 * 22 / 120, 1e-6)
    }

    function test_oneNotchIsOneStep() {
        dial.value = 0.5
        dial.scrollBy(-120)
        fuzzyCompare(dial.value, 0.45, 1e-6)
    }

    function test_angleDeltaIsPreferredOverPixels() {
        compare(dial.wheelDelta(22, -40), 22)
    }
}
