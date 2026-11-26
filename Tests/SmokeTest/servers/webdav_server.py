#!/usr/bin/env python3
"""Minimal read-only WebDAV (class 1) server for the AetherTV smoke test.

Usage: webdav_server.py HOST PORT ROOT USER PASSWORD

Serves ROOT over HTTP with Basic auth (pass an empty USER to serve without
auth). Answers PROPFIND (Depth 0 and 1), GET and HEAD, including single-range
requests, which is what a WebDAV browser and the player's byte-range reader
need. Every request is logged to stderr.
"""
import base64
import os
import sys
import time
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from xml.sax.saxutils import escape

CONTENT_TYPES = {
    ".mp4": "video/mp4",
    ".mkv": "video/x-matroska",
    ".m3u8": "application/vnd.apple.mpegurl",
    ".ts": "video/mp2t",
    ".srt": "text/plain; charset=utf-8",
    ".ass": "text/plain; charset=utf-8",
}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "AetherTVSmokeWebDAV/1.0"
    root = "/"
    user = None
    password = None

    # ---------------------------------------------------------------- helpers

    def authorized(self):
        if not self.user:
            return True
        header = self.headers.get("Authorization", "")
        expected = "Basic " + base64.b64encode(f"{self.user}:{self.password}".encode("utf-8")).decode("ascii")
        if header == expected:
            return True
        self.send_response(401)
        self.send_header("WWW-Authenticate", 'Basic realm="AetherTVSmokeTest"')
        self.send_header("Content-Length", "0")
        self.end_headers()
        return False

    def request_path(self):
        """(decoded path, exists, is_dir, filesystem path) for the URL in self.path."""
        relative = urllib.parse.unquote(urllib.parse.urlsplit(self.path).path)
        if "\x00" in relative or "\\" in relative:
            return relative, False, False, None
        full = os.path.normpath(self.root.rstrip("/") + relative)
        inside = full == os.path.normpath(self.root) or full.startswith(os.path.normpath(self.root) + os.sep)
        if not inside:
            return relative, False, False, None
        return relative, os.path.exists(full), os.path.isdir(full), full

    def send_empty(self, status):
        self.send_response(status)
        self.send_header("Content-Length", "0")
        self.end_headers()

    # ----------------------------------------------------------------- verbs

    def do_HEAD(self):
        self.serve(send_body=False)

    def do_GET(self):
        self.serve(send_body=True)

    def serve(self, send_body):
        if not self.authorized():
            return
        relative, exists, is_dir, full = self.request_path()
        if not exists or is_dir:
            self.send_empty(404 if not exists else 403)
            return

        size = os.path.getsize(full)
        start, end, status = 0, size - 1, 200
        range_header = self.headers.get("Range")
        if range_header and range_header.startswith("bytes=") and "," not in range_header:
            first, _, last = range_header[6:].partition("-")
            try:
                if first:
                    start, end = int(first), int(last) if last else size - 1
                else:
                    start, end = max(0, size - int(last)), size - 1   # "bytes=-N" means the last N bytes
            except ValueError:
                start, end, status = 0, size - 1, 200   # not a range we understand: serve the whole file
            if start >= size or start > end:
                self.send_response(416)
                self.send_header("Content-Range", f"bytes */{size}")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            end = min(end, size - 1)
            status = 206

        self.send_response(status)
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Type", CONTENT_TYPES.get(os.path.splitext(full)[1].lower(), "application/octet-stream"))
        self.send_header("Content-Length", str(end - start + 1))
        self.send_header("Last-Modified", self.date_time_string(int(os.path.getmtime(full))))
        self.send_header("ETag", f'"{size:x}-{int(os.path.getmtime(full)):x}"')
        if status == 206:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        if send_body:
            with open(full, "rb") as handle:
                handle.seek(start)
                remaining = end - start + 1
                while remaining > 0:
                    chunk = handle.read(min(256 * 1024, remaining))
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    remaining -= len(chunk)

    def do_PROPFIND(self):
        if not self.authorized():
            return
        relative, exists, is_dir, full = self.request_path()
        if not exists or not is_dir:
            self.send_empty(404)
            return
        depth = self.headers.get("Depth", "1")
        names = sorted(os.listdir(full)) if depth != "0" else []
        self.send_multi_status([relative] + [
            relative.rstrip("/") + "/" + name for name in names
        ], is_dir=lambda path: path == relative or os.path.isdir(os.path.join(full, path.rsplit("/", 1)[-1])))

    def send_multi_status(self, paths, is_dir):
        parts = []
        for path in paths:
            directory = is_dir(path)
            name = path.rstrip("/").rsplit("/", 1)[-1]
            full = os.path.normpath(self.root.rstrip("/") + path)
            mtime = time.strftime("%a, %d %b %Y %H:%M:%S GMT", time.gmtime(os.path.getmtime(full)))
            props = [f"<D:displayname>{escape(name)}</D:displayname>",
                     "<D:resourcetype>" + ("<D:collection/>" if directory else "") + "</D:resourcetype>",
                     f"<D:getlastmodified>{mtime}</D:getlastmodified>"]
            if not directory:
                size = os.path.getsize(full)
                props.append(f"<D:getcontentlength>{size}</D:getcontentlength>")
                props.append("<D:getcontenttype>%s</D:getcontenttype>" % CONTENT_TYPES.get(os.path.splitext(full)[1].lower(), "application/octet-stream"))
                props.append(f"<D:getetag>&quot;{size:x}-{int(os.path.getmtime(full)):x}&quot;</D:getetag>")
            href = urllib.parse.quote(path if path.endswith("/") or not directory else path + "/", safe="/")
            if directory and not href.endswith("/"):
                href += "/"
            parts.append("<D:response><D:href>%s</D:href><D:propstat><D:prop>%s</D:prop>"
                         "<D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>" % (href, "".join(props)))
        body = ('<?xml version="1.0" encoding="utf-8"?>\n<D:multistatus xmlns:D="DAV:">' + "".join(parts) + "</D:multistatus>").encode("utf-8")
        self.send_response(207)
        self.send_header("Content-Type", 'application/xml; charset="utf-8"')
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("DAV", "1")
        self.send_header("Allow", "OPTIONS, GET, HEAD, PROPFIND")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (time.strftime("%H:%M:%S"), fmt % args))
        sys.stderr.flush()


def main(argv):
    if len(argv) != 6:
        sys.exit(__doc__)
    host, port, root, user, password = argv[1], int(argv[2]), os.path.abspath(argv[3]), argv[4], argv[5]
    Handler.root = root
    Handler.user = user or None
    Handler.password = password
    server = ThreadingHTTPServer((host, port), Handler)
    server.daemon_threads = True
    sys.stderr.write(f"webdav: serving {root} on http://{host}:{port}/ (auth {'on' if user else 'off'})\n")
    sys.stderr.flush()
    server.serve_forever()


if __name__ == "__main__":
    main(sys.argv)
