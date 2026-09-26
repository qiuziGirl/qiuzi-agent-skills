#Requires -Version 5.1
<#
.SYNOPSIS
  查询 Cursor 当前计费周期内的真实消费额度。

.DESCRIPTION
  调用 usage-summary 与 get-aggregated-usage-events，输出 Included 额度、
  真实消费金额和按模型明细。认证自动从 Cursor IDE 本地登录状态读取。

.PARAMETER Json
  输出原始 JSON 结构，供自动化消费。
#>
[CmdletBinding()]
param(
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$queryScript = Join-Path $PSScriptRoot 'query-usage.py'
if (-not (Test-Path $queryScript)) {
    Write-Error "未找到查询脚本：$queryScript"
    exit 1
}

$pythonCommands = @('python', 'python3', 'py')
$pythonExe = $null
foreach ($pythonCommand in $pythonCommands) {
    $command = Get-Command $pythonCommand -ErrorAction SilentlyContinue
    if ($command) {
        $pythonExe = $command.Source
        break
    }
}

if (-not $pythonExe) {
    Write-Error '未找到 Python，请安装 Python 3 后重试。'
    exit 1
}

$arguments = @($queryScript)
if ($Json) {
    $arguments += '--json'
}

& $pythonExe @arguments
exit $LASTEXITCODE
