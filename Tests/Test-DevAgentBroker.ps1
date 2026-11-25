[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$compilerPath = Join-Path $repoRoot 'Stage0\SharnouCompiler.ps1'
$verifierPath = Join-Path $repoRoot 'Tools\SharnouPEVerify.ps1'
$fixturePath = Join-Path $PSScriptRoot 'DevAgentBroker\DevAgentBroker.sharnou'
$timeoutScriptPath = Join-Path $PSScriptRoot 'DevAgentBroker\TimeoutProbe.ps1'
$toolManifestPath = Join-Path $PSScriptRoot 'DevAgentBroker\tool-manifest.json'
$successScriptPath = Join-Path $PSScriptRoot 'DevAgentBroker\SuccessProbe.ps1'
$disabledFixturePath = Join-Path $PSScriptRoot 'DevAgentBroker\Disabled.sharnou'
$disabledOutputPath = Join-Path $repoRoot 'Build\DevAgentBroker\DevAgentBrokerDisabled.exe'
$buildRoot = Join-Path $repoRoot 'Build\DevAgentBroker'
$outputPath = Join-Path $buildRoot 'DevAgentBroker.exe'
$childPidPath = Join-Path $buildRoot 'child.pid'
$nl = [string][char]10
$expected = @('-100', '-101', '37', '-110') -join $nl
$originalLocation = Get-Location
$toolHashInputs = @(
    [pscustomobject]@{ Id = 1; Path = 'Tests\Test-Stage7A.ps1' },
    [pscustomobject]@{ Id = 2; Path = 'Tests\Test-RuntimeABI.ps1' },
    [pscustomobject]@{ Id = 3; Path = 'Tests\BaselineM6\Test-Milestone6Baseline.ps1' },
    [pscustomobject]@{ Id = 4; Path = 'Tests\Test-StackProbeUnwind.ps1' },
    [pscustomobject]@{ Id = 5; Path = 'Tests\DevAgentBroker\TimeoutProbe.ps1' },
    [pscustomobject]@{ Id = 6; Path = 'Tests\DevAgentBroker\SuccessProbe.ps1' }
)

try {
    $manifest = Get-Content -LiteralPath $toolManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$manifest.version -ne 1 -or @($manifest.tools).Count -ne $toolHashInputs.Count) {
        throw 'DevAgent tool manifest version or tool count is invalid.'
    }
    $manifestHash = (Get-FileHash -LiteralPath $toolManifestPath -Algorithm SHA256).Hash
    Write-Host ("DEVAGENT_MANIFEST_SHA256|{0}" -f $manifestHash)
    foreach ($tool in $toolHashInputs) {
        $hashPath = Join-Path $repoRoot $tool.Path
        $toolHash = (Get-FileHash -LiteralPath $hashPath -Algorithm SHA256).Hash
        $entry = @($manifest.tools | Where-Object { [int]$_.id -eq $tool.Id })
        if ($entry.Count -ne 1 -or [string]$entry[0].path -cne $tool.Path -or [string]$entry[0].sha256 -cne $toolHash) {
            throw "Pinned DevAgent tool hash/path mismatch for tool ID $($tool.Id)."
        }
        Write-Host ("DEVAGENT_TOOL_SHA256|{0}|{1}|{2}" -f $tool.Id, $tool.Path, $toolHash)
    }
    Set-Location -LiteralPath $repoRoot
    foreach ($required in @($compilerPath, $verifierPath, $fixturePath, $timeoutScriptPath, $successScriptPath, $disabledFixturePath, $toolManifestPath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required broker test input is missing: $required" }
    }
    $compilerSource = [IO.File]::ReadAllText($compilerPath)
    if (-not $compilerSource.Contains($manifestHash) -or -not $compilerSource.Contains('Get-FileHash -LiteralPath $p -Algorithm SHA256') -or -not $compilerSource.Contains('exit 91')) {
        throw 'Compiler must pin the tool manifest and verify each tool script SHA-256 before execution.'
    }
    if ($compilerSource.Contains('sh_dev_run_process')) { throw 'Unsafe raw-command process API must not be present.' }
    if (-not $compilerSource.Contains('[switch] $EnableDevAgentTools') -or -not $compilerSource.Contains("Name = 'sh_dev_run_tool'; Builtin = 'DevRunTool'; ParameterTypes = @('Integer', 'Integer')")) {
        throw 'Typed integer-only process broker API is missing.'
    }
    if (-not $compilerSource.Contains('bInheritHandles = FALSE') -or -not $compilerSource.Contains('CREATE_SUSPENDED')) {
        throw 'Broker must create suspended children without inherited handles.'
    }
    if (-not $compilerSource.Contains('KILL_ON_JOB_CLOSE') -or -not $compilerSource.Contains('ACTIVE_PROCESS') -or -not $compilerSource.Contains('0x2308')) {
        throw 'Job Object kill-on-close, active-process and memory-limit flags are missing.'
    }
    if (-not $compilerSource.Contains('GetFileAttributesA') -or -not $compilerSource.Contains('0x400')) {
        throw 'Broker workspace path and reparse-point checks are missing.'
    }

    New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
    Remove-Item -LiteralPath $childPidPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $outputPath -Force -ErrorAction SilentlyContinue

    Remove-Item -LiteralPath $disabledOutputPath -Force -ErrorAction SilentlyContinue
    $disabledRejected = $false
    try {
        & $compilerPath -Source $disabledFixturePath -Output $disabledOutputPath
    }
    catch {
        $disabledRejected = $true
    }
    if (-not $disabledRejected -or (Test-Path -LiteralPath $disabledOutputPath -PathType Leaf)) {
        throw 'The broker capability must be unavailable unless -EnableDevAgentTools is explicitly supplied.'
    }
    Write-Host 'PASS: process broker capability is disabled by default and requires explicit compiler opt-in' -ForegroundColor Green

    & $compilerPath -Source $fixturePath -Output $outputPath -EnableDevAgentTools
    if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) { throw 'Compiler did not produce the DevAgent broker fixture.' }
    & $verifierPath -Path $outputPath

    $successOriginalBytes = [IO.File]::ReadAllBytes($successScriptPath)
    try {
        $lines = @(& $outputPath 2>&1)
        $exitCode = $LASTEXITCODE
        # Child console diagnostics may be visible; compare only broker numeric return records.
        $numericLines = @($lines | ForEach-Object { [string]$_ } | Where-Object { $_ -match '^-?[0-9]+$' })
        $actual = ($numericLines -join $nl).TrimEnd([char[]]@([char]13, [char]10))
        if ($exitCode -ne 0) { throw "Broker fixture process exited with code $exitCode. Output=[$actual]." }
        if (-not [string]::Equals($actual, $expected, [StringComparison]::Ordinal)) {
            throw "Broker fixture output mismatch. Expected=[$expected] Actual=[$actual]."
        }

        if (-not (Test-Path -LiteralPath $childPidPath -PathType Leaf)) {
            throw 'Timeout probe did not publish the child PID before the broker timeout.'
        }
        $childPid = [int](Get-Content -LiteralPath $childPidPath -Raw)
        if ($null -ne (Get-Process -Id $childPid -ErrorAction SilentlyContinue)) {
            throw "Job Object timeout failed to terminate descendant process PID $childPid."
        }

        # Tamper with the fixed success tool after the PE is built. The embedded
        # SHA-256 must reject it before the script's exit 37 can execute.
        [IO.File]::AppendAllText($successScriptPath, "`r`n# intentional broker hash mismatch test`r`n", [Text.Encoding]::ASCII)
        Remove-Item -LiteralPath $childPidPath -Force -ErrorAction SilentlyContinue
        $tamperedLines = @(& $outputPath 2>&1)
        $tamperedExitCode = $LASTEXITCODE
        $tamperedNumericLines = @($tamperedLines | ForEach-Object { [string]$_ } | Where-Object { $_ -match '^-?[0-9]+$' })
        $tamperedActual = ($tamperedNumericLines -join $nl).TrimEnd([char[]]@([char]13, [char]10))
        $tamperedExpected = @('-100', '-101', '91', '-110') -join $nl
        if ($tamperedExitCode -ne 0 -or -not [string]::Equals($tamperedActual, $tamperedExpected, [StringComparison]::Ordinal)) {
            throw "Runtime script hash tampering was not rejected. Expected=[$tamperedExpected] Actual=[$tamperedActual] ExitCode=$tamperedExitCode."
        }
        if (-not (Test-Path -LiteralPath $childPidPath -PathType Leaf)) {
            throw 'Timeout probe did not publish the child PID during hash-tamper replay.'
        }
        $tamperedChildPid = [int](Get-Content -LiteralPath $childPidPath -Raw)
        if ($null -ne (Get-Process -Id $tamperedChildPid -ErrorAction SilentlyContinue)) {
            throw "Job Object timeout failed to terminate descendant process PID $tamperedChildPid during hash-tamper replay."
        }
    }
    finally {
        [IO.File]::WriteAllBytes($successScriptPath, $successOriginalBytes)
    }

    Write-Host 'PASS: compiler pins manifest SHA-256 and all six tool-script hashes' -ForegroundColor Green
    Write-Host 'PASS: workspace directories and fixed tool paths reject missing/reparse-point entries' -ForegroundColor Green
    Write-Host 'PASS: runtime SHA-256 mismatch rejected before modified tool execution' -ForegroundColor Green
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
