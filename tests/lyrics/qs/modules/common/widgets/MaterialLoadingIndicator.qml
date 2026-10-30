import QtQuick

// Test stub: the loading spinner is not under test, and the real one drags in
// the whole theme stack.
Rectangle {
    property bool loading: true
    property color colBg
    property color colShape
    property real implicitSize: 48
    radius: width / 2
    color: colBg
}
