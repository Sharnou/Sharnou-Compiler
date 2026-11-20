[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$testScripts = @(
    (Join-Path $PSScriptRoot 'Tests\Test-Stage7A.ps1'),
    (Join-Path $PSScriptRoot 'Tests\Test-Stage7B.ps1')
)
try {
    foreach ($testScript in $testScripts) {
        if (-not (Test-Path -LiteralPath $testScript -PathType Leaf)) { throw "Test suite is missing: $testScript" }
        & $testScript
    }
    Write-Host 'Combined result: PASS' -ForegroundColor Green
} catch {
    Write-Host "Combined result: FAIL - $($_.Exception.Message)" -ForegroundColor Red
    throw
}
