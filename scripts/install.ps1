[CmdletBinding()]
param(
    [string]$SourceRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'skills'),
    [string]$TargetRoot = (Join-Path $HOME '.agents\skills'),
    [Parameter(Mandatory)]
    [string[]]$Skills,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$validator = Join-Path $PSScriptRoot 'validate-skills.ps1'
& $validator -SkillRoot $SourceRoot -Quiet

New-Item -ItemType Directory -Force -Path $TargetRoot | Out-Null

foreach ($skillName in $Skills) {
    if ($skillName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
        throw "非法 Skill 名称：$skillName"
    }

    $sourcePath = Join-Path $SourceRoot $skillName
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Container)) {
        throw "源 Skill 不存在：$skillName"
    }

    $destinationPath = Join-Path $TargetRoot $skillName
    if ((Test-Path -LiteralPath $destinationPath) -and -not $Force) {
        throw "目标 Skill 已存在：$destinationPath。确认覆盖后请添加 -Force。"
    }

    $stagingPath = Join-Path $TargetRoot (".$skillName.install-" + [guid]::NewGuid().ToString('N'))
    $backupPath = $null
    try {
        New-Item -ItemType Directory -Path $stagingPath | Out-Null
        Get-ChildItem -LiteralPath $sourcePath -Force | Copy-Item -Destination $stagingPath -Recurse -Force

        if (Test-Path -LiteralPath $destinationPath) {
            $backupPath = Join-Path $TargetRoot (".$skillName.backup-" + [guid]::NewGuid().ToString('N'))
            Move-Item -LiteralPath $destinationPath -Destination $backupPath
        }

        Move-Item -LiteralPath $stagingPath -Destination $destinationPath
        if ($backupPath -and (Test-Path -LiteralPath $backupPath)) {
            Remove-Item -LiteralPath $backupPath -Recurse -Force
        }
        Write-Host "已安装：$skillName -> $destinationPath"
    }
    catch {
        if ($backupPath -and (Test-Path -LiteralPath $backupPath) -and -not (Test-Path -LiteralPath $destinationPath)) {
            Move-Item -LiteralPath $backupPath -Destination $destinationPath
        }
        throw
    }
    finally {
        if (Test-Path -LiteralPath $stagingPath) {
            Remove-Item -LiteralPath $stagingPath -Recurse -Force
        }
    }
}
