[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSEdition -ne 'Desktop') {
    throw 'Phase 2B.5 requires Windows PowerShell 5.1.'
}
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or [IntPtr]::Size -ne 8) {
    throw 'Phase 2B.5 requires 64-bit Windows.'
}

. (Join-Path $PSScriptRoot 'DevAgentBroker\NativeInterop.ps1')

$manifestPath = Join-Path $PSScriptRoot 'DevAgentBroker\native-abi-manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (@($manifest.phase2B5Apis).Count -ne 6) {
    throw 'Phase 2B.5 requires exactly seven separately reviewed pipe/handle APIs.'
}
if ($manifest.phase2B5Contract.outputCapture.combinedOutputLimitBytes -ne 65536) {
    throw 'Phase 2B.5 combined-output cap changed unexpectedly.'
}

$script:Types = $null
$script:ApiType = $null
$script:Passed = 0
$script:Failed = 0
$script:BaseDirectory = Join-Path ([IO.Path]::GetTempPath()) ('Sharnou-DevAgent-2B5-' + [Guid]::NewGuid().ToString('N'))
$script:ChildScript = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'DevAgentBroker\PipeCaptureChild.ps1'))
$script:SystemDirectory = [Environment]::SystemDirectory
$script:ChildImage = [IO.Path]::GetFullPath((Join-Path $script:SystemDirectory 'WindowsPowerShell\v1.0\powershell.exe'))
$script:OutputLimit = [int]$manifest.phase2B5Contract.outputCapture.combinedOutputLimitBytes
$script:NativeInteropPath = Join-Path $PSScriptRoot 'DevAgentBroker\NativeInterop.ps1'
$script:ScratchAllocations = New-Object 'System.Collections.Generic.List[IntPtr]'
$script:ChunkSize = [int]$manifest.phase2B5Contract.outputCapture.readChunkBytes
$script:SupervisorHandleBaseline = 0

function Assert-Phase2B5 {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) {
        $script:Failed++
        throw ('FAIL: ' + $Message)
    }
    $script:Passed++
    Write-Host ('PASS: ' + $Message) -ForegroundColor Green
}

function Invoke-Phase2B5Api {
    param([string]$Name,[object[]]$Arguments)
    $method = $script:ApiType.GetMethod($Name)
    if ($null -eq $method) { throw ('Native API was not declared: ' + $Name) }
    return $method.Invoke($null,$Arguments)
}

function New-Phase2B5Buffer {
    param([int]$Bytes,[System.Collections.Generic.List[IntPtr]]$Allocations)
    if ($Bytes -lt 1 -or $Bytes -gt 65536) { throw ('Unmanaged allocation outside 64 KiB bound: ' + $Bytes) }
    $pointer = [Runtime.InteropServices.Marshal]::AllocHGlobal($Bytes)
    if ($pointer -eq [IntPtr]::Zero) { throw ('AllocHGlobal failed for ' + $Bytes + ' bytes.') }
    [Runtime.InteropServices.Marshal]::Copy((New-Object byte[] $Bytes),0,$pointer,$Bytes)
    $Allocations.Add($pointer)
    return $pointer
}

function New-Phase2B5Unicode {
    param([string]$Value,[System.Collections.Generic.List[IntPtr]]$Allocations)
    $pointer = [Runtime.InteropServices.Marshal]::StringToHGlobalUni($Value)
    if ($pointer -eq [IntPtr]::Zero) { throw 'StringToHGlobalUni returned NULL.' }
    $Allocations.Add($pointer)
    return $pointer
}

function Get-Phase2B5HandleCount {
    $count = New-Phase2B5Buffer -Bytes 4 -Allocations $script:ScratchAllocations
    if (-not [bool](Invoke-Phase2B5Api 'GetProcessHandleCount' @(
        [IntPtr](Invoke-Phase2B5Api 'GetCurrentProcess' @()),$count
    ))) {
        throw ('GetProcessHandleCount failed: Win32=' + [Runtime.InteropServices.Marshal]::GetLastWin32Error())
    }
    return [Runtime.InteropServices.Marshal]::ReadInt32($count)
}

function Get-Phase2B5HandleFlags {
    param([IntPtr]$Handle)
    $flags = New-Phase2B5Buffer -Bytes 4 -Allocations $script:ScratchAllocations
    if (-not [bool](Invoke-Phase2B5Api 'GetHandleInformation' @($Handle,$flags))) {
        throw ('GetHandleInformation failed: Win32=' + [Runtime.InteropServices.Marshal]::GetLastWin32Error())
    }
    return [Runtime.InteropServices.Marshal]::ReadInt32($flags)
}

function New-Phase2B5SecurityAttributes {
    param([System.Collections.Generic.List[IntPtr]]$Allocations)
    $type = $script:Types['SECURITY_ATTRIBUTES']
    if ((Get-SharnouMarshalSize -NativeType $type) -ne 24 -or
        (Get-SharnouMarshalOffset -NativeType $type -FieldName 'nLength') -ne 0 -or
        (Get-SharnouMarshalOffset -NativeType $type -FieldName 'lpSecurityDescriptor') -ne 8 -or
        (Get-SharnouMarshalOffset -NativeType $type -FieldName 'bInheritHandle') -ne 16) {
        throw 'SECURITY_ATTRIBUTES x64 size/offset contract is invalid.'
    }
    $pointer = New-Phase2B5Buffer -Bytes 24 -Allocations $Allocations
    [Runtime.InteropServices.Marshal]::WriteInt32($pointer,0,24)
    [Runtime.InteropServices.Marshal]::WriteIntPtr($pointer,8,[IntPtr]::Zero)
    [Runtime.InteropServices.Marshal]::WriteInt32($pointer,16,1)
    return $pointer
}

function New-Phase2B5Pipe {
    param(
        [IntPtr]$SecurityAttributes,
        [System.Collections.Generic.List[IntPtr]]$Allocations,
        [System.Collections.Generic.List[IntPtr]]$Handles
    )
    $readOutput = New-Phase2B5Buffer -Bytes 8 -Allocations $Allocations
    $writeOutput = New-Phase2B5Buffer -Bytes 8 -Allocations $Allocations
    $createOk = [bool](Invoke-Phase2B5Api 'CreatePipe' @(
        $readOutput,$writeOutput,$SecurityAttributes,[UInt32]0
    ))
    if (-not $createOk) {
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw ('CreatePipe failed: Win32=' + $errorCode)
    }
    $readHandle = [Runtime.InteropServices.Marshal]::ReadIntPtr($readOutput)
    $writeHandle = [Runtime.InteropServices.Marshal]::ReadIntPtr($writeOutput)
    if ($readHandle -eq [IntPtr]::Zero -or
        $writeHandle -eq [IntPtr]::Zero -or $readHandle -eq [IntPtr](-1) -or
        $writeHandle -eq [IntPtr](-1)) {
        foreach ($partial in @($readHandle,$writeHandle)) {
            if ($partial -ne [IntPtr]::Zero -and $partial -ne [IntPtr](-1)) {
                try { [void](Invoke-Phase2B5Api 'CloseHandle' @($partial)) } catch {}
            }
        }
        throw 'CreatePipe succeeded with an invalid endpoint; any valid partial handle was closed.'
    }
    $Handles.Add($readHandle)
    $Handles.Add($writeHandle)
    return [pscustomobject]@{Read=$readHandle;Write=$writeHandle}
}

function Set-Phase2B5InheritFlag {
    param([IntPtr]$Handle,[bool]$Enabled)
    $flags = [UInt32]0
    if ($Enabled) { $flags = [UInt32]1 }
    if (-not [bool](Invoke-Phase2B5Api 'SetHandleInformation' @(
        $Handle,[UInt32]1,$flags
    ))) {
        throw ('SetHandleInformation failed: Win32=' + [Runtime.InteropServices.Marshal]::GetLastWin32Error())
    }
    $actual = Get-Phase2B5HandleFlags -Handle $Handle
    if ((($actual -band 1) -ne 0) -ne $Enabled) {
        throw 'HANDLE_FLAG_INHERIT did not match the requested endpoint policy.'
    }
    Assert-Phase2B5 ((($actual -band 1) -ne 0) -eq $Enabled) ('HANDLE_FLAG_INHERIT endpoint policy verified: ' + [string]$Enabled)
}

function New-Phase2B5Job {
    param([System.Collections.Generic.List[IntPtr]]$Allocations)
    $job = [IntPtr](Invoke-Phase2B5Api 'CreateJobObjectW' @([IntPtr]::Zero,[IntPtr]::Zero))
    if ($job -eq [IntPtr]::Zero) {
        throw ('CreateJobObjectW failed: Win32=' + [Runtime.InteropServices.Marshal]::GetLastWin32Error())
    }
    try {
        $size = Get-SharnouMarshalSize -NativeType $script:Types['JOBOBJECT_EXTENDED_LIMIT_INFORMATION']
        if ($size -ne 144) { throw ('Unexpected Job Object x64 structure size: ' + $size) }
        $info = New-Phase2B5Buffer -Bytes $size -Allocations $Allocations
        [Runtime.InteropServices.Marshal]::WriteInt32($info,16,0x00002108)
        [Runtime.InteropServices.Marshal]::WriteInt32($info,40,2)
        [Runtime.InteropServices.Marshal]::WriteInt64($info,112,268435456)
        if (-not [bool](Invoke-Phase2B5Api 'SetInformationJobObject' @(
            $job,[Int32]9,$info,[UInt32]$size
        ))) {
            $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw ('SetInformationJobObject failed: Win32=' + $errorCode)
        }
        return $job
    }
    catch {
        try { [void](Invoke-Phase2B5Api 'CloseHandle' @($job)) } catch {}
        throw
    }
}

function Get-Phase2B5ChildCommandLine {
    param(
        [string]$Mode,
        [Int64]$SentinelHandle,
        [string]$ReportPath,
        [string]$PidPath
    )
    $parts = @(
        ('"' + $script:ChildImage + '"'),
        '-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass',
        '-File',('"' + $script:ChildScript + '"'),
        '-Mode',$Mode,
        '-SentinelHandle',[string]$SentinelHandle
    )
    if (-not [string]::IsNullOrEmpty($ReportPath)) {
        $parts += @('-ReportPath',('"' + $ReportPath + '"'))
    }
    if (-not [string]::IsNullOrEmpty($PidPath)) {
        $parts += @('-PidPath',('"' + $PidPath + '"'))
    }
    return ($parts -join ' ')
}

function Get-Phase2B5AvailableBytes {
    param([IntPtr]$PipeReadHandle,[IntPtr]$AvailablePointer)
    $ok = [bool](Invoke-Phase2B5Api 'PeekNamedPipe' @(
        $PipeReadHandle,[IntPtr]::Zero,[UInt32]0,[IntPtr]::Zero,$AvailablePointer,[IntPtr]::Zero
    ))
    if (-not $ok) {
        $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        if ($code -eq 109) { return [pscustomobject]@{Closed=$true;Available=0;Error=0} }
        return [pscustomobject]@{Closed=$false;Available=0;Error=$code}
    }
    return [pscustomobject]@{
        Closed=$false
        Available=[Runtime.InteropServices.Marshal]::ReadInt32($AvailablePointer)
        Error=0
    }
}

function Stop-Phase2B5JobAndReap {
    param(
        [IntPtr]$JobHandle,
        [IntPtr]$ProcessHandle,
        [bool]$JobAssigned
    )
    if ($JobAssigned -and $JobHandle -ne [IntPtr]::Zero) {
        $killed = [bool](Invoke-Phase2B5Api 'TerminateJobObject' @($JobHandle,[UInt32]0x0000DEAD))
        if (-not $killed) {
            $waitNow = [UInt32](Invoke-Phase2B5Api 'WaitForSingleObject' @($ProcessHandle,[UInt32]0))
            if ($waitNow -ne 0) {
                throw ('TerminateJobObject failed: Win32=' + [Runtime.InteropServices.Marshal]::GetLastWin32Error())
            }
        }
    } elseif ($ProcessHandle -ne [IntPtr]::Zero) {
        if (-not [bool](Invoke-Phase2B5Api 'TerminateProcess' @($ProcessHandle,[UInt32]0x0000DEAD))) {
            $waitNow = [UInt32](Invoke-Phase2B5Api 'WaitForSingleObject' @($ProcessHandle,[UInt32]0))
            if ($waitNow -ne 0) {
                throw ('TerminateProcess failed: Win32=' + [Runtime.InteropServices.Marshal]::GetLastWin32Error())
            }
        }
    }
    $wait = [UInt32](Invoke-Phase2B5Api 'WaitForSingleObject' @($ProcessHandle,[UInt32]5000))
    if ($wait -ne 0) { throw ('Child process was not reaped after termination: wait=0x{0:X8}.' -f $wait) }
    return $true
}

function Invoke-Phase2B5Trial {
    param(
        [string]$Mode,
        [int]$TimeoutMilliseconds,
        [bool]$InjectReaderFailure = $false,
        [bool]$CreateSentinel = $false
    )

    $allocations = New-Object 'System.Collections.Generic.List[IntPtr]'
    $handles = New-Object 'System.Collections.Generic.List[IntPtr]'
    $job = [IntPtr]::Zero
    $process = [IntPtr]::Zero
    $thread = [IntPtr]::Zero
    $stdoutRead = [IntPtr]::Zero
    $stdoutWrite = [IntPtr]::Zero
    $stderrRead = [IntPtr]::Zero
    $stderrWrite = [IntPtr]::Zero
    $sentinelHandle = [IntPtr]::Zero
    $attributeList = [IntPtr]::Zero
    $attributeListInitialized = $false
    $processCreated = $false
    $jobAssigned = $false
    $processReaped = $false
    $cleanupVerified = $true
    $descendantMembershipVerified = $false
    $childProcessId = 0
    $status = 'NotStarted'
    $failure = ''
    $exitCode = -1
    $previousSuspendCount = [UInt32]0
    $reportPath = ''
    $pidPath = ''
    $trialDirectory = Join-Path $script:BaseDirectory ([Guid]::NewGuid().ToString('N'))
    $stdoutBytes = New-Object 'System.Collections.Generic.List[byte]'
    $stderrBytes = New-Object 'System.Collections.Generic.List[byte]'
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $pipeStates = $null
    $scriptStream = $null
    $childImageHash = ''
    $childScriptHash = ''
    $combinedCount = 0

    try {
        [void][IO.Directory]::CreateDirectory($trialDirectory)
        if ($CreateSentinel) {
            $sentinelPath = Join-Path $trialDirectory 'sentinel.bin'
            $reportPath = Join-Path $trialDirectory 'sentinel-report.txt'
            [IO.File]::WriteAllBytes($sentinelPath,[byte[]]@(0x53,0x48,0x41,0x52,0x4E,0x4F,0x55,0x2D,0x42,0x52,0x4F,0x4B,0x45,0x52,0x2D,0x32,0x42,0x2E,0x35,0x2D,0x4E,0x4F,0x2D,0x49,0x4E,0x48,0x45,0x52,0x49,0x54,0x21,0x7F))
        }
        if ($Mode -eq 'Descendant') { $pidPath = Join-Path $trialDirectory 'descendant.pid' }

        $scriptStream = [IO.File]::Open($script:ChildScript,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        $sha = [Security.Cryptography.SHA256]::Create()
        try {
            $childScriptHash = ([BitConverter]::ToString($sha.ComputeHash($scriptStream))).Replace('-','')
        } finally {
            $sha.Dispose()
            $scriptStream.Position = 0
        }
        if ($childScriptHash -cne [string]$manifest.phase2B5Contract.fixedChildSha256) {
            throw ('Fixed test child SHA-256 mismatch: ' + $childScriptHash)
        }

        if (-not (Test-Path -LiteralPath $script:ChildImage -PathType Leaf)) { throw 'Fixed Windows PowerShell image is missing.' }
        if (-not $script:ChildImage.StartsWith(($script:SystemDirectory.TrimEnd('\') + '\'),[StringComparison]::OrdinalIgnoreCase)) {
            throw 'Fixed PowerShell image is outside System32.'
        }
        $childImageHash = (Get-FileHash -LiteralPath $script:ChildImage -Algorithm SHA256).Hash

        $job = New-Phase2B5Job -Allocations $allocations
        $handles.Add($job)

        $securityAttributes = New-Phase2B5SecurityAttributes -Allocations $allocations
        $stdoutPipe = New-Phase2B5Pipe -SecurityAttributes $securityAttributes -Allocations $allocations -Handles $handles
        $stdoutRead = $stdoutPipe.Read
        $stdoutWrite = $stdoutPipe.Write
        $stderrPipe = New-Phase2B5Pipe -SecurityAttributes $securityAttributes -Allocations $allocations -Handles $handles
        $stderrRead = $stderrPipe.Read
        $stderrWrite = $stderrPipe.Write

        Set-Phase2B5InheritFlag -Handle $stdoutRead -Enabled $false
        Set-Phase2B5InheritFlag -Handle $stderrRead -Enabled $false
        Set-Phase2B5InheritFlag -Handle $stdoutWrite -Enabled $true
        Set-Phase2B5InheritFlag -Handle $stderrWrite -Enabled $true

        if ($CreateSentinel) {
            $sentinelAttributes = New-Phase2B5SecurityAttributes -Allocations $allocations
            $sentinelPathPointer = New-Phase2B5Unicode -Value $sentinelPath -Allocations $allocations
            $sentinelHandle = [IntPtr](Invoke-Phase2B5Api 'CreateFileW' @(
                $sentinelPathPointer,[UInt32]0x80000000,[UInt32]1,$sentinelAttributes,
                [UInt32]3,[UInt32]0x80,[IntPtr]::Zero
            ))
            if ($sentinelHandle -eq [IntPtr](-1) -or $sentinelHandle -eq [IntPtr]::Zero) {
                throw ('CreateFileW sentinel failed: Win32=' + [Runtime.InteropServices.Marshal]::GetLastWin32Error())
            }
            $handles.Add($sentinelHandle)
            $sentinelFlags = Get-Phase2B5HandleFlags -Handle $sentinelHandle
            if (($sentinelFlags -band 1) -eq 0) { throw 'Sentinel handle was not marked inheritable before process creation.' }
        }

        $attributeSize = New-Phase2B5Buffer -Bytes 8 -Allocations $allocations
        $sizeProbe = [bool](Invoke-Phase2B5Api 'InitializeProcThreadAttributeList' @(
            [IntPtr]::Zero,[UInt32]1,[UInt32]0,$attributeSize
        ))
        $sizeError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        $attributeBytes = [Runtime.InteropServices.Marshal]::ReadInt64($attributeSize)
        if ($sizeProbe -or $sizeError -ne 122 -or $attributeBytes -le 0 -or $attributeBytes -gt 65536) {
            throw ('Attribute-list sizing failed: result={0}; Win32={1}; bytes={2}.' -f $sizeProbe,$sizeError,$attributeBytes)
        }
        $attributeList = New-Phase2B5Buffer -Bytes ([int]$attributeBytes) -Allocations $allocations
        if (-not [bool](Invoke-Phase2B5Api 'InitializeProcThreadAttributeList' @(
            $attributeList,[UInt32]1,[UInt32]0,$attributeSize
        ))) {
            throw ('InitializeProcThreadAttributeList failed: Win32=' + [Runtime.InteropServices.Marshal]::GetLastWin32Error())
        }
        $attributeListInitialized = $true

        $handleList = New-Phase2B5Buffer -Bytes 16 -Allocations $allocations
        $sortedHandles = @($stdoutWrite,$stderrWrite) | Sort-Object { $_.ToInt64() }
        [Runtime.InteropServices.Marshal]::WriteIntPtr($handleList,0,[IntPtr]$sortedHandles[0])
        [Runtime.InteropServices.Marshal]::WriteIntPtr($handleList,8,[IntPtr]$sortedHandles[1])
        if (-not [bool](Invoke-Phase2B5Api 'UpdateProcThreadAttribute' @(
            $attributeList,[UInt32]0,[UIntPtr]::new([UInt64]0x00020002),$handleList,
            [UIntPtr]::new([UInt64]16),[IntPtr]::Zero,[IntPtr]::Zero
        ))) {
            throw ('UpdateProcThreadAttribute(HANDLE_LIST) failed: Win32=' + [Runtime.InteropServices.Marshal]::GetLastWin32Error())
        }
        Assert-Phase2B5 ([Runtime.InteropServices.Marshal]::ReadIntPtr($handleList,0).ToInt64() -lt [Runtime.InteropServices.Marshal]::ReadIntPtr($handleList,8).ToInt64()) 'explicit handle allowlist is exactly two handles in ascending handle-value order'

        $commandText = Get-Phase2B5ChildCommandLine -Mode $Mode -SentinelHandle ([Int64]$sentinelHandle.ToInt64()) -ReportPath $reportPath -PidPath $pidPath
        $applicationPointer = New-Phase2B5Unicode -Value $script:ChildImage -Allocations $allocations
        $commandPointer = New-Phase2B5Unicode -Value $commandText -Allocations $allocations
        $directoryPointer = New-Phase2B5Unicode -Value $script:SystemDirectory -Allocations $allocations
        $startupSize = Get-SharnouMarshalSize -NativeType $script:Types['STARTUPINFOEXW']
        $processInfoSize = Get-SharnouMarshalSize -NativeType $script:Types['PROCESS_INFORMATION']
        if ($startupSize -ne 112 -or $processInfoSize -ne 24) { throw 'STARTUPINFOEXW or PROCESS_INFORMATION size mismatch.' }

        $startup = New-Phase2B5Buffer -Bytes $startupSize -Allocations $allocations
        [Runtime.InteropServices.Marshal]::WriteInt32($startup,0,$startupSize)
        [Runtime.InteropServices.Marshal]::WriteInt32($startup,60,0x00000100)
        [Runtime.InteropServices.Marshal]::WriteIntPtr($startup,80,$stdoutWrite)
        [Runtime.InteropServices.Marshal]::WriteIntPtr($startup,88,$stdoutWrite)
        [Runtime.InteropServices.Marshal]::WriteIntPtr($startup,96,$stderrWrite)
        [Runtime.InteropServices.Marshal]::WriteIntPtr($startup,104,$attributeList)
        Assert-Phase2B5 (([Runtime.InteropServices.Marshal]::ReadInt32($startup,60) -band 0x00000100) -ne 0) 'STARTF_USESTDHANDLES is set in STARTUPINFOEX'
        Assert-Phase2B5 ([Runtime.InteropServices.Marshal]::ReadIntPtr($startup,80) -eq $stdoutWrite) 'stdin is bound only to the fixed child-side stdout pipe endpoint'
        Assert-Phase2B5 ([Runtime.InteropServices.Marshal]::ReadIntPtr($startup,88) -eq $stdoutWrite) 'stdout is bound to the first allowlisted pipe endpoint'
        Assert-Phase2B5 ([Runtime.InteropServices.Marshal]::ReadIntPtr($startup,96) -eq $stderrWrite) 'stderr is bound to the second allowlisted pipe endpoint'
        $processInfo = New-Phase2B5Buffer -Bytes $processInfoSize -Allocations $allocations
        $creationFlags = [UInt32](0x00080000 -bor 0x00000004 -bor 0x00000400)
        Assert-Phase2B5 (($creationFlags -band 0x00080000) -ne 0) 'EXTENDED_STARTUPINFO_PRESENT is set'
        Assert-Phase2B5 (($creationFlags -band 0x00000004) -ne 0) 'CREATE_SUSPENDED is set before Job Object assignment'
        Assert-Phase2B5 (($creationFlags -band 0x00000400) -ne 0) 'CREATE_UNICODE_ENVIRONMENT is set for the inherited NULL environment'

        if (-not [bool](Invoke-Phase2B5Api 'CreateProcessW' @(
            $applicationPointer,$commandPointer,[IntPtr]::Zero,[IntPtr]::Zero,[Boolean]$true,
            $creationFlags,[IntPtr]::Zero,$directoryPointer,$startup,$processInfo
        ))) {
            throw ('CreateProcessW(STARTUPINFOEX handle list) failed: Win32=' + [Runtime.InteropServices.Marshal]::GetLastWin32Error())
        }
        $processCreated = $true
        $process = [Runtime.InteropServices.Marshal]::ReadIntPtr($processInfo,0)
        $thread = [Runtime.InteropServices.Marshal]::ReadIntPtr($processInfo,8)
        $childProcessId = [Runtime.InteropServices.Marshal]::ReadInt32($processInfo,16)
        if ($process -eq [IntPtr]::Zero -or $thread -eq [IntPtr]::Zero -or $childProcessId -le 0) {
            throw 'CreateProcessW returned invalid PROCESS_INFORMATION.'
        }
        $handles.Add($process)
        $handles.Add($thread)
        if ($attributeListInitialized) {
            [void](Invoke-Phase2B5Api 'DeleteProcThreadAttributeList' @($attributeList))
            $attributeListInitialized = $false
        }

        foreach ($parentWrite in @($stdoutWrite,$stderrWrite)) {
            if (-not [bool](Invoke-Phase2B5Api 'CloseHandle' @($parentWrite))) {
                throw ('Parent write-end CloseHandle failed: Win32=' + [Runtime.InteropServices.Marshal]::GetLastWin32Error())
            }
            [void]$handles.Remove($parentWrite)
        }
        $stdoutWrite = [IntPtr]::Zero
        $stderrWrite = [IntPtr]::Zero

        if ($sentinelHandle -ne [IntPtr]::Zero) {
            if (-not [bool](Invoke-Phase2B5Api 'CloseHandle' @($sentinelHandle))) {
                throw ('Sentinel CloseHandle failed: Win32=' + [Runtime.InteropServices.Marshal]::GetLastWin32Error())
            }
            [void]$handles.Remove($sentinelHandle)
            $sentinelHandle = [IntPtr]::Zero
        }

        $assignOk = [bool](Invoke-Phase2B5Api 'AssignProcessToJobObject' @($job,$process))
        if (-not $assignOk) {
            throw ('AssignProcessToJobObject failed: Win32=' + [Runtime.InteropServices.Marshal]::GetLastWin32Error())
        }
        $jobAssigned = $true

        $membership = New-Phase2B5Buffer -Bytes 4 -Allocations $allocations
        if (-not [bool](Invoke-Phase2B5Api 'IsProcessInJob' @($process,$job,$membership)) -or
            [Runtime.InteropServices.Marshal]::ReadInt32($membership) -ne 1) {
            throw ('Suspended process is not in the exact configured Job Object: Win32=' + [Runtime.InteropServices.Marshal]::GetLastWin32Error())
        }

        $suspendState = New-Phase2B5Buffer -Bytes 4 -Allocations $allocations
        if (-not [bool](Invoke-Phase2B5Api 'GetExitCodeProcess' @($process,$suspendState)) -or
            [Runtime.InteropServices.Marshal]::ReadInt32($suspendState) -ne 259) {
            throw 'Child process did not remain suspended before Job Object assignment.'
        }
        $previousSuspendCount = [UInt32](Invoke-Phase2B5Api 'ResumeThread' @($thread))
        if ($previousSuspendCount -ne 1 -or $previousSuspendCount -eq [UInt32]::MaxValue) {
            throw ('ResumeThread returned an unexpected prior suspend count: ' + $previousSuspendCount)
        }

        $pipeStates = @(
            [pscustomobject]@{Name='stdout';Handle=$stdoutRead;Data=$stdoutBytes;Closed=$false;Probe=$stdoutRead},
            [pscustomobject]@{Name='stderr';Handle=$stderrRead;Data=$stderrBytes;Closed=$false;Probe=$stderrRead}
        )
        $readerFailureInjected = $false

        $availablePointer = New-Phase2B5Buffer -Bytes 4 -Allocations $allocations
        $readCountPointer = New-Phase2B5Buffer -Bytes 4 -Allocations $allocations
        $readBuffer = New-Phase2B5Buffer -Bytes $script:ChunkSize -Allocations $allocations
        $deadlineMilliseconds = $TimeoutMilliseconds
        $status = 'Running'

        while ($true) {
            $madeProgress = $false

            foreach ($pipe in $pipeStates) {
                if ($pipe.Closed) { continue }
                $peek = Get-Phase2B5AvailableBytes -PipeReadHandle $pipe.Probe -AvailablePointer $availablePointer
                if ($peek.Error -ne 0) {
                    $status = 'ReaderFailure'
                    $failure = ('PeekNamedPipe(' + $pipe.Name + ') failed: Win32=' + $peek.Error)
                    break
                }
                if ($peek.Closed) {
                    $pipe.Closed = $true
                    $madeProgress = $true
                    continue
                }
                if ($peek.Available -gt 0) {
                    $remaining = $script:OutputLimit - $combinedCount
                    if ($remaining -le 0) {
                        $status = 'CapExceeded'
                        $failure = 'Combined stdout/stderr output exceeded the fixed 65536-byte cap.'
                        break
                    }
                    $readSize = [Math]::Min([int]$script:ChunkSize,[Math]::Min([int]$peek.Available,$remaining))
                    [Runtime.InteropServices.Marshal]::WriteInt32($readCountPointer,0,0)
                    $readOk = [bool](Invoke-Phase2B5Api 'ReadFile' @(
                        $pipe.Handle,$readBuffer,[UInt32]$readSize,$readCountPointer,[IntPtr]::Zero
                    ))
                    if (-not $readOk) {
                        $readError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
                        if ($readError -eq 109) {
                            $pipe.Closed = $true
                            $madeProgress = $true
                            continue
                        }
                        $status = 'ReaderFailure'
                        $failure = ('ReadFile(' + $pipe.Name + ') failed: Win32=' + $readError)
                        break
                    }
                    $actual = [Runtime.InteropServices.Marshal]::ReadInt32($readCountPointer)
                    if ($actual -lt 0 -or $actual -gt $readSize) {
                        $status = 'ReaderFailure'
                        $failure = ('ReadFile(' + $pipe.Name + ') returned an invalid byte count.')
                        break
                    }
                    if ($actual -gt 0) {
                        $chunk = New-Object byte[] $actual
                        [Runtime.InteropServices.Marshal]::Copy($readBuffer,$chunk,0,$actual)
                        $pipe.Data.AddRange($chunk)
                        $combinedCount += $actual
                        $madeProgress = $true
                    }
                }
            }

            if ($Mode -eq 'Descendant' -and -not $descendantMembershipVerified -and (Test-Path -LiteralPath $pidPath -PathType Leaf)) {
                $observedDescendantPid = [int][IO.File]::ReadAllText($pidPath)
                $descendantProbe = $null
                try {
                    $descendantProbe = [Diagnostics.Process]::GetProcessById($observedDescendantPid)
                    $descendantMembership = New-Phase2B5Buffer -Bytes 4 -Allocations $allocations
                    $descendantInJob = [bool](Invoke-Phase2B5Api 'IsProcessInJob' @(
                        $descendantProbe.Handle,$job,$descendantMembership
                    ))
                    $descendantMembershipVerified = ($descendantInJob -and [Runtime.InteropServices.Marshal]::ReadInt32($descendantMembership) -eq 1)
                    if (-not $descendantMembershipVerified) {
                        $descendantProbe.Kill()
                        [void]$descendantProbe.WaitForExit(5000)
                    }
                } catch {
                    $descendantMembershipVerified = $false
                } finally {
                    if ($null -ne $descendantProbe) { $descendantProbe.Dispose() }
                }
            }

            if ($status -eq 'CapExceeded' -or $status -eq 'ReaderFailure') { break }
            if ($InjectReaderFailure -and -not $readerFailureInjected -and $combinedCount -gt 0) {
                $pipeStates[0].Handle = [IntPtr](-1)
                $readerFailureInjected = $true
            }

            $wait = [UInt32](Invoke-Phase2B5Api 'WaitForSingleObject' @($process,[UInt32]0))
            if ($wait -eq 0) {
                $processExited = $true
            } elseif ($wait -eq 258) {
                $processExited = $false
            } else {
                $status = 'ReaderFailure'
                $failure = ('WaitForSingleObject returned unexpected status 0x{0:X8}.' -f $wait)
                break
            }

            if ($processExited -and $pipeStates[0].Closed -and $pipeStates[1].Closed) {
                $status = 'Completed'
                break
            }
            if ($timer.ElapsedMilliseconds -ge $deadlineMilliseconds) {
                $status = 'TimedOut'
                $failure = ('Child process exceeded the {0} ms deadline.' -f $deadlineMilliseconds)
                break
            }
            if (-not $madeProgress) { Start-Sleep -Milliseconds 5 }
        }

        if ($status -ne 'Completed') {
            [void](Stop-Phase2B5JobAndReap -JobHandle $job -ProcessHandle $process -JobAssigned $jobAssigned)
            $processReaped = $true
        } else {
            $waitFinal = [UInt32](Invoke-Phase2B5Api 'WaitForSingleObject' @($process,[UInt32]5000))
            if ($waitFinal -ne 0) { throw ('Completed child failed final wait/reap: 0x{0:X8}.' -f $waitFinal) }
            $processReaped = $true
            $exitOutput = New-Phase2B5Buffer -Bytes 4 -Allocations $allocations
            if (-not [bool](Invoke-Phase2B5Api 'GetExitCodeProcess' @($process,$exitOutput))) {
                throw ('GetExitCodeProcess failed: Win32=' + [Runtime.InteropServices.Marshal]::GetLastWin32Error())
            }
            $exitCode = [Runtime.InteropServices.Marshal]::ReadInt32($exitOutput)
            if ($exitCode -ne 0) { throw ('Fixed child returned nonzero exit code: ' + $exitCode) }
        }
    }
    catch {
        $failure = $_.Exception.Message
        if ($status -eq 'Running' -or $status -eq 'NotStarted') { $status = 'SetupFailure' }
    }
    finally {
        if ($attributeListInitialized -and $attributeList -ne [IntPtr]::Zero) {
            try { [void](Invoke-Phase2B5Api 'DeleteProcThreadAttributeList' @($attributeList)) }
            catch { $cleanupVerified = $false }
            $attributeListInitialized = $false
        }
        if ($processCreated -and -not $processReaped -and $process -ne [IntPtr]::Zero) {
            try {
                [void](Stop-Phase2B5JobAndReap -JobHandle $job -ProcessHandle $process -JobAssigned $jobAssigned)
                $processReaped = $true
            } catch { $cleanupVerified = $false }
        }
        foreach ($handle in @($handles.ToArray())) {
            if ($handle -ne [IntPtr]::Zero) {
                try {
                    if (-not [bool](Invoke-Phase2B5Api 'CloseHandle' @($handle))) { $cleanupVerified = $false }
                } catch { $cleanupVerified = $false }
            }
        }
        for ($i = $allocations.Count - 1; $i -ge 0; $i--) {
            try { [Runtime.InteropServices.Marshal]::FreeHGlobal($allocations[$i]) }
            catch { $cleanupVerified = $false }
        }
        if ($null -ne $scriptStream) {
            try { $scriptStream.Dispose() } catch { $cleanupVerified = $false }
        }
    }

    if (-not $cleanupVerified) { throw 'Phase 2B.5 failed to close every process, thread, job, pipe and sentinel handle.' }
    if ($processCreated -and -not $processReaped) { throw 'Phase 2B.5 child was not confirmed reaped.' }
    if ($status -eq 'Completed' -and $exitCode -ne 0) { throw ('Completed fixed child exit code is not zero: ' + $exitCode) }

    return [pscustomobject]@{
        Mode=$Mode
        Status=$status
        Failure=$failure
        ExitCode=$exitCode
        ProcessId=$childProcessId
        DescendantMembershipVerified=$descendantMembershipVerified
        ProcessReaped=$processReaped
        JobAssigned=$jobAssigned
        Stdout=$stdoutBytes
        Stderr=$stderrBytes
        CombinedBytes=$combinedCount
        Truncated=($status -in @('CapExceeded','ReaderFailure','TimedOut'))
        OutputComplete=($status -eq 'Completed')
        ReportPath=$reportPath
        PidPath=$pidPath
        TrialDirectory=$trialDirectory
        ChildImageSha256=$childImageHash
        ChildScriptSha256=$childScriptHash
        CleanupVerified=$cleanupVerified
        PreviousSuspendCount=$previousSuspendCount
    }
}

try {
    [void][IO.Directory]::CreateDirectory($script:BaseDirectory)

    if (-not (Test-Path -LiteralPath $script:ChildImage -PathType Leaf)) {
        throw ('The fixed System32 PowerShell image is missing: ' + $script:ChildImage)
    }
    if (-not (Test-Path -LiteralPath $script:NativeInteropPath -PathType Leaf)) {
        throw ('The native interop helper is missing: ' + $script:NativeInteropPath)
    }
    $fixedChildHash = (Get-FileHash -LiteralPath $script:ChildScript -Algorithm SHA256).Hash
    if ($fixedChildHash -cne [string]$manifest.phase2B5Contract.fixedChildSha256) {
        throw 'Fixed test child does not match the SHA-256 pinned manifest.'
    }

    $module = New-SharnouNativeInteropModule -Name 'Sharnou.DevAgent.Phase2B5'
    $script:Types = New-SharnouRuntimeStructTypes -Module $module -StructureManifest @($manifest.structureLayouts)
    $script:ApiType = New-SharnouNativeApiType -Module $module -ApiManifest (
        @($manifest.testFixtureApis) + @($manifest.phase2B4Apis) + @($manifest.phase2B5Apis)
    )

    $signatureExpectations = @(
        [pscustomobject]@{Name='CreatePipe';Count=4;Return=[Boolean]},
        [pscustomobject]@{Name='SetHandleInformation';Count=3;Return=[Boolean]},
        [pscustomobject]@{Name='GetHandleInformation';Count=2;Return=[Boolean]},
        [pscustomobject]@{Name='ReadFile';Count=5;Return=[Boolean]},
        [pscustomobject]@{Name='PeekNamedPipe';Count=6;Return=[Boolean]},
        [pscustomobject]@{Name='CloseHandle';Count=1;Return=[Boolean]},
        [pscustomobject]@{Name='GetProcessHandleCount';Count=2;Return=[Boolean]}
    )
    foreach ($expected in $signatureExpectations) {
        $method = $script:ApiType.GetMethod($expected.Name)
        Assert-Phase2B5 ($null -ne $method) ('reviewed native API is present: ' + $expected.Name)
        Assert-Phase2B5 ($method.GetParameters().Count -eq $expected.Count) ('native parameter count matches ABI contract: ' + $expected.Name)
        Assert-Phase2B5 ($method.ReturnType -eq $expected.Return) ('native return type matches ABI contract: ' + $expected.Name)
    }

    $securityAttributesType = $script:Types['SECURITY_ATTRIBUTES']
    Assert-Phase2B5 ((Get-SharnouMarshalSize -NativeType $securityAttributesType) -eq 24) 'SECURITY_ATTRIBUTES has the expected 24-byte x64 layout'
    Assert-Phase2B5 ((Get-SharnouMarshalOffset -NativeType $securityAttributesType -FieldName 'lpSecurityDescriptor') -eq 8) 'SECURITY_ATTRIBUTES pointer field is at x64 offset 8'
    Assert-Phase2B5 ((Get-SharnouMarshalOffset -NativeType $securityAttributesType -FieldName 'bInheritHandle') -eq 16) 'SECURITY_ATTRIBUTES inherit flag is at x64 offset 16'
    Assert-Phase2B5 ((Get-SharnouMarshalSize -NativeType $script:Types['STARTUPINFOEXW']) -eq 112) 'STARTUPINFOEXW retains the expected 112-byte x64 layout'
    Assert-Phase2B5 ((Get-SharnouMarshalOffset -NativeType $script:Types['STARTUPINFOEXW'] -FieldName 'lpAttributeList') -eq 104) 'STARTUPINFOEXW attribute-list pointer is at x64 offset 104'

    [void](Get-Phase2B5HandleCount)
    $baselineHandles = Get-Phase2B5HandleCount
    $script:SupervisorHandleBaseline = $baselineHandles
    $small = Invoke-Phase2B5Trial -Mode 'Streams' -TimeoutMilliseconds 10000 -CreateSentinel $true
    if ($small.Status -ne 'Completed') {
        Write-Host ('DIAGNOSTIC small trial: status={0}; failure={1}; exit={2}; job={3}; reaped={4}; combined={5}' -f $small.Status,$small.Failure,$small.ExitCode,$small.JobAssigned,$small.ProcessReaped,$small.CombinedBytes) -ForegroundColor Yellow
    }
    Assert-Phase2B5 ($small.Status -eq 'Completed' -and $small.ExitCode -eq 0 -and $small.ProcessReaped) ('fixed child completes under a Job Object and is reaped; status={0}; failure={1}; exit={2}; job={3}; reaped={4}' -f $small.Status,$small.Failure,$small.ExitCode,$small.JobAssigned,$small.ProcessReaped)
    $smallOut = [Text.Encoding]::ASCII.GetString($small.Stdout.ToArray())
    $smallErr = [Text.Encoding]::ASCII.GetString($small.Stderr.ToArray())
    Assert-Phase2B5 ($smallOut -ceq ("stdout-ok" + [char]10)) 'stdout is captured byte-exactly'
    Assert-Phase2B5 ($smallErr -ceq ("stderr-ok" + [char]10)) 'stderr is captured byte-exactly and independently'
    Assert-Phase2B5 ((Test-Path -LiteralPath $small.ReportPath -PathType Leaf) -and ([IO.File]::ReadAllText($small.ReportPath) -ceq 'DENIED')) 'an inheritable sentinel handle omitted from the explicit allowlist is not inherited'

    $boundary = Invoke-Phase2B5Trial -Mode 'Boundary' -TimeoutMilliseconds 15000
    Assert-Phase2B5 ($boundary.Status -eq 'Completed' -and $boundary.CombinedBytes -eq 65536) 'exact combined output-cap boundary completes without truncation'
    Assert-Phase2B5 ($boundary.Stdout.Count -eq 32768 -and $boundary.Stderr.Count -eq 32768) 'exact-boundary capture preserves both independent stream lengths'
    Assert-Phase2B5 (@($boundary.Stdout.ToArray() | Where-Object { $_ -ne 65 }).Count -eq 0) 'stdout boundary payload remains byte-exact'
    Assert-Phase2B5 (@($boundary.Stderr.ToArray() | Where-Object { $_ -ne 66 }).Count -eq 0) 'stderr boundary payload remains byte-exact'

    $flood = Invoke-Phase2B5Trial -Mode 'Flood' -TimeoutMilliseconds 15000
    Assert-Phase2B5 ($flood.Status -eq 'CapExceeded' -and $flood.Truncated) 'combined output overflow is detected and reported explicitly'
    Assert-Phase2B5 ($flood.CombinedBytes -eq 65536 -and $flood.Stdout.Count + $flood.Stderr.Count -le 65536) 'captured partial stdout/stderr never exceed the 65536-byte cap'
    Assert-Phase2B5 ($flood.Truncated -and -not $flood.OutputComplete) 'overflow output is explicitly marked truncated/incomplete'
    Assert-Phase2B5 ($flood.ProcessReaped -and $flood.JobAssigned) 'output overflow terminates the Job Object and reaps the child'

    $timeout = Invoke-Phase2B5Trial -Mode 'Timeout' -TimeoutMilliseconds 5000
    Assert-Phase2B5 ($timeout.Status -eq 'TimedOut' -and $timeout.ProcessReaped) 'timeout terminates the Job Object and reaps the process'
    Assert-Phase2B5 ($timeout.Truncated -and -not $timeout.OutputComplete) 'timeout partial output is explicitly marked incomplete'
    Assert-Phase2B5 ($timeout.CombinedBytes -le 65536) 'timeout preserves only bounded partial output'

    $readerFailure = Invoke-Phase2B5Trial -Mode 'Flood' -TimeoutMilliseconds 10000 -InjectReaderFailure $true
    Assert-Phase2B5 ($readerFailure.Status -eq 'ReaderFailure' -and $readerFailure.ProcessReaped -and $readerFailure.Failure.StartsWith('ReadFile(stdout)')) 'ReadFile failure fails closed by terminating and reaping the Job Object child'
    Assert-Phase2B5 ($readerFailure.CombinedBytes -gt 0 -and $readerFailure.CombinedBytes -le 65536) 'reader-failure partial output is preserved and remains within the combined cap'
    Assert-Phase2B5 ($readerFailure.Truncated -and -not $readerFailure.OutputComplete) 'reader-failure partial output is explicitly marked incomplete'

    $descendant = Invoke-Phase2B5Trial -Mode 'Descendant' -TimeoutMilliseconds 7000
    Assert-Phase2B5 ($descendant.Status -eq 'TimedOut' -and $descendant.ProcessReaped) 'descendant fixture reaches timeout and reaps the root process'
    $descendantPid = 0
    if (Test-Path -LiteralPath $descendant.PidPath -PathType Leaf) {
        $descendantPid = [int][IO.File]::ReadAllText($descendant.PidPath)
    }
    Assert-Phase2B5 ($descendantPid -gt 0) 'fixed child created its expected descendant inside the Job Object'
    Assert-Phase2B5 $descendant.DescendantMembershipVerified 'spawned descendant is verified in the same Job Object before termination'
    $descendantGone = $false
    if ($descendantPid -gt 0) {
        $descendantProcess = $null
        try {
            $descendantProcess = [Diagnostics.Process]::GetProcessById($descendantPid)
            $descendantGone = $descendantProcess.WaitForExit(5000)
        } catch [ArgumentException] {
            $descendantGone = $true
        } finally {
            if ($null -ne $descendantProcess) { $descendantProcess.Dispose() }
        }
    }
    Assert-Phase2B5 $descendantGone 'Job Object termination also terminates and reaps the descendant process'

    $finalHandles = Get-Phase2B5HandleCount
    Assert-Phase2B5 ($finalHandles -le ($baselineHandles + 2)) ('native handle count returns to baseline after all trials (before={0}, after={1})' -f $baselineHandles,$finalHandles)

    Write-Host ('Phase 2B.5 bounded pipe fixture: PASS (' + $script:Passed + ' assertions)') -ForegroundColor Green
    Write-Host ('Combined output cap: ' + $script:OutputLimit + ' bytes')
    Write-Host ('Test source SHA-256: ' + (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash)
    Write-Host ('Manifest SHA-256: ' + (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash)
    Write-Host ('Native interop SHA-256: ' + (Get-FileHash -LiteralPath $script:NativeInteropPath -Algorithm SHA256).Hash)
    Write-Host ('Fixed child script SHA-256: ' + $fixedChildHash)
    Write-Host ('PowerShell image SHA-256: ' + (Get-FileHash -LiteralPath $script:ChildImage -Algorithm SHA256).Hash)
    Write-Host ('Native handle count: before={0}; after={1}' -f $baselineHandles,$finalHandles)
    Write-Host 'BOUNDARY: test-only caller-token fixture; lpEnvironment=NULL inherits the CI environment. Production clean environment and AppContainer integration remain separate acceptance gates.'
}
catch {
    Write-Host ('Phase 2B.5 result: FAIL - ' + $_.Exception.Message) -ForegroundColor Red
    throw
}
finally {
    if ($null -ne $script:ScratchAllocations) {
        for ($i=$script:ScratchAllocations.Count-1; $i -ge 0; $i--) {
            try { [Runtime.InteropServices.Marshal]::FreeHGlobal($script:ScratchAllocations[$i]) } catch {}
        }
    }
    if (Test-Path -LiteralPath $script:BaseDirectory) {
        Remove-Item -LiteralPath $script:BaseDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}
Write-Host 'Phase 2B.5 result: PASS' -ForegroundColor Green
