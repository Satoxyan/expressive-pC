import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// The expanded island's content: one view at a time, handed over to the next with a crossfade between two layers
// (DiExpandedSlot). The outgoing view drifts a few px against the direction of travel and fades; the incoming
// one arrives from the other side. Both sit centred in the frame the island gives them, so the island's spring
// resize and this handover play as a single motion.
Item {
    id: content
    required property Item di
    required property string contentId
    property real maxHeight: 100000
    // +1 travelling forward (scrolling to the next island), -1 back, 0 for a jump; consumed by the next swap
    property int direction: 0

    property int activeSlot: 0
    readonly property Item currentSlot: content.activeSlot === 0 ? slotA : slotB
    readonly property Item viewItem: content.currentSlot.view
    // What the incoming view needs, not what is fading out: the island starts resizing for it right away
    readonly property real naturalHeight: content.currentSlot.naturalHeight
    readonly property real naturalWidth: content.currentSlot.naturalWidth

    implicitWidth: content.naturalWidth
    implicitHeight: Math.min(content.naturalHeight, content.maxHeight)

    Component.onCompleted: if (content.contentId !== "") slotA.show(content.contentId, 0, true)
    onContentIdChanged: {
        const outgoing = content.currentSlot
        if (outgoing.contentId === content.contentId) return
        const incoming = content.activeSlot === 0 ? slotB : slotA
        if (outgoing.contentId !== "") outgoing.leave(content.direction)
        if (content.contentId !== "") incoming.show(content.contentId, content.direction, false)
        content.activeSlot = 1 - content.activeSlot
        content.direction = 0
    }

    function componentFor(id) {
        switch (id) {
            case "notification":  return notificationView
            case "media":         return mediaView
            case "f1":
            case "f1Event":
            case "f1Flag":        return f1View
            case "timer":         return timerView
            case "osd":
            case "audioOutput":   return audioView
            case "bluetooth":     return bluetoothView
            case "activity":
            case "approval":
            case "agents":        return activitiesView
            case "system":        return systemView
            case "systemLoad":    return loadView
            case "battery":       return batteryView
            case "screenshot":    return screenshotView
            case "clipboard":     return clipboardView
            case "privacy":       return privacyView
            case "watchRating":   return watchView
            case "weather":       return weatherView
            case "recording":     return recordingView
            case "shelf":
            case "shelfDrop":     return shelfView
            case "overview":      return overviewView
            case "history":       return historyView
            case "calendar":      return calendarView
            case "songRec":
            case "songRecResult": return songRecView
            case "download":
            case "zerotier":      return networkView
            case "hardware":      return hardwareView
            case "display":       return displayView
            case "call":          return callView
            default:              return idleView
        }
    }

    // A scrollable view pulled past its end: the island moves on to the next one
    signal overscrolled(int direction)

    DiExpandedSlot { id: slotA; host: content; onOverscrolled: direction => content.overscrolled(direction) }
    DiExpandedSlot { id: slotB; host: content; onOverscrolled: direction => content.overscrolled(direction) }

    Component { id: notificationView; DiXNotification { di: content.di } }
    Component { id: mediaView; DiXMedia { di: content.di } }
    Component { id: f1View; DiXF1 { di: content.di } }
    Component { id: timerView; DiXTimer { di: content.di } }
    Component { id: audioView; DiXAudio { di: content.di } }
    Component { id: bluetoothView; DiXBluetooth { di: content.di } }
    Component { id: activitiesView; DiXActivities { di: content.di } }
    Component { id: systemView; DiXSystem { di: content.di } }
    Component { id: loadView; DiXLoad { di: content.di } }
    Component { id: callView; DiXCall { di: content.di } }
    Component { id: batteryView; DiXBattery { di: content.di } }
    Component { id: screenshotView; DiXScreenshot { di: content.di } }
    Component { id: clipboardView; DiXClipboard { di: content.di } }
    Component { id: displayView; DiXHardware { di: content.di; payload: IslandHardware.displayPayload ?? ({}); runAction: id => IslandHardware.runDisplayAction(id) } }
    Component { id: privacyView; DiXPrivacy { di: content.di } }
    Component { id: watchView; DiXWatch { di: content.di } }
    Component { id: weatherView; DiXWeather { di: content.di } }
    Component { id: recordingView; DiXRecording { di: content.di } }
    Component { id: shelfView; DiXShelf { di: content.di } }
    Component { id: overviewView; DiXOverview { di: content.di } }
    Component { id: songRecView; DiXSongRec { di: content.di } }
    Component { id: idleView; DiXIdle { di: content.di } }
    Component { id: networkView; DiXNetwork { di: content.di } }
    Component { id: historyView; DiXHistory { di: content.di } }
    Component { id: calendarView; DiXCalendar { di: content.di } }
    Component { id: hardwareView; DiXHardware { di: content.di } }
}
