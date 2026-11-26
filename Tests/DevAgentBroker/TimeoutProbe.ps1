[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath([IO.Path]::Combine([string]$PSScriptRoot, '..', '..'))
$markerDirectory = [IO.Path]::Combine($repoRoot, 'Build', 'DevAgentBroker')
$markerPath = [IO.Path]::Combine($markerDirectory, 'child.pid')
$diagnosticPath = [IO.Path]::Combine($markerDirectory, 'timeout-probe-diagnostic.txt')

try {
    # Use direct .NET file I/O so PowerShell provider initialization cannot consume
    # the timeout budget. Do not spawn a nested process: it is not a granted capability.
    [IO.File]::WriteAllText($markerPath, [string]$PID, [Text.Encoding]::ASCII)
    [IO.File]::WriteAllText($diagnosticPath, ('STARTED|PID={0}|ROOT={1}' -f $PID, $repoRoot), [Text.Encoding]::UTF8)
    [Console]::WriteLine('timeout-probe-started')
    [Threading.Thread]::Sleep(30000)
    [IO.File]::WriteAllText($diagnosticPath, ('UNEXPECTED_COMPLETION|PID={0}' -f $PID), [Text.Encoding]::UTF8)
    $global:SHARNOU_TOOL_EXIT_CODE = 95
    exit 95
}
catch {
    $diagnostic = 'TIMEOUT_PROBE_EXCEPTION|' + [string]$_.Exception.ToString()
    [Console]::Error.WriteLine($diagnostic)
    try { [IO.File]::WriteAllText($diagnosticPath, $diagnostic, [Text.Encoding]::UTF8) } catch { }
    $global:SHARNOU_TOOL_EXIT_CODE = 94
    exit 94
}
