"""Serializable data models used by the predictor and user interfaces."""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Any


@dataclass
class Evidence:
    label: str
    detail: str
    category: str = "context"
    delta: int = 0
    source_url: str | None = None


@dataclass
class RadarEvent:
    event_id: str
    kind: str
    title: str
    occurred_at: str | None
    source_url: str | None = None
    state: str | None = None


@dataclass
class PredictionSnapshot:
    generated_at: str
    global_24h: int
    global_48h: int
    banked_24h: int
    banked_48h: int
    combined_24h: int
    combined_48h: int
    affected_user_banked_24h: int | None
    confidence: str
    confidence_note: str
    level: str
    level_label: str
    likely_window: str
    last_reset_at: str | None
    data_updated_at: str | None
    stale: bool
    evidence: list[Evidence] = field(default_factory=list)
    latest_events: list[RadarEvent] = field(default_factory=list)
    source_errors: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)
