[CmdletBinding()]
param(
    [string]$SkillRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'skills'),
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$issues = [System.Collections.Generic.List[string]]::new()
$credentialPattern = '(?im)(?:^|[\s;])(?:export\s+)?(?:[A-Za-z_$][A-Za-z0-9_$]*\.)*(?:api[_-]?key|client[_-]?secret|(?:aws[_-]?)?secret(?:[_-]?(?:access[_-]?key|key))?|private[_-]?key|password|(?:access|refresh)[_-]?token|(?:[A-Za-z0-9_$]*[_-])?token|authorization)\b\s*(?:=(?!=)|:(?!:))\s*["'']?\S+'
$pemPrivateKeyPattern = '(?im)^-----BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY-----$'

function Add-Issue {
    param([string]$Message)
    [void]$issues.Add($Message)
}

if (-not (Test-Path -LiteralPath $SkillRoot -PathType Container)) {
    Add-Issue "Skill 根目录不存在：$SkillRoot"
}
else {
    $skillDirectories = @(Get-ChildItem -LiteralPath $SkillRoot -Directory -Force)
    if ($skillDirectories.Count -eq 0) {
        Add-Issue "Skill 根目录未包含任何 Skill：$SkillRoot"
    }

    foreach ($skillDirectory in $skillDirectories) {
        $skillFile = Join-Path $skillDirectory.FullName 'SKILL.md'
        if (-not (Test-Path -LiteralPath $skillFile -PathType Leaf)) {
            Add-Issue "$($skillDirectory.Name)：缺少 SKILL.md"
            continue
        }

        $skillContent = [System.IO.File]::ReadAllText($skillFile)
        $frontMatter = [regex]::Match(
            $skillContent,
            '\A---\s*\r?\n(?<content>.*?)\r?\n---(?:\r?\n|$)',
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        )
        if (-not $frontMatter.Success) {
            Add-Issue "$($skillDirectory.Name)：SKILL.md 缺少有效的 YAML front matter"
        }
        else {
            $nameMatch = [regex]::Match(
                $frontMatter.Groups['content'].Value,
                '(?m)^\s*name\s*:\s*(?<name>.+?)\s*$'
            )
            if (-not $nameMatch.Success) {
                Add-Issue "$($skillDirectory.Name)：SKILL.md front matter 缺少 name"
            }
            else {
                $declaredName = $nameMatch.Groups['name'].Value.Trim().Trim('"').Trim("'")
                if ($declaredName -ne $skillDirectory.Name) {
                    Add-Issue "$($skillDirectory.Name)：目录名与 front matter name 不一致（$declaredName）"
                }
            }
        }

        $files = @(Get-ChildItem -LiteralPath $skillDirectory.FullName -File -Recurse -Force)
        foreach ($file in $files) {
            if ($file.Name -match '(?i)^(?:\.env(?:\..*)?|.*\.(?:pem|key|pfx|p12)|(?:credentials?|secrets?|tokens?)(?:\..*)?)$') {
                Add-Issue "$($skillDirectory.Name)：包含禁止提交的敏感文件名 $($file.Name)"
                continue
            }

            if ($file.Extension -in @('.png', '.jpg', '.jpeg', '.gif', '.webp', '.pdf', '.zip', '.7z', '.dll', '.exe')) {
                continue
            }

            $fileContent = [System.IO.File]::ReadAllText($file.FullName)
            if ($fileContent -match $credentialPattern -or $fileContent -match $pemPrivateKeyPattern) {
                Add-Issue "$($skillDirectory.Name)：$($file.FullName) 包含疑似凭据赋值"
            }
        }
    }
}

if ($issues.Count -gt 0) {
    $message = "Skill 校验失败：`n" + ($issues -join "`n")
    if ($Quiet) {
        throw "Skill 校验失败，共 $($issues.Count) 项。"
    }
    throw $message
}

if (-not $Quiet) {
    Write-Host "Skill 校验通过：$SkillRoot"
}
