[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$markerDirectory = Join-Path $repoRoot 'Build\DevAgentBroker'
$markerPath = Join-Path $markerDirectory 'child.pid'
New-Item -ItemType Directory -Path $markerDirectory -Force | Out-Null

$childHost = Join-Path $PSHOME 'powershell.exe'
$child = Start-Process -FilePath $childHost -ArgumentList '-NoLogo -NoProfile -NonInteractive -Command "Start-Sleep -Seconds 30"' -WindowStyle Hidden -PassThru
Set-Content -LiteralPath $markerPath -Value ([string]$child.Id) -NoNewline -Encoding ASCII
Start-Sleep -Seconds 30
