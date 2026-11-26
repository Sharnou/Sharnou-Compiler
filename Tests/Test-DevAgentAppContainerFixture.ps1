[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'DevAgentBroker\NativeInterop.ps1')

function Assert-AppContainerProbe {
    param([bool] $Condition,[string] $Message)
    if (-not $Condition) { throw $Message }
}
function Add-AppContainerPass {
    param([string] $Message)
    $script:AppContainerPassCount++
    Write-Host ("PASS: " + $Message) -ForegroundColor Green
}
function Get-HResultBits {
    param([Int32] $Value)
    return [BitConverter]::ToUInt32([BitConverter]::GetBytes($Value),0)
}
function Get-AppContainerTokenBuffer {
    param(
        [type] $ApiType,
        [IntPtr] $Token,
        [Int32] $InformationClass,
        [System.Collections.Generic.List[IntPtr]] $Allocations
    )
    $returnLength = New-SharnouTrackedBuffer -ByteCount 4 -Allocations $Allocations
    $probeResult = [bool](Invoke-SharnouNativeApi -ApiType $ApiType -Name 'GetTokenInformation' -Arguments @(
        $Token,[Int32]$InformationClass,[IntPtr]::Zero,[UInt32]0,$returnLength
    ))
    $probeError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    $required = [Runtime.InteropServices.Marshal]::ReadInt32($returnLength)
    if ($probeResult -or $probeError -ne 122 -or $required -lt 4 -or $required -gt 65536) {
        throw ("GetTokenInformation size query failed closed for class {0}: result={1}; error={2}; required={3}." -f $InformationClass,$probeResult,$probeError,$required)
    }
    $buffer = New-SharnouTrackedBuffer -ByteCount $required -Allocations $Allocations
    $queryResult = [bool](Invoke-SharnouNativeApi -ApiType $ApiType -Name 'GetTokenInformation' -Arguments @(
        $Token,[Int32]$InformationClass,$buffer,[UInt32]$required,$returnLength
    ))
    if (-not $queryResult) {
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw ("GetTokenInformation failed for class {0}: Win32 error {1}." -f $InformationClass,$errorCode)
    }
    $actualLength = [Runtime.InteropServices.Marshal]::ReadInt32($returnLength)
    if ($actualLength -lt 4 -or $actualLength -gt $required) {
        throw ("GetTokenInformation returned invalid length for class {0}: allocated={1}; returned={2}." -f $InformationClass,$required,$actualLength)
    }
    return [pscustomobject]@{ Buffer=$buffer; Length=$actualLength }
}

$script:AppContainerPassCount = 0
$allocations = New-Object 'System.Collections.Generic.List[IntPtr]'
$handles = New-Object 'System.Collections.Generic.List[IntPtr]'
$profileSid = [IntPtr]::Zero
$processHandle = [IntPtr]::Zero
$threadHandle = [IntPtr]::Zero
$childToken = [IntPtr]::Zero
$parentToken = [IntPtr]::Zero
$attributeList = [IntPtr]::Zero
$attributeListInitialized = $false
$ownsProfile = $false
$childTerminated = $false
$safeToDeleteProfile = $true
$apiType = $null
$failure = $null
$profileName = 'Sharnou.DevAgentProbe.' + [Guid]::NewGuid().ToString('N')

try {
    if (-not [Environment]::Is64BitOperatingSystem -or -not [Environment]::Is64BitProcess) {
        throw 'The AppContainer fixture requires 64-bit Windows PowerShell on a 64-bit OS.'
    }
    if ($profileName.Length -gt 64 -or $profileName -notmatch '^[-_. A-Za-z0-9]+$') {
        throw 'Generated AppContainer profile name violates the documented USERENV naming constraints.'
    }

    $repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $manifestPath = Join-Path $PSScriptRoot 'DevAgentBroker\native-abi-manifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $module = New-SharnouNativeInteropModule -Name 'Sharnou.DevAgent.AppContainerFixture'
    $types = New-SharnouRuntimeStructTypes -Module $module -StructureManifest @($manifest.structureLayouts)

    $apiManifest = @($manifest.testFixtureApis)
    if ($apiManifest.Count -ne 18) { throw 'Test fixture API manifest must contain exactly 18 reviewed native entrypoints.' }
    $apiType = New-SharnouNativeApiType -Module $module -ApiManifest $apiManifest
    Add-AppContainerPass '18 reviewed USERENV, KERNEL32 and ADVAPI32 entrypoints were bound in-memory without Add-Type or a compiler.'

    $profileNamePointer = New-SharnouTrackedUnicodeString -Value $profileName -Allocations $allocations
    $displayNamePointer = New-SharnouTrackedUnicodeString -Value 'Sharnou DevAgent Native AppContainer Probe' -Allocations $allocations
    $descriptionPointer = New-SharnouTrackedUnicodeString -Value 'Test-only profile; fixed suspended child; no model-provided command, path or arguments.' -Allocations $allocations
    $sidOutput = New-SharnouTrackedBuffer -ByteCount 8 -Allocations $allocations

    $createHr = [Int32](Invoke-SharnouNativeApi -ApiType $apiType -Name 'CreateAppContainerProfile' -Arguments @(
        $profileNamePointer,$displayNamePointer,$descriptionPointer,[IntPtr]::Zero,[UInt32]0,$sidOutput
    ))
    if ((Get-HResultBits $createHr) -ne [UInt32]0) {
        throw ("CreateAppContainerProfile failed: HRESULT=0x{0:X8}; profile ownership was not acquired." -f (Get-HResultBits $createHr))
    }
    $ownsProfile = $true
    $profileSid = [Runtime.InteropServices.Marshal]::ReadIntPtr($sidOutput)
    if ($profileSid -eq [IntPtr]::Zero) { throw 'CreateAppContainerProfile returned S_OK with a NULL profile SID.' }
    $sidValid = [bool](Invoke-SharnouNativeApi -ApiType $apiType -Name 'IsValidSid' -Arguments @($profileSid))
    if (-not $sidValid) { throw 'CreateAppContainerProfile returned an invalid SID.' }
    $profileSidText = ([System.Security.Principal.SecurityIdentifier]::new($profileSid)).Value
    if ($profileSidText -notmatch '^S-1-15-2-(\d+-)*\d+$') { throw "The returned package SID is outside the AppContainer SID namespace: $profileSidText" }
    Add-AppContainerPass ("CreateAppContainerProfile returned a valid OS-owned SID: " + $profileSidText)

    # The second create must return HRESULT_FROM_WIN32(ERROR_ALREADY_EXISTS).
    # It must not be treated as profile ownership and must not be deleted.
    $duplicateSidOutput = New-SharnouTrackedBuffer -ByteCount 8 -Allocations $allocations
    $duplicateHr = [Int32](Invoke-SharnouNativeApi -ApiType $apiType -Name 'CreateAppContainerProfile' -Arguments @(
        $profileNamePointer,$displayNamePointer,$descriptionPointer,[IntPtr]::Zero,[UInt32]0,$duplicateSidOutput
    ))
    if ((Get-HResultBits $duplicateHr) -ne [UInt32]0x800700B7) {
        throw ("Duplicate profile creation did not fail with HRESULT_FROM_WIN32(ERROR_ALREADY_EXISTS): 0x{0:X8}." -f (Get-HResultBits $duplicateHr))
    }
    Add-AppContainerPass 'Profile collision is rejected with ERROR_ALREADY_EXISTS; the duplicate path does not claim ownership.'

    # Probe and allocate the native process attribute list.
    $attributeSizePointer = New-SharnouTrackedBuffer -ByteCount 8 -Allocations $allocations
    [Runtime.InteropServices.Marshal]::WriteInt64($attributeSizePointer,0)
    $sizeProbe = [bool](Invoke-SharnouNativeApi -ApiType $apiType -Name 'InitializeProcThreadAttributeList' -Arguments @(
        [IntPtr]::Zero,[UInt32]1,[UInt32]0,$attributeSizePointer
    ))
    $sizeProbeError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    $attributeBytes = [Runtime.InteropServices.Marshal]::ReadInt64($attributeSizePointer)
    if ($sizeProbe -or $sizeProbeError -ne 122 -or $attributeBytes -le 0 -or $attributeBytes -gt 65536) {
        throw ("InitializeProcThreadAttributeList size probe was unexpected: result={0}; error={1}; bytes={2}." -f $sizeProbe,$sizeProbeError,$attributeBytes)
    }
    $attributeList = New-SharnouTrackedBuffer -ByteCount ([int]$attributeBytes) -Allocations $allocations
    $initialized = [bool](Invoke-SharnouNativeApi -ApiType $apiType -Name 'InitializeProcThreadAttributeList' -Arguments @(
        $attributeList,[UInt32]1,[UInt32]0,$attributeSizePointer
    ))
    if (-not $initialized) {
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw ("InitializeProcThreadAttributeList failed: Win32 error {0}." -f $errorCode)
    }
    $attributeListInitialized = $true
    Add-AppContainerPass ("Attribute-list sizing and initialization succeeded; required bytes=" + $attributeBytes)

    # SECURITY_CAPABILITIES: real profile SID, no requested capabilities.
    $capabilitiesType = $types['SECURITY_CAPABILITIES']
    $capabilitiesSize = [Runtime.InteropServices.Marshal]::SizeOf($capabilitiesType)
    if ($capabilitiesSize -ne 24) { throw "SECURITY_CAPABILITIES size mismatch: $capabilitiesSize." }
    $securityCapabilities = New-SharnouTrackedBuffer -ByteCount $capabilitiesSize -Allocations $allocations
    [Runtime.InteropServices.Marshal]::WriteIntPtr($securityCapabilities,0,$profileSid)
    [Runtime.InteropServices.Marshal]::WriteIntPtr($securityCapabilities,8,[IntPtr]::Zero)
    [Runtime.InteropServices.Marshal]::WriteInt32($securityCapabilities,16,0)
    [Runtime.InteropServices.Marshal]::WriteInt32($securityCapabilities,20,0)
    $attributeKey = [UIntPtr]::new([UInt64]0x00020009)
    $attributeUpdated = [bool](Invoke-SharnouNativeApi -ApiType $apiType -Name 'UpdateProcThreadAttribute' -Arguments @(
        $attributeList,[UInt32]0,$attributeKey,$securityCapabilities,[UIntPtr]::new([UInt64]$capabilitiesSize),[IntPtr]::Zero,[IntPtr]::Zero
    ))
    if (-not $attributeUpdated) {
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw ("UpdateProcThreadAttribute(SECURITY_CAPABILITIES) failed: Win32 error {0}." -f $errorCode)
    }
    Add-AppContainerPass 'PROC_THREAD_ATTRIBUTE_SECURITY_CAPABILITIES accepted the validated x64 structure with zero requested capabilities.'

    # A fixed absolute System32 image is created suspended. The fixture never resumes it.
    $systemDirectory = [Environment]::SystemDirectory
    $childImage = [IO.Path]::GetFullPath((Join-Path $systemDirectory 'whoami.exe'))
    if (-not (Test-Path -LiteralPath $childImage -PathType Leaf)) { throw "Fixed System32 test image is missing: $childImage" }
    if (-not $childImage.StartsWith(($systemDirectory.TrimEnd('\') + '\'),[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Fixed test image escaped the System32 directory.'
    }
    $childImageHash = (Get-FileHash -LiteralPath $childImage -Algorithm SHA256).Hash
    $applicationPointer = New-SharnouTrackedUnicodeString -Value $childImage -Allocations $allocations
    $commandLinePointer = New-SharnouTrackedUnicodeString -Value ('"' + $childImage + '"') -Allocations $allocations
    $currentDirectoryPointer = New-SharnouTrackedUnicodeString -Value $systemDirectory -Allocations $allocations
    $environmentText = 'SystemRoot=' + $env:SystemRoot + [char]0 + 'WINDIR=' + $env:SystemRoot + [char]0
    $environmentPointer = New-SharnouTrackedUnicodeString -Value $environmentText -Allocations $allocations

    $startupSize = [Runtime.InteropServices.Marshal]::SizeOf($types['STARTUPINFOEXW'])
    $processInformationSize = [Runtime.InteropServices.Marshal]::SizeOf($types['PROCESS_INFORMATION'])
    if ($startupSize -ne 112 -or $processInformationSize -ne 24) {
        throw ("Process startup ABI mismatch: STARTUPINFOEXW={0}; PROCESS_INFORMATION={1}." -f $startupSize,$processInformationSize)
    }
    $startupInfoEx = New-SharnouTrackedBuffer -ByteCount $startupSize -Allocations $allocations
    [Runtime.InteropServices.Marshal]::WriteInt32($startupInfoEx,0,$startupSize)
    [Runtime.InteropServices.Marshal]::WriteIntPtr($startupInfoEx,104,$attributeList)
    $processInformation = New-SharnouTrackedBuffer -ByteCount $processInformationSize -Allocations $allocations

    $creationFlags = [UInt32](0x00080000 -bor 0x00000004 -bor 0x00000400)
    $created = [bool](Invoke-SharnouNativeApi -ApiType $apiType -Name 'CreateProcessW' -Arguments @(
        $applicationPointer,$commandLinePointer,[IntPtr]::Zero,[IntPtr]::Zero,[Boolean]$false,
        $creationFlags,$environmentPointer,$currentDirectoryPointer,$startupInfoEx,$processInformation
    ))
    if (-not $created) {
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw ("CreateProcessW AppContainer fixture failed: Win32 error {0}; image={1}." -f $errorCode,$childImage)
    }
    $processHandle = [Runtime.InteropServices.Marshal]::ReadIntPtr($processInformation,0)
    $threadHandle = [Runtime.InteropServices.Marshal]::ReadIntPtr($processInformation,8)
    $processId = [Runtime.InteropServices.Marshal]::ReadInt32($processInformation,16)
    if ($processHandle -ne [IntPtr]::Zero) { $handles.Add($processHandle) }
    if ($threadHandle -ne [IntPtr]::Zero) { $handles.Add($threadHandle) }
    if ($processHandle -eq [IntPtr]::Zero -or $threadHandle -eq [IntPtr]::Zero -or $processId -le 0) {
        throw 'CreateProcessW returned success with invalid PROCESS_INFORMATION fields.'
    }
    Add-AppContainerPass ("CreateProcessW created the fixed System32 child suspended; PID=" + $processId)

    # The attribute list is no longer referenced by the process-creation call.
    Invoke-SharnouNativeApi -ApiType $apiType -Name 'DeleteProcThreadAttributeList' -Arguments @($attributeList) | Out-Null
    $attributeListInitialized = $false

    $childTokenOutput = New-SharnouTrackedBuffer -ByteCount 8 -Allocations $allocations
    $openedChildToken = [bool](Invoke-SharnouNativeApi -ApiType $apiType -Name 'OpenProcessToken' -Arguments @(
        $processHandle,[UInt32]0x0008,$childTokenOutput
    ))
    if (-not $openedChildToken) {
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw ("OpenProcessToken(child) failed: Win32 error {0}." -f $errorCode)
    }
    $childToken = [Runtime.InteropServices.Marshal]::ReadIntPtr($childTokenOutput)
    if ($childToken -eq [IntPtr]::Zero) { throw 'OpenProcessToken(child) returned success with a NULL token.' }
    $handles.Add($childToken)

    $isAppContainerInfo = Get-AppContainerTokenBuffer -ApiType $apiType -Token $childToken -InformationClass 29 -Allocations $allocations
    $isAppContainerValue = [Runtime.InteropServices.Marshal]::ReadInt32($isAppContainerInfo.Buffer)
    if ($isAppContainerValue -ne 1) { throw "Child TokenIsAppContainer expected 1, actual $isAppContainerValue." }

    $childSidInfo = Get-AppContainerTokenBuffer -ApiType $apiType -Token $childToken -InformationClass 31 -Allocations $allocations
    $childSid = [Runtime.InteropServices.Marshal]::ReadIntPtr($childSidInfo.Buffer)
    if ($childSid -eq [IntPtr]::Zero) { throw 'Child TokenAppContainerSid returned NULL.' }
    if (-not [bool](Invoke-SharnouNativeApi -ApiType $apiType -Name 'IsValidSid' -Arguments @($childSid))) {
        throw 'Child TokenAppContainerSid is not a valid SID.'
    }
    if (-not [bool](Invoke-SharnouNativeApi -ApiType $apiType -Name 'EqualSid' -Arguments @($profileSid,$childSid))) {
        throw 'Child TokenAppContainerSid does not exactly match this execution-created profile SID.'
    }
    Add-AppContainerPass 'Actual child token reports TokenIsAppContainer=1 and an equal, valid profile SID.'

    $integrityInfo = Get-AppContainerTokenBuffer -ApiType $apiType -Token $childToken -InformationClass 25 -Allocations $allocations
    $integritySid = [Runtime.InteropServices.Marshal]::ReadIntPtr($integrityInfo.Buffer,0)
    if ($integritySid -eq [IntPtr]::Zero) { throw 'TokenIntegrityLevel returned a NULL mandatory-label SID.' }
    $subAuthorityCountPointer = [IntPtr](Invoke-SharnouNativeApi -ApiType $apiType -Name 'GetSidSubAuthorityCount' -Arguments @($integritySid))
    if ($subAuthorityCountPointer -eq [IntPtr]::Zero) { throw 'GetSidSubAuthorityCount returned NULL for the token integrity SID.' }
    $subAuthorityCount = [Runtime.InteropServices.Marshal]::ReadByte($subAuthorityCountPointer)
    if ($subAuthorityCount -lt 1 -or $subAuthorityCount -gt 15) { throw "Invalid integrity SID subauthority count: $subAuthorityCount." }
    $ridPointer = [IntPtr](Invoke-SharnouNativeApi -ApiType $apiType -Name 'GetSidSubAuthority' -Arguments @($integritySid,[UInt32]($subAuthorityCount - 1)))
    if ($ridPointer -eq [IntPtr]::Zero) { throw 'GetSidSubAuthority returned NULL for the integrity RID.' }
    $integrityRid = [Runtime.InteropServices.Marshal]::ReadInt32($ridPointer)
    if ($integrityRid -lt 0 -or $integrityRid -gt 0x1000) {
        throw ("AppContainer integrity level exceeds Low: RID=0x{0:X8}." -f [UInt32]$integrityRid)
    }
    Add-AppContainerPass ("Child token integrity RID is no higher than Low: 0x" + $integrityRid.ToString('X'))

    $capabilityInfo = Get-AppContainerTokenBuffer -ApiType $apiType -Token $childToken -InformationClass 30 -Allocations $allocations
    $capabilityCount = [Runtime.InteropServices.Marshal]::ReadInt32($capabilityInfo.Buffer)
    if ($capabilityCount -ne 0) { throw "Expected zero app-container capabilities; actual TokenCapabilities count=$capabilityCount." }
    Add-AppContainerPass 'Child TokenCapabilities contains zero capability SIDs.'

    # Negative control: a normal CI PowerShell process is not an AppContainer.
    $currentProcess = [IntPtr](Invoke-SharnouNativeApi -ApiType $apiType -Name 'GetCurrentProcess' -Arguments @())
    $parentTokenOutput = New-SharnouTrackedBuffer -ByteCount 8 -Allocations $allocations
    $openedParentToken = [bool](Invoke-SharnouNativeApi -ApiType $apiType -Name 'OpenProcessToken' -Arguments @(
        $currentProcess,[UInt32]0x0008,$parentTokenOutput
    ))
    if (-not $openedParentToken) {
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw ("OpenProcessToken(parent) failed: Win32 error {0}." -f $errorCode)
    }
    $parentToken = [Runtime.InteropServices.Marshal]::ReadIntPtr($parentTokenOutput)
    if ($parentToken -eq [IntPtr]::Zero) { throw 'OpenProcessToken(parent) returned success with a NULL token.' }
    $handles.Add($parentToken)
    $parentContainerInfo = Get-AppContainerTokenBuffer -ApiType $apiType -Token $parentToken -InformationClass 29 -Allocations $allocations
    if ([Runtime.InteropServices.Marshal]::ReadInt32($parentContainerInfo.Buffer) -ne 0) {
        throw 'Negative control failed: current PowerShell parent unexpectedly reports an AppContainer token.'
    }
    $parentSidInfo = Get-AppContainerTokenBuffer -ApiType $apiType -Token $parentToken -InformationClass 31 -Allocations $allocations
    if ([Runtime.InteropServices.Marshal]::ReadIntPtr($parentSidInfo.Buffer) -ne [IntPtr]::Zero) {
        throw 'Negative control failed: non-AppContainer parent unexpectedly has a package SID.'
    }
    Add-AppContainerPass 'Negative control rejects the ordinary parent token and its NULL AppContainer SID.'

    # The child is still suspended: verify STILL_ACTIVE, then terminate it without ResumeThread.
    $exitCodeOutput = New-SharnouTrackedBuffer -ByteCount 4 -Allocations $allocations
    $gotExitCode = [bool](Invoke-SharnouNativeApi -ApiType $apiType -Name 'GetExitCodeProcess' -Arguments @($processHandle,$exitCodeOutput))
    if (-not $gotExitCode) { throw 'GetExitCodeProcess failed before termination.' }
    if ([Runtime.InteropServices.Marshal]::ReadInt32($exitCodeOutput) -ne 259) {
        throw 'The test child did not remain in the expected STILL_ACTIVE state while its primary thread was suspended.'
    }
    $terminated = [bool](Invoke-SharnouNativeApi -ApiType $apiType -Name 'TerminateProcess' -Arguments @($processHandle,[UInt32]0x0000DEAD))
    if (-not $terminated) {
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw ("TerminateProcess(suspended test child) failed: Win32 error {0}." -f $errorCode)
    }
    $waitResult = [UInt32](Invoke-SharnouNativeApi -ApiType $apiType -Name 'WaitForSingleObject' -Arguments @($processHandle,[UInt32]5000))
    if ($waitResult -ne 0) { throw ("WaitForSingleObject returned unexpected value 0x{0:X8}." -f $waitResult) }
    $childTerminated = $true
    Add-AppContainerPass 'Suspended child was terminated and reaped without ever resuming its primary thread.'
    Write-Host ("Fixed child image SHA-256: {0}" -f $childImageHash)
    Write-Host ("AppContainer profile SID: {0}" -f $profileSidText)
} catch {
    $failure = $_.Exception.Message
} finally {
    if ($processHandle -ne [IntPtr]::Zero -and -not $childTerminated) {
        try {
            [void](Invoke-SharnouNativeApi -ApiType $apiType -Name 'TerminateProcess' -Arguments @($processHandle,[UInt32]0x0000DEAD))
            $cleanupWait = [UInt32](Invoke-SharnouNativeApi -ApiType $apiType -Name 'WaitForSingleObject' -Arguments @($processHandle,[UInt32]5000))
            if ($cleanupWait -eq 0) {
                $childTerminated = $true
            } else {
                $safeToDeleteProfile = $false
                if ($null -eq $failure) { $failure = ("Emergency child termination could not be confirmed; wait result=0x{0:X8}. The profile is intentionally retained for recovery." -f $cleanupWait) }
            }
        } catch {
            $safeToDeleteProfile = $false
            if ($null -eq $failure) { $failure = "Emergency child termination failed: $($_.Exception.Message). The profile is intentionally retained for recovery." }
        }
    }
    if ($attributeListInitialized -and $attributeList -ne [IntPtr]::Zero) {
        try { Invoke-SharnouNativeApi -ApiType $apiType -Name 'DeleteProcThreadAttributeList' -Arguments @($attributeList) | Out-Null }
        catch { if ($null -eq $failure) { $failure = "Attribute-list cleanup failed: $($_.Exception.Message)" } }
        $attributeListInitialized = $false
    }
    foreach ($handle in $handles) {
        if ($handle -ne [IntPtr]::Zero) {
            try { [void](Invoke-SharnouNativeApi -ApiType $apiType -Name 'CloseHandle' -Arguments @($handle)) }
            catch { if ($null -eq $failure) { $failure = "Handle cleanup failed: $($_.Exception.Message)" } }
        }
    }
    if ($ownsProfile -and $safeToDeleteProfile) {
        try {
            $deleteHr = [Int32](Invoke-SharnouNativeApi -ApiType $apiType -Name 'DeleteAppContainerProfile' -Arguments @($profileNamePointer))
            if ((Get-HResultBits $deleteHr) -ne [UInt32]0 -and $null -eq $failure) {
                $failure = ("DeleteAppContainerProfile failed: HRESULT=0x{0:X8}." -f (Get-HResultBits $deleteHr))
            }
        } catch {
            if ($null -eq $failure) { $failure = "Profile deletion failed: $($_.Exception.Message)" }
        }
    }
    if ($profileSid -ne [IntPtr]::Zero -and $null -ne $apiType) {
        try { [void](Invoke-SharnouNativeApi -ApiType $apiType -Name 'FreeSid' -Arguments @($profileSid)) }
        catch { if ($null -eq $failure) { $failure = "Profile SID release failed: $($_.Exception.Message)" } }
    }
    for ($i = $allocations.Count - 1; $i -ge 0; $i--) {
        try { [Runtime.InteropServices.Marshal]::FreeHGlobal($allocations[$i]) }
        catch { if ($null -eq $failure) { $failure = "Unmanaged buffer cleanup failed: $($_.Exception.Message)" } }
    }
}

if ($null -ne $failure) {
    Write-Host ("AppContainer fixture: FAIL - " + $failure) -ForegroundColor Red
    throw $failure
}
Write-Host ("Native AppContainer fixture: PASS ({0} assertions)" -f $script:AppContainerPassCount) -ForegroundColor Green
Write-Host ("Windows version: {0}; PowerShell: {1}; architecture: x64" -f [Environment]::OSVersion.Version.ToString(),$PSVersionTable.PSVersion.ToString())
Write-Host ("Source SHA-256: {0}" -f (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash)
Write-Host ("Interop helper SHA-256: {0}" -f (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'DevAgentBroker\NativeInterop.ps1') -Algorithm SHA256).Hash)
Write-Host ("Manifest SHA-256: {0}" -f (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'DevAgentBroker\native-abi-manifest.json') -Algorithm SHA256).Hash)
