[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-BrokerNumericLines {
    param([object[]] $Lines)
    $numeric = New-Object 'System.Collections.Generic.List[string]'
    foreach ($line in $Lines) {
        $parsed = 0
        $value = [string]$line
        if ([int]::TryParse($value, [ref]$parsed)) { $numeric.Add($value) }
    }
    return $numeric.ToArray()
}

function Get-BrokerDaclSddl {
    param([Parameter(Mandatory = $true)][string] $Path)
    $security = Get-Acl -LiteralPath $Path
    return $security.GetSecurityDescriptorSddlForm([Security.AccessControl.AccessControlSections]::Access)
}

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$compilerPath = Join-Path $repoRoot 'Stage0\SharnouCompiler.ps1'
$verifierPath = Join-Path $repoRoot 'Tools\SharnouPEVerify.ps1'
$fixturePath = Join-Path $PSScriptRoot 'DevAgentBroker\DevAgentBroker.sharnou'
$crashHarnessPath = Join-Path $PSScriptRoot 'DevAgentBroker\CrashHarness.sharnou'
$crashProbeScriptPath = Join-Path $PSScriptRoot 'DevAgentBroker\CrashProbe.ps1'
$timeoutScriptPath = Join-Path $PSScriptRoot 'DevAgentBroker\TimeoutProbe.ps1'
$toolManifestPath = Join-Path $PSScriptRoot 'DevAgentBroker\tool-manifest.json'
$successScriptPath = Join-Path $PSScriptRoot 'DevAgentBroker\SuccessProbe.ps1'
$sandboxScriptPath = Join-Path $PSScriptRoot 'DevAgentBroker\SandboxProbe.ps1'
$overflowScriptPath = Join-Path $PSScriptRoot 'DevAgentBroker\OverflowProbe.ps1'
$disabledFixturePath = Join-Path $PSScriptRoot 'DevAgentBroker\Disabled.sharnou'
$disabledOutputPath = Join-Path $repoRoot 'Build\DevAgentBroker\DevAgentBrokerDisabled.exe'
$buildRoot = Join-Path $repoRoot 'Build\DevAgentBroker'
$outputPath = Join-Path $buildRoot 'DevAgentBroker.exe'
$childPidPath = Join-Path $buildRoot 'child.pid'
$sandboxMarkerPath = Join-Path $buildRoot 'sandbox-write-probe.ok'
$deniedMarkerPath = Join-Path $PSScriptRoot 'DevAgentBroker\denied-write-probe.tmp'
$capturedOutputPath = Join-Path $buildRoot 'captured-output.bin'
$journalPath = Join-Path $repoRoot '.sharnou-devagent-acl.journal'
$journalTempPath = Join-Path $repoRoot '.sharnou-devagent-acl.journal.tmp'
$crashChildPidPath = Join-Path $buildRoot 'acl-crash-child.pid'
$crashReadyPath = Join-Path $buildRoot 'acl-crash-ready.marker'
$nl = [string][char]10
$expected = @('-100', '-101', '37', '-110', '0', '-114') -join $nl
$originalLocation = Get-Location
$toolHashInputs = @(
    [pscustomobject]@{ Id = 1; Path = 'Tests\Test-Stage7A.ps1' },
    [pscustomobject]@{ Id = 2; Path = 'Tests\Test-RuntimeABI.ps1' },
    [pscustomobject]@{ Id = 3; Path = 'Tests\BaselineM6\Test-Milestone6Baseline.ps1' },
    [pscustomobject]@{ Id = 4; Path = 'Tests\Test-StackProbeUnwind.ps1' },
    [pscustomobject]@{ Id = 5; Path = 'Tests\DevAgentBroker\TimeoutProbe.ps1' },
    [pscustomobject]@{ Id = 6; Path = 'Tests\DevAgentBroker\SuccessProbe.ps1' },
    [pscustomobject]@{ Id = 7; Path = 'Tests\DevAgentBroker\SandboxProbe.ps1' },
    [pscustomobject]@{ Id = 8; Path = 'Tests\DevAgentBroker\OverflowProbe.ps1' },
    [pscustomobject]@{ Id = 9; Path = 'Tests\DevAgentBroker\CrashProbe.ps1' }
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
        Write-Host ("DEVAGENT_TOOL_SHA256|{0}|{1}|{2}" -f $tool.Id, $tool.Path, $toolHash)
        if ($entry.Count -ne 1 -or [string]$entry[0].path -cne $tool.Path -or [string]$entry[0].sha256 -cne $toolHash) {
            throw "Pinned DevAgent tool hash/path mismatch for tool ID $($tool.Id)."
        }
        Write-Host ("DEVAGENT_TOOL_SHA256|{0}|{1}|{2}" -f $tool.Id, $tool.Path, $toolHash)
    }
    Set-Location -LiteralPath $repoRoot
    foreach ($required in @($compilerPath, $verifierPath, $fixturePath, $crashHarnessPath, $crashProbeScriptPath, $timeoutScriptPath, $successScriptPath, $sandboxScriptPath, $overflowScriptPath, $disabledFixturePath, $toolManifestPath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required broker test input is missing: $required" }
    }
    $compilerSource = [IO.File]::ReadAllText($compilerPath)
    if (-not $compilerSource.Contains($manifestHash) -or -not $compilerSource.Contains('BCryptHash') -or -not $compilerSource.Contains('BCryptOpenAlgorithmProvider') -or -not $compilerSource.Contains('Emit-DevBrokerVerifyScript')) {
        throw 'Compiler must pin the manifest and verify each tool script with native CNG before process creation.'
    }
    if ($compilerSource.Contains('sh_dev_run_process')) { throw 'Unsafe raw-command process API must not be present.' }
    if (-not $compilerSource.Contains('[switch] $EnableDevAgentTools') -or -not $compilerSource.Contains("Name = 'sh_dev_run_tool'; Builtin = 'DevRunTool'; ParameterTypes = @('Integer', 'Integer')")) {
        throw 'Typed integer-only process broker API is missing.'
    }
    $brokerEmitterStart = $compilerSource.IndexOf('function Emit-DevRunTool')
    $brokerEmitterEnd = $compilerSource.IndexOf('function Emit-BuiltinCall', $brokerEmitterStart)
    if ($brokerEmitterStart -lt 0 -or $brokerEmitterEnd -le $brokerEmitterStart) {
        throw 'Native DevAgent broker emitter could not be isolated for policy checks.'
    }
    $brokerEmitterSource = $compilerSource.Substring($brokerEmitterStart, $brokerEmitterEnd - $brokerEmitterStart)
    if (-not $brokerEmitterSource.Contains('bInheritHandles TRUE') -or -not $brokerEmitterSource.Contains('HANDLE_LIST') -or -not $brokerEmitterSource.Contains('CREATE_SUSPENDED')) {
        throw 'Broker must use STARTUPINFOEX with an explicit inherited-handle allowlist and suspended creation.'
    }
    if (-not $brokerEmitterSource.Contains('CreateProcessAsUserA') -or -not $brokerEmitterSource.Contains('CreateRestrictedToken') -or -not $brokerEmitterSource.Contains('TokenIsAppContainer') -or -not $brokerEmitterSource.Contains('TokenHasRestrictions') -or -not $brokerEmitterSource.Contains('TokenCapabilities')) {
        throw 'Broker must create and verify a restricted AppContainer primary token before resume.'
    }
    if ($brokerEmitterSource.Contains('TargetRva ([UInt32]0x3188)')) {
        throw 'Live broker must not fall back to unrestricted CreateProcessA.'
    }
    foreach ($requiredApi in @('CreatePipe', 'PeekNamedPipe', 'UpdateProcThreadAttribute', 'DeleteProcThreadAttributeList', '0x100000')) {
        if (-not $brokerEmitterSource.Contains($requiredApi)) { throw "Required native sandbox/output component is missing: $requiredApi" }
    }
    foreach ($requiredApi in @('GetSecurityInfo', 'SetSecurityInfo', 'SetEntriesInAclA')) {
        if (-not $compilerSource.Contains($requiredApi)) { throw "Required handle-based ACL API is missing: $requiredApi" }
    }
    if (-not $compilerSource.Contains('KILL_ON_JOB_CLOSE') -or -not $compilerSource.Contains('ACTIVE_PROCESS') -or -not $compilerSource.Contains('0x2308')) {
        throw 'Job Object kill-on-close, active-process and memory-limit flags are missing.'
    }
    if (-not $compilerSource.Contains('GetFileAttributesA') -or -not $compilerSource.Contains('GetFileInformationByHandle') -or -not $compilerSource.Contains('GetModuleFileNameA') -or -not $compilerSource.Contains('SetCurrentDirectoryA') -or -not $compilerSource.Contains('0x400') -or -not $compilerSource.Contains('0x00200080')) {
        throw 'Image-relative workspace and opened-handle reparse-point checks are missing.'
    }
    if ($brokerEmitterSource.Contains('GetCurrentDirectoryA')) {
        throw 'Broker must not trust the inherited current directory as its workspace root.'
    }
    if (-not $brokerEmitterSource.Contains('BuildWorkspacePath -RootSlot $workspaceRootSlot') -or
        -not $brokerEmitterSource.Contains('Build commandLineSlot = fixed prefix + the exact SHA-256-verified absolute script path + suffix')) {
        throw 'PowerShell command must be constructed from the hash-verified absolute workspace script path.'
    }
    if (-not $compilerSource.Contains('BCryptOpenAlgorithmProvider') -or -not $compilerSource.Contains('BCryptHash') -or -not $compilerSource.Contains('BCryptCloseAlgorithmProvider')) {
        throw 'Native Windows CNG SHA-256 verification is missing.'
    }
    if (-not $compilerSource.Contains('VirtualAlloc') -or -not $compilerSource.Contains('VirtualFree') -or -not $compilerSource.Contains('0x100000')) {
        throw 'The bounded native script-hash input buffer is missing.'
    }

    foreach ($required in @(
        'function Emit-DevBrokerEnsureAppContainerSid',
        'function Emit-DevBrokerUpdateAcl',
        'CreateAppContainerProfile',
        'DeriveAppContainerSidFromAppContainerName',
        'CreateRestrictedToken',
        'CreateProcessAsUserA',
        'TokenIsAppContainer',
        'TokenHasRestrictions',
        'TokenCapabilities',
        'GetSecurityInfo',
        'SetSecurityInfo',
        'SetEntriesInAclA',
        'TRUSTEE_IS_SID',
        'PROC_THREAD_ATTRIBUTE_SECURITY_CAPABILITIES',
        'HANDLE_LIST'
    )) {
        if (-not $compilerSource.Contains($required)) {
            throw "Native sandbox security component is missing: $required"
        }
    }
    $importArrayMatch = [regex]::Match($compilerSource, '\$importSets\s*=\s*@\(([\s\S]*?)\r?\n\)')
    if (-not $importArrayMatch.Success) { throw 'Native import-set declarations could not be parsed.' }
    $importRecords = [regex]::Matches($importArrayMatch.Groups[1].Value, "Descriptor = (0x[0-9A-Fa-f]+); Lookup = (0x[0-9A-Fa-f]+); Iat = (0x[0-9A-Fa-f]+); Dll = '([^']+)'; Names = @\(([^)]*)\)")
    if ($importRecords.Count -ne 16) { throw "Expected 16 import descriptors, found $($importRecords.Count)." }
    $iatRanges = @()
    $lookupRanges = @()
    foreach ($record in $importRecords) {
        $iatStart = [Convert]::ToInt32($record.Groups[3].Value.Substring(2), 16)
        $lookupStart = [Convert]::ToInt32($record.Groups[2].Value.Substring(2), 16)
        $apiCount = [regex]::Matches($record.Groups[5].Value, "'[^']+'").Count
        if ($apiCount -lt 1) { throw 'An import descriptor contains no API names.' }
        $iatRanges += [pscustomobject]@{ Start = $iatStart; End = $iatStart + (($apiCount + 1) * 8); Dll = $record.Groups[4].Value }
        $lookupRanges += [pscustomobject]@{ Start = $lookupStart; End = $lookupStart + (($apiCount + 1) * 8); Dll = $record.Groups[4].Value }
    }
    for ($i = 0; $i -lt $iatRanges.Count; $i++) {
        for ($j = $i + 1; $j -lt $iatRanges.Count; $j++) {
            if ($iatRanges[$i].Start -lt $iatRanges[$j].End -and $iatRanges[$j].Start -lt $iatRanges[$i].End) {
                throw "IAT arrays overlap, including their terminators: $($iatRanges[$i].Dll) and $($iatRanges[$j].Dll)."
            }
            if ($lookupRanges[$i].Start -lt $lookupRanges[$j].End -and $lookupRanges[$j].Start -lt $lookupRanges[$i].End) {
                throw "Import lookup tables overlap, including their terminators: $($lookupRanges[$i].Dll) and $($lookupRanges[$j].Dll)."
            }
        }
    }
    $iatEnd = ($iatRanges | Measure-Object -Property End -Maximum).Maximum
    if ($iatEnd -ne 0x330 -or -not $compilerSource.Contains('Value 0x2C0')) {
        throw "Import Address Table extent must include the final zero thunk through offset 0x330; actual end=$('{0:X}' -f $iatEnd)."
    }
    Write-Host 'PASS: import lookup and IAT arrays are disjoint, including each module terminator' -ForegroundColor Green

    $expectedHelperIatCalls = @(
        'TargetRva ([UInt32]0x3278)', # CreateAppContainerProfile
        'TargetRva ([UInt32]0x3280)', # DeriveAppContainerSidFromAppContainerName
        'TargetRva ([UInt32]0x32C8)', # GetSecurityInfo
        'TargetRva ([UInt32]0x3298)', # SetEntriesInAclA
        'TargetRva ([UInt32]0x32D0)', # SetSecurityInfo
        'TargetRva ([UInt32]0x32E0)', # GetSecurityDescriptorDacl
        'TargetRva ([UInt32]0x32E8)', # GetSecurityDescriptorSacl
        'TargetRva ([UInt32]0x32F0)', # GetSecurityDescriptorLength
        'TargetRva ([UInt32]0x32F8)', # IsValidSecurityDescriptor
        'TargetRva ([UInt32]0x3318)', # MoveFileExA
        'TargetRva ([UInt32]0x3320)'  # FlushFileBuffers
    )
    foreach ($expectedCall in $expectedHelperIatCalls) {
        if (-not $compilerSource.Contains($expectedCall)) {
            throw "Sandbox helper API call does not target its declared IAT slot: $expectedCall"
        }
    }
    if (-not $brokerEmitterSource.Contains('TargetRva ([UInt32]0x32D8)')) {
        throw 'GetTokenInformation call does not target its declared ADVAPI32 IAT slot.'
    }
    if (-not $brokerEmitterSource.Contains('Emit-DevBrokerUpdateAcl -PathSlot $workspaceRootSlot') -or -not $brokerEmitterSource.Contains('Emit-DevBrokerUpdateAcl -PathSlot $buildPathSlot')) {
        throw 'Broker does not apply the workspace-root and Build ACL policies.'
    }
    if (-not $brokerEmitterSource.Contains('CreatePipe') -or -not $brokerEmitterSource.Contains('PeekNamedPipe') -or -not $brokerEmitterSource.Contains('0x100000')) {
        throw 'Broker does not provide the hard-capped native output drain.'
    }

    # Mandatory Integrity Control is evaluated before the DACL. A low-IL
    # AppContainer therefore needs an inheritable Low IL label on the writable
    # Build subtree; the source workspace must not receive that label.
    foreach ($required in @(
        'SYSTEM_MANDATORY_LABEL_ACE',
        'LABEL_SECURITY_INFORMATION',
        'WRITE_OWNER',
        'S-1-16-4096',
        '0x00001000',
        '0x00000001001C0002',
        '0x00140311'
    )) {
        if (-not $compilerSource.Contains($required)) {
            throw "Low-integrity mandatory-label implementation is missing: $required"
        }
    }
    # Distinguish the migration-time REVOKE_ACCESS calls from the actual grant
    # calls. The positive grants must occur after the durable journal commit.
    $journalCommitOffset = $brokerEmitterSource.IndexOf('Emit-DevBrokerWriteAclJournal', [StringComparison]::Ordinal)
    if ($journalCommitOffset -lt 0) { throw 'Durable ACL snapshot/commit call is missing.' }
    $postJournalAclSource = $brokerEmitterSource.Substring($journalCommitOffset)
    $grantLines = @($postJournalAclSource -split '\r?\n' | Where-Object { $_.Contains('Emit-DevBrokerUpdateAcl') })
    $workspaceGrant = $grantLines | Where-Object { $_.Contains('-PathSlot $workspaceRootSlot') -and $_.Contains('-AccessMode 2') } | Select-Object -First 1
    $buildGrant = $grantLines | Where-Object { $_.Contains('-PathSlot $buildPathSlot') -and $_.Contains('-AccessMode 2') } | Select-Object -First 1
    $brokerBuildGrant = $grantLines | Where-Object { $_.Contains('-PathSlot $brokerDirectorySlot') -and $_.Contains('-AccessMode 2') } | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($workspaceGrant) -or
        [string]::IsNullOrWhiteSpace($buildGrant) -or
        [string]::IsNullOrWhiteSpace($brokerBuildGrant)) {
        throw 'Expected post-journal workspace, Build, and Build\\DevAgentBroker ACL grants were not all found.'
    }
    if ($workspaceGrant.Contains('-SetLowIntegrityLabel')) {
        throw 'The workspace source root must not be relabeled Low IL.'
    }
    if (-not $buildGrant.Contains('-SetLowIntegrityLabel $true') -or
        -not $brokerBuildGrant.Contains('-SetLowIntegrityLabel $true')) {
        throw 'Both writable Build directories must receive the Low IL mandatory label after the durable journal commit.'
    }
    if (-not $brokerEmitterSource.Contains('mainCapReadReady') -or
        -not $brokerEmitterSource.Contains('finalCapReadReady') -or
        ($brokerEmitterSource.IndexOf('read only the remaining capacity', [StringComparison]::OrdinalIgnoreCase) -lt 0)) {
        throw 'Output capture must consume up to exactly 1 MiB before reporting overflow.'
    }
    Write-Host 'PASS: Low IL is applied only to writable Build staging; the source workspace keeps its existing integrity label' -ForegroundColor Green
    Write-Host 'PASS: capture reads the remaining 1 MiB capacity before classifying subsequent bytes as overflow' -ForegroundColor Green
    # Both WAIT_OBJECT_0 and WAIT_ABANDONED converge on recovery while the caller
    # owns the mutex. Recovery must finish before the AppContainer identity is used.
    $mutexBlockStart = $brokerEmitterSource.IndexOf('# Serialize each ACL transaction')
    $mutexBlockEnd = $brokerEmitterSource.IndexOf('Emit-DevBrokerRecoverAclJournal', $mutexBlockStart)
    $recoveryCall = $brokerEmitterSource.IndexOf('Emit-DevBrokerRecoverAclJournal', $mutexBlockStart)
    $sidCreation = $brokerEmitterSource.IndexOf('Emit-DevBrokerEnsureAppContainerSid', $recoveryCall, [StringComparison]::Ordinal)
    $journalCommit = $brokerEmitterSource.IndexOf('Emit-DevBrokerWriteAclJournal', $sidCreation, [StringComparison]::Ordinal)
    $firstGrant = $brokerEmitterSource.IndexOf('AccessMask ([UInt32]0x001200A9)', $journalCommit, [StringComparison]::Ordinal)
    $abandonedBranch = $brokerEmitterSource.IndexOf("New-UniqueLabel -Prefix 'dev_tool_mutex_abandoned'", $mutexBlockStart, [StringComparison]::Ordinal)
    $abandonedJoin = $brokerEmitterSource.IndexOf('Emit-Jump -Label $mutexReady', $abandonedBranch, [StringComparison]::Ordinal)
    if ($mutexBlockStart -lt 0 -or $mutexBlockEnd -le $mutexBlockStart -or
        $abandonedBranch -lt 0 -or $abandonedJoin -le $abandonedBranch -or
        $recoveryCall -lt 0 -or $sidCreation -le $recoveryCall -or
        $journalCommit -le $sidCreation -or $firstGrant -le $journalCommit) {
        throw 'WAIT_ABANDONED recovery, manifest identity setup, durable snapshot and first ACL expansion are out of order.'
    }
    foreach ($requiredJournalApi in @('MoveFileExA', 'FlushFileBuffers', 'Emit-DevBrokerRestoreSecurityDescriptor', 'IsValidSecurityDescriptor', '0x80200002')) {
        if (-not $compilerSource.Contains($requiredJournalApi)) { throw "Crash-safe ACL journal component missing: $requiredJournalApi" }
    }
    $restoreHelperStart = $compilerSource.IndexOf('function Emit-DevBrokerRestoreSecurityDescriptor', [StringComparison]::Ordinal)
    $restoreHelperEnd = $compilerSource.IndexOf('function Emit-DevBrokerWriteAclJournal', $restoreHelperStart, [StringComparison]::Ordinal)
    if ($restoreHelperStart -lt 0 -or $restoreHelperEnd -le $restoreHelperStart) {
        throw 'Security descriptor restore helper could not be isolated.'
    }
    $restoreHelper = $compilerSource.Substring($restoreHelperStart, $restoreHelperEnd - $restoreHelperStart)
    $restoreSuccessCheck = $restoreHelper.IndexOf('Emit-StoreBits32Frame -SlotPosition $daclPresentSlot -Value 1', [StringComparison]::Ordinal)
    $restoreFailureCheck = $restoreHelper.IndexOf('Emit-StoreBits32Frame -SlotPosition $daclPresentSlot -Value 0', $restoreSuccessCheck, [StringComparison]::Ordinal)
    if ($restoreSuccessCheck -lt 0 -or $restoreFailureCheck -le $restoreSuccessCheck) {
        throw 'ACL restore helper must distinguish successful SetSecurityInfo from its fail-closed path.'
    }
    if (-not $restoreHelper.Contains('DACL_SECURITY_INFORMATION only; root label is never changed') -or
        -not $restoreHelper.Contains('DACL_SECURITY_INFORMATION | LABEL_SECURITY_INFORMATION')) {
        throw 'ACL rollback must restore only the components modified at each path: root DACL, child DACL plus mandatory label.'
    }
    if (-not $brokerEmitterSource.Contains('-RestoreLabel $true -FailureLabel $aclRollbackBuildFail') -or
        -not $brokerEmitterSource.Contains('-RestoreLabel $true -FailureLabel $aclRollbackBrokerFail')) {
        throw 'Build and broker directory rollback must restore their temporary Low IL labels.'
    }
    foreach ($restoreStage in 1..6) {
        if (-not $restoreHelper.Contains("-Value $restoreStage")) {
            throw "ACL restore diagnostic stage $restoreStage is missing."
        }
    }
    if (-not $restoreHelper.Contains('$restoreErrorSlot = $scratch + 0xE84') -or
        -not $restoreHelper.Contains('SetSecurityInfo returns a Win32 error code directly')) {
        throw 'ACL rollback must preserve the native SetSecurityInfo error instead of collapsing it into a generic stage failure.'
    }
    Write-Host 'PASS: WAIT_ABANDONED acquires the mutex and recovers the durable ACL journal before any new child' -ForegroundColor Green
    Write-Host 'PASS: all ACL expansions occur after a flushed, write-through journal commit' -ForegroundColor Green
    foreach ($noProfileProbe in @($timeoutScriptPath, $crashProbeScriptPath)) {
        $probeText = [IO.File]::ReadAllText($noProfileProbe)
        if ($probeText.Contains('Start-Sleep') -or -not $probeText.Contains('[Threading.Thread]::Sleep(')) {
            throw "No-profile AppContainer probe must use .NET Thread.Sleep, not profile-dependent Start-Sleep: $noProfileProbe"
        }
    }
    Write-Host 'PASS: timeout and crash probes use profile-independent .NET Thread.Sleep'
    Write-Host 'PASS: broker source declares restricted-token, AppContainer, handle-based ACL and bounded-output runtime gates' -ForegroundColor Green

    New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
    Remove-Item -LiteralPath $journalPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $journalTempPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $crashChildPidPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $crashReadyPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $childPidPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $outputPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $sandboxMarkerPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $deniedMarkerPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $capturedOutputPath -Force -ErrorAction SilentlyContinue

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

    $manifestOriginalBytes = [IO.File]::ReadAllBytes($toolManifestPath)
    $manifestTamperOutputPath = Join-Path $buildRoot 'DevAgentBrokerManifestTamper.exe'
    Remove-Item -LiteralPath $manifestTamperOutputPath -Force -ErrorAction SilentlyContinue
    try {
        [IO.File]::AppendAllText($toolManifestPath, ' ', [Text.Encoding]::ASCII)
        $manifestTamperRejected = $false
        try {
            & $compilerPath -Source $fixturePath -Output $manifestTamperOutputPath -EnableDevAgentTools
        }
        catch {
            $manifestTamperRejected = $true
        }
        if (-not $manifestTamperRejected -or (Test-Path -LiteralPath $manifestTamperOutputPath -PathType Leaf)) {
            throw 'Compiler accepted a modified DevAgent tool manifest.'
        }
    }
    finally {
        [IO.File]::WriteAllBytes($toolManifestPath, $manifestOriginalBytes)
    }
    Write-Host 'PASS: modified tool manifest rejected before native broker generation' -ForegroundColor Green

    & $compilerPath -Source $fixturePath -Output $outputPath -EnableDevAgentTools
    if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) { throw 'Compiler did not produce the DevAgent broker fixture.' }
    & $verifierPath -Path $outputPath

    $successOriginalBytes = [IO.File]::ReadAllBytes($successScriptPath)
    $foreignWorkingDirectory = Join-Path $env:TEMP 'SharnouDevAgent-ForeignWorkingDirectory'
    Remove-Item -LiteralPath $foreignWorkingDirectory -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $foreignWorkingDirectory -Force | Out-Null
    try {
        Set-Location -LiteralPath $foreignWorkingDirectory
        $lines = @(& $outputPath 2>&1)
        $exitCode = $LASTEXITCODE
        # Child console diagnostics may be visible; compare only broker numeric return records.
        $numericLines = @(Get-BrokerNumericLines -Lines $lines)
        $actual = ($numericLines -join $nl).TrimEnd([char[]]@([char]13, [char]10))
        if ($exitCode -ne 0) { throw "Broker fixture process exited with code $exitCode. Output=[$actual]." }
        if (-not [string]::Equals($actual, $expected, [StringComparison]::Ordinal)) {
            $timeoutDiagnosticPath = Join-Path $buildRoot 'timeout-probe-diagnostic.txt'
            Write-Host ("DEVAGENT_TIMEOUT_MARKER_PRESENT|{0}" -f (Test-Path -LiteralPath $childPidPath -PathType Leaf))
            if (Test-Path -LiteralPath $timeoutDiagnosticPath -PathType Leaf) {
                $timeoutProbeDiagnostic = Get-Content -LiteralPath $timeoutDiagnosticPath -Raw -Encoding UTF8
                Write-Host ("DEVAGENT_TIMEOUT_PROBE_DETAIL|{0}" -f $timeoutProbeDiagnostic)
            }
            if (Test-Path -LiteralPath $capturedOutputPath -PathType Leaf) {
                $diagnosticBytes = [IO.File]::ReadAllBytes($capturedOutputPath)
                $diagnosticLength = [Math]::Min(4096, $diagnosticBytes.Length)
                $diagnosticText = [Text.Encoding]::UTF8.GetString($diagnosticBytes, 0, $diagnosticLength)
                Write-Host ("DEVAGENT_CAPTURE_DIAGNOSTIC|length={0}|sample={1}" -f $diagnosticBytes.Length, $diagnosticText)
            }
            throw "Broker fixture output mismatch. Expected=[$expected] Actual=[$actual]."
        }
        if (-not (Test-Path -LiteralPath $sandboxMarkerPath -PathType Leaf)) {
            if (Test-Path -LiteralPath $capturedOutputPath -PathType Leaf) {
                $sandboxDiagnostic = [IO.File]::ReadAllBytes($capturedOutputPath)
                $sandboxDiagnosticLength = [Math]::Min(4096, $sandboxDiagnostic.Length)
                $sandboxDiagnosticText = [Text.Encoding]::UTF8.GetString($sandboxDiagnostic, 0, $sandboxDiagnosticLength)
                Write-Host ("DEVAGENT_SANDBOX_DIAGNOSTIC|length={0}|sample={1}" -f $sandboxDiagnostic.Length, $sandboxDiagnosticText)
            }
            throw 'AppContainer could not write to the designated Build staging directory.'
        }
        if (Test-Path -LiteralPath $deniedMarkerPath -PathType Leaf) {
            throw 'AppContainer unexpectedly wrote into the read-only Tests workspace.'
        }
        if (-not (Test-Path -LiteralPath $capturedOutputPath -PathType Leaf)) {
            throw 'Bounded stdout/stderr capture did not persist captured-output.bin.'
        }
        $capturedLength = (Get-Item -LiteralPath $capturedOutputPath).Length
        if ($capturedLength -ne 1MB) {
            throw "Output overflow probe must persist exactly 1 MiB before returning -114; captured=$capturedLength bytes."
        }

        if (-not (Test-Path -LiteralPath $childPidPath -PathType Leaf)) {
            if (Test-Path -LiteralPath $capturedOutputPath -PathType Leaf) {
                $timeoutDiagnosticBytes = [IO.File]::ReadAllBytes($capturedOutputPath)
                $timeoutDiagnosticLength = [Math]::Min(8192, $timeoutDiagnosticBytes.Length)
                $timeoutDiagnosticText = [Text.Encoding]::UTF8.GetString($timeoutDiagnosticBytes, 0, $timeoutDiagnosticLength)
                Write-Host ("DEVAGENT_TIMEOUT_DIAGNOSTIC|length={0}|sample={1}" -f $timeoutDiagnosticBytes.Length, $timeoutDiagnosticText)
            }
            throw 'Timeout probe did not publish the child PID before the broker timeout.'
        }
        $childPid = [int](Get-Content -LiteralPath $childPidPath -Raw)
        if ($null -ne (Get-Process -Id $childPid -ErrorAction SilentlyContinue)) {
            throw "Job Object timeout failed to terminate timed-out broker child PID $childPid."
        }

        # Tamper with the fixed success tool after the PE is built. The embedded
        # SHA-256 must reject it before the script's exit 37 can execute.
        [IO.File]::AppendAllText($successScriptPath, "`r`n# intentional broker hash mismatch test`r`n", [Text.Encoding]::ASCII)
        $tamperedFileSha256 = (Get-FileHash -LiteralPath $successScriptPath -Algorithm SHA256).Hash
        $pinnedSuccessSha256 = [string](@($manifest.tools | Where-Object { [int]$_.id -eq 6 })[0].sha256)
        if ($tamperedFileSha256 -ceq $pinnedSuccessSha256) { throw 'Test precondition failed: SuccessProbe content was not changed.' }
        Write-Host ("DEVAGENT_TAMPERED_TOOL_SHA256|6|{0}" -f $tamperedFileSha256)
        Remove-Item -LiteralPath $childPidPath -Force -ErrorAction SilentlyContinue
        $tamperedLines = @(& $outputPath 2>&1)
        $tamperedExitCode = $LASTEXITCODE
        $tamperedNumericLines = @(Get-BrokerNumericLines -Lines $tamperedLines)
        $tamperedActual = ($tamperedNumericLines -join $nl).TrimEnd([char[]]@([char]13, [char]10))
        $tamperedExpected = @('-100', '-101', '-111', '-110', '0', '-114') -join $nl
        if ($tamperedExitCode -ne 0 -or -not [string]::Equals($tamperedActual, $tamperedExpected, [StringComparison]::Ordinal)) {
            throw "Runtime script hash tampering was not rejected. Expected=[$tamperedExpected] Actual=[$tamperedActual] ExitCode=$tamperedExitCode."
        }
        if (-not (Test-Path -LiteralPath $childPidPath -PathType Leaf)) {
            throw 'Timeout probe did not publish the child PID during hash-tamper replay.'
        }
        $tamperedChildPid = [int](Get-Content -LiteralPath $childPidPath -Raw)
        if ($null -ne (Get-Process -Id $tamperedChildPid -ErrorAction SilentlyContinue)) {
            throw "Job Object timeout failed to terminate timed-out broker child PID $tamperedChildPid during hash-tamper replay."
        }
    }
    finally {
        [IO.File]::WriteAllBytes($successScriptPath, $successOriginalBytes)
        Set-Location -LiteralPath $repoRoot
        Remove-Item -LiteralPath $foreignWorkingDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Establish the clean post-invocation DACL baseline before inducing a real
    # parent-process crash while an AppContainer child is running.
    if ((Test-Path -LiteralPath $journalPath) -or (Test-Path -LiteralPath $journalTempPath)) {
        throw 'A successful broker invocation left an ACL journal or temporary file behind.'
    }
    $aclPaths = @($repoRoot, (Join-Path $repoRoot 'Build'), $buildRoot)
    $aclBaseline = @{}
    foreach ($aclPath in $aclPaths) { $aclBaseline[$aclPath] = Get-BrokerDaclSddl -Path $aclPath }

    $originalBrokerImage = [IO.File]::ReadAllBytes($outputPath)
    $crashStdoutPath = Join-Path $buildRoot 'acl-crash-parent.stdout'
    $crashStderrPath = Join-Path $buildRoot 'acl-crash-parent.stderr'
    $crashProcess = $null
    try {
        Remove-Item -LiteralPath $crashChildPidPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $crashReadyPath -Force -ErrorAction SilentlyContinue
        & $compilerPath -Source $crashHarnessPath -Output $outputPath -EnableDevAgentTools
        & $verifierPath -Path $outputPath
        $crashProcess = Start-Process -FilePath $outputPath -PassThru -NoNewWindow -RedirectStandardOutput $crashStdoutPath -RedirectStandardError $crashStderrPath

        $crashDeadline = [DateTime]::UtcNow.AddSeconds(25)
        while ([DateTime]::UtcNow -lt $crashDeadline) {
            $crashProcess.Refresh()
            if ($crashProcess.HasExited) { throw 'Crash harness exited before publishing its child-ready marker.' }
            if ((Test-Path -LiteralPath $crashReadyPath -PathType Leaf) -and (Test-Path -LiteralPath $crashChildPidPath -PathType Leaf)) { break }
            Start-Sleep -Milliseconds 200
        }
        if (-not (Test-Path -LiteralPath $crashReadyPath -PathType Leaf) -or
            -not (Test-Path -LiteralPath $crashChildPidPath -PathType Leaf) -or
            -not (Test-Path -LiteralPath $journalPath -PathType Leaf)) {
            throw 'Crash probe did not reach the post-ACL/pre-exit state with a committed journal.'
        }
        $crashChildPid = [int](Get-Content -LiteralPath $crashChildPidPath -Raw)
        foreach ($aclPath in $aclPaths) {
            $duringCrashSddl = Get-BrokerDaclSddl -Path $aclPath
            if ([string]::Equals($duringCrashSddl, $aclBaseline[$aclPath], [StringComparison]::Ordinal)) {
                throw "Expected transient execution ACE was not present on $aclPath during the child run."
            }
        }

        # Abruptly kill the native broker parent. Closing its Job Object handle
        # must terminate the AppContainer child; the durable journal must remain.
        $crashProcess.Kill()
        if (-not $crashProcess.WaitForExit(10000)) { throw 'Crash broker parent did not terminate after Kill().' }
        $childDeadline = [DateTime]::UtcNow.AddSeconds(10)
        while ([DateTime]::UtcNow -lt $childDeadline) {
            if ($null -eq (Get-Process -Id $crashChildPid -ErrorAction SilentlyContinue)) { break }
            Start-Sleep -Milliseconds 200
        }
        if ($null -ne (Get-Process -Id $crashChildPid -ErrorAction SilentlyContinue)) {
            throw "Job Object kill-on-close left crash child PID $crashChildPid alive."
        }
        if (-not (Test-Path -LiteralPath $journalPath -PathType Leaf)) {
            throw 'Abrupt parent termination lost the durable ACL recovery journal.'
        }
    }
    finally {
        if ($null -ne $crashProcess) {
            $crashProcess.Refresh()
            if (-not $crashProcess.HasExited) {
                $crashProcess.Kill()
                [void]$crashProcess.WaitForExit(10000)
            }
        }
        # Restore the exact already-verified normal broker image even if the
        # adversarial phase itself fails, so subsequent tests use the normal fixture.
        [IO.File]::WriteAllBytes($outputPath, $originalBrokerImage)
    }

    $recoveryLines = @(& $outputPath 2>&1)
    $recoveryExitCode = $LASTEXITCODE
    $recoveryNumericLines = @(Get-BrokerNumericLines -Lines $recoveryLines)
    $recoveryActual = ($recoveryNumericLines -join $nl).TrimEnd([char[]]@([char]13, [char]10))
    if ($recoveryExitCode -ne 0 -or -not [string]::Equals($recoveryActual, $expected, [StringComparison]::Ordinal)) {
        throw "Post-crash ACL recovery replay failed. Expected=[$expected] Actual=[$recoveryActual] ExitCode=$recoveryExitCode."
    }
    foreach ($aclPath in $aclPaths) {
        $restoredSddl = Get-BrokerDaclSddl -Path $aclPath
        if (-not [string]::Equals($restoredSddl, $aclBaseline[$aclPath], [StringComparison]::Ordinal)) {
            throw "ACL DACL rollback/recovery did not reproduce its exact pre-run descriptor on $aclPath."
        }
    }
    if ((Test-Path -LiteralPath $journalPath) -or (Test-Path -LiteralPath $journalTempPath)) {
        throw 'Successful crash recovery left a committed or temporary ACL journal behind.'
    }
    Write-Host 'PASS: normal execution restored exact DACL SDDL on workspace root, Build and broker directories' -ForegroundColor Green
    Write-Host 'PASS: forced parent termination preserved its journal and Job Object killed the AppContainer child' -ForegroundColor Green
    Write-Host 'PASS: next invocation recovered the abandoned ACL transaction and removed the journal' -ForegroundColor Green

    $brokerDirectory = Join-Path $repoRoot 'Tests\DevAgentBroker'
    $brokerDirectoryBackup = Join-Path $buildRoot 'DevAgentBroker.original'
    $junctionTarget = Join-Path $buildRoot 'JunctionTarget'
    Remove-Item -LiteralPath $brokerDirectoryBackup -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $junctionTarget -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $junctionTarget -Force | Out-Null
    Move-Item -LiteralPath $brokerDirectory -Destination $brokerDirectoryBackup
    try {
        New-Item -ItemType Junction -Path $brokerDirectory -Target $junctionTarget | Out-Null
        Remove-Item -LiteralPath $childPidPath -Force -ErrorAction SilentlyContinue
        $reparseLines = @(& $outputPath 2>&1)
        $reparseExitCode = $LASTEXITCODE
        $reparseNumericLines = @(Get-BrokerNumericLines -Lines $reparseLines)
        $reparseActual = ($reparseNumericLines -join $nl).TrimEnd([char[]]@([char]13, [char]10))
        $reparseExpected = @('-100', '-101', '-103', '-103', '-103', '-103') -join $nl
        if ($reparseExitCode -ne 0 -or -not [string]::Equals($reparseActual, $reparseExpected, [StringComparison]::Ordinal)) {
            throw "Workspace reparse-point rejection failed. Expected=[$reparseExpected] Actual=[$reparseActual] ExitCode=$reparseExitCode."
        }
        if (Test-Path -LiteralPath $childPidPath -PathType Leaf) {
            throw 'Broker launched a child process despite the workspace reparse-point rejection.'
        }
    }
    finally {
        if (Test-Path -LiteralPath $brokerDirectory) {
            Remove-Item -LiteralPath $brokerDirectory -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $brokerDirectoryBackup -PathType Container) {
            Move-Item -LiteralPath $brokerDirectoryBackup -Destination $brokerDirectory
        }
        Remove-Item -LiteralPath $junctionTarget -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host 'PASS: native Windows CNG SHA-256 verifies every selected tool before CreateProcess' -ForegroundColor Green
    Write-Host 'PASS: native script hash mismatch rejected before child creation' -ForegroundColor Green
    Write-Host 'PASS: compiler pins manifest SHA-256 and all nine tool-script hashes' -ForegroundColor Green
    Write-Host 'PASS: AppContainer token identity and zero-capability token are checked before resume' -ForegroundColor Green
    Write-Host 'PASS: AppContainer writes are confined to Build and denied in Tests' -ForegroundColor Green
    Write-Host 'PASS: merged stdout/stderr capture is capped at exactly 1 MiB and persisted through one exclusive handle' -ForegroundColor Green
    Write-Host 'PASS: broker derives workspace from its image path and ignores a foreign current directory' -ForegroundColor Green
    Write-Host 'PASS: workspace paths and opened script handles reject reparse points' -ForegroundColor Green
    Write-Host 'PASS: runtime CNG SHA-256 mismatch rejected before modified tool execution' -ForegroundColor Green
    Write-Host 'PASS: per-execution DACL grants are journaled and reliably rolled back across process death' -ForegroundColor Green
    Write-Host 'PASS: unknown tool IDs rejected before process creation' -ForegroundColor Green
    Write-Host 'PASS: timeout values below policy minimum rejected' -ForegroundColor Green
    Write-Host 'PASS: fixed allowlisted success tool launched by absolute System32 PowerShell path' -ForegroundColor Green
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
    Remove-Item -LiteralPath $sandboxMarkerPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $deniedMarkerPath -Force -ErrorAction SilentlyContinue
}
