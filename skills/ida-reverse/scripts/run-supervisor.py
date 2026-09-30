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

    try:
        _patch_streamable_http()
    except Exception as exc:
        print(f"WARN: streamable-http patch skipped: {exc}", flush=True)

    from ida_pro_mcp.idalib_supervisor import main as supervisor_main

    supervisor_main()


def _patch_streamable_http() -> None:
    """HTTP MCP clients use Streamable HTTP on /mcp.

    Stock idalib_supervisor serves with background=False → HTTPServer
    (one request at a time). A GET /sse or GET /mcp that stays open
    then makes tools/list hang, and the client marks the server error.
    GET /mcp also returned 405, which breaks live tool discovery.
    """
    import select
    import socket
    import sys
    import time
    import uuid
    from urllib.parse import urlparse

    # Vendored zeromcp lives under site-packages/ida_pro_mcp/ida_mcp.
    # Do not import ida_pro_mcp.ida_mcp (that pulls idaapi).
    import ida_pro_mcp.idalib_supervisor as _sup

    zm_dir = Path(_sup.__file__).resolve().parent / "ida_mcp"
    sys.path.insert(0, str(zm_dir))
    try:
        import zeromcp.mcp as zm  # type: ignore
    finally:
        sys.path.remove(str(zm_dir))

    zm.HTTPServer = zm.ThreadingHTTPServer

    orig_get = zm.McpHttpRequestHandler.do_GET

    def do_get(self):
        if not self._check_api_request():
            return
        if urlparse(self.path).path != "/mcp":
            return orig_get(self)

        session_id = self.headers.get("Mcp-Session-Id") or str(uuid.uuid4())
        self.mcp_server.register_http_session(session_id)
        conn = zm._McpSseConnection(self.wfile)
        self.mcp_server._sse_connections[conn.session_id] = conn
        try:
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "keep-alive")
            self.send_header("Mcp-Session-Id", session_id)
            self.send_cors_headers()
            self.end_headers()
            sock = self.connection
            if sock and hasattr(sock, "settimeout"):
                try:
                    sock.settimeout(1.0)
                except OSError:
                    pass
            last_ping = time.time()
            while conn.alive and self.mcp_server._running:
                now = time.time()
                if sock:
                    try:
                        readable, _, _ = select.select([sock], [], [], 1.0)
                        if readable and sock.recv(1, socket.MSG_PEEK) == b"":
                            break
                    except (OSError, socket.error, ConnectionResetError, BrokenPipeError):
                        break
                else:
                    time.sleep(1.0)
                if now - last_ping >= 30:
                    try:
                        conn.send_event("ping", "")
                    except (OSError, BrokenPipeError):
                        break
                    last_ping = now
        finally:
            conn.alive = False
            self.mcp_server._sse_connections.pop(conn.session_id, None)

    zm.McpHttpRequestHandler.do_GET = do_get


if __name__ == "__main__":
    main()
