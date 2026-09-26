"""从环境变量或 Cursor IDE 本地状态解析 WorkosCursorSessionToken。"""

from __future__ import annotations

import base64
import json
import os
import sqlite3
import sys
from pathlib import Path


def _decode_jwt_sub(jwt_value: str) -> str:
    parts = jwt_value.split(".")
    if len(parts) < 2:
        raise ValueError("无效的 JWT access token")
    payload = parts[1] + "=" * (-len(parts[1]) % 4)
    data = json.loads(base64.urlsafe_b64decode(payload))
    sub = data.get("sub")
    if not isinstance(sub, str) or not sub:
        raise ValueError("JWT 中缺少 sub 字段")
    return sub


def _build_cookie_value(access_value: str) -> str:
    if "::" in access_value or "%3A%3A" in access_value:
        return access_value
    sub = _decode_jwt_sub(access_value)
    return f"{sub}::{access_value}"


def _read_access_token_from_db(db_path: Path) -> str:
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT value FROM ItemTable WHERE key = ?",
            ("cursorAuth/accessToken",),
        )
        row = cur.fetchone()
    finally:
        conn.close()

    if not row or not row[0]:
        raise ValueError(f"未在 {db_path} 中找到 cursorAuth/accessToken")
    return str(row[0])


def _candidate_db_paths() -> list[Path]:
    app_data = os.environ.get("APPDATA")
    local_app_data = os.environ.get("LOCALAPPDATA")
    home = Path.home()
    candidates: list[Path] = []

    if app_data:
        candidates.append(Path(app_data) / "Cursor" / "User" / "globalStorage" / "state.vscdb")
        candidates.append(
            Path(app_data) / "Cursor - Insiders" / "User" / "globalStorage" / "state.vscdb"
        )
    if local_app_data:
        candidates.append(
            Path(local_app_data) / "Cursor" / "User" / "globalStorage" / "state.vscdb"
        )

    candidates.extend(
        [
            home / ".config" / "Cursor" / "User" / "globalStorage" / "state.vscdb",
            home / "Library" / "Application Support" / "Cursor" / "User" / "globalStorage" / "state.vscdb",
        ]
    )

    unique: list[Path] = []
    seen: set[str] = set()
    for path in candidates:
        key = str(path).lower()
        if key not in seen:
            seen.add(key)
            unique.append(path)
    return unique


def resolve_session_token() -> str:
    env_value = os.environ.get("CURSOR_SESSION_TOKEN", "").strip()
    if env_value:
        return env_value

    for db_path in _candidate_db_paths():
        if not db_path.exists():
            continue
        try:
            access_value = _read_access_token_from_db(db_path)
            return _build_cookie_value(access_value)
        except (sqlite3.Error, ValueError, json.JSONDecodeError):
            continue

    raise RuntimeError(
        "无法自动获取 Cursor 会话 token。\n"
        "请确认已登录 Cursor IDE，或手动设置 CURSOR_SESSION_TOKEN。"
    )


def main() -> int:
    try:
        print(resolve_session_token(), end="")
        return 0
    except (RuntimeError, ValueError, json.JSONDecodeError, sqlite3.Error, OSError) as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
