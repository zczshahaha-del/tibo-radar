"""Command line entry point for Tibo Radar."""

from __future__ import annotations

import argparse
import json
import os
import time
import webbrowser

from .notifier import notify
from .server import run_server
from .service import RadarService
from .store import StateStore


def _format_snapshot(snapshot: object) -> str:
    data = snapshot.to_dict()  # type: ignore[attr-defined]
    lines = [
        f"Tibo Radar · {data['level_label']}",
        f"未来 24h  全局重置 {data['global_24h']}%  重置卡 {data['banked_24h']}%  综合 {data['combined_24h']}%",
        f"未来 48h  全局重置 {data['global_48h']}%  重置卡 {data['banked_48h']}%  综合 {data['combined_48h']}%",
        f"高发时段  {data['likely_window']}",
        f"置信度    {data['confidence']}{' · 数据可能陈旧' if data['stale'] else ''}",
    ]
    if data.get("affected_user_banked_24h") is not None:
        lines.append(
            f"故障受影响用户补发卡  {data['affected_user_banked_24h']}%（条件概率）"
        )
    if data["evidence"]:
        lines.append("\n主要依据")
        for item in data["evidence"]:
            delta = item["delta"]
            suffix = f" ({delta:+d})" if delta else ""
            lines.append(f"- {item['label']}{suffix}：{item['detail']}")
    if data["source_errors"]:
        lines.append("\n数据提示")
        lines.extend(f"- {message}" for message in data["source_errors"])
    return "\n".join(lines)


def cmd_snapshot(args: argparse.Namespace) -> int:
    snapshot = RadarService().snapshot(force=True)
    if args.json:
        print(json.dumps(snapshot.to_dict(), ensure_ascii=False, indent=2))
    else:
        print(_format_snapshot(snapshot))
    return 0


def cmd_serve(args: argparse.Namespace) -> int:
    url = f"http://127.0.0.1:{args.port}"
    if args.open:
        # Give the server a moment to bind before the browser retries the page.
        import threading

        threading.Timer(0.6, lambda: webbrowser.open(url)).start()
    run_server(port=args.port)
    return 0


def cmd_watch(args: argparse.Namespace) -> int:
    service = RadarService(ttl_seconds=0)
    store = StateStore()
    print(
        f"Tibo Radar 正在观察：每 {args.interval} 秒刷新，"
        f"24 小时综合概率达到 {args.threshold}% 时提醒。"
    )
    while True:
        snapshot = service.snapshot(force=True)
        decision = store.notification_for(
            snapshot, threshold=args.threshold, notify_first=args.notify_first
        )
        print(
            f"[{snapshot.generated_at}] 综合 {snapshot.combined_24h}% · "
            f"{snapshot.level_label}{' · 缓存' if snapshot.stale else ''}"
        )
        if decision:
            notify(*decision)
            print(f"已提醒：{decision[0]}")
        if args.once:
            return 0
        try:
            time.sleep(args.interval)
        except KeyboardInterrupt:
            return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="tibo-radar", description="预测 Codex 福利重置与重置卡发放概率。"
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    snapshot = subparsers.add_parser("snapshot", help="显示一次当前预测")
    snapshot.add_argument("--json", action="store_true", help="输出 JSON")
    snapshot.set_defaults(func=cmd_snapshot)

    serve = subparsers.add_parser("serve", help="启动本地网页")
    serve.add_argument(
        "--port",
        type=int,
        default=int(os.environ.get("TIBO_RADAR_PORT", "8765")),
    )
    serve.add_argument("--open", action="store_true", help="自动打开浏览器")
    serve.set_defaults(func=cmd_serve)

    watch = subparsers.add_parser("watch", help="持续观察并发送 macOS 通知")
    watch.add_argument(
        "--interval",
        type=int,
        default=int(os.environ.get("TIBO_RADAR_REFRESH_SECONDS", "900")),
        help="刷新间隔（秒）",
    )
    watch.add_argument(
        "--threshold",
        type=int,
        default=int(os.environ.get("TIBO_RADAR_NOTIFY_THRESHOLD", "65")),
        help="24 小时综合概率提醒阈值",
    )
    watch.add_argument("--once", action="store_true", help="只运行一次，便于测试")
    watch.add_argument(
        "--notify-first",
        action="store_true",
        help="首次运行时若已超过阈值也提醒",
    )
    watch.set_defaults(func=cmd_watch)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if hasattr(args, "interval") and args.interval < 60:
        parser.error("刷新间隔不能少于 60 秒")
    if hasattr(args, "threshold") and not 1 <= args.threshold <= 99:
        parser.error("提醒阈值必须在 1 到 99 之间")
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
