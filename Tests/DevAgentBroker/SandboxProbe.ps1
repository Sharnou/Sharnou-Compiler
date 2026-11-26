[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$buildRoot = Join-Path $repoRoot 'Build\DevAgentBroker'
$buildMarker = Join-Path $buildRoot 'sandbox-write-probe.ok'
$deniedMarker = Join-Path $repoRoot 'Tests\DevAgentBroker\denied-write-probe.tmp'

try {
    [IO.File]::WriteAllText($buildMarker, 'appcontainer-build-write-ok')
}
catch {
    $global:SHARNOU_TOOL_EXIT_CODE = 91
    exit 91
}

$sourceWriteSucceeded = $false
try {
    [IO.File]::WriteAllText($deniedMarker, 'must-not-be-created')
    $sourceWriteSucceeded = $true
}
catch {
    $sourceWriteSucceeded = $false
}

if ($sourceWriteSucceeded) {
    Remove-Item -LiteralPath $deniedMarker -Force -ErrorAction SilentlyContinue
    $global:SHARNOU_TOOL_EXIT_CODE = 92
    exit 92
}

[Console]::WriteLine('sandbox-probe-pass')
$global:SHARNOU_TOOL_EXIT_CODE = 0
