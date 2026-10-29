pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

/**
 * Provides extra features not in Quickshell.Services.Notifications:
 *  - Persistent storage
 *  - Popup notifications, with timeout
 *  - Notification groups by app
 */
Singleton {
	id: root
    component Notif: QtObject {
        id: wrapper
        required property int notificationId // Could just be `id` but it conflicts with the default prop in QtObject
        property Notification notification
        property list<var> actions: notification?.actions.map((action) => ({
            "identifier": action.identifier,
            "text": action.text,
        })) ?? []
        property bool popup: false
        property bool isTransient: notification?.hints.transient ?? false
        property string appIcon: notification?.appIcon ?? ""
        property string appName: notification?.appName ?? ""
        property string body: notification?.body ?? ""
        property string image: notification?.image ?? ""
        property string summary: notification?.summary ?? ""
        property double time
        property string urgency: notification?.urgency.toString() ?? "normal"
        property Timer timer

        onNotificationChanged: {
            if (notification === null) {
                root.discardNotification(notificationId);
            }
        }
    }

    function notifToJSON(notif) {
        return {
            "notificationId": notif.notificationId,
            "actions": notif.actions,
            "appIcon": notif.appIcon,
            "appName": notif.appName,
            "body": notif.body,
            "image": notif.image,
            "summary": notif.summary,
            "time": notif.time,
            "urgency": notif.urgency,
        }
    }
    function notifToString(notif) {
        return JSON.stringify(notifToJSON(notif), null, 2);
    }

    component NotifTimer: Timer {
        required property int notificationId
        interval: 7000
        running: true
        onTriggered: () => {
            const index = root.list.findIndex((notif) => notif.notificationId === notificationId);
            // Already dismissed or discarded while the timer was running
            if (index === -1) {
                destroy();
                return;
            }
            const notifObject = root.list[index];
            print("[Notifications] Notification timer triggered for ID: " + notificationId + ", transient: " + notifObject?.isTransient);
            // The Phone tab is this notification's archive, so the card is
            // dropped rather than dismissed: dismissing would tell the daemon
            // the notification closed, and take the row out of the tab too.
            if (root.isPhoneOwnedNotification(notifObject)) root.forgetNotification(notificationId);
            else if (notifObject?.isTransient) root.discardNotification(notificationId);
            else root.timeoutNotification(notificationId);
            destroy()
        }
    }

    property bool silent: false
    property int unread: 0
    property var filePath: Directories.notificationsPath
    property list<Notif> list: []
    property var popupList: list.filter((notif) => notif.popup);
    property bool popupInhibited: (GlobalStates?.sidebarRightOpen ?? false) || silent
    // KDE Connect pushes the phone's notifications to the desktop like any
    // other app's. They belong to the Phone tab, which reads them from the
    // daemon, so the desktop copy is only a flash: it pops up, then is dropped
    // instead of settling into the sidebarRight list, and it never reaches the
    // history file. Two identical archives of one message would disagree.
    readonly property bool phoneNotificationsOwnedByTab: Config.options.sidebar?.phone?.enable ?? true
    function isPhoneOwnedNotification(notif) {
        return root.phoneNotificationsOwnedByTab
            && PhoneNotifications.mirrorsAppName(notif?.appName, PhoneConnect.devices.filter(d => d.paired).map(d => d.name));
    }
    property var latestTimeForApp: ({})
    Component {
        id: notifComponent
        Notif {}
    }
    Component {
        id: notifTimerComponent
        NotifTimer {}
    }

    function stringifyList(list) {
        return JSON.stringify(list
            .filter((notif) => !root.isPhoneOwnedNotification(notif))
            .map((notif) => notifToJSON(notif)), null, 2);
    }
    
    onListChanged: {
        // Update latest time for each app
        root.list.forEach((notif) => {
            if (!root.latestTimeForApp[notif.appName] || notif.time > root.latestTimeForApp[notif.appName]) {
                root.latestTimeForApp[notif.appName] = Math.max(root.latestTimeForApp[notif.appName] || 0, notif.time);
            }
        });
        // Remove apps that no longer have notifications
        Object.keys(root.latestTimeForApp).forEach((appName) => {
            if (!root.list.some((notif) => notif.appName === appName)) {
                delete root.latestTimeForApp[appName];
            }
        });
    }

    function appNameListForGroups(groups) {
        return Object.keys(groups).sort((a, b) => {
            // Sort by time, descending
            return groups[b].time - groups[a].time;
        });
    }

    function groupsForList(list) {
        const groups = {};
        list.forEach((notif) => {
            if (!groups[notif.appName]) {
                groups[notif.appName] = {
                    appName: notif.appName,
                    appIcon: notif.appIcon,
                    notifications: [],
                    time: 0
                };
            }
            groups[notif.appName].notifications.push(notif);
            // Always set to the latest time in the group
            groups[notif.appName].time = latestTimeForApp[notif.appName] || notif.time;
        });
        return groups;
    }

    property var groupsByAppName: groupsForList(root.list)
    property var popupGroupsByAppName: groupsForList(root.popupList)
    property list<string> appNameList: appNameListForGroups(root.groupsByAppName)
    property list<string> popupAppNameList: appNameListForGroups(root.popupGroupsByAppName)

    // Quickshell's notification IDs starts at 1 on each run, while saved notifications
    // can already contain higher IDs. This is for avoiding id collisions
    property int idOffset
    signal initDone();
    signal notify(notification: var);
    signal discard(id: int);
    signal discardAll();
    signal timeout(id: var);

	NotificationServer {
        id: notifServer
        // actionIconsSupported: true
        actionsSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: true
        bodyMarkupSupported: true
        bodySupported: true
        imageSupported: true
        keepOnReload: false
        persistenceSupported: true

        onNotification: (notification) => {
            // KDE Connect hands us the phone's notifications like anyone else's.
            // They are a flash, not a record, so a popup that cannot show -
            // sidebar open, or the shell muted - has nothing to fall back on
            // and is dropped here instead.
            const phoneCopy = root.isPhoneOwnedNotification(notification);
            if (phoneCopy && root.popupInhibited)
                return;
            notification.tracked = true
            const newNotifObject = notifComponent.createObject(root, {
                "notificationId": notification.id + root.idOffset,
                "notification": notification,
                "time": Date.now(),
            });
			root.list = [...root.list, newNotifObject];

            // Popup
            if (!root.popupInhibited) {
                newNotifObject.popup = true;
                // The phone asks for no expiry, which would otherwise leave the
                // card sitting in the list once the popup band hides.
                const statedTimeout = notification.expireTimeout > 0 ? notification.expireTimeout : 0;
                if (phoneCopy || notification.expireTimeout != 0) {
                    newNotifObject.timer = notifTimerComponent.createObject(root, {
                        "notificationId": newNotifObject.notificationId,
                        "interval": statedTimeout || (Config?.options.notifications.timeout ?? 7000),
                    });
                }
                if (!phoneCopy)
                    root.unread++;
            }
            root.notify(newNotifObject);
            // console.log(notifToString(newNotifObject));
            notifFileView.setText(stringifyList(root.list));
        }
    }

    function markAllRead() {
        root.unread = 0;
    }

    function discardNotification(id) {
        root.discardNotifications([id]);
    }

    // Forgetting without dismissing: the shell drops its own record and the
    // sender is left alone with the notification it handed us.
    function forgetNotification(id) {
        const remaining = root.list.filter((notif) => notif.notificationId !== id);
        if (remaining.length !== root.list.length) {
            root.list = remaining;
            notifFileView.setText(stringifyList(root.list));
        }
        root.discard(id);
    }

    function discardNotifications(ids) {
        console.log("[Notifications] Discarding notifications with IDs: " + ids.join(", "));
        const idSet = new Set(ids);
        // Assign a new array instead of splicing: on a list<> property, splice()
        // shifts the following elements one by one and emits listChanged for each,
        // re-running the grouping and every model bound to the list each time.
        const remaining = root.list.filter((notif) => !idSet.has(notif.notificationId));
        if (remaining.length !== root.list.length) {
            root.list = remaining;
            notifFileView.setText(stringifyList(root.list));
        }
        notifServer.trackedNotifications.values
            .filter((notif) => idSet.has(notif.id + root.idOffset))
            .forEach((notif) => notif.dismiss());
        ids.forEach((id) => root.discard(id)); // Emit signal
    }

    function discardAllNotifications() {
        root.list = []
        triggerListChange()
        notifFileView.setText(stringifyList(root.list));
        notifServer.trackedNotifications.values.forEach((notif) => {
            notif.dismiss()
        })
        root.discardAll();
    }

    function cancelTimeout(id) {
        const index = root.list.findIndex((notif) => notif.notificationId === id);
        if (root.list[index] != null && root.list[index].timer != null)
            root.list[index].timer.stop();
    }

    function timeoutNotification(id) {
        const index = root.list.findIndex((notif) => notif.notificationId === id);
        if (root.list[index] != null)
            root.list[index].popup = false;
        root.timeout(id);
    }

    function timeoutAll() {
        root.popupList.forEach((notif) => {
            root.timeout(notif.notificationId);
        })
        root.popupList.forEach((notif) => {
            notif.popup = false;
        });
    }

    function attemptInvokeAction(id, notifIdentifier) {
        console.log("[Notifications] Attempting to invoke action with identifier: " + notifIdentifier + " for notification ID: " + id);
        const notifServerIndex = notifServer.trackedNotifications.values.findIndex((notif) => notif.id + root.idOffset === id);
        console.log("Notification server index: " + notifServerIndex);
        if (notifServerIndex !== -1) {
            const notifServerNotif = notifServer.trackedNotifications.values[notifServerIndex];
            const action = notifServerNotif.actions.find((action) => action.identifier === notifIdentifier);
            // console.log("Action found: " + JSON.stringify(action));
            if (action) {
                action.invoke();
            } else {
                console.warn("[Notifications] Action not found:", notifIdentifier);
            }
        } 
        else {
            console.log("Notification not found in server: " + id)
        }
        root.discardNotification(id);
    }

    function triggerListChange() {
        root.list = root.list.slice(0)
    }

    function refresh() {
        notifFileView.reload()
    }

    Component.onCompleted: {
        refresh()
    }

    FileView {
        id: notifFileView
        path: Qt.resolvedUrl(filePath)
        onLoaded: {
            try {
                const fileContents = notifFileView.text()
                const stored = JSON.parse(fileContents)
                root.list = stored.map((notif) => {
                    return notifComponent.createObject(root, {
                        "notificationId": notif.notificationId,
                        "actions": [], // Notification actions are meaningless if they're not tracked by the server or the sender is dead
                        "appIcon": notif.appIcon,
                        "appName": notif.appName,
                        "body": notif.body,
                        "image": notif.image,
                        "summary": notif.summary,
                        "time": notif.time,
                        "urgency": notif.urgency,
                    });
                });
                // Find largest notificationId
                let maxId = 0
                root.list.forEach((notif) => {
                    maxId = Math.max(maxId, notif.notificationId)
                })

                root.idOffset = maxId
                root.initDone()
            } catch (e) {
                console.error("[Notifications] Failed to parse notifications file, resetting:", e)
                root.list = []
                notifFileView.setText(stringifyList(root.list))
                root.idOffset = 0
                root.initDone()
            }
        }
        onLoadFailed: (error) => {
            if(error == FileViewError.FileNotFound) {
                console.log("[Notifications] File not found, creating new file.")
                root.list = []
                notifFileView.setText(stringifyList(root.list));
            } else {
                console.log("[Notifications] Error loading file: " + error)
            }
        }
    }
}
