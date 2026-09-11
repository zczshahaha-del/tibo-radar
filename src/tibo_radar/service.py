"""Application service joining collection, prediction and persistence."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from threading import Lock

from .client import RadarClient
from .models import PredictionSnapshot
from .predictor import Predictor


UTC = timezone.utc


class RadarService:
    def __init__(self, client: RadarClient | None = None, ttl_seconds: int = 120) -> None:
        self.client = client or RadarClient()
        self.predictor = Predictor()
        self.ttl = timedelta(seconds=ttl_seconds)
        self._lock = Lock()
        self._snapshot: PredictionSnapshot | None = None

    def snapshot(self, force: bool = False) -> PredictionSnapshot:
        with self._lock:
            now = datetime.now(UTC)
            if self._snapshot and not force:
                generated = datetime.fromisoformat(self._snapshot.generated_at)
                if now - generated < self.ttl:
                    return self._snapshot
            bundle = self.client.fetch_all()
            self._snapshot = self.predictor.predict(bundle, now)
            return self._snapshot
