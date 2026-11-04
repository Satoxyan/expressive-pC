pragma Singleton

import QtQuick
import qs.modules.common
import qs.services
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: root
    signal gammaChangeAttempt()

    readonly property real gammaLowerLimit: 25
    readonly property bool isNiri: WM.compositor === "niri"

    property string from: Config.options?.light?.night?.from ?? "19:00"
    property string to: Config.options?.light?.night?.to ?? "06:30"
    property bool automatic: (Config.options?.light?.night?.automatic ?? false) && (Config?.ready ?? true)
    property int colorTemperature: Config.options?.light?.night?.colorTemperature ?? 5000
    property int gamma: 100
    property bool shouldBeOn
    property bool firstEvaluation: true
    property bool temperatureActive: false

    property int fromHour: Number(from.split(":")[0])
    property int fromMinute: Number(from.split(":")[1])
    property int toHour: Number(to.split(":")[0])
    property int toMinute: Number(to.split(":")[1])

    property int clockHour: DateTime.clock.hours
    property int clockMinute: DateTime.clock.minutes

    property var manualActive
    property int manualActiveHour
    property int manualActiveMinute

    onClockMinuteChanged: reEvaluate()
    onAutomaticChanged: {
        // A state the user picked by hand is theirs to keep, so only what the schedule
        // itself applied is handed back when the schedule is switched off. Before this,
        // switching automatic off left a screen the schedule had warmed still warm for
        // the rest of the day: nothing else was ever going to turn it off again, and
        // the night light looked like it had come on by itself.
        const manual = root.manualActive;
        root.manualActive = undefined;
        root.firstEvaluation = true;
        root.reEvaluate();
        if (root.automatic) {
            // The first evaluation is swallowed to keep a starting shell from acting
            // before it has read anything, so the schedule is applied by hand here
            // instead of waiting for the minute to change.
            root.ensureState();
        } else if (manual === undefined && root.temperatureActive) {
            root.disableTemperature();
        }
    }

    function inBetween(t, from, to) {
        if (from < to) {
            return (t >= from && t <= to);
        } else {
            return (t >= from || t <= to);
        }
    }

    function reEvaluate() {
        const t = clockHour * 60 + clockMinute;
        const from = fromHour * 60 + fromMinute;
        const to = toHour * 60 + toMinute;
        const manualActive = manualActiveHour * 60 + manualActiveMinute;

        if (root.manualActive !== undefined && (inBetween(from, manualActive, t) || inBetween(to, manualActive, t))) {
            root.manualActive = undefined;
        }
        root.shouldBeOn = inBetween(t, from, to);

        if (firstEvaluation) {
            firstEvaluation = false;
            return;
        }
        root.ensureState();
    }

    onShouldBeOnChanged: {
        if (!root.firstEvaluation)
            root.ensureState();
    }

    function ensureState() {
        if (!root.automatic || root.manualActive !== undefined)
            return;
        if (root.shouldBeOn) {
            root.enableTemperature();
        } else {
            root.disableTemperature();
        }
    }

    function startHyprsunset() {
        if (root.isNiri) return;
        // A daemon without -i comes up with its own default of 6000K already on the
        // displays, so the shell being merely *present* — started at boot, or woken up
        // by the gamma slider — would warm the screen without anyone asking for the
        // night light. Identity means it starts neutral and only enableTemperature,
        // which sets a real temperature, is allowed to tint anything.
        Quickshell.execDetached(["bash", "-c", `pidof hyprsunset || hyprsunset -i`]);
    }

    function load() {
        if (root.isNiri) {
            root.disableTemperature();
            return;
        }
        root.startHyprsunset();
        // A daemon that outlived the previous session keeps whatever curve it was left
        // with, and this shell knows nothing about it: with the schedule in charge it
        // is put right by the answer below, without it the light begins off. The old
        // `sleep 0.3; hyprctl hyprsunset identity` tried the same thing against a
        // socket that might not exist yet, and left the 6000K default standing when it
        // missed.
        if (root.automatic)
            root.ensureState();
        else
            root.disableTemperature();
        root.fetchState();
    }

    function enableTemperature() {
        if (root.isNiri) {
            root.startNiriSunset(root.colorTemperature);
        } else {
            root.startHyprsunset();
            Quickshell.execDetached(["bash", "-c", `hyprctl hyprsunset temperature ${root.colorTemperature}`]);
        }
        root.temperatureActive = true;
    }

    function disableTemperature() {
        if (root.isNiri) {
            root.stopNiriSunset();
        } else {
            Quickshell.execDetached(["hyprctl", "hyprsunset", "identity"]);
        }
        root.temperatureActive = false;
    }

    function setGamma(gamma) {
        root.gamma = Math.max(root.gammaLowerLimit, Math.min(100, gamma));
        root.gammaChangeAttempt();

        if (root.isNiri) {
            return;
        }
        root.startHyprsunset();
        Quickshell.execDetached(["bash", "-c", `hyprctl hyprsunset gamma ${root.gamma}`]);
    }

    function startNiriSunset(temp) {
        const low = temp;
        const high = temp + 50;
        Quickshell.execDetached(["bash", "-c",
            `pkill -x wlsunset; sleep 0.05; wlsunset -T ${high} -t ${low} -S 23:59 -s 00:00 -d 1 & disown`]);
    }

    function stopNiriSunset() {
        Quickshell.execDetached(["bash", "-c", "pkill -x wlsunset"]);
    }

    function fetchState() {
        if (root.isNiri) {
            niriFetchProc.running = true;
        } else {
            fetchProc.running = true;
        }
    }

    Process {
        id: fetchProc
        running: false
        // The reply to `temperature` is the number last stored, whatever the displays
        // are actually doing — it kept answering 5000 long after the matrix was reset
        // to identity. Only the identity flag says whether a curve is on the screens.
        command: ["bash", "-c", "hyprctl hyprsunset identity get 2>/dev/null"]
        stdout: StdioCollector {
            id: stateCollector
            onStreamFinished: {
                const output = stateCollector.text.trim();
                // No daemon, no socket and an identity matrix all mean the same thing
                // here: there is no night light to show as on.
                root.temperatureActive = output === "false";
            }
        }
    }

    Process {
        id: niriFetchProc
        running: false
        command: ["bash", "-c", "pgrep -x wlsunset"]
        stdout: StdioCollector {
            id: niriStateCollector
            onStreamFinished: {
                root.temperatureActive = niriStateCollector.text.trim().length > 0;
            }
        }
    }

    function toggleTemperature(active = undefined) {
        if (root.manualActive === undefined) {
            root.manualActive = root.temperatureActive;
            root.manualActiveHour = root.clockHour;
            root.manualActiveMinute = root.clockMinute;
        }

        root.manualActive = active !== undefined ? active : !root.manualActive;
        if (root.manualActive) {
            root.enableTemperature();
        } else {
            root.disableTemperature();
        }
    }

    Connections {
        target: Config.options.light.night
        function onColorTemperatureChanged() {
            if (!root.temperatureActive) return;
            if (root.isNiri) {
                root.startNiriSunset(Config.options.light.night.colorTemperature);
            } else {
                Quickshell.execDetached(["hyprctl", "hyprsunset", "temperature", `${Config.options.light.night.colorTemperature}`]);
            }
        }
    }
}
