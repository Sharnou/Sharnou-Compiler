param()

$ErrorActionPreference = 'Stop'

try {
    $repoRoot = [IO.Path]::GetFullPath([IO.Path]::Combine([string]$PSScriptRoot, '..', '..'))
    $buildRoot = [IO.Path]::Combine($repoRoot, 'Build', 'DevAgentBroker')
    $testToolRoot = [IO.Path]::Combine($repoRoot, 'Tests', 'DevAgentBroker')
    $buildMarker = [IO.Path]::Combine($buildRoot, 'sandbox-write-probe.ok')
    $deniedMarker = [IO.Path]::Combine($testToolRoot, 'denied-write-probe.tmp')

    try {
        [IO.File]::WriteAllText($buildMarker, 'appcontainer-build-write-ok')
    }
    catch {
        [Console]::Error.WriteLine(('SANDBOX_BUILD_WRITE_FAILED|{0}' -f [string]$_))
        $global:SHARNOU_TOOL_EXIT_CODE = 91
        exit 91
    }

    $sourceWriteDenied = $false
    try {
        [IO.File]::WriteAllText($deniedMarker, 'must-not-be-created')
    }
    catch [UnauthorizedAccessException] {
        $sourceWriteDenied = $true
    }
    catch [IO.IOException] {
        $sourceWriteDenied = $true
    }

    if (-not $sourceWriteDenied) {
        if ([IO.File]::Exists($deniedMarker)) {
            [IO.File]::Delete($deniedMarker)
        }
        [Console]::Error.WriteLine('SANDBOX_SOURCE_WRITE_WAS_ALLOWED')
        $global:SHARNOU_TOOL_EXIT_CODE = 92
        exit 92
    }

    [Console]::WriteLine('sandbox-probe-pass')
    $global:SHARNOU_TOOL_EXIT_CODE = 0
    exit 0
}
catch {
    [Console]::Error.WriteLine(('SANDBOX_UNHANDLED|{0}' -f [string]$_))
    $global:SHARNOU_TOOL_EXIT_CODE = 93
    exit 93
}
