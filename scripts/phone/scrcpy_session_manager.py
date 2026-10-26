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
  {"cmd": "app_icon", "package": <id>, "target_args": [...],
   "deviceId": <cache key>, "priority": <bool>}
  {"cmd": "device_size", "target_args": [...]}
  {"cmd": "list_encoders", "target_args": [...]}

Events (one JSON object per line on stdout):
  started    {id, pid, title[, alreadyRunning]}
  exited     {id, code, error}          error = scrcpy's last output line
  error      {id, message}
  apps_list  {deviceId, apps[, cached]} apps = [{package, name, system}]
  apps_error {message}
  app_icon   {package, path}            path = "" when the phone has no icon
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
import io
import json
import os
import queue
import re
import shlex
import signal
import struct
import subprocess
import sys
import threading
import time
from base64 import b64encode
from pathlib import Path
from xml.sax.saxutils import escape

# scrcpy's last output line is what an `exited` event carries, so the drain
# below only has to keep the tail. Bounded because the drain runs for the
# life of the child and a chatty one is exactly the case it exists for.
STDERR_TAIL_LINES = 40
# How long to wait past the child's exit for the drain thread to see EOF.
STDERR_DRAIN_TIMEOUT = 2.0

CACHE_DIR = (Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache")
             / "illological-impulse" / "phone" / "apps")
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


# An APK's launcher icon is a picture under `res/<folder>/<name>`. Two things
# can name it. The cheap one is the name itself: launchers build `ic_launcher`,
# and a drawable that only has `icon` in its name is an in-app picture (Apple
# Music's icon, inside Shazam's APK) so it is accepted only inside a `mipmap`
# folder, which exists for launcher icons and hardly anything else. The named
# guess fails on the release builds that let R8 shrink `res/` to two-letter
# files, and those are about half of a real app list - so the second way reads
# the resource id the package manager prints for the launcher activity and
# resolves it through `resources.arsc`, which is what names the file for the
# framework itself. A package neither route can picture keeps the shell's glyph.
ICON_IMAGE_MIME = {".png": "image/png", ".webp": "image/webp",
                   ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
                   ".svg": "image/svg+xml"}
ICON_IMAGE_SUFFIXES = tuple(ICON_IMAGE_MIME)
ICON_DENSITY_RANK = {"xxxhdpi": 60, "xxhdpi": 50, "xhdpi": 40, "nodpi": 35,
                     "hdpi": 30, "mdpi": 20, "ldpi": 10}
# Mipmap drawables that are not the launcher icon: a TV app's banner and an
# ad's feature graphic live in the same folder as the icon does.
ICON_ASSET_WORDS = ("banner", "splash", "promo", "feature_graphic", "header",
                    "card", "hero", "placeholder")
# Bumped whenever the rules for finding a picture change, so an old verdict is
# re-tried once instead of sticking to the app's icon forever.
ICON_RECORD_VERSION = 15
# A name that still carries the launcher's own word - `ic_launcher`,
# `launcher` - is trusted without downloading the resource table, because that
# download is the expensive part of answering and one worker answers the whole
# visible list.
ICON_NAME_TIER_TRUSTED = 30
# The adb calls around an icon, and the size of the resource table the queue is
# willing to wait for. It is a large number on purpose: a Google-sized base is
# 20MB and its icon is named nowhere else, and the read is the *last* thing an
# icon lookup tries - only once the smaller tables of the install have said
# nothing - with `ICON_TABLE_TIMEOUT` bounding the wait it can cost the rows
# behind it. The answer is cached either way, so one phone pays it once.
# How long the worker blocks waiting for the bulk queue before it looks at the
# urgent one again - the price paid for letting a row jump the queue at any time.
ICON_POLL_SECONDS = 0.2
ICON_TIMEOUT = 10
ICON_READ_TIMEOUT = 15
ICON_TABLE_TIMEOUT = 10
ICON_TABLE_MAX_BYTES = 24 << 20
# The two apps whose launcher icon is named nowhere but a table over that budget
# are Google's own - 28MB and 90MB - and reading one is a wait no visible row is
# made to sit behind: such a package is asked a second time, once the queue has
# drained the ones that answer cheaply. See `ICON_DEFERRED`.
ICON_TABLE_HOPEFUL_BYTES = 96 << 20
ICON_TABLE_HOPEFUL_TIMEOUT = 40
ICON_DEFERRED = "deferred"
# The archives one install is made of that are worth listing. Beyond the base,
# only the configuration splits carry a launcher icon; a Play install's module
# splits are code, and each one asked about is a row of the list left unfilled.
ICON_ARCHIVE_MAX = 5
# The density an icon is wanted at: the xxhdpi bucket a launcher on a modern
# phone asks for, and the row nearest it is the one read first.
ICON_WANTED_DENSITY = 480

# `cmd package query-activities -a android.intent.action.MAIN -c
# android.intent.category.LAUNCHER <pkg>` ends its block with
#   ... labelRes=0x7f14037e nonLocalizedLabel=null icon=0x7f100009 banner=0x0
# and `icon=0x0` means the activity inherits the application's own icon, which
# only the manifest - not this output - names.
LAUNCHER_ICON_ID = re.compile(r"\bicon=0x([0-9a-fA-F]{1,8})\b")

# resources.arsc chunk types and the fields of `ResTable_type` that a resource
# id indexes (androidfw/ResourceTypes.h): header 8, id u8, flags u8, reserved
# u16, entryCount u32, entriesStart u32, then the variable-size config, then the
# offsets - all of them measured from the chunk start, and scaled or paired
# depending on the two flag bits.
RES_CHUNK_STRING_POOL = 0x0001
RES_CHUNK_PACKAGE = 0x0200
RES_CHUNK_TYPE = 0x0201
RES_TABLE_TYPE = 0x0002
TYPE_FLAG_SPARSE = 0x01
TYPE_FLAG_OFFSET16 = 0x02
ENTRY_FLAG_COMPLEX = 0x0001
VALUE_TYPE_STRING = 0x03
VALUE_TYPE_FLOAT = 0x04
VALUE_TYPE_DIMENSION = 0x05
VALUE_TYPE_REFERENCE = 0x01
NO_ENTRY_16 = 0xFFFF
NO_ENTRY_32 = 0xFFFFFFFF
# How far an entry that only names another entry is followed. A launcher icon
# alias is one hop in practice; the limit is there so a table that points its
# entries in a ring is given up on rather than walked forever.
ARSC_ALIAS_DEPTH = 4

# A binary AndroidManifest.xml: the file chunk, the resource map that turns an
# attribute's string index into the framework id it names, and the element
# chunks whose attributes follow their extension header. `android:icon` is
# 0x01010002, and for an app it is a reference into the same resource table
# that names the activity's - so it is read the same way afterwards.
RES_XML_TYPE = 0x0003
RES_XML_START_ELEMENT = 0x0102
RES_XML_END_ELEMENT = 0x0103
RES_XML_RESOURCE_MAP = 0x0180
AXML_ANDROID_ICON = 0x01010002
# Typed values a drawable's XML carries: the numbers and colors a vector is
# built from, and the reference that points at one in the resource table.
VALUE_TYPE_INT_DECIMAL = 0x10
# 28 through 31, in the order `Res_value` numbers them: ARGB8, RGB8, ARGB4444,
# RGB4444. The four are read differently, so the order is the whole meaning.
VALUE_INT_COLOR_ARGB8 = 0x1C
VALUE_INT_COLOR_RGB8 = 0x1D
VALUE_INT_COLOR_ARGB4 = 0x1E
VALUE_INT_COLOR_RGB4 = 0x1F
VALUE_COLOR_TYPES = (VALUE_INT_COLOR_ARGB8, VALUE_INT_COLOR_RGB8,
                     VALUE_INT_COLOR_ARGB4, VALUE_INT_COLOR_RGB4)
# Every type a `Res_value` is allowed to name. An entry read at the wrong offset
# lands on a byte that is not one of these, which is how the two entry forms are
# told apart (see `entry_value`).
VALUE_TYPES = frozenset({0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x08}
                        | set(range(0x10, 0x15)) | set(range(0x1C, 0x20))
                        | set(range(0x20, 0x28)))
# An adaptive icon's canvas and the visible part of it, in dp: layers are drawn
# on the 108dp canvas and the launcher crops them to its mask.
ADAPTIVE_CANVAS = 108.0
# The elements an adaptive icon is made of, in draw order, and how deep a
# layer's own drawables are followed before the drawing gives up.
ADAPTIVE_LAYER_ROLES = ("background", "foreground", "monochrome")
# The framework's colour block - `android.R.color.*` - and what a reference into
# it is drawn as. See `resolve_color`.
FRAMEWORK_COLOUR_BLOCK = 0x01060000
FRAMEWORK_PAINT = "#888888ff"
LAYER_DEPTH_MAX = 4
# How an icon picture is stored: a row paints it into a slot of about 39 CSS
# pixels, so 96 is already twice what the largest monitor scale samples, and the
# 192-432 px originals would be several times the disk for pixels that are thrown
# away. `ICON_PICTURE_MAX_BYTES` is the promise instead of the aim: a picture that
# cannot be brought under it is not cached at all, and the row keeps the shell's
# glyph.
ICON_PICTURE_MAX_SIDE = 96
ICON_PICTURE_WEBP_QUALITY = 80
ICON_PICTURE_MAX_BYTES = 2 << 20
# The size the generated SVG reports for itself, so a viewer that ignores
# `sourceSize` still gets a picture worth downscaling rather than an upscale.
SVG_RENDER_SCALE = 4
# Densities that carry no picture of their own: `anydpi` names the adaptive
# XML, `none` the default - both are the last choice after a real density.
DENSITY_ANY = (65534, 65535, 0xFFFE, 0xFFFF)


def parse_zip_listing(lines):
    """[(size, name)] from `unzip -l`, whose rows are `size date time name`."""
    entries = []
    for line in lines:
        parts = line.split()
        if len(parts) < 4 or not parts[0].isdigit():
            continue
        entries.append((int(parts[0]), " ".join(parts[3:])))
    return entries


def icon_entry_rank(name):
    """(tier, score) of an APK entry as a launcher icon; tier 0 when it is not.

    The tier says how much the name itself can be trusted - `ic_launcher` and
    friends are the launcher's, while any picture that only happens to sit in a
    `mipmap` folder is a last resort. The score orders candidates inside a tier:
    the folder's density first, then the kind of folder.
    """
    if not name.startswith("res/") or "$" in name:
        return 0, 0
    folder, _, file_name = name.rpartition("/")
    base, dot, suffix = file_name.rpartition(".")
    if not dot or ("." + suffix.lower()) not in ICON_IMAGE_SUFFIXES:
        return 0, 0
    tokens = folder.rpartition("/")[2].lower().split("-")
    density = max((ICON_DENSITY_RANK.get(token, 0) for token in tokens),
                  default=0)
    kind = 20 if tokens[0] == "mipmap" else 0
    base = base.lower()
    layer = "foreground" in base or "background" in base
    if base == "ic_launcher":
        tier = 100
    elif base in ("ic_launcher_round", "ic_launcher_legacy"):
        tier = 80
    elif "launcher" in base and not layer:
        tier = 60
    elif ("appicon" in base or "app_icon" in base) and kind:
        tier = 40
    elif "launcher" in base:
        tier = 30
    elif kind and not any(bad in base for bad in ICON_ASSET_WORDS):
        # A picture in a `mipmap` folder is a launcher icon whatever it is
        # called; the folder is the tell, not the name. Only the names that
        # mean something else in there - a TV banner is a mipmap too - are
        # turned down.
        tier = 10
    else:
        tier = 0
    return tier, (tier + density + kind if tier else 0)


def icon_entry_score(name):
    """How well an APK entry reads as the launcher icon; 0 when it is not one."""
    return icon_entry_rank(name)[1]


def pick_icon_entry(entries):
    """The best launcher-icon entry in an APK listing, or None."""
    best, best_key = None, (0, 0)
    for size, name in entries:
        score = icon_entry_score(name)
        # A zero-length member is not a picture whatever it is called: an app
        # whose own `ic_launcher.webp` was left empty has a folder full of them,
        # and reading one is how an icon row ends up with nothing to show.
        if score and size and (score, size) > best_key:
            best, best_key = name, (score, size)
    return best


def read_string_pool(data, off):
    """Strings of a RES_STRING_POOL chunk at `off`; [] when it can't be read.

    A truncated download is the failure mode that matters here, so the walk
    stops at the first string that runs past the end of the buffer rather than
    raising out of a worker thread.
    """
    try:
        ctype, header_size, _ = struct.unpack_from("<HHI", data, off)
        count, _styles, flags, strings_start, _styles_start = struct.unpack_from(
            "<IIIII", data, off + 8)
    except struct.error:
        return []
    if ctype != RES_CHUNK_STRING_POOL:
        return []
    utf8 = bool(flags & (1 << 8))
    out = []
    for i in range(count):
        try:
            item = struct.unpack_from("<I", data, off + header_size + i * 4)[0]
            p = off + strings_start + item
            if utf8:
                length = data[p]; p += 1
                if length & 0x80:
                    length = ((length & 0x7f) << 8) | data[p]; p += 1
                chars = data[p]; p += 1
                if chars & 0x80:
                    chars = ((chars & 0x7f) << 8) | data[p]; p += 1
                text = data[p:p + chars].decode("utf-8", "replace")
            else:
                length = struct.unpack_from("<H", data, p)[0]; p += 2
                if length & 0x8000:
                    length = ((length & 0x7fff) << 16) | struct.unpack_from(
                        "<H", data, p)[0]
                    p += 2
                text = data[p:p + length * 2].decode("utf-16-le", "replace")
        except (struct.error, IndexError):
            break
        out.append(text)
    return out


def arsc_entries(data, res_id):
    """[(density, dataType, value)] held by one resource id, per configuration.

    `resources.arsc` is the only structure that maps a resource id to what it
    names, and R8-shrunk builds answer through nothing else: the file on disk
    is `res/Gc.png`, not `res/mipmap-xxhdpi/ic_launcher.png`. Values come in the
    two encodings aapt2 emits - a simple `Res_value` following the entry, or a
    compact entry with the value inline - and a complex entry (a selector, a
    style, an inline XML) is skipped rather than guessed at. String values are
    resolved to their pool text here, so a caller only deals with types it
    wants. Returns None when the blob is not this package's table at all, which
    keeps an unreadable download from being read as "this app has no icon".
    """
    want_type = (res_id >> 16) & 0xFF
    want_entry = res_id & 0xFFFF
    if want_type == 0 or len(data) < 16:
        return None
    if struct.unpack_from("<H", data, 0)[0] != RES_TABLE_TYPE:
        return None
    # The table header's size IS the file's length, so a download that stopped
    # early fails this check rather than being read as a package with no icon.
    if struct.unpack_from("<I", data, 4)[0] != len(data):
        return None
    try:
        return _arsc_entries(data, res_id, want_type, want_entry)
    except (struct.error, IndexError, UnicodeDecodeError):
        return None  # a table that stops parsing halfway is a bad download


def _arsc_entries(data, res_id, want_type, want_entry):
    table_size = struct.unpack_from("<I", data, 4)[0]
    pos = 12
    strings = []
    rows = []
    matched_package = False
    while pos + 8 <= table_size:
        try:
            ctype, header_size, size = struct.unpack_from("<HHI", data, pos)
        except struct.error:
            break
        if size <= 0 or header_size <= 0:
            break
        if ctype == RES_CHUNK_STRING_POOL:
            strings = read_string_pool(data, pos)
        elif ctype == RES_CHUNK_PACKAGE:
            package_id = struct.unpack_from("<I", data, pos + 8)[0]
            if package_id == (res_id >> 24) & 0xFF:
                matched_package = True
                type_strings_off = struct.unpack_from("<I", data, pos + 268)[0]
                type_names = read_string_pool(data, pos + type_strings_off)
                if want_type > len(type_names):
                    break
                sub = pos + header_size
                package_end = pos + size
                while sub + 8 <= package_end:
                    sub_type, sub_header, sub_size = struct.unpack_from(
                        "<HHI", data, sub)
                    if sub_size <= 0 or sub_header <= 0:
                        break
                    if sub_type == RES_CHUNK_TYPE and data[sub + 8] == want_type:
                        found = type_chunk_entry(data, sub, sub_header, sub_size,
                                                 want_entry, strings)
                        if found:
                            density, data_type, value = found
                            if data_type == VALUE_TYPE_STRING and value < len(strings):
                                rows.append((density, data_type, strings[value]))
                            else:
                                rows.append((density, data_type, value))
                    sub += sub_size
        pos += size
    # A table with no package for this id is not a readable answer about the
    # app's icon; only a package that was found and held nothing is.
    return rows if matched_package else None


def arsc_size(entries):
    """The bytes of the archive's resource table, or None when it has none."""
    for size, name in entries:
        if name == "resources.arsc" and size > 0:
            return size
    return None


def plausible_path(value):
    """Whether a table's string value could name a member of the archive.

    `res/…` is the shape a built app's paths keep, and a build that obfuscates
    its resource names drops the folder with the name - `\u1a75\u06e7\u06e2` is the whole
    path of one app's icon. What is turned down is the text that is plainly not a
    path: a format string, a sentence, a name with a space in it. Whether the
    bytes are a picture is what the caller asks the archive, so guessing here is
    cheap and being strict is what loses the icon.
    """
    return bool(value) and len(value) <= 255 and not re.search(r'\s|[%?"]', value)


def arsc_icon_paths(data, res_id):
    """The [(density, archive path)] rows of an id, ready for `arsc_picture_rows`."""
    entries = arsc_entries(data, res_id)
    if entries is None:
        return None
    return [(density, value) for density, data_type, value in entries
            if data_type == VALUE_TYPE_STRING and isinstance(value, str)
            and plausible_path(value)]


class ArscTables:
    """The resource tables an install is spread over, answered as one.

    A store-built app's entries are split by configuration: one table names the
    adaptive icon's XML and another, thousands of entries smaller, names the
    picture that XML points at. Answering from any one of them therefore says
    nothing about the icon; the id is looked up in each, and the rows of all of
    them are the answer.
    """

    def __init__(self, blobs):
        self.blobs = [blob for blob in blobs if blob]

    def entries(self, res_id, depth=0):
        """`arsc_entries` over each table, first one to hold a value wins.

        An id whose rows are nothing but references is another entry's name -
        which is how a launcher icon alias is written - so those are followed to
        the entry that holds a picture or a colour. An id that names a value in
        one configuration and an alias in another keeps its values, and one whose
        aliases lead nowhere keeps what it pointed at: a reference is still a
        fact about the id, and `resolve_color` reads on from it.
        """
        own = None
        for blob in self.blobs:
            rows = arsc_entries(blob, res_id)
            if rows:
                own = own or rows
                if any(kind != VALUE_TYPE_REFERENCE
                       for _density, kind, _value in rows):
                    return rows
        if depth < ARSC_ALIAS_DEPTH:
            for alias in self.references(res_id):
                rows = self.entries(alias, depth + 1)
                if rows:
                    return rows
        return own

    def references(self, res_id):
        """The ids an entry points at without naming anything itself."""
        out = []
        for blob in self.blobs:
            for _density, kind, value in arsc_entries(blob, res_id) or []:
                if kind == VALUE_TYPE_REFERENCE and value and value not in out:
                    out.append(value)
        return out

    def paths(self, res_id):
        """Every `(density, path)` row any table holds for the id."""
        return [(density, value) for density, kind, value in self.entries(res_id) or []
                if kind == VALUE_TYPE_STRING and isinstance(value, str)
                and plausible_path(value)] or None

    def picture_rows(self, res_id):
        return arsc_picture_rows(self.paths(res_id) or [])


def type_chunk_entry(data, sub, header_size, size, want_entry, strings=()):
    """(density, dataType, value) one RES_TABLE_TYPE chunk holds for an entry.

    Returns None when the chunk does not carry that entry: an absent entry is
    normal - it just means that configuration has no value for it.
    """
    flags = data[sub + 9]
    entry_count, entries_start = struct.unpack_from("<II", data, sub + 12)
    config_size = struct.unpack_from("<I", data, sub + 20)[0]
    density = struct.unpack_from("<H", data, sub + 34)[0]
    if config_size <= 0:
        return None
    if entries_start <= 20 + config_size:
        return None  # a header that would overlap its own offsets is not readable
    offsets_at = sub + header_size
    slots = entries_start - header_size
    hit = None
    if flags & TYPE_FLAG_SPARSE:
        # Packed (index, offset / 4) pairs sorted by index, one per entry
        # present in this configuration. `entryCount` here counts the pairs,
        # not the ids they reach: a density split that holds fifteen of a
        # type's seven hundred and fifty-six entries says so with fifteen, and
        # an id above fifteen is still inside it. Only the flat form, where
        # every id has a slot, is bounded by the count.
        for k in range(slots // 4):
            raw = struct.unpack_from("<I", data, offsets_at + 4 * k)[0]
            index, offset = raw & 0xFFFF, raw >> 16
            if index == want_entry:
                hit = sub + entries_start + offset * 4
                break
            if index > want_entry:
                break
    else:
        if want_entry >= entry_count:
            return None
        if flags & TYPE_FLAG_OFFSET16:
            if slots % 2:
                return None
            raw = struct.unpack_from("<H", data, offsets_at + 2 * want_entry)[0]
            if raw != NO_ENTRY_16:
                hit = sub + entries_start + raw * 4
        else:
            if slots % 4:
                return None
            raw = struct.unpack_from("<I", data, offsets_at + 4 * want_entry)[0]
            if raw != NO_ENTRY_32:
                hit = sub + entries_start + raw
    if hit is None or hit + 4 > sub + size:
        return None
    read = entry_value(data, hit, strings)
    return None if read is None else (density, read[0], read[1])


def entry_value(data, hit, strings):
    """(dataType, data) of the value one entry carries, in whichever form it is.

    An entry is an `8`- or `16`-byte header followed by a `Res_value` of eight,
    and it is also - in the builds that shrink their tables - a two-byte key
    followed by a value that spells its own size in a byte. A chunk does not say
    which it uses, so both are read and the one the bytes will bear is kept: a
    type the format has no name for, or a string index past the pool, is not a
    reading worth returning as an answer about an app's icon.
    """
    readings = []
    entry_size = struct.unpack_from("<H", data, hit)[0]
    if 8 <= entry_size <= 24 and hit + entry_size + 8 <= len(data):
        flags = struct.unpack_from("<H", data, hit + 2)[0]
        at = hit + entry_size
        if not flags & ENTRY_FLAG_COMPLEX:
            readings.append((data[at + 3], struct.unpack_from("<I", data, at + 4)[0]))
    if hit + 8 <= len(data):
        key = struct.unpack_from("<H", data, hit)[0]
        if not key & 0x4000:  # the compact form's own `complex` bit
            readings.append((data[hit + 3], struct.unpack_from("<I", data, hit + 4)[0]))
    for data_type, value in readings:
        if data_type not in VALUE_TYPES:
            continue
        if data_type == VALUE_TYPE_STRING and value >= len(strings):
            continue
        return data_type, value
    return None


def arsc_picture_rows(rows, wanted_density=ICON_WANTED_DENSITY):
    """The id's rows that could name a picture, nearest `wanted_density` first.

    A row that ends in `.xml` is a drawable document, not a picture: its layers
    are read by `element_layer_markup` instead. A row whose extension was
    shortened away stays in, because only its bytes say what it is - which is
    why the callers are told to try them in order rather than trust the first.
    """
    def keeps(row, any_density=False):
        lower = row[1].lower()
        return ((any_density or row[0] not in DENSITY_ANY)
                and (lower.endswith(ICON_IMAGE_SUFFIXES)
                     or not lower.endswith(".xml")))

    kept = [row for row in rows if keeps(row)]
    if not kept:
        # `nodpi` and `anydpi` are left to the end because they name the
        # adaptive XML more often than a picture; when nothing else is left they
        # are the picture, which is how a WebAPK's stored SVG answers.
        kept = [row for row in rows if keeps(row, True)]
    return [row[1] for row in sorted(kept, key=lambda row: (
        abs(row[0] - wanted_density), -row[0]))]


def adaptive_icon_layers(root):
    """The `(role, element)` layers an adaptive icon draws, in draw order.

    A layer element either names its drawable - `android:drawable`, which is
    the form that has been around since adaptive icons appeared - or carries it
    inline, which is what a recent app's launcher icon does: the `<vector>` or
    `<layer-list>` sits inside `<background>` and `<foreground>` themselves.
    """
    return [(element["name"], element) for element in (root or {}).get("children", [])
            if element["name"] in ADAPTIVE_LAYER_ROLES]


def axml_tree(data):
    """The root element of a compiled XML file, or None.

    AAPT2 writes a drawable's XML in the same binary form as the manifest: a
    string pool, then one chunk per element with its typed attribute values.
    The tree is kept because a vector's paths sit inside `<group>` elements
    whose transforms they inherit - a flat list would draw them upright.
    """
    try:
        if struct.unpack_from("<H", data, 0)[0] != RES_XML_TYPE:
            return None
        end = struct.unpack_from("<I", data, 4)[0] or len(data)
        end = min(end, len(data))
    except struct.error:
        return None
    strings, root, stack, pos = [], None, [], 8
    while pos + 8 <= end:
        try:
            ctype, header_size, size = struct.unpack_from("<HHI", data, pos)
        except struct.error:
            break
        if size <= 0 or pos + size > end:
            break
        if ctype == RES_CHUNK_STRING_POOL:
            strings = read_string_pool(data, pos)
        elif ctype == RES_XML_START_ELEMENT and strings:
            name_ref = struct.unpack_from("<I", data, pos + 20)[0]
            attr_start, attr_size, attr_count = struct.unpack_from("<HHH", data, pos + 24)
            attrs = {}
            for i in range(attr_count):
                at = pos + 16 + attr_start + i * max(attr_size, 20)
                ref = struct.unpack_from("<I", data, at + 4)[0]
                key = strings[ref] if ref < len(strings) else str(ref)
                data_type = data[at + 15]
                value = struct.unpack_from("<I", data, at + 16)[0]
                text = (strings[value] if data_type == VALUE_TYPE_STRING
                        and value < len(strings) else None)
                attrs[key] = (data_type, value, text)
            node = {"name": strings[name_ref] if name_ref < len(strings) else "",
                    "attrs": attrs, "children": []}
            if stack:
                stack[-1]["children"].append(node)
            elif root is None:
                root = node
            stack.append(node)
        elif ctype == RES_XML_END_ELEMENT and stack:
            stack.pop()
        pos += size
    return root


def axml_number(element, key, table=None):
    """One numeric attribute as a float, with a reference followed into `table`."""
    attr = element["attrs"].get(key)
    if not attr:
        return None
    data_type, value, text = attr
    if data_type == VALUE_TYPE_FLOAT:
        return struct.unpack("<f", struct.pack("<I", value))[0]
    if data_type == VALUE_TYPE_DIMENSION:
        return axml_fixed(value)
    if data_type == VALUE_TYPE_INT_DECIMAL:
        return float(struct.unpack("<i", struct.pack("<I", value))[0])
    if data_type == VALUE_TYPE_REFERENCE and value and table:
        for _density, kind, resolved in table.entries(value) or []:
            if kind == VALUE_TYPE_INT_DECIMAL:
                return float(struct.unpack("<i", struct.pack("<I", resolved))[0])
            if kind == VALUE_TYPE_FLOAT:
                return struct.unpack("<f", struct.pack("<I", resolved))[0]
    if data_type == VALUE_TYPE_STRING and text:
        try:
            return float(text)
        except ValueError:
            return None
    return None


def axml_fixed(value):
    """A packed Android dimension as a float, per ResourceTypes' radix."""
    radix = value & 0x3
    mantissa = value >> 8
    if mantissa & 0x800000:
        mantissa -= 1 << 24
    return mantissa / (1 << (0, 7, 15, 23)[radix])


def argb_svg(value, data_type):
    """An Android color value as the #rrggbbaa that SVG wants."""
    if data_type == VALUE_INT_COLOR_ARGB4:
        a, r, g, b = ((value >> 12) & 0xF, (value >> 8) & 0xF,
                      (value >> 4) & 0xF, value & 0xF)
        return "#{:02x}{:02x}{:02x}{:02x}".format(r * 17, g * 17, b * 17, a * 17)
    if data_type == VALUE_INT_COLOR_RGB4:
        r, g, b = ((value >> 8) & 0xF, (value >> 4) & 0xF, value & 0xF)
        return "#{:02x}{:02x}{:02x}ff".format(r * 17, g * 17, b * 17)
    if data_type == VALUE_INT_COLOR_RGB8:
        return "#{:06x}ff".format(value & 0xFFFFFF)
    return argb8_svg(value)


def argb8_svg(value):
    """TYPE_INT_COLOR_ARGB8 - and every color resource's stored shape."""
    return "#{:02x}{:02x}{:02x}{:02x}".format(
        (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF,
        (value >> 24) & 0xFF)


def resolve_color(tables, res_id, depth=0, framework=True):
    """The #rrggbbaa a resource id names, following the chain a colour is written as.

    An entry that is a colour, an entry that is the text of one, an entry that is
    another entry's name - the shapes a colour comes in. A reference into the
    framework's colour block names a themed colour whose value sits in the 20MB
    table at `/system/framework`, which no icon is worth downloading, so the mid
    grey it stands in for is drawn: visible on any background, which nothing else
    here is promised to be. A reference into any other part of the framework names
    `android.R.drawable` or an attribute rather than a colour, and nothing is
    painted for it - a rectangle laid over the layer that did resolve is the worse
    answer of the two. `framework` is off below the layer's own top element for
    that reason: an `<item>` inside a `<layer-list>` may well name
    `@android:color/transparent`, whose stand-in would be an opaque sheet over
    the icon.
    """
    if not tables or not res_id:
        return None
    for _density, kind, resolved in tables.entries(res_id) or []:
        if kind in VALUE_COLOR_TYPES:
            return argb_svg(resolved, kind)
        if kind == VALUE_TYPE_STRING and isinstance(resolved, str) \
                and resolved.startswith("#"):
            return resolved
        if kind == VALUE_TYPE_REFERENCE and resolved and depth < ARSC_ALIAS_DEPTH:
            color = resolve_color(tables, resolved, depth + 1, framework)
            if color:
                return color
    if framework and (res_id & 0xFFFF0000) == FRAMEWORK_COLOUR_BLOCK:
        return FRAMEWORK_PAINT
    return None


def axml_color(element, key, table=None):
    """One color attribute as #rrggbbaa, following a reference into the tables."""
    attr = element["attrs"].get(key)
    if not attr:
        return None
    data_type, value, text = attr
    if data_type in VALUE_COLOR_TYPES:
        return argb_svg(value, data_type)
    if data_type == VALUE_TYPE_STRING and text and text.startswith("#"):
        return text
    if data_type == VALUE_TYPE_REFERENCE:
        return resolve_color(table, value)
    return None


def split_color(paint):
    """Android's `#rrggbbaa` as (`#rrggbb`, alpha).

    Eight-digit hex is what the packed colour values make, and both librsvg and
    recent Qt read it - but the six-digit form plus an opacity attribute is what
    SVG was written to say, and the two orders of the extra byte have been
    confused by renderers before.
    """
    if paint and len(paint) == 9 and paint[0] == "#":
        try:
            return "#" + paint[1:7], int(paint[7:9], 16) / 255.0
        except ValueError:
            pass
    return paint, 1.0


def svg_path(element, table, paint):
    """A `<path>` as SVG, or None when it neither fills nor strokes anything."""
    data = element["attrs"].get("pathData")
    if not data or not data[2]:
        return None
    fill = paint(element, "fillColor")
    stroke = paint(element, "strokeColor")
    if fill is None and stroke is None:
        return None
    parts = ['<path d="{}"'.format(escape(data[2], {'"': "&quot;"}))]
    fill_color, fill_alpha_color = split_color(fill) if fill else (None, 1.0)
    parts.append('fill="{}"'.format(fill_color or "none"))
    fill_alpha = axml_number(element, "fillAlpha", table)
    opacity = fill_alpha_color * (1.0 if fill_alpha is None else fill_alpha)
    if fill and opacity < 1.0:
        parts.append('fill-opacity="{:g}"'.format(opacity))
    if int(axml_number(element, "fillType", table) or 0) == 1:
        parts.append('fill-rule="evenodd"')
    if stroke:
        width = axml_number(element, "strokeWidth", table) or 0
        if width <= 0:
            stroke = None
        else:
            stroke_color, stroke_alpha_color = split_color(stroke)
            parts.append('stroke="{}"'.format(stroke_color))
            parts.append('stroke-width="{:g}"'.format(width))
            stroke_alpha = axml_number(element, "strokeAlpha", table)
            opacity = stroke_alpha_color * (1.0 if stroke_alpha is None
                                            else stroke_alpha)
            if opacity < 1.0:
                parts.append('stroke-opacity="{:g}"'.format(opacity))
            cap = int(axml_number(element, "strokeLineCap", table) or 0)
            parts.append('stroke-linecap="{}"'.format(
                ("butt", "round", "square")[cap] if cap < 3 else "butt"))
            join = int(axml_number(element, "strokeLineJoin", table) or 0)
            parts.append('stroke-linejoin="{}"'.format(
                ("miter", "round", "bevel")[join] if join < 3 else "miter"))
    parts.append("/>")
    return " ".join(parts)


def svg_group(element, table, paint):
    """A `<group>` as an SVG transform wrapping its own children's markup."""
    inner = svg_children(element, table, paint)
    if not inner:
        return None
    translate_x = axml_number(element, "translateX", table) or 0.0
    translate_y = axml_number(element, "translateY", table) or 0.0
    pivot_x = axml_number(element, "pivotX", table) or 0.0
    pivot_y = axml_number(element, "pivotY", table) or 0.0
    rotation = axml_number(element, "rotation", table) or 0.0
    scale_x = axml_number(element, "scaleX", table)
    scale_y = axml_number(element, "scaleY", table)
    # Android rotates and scales about the pivot and then offsets the group;
    # the same order as a list of SVG transform functions.
    transform = "translate({:g},{:g}) translate({:g},{:g}) rotate({:g})".format(
        translate_x, translate_y, pivot_x, pivot_y, rotation)
    if scale_x is not None or scale_y is not None:
        transform += " scale({:g},{:g})".format(
            1.0 if scale_x is None else scale_x, 1.0 if scale_y is None else scale_y)
    if pivot_x or pivot_y:
        transform += " translate({:g},{:g})".format(-pivot_x, -pivot_y)
    return '<g transform="{}">{}</g>'.format(transform, inner)


def svg_children(element, table, paint):
    """The markup of a vector element's children, or None when it draws none."""
    out = []
    for child in element["children"]:
        if child["name"] == "group":
            markup = svg_group(child, table, paint)
        elif child["name"] == "path":
            markup = svg_path(child, table, paint)
        else:
            markup = None  # clip-path and friends are left unserved
        if markup:
            out.append(markup)
    return "".join(out) or None


def svg_document(body, width, height, defs=()):
    head = "<defs>{}</defs>".format("".join(defs)) if defs else ""
    return ('<svg xmlns="http://www.w3.org/2000/svg" '
            'xmlns:xlink="http://www.w3.org/1999/xlink" '
            'width="{:g}" height="{:g}" viewBox="0 0 {:g} {:g}">{}</svg>').format(
                width * SVG_RENDER_SCALE, height * SVG_RENDER_SCALE,
                width, height, head + body)


def gradient_node(element, key):
    """The `<gradient>` an element carries inline through an `<aapt:attr>`."""
    for child in element["children"]:
        if child["name"] != "attr":
            continue
        named = (child["attrs"].get("name") or (0, 0, ""))[2] or ""
        if not named.endswith(":" + key):
            continue
        for node in child["children"]:
            if node["name"] == "gradient":
                return node
    return None


def gradient_svg(node, table, gid):
    """A compiled `<gradient>` as a paint SVG can draw, or None.

    Android's coordinates are in the drawable's own user space, the same space
    the path is drawn in, so `userSpaceOnUse` hands them to SVG unchanged. A
    gradient spelled with an angle rather than a line, and a sweep, are left
    undrawn: the first has no line to give until the shape it fills is measured
    and the second has no SVG equivalent at all.
    """
    if not node or node["name"] != "gradient":
        return None
    stops = []
    for item in node["children"]:
        if item["name"] != "item":
            continue
        color = axml_color(item, "color", table)
        if color:
            offset = axml_number(item, "offset", table)
            stops.append((0.0 if offset is None else max(0.0, min(1.0, offset)),
                          color))
    if len(stops) < 2:
        return None
    stops_markup = []
    for offset, color in stops:
        hex_color, alpha = split_color(color)
        stops_markup.append('<stop offset="{:g}" stop-color="{}"{}/>'.format(
            offset, hex_color,
            "" if alpha >= 1.0 else ' stop-opacity="{:g}"'.format(alpha)))
    body = "".join(stops_markup)
    kind = int(axml_number(node, "type", table) or 0)
    if kind == 0:
        line = [axml_number(node, key, table)
                for key in ("startX", "startY", "endX", "endY")]
        if None in line:
            return None
        return ('<linearGradient id="{}" gradientUnits="userSpaceOnUse" '
                'x1="{:g}" y1="{:g}" x2="{:g}" y2="{:g}">{}</linearGradient>'
                ).format(gid, line[0], line[1], line[2], line[3], body)
    if kind == 1:
        circle = [axml_number(node, key, table)
                  for key in ("centerX", "centerY", "gradientRadius")]
        if None in circle:
            return None
        return ('<radialGradient id="{}" gradientUnits="userSpaceOnUse" '
                'cx="{:g}" cy="{:g}" r="{:g}" fx="{:g}" fy="{:g}">{}</radialGradient>'
                ).format(gid, circle[0], circle[1], circle[2], circle[0],
                         circle[1], body)
    return None


def vector_svg_document(root, table, paint, defs=()):
    """A `<vector>` tree as a standalone SVG document, or None."""
    if not root or root["name"] != "vector":
        return None
    body = svg_children(root, table, paint)
    if not body:
        return None
    width = axml_number(root, "viewportWidth", table) or 0.0
    height = axml_number(root, "viewportHeight", table) or 0.0
    if width <= 0 or height <= 0:
        # A vector with no viewport sizes itself by its own bounds, which SVG
        # cannot do; the intrinsic dp size is the best canvas there is.
        width = axml_number(root, "width", table) or 48.0
        height = axml_number(root, "height", table) or width
    return svg_document(body, width, height, defs)


def vector_svg_group(root, table, paint, canvas=ADAPTIVE_CANVAS):
    """A `<vector>`'s markup, scaled from its own viewport onto `canvas`."""
    if not root or root["name"] != "vector":
        return None
    body = svg_children(root, table, paint)
    if not body:
        return None
    view_w = axml_number(root, "viewportWidth", table) or 0.0
    view_h = axml_number(root, "viewportHeight", table) or 0.0
    if view_w <= 0 or view_h <= 0:
        return "<g>{}</g>".format(body)
    return '<g transform="scale({:g},{:g})">{}</g>'.format(
        canvas / view_w, canvas / view_h, body)


def adaptive_svg_document(markups, canvas=ADAPTIVE_CANVAS, defs=()):
    """The layers of an adaptive icon, painted into one SVG document.

    Each layer was authored on the 108dp canvas and is drawn onto it as is -
    what the launcher then crops to its mask is its own business, and the
    shell shapes the picture it is given anyway.
    """
    body = "".join(part for part in markups if part)
    if not body:
        return None
    return svg_document(body, canvas, canvas, defs)


def color_rect_svg(color, canvas=ADAPTIVE_CANVAS):
    if not color:
        return None
    hex_color, alpha = split_color(color)
    return '<rect width="{:g}" height="{:g}" fill="{}"{}/>'.format(
        canvas, canvas, hex_color,
        "" if alpha >= 1.0 else ' fill-opacity="{:g}"'.format(alpha))


def raster_image_svg(data, mime="image/png", canvas=ADAPTIVE_CANVAS):
    """A bitmap layer carried inside the SVG, so one file holds the whole icon."""
    if not data:
        return None
    href = "data:{};base64,{}".format(mime, b64encode(data).decode("ascii"))
    return ('<image x="0" y="0" width="{:g}" height="{:g}" href="{}" '
            'xlink:href="{}"/>').format(canvas, canvas, href, href)


def icon_id_from_query(text):
    """The launcher activity's `icon=0x...`, or None when it declares none."""
    match = LAUNCHER_ICON_ID.search(text or "")
    if not match:
        return None
    return int(match.group(1), 16) or None


def manifest_application_icon(data):
    """The `<application android:icon>` resource id, or None.

    An activity that declares no icon of its own is answered `icon=0x0` by the
    package manager, and the icon the launcher actually draws is the
    application's - which only the manifest names. The attribute's index into
    the string pool is mapped through the file's resource map to the framework
    id `android:icon`, and its typed value is the reference to look up.
    """
    try:
        if struct.unpack_from("<H", data, 0)[0] != RES_XML_TYPE:
            return None
    except struct.error:
        return None
    strings = []
    resource_map = []
    pos = 8
    end = struct.unpack_from("<I", data, 4)[0] if len(data) > 8 else 0
    end = min(end or len(data), len(data))
    while pos + 8 <= end:
        ctype, header_size, size = struct.unpack_from("<HHI", data, pos)
        if size <= 0 or pos + size > end:
            break
        if ctype == RES_CHUNK_STRING_POOL:
            strings = read_string_pool(data, pos)
        elif ctype == RES_XML_RESOURCE_MAP:
            slots = (size - header_size) // 4
            resource_map = list(struct.unpack_from("<%dI" % slots, data, pos + header_size))
        elif ctype == RES_XML_START_ELEMENT and strings:
            # ResXMLTree_node is 16 bytes, then the attribute block starts at
            # `attributeStart` from there.
            name_index = struct.unpack_from("<I", data, pos + 20)[0]
            if name_index < len(strings) and strings[name_index] == "application":
                attr_start, attr_size, attr_count = struct.unpack_from(
                    "<HHH", data, pos + 24)
                for i in range(attr_count):
                    at = pos + 16 + attr_start + i * max(attr_size, 20)
                    name = struct.unpack_from("<I", data, at + 4)[0]
                    res_id = resource_map[name] if name < len(resource_map) else 0
                    if res_id != AXML_ANDROID_ICON:
                        continue
                    data_type = data[at + 15]
                    value = struct.unpack_from("<I", data, at + 16)[0]
                    if data_type == VALUE_TYPE_REFERENCE and value:
                        return value
            pos += size
            continue
        pos += size
    return None


def image_suffix(data):
    """The suffix for bytes that are one of the accepted pictures, else None."""
    data = data or b""
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return ".png"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return ".webp"
    if data[:3] == b"\xff\xd8\xff":
        return ".jpg"
    # A WebAPK's site icon is the SVG the page served, stored as it came, and it
    # is the only thing that answers for that app's launcher icon. A compiled
    # drawable is binary XML and starts with a chunk type, so it is not this.
    head = data[:256].lstrip()
    if head[:4] == b"<svg" or (head[:5] == b"<?xml" and b"<svg" in data[:1024]):
        return ".svg"
    return None


def shrink_icon_picture(data, suffix):
    """One icon picture as it is kept: no bigger than it is drawn, and bounded.

    A row paints these into a slot of about 39 CSS pixels, so `ICON_PICTURE_MAX_SIDE`
    is already twice what the largest monitor scale samples from, and the
    192-432 px originals are several times the disk for pixels that are thrown
    away. PNG and WebP are both encoded and the smaller is kept, because a flat
    logo is a third of its size as a PNG while a shaded one is a sixth of it as a
    WebP.

    Pillow is not a condition for having an icon. Without it - or without the
    patience to shrink - the archive's own bytes are kept when they fit
    `ICON_PICTURE_MAX_BYTES` and dropped when they do not: the bound is the
    promise, and a file over it is the one thing that cannot be stored.
    """
    def fits_as_is():
        return (data, suffix) if len(data) <= ICON_PICTURE_MAX_BYTES else (None, None)

    if not data:
        return None, None
    try:
        from PIL import Image
    except ImportError:
        return fits_as_is()
    side = ICON_PICTURE_MAX_SIDE
    while True:
        try:
            image = Image.open(io.BytesIO(data))
            image.load()
            # An animated icon is the animation's own first frame and its loops
            # are its own business; the archive's bytes keep both.
            if getattr(image, "n_frames", 1) > 1:
                return fits_as_is()
            if max(image.size) <= side and len(data) <= ICON_PICTURE_MAX_BYTES:
                return data, suffix
            if image.mode not in ("RGB", "RGBA"):
                image = image.convert("RGBA")
            if max(image.size) > side:
                image = image.resize((min(image.width, side),
                                      min(image.height, side)), Image.LANCZOS)
                if image.mode not in ("RGB", "RGBA"):
                    image = image.convert("RGBA")
            png = io.BytesIO()
            image.save(png, "PNG", optimize=True)
            webp = io.BytesIO()
            image.save(webp, "WEBP", quality=ICON_PICTURE_WEBP_QUALITY, method=4)
        except Exception:
            return fits_as_is()
        best = min(((png.getvalue(), ".png"), (webp.getvalue(), ".webp")),
                   key=lambda pair: len(pair[0]))
        if len(best[0]) <= ICON_PICTURE_MAX_BYTES:
            return best
        if side <= 32:
            return fits_as_is()
        side //= 2


def safe_name(value):
    return re.sub(r"[^A-Za-z0-9_.-]", "_", str(value) or "default")


def icon_cache_dir(device_id):
    """The per-phone icon folder, next to the per-phone app cache."""
    return CACHE_DIR.parent / "icons" / safe_name(device_id)


def icon_record_path(device_id, package):
    return icon_cache_dir(device_id) / (safe_name(package) + ".json")


def icon_picture_path(device_id, package, suffix):
    return icon_cache_dir(device_id) / (safe_name(package) + (suffix or ""))


def read_icon_record(device_id, package):
    """What the last read of this package's APK said, or None when it can't be
    believed.

    A picture is believed only while the rules that made it are the current
    ones, and a verdict of "this app has no icon" likewise: the first pass
    answered from file names alone and called every shrunk-path package iconless,
    and honoring that verdict would keep such an app iconless even after the
    resource table learned to name its picture.
    """
    try:
        record = json.loads(icon_record_path(device_id, package).read_text())
    except Exception:
        return None
    if not isinstance(record, dict):
        return None
    suffix = record.get("suffix")
    if not suffix:
        return record if record.get("v") == ICON_RECORD_VERSION else None
    path = icon_picture_path(device_id, package, suffix)
    # An icon cached at 192 px while the rules now keep 96 is read again rather
    # than kept at four times the disk it needs.
    if record.get("v") != ICON_RECORD_VERSION:
        return None
    return record if path.is_file() else None


def write_icon_record(device_id, package, record):
    directory = icon_cache_dir(device_id)
    directory.mkdir(parents=True, exist_ok=True)
    path = icon_record_path(device_id, package)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(dict(record, v=ICON_RECORD_VERSION)),
                         encoding="utf-8")
    os.replace(temporary, path)


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
        # Launcher icons arrive one package at a time on a worker of their
        # own, and `icon_pending` is the queue's dedupe. `icon_ids` remembers
        # each launcher activity's resource id, which is asked for with a
        # package-manager query and holds for the life of this process.
        self.icon_queue = queue.Queue()
        # The icon a row asked for the moment it appeared. Drained before the
        # bulk fill below, so the list the user is reading is never queued
        # behind the two hundred packages they have not reached yet.
        self.icon_urgent = queue.Queue()
        self.icon_worker = None
        self.icon_pending = set()
        self.icon_ids = {}
        # Which archive an entry of this package was read from, kept only for
        # the fetch that learned it. One install's icon is read through the same
        # few paths several times over, and a miss costs a whole `adb` call.
        self.icon_entry_hits = {}
        # Which phone the icon queue is reading from, and when that was asked.
        self.icon_target_cache = None
        self.icon_target_at = 0.0

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

    # ---- launcher icons --------------------------------------------------

    def request_app_icon(self, package, target_args=None, device_id="default",
                         hopeful=False, urgent=False):
        """Queue one package's launcher icon.

        Rows ask as they appear, so a page showing 60 apps is 60 requests. They
        sit on one worker because two `adb` processes over the wireless link are
        slower than either alone, and `icon_pending` keeps a package already on
        its way from being fetched twice. Nothing is answered on this thread:
        even a cached icon needs the one cheap `pm path` that says the install
        is still the archive the cache was read from.

        `urgent` is a row's own ask, and goes to a queue drained before the bulk
        one the page fills in the background - the alternative is the list the
        user is reading waiting behind two hundred they have not reached.
        """
        if not package:
            return
        device_id = device_id or "default"
        key = (device_id, package)
        with self.lock:
            if key in self.icon_pending:
                return
            self.icon_pending.add(key)
        if self.icon_worker is None or not self.icon_worker.is_alive():
            self.icon_worker = threading.Thread(target=self._icon_loop,
                                                daemon=True)
            self.icon_worker.start()
        queue_ = self.icon_urgent if urgent else self.icon_queue
        queue_.put((package, target_args, device_id, bool(hopeful)))

    def _icon_loop(self):
        while True:
            package, target_args, device_id, hopeful = self._next_icon_job()
            try:
                outcome = self.fetch_app_icon(package, target_args, device_id,
                                             hopeful)
            except Exception as error:
                sys.stderr.write(f"app_icon: {error}\n")
                self.emit({"event": "app_icon", "package": package, "path": ""})
                outcome = None
            if outcome == ICON_DEFERRED:
                # Back of the queue, with leave to read the table it is waiting
                # on: the cheap rows go first either way.
                self.icon_queue.put((package, target_args, device_id, True))
                continue
            with self.lock:
                self.icon_pending.discard((device_id, package))

    def _next_icon_job(self):
        """The next icon to read: a visible row's, then the bulk fill's.

        The bulk queue is polled with a short timeout rather than blocked on, so
        a row that appears while nothing else is queued is picked up within that
        poll instead of waiting for an unrelated package to arrive.
        """
        while True:
            try:
                return self.icon_urgent.get_nowait()
            except queue.Empty:
                pass
            try:
                return self.icon_queue.get(timeout=ICON_POLL_SECONDS)
            except queue.Empty:
                continue

    def fetch_app_icon(self, package, target_args=None, device_id="default",
                       hopeful=False):
        """Read one icon out of the install without pulling it.

        Three readings, cheapest first, because one worker answers the whole
        list and a slow app is a row that never fills:

        1. `unzip -l` and the names it still spells out. A build that kept
           `res/mipmap-xxxhdpi/ic_launcher.png` needs nothing else, and that is
           most apps.
        2. `resources.arsc`, which is what names the picture after the release
           tool has shrunk the file to `res/Gc.png` - and the only way to an
           adaptive icon's XML, which is then drawn (see `icon_svg_document`).
           It costs a download, so it is read only when the names tell nothing,
           smallest table first, and never when it is absurdly large.
        3. The loose reading of the names, for the entries that sit in a
           `mipmap` folder under some other name.

        An install is often several archives, because a store-built app has its
        pictures split out by density; the icon is therefore looked for across
        the base and the configuration splits (see `icon_listing`). Whatever
        answers is recorded against the archive list it came from, so asking
        twice about one install costs a single `pm path`, and an update that
        moves an archive is read again rather than keeping the icon it no
        longer has.

        `hopeful` is the second time this is asked of one package, after the
        queue drained the rows that answer cheaply, and it lifts the table budget
        to the size of Google's own - the only apps whose icon is named nowhere
        else. Without it the same lookup stops at `ICON_TABLE_MAX_BYTES`.
        """
        device_id = device_id or "default"
        self.icon_entry_hits = {}
        target = self.icon_target(target_args)
        apks = self.icon_archives(package, target)
        installed = "+".join(apks)
        record = read_icon_record(device_id, package)
        if installed and record and record.get("apk") == installed:
            suffix = record.get("suffix")
            path = icon_picture_path(device_id, package, suffix) if suffix else None
            if path is None or path.is_file():
                self.emit({"event": "app_icon", "package": package,
                           "path": str(path) if path else ""})
                return
        if not apks:

            # No archive to read is a fact about this moment, not about the
            # app: nothing is recorded, so the next ask tries again.
            self.emit({"event": "app_icon", "package": package, "path": ""})
            return

        # The two sizes asked about: what the queue will wait for now, and what
        # its second pass over this package will be allowed to wait for.
        limit = ICON_TABLE_HOPEFUL_BYTES if hopeful else ICON_TABLE_MAX_BYTES
        entries, tables, bigger = self.icon_listing(apks, target, limit)
        hopeful_available = bigger and not hopeful
        named = pick_icon_entry(entries)
        data = suffix = None
        if named and icon_entry_rank(named)[0] >= ICON_NAME_TIER_TRUSTED:
            data = self.zip_entry_bytes(apks, named, target)
            suffix = image_suffix(data)

        # A table is the one step that can hold the queue behind a Google-sized
        # base, so the install's tables are read smallest first and the sweep
        # stops as soon as one of them names a picture.
        conclusive = data is not None
        if data is None:
            res_id = self.icon_resource_id(package, apks[0], target)
            if res_id is None:
                conclusive = True  # neither place names an icon: that is one
            else:
                blobs = []
                for budget, archive in tables:
                    table = self.zip_entry_bytes(
                        [archive], "resources.arsc", target,
                        ICON_TABLE_HOPEFUL_TIMEOUT if hopeful else
                        ICON_TABLE_TIMEOUT,
                        budget)
                    if not table:
                        continue
                    conclusive = True
                    blobs.append(table)
                    # The table said picture; the bytes settle it, because a
                    # shortened path is a name that says nothing and an empty
                    # member is a name that was left standing in the folder.
                    for path in ArscTables(blobs).picture_rows(res_id):
                        candidate = self.zip_entry_bytes(apks, path, target)
                        found = image_suffix(candidate)
                        if found:
                            data, suffix, named = candidate, found, named or path
                            break
                    if data is not None:
                        break
                if data is None and blobs:
                    # Nothing named a picture, so the drawing is read out of all
                    # of them together: one table holds an adaptive icon's XML
                    # and another the layers that XML points at.
                    svg = self.icon_svg_document(res_id, ArscTables(blobs), apks,
                                         target)
                    if svg:
                        data, suffix, named = svg.encode("utf-8"), ".svg", "drawn"
        if data is None and hopeful_available:
            # The names and every affordable table said nothing, and what they
            # cannot see is a table the queue must not wait on. Asked again at
            # the back of it, when the rows that answer cheaply are filled.
            return ICON_DEFERRED
        if data is None and named:
            # Either there was no table to read or it said nothing, so the
            # mipmap folder's last word is taken.
            data = self.zip_entry_bytes(apks, named, target)
            suffix = image_suffix(data)
            conclusive = True
        if data is None or suffix is None:
            if conclusive:
                # Recorded, because the archive holds neither a picture nor
                # instructions the loader can use, and asking again each boot
                # would only repeat that.
                write_icon_record(device_id, package,
                                  {"apk": installed, "suffix": None, "entry": None})
            self.emit({"event": "app_icon", "package": package, "path": ""})
            return

        # Kept at the size it is drawn at and under the bound one icon may take;
        # a layer that cannot be brought under it answers as no icon rather than
        # as a file the promise said it would not be.
        if suffix in ICON_IMAGE_MIME:
            data, suffix = shrink_icon_picture(data, suffix)
        if data is None or suffix is None:
            self.emit({"event": "app_icon", "package": package, "path": ""})
            return

        path = icon_picture_path(device_id, package, suffix)
        icon_cache_dir(device_id).mkdir(parents=True, exist_ok=True)
        # Written beside its name and moved in, so a row that asks while this
        # is half-written never reads a truncated picture.
        temporary = path.with_name(path.name + ".tmp")
        temporary.write_bytes(data)
        os.replace(temporary, path)
        # A picture whose encoding changed leaves the previous one on disk. A row
        # that is still showing it holds that path, and deleting the file from
        # under it is how an icon that was fine at the start of a session turns
        # back into a glyph in the middle of one. The record names the current
        # file; the others cost a few kilobytes each, and rewriting the same
        # encoding overwrites rather than accumulates.
        write_icon_record(device_id, package,
                          {"apk": installed, "suffix": suffix, "entry": named})
        self.emit({"event": "app_icon", "package": package, "path": str(path)})

    def icon_target(self, target_args=None):
        """`resolve_adb_target` with a few seconds of memory.

        A resolve is an `adb connect` and an `adb devices`, and the icon queue
        does one per row of a phone's whole app list on a single worker -
        which is how one app's table read came to look like every icon behind
        it having stopped. Launches, mirrors and focus still resolve every
        time, so a phone that was swapped is picked up by the next of those and
        by the next drain of the icon queue.
        """
        if self.icon_target_cache is None or time.time() - self.icon_target_at > 5:
            self.icon_target_cache = self.resolve_adb_target(target_args)
            self.icon_target_at = time.time()
        return self.icon_target_cache

    def icon_archives(self, package, target):
        """Every archive the install is made of, the base first."""
        res = subprocess.run(["adb"] + target + ["shell", "pm", "path", package],
                             capture_output=True, text=True, timeout=ICON_TIMEOUT)
        return [line[len("package:"):].strip() for line in res.stdout.splitlines()
                if line.startswith("package:")]

    def icon_listing(self, apks, target, budget=ICON_TABLE_MAX_BYTES):
        """`([entries], [(table bytes, archive)], another_is_bigger)` to ask.

        Past the base only a `split_config.*` is listed: those are the archives
        a store build's pictures were moved into, while a module split is code
        and its listing is a call that answers nothing. The tables come back
        smallest first because the download is what the queue has to wait on,
        and a split's table is kilobytes against a base's megabytes. The third
        answer says a table was left out for being over `budget`, which is what
        tells the caller that a second, wider pass could still find something.
        """
        splits = [one for one in apks[1:] if "_config" in one]
        entries, tables, bigger = [], [], False
        for archive in (apks[:1] + splits)[:ICON_ARCHIVE_MAX]:
            listed = parse_zip_listing((self.zip_entry_text(
                archive, ["unzip", "-l", shlex.quote(archive)], target,
                ICON_TIMEOUT) or "").splitlines())
            entries += listed
            size = arsc_size(listed)
            if size and size <= budget:
                tables.append((size, archive))
            elif size:
                bigger = True
        tables.sort()
        return entries, tables, bigger

    def icon_resource_id(self, package, apk, target):
        """The icon's resource id, from the launcher activity then the manifest.

        Most apps carry the icon on the `<application>` tag rather than on the
        activity, which only the manifest names, so the query's silence is
        followed by a manifest read rather than taken for an answer. Asked once
        per package for the life of this process.
        """
        if package not in self.icon_ids:
            res = subprocess.run(
                ["adb"] + target + ["shell", "cmd", "package", "query-activities",
                                    "-a", "android.intent.action.MAIN", "-c",
                                    "android.intent.category.LAUNCHER", package],
                capture_output=True, text=True, timeout=ICON_TIMEOUT)
            self.icon_ids[package] = icon_id_from_query(res.stdout)
            if self.icon_ids[package] is None:
                manifest = self.zip_entry_bytes(apk, "AndroidManifest.xml", target)
                self.icon_ids[package] = manifest_application_icon(manifest or b"")
        return self.icon_ids[package]

    def zip_entry_bytes(self, apks, path, target, timeout=ICON_READ_TIMEOUT,
                        max_bytes=None):
        """One entry of the install, read without pulling any archive.

        `apks` is one archive or the several an install is made of, tried in
        order; whichever answered is remembered for the rest of this package,
        since one icon is read through the same path two or three times.

        `exec-out` rather than `shell`, which runs its command through a PTY
        that rewrites bytes and corrupts pictures.

        `max_bytes` is why this is not a `subprocess.run` call: the size has to
        be noticed while the entry is still arriving, so an archive member
        bigger than the caller will wait for is abandoned at once instead of
        holding the icon queue behind it.
        """
        candidates = [apks] if isinstance(apks, str) else list(apks or [])
        remembered = self.icon_entry_hits.get(path)
        if remembered in candidates and remembered != candidates[0]:
            candidates.remove(remembered)
            candidates.insert(0, remembered)
        for archive in candidates:
            data = self._zip_entry_once(archive, path, target, timeout, max_bytes)
            if data:
                self.icon_entry_hits[path] = archive
                return data
        return None

    def _zip_entry_once(self, apk, path, target, timeout, max_bytes):
        # No quoting, and no shell either: `exec-out` hands its arguments to the
        # binary as they are, so a drawable named `$ic_launcher__0.xml` arrives
        # with its dollar sign rather than as the empty variable a shell would
        # see. (The `shell` calls above are the ones that need quoting.)
        proc = subprocess.Popen(
            ["adb"] + target + ["exec-out", "unzip", "-p", apk, path],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        timer = threading.Timer(timeout, proc.kill)
        timer.start()
        data, too_big = b"", False
        try:
            while True:
                chunk = proc.stdout.read(1 << 16)
                if not chunk:
                    break
                data += chunk
                if max_bytes and len(data) > max_bytes:
                    too_big = True
                    proc.kill()
                    break
        except OSError:
            too_big = True
        finally:
            timer.cancel()
            try:
                proc.stdout.close()
            except OSError:
                pass
            proc.wait()
        if too_big or proc.returncode != 0:
            return None
        return data

    def zip_entry_text(self, apk, command, target, timeout=ICON_TIMEOUT):
        """One `unzip` run against the archive, as text, or None when it fails."""
        res = subprocess.run(["adb"] + target + ["shell"] + command,
                             capture_output=True, text=True, timeout=timeout)
        return res.stdout if res.returncode == 0 else None

    def icon_paint(self, table, apks, target, defs):
        """The brush one icon is drawn with, recording the gradients it finds.

        A `fillColor` is a colour until a build decides otherwise: AGP pulls a
        vector's gradient out into a file of its own and leaves the attribute
        pointing at it. Then the answer is a definition the document has to
        carry, so the brush appends it to `defs` and hands back the `url(#…)`
        that names it - and a path that only has this kind of paint is drawn by
        the same rule as one with a colour.
        """
        def paint(element, key):
            color = axml_color(element, key, table)
            if color:
                return color
            node = gradient_node(element, key)
            attr = element["attrs"].get(key)
            if node is None and attr and attr[0] == VALUE_TYPE_REFERENCE:
                node = self.referenced_gradient(attr[1], table, apks, target)
            if node is None:
                return None
            gid = "imi{}".format(len(defs))
            markup = gradient_svg(node, table, gid)
            if markup is None:
                return None
            defs.append(markup)
            return "url(#{})".format(gid)

        return paint

    def referenced_gradient(self, res_id, table, apks, target):
        """The `<gradient>` a resource id names, when it names one."""
        if not res_id:
            return None
        for _density, path in sorted(table.paths(res_id) or [],
                                     key=lambda row: -row[0]):
            if not path.lower().endswith(".xml"):
                continue
            doc = self.zip_entry_bytes(apks, path, target)
            root = axml_tree(doc) if doc else None
            if root and root["name"] == "gradient":
                return root
        return None

    def drawable_layer_markup(self, res_id, apks, target, table, paint, defs,
                              theme_fill=False):
        """One adaptive-icon layer named by a resource id, as SVG body.

        The three things a layer can be are painted three ways: a colour fills
        the canvas, a bitmap rides inside the SVG as a data URI so the icon
        stays one file, and a vector contributes its paths - scaled from the
        viewport it was drawn on to the adaptive canvas, which is how the
        launcher fits it. Which of the three it is comes from the bytes rather
        than the file name, because a release build's shortened paths leave
        nothing in the name to read.
        """
        color = resolve_color(table, res_id, framework=theme_fill)
        if color:
            return color_rect_svg(color)
        rows = table.paths(res_id) or []
        for path in arsc_picture_rows(rows):
            data = self.zip_entry_bytes(apks, path, target)
            suffix = image_suffix(data)
            if suffix:
                # The layer rides inside the SVG as a data URI, so it is shrunk
                # here as well: a 432 px layer inlined would weigh more than the
                # whole document is allowed to.
                data, suffix = shrink_icon_picture(data, suffix)
                if data is None:
                    continue
                return raster_image_svg(data, ICON_IMAGE_MIME[suffix])
        for _density, path in sorted(rows, key=lambda row: -row[0]):
            if not path.lower().endswith(".xml"):
                continue
            data = self.zip_entry_bytes(apks, path, target)
            root = axml_tree(data) if data else None
            if root:
                markup = self.element_layer_markup(root, apks, target, table,
                                                  paint, defs)
                if markup:
                    return markup
        return None

    def element_layer_markup(self, node, apks, target, table, paint, defs,
                             depth=0, theme_fill=False):
        """One drawable as it is spelled inside an adaptive icon, or None.

        A recent app's `<foreground>` holds its `<vector>` or `<layer-list>`
        rather than naming one, and a `<layer-list>` holds `<item>`s that each
        hold one; all of it is drawn, in the order the launcher would, until the
        nesting runs deeper than `LAYER_DEPTH_MAX`.
        """
        if node is None or depth > LAYER_DEPTH_MAX:
            return None
        if node["name"] == "vector":
            return vector_svg_group(node, table, paint)
        for key in ("drawable", "src"):
            attr = node["attrs"].get(key)
            if attr and attr[0] == VALUE_TYPE_REFERENCE and attr[1]:
                markup = self.drawable_layer_markup(attr[1], apks, target, table,
                                                   paint, defs, theme_fill)
                if markup:
                    return markup
        if node["name"] == "shape":
            solid = next((child for child in node["children"]
                          if child["name"] == "solid"), None)
            color = solid and axml_color(solid, "color", table)
            return color_rect_svg(color) if color else None
        body = "".join(filter(None, (self.element_layer_markup(
            child, apks, target, table, paint, defs, depth + 1)
            for child in node["children"])))
        return body or None

    def icon_svg_document(self, res_id, table, apks, target):
        """A drawn SVG for an icon that has no bitmap in the install, or None.

        Most launch icons today are only instructions: an adaptive icon's XML
        naming a colour and a vector, or a bare vector. Those become the SVG
        the shell's image loader paints, which is what lets GitHub, Claude or a
        Google app show its own mark rather than the shell's glyph.
        """
        rows = table.paths(res_id)
        if not rows:
            return None  # the tables name nothing for this id
        defs = []
        paint = self.icon_paint(table, apks, target, defs)
        # A document first: an id's other rows are bitmaps, which the caller has
        # already tried, and reading them again to learn they are not XML is a
        # download for nothing.
        for _density, path in sorted(rows, key=lambda row: (
                not row[1].lower().endswith(".xml"), -row[0])):
            doc = self.zip_entry_bytes(apks, path, target)
            root = axml_tree(doc) if doc else None
            if not root:
                continue
            if root["name"] == "vector":
                return vector_svg_document(root, table, paint, defs)
            if root["name"] == "adaptive-icon":
                painted = {}
                for role, layer in adaptive_icon_layers(root):
                    markup = self.element_layer_markup(
                        layer, apks, target, table, paint, defs,
                        theme_fill=role != "monochrome")
                    if markup:
                        painted[role] = markup
                # A monochrome layer is the themed shape the launcher tints, so
                # it is drawn only when there is nothing else to draw.
                body = [markup for role, markup in painted.items()
                        if role != "monochrome"] or list(painted.values())
                return adaptive_svg_document(body, defs=defs)
            # A selector, a layer list, an inset: whatever it composes, it
            # composes onto the launcher's canvas like any other icon.
            markup = self.element_layer_markup(root, apks, target, table, paint,
                                               defs)
            if markup:
                return svg_document(markup, ADAPTIVE_CANVAS, ADAPTIVE_CANVAS, defs)
        return None

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
        elif cmd == "app_icon":
            self.request_app_icon(msg.get("package"),
                                  target_args=msg.get("target_args"),
                                  device_id=msg.get("deviceId", "default"),
                                  urgent=bool(msg.get("priority")))
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
    parser = argparse.ArgumentParser(description="scrcpy session supervisor for Illogical Impulse")
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
