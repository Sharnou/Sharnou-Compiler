[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$source = Join-Path $repoRoot 'Examples\NativeScmServiceHost.sharnou'
$compiler = Join-Path $repoRoot 'Stage0\SharnouCompiler.ps1'
$verifier = Join-Path $repoRoot 'Tools\SharnouPEVerify.ps1'
$relocations = Join-Path $repoRoot 'Tools\SharnouPERelocations.ps1'
foreach ($path in @($source, $compiler, $verifier, $relocations)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required R5.1.d input is missing: $path"
    }
}
if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitOperatingSystem) {
    throw 'R5.1.d requires a 64-bit Windows runner.'
}

$testedHead = (& git -C $repoRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $testedHead -notmatch '^[0-9a-f]{40}$') {
    throw 'Could not resolve the exact R5.1.d tested Git commit.'
}
$expectedHead = [string]$env:EXPECTED_TESTED_SHA
if (-not [string]::IsNullOrEmpty($expectedHead) -and $testedHead -cne $expectedHead) {
    throw "Exact-head mismatch: expected=$expectedHead actual=$testedHead"
}

$buildRoot = Join-Path $repoRoot 'Build\R51D'
$evidenceRoot = Join-Path $buildRoot 'Evidence'
New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
$sc = Join-Path $env:WINDIR 'System32\sc.exe'
if (-not (Test-Path -LiteralPath $sc -PathType Leaf)) {
    throw 'Windows Service Control utility is unavailable.'
}

$script:ScPath = $sc
$script:Evidence = [System.Collections.Generic.List[object]]::new()
$script:Images = [System.Collections.Generic.List[object]]::new()
$script:Services = [System.Collections.Generic.List[string]]::new()
$script:ScSequence = 0

function Invoke-ScCommand {
    param(
        [Parameter(Mandatory = $true)][string[]] $Arguments,
        [switch] $AllowFailure
    )
    $lines = @(& $script:ScPath @Arguments 2>&1 | ForEach-Object { [string]$_ })
    $code = $LASTEXITCODE
    $rendered = $lines -join [Environment]::NewLine
    $script:Evidence.Add([pscustomobject]@{
        timestamp_utc = [DateTime]::UtcNow.ToString('o')
        command = 'sc.exe ' + ($Arguments -join ' ')
        exit_code = $code
        output = $rendered
    })
    if ($code -ne 0 -and -not $AllowFailure) {
        throw ("sc.exe failed ({0}): {1}{2}{3}" -f $code, ($Arguments -join ' '), [Environment]::NewLine, $rendered)
    }
    return [pscustomobject]@{ ExitCode = $code; Output = $rendered }
}

function Start-ScAsync {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('start', 'stop')][string] $Verb,
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][string] $Tag
    )
    $script:ScSequence++
    $stdout = Join-Path $evidenceRoot ("{0}-{1:D3}.stdout.txt" -f $Tag, $script:ScSequence)
    $stderr = Join-Path $evidenceRoot ("{0}-{1:D3}.stderr.txt" -f $Tag, $script:ScSequence)
    $process = Start-Process -FilePath $script:ScPath -ArgumentList @($Verb, $Name) -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    return [pscustomobject]@{ Process = $process; Stdout = $stdout; Stderr = $stderr; Verb = $Verb; Name = $Name }
}

function Complete-ScAsync {
    param([Parameter(Mandatory = $true)][object] $Operation, [int] $TimeoutSeconds = 20)
    if (-not $Operation.Process.WaitForExit($TimeoutSeconds * 1000)) {
        Stop-Process -Id $Operation.Process.Id -Force -ErrorAction SilentlyContinue
        throw "sc.exe $($Operation.Verb) $($Operation.Name) exceeded its $TimeoutSeconds second bound."
    }
    $stdoutText = if (Test-Path -LiteralPath $Operation.Stdout) { Get-Content -LiteralPath $Operation.Stdout -Raw } else { '' }
    $stderrText = if (Test-Path -LiteralPath $Operation.Stderr) { Get-Content -LiteralPath $Operation.Stderr -Raw } else { '' }
    $record = [pscustomobject]@{
        timestamp_utc = [DateTime]::UtcNow.ToString('o')
        command = "sc.exe $($Operation.Verb) $($Operation.Name)"
        exit_code = $Operation.Process.ExitCode
        stdout = $stdoutText
        stderr = $stderrText
    }
    $script:Evidence.Add($record)
    return $record
}

function Convert-ScNumber {
    param([Parameter(Mandatory = $true)][string] $Value)
    if ($Value.StartsWith('0x', [StringComparison]::OrdinalIgnoreCase)) {
        return [UInt32]::Parse($Value.Substring(2), [Globalization.NumberStyles]::HexNumber)
    }
    return [UInt32]::Parse($Value, [Globalization.NumberStyles]::Integer)
}

function Get-ScField {
    param([string] $Text, [string] $Field)
    $pattern = '(?im)^\s*' + [Regex]::Escape($Field) + '\s*:\s*(0x[0-9a-f]+|\d+)'
    $match = [Regex]::Match($Text, $pattern)
    if (-not $match.Success) { throw "SCM query omitted numeric field '$Field'." }
    return Convert-ScNumber -Value $match.Groups[1].Value
}

function Get-ServiceSnapshot {
    param([Parameter(Mandatory = $true)][string] $Name)
    $query = Invoke-ScCommand -Arguments @('queryex', $Name)
    $stateMatch = [Regex]::Match($query.Output, '(?im)^\s*STATE\s*:\s*(\d+)\s+([A-Z_]+)')
    if (-not $stateMatch.Success) {
        throw "Could not parse SCM service state for '$Name'. $($query.Output)"
    }
    $flagsMatch = [Regex]::Match($query.Output, '(?im)^\s*\(([^)]*)\)')
    $snapshot = [pscustomobject]@{
        Name = $Name
        StateCode = [UInt32]$stateMatch.Groups[1].Value
        State = $stateMatch.Groups[2].Value
        Win32ExitCode = Get-ScField -Text $query.Output -Field 'WIN32_EXIT_CODE'
        ServiceExitCode = Get-ScField -Text $query.Output -Field 'SERVICE_EXIT_CODE'
        Checkpoint = Get-ScField -Text $query.Output -Field 'CHECKPOINT'
        WaitHint = Get-ScField -Text $query.Output -Field 'WAIT_HINT'
        ProcessId = Get-ScField -Text $query.Output -Field 'PID'
        Flags = if ($flagsMatch.Success) { $flagsMatch.Groups[1].Value } else { '' }
        Raw = $query.Output
    }
    $script:Evidence.Add([pscustomobject]@{
        timestamp_utc = [DateTime]::UtcNow.ToString('o')
        service = $Name
        observation = 'SCM_QUERYEX'
        state = $snapshot.State
        state_code = $snapshot.StateCode
        checkpoint = $snapshot.Checkpoint
        wait_hint_ms = $snapshot.WaitHint
        controls = $snapshot.Flags
        win32_exit_code = $snapshot.Win32ExitCode
        service_exit_code = $snapshot.ServiceExitCode
        process_id = $snapshot.ProcessId
        raw = $snapshot.Raw
    })
    return $snapshot
}

function Test-PendingSnapshot {
    param(
        [Parameter(Mandatory = $true)][object] $Snapshot,
        [Parameter(Mandatory = $true)][ValidateSet(2, 3)][int] $PendingState
    )
    # SCM first exposes a short framework-owned pending state before the service
    # has published its first SERVICE_STATUS. It is not accepted as the service's
    # checkpoint/wait-hint report; observe it, then keep polling for our exact tuple.
    $isFrameworkStart = $PendingState -eq 2 -and $Snapshot.Checkpoint -eq 0 -and $Snapshot.WaitHint -eq 2000
    $isFrameworkStop = $PendingState -eq 3 -and $Snapshot.Checkpoint -eq 0 -and $Snapshot.WaitHint -eq 0
    if ($isFrameworkStart -or $isFrameworkStop) {
        $script:Evidence.Add([pscustomobject]@{
            timestamp_utc = [DateTime]::UtcNow.ToString('o')
            service = $Snapshot.Name
            observation = 'SCM_FRAMEWORK_PENDING_BEFORE_SERVICE_STATUS'
            state = $Snapshot.State
            checkpoint = $Snapshot.Checkpoint
            wait_hint_ms = $Snapshot.WaitHint
            accepted_as_service_report = $false
        })
        return $false
    }

    if ($PendingState -eq 2) {
        if ($Snapshot.Checkpoint -ne 1 -or $Snapshot.WaitHint -ne 10000) {
            throw "START_PENDING service status invalid: checkpoint=$($Snapshot.Checkpoint), waitHint=$($Snapshot.WaitHint)."
        }
    } else {
        if ($Snapshot.Checkpoint -ne 1 -or $Snapshot.WaitHint -ne 5000) {
            throw "STOP_PENDING service status invalid: checkpoint=$($Snapshot.Checkpoint), waitHint=$($Snapshot.WaitHint)."
        }
    }
    if ($Snapshot.Flags -notmatch 'NOT_STOPPABLE' -or $Snapshot.Flags -match 'ACCEPTS_SHUTDOWN') {
        throw "$($Snapshot.State) advertised controls while pending: '$($Snapshot.Flags)'."
    }
    return $true
}

function Assert-RunningSnapshot {
    param([Parameter(Mandatory = $true)][object] $Snapshot)
    if ($Snapshot.ProcessId -eq 0) { throw 'RUNNING service did not expose a live process ID.' }
    if ($Snapshot.Checkpoint -ne 0 -or $Snapshot.WaitHint -ne 0) {
        throw "RUNNING did not clear checkpoint/wait hint."
    }
    if ($Snapshot.Flags -notmatch 'STOPPABLE' -or $Snapshot.Flags -match 'NOT_STOPPABLE' -or
        $Snapshot.Flags -notmatch 'ACCEPTS_SHUTDOWN') {
        throw "RUNNING did not advertise STOP and SHUTDOWN acceptance: '$($Snapshot.Flags)'."
    }
    if ($Snapshot.Win32ExitCode -ne 0 -or $Snapshot.ServiceExitCode -ne 0) {
        throw 'RUNNING reports a nonzero service exit status.'
    }
}

function Wait-ServiceState {
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][ValidateSet(1, 4)][int] $ExpectedState,
        [int] $TimeoutSeconds = 20,
        [switch] $RequireStartPending,
        [switch] $RequireStopPending,
        [switch] $SkipPendingValidation
    )
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $sawStartPending = $false
    $sawStopPending = $false
    $last = $null
    do {
        $last = Get-ServiceSnapshot -Name $Name
        if ($last.StateCode -eq 2) {
            if (-not $SkipPendingValidation -and (Test-PendingSnapshot -Snapshot $last -PendingState 2)) {
                $sawStartPending = $true
            }
        } elseif ($last.StateCode -eq 3) {
            if (-not $SkipPendingValidation -and (Test-PendingSnapshot -Snapshot $last -PendingState 3)) {
                $sawStopPending = $true
            }
        } elseif ($last.StateCode -eq 4) {
            Assert-RunningSnapshot -Snapshot $last
        }
        if ($last.StateCode -eq $ExpectedState) {
            if ($RequireStartPending -and -not $sawStartPending) { throw "START_PENDING was not observed for '$Name'." }
            if ($RequireStopPending -and -not $sawStopPending) { throw "STOP_PENDING was not observed for '$Name'." }
            return $last
        }
        Start-Sleep -Milliseconds 75
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Service '$Name' did not reach state $ExpectedState within $TimeoutSeconds seconds. Last query: $($last.Raw)"
}

function Wait-ProcessGone {
    param([Parameter(Mandatory = $true)][UInt32] $ProcessId, [int] $TimeoutSeconds = 10)
    if ($ProcessId -eq 0) { return }
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $existing = Get-Process -Id ([int]$ProcessId) -ErrorAction SilentlyContinue
        if ($null -eq $existing) { return }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Service process $ProcessId remains alive after SCM reported STOPPED."
}

function Assert-TestCompilerGuards {
    $probeOutput = Join-Path $buildRoot 'must-not-be-generated.exe'
    if (Test-Path -LiteralPath $probeOutput) { Remove-Item -LiteralPath $probeOutput -Force }

    $rejectedWithoutHost = $false
    try {
        & $compiler -Source $source -Output $probeOutput -EnableNativeScmServiceTestMode
    } catch {
        $rejectedWithoutHost = $_.Exception.Message -match 'require the isolated native SCM service compiler mode'
    }
    if (-not $rejectedWithoutHost -or (Test-Path -LiteralPath $probeOutput)) {
        throw 'Compiler accepted test mode without the native SCM host boundary.'
    }

    $rejectedWithoutTestFlag = $false
    try {
        & $compiler -Source $source -Output $probeOutput -EnableNativeScmServiceHost -NativeScmServiceName (New-ServiceName) -NativeScmServiceTestFault 'Dispatcher'
    } catch {
        $rejectedWithoutTestFlag = $_.Exception.Message -match 'require EnableNativeScmServiceTestMode'
    }
    if (-not $rejectedWithoutTestFlag -or (Test-Path -LiteralPath $probeOutput)) {
        throw 'Compiler accepted a fault-injection selector without the explicit test-mode flag.'
    }
    $script:Evidence.Add([pscustomobject]@{
        timestamp_utc = [DateTime]::UtcNow.ToString('o')
        test = 'compiler-test-mode-boundary'
        result = 'PASS'
        test_mode_requires_native_scm_host = $true
        fault_injection_requires_explicit_test_flag = $true
        executable_emitted_by_negative_tests = $false
    })
}

function New-ServiceImage {
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [string] $Fault = 'None',
        [string] $Action = 'Service',
        [switch] $TestMode
    )
    $file = Join-Path $buildRoot ($Name + '.exe')
    if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force }
    $compilerArgs = @{
        Source = $source
        Output = $file
        EnableNativeScmServiceHost = $true
        NativeScmServiceName = $Name
    }
    if ($TestMode) {
        $compilerArgs.EnableNativeScmServiceTestMode = $true
        $compilerArgs.NativeScmServiceTestFault = $Fault
        $compilerArgs.NativeScmServiceTestAction = $Action
        $compilerArgs.NativeScmTestHoldMilliseconds = 1200
    }
    $compileOutput = & $compiler @compilerArgs 2>&1 | ForEach-Object { [string]$_ }
    if (-not $?) {
        throw "Sharnou compiler failed for '$Name'. $($compileOutput -join [Environment]::NewLine)"
    }
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "Sharnou compiler did not emit '$file'."
    }
    $productionVerifierRejectedTestImage = $false
    if ($TestMode) {
        & $verifier -Path $file -NativeScmServiceHost -NativeScmServiceTestImage
        $rejectionReason = ''
        try {
            & $verifier -Path $file -NativeScmServiceHost
        } catch {
            $rejectionReason = $_.Exception.Message
            $productionVerifierRejectedTestImage = $rejectionReason -match 'unexpected thunk count|unexpected API|test-only marker'
        }
        if (-not $productionVerifierRejectedTestImage) {
            throw "Production verifier did not reject marked R5.1.d test image. Reason: $rejectionReason"
        }
    } else {
        & $verifier -Path $file -NativeScmServiceHost
    }
    $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    $imageInfo = [pscustomobject]@{
        service_name = $Name
        image_path = $file
        image_bytes = (Get-Item -LiteralPath $file).Length
        image_sha256 = $hash
        test_mode = [bool]$TestMode
        production_verifier_rejected_test_image = [bool]$productionVerifierRejectedTestImage
        fault = $Fault
        action = $Action
    }
    $script:Images.Add($imageInfo)
    return $imageInfo
}

function Install-DisposableService {
    param([Parameter(Mandatory = $true)][object] $Image)
    $name = [string]$Image.service_name
    $null = Invoke-ScCommand -Arguments @(
        'create', $name,
        'binPath=', [string]$Image.image_path,
        'start=', 'demand',
        'type=', 'own',
        'DisplayName=', $name
    )
    $null = $script:Services.Add($name)
    $null = Invoke-ScCommand -Arguments @('qc', $name)
}

function Remove-DisposableService {
    param([Parameter(Mandatory = $true)][string] $Name)
    $current = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($null -ne $current -and $current.Status.ToString() -ne 'Stopped') {
        $null = Invoke-ScCommand -Arguments @('stop', $Name) -AllowFailure
        try { $null = Wait-ServiceState -Name $Name -ExpectedState 1 -TimeoutSeconds 8 -SkipPendingValidation } catch { }
        $snapshot = $null
        try { $snapshot = Get-ServiceSnapshot -Name $Name } catch { }
        if ($null -ne $snapshot -and $snapshot.ProcessId -gt 0) {
            Stop-Process -Id ([int]$snapshot.ProcessId) -Force -ErrorAction SilentlyContinue
            try { Wait-ProcessGone -ProcessId $snapshot.ProcessId -TimeoutSeconds 10 } catch { }
            try { $null = Wait-ServiceState -Name $Name -ExpectedState 1 -TimeoutSeconds 10 -SkipPendingValidation } catch { }
        }
    }
    $null = Invoke-ScCommand -Arguments @('delete', $Name) -AllowFailure
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    do {
        $current = Get-Service -Name $Name -ErrorAction SilentlyContinue
        if ($null -eq $current) { return }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Disposable service '$Name' remains registered after deletion."
}

function New-ServiceName {
    return 'SharnouR51D_' + [Guid]::NewGuid().ToString('N').Substring(0, 12)
}

function Start-And-Observe {
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][string] $Tag,
        [switch] $StartRace
    )
    $operation = Start-ScAsync -Verb 'start' -Name $Name -Tag ($Tag + '-start')
    $deadline = [DateTime]::UtcNow.AddSeconds(25)
    $sawPending = $false
    $raceSent = $false
    $running = $null
    do {
        $snapshot = Get-ServiceSnapshot -Name $Name
        if ($snapshot.StateCode -eq 2) {
            if (Test-PendingSnapshot -Snapshot $snapshot -PendingState 2) {
                $sawPending = $true
                if ($StartRace -and -not $raceSent) {
                    $race = Invoke-ScCommand -Arguments @('stop', $Name) -AllowFailure
                    if ($race.ExitCode -eq 0) {
                        throw 'SCM accepted STOP before SERVICE_RUNNING while ControlsAccepted=0.'
                    }
                    $raceSent = $true
                }
            }
        } elseif ($snapshot.StateCode -eq 4) {
            Assert-RunningSnapshot -Snapshot $snapshot
            $running = $snapshot
            break
        } elseif ($snapshot.StateCode -eq 1) {
            throw "Service '$Name' stopped during startup. $($snapshot.Raw)"
        }
        Start-Sleep -Milliseconds 60
    } while ([DateTime]::UtcNow -lt $deadline)
    if ($null -eq $running) { throw "Service '$Name' did not reach RUNNING within startup bound." }
    if (-not $sawPending) { throw "Service '$Name' never exposed START_PENDING." }
    $startResult = Complete-ScAsync -Operation $operation -TimeoutSeconds 15
    if ($startResult.exit_code -ne 0) {
        $confirmed = Get-ServiceSnapshot -Name $Name
        if ($confirmed.StateCode -ne 4 -or $confirmed.ProcessId -ne $running.ProcessId) {
            throw "sc.exe start failed and SCM did not confirm the same RUNNING process for '$Name': $($startResult.stdout)"
        }
        $script:Evidence.Add([pscustomobject]@{
            timestamp_utc = [DateTime]::UtcNow.ToString('o')
            test = 'sc-start-cli-nonzero-but-scm-running-confirmed'
            service = $Name
            cli_exit_code = $startResult.exit_code
            scm_state = $confirmed.State
            pid = $confirmed.ProcessId
            result = 'STATE_CONFIRMED_WITH_RAW_CLI_DIAGNOSTIC'
        })
    }
    if ($StartRace -and -not $raceSent) { throw 'START_PENDING race control was not attempted.' }
    return $running
}

function Stop-And-Observe {
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][string] $Tag,
        [Parameter(Mandatory = $true)][UInt32] $ProcessId,
        [switch] $DuplicateStop
    )
    $operation = Start-ScAsync -Verb 'stop' -Name $Name -Tag ($Tag + '-stop')
    $deadline = [DateTime]::UtcNow.AddSeconds(25)
    $sawPending = $false
    $duplicateSent = $false
    $stopped = $null
    do {
        $snapshot = Get-ServiceSnapshot -Name $Name
        if ($snapshot.StateCode -eq 3) {
            if (Test-PendingSnapshot -Snapshot $snapshot -PendingState 3) {
                $sawPending = $true
                if ($DuplicateStop -and -not $duplicateSent) {
                    $null = Invoke-ScCommand -Arguments @('stop', $Name) -AllowFailure
                    $duplicateSent = $true
                }
            }
        } elseif ($snapshot.StateCode -eq 1) {
            $stopped = $snapshot
            break
        } elseif ($snapshot.StateCode -eq 2) {
            throw "Service '$Name' unexpectedly returned to START_PENDING while STOP was being observed. $($snapshot.Raw)"
        }
        Start-Sleep -Milliseconds 60
    } while ([DateTime]::UtcNow -lt $deadline)
    if ($null -eq $stopped) { throw "Service '$Name' did not reach STOPPED within shutdown bound." }
    if (-not $sawPending) { throw "Service '$Name' never exposed STOP_PENDING." }
    $stopResult = Complete-ScAsync -Operation $operation -TimeoutSeconds 15
    if ($stopResult.exit_code -ne 0) {
        $confirmed = Get-ServiceSnapshot -Name $Name
        if ($confirmed.StateCode -ne 1 -or $confirmed.ProcessId -ne 0) {
            throw "sc.exe stop failed and SCM did not confirm STOPPED/PID=0 for '$Name': $($stopResult.stdout)"
        }
        $script:Evidence.Add([pscustomobject]@{
            timestamp_utc = [DateTime]::UtcNow.ToString('o')
            test = 'sc-stop-cli-nonzero-but-scm-stopped-confirmed'
            service = $Name
            cli_exit_code = $stopResult.exit_code
            scm_state = $confirmed.State
            pid = $confirmed.ProcessId
            result = 'STATE_CONFIRMED_WITH_RAW_CLI_DIAGNOSTIC'
        })
    }
    if ($DuplicateStop -and -not $duplicateSent) { throw 'Duplicate STOP was not attempted during STOP_PENDING.' }
    if ($stopped.ProcessId -ne 0) { throw "SCM reports STOPPED but PID=$($stopped.ProcessId)." }
    Wait-ProcessGone -ProcessId $ProcessId
    return $stopped
}

$transcript = Join-Path $evidenceRoot 'r5-1d-transcript.txt'
$transcriptStarted = $false
try {
    Start-Transcript -LiteralPath $transcript -Force | Out-Null
    $transcriptStarted = $true
    Assert-TestCompilerGuards

    # This marked test image directly calls the generated HandlerEx callback.
    # It proves callback behavior only; it is not an OS shutdown broadcast test.
    $probeName = New-ServiceName
    $probeImage = New-ServiceImage -Name $probeName -Fault 'None' -Action 'ProbeControlCallbacks' -TestMode
    $probeProcess = Start-Process -FilePath $probeImage.image_path -PassThru -NoNewWindow -Wait
    if ($probeProcess.ExitCode -ne 0) {
        throw "Generated HandlerEx callback probe failed with exit code $($probeProcess.ExitCode)."
    }
    $script:Evidence.Add([pscustomobject]@{
        timestamp_utc = [DateTime]::UtcNow.ToString('o')
        test = 'handlerex-interrogate-stop-shutdown-duplicate-callback'
        result = 'PASS_CALLBACK_LEVEL_ONLY'
        process_exit_code = $probeProcess.ExitCode
    })

    # A production-profile image launched outside SCM must fail naturally with
    # ERROR_FAILED_SERVICE_CONTROLLER_CONNECT (1063).
    $naturalName = New-ServiceName
    $naturalImage = New-ServiceImage -Name $naturalName
    $naturalProcess = Start-Process -FilePath $naturalImage.image_path -PassThru -NoNewWindow -Wait
    if ($naturalProcess.ExitCode -ne 1063) {
        throw "Out-of-SCM dispatcher expected exit code 1063, got $($naturalProcess.ExitCode)."
    }
    $script:Evidence.Add([pscustomobject]@{
        timestamp_utc = [DateTime]::UtcNow.ToString('o')
        test = 'natural-dispatcher-rejects-non-scm-launch'
        result = 'PASS'
        expected_exit_code = 1063
        actual_exit_code = $naturalProcess.ExitCode
    })

    # Three genuine SCM start/stop cycles: START_PENDING, RUNNING, INTERROGATE,
    # STOP_PENDING, STOPPED. Cycle 1 races STOP against START_PENDING; cycle 2
    # sends a duplicate STOP while STOP_PENDING is visible.
    $lifecycleName = New-ServiceName
    $lifecycleImage = New-ServiceImage -Name $lifecycleName -Fault 'None' -TestMode
    Install-DisposableService -Image $lifecycleImage
    for ($cycle = 1; $cycle -le 3; $cycle++) {
        $tag = "lifecycle-cycle-$cycle"
        $running = Start-And-Observe -Name $lifecycleName -Tag $tag -StartRace:($cycle -eq 1)
        $null = Invoke-ScCommand -Arguments @('interrogate', $lifecycleName)
        $stopped = Stop-And-Observe -Name $lifecycleName -Tag $tag -ProcessId $running.ProcessId -DuplicateStop:($cycle -eq 2)
        if ($stopped.Win32ExitCode -ne 0 -or $stopped.ServiceExitCode -ne 0) {
            throw "Normal STOP cycle $cycle reported nonzero exit status."
        }
    }

    # Forced process termination must yield STOPPED/PID=0; then the same service
    # registration must support a fresh start and graceful stop.
    $crashRunning = Start-And-Observe -Name $lifecycleName -Tag 'forced-crash'
    Stop-Process -Id ([int]$crashRunning.ProcessId) -Force
    $crashStopped = Wait-ServiceState -Name $lifecycleName -ExpectedState 1 -TimeoutSeconds 25 -SkipPendingValidation
    if ($crashStopped.ProcessId -ne 0) { throw "Forced termination left service PID=$($crashStopped.ProcessId)." }
    Wait-ProcessGone -ProcessId $crashRunning.ProcessId
    $script:Evidence.Add([pscustomobject]@{
        timestamp_utc = [DateTime]::UtcNow.ToString('o')
        test = 'forced-process-termination'
        result = 'PASS'
        terminated_pid = $crashRunning.ProcessId
        scm_state = $crashStopped.State
        scm_pid = $crashStopped.ProcessId
    })
    $restartRunning = Start-And-Observe -Name $lifecycleName -Tag 'post-crash-restart'
    $null = Stop-And-Observe -Name $lifecycleName -Tag 'post-crash-restart' -ProcessId $restartRunning.ProcessId

    # Delete a live service registration, terminate its process, and ensure SCM
    # completes the deferred deletion without a live process or stale registration.
    $deleteName = New-ServiceName
    $deleteImage = New-ServiceImage -Name $deleteName -Fault 'None' -TestMode
    Install-DisposableService -Image $deleteImage
    $deleteRunning = Start-And-Observe -Name $deleteName -Tag 'interrupted-delete'
    $null = Invoke-ScCommand -Arguments @('delete', $deleteName)
    Stop-Process -Id ([int]$deleteRunning.ProcessId) -Force
    Wait-ProcessGone -ProcessId $deleteRunning.ProcessId
    $deleteDeadline = [DateTime]::UtcNow.AddSeconds(25)
    $remaining = $null
    do {
        $remaining = Get-Service -Name $deleteName -ErrorAction SilentlyContinue
        if ($null -eq $remaining) { break }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deleteDeadline)
    if ($null -ne $remaining) { throw "Interrupted deletion did not remove '$deleteName'." }
    $script:Evidence.Add([pscustomobject]@{
        timestamp_utc = [DateTime]::UtcNow.ToString('o')
        test = 'delete-while-running-then-process-crash'
        result = 'PASS'
        service_name = $deleteName
        terminated_pid = $deleteRunning.ProcessId
        registration_removed = $true
    })

    # Faults that prevent the dispatcher, HandlerEx registration, event creation,
    # or either startup status transition must fail closed and leave PID=0.
    foreach ($fault in @('Dispatcher', 'HandlerRegistration', 'EventCreation', 'SetServiceStatusStartPending', 'SetServiceStatusRunning')) {
        $name = New-ServiceName
        $image = New-ServiceImage -Name $name -Fault $fault -TestMode
        Install-DisposableService -Image $image
        $operation = Start-ScAsync -Verb 'start' -Name $name -Tag ("fault-" + $fault)
        $terminal = Wait-ServiceState -Name $name -ExpectedState 1 -TimeoutSeconds 25 -SkipPendingValidation
        $null = Complete-ScAsync -Operation $operation -TimeoutSeconds 15
        if ($terminal.ProcessId -ne 0) { throw "Startup fault '$fault' left PID=$($terminal.ProcessId)." }
        if ($fault -in @('EventCreation', 'SetServiceStatusStartPending', 'SetServiceStatusRunning') -and
            $terminal.Win32ExitCode -ne 5) {
            throw "Startup fault '$fault' did not preserve deterministic ERROR_ACCESS_DENIED (5)."
        }
        $script:Evidence.Add([pscustomobject]@{
            timestamp_utc = [DateTime]::UtcNow.ToString('o')
            test = 'startup-fault-injection'
            fault = $fault
            result = 'PASS_FAIL_CLOSED'
            terminal_state = $terminal.State
            pid = $terminal.ProcessId
            win32_exit_code = $terminal.Win32ExitCode
        })
        Remove-DisposableService -Name $name
    }

    # Exercise both STOP_PENDING and STOPPED SetServiceStatus failure edges.
    foreach ($fault in @('SetServiceStatusStopPending', 'SetServiceStatusStopped')) {
        $name = New-ServiceName
        $image = New-ServiceImage -Name $name -Fault $fault -TestMode
        Install-DisposableService -Image $image
        $running = Start-And-Observe -Name $name -Tag ("fault-" + $fault + '-start')
        $operation = Start-ScAsync -Verb 'stop' -Name $name -Tag ("fault-" + $fault + '-stop')
        if ($fault -eq 'SetServiceStatusStopped') {
            $terminal = Wait-ServiceState -Name $name -ExpectedState 1 -TimeoutSeconds 25 -RequireStopPending
        } else {
            $terminal = Wait-ServiceState -Name $name -ExpectedState 1 -TimeoutSeconds 25 -SkipPendingValidation
        }
        $null = Complete-ScAsync -Operation $operation -TimeoutSeconds 15
        if ($terminal.ProcessId -ne 0) { throw "Stop fault '$fault' left PID=$($terminal.ProcessId)." }
        Wait-ProcessGone -ProcessId $running.ProcessId
        if ($fault -eq 'SetServiceStatusStopPending' -and $terminal.Win32ExitCode -ne 5) {
            throw 'Injected STOP_PENDING failure was not carried to terminal SERVICE_STATUS.'
        }
        $script:Evidence.Add([pscustomobject]@{
            timestamp_utc = [DateTime]::UtcNow.ToString('o')
            test = 'stop-fault-injection'
            fault = $fault
            result = 'PASS_FAIL_CLOSED'
            terminal_state = $terminal.State
            pid = $terminal.ProcessId
            win32_exit_code = $terminal.Win32ExitCode
        })
        Remove-DisposableService -Name $name
    }

    Remove-DisposableService -Name $lifecycleName

    $manifest = [ordered]@{
        schema = 'sharnou.phase-2b8.r5-1d.evidence.v1'
        acceptance = 'PASS'
        acceptance_scope = 'Exact-head Windows SCM status/field lifecycle; three repeated start-stop cycles; start-stop race; duplicate STOP attempt; INTERROGATE; natural and injected dispatcher failure; HandlerEx registration/event creation failure; all four SetServiceStatus boundaries; forced process termination; restart; and deferred deletion recovery.'
        tested_commit = $testedHead
        expected_tested_commit = $expectedHead
        runner_os = $env:RUNNER_OS
        runner_arch = $env:RUNNER_ARCH
        windows = [Environment]::OSVersion.VersionString
        powershell = $PSVersionTable.PSVersion.ToString()
        test_only_marker = 'SHARNOU_R5_1_D_TEST_ONLY_V1'
        test_image_profile = 'Explicit opt-in compiler mode; test-only Sleep import and fault branches occur only in marked test images; production verifier rejects marker and test import.'
        lifecycle_cycles = 3
        start_pending_observed = $true
        running_fields_verified = $true
        stop_pending_observed = $true
        stopped_pid_zero = $true
        forced_termination_no_orphan = $true
        interrupted_deletion_recovered = $true
        callback_shutdown_probe = 'PASS_CALLBACK_LEVEL_ONLY'
        actual_os_shutdown_broadcast = 'NOT_TESTED_REQUIRES_DISPOSABLE_VM'
        phase_2b8_security_acceptance = 'NOT ACCEPTED'
        model_facing_execution = 'DISABLED'
        autonomous_execution = 'DISABLED'
        images = $script:Images.ToArray()
        evidence = $script:Evidence.ToArray()
    }
    $manifestPath = Join-Path $evidenceRoot 'r5-1d-evidence.json'
    [IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 10), [Text.Encoding]::ASCII)
    Write-Host 'R5.1.d lifecycle/failure qualification: PASS for the explicitly enumerated scope.' -ForegroundColor Green
}
finally {
    foreach ($name in @($script:Services.ToArray())) {
        try { Remove-DisposableService -Name $name } catch { Write-Warning $_.Exception.Message }
    }
    if ($transcriptStarted) { Stop-Transcript | Out-Null }
}
