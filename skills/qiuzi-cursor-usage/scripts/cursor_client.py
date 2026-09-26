"""Cursor Dashboard API 客户端。"""

from __future__ import annotations

import json
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from resolve_session_token import resolve_session_token

USAGE_SUMMARY_URL = "https://cursor.com/api/usage-summary"
AGGREGATED_USAGE_URL = "https://cursor.com/api/dashboard/get-aggregated-usage-events"


class CursorApiError(RuntimeError):
    """Cursor API 调用失败。"""

    def __init__(self, message: str, status_code: int | None = None) -> None:
        super().__init__(message)
        self.status_code = status_code


def _request_json(
    url: str,
    session_value: str,
    *,
    method: str = "GET",
    body: dict[str, Any] | None = None,
) -> dict[str, Any]:
    headers = {
        "Cookie": f"WorkosCursorSessionToken={session_value}",
        "Accept": "application/json",
        "Origin": "https://cursor.com",
    }
    data = None
    if body is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(body).encode("utf-8")

    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace")
        raise CursorApiError(
            f"HTTP {exc.code}: {raw[:200] or exc.reason}",
            status_code=exc.code,
        ) from exc
    except urllib.error.URLError as exc:
        raise CursorApiError(f"网络请求失败: {exc.reason}") from exc

    if not isinstance(payload, dict):
        raise CursorApiError("响应不是 JSON 对象")
    return payload


def fetch_usage_summary(session_value: str) -> dict[str, Any]:
    return _request_json(USAGE_SUMMARY_URL, session_value)


def fetch_aggregated_usage(session_value: str) -> dict[str, Any]:
    return _request_json(AGGREGATED_USAGE_URL, session_value, method="POST", body={})


def resolve_auth_source() -> str:
    if __import__("os").environ.get("CURSOR_SESSION_TOKEN", "").strip():
        return "environment"
    return "cursor-ide"
