[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$markerDirectory = Join-Path $repoRoot 'Build\DevAgentBroker'
$markerPath = Join-Path $markerDirectory 'child.pid'
New-Item -ItemType Directory -Path $markerDirectory -Force | Out-Null

# Start the descendant directly through CreateProcess. Windows PowerShell 5.1
# runs on .NET Framework, where ProcessStartInfo.UseShellExecute defaults to
# true; ShellExecute is not the process-creation path being tested inside an
# AppContainer. Explicitly select direct executable creation and inherit only
# the parent's standard handles so the Job Object and broker pipe cover it.
$childHost = Join-Path $PSHOME 'powershell.exe'
$startInfo = New-Object System.Diagnostics.ProcessStartInfo
$startInfo.FileName = $childHost
$startInfo.Arguments = '-NoLogo -NoProfile -NonInteractive -Command "Start-Sleep -Seconds 30"'
$startInfo.WorkingDirectory = $markerDirectory
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$child = [System.Diagnostics.Process]::Start($startInfo)
if ($null -eq $child) { throw 'CreateProcess returned no descendant Process object.' }

try {
    Set-Content -LiteralPath $markerPath -Value ([string]$child.Id) -NoNewline -Encoding ASCII
    Start-Sleep -Seconds 30
}
finally {
    $child.Dispose()
}
