[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$compilerPath = Join-Path $repoRoot 'Stage0\SharnouCompiler.ps1'
$verifierPath = Join-Path $repoRoot 'Tools\SharnouPEVerify.ps1'
$fixturePath = Join-Path $PSScriptRoot 'DevAgentBroker\DevAgentBroker.sharnou'
$timeoutScriptPath = Join-Path $PSScriptRoot 'DevAgentBroker\TimeoutProbe.ps1'
$buildRoot = Join-Path $repoRoot 'Build\DevAgentBroker'
$outputPath = Join-Path $buildRoot 'DevAgentBroker.exe'
$childPidPath = Join-Path $buildRoot 'child.pid'
$nl = [string][char]10
$expected = @('-100', '-101', '0', '-110') -join $nl
$originalLocation = Get-Location

try {
    Set-Location -LiteralPath $repoRoot
    foreach ($required in @($compilerPath, $verifierPath, $fixturePath, $timeoutScriptPath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required broker test input is missing: $required" }
    }
    $compilerSource = [IO.File]::ReadAllText($compilerPath)
    if ($compilerSource.Contains('sh_dev_run_process')) { throw 'Unsafe raw-command process API must not be present.' }
    if (-not $compilerSource.Contains("Name = 'sh_dev_run_tool'; Builtin = 'DevRunTool'; ParameterTypes = @('Integer', 'Integer')")) {
        throw 'Typed integer-only process broker API is missing.'
    }
    if (-not $compilerSource.Contains('bInheritHandles = FALSE') -or -not $compilerSource.Contains('CREATE_SUSPENDED')) {
        throw 'Broker must create suspended children without inherited handles.'
    }
    if (-not $compilerSource.Contains('KILL_ON_JOB_CLOSE') -or -not $compilerSource.Contains('JOB_OBJECT_LIMIT_ACTIVE_PROCESS')) {
        throw 'Job Object containment and active-process policy are missing.'
    }

    New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
    Remove-Item -LiteralPath $childPidPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $outputPath -Force -ErrorAction SilentlyContinue

    & $compilerPath -Source $fixturePath -Output $outputPath
    if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) { throw 'Compiler did not produce the DevAgent broker fixture.' }
    & $verifierPath -Path $outputPath

    $lines = @(& $outputPath 2>&1)
    $exitCode = $LASTEXITCODE
    $actual = (($lines | ForEach-Object { [string]$_ }) -join $nl).TrimEnd([char[]]@([char]13, [char]10))
    if ($exitCode -ne 0) { throw "Broker fixture process exited with code $exitCode. Output=[$actual]." }
    if (-not [string]::Equals($actual, $expected, [StringComparison]::Ordinal)) {
        throw "Broker fixture output mismatch. Expected=[$expected] Actual=[$actual]."
    }

    if (-not (Test-Path -LiteralPath $childPidPath -PathType Leaf)) {
        throw 'Timeout probe did not publish the child PID before the broker timeout.'
    }
    $childPid = [int](Get-Content -LiteralPath $childPidPath -Raw)
    $survivor = Get-Process -Id $childPid -ErrorAction SilentlyContinue
    if ($null -ne $survivor) {
        throw "Job Object timeout failed to terminate descendant process PID $childPid."
    }

    Write-Host 'PASS: unknown tool IDs rejected before process creation' -ForegroundColor Green
    Write-Host 'PASS: timeout values below policy minimum rejected' -ForegroundColor Green
    Write-Host 'PASS: fixed allowlisted Stage 7A tool launched by absolute System32 PowerShell path' -ForegroundColor Green
    Write-Host 'PASS: child process exit code propagated' -ForegroundColor Green
    Write-Host 'PASS: suspended process assigned to Job Object before resume' -ForegroundColor Green
    Write-Host 'PASS: timeout terminated the child and its spawned descendant' -ForegroundColor Green
    Write-Host 'DevAgent broker phase-1 result: PASS' -ForegroundColor Green
}
catch {
    Write-Host "DevAgent broker phase-1 result: FAIL - $($_.Exception.Message)" -ForegroundColor Red
    throw
}
finally {
    Set-Location -LiteralPath $originalLocation
}
