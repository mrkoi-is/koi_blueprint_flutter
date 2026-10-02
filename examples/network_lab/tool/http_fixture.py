#!/usr/bin/env python3
"""Owned local HTTP fixture. No public endpoints or user files are touched."""
import argparse
import base64
import hashlib
import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

DATA = bytes(range(256)) * 8192
DIGEST = hashlib.sha256(DATA).hexdigest()
IMAGE = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEUlEQVR4nGNgSDkBQidSQAgAIN4EsaJdpP4AAAAASUVORK5CYII=")
COUNTERS = {"started": 0, "completed": 0, "aborted": 0, "bytes": 0,
            "active": 0, "peakActive": 0}
LOCK = threading.Lock()

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def _headers(self, status, length=0, extra=None):
        self.send_response(status)
        self.send_header("Content-Length", str(length))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Range, If-Range, Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, HEAD, OPTIONS")
        self.send_header("Access-Control-Expose-Headers", "Content-Length, Content-Range, ETag, Accept-Ranges")
        for key, value in (extra or {}).items():
            self.send_header(key, str(value))
        self.end_headers()

    def do_OPTIONS(self):
        self._headers(204)

    def do_HEAD(self):
        self._serve(head=True)

    def do_GET(self):
        self._serve(head=False)

    def _serve(self, head):
        path = urlparse(self.path)
        query = parse_qs(path.query)
        mode = query.get("mode", [""])[0]
        if path.path == "/health":
            self._headers(204)
            return
        if path.path == "/metrics":
            with LOCK:
                if query.get("resetPeak") == ["true"]:
                    COUNTERS["peakActive"] = COUNTERS["active"]
                value = json.dumps(COUNTERS).encode()
            self._headers(200, len(value), {"Content-Type": "application/json"})
            if not head:
                self.wfile.write(value)
            return
        if path.path == "/catalog":
            q = query.get("q", [""])[0]
            time.sleep(min(float(query.get("delay", ["0.03"])[0]), 2))
            offset = int(query.get("cursor", ["0"])[0])
            items = [{"id": str(i), "label": f"{q} item {i}"} for i in range(24)] if q else []
            value = json.dumps({"items": items[offset:offset+5], "nextCursor": str(offset+5) if offset+5<len(items) else None, "total":len(items)}).encode()
            self._headers(403 if q == "forbidden" else 200, len(value), {"Content-Type":"application/json"})
            if not head:
                try:
                    self.wfile.write(value)
                except (BrokenPipeError, ConnectionResetError):
                    pass
            return
        if path.path == "/image":
            status = int(mode) if mode in ("403", "404") else 200
            value = b"invalid image" if mode == "corrupt" else IMAGE
            self._headers(status, len(value), {"Content-Type": "image/png"})
            if not head:
                try:
                    self.wfile.write(value)
                except (BrokenPipeError, ConnectionResetError):
                    pass
            return
        if path.path != "/file":
            self._headers(404)
            return
        tag = '"fixture-v1"' if head or mode != "changed" else '"fixture-v2"'
        extra = {"ETag": tag, "Accept-Ranges": "none" if mode == "plain" else "bytes", "Content-Type":"application/octet-stream"}
        if head:
            self._headers(200, len(DATA), extra)
            return
        begin, end = 0, len(DATA)-1
        status = 200
        if self.headers.get("Range") and mode != "plain":
            begin_text, end_text = self.headers["Range"].removeprefix("bytes=").split("-", 1)
            begin, end = int(begin_text), min(int(end_text) if end_text else end, end)
            if begin > end:
                self._headers(416)
                return
            status = 206
            extra["Content-Range"] = f"bytes {begin + (1 if mode == 'wrong' else 0)}-{end}/{len(DATA)}"
        payload = DATA[begin:end+1]
        self._headers(status, len(payload), extra)
        with LOCK:
            COUNTERS["started"] += 1
            COUNTERS["active"] += 1
            COUNTERS["peakActive"] = max(COUNTERS["peakActive"], COUNTERS["active"])
        try:
            stop = len(payload)//2 if mode == "short" else len(payload)
            for offset in range(0, stop, 8192):
                time.sleep(0.004)
                block = payload[offset:min(offset+8192,stop)]
                self.wfile.write(block)
                self.wfile.flush()
                with LOCK:
                    COUNTERS["bytes"] += len(block)
            if mode == "short":
                self.close_connection = True
            else:
                with LOCK:
                    COUNTERS["completed"] += 1
        except (BrokenPipeError, ConnectionResetError):
            with LOCK:
                COUNTERS["aborted"] += 1
        finally:
            with LOCK:
                COUNTERS["active"] -= 1

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(json.dumps({"url":f"http://{args.host}:{server.server_port}/", "sha256":DIGEST,"size":len(DATA)}), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
