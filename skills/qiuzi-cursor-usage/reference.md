# Cursor 用量 API 参考

> **警告**：以下接口为 Dashboard 逆向文档，非 Cursor 官方公开 API，可能随时变更。仅供个人用量查询，不可用于生产集成。

## 认证

所有 Dashboard REST 请求使用 Cookie 认证：

```http
Cookie: WorkosCursorSessionToken=<token>
```

### 自动获取（推荐）

Skill 会按以下优先级解析 token：

1. 环境变量 `CURSOR_SESSION_TOKEN`
2. Cursor IDE SQLite 状态库：`%APPDATA%\Cursor\User\globalStorage\state.vscdb`
   - 读取键 `cursorAuth/accessToken`（JWT）
   - 从 JWT 的 `sub` 字段拼接为 `sub::jwt`，即 `WorkosCursorSessionToken` 的值

实现脚本：[scripts/resolve_session_token.py](scripts/resolve_session_token.py)

> 前提：Cursor IDE 已登录。无需单独在浏览器复制 Cookie。

### 手动获取（备用）

浏览器登录 cursor.com 后，从 DevTools → Cookies 复制 `WorkosCursorSessionToken`。

## 主接口：GET /api/usage-summary

用于 Included 额度、On-demand 状态、计费周期。

```http
GET https://cursor.com/api/usage-summary
Cookie: WorkosCursorSessionToken=<token>
Accept: application/json
```

### 响应字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `billingCycleStart` | string (ISO 8601) | 当前计费周期开始 |
| `billingCycleEnd` | string (ISO 8601) | 当前计费周期结束 |
| `membershipType` | string | 如 `pro`、`enterprise` |
| `limitType` | string | 如 `user`、`team` |
| `autoModelSelectedDisplayMessage` | string | 第一方模型池提示文案 |
| `namedModelSelectedDisplayMessage` | string | 第三方 API 池提示文案 |
| `individualUsage.plan` | object | included 额度（金额单位：cents） |
| `individualUsage.onDemand` | object | 个人 on-demand 按量消费 |
| `individualUsage.overall` | object | 部分 Team 账户的个人配额 |
| `teamUsage.onDemand` | object | 团队级 on-demand |
| `teamUsage.pooled` | object | 团队 pooled 用量（Enterprise） |

### individualUsage.plan 子字段

| 字段 | 说明 |
|------|------|
| `used` / `limit` / `remaining` | included 已用/上限/剩余（cents） |
| `autoPercentUsed` | 第一方模型池使用百分比 |
| `apiPercentUsed` | 第三方 API 池使用百分比 |
| `totalPercentUsed` | 合计使用百分比 |
| `breakdown.included` | 包含额度明细 |
| `breakdown.bonus` | 赠送额度 |
| `breakdown.total` | 总额度 |

### individualUsage.onDemand 子字段

| 字段 | 说明 |
|------|------|
| `enabled` | 是否开启 on-demand |
| `used` | 当前周期 on-demand 消费（cents） |
| `limit` | 上限（cents），null 表示无上限 |
| `remaining` | 剩余（cents） |

### 响应示例

```json
{
  "billingCycleStart": "2026-06-27T00:00:00.000Z",
  "billingCycleEnd": "2026-07-27T00:00:00.000Z",
  "membershipType": "enterprise",
  "limitType": "team",
  "autoModelSelectedDisplayMessage": "You've used 100% of your included total usage",
  "namedModelSelectedDisplayMessage": "You've used 85% of your included API usage",
  "individualUsage": {
    "plan": {
      "enabled": true,
      "used": 3850,
      "limit": 4000,
      "remaining": 150,
      "autoPercentUsed": 100,
      "apiPercentUsed": 85,
      "totalPercentUsed": 96.25,
      "breakdown": {
        "included": 3850,
        "bonus": 0,
        "total": 3850
      }
    },
    "onDemand": {
      "enabled": true,
      "used": 1235,
      "limit": null,
      "remaining": null
    }
  },
  "teamUsage": {
    "onDemand": {
      "enabled": true,
      "used": 0,
      "limit": 5000000,
      "remaining": 5000000
    }
  }
}
```

上例解读：
- Included 已用 $38.50 / $40.00
- On-demand 额外 $12.35（IDE $20/$20 条满后真实继续计费的部分）

## 真实消费接口：POST /api/dashboard/get-aggregated-usage-events

**Skill 升级后用于查询接近管理员报表的「消费金额」。**

```http
POST https://cursor.com/api/dashboard/get-aggregated-usage-events
Cookie: WorkosCursorSessionToken=<token>
Origin: https://cursor.com
Content-Type: application/json

{}
```

### 响应字段

| 字段 | 说明 |
|------|------|
| `totalCostCents` | **当前计费周期真实消费总额**（cents），接近管理员 `overallSpendCents` |
| `aggregations[]` | 按模型聚合明细 |
| `aggregations[].modelIntent` | 模型标识，如 `default`、`composer-2.5-fast` |
| `aggregations[].totalCents` | 该模型消费金额（cents） |
| `aggregations[].inputTokens` | 输入 token 数 |
| `aggregations[].outputTokens` | 输出 token 数 |
| `aggregations[].cacheReadTokens` | 缓存读取 token 数 |

### 响应示例

```json
{
  "aggregations": [
    {
      "modelIntent": "default",
      "inputTokens": "4279689",
      "outputTokens": "328279",
      "cacheReadTokens": "53941065",
      "totalCents": 2080.45515,
      "tier": 1
    },
    {
      "modelIntent": "composer-2.5-fast",
      "totalCents": 158.62075,
      "tier": 1
    }
  ],
  "totalCostCents": 2247.724045
}
```

解读：`totalCostCents: 2247.72` = **$22.48** 真实消费，可能高于 `usage-summary` 中的 Included $20.00 进度条。

### 与管理员的差异

| 能力 | 本接口（普通成员） | Admin API `/teams/spend` |
|------|-------------------|--------------------------|
| 真实消费金额 | ✅ 仅本人 `totalCostCents` | ✅ 全员 `overallSpendCents` |
| 按模型明细 | ✅ | 需 `filtered-usage-events` |
| 历史账期 | ❌ 带日期参数常 500 | ✅ 管理员可导出 |
| 认证 | IDE 本地 token | Admin API Key |

## 辅助接口：POST /api/dashboard/get-filtered-usage-events

按事件查询明细，用于对账或按模型汇总。

```http
POST https://cursor.com/api/dashboard/get-filtered-usage-events
Cookie: WorkosCursorSessionToken=<token>
Origin: https://cursor.com
Content-Type: application/json

{
  "teamId": 0,
  "startDate": "2026-06-27T00:00:00.000Z",
  "endDate": "2026-07-27T00:00:00.000Z",
  "page": 1,
  "pageSize": 100
}
```

事件字段参考：`model`, `kind`, `chargedCents`, `timestamp` 等。`kind=Usage-based` 表示 on-demand 事件。

## 辅助接口：POST /api/dashboard/get-aggregated-usage-events

按模型聚合用量：

```http
POST https://cursor.com/api/dashboard/get-aggregated-usage-events
Cookie: WorkosCursorSessionToken=<token>
Origin: https://cursor.com
Content-Type: application/json

{
  "teamId": 0,
  "startDate": "2026-06-27T00:00:00.000Z",
  "endDate": "2026-07-27T00:00:00.000Z"
}
```

返回 `aggregations[]` 含 `modelIntent`、`totalCents`、`inputTokens`、`outputTokens` 等。

## 团队管理员：Admin API（可选）

若用户日后成为团队管理员，可使用官方 Admin API：

- Base URL: `https://api.cursor.com`
- 认证: HTTP Basic Auth，API Key 作 username，密码留空
- 端点: `POST /teams/spend`、`POST /teams/filtered-usage-events`
- 文档: https://cursor.com/docs/account/teams/admin-api

`spendCents` 仅含 on-demand；`overallSpendCents` 含 included。

## 故障排查

### token 获取步骤（Chrome）

1. 打开 https://cursor.com/dashboard 并登录
2. F12 → Application → Storage → Cookies → `https://cursor.com`
3. 找到 `WorkosCursorSessionToken`，复制 Value
4. 值可能以 `user_` 开头，包含 `%3A%3A` 编码字符，原样复制即可

### 常见错误

| HTTP 状态 | 原因 | 处理 |
|-----------|------|------|
| 401 | token 无效或过期 | 重新复制 Cookie |
| 403 | 权限不足 | 确认已登录正确账户 |
| 空响应 / 字段缺失 | API 结构变更 | 使用 `-Json` 输出原始数据排查 |

### PowerShell 手动验证

```powershell
$skillRoot = Join-Path $HOME '.agents\skills\qiuzi-cursor-usage'
& (Join-Path $skillRoot 'scripts\query-usage.ps1')
python (Join-Path $skillRoot 'scripts\query-usage.py') --json
```

## 参考来源

- [dmwyatt gist - Cursor dashboard API](https://gist.github.com/dmwyatt/1e9359b1862e7cbfe1e754fe4c8db764)
- [openusage #829 - Team usage-summary fallback](https://github.com/robinebers/openusage/issues/829)
- [Cursor Team Pricing](https://cursor.com/docs/account/teams/pricing)
