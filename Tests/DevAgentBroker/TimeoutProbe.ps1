[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$markerDirectory = Join-Path $repoRoot 'Build\DevAgentBroker'
$markerPath = Join-Path $markerDirectory 'child.pid'
New-Item -ItemType Directory -Path $markerDirectory -Force | Out-Null

# Record this broker-owned child PID, then block until the broker timeout fires.
# This probe deliberately does not spawn another process: AppContainer child-process
# policy is a separate capability boundary and must not invalidate timeout testing.
Set-Content -LiteralPath $markerPath -Value ([string]$PID) -NoNewline -Encoding ASCII
Start-Sleep -Seconds 30
