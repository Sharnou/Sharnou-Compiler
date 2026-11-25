[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$testScript = Join-Path $PSScriptRoot 'Tests\Test-Stage7A.ps1'
if (-not (Test-Path -LiteralPath $testScript -PathType Leaf)) { throw "Test suite is missing: $testScript" }
try {
    & $testScript
    $collectionTest = Join-Path $PSScriptRoot 'Tests\Test-Stage5CollectionImport.ps1'
    if (-not (Test-Path -LiteralPath $collectionTest -PathType Leaf)) { throw "Stage 5 collection regression is missing: $collectionTest" }
    & $collectionTest
    Write-Host 'Combined result: PASS' -ForegroundColor Green
} catch {
    Write-Host "Combined result: FAIL - $($_.Exception.Message)" -ForegroundColor Red
    throw
}
