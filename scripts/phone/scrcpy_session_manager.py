#!/usr/bin/env python3
"""scrcpy session supervisor for the Phone tab (services/PhoneScrcpy.qml).

One long-lived process speaking NDJSON on stdin/stdout. QML holds no scrcpy
process handles: it sends commands and reads events, and this supervisor owns
every scrcpy child, its window title and its exit.

Commands (one JSON object per line on stdin):
  {"cmd": "launch", "id": <session id>, "type": "mirror"|"app",
   "target_args": [...], "extra_args": [...],
   "follow_orientation": <bool>}
  {"cmd": "stop", "id": <session id>}
  {"cmd": "stop_all"}
  {"cmd": "focus", "id": <session id>}
  {"cmd": "list_apps", "target_args": [...], "deviceId": <cache key>}
  {"cmd": "device_size", "target_args": [...]}
  {"cmd": "list_encoders", "target_args": [...]}

Events (one JSON object per line on stdout):
  started    {id, pid, title[, alreadyRunning]}
  exited     {id, code, error}          error = scrcpy's last output line
  error      {id, message}
  apps_list  {deviceId, apps[, cached]} apps = [{package, name, system}]
  apps_error {message}
  device_size       {width, height}
  device_size_error {message}
  encoders_list  {encoders}   encoders = [{codec, name, label, hardware}]
  encoders_error {message}

Every scrcpy child is spawned as
  scrcpy [-s <serial>] --window-title=imi-phone-<type>-<id> <extra_args...>
so that `focus` can address the window by its title and nothing else. The
`-s` target is resolved from `adb devices` on every launch: a USB serial the
caller names and adb lists wins outright, then any USB serial (no ":" in it)
over any ip:port, and only when adb lists nothing do the caller's target_args
stand. Among several USB devices the pick is sorted, not adb's print order. A
wireless target the caller names is `adb connect`ed first, bounded, so a phone
on wireless debugging that adb has not seen yet still resolves.

App Mode may follow the app's orientation (`follow_orientation`). The
virtual display is created with `--new-display`; scrcpy logs its id on
stdout as "New display: WxH/DPI (id=N)". For a followed session this
supervisor tells the phone to honour orientation requests on THAT display
(`wm set-ignore-orientation-request -d N 0`), then watches the display's
logical size and resizes the scrcpy window to the new shape. The mirror can
follow too: it has no virtual display, so the display watched is the phone's
own (id 0) and no `wm` policy is applied - the phone's rotation stands and
only the window follows it. Hyprland ignores SDL's own resize, so the window
is resized through the compositor, preserving the window's current scale and
fitting within the usable screen minus scrcpy's own 96 px margins. A fixed
rotation instead pins the virtual display (`... 1`) so the picture flag is
the only rotation applied.

stdin closing means the shell went away; every session is stopped then, so a
shell restart never leaves headless scrcpy windows behind.
"""
import argparse
import collections
import json
import os
import queue
import re
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path

# scrcpy's last output line is what an `exited` event carries, so the drain
# below only has to keep the tail. Bounded because the drain runs for the
# life of the child and a chatty one is exactly the case it exists for.
STDERR_TAIL_LINES = 40
# How long to wait past the child's exit for the drain thread to see EOF.
STDERR_DRAIN_TIMEOUT = 2.0

CACHE_DIR = (Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache")
             / "immaterial-impulse" / "phone" / "apps")
TITLE_PREFIX = "imi-phone-"

# How often a followed display's logical size is read back. The display turns
# at speed the app chooses, so a short poll is the only reliable signal; the
# follow thread only polls while such a session is live.
FOLLOW_POLL_INTERVAL = 0.5
# scrcpy's own window sizing reserves this much of the usable screen
# (screen.c's DISPLAY_MARGINS, total per axis, not per side).
DISPLAY_MARGINS = 96

# Output line for a created virtual display (scrcpy's server logs are on
# stdout, which is why the supervisor merges the child's streams):
#   [server] INFO: New display: 960x1280/160 (id=39)
NEW_DISPLAY_LINE = re.compile(r"New display: \d+x\d+/\d+ \(id=(\d+)\)")
NEW_DISPLAY_ARG = re.compile(r"--new-display=(\d+)x(\d+)(?:/\d+)?")
# `dumpsys window displays` groups each display as
#   Display: mDisplayId=39
#     init=960x1280 160dpi cur=1280x960 app=1280x960 ...
# The logical size is `cur`; `wm size` reports the UNROTATED base size and is
# useless after the display turned.
DISPLAY_BLOCK_LINE = re.compile(r"^\s*Display: mDisplayId=(\d+)")
DISPLAY_CUR_SIZE = re.compile(r"\bcur=(\d+)x(\d+)")

# `scrcpy --list-apps` prints one app per line: `*` for a system app, `-` for
# a user app, then the label, then the package. The label may carry spaces.
APP_LINE = re.compile(r"^\s*([\*\-])\s+(.+?)\s+([a-zA-Z0-9_]+\.[a-zA-Z0-9_\.]+)\s*$")

# `adb shell wm size` prints "Physical size: WxH", and an "Override size: WxH"
# line when one is set. The override is what scrcpy mirrors, so it wins.
WM_SIZE_LINE = re.compile(r"^\s*(Physical|Override) size:\s*(\d+)x(\d+)\s*$",
                          re.IGNORECASE)

# `scrcpy --list-encoders` prints one line per encoder:
#   --video-codec=h264 --video-encoder=c2.qti.avc.encoder  (hw) [vendor]
# Aliases repeat the same encoder under a second name; they are dropped
# unless a codec has nothing else, because two rows that drive one encoder
# are a choice the user cannot tell apart.
VIDEO_ENCODER_LINE = re.compile(
    r"--video-codec=([a-z0-9]+)\s+--video-encoder=(\S+)(.*)$")


def session_title(type_str, session_id):
    return TITLE_PREFIX + str(type_str) + "-" + str(session_id).replace(":", "_")


def parse_app_list(lines):
    apps = []
    for line in lines:
        match = APP_LINE.match(line)
        if match:
            symbol, name, pkg = match.groups()
            apps.append({"package": pkg.strip(), "name": name.strip(),
                         "system": symbol == "*"})
    return apps


def parse_pm_list(lines):
    apps = []
    for line in lines:
        line = line.strip()
        if line.startswith("package:"):
            pkg = line[len("package:"):].strip()
            apps.append({"package": pkg, "name": pkg.split(".")[-1].capitalize(),
                         "system": False})
    return apps


def parse_wm_size(text):
    """(width, height) of the display, or None.

    An override wins over the physical size: `wm size` keeps the physical
    line after an override is set, and the override is what the display -
    and therefore scrcpy - actually draws.
    """
    physical = None
    override = None
    for line in (text or "").splitlines():
        match = WM_SIZE_LINE.match(line)
        if not match:
            continue
        size = (int(match.group(2)), int(match.group(3)))
        if match.group(1).lower() == "override":
            override = size
        else:
            physical = size
    return override or physical


def parse_new_display_size(args):
    """(width, height) of a `--new-display` flag, or None."""
    for arg in args or []:
        match = NEW_DISPLAY_ARG.search(str(arg))
        if match:
            return (int(match.group(1)), int(match.group(2)))
    return None


def parse_display_sizes(text):
    """The logical (cur=) size of every display in `dumpsys window displays`.

    `init=` is the size the display was created at and `cur=` the size it
    has now; only the latter turns when an app asks for another orientation.
    """
    sizes = {}
    current = None
    for line in (text or "").splitlines():
        block = DISPLAY_BLOCK_LINE.match(line)
        if block:
            current = int(block.group(1))
        elif line and not line[0].isspace():
            current = None
            continue
        if current is None or current in sizes:
            continue
        match = DISPLAY_CUR_SIZE.search(line)
        if match:
            sizes[current] = (int(match.group(1)), int(match.group(2)))
    return sizes


def lua_quote(value):
    """A Python string as the contents of a Lua string literal."""
    return str(value).replace("\\", "\\\\").replace('"', '\\"')


def parse_encoders(text):
    """The phone's video encoders, one entry per real encoder.

    `scrcpy --list-encoders` also prints the audio encoders; only lines that
    name a video codec and a video encoder are read.
    """
    groups = collections.OrderedDict()
    for line in (text or "").splitlines():
        match = VIDEO_ENCODER_LINE.search(line)
        if not match:
            continue
        codec, name, rest = match.groups()
        qualifiers = rest or ""
        alias = re.search(r"\(alias for ([^)]+)\)", qualifiers)
        hardware = "(hw)" in qualifiers
        label = name + (" (hw)" if hardware else " (sw)" if "(sw)" in qualifiers else "")
        groups.setdefault(codec, []).append({
            "codec": codec,
            "name": name,
            "label": label,
            "hardware": hardware,
            "aliasOf": alias.group(1) if alias else "",
        })
    encoders = []
    for entries in groups.values():
        primary = [entry for entry in entries if not entry["aliasOf"]]
        encoders.extend(primary or entries)
    return encoders


def dedupe_sorted(apps):
    seen = set()
    unique = []
    for app in apps:
        if app["package"] in seen:
            continue
        seen.add(app["package"])
        unique.append(app)
    unique.sort(key=lambda app: app["name"].lower())
    return unique


def cache_path(device_id):
    safe = re.sub(r"[^A-Za-z0-9_.-]", "_", str(device_id) or "default")
    return CACHE_DIR / f"{safe}.json"


class ScrcpySessionManager:
    def __init__(self):
        self.lock = threading.Lock()
        # A lock of its own, never `self.lock`: that one is held around the
        # process maps and an emit inside it would tie the two orders
        # together.
        self.emit_lock = threading.Lock()
        self.processes = {}     # session_id -> subprocess.Popen
        self.session_info = {}  # session_id -> {id, type, title, pid, startedAt, ...}
        # Sessions whose window follows a display: App Mode's virtual display
        # (id learned from scrcpy's output), or the phone's own display 0 for
        # a mirror. `size` is the last logical size the window was fitted to
        # (None until the first reading).
        self.follow_displays = {}
        self.follow_wake = threading.Event()
        self.follow_thread = None
        # The app scan runs on a worker of its own (see request_apps).
        self.apps_queue = queue.Queue()
        self.apps_worker = None

    def emit(self, event):
        """One lock around one write.

        `print(json.dumps(event), flush=True)` is two writes into a shared
        buffered stream, and every reaper thread emits `exited` concurrently
        with the main thread and with the app scan. An event large enough to
        flush part way through - an `apps_list` for a real phone is tens of
        kilobytes - can therefore be split by another thread's line, and
        interleaved NDJSON makes the QML parser return null and drop BOTH
        events. A lost `exited` leaves a session row live with no window
        behind it. Observed against real stdout at roughly one corruption in
        three runs of a stress harness.
        """
        line = json.dumps(event) + "\n"
        try:
            with self.emit_lock:
                sys.stdout.write(line)
                sys.stdout.flush()
        except Exception as error:  # a closed stdout: nothing left to tell
            sys.stderr.write(f"emit failed: {error}\n")

    # ---- adb -------------------------------------------------------------

    @staticmethod
    def named_serial(target_args):
        """The serial the caller asked for, `-s <serial>`, or ""."""
        args = list(target_args or [])
        for index, arg in enumerate(args):
            if arg == "-s" and index + 1 < len(args):
                return args[index + 1]
        return ""

    @classmethod
    def wireless_serial(cls, target_args):
        serial = cls.named_serial(target_args)
        return serial if ":" in serial else ""

    def connect_wireless(self, target_args):
        serial = self.wireless_serial(target_args)
        if not serial:
            return
        try:
            subprocess.run(["adb", "connect", serial], capture_output=True,
                           text=True, timeout=4)
        except Exception:
            pass

    def resolve_adb_target(self, target_args=None):
        """Which phone this launch is aimed at.

        A USB serial still beats a WIRELESS one the caller named, and that is
        deliberate rather than an oversight: `PhoneScrcpy.targetArgs()` names
        a wireless address whenever the "use wireless" setting is on and
        never names a USB serial at all, scrcpy over USB is the better link,
        and the rule is stated in the docstring at the top of this file and
        pinned by `test_a_usb_serial_wins_over_a_wireless_one`.

        What was wrong is narrower and had no argument behind it: with two
        phones attached, `usb_devices[0]` is whichever `adb devices` happened
        to print first, and nothing - not the caller, not the tab - could
        steer it. So a USB serial the caller names and adb really lists is
        honoured, and the unsteered pick is sorted rather than left to adb's
        output order, which is not a choice anybody made.
        """
        self.connect_wireless(target_args)
        requested = self.named_serial(target_args)
        try:
            res = subprocess.run(["adb", "devices"], capture_output=True,
                                 text=True, timeout=4)
            usb_devices = []
            ip_devices = []
            for line in res.stdout.splitlines():
                line = line.strip()
                if not line or line.startswith("List of"):
                    continue
                parts = line.split()
                if len(parts) >= 2 and parts[1] == "device":
                    serial = parts[0]
                    (ip_devices if ":" in serial else usb_devices).append(serial)
            if requested and requested in usb_devices:
                return ["-s", requested]
            if usb_devices:
                return ["-s", sorted(usb_devices)[0]]
            if ip_devices:
                return ["-s", sorted(ip_devices)[0]]
        except Exception:
            pass
        return list(target_args or [])

    # ---- apps ------------------------------------------------------------

    def emit_cached_apps(self, device_id):
        path = cache_path(device_id)
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            apps = data.get("apps")
        except Exception:
            return
        if isinstance(apps, list) and apps:
            self.emit({"event": "apps_list", "deviceId": device_id,
                       "apps": apps, "cached": True})

    def write_cache(self, device_id, apps):
        try:
            CACHE_DIR.mkdir(parents=True, exist_ok=True)
            path = cache_path(device_id)
            tmp = path.with_suffix(".json.tmp")
            tmp.write_text(json.dumps({"deviceId": device_id,
                                       "generatedAt": int(time.time()),
                                       "apps": apps}), encoding="utf-8")
            os.replace(tmp, path)
        except Exception as error:
            sys.stderr.write(f"cache write failed: {error}\n")

    def request_apps(self, target_args=None, device_id="default"):
        """Queue an app scan for the worker, and return to reading stdin.

        `list_apps` was called straight from the command loop, and it is
        worth up to ~26 seconds of blocking subprocesses: `adb connect` (4s)
        + `adb devices` (4s) + `scrcpy --list-apps` (10s) + `pm list` (8s).
        For all of that time `stop`, `stop_all` and `focus` were not even
        read off stdin, so a click on a live mirror did nothing until the
        scan the user had not asked about finished. Measured with a fake
        that sleeps 4s in `--list-apps`: a focus sent 0.3s in was acted on at
        4.01s.

        A queue with one worker rather than a thread per request, so two
        scans cannot run `adb` at each other, and so every request is
        answered in the order it arrived - a scan dropped as a duplicate is
        an `apps_list` the page waits for and never gets.
        """
        if self.apps_worker is None or not self.apps_worker.is_alive():
            self.apps_worker = threading.Thread(target=self._apps_loop, daemon=True)
            self.apps_worker.start()
        self.apps_queue.put((target_args, device_id))

    def _apps_loop(self):
        while True:
            target_args, device_id = self.apps_queue.get()
            try:
                self.list_apps(target_args, device_id)
            except Exception as error:
                self.emit({"event": "apps_error",
                           "message": f"Failed to list apps: {error}"})

    def list_apps(self, target_args=None, device_id="default"):
        device_id = device_id or "default"
        self.emit_cached_apps(device_id)
        target_args = self.resolve_adb_target(target_args)
        try:
            res = subprocess.run(["scrcpy"] + target_args + ["--list-apps"],
                                 capture_output=True, text=True, timeout=10)
            apps = parse_app_list(res.stdout.splitlines() + res.stderr.splitlines())

            device_ok = True
            if not apps:
                res_adb = subprocess.run(
                    ["adb"] + target_args + ["shell", "pm", "list", "packages", "-3"],
                    capture_output=True, text=True, timeout=8)
                device_ok = res_adb.returncode == 0
                if device_ok:
                    apps = parse_pm_list(res_adb.stdout.splitlines())

            # A phone that dropped off ADB is an error, not an empty catalog:
            # an empty list would wipe the apps already on screen.
            if not apps and not device_ok:
                self.emit({"event": "apps_error", "message": "Phone not reachable over ADB"})
                return

            unique = dedupe_sorted(apps)
            self.write_cache(device_id, unique)
            self.emit({"event": "apps_list", "deviceId": device_id, "apps": unique})
        except Exception as error:
            self.emit({"event": "apps_error", "message": f"Failed to list apps: {error}"})

    # ---- device facts ----------------------------------------------------

    def request_device_size(self, target_args=None):
        """Ask the phone for its display size on a worker.

        `resolve_adb_target` can spend up to 8 seconds on `adb connect` and
        `adb devices`, and this runs while a mirror may be live; a blocking
        call here would stop `stop` from being read off stdin for that long.
        """
        threading.Thread(target=self._device_size_worker,
                         args=(target_args,), daemon=True).start()

    def _device_size_worker(self, target_args):
        try:
            resolved = self.resolve_adb_target(target_args)
            res = subprocess.run(["adb"] + resolved + ["shell", "wm", "size"],
                                 capture_output=True, text=True, timeout=10)
            size = parse_wm_size(res.stdout)
            if size:
                self.emit({"event": "device_size",
                           "width": size[0], "height": size[1]})
                return
            lines = (res.stderr or res.stdout or "").strip().splitlines()
            self.emit({"event": "device_size_error",
                       "message": lines[0] if lines else "No display size reported"})
        except Exception as error:
            self.emit({"event": "device_size_error", "message": str(error)})

    def request_encoders(self, target_args=None):
        """List the phone's video encoders on a worker.

        `scrcpy --list-encoders` pushes the server and starts it, so it takes
        over a second even on a good link - the same reason the app scan has
        a worker of its own.
        """
        threading.Thread(target=self._encoders_worker,
                         args=(target_args,), daemon=True).start()

    def _encoders_worker(self, target_args):
        try:
            resolved = self.resolve_adb_target(target_args)
            res = subprocess.run(["scrcpy"] + resolved + ["--list-encoders"],
                                 capture_output=True, text=True, timeout=15)
            encoders = parse_encoders(res.stdout + "\n" + res.stderr)
            if encoders:
                self.emit({"event": "encoders_list", "encoders": encoders})
                return
            lines = [line.strip() for line in
                     (res.stderr or res.stdout or "").splitlines() if line.strip()]
            message = next((line for line in reversed(lines)
                            if "ERROR" in line.upper()),
                           lines[-1] if lines else "No video encoders reported")
            self.emit({"event": "encoders_error", "message": message})
        except Exception as error:
            self.emit({"event": "encoders_error", "message": str(error)})

    # ---- sessions --------------------------------------------------------

    def launch_session(self, session_id, type_str, target_args, extra_args,
                       follow_orientation=False):
        if not session_id:
            self.emit({"event": "error", "id": "", "message": "launch needs an id"})
            return
        with self.lock:
            proc = self.processes.get(session_id)
            if proc is not None and proc.poll() is None:
                pid = proc.pid
            else:
                pid = None
        if pid is not None:
            self.focus_session(session_id)
            self.emit({"event": "started", "id": session_id, "pid": pid,
                       "title": session_title(type_str, session_id),
                       "alreadyRunning": True})
            return

        title = session_title(type_str, session_id)
        extra_args = list(extra_args or [])
        adb_args = self.resolve_adb_target(target_args)
        cmd = (["scrcpy"] + adb_args
               + ["--window-title=" + title] + extra_args)
        try:
            proc = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, text=True)
        except Exception as error:
            self.emit({"event": "error", "id": session_id,
                       "message": f"Failed to launch scrcpy: {error}"})
            return

        with self.lock:
            self.processes[session_id] = proc
            info = {
                "id": session_id, "type": type_str, "title": title,
                "pid": proc.pid, "startedAt": int(time.time()),
                # The display id is learned from scrcpy's output. The
                # baseline comes from the launch flag so a turn that happens
                # before the first poll is still a change to follow.
                "followOrientation": bool(follow_orientation),
                "adbArgs": adb_args,
                "displayId": None,
                "displaySize": parse_new_display_size(extra_args)}
            self.session_info[session_id] = info
            # A followed session without a virtual display is the mirror. Its
            # display is the phone's own (id 0), which swaps its logical size
            # when the phone turns; no wm policy applies - the phone's own
            # rotation stands - but the window still has to follow. The first
            # poll records the baseline, so the shape the phone starts in is
            # never treated as a turn.
            mirror_follow = (bool(follow_orientation)
                             and info["displaySize"] is None)
            if mirror_follow:
                self.follow_displays[session_id] = {
                    "display_id": 0,
                    "title": title,
                    "args": adb_args,
                    "size": None,
                }
        if mirror_follow:
            self._ensure_follow_thread()
        self.emit({"event": "started", "id": session_id, "pid": proc.pid, "title": title})
        threading.Thread(target=self._wait_process, args=(session_id, proc),
                         daemon=True).start()

    def _drain_output(self, proc, tail, session_id):
        """Read the child's output for as long as it writes, keeping the tail.

        scrcpy's server logs go to STDOUT (the ADB push message and client
        warnings are the stderr half), which is why the child's streams are
        merged: the "New display ... (id=N)" line needed to apply a followed
        display's orientation is only ever on stdout.

        This used to be a single `read()` AFTER `proc.wait()`. A pipe holds
        ~64 KiB: past that, scrcpy blocks in `write()` with nobody reading,
        so it never exits, `wait()` never returns, no `exited` event is ever
        emitted, and the card sits on "running" over a frozen mirror with
        nothing in any log. Draining while it runs is what `communicate()`
        does; a thread is used so the wait below still returns the moment the
        child is gone rather than when its output reaches EOF (a grandchild
        can hold that open).
        """
        stream = proc.stdout
        if stream is None:
            return
        try:
            for line in stream:
                stripped = line.strip()
                if not stripped:
                    continue
                tail.append(stripped)
                match = NEW_DISPLAY_LINE.search(stripped)
                if match:
                    try:
                        self._on_new_display(session_id, int(match.group(1)))
                    except Exception as error:
                        # Never let a handling error end this loop: the pipe
                        # would fill and scrcpy would block in write().
                        sys.stderr.write(f"orientation: {error}\n")
        except Exception:
            pass
        finally:
            try:
                stream.close()
            except Exception:
                pass

    def _wait_process(self, session_id, proc):
        tail = collections.deque(maxlen=STDERR_TAIL_LINES)
        drain = threading.Thread(target=self._drain_output,
                                 args=(proc, tail, session_id), daemon=True)
        drain.start()
        code = proc.wait()
        drain.join(timeout=STDERR_DRAIN_TIMEOUT)
        err_msg = tail[-1] if tail else ""
        with self.lock:
            if self.processes.get(session_id) is proc:
                del self.processes[session_id]
                self.session_info.pop(session_id, None)
                self.follow_displays.pop(session_id, None)
        self.follow_wake.set()
        self.emit({"event": "exited", "id": session_id, "code": code, "error": err_msg})

    def stop_session(self, session_id):
        with self.lock:
            proc = self.processes.get(session_id)
        if proc is None or proc.poll() is not None:
            return
        try:
            proc.terminate()
            for _ in range(20):
                if proc.poll() is not None:
                    return
                time.sleep(0.1)
            proc.kill()
        except Exception:
            pass

    def stop_all(self):
        with self.lock:
            ids = list(self.processes.keys())
        for session_id in ids:
            self.stop_session(session_id)

    def focus_session(self, session_id):
        with self.lock:
            info = self.session_info.get(session_id)
        if not info or not info.get("title"):
            return
        selector = f"title:^{info['title']}$"
        self.hypr_dispatch(
            f'hl.dsp.focus({{ window = "{lua_quote(selector)}" }})',
            ["focuswindow", selector])

    # ---- followed orientation -------------------------------------------

    def _on_new_display(self, session_id, display_id):
        """scrcpy created this session's virtual display, id in hand.

        scrcpy logs the id before `--start-app` starts the app, so applying
        the policy here is the one point that beats the app's first
        orientation request. A followed display is registered before the
        `wm` command returns: the baseline size is known from the launch
        flag, so an early turn is not lost while `adb` is still talking.
        """
        with self.lock:
            info = self.session_info.get(session_id)
            if info is None:
                return
            info["displayId"] = display_id
            follow = bool(info.get("followOrientation"))
            args = list(info.get("adbArgs") or [])
            baseline = info.get("displaySize")
            if follow:
                self.follow_displays[session_id] = {
                    "display_id": display_id,
                    "title": info["title"],
                    "args": args,
                    "size": baseline,
                }
        if follow:
            self._ensure_follow_thread()
        threading.Thread(target=self._set_ignore_orientation,
                         args=(args, display_id, not follow),
                         daemon=True).start()

    @staticmethod
    def _set_ignore_orientation(adb_args, display_id, ignore):
        """Honour (0) or ignore (1) app orientation requests on a display.

        The value is an integer on this Android build; `true`/`false` are
        rejected with a NumberFormatException.
        """
        value = "1" if ignore else "0"
        try:
            res = subprocess.run(
                ["adb"] + list(adb_args)
                + ["shell", "wm", "set-ignore-orientation-request",
                   "-d", str(display_id), value],
                capture_output=True, text=True, timeout=8)
        except Exception as error:
            sys.stderr.write(f"orientation: {error}\n")
            return
        if res.returncode != 0:
            lines = (res.stderr or res.stdout or "").strip().splitlines()
            sys.stderr.write(
                f"orientation: wm set-ignore-orientation-request -d "
                f"{display_id} {value} failed"
                + (f": {lines[0]}" if lines else "") + "\n")
        else:
            sys.stderr.write(f"orientation: display {display_id} ignore={value}\n")

    def _ensure_follow_thread(self):
        with self.lock:
            if self.follow_thread is None or not self.follow_thread.is_alive():
                self.follow_thread = threading.Thread(target=self._follow_loop,
                                                      daemon=True)
                self.follow_thread.start()
        # Even a live thread may be parked on the no-contexts wait; a new
        # context has to wake it, not wait for another session to end.
        self.follow_wake.set()

    def _follow_loop(self):
        while True:
            with self.lock:
                contexts = {sid: dict(entry)
                            for sid, entry in self.follow_displays.items()}
            if not contexts:
                self.follow_wake.wait()
                self.follow_wake.clear()
                continue
            try:
                self._poll_followed_displays(contexts)
            except Exception as error:
                sys.stderr.write(f"orientation poll failed: {error}\n")
            self.follow_wake.wait(FOLLOW_POLL_INTERVAL)
            self.follow_wake.clear()

    def _poll_followed_displays(self, contexts):
        groups = collections.OrderedDict()
        for session_id, context in contexts.items():
            groups.setdefault(tuple(context.get("args") or ()), []).append(
                (session_id, context))
        for args, members in groups.items():
            sizes = self._read_display_sizes(args)
            if not sizes:
                continue
            for session_id, context in members:
                display_id = context["display_id"]
                observed = sizes.get(display_id)
                if observed is None:
                    continue
                previous = context.get("size")
                if observed == previous:
                    continue
                if previous is None:
                    # First reading of a display with no known baseline: it
                    # is where the window already is, not a turn to apply.
                    self._remember_display_size(session_id, display_id, observed)
                    continue
                if not self._resize_window(context["title"], previous, observed):
                    # The window may not be mapped yet; keep the old
                    # baseline so the next poll tries again.
                    continue
                self._remember_display_size(session_id, display_id, observed)
                sys.stderr.write(
                    f"orientation: {context['title']} "
                    f"{previous[0]}x{previous[1]} -> "
                    f"{observed[0]}x{observed[1]}\n")

    def _remember_display_size(self, session_id, display_id, size):
        with self.lock:
            entry = self.follow_displays.get(session_id)
            if entry is not None and entry["display_id"] == display_id:
                entry["size"] = size

    @staticmethod
    def _read_display_sizes(adb_args):
        try:
            res = subprocess.run(
                ["adb"] + list(adb_args)
                + ["shell", "dumpsys", "window", "displays"],
                capture_output=True, text=True, timeout=6)
        except Exception:
            return {}
        if res.returncode != 0:
            return {}
        return parse_display_sizes(res.stdout)

    def _resize_window(self, title, old_size, new_size):
        """Fit the scrcpy window to the display's new shape.

        True means the window is now (or already was) at the target size, so
        the new size may become the baseline. False leaves the old baseline
        in place and the next poll retries - the window is often not mapped
        yet when a fast app turns its display.
        """
        client = next((entry for entry in self._hypr_json(["clients"])
                       if entry.get("title") == title
                       and entry.get("mapped", True)), None)
        if client is None:
            return False
        window_size = client.get("size") or []
        if len(window_size) != 2 or window_size[0] <= 0 or window_size[1] <= 0:
            return False
        target = self._follow_target_size(
            (int(window_size[0]), int(window_size[1])), old_size, new_size,
            client.get("monitor"))
        if target is None:
            return False
        if abs(target[0] - window_size[0]) <= 2 and abs(target[1] - window_size[1]) <= 2:
            return True
        selector = f"title:^{title}$"
        expression = ('hl.dsp.window.resize({ x = %d, y = %d, window = "%s" })'
                      % (target[0], target[1], lua_quote(selector)))
        return self.hypr_dispatch(
            expression,
            ["resizewindowpixel",
             f"exact {target[0]} {target[1]},{selector}"])

    def _follow_target_size(self, window_size, old_size, new_size, monitor_id):
        if old_size[0] <= 0 or old_size[1] <= 0:
            return None
        # Keep the scale the window was already showing the content at, so a
        # window the user resized stays that size through the turn.
        scale = min(window_size[0] / old_size[0], window_size[1] / old_size[1])
        monitor = self._hypr_monitor(monitor_id)
        if monitor is not None:
            try:
                monitor_scale = float(monitor.get("scale") or 1.0)
            except (TypeError, ValueError):
                monitor_scale = 1.0
            if monitor_scale <= 0:
                monitor_scale = 1.0
            reserved = monitor.get("reserved") or [0, 0, 0, 0]
            usable_w = (monitor.get("width", 0) / monitor_scale
                        - reserved[0] - reserved[2] - DISPLAY_MARGINS)
            usable_h = (monitor.get("height", 0) / monitor_scale
                        - reserved[1] - reserved[3] - DISPLAY_MARGINS)
            if usable_w > 0 and usable_h > 0:
                scale = min(scale, usable_w / new_size[0],
                            usable_h / new_size[1])
        if scale <= 0:
            return None
        return (max(1, round(new_size[0] * scale)),
                max(1, round(new_size[1] * scale)))

    def _hypr_monitor(self, monitor_id):
        monitors = self._hypr_json(["monitors"])
        for monitor in monitors:
            if monitor.get("id") == monitor_id:
                return monitor
        return monitors[0] if monitors else None

    @staticmethod
    def _hypr_json(args):
        try:
            res = subprocess.run(["hyprctl", "-j"] + list(args),
                                 capture_output=True, text=True, timeout=4)
            if res.returncode != 0:
                return []
            data = json.loads(res.stdout)
        except Exception:
            return []
        return data if isinstance(data, list) else []

    @staticmethod
    def hypr_dispatch(expression, legacy_args):
        """Run a dispatcher as Lua, falling back to the legacy argv syntax.

        Hyprland with a Lua config rejects `dispatch focuswindow ...` (exit
        7), and a legacy config rejects the Lua expression; trying Lua first
        and the old form second is what lets one supervisor drive either.
        """
        try:
            res = subprocess.run(["hyprctl", "dispatch", expression],
                                 capture_output=True, text=True, timeout=4)
            if res.returncode == 0:
                return True
        except Exception:
            pass
        try:
            res = subprocess.run(["hyprctl", "dispatch"] + list(legacy_args),
                                 capture_output=True, text=True, timeout=4)
            return res.returncode == 0
        except Exception:
            return False

    # ---- protocol --------------------------------------------------------

    def handle_line(self, line):
        line = line.strip()
        if not line:
            return
        try:
            msg = json.loads(line)
        except Exception as error:
            sys.stderr.write(f"command parse error: {error}\n")
            return
        cmd = msg.get("cmd")
        if cmd == "list_apps":
            self.request_apps(target_args=msg.get("target_args"),
                              device_id=msg.get("deviceId", "default"))
        elif cmd == "launch":
            self.launch_session(msg.get("id"), msg.get("type", "app"),
                                msg.get("target_args"), msg.get("extra_args"),
                                follow_orientation=msg.get("follow_orientation") is True)
        elif cmd == "stop":
            self.stop_session(msg.get("id"))
        elif cmd == "stop_all":
            self.stop_all()
        elif cmd == "focus":
            self.focus_session(msg.get("id"))
        elif cmd == "device_size":
            self.request_device_size(target_args=msg.get("target_args"))
        elif cmd == "list_encoders":
            self.request_encoders(target_args=msg.get("target_args"))
        else:
            sys.stderr.write(f"unknown command: {cmd}\n")

    def install_signal_handlers(self):
        """A signal is the other way this process ends, and it was unhandled.

        The docstring above promises that a shell restart never leaves
        headless scrcpy windows behind, and only the clean-EOF path kept it:
        `PhoneScrcpy.stopManager()` sets `running = false`, which Quickshell
        sends as SIGTERM, and Python's default handler exits the process
        without running `stop_all()` - so every mirror and every app window
        the supervisor owned was orphaned. Measured: the child was still
        alive a second after the supervisor was gone.

        The signal is re-raised through the default handler afterwards, so
        the exit status still says what killed it. Called from `main`,
        because `signal.signal` only works on the main thread.
        """
        def handler(signum, _frame):
            self.stop_all()
            signal.signal(signum, signal.SIG_DFL)
            os.kill(os.getpid(), signum)

        for name in ("SIGTERM", "SIGINT", "SIGHUP"):
            number = getattr(signal, name, None)
            if number is None:
                continue
            try:
                signal.signal(number, handler)
            except (ValueError, OSError):
                pass

    def run(self):
        for line in sys.stdin:
            self.handle_line(line)
        self.stop_all()


def main():
    parser = argparse.ArgumentParser(description="scrcpy session supervisor for Immaterial Impulse")
    parser.add_argument("--list-apps", action="store_true", help="list apps once and exit")
    parser.add_argument("--device-id", default="default", help="cache key for --list-apps")
    args = parser.parse_args()

    manager = ScrcpySessionManager()
    if args.list_apps:
        manager.list_apps(device_id=args.device_id)
        return 0
    manager.install_signal_handlers()
    manager.run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
