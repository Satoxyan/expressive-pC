pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import qs.modules.common

/**
 * scrcpy for the Phone tab: the screen mirror and app mode
 * (docs/superpowers/specs/2026-08-27-phone-tab-design.md, W3).
 *
 * QML holds no scrcpy process handle. One supervisor -
 * scripts/phone/scrcpy_session_manager.py, NDJSON on stdin/stdout - owns
 * every scrcpy child, its `imi-phone-<type>-<id>` window title and its
 * exit; this service sends launch/stop/focus/list_apps and applies the
 * started/exited/error/apps_list/apps_error events to the model. The
 * supervisor is started on demand by the first command and stopped by a
 * 10 s idle timer once no session is live and nothing is loading; a
 * supervisor that dies with commands still queued is restarted on the
 * DiscordVoice ladder (capped exponential backoff, five attempts), and one
 * that dies with nothing queued is simply gone until the next command.
 *
 * `mirrorArgs()` and `appModeArgs()` are the flag tables, pure: they share
 * `videoArgs()` and `audioArgs()`, and each takes its picture and sound
 * flags from its own table -
 * Config.options.phone.scrcpy for the mirror, its `appMode` child for an
 * app - so the two settings pages cannot leak into one another. App mode
 * adds --start-app, plus --new-display when its Virtual Display is on.
 * `targetArgs()` names a
 * wireless target when the user asked for one; the supervisor still
 * prefers a USB serial over it.
 *
 * Everything between the sync markers is kept byte-for-byte in sync with
 * the logic-only double (tests/imports/testservices/PhoneScrcpy.qml);
 * tests/test_phone_sessions_contract.py enforces it.
 */
Singleton {
    id: root

    readonly property bool available: PhoneDeps.scrcpy
    readonly property bool appModeSupported: PhoneDeps.appModeSupported
    readonly property var activeDevice: PhoneConnect.activeDevice
    // Tracked by id: the device OBJECT is rebuilt on every sweep, so a
    // change handler on it would fire once a poll.
    readonly property string activeDeviceId: String(PhoneConnect.activeDevice?.id ?? "")

    property bool mirrorRunning: false
    property bool mirrorLaunching: false
    property string lastError: ""
    // The MIRROR's own last failure, cleared by the next launchMirror().
    // `lastError` is written by any session's failure and by the supervisor's
    // own ladder, so a failed app launch an hour ago is still sitting in it
    // while the mirror card reads it - which is why the card's subtitle used
    // to have to ask the ADB precondition first to avoid quoting somebody
    // else's error. Scoped here, a non-empty string means "the launch you
    // just asked for did not take".
    property string mirrorError: ""

    // Facts about the phone that the settings page needs before a session
    // exists: its real screen size ("1220x2712") and the video encoders its
    // MediaCodec exposes. Both are answered by the supervisor, which is the
    // one thing that already resolves WHICH phone a command is aimed at.
    property string deviceScreenSize: ""
    property bool deviceScreenSizeLoading: false
    // [{ codec, name, label, hardware }] - the phone's video encoders, as
    // the supervisor parsed them from `scrcpy --list-encoders`.
    property var encoders: []
    property bool encodersLoading: false
    property string encodersError: ""
    // Set when a setting change stops a live mirror: the exited event
    // relaunches it with the new flags.
    property bool mirrorRestartPending: false

    // [{ name, package, system }]
    property var apps: []
    property bool appsLoading: false
    property string appsError: ""

    // Launcher icons: package -> the picture the supervisor wrote for it, and
    // "" once the phone has answered that it has none. `appIconsAsked` keeps a
    // second row from asking while the first answer is still on its way, and
    // `appIconsPending` is what holds the supervisor alive through a burst.
    property var appIcons: ({})
    property var appIconsAsked: ({})
    // Answers that have arrived but are not published yet. A sweep asks for a
    // phone's whole catalogue at once and the supervisor answers it in a few
    // hundred milliseconds; publishing per answer would rebuild the map and
    // rebind every visible row once per app, which is the scroll lag this list
    // paid for years. See `appIconAnswerTimer`.
    property var appIconAnswers: ({})
    // When each package was last asked, for the cooldown on re-asking one that
    // was answered "none". A bookkeeping map, never a binding source.
    property var appIconsAskedAt: ({})
    readonly property int appIconRetryMs: 5000
    // How long an ask with no answer coming back is taken to be in flight. Past
    // it the package is asked again: an answer can be lost when the supervisor
    // is stopped with a queue still in it, and a row must not stay empty because
    // of a request nobody remembers making any more.
    readonly property int appIconStaleMs: 15000
    property int appIconsPending: 0

    // One row per live scrcpy window: { id, type, title, pid, package, startedAt }.
    readonly property alias sessions: sessionsModel
    readonly property int sessionCount: sessionsModel.count

    readonly property var favorites: Config.options.phone.scrcpy.appMode.favoritePackages
    readonly property var recents: Persistent.states.phone.scrcpy.recentPackages
    readonly property int maxRecents: 20

    // idle | starting | running | restarting | stopped
    property string managerState: "idle"
    property int restartAttempts: 0
    readonly property int maxRestartAttempts: 5
    property var pendingMessages: []

    signal feedback(string message, bool ok)

    ListModel {
        id: sessionsModel
        dynamicRoles: true
    }

    // BEGIN phone-scrcpy logic (synced with tests/imports/testservices/PhoneScrcpy.qml)
    // The long edge of "WIDTHxHEIGHT" or of a bare number. scrcpy has no
    // exact-size flag: --max-size caps the long edge and derives the other
    // one from the phone's aspect ratio. 0 for anything unparsable.
    function resolutionLongEdge(text: string): int {
        const raw = String(text ?? "").trim().toLowerCase().replace(/\s+/g, "");
        let match = /^(\d{2,5})[x*](\d{2,5})$/.exec(raw);
        if (match) return Math.max(parseInt(match[1]), parseInt(match[2]));
        match = /^(\d{2,5})$/.exec(raw);
        return match ? parseInt(match[1]) : 0;
    }

    // A resolution as the settings page needs it. `ok` is false for text
    // that would become no flag at all; `text` is what gets stored.
    function parseResolution(text: string): var {
        const raw = String(text ?? "").trim().toLowerCase().replace(/\s+/g, "");
        if (raw.length === 0) return { ok: true, width: 0, height: 0, longEdge: 0, text: "" };
        let match = /^(\d{2,5})[x*](\d{2,5})$/.exec(raw);
        if (match) {
            const width = parseInt(match[1]);
            const height = parseInt(match[2]);
            if (width > 0 && height > 0)
                return { ok: true, width: width, height: height,
                         longEdge: Math.max(width, height), text: width + "x" + height };
        }
        match = /^(\d{2,5})$/.exec(raw);
        if (match) {
            const edge = parseInt(match[1]);
            if (edge > 0)
                return { ok: true, width: 0, height: 0, longEdge: edge, text: String(edge) };
        }
        return { ok: false, width: 0, height: 0, longEdge: 0, text: "" };
    }

    // "8M" / "8000000" / "8k" as whole Mbps, for the bit-rate spin box.
    function bitRateMbps(text: string): int {
        const match = /^(\d+(?:\.\d+)?)\s*([kmg]?)$/.exec(String(text ?? "").trim().toLowerCase());
        if (!match) return 0;
        const value = parseFloat(match[1]);
        const factor = match[2] === "k" ? 0.001 : match[2] === "g" ? 1000
            : match[2] === "m" ? 1 : 0.000001;
        return Math.max(0, Math.round(value * factor));
    }

    // "128K" / "128000" / "0.128M" as whole Kbps, for the audio bit-rate box.
    function bitRateKbps(text: string): int {
        const match = /^(\d+(?:\.\d+)?)\s*([kmg]?)$/.exec(String(text ?? "").trim().toLowerCase());
        if (!match) return 0;
        const value = parseFloat(match[1]);
        const factor = match[2] === "k" ? 1 : match[2] === "m" ? 1000
            : match[2] === "g" ? 1000000 : 0.001;
        return Math.max(0, Math.round(value * factor));
    }

    // The picture's flags, shared by the mirror and App Mode so the two
    // settings pages offer the same scrcpy table without either one owning
    // the list. `--video-buffer` is scrcpy >= 2's name for the display
    // buffer; empty options are no flag at all. App Mode leaves the video
    // toggle out: a virtual display needs a picture, and a mirrored app
    // without one would open with no window.
    function videoArgs(opts: var, includeVideoToggle = true): var {
        const o = opts ?? {};
        const args = [];
        if (includeVideoToggle && o.videoEnabled === false) args.push("--no-video");
        if (Number(o.maxFps) > 0) args.push("--max-fps=" + Number(o.maxFps));
        if (typeof o.bitRate === "string" && o.bitRate.trim() !== "") args.push("--video-bit-rate=" + o.bitRate.trim());
        const longEdge = root.resolutionLongEdge(o.resolution);
        if (longEdge > 0) args.push("--max-size=" + longEdge);
        if (Number(o.videoBuffer) > 0) args.push("--video-buffer=" + Number(o.videoBuffer));
        const codec = String(o.videoCodec ?? "").trim();
        if (codec.length > 0) args.push("--video-codec=" + codec);
        const encoder = String(o.videoEncoder ?? "").trim();
        if (encoder.length > 0) args.push("--video-encoder=" + encoder);
        // No flag at all is Auto (-1): scrcpy applies no static rotation, and
        // a followed session forwards the display's own turn.
        const orientation = Number(o.captureOrientation);
        if (orientation === 0 || orientation === 90 || orientation === 180 || orientation === 270)
            args.push("--capture-orientation=" + orientation);
        return args;
    }

    // The sound's flags, shared by the two features and read from the same
    // per-feature table as the picture's. A disabled audio is just
    // `--no-audio`: the other flags would describe a stream nobody captures.
    // `--audio-dup` is refused on any source but playback, so the duplicate
    // flag only ever travels with that source.
    function audioArgs(opts: var): var {
        const o = opts ?? {};
        if (o.audioEnabled === false) return ["--no-audio"];
        const args = [];
        const source = String(o.audioSource ?? "").trim();
        if (source.length > 0) args.push("--audio-source=" + source);
        if (source === "playback" && o.audioDup === true) args.push("--audio-dup");
        const codec = String(o.audioCodec ?? "").trim();
        if (codec.length > 0) args.push("--audio-codec=" + codec);
        const bitRate = String(o.audioBitRate ?? "").trim();
        if (bitRate.length > 0) args.push("--audio-bit-rate=" + bitRate);
        return args;
    }

    // The mirror's flags: the tab's own table plus the picture above.
    function mirrorArgs(opts: var): var {
        const o = opts ?? {};
        const args = [];
        if (o.stayAwake) args.push("--stay-awake");
        if (o.turnScreenOff) args.push("--turn-screen-off");
        if (o.noPowerOn) args.push("--no-power-on");
        if (o.showTouches) args.push("--show-touches");
        if (o.fullscreen) args.push("--fullscreen");
        if (o.alwaysOnTop) args.push("--always-on-top");
        // A followed window is resized by the compositor, which the aspect
        // lock would fight; same trade as App Mode's Auto.
        if (root.mirrorFollowsOrientation(o)) args.push("--no-window-aspect-ratio-lock");
        return args.concat(root.videoArgs(o), root.audioArgs(o));
    }

    // The size the app's virtual display is created at. A stored
    // resolution wins over displayWidth/Height: WIDTHxHEIGHT is used
    // exactly, a single edge scales the configured shape. Sizing the
    // display here matters because --max-size clamps a flex display's
    // width and height SEPARATELY, which would turn anything but the
    // display's own shape into a different one (a square, for a phone's
    // portrait screen).
    function appModeDisplaySize(appOpts: var): var {
        const o = appOpts ?? {};
        const width = Number(o.displayWidth) > 0 ? Number(o.displayWidth) : 1280;
        const height = Number(o.displayHeight) > 0 ? Number(o.displayHeight) : 960;
        const parsed = root.parseResolution(o.resolution);
        if (!parsed.ok || parsed.text.length === 0)
            return { width: width, height: height };
        if (parsed.width > 0 && parsed.height > 0)
            return { width: parsed.width, height: parsed.height };
        const scale = parsed.longEdge / Math.max(width, height);
        return {
            width: Math.max(1, Math.round(width * scale)),
            height: Math.max(1, Math.round(height * scale))
        };
    }

    // App Mode's Auto rotation only exists with a virtual display: the
    // supervisor watches THAT display and applies the orientation policy.
    // Without one the app runs on the phone's own screen and the page does
    // not offer Auto. The mirror has its own follow path below, on display 0.
    function appFollowsOrientation(appOpts: var): bool {
        const o = appOpts ?? {};
        return Number(o.captureOrientation) === -1 && o.flexDisplay === true;
    }

    // The mirror can follow the phone's own screen (display 0), whose logical
    // size swaps when the phone turns. Auto drops the fixed picture flag and
    // asks the supervisor to resize the window; a fullscreen window already
    // fills the screen, so there is nothing to follow.
    function mirrorFollowsOrientation(opts: var): bool {
        const o = opts ?? {};
        return Number(o.captureOrientation) === -1
            && o.videoEnabled !== false && o.fullscreen !== true;
    }

    // App mode: one app on a virtual display of its own when Virtual Display
    // is on, otherwise started on the phone's screen and mirrored. The
    // picture flags come from the appMode table, never from the mirror's,
    // and always include the picture - a virtual display needs video, and a
    // mirrored app without one would open with no window. There is no
    // virtual display to size, keep active or decorate when it is off.
    //
    // Auto rotation drops --flex-display: flex makes the display chase the
    // window while the supervisor makes the window chase the display, and
    // the two oscillate. The display stays at the configured size unless the
    // app turns it, which is exactly what the supervisor follows.
    function appModeArgs(packageName: string, appOpts: var): var {
        const o = appOpts ?? {};
        const args = ["--start-app=" + packageName];
        if (o.flexDisplay) {
            const size = root.appModeDisplaySize(o);
            const density = Number(o.density) > 0 ? Number(o.density) : 160;
            args.push("--new-display=" + size.width + "x" + size.height + "/" + density);
            if (root.appFollowsOrientation(o)) args.push("--no-window-aspect-ratio-lock");
            else args.push("--flex-display");
            if (o.keepActive) args.push("--keep-active");
            if (o.systemDecorations === false) args.push("--no-vd-system-decorations");
        }
        return args.concat(root.videoArgs(o, false), root.audioArgs(o));
    }

    // The `-s` target for a wireless phone: the address KDE Connect reaches
    // it on (autoWirelessIp) or the configured one, with the configured
    // port. Empty when the user did not ask for wireless or no address is
    // known - the supervisor then lets adb pick, USB first.
    function targetArgs(opts: var, device: var): var {
        const o = opts ?? {};
        if (!o.useWireless) return [];
        let ip = "";
        if (o.autoWirelessIp) {
            const addresses = device?.reachableAddresses ?? [];
            for (let i = 0; i < addresses.length; i++) {
                const address = String(addresses[i] ?? "").trim();
                if (address.length > 0) { ip = address; break; }
            }
        }
        if (!ip) ip = String(o.wirelessIp ?? "").trim();
        if (!ip) return [];
        const port = String(o.wirelessPort ?? "").trim() || "5555";
        return ["-s", ip.indexOf(":") >= 0 ? ip : ip + ":" + port];
    }

    function sessionIdFor(packageName: string): string {
        return "app:" + packageName;
    }

    // MRU: the package moves to the front, the list is capped.
    function pushRecent(list: var, packageName: string, max: int): var {
        const out = [];
        for (let i = 0; i < (list?.length ?? 0); i++) {
            const entry = String(list[i]);
            if (entry !== packageName) out.push(entry);
        }
        out.unshift(packageName);
        return out.slice(0, max);
    }

    function toggleInList(list: var, packageName: string): var {
        const out = [];
        let found = false;
        for (let i = 0; i < (list?.length ?? 0); i++) {
            const entry = String(list[i]);
            if (entry === packageName) { found = true; continue; }
            out.push(entry);
        }
        if (!found) out.push(packageName);
        return out;
    }

    function isFavorite(packageName: string): bool {
        const list = root.favorites ?? [];
        for (let i = 0; i < list.length; i++)
            if (String(list[i]) === packageName) return true;
        return false;
    }

    function sessionIndex(id: string): int {
        for (let i = 0; i < sessionsModel.count; i++)
            if (sessionsModel.get(i).id === id) return i;
        return -1;
    }

    function isAppRunning(packageName: string): bool {
        return root.sessionIndex(root.sessionIdFor(packageName)) >= 0;
    }

    // Delay before the Nth restart of the supervisor: 1s, 2s, 4s, ... 30s.
    function backoffDelay(attempt: int): int {
        return Math.min(30000, 1000 * Math.pow(2, Math.max(1, attempt) - 1));
    }

    // The supervisor is wanted while anything is live or pending - the
    // idle timer stops it otherwise. Icons count as pending: a page that has
    // just asked for forty of them must not have its supervisor shut down
    // halfway through the queue, and an unanswered package is never re-asked.
    function managerWanted(): bool {
        return sessionsModel.count > 0 || root.mirrorLaunching || root.appsLoading
            || root.appIconsPending > 0 || (root.pendingMessages?.length ?? 0) > 0;
    }

    function parseManagerLine(line: string): var {
        const trimmed = (line ?? "").trim();
        if (trimmed.length === 0) return null;
        try {
            const doc = JSON.parse(trimmed);
            return (doc && typeof doc === "object" && typeof doc.event === "string") ? doc : null;
        } catch (e) {
            return null;
        }
    }

    // One supervisor event onto the model.
    //
    // `started` is the supervisor saying it SPAWNED scrcpy, not that a mirror
    // is on screen - it emits the event the instant Popen returns and has no
    // way to know a window appeared. On a phone adb cannot see, scrcpy prints
    // "Could not find any ADB device" and exits about a second later, so
    // reading the spawn as `mirrorRunning` put the card on "scrcpy Mirror /
    // Mirror is running - click to focus its window", a filled check mark and
    // "Active for 0s" where no mirror could possibly exist, and then dropped
    // it back to the line it had before the click. A spawn therefore keeps
    // the mirror LAUNCHING and arms the settle; the settle, or the exit, is
    // what decides which it was.
    function applyEvent(msg: var): void {
        if (!msg) return;
        const id = String(msg.id ?? "");
        if (msg.event === "started") {
            const row = {
                id: id,
                type: String(msg.type ?? (id === "mirror" ? "mirror" : "app")),
                title: String(msg.title ?? ""),
                pid: Number(msg.pid ?? 0),
                package: id.startsWith("app:") ? id.substring(4) : "",
                startedAt: Date.now()
            };
            const index = root.sessionIndex(id);
            if (index >= 0) {
                for (const key in row) if (key !== "startedAt") sessionsModel.setProperty(index, key, row[key]);
            } else {
                sessionsModel.append(row);
            }
            if (id === "mirror") {
                // `alreadyRunning` is the supervisor answering about a child
                // it has been watching since some earlier launch, which IS
                // evidence of a live session - there is nothing to settle.
                if (msg.alreadyRunning === true) {
                    root.cancelMirrorSettle();
                    root.mirrorRunning = true;
                    root.mirrorLaunching = false;
                } else {
                    root.mirrorRunning = false;
                    root.mirrorLaunching = true;
                    root.armMirrorSettle();
                }
            }
        } else if (msg.event === "exited") {
            const index = root.sessionIndex(id);
            if (index >= 0) sessionsModel.remove(index);
            const failure = Number(msg.code ?? 0) !== 0 ? String(msg.error ?? "") : "";
            const restarting = id === "mirror" && root.mirrorRestartPending;
            if (id === "mirror") {
                const wasLaunching = root.mirrorLaunching;
                root.cancelMirrorSettle();
                root.mirrorRunning = false;
                root.mirrorLaunching = false;
                if (restarting) {
                    root.mirrorRestartPending = false;
                    root.launchMirror();
                } else {
                    // A launch that exits before the settle never opened a
                    // window, so silence would read as the click being
                    // ignored; say that rather than nothing.
                    root.mirrorError = failure.length > 0 ? failure
                        : (wasLaunching ? "scrcpy exited before the mirror window opened" : "");
                }
            }
            if (failure.length > 0 && !restarting) {
                root.lastError = failure;
                root.feedback(root.lastError, false);
            }
        } else if (msg.event === "error") {
            if (id === "mirror") {
                root.cancelMirrorSettle();
                root.mirrorLaunching = false;
                root.mirrorRunning = false;
                root.mirrorError = String(msg.message ?? "scrcpy error");
            }
            root.lastError = String(msg.message ?? "scrcpy error");
            root.feedback(root.lastError, false);
        } else if (msg.event === "apps_list") {
            root.apps = Array.isArray(msg.apps) ? msg.apps : [];
            // A cached list is served before the live one; loading stays on
            // until the live one lands.
            if (msg.cached !== true) {
                root.appsLoading = false;
                root.appsError = "";
            }
        } else if (msg.event === "apps_error") {
            root.appsLoading = false;
            root.appsError = String(msg.message ?? "Failed to list apps");
        } else if (msg.event === "app_icon") {
            const pkg = String(msg.package ?? "");
            if (pkg.length === 0) return;
            const path = String(msg.path ?? "");
            root.appIconsPending = Math.max(0, root.appIconsPending - 1);
            // Buffered rather than published: a sweep asks for a phone's whole
            // catalogue and the answers land within a few hundred milliseconds,
            // and a rebuilt map per answer is a rebinding pass over every visible
            // row per answer.
            //
            // An empty answer never replaces a picture that is already held,
            // though: "" is also what a link that timed out leaves behind, and
            // overwriting with it turns an icon the user can see into one they
            // cannot, for the rest of the session, with nothing left to retry it.
            const held = root.appIcons[pkg] ?? root.appIconAnswers[pkg];
            if (path.length === 0 && held !== undefined && held !== "") return;
            const answers = Object.assign({}, root.appIconAnswers);
            answers[pkg] = path;
            root.appIconAnswers = answers;
        } else if (msg.event === "device_size") {
            root.deviceScreenSize = Number(msg.width) + "x" + Number(msg.height);
            root.deviceScreenSizeLoading = false;
        } else if (msg.event === "device_size_error") {
            root.deviceScreenSizeLoading = false;
        } else if (msg.event === "encoders_list") {
            root.encoders = Array.isArray(msg.encoders) ? msg.encoders : [];
            root.encodersError = "";
            root.encodersLoading = false;
        } else if (msg.event === "encoders_error") {
            root.encoders = [];
            root.encodersError = String(msg.message ?? "Failed to list encoders");
            root.encodersLoading = false;
        }
    }

    // The settle's own answer: a spawned scrcpy still in the session list
    // after the settle has outlived every way a launch fails, so it is a
    // mirror rather than an attempt. A row that has gone means `exited`
    // already answered and this must not put the card back on `running`.
    function mirrorSettled(): void {
        if (root.sessionIndex("mirror") < 0) return;
        root.mirrorLaunching = false;
        root.mirrorRunning = true;
    }

    function handleLine(line: string): void {
        root.applyEvent(root.parseManagerLine(line));
    }

    function deviceId(): string {
        return root.activeDeviceId || "default";
    }

    function scrcpyTarget(): var {
        return root.targetArgs(Config.options.phone.scrcpy, root.activeDevice);
    }

    function launchMirror(): void {
        if (!root.available) {
            root.lastError = "scrcpy is not installed";
            return;
        }
        if (root.mirrorRunning) {
            root.focusMirror();
            return;
        }
        // A launch already in flight answers itself, through the settle or
        // through the supervisor's exit. Without this, a second click inside
        // the settle window gets `alreadyRunning` back - which is the
        // supervisor saying only that the child it spawned a moment ago has
        // not exited yet, i.e. exactly the weak evidence the settle exists to
        // stop reading as a mirror.
        if (root.mirrorLaunching) return;
        root.mirrorLaunching = true;
        root.lastError = "";
        root.mirrorError = "";
        const opts = Config.options.phone.scrcpy;
        root.send({
            cmd: "launch", id: "mirror", type: "mirror",
            target_args: root.scrcpyTarget(),
            extra_args: root.mirrorArgs(opts),
            follow_orientation: root.mirrorFollowsOrientation(opts)
        });
    }

    function stopMirror(): void {
        root.send({ cmd: "stop", id: "mirror" });
    }

    function focusMirror(): void {
        root.send({ cmd: "focus", id: "mirror" });
    }

    // ---- the mirror's settings ------------------------------------------

    // Every value on the settings page is a flag the session is STARTED
    // with, so a change to a live mirror is a restart: the supervisor is
    // told to stop, and the exited event relaunches it with the new table.
    // A change while nothing runs is just the next launch's flags.
    function applyMirrorSetting(key: string, value: var): void {
        const conf = Config.options.phone.scrcpy;
        if (conf[key] === value) return;
        conf[key] = value;
        root.restartMirrorForSettings();
    }

    // The encoder belongs to the codec: a name from another codec is a flag
    // scrcpy refuses. Dropping it here keeps one config write and one
    // restart rather than leaving a stale choice behind a disabled row.
    function setMirrorCodec(codec: string): void {
        const conf = Config.options.phone.scrcpy;
        if (conf.videoCodec === codec) return;
        conf.videoCodec = codec;
        const encoder = String(conf.videoEncoder ?? "").trim();
        if (encoder.length > 0 && !root.encoderForCodec(codec, encoder))
            conf.videoEncoder = "";
        root.restartMirrorForSettings();
    }

    function encoderForCodec(codec: string, name: string): bool {
        for (const entry of root.encoders ?? [])
            if (String(entry.codec) === codec && String(entry.name) === name) return true;
        return false;
    }

    // --audio-dup only exists for the playback source, so moving away from
    // playback drops the stored duplicate rather than leaving a choice no
    // flag can carry - the rule the video encoder already follows its codec.
    function setMirrorAudioSource(source: string): void {
        const conf = Config.options.phone.scrcpy;
        if (conf.audioSource === source) return;
        conf.audioSource = source;
        if (source !== "playback") conf.audioDup = false;
        root.restartMirrorForSettings();
    }

    function restartMirrorForSettings(): void {
        if (!root.mirrorRunning && !root.mirrorLaunching) return;
        if (root.mirrorRestartPending) return;
        root.mirrorRestartPending = true;
        root.stopMirror();
    }

    // ---- App Mode's settings --------------------------------------------

    // Every value is a launch flag, and App Mode can have several windows
    // live at once: a change is the NEXT launch's flags rather than a
    // restart of everything that is open. Nothing here touches a running
    // session, and the settings page says so.
    function applyAppSetting(key: string, value: var): void {
        const conf = Config.options.phone.scrcpy.appMode;
        if (conf[key] === value) return;
        conf[key] = value;
    }

    // Same rule as the mirror's: an encoder from another codec is a flag
    // scrcpy refuses, so the stale choice goes with the codec.
    function setAppCodec(codec: string): void {
        const conf = Config.options.phone.scrcpy.appMode;
        if (conf.videoCodec === codec) return;
        conf.videoCodec = codec;
        const encoder = String(conf.videoEncoder ?? "").trim();
        if (encoder.length > 0 && !root.encoderForCodec(codec, encoder))
            conf.videoEncoder = "";
    }

    function setAppAudioSource(source: string): void {
        const conf = Config.options.phone.scrcpy.appMode;
        if (conf.audioSource === source) return;
        conf.audioSource = source;
        if (source !== "playback") conf.audioDup = false;
    }

    // ---- the phone facts the settings page asks for ---------------------

    // The size the phone reports for its own display. Asked of the
    // supervisor rather than adb directly: the supervisor already resolves
    // which phone a command is for, USB before wireless, and a second
    // resolution here could pick a different phone than the mirror does.
    function refreshDeviceScreenSize(): void {
        if (!root.available || root.deviceScreenSizeLoading) return;
        root.deviceScreenSizeLoading = true;
        root.send({ cmd: "device_size", target_args: root.scrcpyTarget() });
    }

    // The video encoders the phone exposes, grouped by codec by the
    // supervisor. Listing them starts the scrcpy server on the phone, so
    // this is asked when the settings page opens rather than at startup.
    function refreshEncoders(): void {
        if (!root.available || root.encodersLoading) return;
        root.encodersLoading = true;
        root.encodersError = "";
        root.send({ cmd: "list_encoders", target_args: root.scrcpyTarget() });
    }

    // What the settings page calls when it appears. Both answers are cached
    // for the life of the device, so reopening the page does not start the
    // phone's scrcpy server again.
    function ensureDeviceFacts(): void {
        if (!root.available) return;
        if (root.deviceScreenSize.length === 0) root.refreshDeviceScreenSize();
        if (root.encoders.length === 0) root.refreshEncoders();
    }

    function refreshApps(): void {
        if (!root.appModeSupported) return;
        root.appsLoading = true;
        root.appsError = "";
        root.send({ cmd: "list_apps", target_args: root.scrcpyTarget(), deviceId: root.deviceId() });
    }

    function launchApp(packageName: string): void {
        if (!packageName) return;
        if (!root.appModeSupported) {
            root.lastError = "scrcpy 4.0+ is required for App Mode";
            root.feedback(root.lastError, false);
            return;
        }
        if (root.isAppRunning(packageName)) {
            root.focusApp(packageName);
            return;
        }
        const appOpts = Config.options.phone.scrcpy.appMode;
        root.send({
            cmd: "launch", id: root.sessionIdFor(packageName), type: "app",
            target_args: root.scrcpyTarget(),
            extra_args: root.appModeArgs(packageName, appOpts),
            follow_orientation: root.appFollowsOrientation(appOpts)
        });
        Persistent.states.phone.scrcpy.recentPackages =
            root.pushRecent(Persistent.states.phone.scrcpy.recentPackages, packageName, root.maxRecents);
    }

    function stopApp(packageName: string): void {
        if (!packageName) return;
        root.send({ cmd: "stop", id: root.sessionIdFor(packageName) });
    }

    function focusApp(packageName: string): void {
        if (!packageName) return;
        root.send({ cmd: "focus", id: root.sessionIdFor(packageName) });
    }

    function stopAllApps(): void {
        root.send({ cmd: "stop_all" });
    }

    function toggleFavorite(packageName: string): void {
        if (!packageName) return;
        Config.options.phone.scrcpy.appMode.favoritePackages =
            root.toggleInList(Config.options.phone.scrcpy.appMode.favoritePackages, packageName);
    }

    // ---- launcher icons --------------------------------------------------

    // The file the supervisor put on disk, as an Image source. Empty for a
    // package the phone has no picture for, which is what keeps its row's
    // generic glyph up instead of a hole.
    function appIconSource(packageName: string): string {
        const path = String(root.appIcons[packageName] ?? "");
        return path.length > 0 ? "file://" + path : "";
    }

    // Rows ask as they appear: a phone's whole catalogue is not worth one
    // ADB call per package before anyone has scrolled to it, and the
    // supervisor's cache answers the next shell without asking it again.
    // `urgent` is the ask of a row that is on screen: the supervisor drains
    // those before the background fill, so what the user is looking at never
    // waits behind the rest of the phone's app list.
    function requestAppIcon(packageName: string, urgent: bool): void {
        if (!packageName || !root.available) return;
        const answer = root.appIcons[packageName]
            ?? root.appIconAnswers[packageName];
        if (answer !== undefined && answer !== "")
            return;                     // a picture is already held
        const since = root.appIconsAskedAt[packageName] ?? 0;
        if (answer === undefined && root.appIconsAsked[packageName] === true
                && Date.now() - since < root.appIconStaleMs)
            return;                     // asked, and the answer is still in flight
        // A "none" answer is asked again when the row is looked at, because ""
        // is also what a link that blinked and an icon that was not cached yet
        // leave behind - and the row would otherwise stay a glyph beside a file
        // the phone has already written. The cooldown is what keeps a fast scroll
        // from turning that into a query per frame.
        if (answer === "" && Date.now() - since < root.appIconRetryMs)
            return;
        root.appIconsAsked[packageName] = true;
        root.appIconsAskedAt[packageName] = Date.now();
        root.appIconsPending++;
        root.send({
            cmd: "app_icon", package: packageName,
            priority: urgent === true,
            target_args: root.scrcpyTarget(), deviceId: root.deviceId()
        });
    }

    // When the page is opened, the packages answered "none" lose their asked
    // mark so the background fill walks them again - an empty answer is often a
    // link that was not up yet, and the record makes the retry a single
    // `pm path`. What bounds the chatter is the cooldown in `requestAppIcon`,
    // not this: an app with no icon is re-asked a few seconds after it is
    // looked at, and never on a timer while nobody is looking.
    function forgetEmptyAppIcons(): void {
        const asked = Object.assign({}, root.appIconsAsked);
        let forgotten = 0;
        for (const pkg of Object.keys(asked)) {
            if (root.appIcons[pkg] !== "") continue;
            delete asked[pkg];
            ++forgotten;
        }
        if (forgotten > 0) root.appIconsAsked = asked;
    }

    // Rows ask as they appear, which leaves a hole wherever the list has not been
    // scrolled: a package nobody has opened a row for has no icon to show even
    // though the phone has one. This asks for every one of them at once, and
    // answers whether it asked for anything.
    //
    // A sweep rather than one ask per tick, because a cached icon is now checked
    // against one listing of the phone instead of a lookup of its own: a whole
    // catalogue answers in the time this used to take to ask for three of them.
    // The order is still the supervisor's to choose - a row the user is looking at
    // asks with `priority`, which jumps the queue, and this fill does not.
    property int iconRetryTick: 0
    property int iconRetryCursor: 0

    function fillAppIconQueue(): bool {
        if (!root.available) return false;
        ++root.iconRetryTick;
        const now = Date.now();
        const apps = root.apps;
        if (!Array.isArray(apps)) return false;
        let asked = 0;
        for (let index = 0; index < apps.length; ++index) {
            const pkg = String(apps[index]?.package ?? "");
            if (pkg.length === 0) continue;
            if (root.appIcons[pkg] !== undefined
                    || root.appIconAnswers[pkg] !== undefined) continue;
            if (root.appIconsAsked[pkg] === true
                    && now - (root.appIconsAskedAt[pkg] ?? 0) < root.appIconStaleMs)
                continue;
            root.requestAppIcon(pkg, false);
            ++asked;
        }
        if (asked > 0) return true;
        // Nothing left to ask, which is not the same as everything answered: an
        // empty answer is also what a link that blinked leaves behind, and a row
        // told "no icon" before the phone had written its cache stays a glyph for
        // the rest of the session, because its ask is spent. So one of them is
        // asked again, in rotation, every twentieth tick - ten seconds of this
        // timer - and a package whose icon is cached by then answers out of the
        // listing this sweep already paid for.
        const empties = Object.keys(root.appIcons)
            .filter(pkg => root.appIcons[pkg] === "");
        if (empties.length === 0 || root.iconRetryTick % 20 !== 0) return false;
        const retry = empties[root.iconRetryCursor % empties.length];
        ++root.iconRetryCursor;
        const askedMap = Object.assign({}, root.appIconsAsked);
        delete askedMap[retry];
        root.appIconsAsked = askedMap;
        root.requestAppIcon(retry, false);
        return true;
    }

    // What the buffer is for: one rebuilt map per burst instead of one per answer,
    // because every visible row binds its picture source to this map and a rebuild
    // re-evaluates all of them. A package already held is never handed an empty
    // answer, which is the same rule the arrival used to enforce on its own.
    function publishAppIconAnswers(): void {
        const answers = root.appIconAnswers;
        if (Object.keys(answers).length === 0) return;
        const icons = Object.assign({}, root.appIcons);
        for (const pkg of Object.keys(answers)) {
            const path = String(answers[pkg]);
            if (path.length === 0 && icons[pkg] !== undefined && icons[pkg] !== "")
                continue;
            icons[pkg] = path;
        }
        root.appIcons = icons;
        root.appIconAnswers = {};
    }
    // END phone-scrcpy logic

    // ---- the mirror's settle ----

    // How long a spawned scrcpy has to stay alive before the mirror counts as
    // running, rather than as still launching. The supervisor cannot answer
    // "is a window up" - see applyEvent - so surviving the window in which a
    // launch fails is the evidence there is. Measured against scrcpy 3.1 with
    // no device attached: it prints "Could not find any ADB device" and exits
    // well inside a second. Erring long is the conservative direction here:
    // the card says "Connecting scrcpy…" for a beat longer than it strictly
    // needs to, where erring short is the lie this replaced.
    readonly property int mirrorSettleMs: 1500

    // Named hooks rather than the timer itself, because applyEvent is inside
    // the synced region and the logic-only double has no Timer to reach.
    function armMirrorSettle(): void {
        mirrorSettleTimer.restart();
    }

    function cancelMirrorSettle(): void {
        mirrorSettleTimer.stop();
    }

    Timer {
        id: mirrorSettleTimer
        interval: root.mirrorSettleMs
        onTriggered: root.mirrorSettled()
    }

    // The burst that a sweep's worth of answers is, published as one change. Long
    // enough that a phone's catalogue lands inside a single pass over the rows,
    // short enough that an icon is on its row before anyone has looked for it.
    Timer {
        id: appIconAnswerTimer
        interval: 120
        repeat: true
        running: Object.keys(root.appIconAnswers).length > 0
        onTriggered: root.publishAppIconAnswers()
    }

    // ---- the supervisor's lifetime ----

    function send(message: var): void {
        managerIdleTimer.restart();
        if (!manager.running) {
            root.pendingMessages = root.pendingMessages.concat([message]);
            root.startManager(true);
            return;
        }
        manager.write(JSON.stringify(message) + "\n");
    }

    function startManager(manual: bool): void {
        if (manager.running) return;
        if (manual) root.restartAttempts = 0;
        restartTimer.stop();
        root.managerState = "starting";
        manager.running = true;
    }

    function flushPending(): void {
        const queued = root.pendingMessages;
        root.pendingMessages = [];
        for (const message of queued)
            manager.write(JSON.stringify(message) + "\n");
    }

    // The supervisor stops every session when its stdin closes, so this is
    // only ever called with nothing live (managerWanted() false).
    function stopManager(): void {
        if (!manager.running) return;
        root.managerState = "idle";
        manager.running = false;
    }

    function clearLive(): void {
        root.cancelMirrorSettle();
        sessionsModel.clear();
        root.mirrorRunning = false;
        root.mirrorLaunching = false;
        root.mirrorRestartPending = false;
        root.appsLoading = false;
        // A query whose supervisor died will never answer; leaving these on
        // would make the settings page refuse to ask again.
        root.deviceScreenSizeLoading = false;
        root.encodersLoading = false;
        // Same for an icon ask that died mid-flight: forgetting it lets the
        // row ask again, while an answered package keeps its answer. An answer
        // that had only reached the buffer is still an answer, so it is published
        // before the in-flight list is pruned.
        root.publishAppIconAnswers();
        const unanswered = Object.keys(root.appIconsAsked)
            .filter(pkg => root.appIcons[pkg] === undefined);
        for (const pkg of unanswered) {
            delete root.appIconsAsked[pkg];
            delete root.appIconsAskedAt[pkg];
        }
        root.appIconsPending = Math.max(0, root.appIconsPending - unanswered.length);
    }

    onSessionCountChanged: managerIdleTimer.restart()
    onAppsLoadingChanged: managerIdleTimer.restart()
    onMirrorLaunchingChanged: managerIdleTimer.restart()
    onAppIconsPendingChanged: managerIdleTimer.restart()

    Timer {
        id: managerIdleTimer
        interval: 10000
        onTriggered: {
            if (root.managerWanted()) {
                managerIdleTimer.restart();
                return;
            }
            root.stopManager();
        }
    }

    Timer {
        id: restartTimer
        onTriggered: root.startManager(false)
    }

    Process {
        id: manager
        // process-lifecycle: restart-safe -- capped exponential backoff; no running binding.
        command: ["python3", `${Directories.scriptPath}/phone/scrcpy_session_manager.py`]
        stdinEnabled: true
        onStarted: {
            root.managerState = "running";
            root.flushPending();
        }
        stdout: SplitParser { onRead: data => root.handleLine(data) }
        stderr: SplitParser { onRead: data => console.warn("[PhoneScrcpy]", data) }
        onExited: (exitCode, exitStatus) => {
            const wasDeliberate = root.managerState === "idle";
            root.clearLive();
            if (wasDeliberate || root.pendingMessages.length === 0) {
                root.managerState = "idle";
                return;
            }
            if (root.restartAttempts >= root.maxRestartAttempts) {
                root.managerState = "stopped";
                root.pendingMessages = [];
                root.lastError = "scrcpy session manager stopped after repeated failures";
                // The mirror card is where a click that asked for this
                // supervisor is waiting for an answer; clearLive() has just
                // taken it off `launching`, so with nothing here it would go
                // back to its pre-click line and say nothing happened.
                root.mirrorError = root.lastError;
                root.feedback(root.lastError, false);
                return;
            }
            root.restartAttempts++;
            root.managerState = "restarting";
            restartTimer.interval = root.backoffDelay(root.restartAttempts);
            restartTimer.restart();
        }
    }

    // A device change is a different phone: what was mirrored is not what
    // the tab is about any more, and the size and encoder list belonged to
    // the old one.
    onActiveDeviceIdChanged: {
        if (sessionsModel.count > 0) root.send({ cmd: "stop_all" });
        root.deviceScreenSize = "";
        root.deviceScreenSizeLoading = false;
        root.encoders = [];
        root.encodersError = "";
        root.encodersLoading = false;
        // Icons are cached per phone, so the old one's answers - and the fact
        // that a package was already asked - belong to a different device.
        root.appIcons = {};
        root.appIconsAsked = {};
        root.appIconsAskedAt = {};
        root.appIconAnswers = {};
        root.appIconsPending = 0;
    }
}
