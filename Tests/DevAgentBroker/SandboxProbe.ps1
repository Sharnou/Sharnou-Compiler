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

    # First prove the child can write to its intended Build staging directory.
    try {
        [IO.File]::WriteAllText($buildMarker, 'appcontainer-build-write-ok')
    }
    catch {
        [Console]::Error.WriteLine(('SANDBOX_BUILD_WRITE_FAILED|{0}' -f [string]$_))
        $global:SHARNOU_TOOL_EXIT_CODE = 91
        exit 91
    }

    # Probe user-scope DPAPI through Windows PowerShell's built-in SecureString
    # serialization. Add-Type is not available in the restricted sandbox command
    # surface; ConvertFrom-SecureString exercises CurrentUser DPAPI without adding
    # any assembly or script compilation capability.
    $dpapiStatus = $null
    try {
        $dpapiPlaintext = 'appcontainer-created-dpapi-record-v1'
        $dpapiSecureString = ConvertTo-SecureString -String $dpapiPlaintext -AsPlainText -Force -ErrorAction Stop
        $dpapiEnvelopeText = ConvertFrom-SecureString -SecureString $dpapiSecureString -ErrorAction Stop
        if ([string]::IsNullOrEmpty($dpapiEnvelopeText) -or $dpapiEnvelopeText.Length -gt 65536) {
            throw 'ConvertFrom-SecureString returned an empty or over-limit DPAPI envelope.'
        }
        [IO.File]::WriteAllText($dpapiForgeryPath, $dpapiEnvelopeText, [Text.Encoding]::ASCII)
        $dpapiStatus = 'PROTECT_SUCCESS'
        [Console]::WriteLine(('SANDBOX_DPAPI_PROTECT_SUCCESS|chars={0}' -f $dpapiEnvelopeText.Length))
    }
    catch {
        $baseException = $_.Exception.GetBaseException()
        $dpapiStatus = 'PROTECT_FAILURE|{0}|0x{1:X8}|{2}' -f
            $baseException.GetType().FullName, $baseException.HResult, $baseException.Message
        [Console]::WriteLine(('SANDBOX_DPAPI_PROTECT_FAILURE|{0}' -f $dpapiStatus))
    }

    # Failure to persist the diagnostic is not converted into a generic tool
    # failure. The parent will report the probe as inconclusive if the status
    # marker cannot be read.
    try {
        [IO.File]::WriteAllText($dpapiStatusPath, $dpapiStatus, [Text.Encoding]::ASCII)
    }
    catch {
        [Console]::Error.WriteLine(('SANDBOX_DPAPI_STATUS_WRITE_FAILED|{0}' -f [string]$_))
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
    $outerError = $_.Exception.GetBaseException()
    $outerStatus = 'SANDBOX_OUTER_FAILURE|{0}|0x{1:X8}|{2}' -f
        $outerError.GetType().FullName, $outerError.HResult, $outerError.Message
    try {
        [IO.File]::WriteAllText($dpapiStatusPath, $outerStatus, [Text.Encoding]::ASCII)
    }
    catch {
        [Console]::Error.WriteLine(('SANDBOX_OUTER_STATUS_WRITE_FAILED|{0}' -f [string]$_))
    }
    [Console]::Error.WriteLine($outerStatus)
    $global:SHARNOU_TOOL_EXIT_CODE = 93
    exit 93
}
