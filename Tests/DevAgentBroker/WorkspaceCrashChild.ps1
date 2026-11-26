[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
    [Parameter(Mandatory = $true)][string]$JournalRoot,
    [Parameter(Mandatory = $true)][string]$ExecutionSid,
    [Parameter(Mandatory = $true)][string]$SupervisorSid,
    [Parameter(Mandatory = $true)][string]$CrashAfterPhase,
    [Parameter(Mandatory = $true)][string]$MarkerPath,
    [string]$ExternalRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'WorkspaceTransaction.ps1'
. $modulePath

if ($CrashAfterPhase -eq 'AfterAclApplied' -or $CrashAfterPhase -eq 'AfterActive' -or $CrashAfterPhase -eq 'AfterWorkspaceCreated') {
    $null = New-SharnouExecutionWorkspace -WorkspaceRoot $WorkspaceRoot -JournalRoot $JournalRoot -ExecutionSid $ExecutionSid -SupervisorSid $SupervisorSid -EnableTestHooks -PauseAfterPhase $CrashAfterPhase -MarkerPath $MarkerPath
    throw 'The expected crash pause returned unexpectedly.'
}

if ($CrashAfterPhase -eq 'ActiveWork') {
    $transaction = New-SharnouExecutionWorkspace -WorkspaceRoot $WorkspaceRoot -JournalRoot $JournalRoot -ExecutionSid $ExecutionSid -SupervisorSid $SupervisorSid
    $nested = Join-Path $transaction.WorkspacePath 'nested'
    [void][System.IO.Directory]::CreateDirectory($nested)
    [System.IO.File]::WriteAllText((Join-Path $nested 'payload.bin'), 'workspace-data', [System.Text.Encoding]::ASCII)
    if (-not [string]::IsNullOrWhiteSpace($ExternalRoot)) {
        New-Item -ItemType Junction -Path (Join-Path $nested 'external-link') -Target $ExternalRoot | Out-Null
    }
    [System.IO.File]::WriteAllText($MarkerPath, $transaction.WorkspacePath, [System.Text.Encoding]::ASCII)
    while ($true) { Start-Sleep -Seconds 1 }
}

$transaction = New-SharnouExecutionWorkspace -WorkspaceRoot $WorkspaceRoot -JournalRoot $JournalRoot -ExecutionSid $ExecutionSid -SupervisorSid $SupervisorSid
if ($CrashAfterPhase -eq 'AfterRestoreIntent' -or $CrashAfterPhase -eq 'AfterAclRestored' -or $CrashAfterPhase -eq 'AfterRestoredJournal') {
    [System.IO.File]::WriteAllText((Join-Path $transaction.WorkspacePath 'payload.bin'), 'workspace-data', [System.Text.Encoding]::ASCII)
    $null = Complete-SharnouExecutionWorkspace -Transaction $transaction -EnableTestHooks -PauseAfterPhase $CrashAfterPhase -MarkerPath $MarkerPath
    throw 'The expected rollback crash pause returned unexpectedly.'
}

throw "Unsupported crash phase: $CrashAfterPhase"
