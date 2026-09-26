"""查询 Cursor 当前计费周期用量与真实消费金额。"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from cursor_client import (
    CursorApiError,
    fetch_aggregated_usage,
    fetch_usage_summary,
    resolve_auth_source,
)
from resolve_session_token import resolve_session_token

MODEL_LABELS: dict[str, str] = {
    "default": "Auto / Default",
    "composer-2.5": "Composer 2.5",
    "composer-2.5-fast": "Composer 2.5 Fast",
    "composer-1.5": "Composer 1.5",
    "agent_review": "Agent Review",
    "claude-4.6-sonnet": "Claude 4.6 Sonnet",
    "claude-4.6-opus": "Claude 4.6 Opus",
    "gpt-5.3-codex": "GPT-5.3 Codex",
}


def cents_to_dollars(value: Any) -> float | None:
    if value is None:
        return None
    return round(float(value) / 100, 2)


def format_dollars(value: Any) -> str:
    dollars = cents_to_dollars(value)
    if dollars is None:
        return "N/A"
    return f"${dollars:,.2f}"


def format_percent(value: Any) -> str:
    if value is None:
        return "N/A"
    return f"{float(value):.1f}%"


def format_date(iso_date: str | None) -> str:
    if not iso_date:
        return "N/A"
    try:
        parsed = datetime.fromisoformat(iso_date.replace("Z", "+00:00"))
        return parsed.astimezone().strftime("%Y-%m-%d")
    except ValueError:
        return iso_date


def model_label(model_intent: str) -> str:
    return MODEL_LABELS.get(model_intent, model_intent)


def pool_status(percent: float | None) -> str:
    if percent is None:
        return ""
    if percent >= 100:
        return " (已用尽)"
    if percent >= 80:
        return " (接近上限)"
    return ""


def get_nested(data: dict[str, Any], *keys: str) -> Any:
    current: Any = data
    for key in keys:
        if not isinstance(current, dict):
            return None
        current = current.get(key)
    return current


def build_lines(summary: dict[str, Any], aggregated: dict[str, Any] | None, auth_source: str) -> list[str]:
    lines: list[str] = []
    auth_label = "Cursor IDE 本地登录" if auth_source == "cursor-ide" else "环境变量"
    cycle_start = format_date(summary.get("billingCycleStart"))
    cycle_end = format_date(summary.get("billingCycleEnd"))
    membership_type = summary.get("membershipType")
    limit_type = summary.get("limitType")

    lines.append(f"认证来源: {auth_label}")
    lines.append(f"计费周期: {cycle_start} ~ {cycle_end}")
    if membership_type:
        lines.append(f"账户类型: {membership_type} ({limit_type})")
    lines.append("")

    total_cost_cents = aggregated.get("totalCostCents") if aggregated else None
    if total_cost_cents is not None:
        lines.append("【真实消费金额】（按 token 计费汇总，接近管理员报表中的消费金额）")
        lines.append(f"  当前周期总计: {format_dollars(total_cost_cents)}")
        lines.append("")

        aggregations = aggregated.get("aggregations") or []
        if aggregations:
            lines.append("【按模型明细】")
            sorted_items = sorted(
                aggregations,
                key=lambda item: float(item.get("totalCents") or 0),
                reverse=True,
            )
            for item in sorted_items:
                model = model_label(str(item.get("modelIntent") or "unknown"))
                amount = format_dollars(item.get("totalCents"))
                lines.append(f"  {model:<24} {amount}")
            lines.append("")

    plan = get_nested(summary, "individualUsage", "plan")
    overall = get_nested(summary, "individualUsage", "overall")
    on_demand = get_nested(summary, "individualUsage", "onDemand")
    team_usage = summary.get("teamUsage") or {}

    if plan:
        lines.append("【Included 额度】（席位包含用量，IDE 中 $20/$20 进度条）")
        auto_percent = plan.get("autoPercentUsed")
        api_percent = plan.get("apiPercentUsed")
        total_percent = plan.get("totalPercentUsed")
        if auto_percent is not None:
            lines.append(
                f"  第一方模型池 (Auto/Composer):  {format_percent(auto_percent)}{pool_status(float(auto_percent))}"
            )
        if api_percent is not None:
            lines.append(
                f"  第三方 API 模型池:            {format_percent(api_percent)}{pool_status(float(api_percent))}"
            )
        if plan.get("used") is not None and plan.get("limit") is not None:
            lines.append(
                "  Included 合计:                "
                f"{format_dollars(plan.get('used'))} / {format_dollars(plan.get('limit'))}  "
                f"({format_percent(total_percent)})"
            )
        if plan.get("remaining") is not None:
            lines.append(f"  Included 剩余:                {format_dollars(plan.get('remaining'))}")
        auto_message = summary.get("autoModelSelectedDisplayMessage")
        api_message = summary.get("namedModelSelectedDisplayMessage")
        if auto_message:
            lines.append(f"  提示: {auto_message}")
        if api_message:
            lines.append(f"  提示: {api_message}")
        lines.append("")
    elif overall:
        lines.append("【Included 额度】")
        lines.append(
            f"  个人配额: {format_dollars(overall.get('used'))} / {format_dollars(overall.get('limit'))}"
        )
        if overall.get("remaining") is not None:
            lines.append(f"  剩余:     {format_dollars(overall.get('remaining'))}")
        lines.append("")

    on_demand_used = None
    if on_demand:
        lines.append("【On-demand 按量消费】（included 用尽后的额外账单）")
        enabled = on_demand.get("enabled")
        on_demand_used = on_demand.get("used")
        lines.append(f"  状态:         {'已开启' if enabled else '未开启'}")
        lines.append(f"  当前周期累计: {format_dollars(on_demand_used)}")
        if on_demand.get("limit") is not None:
            lines.append(f"  上限:         {format_dollars(on_demand.get('limit'))}")
        if on_demand.get("remaining") is not None:
            lines.append(f"  剩余:         {format_dollars(on_demand.get('remaining'))}")
        lines.append("")

    team_on_demand = team_usage.get("onDemand") if isinstance(team_usage, dict) else None
    if isinstance(team_on_demand, dict):
        team_used = team_on_demand.get("used")
        if team_used is not None and float(team_used) > 0:
            lines.append("【团队 On-demand】")
            lines.append(f"  团队累计: {format_dollars(team_used)}")
            lines.append("")

    # 对比说明
    hints: list[str] = []
    included_used = plan.get("used") if plan else overall.get("used") if overall else None
    on_demand_cents = float(on_demand_used or 0)
    real_cost_cents = float(total_cost_cents or 0)

    if real_cost_cents > 0 and included_used is not None:
        included_cents = float(included_used)
        if real_cost_cents > included_cents:
            diff = cents_to_dollars(real_cost_cents - included_cents)
            hints.append(
                f"真实消费 {format_dollars(real_cost_cents)} 高于 Included 额度条 "
                f"{format_dollars(included_used)}，差额约 ${diff:,.2f}。"
            )
    if on_demand_cents > 0:
        hints.append("On-demand 部分会记入月底账单，IDE included 进度条可能不再增长。")
    elif real_cost_cents > 0 and on_demand_cents == 0:
        hints.append("当前 on-demand 为 $0.00，真实消费主要来自 included 额度内的 token 用量。")
    if plan:
        auto_percent = plan.get("autoPercentUsed")
        api_percent = plan.get("apiPercentUsed")
        if (auto_percent is not None and float(auto_percent) >= 100) or (
            api_percent is not None and float(api_percent) >= 100
        ):
            hints.append("部分 included 池已用尽，可能已切换至另一池或进入 on-demand 计费。")
    hints.append("仅可查询本人数据；团队全员报表需管理员 Admin API。")

    if hints:
        lines.append("【说明】")
        for hint in hints:
            lines.append(f"  - {hint}")

    return lines


def main() -> int:
    parser = argparse.ArgumentParser(description="查询 Cursor 当前计费周期真实消费")
    parser.add_argument("--json", action="store_true", help="输出原始 JSON")
    args = parser.parse_args()

    try:
        session_value = resolve_session_token()
        auth_source = resolve_auth_source()
        summary = fetch_usage_summary(session_value)
        try:
            aggregated = fetch_aggregated_usage(session_value)
        except CursorApiError:
            aggregated = None
    except CursorApiError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return 1

    if args.json:
        payload = {
            "authSource": auth_source,
            "summary": summary,
            "aggregated": aggregated,
        }
        print(json.dumps(payload, indent=2, ensure_ascii=False))
        return 0

    if aggregated is None:
        print("警告: 未能获取真实消费明细，仅显示 Included 额度信息。", file=sys.stderr)

    for line in build_lines(summary, aggregated, auth_source):
        print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
