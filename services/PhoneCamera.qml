pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import qs.modules.common

/**
 * The phone as a webcam, through scrcpy
 * (docs/superpowers/specs/2026-08-27-phone-tab-design.md, W3).
 *
 * `scrcpy --video-source=camera --v4l2-sink=/dev/videoN` decodes the phone's
 * camera on this machine and writes it into a v4l2loopback device, which is
 * what makes it a webcam every other application can open. Nothing has to be
 * installed on the phone: scrcpy pushes its own server over adb, so there is
 * no companion app, no port to configure and no address to plan a route to -
 * adb already knows how to reach the device, and scrcpy picks it the same way
 * the mirror does.
 *
 * It is launched DETACHED through scripts/phone/droidcam_session.sh - the
 * pidfile is the binary's own - so the webcam survives a shell restart and is
 * re-adopted at boot from the session's state file. No streaming Process
 * lives here: every command is a one-shot argv through one serialized queue,
 * and liveness is the session script's `status` verb on a watchdog, while a
 * connect is resolved by asking the node for one frame.
 *
 * The preview PLAYER is the one process this file owns outright, and it is
 * deliberately the opposite arrangement to the stream's: the stream outlives
 * the shell because a webcam other applications are using has to, while a
 * preview is a view of that stream and its lifetime is the session's. See
 * the `previewProc` block for what "owned" buys and what it costs.
 *
 * Everything between the sync markers is meant to be kept byte-for-byte in
 * sync with the logic-only double (tests/imports/testservices/PhoneCamera.qml),
 * enforced by tests/test_phone_sessions_contract.py. NEITHER exists in this
 * checkout - tests/ holds only icon_theme_manager/ - so that claim is debt, not
 * a passing check (the same debt PhoneDeps.qml:32 records). The markers are
 * still where argv-shaped logic belongs, and the double has to be regenerated
 * from this file before the contract can be enforced again.
 */
Singleton {
    id: root

    // The loopback module has to be LOADED, not merely installed: nothing in
    // the session's own script modprobes, so an unloaded module means no
    // /dev/videoN ever appears and a start that cannot possibly succeed. The
    // card then reads "unavailable", which is the only way its click reaches
    // the guide carrying the modprobe command.
    readonly property bool available: PhoneDeps.scrcpy
        && PhoneDeps.v4l2loopbackLoaded
    readonly property bool deviceReachable: PhoneConnect.activeDevice?.reachable === true
    readonly property string activeDeviceId: String(PhoneConnect.activeDevice?.id ?? "")

    property bool connecting: false
    property bool active: false
    // unavailable | offline | connecting | ready | active
    readonly property string state: root.stateFor(root.available, root.deviceReachable, root.connecting, root.active)

    property string device: "" // /dev/videoN
    property int sessionPid: 0
    property int startedAt: 0 // unix seconds
    property string lastError: ""
    property bool userStopped: false
    readonly property bool previewRunning: previewProc.running
    // Set by a restart that found a preview open, so the window comes back with
    // the session rather than being collateral damage of a camera flip.
    property bool previewAfterStart: false

    readonly property string sessionScript: `${Directories.scriptPath}/phone/droidcam_session.sh`
    readonly property int connectTimeoutMs: 9000
    readonly property int successAfterMs: 6000
    readonly property int frameProbeMs: 400
    // The first poll waits, and not for politeness: a connect is also the
    // moment scrcpy configures the node, and a reader attaching during that
    // window is the one case here that has never been measured against a live
    // phone. Every poll after it is the shape that was.
    readonly property int firstFrameProbeMs: 1200

    signal errorOccurred(string message)

    // BEGIN phone-camera logic (synced with tests/imports/testservices/PhoneCamera.qml)
    function stateFor(available: bool, reachable: bool, connecting: bool, active: bool): string {
        if (!available) return "unavailable";
        if (active) return "active";
        if (connecting) return "connecting";
        if (!reachable) return "offline";
        return "ready";
    }

    // `v4l2-ctl --list-devices` prints a name line per device - the card label
    // and the bus in brackets - followed by its indented nodes:
    //
    //     Dummy video device (0x0000) (platform:v4l2loopback-000):
    //         /dev/video2
    //
    // The bus is what identifies a loopback node, and it is the same whatever
    // the card has been labelled, so this does not have to guess from a name.
    // A machine's own webcam is `usb-...`, a VM's is `pci-...`.
    function parseV4l2Devices(text: string): string {
        const lines = (text ?? "").split("\n");
        let inLoopback = false;
        for (const raw of lines) {
            const line = raw.replace(/\s+$/, "");
            if (line.length === 0) continue;
            if (/^\s+\/dev\/video\d+/.test(line)) {
                if (inLoopback) return line.trim();
                continue;
            }
            inLoopback = /platform:v4l2loopback/.test(line);
        }
        return "";
    }

    // The webcam's scrcpy argv. Four of these flags are load-bearing and one
    // is a matter of taste:
    //
    //   --camera-size  is NOT decoration. Left out, scrcpy asks the camera for
    //                  its default size, the node is still holding the size
    //                  the last writer negotiated, and the encoder on the
    //                  phone throws IllegalArgumentException in
    //                  SurfaceEncoder.streamCapture - a session that dies
    //                  before it produces a frame.
    //   --crop         is what the aspect ratio row is. It changes the NODE's
    //                  own size (measured: --crop=720:720:280:0 on a 1280x720
    //                  capture makes a 720x720 node), so the crop is real for
    //                  every application that opens the webcam rather than a
    //                  trick the preview plays.
    //   --no-window    keeps a webcam out of the user's face; without it
    //                  scrcpy opens a window for every stream.
    //   --no-audio     because the microphone is a different feature with its
    //                  own card, and the camera source pulls the phone's mic
    //                  by default.
    //   --no-control   nothing here should be typing into the phone.
    //
    // `--capture-orientation` carries the turn and the mirror together, and the
    // number it carries is NOT the turn the mirror rides on. scrcpy's own help
    // says the `flip` keyword "applies a horizontal flip BEFORE the rotation",
    // and a horizontal flip conjugated by a quarter turn is a VERTICAL flip of
    // the upright picture - so `flip90` mirrors a Portrait stream up-down. The
    // value that mirrors the picture as displayed is the other quarter,
    // `(360 - upright) % 360`: measured on this POCO by classifying frames
    // against a flop and a flipud of the same unmirrored frame (ImageMagick
    // RMSE, lower is the match) - back lens upright at 90: flip90 -> flipud
    // 8372 vs flop 30500, flip270 -> flop 9899 vs flipud 30553; front lens
    // upright at 270, the pair reversed: flip270 -> flipud 3488, flip90 -> flop
    // 5217. Landscape is upright at 0, and (360-0)%360 is 0, which is why the
    // mirror was always correct there and only ever looked wrong in Portrait.
    //
    // Portrait is a turn, not a size. The phone only offers landscape capture
    // sizes, and `--capture-orientation=90` makes scrcpy write a 720x1280 node -
    // measured, both the node's format and the decoded frame swap. Which quarter
    // turn is UPRIGHT differs per camera, because the front one is mirrored in
    // the pipeline: on this POCO the back is upright at 90 and the front at 270,
    // so the two are 180° apart and the facing picks the value rather than one
    // constant serving both.
    function captureOrientation(conf: var): string {
        const c = conf ?? {};
        const upright = String(c.orientation ?? "").trim() === "portrait"
            ? (String(c.cameraFacing ?? "").trim() === "front" ? 270 : 90) : 0;
        return c.mirrorHorizontally ? "flip" + ((360 - upright) % 360) : String(upright);
    }

    // The box scrcpy crops the CAPTURE to, as "w:h:x:y", or "" for no crop.
    //
    // The orientation does not enter this. A ratio's long edge is laid along the
    // capture's long edge and the turn then turns the box with the picture
    // (measured: --crop=960:720 on a 1280x720 capture is a 960x720 node in
    // Landscape and a 720x960 one in Portrait), so "3:4" means the shape of the
    // picture however it stands - which is also why every ratio is achievable
    // from every capture size, rather than a tall ratio being impossible in
    // Landscape.
    //
    // Even numbers, because the node is YUV420; centred, because a corner crop
    // would cut the subject off to one side.
    //
    // "" is returned for "full", for anything unparsable, and for a crop that
    // would be the whole capture - an identity crop buys nothing and "Fullscreen"
    // means no crop at all. And no rect that overflows the capture is ever
    // returned, because scrcpy's server does not clip it: measured,
    // --crop=720:720:920:0 on a 1280-wide capture threw an IllegalStateException
    // on the video thread and produced not one frame. A rect that fits by
    // construction is the whole point; the alternative is a stream that dies.
    function cropArgument(ratio: string, captureSize: string): string {
        const r = /^(\d+):(\d+)$/.exec(String(ratio ?? "").trim());
        const s = /^(\d+)x(\d+)$/.exec(String(captureSize ?? "").trim());
        if (!r || !s) return "";
        const cw = Number(s[1]), ch = Number(s[2]);
        const a = Number(r[1]), b = Number(r[2]);
        if (cw < 2 || ch < 2 || a < 1 || b < 1) return "";
        const long = Math.max(a, b), short = Math.min(a, b);
        const evenDown = v => Math.floor(v / 2) * 2;
        // Fit the ratio box inside the capture: the edge that runs out of room
        // first decides which of the two is taken whole. The taken edge is
        // floored to even too, so an odd capture size cannot hand back an odd
        // crop - the node is YUV420 and every size the phone offers is even
        // already (measured, 176x144 through 4624x2080), which is why this only
        // shows up for a size the list does not contain.
        let w = evenDown(cw), h = evenDown(ch);
        if (cw * short >= ch * long) { h = evenDown(ch); w = evenDown(ch * long / short); }
        else { w = evenDown(cw); h = evenDown(cw * short / long); }
        if (w < 2 || h < 2 || w > cw || h > ch) return "";
        if (w === cw && h === ch) return "";
        return `${w}:${h}:${evenDown((cw - w) / 2)}:${evenDown((ch - h) / 2)}`;
    }

    // The size /dev/videoN ends up at: the crop box, or the whole capture when
    // there is none, turned by the quarter turn Portrait asks for. Checked
    // against the node's own `v4l2-ctl --get-fmt-video` reply for every cell this
    // produces, which is why the shell can name the webcam's size and shape its
    // preview window from the settings rather than asking the kernel again.
    function frameSize(captureSize: string, cropArg: string, orientation: string): var {
        const parts = String(cropArg ?? "").length > 0
            ? String(cropArg).split(":").slice(0, 2).join("x") : String(captureSize ?? "");
        const s = /^(\d+)x(\d+)$/.exec(parts.trim());
        if (!s) return { w: 0, h: 0 };
        const w = Number(s[1]), h = Number(s[2]);
        if (String(orientation ?? "").trim() === "portrait") return { w: h, h: w };
        return { w: w, h: h };
    }

    // The preview window's size. `maxHeight` is what the caller can actually put
    // on a screen; 0 means "do not cap". Shrinking is proportional, because the
    // window matches the video only while the two aspects are the same.
    function previewGeometry(width: int, height: int, maxHeight: int): var {
        if (width < 2 || height < 2) return { w: 0, h: 0 };
        const evenDown = v => Math.floor(v / 2) * 2;
        if (maxHeight >= 2 && height > maxHeight) {
            const h = evenDown(maxHeight);
            const w = evenDown(width * h / height);
            if (w >= 2 && h >= 2) return { w: w, h: h };
        }
        return { w: width, h: height };
    }

    function scrcpyWebcamArgs(conf: var, device: string): var {
        const c = conf ?? {};
        const facing = String(c.cameraFacing ?? "").trim();
        const size = String(c.resolution ?? "").trim();
        const capture = size.length > 0 ? size : "1280x720";
        const crop = root.cropArgument(String(c.aspectRatio ?? "").trim(), capture);
        const args = ["scrcpy",
            "--video-source=camera",
            "--camera-size=" + capture,
            "--v4l2-sink=" + device,
            "--capture-orientation=" + root.captureOrientation(c),
            "--no-window", "--no-control", "--no-audio"];
        if (crop.length > 0) args.push("--crop=" + crop);
        if (facing === "front" || facing === "back" || facing === "external")
            args.push("--camera-facing=" + facing);
        return args;
    }

    // The preview player: mpv, else ffplay, else vlc. Empty when none is there.
    //
    // `width`/`height` are the stream's own size and they are NOT decoration:
    // --force-window below makes mpv build its window before it has seen a
    // frame, so without a size it builds a 16:9-shaped box - measured on this
    // machine, 1344x756 for a 720x1280 v4l2 node and 960x540 for a file of the
    // same size - and --keepaspect spends the whole difference on black bars.
    // With the geometry passed the window came up at exactly 534x950 for that
    // node capped to 950, floating, all of it on the monitor.
    // Only mpv gets them: ffplay has no size flag in this build (`-x`/`-y` are
    // its initial window COORDINATES, and a probe with -x 400 -y 700 left it at
    // 949x1024), and vlc is here a fallback for a machine that has no mpv.
    function previewCommand(device: string, deps: var, width: int, height: int): var {
        const d = deps ?? {};
        if (!device) return [];
        const geometry = width >= 2 && height >= 2 ? `${width}x${height}` : "";
        // --force-window: mpv creates its window when the FIRST FRAME arrives,
        // and a session whose phone has stopped producing frames yields none,
        // so without it a click on preview appears to do nothing at all. That
        // is why the size is passed to it rather than the flag being dropped.
        if (d.mpv) {
            const args = ["mpv", "--profile=low-latency", "--no-fullscreen", "--no-osc",
                          "--force-window=immediate"];
            if (geometry.length > 0) args.push("--geometry=" + geometry);
            args.push("--title=imi webcam preview", "av://v4l2:" + device);
            return args;
        }
        if (d.ffplay) return ["ffplay", "-fflags", "nobuffer", "-framedrop",
                              "-window_title", "imi webcam preview", "-f", "v4l2", "-i", device];
        if (d.vlc) return ["vlc", "--no-video-title-show", "--no-fullscreen", "v4l2://" + device];
        return [];
    }

    // One `droidcam_session.sh status video` reply. The reply also carries
    // port/mode/ip, which belong to the microphone's droidcam-cli sessions and
    // mean nothing for a stream this side writes to a node.
    function parseSessionStatus(text: string): var {
        try {
            const doc = JSON.parse((text ?? "").trim());
            if (!doc || typeof doc !== "object") return null;
            return {
                alive: doc.alive === true || doc.alive === "true",
                pid: parseInt(doc.pid) || 0,
                started: parseInt(doc.started) || 0,
                device: String(doc.device ?? "")
            };
        } catch (e) {
            return null;
        }
    }

    function fail(message: string): void {
        root.connecting = false;
        root.active = false;
        root.lastError = message;
        root.errorOccurred(message);
    }

    // Is the stream live? Answered exactly rather than guessed at, by asking
    // the node for one frame: the phone pushes its server, opens the camera
    // and is streaming inside ~2 s, so the alternative - sitting on
    // `successAfterMs` and only then declaring a process that is still alive
    // to be a stream - spends 4 of those seconds saying "Connecting…".
    //
    // `v4l2-ctl --stream-mmap --stream-count=1` is NOT this probe, however
    // obvious it looks: measured, it exits 0 having written zero bytes when no
    // writer is attached at all, so it cannot tell a live stream from an empty
    // node. ffmpeg does: 0 only on a frame it actually decoded.
    //
    // `timeout` is load-bearing, not insurance. A reader that opens a node
    // whose format is pinned and which has no writer on it BLOCKS - measured,
    // it sat there past 4 s and past SIGTERM, and was still parked when its
    // shell was killed under it - so the poll has to be cut short from outside
    // rather than trusted to answer, and `-s KILL` because a process parked in
    // a kernel read does not answer SIGTERM.
    //
    // It runs on its OWN process rather than through `run()`, and that is not a
    // style choice either: Quickshell reports no exit at all for a program it
    // cannot start - measured, `exec` of a missing binary emits neither
    // `exited` nor an error - so a poll queued there would hold the queue's
    // callback open for ever and leave every later command, stop included,
    // unserved. `timeout` being the program means a reply always comes, and
    // its 127 for an absent ffmpeg is the real answer rather than a guess.
    function probeArgv(device: string): var {
        return ["timeout", "-s", "KILL", "1", "ffmpeg",
            "-hide_banner", "-loglevel", "error", "-f", "v4l2",
            "-i", device, "-frames:v", "1", "-f", "null", "-"];
    }

    function probeReply(code: int): void {
        if (!root.connecting) return;
        if (code === 0) { root.checkSession(); return; }
        // 127 is `timeout` not finding ffmpeg: this machine has no prober, and
        // asking for one every 400 ms for the rest of the connect is a waste.
        // successAfterMs decides the way it did before the probe existed.
        if (code === 127) { root.stopFrameProbe(); return; }
        root.armFrameProbe();
    }

    function start(): void {
        if (!root.available || root.connecting || root.active) return;
        if (!root.deviceReachable) {
            root.fail("No reachable phone - pair a device first");
            return;
        }
        root.connecting = true;
        root.userStopped = false;
        root.lastError = "";
        // The node is an argument the stream is started WITH now, not something
        // it reports back once running, so it has to be known first.
        root.refreshDevice(root.prepareNode);
    }

    // The loopback node holds the format its last writer negotiated, and a
    // writer wanting another size then attaches and produces NOTHING:
    // measured, a 1920x1080 session on a node left at 1280x720 stayed alive
    // for 20 s without a single frame reaching a reader, while the same
    // session recording to a file wrote 157 frames in 6 s. So the fault is the
    // node's, and `keep_format=0` - a runtime control, no root needed - is
    // what lets a resolution change land. Cleared before every launch rather
    // than once, because the module's own default is 1 and anything else on
    // the machine (DroidCam's CLI among them) may have set it back.
    function prepareNode(): void {
        if (!PhoneDeps.v4l2Ctl || root.device.length === 0) { root.launch(); return; }
        root.run(["v4l2-ctl", "-d", root.device, "--set-ctrl=keep_format=0"], (text, code) => {
            // A driver without that control answers non-zero; the stream is
            // still worth starting at the size it can hold.
            root.launch();
        });
    }

    // `v4l2-ctl --list-devices` → the loopback node to write to, then `then`.
    // Re-read on every start rather than remembered: the number moves when the
    // module is reloaded, when another loopback card appears, or when the
    // machine comes back from a reboot with the module loaded differently.
    function refreshDevice(then: var): void {
        if (!PhoneDeps.v4l2Ctl) {
            root.fail("v4l2-ctl is missing - install v4l-utils so the webcam can find its /dev/videoN");
            return;
        }
        root.run(["v4l2-ctl", "--list-devices"], (text, code) => {
            if (!root.connecting && !root.active) return;
            const node = code === 0 ? root.parseV4l2Devices(text) : "";
            if (node.length === 0) {
                root.fail("No v4l2loopback device to write to - load the kernel module (the install guide has the command)");
                return;
            }
            root.device = node;
            then?.();
        });
    }

    function launch(): void {
        // A stop that arrived while the node was being prepared is not a
        // reason to start a stream nobody is tracking any more: stop() has
        // already told the session script to end a session that did not exist
        // yet, and this would create it.
        if (!root.connecting) return;
        const argv = ["bash", root.sessionScript, "launch", "video"]
            .concat(root.scrcpyWebcamArgs(Config.options.phone.webcam, root.device));
        root.run(argv, (text, code) => {
            if (!root.connecting) return;
            if (code !== 0) {
                root.fail("scrcpy did not start - is the phone still reachable over adb?");
                return;
            }
            root.sessionPid = parseInt(text) || 0;
            root.armConnectTimers();
        });
    }

    function adoptStatus(status: var): void {
        root.sessionPid = status.pid;
        root.startedAt = status.started;
        root.connecting = false;
        root.active = true;
        root.lastError = "";
        if (status.device.length > 0) root.device = status.device;
        else root.refreshDevice(null);
        root.armWatchdog();
        // The close that came with a restart was the observer's doing, not a
        // decision anybody made, so the window comes back with the stream.
        const reopenPreview = root.previewAfterStart;
        root.previewAfterStart = false;
        if (reopenPreview && root.device.length > 0) root.openPreview();
    }

    function checkSession(): void {
        root.run(["bash", root.sessionScript, "status", "video"], (text, code) => {
            const status = root.parseSessionStatus(text);
            if (status && status.alive) {
                if (!root.active) root.adoptStatus(status);
                return;
            }
            if (root.active) {
                root.active = false;
                root.device = "";
                root.disarmWatchdog();
                if (!root.userStopped) root.fail("The webcam stream ended");
            } else if (root.connecting && root.connectDeadlinePassed()) {
                root.fail("Could not start the camera within " + Math.round(root.connectTimeoutMs / 1000)
                    + "s - scrcpy is alive but the phone has produced no frames");
            }
        });
    }

    function stop(): void {
        if (!root.connecting && !root.active) return;
        root.userStopped = true;
        root.disarmWatchdog();
        root.connecting = false;
        root.active = false;
        root.device = "";
        root.sessionPid = 0;
        root.run(["bash", root.sessionScript, "stop", "video"], null);
    }

    function toggle(): void {
        if (root.connecting || root.active) root.stop();
        else root.start();
    }

    // Every camera setting here is an argument the stream is STARTED with, so
    // changing one means a fresh session. The blink is the price; the
    // alternative is a control that does nothing until the next manual
    // restart, which is what this card's settings used to be.
    function restartSession(): void {
        if (!root.connecting && !root.active) return;
        const reopenPreview = root.previewRunning;
        root.stop();
        root.start();
        root.previewAfterStart = reopenPreview;
    }

    // The one way a setting is written. Picking the value that is already
    // active used to restart the stream too - a 3 s blink and a re-negotiated
    // node for a decision the user did not actually make - so the comparison
    // happens before anything is touched.
    function applySetting(key: string, value: var): void {
        const conf = Config.options.phone.webcam;
        if (conf[key] === value) return;
        conf[key] = value;
        root.restartSession();
    }

    function flip(): void {
        const conf = Config.options.phone.webcam;
        root.applySetting("cameraFacing", conf.cameraFacing === "front" ? "back" : "front");
    }

    function mirror(on: bool): void {
        root.applySetting("mirrorHorizontally", on);
    }

    // The preview belongs to the SESSION, not to the desktop: a player left
    // on a /dev/videoN that has stopped producing frames holds its last frame
    // on screen for ever, which is what it looks like when nothing owns it.
    // So the player is started through startPreview() - a handle, never a
    // detached spawn - and a second click while one is up is not a second
    // window.
    // `maxHeight` is how tall a window the caller can really show - the panel
    // passes its own window's height. A caller that is not on a screen at all
    // (a session re-adopted by a restarted shell) passes nothing and gets the
    // cap the last real open remembered, which is the size the user was looking
    // at.
    function openPreview(maxHeight): void {
        if (root.previewRunning) return;
        const asked = Number(maxHeight) || 0;
        if (asked > 0) root.previewCapHeight = Math.round(asked);
        // Two different empties, and they used to share one report. The
        // command is empty both when there is no player to watch with and
        // when there is nothing to watch: a session that never started - the
        // loopback module is not loaded, so no /dev/videoN ever appears -
        // left `device` empty and the error told the user to install mpv
        // while mpv sat there quite happily installed.
        if (!root.device) {
            root.lastError = "No webcam session to preview - start the webcam first";
            root.errorOccurred(root.lastError);
            return;
        }
        const geo = root.previewGeometry(root.streamWidth, root.streamHeight,
                                         root.previewCapHeight);
        const argv = root.previewCommand(root.device, PhoneDeps, geo.w, geo.h);
        if (argv.length === 0) {
            root.lastError = "No preview player found - install mpv";
            root.errorOccurred(root.lastError);
            return;
        }
        root.startPreview(argv);
    }

    function closePreview(): void {
        if (!root.previewRunning) return;
        root.stopPreview();
    }

    // One observer rather than a closePreview() in stop(), in checkSession()'s
    // death branch and in fail(): `active` IS the session, so every way the
    // session can end arrives here - the stop button, the watchdog finding the
    // pidfile dead, a connect that timed out, and the device disappearing,
    // which reaches it through onActiveDeviceIdChanged's own stop().
    onActiveChanged: if (!root.active) root.closePreview();
    // END phone-camera logic

    // ---- the shape the settings describe ----
    //
    // Computed once here rather than re-derived by each caller: the status line,
    // the preview window's size and the crop in the argv have to be the same
    // numbers, or a window sized for an uncropped stream shows exactly the black
    // bars the aspect row was added to remove.
    readonly property string webcamCrop: root.cropArgument(
        Config.options.phone.webcam.aspectRatio, Config.options.phone.webcam.resolution)
    readonly property var streamFrame: root.frameSize(
        Config.options.phone.webcam.resolution, root.webcamCrop,
        Config.options.phone.webcam.orientation)
    readonly property int streamWidth: root.streamFrame.w
    readonly property int streamHeight: root.streamFrame.h
    // Kept, not passed along: a setting change closes the preview and reopens it
    // with the session, and a reopen from the re-adopted status has no window of
    // its own to measure, so the last real cap is the only bound it can use.
    property int previewCapHeight: 0

    // ---- the preview player ----
    //
    // Owned rather than detached, and that IS the fix. `Quickshell.
    // execDetached` returns no handle, so nothing in the shell could stop the
    // player: ending the session left its window on screen, frozen on the last
    // frame the loopback device produced.
    //
    // The alternative - detach it and record the pid, the way the stream's own
    // session script does - buys a stop and costs a stale one. A stream is
    // stopped only by this shell, so its pid is good until it is used; a
    // player is closed by the USER at any moment, so a pid recorded when it
    // started is a number the kernel is free to hand to something else, and a
    // later stop would kill a stranger. A Process cannot address anything it
    // did not start, which is why that is the shape here and a pidfile is the
    // shape beside droidcam_session.sh.
    //
    // What it costs: the player does not outlive a shell restart the way the
    // stream deliberately does. A preview is one click to reopen; an
    // unstoppable one is the bug being fixed.
    function startPreview(argv: var): void {
        killEscalation.stop();
        previewProc.exec(argv);
    }
    // Stopping is not one signal. A player parked on a device that has never
    // produced a frame sits inside the kernel's read and answers neither
    // SIGTERM nor SIGINT - measured on mpv, `Sl` and alive through both - so
    // `running = false` alone leaves it running, its window on screen and
    // `previewRunning` stuck true, which is a close button that does nothing.
    // So the polite stop is followed up: if the process is still there a
    // moment later, it is killed.
    function stopPreview(): void {
        previewProc.running = false;
        killEscalation.restart();
    }

    Process {
        id: previewProc
        // process-lifecycle: restart-safe -- no `running:` binding and no
        // respawn of any kind. The player starts only from a click through
        // openPreview() and stops only through closePreview(), so a player
        // that exits instantly (a node it refuses, a missing codec) cannot
        // become a respawn loop.
    }

    Timer {
        id: killEscalation
        interval: 700
        // A player that took SIGTERM has exited and running is false by now,
        // so this fires only for the one that ignored it.
        onTriggered: if (previewProc.running) previewProc.signal(9)
    }

    // ---- timers ----

    property real connectStartedAt: 0

    function connectDeadlinePassed(): bool {
        return Date.now() - root.connectStartedAt >= root.connectTimeoutMs;
    }

    function armConnectTimers(): void {
        root.connectStartedAt = Date.now();
        successTimer.restart();
        failTimer.restart();
        frameProbe.interval = root.firstFrameProbeMs;
        frameProbe.restart();
    }

    function armWatchdog(): void { watchdog.restart(); }
    function disarmWatchdog(): void {
        watchdog.stop();
        successTimer.stop();
        failTimer.stop();
        root.stopFrameProbe();
    }

    function armFrameProbe(): void {
        frameProbe.interval = root.frameProbeMs;
        frameProbe.restart();
    }
    function stopFrameProbe(): void {
        frameProbe.stop();
        if (!frameProbeProc.running) return;
        frameProbeProc.running = false;
        // Terminating reaches `timeout`, which forwards the SIGTERM and walks
        // off, leaving the ffmpeg it was capping parked in a read that answers
        // nothing - the same orphan this probe produced before it had a cap at
        // all. So the stop escalates, as it does for the player.
        frameProbeKill.restart();
    }

    // The probe, one at a time: timer -> exec -> reply -> timer. A reply that
    // is not 0 re-arms, so the chain runs until a frame shows up or the
    // connect ends, and every link is capped by the poll's own `timeout`.
    function startFrameProbe(): void {
        if (root.device.length === 0) return;
        frameProbeProc.exec(root.probeArgv(root.device));
    }

    Process {
        id: frameProbeProc
        // No `running:` binding and no respawn: the probe is only ever started
        // from the timer. Its own process, so a probe that outlives its
        // connect cannot hold up the queue the session commands share.
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: (exitCode, exitStatus) => root.probeReply(exitCode)
    }

    Timer {
        id: frameProbeKill
        interval: 700
        onTriggered: if (frameProbeProc.running) frameProbeProc.signal(9)
    }

    // scrcpy pushes its server, opens the camera and starts negotiating, and
    // prints transient errors on the way; a process still alive this long in
    // is a stream.
    Timer {
        id: successTimer
        interval: root.successAfterMs
        onTriggered: if (root.connecting) root.checkSession()
    }

    // The poll behind probeArgv(): one ffmpeg run, re-armed by its own reply
    // only while the node still has no frame to give. The gap is 400 ms
    // because that is what the wait is worth: a stream on this device is live
    // between 2 and 2.8 s after the spawn, so the polling says so within one
    // hop of that, while successTimer's fixed 6 s kept the card on
    // "Connecting…" for four seconds the user could already be looking
    // through.
    Timer {
        id: frameProbe
        interval: root.frameProbeMs
        onTriggered: root.startFrameProbe()
    }

    Timer {
        id: failTimer
        interval: root.connectTimeoutMs
        onTriggered: if (root.connecting) root.checkSession()
    }

    Timer {
        id: watchdog
        interval: 5000
        repeat: true
        onTriggered: {
            if (!root.active) { watchdog.stop(); return; }
            root.checkSession();
        }
    }

    // ---- the serialized command queue ----

    property var callQueue: []
    property var activeCallback: null

    function run(argv: var, callback: var): void {
        root.callQueue.push({ argv: argv, callback: callback });
        root.pump();
    }

    function pump(): void {
        if (cmdProc.running || root.callQueue.length === 0) return;
        const next = root.callQueue.shift();
        root.activeCallback = next.callback;
        cmdProc.exec(next.argv);
    }

    Process {
        id: cmdProc
        environment: ({ LANG: "C", LC_ALL: "C" })
        stdout: StdioCollector { id: cmdOut }
        stderr: StdioCollector {}
        onExited: (exitCode, exitStatus) => {
            const callback = root.activeCallback;
            root.activeCallback = null;
            callback?.(cmdOut.text, exitCode);
            root.pump();
        }
    }

    // A webcam left running by the previous shell is adopted, not doubled.
    Component.onCompleted: root.checkSession()

    // Belt and braces, and measured as such: planted out and re-run, the
    // player is STILL reaped when the shell exits, because Quickshell kills a
    // Process it owns rather than leaving it behind. So this line states that
    // the preview's death at shutdown is intended - it is not the mechanism
    // that produces it, and it must not be read as one. The stream is not a
    // child of this process and is untouched either way, which is what lets
    // it be re-adopted when the shell comes back.
    Component.onDestruction: root.closePreview()

    onActiveDeviceIdChanged: if (root.active || root.connecting) root.stop()
}
