[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
while ($true) {
    Write-Host ''
    Write-Host 'Sharnou Compiler - Milestone 7A'
    Write-Host '1) Build control-flow examples'
    Write-Host '2) Run control-flow examples'
    Write-Host '3) Test (compile, runtime, negatives, opcodes)'
    Write-Host '4) Run SharnouDevAgent test'
    Write-Host '5) Clean Stage7A build output'
    Write-Host 'Q) Quit'
    $choice = (Read-Host 'Select an option').Trim()
    if ($choice -match '^(?i:q|quit)$') { break }
    try {
        switch ($choice) {
            '1' { & (Join-Path $root 'Build.ps1') }
            '2' { & (Join-Path $root 'Run.ps1') }
            '3' { & (Join-Path $root 'Test.ps1') }
            '4' { & (Join-Path $root 'Tests\Test-DevAgent.ps1') }
            '5' {
                $build = Join-Path $root 'Build\Stage7A'
                if (Test-Path -LiteralPath $build -PathType Container) {
                    Get-ChildItem -LiteralPath $build -Force | Remove-Item -Recurse -Force
                }
                Write-Host 'Clean result: PASS' -ForegroundColor Green
            }
            default { Write-Host 'Choose 1, 2, 3, 4, 5, or Q.' -ForegroundColor Yellow }
        }
    } catch {
        Write-Host "Operation result: FAIL - $($_.Exception.Message)" -ForegroundColor Red
    }
}
