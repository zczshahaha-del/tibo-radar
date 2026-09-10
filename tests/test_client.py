from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from urllib.error import URLError

from tibo_radar.client import RadarClient


class RadarClientTests(unittest.TestCase):
    def test_network_failure_falls_back_to_cached_payload(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            client = RadarClient(Path(directory))
            client._write_cache("forecast", {"updated_at": "2026-09-10T00:00:00Z"})

            with patch("tibo_radar.client.urlopen", side_effect=URLError("offline")):
                payload, from_cache, error = client._fetch_one(
                    "forecast", "https://example.invalid/forecast"
                )

            self.assertEqual(payload["updated_at"], "2026-09-10T00:00:00Z")
            self.assertTrue(from_cache)
            self.assertIn("正在使用缓存", error or "")


if __name__ == "__main__":
    unittest.main()
