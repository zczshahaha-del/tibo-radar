from __future__ import annotations

import unittest
from datetime import datetime, timezone

from tibo_radar.client import SourceBundle
from tibo_radar.predictor import Predictor


UTC = timezone.utc
NOW = datetime(2026, 9, 10, 12, 0, tzinfo=UTC)


def bundle_with(events: list[dict], incidents: list[dict] | None = None) -> SourceBundle:
    return SourceBundle(
        payloads={
            "forecast": {
                "probabilities": {"rounded_24h": 27, "rounded_48h": 47},
                "last_reset_at": "2026-09-08T04:05:53Z",
                "age_days": 2.3,
                "cadence": {"recent_median_days": 2.1},
                "confidence": "low",
                "time_window": {"start_hour": 23, "end_hour": 2, "timezone": "UTC"},
                "updated_at": "2026-09-10T11:55:00Z",
            },
            "timeline": {"events": events, "updated_at": "2026-09-10T11:55:00Z"},
            "openai_status": {"incidents": incidents or []},
        },
        cache_fallbacks=set(),
        errors=[],
    )


class PredictorTests(unittest.TestCase):
    def test_targeted_compensation_does_not_inflate_broad_banked_probability(self) -> None:
        event = {
            "id": "credits-targeted",
            "group": "credits",
            "text": "Banked resets are arriving for affected users without access.",
            "announced_at": "2026-09-09T20:00:00Z",
            "banked_state": "arriving",
        }

        snapshot = Predictor().predict(bundle_with([event]), NOW)

        self.assertEqual(snapshot.banked_24h, 8)
        self.assertEqual(snapshot.affected_user_banked_24h, 94)
        self.assertTrue(any(item.category == "targeted" for item in snapshot.evidence))

    def test_explicit_global_future_reset_is_high_probability(self) -> None:
        event = {
            "id": "global-future",
            "group": "reset",
            "text": "All paid Codex users will reset tomorrow.",
            "announced_at": "2026-09-10T10:00:00Z",
        }

        snapshot = Predictor().predict(bundle_with([event]), NOW)

        self.assertGreaterEqual(snapshot.global_24h, 88)
        self.assertGreaterEqual(snapshot.global_48h, snapshot.global_24h)
        self.assertEqual(snapshot.confidence, "high")

    def test_broad_banked_announcement_is_not_mixed_into_global_reset(self) -> None:
        event = {
            "id": "banked-global",
            "group": "credits",
            "text": "Banked reset credits are arriving for everyone.",
            "announced_at": "2026-09-10T10:00:00Z",
            "banked_state": "arriving",
        }

        snapshot = Predictor().predict(bundle_with([event]), NOW)

        self.assertEqual(snapshot.global_24h, 27)
        self.assertEqual(snapshot.banked_24h, 94)
        self.assertGreater(snapshot.combined_24h, 94)

    def test_recent_resolved_codex_incident_is_a_small_modifier(self) -> None:
        incident = {
            "id": "incident-1",
            "name": "Investigating unexpected Codex usage limit resets",
            "status": "resolved",
            "resolved_at": "2026-09-10T08:00:00Z",
        }

        snapshot = Predictor().predict(bundle_with([], [incident]), NOW)

        self.assertEqual(snapshot.global_24h, 32)
        self.assertTrue(any(item.label == "Codex 状态事件" for item in snapshot.evidence))


if __name__ == "__main__":
    unittest.main()
