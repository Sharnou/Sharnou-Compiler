[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$source = Join-Path $repoRoot 'Examples\NativeScmServiceHost.sharnou'
$compiler = Join-Path $repoRoot 'Stage0\SharnouCompiler.ps1'
$verifier = Join-Path $repoRoot 'Tools\SharnouPEVerify.ps1'
$relocations = Join-Path $repoRoot 'Tools\SharnouPERelocations.ps1'
$required = @($source, $compiler, $verifier, $relocations)
foreach ($path in $required) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required R5.1.c input is missing: $path"
    }
}

if (-not [Environment]::Is64BitOperatingSystem) {
    throw 'R5.1.c SCM qualification requires a 64-bit Windows runner.'
}
if ($env:OS -ne 'Windows_NT') {
    throw 'R5.1.c SCM qualification must run on Windows.'
}

$expectedHead = [string]$env:EXPECTED_TESTED_SHA
$testedHead = (& git -C $repoRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $testedHead -notmatch '^[0-9a-f]{40}$') {
    throw 'Could not resolve the exact tested Git commit.'
}
if (-not [string]::IsNullOrEmpty($expectedHead) -and $testedHead -cne $expectedHead) {
    throw "Exact-head mismatch: expected=$expectedHead actual=$testedHead"
}

$buildRoot = Join-Path $repoRoot 'Build\R51C'
New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
$output = Join-Path $buildRoot 'SharnouAuthorityHost.exe'
$evidencePath = Join-Path $buildRoot 'r5-1c-evidence.json'
$transcriptPath = Join-Path $buildRoot 'r5-1c-transcript.txt'
$serviceName = 'SharnouR51C_' + [Guid]::NewGuid().ToString('N').Substring(0, 12)
$sc = Join-Path $env:WINDIR 'System32\sc.exe'
if (-not (Test-Path -LiteralPath $sc -PathType Leaf)) {
    throw 'The Windows Service Control utility sc.exe is unavailable.'
}

$serviceCreated = $false
$transcriptStarted = $false
$observations = [ordered]@{}
$manifest = $null

function Invoke-ScCommand {
    param(
        [Parameter(Mandatory = $true)][string[]] $Arguments,
        [switch] $AllowFailure
    )
    $lines = @(& $script:ScPath @Arguments 2>&1 | ForEach-Object { [string]$_ })
    $code = $LASTEXITCODE
    $rendered = $lines -join [Environment]::NewLine
    Write-Host ("sc.exe {0} (exit={1})" -f ($Arguments -join ' '), $code)
    if (-not [string]::IsNullOrEmpty($rendered)) { Write-Host $rendered }
    if ($code -ne 0 -and -not $AllowFailure) {
        throw ("sc.exe failed with exit code {0}: {1}" -f $code, ($Arguments -join ' '))
    }
    return [pscustomobject]@{ ExitCode = $code; Output = $rendered }
}

function Wait-ServiceState {
    param(
        [Parameter(Mandatory = $true)][string] $ExpectedState,
        [int] $TimeoutSeconds = 25
    )
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $service = Get-Service -Name $script:ServiceName -ErrorAction SilentlyContinue
        if ($null -ne $service -and $service.Status.ToString() -ceq $ExpectedState) {
            return $service
        }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $deadline)

    $diagnostic = Invoke-ScCommand -Arguments @('queryex', $script:ServiceName) -AllowFailure
    throw ("Service did not reach state '{0}' within {1} seconds. Last SCM result: {2}" -f $ExpectedState, $TimeoutSeconds, $diagnostic.Output)
}

$script:ScPath = $sc
$script:ServiceName = $serviceName

try {
    Start-Transcript -LiteralPath $transcriptPath -Force | Out-Null
    $transcriptStarted = $true

    Write-Host 'R5.1.c: compile genuine Sharnou source into a native SCM service image.'
    $sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    $compilerHash = (Get-FileHash -LiteralPath $compiler -Algorithm SHA256).Hash
    $verifierHash = (Get-FileHash -LiteralPath $verifier -Algorithm SHA256).Hash
    $relocationHash = (Get-FileHash -LiteralPath $relocations -Algorithm SHA256).Hash

    if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output -Force }
    & $compiler -Source $source -Output $output -EnableNativeScmServiceHost -NativeScmServiceName $serviceName
    if (-not (Test-Path -LiteralPath $output -PathType Leaf)) {
        throw 'Sharnou compiler did not produce the native SCM service executable.'
    }

    Write-Host 'R5.1.c: independently verify the generated PE import table, relocations and service table.'
    & $verifier -Path $output -NativeScmServiceHost
    $executableHash = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
    $observations.SourceSha256 = $sourceHash
    $observations.CompilerSha256 = $compilerHash
    $observations.VerifierSha256 = $verifierHash
    $observations.RelocationToolSha256 = $relocationHash
    $observations.ExecutableSha256 = $executableHash
    $observations.ExecutableBytes = (Get-Item -LiteralPath $output).Length
    $observations.ExecutablePath = $output

    Write-Host 'R5.1.c: create a uniquely named disposable own-process service.'
    $binPath = 'binPath= "' + $output + '"'
    $create = Invoke-ScCommand -Arguments @('create', $serviceName, $binPath, 'start= demand', 'type= own', 'DisplayName= ' + $serviceName)
    $serviceCreated = $true
    $observations.ServiceCreate = $create.Output
    $observations.ServiceConfig = (Invoke-ScCommand -Arguments @('qc', $serviceName)).Output

    Write-Host 'R5.1.c: start through the actual Windows Service Control Manager.'
    $start = Invoke-ScCommand -Arguments @('start', $serviceName)
    $observations.ServiceStart = $start.Output
    $running = Wait-ServiceState -ExpectedState 'Running' -TimeoutSeconds 25
    $observations.RunningState = $running.Status.ToString()
    $observations.RunningQuery = (Invoke-ScCommand -Arguments @('queryex', $serviceName)).Output

    Write-Host 'R5.1.c: send SERVICE_CONTROL_INTERROGATE and verify the service remains running.'
    $interrogate = Invoke-ScCommand -Arguments @('interrogate', $serviceName)
    $observations.Interrogate = $interrogate.Output
    $running = Wait-ServiceState -ExpectedState 'Running' -TimeoutSeconds 10

    Write-Host 'R5.1.c: request STOP and verify SCM observes STOPPED.'
    $stop = Invoke-ScCommand -Arguments @('stop', $serviceName)
    $observations.ServiceStop = $stop.Output
    $stopped = Wait-ServiceState -ExpectedState 'Stopped' -TimeoutSeconds 25
    $observations.StoppedState = $stopped.Status.ToString()
    $observations.StoppedQuery = (Invoke-ScCommand -Arguments @('queryex', $serviceName)).Output

    if ($observations.StoppedQuery -notmatch '(?im)^\s*PID\s*:\s*0\s*$') {
        throw 'SCM reports STOPPED but the service process identifier is not zero.'
    }

    Write-Host 'R5.1.c: delete the disposable service registration.'
    $delete = Invoke-ScCommand -Arguments @('delete', $serviceName)
    $observations.ServiceDelete = $delete.Output
    $serviceCreated = $false

    $absent = $false
    $deleteDeadline = [DateTime]::UtcNow.AddSeconds(15)
    do {
        $remaining = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($null -eq $remaining) { $absent = $true; break }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $deleteDeadline)
    if (-not $absent) {
        throw 'Disposable service registration remains visible after sc.exe delete.'
    }

    $manifest = [ordered]@{
        schema = 'sharnou.phase-2b8.r5-1c.evidence.v1'
        acceptance = 'PASS'
        acceptance_scope = 'R5.1.c native Sharnou SCM service image generation, PE verification, real SCM start/interrogate/stop and disposable service cleanup'
        tested_commit = $testedHead
        expected_tested_commit = $expectedHead
        service_name = $serviceName
        platform = [Environment]::OSVersion.VersionString
        is_64bit_os = [Environment]::Is64BitOperatingSystem
        executable = $observations
        scm = @{
            running_state = $observations.RunningState
            stopped_state = $observations.StoppedState
            stopped_pid_zero = $true
            service_registration_removed = $true
        }
        imports = @(
            'KERNEL32.dll!ExitProcess',
            'KERNEL32.dll!GetLastError',
            'KERNEL32.dll!CreateEventW',
            'KERNEL32.dll!SetEvent',
            'KERNEL32.dll!WaitForSingleObject',
            'KERNEL32.dll!CloseHandle',
            'ADVAPI32.dll!StartServiceCtrlDispatcherW',
            'ADVAPI32.dll!RegisterServiceCtrlHandlerExW',
            'ADVAPI32.dll!SetServiceStatus'
        )
        later_qualification_required = 'R5.1.d must independently cover startup/shutdown/failure injection/repeated lifecycle/orphan cleanup before R5.2.'
        model_facing_execution = 'DISABLED'
        autonomous_execution = 'DISABLED'
    }
    [IO.File]::WriteAllText($evidencePath, ($manifest | ConvertTo-Json -Depth 8), [Text.Encoding]::ASCII)
    Write-Host ("R5.1.c SCM smoke qualification: PASS; service={0}; executable SHA-256={1}" -f $serviceName, $executableHash)
}
finally {
    if ($serviceCreated) {
        $existing = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($null -ne $existing -and $existing.Status.ToString() -ne 'Stopped') {
            $null = Invoke-ScCommand -Arguments @('stop', $serviceName) -AllowFailure
            try { $null = Wait-ServiceState -ExpectedState 'Stopped' -TimeoutSeconds 20 } catch { Write-Warning $_.Exception.Message }
        }
        $null = Invoke-ScCommand -Arguments @('delete', $serviceName) -AllowFailure
    }
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}
