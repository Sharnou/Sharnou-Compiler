[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSEdition -ne 'Desktop') {
    throw 'Phase 2B.4 requires Windows PowerShell 5.1.'
}
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or [IntPtr]::Size -ne 8) {
    throw 'Phase 2B.4 requires 64-bit Windows.'
}

. (Join-Path $PSScriptRoot 'DevAgentBroker\NativeInterop.ps1')
. (Join-Path $PSScriptRoot 'DevAgentBroker\WorkspaceTransaction.ps1')

$manifestPath = Join-Path $PSScriptRoot 'DevAgentBroker\native-abi-manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (@($manifest.testFixtureApis).Count -ne 22) { throw 'The Phase 2B.2 API manifest changed unexpectedly.' }
if (@($manifest.phase2B4Apis).Count -ne 6) { throw 'Phase 2B.4 requires exactly six separately reviewed Job Object/resume APIs.' }

$module = New-SharnouNativeInteropModule -Name 'Sharnou.DevAgent.Phase2B4'
$types = New-SharnouRuntimeStructTypes -Module $module -StructureManifest @($manifest.structureLayouts)
$script:Types = $types
$script:ApiType = New-SharnouNativeApiType -Module $module -ApiManifest (@($manifest.testFixtureApis) + @($manifest.phase2B4Apis))
$script:ProfileAllocations = New-Object 'System.Collections.Generic.List[IntPtr]'
$script:Profiles = New-Object 'System.Collections.Generic.List[object]'
$script:Transactions = New-Object 'System.Collections.Generic.List[object]'
$script:Passed = 0
$script:CleanupSafe = $true
$script:Base = Join-Path $env:TEMP ('Sharnou-DevAgent-2B4-' + [Guid]::NewGuid().ToString('N'))
$script:WorkspaceRoot = Join-Path $script:Base 'executions'
$script:JournalRoot = Join-Path $script:Base 'journal'
$script:SupervisorSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$script:SystemSid = 'S-1-5-18'
$script:ChildImage = [IO.Path]::GetFullPath((Join-Path ([Environment]::SystemDirectory) 'whoami.exe'))
$script:SystemDirectory = [Environment]::SystemDirectory
$script:TempDirectory = [IO.Path]::GetTempPath()
$script:Failure = $null

function Assert-Phase2B4 {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw ("FAIL: " + $Message) }
    $script:Passed++
    Write-Host ("PASS: " + $Message) -ForegroundColor Green
}

function Invoke-Phase2B4Api {
    param([string]$Name,[object[]]$Arguments)
    return Invoke-SharnouNativeApi -ApiType $script:ApiType -Name $Name -Arguments $Arguments
}

function New-Phase2B4Buffer {
    param([int]$Bytes,[System.Collections.Generic.List[IntPtr]]$Allocations)
    if ($Bytes -lt 1 -or $Bytes -gt 65536) { throw "Unmanaged allocation is outside the 64 KiB bound: $Bytes." }
    $pointer = [Runtime.InteropServices.Marshal]::AllocHGlobal($Bytes)
    if ($pointer -eq [IntPtr]::Zero) { throw "AllocHGlobal failed for $Bytes bytes." }
    [Runtime.InteropServices.Marshal]::Copy((New-Object byte[] $Bytes),0,$pointer,$Bytes)
    $Allocations.Add($pointer)
    return $pointer
}

function New-Phase2B4Unicode {
    param([string]$Value,[System.Collections.Generic.List[IntPtr]]$Allocations)
    $pointer = [Runtime.InteropServices.Marshal]::StringToHGlobalUni($Value)
    if ($pointer -eq [IntPtr]::Zero) { throw 'Unicode string allocation returned NULL.' }
    $Allocations.Add($pointer)
    return $pointer
}

function New-Phase2B4Profile {
    param([string]$Label)

    $name = 'Sharnou.DevAgent.2B4.' + [Guid]::NewGuid().ToString('N')
    $namePointer = [Runtime.InteropServices.Marshal]::StringToHGlobalUni($name)
    $displayPointer = [Runtime.InteropServices.Marshal]::StringToHGlobalUni('Sharnou DevAgent 2B4 ' + $Label)
    $descriptionPointer = [Runtime.InteropServices.Marshal]::StringToHGlobalUni('Test-only fixed-image AppContainer Job Object launch.')
    foreach ($pointer in @($namePointer,$displayPointer,$descriptionPointer)) {
        if ($pointer -eq [IntPtr]::Zero) { throw 'Profile string allocation returned NULL.' }
        $script:ProfileAllocations.Add($pointer)
    }
    $sidOutput = New-Phase2B4Buffer -Bytes 8 -Allocations $script:ProfileAllocations
    $hr = [Int32](Invoke-Phase2B4Api 'CreateAppContainerProfile' @(
        $namePointer,$displayPointer,$descriptionPointer,[IntPtr]::Zero,[UInt32]0,$sidOutput
    ))
    if ($hr -ne 0) { throw ('CreateAppContainerProfile failed: HRESULT=0x{0:X8}.' -f $hr) }
    $sid = [Runtime.InteropServices.Marshal]::ReadIntPtr($sidOutput)
    if ($sid -eq [IntPtr]::Zero) { throw 'CreateAppContainerProfile returned a NULL package SID.' }
    if (-not [bool](Invoke-Phase2B4Api 'IsValidSid' @($sid))) { throw 'CreateAppContainerProfile returned an invalid SID.' }
    $sidText = ([System.Security.Principal.SecurityIdentifier]::new($sid)).Value
    if ($sidText -notmatch '^S-1-15-2-(\d+-)*\d+$') { throw "Unexpected OS AppContainer SID: $sidText" }
    $profile = [pscustomobject]@{
        Name=$name
        NamePointer=$namePointer
        Sid=$sid
        SidText=$sidText
        Owned=$true
        SafeToDelete=$false
        Deleted=$false
    }
    $script:Profiles.Add($profile)
    return $profile
}

function Get-Phase2B4TokenInformation {
    param(
        [IntPtr]$Token,
        [Int32]$InformationClass,
        [System.Collections.Generic.List[IntPtr]]$Allocations
    )
    $returnLength = New-Phase2B4Buffer -Bytes 4 -Allocations $Allocations
    $probe = [bool](Invoke-Phase2B4Api 'GetTokenInformation' @(
        $Token,[Int32]$InformationClass,[IntPtr]::Zero,[UInt32]0,$returnLength
    ))
    $probeError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    $required = [Runtime.InteropServices.Marshal]::ReadInt32($returnLength)
    if ($probe -or $probeError -ne 122 -or $required -lt 4 -or $required -gt 65536) {
        throw ("TOKEN_GATE: invalid GetTokenInformation sizing response for class {0}: result={1}; error={2}; bytes={3}." -f $InformationClass,$probe,$probeError,$required)
    }
    $buffer = New-Phase2B4Buffer -Bytes $required -Allocations $Allocations
    $query = [bool](Invoke-Phase2B4Api 'GetTokenInformation' @(
        $Token,[Int32]$InformationClass,$buffer,[UInt32]$required,$returnLength
    ))
    if (-not $query) {
        throw ("TOKEN_GATE: GetTokenInformation class {0} failed: Win32={1}." -f $InformationClass,[Runtime.InteropServices.Marshal]::GetLastWin32Error())
    }
    $actual = [Runtime.InteropServices.Marshal]::ReadInt32($returnLength)
    if ($actual -lt 4 -or $actual -gt $required) {
        throw ("TOKEN_GATE: invalid GetTokenInformation result length for class {0}: {1}/{2}." -f $InformationClass,$actual,$required)
    }
    return [pscustomobject]@{Buffer=$buffer;Length=$actual}
}

function Get-Phase2B4VerifiedToken {
    param(
        [IntPtr]$Token,
        [string]$ExpectedPackageSid,
        [System.Collections.Generic.List[IntPtr]]$Allocations
    )

    $containerInfo = Get-Phase2B4TokenInformation -Token $Token -InformationClass 29 -Allocations $Allocations
    if ([Runtime.InteropServices.Marshal]::ReadInt32($containerInfo.Buffer) -ne 1) {
        throw 'TOKEN_GATE: TokenIsAppContainer is not TRUE.'
    }

    $sidInfo = Get-Phase2B4TokenInformation -Token $Token -InformationClass 31 -Allocations $Allocations
    $sidPointer = [Runtime.InteropServices.Marshal]::ReadIntPtr($sidInfo.Buffer)
    if ($sidPointer -eq [IntPtr]::Zero) { throw 'TOKEN_GATE: TokenAppContainerSid is NULL.' }
    if (-not [bool](Invoke-Phase2B4Api 'IsValidSid' @($sidPointer))) { throw 'TOKEN_GATE: TokenAppContainerSid is invalid.' }
    $actualSid = ([System.Security.Principal.SecurityIdentifier]::new($sidPointer)).Value
    if ($actualSid -cne $ExpectedPackageSid) {
        throw ("TOKEN_GATE: package SID mismatch; expected={0}; actual={1}." -f $ExpectedPackageSid,$actualSid)
    }

    $integrityInfo = Get-Phase2B4TokenInformation -Token $Token -InformationClass 25 -Allocations $Allocations
    if ($integrityInfo.Length -lt 16) { throw 'TOKEN_GATE: TokenIntegrityLevel buffer is shorter than TOKEN_MANDATORY_LABEL.' }
    $integritySid = [Runtime.InteropServices.Marshal]::ReadIntPtr($integrityInfo.Buffer,0)
    if ($integritySid -eq [IntPtr]::Zero) { throw 'TOKEN_GATE: TokenIntegrityLevel SID is NULL.' }
    $countPointer = [IntPtr](Invoke-Phase2B4Api 'GetSidSubAuthorityCount' @($integritySid))
    if ($countPointer -eq [IntPtr]::Zero) { throw 'TOKEN_GATE: integrity SID subauthority count pointer is NULL.' }
    $count = [Runtime.InteropServices.Marshal]::ReadByte($countPointer)
    if ($count -lt 1 -or $count -gt 15) { throw "TOKEN_GATE: invalid integrity SID subauthority count $count." }
    $ridPointer = [IntPtr](Invoke-Phase2B4Api 'GetSidSubAuthority' @($integritySid,[UInt32]($count-1)))
    if ($ridPointer -eq [IntPtr]::Zero) { throw 'TOKEN_GATE: integrity RID pointer is NULL.' }
    $integrityRid = [Runtime.InteropServices.Marshal]::ReadInt32($ridPointer)
    if ($integrityRid -lt 0 -or $integrityRid -gt 0x1000) {
        throw ("TOKEN_GATE: integrity level exceeds Low: RID=0x{0:X8}." -f $integrityRid)
    }

    $capabilityInfo = Get-Phase2B4TokenInformation -Token $Token -InformationClass 30 -Allocations $Allocations
    $capabilityCount = [Runtime.InteropServices.Marshal]::ReadInt32($capabilityInfo.Buffer)
    if ($capabilityCount -ne 0) { throw "TOKEN_GATE: expected zero TokenCapabilities entries; actual=$capabilityCount." }

    return [pscustomobject]@{
        IsAppContainer=$true
        PackageSid=$actualSid
        IntegrityRid=$integrityRid
        CapabilityCount=$capabilityCount
    }
}

function Assert-Phase2B4ResumeGates {
    param([hashtable]$Gates)
    $required = @(
        'WorkspaceAclReady','ExplicitEnvironmentReady','ChildStillSuspended',
        'JobConfigured','JobAssigned','JobMembershipVerified','TokenIsAppContainer',
        'PackageSidMatches','IntegrityAtMostLow','CapabilitiesEmpty','NoInheritedHandles'
    )
    foreach ($name in $required) {
        if (-not $Gates.ContainsKey($name) -or -not [bool]$Gates[$name]) {
            throw ("RESUME_GATE: required pre-resume condition is false: " + $name)
        }
    }
}

function Invoke-Phase2B4Trial {
    param([object]$Profile,[string]$FailurePoint,[string]$ExpectedPackageSid)

    $allocations = New-Object 'System.Collections.Generic.List[IntPtr]'
    $handles = New-Object 'System.Collections.Generic.List[IntPtr]'
    $jobHandle = [IntPtr]::Zero
    $processHandle = [IntPtr]::Zero
    $threadHandle = [IntPtr]::Zero
    $tokenHandle = [IntPtr]::Zero
    $attributeList = [IntPtr]::Zero
    $attributeListInitialized = $false
    $processCreated = $false
    $jobConfigured = $false
    $jobAssigned = $false
    $membershipVerified = $false
    $tokenVerified = $false
    $resumeAttempted = $false
    $resumed = $false
    $processReaped = $false
    $stillActiveBeforeCleanup = $false
    $cleanupVerified = $true
    $expectedFailureObserved = $false
    $failureMessage = ''
    $exitCode = -1
    $assignError = 0
    $imageHash = ''
    $previousSuspendCount = -1

    try {
        $jobHandle = [IntPtr](Invoke-Phase2B4Api 'CreateJobObjectW' @([IntPtr]::Zero,[IntPtr]::Zero))
        if ($jobHandle -eq [IntPtr]::Zero) { throw ("CreateJobObjectW failed: Win32={0}." -f [Runtime.InteropServices.Marshal]::GetLastWin32Error()) }
        $handles.Add($jobHandle)

        $jobInfoSize = Get-SharnouMarshalSize -NativeType $script:Types['JOBOBJECT_EXTENDED_LIMIT_INFORMATION']
        if ($jobInfoSize -ne 144) { throw "JOBOBJECT_EXTENDED_LIMIT_INFORMATION x64 size mismatch: $jobInfoSize." }
        $jobInfo = New-Phase2B4Buffer -Bytes $jobInfoSize -Allocations $allocations
        [Runtime.InteropServices.Marshal]::WriteInt32($jobInfo,16,0x00002108)
        [Runtime.InteropServices.Marshal]::WriteInt32($jobInfo,40,1)
        [Runtime.InteropServices.Marshal]::WriteInt64($jobInfo,112,268435456)
        if (-not [bool](Invoke-Phase2B4Api 'SetInformationJobObject' @($jobHandle,[Int32]9,$jobInfo,[UInt32]$jobInfoSize))) {
            throw ("SetInformationJobObject failed: Win32={0}." -f [Runtime.InteropServices.Marshal]::GetLastWin32Error())
        }
        $jobConfigured = $true

        $attributeSize = New-Phase2B4Buffer -Bytes 8 -Allocations $allocations
        $sizeProbe = [bool](Invoke-Phase2B4Api 'InitializeProcThreadAttributeList' @([IntPtr]::Zero,[UInt32]1,[UInt32]0,$attributeSize))
        $sizeError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        $attributeBytes = [Runtime.InteropServices.Marshal]::ReadInt64($attributeSize)
        if ($sizeProbe -or $sizeError -ne 122 -or $attributeBytes -le 0 -or $attributeBytes -gt 65536) {
            throw ("InitializeProcThreadAttributeList sizing failed: result={0}; error={1}; bytes={2}." -f $sizeProbe,$sizeError,$attributeBytes)
        }
        $attributeList = New-Phase2B4Buffer -Bytes ([int]$attributeBytes) -Allocations $allocations
        if (-not [bool](Invoke-Phase2B4Api 'InitializeProcThreadAttributeList' @($attributeList,[UInt32]1,[UInt32]0,$attributeSize))) {
            throw ("InitializeProcThreadAttributeList failed: Win32={0}." -f [Runtime.InteropServices.Marshal]::GetLastWin32Error())
        }
        $attributeListInitialized = $true

        $securityCapabilities = New-Phase2B4Buffer -Bytes 24 -Allocations $allocations
        [Runtime.InteropServices.Marshal]::WriteIntPtr($securityCapabilities,0,$Profile.Sid)
        [Runtime.InteropServices.Marshal]::WriteIntPtr($securityCapabilities,8,[IntPtr]::Zero)
        [Runtime.InteropServices.Marshal]::WriteInt32($securityCapabilities,16,0)
        [Runtime.InteropServices.Marshal]::WriteInt32($securityCapabilities,20,0)
        if (-not [bool](Invoke-Phase2B4Api 'UpdateProcThreadAttribute' @(
            $attributeList,[UInt32]0,[UIntPtr]::new([UInt64]0x00020009),$securityCapabilities,
            [UIntPtr]::new([UInt64]24),[IntPtr]::Zero,[IntPtr]::Zero
        ))) {
            throw ("UpdateProcThreadAttribute(SECURITY_CAPABILITIES) failed: Win32={0}." -f [Runtime.InteropServices.Marshal]::GetLastWin32Error())
        }

        $driveRoot = [System.IO.Path]::GetPathRoot($script:SystemDirectory)
        if ($driveRoot.Length -ne 3 -or $driveRoot[1] -ne ':' -or [char]$driveRoot[2] -ne [char]92) {
            throw 'The fixed System32 directory is not on a canonical local drive.'
        }
        if ([string]::IsNullOrWhiteSpace($env:SystemRoot)) { throw 'SystemRoot is missing from the supervisor environment.' }
        # Snapshot the native parent environment so the special =C: / =D: entries
        # are copied exactly, then filter it to a small explicit allowlist.
        $sourceEnvironment = [IntPtr](Invoke-Phase2B4Api 'GetEnvironmentStringsW' @())
        if ($sourceEnvironment -eq [IntPtr]::Zero) { throw 'GetEnvironmentStringsW returned NULL.' }
        $environmentEntries = New-Object 'System.Collections.Generic.List[string]'
        $wantedDriveNames = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        $wantedDriveNames.Add(('=' + $driveRoot.Substring(0,2))) | Out-Null
        $parentDirectory = [Environment]::CurrentDirectory
        $parentDrive = [System.IO.Path]::GetPathRoot($parentDirectory)
        if ($parentDrive.Length -eq 3 -and $parentDrive[1] -eq ':' -and [char]$parentDrive[2] -eq [char]92) {
            $wantedDriveNames.Add(('=' + $parentDrive.Substring(0,2))) | Out-Null
        }
        try {
            $cursor = $sourceEnvironment
            $totalChars = 0
            while ($true) {
                $entry = [Runtime.InteropServices.Marshal]::PtrToStringUni($cursor)
                if ($null -eq $entry -or $entry.Length -eq 0) { break }
                $totalChars += ($entry.Length + 1)
                if ($totalChars -gt 32768) { throw 'Parent environment block exceeds the 32768-character fixture bound.' }
                if ($entry.StartsWith('=')) {
                    if ($entry.Length -ge 5 -and $entry[2] -eq ':' -and $entry[3] -eq '=' -and $wantedDriveNames.Contains($entry.Substring(0,3))) {
                        $environmentEntries.Add($entry)
                    }
                }
                else {
                    $separator = $entry.IndexOf('=')
                    if ($separator -gt 0) {
                        $name = $entry.Substring(0,$separator)
                        if ($name -ieq 'SystemRoot' -or $name -ieq 'WINDIR') {
                            $environmentEntries.Add($entry)
                        }
                    }
                }
                $cursor = [IntPtr]::Add($cursor,(($entry.Length + 1) * 2))
            }
        }
        finally {
            if (-not [bool](Invoke-Phase2B4Api 'FreeEnvironmentStringsW' @($sourceEnvironment))) {
                throw ('FreeEnvironmentStringsW failed: Win32={0}.' -f [Runtime.InteropServices.Marshal]::GetLastWin32Error())
            }
        }
        $environmentEntries.Add(('PATH=' + $script:SystemDirectory))
        $environmentEntries.Add(('TEMP=' + $script:TempDirectory))
        $environmentEntries.Add(('TMP=' + $script:TempDirectory))
        if (@($environmentEntries | Where-Object { $_ -match '^SystemRoot=' }).Count -ne 1) {
            throw 'The filtered environment must contain exactly one SystemRoot entry.'
        }
        $environment = New-SharnouTrackedEnvironmentBlock -Entries $environmentEntries.ToArray() -Allocations $allocations

        Assert-SharnouNoReparseAncestors -Path $script:ChildImage
        if (-not (Test-Path -LiteralPath $script:ChildImage -PathType Leaf)) { throw 'Fixed System32 whoami.exe is missing.' }
        if (-not $script:ChildImage.StartsWith(($script:SystemDirectory.TrimEnd('\') + '\'),[StringComparison]::OrdinalIgnoreCase)) {
            throw 'Fixed test image escaped the System32 directory.'
        }
        $imageHash = (Get-FileHash -LiteralPath $script:ChildImage -Algorithm SHA256).Hash
        $application = New-Phase2B4Unicode -Value $script:ChildImage -Allocations $allocations
        $commandLine = New-Phase2B4Unicode -Value ('"' + $script:ChildImage + '"') -Allocations $allocations
        $currentDirectory = New-Phase2B4Unicode -Value $script:SystemDirectory -Allocations $allocations

        $startupSize = Get-SharnouMarshalSize -NativeType $script:Types['STARTUPINFOEXW']
        $processInfoSize = Get-SharnouMarshalSize -NativeType $script:Types['PROCESS_INFORMATION']
        if ($startupSize -ne 112 -or $processInfoSize -ne 24) { throw 'STARTUPINFOEXW or PROCESS_INFORMATION x64 size mismatch.' }
        $startup = New-Phase2B4Buffer -Bytes $startupSize -Allocations $allocations
        [Runtime.InteropServices.Marshal]::WriteInt32($startup,0,$startupSize)
        [Runtime.InteropServices.Marshal]::WriteIntPtr($startup,104,$attributeList)
        $processInfo = New-Phase2B4Buffer -Bytes $processInfoSize -Allocations $allocations
        $creationFlags = [UInt32](0x00080000 -bor 0x00000004 -bor 0x00000400)

        if (-not [bool](Invoke-Phase2B4Api 'CreateProcessW' @(
            $application,$commandLine,[IntPtr]::Zero,[IntPtr]::Zero,[Boolean]$false,
            $creationFlags,$environment,$currentDirectory,$startup,$processInfo
        ))) {
            throw ("CreateProcessW(CREATE_SUSPENDED AppContainer) failed: Win32={0}." -f [Runtime.InteropServices.Marshal]::GetLastWin32Error())
        }
        $processCreated = $true
        $processHandle = [Runtime.InteropServices.Marshal]::ReadIntPtr($processInfo,0)
        $threadHandle = [Runtime.InteropServices.Marshal]::ReadIntPtr($processInfo,8)
        $processId = [Runtime.InteropServices.Marshal]::ReadInt32($processInfo,16)
        if ($processHandle -eq [IntPtr]::Zero -or $threadHandle -eq [IntPtr]::Zero -or $processId -le 0) {
            throw 'CreateProcessW returned success with invalid PROCESS_INFORMATION fields.'
        }
        $handles.Add($processHandle)
        $handles.Add($threadHandle)
        if ($attributeListInitialized) {
            [void](Invoke-Phase2B4Api 'DeleteProcThreadAttributeList' @($attributeList))
            $attributeListInitialized = $false
        }

        $state = New-Phase2B4Buffer -Bytes 4 -Allocations $allocations
        if (-not [bool](Invoke-Phase2B4Api 'GetExitCodeProcess' @($processHandle,$state)) -or
            [Runtime.InteropServices.Marshal]::ReadInt32($state) -ne 259) {
            throw 'The newly created process was not confirmed STILL_ACTIVE while suspended.'
        }
        if ($FailurePoint -eq 'AfterProcessCreated') { throw 'INJECTED:AfterProcessCreated' }

        $jobForAssign = $jobHandle
        if ($FailurePoint -eq 'AssignFailure') { $jobForAssign = [IntPtr]::Zero }
        $assigned = [bool](Invoke-Phase2B4Api 'AssignProcessToJobObject' @($jobForAssign,$processHandle))
        if ($FailurePoint -eq 'AssignFailure') {
            $assignError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            if ($assigned -or $assignError -ne 6) {
                throw ("Invalid-job assignment negative control returned unexpected result: assigned={0}; Win32={1}." -f $assigned,$assignError)
            }
            throw 'INJECTED:AssignFailure'
        }
        if (-not $assigned) { throw ("AssignProcessToJobObject failed closed: Win32={0}." -f [Runtime.InteropServices.Marshal]::GetLastWin32Error()) }
        $jobAssigned = $true

        $membership = New-Phase2B4Buffer -Bytes 4 -Allocations $allocations
        $membershipCall = [bool](Invoke-Phase2B4Api 'IsProcessInJob' @($processHandle,$jobHandle,$membership))
        if (-not $membershipCall -or [Runtime.InteropServices.Marshal]::ReadInt32($membership) -ne 1) {
            throw ("IsProcessInJob did not verify the exact process/job association: Win32={0}." -f [Runtime.InteropServices.Marshal]::GetLastWin32Error())
        }
        $membershipVerified = $true

        $tokenOutput = New-Phase2B4Buffer -Bytes 8 -Allocations $allocations
        if (-not [bool](Invoke-Phase2B4Api 'OpenProcessToken' @($processHandle,[UInt32]0x0008,$tokenOutput))) {
            throw ("OpenProcessToken(TOKEN_QUERY) failed: Win32={0}." -f [Runtime.InteropServices.Marshal]::GetLastWin32Error())
        }
        $tokenHandle = [Runtime.InteropServices.Marshal]::ReadIntPtr($tokenOutput)
        if ($tokenHandle -eq [IntPtr]::Zero) { throw 'OpenProcessToken returned a NULL token.' }
        $handles.Add($tokenHandle)

        $sidToVerify = $ExpectedPackageSid
        if ($FailurePoint -eq 'TokenMismatch') { $sidToVerify = 'S-1-15-2-1-2-3-4-5-6-7' }
        $tokenSnapshot = Get-Phase2B4VerifiedToken -Token $tokenHandle -ExpectedPackageSid $sidToVerify -Allocations $allocations
        $stillActive = New-Phase2B4Buffer -Bytes 4 -Allocations $allocations
        if (-not [bool](Invoke-Phase2B4Api 'GetExitCodeProcess' @($processHandle,$stillActive)) -or
            [Runtime.InteropServices.Marshal]::ReadInt32($stillActive) -ne 259) {
            throw 'Child did not remain suspended through job assignment and token verification.'
        }

        if ($FailurePoint -eq 'TokenMismatch') { throw 'TOKEN_GATE: token mismatch negative control unexpectedly passed.' }
        if ($FailurePoint -eq 'ResumeGateDenied') {
            Assert-Phase2B4ResumeGates -Gates @{
                WorkspaceAclReady=$true;ExplicitEnvironmentReady=$true;ChildStillSuspended=$true
                JobConfigured=$jobConfigured;JobAssigned=$false;JobMembershipVerified=$membershipVerified
                TokenIsAppContainer=$tokenSnapshot.IsAppContainer;PackageSidMatches=$true
                IntegrityAtMostLow=($tokenSnapshot.IntegrityRid -le 0x1000)
                CapabilitiesEmpty=($tokenSnapshot.CapabilityCount -eq 0);NoInheritedHandles=$true
            }
        }

        $gates = @{
            WorkspaceAclReady=$true
            ExplicitEnvironmentReady=$true
            ChildStillSuspended=$true
            JobConfigured=$jobConfigured
            JobAssigned=$jobAssigned
            JobMembershipVerified=$membershipVerified
            TokenIsAppContainer=$tokenSnapshot.IsAppContainer
            PackageSidMatches=($tokenSnapshot.PackageSid -ceq $ExpectedPackageSid)
            IntegrityAtMostLow=($tokenSnapshot.IntegrityRid -le 0x1000)
            CapabilitiesEmpty=($tokenSnapshot.CapabilityCount -eq 0)
            NoInheritedHandles=$true
        }
        Assert-Phase2B4ResumeGates -Gates $gates

        # The sole ResumeThread call is below the complete fail-closed policy gate.
        $resumeAttempted = $true
        $previousSuspendCount = [UInt32](Invoke-Phase2B4Api 'ResumeThread' @($threadHandle))
        if ($previousSuspendCount -eq [UInt32]::MaxValue) {
            throw ("ResumeThread failed: Win32={0}." -f [Runtime.InteropServices.Marshal]::GetLastWin32Error())
        }
        if ($previousSuspendCount -ne 1) { throw "ResumeThread previous suspend count was not 1: $previousSuspendCount." }
        $resumed = $true

        $waitResult = [UInt32](Invoke-Phase2B4Api 'WaitForSingleObject' @($processHandle,[UInt32]15000))
        if ($waitResult -ne 0) { throw ("Fixed AppContainer image did not exit within 15 seconds: wait=0x{0:X8}." -f $waitResult) }
        $processReaped = $true
        $exitOutput = New-Phase2B4Buffer -Bytes 4 -Allocations $allocations
        if (-not [bool](Invoke-Phase2B4Api 'GetExitCodeProcess' @($processHandle,$exitOutput))) {
            throw ("GetExitCodeProcess failed: Win32={0}." -f [Runtime.InteropServices.Marshal]::GetLastWin32Error())
        }
        $exitCode = [Runtime.InteropServices.Marshal]::ReadInt32($exitOutput)
        if ($exitCode -ne 0) { throw "System32 whoami.exe returned exit code $exitCode." }
    }
    catch {
        $failureMessage = $_.Exception.Message
        if ($FailurePoint -eq 'TokenMismatch' -and $failureMessage.StartsWith('TOKEN_GATE: package SID mismatch')) {
            $expectedFailureObserved = $true
        } elseif ($FailurePoint -eq 'ResumeGateDenied' -and $failureMessage.StartsWith('RESUME_GATE:')) {
            $expectedFailureObserved = $true
        } elseif ($FailurePoint -eq 'AssignFailure' -and $failureMessage -ceq 'INJECTED:AssignFailure') {
            $expectedFailureObserved = $true
        } elseif ($FailurePoint -eq 'AfterProcessCreated' -and $failureMessage -ceq 'INJECTED:AfterProcessCreated') {
            $expectedFailureObserved = $true
        }
    }
    finally {
        if ($attributeListInitialized -and $attributeList -ne [IntPtr]::Zero) {
            try { [void](Invoke-Phase2B4Api 'DeleteProcThreadAttributeList' @($attributeList)) }
            catch { $cleanupVerified = $false }
        }

        if ($processCreated -and $processHandle -ne [IntPtr]::Zero) {
            if (-not $resumeAttempted) {
                $preCleanup = New-Phase2B4Buffer -Bytes 4 -Allocations $allocations
                $preCleanupOk = [bool](Invoke-Phase2B4Api 'GetExitCodeProcess' @($processHandle,$preCleanup))
                if ($preCleanupOk -and [Runtime.InteropServices.Marshal]::ReadInt32($preCleanup) -eq 259) {
                    $stillActiveBeforeCleanup = $true
                } else {
                    $cleanupVerified = $false
                }
            }

            if (-not $processReaped) {
                try {
                    if ($jobAssigned -and $jobHandle -ne [IntPtr]::Zero) {
                        $killed = [bool](Invoke-Phase2B4Api 'TerminateJobObject' @($jobHandle,[UInt32]0x0000DEAD))
                        if (-not $killed) { [void](Invoke-Phase2B4Api 'TerminateProcess' @($processHandle,[UInt32]0x0000DEAD)) }
                    } else {
                        [void](Invoke-Phase2B4Api 'TerminateProcess' @($processHandle,[UInt32]0x0000DEAD))
                    }
                    $cleanupWait = [UInt32](Invoke-Phase2B4Api 'WaitForSingleObject' @($processHandle,[UInt32]5000))
                    if ($cleanupWait -eq 0) { $processReaped = $true } else { $cleanupVerified = $false }
                } catch { $cleanupVerified = $false }
            }
        }

        foreach ($handle in @($tokenHandle,$threadHandle,$processHandle,$jobHandle)) {
            if ($handle -ne [IntPtr]::Zero) {
                try { if (-not [bool](Invoke-Phase2B4Api 'CloseHandle' @($handle))) { $cleanupVerified = $false } }
                catch { $cleanupVerified = $false }
            }
        }
        for ($i=$allocations.Count-1; $i -ge 0; $i--) {
            try { [Runtime.InteropServices.Marshal]::FreeHGlobal($allocations[$i]) }
            catch { $cleanupVerified = $false }
        }
    }

    if (-not $cleanupVerified) { throw 'Phase 2B.4 trial could not prove process/job cleanup.' }
    if ($FailurePoint -eq 'None') {
        if ($failureMessage) { throw ("Normal launch failed: " + $failureMessage) }
        if (-not $resumed -or -not $processReaped -or $exitCode -ne 0) { throw 'Normal launch did not resume and exit zero.' }
    } else {
        if (-not $expectedFailureObserved) { throw ("Expected fail-closed event '{0}' was not observed: {1}" -f $FailurePoint,$failureMessage) }
        if ($resumeAttempted -or $resumed) { throw "Negative control $FailurePoint reached ResumeThread." }
        if (-not $stillActiveBeforeCleanup -or -not $processReaped) {
            throw "Negative control $FailurePoint did not prove suspended state followed by successful reap."
        }
    }

    return [pscustomobject]@{
        FailurePoint=$FailurePoint
        ExpectedFailureObserved=$expectedFailureObserved
        ProcessCreated=$processCreated
        JobConfigured=$jobConfigured
        JobAssigned=$jobAssigned
        JobMembershipVerified=$membershipVerified
        TokenVerified=($FailurePoint -ne 'TokenMismatch' -and $jobAssigned)
        ResumeAttempted=$resumeAttempted
        Resumed=$resumed
        PreviousSuspendCount=$previousSuspendCount
        ProcessReaped=$processReaped
        StillActiveBeforeCleanup=$stillActiveBeforeCleanup
        ExitCode=$exitCode
        AssignWin32Error=$assignError
        ImageSha256=$imageHash
        CleanupVerified=$cleanupVerified
    }
}

function Remove-Phase2B4Profile {
    param([object]$Profile)
    if (-not $Profile.Owned -or -not $Profile.SafeToDelete) {
        throw ("Refusing to delete AppContainer profile without verified child/job termination and workspace rollback: " + $Profile.Name)
    }
    $hr = [Int32](Invoke-Phase2B4Api 'DeleteAppContainerProfile' @($Profile.NamePointer))
    if ($hr -ne 0) { throw ('DeleteAppContainerProfile failed: HRESULT=0x{0:X8}.' -f $hr) }
    $Profile.Deleted = $true
    $Profile.Owned = $false
    if ($Profile.Sid -ne [IntPtr]::Zero) {
        [void](Invoke-Phase2B4Api 'FreeSid' @($Profile.Sid))
        $Profile.Sid = [IntPtr]::Zero
    }
}

function Complete-Phase2B4Transaction {
    param([object]$Transaction)
    $original = [string]$Transaction.OriginalSddl
    $result = Complete-SharnouExecutionWorkspace -Transaction $Transaction -KeepRestoredWorkspace
    if ($result -ne 'RESTORED') { throw "Workspace did not enter RESTORED state: $result." }
    if ((Get-SharnouDirectorySddl -Path $Transaction.WorkspacePath) -cne $original) {
        throw 'Workspace rollback did not reproduce exact original owner/group/DACL SDDL.'
    }
    $recovery = Recover-SharnouExecutionWorkspaces -WorkspaceRoot $script:WorkspaceRoot -JournalRoot $script:JournalRoot -SupervisorSid $script:SupervisorSid
    if ($recovery.Failed -ne 0 -or $recovery.Deleted -ne 1) {
        throw ("Workspace finalization failed: recovered={0}; deleted={1}; failed={2}." -f $recovery.Recovered,$recovery.Deleted,$recovery.Failed)
    }
}

try {
    if (-not (Test-Path -LiteralPath $script:ChildImage -PathType Leaf)) { throw "Fixed System32 image missing: $script:ChildImage" }
    Assert-SharnouNoReparseAncestors -Path $script:ChildImage
    $jobApis = @($manifest.phase2B4Apis | ForEach-Object { $_.name })
    foreach ($name in @('CreateJobObjectW','SetInformationJobObject','AssignProcessToJobObject','IsProcessInJob','ResumeThread','TerminateJobObject')) {
        Assert-Phase2B4 ($jobApis -contains $name) ("manifest declares " + $name)
    }

    Assert-Phase2B4 ((Get-SharnouMarshalSize -NativeType $types['JOBOBJECT_EXTENDED_LIMIT_INFORMATION']) -eq 144 -and
        (Get-SharnouMarshalSize -NativeType $types['STARTUPINFOEXW']) -eq 112 -and
        (Get-SharnouMarshalSize -NativeType $types['PROCESS_INFORMATION']) -eq 24) 'runtime x64 job/startup/process structures have the expected 144/112/24-byte layouts'
    Assert-Phase2B4 ((0x2000 -bor 0x0008 -bor 0x0100) -eq 0x2108) 'Job Object policy selects kill-on-close, active-process limit and per-process memory limit'

    [void][IO.Directory]::CreateDirectory($script:Base)
    foreach ($path in @($script:WorkspaceRoot,$script:JournalRoot)) {
        [void][IO.Directory]::CreateDirectory($path)
        Assert-SharnouNoReparseAncestors -Path $path
        Set-SharnouProtectedDirectoryAcl -Path $path -AllowedSids @($script:SupervisorSid,$script:SystemSid)
    }
    $script:RootSddl = Get-SharnouDirectorySddl -Path $script:WorkspaceRoot
    $script:JournalSddl = Get-SharnouDirectorySddl -Path $script:JournalRoot

    $scenarios = @(
        [pscustomobject]@{Name='AfterProcessCreated';Label='failure before job assignment'},
        [pscustomobject]@{Name='AssignFailure';Label='invalid Job Object assignment'},
        [pscustomobject]@{Name='TokenMismatch';Label='package SID mismatch'},
        [pscustomobject]@{Name='ResumeGateDenied';Label='mandatory final gate denied'},
        [pscustomobject]@{Name='None';Label='fully authorized fixed test launch'}
    )

    foreach ($scenario in $scenarios) {
        $profile = New-Phase2B4Profile -Label $scenario.Name
        $transaction = New-SharnouExecutionWorkspace -WorkspaceRoot $script:WorkspaceRoot -JournalRoot $script:JournalRoot -ExecutionSid $profile.SidText -SupervisorSid $script:SupervisorSid
        $script:Transactions.Add($transaction)
        $result = Invoke-Phase2B4Trial -Profile $profile -FailurePoint $scenario.Name -ExpectedPackageSid $profile.SidText

        if ($scenario.Name -eq 'None') {
            Assert-Phase2B4 ($result.ProcessCreated -and $result.JobConfigured -and $result.JobAssigned -and $result.JobMembershipVerified) 'normal launch assigns the suspended child to its configured Job Object before resume'
            Assert-Phase2B4 $result.TokenVerified 'normal launch verifies the actual AppContainer token before resume'
            Assert-Phase2B4 ($result.ResumeAttempted -and $result.Resumed -and $result.PreviousSuspendCount -eq 1) 'ResumeThread is reached only after all mandatory gates pass'
            Assert-Phase2B4 ($result.ProcessReaped -and $result.ExitCode -eq 0) 'fixed System32 whoami.exe executes in AppContainer and exits zero'
        } else {
            Assert-Phase2B4 $result.ExpectedFailureObserved ("negative control rejected: " + $scenario.Label)
            Assert-Phase2B4 (-not $result.ResumeAttempted -and -not $result.Resumed) ("negative control never reaches ResumeThread: " + $scenario.Label)
            Assert-Phase2B4 ($result.StillActiveBeforeCleanup -and $result.ProcessReaped) ("negative control proves suspended child then termination/reap: " + $scenario.Label)
            if ($scenario.Name -in @('TokenMismatch','ResumeGateDenied')) {
                Assert-Phase2B4 ($result.JobAssigned -and $result.JobMembershipVerified) ("failed child was contained by its Job Object: " + $scenario.Label)
            }
            if ($scenario.Name -eq 'AssignFailure') {
                Assert-Phase2B4 ($result.AssignWin32Error -eq 6) 'invalid Job Object handle returns ERROR_INVALID_HANDLE (6)'
                Assert-Phase2B4 (-not $result.JobAssigned) 'failed assignment is never treated as process containment'
            }
        }

        Complete-Phase2B4Transaction -Transaction $transaction
        $profile.SafeToDelete = $result.CleanupVerified -and $result.ProcessReaped
        Assert-Phase2B4 $true ("exact workspace owner/group/DACL restored after " + $scenario.Name)
        Remove-Phase2B4Profile -Profile $profile
        Assert-Phase2B4 $profile.Deleted ("owned profile removed after process handles and workspace artifacts closed: " + $scenario.Name)
    }

    Assert-Phase2B4 ((Get-SharnouDirectorySddl -Path $script:WorkspaceRoot) -ceq $script:RootSddl) 'all trials preserve the shared workspace-root security descriptor'
    Assert-Phase2B4 ((Get-SharnouDirectorySddl -Path $script:JournalRoot) -ceq $script:JournalSddl) 'all trials preserve the private journal-root security descriptor'
    $journalFiles = @(Get-ChildItem -LiteralPath $script:JournalRoot -Force -File)
    $workspaceEntries = @(Get-ChildItem -LiteralPath $script:WorkspaceRoot -Force)
    Assert-Phase2B4 ($journalFiles.Count -eq 0 -and $workspaceEntries.Count -eq 0) 'five trials leave no workspace, journal, lease, temporary-file or backup residue'

    Write-Host ("Phase 2B.4 AppContainer Job Object fixture: PASS ({0} assertions)" -f $script:Passed) -ForegroundColor Green
    Write-Host ("Windows: {0}; PowerShell: {1}; architecture: x64" -f [Environment]::OSVersion.Version.ToString(),$PSVersionTable.PSVersion.ToString())
    Write-Host ("Fixed image SHA-256: {0}" -f (Get-FileHash -LiteralPath $script:ChildImage -Algorithm SHA256).Hash)
    Write-Host ("Test source SHA-256: {0}" -f (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash)
    Write-Host ("Workspace transaction SHA-256: {0}" -f (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'DevAgentBroker\WorkspaceTransaction.ps1') -Algorithm SHA256).Hash)
    Write-Host ("Interop helper SHA-256: {0}" -f (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'DevAgentBroker\NativeInterop.ps1') -Algorithm SHA256).Hash)
    Write-Host ("Manifest SHA-256: {0}" -f (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash)
}
catch {
    $script:Failure = $_.Exception.Message
}
finally {
    if ($script:CleanupSafe -and (Test-Path -LiteralPath $script:JournalRoot -PathType Container)) {
        foreach ($transaction in $script:Transactions) {
            if ($null -ne $transaction.LeaseStream -and -not $transaction.LeaseStream.SafeFileHandle.IsClosed) {
                try { [void](Complete-SharnouExecutionWorkspace -Transaction $transaction) }
                catch { $script:CleanupSafe = $false }
            }
        }
        try {
            $recovery = Recover-SharnouExecutionWorkspaces -WorkspaceRoot $script:WorkspaceRoot -JournalRoot $script:JournalRoot -SupervisorSid $script:SupervisorSid
            if ($recovery.Failed -ne 0) { $script:CleanupSafe = $false }
        } catch { $script:CleanupSafe = $false }
    }

    if ($script:CleanupSafe) {
        foreach ($profile in $script:Profiles) {
            if ($profile.Owned -and $profile.SafeToDelete) {
                try {
                    $hr = [Int32](Invoke-Phase2B4Api 'DeleteAppContainerProfile' @($profile.NamePointer))
                    if ($hr -ne 0) { $script:CleanupSafe = $false }
                    else {
                        $profile.Deleted = $true
                        $profile.Owned = $false
                        if ($profile.Sid -ne [IntPtr]::Zero) {
                            [void](Invoke-Phase2B4Api 'FreeSid' @($profile.Sid))
                            $profile.Sid = [IntPtr]::Zero
                        }
                    }
                } catch { $script:CleanupSafe = $false }
            } elseif ($profile.Owned -and -not $profile.SafeToDelete) {
                $script:CleanupSafe = $false
            }
        }
    }

    for ($i=$script:ProfileAllocations.Count-1; $i -ge 0; $i--) {
        try { [Runtime.InteropServices.Marshal]::FreeHGlobal($script:ProfileAllocations[$i]) }
        catch { $script:CleanupSafe = $false }
    }

    if ($script:CleanupSafe -and (Test-Path -LiteralPath $script:Base)) {
        Remove-Item -LiteralPath $script:Base -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        Write-Warning 'Emergency cleanup could not prove every process/profile/workspace safe; remaining artifacts are retained.'
    }
}

if ($null -ne $script:Failure) {
    Write-Host ("Phase 2B.4 AppContainer Job Object result: FAIL - " + $script:Failure) -ForegroundColor Red
    throw $script:Failure
}
if (-not $script:CleanupSafe) { throw 'Phase 2B.4 cleanup verification failed; protected artifacts were retained.' }
Write-Host 'Phase 2B.4 result: PASS' -ForegroundColor Green
