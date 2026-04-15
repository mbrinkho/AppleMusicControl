#!/usr/bin/env python3
"""Apple Music web controller — no dependencies, Python 3.6+"""

import json
import os
import subprocess
import tempfile
import urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = 3000
ART_PATH = os.path.join(tempfile.gettempdir(), "apple_music_art.jpg")
PUBLIC_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "public")

MIME = {
    ".html": "text/html; charset=utf-8",
    ".css":  "text/css",
    ".js":   "application/javascript",
    ".ico":  "image/x-icon",
    ".png":  "image/png",
    ".jpg":  "image/jpeg",
    ".svg":  "image/svg+xml",
}


# ── AppleScript helpers ────────────────────────────────────────────────────────

def osascript(script: str, timeout: int = 6) -> str:
    result = subprocess.run(
        ["osascript", "-e", script],
        capture_output=True, text=True, timeout=timeout
    )
    return result.stdout.strip()


def now_playing() -> dict:
    script = """
tell application "Music"
    try
        set s to player state as string
        if s is "stopped" then
            return "stopped" & "|||" & "" & "|||" & "" & "|||" & "" & "|||" & "0" & "|||" & "0" & "|||" & (sound volume as string) & "|||" & "false" & "|||" & "off"
        end if
        set t to current track
        return s & "|||" & (name of t) & "|||" & (artist of t) & "|||" & (album of t) & "|||" & (duration of t as string) & "|||" & (player position as string) & "|||" & (sound volume as string) & "|||" & (shuffle enabled as string) & "|||" & (song repeat as string)
    on error
        return "stopped||||||||50|false|off"
    end try
end tell"""
    try:
        raw = osascript(script)
        p = raw.split("|||")
        return {
            "state":    p[0] if len(p) > 0 else "stopped",
            "track":    p[1] if len(p) > 1 else "",
            "artist":   p[2] if len(p) > 2 else "",
            "album":    p[3] if len(p) > 3 else "",
            "duration": float(p[4]) if len(p) > 4 and p[4] else 0,
            "position": float(p[5]) if len(p) > 5 and p[5] else 0,
            "volume":   int(p[6])   if len(p) > 6 and p[6] else 50,
            "shuffle":  p[7] == "true" if len(p) > 7 else False,
            "repeat":   p[8] if len(p) > 8 else "off",
        }
    except Exception:
        return {"state": "stopped", "track": "", "artist": "", "album": "",
                "duration": 0, "position": 0, "volume": 50, "shuffle": False, "repeat": "off"}


def get_playlists() -> list:
    script = """
tell application "Music"
    set results to {}
    repeat with p in playlists
        try
            set pName to name of p
            set pCount to count of tracks of p
            set pKind to class of p as string
            set pID to persistent ID of p
            set end of results to pName & "~~~" & (pCount as string) & "~~~" & pKind & "~~~" & pID
        end try
    end repeat
    set AppleScript's text item delimiters to "|||"
    set output to results as string
    set AppleScript's text item delimiters to ""
    return output
end tell"""
    try:
        raw = osascript(script, timeout=30)
        if not raw:
            return []
        playlists = []
        for item in raw.split("|||"):
            parts = item.split("~~~")
            if len(parts) == 4:
                name, count, kind, pid = parts
                playlists.append({
                    "name":  name,
                    "count": int(count) if count.isdigit() else 0,
                    "kind":  kind,
                    "pid":   pid,
                })
        return playlists
    except Exception:
        return []


def fetch_artwork() -> bool:
    script = f"""
tell application "Music"
    try
        set artData to data of artwork 1 of current track
        set f to open for access POSIX file "{ART_PATH}" with write permission
        set eof of f to 0
        write artData to f
        close access f
        return "ok"
    on error e
        try
            close access POSIX file "{ART_PATH}"
        end try
        return "error"
    end try
end tell"""
    try:
        result = osascript(script)
        return result == "ok" and os.path.exists(ART_PATH)
    except Exception:
        return False


# ── HTTP handler ───────────────────────────────────────────────────────────────

class Handler(BaseHTTPRequestHandler):

    def log_message(self, fmt, *args):
        print(f"  {self.address_string()} {fmt % args}")

    # ── Routing ──────────────────────────────────────────────────────────────

    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path

        if path == "/" or path == "/index.html":
            self._serve_file(os.path.join(PUBLIC_DIR, "index.html"))
        elif path == "/api/now-playing":
            self._json(now_playing())
        elif path == "/api/playlists":
            self._json(get_playlists())
        elif path == "/api/artwork":
            if fetch_artwork():
                self._send_file(ART_PATH, "image/jpeg", no_cache=True)
            else:
                self._status(404)
        elif path.startswith("/"):
            # Static files
            safe = os.path.normpath(path.lstrip("/"))
            full = os.path.join(PUBLIC_DIR, safe)
            if os.path.isfile(full):
                self._serve_file(full)
            else:
                self._status(404)

    def do_POST(self):
        path = urllib.parse.urlparse(self.path).path
        length = int(self.headers.get("Content-Length", 0))
        body = {}
        if length:
            try:
                body = json.loads(self.rfile.read(length))
            except Exception:
                pass

        try:
            if path == "/api/playpause":
                osascript('tell application "Music" to playpause')
                self._json({"ok": True})

            elif path == "/api/next":
                osascript('tell application "Music" to next track')
                self._json({"ok": True})

            elif path == "/api/previous":
                osascript('tell application "Music" to previous track')
                self._json({"ok": True})

            elif path == "/api/volume":
                vol = max(0, min(100, int(body.get("volume", 50))))
                osascript(f'tell application "Music" to set sound volume to {vol}')
                self._json({"ok": True})

            elif path == "/api/seek":
                pos = float(body.get("position", 0))
                osascript(f'tell application "Music" to set player position to {pos}')
                self._json({"ok": True})

            elif path == "/api/shuffle":
                result = osascript("""
tell application "Music"
    set shuffle enabled to (not shuffle enabled)
    return shuffle enabled as string
end tell""")
                self._json({"ok": True, "shuffle": result == "true"})

            elif path == "/api/play-playlist":
                pid = body.get("pid", "")
                if not pid:
                    self._json({"error": "pid required"}, 400)
                    return
                # Persistent IDs are hex strings — safe to embed directly
                result = osascript(f"""
tell application "Music"
    set matches to (every playlist whose persistent ID is "{pid}")
    if matches is not {{}} then
        play item 1 of matches
        return "ok"
    end if
    return "not found"
end tell""")
                if result == "ok":
                    self._json({"ok": True})
                else:
                    self._json({"error": "playlist not found"}, 404)

            elif path == "/api/repeat":
                result = osascript("""
tell application "Music"
    if song repeat is off then
        set song repeat to one
    else if song repeat is one then
        set song repeat to all
    else
        set song repeat to off
    end if
    return song repeat as string
end tell""")
                self._json({"ok": True, "repeat": result})

            else:
                self._status(404)

        except Exception as e:
            self._json({"error": str(e)}, 500)

    # ── Response helpers ──────────────────────────────────────────────────────

    def _json(self, data, code=200):
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def _status(self, code):
        self.send_response(code)
        self.end_headers()

    def _serve_file(self, path):
        ext = os.path.splitext(path)[1].lower()
        mime = MIME.get(ext, "application/octet-stream")
        self._send_file(path, mime)

    def _send_file(self, path, mime, no_cache=False):
        try:
            with open(path, "rb") as f:
                data = f.read()
            self.send_response(200)
            self.send_header("Content-Type", mime)
            self.send_header("Content-Length", str(len(data)))
            if no_cache:
                self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data)
        except FileNotFoundError:
            self._status(404)


# ── Entry point ────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", PORT), Handler)
    print(f"Apple Music Controller → http://localhost:{PORT}")
    print("Press Ctrl+C to stop.\n")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")
