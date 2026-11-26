[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath([IO.Path]::Combine([string]$PSScriptRoot, '..', '..'))
$markerDirectory = [IO.Path]::Combine($repoRoot, 'Build', 'DevAgentBroker')
$markerPath = [IO.Path]::Combine($markerDirectory, 'child.pid')

# The broker fixture grants this AppContainer write access to its private Build staging directory.
# Use direct .NET file I/O so PowerShell provider startup does not consume the timeout budget.
# Do not spawn a nested process: child-process creation is intentionally not a granted capability.
[IO.File]::WriteAllText($markerPath, [string]$PID, [Text.Encoding]::ASCII)
[Console]::WriteLine('timeout-probe-started')
Start-Sleep -Seconds 30
