"""Explainable probability model for goodwill resets and banked resets."""

from __future__ import annotations

import math
import re
from datetime import datetime, timedelta, timezone
from typing import Any, Iterable
from zoneinfo import ZoneInfo

from .client import SourceBundle
from .models import Evidence, PredictionSnapshot, RadarEvent


BEIJING = ZoneInfo("Asia/Shanghai")
UTC = timezone.utc
DIRECT_FUTURE = re.compile(
    r"\b(will|tomorrow|later today|next hour|within (?:an? )?hour|lands? (?:at|around|by)|soon)\b",
    re.IGNORECASE,
)
RESET_WORDS = re.compile(r"\b(reset|reseting|resetting|banked reset)\b", re.IGNORECASE)
GLOBAL_WORDS = re.compile(
    r"\b(all paid|all users|everyone|every codex|every .* user|global)\b",
    re.IGNORECASE,
)
TARGETED_WORDS = re.compile(
    r"affected|eligible|some users|some plus|who used one|without access",
    re.IGNORECASE,
)
TEASER_WORDS = re.compile(
    r"hold on to your codex|burn (?:as much )?usage|you know what.s coming|who says it won.t reset|new milestone",
    re.IGNORECASE,
)
COMPLETED_WORDS = re.compile(
    r"all reset|have reset|has been reset|reset propagated|it is done|reset for everyone",
    re.IGNORECASE,
)


def parse_time(value: Any) -> datetime | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=UTC)
    return parsed.astimezone(UTC)


def clamp_probability(value: float) -> int:
    return max(1, min(99, round(value)))


def union_probability(first: int, second: int) -> int:
    result = 1 - (1 - first / 100) * (1 - second / 100)
    return clamp_probability(result * 100)


def _freshness_time(payloads: Iterable[dict[str, Any]]) -> datetime | None:
    candidates: list[datetime] = []
    for payload in payloads:
        for key in ("updated_at", "fetched_at", "checked_at", "newest_post_at"):
            parsed = parse_time(payload.get(key))
            if parsed:
                candidates.append(parsed)
    return max(candidates) if candidates else None


def _event_time(event: dict[str, Any]) -> datetime | None:
    for key in ("effective_at", "announced_at", "observed_at", "date"):
        parsed = parse_time(event.get(key))
        if parsed:
            return parsed
    return None


def _likely_window(forecast: dict[str, Any]) -> str:
    time_window = forecast.get("time_window") or {}
    start = time_window.get("start_hour")
    end = time_window.get("end_hour")
    timezone = time_window.get("timezone")
    if not isinstance(start, int) or not isinstance(end, int) or timezone != "UTC":
        return "北京时间凌晨至上午（历史高发段）"
    anchor = datetime(2026, 1, 1, start, tzinfo=UTC).astimezone(BEIJING)
    end_anchor = datetime(2026, 1, 1, end, tzinfo=UTC).astimezone(BEIJING)
    return f"北京时间 {anchor:%H}:00–{end_anchor:%H}:00"


def _latest_events(events: list[dict[str, Any]], limit: int = 5) -> list[RadarEvent]:
    ordered = sorted(events, key=lambda event: _event_time(event) or datetime.min.replace(tzinfo=UTC), reverse=True)
    output: list[RadarEvent] = []
    seen: set[str] = set()
    for event in ordered:
        event_id = str(event.get("id") or "")
        if not event_id or event_id in seen:
            continue
        seen.add(event_id)
        text = str(event.get("text") or event.get("summary") or "").strip()
        if not text:
            continue
        output.append(
            RadarEvent(
                event_id=event_id,
                kind=str(event.get("group") or event.get("type") or "signal"),
                title=text,
                occurred_at=(_event_time(event) or None).isoformat() if _event_time(event) else None,
                source_url=event.get("url") or event.get("source_url"),
                state=event.get("banked_state") or event.get("announcement_state"),
            )
        )
        if len(output) >= limit:
            break
    return output


class Predictor:
    """Blend a calibrated public baseline with small, visible event modifiers."""

    def predict(
        self, bundle: SourceBundle, now: datetime | None = None
    ) -> PredictionSnapshot:
        now = (now or datetime.now(UTC)).astimezone(UTC)
        forecast = bundle.payloads.get("forecast", {})
        timeline = bundle.payloads.get("timeline", {})
        status = bundle.payloads.get("status", {})
        openai_status = bundle.payloads.get("openai_status", {})
        events = list(timeline.get("events") or [])

        probabilities = forecast.get("probabilities") or {}
        global_24 = float(probabilities.get("rounded_24h") or 24)
        global_48 = float(probabilities.get("rounded_48h") or 43)
        banked_24 = 8.0
        banked_48 = 15.0
        affected_user_banked: int | None = None
        evidence: list[Evidence] = []

        cadence = forecast.get("cadence") or {}
        median_days = cadence.get("recent_median_days")
        age_days = forecast.get("age_days")
        if isinstance(median_days, (int, float)) and isinstance(age_days, (int, float)):
            evidence.append(
                Evidence(
                    "历史节奏",
                    f"距上次重置 {age_days:.1f} 天；近期典型间隔 {median_days:.1f} 天。",
                    "baseline",
                    0,
                    "https://codex-reset.com/timeline",
                )
            )

        last_reset = parse_time(forecast.get("last_reset_at"))
        if last_reset and now - last_reset < timedelta(hours=24):
            global_24 -= 8
            global_48 -= 4
            evidence.append(Evidence("重置冷却", "上次全局重置不足 24 小时。", "negative", -8))

        post_reset_events = [
            event for event in events
            if (_event_time(event) and (not last_reset or _event_time(event) > last_reset))
        ]
        post_reset_events.sort(key=lambda event: _event_time(event) or now, reverse=True)

        explicit_future: dict[str, Any] | None = None
        strong_teaser: dict[str, Any] | None = None
        latest_banked: dict[str, Any] | None = None
        for event in post_reset_events:
            text = str(event.get("text") or event.get("summary") or "")
            kind = str(event.get("group") or event.get("type") or "")
            if kind == "credits" and latest_banked is None:
                latest_banked = event
            if (
                kind == "reset"
                and RESET_WORDS.search(text)
                and DIRECT_FUTURE.search(text)
                and not COMPLETED_WORDS.search(text)
                and explicit_future is None
            ):
                explicit_future = event
            elif TEASER_WORDS.search(text) and strong_teaser is None:
                strong_teaser = event

        if explicit_future:
            text = str(explicit_future.get("text") or explicit_future.get("summary") or "")
            floor = 88 if GLOBAL_WORDS.search(text) else 72
            global_24 = max(global_24, floor)
            global_48 = max(global_48, min(96, floor + 7))
            evidence.append(
                Evidence(
                    "Tibo 明确预告",
                    text[:180],
                    "positive",
                    floor,
                    explicit_future.get("url"),
                )
            )
        elif strong_teaser:
            global_24 += 18
            global_48 += 12
            evidence.append(
                Evidence(
                    "Tibo 强暗示",
                    str(strong_teaser.get("text") or strong_teaser.get("summary") or "")[:180],
                    "positive",
                    18,
                    strong_teaser.get("url"),
                )
            )

        if latest_banked:
            text = str(latest_banked.get("text") or latest_banked.get("summary") or "")
            occurred_at = _event_time(latest_banked)
            recent = occurred_at is not None and now - occurred_at <= timedelta(hours=48)
            targeted = bool(TARGETED_WORDS.search(text))
            broad = bool(GLOBAL_WORDS.search(text)) and not targeted
            state = str(latest_banked.get("banked_state") or "")
            if recent and targeted:
                affected_user_banked = 94
                evidence.append(
                    Evidence(
                        "定向补发",
                        "Tibo 已承诺补发给故障时段内受影响的用户；这不会提高普发概率。",
                        "targeted",
                        0,
                        latest_banked.get("url"),
                    )
                )
            elif recent and broad and state in {"announced", "arriving"}:
                banked_24 = max(banked_24, 94)
                banked_48 = max(banked_48, 98)
                evidence.append(
                    Evidence(
                        "重置卡已预告",
                        text[:180],
                        "positive",
                        86,
                        latest_banked.get("url"),
                    )
                )
            elif recent and broad:
                banked_24 = max(banked_24, 72)
                banked_48 = max(banked_48, 84)

        incident = self._recent_incident(openai_status, status, now)
        if incident:
            active = str(incident.get("status")) not in {"resolved", "postmortem", "completed"}
            delta = 12 if active else 5
            global_24 += delta
            global_48 += max(3, delta - 4)
            evidence.append(
                Evidence(
                    "Codex 状态事件",
                    str(incident.get("name") or "近期 Codex 服务异常"),
                    "positive" if active else "context",
                    delta,
                    incident.get("shortlink") or incident.get("source_url"),
                )
            )

        global_24_i = clamp_probability(global_24)
        global_48_i = max(global_24_i, clamp_probability(global_48))
        banked_24_i = clamp_probability(banked_24)
        banked_48_i = max(banked_24_i, clamp_probability(banked_48))
        combined_24 = union_probability(global_24_i, banked_24_i)
        combined_48 = max(combined_24, union_probability(global_48_i, banked_48_i))

        if combined_24 >= 85:
            level, label = "red", "很可能"
        elif combined_24 >= 65:
            level, label = "orange", "高关注"
        elif combined_24 >= 45:
            level, label = "yellow", "开始关注"
        else:
            level, label = "green", "正常使用"

        data_updated = _freshness_time(bundle.payloads.values())
        stale = bool(bundle.cache_fallbacks)
        if data_updated and now - data_updated > timedelta(hours=4):
            stale = True

        confidence = str(forecast.get("confidence") or "low")
        if explicit_future or banked_24_i >= 90:
            confidence = "high"
        elif stale:
            confidence = "low"
        confidence_note = str(
            forecast.get("confidence_note")
            or "历史样本较少，概率只用于安排用量。"
        )
        if stale:
            confidence_note = "部分数据来自缓存；请把当前概率视为低置信度。"

        return PredictionSnapshot(
            generated_at=now.isoformat(),
            global_24h=global_24_i,
            global_48h=global_48_i,
            banked_24h=banked_24_i,
            banked_48h=banked_48_i,
            combined_24h=combined_24,
            combined_48h=combined_48,
            affected_user_banked_24h=affected_user_banked,
            confidence=confidence,
            confidence_note=confidence_note,
            level=level,
            level_label=label,
            likely_window=_likely_window(forecast),
            last_reset_at=last_reset.isoformat() if last_reset else None,
            data_updated_at=data_updated.isoformat() if data_updated else None,
            stale=stale,
            evidence=evidence[:6],
            latest_events=_latest_events(events),
            source_errors=bundle.errors,
        )

    @staticmethod
    def _recent_incident(
        openai_status: dict[str, Any], fallback_status: dict[str, Any], now: datetime
    ) -> dict[str, Any] | None:
        incidents = list(openai_status.get("incidents") or [])
        incidents.extend(fallback_status.get("incidents") or [])
        candidates: list[tuple[datetime, dict[str, Any]]] = []
        seen: set[str] = set()
        for incident in incidents:
            incident_id = str(incident.get("id") or "")
            if incident_id in seen:
                continue
            seen.add(incident_id)
            text = f"{incident.get('name', '')} {incident.get('body', '')}".lower()
            codex_related = incident.get("codex_related") is True or any(
                term in text for term in ("codex", "work mode", "usage limit")
            )
            if not codex_related:
                continue
            at = parse_time(
                incident.get("resolved_at")
                or incident.get("updated_at")
                or incident.get("started_at")
            )
            if at and now - at <= timedelta(hours=36):
                candidates.append((at, incident))
        if not candidates:
            return None
        candidates.sort(key=lambda item: item[0], reverse=True)
        return candidates[0][1]
