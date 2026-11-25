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
    $abiTest = Join-Path $PSScriptRoot 'Tests\Test-StackProbeUnwind.ps1'
    if (-not (Test-Path -LiteralPath $abiTest -PathType Leaf)) { throw "Windows x64 stack-probe/unwind regression is missing: $abiTest" }
    & $abiTest
    $runtimeAbiTest = Join-Path $PSScriptRoot 'Tests\Test-RuntimeABI.ps1'
    if (-not (Test-Path -LiteralPath $runtimeAbiTest -PathType Leaf)) { throw "Runtime ABI regression is missing: $runtimeAbiTest" }
    & $runtimeAbiTest
    $baselineTest = Join-Path $PSScriptRoot 'Tests\BaselineM6\Test-Milestone6Baseline.ps1'
    if (-not (Test-Path -LiteralPath $baselineTest -PathType Leaf)) { throw "Frozen M1-M6 baseline regression is missing: $baselineTest" }
    & $baselineTest
    Write-Host 'Combined result: PASS' -ForegroundColor Green
} catch {
    Write-Host "Combined result: FAIL - $($_.Exception.Message)" -ForegroundColor Red
    throw
}
