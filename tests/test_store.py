from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from tibo_radar.models import PredictionSnapshot, RadarEvent
from tibo_radar.store import StateStore


def snapshot(probability: int, events: list[RadarEvent] | None = None) -> PredictionSnapshot:
    return PredictionSnapshot(
        generated_at="2026-09-10T12:00:00+00:00",
        global_24h=probability,
        global_48h=probability,
        banked_24h=8,
        banked_48h=15,
        combined_24h=probability,
        combined_48h=probability,
        affected_user_banked_24h=None,
        confidence="low",
        confidence_note="test",
        level="green",
        level_label="正常使用",
        likely_window="北京时间 07:00–10:00",
        last_reset_at=None,
        data_updated_at=None,
        stale=False,
        evidence=[],
        latest_events=events or [],
        source_errors=[],
    )


class StateStoreTests(unittest.TestCase):
    def test_first_run_is_silent_then_threshold_crossing_notifies(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            store = StateStore(Path(directory))
            self.assertIsNone(store.notification_for(snapshot(50), threshold=65))

            decision = store.notification_for(snapshot(70), threshold=65)

            self.assertIsNotNone(decision)
            self.assertIn("70%", decision[0])

    def test_new_reset_event_notifies_only_once(self) -> None:
        event = RadarEvent("new-reset", "reset", "Reset tomorrow", None)
        with tempfile.TemporaryDirectory() as directory:
            store = StateStore(Path(directory))
            store.notification_for(snapshot(40), threshold=65)

            decision = store.notification_for(snapshot(40, [event]), threshold=65)
            repeated = store.notification_for(snapshot(40, [event]), threshold=65)

            self.assertIsNotNone(decision)
            self.assertIsNone(repeated)


if __name__ == "__main__":
    unittest.main()
