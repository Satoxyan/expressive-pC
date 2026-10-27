#!/usr/bin/env python3
"""Send this machine's pointer to a paired phone, over D-Bus.

KDE Connect's `remotecontrol` interface takes one packet body per call, and the
pointer that has to be forwarded moves a hundred and twenty-five times a second.
A `busctl` process per event would spend more time forking `busctl` than the
phone would spend drawing the pointer, so this holds ONE D-Bus connection open
for the whole session and reads one command on stdin before the devices:

    {"device": "<device id>"}          # which phone to talk to

The body a mouse packet needs is exactly what the phone reads, and the names are
the ones `MouseReceiverPlugin` looks for: `dx` and `dy` for motion, `scroll` set
beside them for the wheel, `singlehold` and `singlerelease` for what the left
button does, `rightclick` and `middleclick` for what the other two are worth on
a phone, and `backclick` for what the Escape key is worth now that it is worth
nothing to this machine. Any other name is accepted by the daemon and ignored by
the phone, which is the worst possible failure: every call answers, and no
cursor ever moves.

The desktop cursor is stopped at the devices, not on the screen. `EVIOCGRAB`,
taken on a read-write open of every node the hand steers with - every mouse, and
every touchpad as well - keeps the compositor from seeing a single pixel:
whatever the pointer is sitting on - a bar, a sidebar or a window - it stays
exactly where it was the moment the grab landed, and no panel of this shell has
to close or be reordered for that to hold. So the grab is the first thing done
here, before the phone's bus is even named: `gi` and the D-Bus connection it
brings cost about a tenth of a second, and a tenth of a second between a click
and a frozen cursor is a tenth of a second the hand spends moving a mouse that is
already supposed to be dead. Holding a device needs the `input` group, and a node
that cannot be held is closed rather than merely watched - a mouse whose travel
goes to the phone *and* to the desktop is worse than one that goes nowhere.

A touchpad is the awkward one, because it has no relative axes to read: the
compositor takes its fingers from a multitouch interface that reports absolute
positions, and leaves the older mouse-shaped face of the same device unopened.
Both are held, so there is no way left for the pad to reach the desktop, and the
multitouch one is read for the phone: the travel of one finger becomes motion, the
travel of two becomes the wheel, a tap becomes the click nobody is left to
invent, and pressing the pad itself is a finger held down. A pad cannot offer the
two-button way out, because a second finger is only a right button as far as the
compositor is concerned, so the keyboard keeps that job on a laptop.

Escape is the key the phone wants now that this machine cannot have it, and the
keyboard is held for the same reason the pointer is: the shell keeps its sidebars
open with a compositor focus grab, and Hyprland clears that grab on Escape at the
seat itself, below every surface, so no part of the shell could be told to ignore
the press. A held keyboard means the desktop hears nothing - no Escape, no
typing - for the length of a session, which is what the pointer cage has always
implied. Alt+X therefore cannot reach the shortcut this shell installed, and is
answered here instead: the two Alt keys, then X or Enter, gives everything back.

A press is a held finger. The phone's pointer is drawn by an accessibility
service that can only be told to put a finger down, move it, or lift it, so a
press sends `singlehold` and its release sends `singlerelease` exactly as KDE's
own mousepad does - which is what makes a held drag, a long press and a tap all
fall out of the same two packets, with no threshold deciding between them: a
stroke that is lifted straight away is a tap, one that travels is a drag, and
one that is merely kept down is a long press. The frames between the two are the
finger's path.

Both buttons down at once ends the session. That is the hand's own way out, for
the moments Alt+X belongs to something else, and it is answered here rather than
in the shell because the shell is not being told about these clicks any more. The
shell's own way out arrives as a signal to this process, which is caught for the
same reason the buttons are: an ended session that never reported its release
leaves a finger pressed on the phone until the next one moves it.

Everything is asynchronous for the same reason. A reply waited for is a device
not read, and the phone is on Wi-Fi behind a daemon: a wheel spin answered one
blocking call per notch stops the whole session for seconds. So calls are
pipelined, motion goes out on the beat it arrives on, and the wheel is allowed
one scroll per breath - which is also what the phone wants, since each of its
scroll actions walks the accessibility tree of whatever is on screen.

The process ends when stdin closes, because that is the shell letting go of the
pointer, and it takes the grab with it: a grab belongs to a file descriptor, so
any exit at all - this one, a crash, a kill - hands the mouse back.
"""

import ctypes
import fcntl
import json
import os
import signal
import struct
import sys
import time

# Filled by `load_gi`, late, because the grab must not wait for it.
Gio = None
GLib = None
GLibUnix = None

DAEMON = "org.kde.kdeconnect.daemon"
IFACE = "org.kde.kdeconnect.device.remotecontrol"
TIMEOUT_MS = 2000
# A mouse reports every eight milliseconds, and the phone moves its cursor the
# instant a packet lands rather than easing it there, so a frame is sent with
# the travel that made it and never held for a beat it does not need.
FRAME_MS = 8
# The phone scrolls when its own sum of `dy` passes 500 and then forgets the
# sum, so a packet bigger than that is still ONE scroll: the surplus of a fast
# flick is spent on the packets after it, four notches to a scroll like the
# wheel's own 120-unit detents.
SCROLL_MS = 150
SCROLL_NOTCHES = 4
SCROLL_TRIGGER = 500
# Pixels of measured motion a frame has to carry before it is worth a packet. A
# mouse at rest still reports a pixel every now and then, and one packet each
# way is a phone cursor that jitters where nobody touched it; two is more than
# either of those single ticks and less than any motion meant as such.
MOTION_FLOOR = 2
# Calls in flight before motion stops going out. Deltas are relative, so the
# ones not sent are still here for the frame that follows them. A ceiling is the
# only thing keeping a slow phone from being handed a backlog it will work off
# seconds after the hand stopped moving.
IN_FLIGHT_CEILING = 16
EV_SYN = 0x00
EV_KEY = 0x01
EV_REL = 0x02
EV_ABS = 0x03
EV_MSC = 0x04
REL_X, REL_Y, REL_HWHEEL, REL_WHEEL = 0x00, 0x01, 0x06, 0x08
ABS_MT_SLOT, ABS_MT_TRACKING_ID = 0x2F, 0x39
ABS_MT_POSITION_X, ABS_MT_POSITION_Y = 0x35, 0x36
BTN_LEFT, BTN_RIGHT, BTN_MIDDLE = 0x110, 0x111, 0x112
BTN_NAMES = {BTN_LEFT: "left", BTN_RIGHT: "right", BTN_MIDDLE: "middle"}
# A finger's travel is counted in the pad's own axis units, which say nothing
# about how far the finger went; the axis knows its resolution in units per
# millimetre, and thirty-one pixels to the millimetre is what the eight-hundred
# dot-per-inch mouse next to it hands over for the same travel. So the pad moves
# the phone's cursor at the rate the mouse already does, and one stroke from edge
# to edge of the pad is one stroke down a long phone screen.
POINTER_PX_PER_MM = 31
PAD_MM = 100          # assumed width for an axis that reports no resolution
PAD_NOTCHES = 8       # a two-finger stroke across the whole pad is this notches
# A finger down and up again without travelling is a tap, and nothing on the wire
# ever says so: the click a tap performs is something the compositor used to
# invent from the contact's timing. Under a grab there is no compositor, so the
# tap has to be invented here, or the pad would steer a cursor it could never
# press.
TAP_MS = 200
TAP_TRAVEL_MM = 3
KEY_ESC = 1
KEY_ENTER = 28
KEY_LEFTALT = 56
KEY_RIGHTALT = 100
KEY_X = 45
ALT_KEYS = {KEY_LEFTALT, KEY_RIGHTALT}
# EVIOCGRAB = _IOW('E', 0x90, int)
EVIOCGRAB = (1 << 30) | (4 << 16) | (ord("E") << 8) | 0x90
# EVIOCGABS(code) = _IOR('E', 0x40 + code, struct input_absinfo), six int32s:
# value, minimum, maximum, fuzz, flat, resolution.
EVIOCGABS = (2 << 30) | (24 << 16) | (ord("E") << 8) | 0x40
# Slots: 0-1 are the axes of motion, 2-3 the axes of the wheel.
REL_SLOTS = {REL_X: 0, REL_Y: 1, REL_HWHEEL: 2, REL_WHEEL: 3}
MT_POSITIONS = {ABS_MT_POSITION_X: "x", ABS_MT_POSITION_Y: "y"}
EVENT_SIZE = struct.calcsize("@llHHi")
CLICK_KEYS = {"right": "rightclick", "middle": "middleclick"}

libc = ctypes.CDLL("libc.so.6", use_errno=True)


def load_gi():
    """Import `gi` into this module's own globals.

    The grab happens before this is ever called, which is the whole reason it is
    a function rather than the three lines at the top of the file they would
    otherwise be.
    """
    global Gio, GLib, GLibUnix
    import gi

    gi.require_version("Gio", "2.0")
    gi.require_version("GLib", "2.0")
    gi.require_version("GLibUnix", "2.0")
    from gi.repository import Gio as GioModule, GLib as GLibModule
    from gi.repository import GLibUnix as GLibUnixModule
    Gio = GioModule
    GLib = GLibModule
    GLibUnix = GLibUnixModule


def open_node(path, flags):
    try:
        return os.open(path, flags | os.O_NONBLOCK)
    except OSError:
        return None


def _capabilities(event_name, kind):
    """One capability bitmap out of sysfs: words of sixty-four bits, the most
    significant word first, leading zeros trimmed by the kernel.

    Read here rather than asked of an open node, because opening every
    `/dev/input/event*` to look inside it and closing it again costs eight to
    twenty milliseconds each - half a second before the cursor is stopped, which
    is the one thing this process must not be slow about. A node that has
    disappeared between the listing and the open is skipped by the open.
    """
    try:
        with open(f"/sys/class/input/{event_name}/device/capabilities/{kind}") as handle:
            return handle.read().split()
    except OSError:
        return []


def _reports(bits, code):
    if not bits:
        return False
    index = len(bits) - 1 - (code // 64)
    if index < 0:
        return False
    return bool(int(bits[index], 16) >> (code % 64) & 1)


def event_names():
    try:
        return sorted(name for name in os.listdir("/sys/class/input")
                      if name.startswith("event"))
    except OSError:
        return []


def _interface(name):
    """The sysfs folder holding every input interface of one physical device.

    A touchpad that answers both as a pad and as a mouse lives twice in here, and
    the two are the same fingers reported twice.
    """
    return os.path.dirname(os.path.realpath(f"/sys/class/input/{name}/device"))


def _is_touchpad(name):
    """A node whose fingers are reported as contact positions rather than travel.

    The multitouch protocol and nothing less: a pad that only has the old single
    contact axes is a device this bridge would have to guess the fingers of, and
    guessing is how a palm becomes a click.
    """
    abs_bits = _capabilities(name, "abs")
    return all(_reports(abs_bits, code) for code in
               (ABS_MT_SLOT, ABS_MT_TRACKING_ID, ABS_MT_POSITION_X,
                ABS_MT_POSITION_Y))


def _is_mouse(name):
    rel = _capabilities(name, "rel")
    return _reports(rel, REL_X) and _reports(rel, REL_Y)


def desktop_paths():
    """Every node the hand steers with, and which of them is worth reading.

    A touchpad is held through both of its faces, because the compositor reads
    one and might be reading the other, but only the multitouch face is listened
    to: the mouse-shaped one reports the same travel a second time over again,
    and a finger whose stroke reaches the phone twice arrives at twice the place
    it was pointed at.
    """
    names = event_names()
    pads = {name for name in names if _is_touchpad(name)}
    faces = {_interface(name) for name in pads}
    found = []
    for name in names:
        if name in pads:
            found.append((f"/dev/input/{name}", "touchpad"))
        elif _is_mouse(name):
            found.append((f"/dev/input/{name}",
                          "silent" if _interface(name) in faces else "mouse"))
    return found


def keyboard_paths(skip):
    """Every physical node that can answer Escape, other than the held pointers.

    These get held too, which is the only thing that keeps a pressed Escape from
    reaching this machine at all: Hyprland answers Escape to a focus grab by
    clearing the grab, below every surface, so no part of the shell ever sees the
    key in time to stay open. Two kinds of node are left alone. A node that is
    both a pointer and a keyboard is one the hand is steering with, and holding
    it would take its keys away. A virtual node belongs to something that types
    on this machine deliberately - KDE Connect's own remote keyboard among them,
    which arrives through a device it creates for the purpose - and the key the
    hand presses is a physical one.
    """
    paths = []
    for name in event_names():
        path = f"/dev/input/{name}"
        if path in skip:
            continue
        if os.path.realpath(f"/sys/class/input/{name}/device").startswith(
                "/sys/devices/virtual/"):
            continue
        if _reports(_capabilities(name, "key"), KEY_ESC):
            paths.append(path)
    return paths


def hold_desktop(wanted):
    """Open every listed node and take it off the desktop.

    Read-write or nothing: a held pointer node whose travel the compositor still
    sees is a mouse that moves the phone and the desktop cursor at once, so one
    that will not be held is closed again instead of being watched.
    """
    held, refused = [], []
    for path, role in wanted:
        fd = open_node(path, os.O_RDWR)
        if fd is None:
            continue
        if libc.ioctl(fd, EVIOCGRAB, 1) == 0:
            held.append((path, fd, role))
        else:
            refused.append(path)
            os.close(fd)
    if refused:
        print(f"remote input bridge: left alone, could not be held: "
              f"{', '.join(refused)}", file=sys.stderr, flush=True)
    return held


def unhold(nodes):
    """Put the held devices back on the desktop without waiting for the closes:
    an evdev release is slow, and the hand wants its machine back now."""
    for path, fd, _ in nodes:
        libc.ioctl(fd, EVIOCGRAB, 0)


def release_nodes(nodes):
    unhold(nodes)
    for path, fd, _ in nodes:
        os.close(fd)


def axis_info(fd, code):
    """Phone pixels per device unit, and how many units span the whole axis.

    Asked of the held node rather than assumed, because a pad's axis units mean
    whatever its driver says they mean: the same gesture on two pads of two
    laptops is a different number of units, and a gain written down by hand would
    be right on one machine and twice too fast on the next.
    """
    info = bytearray(24)
    try:
        fcntl.ioctl(fd, EVIOCGABS + code, info)
    except OSError:
        return 1.0, 1.0
    unused, minimum, maximum, _, _, per_mm = struct.unpack("@6i", info)
    span = max(maximum - minimum, 1)
    return POINTER_PX_PER_MM / (per_mm if per_mm > 0 else span / PAD_MM), span


class Session:
    """One phone, one connection, one pointer held between them."""

    def __init__(self, nodes, keys):
        self.bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        self.device = None
        self.in_flight = 0
        self.pending = [0.0, 0.0, 0.0, 0.0]
        self.nodes = nodes
        self.keys = keys
        self.pressed = set()
        self.pressed_keys = set()
        self.pads = {}
        self.held = None
        self.buffer = b""
        self.sources = []
        self.deadline = 0.0
        self.scroll_deadline = 0.0
        self.error = None
        self.loop = None

    # -- the phone -------------------------------------------------------

    def set_device(self, device_id):
        # Device ids are hex from the daemon's own list, and they are spliced
        # into an object path, so anything but hex is refused rather than
        # escaped.
        clean = str(device_id or "")
        if not clean or any(c not in "0123456789abcdef" for c in clean):
            raise ValueError("refused a device id that is not hex")
        self.device = clean

    def path(self):
        if not self.device:
            raise ValueError("no device named yet")
        return f"/modules/kdeconnect/devices/{self.device}/remotecontrol"

    def send(self, body):
        # A D-Bus call's parameters are a TUPLE of the in-arguments, so the
        # packet body is one cell of `(a{sv})` rather than a bare `a{sv}` -
        # GLib refuses the latter before the message ever reaches the daemon.
        packet = GLib.Variant("(a{sv})", ({
            key: self.variant(value) for key, value in body.items()},))
        self.in_flight += 1
        self.bus.call(DAEMON, self.path(), IFACE, "sendCommand", packet, None,
                      Gio.DBusCallFlags.NONE, TIMEOUT_MS, None, self._sent,
                      None)

    def _sent(self, connection, result, *unused):
        self.in_flight -= 1
        try:
            connection.call_finish(result)
        except Exception as error:
            self.fail(error)

    def fail(self, error):
        # Dying loudly is the only honest answer: the shell watches this process,
        # and its exit code is what tells a session that was given back from one
        # that broke. A bridge that kept swallowing frames while the daemon
        # refused them would leave the user moving a mouse that goes nowhere.
        print(f"remote input bridge: {error}", file=sys.stderr, flush=True)
        self.error = error or RuntimeError("unknown failure")
        if self.loop is None:
            self.quit()
        else:
            GLib.idle_add(self.quit)
        return 1

    def quit(self):
        # The grabs go first: the phone does not care whether this machine's
        # devices are held, and the release packet that follows is a call out on
        # a Wi-Fi link that might not answer for a while.
        unhold(self.nodes + self.keys)
        if self.held:
            # A finger left down on the phone outlives this process: the shell's
            # surface is already gone, so nothing would ever report the release,
            # and the next session would start inside a drag.
            self.held = None
            try:
                self.send_sync({"singlerelease": True})
            except Exception:
                pass
        self.pressed.clear()
        self.pressed_keys.clear()
        if self.loop is not None:
            self.loop.quit()
        return False

    def exit_desktop(self):
        """End the session from inside it, for a key the compositor cannot hear.

        The keyboard is held, so Alt+X never reaches the shortcut the shell
        installed: this process is the only thing standing between the user and a
        machine that answers nothing. `quit` has already handed the devices back,
        so leaving straight here costs the desktop nothing.
        """
        self.quit()
        os._exit(0)

    def send_sync(self, body):
        packet = GLib.Variant("(a{sv})", ({
            key: self.variant(value) for key, value in body.items()},))
        self.bus.call_sync(DAEMON, self.path(), IFACE, "sendCommand", packet,
                           None, Gio.DBusCallFlags.NONE, TIMEOUT_MS, None)

    @staticmethod
    def variant(value):
        if isinstance(value, bool):
            return GLib.Variant("b", value)
        if isinstance(value, (int, float)):
            return GLib.Variant("d", float(value))
        return GLib.Variant("s", str(value))

    # -- the hand --------------------------------------------------------

    def take(self, slots, index):
        # The whole pixels queued on an axis, with any fraction left for the next
        # frame: a motion of 20.5 px is not 20 px, twice over.
        value = slots[index]
        whole = int(value + (0.5 if value > 0 else -0.5))
        slots[index] = value - whole
        return whole

    def button(self, name, pressed):
        if name in ("left", "right"):
            if pressed:
                self.pressed.add(name)
                if len(self.pressed) == 2:
                    # The hand is asking out with both buttons at once. Nothing
                    # else is sent for this press: the release that follows it
                    # belongs to the desktop, which is getting the mouse back.
                    self.quit()
                    return
            else:
                self.pressed.discard(name)
        self.click(name, pressed)

    def click(self, button, pressed):
        # The left button is a finger: down, and up. The other two are the
        # global actions the phone answers a rightclick and a middleclick with,
        # which have no hold half - they happen on release, like a click.
        button = str(button)
        if button in CLICK_KEYS:
            if not pressed:
                self.send({CLICK_KEYS[button]: True})
            return
        if pressed:
            if self.held == button:
                return
            self.release_press()
            self.held = button
            self.send({"singlehold": True})
        elif self.held == button:
            self.release_press()

    def release_press(self):
        if self.held:
            self.send({"singlerelease": True})
            self.held = None

    # -- the pad ---------------------------------------------------------

    def pad_state(self, node):
        """Where one touchpad keeps its fingers, measured in its own units."""
        path, fd, _ = node
        pad = self.pads.get(path)
        if pad is not None:
            return pad
        x_axis, y_axis = axis_info(fd, ABS_MT_POSITION_X), axis_info(
            fd, ABS_MT_POSITION_Y)
        self.pads[path] = pad = {
            "slot": 0, "contacts": {}, "point": None, "tap": None,
            "widest": 0, "clicked": False,
            "px": (x_axis[0], y_axis[0]),
            "units": (x_axis[1], y_axis[1]),
            "limit": (x_axis[1] + y_axis[1]) / 2 * TAP_TRAVEL_MM / PAD_MM}
        return pad

    def touchpad(self, node, etype, code, value):
        """One event off a multitouch pad, folded into what a mouse already fills.

        The kernel reports an axis of a contact at a time and closes the set with
        a syn, so nothing is counted, and no position is compared, until a frame
        is whole: half a gesture averaged is a cursor that jumps.
        """
        pad = self.pad_state(node)
        if etype == EV_ABS:
            if code == ABS_MT_SLOT:
                pad["slot"] = value
            elif code == ABS_MT_TRACKING_ID:
                if value < 0:
                    pad["contacts"].pop(pad["slot"], None)
                else:
                    pad["contacts"].setdefault(
                        pad["slot"], {"x": None, "y": None})
            elif code in MT_POSITIONS:
                pad["contacts"].setdefault(
                    pad["slot"], {"x": None, "y": None})[MT_POSITIONS[code]] = value
            return
        if etype == EV_SYN:
            self.pad_frame(pad)
            return
        if etype != EV_KEY:
            return
        name = BTN_NAMES.get(code)
        if name:
            if name == "left" and value:
                # The pad was pressed, which is a click of its own: the tap that
                # is invented when the finger lifts would be that click twice.
                pad["clicked"] = True
            self.button(name, value != 0)

    def pad_frame(self, pad):
        now = time.monotonic()
        points = [(contact["x"], contact["y"]) for contact in
                  pad["contacts"].values()
                  if contact["x"] is not None and contact["y"] is not None]
        pad["widest"] = max(pad["widest"], len(pad["contacts"]))
        if not pad["contacts"]:
            self.pad_lift(pad)
            pad["point"] = None
            return
        if not points:
            return
        x = sum(point[0] for point in points) / len(points)
        y = sum(point[1] for point in points) / len(points)
        previous, pad["point"] = pad["point"], (x, y)
        if previous is None:
            if pad["tap"] is None:
                pad["tap"] = [now, 0.0]
            return
        dx, dy = x - previous[0], y - previous[1]
        if pad["widest"] > 1:
            # Two fingers are the wheel, and a stroke up the pad is a notch away
            # from the hand: the same direction the same finger on a wheel would
            # have turned it, so a scroll that was right on this machine is right
            # on the phone. Once the second finger joined, the whole stroke stays
            # a scroll even after one of them leaves.
            self.pending[2] -= dx / pad["units"][0] * PAD_NOTCHES
            self.pending[3] -= dy / pad["units"][1] * PAD_NOTCHES
            return
        pad["tap"][1] += abs(dx) + abs(dy)
        self.pending[0] += dx * pad["px"][0]
        self.pending[1] += dy * pad["px"][1]

    def pad_lift(self, pad):
        if pad["tap"] and not pad["clicked"] and pad["widest"] == 1:
            still = pad["tap"][1] <= pad["limit"]
            quick = (time.monotonic() - pad["tap"][0]) * 1000 < TAP_MS
            if still and quick:
                self.button("left", True)
                self.button("left", False)
        pad["tap"] = None
        pad["widest"] = 0
        pad["clicked"] = False

    # -- the loop --------------------------------------------------------

    def flush_motion(self):
        if not self.device or self.in_flight >= IN_FLIGHT_CEILING:
            # The frames are kept, not dropped: a delta that is not sent is
            # still here when the phone comes back for the next one.
            return
        # A mouse that is not being moved still reports a pixel now and then, and
        # a packet for each of them is a phone cursor that never sits still. So a
        # count under the floor is not sent yet: it is kept, where it either
        # cancels itself out or grows into a motion worth a packet.
        if abs(self.pending[0]) < MOTION_FLOOR and abs(self.pending[1]) < MOTION_FLOOR:
            return
        dx, dy = self.take(self.pending, 0), self.take(self.pending, 1)
        if dx or dy:
            self.send({"dx": dx, "dy": dy})

    def take_scroll(self, index):
        """One scroll's worth of notches, or none if the wheel has not moved.

        The magnitude is always the same because the phone's own sum is reset
        by the scroll it performs: sending twelve notches as one packet buys one
        scroll and throws eleven notches away. Four notches, one scroll, and the
        rest of the flick waits its turn on the following ticks.
        """
        remaining = int(self.pending[index])
        if not remaining:
            return 0
        steps = int(min(abs(remaining), SCROLL_NOTCHES)) * (1 if remaining > 0 else -1)
        self.pending[index] -= steps
        return steps

    def flush_scroll(self):
        if not self.device or self.in_flight >= IN_FLIGHT_CEILING:
            return
        hx, wy = self.take_scroll(2), self.take_scroll(3)
        if not (hx or wy):
            return
        # The phone scrolls forward on a positive dy and back on a negative
        # one, while a wheel notch away from the user is positive - so the
        # desktop's sense of the wheel is the one handed over negated.
        self.send({"dx": -hx * SCROLL_TRIGGER,
                   "dy": -wy * SCROLL_TRIGGER,
                   "scroll": True})

    def beat(self):
        """Send what is owed, at most once per frame.

        This is called both from the clock and from the moment a device is read,
        so travel leaves on the frame it arrived on instead of waiting up to a
        whole beat for the timer that would have noticed it.
        """
        now = time.monotonic()
        if now >= self.deadline:
            self.deadline = now + FRAME_MS / 1000
            self.flush_motion()
        if now >= self.scroll_deadline:
            self.scroll_deadline = now + SCROLL_MS / 1000
            self.flush_scroll()
        return True

    def drain(self, node):
        path, fd, role = node
        events = b""
        while True:
            try:
                chunk = os.read(fd, EVENT_SIZE * 128)
            except BlockingIOError:
                break
            except OSError:
                # An unplugged mouse must not end a session: the others are still
                # held, and the hand will find the phone through whichever one it
                # picks up next.
                for group in (self.nodes, self.keys):
                    if node in group:
                        group.remove(node)
                self.pads.pop(path, None)
                os.close(fd)
                break
            if not chunk:
                break
            events += chunk
        for offset in range(0, len(events) - EVENT_SIZE + 1, EVENT_SIZE):
            _, _, etype, code, value = struct.unpack_from(
                "@llHHi", events, offset)
            if role == "touchpad":
                self.touchpad(node, etype, code, value)
                continue
            if role == "silent" or etype == EV_MSC:
                continue
            if etype == EV_KEY:
                self.key(code, value, role == "mouse")
                continue
            if role != "mouse" or etype != EV_REL:
                continue
            slot = REL_SLOTS.get(code)
            if slot is not None:
                self.pending[slot] += value
        if events:
            self.beat()

    def key(self, code, value, pointer):
        if value == 0:
            self.pressed_keys.discard(code)
        elif value == 1:
            self.pressed_keys.add(code)
        else:
            return  # autorepeat repeats a press that was already answered
        name = BTN_NAMES.get(code)
        if name and pointer:
            # Under a grab the nodes are the only place a click exists: the
            # compositor never sees the button, so no shell surface can report
            # it, and the phone's finger comes straight off the key.
            self.button(name, value != 0)
            return
        if value != 1:
            return
        if code == KEY_ESC:
            # Only the press counts: a held Escape autorepeats, and the phone
            # would walk back a screen every other frame.
            if self.device:
                self.send({"backclick": True})
        elif code in (KEY_X, KEY_ENTER) and ALT_KEYS & self.pressed_keys:
            # Alt+X, and Alt+Enter for the ten percent of boards where X is
            # somewhere else. The release of the chord is left to the desktop,
            # which is why the grab goes before this is even noticed.
            self.exit_desktop()

    def read_commands(self):
        chunk = b""
        while True:
            try:
                more = os.read(0, 4096)
            except BlockingIOError:
                break
            if not more:
                self.quit()
                return
            chunk += more
        if not chunk:
            return
        self.buffer += chunk
        lines = self.buffer.split(b"\n")
        self.buffer = lines.pop()
        for line in lines:
            if not line.strip():
                continue
            command = json.loads(line)
            if "device" in command:
                self.set_device(command["device"])
            else:
                raise ValueError(f"unknown command: {list(command)}")

    def watch(self, fd, handler):
        fcntl.fcntl(fd, fcntl.F_SETFL, os.O_NONBLOCK | fcntl.fcntl(fd, fcntl.F_GETFL))

        def on_ready(source_fd, condition, data):
            try:
                handler()
            except Exception as error:
                self.fail(error)
            return True

        self.sources.append(GLibUnix.fd_add_full(
            0, fd, GLib.IOCondition.IN, on_ready, None))

    def start(self):
        self.watch(0, self.read_commands)
        for node in self.nodes + self.keys:
            self.watch(node[1], lambda node=node: self.drain(node))
        # The shell ends a session by asking this process to stop. Handled here
        # rather than left to the default action, because the default action is a
        # finger left pressed on the phone until the next session touches it.
        GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, self.quit)

        def on_beat():
            try:
                self.beat()
            except Exception as error:
                self.fail(error)
            return True

        GLib.timeout_add(FRAME_MS, lambda: on_beat())
        self.deadline = time.monotonic()
        self.scroll_deadline = time.monotonic()
        self.loop = GLib.MainLoop()
        self.loop.run()
        return 1 if self.error else 0


def main():
    # The freeze goes first: everything after it is the phone's business, and a
    # session that cannot stop this machine's cursor has no business starting -
    # a pointer that moves on both screens at once is worse than no session.
    nodes = hold_desktop(desktop_paths())
    if not [node for node in nodes if node[2] != "silent"]:
        print("remote input bridge: no pointer device could be held; is this "
              "account in the `input` group?", file=sys.stderr, flush=True)
        return 1
    paths = {path for path, _, _ in nodes}
    keys = hold_desktop([(path, "key") for path in keyboard_paths(paths)])
    session = None
    try:
        load_gi()
        session = Session(nodes, keys)
        return session.start()
    except Exception as error:
        if session is None:
            release_nodes(nodes + keys)
            print(f"remote input bridge: {error}", file=sys.stderr, flush=True)
            return 1
        return session.fail(error)


if __name__ == "__main__":
    sys.exit(main())
