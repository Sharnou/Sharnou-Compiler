param()

$ErrorActionPreference = 'Stop'

try {
    $repoRoot = [IO.Path]::GetFullPath([IO.Path]::Combine([string]$PSScriptRoot, '..', '..'))
    $buildRoot = [IO.Path]::Combine($repoRoot, 'Build', 'DevAgentBroker')
    $testToolRoot = [IO.Path]::Combine($repoRoot, 'Tests', 'DevAgentBroker')
    $hostRoot = [IO.Path]::Combine($repoRoot, '.sharnou-devagent-host')
    $buildMarker = [IO.Path]::Combine($buildRoot, 'sandbox-write-probe.ok')
    $deniedMarker = [IO.Path]::Combine($testToolRoot, 'denied-write-probe.tmp')
    $hostDeniedMarker = [IO.Path]::Combine($hostRoot, 'sandbox-host-write-probe.tmp')
    $dpapiForgeryPath = [IO.Path]::Combine($buildRoot, 'appcontainer-dpapi-forgery.bin')
    $dpapiStatusPath = [IO.Path]::Combine($buildRoot, 'appcontainer-dpapi-status.txt')

    # Probe whether a Low-IL AppContainer process can mint a CurrentUser DPAPI
    # envelope with the same public context entropy as the trusted broker.
    # The parent test independently attempts to unprotect the result. This
    # characterizes the real sandbox boundary; it is not a production journal.
    Remove-Item -LiteralPath $dpapiForgeryPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $dpapiStatusPath -Force -ErrorAction SilentlyContinue
    try {
        Add-Type -AssemblyName System.Security -ErrorAction Stop
        $dpapiEntropy = [Text.Encoding]::UTF8.GetBytes('Sharnou.DevAgent.AuthenticatedJournal.v2|user-scope')
        $dpapiPayload = [Text.Encoding]::ASCII.GetBytes('appcontainer-created-dpapi-record-v1')
        $dpapiEnvelope = [Security.Cryptography.ProtectedData]::Protect(
            $dpapiPayload,
            $dpapiEntropy,
            [Security.Cryptography.DataProtectionScope]::CurrentUser)
        if ($dpapiEnvelope.Length -lt 32 -or $dpapiEnvelope.Length -gt 65536) {
            throw 'DPAPI returned an envelope outside the bounded test range.'
        }
        [IO.File]::WriteAllBytes($dpapiForgeryPath, $dpapiEnvelope)
        [IO.File]::WriteAllText($dpapiStatusPath, 'PROTECT_SUCCESS', [Text.Encoding]::ASCII)
        [Console]::WriteLine(('SANDBOX_DPAPI_PROTECT_SUCCESS|bytes={0}' -f $dpapiEnvelope.Length))
    }
    catch {
        $baseException = $_.Exception.GetBaseException()
        $status = 'PROTECT_FAILURE|{0}|0x{1:X8}' -f $baseException.GetType().FullName, $baseException.HResult
        [IO.File]::WriteAllText($dpapiStatusPath, $status, [Text.Encoding]::ASCII)
        [Console]::WriteLine(('SANDBOX_DPAPI_PROTECT_FAILURE|{0}' -f $status))
    }

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

    $hostWriteDenied = $false
    try {
        [IO.File]::WriteAllText($hostDeniedMarker, 'must-not-be-created')
    }
    catch [UnauthorizedAccessException] {
        $hostWriteDenied = $true
    }
    catch [IO.IOException] {
        $hostWriteDenied = $true
    }

    if (-not $hostWriteDenied) {
        if ([IO.File]::Exists($hostDeniedMarker)) {
            [IO.File]::Delete($hostDeniedMarker)
        }
        [Console]::Error.WriteLine('SANDBOX_HOST_DIRECTORY_WRITE_WAS_ALLOWED')
        $global:SHARNOU_TOOL_EXIT_CODE = 94
        exit 94
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
