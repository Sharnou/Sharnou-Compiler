[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'Tools\DevAgent\GfxTaskJournal.psm1') -Force
$script:Passed=0;$script:Failed=0
$script:TestRoot=Join-Path ([IO.Path]::GetTempPath()) ('Sharnou-GfxJournal-Test-'+[Guid]::NewGuid().ToString('N'))
$script:JournalRootPath=Join-Path $script:TestRoot 'state'
function Assert-GfxJournal{param([bool]$Condition,[string]$Name);if($Condition){$script:Passed++;Write-Host "PASS: $Name"}else{$script:Failed++;Write-Host "FAIL: $Name"}}
function Assert-GfxThrows{param([scriptblock]$Action,[string]$Name);$threw=$false;try{&$Action}catch{$threw=$true};Assert-GfxJournal $threw $Name}
function Copy-GfxJournal{param($Value);return (ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $Value -Depth 20))}
function New-GfxTestTask{return (New-GfxPlannedTask -StateDirectory $script:JournalRootPath -MilestoneId 'GFX-0.3' -TaskKind 'implementation' -InputSha256 ('1'*64) -ScopeSha256 ('2'*64) -IdempotencyKey 'test/dga03/main-task')}
try{
 $null=Initialize-GfxTaskJournal -StateDirectory $script:JournalRootPath
 $initial=Get-GfxTaskJournalStatus -StateDirectory $script:JournalRootPath
 Assert-GfxJournal ($initial.initialized -and $initial.recordCount -eq 1 -and $initial.taskCount -eq 0) 'initializes journal with one genesis record'
 Assert-GfxJournal ($initial.integrity -eq 'PASS') 'initial hash chain verifies'
 $task=New-GfxTestTask;$taskId=$task.taskId
 Assert-GfxJournal ($task.status -eq 'APPENDED' -and $taskId -match '^t[0-9a-f]{32}$') 'plans deterministic task identity'
 $same=New-GfxTestTask
 Assert-GfxJournal ($same.status -eq 'DUPLICATE_NOOP' -and $same.taskId -eq $taskId) 'replayed task planning is idempotent'
 Assert-GfxJournal ((Get-GfxTaskJournalStatus -StateDirectory $script:JournalRootPath).taskCount -eq 1) 'duplicate planning creates no duplicate task'
 Assert-GfxThrows {New-GfxPlannedTask -StateDirectory $script:JournalRootPath -MilestoneId 'GFX-0.3' -TaskKind 'implementation' -InputSha256 ('3'*64) -ScopeSha256 ('2'*64) -IdempotencyKey 'test/dga03/main-task'} 'conflicting idempotency reuse rejected'
 $start=Start-GfxTask -StateDirectory $script:JournalRootPath -TaskId $taskId -SessionId 'worker-session-01'
 Assert-GfxJournal ($start.status -eq 'APPENDED') 'starts planned task'
 $startAgain=Start-GfxTask -StateDirectory $script:JournalRootPath -TaskId $taskId -SessionId 'worker-session-01'
 Assert-GfxJournal ($startAgain.status -eq 'DUPLICATE_NOOP') 'replayed start is idempotent'
 $checkpointPayload=[pscustomobject][ordered]@{phase='analysis';completedUnits=7;sourceRevision='9db82798bd3e4f97f16cbfa74baee85687932ce1';findings=@('dependency graph reviewed','resume boundary verified')}
 $cp=Save-GfxTaskCheckpoint -StateDirectory $script:JournalRootPath -TaskId $taskId -CheckpointState $checkpointPayload
 Assert-GfxJournal ($cp.status -eq 'APPENDED' -and $cp.checkpointSequence -eq 1 -and (Test-Path -LiteralPath (Join-Path (Join-Path $script:JournalRootPath 'checkpoints') $cp.checkpointFileName))) 'persists immutable hash-bound checkpoint'
 $cpAgain=Save-GfxTaskCheckpoint -StateDirectory $script:JournalRootPath -TaskId $taskId -CheckpointState $checkpointPayload
 Assert-GfxJournal ($cpAgain.status -eq 'DUPLICATE_NOOP' -and $cpAgain.checkpointSha256 -eq $cp.checkpointSha256) 'checkpoint retry is idempotent'
 $loaded=Get-GfxTaskCheckpoint -StateDirectory $script:JournalRootPath -TaskId $taskId
 Assert-GfxJournal ($loaded.stateSha256 -eq $cp.checkpointStateSha256 -and $loaded.state.phase -eq 'analysis') 'restores state after digest verification'
 Assert-GfxThrows {Save-GfxTaskCheckpoint -StateDirectory $script:JournalRootPath -TaskId $taskId -CheckpointState ([pscustomobject]@{apiToken='do-not-persist'})} 'rejects credential-shaped checkpoint keys'
 $recovery=Recover-GfxTaskJournal -StateDirectory $script:JournalRootPath
 Assert-GfxJournal ($recovery.recoveredCount -eq 1 -and $recovery.status.tasks[0].state -eq 'INTERRUPTED') 'restart recovery marks task interrupted'
 $recordCount=$recovery.status.recordCount
 $again=Recover-GfxTaskJournal -StateDirectory $script:JournalRootPath
 Assert-GfxJournal ($again.recoveredCount -eq 0 -and $again.status.recordCount -eq $recordCount) 'repeated recovery adds no duplicate event'
 $resume=Resume-GfxTask -StateDirectory $script:JournalRootPath -TaskId $taskId -SessionId 'worker-session-02'
 Assert-GfxJournal ($resume.status -eq 'APPENDED' -and $resume.checkpointSha256 -eq $cp.checkpointSha256) 'resumes from latest verified checkpoint'
 $complete=Complete-GfxTask -StateDirectory $script:JournalRootPath -TaskId $taskId -OutputSha256 ('4'*64)
 Assert-GfxJournal ($complete.status -eq 'APPENDED') 'completes task with output digest'
 $status=Get-GfxTaskJournalStatus -StateDirectory $script:JournalRootPath
 Assert-GfxJournal ($status.tasks[0].state -eq 'COMPLETED' -and $status.integrity -eq 'PASS') 'replay reconstructs completed state'
 Assert-GfxThrows {Start-GfxTask -StateDirectory $script:JournalRootPath -TaskId $taskId -SessionId 'worker-session-03'} 'terminal task cannot restart'
 $second=New-GfxPlannedTask -StateDirectory $script:JournalRootPath -MilestoneId 'GFX-A.1' -TaskKind 'validation' -InputSha256 ('5'*64) -ScopeSha256 ('6'*64) -IdempotencyKey 'test/dga03/second-task'
 $null=Start-GfxTask -StateDirectory $script:JournalRootPath -TaskId $second.taskId -SessionId 'worker-session-04'
 $null=Fail-GfxTask -StateDirectory $script:JournalRootPath -TaskId $second.taskId -FailureCode 'VALIDATION_FAILED' -Retryable $true
 $failedStatus=Get-GfxTaskJournalStatus -StateDirectory $script:JournalRootPath
 $failed=@($failedStatus.tasks|Where-Object{$_.taskId -eq $second.taskId})[0]
 Assert-GfxJournal ($failed.state -eq 'FAILED') 'records bounded task failure'
 $third=New-GfxPlannedTask -StateDirectory $script:JournalRootPath -MilestoneId 'GFX-A.2' -TaskKind 'research' -InputSha256 ('7'*64) -ScopeSha256 ('8'*64) -IdempotencyKey 'test/dga03/third-task'
 $null=Cancel-GfxTask -StateDirectory $script:JournalRootPath -TaskId $third.taskId -ReasonCode 'OWNER_REQUEST'
 $cancelStatus=Get-GfxTaskJournalStatus -StateDirectory $script:JournalRootPath
 $cancelled=@($cancelStatus.tasks|Where-Object{$_.taskId -eq $third.taskId})[0]
 Assert-GfxJournal ($cancelled.state -eq 'CANCELLED') 'records explicit cancellation'
 $fourth=New-GfxPlannedTask -StateDirectory $script:JournalRootPath -MilestoneId 'GFX-A.3' -TaskKind 'design' -InputSha256 ('9'*64) -ScopeSha256 ('a'*64) -IdempotencyKey 'test/dga03/fourth-task'
 $null=Start-GfxTask -StateDirectory $script:JournalRootPath -TaskId $fourth.taskId -SessionId 'worker-session-05'
 $null=Save-GfxTaskCheckpoint -StateDirectory $script:JournalRootPath -TaskId $fourth.taskId -CheckpointState ([pscustomobject]@{step='tamper-test'})
 $cpPath=Join-Path (Join-Path $script:JournalRootPath 'checkpoints') ($fourth.taskId+'.000001.checkpoint.json')
 $outer=Copy-GfxJournal (ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($cpPath)))
 $outer.body=$outer.body+' '
 [IO.File]::WriteAllText($cpPath,(ConvertTo-Json -InputObject $outer -Compress),(New-Object System.Text.UTF8Encoding($false)))
 Assert-GfxThrows {Get-GfxTaskJournalStatus -StateDirectory $script:JournalRootPath} 'tampered checkpoint fails closed'
}finally{if(Test-Path -LiteralPath $script:TestRoot){Remove-Item -LiteralPath $script:TestRoot -Recurse -Force}}
$module=[IO.File]::ReadAllText((Join-Path $root 'Tools\DevAgent\GfxTaskJournal.psm1'))
Assert-GfxJournal (-not($module -match '(?i)Start-Process|Invoke-Expression|Invoke-WebRequest|Invoke-RestMethod|cmd\.exe|powershell\.exe|ProcessStartInfo')) 'module has no process/shell/network execution path'
Assert-GfxJournal ($module -match 'Flush\(\$true\)' -and $module -match '\[IO\.File\]::Move') 'persistence flushes temporary files before immutable rename'
Write-Host ''
Write-Host ("DGA-0.3 journal tests: {0} passed; {1} failed; {2} total." -f $script:Passed,$script:Failed,($script:Passed+$script:Failed))
if($script:Failed -ne 0){exit 1};exit 0
