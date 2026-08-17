---
name: qiuzi-zh-commit
description: Use when the user asks to translate an English Git commit message into Simplified Chinese, generate a Chinese Conventional Commits message from repository changes, or write a Chinese commit message. Triggers include '翻译 commit', '中文 commit message', '生成 commit message', and '写提交说明'.
---

# 中文 Git Commit Message

有现成 commit message → 译成简体中文；没有 → 基于当前仓库改动生成中文 Conventional Commits message。<br>
**默认只产出可复制文本，不执行 `git commit`。**

## Quick Start

```
进度清单：
- [ ] 1. 判定分支：翻译（A）还是生成（B）
- [ ] 2. 执行对应流程
- [ ] 3. 以单独 Markdown 代码块输出完整 message
- [ ] 4. 仅当用户明确要求提交时才 git commit
```

## 分支判定

满足任一条件 → **分支 A（翻译）**：

- 用户粘贴了多行英文 commit 文本（含 `feat:` / `fix:` / 项目符号列表等）
- 用户说「翻译成中文」且上下文已有 commit message
- `@` / 附件中含 commit message 输入

否则 → **分支 B（生成）**。

---

## 分支 A：翻译

翻译规则：

1. 使用简体中文；**保留** Conventional Commits 前缀与 scope（如 `feat(auth):`）
2. 完整译文放入**单独一个** Markdown 代码块
3. 代码块内只放译文，块外不重复完整正文
4. 列表项用 `-`，与英文条目一一对应
5. 不擅自改动原意；不扩写成无关总结
6. 用户未要求翻译时，不要主动翻译无关内容

### 输出示例

用户粘贴英文 message 并说「翻译成中文」后，回复形态：

````markdown
```
feat(order): 完善订单处理校验与前端绑定

- 更新订单相关接口与一致性校验
- 补充订单主数据与流程状态模型
- 前端业务页面对接处理结果
```
````

块外可有一句极短说明（如「译文如下：」），但**不要**在块外再贴一遍完整正文。

---

## 分支 B：生成

### Step 1 — 定位目标仓库

工作区可能多仓库。优先级：

1. 用户明确指定的仓库 / 路径
2. 用户当前打开文件所在仓库
3. 仅一个仓库有改动 → 用该仓
4. 多个仓库都有改动 → 询问用户选择后再继续

### Step 2 — 收集改动

**实时执行** git 命令，禁止依赖会话开始时的 `git_status` 快照。

优先级：

1. 若 `git diff --cached --name-only` 非空 → 以 staged 为准：
   ```bash
   git diff --cached --stat
   git diff --cached
   ```
2. 若无 staged → 用工作区改动：
   ```bash
   git status --short
   git diff
   git diff --stat
   ```
3. 参考近期风格（可选）：
   ```bash
   git log -5 --oneline
   ```

无任何改动时：说明无法生成，请用户先改代码或提供 message 草稿；**不要编造**。

大 diff（约 >1500 行）：先看 `--stat` / `--name-status`，再按关键文件分批 `git diff`，避免上下文爆炸。

### Step 3 — 生成中文 Conventional Commits

格式：

```
type(optional-scope): 中文摘要

- 要点一（可选）
- 要点二（可选）
```

约束：

- `type` 用英文：`feat` / `fix` / `refactor` / `docs` / `test` / `chore` / `perf` / `style` / `ci` / `build` 等
- `scope` 可选，用简短英文或拼音缩写（与仓库习惯一致时优先跟历史）
- 摘要与正文用**简体中文**
- 聚焦 **why**（意图与影响），避免堆砌文件名
- 摘要宜 1 句；要点用 `-` 列表，通常不超过 5 条
- 不要包含无关机密（`.env`、凭证等）描述

### Step 4 — 输出

与分支 A 相同：完整 message 放入**单独一个** Markdown 代码块，便于粘贴到 Git 提交框。

---

## 输出契约

| 项 | 要求 |
|---|---|
| 语言 | 简体中文（type/scope 保留英文 Conventional 形式） |
| 载体 | 单独一个 Markdown 代码块 |
| 块内 | 只放完整 commit message |
| 块外 | 不重复完整正文 |
| 默认 | **不**执行 `git add` / `git commit` / `git push` |

---

## 提交边界

- 本 Skill **默认只写 message**。
- 仅当用户在同一次对话中明确说「提交」「commit」「帮我提交」等时，才可执行提交，并遵循当前仓库及会话中的 Git 协作规则。
- 用户只说「翻译成中文」或「生成 commit message」→ **到输出代码块为止**，不要擅自提交。

---

## 反例

- 把英文 message 译完后又在块外再贴一遍全文
- 翻译时丢掉 `feat(scope):` 前缀
- 无改动时编造 message
- 未明确要求却执行 `git commit`
- 生成一长串文件清单当摘要
