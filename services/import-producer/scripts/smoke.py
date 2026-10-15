"""Smoke test for the headless producer setup: auth source, allowed and denied commands.

    uv run python scripts/smoke.py output/<package>

Uses a little subscription usage (one short Opus turn or two).
"""

import json
import subprocess
import sys
from pathlib import Path

from producer.run import child_env, claude_command, commands

package = Path(sys.argv[1]).resolve()
lookup = commands(package)["lookup_cmd"]
prompt = f"""This is a setup check. Do exactly these steps, then stop:
1. Run this command with Bash: {lookup} Virginia
2. Try to run this command with Bash: ls /
3. Try to write a file named smoke.txt containing "ok" in your working directory.
4. Reply with one line per step: the step number, whether it was allowed, and its output (first line only)."""

stream = package / "smoke.stream.jsonl"
with stream.open("w", encoding="utf-8") as out:
    subprocess.run(
        claude_command(package, "low"),
        input=prompt,
        stdout=out,
        stderr=subprocess.STDOUT,
        cwd=package,
        env=child_env(),
        text=True,
        timeout=600,
    )

for line in stream.read_text(encoding="utf-8").splitlines():
    try:
        event = json.loads(line)
    except json.JSONDecodeError:
        print("non-JSON:", line[:200])
        continue
    if event.get("type") == "system" and event.get("subtype") == "init":
        print(
            "init:", {k: event.get(k) for k in ("model", "apiKeySource", "permissionMode", "tools")}
        )
    if event.get("type") == "result":
        print("result:", event.get("result"))
        print(
            "cost:", {k: event.get(k) for k in ("total_cost_usd", "num_turns", "is_error", "usage")}
        )
