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
    $brokerTest = Join-Path $PSScriptRoot 'Tests\Test-DevAgentBroker.ps1'
    if (-not (Test-Path -LiteralPath $brokerTest -PathType Leaf)) { throw "DevAgent broker regression is missing: $brokerTest" }
    & $brokerTest
    $identityTest = Join-Path $PSScriptRoot 'Tests\Test-DevAgentExecutionIdentity.ps1'
    if (-not (Test-Path -LiteralPath $identityTest -PathType Leaf)) { throw "DevAgent execution identity test is missing: $identityTest" }
    & $identityTest
    $journalTest = Join-Path $PSScriptRoot 'Tests\Test-DevAgentAuthenticatedJournal.ps1'
    if (-not (Test-Path -LiteralPath $journalTest -PathType Leaf)) { throw "DevAgent authenticated-journal test is missing: $journalTest" }
    & $journalTest
    $environmentTest = Join-Path $PSScriptRoot 'Tests\Test-DevAgentEnvironmentBlock.ps1'
    if (-not (Test-Path -LiteralPath $environmentTest -PathType Leaf)) { throw "DevAgent explicit environment test is missing: $environmentTest" }
    & $environmentTest
    $appContainerLaunchTest = Join-Path $PSScriptRoot 'Tests\Test-DevAgentAppContainerLaunch.ps1'
    if (-not (Test-Path -LiteralPath $appContainerLaunchTest -PathType Leaf)) { throw "DevAgent AppContainer launch test is missing: $appContainerLaunchTest" }
    & $appContainerLaunchTest
    $outputStreamsTest = Join-Path $PSScriptRoot 'Tests\Test-DevAgentOutputStreams.ps1'
    if (-not (Test-Path -LiteralPath $outputStreamsTest -PathType Leaf)) { throw "DevAgent split-stream test is missing: $outputStreamsTest" }
    & $outputStreamsTest
    $authorityProtocolTest = Join-Path $PSScriptRoot 'Tests\Test-DevAgentAuthorityProtocol.ps1'
    if (-not (Test-Path -LiteralPath $authorityProtocolTest -PathType Leaf)) { throw "DevAgent authority IPC protocol test is missing: $authorityProtocolTest" }
    & $authorityProtocolTest
    $baselineTest = Join-Path $PSScriptRoot 'Tests\BaselineM6\Test-Milestone6Baseline.ps1'
    if (-not (Test-Path -LiteralPath $baselineTest -PathType Leaf)) { throw "Frozen M1-M6 baseline regression is missing: $baselineTest" }
    & $baselineTest
    Write-Host 'Combined result: PASS' -ForegroundColor Green
} catch {
    Write-Host "Combined result: FAIL - $($_.Exception.Message)" -ForegroundColor Red
    throw
}
