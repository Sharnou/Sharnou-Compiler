param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath([IO.Path]::Combine([string]$PSScriptRoot, '..', '..'))
$buildRoot = [IO.Path]::Combine($repoRoot, 'Build', 'DevAgentBroker')
$pidPath = [IO.Path]::Combine($buildRoot, 'acl-crash-child.pid')
$readyPath = [IO.Path]::Combine($buildRoot, 'acl-crash-ready.marker')

if (-not [IO.Directory]::Exists($buildRoot)) { throw 'Broker staging directory is missing.' }
[IO.File]::WriteAllText($pidPath, [string]$PID, [Text.Encoding]::ASCII)
[IO.File]::WriteAllText($readyPath, 'ready', [Text.Encoding]::ASCII)
[Console]::WriteLine('acl-crash-probe-ready')
Start-Sleep -Seconds 60
exit 0
