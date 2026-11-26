[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSEdition -ne 'Desktop') {
    throw 'Phase 2B.3 requires Windows PowerShell 5.1.'
}
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or [IntPtr]::Size -ne 8) {
    throw 'Phase 2B.3 requires 64-bit Windows.'
}

. (Join-Path $PSScriptRoot 'DevAgentBroker\NativeInterop.ps1')
. (Join-Path $PSScriptRoot 'DevAgentBroker\WorkspaceTransaction.ps1')

$manifestPath = Join-Path $PSScriptRoot 'DevAgentBroker\native-abi-manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if (@($manifest.testFixtureApis).Count -ne 22) { throw 'Phase 2B.3 requires exactly 22 reviewed test-fixture API signatures.' }

$module = New-SharnouNativeInteropModule -Name 'Sharnou.DevAgent.Phase2B3'
$types = New-SharnouRuntimeStructTypes -Module $module -StructureManifest @($manifest.structureLayouts)
$apiType = New-SharnouNativeApiType -Module $module -ApiManifest @($manifest.testFixtureApis)

$allocations = New-Object 'System.Collections.Generic.List[System.IntPtr]'
$handles = New-Object 'System.Collections.Generic.List[System.IntPtr]'
$profiles = New-Object 'System.Collections.Generic.List[object]'
$transactions = New-Object 'System.Collections.Generic.List[object]'
$childCreated = $false
$childTerminated = $false
$childProcessHandle = [IntPtr]::Zero
$threadImpersonating = $false
$cleanupSafe = $true
$failure = $null
$assertions = 0
$base = Join-Path $env:TEMP ('Sharnou-DevAgent-2B3-' + [Guid]::NewGuid().ToString('N'))
$workspaceRoot = Join-Path $base 'executions'
$journalRoot = Join-Path $base 'journal'
$sourceRoot = Join-Path $base 'compiler-source'
$brokerRoot = Join-Path $base 'broker-image'
$outsideRoot = Join-Path $base 'outside'
$supervisorSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$systemSid = 'S-1-5-18'

function Assert-Phase2B3 {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw ("FAIL: " + $Message) }
    $script:assertions++
    Write-Host ("PASS: " + $Message) -ForegroundColor Green
}

function New-Phase2B3Buffer {
    param([int]$Bytes)
    $pointer = [Runtime.InteropServices.Marshal]::AllocHGlobal($Bytes)
    if ($pointer -eq [IntPtr]::Zero) { throw "AllocHGlobal failed for $Bytes bytes." }
    [Runtime.InteropServices.Marshal]::Copy((New-Object byte[] $Bytes),0,$pointer,$Bytes)
    $allocations.Add($pointer)
    return $pointer
}

function New-Phase2B3String {
    param([string]$Value)
    $pointer = [Runtime.InteropServices.Marshal]::StringToHGlobalUni($Value)
    if ($pointer -eq [IntPtr]::Zero) { throw 'StringToHGlobalUni returned NULL.' }
    $allocations.Add($pointer)
    return $pointer
}

function Invoke-Phase2B3Api {
    param([string]$Name,[object[]]$Arguments)
    return Invoke-SharnouNativeApi -ApiType $apiType -Name $Name -Arguments $Arguments
}

function New-Phase2B3Profile {
    param([string]$Label)
    $suffix = [Guid]::NewGuid().ToString('N')
    $name = 'Sharnou.DevAgent.WsAcl.' + $suffix
    $namePointer = New-Phase2B3String $name
    $displayPointer = New-Phase2B3String ('Sharnou DevAgent Workspace ACL ' + $Label)
    $descriptionPointer = New-Phase2B3String 'Phase 2B.3 test-only AppContainer profile; no model-provided command.'
    $sidOutput = New-Phase2B3Buffer 8
    $hr = [Int32](Invoke-Phase2B3Api 'CreateAppContainerProfile' @(
        $namePointer,$displayPointer,$descriptionPointer,[IntPtr]::Zero,[UInt32]0,$sidOutput
    ))
    if ($hr -ne 0) { throw ('CreateAppContainerProfile failed with HRESULT 0x{0:X8}.' -f [UInt32]$hr) }
    $sid = [Runtime.InteropServices.Marshal]::ReadIntPtr($sidOutput)
    if ($sid -eq [IntPtr]::Zero) { throw 'CreateAppContainerProfile returned a NULL package SID.' }
    if (-not [bool](Invoke-Phase2B3Api 'IsValidSid' @($sid))) { throw 'CreateAppContainerProfile returned an invalid SID.' }
    $sidText = ([System.Security.Principal.SecurityIdentifier]::new($sid)).Value
    if ($sidText -notmatch '^S-1-15-2-(\d+-)*\d+$') { throw "OS package SID is outside the AppContainer namespace: $sidText" }
    $profile = [pscustomobject]@{ Name=$name; NamePointer=$namePointer; Sid=$sid; SidText=$sidText; Owned=$true }
    $profiles.Add($profile)
    Write-Host ("OS-created AppContainer {0} SID: {1}" -f $Label,$sidText)
    return $profile
}

function New-Phase2B3AppContainerChild {
    param([object]$Profile)
    $attributeSizePointer = New-Phase2B3Buffer 8
    [Runtime.InteropServices.Marshal]::WriteInt64($attributeSizePointer,0)
    $probe = [bool](Invoke-Phase2B3Api 'InitializeProcThreadAttributeList' @(
        [IntPtr]::Zero,[UInt32]1,[UInt32]0,$attributeSizePointer
    ))
    $probeError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    $attributeBytes = [Runtime.InteropServices.Marshal]::ReadInt64($attributeSizePointer)
    if ($probe -or $probeError -ne 122 -or $attributeBytes -le 0 -or $attributeBytes -gt 65536) {
        throw ("AppContainer attribute-list sizing failed: result={0}; error={1}; bytes={2}." -f $probe,$probeError,$attributeBytes)
    }
    $attributeList = New-Phase2B3Buffer ([int]$attributeBytes)
    $initialized = $false
    try {
        if (-not [bool](Invoke-Phase2B3Api 'InitializeProcThreadAttributeList' @(
            $attributeList,[UInt32]1,[UInt32]0,$attributeSizePointer
        ))) {
            throw ("InitializeProcThreadAttributeList failed: {0}." -f [Runtime.InteropServices.Marshal]::GetLastWin32Error())
        }
        $initialized = $true
        $securityCapabilities = New-Phase2B3Buffer 24
        [Runtime.InteropServices.Marshal]::WriteIntPtr($securityCapabilities,0,$Profile.Sid)
        [Runtime.InteropServices.Marshal]::WriteIntPtr($securityCapabilities,8,[IntPtr]::Zero)
        [Runtime.InteropServices.Marshal]::WriteInt32($securityCapabilities,16,0)
        [Runtime.InteropServices.Marshal]::WriteInt32($securityCapabilities,20,0)
        if (-not [bool](Invoke-Phase2B3Api 'UpdateProcThreadAttribute' @(
            $attributeList,[UInt32]0,[UIntPtr]::new([UInt64]0x00020009),$securityCapabilities,
            [UIntPtr]::new([UInt64]24),[IntPtr]::Zero,[IntPtr]::Zero
        ))) { throw ("UpdateProcThreadAttribute failed: {0}." -f [Runtime.InteropServices.Marshal]::GetLastWin32Error()) }

        $systemDirectory = [Environment]::SystemDirectory
        $childImage = [IO.Path]::GetFullPath((Join-Path $systemDirectory 'whoami.exe'))
        if (-not (Test-Path -LiteralPath $childImage -PathType Leaf)) { throw 'Fixed System32 whoami.exe is missing.' }
        $application = New-Phase2B3String $childImage
        $commandLine = New-Phase2B3String ('"' + $childImage + '"')
        $currentDirectory = New-Phase2B3String $systemDirectory
        $startupSize = Get-SharnouMarshalSize -NativeType $types['STARTUPINFOEXW']
        $processInfoSize = Get-SharnouMarshalSize -NativeType $types['PROCESS_INFORMATION']
        if ($startupSize -ne 112 -or $processInfoSize -ne 24) { throw 'STARTUPINFOEXW / PROCESS_INFORMATION x64 layout mismatch.' }
        $startup = New-Phase2B3Buffer $startupSize
        [Runtime.InteropServices.Marshal]::WriteInt32($startup,0,$startupSize)
        [Runtime.InteropServices.Marshal]::WriteIntPtr($startup,104,$attributeList)
        $processInfo = New-Phase2B3Buffer $processInfoSize
        $flags = [UInt32](0x00080000 -bor 0x00000004 -bor 0x00000400)
        # The child remains suspended and is terminated before its user-mode entry point.
        $created = [bool](Invoke-Phase2B3Api 'CreateProcessW' @(
            $application,$commandLine,[IntPtr]::Zero,[IntPtr]::Zero,[Boolean]$false,
            $flags,[IntPtr]::Zero,$currentDirectory,$startup,$processInfo
        ))
        if (-not $created) { throw ("CreateProcessW failed: Win32 error {0}." -f [Runtime.InteropServices.Marshal]::GetLastWin32Error()) }
        $process = [Runtime.InteropServices.Marshal]::ReadIntPtr($processInfo,0)
        $thread = [Runtime.InteropServices.Marshal]::ReadIntPtr($processInfo,8)
        $childProcessId = [Runtime.InteropServices.Marshal]::ReadInt32($processInfo,16)
        if ($process -eq [IntPtr]::Zero -or $thread -eq [IntPtr]::Zero -or $childProcessId -le 0) { throw 'CreateProcessW returned invalid process information.' }
        if ($process -ne [IntPtr]::Zero) {
            $handles.Add($process)
            $script:childCreated = $true
            $script:childProcessHandle = $process
        }
        if ($thread -ne [IntPtr]::Zero) { $handles.Add($thread) }

        $tokenOutput = New-Phase2B3Buffer 8
        if (-not [bool](Invoke-Phase2B3Api 'OpenProcessToken' @($process,[UInt32]0x000A,$tokenOutput))) {
            throw ("OpenProcessToken(TOKEN_QUERY|TOKEN_DUPLICATE) failed: {0}." -f [Runtime.InteropServices.Marshal]::GetLastWin32Error())
        }
        $primaryToken = [Runtime.InteropServices.Marshal]::ReadIntPtr($tokenOutput)
        if ($primaryToken -eq [IntPtr]::Zero) { throw 'OpenProcessToken returned NULL.' }
        $handles.Add($primaryToken)

        $isContainer = New-Phase2B3Buffer 4
        $returnLength = New-Phase2B3Buffer 4
        if (-not [bool](Invoke-Phase2B3Api 'GetTokenInformation' @($primaryToken,[Int32]29,$isContainer,[UInt32]4,$returnLength))) {
            throw ("GetTokenInformation(TokenIsAppContainer) failed: {0}." -f [Runtime.InteropServices.Marshal]::GetLastWin32Error())
        }
        if ([Runtime.InteropServices.Marshal]::ReadInt32($isContainer) -ne 1) { throw 'New child token is not an AppContainer.' }
        $sidBuffer = New-Phase2B3Buffer 128
        [Runtime.InteropServices.Marshal]::WriteInt32($returnLength,0)
        if (-not [bool](Invoke-Phase2B3Api 'GetTokenInformation' @($primaryToken,[Int32]31,$sidBuffer,[UInt32]128,$returnLength))) {
            throw ("GetTokenInformation(TokenAppContainerSid) failed: {0}." -f [Runtime.InteropServices.Marshal]::GetLastWin32Error())
        }
        $childSid = [Runtime.InteropServices.Marshal]::ReadIntPtr($sidBuffer)
        if ($childSid -eq [IntPtr]::Zero -or -not [bool](Invoke-Phase2B3Api 'IsValidSid' @($childSid)) -or
            -not [bool](Invoke-Phase2B3Api 'EqualSid' @($Profile.Sid,$childSid))) {
            throw 'Child token package SID does not equal the exact OS-created profile SID.'
        }

        $impersonationOutput = New-Phase2B3Buffer 8
        if (-not [bool](Invoke-Phase2B3Api 'DuplicateTokenEx' @(
            $primaryToken,[UInt32]0x000C,[IntPtr]::Zero,[UInt32]2,[UInt32]2,$impersonationOutput
        ))) { throw ("DuplicateTokenEx(SecurityImpersonation) failed: {0}." -f [Runtime.InteropServices.Marshal]::GetLastWin32Error()) }
        $impersonationToken = [Runtime.InteropServices.Marshal]::ReadIntPtr($impersonationOutput)
        if ($impersonationToken -eq [IntPtr]::Zero) { throw 'DuplicateTokenEx returned NULL.' }
        $handles.Add($impersonationToken)

        $exitCode = New-Phase2B3Buffer 4
        if (-not [bool](Invoke-Phase2B3Api 'GetExitCodeProcess' @($process,$exitCode)) -or
            [Runtime.InteropServices.Marshal]::ReadInt32($exitCode) -ne 259) {
            throw 'The AppContainer probe child did not remain suspended.'
        }
        return [pscustomobject]@{ Process=$process; Thread=$thread; Token=$primaryToken; ImpersonationToken=$impersonationToken; ProcessId=$childProcessId; ProfileSid=$Profile.SidText }
    }
    finally {
        if ($initialized) { [void](Invoke-Phase2B3Api 'DeleteProcThreadAttributeList' @($attributeList)) }
    }
}

function Invoke-Phase2B3Open {
    param([IntPtr]$Token,[string]$Path,[UInt32]$DesiredAccess,[UInt32]$Disposition,[bool]$ExpectedAllowed)
    if (-not [bool](Invoke-Phase2B3Api 'SetThreadToken' @([IntPtr]::Zero,$Token))) {
        throw ("SetThreadToken failed: {0}." -f [Runtime.InteropServices.Marshal]::GetLastWin32Error())
    }
    $script:threadImpersonating = $true
    $file = [IntPtr]::Zero
    $errorCode = 0
    try {
        $pathPointer = New-Phase2B3String $Path
        $file = [IntPtr](Invoke-Phase2B3Api 'CreateFileW' @(
            $pathPointer,$DesiredAccess,[UInt32]7,[IntPtr]::Zero,$Disposition,[UInt32]0x80,[IntPtr]::Zero
        ))
        if ($file -eq [IntPtr](-1)) { $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error() }
    }
    finally {
        if (-not [bool](Invoke-Phase2B3Api 'RevertToSelf' @())) { throw ("RevertToSelf failed: {0}." -f [Runtime.InteropServices.Marshal]::GetLastWin32Error()) }
        $script:threadImpersonating = $false
    }
    $opened = ($file -ne [IntPtr](-1))
    if ($opened) { [void](Invoke-Phase2B3Api 'CloseHandle' @($file)) }
    if ($ExpectedAllowed -and -not $opened) { throw "Expected AppContainer access was denied for '$Path': Win32 $errorCode." }
    if (-not $ExpectedAllowed -and ($opened -or $errorCode -ne 5)) {
        throw "Expected access denied for '$Path'; opened=$opened; Win32=$errorCode."
    }
    return $opened
}

function Quote-Phase2B3Argument {
    param([string]$Value)
    return '"' + $Value.Replace('"','\"') + '"'
}

function Start-Phase2B3CrashWorker {
    param([string]$MarkerPath,[string]$ExecutionSid)
    $workerPath = Join-Path $PSScriptRoot 'DevAgentBroker\WorkspaceCrashChild.ps1'
    $hostPath = Join-Path $PSHOME 'powershell.exe'
    $arguments = @(
        '-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass',
        '-File',$workerPath,
        '-WorkspaceRoot',$workspaceRoot,
        '-JournalRoot',$journalRoot,
        '-ExecutionSid',$ExecutionSid,
        '-SupervisorSid',$supervisorSid,
        '-CrashAfterPhase','AfterAclApplied',
        '-MarkerPath',$MarkerPath,
        '-ExternalRoot',$outsideRoot
    )
    $line = ($arguments | ForEach-Object { Quote-Phase2B3Argument ([string]$_) }) -join ' '
    $stdout = $MarkerPath + '.stdout'
    $stderr = $MarkerPath + '.stderr'
    $worker = Start-Process -FilePath $hostPath -ArgumentList $line -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    while ([DateTime]::UtcNow -lt $deadline -and -not (Test-Path -LiteralPath $MarkerPath -PathType Leaf)) {
        if ($worker.HasExited) { break }
        Start-Sleep -Milliseconds 100
    }
    if (-not (Test-Path -LiteralPath $MarkerPath -PathType Leaf)) {
        $out = if (Test-Path -LiteralPath $stdout) { Get-Content -LiteralPath $stdout -Raw } else { '' }
        $err = if (Test-Path -LiteralPath $stderr) { Get-Content -LiteralPath $stderr -Raw } else { '' }
        if (-not $worker.HasExited) { Stop-Process -Id $worker.Id -Force -ErrorAction SilentlyContinue }
        throw "Crash worker did not reach AfterAclApplied. Exit=$($worker.ExitCode); stdout=[$out]; stderr=[$err]"
    }
    Stop-Process -Id $worker.Id -Force
    if (-not $worker.WaitForExit(10000)) { throw 'Crash worker did not terminate after forced death.' }
}

try {
    [void][IO.Directory]::CreateDirectory($base)
    foreach ($path in @($workspaceRoot,$journalRoot,$sourceRoot,$brokerRoot,$outsideRoot)) {
        [void][IO.Directory]::CreateDirectory($path)
        Assert-SharnouNoReparseAncestors -Path $path
    }
    foreach ($path in @($workspaceRoot,$journalRoot,$sourceRoot,$brokerRoot,$outsideRoot)) {
        Set-SharnouProtectedDirectoryAcl -Path $path -AllowedSids @($supervisorSid,$systemSid)
    }

    $profileA = New-Phase2B3Profile 'A'
    $profileB = New-Phase2B3Profile 'B'
    Assert-Phase2B3 ($profileA.SidText -cne $profileB.SidText) 'two independently created AppContainer profiles have distinct OS-issued package SIDs'

    $rootSddl = Get-SharnouDirectorySddl -Path $workspaceRoot
    $journalRootSddl = Get-SharnouDirectorySddl -Path $journalRoot
    $brokerSentinel = Join-Path $brokerRoot 'DevAgentBroker.exe.sentinel'
    $sourceSentinel = Join-Path $sourceRoot 'SharnouCompiler.ps1.sentinel'
    $parentSentinel = Join-Path $workspaceRoot 'shared-parent.sentinel'
    [IO.File]::WriteAllText($brokerSentinel,'broker sentinel',[Text.Encoding]::ASCII)
    [IO.File]::WriteAllText($sourceSentinel,'compiler source sentinel',[Text.Encoding]::ASCII)
    [IO.File]::WriteAllText($parentSentinel,'shared parent sentinel',[Text.Encoding]::ASCII)

    $txA = New-SharnouExecutionWorkspace -WorkspaceRoot $workspaceRoot -JournalRoot $journalRoot -ExecutionSid $profileA.SidText -SupervisorSid $supervisorSid
    $transactions.Add($txA)
    $txB = New-SharnouExecutionWorkspace -WorkspaceRoot $workspaceRoot -JournalRoot $journalRoot -ExecutionSid $profileB.SidText -SupervisorSid $supervisorSid
    $transactions.Add($txB)
    Assert-Phase2B3 ((Get-SharnouDirectorySddl -Path $workspaceRoot) -ceq $rootSddl) 'per-execution DACL application never changes the shared workspace-parent descriptor'
    Assert-Phase2B3 ((Get-SharnouDirectorySddl -Path $journalRoot) -ceq $journalRootSddl) 'per-execution DACL application never weakens the separate journal-root descriptor'

    $ownFile = Join-Path $txA.WorkspacePath 'owned.txt'
    $otherFile = Join-Path $txB.WorkspacePath 'foreign-execution.txt'
    [IO.File]::WriteAllText($ownFile,'owned by execution A',[Text.Encoding]::ASCII)
    [IO.File]::WriteAllText($otherFile,'owned by execution B',[Text.Encoding]::ASCII)
    $rules = [IO.Directory]::GetAccessControl($txA.WorkspacePath,$script:SharnouSecuritySections).GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])
    $packageRules = @($rules | Where-Object { $_.IdentityReference.Value -ceq $profileA.SidText })
    $scratchRights = Get-SharnouExecutionWorkspaceRights
    Assert-Phase2B3 ($packageRules.Count -eq 1 -and $packageRules[0].FileSystemRights -eq $scratchRights) 'AppContainer package ACE exactly matches the reviewed scratch-only rights mask 0x0013019F'
    $forbiddenMask = [int](0x00000020 -bor 0x00000040 -bor 0x00040000 -bor 0x00080000)
    Assert-Phase2B3 (([int]$packageRules[0].FileSystemRights -band $forbiddenMask) -eq 0) 'package ACE excludes execute, delete-child, WRITE_DAC and WRITE_OWNER rights'
    Assert-Phase2B3 (([IO.Directory]::GetAccessControl($txA.WorkspacePath,$script:SharnouSecuritySections)).AreAccessRulesProtected) 'AppContainer workspace DACL is protected from parent inheritance'
    Assert-Phase2B3 ((@($rules | Where-Object { $_.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow -or $_.IsInherited }).Count) -eq 0) 'workspace has no inherited ACEs or unexpected deny entries'

    $child = New-Phase2B3AppContainerChild -Profile $profileA
    Assert-Phase2B3 ($child.ProfileSid -ceq $profileA.SidText) 'suspended child token is bound to the exact OS-created package SID'
    $script:childCreated = $true

    [void](Invoke-Phase2B3Open -Token $child.ImpersonationToken -Path $ownFile -DesiredAccess ([UInt32]0x80000000) -Disposition ([UInt32]3) -ExpectedAllowed $true)
    Assert-Phase2B3 $true 'AppContainer token can read a file in its own execution workspace'
    [void](Invoke-Phase2B3Open -Token $child.ImpersonationToken -Path $ownFile -DesiredAccess ([UInt32]0x40000000) -Disposition ([UInt32]3) -ExpectedAllowed $true)
    Assert-Phase2B3 $true 'AppContainer token can write an existing file in its own execution workspace'
    $createdInside = Join-Path $txA.WorkspacePath 'created-by-package.txt'
    [void](Invoke-Phase2B3Open -Token $child.ImpersonationToken -Path $createdInside -DesiredAccess ([UInt32]0x40000000) -Disposition ([UInt32]1) -ExpectedAllowed $true)
    Assert-Phase2B3 (Test-Path -LiteralPath $createdInside -PathType Leaf) 'AppContainer token can create a new file in its own execution workspace'

    $deniedTargets = @(
        @{Path=$txA.JournalPath;Name='private execution journal'},
        @{Path=$parentSentinel;Name='shared workspace parent'},
        @{Path=$otherFile;Name='another execution workspace'},
        @{Path=$sourceSentinel;Name='compiler source sentinel'},
        @{Path=$brokerSentinel;Name='broker image sentinel'}
    )
    foreach ($target in $deniedTargets) {
        [void](Invoke-Phase2B3Open -Token $child.ImpersonationToken -Path $target.Path -DesiredAccess ([UInt32]0x80000000) -Disposition ([UInt32]3) -ExpectedAllowed $false)
        Assert-Phase2B3 $true ("AppContainer token is denied access to " + $target.Name)
    }

    [void](Invoke-Phase2B3Open -Token $child.ImpersonationToken -Path $ownFile -DesiredAccess ([UInt32]0x20) -Disposition ([UInt32]3) -ExpectedAllowed $false)
    Assert-Phase2B3 $true 'AppContainer token cannot request FILE_EXECUTE on its own scratch file'
    [void](Invoke-Phase2B3Open -Token $child.ImpersonationToken -Path $ownFile -DesiredAccess ([UInt32]0x40000) -Disposition ([UInt32]3) -ExpectedAllowed $false)
    Assert-Phase2B3 $true 'AppContainer token cannot change the DACL of its own scratch file'
    [void](Invoke-Phase2B3Open -Token $child.ImpersonationToken -Path $ownFile -DesiredAccess ([UInt32]0x80000) -Disposition ([UInt32]3) -ExpectedAllowed $false)
    Assert-Phase2B3 $true 'AppContainer token cannot take ownership of its own scratch file'

    # The test AppContainer process is still suspended. Terminate and reap it
    # before any rollback, matching the required production lifecycle ordering.
    $terminated = [bool](Invoke-Phase2B3Api 'TerminateProcess' @($child.Process,[UInt32]0x0000DEAD))
    if (-not $terminated) { throw ("TerminateProcess failed: {0}." -f [Runtime.InteropServices.Marshal]::GetLastWin32Error()) }
    $wait = [UInt32](Invoke-Phase2B3Api 'WaitForSingleObject' @($child.Process,[UInt32]5000))
    if ($wait -ne 0) { throw ("AppContainer child did not terminate: wait=0x{0:X8}." -f $wait) }
    $script:childTerminated = $true
    Assert-Phase2B3 $true 'AppContainer process is terminated and waited before crash-recovery ACL restoration'

    $originalSddlA = $txA.OriginalSddl
    $originalSddlB = $txB.OriginalSddl
    $null = Complete-SharnouExecutionWorkspace -Transaction $txA -KeepRestoredWorkspace
    $null = Complete-SharnouExecutionWorkspace -Transaction $txB -KeepRestoredWorkspace
    Assert-Phase2B3 ((Get-SharnouDirectorySddl -Path $txA.WorkspacePath) -ceq $originalSddlA) 'normal rollback restores exact original owner/group/DACL for execution A'
    Assert-Phase2B3 ((Get-SharnouDirectorySddl -Path $txB.WorkspacePath) -ceq $originalSddlB) 'normal rollback restores exact original owner/group/DACL for execution B'
    $normalCleanup = Recover-SharnouExecutionWorkspaces -WorkspaceRoot $workspaceRoot -JournalRoot $journalRoot -SupervisorSid $supervisorSid
    Assert-Phase2B3 ($normalCleanup.Failed -eq 0 -and $normalCleanup.Deleted -eq 2) 'normal restored workspaces are removed only after original descriptors are verified'

    # Use the genuine package SID again to force process death after ACL application.
    $crashMarker = Join-Path $base 'crash-after-package-acl.marker'
    Start-Phase2B3CrashWorker -MarkerPath $crashMarker -ExecutionSid $profileA.SidText
    $crashJournals = @(Get-ChildItem -LiteralPath $journalRoot -Filter '*.json' -File)
    if ($crashJournals.Count -ne 1) { throw 'Expected one crash-recovery journal for the package SID fixture.' }
    $crashRecord = Get-Content -LiteralPath $crashJournals[0].FullName -Raw | ConvertFrom-Json
    Assert-Phase2B3 ($crashRecord.state -eq 'ACL_PENDING' -and $crashRecord.executionSid -ceq $profileA.SidText -and -not [string]::IsNullOrWhiteSpace($crashRecord.originalSddl)) 'crash journal durably records the genuine package SID and original descriptor before DACL application'
    $crashOriginalSddl = [string]$crashRecord.originalSddl
    $crashWorkspace = [string]$crashRecord.workspacePath

    $recovery = Recover-SharnouExecutionWorkspaces -WorkspaceRoot $workspaceRoot -JournalRoot $journalRoot -SupervisorSid $supervisorSid -KeepRestoredWorkspaces
    Assert-Phase2B3 ($recovery.Recovered -eq 1 -and $recovery.Failed -eq 0 -and (Test-Path -LiteralPath $crashWorkspace -PathType Container)) 'crash recovery restores the package-bound workspace without deleting it prematurely'
    Assert-Phase2B3 ((Get-SharnouDirectorySddl -Path $crashWorkspace) -ceq $crashOriginalSddl) 'crash recovery restores the exact pre-mutation owner/group/DACL descriptor'
    $replay = Recover-SharnouExecutionWorkspaces -WorkspaceRoot $workspaceRoot -JournalRoot $journalRoot -SupervisorSid $supervisorSid
    Assert-Phase2B3 ($replay.Recovered -eq 1 -and $replay.Failed -eq 0 -and -not (Test-Path -LiteralPath $crashWorkspace)) 'second recovery replay safely deletes the already-restored workspace and finalizes its journal'

    $rootAfter = Get-SharnouDirectorySddl -Path $workspaceRoot
    $journalRootAfter = Get-SharnouDirectorySddl -Path $journalRoot
    Assert-Phase2B3 ($rootAfter -ceq $rootSddl) 'all success and crash paths preserve the shared workspace-root descriptor'
    Assert-Phase2B3 ($journalRootAfter -ceq $journalRootSddl) 'all success and crash paths preserve the private journal-root descriptor'
    $residue = @(
        (Get-ChildItem -LiteralPath $journalRoot -Force -File).Count,
        (Get-ChildItem -LiteralPath $workspaceRoot -Force).Count
    )
    Assert-Phase2B3 (($residue -join ',') -ceq '0,1') 'journal root is empty and only the fixed shared-parent sentinel remains after recovery'
}
catch {
    $failure = $_.Exception.Message
}
finally {
    if ($threadImpersonating) {
        try { [void](Invoke-Phase2B3Api 'RevertToSelf' @()) } catch { $cleanupSafe = $false }
        $threadImpersonating = $false
    }
    if ($childCreated -and -not $childTerminated -and $childProcessHandle -ne [IntPtr]::Zero) {
        try {
            [void](Invoke-Phase2B3Api 'TerminateProcess' @($childProcessHandle,[UInt32]0x0000DEAD))
            $wait = [UInt32](Invoke-Phase2B3Api 'WaitForSingleObject' @($childProcessHandle,[UInt32]5000))
            if ($wait -eq 0) { $childTerminated = $true } else { $cleanupSafe = $false }
        } catch { $cleanupSafe = $false }
    }

    # Do not delete the profile while any child process may still reference it.
    foreach ($handle in $handles) {
        if ($handle -ne [IntPtr]::Zero) {
            try { [void](Invoke-Phase2B3Api 'CloseHandle' @($handle)) } catch { $cleanupSafe = $false }
        }
    }

    if ($cleanupSafe -and (Test-Path -LiteralPath $journalRoot -PathType Container)) {
        try {
            foreach ($transaction in $transactions) {
                if ($null -ne $transaction.LeaseStream -and -not $transaction.LeaseStream.SafeFileHandle.IsClosed) {
                    [void](Complete-SharnouExecutionWorkspace -Transaction $transaction)
                }
            }
            $pending = Recover-SharnouExecutionWorkspaces -WorkspaceRoot $workspaceRoot -JournalRoot $journalRoot -SupervisorSid $supervisorSid
            if ($pending.Failed -ne 0) { $cleanupSafe = $false }
        } catch { $cleanupSafe = $false }
    }

    if ($cleanupSafe) {
        foreach ($profile in $profiles) {
            if ($profile.Owned) {
                try {
                    $deleteHr = [Int32](Invoke-Phase2B3Api 'DeleteAppContainerProfile' @($profile.NamePointer))
                    if ($deleteHr -ne 0) { $cleanupSafe = $false }
                    else { $profile.Owned = $false }
                } catch { $cleanupSafe = $false }
            }
            if ($profile.Sid -ne [IntPtr]::Zero) {
                try { [void](Invoke-Phase2B3Api 'FreeSid' @($profile.Sid)) } catch { $cleanupSafe = $false }
            }
        }
    }
    else {
        Write-Warning 'Cleanup could not prove process termination and exact workspace recovery. AppContainer profile(s) and test workspace are intentionally retained for manual recovery.'
    }

    for ($i = $allocations.Count - 1; $i -ge 0; $i--) {
        try { [Runtime.InteropServices.Marshal]::FreeHGlobal($allocations[$i]) } catch { $cleanupSafe = $false }
    }

    if ($cleanupSafe -and (Test-Path -LiteralPath $base)) {
        Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($null -ne $failure) {
    Write-Host ("Phase 2B.3 AppContainer workspace ACL result: FAIL - " + $failure) -ForegroundColor Red
    throw $failure
}
if (-not $cleanupSafe) { throw 'Phase 2B.3 cleanup was not fully verified; profile/workspace artifacts were retained.' }
Write-Host ("Phase 2B.3 AppContainer workspace ACL result: PASS ({0} assertions)" -f $assertions) -ForegroundColor Green
Write-Host ("Windows: {0}; PowerShell: {1}; architecture: x64" -f [Environment]::OSVersion.Version.ToString(),$PSVersionTable.PSVersion.ToString())
Write-Host ("Source SHA-256: {0}" -f (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash)
Write-Host ("Workspace transaction SHA-256: {0}" -f (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'DevAgentBroker\WorkspaceTransaction.ps1') -Algorithm SHA256).Hash)
Write-Host ("Interop helper SHA-256: {0}" -f (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'DevAgentBroker\NativeInterop.ps1') -Algorithm SHA256).Hash)
Write-Host ("Manifest SHA-256: {0}" -f (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash)
