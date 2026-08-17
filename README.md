# Qiuzi Agent Skills

个人 Codex Skill 集合，面向个人电脑和服务器的可复核安装、版本管理与受控分享。

## 当前包含

- `qiuzi-review-approval`：先核查审查意见、获得确认后再修改的受控流程。
- `qiuzi-spring-boot-testing`：Spring Boot 的 JUnit 5 与 Mockito 分层测试指引。
- `qiuzi-zh-commit`：生成或翻译简体中文 Conventional Commit 信息。
- `qiuzi-review-staged`：聚焦暂存区改动的提交前评审。

本仓库不包含公司内部 Skill、第三方 Skill、内置 Skill，也不包含 `qiuzi-workspace-builder`。

## Windows 安装

在仓库根目录执行。默认安装到 `~/.agents/skills`，若同名 Skill 已存在，必须显式传入 `-Force`。

```powershell
.\scripts\validate-skills.ps1
.\scripts\install.ps1 -Skills qiuzi-review-approval,qiuzi-spring-boot-testing
```

可指定安装目录，先在临时目录验证：

```powershell
.\scripts\install.ps1 `
  -Skills qiuzi-zh-commit `
  -TargetRoot "$env:TEMP\qiuzi-agent-skills-test"
```

## Linux 服务器安装

推荐使用只读 Deploy Key 克隆指定 tag，再执行安装脚本：

```bash
git clone --branch v0.1.0 --depth 1 git@github.com:<owner>/qiuzi-agent-skills.git
cd qiuzi-agent-skills
./scripts/install.sh --skill qiuzi-review-approval --skill qiuzi-review-staged
```

默认安装目录为 `~/.agents/skills`；若要覆盖已安装的同名目录，添加 `--force`。

## 更新到指定版本

不要在服务器自动追踪 `main`。应明确升级到审核过的 tag：

```bash
git fetch --tags
git checkout v0.1.0
./scripts/install.sh --skill qiuzi-spring-boot-testing --force
```

## 发布与贡献约束

- 禁止提交 Token、密码、证书、私钥、`.env` 文件、公司内网地址、内部业务规则或受限第三方内容。
- 新增或修改 Skill 后，先执行 `.\scripts\validate-skills.ps1` 与 `.\tests\test-scripts.ps1`。
- 发布到公开仓库前，必须重新做脱敏审查，并单独确定开源许可证；本私有仓库首版未授予开源许可。
