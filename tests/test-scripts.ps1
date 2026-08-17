$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$validator = Join-Path $repoRoot 'scripts\validate-skills.ps1'
$installer = Join-Path $repoRoot 'scripts\install.ps1'
$bashInstaller = Join-Path $repoRoot 'scripts\install.sh'

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function New-TestSkill {
    param(
        [string]$Root,
        [string]$Name
    )

    $skillPath = Join-Path $Root $Name
    New-Item -ItemType Directory -Force -Path $skillPath | Out-Null
    @"
---
name: $Name
description: 用于安装脚本测试的示例 Skill。
---

# $Name
"@ | Set-Content -LiteralPath (Join-Path $skillPath 'SKILL.md') -Encoding utf8NoBOM
}

function Invoke-PowerShellScript {
    param(
        [scriptblock]$Script
    )

    try {
        & $Script | Out-Host
        return 0
    }
    catch {
        Write-Host $_
        return 1
    }
}

Assert-True (Test-Path -LiteralPath $validator) "缺少校验脚本：$validator"
Assert-True (Test-Path -LiteralPath $installer) "缺少 Windows 安装脚本：$installer"
Assert-True (Test-Path -LiteralPath $bashInstaller) "缺少 Linux 安装脚本：$bashInstaller"

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("qiuzi-agent-skills-tests-" + [guid]::NewGuid().ToString('N'))
try {
    $validRoot = Join-Path $testRoot 'valid-skills'
    $targetRoot = Join-Path $testRoot 'installed-skills'
    New-TestSkill -Root $validRoot -Name 'sample-skill'
    New-TestSkill -Root $validRoot -Name 'other-skill'

    $validationExitCode = Invoke-PowerShellScript -Script { & $validator -SkillRoot $validRoot -Quiet }
    Assert-True ($validationExitCode -eq 0) '合法 Skill 未通过校验。'

    $installExitCode = Invoke-PowerShellScript -Script { & $installer -SourceRoot $validRoot -TargetRoot $targetRoot -Skills 'sample-skill' }
    Assert-True ($installExitCode -eq 0) 'Windows 安装脚本执行失败。'
    Assert-True (Test-Path -LiteralPath (Join-Path $targetRoot 'sample-skill\SKILL.md')) '指定 Skill 未安装。'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $targetRoot 'other-skill'))) '安装脚本安装了未指定的 Skill。'

    $credentialVariants = @(
        'api_key = example-not-a-real-secret',
        'export API_KEY=example-not-a-real-secret',
        'client_secret = example-not-a-real-secret',
        'AWS_SECRET_ACCESS_KEY=example-not-a-real-secret',
        'process.env.API_KEY = example-not-a-real-secret',
        'TOKEN=example-not-a-real-secret',
        'accessToken=example-not-a-real-secret',
        'refreshToken=example-not-a-real-secret'
    )
    $sensitiveRoot = $null
    foreach ($credentialVariant in $credentialVariants) {
        $candidateRoot = Join-Path $testRoot ("sensitive-skills-" + [guid]::NewGuid().ToString('N'))
        New-TestSkill -Root $candidateRoot -Name 'sample-skill'
        $credentialVariant | Set-Content -LiteralPath (Join-Path $candidateRoot 'sample-skill\settings.txt') -Encoding utf8NoBOM
        $sensitiveExitCode = Invoke-PowerShellScript -Script { & $validator -SkillRoot $candidateRoot -Quiet }
        Assert-True ($sensitiveExitCode -ne 0) "未拒绝疑似凭据写法：$credentialVariant"
        if ($null -eq $sensitiveRoot) {
            $sensitiveRoot = $candidateRoot
        }
    }

    $sensitiveFileRoot = Join-Path $testRoot 'sensitive-file-name'
    New-TestSkill -Root $sensitiveFileRoot -Name 'sample-skill'
    'placeholder' | Set-Content -LiteralPath (Join-Path $sensitiveFileRoot 'sample-skill\.env.production') -Encoding utf8NoBOM
    $sensitiveFileExitCode = Invoke-PowerShellScript -Script { & $validator -SkillRoot $sensitiveFileRoot -Quiet }
    Assert-True ($sensitiveFileExitCode -ne 0) '未拒绝敏感文件名。'

    $pemRoot = Join-Path $testRoot 'pem-content'
    New-TestSkill -Root $pemRoot -Name 'sample-skill'
    @'
-----BEGIN PRIVATE KEY-----
not-a-real-key
-----END PRIVATE KEY-----
'@ | Set-Content -LiteralPath (Join-Path $pemRoot 'sample-skill\notes.md') -Encoding utf8NoBOM
    $pemExitCode = Invoke-PowerShellScript -Script { & $validator -SkillRoot $pemRoot -Quiet }
    Assert-True ($pemExitCode -ne 0) '未拒绝 PEM 私钥内容。'

    $sensitiveTargetRoot = Join-Path $testRoot 'sensitive-install-target'
    $sensitiveInstallExitCode = Invoke-PowerShellScript -Script { & $installer -SourceRoot $sensitiveRoot -TargetRoot $sensitiveTargetRoot -Skills 'sample-skill' }
    Assert-True ($sensitiveInstallExitCode -ne 0) '安装脚本未拒绝未通过校验的源 Skill。'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $sensitiveTargetRoot 'sample-skill'))) '安装脚本安装了未通过校验的源 Skill。'

    '旧版本内容' | Set-Content -LiteralPath (Join-Path $targetRoot 'sample-skill\legacy.txt') -Encoding utf8NoBOM
    $noForceExitCode = Invoke-PowerShellScript -Script { & $installer -SourceRoot $validRoot -TargetRoot $targetRoot -Skills 'sample-skill' }
    Assert-True ($noForceExitCode -ne 0) '未传 -Force 时覆盖了已安装 Skill。'
    Assert-True ((Get-Content -LiteralPath (Join-Path $targetRoot 'sample-skill\legacy.txt') -Raw).TrimEnd("`r", "`n") -eq '旧版本内容') '拒绝覆盖后原有内容被修改。'

    $forceExitCode = Invoke-PowerShellScript -Script { & $installer -SourceRoot $validRoot -TargetRoot $targetRoot -Skills 'sample-skill' -Force }
    Assert-True ($forceExitCode -eq 0) '传入 -Force 后未能覆盖已安装 Skill。'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $targetRoot 'sample-skill\legacy.txt'))) '传入 -Force 后保留了旧文件。'

    $repositorySkillRoot = Join-Path $repoRoot 'skills'
    $repositorySkillNames = @(
        'qiuzi-review-approval',
        'qiuzi-spring-boot-testing',
        'qiuzi-zh-commit',
        'qiuzi-review-staged'
    )
    $repositoryTargetRoot = Join-Path $testRoot 'repository-install-target'
    $repositoryInstallExitCode = Invoke-PowerShellScript -Script {
        & $installer `
            -SourceRoot $repositorySkillRoot `
            -TargetRoot $repositoryTargetRoot `
            -Skills $repositorySkillNames
    }
    Assert-True ($repositoryInstallExitCode -eq 0) '仓库内的 Skill 未能安装到临时目录。'
    foreach ($skillName in $repositorySkillNames) {
        Assert-True (Test-Path -LiteralPath (Join-Path $repositoryTargetRoot "$skillName\SKILL.md")) "仓库 Skill 未安装：$skillName"
    }
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

Write-Host 'test-scripts.ps1: PASS'
