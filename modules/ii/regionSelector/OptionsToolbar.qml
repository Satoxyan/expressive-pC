pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Options toolbar
Toolbar {
    id: root

    // Use a synchronizer on these
    property var action
    property var selectionMode
    // Signals
    signal dismiss()

    ToolbarTabBar {
        id: tabBar
        tabButtonList: [
            {"icon": "activity_zone", "name": Translation.tr("Rect")},
            {"icon": "gesture", "name": Translation.tr("Circle")},
            {"icon": "fullscreen", "name": Translation.tr("Fullscreen")}
        ]
        currentIndex: {
            if (root.selectionMode === RegionSelection.SelectionMode.RectCorners) return 0;
            if (root.selectionMode === RegionSelection.SelectionMode.Circle) return 1;
            if (root.selectionMode === RegionSelection.SelectionMode.Fullscreen) return 2;
            return 0;
        }
        onCurrentIndexChanged: {
            let newMode;
            if (currentIndex === 0) newMode = RegionSelection.SelectionMode.RectCorners;
            else if (currentIndex === 1) newMode = RegionSelection.SelectionMode.Circle;
            else if (currentIndex === 2) newMode = RegionSelection.SelectionMode.Fullscreen;
            if (root.selectionMode !== newMode)
                root.selectionMode = newMode;
        }
    }
}
