[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$testScript = Join-Path $PSScriptRoot 'Tests\Test-Stage7A.ps1'
$agentTestScript = Join-Path $PSScriptRoot 'Tests\Test-DevAgent.ps1'
if (-not (Test-Path -LiteralPath $testScript -PathType Leaf)) { throw "Test suite is missing: $testScript" }
if (-not (Test-Path -LiteralPath $agentTestScript -PathType Leaf)) { throw "DevAgent test suite is missing: $agentTestScript" }
try {
    & $testScript
    & $agentTestScript
    Write-Host 'Combined result: PASS' -ForegroundColor Green
} catch {
    Write-Host "Combined result: FAIL - $($_.Exception.Message)" -ForegroundColor Red
    throw
}
