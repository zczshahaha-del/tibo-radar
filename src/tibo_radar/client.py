"""Small resilient client for public reset and status data."""

from __future__ import annotations

import json
import os
import tempfile
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


SOURCE_URLS = {
    "forecast": "https://codex-reset.com/api/forecast",
    "timeline": "https://codex-reset.com/api/timeline",
    "feed": "https://codex-reset.com/api/feed",
    "status": "https://codex-reset.com/api/status-history",
    "openai_status": "https://status.openai.com/api/v2/incidents.json",
}


def default_data_dir() -> Path:
    override = os.environ.get("TIBO_RADAR_DATA_DIR")
    if override:
        return Path(override).expanduser()
    return Path.home() / "Library" / "Application Support" / "TiboRadar"


@dataclass
class SourceBundle:
    payloads: dict[str, dict[str, Any]]
    cache_fallbacks: set[str]
    errors: list[str]


class RadarClient:
    def __init__(self, cache_dir: Path | None = None, timeout: float = 12.0) -> None:
        self.cache_dir = cache_dir or default_data_dir()
        self.timeout = timeout

    def fetch_all(self) -> SourceBundle:
        payloads: dict[str, dict[str, Any]] = {}
        cache_fallbacks: set[str] = set()
        errors: list[str] = []

        with ThreadPoolExecutor(max_workers=len(SOURCE_URLS)) as pool:
            futures = {
                pool.submit(self._fetch_one, name, url): name
                for name, url in SOURCE_URLS.items()
            }
            for future in as_completed(futures):
                name = futures[future]
                try:
                    payload, from_cache, error = future.result()
                except Exception as exc:  # defensive boundary around public sources
                    payload, from_cache, error = {}, False, f"{name}: {exc}"
                if payload:
                    payloads[name] = payload
                if from_cache:
                    cache_fallbacks.add(name)
                if error:
                    errors.append(error)

        return SourceBundle(payloads, cache_fallbacks, sorted(errors))

    def _fetch_one(
        self, name: str, url: str
    ) -> tuple[dict[str, Any], bool, str | None]:
        request = Request(
            url,
            headers={
                "Accept": "application/json",
                "User-Agent": "TiboRadar/0.1 (+local personal monitor)",
            },
        )
        try:
            with urlopen(request, timeout=self.timeout) as response:
                raw = response.read()
            payload = json.loads(raw)
            if not isinstance(payload, dict):
                raise ValueError("response is not a JSON object")
            self._write_cache(name, payload)
            return payload, False, None
        except (HTTPError, URLError, TimeoutError, ValueError, json.JSONDecodeError) as exc:
            cached = self._read_cache(name)
            if cached is not None:
                return cached, True, f"{name}: 网络失败，正在使用缓存（{exc}）"
            return {}, False, f"{name}: 无法获取且没有缓存（{exc}）"

    def _cache_path(self, name: str) -> Path:
        return self.cache_dir / f"{name}.json"

    def _write_cache(self, name: str, payload: dict[str, Any]) -> None:
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        target = self._cache_path(name)
        handle, temp_name = tempfile.mkstemp(
            prefix=f".{name}-", suffix=".json", dir=self.cache_dir
        )
        try:
            with os.fdopen(handle, "w", encoding="utf-8") as stream:
                json.dump(payload, stream, ensure_ascii=False, separators=(",", ":"))
            os.replace(temp_name, target)
        finally:
            if os.path.exists(temp_name):
                os.unlink(temp_name)

    def _read_cache(self, name: str) -> dict[str, Any] | None:
        path = self._cache_path(name)
        if not path.exists():
            return None
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return None
        return payload if isinstance(payload, dict) else None
