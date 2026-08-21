"""Hidden idalib supervisor launcher with file logging.

Started via pythonw so no console window appears. stdout/stderr and the
logging module both go to %LOCALAPPDATA%\\reverse-skill\\ida-mcp\\supervisor.log.
"""

from __future__ import annotations

import os
import sys
from datetime import datetime
from pathlib import Path


def _log_path() -> Path:
    root = Path(os.environ.get("LOCALAPPDATA") or ".") / "reverse-skill" / "ida-mcp"
    root.mkdir(parents=True, exist_ok=True)
    return root / "supervisor.log"


def _rotate(path: Path, max_bytes: int = 5 * 1024 * 1024) -> None:
    if path.exists() and path.stat().st_size > max_bytes:
        bak = path.with_name(path.name + ".1")
        if bak.exists():
            bak.unlink()
        path.replace(bak)


def main() -> None:
    log_path = _log_path()
    _rotate(log_path)
    log_fp = open(log_path, "a", encoding="utf-8", buffering=1, errors="replace")
    sys.stdout = log_fp
    sys.stderr = log_fp
    print(
        f"==== start {datetime.now():%Y-%m-%d %H:%M:%S} pid={os.getpid()} ====",
        flush=True,
    )

    from ida_pro_mcp.idalib_supervisor import main as supervisor_main

    supervisor_main()


if __name__ == "__main__":
    main()
