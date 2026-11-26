[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSEdition -ne 'Desktop') {
    throw 'Workspace security tests require Windows PowerShell 5.1.'
}
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or [IntPtr]::Size -ne 8) {
    throw 'Workspace security tests require 64-bit Windows.'
}

$modulePath = Join-Path $PSScriptRoot 'DevAgentBroker\WorkspaceTransaction.ps1'
$crashChildPath = Join-Path $PSScriptRoot 'DevAgentBroker\WorkspaceCrashChild.ps1'
. $modulePath

$script:Passed = 0
$script:Failed = 0
$junctionId = ''
$sections = [System.Security.AccessControl.AccessControlSections]::Owner -bor [System.Security.AccessControl.AccessControlSections]::Group -bor [System.Security.AccessControl.AccessControlSections]::Access
$supervisorSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$executionSidA = 'S-1-15-2-11001-22002-33003-44004-55005-66006'
$executionSidB = 'S-1-15-2-11006-22007-33008-44009-55010-66011'
$systemSid = 'S-1-5-18'
$base = Join-Path $env:TEMP ('Sharnou-Workspace-Security-' + [Guid]::NewGuid().ToString('N'))
$workspaceRoot = Join-Path $base 'executions'
$journalRoot = Join-Path $base 'state'
$externalRoot = Join-Path $base 'outside'
$processHost = Join-Path $PSHOME 'powershell.exe'

function Assert-WorkspaceTest {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        $script:Failed++
        throw "FAIL: $Message"
    }
    $script:Passed++
    Write-Host ("PASS: {0}" -f $Message) -ForegroundColor Green
}

function Get-TestSddl {
    param([string]$Path)
    $acl = [System.IO.Directory]::GetAccessControl($Path, $sections)
    return $acl.GetSecurityDescriptorSddlForm($sections)
}

function Get-TestAccessRules {
    param([string]$Path)
    $acl = [System.IO.Directory]::GetAccessControl($Path, $sections)
    return $acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])
}

function Quote-WindowsArgument {
    param([string]$Value)
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Wait-ForCrashMarker {
    param(
        [string]$Phase,
        [string]$WorkspacePath,
        [string]$JournalPath,
        [string]$ExecutionSid,
        [string]$MarkerPath
    )

    $arguments = @(
        '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', $crashChildPath,
        '-WorkspaceRoot', $WorkspacePath,
        '-JournalRoot', $JournalPath,
        '-ExecutionSid', $ExecutionSid,
        '-SupervisorSid', $supervisorSid,
        '-CrashAfterPhase', $Phase,
        '-MarkerPath', $MarkerPath,
        '-ExternalRoot', $externalRoot
    )
    $argumentLine = ($arguments | ForEach-Object { Quote-WindowsArgument -Value ([string]$_) }) -join ' '
    $stdoutPath = $MarkerPath + '.stdout'
    $stderrPath = $MarkerPath + '.stderr'
    $process = Start-Process -FilePath $processHost -ArgumentList $argumentLine -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    while ([DateTime]::UtcNow -lt $deadline -and -not (Test-Path -LiteralPath $MarkerPath -PathType Leaf)) {
        if ($process.HasExited) { break }
        Start-Sleep -Milliseconds 100
    }

    if (-not (Test-Path -LiteralPath $MarkerPath -PathType Leaf)) {
        $out = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw } else { '' }
        $err = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw } else { '' }
        if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
        throw "Crash child did not reach $Phase. Exit=$($process.ExitCode). stdout=[$out] stderr=[$err]"
    }

    Stop-Process -Id $process.Id -Force
    if (-not $process.WaitForExit(10000)) {
        throw "Crash child PID $($process.Id) did not terminate after forced process death."
    }

    if (Test-Path -LiteralPath $stdoutPath) { Remove-Item -LiteralPath $stdoutPath -Force }
    if (Test-Path -LiteralPath $stderrPath) { Remove-Item -LiteralPath $stderrPath -Force }
}

function New-FakeJournal {
    param(
        [string]$Id,
        [string]$WorkspacePath,
        [string]$State = 'PREPARING',
        [string]$OriginalSddl = ''
    )
    $record = [pscustomobject]@{
        version = 1
        id = $Id
        state = $State
        workspacePath = $WorkspacePath
        executionSid = $executionSidA
        supervisorSid = $supervisorSid
        originalSddl = $OriginalSddl
        createdUtc = [DateTime]::UtcNow.ToString('o')
        updatedUtc = [DateTime]::UtcNow.ToString('o')
    }
    $path = Join-Path $journalRoot ($Id + '.json')
    [System.IO.File]::WriteAllText($path, (ConvertTo-Json -InputObject $record -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
    return $path
}

try {
    [void][System.IO.Directory]::CreateDirectory($base)
    [void][System.IO.Directory]::CreateDirectory($workspaceRoot)
    [void][System.IO.Directory]::CreateDirectory($journalRoot)
    [void][System.IO.Directory]::CreateDirectory($externalRoot)

    Set-SharnouProtectedDirectoryAcl -Path $workspaceRoot -AllowedSids @($supervisorSid, $systemSid)
    $baseSddlBefore = Get-TestSddl -Path $base
    $workspaceRootSddlBefore = Get-TestSddl -Path $workspaceRoot

    $badPaths = @(
        '\\server\share\workspace',
        '\\?\C:\device\workspace',
        '\\.\C:\device\workspace',
        'C:\temp\stream.txt:payload',
        '.\relative-workspace'
    )
    foreach ($badPath in $badPaths) {
        $rejected = $false
        try { [void](ConvertTo-SharnouCanonicalLocalPath -Path $badPath) } catch { $rejected = $true }
        Assert-WorkspaceTest -Condition $rejected -Message ("reject unsafe path syntax: " + $badPath)
    }

    $untrustedWorkspaceRoot = Join-Path $base 'untrusted-executions'
    $untrustedJournalRoot = Join-Path $base 'untrusted-state'
    [void][System.IO.Directory]::CreateDirectory($untrustedWorkspaceRoot)
    [void][System.IO.Directory]::CreateDirectory($untrustedJournalRoot)
    $untrustedParentSddl = Get-TestSddl -Path $base
    $untrustedWorkspaceSddl = Get-TestSddl -Path $untrustedWorkspaceRoot
    $untrustedJournalSddl = Get-TestSddl -Path $untrustedJournalRoot
    $untrustedRejected = $false
    try {
        [void](Initialize-SharnouWorkspaceSecurityRoots -WorkspaceRoot $untrustedWorkspaceRoot -JournalRoot $untrustedJournalRoot -SupervisorSid $supervisorSid)
    }
    catch {
        $untrustedRejected = $true
    }
    Assert-WorkspaceTest -Condition ($untrustedRejected -and ((Get-TestSddl -Path $untrustedWorkspaceRoot) -ceq $untrustedWorkspaceSddl) -and ((Get-TestSddl -Path $untrustedJournalRoot) -ceq $untrustedJournalSddl)) -Message 'untrusted workspace root is rejected without mutating either supplied root'
    Assert-WorkspaceTest -Condition ((Get-TestSddl -Path $base) -ceq $untrustedParentSddl) -Message 'failed root preflight does not mutate the shared parent ACL'

    $roots = Initialize-SharnouWorkspaceSecurityRoots -WorkspaceRoot $workspaceRoot -JournalRoot $journalRoot -SupervisorSid $supervisorSid
    $outsideSentinel = Join-Path $externalRoot 'must-survive.txt'
    [System.IO.File]::WriteAllText($outsideSentinel, 'untouched', [System.Text.Encoding]::ASCII)
    $invalidExecutionSidRejected = $false
    try {
        [void](New-SharnouExecutionWorkspace -WorkspaceRoot $workspaceRoot -JournalRoot $journalRoot -ExecutionSid $supervisorSid -SupervisorSid $supervisorSid)
    }
    catch {
        $invalidExecutionSidRejected = $true
    }
    Assert-WorkspaceTest -Condition $invalidExecutionSidRejected -Message 'non-AppContainer execution SID is rejected before workspace creation'

    $journalRules = @(Get-TestAccessRules -Path $journalRoot)
    $journalIdentities = @($journalRules | ForEach-Object { $_.IdentityReference.Value } | Sort-Object)
    $expectedJournalIdentities = @($supervisorSid, $systemSid) | Sort-Object
    Assert-WorkspaceTest -Condition ($journalIdentities.Count -eq 2 -and (($journalIdentities -join '|') -ceq ($expectedJournalIdentities -join '|'))) -Message 'journal directory is private to supervisor and SYSTEM'
    Assert-WorkspaceTest -Condition ((Get-TestSddl -Path $base) -ceq $baseSddlBefore) -Message 'journal hardening leaves its parent directory ACL unchanged'

    $txA = New-SharnouExecutionWorkspace -WorkspaceRoot $workspaceRoot -JournalRoot $journalRoot -ExecutionSid $executionSidA -SupervisorSid $supervisorSid
    $txB = New-SharnouExecutionWorkspace -WorkspaceRoot $workspaceRoot -JournalRoot $journalRoot -ExecutionSid $executionSidB -SupervisorSid $supervisorSid
    Assert-WorkspaceTest -Condition ($txA.Id -ne $txB.Id -and $txA.WorkspacePath -ne $txB.WorkspacePath) -Message 'each execution receives a unique non-shared workspace'
    Assert-WorkspaceTest -Condition ((Get-TestSddl -Path $workspaceRoot) -ceq $workspaceRootSddlBefore) -Message 'per-execution ACL application leaves the shared workspace root ACL unchanged'

    $rulesA = @(Get-TestAccessRules -Path $txA.WorkspacePath)
    $rulesB = @(Get-TestAccessRules -Path $txB.WorkspacePath)
    $idsA = @($rulesA | ForEach-Object { $_.IdentityReference.Value } | Sort-Object)
    $idsB = @($rulesB | ForEach-Object { $_.IdentityReference.Value } | Sort-Object)
    Assert-WorkspaceTest -Condition ($idsA.Count -eq 3 -and $idsA -contains $supervisorSid -and $idsA -contains $executionSidA -and $idsA -contains $systemSid -and $idsA -notcontains $executionSidB) -Message 'execution A DACL contains only supervisor, execution A and SYSTEM'
    Assert-WorkspaceTest -Condition ($idsB.Count -eq 3 -and $idsB -contains $supervisorSid -and $idsB -contains $executionSidB -and $idsB -contains $systemSid -and $idsB -notcontains $executionSidA) -Message 'execution B DACL contains only supervisor, execution B and SYSTEM'
    $minimalWorkspaceRights = Get-SharnouExecutionWorkspaceRights
    $executionRuleA = @($rulesA | Where-Object { $_.IdentityReference.Value -ceq $executionSidA })
    $executionRuleB = @($rulesB | Where-Object { $_.IdentityReference.Value -ceq $executionSidB })
    Assert-WorkspaceTest -Condition ($executionRuleA.Count -eq 1 -and $executionRuleA[0].FileSystemRights -eq $minimalWorkspaceRights -and $executionRuleA[0].FileSystemRights -ne [System.Security.AccessControl.FileSystemRights]::FullControl) -Message 'execution A receives the exact non-FullControl scratch-workspace rights mask'
    Assert-WorkspaceTest -Condition ($executionRuleB.Count -eq 1 -and $executionRuleB[0].FileSystemRights -eq $minimalWorkspaceRights -and $executionRuleB[0].FileSystemRights -ne [System.Security.AccessControl.FileSystemRights]::FullControl) -Message 'execution B receives the exact non-FullControl scratch-workspace rights mask'
    Assert-WorkspaceTest -Condition (([System.IO.Directory]::GetAccessControl($txA.WorkspacePath, $sections)).AreAccessRulesProtected) -Message 'execution workspace disables inherited ACEs'
    [System.IO.File]::WriteAllText((Join-Path $txA.WorkspacePath 'a.txt'), 'A', [System.Text.Encoding]::ASCII)
    [System.IO.File]::WriteAllText((Join-Path $txB.WorkspacePath 'b.txt'), 'B', [System.Text.Encoding]::ASCII)

    $activeRecovery = Recover-SharnouExecutionWorkspaces -WorkspaceRoot $workspaceRoot -JournalRoot $journalRoot -SupervisorSid $supervisorSid
    Assert-WorkspaceTest -Condition ($activeRecovery.SkippedActive -eq 2 -and $activeRecovery.Failed -eq 0) -Message 'recovery skips two live executions while their exclusive leases are held'

    $doneA = Complete-SharnouExecutionWorkspace -Transaction $txA
    $doneB = Complete-SharnouExecutionWorkspace -Transaction $txB
    Assert-WorkspaceTest -Condition ($doneA -eq 'DELETED' -and $doneB -eq 'DELETED') -Message 'normal completion restores original DACLs before removing workspaces'
    Assert-WorkspaceTest -Condition (-not (Test-Path -LiteralPath $txA.WorkspacePath) -and -not (Test-Path -LiteralPath $txB.WorkspacePath)) -Message 'normal completion removes both execution trees'
    Assert-WorkspaceTest -Condition ((Get-TestSddl -Path $workspaceRoot) -ceq $workspaceRootSddlBefore) -Message 'normal rollback preserves shared workspace-root ACL byte-for-byte'
    $emptyRecovery = Recover-SharnouExecutionWorkspaces -WorkspaceRoot $workspaceRoot -JournalRoot $journalRoot -SupervisorSid $supervisorSid
    Assert-WorkspaceTest -Condition ($emptyRecovery.Recovered -eq 0 -and $emptyRecovery.Failed -eq 0 -and $emptyRecovery.SkippedActive -eq 0) -Message 'recovery is idempotent after successful completion'

    # A crash after mkdir but before the original SDDL is journaled must only
    # delete the still-empty, never-exposed execution directory.
    $markerPrep = Join-Path $base 'crash-after-workspace-created.marker'
    Wait-ForCrashMarker -Phase 'AfterWorkspaceCreated' -WorkspacePath $workspaceRoot -JournalPath $journalRoot -ExecutionSid $executionSidA -MarkerPath $markerPrep
    $preparingJournals = @(Get-ChildItem -LiteralPath $journalRoot -Filter '*.json' -File)
    $preparingRecord = Get-Content -LiteralPath $preparingJournals[0].FullName -Raw | ConvertFrom-Json
    Assert-WorkspaceTest -Condition ($preparingJournals.Count -eq 1 -and $preparingRecord.state -eq 'PREPARING' -and [string]::IsNullOrEmpty($preparingRecord.originalSddl)) -Message 'PREPARING intent precedes directory creation and descriptor capture'
    $preparingRecovery = Recover-SharnouExecutionWorkspaces -WorkspaceRoot $workspaceRoot -JournalRoot $journalRoot -SupervisorSid $supervisorSid
    Assert-WorkspaceTest -Condition ($preparingRecovery.Recovered -eq 1 -and $preparingRecovery.Deleted -eq 1 -and -not (Test-Path -LiteralPath $preparingRecord.workspacePath)) -Message 'recovery safely removes an empty directory created before descriptor capture'

    # Abrupt worker death after applying the execution DACL, before ACTIVE is committed.
    $marker1 = Join-Path $base 'crash-after-acl.marker'
    Wait-ForCrashMarker -Phase 'AfterAclApplied' -WorkspacePath $workspaceRoot -JournalPath $journalRoot -ExecutionSid $executionSidA -MarkerPath $marker1
    $pendingJournal = @(Get-ChildItem -LiteralPath $journalRoot -Filter '*.json' -File)
    Assert-WorkspaceTest -Condition ($pendingJournal.Count -eq 1) -Message 'crash leaves one durable rollback journal'
    $pendingRecord = Get-Content -LiteralPath $pendingJournal[0].FullName -Raw | ConvertFrom-Json
    Assert-WorkspaceTest -Condition ($pendingRecord.state -eq 'ACL_PENDING' -and -not [string]::IsNullOrWhiteSpace($pendingRecord.originalSddl)) -Message 'journal records original SDDL before restrictive ACL mutation'
    $expectedOriginal = [string]$pendingRecord.originalSddl
    $pendingWorkspace = [string]$pendingRecord.workspacePath
    $crashRecovery = Recover-SharnouExecutionWorkspaces -WorkspaceRoot $workspaceRoot -JournalRoot $journalRoot -SupervisorSid $supervisorSid -KeepRestoredWorkspaces
    Assert-WorkspaceTest -Condition ($crashRecovery.Recovered -eq 1 -and $crashRecovery.Failed -eq 0 -and (Test-Path -LiteralPath $pendingWorkspace)) -Message 'crash recovery restores ACL and can retain the directory for inspection'
    Assert-WorkspaceTest -Condition ((Get-TestSddl -Path $pendingWorkspace) -ceq $expectedOriginal) -Message 'crash recovery restores the exact pre-execution owner/group/DACL descriptor'
    $restoredJournalObject = Get-Content -LiteralPath $pendingJournal[0].FullName -Raw | ConvertFrom-Json
    Assert-WorkspaceTest -Condition ($restoredJournalObject.version -eq 1 -and $restoredJournalObject.state -eq 'RESTORED' -and $restoredJournalObject.id -eq $pendingRecord.id -and $restoredJournalObject.workspacePath -eq $pendingRecord.workspacePath) -Message 'recovery preserves the versioned lowercase journal wire schema for repeated restarts'
    $finishRecovery = Recover-SharnouExecutionWorkspaces -WorkspaceRoot $workspaceRoot -JournalRoot $journalRoot -SupervisorSid $supervisorSid
    $finishRecoveryJson = ConvertTo-Json -InputObject $finishRecovery -Depth 5 -Compress
    Write-Host ("DEBUG second recovery: " + $finishRecoveryJson)
    Write-Host ("DEBUG pending workspace exists: " + (Test-Path -LiteralPath $pendingWorkspace))
    Write-Host ("DEBUG pending journal exists: " + (Test-Path -LiteralPath $pendingJournal[0].FullName))
    Assert-WorkspaceTest -Condition ($finishRecovery.Recovered -eq 1 -and $finishRecovery.Deleted -eq 1 -and -not (Test-Path -LiteralPath $pendingWorkspace)) -Message ('second recovery safely deletes the restored workspace and finalizes the journal; result=' + $finishRecoveryJson)

    # Abrupt death during active execution, with nested data and a junction that
    # points outside the workspace. Recovery must unlink the junction, not traverse it.
    $activeMarker = Join-Path $base 'crash-active-work.marker'
    Wait-ForCrashMarker -Phase 'ActiveWork' -WorkspacePath $workspaceRoot -JournalPath $journalRoot -ExecutionSid $executionSidB -MarkerPath $activeMarker
    $activeWorkspace = [System.IO.File]::ReadAllText($activeMarker)
    $activeJournal = @(Get-ChildItem -LiteralPath $journalRoot -Filter '*.json' -File)
    if ($activeJournal.Count -ne 1) { throw 'Expected one active journal before backup recovery test.' }
    $simulatedBackup = $activeJournal[0].FullName + '.bak-' + [Guid]::NewGuid().ToString('N')
    Copy-Item -LiteralPath $activeJournal[0].FullName -Destination $simulatedBackup
    Assert-WorkspaceTest -Condition (Test-Path -LiteralPath $simulatedBackup -PathType Leaf) -Message 'simulated interrupted File.Replace leaves a uniquely named journal backup'
    Assert-WorkspaceTest -Condition (Test-Path -LiteralPath (Join-Path $activeWorkspace 'nested\payload.bin')) -Message 'active worker crash leaves test data for recovery'
    $activeRecovery = Recover-SharnouExecutionWorkspaces -WorkspaceRoot $workspaceRoot -JournalRoot $journalRoot -SupervisorSid $supervisorSid
    Assert-WorkspaceTest -Condition ($activeRecovery.Recovered -eq 1 -and $activeRecovery.Deleted -eq 1 -and -not (Test-Path -LiteralPath $activeWorkspace)) -Message 'crash recovery removes the entire per-execution tree'
    Assert-WorkspaceTest -Condition (Test-Path -LiteralPath $outsideSentinel -PathType Leaf) -Message 'recursive cleanup does not follow a nested external junction'

    # Crash while rollback is in progress, before the original descriptor is applied.
    $marker2 = Join-Path $base 'crash-after-restore-intent.marker'
    Wait-ForCrashMarker -Phase 'AfterRestoreIntent' -WorkspacePath $workspaceRoot -JournalPath $journalRoot -ExecutionSid $executionSidB -MarkerPath $marker2
    $restoring = @(Get-ChildItem -LiteralPath $journalRoot -Filter '*.json' -File)
    Assert-WorkspaceTest -Condition ($restoring.Count -eq 1 -and ((Get-Content -LiteralPath $restoring[0].FullName -Raw | ConvertFrom-Json).state -eq 'RESTORING')) -Message 'rollback intent is durable before ACL restoration starts'
    $rollbackRecovery = Recover-SharnouExecutionWorkspaces -WorkspaceRoot $workspaceRoot -JournalRoot $journalRoot -SupervisorSid $supervisorSid
    Assert-WorkspaceTest -Condition ($rollbackRecovery.Recovered -eq 1 -and $rollbackRecovery.Failed -eq 0) -Message 'recovery completes a rollback interrupted before Set-Acl'

    # Crash after ACL restoration but before committing RESTORED; replay must be safe.
    $marker3 = Join-Path $base 'crash-after-acl-restored.marker'
    Wait-ForCrashMarker -Phase 'AfterAclRestored' -WorkspacePath $workspaceRoot -JournalPath $journalRoot -ExecutionSid $executionSidA -MarkerPath $marker3
    $restoredCrash = @(Get-ChildItem -LiteralPath $journalRoot -Filter '*.json' -File)
    Assert-WorkspaceTest -Condition ($restoredCrash.Count -eq 1 -and ((Get-Content -LiteralPath $restoredCrash[0].FullName -Raw | ConvertFrom-Json).state -eq 'RESTORING')) -Message 'crash after Set-Acl leaves a replayable RESTORING journal'
    $restoreReplay = Recover-SharnouExecutionWorkspaces -WorkspaceRoot $workspaceRoot -JournalRoot $journalRoot -SupervisorSid $supervisorSid
    Assert-WorkspaceTest -Condition ($restoreReplay.Recovered -eq 1 -and $restoreReplay.Deleted -eq 1 -and $restoreReplay.Failed -eq 0) -Message 'replaying an already-restored descriptor is idempotent'

    # Crash after RESTORED is durable but before directory deletion. Replay must
    # safely re-apply the saved DACL and complete the final cleanup.
    $marker4 = Join-Path $base 'crash-after-restored-journal.marker'
    Wait-ForCrashMarker -Phase 'AfterRestoredJournal' -WorkspacePath $workspaceRoot -JournalPath $journalRoot -ExecutionSid $executionSidA -MarkerPath $marker4
    $restoredJournal = @(Get-ChildItem -LiteralPath $journalRoot -Filter '*.json' -File)
    Assert-WorkspaceTest -Condition ($restoredJournal.Count -eq 1 -and ((Get-Content -LiteralPath $restoredJournal[0].FullName -Raw | ConvertFrom-Json).state -eq 'RESTORED')) -Message 'RESTORED journal is durable before workspace deletion'
    $finalReplay = Recover-SharnouExecutionWorkspaces -WorkspaceRoot $workspaceRoot -JournalRoot $journalRoot -SupervisorSid $supervisorSid
    Assert-WorkspaceTest -Condition ($finalReplay.Recovered -eq 1 -and $finalReplay.Deleted -eq 1 -and $finalReplay.Failed -eq 0) -Message 'recovery finishes a crash after RESTORED commit'

    # Invalid records must never redirect cleanup outside the dedicated workspace root.
    $outsideId = [Guid]::NewGuid().ToString('N')
    $outsideJournal = New-FakeJournal -Id $outsideId -WorkspacePath $externalRoot
    $outsideRecovery = Recover-SharnouExecutionWorkspaces -WorkspaceRoot $workspaceRoot -JournalRoot $journalRoot -SupervisorSid $supervisorSid
    Assert-WorkspaceTest -Condition ($outsideRecovery.Failed -ge 1 -and (Test-Path -LiteralPath $outsideSentinel)) -Message 'tampered journal path cannot redirect recovery outside the workspace root'
    Remove-Item -LiteralPath $outsideJournal -Force
    Remove-Item -LiteralPath (Join-Path $journalRoot ($outsideId + '.lease')) -Force -ErrorAction SilentlyContinue

    $badJsonPath = Join-Path $journalRoot 'not-a-guid.json'
    [System.IO.File]::WriteAllText($badJsonPath, '{truncated-json', [System.Text.Encoding]::ASCII)
    $badJsonRecovery = Recover-SharnouExecutionWorkspaces -WorkspaceRoot $workspaceRoot -JournalRoot $journalRoot -SupervisorSid $supervisorSid
    Assert-WorkspaceTest -Condition ($badJsonRecovery.Failed -ge 1 -and (Test-Path -LiteralPath $badJsonPath)) -Message 'malformed journal is retained and fails closed'
    Remove-Item -LiteralPath $badJsonPath -Force

    # A directory junction at the execution slot is not followed or deleted as its target.
    $junctionId = [Guid]::NewGuid().ToString('N')
    $junctionPath = Join-Path $workspaceRoot ('exec-' + $junctionId)
    $junctionJournal = New-FakeJournal -Id $junctionId -WorkspacePath $junctionPath
    New-Item -ItemType Junction -Path $junctionPath -Target $externalRoot | Out-Null
    $junctionRecovery = Recover-SharnouExecutionWorkspaces -WorkspaceRoot $workspaceRoot -JournalRoot $journalRoot -SupervisorSid $supervisorSid
    Assert-WorkspaceTest -Condition ($junctionRecovery.Failed -ge 1 -and (Test-Path -LiteralPath $outsideSentinel)) -Message 'reparse-point workspace slot is rejected without following the junction'
    [System.IO.Directory]::Delete($junctionPath, $false)
    Remove-Item -LiteralPath $junctionJournal -Force
    Remove-Item -LiteralPath (Join-Path $journalRoot ($junctionId + '.lease')) -Force -ErrorAction SilentlyContinue

    # Simulate the tiny crash window between temp-file creation and a journal commit.
    $orphanId = [Guid]::NewGuid().ToString('N')
    $orphanLease = Join-Path $journalRoot ($orphanId + '.lease')
    [System.IO.File]::WriteAllText($orphanLease, '', [System.Text.Encoding]::ASCII)
    $orphanTemp = Join-Path $journalRoot ($orphanId + '.json.tmp-' + [Guid]::NewGuid().ToString('N'))
    [System.IO.File]::WriteAllText($orphanTemp, '{"partial":', [System.Text.Encoding]::ASCII)
    $orphanRecovery = Recover-SharnouExecutionWorkspaces -WorkspaceRoot $workspaceRoot -JournalRoot $journalRoot -SupervisorSid $supervisorSid
    Assert-WorkspaceTest -Condition (-not (Test-Path -LiteralPath $orphanLease) -and -not (Test-Path -LiteralPath $orphanTemp)) -Message 'orphan atomic-write temp and lease artifacts are reclaimed safely'

    Assert-WorkspaceTest -Condition ((Get-TestSddl -Path $workspaceRoot) -ceq $workspaceRootSddlBefore) -Message 'all success, failure and recovery paths preserve the shared workspace-root ACL'
    $finalJournals = @(Get-ChildItem -LiteralPath $journalRoot -Filter '*.json' -File)
    $finalLeases = @(Get-ChildItem -LiteralPath $journalRoot -Filter '*.lease' -File)
    $finalTemps = @(Get-ChildItem -LiteralPath $journalRoot -Filter '*.json.tmp-*' -File)
    $finalBackups = @(Get-ChildItem -LiteralPath $journalRoot -Filter '*.json.bak-*' -File)
    Assert-WorkspaceTest -Condition ($finalJournals.Count -eq 0 -and $finalLeases.Count -eq 0 -and $finalTemps.Count -eq 0 -and $finalBackups.Count -eq 0) -Message 'successful recovery leaves no journal, lease, temporary-file or backup residue'

    Write-Host ("Workspace transaction suite: {0} passed, {1} failed, {2} total." -f $script:Passed, $script:Failed, ($script:Passed + $script:Failed)) -ForegroundColor Green
    Write-Host 'DevAgent workspace security result: PASS' -ForegroundColor Green
}
catch {
    Write-Host ("DevAgent workspace security result: FAIL - {0}" -f $_.Exception.Message) -ForegroundColor Red
    throw
}
finally {
    if (Test-Path -LiteralPath $base) {
        # Remove all test content only after recovery tests; remove junctions as links.
        $link = Join-Path $workspaceRoot ('exec-' + $junctionId)
        if ($junctionId -and (Test-Path -LiteralPath $link)) {
            try { [System.IO.Directory]::Delete($link, $false) } catch {}
        }
        Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
    }
}
