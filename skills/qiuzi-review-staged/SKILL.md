---
name: qiuzi-review-staged
description: 对当前 Git 仓库的暂存区文件进行提交前代码评审。默认只审查 staged（git diff --cached）内容；当用户要求“review staged files”“审查暂存区”“review working changes”“提交前评审”“/review-staged”或“/qiuzi-review-staged”时使用。
---

# 暂存区提交前评审

聚焦 **staged 区**（`git diff --cached`）的提交前评审。仅当用户显式要求时，才扩展到 unstaged / untracked。

## Default Scope

| 范围 | 默认是否纳入 | 触发扩展的关键词 |
|---|---|---|
| **staged**（已 `git add`） | ✅ 默认必审 | — |
| unstaged（工作区未 add） | ❌ 跳过 | "包含未暂存"、"全部改动"、"working tree"、"--all" |
| untracked（新增未 add） | ❌ 跳过 | 同上 |

> 没有 staged 文件时，**不要静默回退到 unstaged**。停下来用 `AskQuestion` 询问：是否改审 unstaged，或先 `git add` 再来。

## Quick Start

```
进度清单：
- [ ] 1. 定位目标 git 仓库
- [ ] 2. 检查 staged 区是否非空
- [ ] 3. 收集 staged 改动（仅 --cached）
- [ ] 4. 加载项目规则
- [ ] 5. 阅读改动文件实际内容
- [ ] 6. 按检查清单逐项评审
- [ ] 7. 输出结构化评审报告
```

## Step 1 — 定位目标仓库

工作区可能多仓库。优先级：
1. 用户明确指定的仓库 / 路径；
2. 用户当前打开文件所在仓库；
3. 多个仓库都有 staged 改动 → `AskQuestion` 让用户选。

## Step 2 — 检查 staged 是否非空

**唯一权威判断方式**：

```bash
git diff --cached --name-only
```

- 输出为空 → 用 `AskQuestion` 询问后续动作（改审 unstaged / 等用户 add 后再来 / 取消）。**不要擅自切换范围**。
- 输出非空 → 进入 Step 3。

> ⚠️ **禁止**依赖会话开始时注入的 `git_status` 快照、IDE 截图、或自己的记忆来判断 staged 是否为空——那些信息可能已过期。每次本 skill 触发，必须**实时执行**上面的命令。

## Step 3 — 收集 staged 改动

```bash
git diff --cached --stat                           # 概览
git diff --cached --name-status                    # 文件状态（A/M/D/R）
git diff --cached                                  # 完整 diff
```

新增（status `A`）的文件 diff 中已包含全部行；不需要额外 `ls-files`。

> **大 diff 策略**：若 `--cached --stat` 显示总行数 >1500，不要一次性 `git diff --cached`。改为按文件：
> ```bash
> git diff --cached -- <file>
> ```
> 分批审，避免上下文爆炸。

## Step 4 — 加载项目规则

仓库根目录起算，**必读**：
- `.cursor/rules/*.mdc`（always_applied 优先级最高）
- `AGENTS.md`、`CLAUDE.md`（如存在）
- `package.json` 的 `scripts`（确认 lint / type-check 命令）
- `tsconfig.json`（确认 strict / path alias）

将规则要点作为评审硬约束。

## Step 5 — 阅读 staged 文件实际内容

仅看 diff 不够。对每个 staged 文件用 `Read` 看完整文件（或受影响函数的完整上下文），评估 diff 之外的连带影响。

> 注意：`Read` 看到的是**工作区**内容。若该文件还有 unstaged 改动（即 staged 与 working tree 不一致），需提示用户："文件 X 的 staged 与工作区不同，本次只评审 staged 版本"，并以 `git show :<file>` 取 staged 版本为准：
> ```bash
> git show :path/to/file.tsx
> ```

判断方法：`git diff --name-only` 输出中若包含某 staged 文件 → 该文件存在 unstaged 差异。

## Step 6 — 评审检查清单

对每个 staged 文件按下列顺序检查：

### 6.1 正确性
- [ ] 业务逻辑正确，边界条件（空数组 / null / 异常）已处理
- [ ] 异步操作三态：`loading` / 错误 / 成功
- [ ] 是否存在项目请求层已统一处理却仍在调用处重复判断的逻辑
- [ ] 防重入 / 防抖 / 重复请求

### 6.2 类型与代码质量
- [ ] 遵循项目类型约束；若项目禁止 `any`，命中时给出建议类型
- [ ] 类型导入用 `import type`
- [ ] 导入顺序符合项目既有规则
- [ ] 使用项目配置的路径别名，避免无必要的深层相对路径
- [ ] 无未使用 import / 变量
- [ ] 函数有 `/** */` 头注释

### 6.3 组件与 UI 规范
- [ ] 组件模式和目录结构符合项目既有约定
- [ ] 优先复用项目已有的共享组件库
- [ ] 选择器和表单类需求使用项目已约定的组件
- [ ] 组件用法符合项目规则文件
- [ ] 样式方案符合项目既有约定

### 6.4 安全与稳定性
- [ ] 未误改受保护配置文件；变更此类文件时已获得明确授权
- [ ] 未误改项目约定不可直接修改的共享组件或依赖目录
- [ ] 危险操作有二次确认 / 权限校验
- [ ] 日志无敏感字段泄漏

### 6.5 文档
- [ ] 如项目规则要求，已同步更新相关 README 或文档

### 6.6 后端（仅当 staged 涉及 Java 服务）
- [ ] 遵守项目既有分层和依赖方向
- [ ] 依赖注入方式符合项目约定
- [ ] 响应模型符合项目约定
- [ ] URL 命名符合项目既有 REST 风格

## Step 7 — 输出报告

严格按下列模板。先总评，再分文件。

```markdown
# Staged 改动评审报告

**仓库**：`<repo path>`<br>
**评审范围**：staged-only（git diff --cached）<br>
**文件数**：N 个（A: 新增 / M: 修改 / D: 删除 / R: 重命名）<br>
**总体结论**：✅ 可提交 / ⚠️ 建议修改后提交 / ❌ 阻断提交

> 注：本次未评审 X 个 unstaged、Y 个 untracked 文件。如需扩展，请回复"包含未暂存"。

## 总体亮点
- ...

## 关键问题（按严重度）

### 🔴 Critical（必须修复）
- **`path/to/file.tsx:42`** — 简述<br>
  **影响**：...<br>
  **建议**：...

### 🟡 Major（强烈建议）
- ...

### 🟢 Minor（可选）
- ...

## 分文件详情

### `path/to/file.tsx` (M)
- 改动概要：...
- 命中规则：项目类型、导入或组件规范 / ...
- 问题：
  - 🔴 ...
  - 🟡 ...
- 建议示意：
  ```diff
  - const data: any = ...
  + const data: OrderItem[] = ...
  ```

## 提交前 Checklist
- [ ] 所有 🔴 已修复
- [ ] `npm run type-check` 通过
- [ ] `npm run lint` 通过
- [ ] 相关 README 已同步
- [ ] 未误提交受保护配置、凭据或共享依赖目录中的无关改动
```

## 触发短语

- "review staged files" / "审查暂存区" / "审一下我 add 过的文件"
- "提交前 review" / "pre-commit review"
- `/review-staged` / `/review-working-changes` / `/qiuzi-review-staged`

## 使用须知

- **范围严格**：默认 staged-only，不要擅自扩到 unstaged。
- **空 staged 不静默回退**：停下来 `AskQuestion`。
- **只读评审**：不直接改文件，除非用户要求"按建议修改"。
- **证据优先**：每条问题给 `文件:行号`，无笼统结论。
- **多仓库**：先确认目标仓库再开审。
- **取 staged 版本**：当 staged 与工作区有差异时，用 `git show :<file>` 取 staged 版本评审。
