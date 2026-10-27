pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    required property Component lockSurface
    property alias context: lockContext

    // Session lock surfaces get destroyed when the compositor recreates outputs
    // (e.g. on resume) and Quickshell does not always recreate them, which leaves
    // Hyprland showing its "lockscreen app died" screen. Track them to detect that.
    property var lockSurfaces: []
    property int visibleLockSurfaces: 0
    property bool lockRepairStarted: false

    function registerLockSurface(surface) {
        root.lockSurfaces.push(surface);
        root.updateLockSurfaceVisibility();
    }
    function unregisterLockSurface(surface) {
        root.lockSurfaces = root.lockSurfaces.filter(s => s !== surface);
        root.updateLockSurfaceVisibility();
    }
    function updateLockSurfaceVisibility() {
        root.visibleLockSurfaces = root.lockSurfaces.filter(s => s.visible).length;
    }

    property Component sessionLockSurface: WlSessionLockSurface {
        id: sessionLockSurface
        color: "transparent"

        Component.onCompleted: root.registerLockSurface(sessionLockSurface)
        Component.onDestruction: root.unregisterLockSurface(sessionLockSurface)
        onVisibleChanged: root.updateLockSurfaceVisibility()

        Loader {
            active: GlobalStates.screenLocked
            anchors.fill: parent
            opacity: active ? 1 : 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
            sourceComponent: root.lockSurface
        }
    }

    Process {
        id: unlockKeyringProc
        onExited: (exitCode, exitStatus) => {
            KeyringStorage.fetchKeyringData();
        }
    }
    function unlockKeyring() {
        unlockKeyringProc.exec({
            environment: ({
                "UNLOCK_PASSWORD": lockContext.currentText
            }),
            command: ["bash", "-c", Quickshell.shellPath("scripts/keyring/unlock.sh")]
        })
    }

    // This stores all the information shared between the lock surfaces on each screen.
    // https://github.com/quickshell-mirror/quickshell-examples/tree/master/lockscreen
    LockContext {
        id: lockContext

        Connections {
            target: GlobalStates
            function onScreenLockedChanged() {
                if (GlobalStates.screenLocked) {
                    lockContext.reset();
                    lockContext.tryFingerUnlock();
                }
            }
        }

        onUnlocked: (targetAction) => {
            // Perform the target action if it's not just unlocking
            if (targetAction == LockContext.ActionEnum.Poweroff) {
                Session.poweroff();
                return;
            } else if (targetAction == LockContext.ActionEnum.Reboot) {
                Session.reboot();
                return;
            }

            // Unlock the keyring if configured to do so
            if (Config.options.lock.security.unlockKeyring) root.unlockKeyring(); // Async

            // Unlock the screen before exiting, or the compositor will display a
            // fallback lock you can't interact with.
            GlobalStates.screenLockPending = false;
            unlockPendingTimer.restart();

            // Reset
            lockContext.reset();

            // Post-unlock actions
            if (lockContext.alsoInhibitIdle) {
                lockContext.alsoInhibitIdle = false;
                Idle.toggleInhibit(true);
            }
        }
    }

    WlSessionLock {
        id: lock
        locked: GlobalStates.screenLocked
        surface: root.sessionLockSurface
        onSecureChanged: {
            if (lock.secure) GlobalStates.startupLockPending = false;
            else root.lockRepairStarted = false;
        }
    }

    // Hyprland renders its "lockscreen app died" screen when no lock client owns a
    // mapped surface. Hyprlock can take over such a dead lock, so use it as a
    // fallback and then drop the stale Quickshell lock state.
    // shortcut: only catches losing every surface (the single-monitor case), not
    // one dead output in a multi-monitor lock.
    Timer {
        interval: 10000
        running: lock.secure && root.visibleLockSurfaces === 0
        onTriggered: {
            if (root.lockRepairStarted) return;
            root.lockRepairStarted = true;
            lockStateCheck.running = true;
        }
    }

    Process {
        id: lockStateCheck
        command: ["bash", "-c", "out=$(hyprctl locked 2>/dev/null) || { echo error; exit; }; [ \"$out\" = true ] || { echo unlocked; exit; }; pidof hyprlock >/dev/null && { echo busy; exit; }; echo locked"]
        stdout: StdioCollector {
            onStreamFinished: {
                const state = text.trim();
                if (state === "unlocked") {
                    // Someone else already unlocked the session; only our state is stale.
                    GlobalStates.screenLocked = false;
                    lockContext.reset();
                } else if (state === "locked") {
                    console.warn("LockScreen: lock surfaces are gone; starting hyprlock fallback");
                    repairLockProc.running = true;
                } else if (state !== "busy") {
                    console.warn("LockScreen: cannot determine lock state, leaving it alone");
                }
            }
        }
    }

    Process {
        id: repairLockProc
        command: ["hyprlock"]
        onExited: (exitCode, exitStatus) => {
            // hyprlock exits 0 only after it unlocked the session.
            if (exitCode === 0) {
                GlobalStates.screenLocked = false;
                lockContext.reset();
            } else {
                console.warn("LockScreen: hyprlock fallback exited with", exitCode);
            }
        }
    }

    // The lock badge ("Locked") fades in before the screen locks and fades out
    // before it unlocks, so the clock's size is already settled when its
    // centering animation runs. Lead it by a short delay.
    Timer {
        id: lockPendingTimer
        interval: 100
        onTriggered: GlobalStates.screenLocked = true
    }
    Timer {
        id: unlockPendingTimer
        interval: 100
        onTriggered: GlobalStates.screenLocked = false
    }

    function lock() {
        if (Config.options.lock.useHyprlock) {
            Quickshell.execDetached(["bash", "-c", "pidof hyprlock || hyprlock"]);
            return;
        }
        if (GlobalStates.screenLockPending || GlobalStates.screenLocked) return;
        GlobalStates.screenLockPending = true;
        lockPendingTimer.restart();
    }

    IpcHandler {
        target: "lock"

        function activate(): void {
            root.lock();
        }
        function focus(): void {
            lockContext.shouldReFocus();
        }
    }

    CompositorGlobalShortcut {
        name: "lock"
        description: "Locks the screen"

        onPressed: {
            root.lock()
        }
    }

    CompositorGlobalShortcut {
        name: "lockFocus"
        description: "Re-focuses the lock screen. This is because Hyprland after waking up for whatever reason"
            + "decides to keyboard-unfocus the lock screen"

        onPressed: {
            lockContext.shouldReFocus();
        }
    }

    function initIfReady() {
        if (!Config.ready || !Persistent.ready) return;
        if (Config.options.lock.launchOnStartup && Persistent.isNewHyprlandInstance) {
            root.lock();
        } else {
            KeyringStorage.fetchKeyringData();
            GlobalStates.startupLockPending = false;
        }
    }
    Connections {
        target: Config
        function onReadyChanged() {
            root.initIfReady();
        }
    }
    Connections {
        target: Persistent
        function onReadyChanged() {
            root.initIfReady();
        }
    }
}