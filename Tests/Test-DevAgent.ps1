[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$agentPath = Join-Path $repoRoot 'Build\Stage7A\SharnouDevAgent.exe'

try {
    if (-not (Test-Path -LiteralPath $agentPath -PathType Leaf)) {
        throw "SharnouDevAgent.exe is missing: $agentPath. Run .\Build.ps1 first."
    }

    Write-Host '=== Running native SharnouDevAgent.exe ==='
    $lines = @(& $agentPath 2>&1)
    $exitCode = $LASTEXITCODE
    $actual = (($lines | ForEach-Object { [string]$_ }) -join [string][char]10).TrimEnd([char[]]@([char]13, [char]10))

    if ($actual.Length -gt 0) { Write-Host $actual }
    Write-Host "SharnouDevAgent process exit code: $exitCode"

    if ($exitCode -ne 0) {
        throw "SharnouDevAgent.exe exited with code $exitCode."
    }

    $requiredMarkers = @(
        'PASS: Stage 0 bootstrap compiler found',
        'PASS: Sharnou PE verifier found',
        'PASS: Stage 7A regression suite found',
        'PASS: Child process exit code 7 propagated correctly',
        'Stage 7A test result: PASS',
        'PASS: Stage 7A regression suite completed',
        'Self-hosted native SharnouCompiler.exe: NOT YET IMPLEMENTED',
        'SharnouDevAgent result: PASS'
    )
    foreach ($marker in $requiredMarkers) {
        if (-not $actual.Contains($marker)) {
            throw "SharnouDevAgent output is missing required proof marker: [$marker]. Actual output: [$actual]"
        }
    }

    Write-Host 'SharnouDevAgent test result: PASS' -ForegroundColor Green
}
catch {
    Write-Host "SharnouDevAgent test result: FAIL - $($_.Exception.Message)" -ForegroundColor Red
    throw
}
