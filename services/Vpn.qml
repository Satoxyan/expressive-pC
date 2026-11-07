pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common

Singleton {
    id: root

    property list<var> profiles: []
    property list<string> activeUuids: []
    property string selectedUuid: ""
    property bool busy: connectProc.running || disconnectProc.running || actionProc.running
    property string pendingUuid: ""

    signal dialogRequested()

    readonly property var activeProfile: profiles.find(p => activeUuids.includes(p.uuid)) ?? null
    readonly property var selectedProfile: activeProfile
        ?? profiles.find(p => p.uuid === selectedUuid)
        ?? profiles[0]
        ?? null
    readonly property bool available: profiles.length > 0
    readonly property bool connected: activeProfile !== null

    // Whether the traffic leaving this machine is carried by a tunnel rather than by
    // the network card itself. Read off the default route and the type of whatever
    // interface it lands on, so a VPN that runs its own daemon — Cloudflare WARP,
    // Mullvad, Proton, openvpn — counts just as much as one NetworkManager knows
    // about, which is all `connected` can see.
    //
    // The answer is watched, not asked: whoever brings a VPN up gets the bar key
    // within a second, without the sidebar being opened to poke the listing.
    property string tunnelDevice: ""
    readonly property bool tunnelActive: tunnelDevice.length > 0
    readonly property bool running: connected || tunnelActive

    function splitFields(line) {
        const fields = [];
        let current = "";
        for (let i = 0; i < line.length; i++) {
            const ch = line[i];
            if (ch === "\\" && i + 1 < line.length) {
                current += line[++i];
            } else if (ch === ":") {
                fields.push(current);
                current = "";
            } else {
                current += ch;
            }
        }
        fields.push(current);
        return fields;
    }

    function refresh() {
        if (!listProc.running) listProc.running = true;
    }

    // The watcher never stops writing into the same buffer, so the current verdict
    // is simply the last line it has produced.
    function readTunnelLine() {
        const lines = tunnelOut.text.split("\n").filter(s => s.length > 0);
        const last = lines[lines.length - 1] ?? "";
        root.tunnelDevice = last === "-" ? "" : last;
    }

    function toggle() {
        const profile = root.selectedProfile;
        if (!profile) {
            root.dialogRequested();
            return;
        }
        if (busy) return;
        if (root.connected) disconnectProc.exec(["nmcli", "connection", "down", "uuid", root.activeProfile.uuid]);
        else connectProc.exec(["nmcli", "connection", "up", "uuid", profile.uuid]);
    }

    function connectTo(uuid) {
        if (busy) return;
        if (root.connected && root.activeProfile.uuid === uuid) {
            disconnectProc.exec(["nmcli", "connection", "down", "uuid", uuid]);
            return;
        }
        root.selectedUuid = uuid;
        if (root.connected) {
            root.pendingUuid = uuid;
            disconnectProc.exec(["nmcli", "connection", "down", "uuid", root.activeProfile.uuid]);
        } else {
            connectProc.exec(["nmcli", "connection", "up", "uuid", uuid]);
        }
    }

    function remove(uuid) {
        actionProc.exec(["nmcli", "connection", "delete", "uuid", uuid]);
    }

    function importFile(path) {
        const file = path.trim();
        if (file === "") return;
        const type = file.toLowerCase().endsWith(".ovpn") ? "openvpn" : "wireguard";
        actionProc.exec(["nmcli", "connection", "import", "type", type, "file", file]);
    }

    function pickAndImport() {
        if (!pickerProc.running) pickerProc.running = true;
    }

    function notifyFailure(message) {
        Quickshell.execDetached(["notify-send", "VPN", message, "-a", "Shell"]);
    }

    Timer {
        running: GlobalStates.sidebarRightOpen
        interval: 4000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: listProc
        command: ["bash", "-c", "nmcli -t -f NAME,UUID,TYPE connection show; echo :::ACTIVE; nmcli -t -f UUID connection show --active"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split(":::ACTIVE");
                const found = [];
                for (const line of parts[0].split("\n")) {
                    const fields = root.splitFields(line);
                    if (fields.length < 3) continue;
                    if (fields[2] === "vpn" || fields[2] === "wireguard")
                        found.push({ name: fields[0], uuid: fields[1], type: fields[2] });
                }
                root.profiles = found;
                root.activeUuids = (parts[1] ?? "").split("\n").map(s => s.trim()).filter(s => s.length > 0);
            }
        }
    }

    Process {
        id: tunnelWatch
        running: true
        // The interface the default route lands on, printed only when its type says
        // tunnel: 1 is a network card and 772 is the loopback, while 65534 covers
        // tun/tap/wireguard — WARP, Mullvad, Proton, openvpn alike — and 512 is ppp.
        // A line is written only when the verdict differs from the last one, so the
        // shell hears about a change and nothing else. `ip route get` rather than the
        // routing table because a VPN usually sits in its own table behind a rule.
        command: ["bash", "-c", "p=init; while :; do out=$(ip -4 route get 1.1.1.1 2>/dev/null); rest=\"${out#* dev }\"; d=\"${rest%% *}\"; t=\"\"; read -r t < \"/sys/class/net/$d/type\" 2>/dev/null; case \"$t\" in 1|772|\"\") c=\"\" ;; *) c=\"$d\" ;; esac; [ \"$c\" != \"$p\" ] && { echo \"${c:--}\"; p=\"$c\"; }; sleep 1; done"]
        stdout: StdioCollector {
            id: tunnelOut
            waitForEnd: false
            onStreamFinished: root.readTunnelLine()
            onDataChanged: root.readTunnelLine()
        }
        // Should it ever be killed, the bar key must not go deaf for good.
        onExited: tunnelWatch.running = true
    }

    Process {
        id: connectProc
        stderr: StdioCollector {
            id: connectErr
        }
        onExited: (code, status) => {
            if (code !== 0) root.notifyFailure(connectErr.text.trim() || "Connection failed");
            root.refresh();
        }
    }

    Process {
        id: disconnectProc
        onExited: {
            if (root.pendingUuid !== "") {
                const uuid = root.pendingUuid;
                root.pendingUuid = "";
                connectProc.exec(["nmcli", "connection", "up", "uuid", uuid]);
                return;
            }
            root.refresh();
        }
    }

    Process {
        id: actionProc
        stderr: StdioCollector {
            id: actionErr
        }
        onExited: (code, status) => {
            if (code !== 0) root.notifyFailure(actionErr.text.trim() || "Action failed");
            root.refresh();
        }
    }

    Process {
        id: pickerProc
        command: ["bash", "-c", "kdialog --getopenfilename \"$HOME\" '*.conf *.ovpn|VPN configs' 2>/dev/null || zenity --file-selection --file-filter='*.conf *.ovpn' 2>/dev/null"]
        stdout: StdioCollector {
            id: pickerOut
            onStreamFinished: root.importFile(pickerOut.text)
        }
    }
}
