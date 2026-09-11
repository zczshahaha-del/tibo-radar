"""Local state for cached snapshots and notification deduplication."""

from __future__ import annotations

import json
import os
import tempfile
from pathlib import Path
from typing import Any

from .client import default_data_dir
from .models import PredictionSnapshot


class StateStore:
    def __init__(self, data_dir: Path | None = None) -> None:
        self.data_dir = data_dir or default_data_dir()
        self.path = self.data_dir / "state.json"

    def load(self) -> dict[str, Any]:
        if not self.path.exists():
            return {}
        try:
            payload = json.loads(self.path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return {}
        return payload if isinstance(payload, dict) else {}

    def save(self, payload: dict[str, Any]) -> None:
        self.data_dir.mkdir(parents=True, exist_ok=True)
        handle, temp_name = tempfile.mkstemp(prefix=".state-", suffix=".json", dir=self.data_dir)
        try:
            with os.fdopen(handle, "w", encoding="utf-8") as stream:
                json.dump(payload, stream, ensure_ascii=False, indent=2)
            os.replace(temp_name, self.path)
        finally:
            if os.path.exists(temp_name):
                os.unlink(temp_name)

    def notification_for(
        self, snapshot: PredictionSnapshot, threshold: int, notify_first: bool = False
    ) -> tuple[str, str] | None:
        state = self.load()
        previous_probability = state.get("combined_24h")
        previous_event_ids = set(state.get("event_ids") or [])
        current_event_ids = [event.event_id for event in snapshot.latest_events]
        first_run = previous_probability is None

        title: str | None = None
        body: str | None = None
        if not first_run:
            new_events = [
                event for event in snapshot.latest_events
                if event.event_id not in previous_event_ids
                and event.kind in {"reset", "credits"}
            ]
            if new_events:
                newest = new_events[0]
                title = "Tibo Radar：发现新的重置信号"
                body = newest.title[:180]
            elif (
                isinstance(previous_probability, (int, float))
                and previous_probability < threshold <= snapshot.combined_24h
            ):
                title = f"Tibo Radar：24 小时概率升至 {snapshot.combined_24h}%"
                reason = snapshot.evidence[-1].detail if snapshot.evidence else snapshot.level_label
                body = f"{reason} 最可能时段：{snapshot.likely_window}"
        elif notify_first and snapshot.combined_24h >= threshold:
            title = f"Tibo Radar：当前概率 {snapshot.combined_24h}%"
            body = f"已达到提醒阈值 {threshold}%。{snapshot.likely_window}"

        self.save(
            {
                "generated_at": snapshot.generated_at,
                "combined_24h": snapshot.combined_24h,
                "event_ids": current_event_ids,
                "last_snapshot": snapshot.to_dict(),
            }
        )
        return (title, body) if title and body else None

