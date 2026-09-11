"""System notifications without shell interpolation."""

from __future__ import annotations

import platform
import subprocess


def notify(title: str, body: str) -> bool:
    if platform.system() != "Darwin":
        print(f"{title}: {body}")
        return False
    script = (
        "on run argv\n"
        "display notification (item 2 of argv) with title (item 1 of argv)\n"
        "end run"
    )
    result = subprocess.run(
        ["osascript", "-e", script, title, body],
        check=False,
        capture_output=True,
        text=True,
        timeout=10,
    )
    return result.returncode == 0

