# SharnouDevAgent per-execution workspace transaction manager.
# Windows PowerShell 5.1 / .NET Framework only. No external modules or tools.
# This is a security-testable workspace/ACL transaction component; it does not
# create restricted tokens or AppContainer processes and is not a process sandbox.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:SharnouSecuritySections = [System.Security.AccessControl.AccessControlSections]::Owner -bor [System.Security.AccessControl.AccessControlSections]::Group -bor [System.Security.AccessControl.AccessControlSections]::Access
$script:SharnouSystemSid = 'S-1-5-18'

function ConvertTo-SharnouCanonicalLocalPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Path is empty.' }
    if ($Path -notmatch '^[A-Za-z]:\\') { throw 'Workspace roots must be absolute local drive paths; relative paths are not permitted.' }
    if ($Path.StartsWith('\\') -or $Path.StartsWith('\??\') -or $Path.StartsWith('\Device\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'UNC, device and NT namespace paths are not permitted.'
    }
    if ($Path -match '^[\\/]{2}' -or $Path.StartsWith('\\?\') -or $Path.StartsWith('\\.\')) {
        throw 'UNC and device paths are not permitted.'
    }

    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full -notmatch '^[A-Za-z]:\\') { throw 'Only canonical local drive paths are permitted.' }
    if ($full.IndexOf(':', 2) -ge 0) { throw 'Alternate data stream syntax is not permitted.' }

    $driveRoot = [System.IO.Path]::GetPathRoot($full)
    $trimmed = $full.TrimEnd([char]'\')
    if ($trimmed.Length -lt $driveRoot.Length) { return $driveRoot }
    return $trimmed
}

function Test-SharnouPathWithin {
    param([string]$Root, [string]$Candidate)
    $prefix = $Root.TrimEnd([char]'\') + '\'
    return $Candidate.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

function Assert-SharnouNoReparseAncestors {
    param([Parameter(Mandatory = $true)][string]$Path)

    $full = ConvertTo-SharnouCanonicalLocalPath -Path $Path
    $driveRoot = [System.IO.Path]::GetPathRoot($full)
    $relative = $full.Substring($driveRoot.Length)
    $current = $driveRoot

    if ((Test-Path -LiteralPath $current) -and ((Get-Item -LiteralPath $current -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
        throw "Reparse-point drive root is not permitted: $current"
    }

    foreach ($component in $relative.Split([char]'\')) {
        if ([string]::IsNullOrEmpty($component)) { continue }
        $current = [System.IO.Path]::Combine($current, $component)
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Reparse point in protected path: $current"
            }
        }
    }
}

function Get-SharnouDirectorySddl {
    param([Parameter(Mandatory = $true)][string]$Path)
    $security = [System.IO.Directory]::GetAccessControl($Path, $script:SharnouSecuritySections)
    return $security.GetSecurityDescriptorSddlForm($script:SharnouSecuritySections)
}

function Set-SharnouDirectorySddl {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Sddl
    )
    if ([string]::IsNullOrWhiteSpace($Sddl) -or $Sddl.Length -gt 16384) {
        throw 'The journal does not contain a bounded original security descriptor.'
    }
    # Owner and group are deliberately never changed by this transaction.
    # Restore only the DACL so rollback does not require WRITE_OWNER or elevated
    # privileges; then the caller verifies the complete owner/group/DACL SDDL.
    $security = [System.IO.Directory]::GetAccessControl($Path, $script:SharnouSecuritySections)
    $security.SetSecurityDescriptorSddlForm($Sddl, [System.Security.AccessControl.AccessControlSections]::Access)
    [System.IO.Directory]::SetAccessControl($Path, $security)
}

function Set-SharnouProtectedDirectoryAcl {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$AllowedSids
    )

    $security = [System.IO.Directory]::GetAccessControl($Path, [System.Security.AccessControl.AccessControlSections]::Access)
    # Preserve owner/group exactly; only replace the DACL. Protecting the DACL
    # first removes inherited ACEs, then every remaining explicit ACE is removed.
    $security.SetAccessRuleProtection($true, $false)
    $existingRules = $security.GetAccessRules($true, $false, [System.Security.Principal.SecurityIdentifier])
    foreach ($existingRule in @($existingRules)) {
        [void]$security.RemoveAccessRuleSpecific($existingRule)
    }

    $inheritance = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
    foreach ($sidText in @($AllowedSids | Select-Object -Unique)) {
        $sid = New-Object System.Security.Principal.SecurityIdentifier($sidText)
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $sid,
            [System.Security.AccessControl.FileSystemRights]::FullControl,
            $inheritance,
            [System.Security.AccessControl.PropagationFlags]::None,
            [System.Security.AccessControl.AccessControlType]::Allow
        )
        [void]$security.AddAccessRule($rule)
    }

    [System.IO.Directory]::SetAccessControl($Path, $security)
    Assert-SharnouProtectedDirectoryAcl -Path $Path -AllowedSids $AllowedSids
}

function Assert-SharnouProtectedDirectoryAcl {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$AllowedSids
    )

    $security = [System.IO.Directory]::GetAccessControl($Path, $script:SharnouSecuritySections)
    if (-not $security.AreAccessRulesProtected) { throw "DACL inheritance is not protected: $Path" }

    $rules = $security.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])
    $expected = @($AllowedSids | Select-Object -Unique | Sort-Object)
    if ($rules.Count -ne $expected.Count) {
        throw "Unexpected ACE count for protected directory '$Path': expected=$($expected.Count) actual=$($rules.Count)"
    }

    $actual = New-Object 'System.Collections.Generic.List[string]'
    foreach ($rule in $rules) {
        $sid = $rule.IdentityReference.Value
        $actual.Add($sid)
        if ($rule.IsInherited) { throw "Inherited ACE remains on protected directory: $Path" }
        if ($rule.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow) {
            throw "Unexpected deny ACE on protected directory: $Path"
        }
        if ($rule.FileSystemRights -ne [System.Security.AccessControl.FileSystemRights]::FullControl) {
            throw "Unexpected rights on protected directory for SID $sid"
        }
        $expectedInheritance = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
        if ($rule.InheritanceFlags -ne $expectedInheritance -or $rule.PropagationFlags -ne [System.Security.AccessControl.PropagationFlags]::None) {
            throw "Unexpected ACE inheritance on protected directory for SID $sid"
        }
    }

    $actualSorted = @($actual.ToArray() | Sort-Object)
    if (($actualSorted -join '|') -cne ($expected -join '|')) {
        throw "Protected directory DACL identities do not match the allowlist: $Path"
    }
}

function Initialize-SharnouWorkspaceSecurityRoots {
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][string]$JournalRoot,
        [Parameter(Mandatory = $true)][string]$SupervisorSid
    )

    $workspace = ConvertTo-SharnouCanonicalLocalPath -Path $WorkspaceRoot
    $journal = ConvertTo-SharnouCanonicalLocalPath -Path $JournalRoot
    if ($workspace -ieq $journal -or (Test-SharnouPathWithin -Root $workspace -Candidate $journal) -or (Test-SharnouPathWithin -Root $journal -Candidate $workspace)) {
        throw 'WorkspaceRoot and JournalRoot must be disjoint directories.'
    }
    foreach ($root in @($workspace, $journal)) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw "Security root does not exist: $root" }
        Assert-SharnouNoReparseAncestors -Path $root
    }

    $supervisor = New-Object System.Security.Principal.SecurityIdentifier($SupervisorSid)
    $allowed = @($supervisor.Value, $script:SharnouSystemSid)
    # The dedicated execution root must already be private. Validate it without
    # changing its ACL so per-run transactions never mutate the shared parent.
    Assert-SharnouProtectedDirectoryAcl -Path $workspace -AllowedSids $allowed
    Set-SharnouProtectedDirectoryAcl -Path $journal -AllowedSids $allowed

    return [pscustomobject]@{
        WorkspaceRoot = $workspace
        JournalRoot = $journal
        SupervisorSid = $supervisor.Value
    }
}

function Write-SharnouWorkspaceJournal {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Record
    )

    $json = ConvertTo-Json -InputObject $Record -Depth 6
    $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($json)
    if ($bytes.Length -gt 65536) { throw 'Workspace journal record exceeds the 64 KiB policy limit.' }
    $temp = $Path + '.tmp-' + [Guid]::NewGuid().ToString('N')
    $stream = $null
    try {
        $stream = [System.IO.File]::Open($temp, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
        $stream.Dispose()
        $stream = $null

        if ([System.IO.File]::Exists($Path)) {
            [System.IO.File]::Replace($temp, $Path, $null)
        }
        else {
            [System.IO.File]::Move($temp, $Path)
        }
    }
    finally {
        if ($null -ne $stream) { $stream.Dispose() }
        if ([System.IO.File]::Exists($temp)) { [System.IO.File]::Delete($temp) }
    }
}

function Invoke-SharnouWorkspaceTestPause {
    param(
        [bool]$Enabled,
        [string]$PauseAfterPhase,
        [string]$Phase,
        [string]$MarkerPath
    )

    if ($Enabled -and -not [string]::IsNullOrEmpty($PauseAfterPhase) -and $PauseAfterPhase -ceq $Phase) {
        if ([string]::IsNullOrWhiteSpace($MarkerPath)) { throw 'A marker path is required for a test pause.' }
        [System.IO.File]::WriteAllText($MarkerPath, $Phase, [System.Text.Encoding]::ASCII)
        while ($true) { Start-Sleep -Seconds 1 }
    }
}

function Get-SharnouWorkspaceLeasePath {
    param([string]$JournalRoot, [string]$Id)
    return Join-Path $JournalRoot ($Id + '.lease')
}

function Get-SharnouWorkspaceJournalPath {
    param([string]$JournalRoot, [string]$Id)
    return Join-Path $JournalRoot ($Id + '.json')
}

function Assert-SharnouJournalRecord {
    param(
        [Parameter(Mandatory = $true)][object]$Record,
        [Parameter(Mandatory = $true)][string]$JournalPath,
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][string]$JournalRoot,
        [Parameter(Mandatory = $true)][string]$SupervisorSid
    )

    if ([int]$Record.version -ne 1) { throw 'Unsupported workspace journal version.' }
    $id = [Guid]::ParseExact([string]$Record.id, 'N')
    $expectedJournal = Get-SharnouWorkspaceJournalPath -JournalRoot $JournalRoot -Id $id.ToString('N')
    $actualJournal = ConvertTo-SharnouCanonicalLocalPath -Path $JournalPath
    if ($actualJournal -ine (ConvertTo-SharnouCanonicalLocalPath -Path $expectedJournal)) { throw 'Journal filename does not match its execution ID.' }

    $expectedWorkspace = Join-Path $WorkspaceRoot ('exec-' + $id.ToString('N'))
    $actualWorkspace = ConvertTo-SharnouCanonicalLocalPath -Path ([string]$Record.workspacePath)
    if ($actualWorkspace -ine (ConvertTo-SharnouCanonicalLocalPath -Path $expectedWorkspace)) {
        throw 'Journal workspace path escapes its canonical execution slot.'
    }
    if ([string]$Record.supervisorSid -cne $SupervisorSid) { throw 'Journal supervisor SID does not match the current broker identity.' }

    $executionSid = New-Object System.Security.Principal.SecurityIdentifier([string]$Record.executionSid)
    if ($executionSid.Value -notmatch '^S-1-15-2-') { throw 'Execution SID must be an AppContainer package SID.' }
    if ($executionSid.Value -ceq $SupervisorSid -or $executionSid.Value -ceq $script:SharnouSystemSid) {
        throw 'Execution SID must be distinct from broker and SYSTEM identities.'
    }

    $validStates = @('PREPARING', 'ACL_PENDING', 'ACTIVE', 'RESTORING', 'RESTORED')
    if ($validStates -cnotcontains [string]$Record.state) { throw 'Unknown workspace transaction state.' }
    $sddl = [string]$Record.originalSddl
    if ($sddl.Length -gt 16384) { throw 'Original security descriptor exceeds the journal limit.' }
    if ([string]$Record.state -ne 'PREPARING' -and [string]::IsNullOrWhiteSpace($sddl)) {
        throw 'A rollback-capable transaction state has no original security descriptor.'
    }

    return [pscustomobject]@{
        Id = $id.ToString('N')
        State = [string]$Record.state
        WorkspacePath = $actualWorkspace
        JournalPath = $actualJournal
        ExecutionSid = $executionSid.Value
        SupervisorSid = $SupervisorSid
        OriginalSddl = $sddl
        CreatedUtc = [string]$Record.createdUtc
        UpdatedUtc = [string]$Record.updatedUtc
    }
}

function Assert-SharnouWorkspaceSlot {
    param([string]$WorkspaceRoot, [string]$WorkspacePath)
    $canonical = ConvertTo-SharnouCanonicalLocalPath -Path $WorkspacePath
    if (-not (Test-SharnouPathWithin -Root $WorkspaceRoot -Candidate $canonical)) {
        throw 'Workspace path is not a child of the dedicated execution root.'
    }
    $leaf = [System.IO.Path]::GetFileName($canonical)
    if ($leaf -notmatch '^exec-[0-9a-f]{32}$') { throw 'Workspace directory name is not a generated execution ID.' }
    Assert-SharnouNoReparseAncestors -Path $canonical
}

function Remove-SharnouWorkspaceTree {
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][string]$WorkspacePath
    )

    Assert-SharnouWorkspaceSlot -WorkspaceRoot $WorkspaceRoot -WorkspacePath $WorkspacePath
    if (-not (Test-Path -LiteralPath $WorkspacePath -PathType Container)) { return }

    # Explicit iterative deletion; never recursively traverse a reparse point.
    $stack = New-Object 'System.Collections.Generic.Stack[object]'
    $stack.Push([pscustomobject]@{ Path = $WorkspacePath; Visited = $false })
    while ($stack.Count -gt 0) {
        $node = $stack.Pop()
        $dir = [string]$node.Path
        if (-not $node.Visited) {
            $canonicalDir = ConvertTo-SharnouCanonicalLocalPath -Path $dir
            if (-not (Test-SharnouPathWithin -Root $WorkspaceRoot -Candidate $canonicalDir) -and $canonicalDir -ine $WorkspaceRoot) {
                throw 'Nested workspace directory escaped the execution root.'
            }
            Assert-SharnouNoReparseAncestors -Path $canonicalDir
            $stack.Push([pscustomobject]@{ Path = $dir; Visited = $true })
            foreach ($entry in [System.IO.Directory]::GetFileSystemEntries($dir)) {
                $entryFull = ConvertTo-SharnouCanonicalLocalPath -Path $entry
                if (-not (Test-SharnouPathWithin -Root $WorkspacePath -Candidate $entryFull)) { throw 'Workspace entry escaped its execution root.' }
                $attributes = [System.IO.File]::GetAttributes($entryFull)
                if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                    if (($attributes -band [System.IO.FileAttributes]::Directory) -ne 0) {
                        [System.IO.Directory]::Delete($entryFull, $false)
                    }
                    else {
                        [System.IO.File]::Delete($entryFull)
                    }
                }
                elseif (($attributes -band [System.IO.FileAttributes]::Directory) -ne 0) {
                    $stack.Push([pscustomobject]@{ Path = $entryFull; Visited = $false })
                }
                else {
                    [System.IO.File]::Delete($entryFull)
                }
            }
        }
        else {
            [System.IO.Directory]::Delete($dir, $false)
        }
    }
}

function Invoke-SharnouWorkspaceRollback {
    param(
        [Parameter(Mandatory = $true)][object]$Record,
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][string]$JournalPath,
        [Parameter(Mandatory = $true)][System.IO.FileStream]$LeaseStream,
        [switch]$KeepRestoredWorkspace,
        [bool]$EnableTestHooks = $false,
        [string]$PauseAfterPhase = '',
        [string]$MarkerPath = ''
    )

    Assert-SharnouWorkspaceSlot -WorkspaceRoot $WorkspaceRoot -WorkspacePath $Record.WorkspacePath
    if (Test-Path -LiteralPath $Record.WorkspacePath -PathType Container) {
        if ([string]::IsNullOrWhiteSpace([string]$Record.OriginalSddl)) {
            $entries = [System.IO.Directory]::GetFileSystemEntries([string]$Record.WorkspacePath)
            if ($entries.Count -ne 0) {
                throw 'A PREPARING workspace without a saved descriptor is not empty; refusing destructive recovery.'
            }
        }
        else {
            $Record.State = 'RESTORING'
            $Record.UpdatedUtc = [DateTime]::UtcNow.ToString('o')
            Write-SharnouWorkspaceJournal -Path $JournalPath -Record $Record
            Invoke-SharnouWorkspaceTestPause -Enabled $EnableTestHooks -PauseAfterPhase $PauseAfterPhase -Phase 'AfterRestoreIntent' -MarkerPath $MarkerPath

            Set-SharnouDirectorySddl -Path $Record.WorkspacePath -Sddl $Record.OriginalSddl
            $restoredSddl = Get-SharnouDirectorySddl -Path $Record.WorkspacePath
            if ($restoredSddl -cne $Record.OriginalSddl) {
                throw 'Restored workspace security descriptor does not match the durable original SDDL.'
            }
            Invoke-SharnouWorkspaceTestPause -Enabled $EnableTestHooks -PauseAfterPhase $PauseAfterPhase -Phase 'AfterAclRestored' -MarkerPath $MarkerPath

            $Record.State = 'RESTORED'
            $Record.UpdatedUtc = [DateTime]::UtcNow.ToString('o')
            Write-SharnouWorkspaceJournal -Path $JournalPath -Record $Record
            Invoke-SharnouWorkspaceTestPause -Enabled $EnableTestHooks -PauseAfterPhase $PauseAfterPhase -Phase 'AfterRestoredJournal' -MarkerPath $MarkerPath
        }

        if ($KeepRestoredWorkspace) {
            $leasePath = Get-SharnouWorkspaceLeasePath -JournalRoot (Split-Path -Parent $JournalPath) -Id $Record.Id
            $LeaseStream.Dispose()
            return 'RESTORED'
        }
        Remove-SharnouWorkspaceTree -WorkspaceRoot $WorkspaceRoot -WorkspacePath $Record.WorkspacePath
    }

    if ([System.IO.File]::Exists($JournalPath)) { [System.IO.File]::Delete($JournalPath) }
    $leasePath = Get-SharnouWorkspaceLeasePath -JournalRoot (Split-Path -Parent $JournalPath) -Id $Record.Id
    $LeaseStream.Dispose()
    if ([System.IO.File]::Exists($leasePath)) { [System.IO.File]::Delete($leasePath) }
    return 'DELETED'
}

function New-SharnouExecutionWorkspace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][string]$JournalRoot,
        [Parameter(Mandatory = $true)][string]$ExecutionSid,
        [string]$SupervisorSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value,
        [switch]$EnableTestHooks,
        [string]$PauseAfterPhase = '',
        [string]$MarkerPath = ''
    )

    $roots = Initialize-SharnouWorkspaceSecurityRoots -WorkspaceRoot $WorkspaceRoot -JournalRoot $JournalRoot -SupervisorSid $SupervisorSid
    $execution = New-Object System.Security.Principal.SecurityIdentifier($ExecutionSid)
    if ($execution.Value -notmatch '^S-1-15-2-') { throw 'Execution SID must be an AppContainer package SID.' }
    if ($execution.Value -ceq $roots.SupervisorSid -or $execution.Value -ceq $script:SharnouSystemSid) {
        throw 'Execution SID must be distinct from supervisor and SYSTEM.'
    }

    $id = [Guid]::NewGuid().ToString('N')
    $workspacePath = Join-Path $roots.WorkspaceRoot ('exec-' + $id)
    $journalPath = Get-SharnouWorkspaceJournalPath -JournalRoot $roots.JournalRoot -Id $id
    $leasePath = Get-SharnouWorkspaceLeasePath -JournalRoot $roots.JournalRoot -Id $id
    $lease = $null
    $record = [pscustomobject]@{
        version = 1
        id = $id
        state = 'PREPARING'
        workspacePath = $workspacePath
        executionSid = $execution.Value
        supervisorSid = $roots.SupervisorSid
        originalSddl = ''
        createdUtc = [DateTime]::UtcNow.ToString('o')
        updatedUtc = [DateTime]::UtcNow.ToString('o')
    }

    try {
        $lease = [System.IO.File]::Open($leasePath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $lease.Flush($true)
        Write-SharnouWorkspaceJournal -Path $journalPath -Record $record
        Invoke-SharnouWorkspaceTestPause -Enabled ([bool]$EnableTestHooks) -PauseAfterPhase $PauseAfterPhase -Phase 'AfterPrepared' -MarkerPath $MarkerPath

        [void][System.IO.Directory]::CreateDirectory($workspacePath)
        Assert-SharnouWorkspaceSlot -WorkspaceRoot $roots.WorkspaceRoot -WorkspacePath $workspacePath
        Invoke-SharnouWorkspaceTestPause -Enabled ([bool]$EnableTestHooks) -PauseAfterPhase $PauseAfterPhase -Phase 'AfterWorkspaceCreated' -MarkerPath $MarkerPath

        $record.originalSddl = Get-SharnouDirectorySddl -Path $workspacePath
        if ([string]::IsNullOrWhiteSpace($record.originalSddl) -or $record.originalSddl.Length -gt 16384) {
            throw 'Could not capture a bounded original workspace security descriptor.'
        }
        $record.state = 'ACL_PENDING'
        $record.updatedUtc = [DateTime]::UtcNow.ToString('o')
        Write-SharnouWorkspaceJournal -Path $journalPath -Record $record
        Invoke-SharnouWorkspaceTestPause -Enabled ([bool]$EnableTestHooks) -PauseAfterPhase $PauseAfterPhase -Phase 'AfterAclPending' -MarkerPath $MarkerPath

        $allowed = @($roots.SupervisorSid, $execution.Value, $script:SharnouSystemSid)
        Set-SharnouProtectedDirectoryAcl -Path $workspacePath -AllowedSids $allowed
        Invoke-SharnouWorkspaceTestPause -Enabled ([bool]$EnableTestHooks) -PauseAfterPhase $PauseAfterPhase -Phase 'AfterAclApplied' -MarkerPath $MarkerPath

        $record.state = 'ACTIVE'
        $record.updatedUtc = [DateTime]::UtcNow.ToString('o')
        Write-SharnouWorkspaceJournal -Path $journalPath -Record $record
        Invoke-SharnouWorkspaceTestPause -Enabled ([bool]$EnableTestHooks) -PauseAfterPhase $PauseAfterPhase -Phase 'AfterActive' -MarkerPath $MarkerPath

        return [pscustomobject]@{
            Id = $id
            WorkspacePath = $workspacePath
            JournalPath = $journalPath
            LeasePath = $leasePath
            LeaseStream = $lease
            ExecutionSid = $execution.Value
            SupervisorSid = $roots.SupervisorSid
            OriginalSddl = $record.originalSddl
            State = 'ACTIVE'
        }
    }
    catch {
        $primaryError = $_
        if ($null -ne $lease) {
            if (Test-Path -LiteralPath $journalPath -PathType Leaf) {
                try {
                    $normalized = [pscustomobject]@{
                        Id = $id
                        State = [string]$record.state
                        WorkspacePath = $workspacePath
                        JournalPath = $journalPath
                        ExecutionSid = $execution.Value
                        SupervisorSid = $roots.SupervisorSid
                        OriginalSddl = [string]$record.originalSddl
                        CreatedUtc = [string]$record.createdUtc
                        UpdatedUtc = [string]$record.updatedUtc
                    }
                    [void](Invoke-SharnouWorkspaceRollback -Record $normalized -WorkspaceRoot $roots.WorkspaceRoot -JournalPath $journalPath -LeaseStream $lease)
                    $lease = $null
                }
                catch {
                    if ($null -ne $lease) { $lease.Dispose(); $lease = $null }
                    throw ("Workspace creation failed and automatic rollback remains journaled: {0}; rollback: {1}" -f $primaryError.Exception.Message, $_.Exception.Message)
                }
            }
            else {
                $lease.Dispose()
                $lease = $null
                if ([System.IO.File]::Exists($leasePath)) { [System.IO.File]::Delete($leasePath) }
            }
        }
        throw $primaryError
    }
}

function Complete-SharnouExecutionWorkspace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Transaction,
        [switch]$KeepRestoredWorkspace,
        [switch]$EnableTestHooks,
        [string]$PauseAfterPhase = '',
        [string]$MarkerPath = ''
    )

    if ($null -eq $Transaction.LeaseStream -or $Transaction.LeaseStream.SafeFileHandle.IsClosed) {
        throw 'Execution workspace lease is not held by this transaction.'
    }
    $roots = Initialize-SharnouWorkspaceSecurityRoots -WorkspaceRoot (Split-Path -Parent $Transaction.WorkspacePath) -JournalRoot (Split-Path -Parent $Transaction.JournalPath) -SupervisorSid $Transaction.SupervisorSid

    $recordObject = Get-Content -LiteralPath $Transaction.JournalPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $record = Assert-SharnouJournalRecord -Record $recordObject -JournalPath $Transaction.JournalPath -WorkspaceRoot $roots.WorkspaceRoot -JournalRoot $roots.JournalRoot -SupervisorSid $roots.SupervisorSid
    $result = Invoke-SharnouWorkspaceRollback -Record $record -WorkspaceRoot $roots.WorkspaceRoot -JournalPath $Transaction.JournalPath -LeaseStream $Transaction.LeaseStream -KeepRestoredWorkspace:$KeepRestoredWorkspace -EnableTestHooks:([bool]$EnableTestHooks) -PauseAfterPhase $PauseAfterPhase -MarkerPath $MarkerPath
    $Transaction.LeaseStream = $null
    $Transaction.State = $result
    return $result
}

function Recover-SharnouExecutionWorkspaces {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][string]$JournalRoot,
        [string]$SupervisorSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value,
        [switch]$KeepRestoredWorkspaces
    )

    $roots = Initialize-SharnouWorkspaceSecurityRoots -WorkspaceRoot $WorkspaceRoot -JournalRoot $JournalRoot -SupervisorSid $SupervisorSid
    $recovered = 0
    $deleted = 0
    $skippedActive = 0
    $failed = 0
    $errors = New-Object 'System.Collections.Generic.List[string]'

    foreach ($journalPath in [System.IO.Directory]::GetFiles($roots.JournalRoot, '*.json')) {
        $lease = $null
        try {
            $fileItem = Get-Item -LiteralPath $journalPath -Force
            if (($fileItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Journal file is a reparse point.' }

            if ((Get-Item -LiteralPath $journalPath -Force).Length -gt 65536) { throw 'Workspace journal exceeds the 64 KiB policy limit.' }
            $raw = Get-Content -LiteralPath $journalPath -Raw -Encoding UTF8
            $recordObject = ConvertFrom-Json -InputObject $raw
            if ($null -eq $recordObject) { throw 'Journal JSON is empty.' }

            # Validate the ID enough to open the matching exclusive lease; full schema
            # and path validation occurs after the lease is held.
            $id = [Guid]::ParseExact([string]$recordObject.id, 'N').ToString('N')
            $leasePath = Get-SharnouWorkspaceLeasePath -JournalRoot $roots.JournalRoot -Id $id
            try {
                $lease = [System.IO.File]::Open($leasePath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            }
            catch [System.IO.IOException] {
                $skippedActive++
                continue
            }

            # Re-read after acquiring the lease: a writer may have atomically
            # advanced the journal between the initial ID probe and lock acquisition.
            if ((Get-Item -LiteralPath $journalPath -Force).Length -gt 65536) { throw 'Workspace journal exceeds the 64 KiB policy limit.' }
            $raw = Get-Content -LiteralPath $journalPath -Raw -Encoding UTF8
            $recordObject = ConvertFrom-Json -InputObject $raw
            $record = Assert-SharnouJournalRecord -Record $recordObject -JournalPath $journalPath -WorkspaceRoot $roots.WorkspaceRoot -JournalRoot $roots.JournalRoot -SupervisorSid $roots.SupervisorSid
            Assert-SharnouWorkspaceSlot -WorkspaceRoot $roots.WorkspaceRoot -WorkspacePath $record.WorkspacePath

            if (Test-Path -LiteralPath $record.WorkspacePath -PathType Container) {
                [void](Invoke-SharnouWorkspaceRollback -Record $record -WorkspaceRoot $roots.WorkspaceRoot -JournalPath $journalPath -LeaseStream $lease -KeepRestoredWorkspace:$KeepRestoredWorkspaces)
                $lease = $null
                $recovered++
                if (-not $KeepRestoredWorkspaces) { $deleted++ }
            }
            else {
                if ([System.IO.File]::Exists($journalPath)) { [System.IO.File]::Delete($journalPath) }
                $lease.Dispose()
                $lease = $null
                if ([System.IO.File]::Exists($leasePath)) { [System.IO.File]::Delete($leasePath) }
                $recovered++
                $deleted++
            }
        }
        catch {
            $failed++
            $errors.Add(("{0}: {1}" -f $journalPath, $_.Exception.Message))
        }
        finally {
            if ($null -ne $lease) { $lease.Dispose() }
        }
    }

    # A crash between exclusive lease creation and the first durable journal write
    # leaves no workspace; orphan leases are safe to reclaim after acquiring them.

    # Remove abandoned atomic-write temp files only while holding the execution
    # lease. A temp file with no committed journal can exist only before any
    # workspace is created, because PREPARING is committed before mkdir.
    foreach ($tempPath in [System.IO.Directory]::GetFiles($roots.JournalRoot, '*.json.tmp-*')) {
        $tempName = [System.IO.Path]::GetFileName($tempPath)
        if ($tempName -notmatch '^([0-9a-f]{32})\.json\.tmp-[0-9a-f]{32}$') {
            $failed++
            $errors.Add(("{0}: invalid atomic journal temp filename" -f $tempPath))
            continue
        }
        $tempId = $Matches[1]
        $tempLeasePath = Get-SharnouWorkspaceLeasePath -JournalRoot $roots.JournalRoot -Id $tempId
        $tempJournalPath = Get-SharnouWorkspaceJournalPath -JournalRoot $roots.JournalRoot -Id $tempId
        $tempLease = $null
        try {
            $tempLease = [System.IO.File]::Open($tempLeasePath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            if ([System.IO.File]::Exists($tempPath)) { [System.IO.File]::Delete($tempPath) }
            $tempLease.Dispose()
            $tempLease = $null
            if (-not [System.IO.File]::Exists($tempJournalPath) -and [System.IO.File]::Exists($tempLeasePath)) {
                [System.IO.File]::Delete($tempLeasePath)
            }
        }
        catch [System.IO.IOException] {
            $skippedActive++
        }
        catch {
            $failed++
            $errors.Add(("{0}: {1}" -f $tempPath, $_.Exception.Message))
        }
        finally {
            if ($null -ne $tempLease) { $tempLease.Dispose() }
        }
    }

    foreach ($leasePath in [System.IO.Directory]::GetFiles($roots.JournalRoot, '*.lease')) {
        $id = [System.IO.Path]::GetFileNameWithoutExtension($leasePath)
        $journalPath = Get-SharnouWorkspaceJournalPath -JournalRoot $roots.JournalRoot -Id $id
        if ([System.IO.File]::Exists($journalPath)) { continue }
        $orphanLease = $null
        try {
            $orphanLease = [System.IO.File]::Open($leasePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            $orphanLease.Dispose()
            $orphanLease = $null
            [System.IO.File]::Delete($leasePath)
        }
        catch [System.IO.IOException] {
            $skippedActive++
        }
        catch {
            $failed++
            $errors.Add(("{0}: {1}" -f $leasePath, $_.Exception.Message))
        }
        finally {
            if ($null -ne $orphanLease) { $orphanLease.Dispose() }
        }
    }

    return [pscustomobject]@{
        Recovered = $recovered
        Deleted = $deleted
        SkippedActive = $skippedActive
        Failed = $failed
        Errors = $errors.ToArray()
    }
}
