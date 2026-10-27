import QtQuick
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.ii.background
import qs.modules.ii.bar
import qs.modules.ii.dock
import qs.modules.ii.dotsSwitcher
import qs.modules.ii.equalizer
import qs.modules.ii.lock
import qs.modules.ii.mediaControls
import qs.modules.ii.notificationPopup
import qs.modules.ii.onScreenDisplay
import qs.modules.ii.onScreenKeyboard
import qs.modules.ii.overview
import qs.modules.ii.polkit
import qs.modules.ii.settings
import qs.modules.ii.regionSelector
import qs.modules.ii.screenCorners
import qs.modules.ii.screenTranslator
import qs.modules.ii.sessionScreen
import qs.modules.ii.sidebarLeft
import qs.modules.ii.sidebarRight
import qs.modules.ii.overlay
import qs.modules.ii.verticalBar
import qs.modules.ii.wallpaperSelector
import qs.modules.ii.desktopMenu
import qs.modules.ii.dropover
import qs.modules.ii.frame

Scope {
    PanelLoader { extraCondition: !Config.options.bar.vertical; component: Bar {} }
    PanelLoader { component: Background {} }
    PanelLoader { extraCondition: Config.options.dock.enable; component: Dock {} }
    PanelLoader { component: DotsSwitcher {} }
    PanelLoader { component: EqualizerPopup {} }
    PanelLoader { component: Lock {} }
    PanelLoader { component: MediaControls {} }
    PanelLoader { component: NotificationPopup {} }
    PanelLoader { component: OnScreenDisplay {} }
    PanelLoader { component: OnScreenKeyboard {} }
    PanelLoader { component: Overlay {} }
    PanelLoader { component: Overview {} }
    PanelLoader { component: Polkit {} }
    PanelLoader { component: RegionSelector {} }
    PanelLoader { component: ScreenCorners {} }
    PanelLoader { component: ScreenTranslator {} }
    PanelLoader { component: SessionScreen {} }
    PanelLoader { component: SidebarLeft {} }
    PanelLoader { component: SidebarRight {} }
    PanelLoader { extraCondition: Config.options.bar.vertical; component: VerticalBar {} }
    PanelLoader { component: WallpaperSelector {} }
    PanelLoader { component: Settings {} }
    PanelLoader { component: DesktopMenu {} }
    PanelLoader { extraCondition: GlobalStates.dropShelfOpen; component: DropShelfPanel {} }
    PanelLoader { component: NiriBackdrop {} }
    PanelLoader { component: ScreenFrame {} }

    // Alt+X is answered by the bridge itself while it holds the keyboards, and it
    // is answered here as well because a board that cannot be held - one the
    // `input` group does not reach - would otherwise leave no key that gives the
    // machine back. Both mouse buttons together is the third way, inside the
    // bridge, for the moments the keyboards are not reachable at all.
    CompositorGlobalShortcut {
        name: "phoneRemoteInputRelease"
        description: "Gives the mouse back from phone remote input"

        onPressed: PhoneConnect.setRemoteInputActive(false)
    }

    // A locked screen is the end of a session: the pointer devices are held from
    // below the compositor, so nothing on that screen would ever answer the hand
    // and the mouse would stay dead behind a wall of wallpaper.
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked)
                PhoneConnect.setRemoteInputActive(false);
        }
    }
}
