Set-StrictMode -Version 2.0
$script:GfxJournalSchema='sharnou.devagent.task-journal/1'
$script:GfxRecordSchema='sharnou.devagent.task-journal-record/1'
$script:GfxCheckpointSchema='sharnou.devagent.task-checkpoint/1'
$script:GfxZeroSha256='0000000000000000000000000000000000000000000000000000000000000000'
$script:GfxMaxRecordBytes=262144
$script:GfxMaxCheckpointBytes=1048576
$script:GfxMaxJournalRecords=200000
$script:GfxUtf8=New-Object System.Text.UTF8Encoding($false,$true)

function Get-GfxNames { param($Object) if($null -eq $Object){return @()};return @($Object.PSObject.Properties|ForEach-Object{[string]$_.Name}) }
function Assert-GfxObject {
 param($Object,[string[]]$Expected,[string]$Path)
 if($null -eq $Object -or $Object -is [string] -or $Object -is [System.Array]){throw "$Path must be a JSON object."}
 $actual=Get-GfxNames $Object
 foreach($n in $Expected){if($actual -notcontains $n){throw "$Path is missing '$n'."}}
 foreach($n in $actual){if($Expected -notcontains $n){throw "$Path contains unsupported '$n'."}}
}
function ConvertTo-GfxHex { param([byte[]]$Bytes) return ([BitConverter]::ToString($Bytes).Replace('-','').ToLowerInvariant()) }
function Get-GfxSha256 { param([byte[]]$Bytes) $sha=[Security.Cryptography.SHA256]::Create();try{return (ConvertTo-GfxHex ($sha.ComputeHash($Bytes)))}finally{$sha.Dispose()} }
function ConvertTo-GfxBytes { param([string]$Text) return $script:GfxUtf8.GetBytes($Text) }
function ConvertFrom-GfxBytes { param([byte[]]$Bytes) return $script:GfxUtf8.GetString($Bytes) }
function Test-GfxSha256 { param([string]$Value) return ($Value -cmatch '^[0-9a-f]{64}$') }
function Get-GfxStableId { param([string]$Prefix,[string]$Value) $h=Get-GfxSha256 (ConvertTo-GfxBytes $Value);return ($Prefix+$h.Substring(0,32)) }
function ConvertTo-GfxJson { param($Value,[int]$Depth=12) return (ConvertTo-Json -InputObject $Value -Depth $Depth -Compress) }
function Assert-GfxIdempotencyKey { param([string]$Key) if([string]::IsNullOrWhiteSpace($Key) -or $Key.Length -gt 240 -or $Key -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._:/+|=-]{0,239}$'){throw 'Idempotency key must be 1-240 safe ASCII characters.'} }
function Test-GfxSensitiveNames {
 param($Value,[int]$Depth=0)
 if($Depth -gt 12 -or $null -eq $Value){return $false}
 if($Value -is [System.Array]){foreach($item in $Value){if(Test-GfxSensitiveNames $item ($Depth+1)){return $true}};return $false}
 if($Value -is [string] -or $Value.GetType().IsValueType){return $false}
 if($Value -is [System.Collections.IDictionary]){foreach($key in $Value.Keys){if([string]$key -match '(?i)(password|secret|token|credential|private.?key|api.?key|authorization)'){return $true};if(Test-GfxSensitiveNames $Value[$key] ($Depth+1)){return $true}};return $false}
 foreach($property in $Value.PSObject.Properties){if($property.Name -match '(?i)(password|secret|token|credential|private.?key|api.?key|authorization)'){return $true};if(Test-GfxSensitiveNames $property.Value ($Depth+1)){return $true}}
 return $false
}
function Get-GfxStatePaths {
 param([string]$StateDirectory)
 if([string]::IsNullOrWhiteSpace($StateDirectory)){throw 'StateDirectory is required.'}
 if(-not [IO.Path]::IsPathRooted($StateDirectory)){throw 'StateDirectory must be absolute.'}
 $root=[IO.Path]::GetFullPath($StateDirectory)
 return [pscustomobject][ordered]@{root=$root;journal=[IO.Path]::Combine($root,'journal');checkpoints=[IO.Path]::Combine($root,'checkpoints')}
}
function Assert-GfxDirectory {
 param([string]$Path)
 $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
 if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw "Reparse-point state directory is not permitted: $Path"}
 if(-not $item.PSIsContainer){throw "State path is not a directory: $Path"}
}
function Ensure-GfxDirectories {
 param($Paths)
 foreach($p in @($Paths.root,$Paths.journal,$Paths.checkpoints)){if(-not(Test-Path -LiteralPath $p)){$null=[IO.Directory]::CreateDirectory($p)};Assert-GfxDirectory $p}
}
function Enter-GfxLock {
 param([string]$Root)
 $norm=$Root.TrimEnd([IO.Path]::DirectorySeparatorChar).ToLowerInvariant()
 $name='Local\Sharnou.GfxTaskJournal.'+(Get-GfxSha256 (ConvertTo-GfxBytes $norm)).Substring(0,40)
 $mutex=New-Object System.Threading.Mutex($false,$name);$acquired=$false
 try{try{$acquired=$mutex.WaitOne(15000)}catch [System.Threading.AbandonedMutexException]{$acquired=$true};if(-not $acquired){throw 'Timed out waiting for the task journal lock.'};return $mutex}catch{$mutex.Dispose();throw}
}
function Exit-GfxLock { param([System.Threading.Mutex]$Mutex) if($null -ne $Mutex){try{$Mutex.ReleaseMutex()}finally{$Mutex.Dispose()}} }
function Write-GfxImmutableFile {
 param([string]$Path,[byte[]]$Bytes)
 $dir=[IO.Path]::GetDirectoryName($Path);$temp=[IO.Path]::Combine($dir,('.pending-'+[Guid]::NewGuid().ToString('N')+'.tmp'));$stream=$null
 try{$stream=[IO.File]::Open($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);$stream.Write($Bytes,0,$Bytes.Length);$stream.Flush($true);$stream.Dispose();$stream=$null;[IO.File]::Move($temp,$Path)}
 catch{if($null -ne $stream){$stream.Dispose()};if(Test-Path -LiteralPath $temp){try{[IO.File]::Delete($temp)}catch{}};throw}
}
function Read-GfxJsonFile {
 param([string]$Path,[int]$MaximumBytes)
 if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "Required immutable file is missing: $Path"}
 $item=Get-Item -LiteralPath $Path;if($item.Length -gt $MaximumBytes){throw "Immutable file exceeds $MaximumBytes bytes: $Path"}
 return (ConvertFrom-Json -InputObject (ConvertFrom-GfxBytes ([IO.File]::ReadAllBytes($Path))) -ErrorAction Stop)
}

function Get-GfxCheckpointFile {
 param($Paths,[string]$FileName,[string]$TaskId,[int]$Sequence,[string]$JournalId,[string]$ExpectedPreviousHash)
 $expected='{0}.{1:D6}.checkpoint.json' -f $TaskId,$Sequence
 if($FileName -cne $expected){throw 'Checkpoint filename does not match its task/sequence.'}
 $path=[IO.Path]::Combine($Paths.checkpoints,$expected)
 $outer=Read-GfxJsonFile $path $script:GfxMaxCheckpointBytes
 Assert-GfxObject $outer @('body','checkpointSha256') 'checkpoint envelope'
 if($outer.body -isnot [string] -or -not(Test-GfxSha256 ([string]$outer.checkpointSha256))){throw 'Checkpoint envelope is malformed.'}
 if((Get-GfxSha256 (ConvertTo-GfxBytes ([string]$outer.body))) -cne [string]$outer.checkpointSha256){throw 'Checkpoint body SHA-256 mismatch.'}
 $body=ConvertFrom-Json -InputObject ([string]$outer.body) -ErrorAction Stop
 Assert-GfxObject $body @('schemaVersion','journalId','taskId','checkpointSequence','createdAtUtc','previousCheckpointSha256','stateBase64','stateSha256') 'checkpoint body'
 if($body.schemaVersion -cne $script:GfxCheckpointSchema -or $body.journalId -cne $JournalId -or $body.taskId -cne $TaskId){throw 'Checkpoint identity/schema mismatch.'}
 if([long]$body.checkpointSequence -ne $Sequence -or $body.previousCheckpointSha256 -cne $ExpectedPreviousHash){throw 'Checkpoint sequence/predecessor mismatch.'}
 if(-not(Test-GfxSha256 ([string]$body.stateSha256))){throw 'Checkpoint state hash is malformed.'}
 try{$stateBytes=[Convert]::FromBase64String([string]$body.stateBase64)}catch{throw 'Checkpoint state Base64 is invalid.'}
 if((Get-GfxSha256 $stateBytes) -cne [string]$body.stateSha256){throw 'Checkpoint state SHA-256 mismatch.'}
 $state=ConvertFrom-Json -InputObject (ConvertFrom-GfxBytes $stateBytes) -ErrorAction Stop
 return [pscustomobject][ordered]@{fileName=$expected;checkpointSha256=[string]$outer.checkpointSha256;stateSha256=[string]$body.stateSha256;previousCheckpointSha256=[string]$body.previousCheckpointSha256;checkpointSequence=$Sequence;state=$state}
}

function Assert-GfxTransition {
 param($Store,[string]$EventType,$TaskId,$Payload)
 if($EventType -eq 'JournalCreated'){
  if($Store.records.Count -ne 0 -or $null -ne $TaskId){throw 'JournalCreated is valid only as the first event.'}
  Assert-GfxObject $Payload @('campaignId','purpose') 'JournalCreated payload'
  if($Payload.campaignId -cne 'sharnou.graphics-compiler' -or $Payload.purpose -cne 'durable_gfx_campaign_execution'){throw 'Journal genesis identity/purpose is invalid.'}
  return
 }
 if(-not $Store.initialized){throw 'Journal is not initialized.'}
 if($EventType -eq 'TaskPlanned'){
  if($null -eq $TaskId -or $Store.tasks.ContainsKey([string]$TaskId)){throw 'Task ID is null or already exists.'}
  if($TaskId -cnotmatch '^t[0-9a-f]{32}$'){throw 'Task ID is malformed.'}
  Assert-GfxObject $Payload @('milestoneId','taskKind','inputSha256','scopeSha256','attempt') 'TaskPlanned payload'
  if([string]$Payload.milestoneId -cnotmatch '^GFX-(0\.[1-8]|A\.[1-3]|EVOL-[A-Za-z0-9.-]{1,32})$'){throw 'Milestone ID is invalid.'}
  if(@('research','design','implementation','validation','qualification','review','documentation') -cnotcontains [string]$Payload.taskKind){throw 'Task kind is invalid.'}
  if(-not(Test-GfxSha256 ([string]$Payload.inputSha256)) -or -not(Test-GfxSha256 ([string]$Payload.scopeSha256))){throw 'Task input/scope digest is invalid.'}
  if($Payload.attempt -isnot [int] -or $Payload.attempt -lt 1 -or $Payload.attempt -gt 3){throw 'Task attempt must be 1-3.'}
  return
 }
 if([string]::IsNullOrWhiteSpace([string]$TaskId) -or -not $Store.tasks.ContainsKey([string]$TaskId)){throw "Event '$EventType' references unknown task."}
 $task=$Store.tasks[[string]$TaskId]
 switch($EventType){
  'TaskStarted' {Assert-GfxObject $Payload @('sessionId') 'TaskStarted payload';if($task.state -ne 'PLANNED'){throw "Cannot start task in state $($task.state)."};if([string]$Payload.sessionId -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$'){throw 'SessionId invalid.'}}
  'TaskCheckpointed' {
   Assert-GfxObject $Payload @('checkpointFileName','checkpointSequence','checkpointSha256','checkpointStateSha256','previousCheckpointSha256') 'TaskCheckpointed payload'
   if($task.state -ne 'RUNNING'){throw "Cannot checkpoint task in state $($task.state)."}
   if([long]$Payload.checkpointSequence -ne ($task.checkpointSequence+1)){throw 'Checkpoint sequence is not contiguous.'}
   if(-not(Test-GfxSha256 ([string]$Payload.checkpointSha256)) -or -not(Test-GfxSha256 ([string]$Payload.checkpointStateSha256))){throw 'Checkpoint digest invalid.'}
   if($Payload.previousCheckpointSha256 -cne $task.checkpointSha256){throw 'Checkpoint predecessor mismatch.'}
   $cp=Get-GfxCheckpointFile $Store.paths ([string]$Payload.checkpointFileName) ([string]$TaskId) ([int]$Payload.checkpointSequence) $Store.journalId ([string]$Payload.previousCheckpointSha256)
   if($cp.checkpointSha256 -cne [string]$Payload.checkpointSha256 -or $cp.stateSha256 -cne [string]$Payload.checkpointStateSha256){throw 'Checkpoint file/event digest mismatch.'}
  }
  'TaskInterrupted' {Assert-GfxObject $Payload @('reasonCode','lastCheckpointSha256') 'TaskInterrupted payload';if($task.state -ne 'RUNNING' -or $Payload.reasonCode -cne 'HOST_RESTART'){throw 'Only RUNNING tasks can be interrupted for host restart.'};if($Payload.lastCheckpointSha256 -cne $task.checkpointSha256){throw 'Interruption checkpoint mismatch.'}}
  'TaskResumed' {Assert-GfxObject $Payload @('sessionId','checkpointSha256') 'TaskResumed payload';if($task.state -ne 'INTERRUPTED'){throw "Cannot resume task in state $($task.state)."};if([string]$Payload.sessionId -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$'){throw 'Resume session ID invalid.'};if($Payload.checkpointSha256 -cne $task.checkpointSha256){throw 'Resume checkpoint is not latest.'}}
  'TaskCompleted' {Assert-GfxObject $Payload @('outputSha256') 'TaskCompleted payload';if($task.state -ne 'RUNNING' -or -not(Test-GfxSha256 ([string]$Payload.outputSha256))){throw 'Task completion state/output digest invalid.'}}
  'TaskFailed' {Assert-GfxObject $Payload @('failureCode','retryable') 'TaskFailed payload';if(@('RUNNING','INTERRUPTED') -cnotcontains [string]$task.state){throw "Cannot fail task in state $($task.state)."};if(@('EVIDENCE_MISSING','VALIDATION_FAILED','RESOURCE_LIMIT','DEPENDENCY_BLOCKED','REPAIR_LIMIT_REACHED','INTERNAL_ERROR') -cnotcontains [string]$Payload.failureCode){throw 'Failure code invalid.'};if($Payload.retryable -isnot [bool]){throw 'retryable must be Boolean.'}}
  'TaskCancelled' {Assert-GfxObject $Payload @('reasonCode') 'TaskCancelled payload';if(@('PLANNED','RUNNING','INTERRUPTED') -cnotcontains [string]$task.state){throw "Cannot cancel task in state $($task.state)."};if(@('OWNER_REQUEST','CAMPAIGN_PAUSED','PREDEQUISITE_REVOKED') -cnotcontains [string]$Payload.reasonCode){throw 'Cancellation reason invalid.'}}
  default {throw "Unsupported journal event type: $EventType"}
 }
}

function Apply-GfxEvent {
 param($Store,$Body,$Payload)
 $type=[string]$Body.eventType;$taskId=$Body.taskId
 if($type -eq 'JournalCreated'){Assert-GfxTransition $Store $type $null $Payload;$Store.initialized=$true;$Store.journalId=[string]$Body.journalId;return}
 Assert-GfxTransition $Store $type $taskId $Payload
 if($type -eq 'TaskPlanned'){
  $Store.tasks[[string]$taskId]=@{taskId=[string]$taskId;milestoneId=[string]$Payload.milestoneId;taskKind=[string]$Payload.taskKind;inputSha256=[string]$Payload.inputSha256;scopeSha256=[string]$Payload.scopeSha256;attempt=[int]$Payload.attempt;state='PLANNED';checkpointSequence=0;checkpointSha256=$script:GfxZeroSha256;previousCheckpointSha256=$script:GfxZeroSha256;checkpointFileName=$null;lastEventSequence=[long]$Body.sequence;lastEventType=$type}
  return
 }
 $task=$Store.tasks[[string]$taskId]
 switch($type){
  'TaskStarted' {$task.state='RUNNING';$task.sessionId=[string]$Payload.sessionId}
  'TaskCheckpointed' {$task.checkpointSequence=[int]$Payload.checkpointSequence;$task.previousCheckpointSha256=[string]$Payload.previousCheckpointSha256;$task.checkpointSha256=[string]$Payload.checkpointSha256;$task.checkpointFileName=[string]$Payload.checkpointFileName}
  'TaskInterrupted' {$task.state='INTERRUPTED'}
  'TaskResumed' {$task.state='RUNNING';$task.sessionId=[string]$Payload.sessionId}
  'TaskCompleted' {$task.state='COMPLETED';$task.outputSha256=[string]$Payload.outputSha256}
  'TaskFailed' {$task.state='FAILED';$task.failureCode=[string]$Payload.failureCode;$task.retryable=[bool]$Payload.retryable}
  'TaskCancelled' {$task.state='CANCELLED';$task.cancelReason=[string]$Payload.reasonCode}
 }
 $task.lastEventSequence=[long]$Body.sequence;$task.lastEventType=$type
}

function Read-GfxJournalUnlocked {
 param($Paths)
 Ensure-GfxDirectories $Paths
 $files=@(Get-ChildItem -LiteralPath $Paths.journal -Filter '*.json' -File|Sort-Object Name)
 if($files.Count -gt $script:GfxMaxJournalRecords){throw 'Journal exceeds maximum record count.'}
 $store=@{paths=$Paths;initialized=$false;journalId=$null;records=(New-Object System.Collections.ArrayList);tasks=@{};idempotency=@{};referencedCheckpoints=@{};lastRecordSha256=$script:GfxZeroSha256}
 $expected=[long]1;$previous=$script:GfxZeroSha256;$journalId=$null
 foreach($file in $files){
  if($file.Name -cnotmatch '^([0-9]{12})_(e[0-9a-f]{32})\.json$'){throw "Unexpected journal record filename: $($file.Name)"}
  $outer=Read-GfxJsonFile $file.FullName $script:GfxMaxRecordBytes
  Assert-GfxObject $outer @('body','recordSha256') 'journal envelope'
  if($outer.body -isnot [string] -or -not(Test-GfxSha256 ([string]$outer.recordSha256))){throw "Malformed journal envelope: $($file.Name)"}
  $bodyText=[string]$outer.body;$recordHash=Get-GfxSha256 (ConvertTo-GfxBytes $bodyText)
  if($recordHash -cne [string]$outer.recordSha256){throw "Journal record hash mismatch: $($file.Name)"}
  $body=ConvertFrom-Json -InputObject $bodyText -ErrorAction Stop
  Assert-GfxObject $body @('schemaVersion','journalId','sequence','eventId','idempotencyKey','taskId','eventType','occurredAtUtc','previousRecordSha256','payloadBase64') 'journal body'
  if($body.schemaVersion -cne $script:GfxRecordSchema){throw 'Unsupported record schema.'}
  if([long]$body.sequence -ne $expected){throw "Journal sequence gap at $($file.Name)."}
  if($file.Name -cne ('{0:D12}_{1}.json' -f [long]$body.sequence,[string]$body.eventId)){throw 'Journal filename/body mismatch.'}
  if($body.previousRecordSha256 -cne $previous){throw "Journal hash-chain mismatch at record $expected."}
  if($null -eq $journalId){$journalId=[string]$body.journalId}else{if($body.journalId -cne $journalId){throw 'Journal ID changed within stream.'}}
  if([string]$body.eventId -cnotmatch '^e[0-9a-f]{32}$'){throw 'Event ID malformed.'}
  Assert-GfxIdempotencyKey ([string]$body.idempotencyKey)
  if($body.eventId -cne (Get-GfxStableId 'e' ('event:'+[string]$body.idempotencyKey))){throw 'Event ID is inconsistent with idempotency key.'}
  $parsedTime=[DateTimeOffset]::MinValue
  if($body.occurredAtUtc -is [DateTime]){$parsedTime=[DateTimeOffset]::new(([DateTime]$body.occurredAtUtc).ToUniversalTime())}
  elseif(-not [DateTimeOffset]::TryParse([string]$body.occurredAtUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$parsedTime)){throw 'Journal timestamp invalid.'}
  try{$payloadBytes=[Convert]::FromBase64String([string]$body.payloadBase64)}catch{throw 'Journal payload Base64 invalid.'}
  $payload=ConvertFrom-Json -InputObject (ConvertFrom-GfxBytes $payloadBytes) -ErrorAction Stop
  if($store.idempotency.ContainsKey([string]$body.idempotencyKey)){throw 'Duplicate journal idempotency key.'}
  if($body.eventType -eq 'JournalCreated'){if($expected -ne 1 -or $body.idempotencyKey -cne 'journal-created/v1'){throw 'JournalCreated must be first.'}}elseif(-not $store.initialized){throw 'Journal event precedes genesis.'}
  if($body.eventType -eq 'TaskPlanned' -and $body.taskId -cne (Get-GfxStableId 't' ([string]$body.idempotencyKey))){throw 'Task ID is not derived from plan idempotency key.'}
  Apply-GfxEvent $store $body $payload
  if($body.eventType -eq 'TaskCheckpointed'){$store.referencedCheckpoints[[string]$payload.checkpointFileName]=$true}
  $store.idempotency[[string]$body.idempotencyKey]=@{eventType=[string]$body.eventType;taskId=[string]$body.taskId;payloadBase64=[string]$body.payloadBase64;sequence=[long]$body.sequence;recordSha256=$recordHash;eventId=[string]$body.eventId}
  $null=$store.records.Add([pscustomobject][ordered]@{sequence=[long]$body.sequence;eventId=[string]$body.eventId;eventType=[string]$body.eventType;taskId=[string]$body.taskId;idempotencyKey=[string]$body.idempotencyKey;recordSha256=$recordHash})
  $previous=$recordHash;$expected++
 }
 if($files.Count -gt 0){if(-not $store.initialized){throw 'Journal exists but genesis record is missing.'};$store.lastRecordSha256=$previous}
 return $store
}
function Add-GfxJournalRecordUnlocked {
 param($Store,[string]$EventType,$TaskId,$Payload,[string]$IdempotencyKey)
 Assert-GfxIdempotencyKey $IdempotencyKey
 if($Store.idempotency.ContainsKey($IdempotencyKey)){throw 'Internal duplicate idempotency key; resolve before append.'}
 Assert-GfxTransition $Store $EventType $TaskId $Payload
 $eventId=Get-GfxStableId 'e' ('event:'+$IdempotencyKey)
 $payloadBytes=ConvertTo-GfxBytes (ConvertTo-GfxJson $Payload 12)
 if($payloadBytes.Length -gt 32768){throw 'Event payload exceeds 32 KiB.'}
 $body=[pscustomobject][ordered]@{schemaVersion=$script:GfxRecordSchema;journalId=[string]$Store.journalId;sequence=([long]$Store.records.Count+1);eventId=$eventId;idempotencyKey=$IdempotencyKey;taskId=$TaskId;eventType=$EventType;occurredAtUtc=[DateTime]::UtcNow.ToString('o',[Globalization.CultureInfo]::InvariantCulture);previousRecordSha256=[string]$Store.lastRecordSha256;payloadBase64=[Convert]::ToBase64String($payloadBytes)}
 $bodyText=ConvertTo-GfxJson $body 8;$hash=Get-GfxSha256 (ConvertTo-GfxBytes $bodyText)
 $outer=[pscustomobject][ordered]@{body=$bodyText;recordSha256=$hash};$bytes=ConvertTo-GfxBytes (ConvertTo-GfxJson $outer 4)
 if($bytes.Length -gt $script:GfxMaxRecordBytes){throw 'Serialized journal record exceeds size limit.'}
 $name='{0:D12}_{1}.json' -f [long]$body.sequence,$eventId
 Write-GfxImmutableFile ([IO.Path]::Combine($Store.paths.journal,$name)) $bytes
 $fresh=Read-GfxJournalUnlocked $Store.paths
 return [pscustomobject][ordered]@{status='APPENDED';sequence=[long]$body.sequence;eventId=$eventId;taskId=$TaskId;eventType=$EventType;recordSha256=$hash;store=$fresh}
}
function Resolve-GfxIdempotency {
 param($Store,[string]$EventType,$TaskId,$Payload,[string]$Key)
 Assert-GfxIdempotencyKey $Key
 if(-not $Store.idempotency.ContainsKey($Key)){return $null}
 $old=$Store.idempotency[$Key];$new=[Convert]::ToBase64String((ConvertTo-GfxBytes (ConvertTo-GfxJson $Payload 12)))
 if($old.eventType -cne $EventType -or [string]$old.taskId -cne [string]$TaskId -or $old.payloadBase64 -cne $new){throw 'Idempotency conflict: key was committed with different content.'}
 return [pscustomobject][ordered]@{status='DUPLICATE_NOOP';sequence=$old.sequence;eventId=$old.eventId;taskId=$TaskId;eventType=$EventType;recordSha256=$old.recordSha256}
}
function Get-GfxStoreStatus {
 param($Store)
 $tasks=@()
 foreach($id in @($Store.tasks.Keys|Sort-Object)){$t=$Store.tasks[$id];$tasks += [pscustomobject][ordered]@{taskId=$t.taskId;milestoneId=$t.milestoneId;taskKind=$t.taskKind;attempt=$t.attempt;state=$t.state;checkpointSequence=$t.checkpointSequence;checkpointSha256=$t.checkpointSha256;lastEventSequence=$t.lastEventSequence;lastEventType=$t.lastEventType}}
 $orphans=@();foreach($f in @(Get-ChildItem -LiteralPath $Store.paths.checkpoints -Filter '*.checkpoint.json' -File)){if(-not $Store.referencedCheckpoints.ContainsKey($f.Name)){$orphans+=$f.Name}}
 $temps=@(Get-ChildItem -LiteralPath $Store.paths.journal -Filter '.pending-*.tmp' -File).Count+@(Get-ChildItem -LiteralPath $Store.paths.checkpoints -Filter '.pending-*.tmp' -File).Count
 return [pscustomobject][ordered]@{schemaVersion=$script:GfxJournalSchema;initialized=$Store.initialized;journalId=$Store.journalId;recordCount=$Store.records.Count;lastSequence=$Store.records.Count;lastRecordSha256=$Store.lastRecordSha256;pendingRecoveryCount=@($tasks|Where-Object{$_.state -eq 'RUNNING'}).Count;taskCount=$tasks.Count;tasks=$tasks;orphanCheckpointFiles=$orphans;abandonedTemporaryFiles=$temps;integrity='PASS'}
}
function Initialize-GfxTaskJournal {
 [CmdletBinding()]param([Parameter(Mandatory=$true)][string]$StateDirectory)
 $paths=Get-GfxStatePaths $StateDirectory;$mutex=Enter-GfxLock $paths.root
 try{Ensure-GfxDirectories $paths;$store=Read-GfxJournalUnlocked $paths;if(-not $store.initialized){$store.journalId=[Guid]::NewGuid().ToString('N');$p=[pscustomobject][ordered]@{campaignId='sharnou.graphics-compiler';purpose='durable_gfx_campaign_execution'};$null=Add-GfxJournalRecordUnlocked $store 'JournalCreated' $null $p 'journal-created/v1';$store=Read-GfxJournalUnlocked $paths};return (Get-GfxStoreStatus $store)}finally{Exit-GfxLock $mutex}
}
function Get-GfxTaskJournalStatus {
 [CmdletBinding()]param([Parameter(Mandatory=$true)][string]$StateDirectory)
 $paths=Get-GfxStatePaths $StateDirectory;$mutex=Enter-GfxLock $paths.root
 try{Ensure-GfxDirectories $paths;return (Get-GfxStoreStatus (Read-GfxJournalUnlocked $paths))}finally{Exit-GfxLock $mutex}
}
function New-GfxPlannedTask {
 [CmdletBinding()]param([Parameter(Mandatory=$true)][string]$StateDirectory,[Parameter(Mandatory=$true)][string]$MilestoneId,[Parameter(Mandatory=$true)][ValidateSet('research','design','implementation','validation','qualification','review','documentation')][string]$TaskKind,[Parameter(Mandatory=$true)][string]$InputSha256,[Parameter(Mandatory=$true)][string]$ScopeSha256,[Parameter(Mandatory=$true)][string]$IdempotencyKey,[int]$Attempt=1)
 if(-not(Test-GfxSha256 $InputSha256) -or -not(Test-GfxSha256 $ScopeSha256)){throw 'Input/scope must be lowercase SHA-256.'}
 if($MilestoneId -cnotmatch '^GFX-(0\.[1-8]|A\.[1-3]|EVOL-[A-Za-z0-9.-]{1,32})$'){throw 'Milestone ID invalid.'}
 if($Attempt -lt 1 -or $Attempt -gt 3){throw 'Attempt must be 1-3.'}
 Assert-GfxIdempotencyKey $IdempotencyKey;$taskId=Get-GfxStableId 't' $IdempotencyKey
 $payload=[pscustomobject][ordered]@{milestoneId=$MilestoneId;taskKind=$TaskKind;inputSha256=$InputSha256;scopeSha256=$ScopeSha256;attempt=$Attempt}
 $paths=Get-GfxStatePaths $StateDirectory;$mutex=Enter-GfxLock $paths.root
 try{$store=Read-GfxJournalUnlocked $paths;if(-not $store.initialized){throw 'Initialize journal before planning.'};$dup=Resolve-GfxIdempotency $store 'TaskPlanned' $taskId $payload $IdempotencyKey;if($null -ne $dup){return $dup};$r=Add-GfxJournalRecordUnlocked $store 'TaskPlanned' $taskId $payload $IdempotencyKey;return [pscustomobject][ordered]@{status=$r.status;taskId=$taskId;sequence=$r.sequence;eventId=$r.eventId;recordSha256=$r.recordSha256}}finally{Exit-GfxLock $mutex}
}
function Start-GfxTask {
 [CmdletBinding()]param([Parameter(Mandatory=$true)][string]$StateDirectory,[Parameter(Mandatory=$true)][string]$TaskId,[Parameter(Mandatory=$true)][string]$SessionId)
 if($SessionId -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$'){throw 'SessionId invalid.'}
 $key='start/'+$TaskId+'/'+$SessionId;$payload=[pscustomobject][ordered]@{sessionId=$SessionId}
 $paths=Get-GfxStatePaths $StateDirectory;$mutex=Enter-GfxLock $paths.root
 try{$store=Read-GfxJournalUnlocked $paths;$dup=Resolve-GfxIdempotency $store 'TaskStarted' $TaskId $payload $key;if($null -ne $dup){return $dup};$r=Add-GfxJournalRecordUnlocked $store 'TaskStarted' $TaskId $payload $key;return [pscustomobject][ordered]@{status=$r.status;taskId=$TaskId;sequence=$r.sequence;recordSha256=$r.recordSha256}}finally{Exit-GfxLock $mutex}
}
function Save-GfxCheckpointUnlocked {
 param($Paths,$Store,[string]$TaskId,$Task,$State)
 if($null -eq $State -or $State -is [string] -or $State -is [System.Array] -or $State.GetType().IsValueType){throw 'Checkpoint state must be a JSON object.'}
 if(Test-GfxSensitiveNames $State){throw 'Checkpoint state contains a prohibited credential/secret property name.'}
 $stateBytes=ConvertTo-GfxBytes (ConvertTo-GfxJson $State 12);if($stateBytes.Length -gt 262144){throw 'Checkpoint state exceeds 256 KiB.'}
 $stateHash=Get-GfxSha256 $stateBytes;$previous=[string]$Task.checkpointSha256;$key='checkpoint/'+$TaskId+'/'+$stateHash
 if($Store.idempotency.ContainsKey($key)){
  $old=$Store.idempotency[$key];$oldPayload=ConvertFrom-Json -InputObject (ConvertFrom-GfxBytes ([Convert]::FromBase64String($old.payloadBase64)))
  if($oldPayload.checkpointStateSha256 -cne $stateHash){throw 'Checkpoint idempotency conflict.'}
  $null=Get-GfxCheckpointFile $Paths ([string]$oldPayload.checkpointFileName) $TaskId ([int]$oldPayload.checkpointSequence) $Store.journalId ([string]$oldPayload.previousCheckpointSha256)
  return [pscustomobject][ordered]@{status='DUPLICATE_NOOP';taskId=$TaskId;sequence=$old.sequence;checkpointSequence=[int]$oldPayload.checkpointSequence;checkpointFileName=[string]$oldPayload.checkpointFileName;checkpointSha256=[string]$oldPayload.checkpointSha256}
 }
 $n=[int]$Task.checkpointSequence+1;$fileName='{0}.{1:D6}.checkpoint.json' -f $TaskId,$n;$path=[IO.Path]::Combine($Paths.checkpoints,$fileName)
 if(Test-Path -LiteralPath $path -PathType Leaf){$existing=Get-GfxCheckpointFile $Paths $fileName $TaskId $n $Store.journalId $previous;if($existing.stateSha256 -cne $stateHash){throw 'Orphan checkpoint conflicts with requested state.'};$checkpointHash=$existing.checkpointSha256}
 else{
  $body=[pscustomobject][ordered]@{schemaVersion=$script:GfxCheckpointSchema;journalId=$Store.journalId;taskId=$TaskId;checkpointSequence=$n;createdAtUtc=[DateTime]::UtcNow.ToString('o',[Globalization.CultureInfo]::InvariantCulture);previousCheckpointSha256=$previous;stateBase64=[Convert]::ToBase64String($stateBytes);stateSha256=$stateHash}
  $bodyText=ConvertTo-GfxJson $body 8;$checkpointHash=Get-GfxSha256 (ConvertTo-GfxBytes $bodyText);$outer=[pscustomobject][ordered]@{body=$bodyText;checkpointSha256=$checkpointHash};$bytes=ConvertTo-GfxBytes (ConvertTo-GfxJson $outer 4)
  if($bytes.Length -gt $script:GfxMaxCheckpointBytes){throw 'Checkpoint file exceeds size limit.'}
  Write-GfxImmutableFile $path $bytes
 }
 $payload=[pscustomobject][ordered]@{checkpointFileName=$fileName;checkpointSequence=$n;checkpointSha256=$checkpointHash;checkpointStateSha256=$stateHash;previousCheckpointSha256=$previous}
 $r=Add-GfxJournalRecordUnlocked $Store 'TaskCheckpointed' $TaskId $payload $key
 return [pscustomobject][ordered]@{status=$r.status;taskId=$TaskId;sequence=$r.sequence;checkpointSequence=$n;checkpointFileName=$fileName;checkpointSha256=$checkpointHash;checkpointStateSha256=$stateHash}
}
function Save-GfxTaskCheckpoint {
 [CmdletBinding()]param([Parameter(Mandatory=$true)][string]$StateDirectory,[Parameter(Mandatory=$true)][string]$TaskId,[Parameter(Mandatory=$true)]$State)
 $paths=Get-GfxStatePaths $StateDirectory;$mutex=Enter-GfxLock $paths.root
 try{$store=Read-GfxJournalUnlocked $paths;if(-not $store.tasks.ContainsKey($TaskId)){throw 'Unknown task.'};$task=$store.tasks[$TaskId];if($task.state -ne 'RUNNING'){throw 'Checkpoint requires RUNNING state.'};return (Save-GfxCheckpointUnlocked $paths $store $TaskId $task $State)}finally{Exit-GfxLock $mutex}
}
function Get-GfxTaskCheckpoint {
 [CmdletBinding()]param([Parameter(Mandatory=$true)][string]$StateDirectory,[Parameter(Mandatory=$true)][string]$TaskId)
 $paths=Get-GfxStatePaths $StateDirectory;$mutex=Enter-GfxLock $paths.root
 try{$store=Read-GfxJournalUnlocked $paths;if(-not $store.tasks.ContainsKey($TaskId)){throw 'Unknown task.'};$t=$store.tasks[$TaskId];if($t.checkpointSequence -lt 1){return $null};return (Get-GfxCheckpointFile $paths $t.checkpointFileName $TaskId $t.checkpointSequence $store.journalId $t.previousCheckpointSha256)}finally{Exit-GfxLock $mutex}
}
function Invoke-GfxTaskEvent {
 param([string]$StateDirectory,[string]$TaskId,[string]$EventType,$Payload,[string]$Key)
 $paths=Get-GfxStatePaths $StateDirectory;$mutex=Enter-GfxLock $paths.root
 try{$store=Read-GfxJournalUnlocked $paths;$dup=Resolve-GfxIdempotency $store $EventType $TaskId $Payload $Key;if($null -ne $dup){return $dup};$r=Add-GfxJournalRecordUnlocked $store $EventType $TaskId $Payload $Key;return [pscustomobject][ordered]@{status=$r.status;taskId=$TaskId;eventType=$EventType;sequence=$r.sequence;recordSha256=$r.recordSha256}}finally{Exit-GfxLock $mutex}
}
function Complete-GfxTask {
 [CmdletBinding()]param([Parameter(Mandatory=$true)][string]$StateDirectory,[Parameter(Mandatory=$true)][string]$TaskId,[Parameter(Mandatory=$true)][string]$OutputSha256)
 if(-not(Test-GfxSha256 $OutputSha256)){throw 'Output digest invalid.'};$p=[pscustomobject][ordered]@{outputSha256=$OutputSha256}
 return (Invoke-GfxTaskEvent $StateDirectory $TaskId 'TaskCompleted' $p ('complete/'+$TaskId+'/'+$OutputSha256))
}
function Fail-GfxTask {
 [CmdletBinding()]param([Parameter(Mandatory=$true)][string]$StateDirectory,[Parameter(Mandatory=$true)][string]$TaskId,[Parameter(Mandatory=$true)][ValidateSet('EVIDENCE_MISSING','VALIDATION_FAILED','RESOURCE_LIMIT','DEPENDENCY_BLOCKED','REPAIR_LIMIT_REACHED','INTERNAL_ERROR')][string]$FailureCode,[Parameter(Mandatory=$true)][bool]$Retryable)
 $p=[pscustomobject][ordered]@{failureCode=$FailureCode;retryable=$Retryable}
 return (Invoke-GfxTaskEvent $StateDirectory $TaskId 'TaskFailed' $p ('fail/'+$TaskId+'/'+$FailureCode+'/'+([string]$Retryable).ToLowerInvariant()))
}
function Cancel-GfxTask {
 [CmdletBinding()]param([Parameter(Mandatory=$true)][string]$StateDirectory,[Parameter(Mandatory=$true)][string]$TaskId,[Parameter(Mandatory=$true)][ValidateSet('OWNER_REQUEST','CAMPAIGN_PAUSED','PREDEQUISITE_REVOKED')][string]$ReasonCode)
 $p=[pscustomobject][ordered]@{reasonCode=$ReasonCode}
 return (Invoke-GfxTaskEvent $StateDirectory $TaskId 'TaskCancelled' $p ('cancel/'+$TaskId+'/'+$ReasonCode))
}
function Resume-GfxTask {
 [CmdletBinding()]param([Parameter(Mandatory=$true)][string]$StateDirectory,[Parameter(Mandatory=$true)][string]$TaskId,[Parameter(Mandatory=$true)][string]$SessionId)
 if($SessionId -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$'){throw 'SessionId invalid.'}
 $paths=Get-GfxStatePaths $StateDirectory;$mutex=Enter-GfxLock $paths.root
 try{$store=Read-GfxJournalUnlocked $paths;if(-not $store.tasks.ContainsKey($TaskId)){throw 'Unknown task.'};$t=$store.tasks[$TaskId];$p=[pscustomobject][ordered]@{sessionId=$SessionId;checkpointSha256=[string]$t.checkpointSha256};$key='resume/'+$TaskId+'/'+$SessionId+'/'+[string]$t.checkpointSha256;$dup=Resolve-GfxIdempotency $store 'TaskResumed' $TaskId $p $key;if($null -ne $dup){return $dup};$r=Add-GfxJournalRecordUnlocked $store 'TaskResumed' $TaskId $p $key;return [pscustomobject][ordered]@{status=$r.status;taskId=$TaskId;sequence=$r.sequence;checkpointSha256=[string]$t.checkpointSha256}}finally{Exit-GfxLock $mutex}
}
function Recover-GfxTaskJournal {
 [CmdletBinding()]param([Parameter(Mandatory=$true)][string]$StateDirectory)
 $paths=Get-GfxStatePaths $StateDirectory;$mutex=Enter-GfxLock $paths.root
 try{
  $store=Read-GfxJournalUnlocked $paths;if(-not $store.initialized){throw 'Cannot recover an uninitialized journal.'}
  $recovered=New-Object System.Collections.ArrayList
  foreach($taskId in @($store.tasks.Keys)){
   $store=Read-GfxJournalUnlocked $paths;$t=$store.tasks[$taskId]
   if($t.state -eq 'RUNNING'){$p=[pscustomobject][ordered]@{reasonCode='HOST_RESTART';lastCheckpointSha256=[string]$t.checkpointSha256};$key='recover/'+$taskId+'/'+[string]$t.lastEventSequence;$r=Add-GfxJournalRecordUnlocked $store 'TaskInterrupted' $taskId $p $key;$null=$recovered.Add([pscustomobject][ordered]@{taskId=$taskId;sequence=$r.sequence;checkpointSha256=[string]$t.checkpointSha256})}
  }
  $final=Read-GfxJournalUnlocked $paths
  return [pscustomobject][ordered]@{recoveredCount=$recovered.Count;recoveredTasks=@($recovered.ToArray());status=(Get-GfxStoreStatus $final)}
 }finally{Exit-GfxLock $mutex}
}
Export-ModuleMember -Function Initialize-GfxTaskJournal,Get-GfxTaskJournalStatus,New-GfxPlannedTask,Start-GfxTask,Save-GfxTaskCheckpoint,Get-GfxTaskCheckpoint,Resume-GfxTask,Complete-GfxTask,Fail-GfxTask,Cancel-GfxTask,Recover-GfxTaskJournal
