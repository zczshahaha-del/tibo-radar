"""Local dashboard server."""

from __future__ import annotations

import json
import mimetypes
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from importlib.resources import files
from urllib.parse import urlparse

from .service import RadarService


STATIC_ROOT = files("tibo_radar").joinpath("static")


class DashboardHandler(BaseHTTPRequestHandler):
    service = RadarService()

    def do_GET(self) -> None:  # noqa: N802 - stdlib handler API
        path = urlparse(self.path).path
        if path == "/api/snapshot":
            self._serve_snapshot(force=False)
            return
        if path == "/api/refresh":
            self._serve_snapshot(force=True)
            return
        if path == "/healthz":
            self._send_bytes(b"ok\n", "text/plain; charset=utf-8")
            return
        asset = "index.html" if path in {"", "/"} else path.lstrip("/")
        if "/" in asset or asset.startswith("."):
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        resource = STATIC_ROOT.joinpath(asset)
        try:
            content = resource.read_bytes()
        except (FileNotFoundError, IsADirectoryError):
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        mime = mimetypes.guess_type(asset)[0] or "application/octet-stream"
        if mime.startswith("text/") or mime in {"application/javascript", "application/json"}:
            mime += "; charset=utf-8"
        self._send_bytes(content, mime)

    def _serve_snapshot(self, force: bool) -> None:
        try:
            snapshot = self.service.snapshot(force=force)
            raw = json.dumps(snapshot.to_dict(), ensure_ascii=False).encode("utf-8")
            self._send_bytes(raw, "application/json; charset=utf-8", no_store=True)
        except Exception as exc:  # keep the dashboard useful when a source changes
            raw = json.dumps(
                {"error": "暂时无法生成预测", "detail": str(exc)}, ensure_ascii=False
            ).encode("utf-8")
            self._send_bytes(
                raw,
                "application/json; charset=utf-8",
                status=HTTPStatus.SERVICE_UNAVAILABLE,
                no_store=True,
            )

    def _send_bytes(
        self,
        content: bytes,
        content_type: str,
        status: HTTPStatus = HTTPStatus.OK,
        no_store: bool = False,
    ) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(content)))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Security-Policy", "default-src 'self'; connect-src 'self'; style-src 'self'; script-src 'self'; img-src 'self' data:")
        if no_store:
            self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(content)

    def log_message(self, format: str, *args: object) -> None:
        return


def run_server(host: str = "127.0.0.1", port: int = 8765) -> None:
    server = ThreadingHTTPServer((host, port), DashboardHandler)
    print(f"Tibo Radar 已启动：http://{host}:{port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()

