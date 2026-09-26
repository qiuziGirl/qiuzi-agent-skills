---
name: qiuzi-cursor-usage
description: >-
  查询 Cursor Team 账号当前计费周期内的真实 AI 消费金额，包括按 token 计费汇总、
  按模型明细、included 双池用量和 on-demand 按量费用。当用户询问 Cursor 用量、额度、
  消费金额、$20 封顶、计费周期消费、Auto 模式是否还在计费时使用。
---

# Cursor 真实消费额度查询

查询 Cursor 当前计费周期的**真实消费金额**（接近管理员报表中的「消费金额」）以及 Included 额度、On-demand 费用。

## 前置条件

**默认无需手动配置**：若 Cursor IDE 已登录，脚本会自动从本地 `state.vscdb` 读取会话 token。

认证优先级：

1. 环境变量 `CURSOR_SESSION_TOKEN`（手动覆盖）
2. Cursor IDE 本地登录状态（`%APPDATA%\Cursor\User\globalStorage\state.vscdb`）

仅在自动读取失败时，才需手动配置 Cookie（见 [reference.md](reference.md)）。

**不要把 token 写入 Skill 文件、代码仓库或聊天记录。**

## 执行流程

1. 运行查询脚本：

```powershell
$skillRoot = Join-Path $HOME '.agents\skills\qiuzi-cursor-usage'
& (Join-Path $skillRoot 'scripts\query-usage.ps1')
```

或：

```powershell
$skillRoot = Join-Path $HOME '.agents\skills\qiuzi-cursor-usage'
python (Join-Path $skillRoot 'scripts\query-usage.py')
```

以上路径对应仓库安装脚本的默认目标目录；若使用自定义 `-TargetRoot`，将
`$skillRoot` 替换为实际安装目录。

2. 需要原始 JSON 时加 `--json` / `-Json`
3. 用中文解读输出，重点区分：
   - **真实消费金额**（`totalCostCents`，管理员报表同类数据）
   - **Included 额度**（$20/$20 进度条）
   - **On-demand**（超出 included 的额外账单）
4. 用户需要逐条事件明细时，参考 [reference.md](reference.md)

## 结果解读模板

| 概念 | 含义 | 数据来源 |
|------|------|----------|
| 真实消费金额 | 本周期按 token 计费的实际用量成本 | `get-aggregated-usage-events` |
| 按模型明细 | 各模型分别消费多少美元 | `aggregations[].totalCents` |
| Included 额度 | 席位包含用量（UI $20/$20 进度条） | `usage-summary` |
| On-demand | included 用尽后的额外按量账单 | `usage-summary` |

解读示例结构：

```
计费周期: YYYY-MM-DD ~ YYYY-MM-DD

【真实消费金额】
  当前周期总计: $22.48

【按模型明细】
  Auto / Default           $20.80
  Composer 2.5 Fast        $1.59

【Included 额度】
  Included 合计: $20.00 / $20.00

【On-demand 按量消费】
  当前周期累计: $0.00

【说明】
  - 真实消费高于 Included 额度条时，说明 token 用量已超过 $20 包含额度
```

## 权限说明

- **普通成员**：可查本人真实消费金额、按模型明细、Included / On-demand
- **团队管理员**：可查全员消费，需 Admin API（`POST api.cursor.com/teams/spend`）
- **历史账期**：普通成员接口仅覆盖当前计费周期；上月数据需管理员导出或 Admin API

## 故障处理

| 现象 | 处理 |
|------|------|
| 无法自动获取 token | 确认 Cursor IDE 已登录 |
| HTTP 401/403 | 重新登录 IDE 或更新 `CURSOR_SESSION_TOKEN` |
| 缺少真实消费金额 | 检查 `get-aggregated-usage-events` 是否可用，用 `--json` 排查 |
| 与 Dashboard 数字不一致 | 以 Dashboard / 发票为准；API 为实时估算 |

## 限制

- 接口为非官方 Dashboard REST，可能随时变更
- 仅查询**本人**数据
- 不能替代正式发票

## 附加资源

- API 字段与明细接口：[reference.md](reference.md)
