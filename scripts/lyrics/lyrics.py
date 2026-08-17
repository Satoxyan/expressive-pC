#!/usr/bin/env python3
import sys
import os
import re
import json
import base64
import hashlib
import hmac
import signal
import time
import threading
import datetime
import urllib.request
import urllib.parse

DEFAULT_PROVIDERS = "musixmatch,youlyplus,paxsenix,betterlyric,simpmusic,lrclib,kugou"

USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

PROVIDER_TIMEOUT = 12  # seconds per provider


# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------

_PROVIDER_DEADLINE = 0.0  # module-global; set by orchestrator before each provider


def _http(url, headers=None, timeout=12):
    # Bound every request by the provider deadline so that a provider can
    # never exceed PROVIDER_TIMEOUT even when an internal handler swallows
    # SIGALRM (which is one-shot and gets eaten by except blocks).
    if _PROVIDER_DEADLINE > 0:
        remaining = _PROVIDER_DEADLINE - time.time()
        if remaining <= 0:
            raise TimeoutError("provider deadline exceeded")
        timeout = min(timeout, remaining)
    hdrs = {"User-Agent": USER_AGENT}
    if headers:
        hdrs.update(headers)
    req = urllib.request.Request(url, headers=hdrs)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode("utf-8", "replace")


def _http_json(url, headers=None, timeout=12):
    return json.loads(_http(url, headers, timeout))


def _q(s):
    return urllib.parse.quote(s)


# ---------------------------------------------------------------------------
# Text normalization (mirrors vivi-music)
# ---------------------------------------------------------------------------

TITLE_CLEANUP = [
    re.compile(r'\s*\(.*?(official|video|audio|lyrics|lyric|visualizer|hd|hq|4k|remaster|remix|live|acoustic|version|edit|extended|radio|clean|explicit).*?\)', re.I),
    re.compile(r'\s*\[.*?(official|video|audio|lyrics|lyric|visualizer|hd|hq|4k|remaster|remix|live|acoustic|version|edit|extended|radio|clean|explicit).*?\]', re.I),
    re.compile(r'\s*【.*?】'),
    re.compile(r'\s*\|.*$'),
    re.compile(r'\s*-\s*(official|video|audio|lyrics|lyric|visualizer).*$', re.I),
    re.compile(r'\s*\(feat\..*?\)', re.I),
    re.compile(r'\s*\(ft\..*?\)', re.I),
    re.compile(r'\s*feat\..*$', re.I),
    re.compile(r'\s*ft\..*$', re.I),
    re.compile(r'\s*\([^)]*\d{4}[^)]*\)'),
]

ARTIST_SEPARATORS = [" & ", " and ", ", ", " x ", " X ", " feat. ", " feat ", " ft. ", " ft ", " featuring ", " with "]


def clean_title(title):
    for pattern in TITLE_CLEANUP:
        title = pattern.sub("", title)
    return title.strip()


def clean_artist(artist):
    artist = artist.strip()
    lower = artist.lower()
    for sep in ARTIST_SEPARATORS:
        idx = lower.find(sep.lower())
        if idx != -1:
            return artist[:idx].strip()
    return artist


def clean_text(text):
    text = text.replace(",", " ").replace("&", " ")
    text = re.sub(r"\(.*?\)", "", text)
    text = re.sub(r"\[.*?\]", "", text)
    text = text.lower()
    text = re.sub(r"[^a-z0-9 ]", "", text)
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def _kugou_normalize_title(t):
    for pat in (r"\(.*\)", r"（.*）", r"「.*」", r"『.*』", r"<.*>", r"《.*》", r"〈.*〉", r"＜.*＞"):
        t = re.sub(pat, "", t)
    return t


def _kugou_normalize_artist(a):
    a = a.replace(", ", "、").replace(" & ", "、").replace(".", "").replace("和", "、")
    a = re.sub(r"\(.*\)", "", a)
    a = re.sub(r"（.*）", "", a)
    return a


# ---------------------------------------------------------------------------
# LRC parsing
# ---------------------------------------------------------------------------

_INLINE_TAG = re.compile(r"<(\d{1,2}):(\d{2}(?:\.\d{1,3})?)>\s*([^<]*)")


def _parse_lrc(lrc_text):
    lines = []
    for raw in lrc_text.splitlines():
        raw = raw.strip()
        if not raw:
            continue
        try:
            tag_end = raw.index("]")
            time_str = raw[1:tag_end]
            text = raw[tag_end + 1:].strip()
            mins, secs = time_str.split(":")
            timestamp = int(mins) * 60 + float(secs)
        except Exception:
            continue
        # Enhanced LRC: inline <mm:ss.xx> word tags are relative to the line start
        inline = _INLINE_TAG.findall(text)
        words = []
        if inline:
            for m, s, wtxt in inline:
                wtxt = wtxt.strip()
                if wtxt:
                    words.append({"t": timestamp + int(m) * 60 + float(s), "w": wtxt})
            lead = text[:text.find("<")].strip()
            if lead:
                words.insert(0, {"t": timestamp, "w": lead})
            clean = _INLINE_TAG.sub("", text)
        else:
            clean = text
        clean = re.sub(r"<[^>]+>", "", clean)   # strip other inline word tags
        clean = re.sub(r"\{[^}]*\}", "", clean)  # strip {bg} / {agent:...} markers
        clean = clean.strip()
        if not clean:
            continue
        lines.append({"time": timestamp, "text": clean, "words": words})
    return sorted(lines, key=lambda x: x["time"])


# ---------------------------------------------------------------------------
# TTML -> LRC (port of vivi-music TTMLParser)
# ---------------------------------------------------------------------------

def _ttml_time(t):
    t = t.strip()
    if ":" in t:
        parts = t.split(":")
        if len(parts) == 2:
            return float(parts[0]) * 60 + float(parts[1])
        if len(parts) == 3:
            return float(parts[0]) * 3600 + float(parts[1]) * 60 + float(parts[2])
    try:
        return float(t)
    except Exception:
        return 0.0


def _ttml_role(el):
    for attr, val in el.attrib.items():
        if attr.rsplit("}", 1)[-1] == "role":
            return val
    return ""


def _ttml_line_text(p):
    parts = []
    for span in p.iter():
        tag = span.tag.rsplit("}", 1)[-1]
        if tag != "span":
            continue
        role = _ttml_role(span)
        if role in ("x-translation", "x-roman", "x-bg"):
            continue
        if span.text and span.text.strip():
            parts.append(span.text.strip())
    if parts:
        return " ".join(parts)
    return " ".join("".join(p.itertext()).split())


def _ttml_line_words(p):
    """Extract per-word timings from a TTML <p> element (Apple Music style).

    Each <span> typically carries its own begin time. Words without a span
    begin fall back to the line's begin time.
    """
    words = []
    for span in p.iter():
        tag = span.tag.rsplit("}", 1)[-1]
        if tag != "span":
            continue
        role = _ttml_role(span)
        if role in ("x-translation", "x-roman", "x-bg"):
            continue
        begin = span.get("begin")
        if begin:
            text = "".join(span.itertext()).strip()
            if text:
                words.append({"t": _ttml_time(begin), "w": text})
    if words:
        return words
    # No per-span timings: treat whole line as a single "word"
    text = _ttml_line_text(p)
    if text:
        return [{"t": _ttml_time(p.get("begin")), "w": text}]
    return []


def ttml_to_lrc(ttml):
    try:
        import xml.etree.ElementTree as ET
        root = ET.fromstring(ttml)
    except Exception:
        return []
    lines = []
    for p in root.iter():
        if p.tag.rsplit("}", 1)[-1] != "p":
            continue
        begin = p.get("begin")
        if not begin:
            continue
        text = _ttml_line_text(p)
        if not text:
            continue
        lines.append({
            "time": _ttml_time(begin),
            "text": text,
            "words": _ttml_line_words(p),
        })
    return sorted(lines, key=lambda x: x["time"])


# ---------------------------------------------------------------------------
# Provider: musixmatch (reverse-engineered web signing, keyless)
# ---------------------------------------------------------------------------

_MS_HEADERS = {
    "User-Agent": USER_AGENT,
    "Accept": "application/json, text/plain, */*",
    "Accept-Language": "en-US,en;q=0.9",
}

_MS_SECRET_FALLBACK = "b3dc8788299f5806a70a6a20a0cb0ffc"
_ms_secret_cache = [None]
_ms_token_cache = [None]


def _ms_get_secret():
    if _ms_secret_cache[0]:
        return _ms_secret_cache[0]
    try:
        page = _http("https://www.musixmatch.com/search", headers={
            "User-Agent": USER_AGENT,
            "Cookie": "mxm_bab=AB",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.9",
        }, timeout=8)
        m = re.search(r'src="([^"]*/_next/static/chunks/pages/_app-[^"]+\.js)"', page)
        if not m:
            raise Exception("no app js")
        js = _http(m.group(1), headers={"User-Agent": USER_AGENT, "Accept": "*/*"}, timeout=8)
        m2 = re.search(r'from\(\s*"(.*?)"\s*\.split', js)
        if not m2:
            raise Exception("no secret")
        secret = base64.b64decode(m2.group(1)[::-1]).decode("utf-8")
    except Exception:
        secret = _MS_SECRET_FALLBACK
    _ms_secret_cache[0] = secret
    return secret


def _ms_sign(url, secret):
    normalized = url.replace("%20", "+").replace(" ", "+")
    date_str = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d")
    message = (normalized + date_str).encode("utf-8")
    sig = hmac.new(secret.encode("utf-8"), message, hashlib.sha256).digest()
    b64 = base64.b64encode(sig).decode()
    return f"{normalized}&signature={urllib.parse.quote(b64, safe='')}&signature_protocol=sha256"


def _ms_get_token(secret, force=False):
    if not force and _ms_token_cache[0]:
        return _ms_token_cache[0]
    url = "https://apic.musixmatch.com/ws/1.1/token.get?app_id=web-desktop-app-v1.0&format=json"
    data = _http_json(_ms_sign(url, secret), headers=_MS_HEADERS)
    body = data.get("message", {}).get("body")
    if isinstance(body, dict):
        token = body.get("user_token")
        if token:
            _ms_token_cache[0] = token
            return token
    raise Exception("no user token")


def _ms_fetch_lyric(track_id, token, secret, kind):
    ep = {"richsync": "track.richsync.get", "subtitle": "track.subtitle.get"}[kind]
    url = (f"https://apic.musixmatch.com/ws/1.1/{ep}?app_id=web-desktop-app-v1.0&format=json"
           f"&track_id={track_id}&usertoken={token}")
    data = _http_json(_ms_sign(url, secret), headers=_MS_HEADERS)
    if data.get("message", {}).get("header", {}).get("status_code") in (401, 402):
        return None
    body = data.get("message", {}).get("body") or {}
    if kind == "richsync":
        return (body.get("richsync") or {}).get("richsync_body")
    return (body.get("subtitle") or {}).get("subtitle_body")


def _ms_richsync_to_lines(body):
    try:
        entries = json.loads(body)
    except Exception:
        return []
    lines = []
    for e in entries:
        ts = float(e.get("ts") or 0)
        text = (e.get("x") or "").strip()
        if not text:
            continue
        words = []
        rows = e.get("l")
        if rows:
            # Current richsync shape: "l" is a list of {"c": word,
            # "o": seconds from line start}; spaces are {"c": " "}.
            for row in rows:
                c = (row.get("c") or "").strip()
                if not c:
                    continue
                words.append({"t": ts + (row.get("o") or 0), "w": c})
        else:
            # Older shape: "c" was a list of per-char {"t", "o"};
            # group consecutive chars into words.
            cur = ""
            cur_offset = None
            for ch in e.get("c") or []:
                c = ch.get("t") or ""
                o = ch.get("o")
                if c == " ":
                    if cur:
                        words.append({"t": ts + (cur_offset or 0) / 1000.0, "w": cur})
                        cur = ""
                        cur_offset = None
                else:
                    if cur_offset is None:
                        cur_offset = o
                    cur += c
            if cur:
                words.append({"t": ts + (cur_offset or 0) / 1000.0, "w": cur})
        lines.append({"time": ts, "text": text, "words": words})
    return sorted(lines, key=lambda x: x["time"])


def _ms_subtitle_to_lines(body):
    try:
        entries = json.loads(body)
    except Exception:
        return []
    lines = []
    for e in entries:
        text = (e.get("text") or "").strip()
        total = (e.get("time") or {}).get("total")
        if total is None or not text:
            continue
        lines.append({"time": float(total), "text": text, "words": []})
    return sorted(lines, key=lambda x: x["time"])


def fetch_musixmatch(title, artist, duration):
    for attempt in range(2):
        try:
            secret = _ms_get_secret()
            token = _ms_get_token(secret, force=(attempt > 0))
            search_url = ("https://apic.musixmatch.com/ws/1.1/track.search?"
                          "app_id=web-desktop-app-v1.0&format=json"
                          f"&q_track={_q(title)}&q_artist={_q(artist)}"
                          "&f_has_lyrics=true&page_size=10"
                          f"&usertoken={token}")
            data = _http_json(_ms_sign(search_url, secret), headers=_MS_HEADERS)
            status = data.get("message", {}).get("header", {}).get("status_code")
            if status in (401, 402):
                raise Exception("token expired")
            track_list = data.get("message", {}).get("body", {}).get("track_list") or []
            tracks = [t["track"] for t in track_list if isinstance(t, dict) and "track" in t]
            if not tracks:
                return []
            query_title = clean_text(title)
            duration = int(duration)

            def keyfn(t):
                tt = clean_text(t.get("track_name") or "")
                if tt == query_title:
                    ts = 0
                elif tt in query_title or query_title in tt:
                    ts = 1
                else:
                    ts = 2
                td = t.get("track_length") or 0
                if duration > 0 and td > 0:
                    dd = abs(td - duration)
                elif td == 0:
                    dd = 999
                else:
                    dd = 1 << 31
                return (ts << 32) + dd

            tracks.sort(key=keyfn)
            best = tracks[0]
            track_id = best.get("track_id")
            for kind in ("richsync", "subtitle"):
                body = _ms_fetch_lyric(track_id, token, secret, kind)
                if not body:
                    continue
                lines = (_ms_richsync_to_lines(body) if kind == "richsync"
                         else _ms_subtitle_to_lines(body))
                if lines:
                    return lines
            return []
        except Exception:
            _ms_token_cache[0] = None
            _ms_secret_cache[0] = None
    return []


# ---------------------------------------------------------------------------
# Provider: youlyplus / LyricsPlus (multi-server race)
# ---------------------------------------------------------------------------

YOULYPLUS_SERVERS = [
    "https://lyricsplus.prjktla.my.id",
    "https://lyricsplus.atomix.one",
    "https://lyricsplus.binimum.org",
    "https://lyricsplus.prjktla.workers.dev",
    "https://lyrics-plus-backend.vercel.app",
    "https://lyricsplus-seven.vercel.app",
]


def fetch_youlyplus(title, artist, duration):
    for server in YOULYPLUS_SERVERS:
        try:
            url = (f"{server}/v2/lyrics/get?title={_q(title)}&artist={_q(artist)}"
                   f"&duration={int(duration)}")
            data = _http_json(url)
            synced = data.get("syncedLyrics") or ""
            if synced.strip():
                lines = _parse_lrc(synced)
                if lines:
                    return lines
            items = data.get("lyrics") or []
            if items:
                lrc = []
                for it in items:
                    t = it.get("time")
                    txt = (it.get("text") or "").strip()
                    if t is None or not txt:
                        continue
                    lrc.append({"time": t / 1000.0, "text": txt, "words": []})
                if lrc:
                    return sorted(lrc, key=lambda x: x["time"])
        except Exception:
            continue
    return []


# ---------------------------------------------------------------------------
# Provider: paxsenix (Apple Music search + lyrics.paxsenix.org)
# ---------------------------------------------------------------------------

_APPLE_TOKEN_CACHE = [None]


def _apple_token():
    if _APPLE_TOKEN_CACHE[0]:
        return _APPLE_TOKEN_CACHE[0]
    page = _http("https://beta.music.apple.com", timeout=8)
    m = re.search(r"/assets/index~[^/]+\.js", page)
    if not m:
        raise Exception("no apple js")
    js = _http("https://beta.music.apple.com" + m.group(0), timeout=8)
    m2 = re.search(r"eyJ[A-Za-z0-9\-_=]+\.[A-Za-z0-9\-_=]+\.[A-Za-z0-9\-_=]+", js)
    if not m2:
        raise Exception("no apple token")
    _APPLE_TOKEN_CACHE[0] = m2.group(0)
    return m2.group(0)


def _apple_search(token, query):
    url = ("https://amp-api.music.apple.com/v1/catalog/us/search?"
           f"term={_q(query)}&types=songs&limit=25&l=en-US&platform=web"
           "&format[resources]=map&include[songs]=artists&extend=artistUrl")
    data = _http_json(url, headers={
        "Authorization": f"Bearer {token}",
        "Origin": "https://music.apple.com",
        "Referer": "https://music.apple.com/",
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:95.0) Gecko/20100101 Firefox/95.0",
        "Accept": "application/json",
        "Accept-Language": "en-US,en;q=0.5",
        "x-apple-renewal": "true",
    })
    results = []
    try:
        songs = data["results"]["songs"]["data"] or []
        resources = data.get("resources", {}).get("songs", {}) or {}
    except Exception:
        return results
    for song in songs:
        detail = resources.get(song.get("id")) or {}
        attr = detail.get("attributes") or {}
        dur_ms = attr.get("durationInMillis") or 0
        results.append({
            "id": song.get("id"),
            "name": attr.get("name") or "",
            "artist": attr.get("artistName") or "",
            "duration": dur_ms // 1000 if dur_ms else None,
        })
    return results


def _score_apple_results(results, title, artist, duration):
    cleanup = re.compile(r'\s*\(.*?\)|\s*\[.*?\]')
    cleaned_title = cleanup.sub("", title).lower().strip()
    cleaned_artist = clean_artist(artist).lower()
    target_is_mixed = "mixed" in title.lower()
    target_is_remix = "remix" in title.lower()
    scored = []
    for r in results:
        score = 0
        if duration and r["duration"]:
            diff = abs(r["duration"] - int(duration))
            if diff <= 2:
                score += 100
            elif diff <= 5:
                score += 50
            elif diff <= 10:
                score += 10
            else:
                score -= 50
        rt = cleanup.sub("", r["name"]).lower().strip()
        if rt == cleaned_title:
            score += 80
        elif rt in cleaned_title or cleaned_title in rt:
            score += 40
        if "mixed" in r["name"].lower() and not target_is_mixed:
            score -= 60
        if "remix" in r["name"].lower() and not target_is_remix:
            score -= 40
        ra = r["artist"].lower()
        if cleaned_artist and cleaned_artist in ra:
            score += 50
        else:
            words = [w for w in cleaned_artist.split() if len(w) > 2]
            if any(w in ra for w in words):
                score += 25
        if score > 0:
            scored.append((r, score))
    scored.sort(key=lambda x: x[1], reverse=True)
    return scored[:10]


def _parse_elrc(raw):
    """Parse enhanced-LRC lines -> [{time, text, words: [{t, w}]}].

    Each word carries an absolute <mm:ss.xx> timestamp. A trailing tag with no
    text (the line's end time) and any lead text such as "v1:" are ignored.
    """
    lines = []
    for line in raw.splitlines():
        line = line.strip()
        if not line:
            continue
        m = re.match(r"\[([\d:.]+)\](.*)", line)
        if not m:
            continue
        t = _ttml_time(m.group(1))
        words = []
        for wm in re.finditer(r"<([^>]+)>\s*([^<]*)", m.group(2)):
            w = wm.group(2).strip()
            if w:
                words.append({"t": _ttml_time(wm.group(1)), "w": w})
        if words:
            text = " ".join(x["w"] for x in words)
            lines.append({"time": t, "text": text, "words": words})
    return sorted(lines, key=lambda x: x["time"])


def _merge_split_words(lines, text_map):
    """Re-segment over-split timed words to match the full word text.

    Apple/paxsenix word timings sometimes split a sung word into fragments
    ("conver" + "sation") even though it is one word ("conversation"), while
    the plain/lrc text keeps the real segmentation. Align the timed tokens
    against that text and merge fragments that together spell one word.
    Falls back to the input line when a line can't be aligned.
    """
    times = sorted(text_map)
    merged = []
    for ln in lines:
        tokens = ln["words"]
        if not tokens:
            merged.append(ln)
            continue
        target = None
        best = 0.05
        for t in times:
            d = abs(t - ln["time"])
            if d < best:
                best = d
                target = text_map[t]
        if target is None:
            merged.append(ln)
            continue
        twords = target.split()
        concat = "".join(x["w"] for x in tokens)
        if concat != re.sub(r"\s+", "", target):
            merged.append(ln)
            continue
        out = []
        ti = 0
        ok = True
        for tw in twords:
            acc = ""
            acc_t = None
            while ti < len(tokens) and len(acc) < len(tw):
                tok = tokens[ti]
                if acc_t is None:
                    acc_t = tok["t"]
                acc += tok["w"]
                ti += 1
            if acc == tw:
                out.append({"t": acc_t, "w": acc})
            else:
                ok = False
                break
        if ok and ti == len(tokens) and len(out) == len(twords):
            merged.append({"time": ln["time"], "text": target, "words": out})
        else:
            merged.append(ln)
    return merged


def _paxsenix_lyrics(track_id):
    data = _http_json(f"https://lyrics.paxsenix.org/apple-music/lyrics?id={track_id}",
                      headers={"User-Agent": "ViviMusic/1.0"})
    # Ground-truth per-line text: keeps the real word segmentation that the
    # timed spans below split into fragments.
    text_map = {}
    for field in ("lrc", "elrc", "elrcMultiPerson"):
        raw = data.get(field) or ""
        if raw.strip():
            for ln in _parse_lrc(raw):
                text_map.setdefault(ln["time"], ln["text"])
    ttml = data.get("ttmlContent") or ""
    if ttml.strip():
        lines = ttml_to_lrc(ttml)
        if lines:
            return _merge_split_words(lines, text_map), 3
    for field in ("elrcMultiPerson", "elrc"):
        raw = data.get(field) or ""
        if raw.strip():
            lines = _parse_elrc(raw)
            if lines:
                return _merge_split_words(lines, text_map), 3
    content = data.get("content") or []
    if content:
        lines = []
        for line in content:
            t = line.get("timestamp")
            txt = " ".join((w.get("text") or "") for w in line.get("text") or []).strip()
            if t is not None and txt:
                lines.append({"time": t / 1000.0, "text": txt, "words": []})
        if lines:
            return sorted(lines, key=lambda x: x["time"]), 3
    return [], 0


def fetch_paxsenix(title, artist, duration):
    try:
        token = _apple_token()
    except Exception:
        return []
    cleaned_title = clean_title(title)
    cleaned_artist = clean_artist(artist)
    queries = [f"{cleaned_title} {cleaned_artist}", cleaned_title]
    scored = []
    for query in queries:
        if scored:
            break
        try:
            results = _apple_search(token, query)
        except Exception:
            _APPLE_TOKEN_CACHE[0] = None
            try:
                token = _apple_token()
                results = _apple_search(token, query)
            except Exception:
                results = []
        scored = _score_apple_results(results, title, artist, duration)
    best = None
    best_quality = 0
    for result, _score in scored:
        try:
            lrc, quality = _paxsenix_lyrics(result["id"])
        except Exception:
            lrc, quality = [], 0
        if lrc and quality > best_quality:
            best = lrc
            best_quality = quality
        if best_quality == 3:
            break
    return best or []


# ---------------------------------------------------------------------------
# Provider: better lyric (lyrics-api.boidu.dev)
# ---------------------------------------------------------------------------

def fetch_betterlyric(title, artist, duration):
    url = (f"https://lyrics-api.boidu.dev/getLyrics?s={_q(title)}"
           f"&a={_q(artist)}&d={int(duration)}")
    try:
        data = _http_json(url)
    except Exception:
        return []
    ttml = data.get("ttml") or ""
    if not ttml.strip():
        return []
    return ttml_to_lrc(ttml)


# ---------------------------------------------------------------------------
# Provider: simpmusic (YouTube videoId based)
# ---------------------------------------------------------------------------

SIMPMUSIC_BASE = "https://api-lyrics.simpmusic.org/v1/"
SIMPMUSIC_FALLBACK = "https://vivi-yt-music-server.onrender.com/v1/"


def _simpmusic_best_item(items, title, artist, duration):
    best = None
    best_score = None
    for it in items:
        score = 0
        st = (it.get("songTitle") or "").lower()
        t = title.lower()
        if st == t:
            score += 100
        elif t in st or st in t:
            score += 50
        dur = it.get("durationSeconds")
        if dur is not None and duration > 0:
            score += max(0, 30 - abs(int(dur) - int(duration)))
        else:
            score += 5
        if best_score is None or score > best_score:
            best_score = score
            best = it
    return best


def fetch_simpmusic(title, artist, duration):
    try:
        data = _http_json(SIMPMUSIC_BASE + "search?q=" + _q(f"{title} {artist}"))
    except Exception:
        return []
    if data.get("type") != "success":
        return []
    items = data.get("data") or []
    if not items:
        return []
    best = _simpmusic_best_item(items, title, artist, duration)
    video_id = (best or {}).get("videoId")
    if not video_id:
        return []
    for base in (SIMPMUSIC_BASE, SIMPMUSIC_FALLBACK):
        try:
            resp = _http_json(base + video_id)
        except Exception:
            continue
        if resp.get("type") != "success":
            continue
        tracks = resp.get("data") or []
        if duration > 0 and tracks:
            tracks = sorted(tracks, key=lambda tr: abs((tr.get("durationSeconds") or 0) - int(duration)))
        for tr in tracks:
            for field in ("richSyncLyrics", "syncedLyrics"):
                raw = tr.get(field) or ""
                if raw.strip():
                    lines = _parse_lrc(raw)
                    if lines:
                        return lines
    return []


# ---------------------------------------------------------------------------
# Provider: lrclib
# ---------------------------------------------------------------------------

def fetch_lrclib(title, artist, duration):
    cleaned_title = clean_title(title)
    cleaned_artist = clean_artist(artist)
    queries = [
        {"track_name": cleaned_title, "artist_name": cleaned_artist},
        {"track_name": cleaned_title},
        {"q": f"{cleaned_artist} {cleaned_title}"},
        {"q": cleaned_title},
    ]
    if cleaned_title != title.strip():
        queries.append({"track_name": title.strip(), "artist_name": artist.strip()})
    qt = cleaned_title.lower()
    qa = cleaned_artist.lower()

    for params in queries:
        try:
            data = _http_json("https://lrclib.net/api/search?" + urllib.parse.urlencode(params))
        except Exception:
            continue
        if not isinstance(data, list):
            continue
        tracks = [d for d in data if d.get("syncedLyrics")]
        if not tracks:
            continue

        def keyfn(d):
            rt = (d.get("trackName") or "").lower()
            ra = (d.get("artistName") or "").lower()
            title_score = 0 if rt == qt else (1 if (qt in rt or rt in qt) else 2)
            artist_score = 0 if ra == qa else (1 if (qa in ra or ra in qa) else 2)
            td = d.get("duration")
            dur = abs(td - duration) if (td and duration) else 0
            return (title_score, artist_score, dur)

        tracks.sort(key=keyfn)
        for track in tracks:
            lines = _parse_lrc(track["syncedLyrics"])
            if lines:
                return lines
    return []


# ---------------------------------------------------------------------------
# Provider: kugou
# ---------------------------------------------------------------------------

DURATION_TOLERANCE = 8


def _kugou_search_by_hash(hash_):
    data = _http_json(f"https://lyrics.kugou.com/search?ver=1&man=yes&client=pc&hash={hash_}")
    candidates = data.get("candidates") or []
    if candidates:
        return {"id": candidates[0].get("id"), "accesskey": candidates[0].get("accesskey")}
    return None


def _kugou_search_by_keyword(keyword, duration):
    url = f"https://lyrics.kugou.com/search?ver=1&man=yes&client=pc&keyword={_q(keyword)}"
    if duration and duration != -1:
        url += f"&duration={int(duration) * 1000}"
    data = _http_json(url)
    candidates = data.get("candidates") or []
    if candidates:
        return {"id": candidates[0].get("id"), "accesskey": candidates[0].get("accesskey")}
    return None


def _kugou_download(id_, accesskey):
    url = (f"https://lyrics.kugou.com/download?fmt=lrc&charset=utf8&client=pc&ver=1"
           f"&id={id_}&accesskey={accesskey}")
    data = _http_json(url)
    content = data.get("content")
    if not content:
        return None
    try:
        lrc = base64.b64decode(content).decode("utf-8", "replace")
    except Exception:
        return None
    return "\n".join(line for line in lrc.splitlines()
                     if not re.match(r".+].+[:：].+", line))


def fetch_kugou(title, artist, duration):
    keyword = f"{_kugou_normalize_title(title)} - {_kugou_normalize_artist(artist)}"
    candidate = None
    try:
        data = _http_json("https://mobileservice.kugou.com/api/v3/search/song"
                          "?version=9108&plat=0&pagesize=8&showtype=0"
                          f"&keyword={_q(keyword)}")
        for song in (data.get("data", {}) or {}).get("info", []) or []:
            if duration and duration != -1:
                if abs(int(song.get("duration") or 0) - int(duration)) > DURATION_TOLERANCE:
                    continue
            if song.get("hash"):
                candidate = _kugou_search_by_hash(song["hash"])
                if candidate:
                    break
    except Exception:
        pass
    if not candidate:
        try:
            candidate = _kugou_search_by_keyword(keyword, duration)
        except Exception:
            candidate = None
    if not candidate:
        return []
    try:
        lrc = _kugou_download(candidate.get("id"), candidate.get("accesskey"))
    except Exception:
        return []
    if not lrc:
        return []
    return _parse_lrc(lrc)


# ---------------------------------------------------------------------------
# Orchestrator
# ---------------------------------------------------------------------------

PROVIDERS = {
    "musixmatch": fetch_musixmatch,
    "youlyplus": fetch_youlyplus,
    "paxsenix": fetch_paxsenix,
    "betterlyric": fetch_betterlyric,
    "simpmusic": fetch_simpmusic,
    "lrclib": fetch_lrclib,
    "kugou": fetch_kugou,
}


def _provider_names(arg):
    if not arg or not arg.strip():
        return DEFAULT_PROVIDERS.split(",")
    return [p.strip() for p in arg.split(",") if p.strip()]


_PAUSE_PUNCT = frozenset(",.;:!?—–…-()[]\"")


def _synthesize_words(lines):
    """Assign per-word timings to lines that lack them.

    Distributes each line's time span (line start -> next line start) across
    its words so the karaoke effect still works for plain LRC sources without
    word-level timestamps. A word's share is proportional to its length, and
    words ending in punctuation get extra time so phrasing/pauses feel natural
    instead of a uniform sweep.
    """
    out = []
    n = len(lines)
    for i, line in enumerate(lines):
        if line.get("words"):
            out.append(line)
            continue
        text = line.get("text") or ""
        words = text.split()
        if not words:
            out.append(line)
            continue
        start = line["time"]
        end = lines[i + 1]["time"] if i + 1 < n else start + 5.0
        span = max(0.25, end - start)
        weights = [len(w) + (3 if w[-1] in _PAUSE_PUNCT else 0) for w in words]
        total = sum(weights)
        ws = []
        t = start
        for w, wt in zip(words, weights):
            ws.append({"t": t, "w": w})
            t += span * (wt / total)
        line["words"] = ws
        out.append(line)
    return out


def main():
    if len(sys.argv) < 4:
        print("no_info", flush=True)
        return
    title = sys.argv[1]
    artist = sys.argv[2]
    try:
        duration = float(sys.argv[3])
    except Exception:
        duration = 0
    providers = DEFAULT_PROVIDERS
    if "--providers" in sys.argv:
        idx = sys.argv.index("--providers")
        if idx + 1 < len(sys.argv):
            providers = sys.argv[idx + 1]
    if not title or not artist:
        print("no_info", flush=True)
        return

    def run_with_timeout(fn):
        """Run a provider function on a daemon thread with a hard timeout.

        SIGALRM is unreliable here because one-shot alarm fires once and gets
        swallowed by the many `except Exception` blocks inside providers, and
        urllib tries every resolved address (4+ IPs) at the socket timeout, so
        a single request can block for address_count * timeout seconds.
        A worker thread guarantees each provider gets at most PROVIDER_TIMEOUT
        seconds regardless of what it swallows.
        """
        result = {}
        def worker():
            try:
                result["lines"] = fn(title, artist, duration)
            except Exception:
                result["lines"] = []
        t = threading.Thread(target=worker, daemon=True)
        t.start()
        t.join(PROVIDER_TIMEOUT)
        if t.is_alive():
            return []
        return result.get("lines") or []

    for name in _provider_names(providers):
        fn = PROVIDERS.get(name)
        if not fn:
            continue
        lines = run_with_timeout(fn)
        if lines:
            lines = _synthesize_words(lines)
            payload = {
                "ok": True,
                "provider": name,
                "lines": [
                    {
                        "t": line["time"],
                        "x": line["text"].replace("§", ""),
                        "w": [[w["t"], w["w"]] for w in line.get("words") or []],
                    }
                    for line in lines
                ],
            }
            print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), flush=True)
            return

    print("not_found", flush=True)


if __name__ == "__main__":
    main()