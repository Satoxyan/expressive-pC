pragma Singleton

import QtQuick
import Quickshell

/**
 * Motion tokens for the Dynamic Island. Four speeds, each with one job — so the same kind of
 * change feels the same everywhere:
 *
 *   micro  150  hover, press, colour and small opacity flips
 *   short  220  a control changing state: toggles, chips, a row arming
 *   medium 320  content swapping or sliding: a line rising in, a list refilling
 *   long   460  size and layout: the island widening, a card growing
 *
 * Curves: OutCubic for almost everything (settles without a bounce); OutBack only for an arrival that should
 * be felt — a badge popping, chips dealt in; the expressive spatial curve for the island's own shape. Loops
 * (breathing, pulses) are ambient, ~1 s per half, and always gated by the state that justifies them.
 * The big choreographies (overlay open/close, the IMDb rating piece, F1 start lights) keep their own timing.
 */
Singleton {
    readonly property int micro: 150
    readonly property int short: 220
    readonly property int medium: 320
    readonly property int long: 460

    // Springs (Material 3 Expressive: stiffness + damping ratio, see DiSpring.qml) for the expanded island's
    // own shape. Opening may overshoot a hair, like a surface with some mass; resizing barely does; closing
    // never does, so shrinking back reads as settling rather than bouncing.
    readonly property var springOpen: ({ stiffness: 320, dampingRatio: 0.8 })
    readonly property var springResize: ({ stiffness: 380, dampingRatio: 0.86 })
    readonly property var springClose: ({ stiffness: 520, dampingRatio: 1 })
}
