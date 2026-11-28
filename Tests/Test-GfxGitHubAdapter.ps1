[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'Tools\DevAgent\GfxGitHubAdapter.psm1') -Force
$module=Get-Module GfxGitHubAdapter
$script:Passed=0;$script:Failed=0
function Assert-GfxAdapter {
 param([bool]$Condition,[string]$Name)
 if($Condition){$script:Passed++;Write-Host "PASS: $Name"}else{$script:Failed++;Write-Host "FAIL: $Name"}
}
function Copy-Object {param($Value);return (ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $Value -Depth 32))}
function New-MockResponse {
 param([int]$Status=200,$Object,[string]$Location='')
 $bytes=New-Object byte[] 0
 if($null -ne $Object){$json=ConvertTo-Json -InputObject $Object -Depth 24 -Compress;$bytes=(New-Object Text.UTF8Encoding($false)).GetBytes($json)}
 return [pscustomobject][ordered]@{StatusCode=$Status;ContentType='application/vnd.github+json';BodyBytes=$bytes;Location=$Location;Headers=@{requestId='mock-request';retryAfter='';rateLimitReset=''}}
}
function Set-MockQueue {
 param([object[]]$Responses)
 $queue=New-Object Collections.Queue
 foreach($response in $Responses){$queue.Enqueue($response)}
 $transport={
  param($Uri,$SendAuth,$MaxBytes)
  if($queue.Count -eq 0){throw 'Unexpected outbound HTTP request in test.'}
  return $queue.Dequeue()
 }.GetNewClosure()
 & $module {param($value)$script:GfxTransportOverride=$value} $transport
 return ,$queue
}
function Clear-MockTransport {& $module {$script:GfxTransportOverride=$null}}
function Get-TestCommitObject {
 param([string]$Sha)
 return [pscustomobject]@{
  sha=$Sha;html_url=('https://github.com/Sharnou/Sharnou-Compiler/commit/'+$Sha)
  commit=[pscustomobject]@{
   message='test commit';tree=[pscustomobject]@{sha=('b'*40)}
   author=[pscustomobject]@{date='2026-11-28T10:00:00Z'}
   committer=[pscustomobject]@{date='2026-11-28T10:01:00Z'}
  }
 }
}
function Get-TestRun {
 param([string]$Sha,[long]$Id=77)
 return [pscustomobject]@{
  id=$Id;workflow_id=9;run_number=3;run_attempt=1;name='Windows qualification';event='pull_request'
  status='completed';conclusion='success';head_sha=$Sha;head_branch='test-branch'
  created_at='2026-11-28T10:02:00Z';updated_at='2026-11-28T10:05:00Z'
  html_url='https://github.com/Sharnou/Sharnou-Compiler/actions/runs/77'
 }
}
$sha='a'*40
$repoObject=[pscustomobject]@{id=1442471501;full_name='Sharnou/Sharnou-Compiler';default_branch='Sharnou-Compiler';visibility='public';archived=$false;private=$false;html_url='https://github.com/Sharnou/Sharnou-Compiler'}
$artifact=[pscustomobject]@{id=501;name='qualification-evidence';size_in_bytes=1234;expired=$false;digest=('sha256:' + ('c'*64));created_at='2026-11-28T10:03:00Z';expires_at='2026-12-28T10:03:00Z';archive_download_url='https://api.github.com/repos/Sharnou/Sharnou-Compiler/actions/artifacts/501/zip'}

$status=Get-GfxGitHubCredentialStatus
Assert-GfxAdapter ($status.status -in @('NOT_CONFIGURED','CONFIGURED')) 'credential status reports only an explicit state'
Assert-GfxAdapter ($status.storage -eq 'DPAPI_CURRENT_USER') 'credential storage declares current-user DPAPI protection'
Assert-GfxAdapter ($status.PSObject.Properties.Name -notcontains 'token') 'credential status never returns token material'

$priorLocalAppData=$env:LOCALAPPDATA
$testLocalAppData=Join-Path $env:TEMP ('Sharnou-DGA-GFX04-CredentialTest-'+[Guid]::NewGuid().ToString('N'))
$testToken='ghp_dga_gfx_test_token_1234567890'
$testSecureToken=$null
try{
 $env:LOCALAPPDATA=$testLocalAppData
 $testSecureToken=ConvertTo-SecureString -String $testToken -AsPlainText -Force
 $configured=Set-GfxGitHubCredential -Token $testSecureToken
 $configuredStatus=Get-GfxGitHubCredentialStatus
 $storedCipher=[IO.File]::ReadAllText($configuredStatus.path)
 $recoveredToken=& $module {Get-GfxAuthToken}
 Assert-GfxAdapter ($configured.status -eq 'CONFIGURED' -and $configured.aclVerified) 'credential setup writes only after owner ACL verification'
 Assert-GfxAdapter ($configuredStatus.status -eq 'CONFIGURED' -and $configuredStatus.aclVerified) 'DPAPI credential file passes strict owner-only ACL verification'
 Assert-GfxAdapter ($storedCipher -ne $testToken -and $storedCipher.Length -gt $testToken.Length) 'credential file stores DPAPI ciphertext rather than plaintext token'
 Assert-GfxAdapter ($recoveredToken -ceq $testToken) 'DPAPI current-user credential round-trip succeeds'
 $recoveredToken=$null
 $removed=Remove-GfxGitHubCredential
 $afterRemove=Get-GfxGitHubCredentialStatus
 Assert-GfxAdapter ($removed.status -eq 'NOT_CONFIGURED' -and $afterRemove.status -eq 'NOT_CONFIGURED') 'credential removal deletes the encrypted token file'
}catch{
 Assert-GfxAdapter $false ('credential round-trip and ACL lifecycle: '+$_.Exception.Message)
}finally{
 if($null -ne $testSecureToken){$testSecureToken.Dispose()}
 $env:LOCALAPPDATA=$priorLocalAppData
 if(Test-Path -LiteralPath $testLocalAppData){Remove-Item -LiteralPath $testLocalAppData -Recurse -Force}
}

$requests=Set-MockQueue @((New-MockResponse -Object $repoObject))
$r=Get-GfxGitHubRepository
Assert-GfxAdapter ($r.repository -eq 'Sharnou/Sharnou-Compiler' -and $r.repositoryId -eq 1442471501) 'repository metadata is bound to the fixed repository identity'
Assert-GfxAdapter ($requests.Count -eq 0) 'repository call consumes exactly one bounded request'

$requests=Set-MockQueue @((New-MockResponse -Object ([pscustomobject]@{name='devagent-test';protected=$true;commit=[pscustomobject]@{sha=$sha;url='https://api.github.com/repos/Sharnou/Sharnou-Compiler/commits/'+$sha}})))
$b=Get-GfxGitHubBranch -BranchName 'devagent-test'
Assert-GfxAdapter ($b.commitSha -eq $sha -and $b.protected) 'branch lookup returns the canonical commit SHA'

$requests=Set-MockQueue @((New-MockResponse -Object (Get-TestCommitObject $sha)))
$c=Get-GfxGitHubCommit -Ref $sha
Assert-GfxAdapter ($c.sha -eq $sha -and $c.messageSha256.Length -eq 64) 'commit metadata hashes the message and preserves exact SHA'

$requests=Set-MockQueue @((New-MockResponse -Object (Get-TestCommitObject $sha)))
$pathRejected=$false
try{$null=Get-GfxGitHubFile -Path '../README.md' -Ref $sha}catch{$pathRejected=$true}
Assert-GfxAdapter $pathRejected 'source reader rejects parent traversal before making a request'
Assert-GfxAdapter ($requests.Count -eq 1) 'path rejection does not consume the queued transport response'

$fileBytes=(New-Object Text.UTF8Encoding($false)).GetBytes('hello')
$gitPrefix=(New-Object Text.UTF8Encoding($false)).GetBytes('blob 5'+[char]0)
$gitBytes=New-Object byte[] ($gitPrefix.Length+$fileBytes.Length)
[Buffer]::BlockCopy($gitPrefix,0,$gitBytes,0,$gitPrefix.Length);[Buffer]::BlockCopy($fileBytes,0,$gitBytes,$gitPrefix.Length,$fileBytes.Length)
$blobSha=[BitConverter]::ToString(([Security.Cryptography.SHA1]::Create()).ComputeHash($gitBytes)).Replace('-','').ToLowerInvariant()
$fileObject=[pscustomobject]@{type='file';encoding='base64';size=5;sha=$blobSha;content=[Convert]::ToBase64String($fileBytes)}
$requests=Set-MockQueue @((New-MockResponse -Object (Get-TestCommitObject $sha)),(New-MockResponse -Object $fileObject))
$f=Get-GfxGitHubFile -Path 'Tools/DevAgent/example.ps1' -Ref 'devagent-test'
Assert-GfxAdapter ($f.content -eq 'hello' -and $f.commitSha -eq $sha -and $f.gitBlobSha -eq $blobSha) 'source reader pins to commit SHA and verifies the Git blob hash'
Assert-GfxAdapter ($f.contentSha256.Length -eq 64 -and $f.byteCount -eq 5) 'source reader records SHA-256 and byte count'

$badFile=Copy-Object $fileObject;$badFile.sha=('d'*40)
$requests=Set-MockQueue @((New-MockResponse -Object (Get-TestCommitObject $sha)),(New-MockResponse -Object $badFile))
$blobRejected=$false
try{$null=Get-GfxGitHubFile -Path 'README.md' -Ref $sha}catch{$blobRejected=$true}
Assert-GfxAdapter $blobRejected 'source reader fails closed on a Git blob digest mismatch'

$prObject=[pscustomobject]@{
 number=44;state='open';draft=$true;merged_at=$null;html_url='https://github.com/Sharnou/Sharnou-Compiler/pull/44'
 created_at='2026-11-28T10:00:00Z';updated_at='2026-11-28T10:01:00Z'
 base=[pscustomobject]@{ref='devagent-gfx-campaign-planner-20261128';sha=('b'*40);repo=[pscustomobject]@{full_name='Sharnou/Sharnou-Compiler'}}
 head=[pscustomobject]@{ref='devagent-gfx-task-journal-20261128';sha=$sha;repo=[pscustomobject]@{full_name='Sharnou/Sharnou-Compiler'}}
}
$requests=Set-MockQueue @((New-MockResponse -Object $prObject))
$pr=Get-GfxGitHubPullRequest -PullRequestNumber 44
Assert-GfxAdapter ($pr.number -eq 44 -and $pr.draft -and -not $pr.merged -and $pr.headSha -eq $sha) 'pull request metadata preserves draft, merge and exact head state'

$requests=Set-MockQueue @((New-MockResponse -Object @($prObject)))
$singlePrList=Get-GfxGitHubPullRequests -PerPage 100
Assert-GfxAdapter ($singlePrList.count -eq 1 -and $singlePrList.pullRequests.Count -eq 1 -and $singlePrList.pullRequests[0].number -eq 44) 'pull request collection preserves a one-element JSON array'
Assert-GfxAdapter ($requests.Count -eq 0) 'single-item pull request collection completes without extra page requests'

$requests=Set-MockQueue @((New-MockResponse -Object @()))
$emptyPrList=Get-GfxGitHubPullRequests -PerPage 100
Assert-GfxAdapter ($emptyPrList.count -eq 0 -and $emptyPrList.pullRequests.Count -eq 0 -and -not $emptyPrList.truncated) 'pull request collection preserves an empty JSON array'

$secondPrObject=Copy-Object $prObject
$secondPrObject.number=45
$secondPrObject.head.ref='devagent-gfx-readonly-github-adapter-20261128'
$requests=Set-MockQueue @(
 (New-MockResponse -Object @($prObject,$secondPrObject)),
 (New-MockResponse -Object @())
)
$pagedPrList=Get-GfxGitHubPullRequests -PerPage 2
Assert-GfxAdapter ($pagedPrList.count -eq 2 -and $pagedPrList.pullRequests[0].number -eq 44 -and $pagedPrList.pullRequests[1].number -eq 45) 'pull request collection preserves array ordering across pages'
Assert-GfxAdapter ($requests.Count -eq 0) 'pull request pagination stops after a short final page'

$requests=Set-MockQueue @((New-MockResponse -Object ([pscustomobject]@{total_count=1;workflow_runs=@((Get-TestRun $sha))})))
$runs=Get-GfxGitHubWorkflowRuns -CommitSha $sha
Assert-GfxAdapter ($runs.workflowRuns.Count -eq 1 -and $runs.workflowRuns[0].headSha -eq $sha -and $runs.workflowRuns[0].conclusion -eq 'success') 'Actions result is bound to the queried exact commit'

$otherRun=Get-TestRun ('e'*40)
$requests=Set-MockQueue @((New-MockResponse -Object ([pscustomobject]@{total_count=1;workflow_runs=@($otherRun)})))
$wrongRunRejected=$false
try{$null=Get-GfxGitHubWorkflowRuns -CommitSha $sha}catch{$wrongRunRejected=$true}
Assert-GfxAdapter $wrongRunRejected 'workflow query rejects an unexpected head SHA rather than treating it as evidence'

$requests=Set-MockQueue @((New-MockResponse -Object ([pscustomobject]@{total_count=1;artifacts=@($artifact)})))
$artifacts=Get-GfxGitHubRunArtifacts -RunId 77
Assert-GfxAdapter ($artifacts.artifacts.Count -eq 1 -and $artifacts.artifacts[0].digest -eq ('sha256:'+('c'*64))) 'Actions artifact metadata retains GitHub SHA-256 digest and run binding'

$badArtifact=Copy-Object $artifact;$badArtifact.digest='sha1:bad'
$requests=Set-MockQueue @((New-MockResponse -Object ([pscustomobject]@{total_count=1;artifacts=@($badArtifact)})))
$badDigestRejected=$false
try{$null=Get-GfxGitHubRunArtifacts -RunId 77}catch{$badDigestRejected=$true}
Assert-GfxAdapter $badDigestRejected 'artifact metadata rejects unsupported digest algorithms'

$requests=Set-MockQueue @(
 (New-MockResponse -Object $repoObject),
 (New-MockResponse -Object (Get-TestCommitObject $sha)),
 (New-MockResponse -Object ([pscustomobject]@{total_count=1;workflow_runs=@((Get-TestRun $sha))})),
 (New-MockResponse -Object ([pscustomobject]@{total_count=1;artifacts=@($artifact)}))
)
$e=Get-GfxGitHubCommitEvidence -CommitSha $sha
$ev=Test-GfxGitHubEvidenceObject -Evidence $e
Assert-GfxAdapter $ev.valid 'commit evidence snapshot validates end-to-end'
Assert-GfxAdapter ($e.commit.sha -eq $sha -and $e.workflowRuns[0].headSha -eq $sha -and $e.artifacts[0].runId -eq 77) 'evidence links repository, exact commit, Actions run and artifact metadata'
Assert-GfxAdapter ($e.artifacts[0].digest -eq ('sha256:'+('c'*64))) 'evidence snapshot preserves the artifact digest without claiming payload verification'

$priorMaxPages=& $module {$script:GfxMaxPages}
try{
 & $module {$script:GfxMaxPages=1}
 $manyArtifacts=New-Object Collections.ArrayList
 for($n=0;$n -lt 100;$n++){
  $null=$manyArtifacts.Add([pscustomobject]@{id=(1000+$n);name=('artifact-'+$n);size_in_bytes=512;expired=$false;digest=('sha256:'+('c'*64));created_at='2026-11-28T10:03:00Z';expires_at='2026-12-28T10:03:00Z';archive_download_url=('https://api.github.com/repos/Sharnou/Sharnou-Compiler/actions/artifacts/'+(1000+$n)+'/zip')})
 }
 $requests=Set-MockQueue @(
  (New-MockResponse -Object $repoObject),
  (New-MockResponse -Object (Get-TestCommitObject $sha)),
  (New-MockResponse -Object ([pscustomobject]@{total_count=1;workflow_runs=@((Get-TestRun $sha))})),
  (New-MockResponse -Object ([pscustomobject]@{total_count=101;artifacts=@($manyArtifacts.ToArray())}))
 )
 $truncatedEvidence=Get-GfxGitHubCommitEvidence -CommitSha $sha
 Assert-GfxAdapter ($truncatedEvidence.artifacts.Count -eq 100 -and $truncatedEvidence.truncated) 'commit evidence propagates artifact pagination truncation'
}catch{
 Assert-GfxAdapter $false ('artifact truncation propagation: '+$_.Exception.Message)
}finally{
 & $module {param($value)$script:GfxMaxPages=$value} $priorMaxPages
}

$badEvidence=Copy-Object $e;$badEvidence.workflowRuns[0].headSha=('e'*40)
Assert-GfxAdapter (-not(Test-GfxGitHubEvidenceObject -Evidence $badEvidence).valid) 'evidence validator rejects stale or mismatched workflow head'
$badEvidence=Copy-Object $e;$badEvidence.artifacts[0].runId=999
Assert-GfxAdapter (-not(Test-GfxGitHubEvidenceObject -Evidence $badEvidence).valid) 'evidence validator rejects artifacts detached from their captured run'
$badEvidence=Copy-Object $e;$badEvidence.commit.sha='ABC'
Assert-GfxAdapter (-not(Test-GfxGitHubEvidenceObject -Evidence $badEvidence).valid) 'evidence validator rejects malformed commit identity'

$requests=Set-MockQueue @(
 (New-MockResponse -Object $prObject),
 (New-MockResponse -Object $repoObject),
 (New-MockResponse -Object (Get-TestCommitObject $sha)),
 (New-MockResponse -Object ([pscustomobject]@{total_count=1;workflow_runs=@((Get-TestRun $sha))})),
 (New-MockResponse -Object ([pscustomobject]@{total_count=1;artifacts=@($artifact)}))
)
$pe=Get-GfxGitHubPullRequestEvidence -PullRequestNumber 44
Assert-GfxAdapter ($pe.pullRequest.number -eq 44 -and $pe.pullRequest.headSha -eq $pe.commit.sha) 'pull request evidence binds PR head to commit evidence'

$badEvidence=Copy-Object $e
Add-Member -InputObject $badEvidence -NotePropertyName untrustedExtra -NotePropertyValue 'unexpected'
Assert-GfxAdapter (-not(Test-GfxGitHubEvidenceObject -Evidence $badEvidence).valid) 'evidence validator rejects unsupported root properties'
$badEvidence=Copy-Object $e;$badEvidence.commit.authorDateUtc='not-a-date'
Assert-GfxAdapter (-not(Test-GfxGitHubEvidenceObject -Evidence $badEvidence).valid) 'evidence validator rejects malformed commit timestamps'
$badEvidence=Copy-Object $e;$badEvidence.workflowRuns=@($badEvidence.workflowRuns)+@($badEvidence.workflowRuns)
Assert-GfxAdapter (-not(Test-GfxGitHubEvidenceObject -Evidence $badEvidence).valid) 'evidence validator rejects duplicate workflow run identities'

$journalRoot=Join-Path $env:TEMP ('Sharnou-DGA-GFX04-JournalTest-'+[Guid]::NewGuid().ToString('N'))
try{
 Import-Module (Join-Path $root 'Tools\DevAgent\GfxTaskJournal.psm1') -Force
 $persisted=Save-GfxGitHubEvidenceCheckpoint -Evidence $pe -StateDirectory $journalRoot
 $journalStatus=Get-GfxTaskJournalStatus -StateDirectory $journalRoot
 $journalTask=@($journalStatus.tasks|Where-Object{$_.taskId -eq $persisted.taskId})
 $journalCheckpoint=Get-GfxTaskCheckpoint -StateDirectory $journalRoot -TaskId $persisted.taskId
 Assert-GfxAdapter ($persisted.persisted -and $persisted.state -eq 'COMPLETED' -and $journalStatus.integrity -eq 'PASS') 'GitHub evidence is checkpointed and completed through the DGA-0.3 journal'
 Assert-GfxAdapter ($journalStatus.campaignId -eq 'sharnou.devagent.graphics-automation' -and $journalStatus.purpose -eq 'durable_dga_gfx_milestone_execution') 'DevAgent evidence uses an isolated journal identity and purpose'
 Assert-GfxAdapter ($journalTask.Count -eq 1 -and $journalTask[0].milestoneId -eq 'DGA-GFX-0.4' -and $journalTask[0].state -eq 'COMPLETED') 'journal records a typed DGA-GFX-0.4 qualification task'
 Assert-GfxAdapter ($journalCheckpoint.state.snapshot.payloadKind -eq 'metadata-only' -and $journalCheckpoint.state.snapshot.PSObject.Properties.Name -notcontains 'content') 'checkpoint stores bounded metadata and excludes source content'
 $journalCountBefore=$journalStatus.recordCount
 $persistedAgain=Save-GfxGitHubEvidenceCheckpoint -Evidence $pe -StateDirectory $journalRoot
 $journalStatusAfter=Get-GfxTaskJournalStatus -StateDirectory $journalRoot
 Assert-GfxAdapter ($persistedAgain.status -eq 'DUPLICATE_NOOP' -and $journalStatusAfter.recordCount -eq $journalCountBefore) 'identical evidence replay is idempotent and appends no records'
}catch{
 Assert-GfxAdapter $false ('DGA journal evidence persistence: '+$_.Exception.Message)
}finally{
 if(Test-Path -LiteralPath $journalRoot){Remove-Item -LiteralPath $journalRoot -Recurse -Force}
}
$requests=Set-MockQueue @((New-MockResponse -Status 403 -Object ([pscustomobject]@{message='rate limit'})))
$httpBlocked=$false
try{$null=Get-GfxGitHubRepository}catch{$httpBlocked=$_.Exception.Message -match 'HTTP 403'}
Assert-GfxAdapter $httpBlocked 'HTTP/API failures are surfaced without returning response bodies'

$requests=Set-MockQueue @((New-MockResponse -Object $repoObject),(New-MockResponse -Object $repoObject))
$badRefRejected=$false
try{$null=Get-GfxGitHubWorkflowRuns -CommitSha 'ABC'}catch{$badRefRejected=$true}
Assert-GfxAdapter $badRefRejected 'Actions adapter rejects abbreviated or malformed commit references'

$moduleText=[IO.File]::ReadAllText((Join-Path $root 'Tools\DevAgent\GfxGitHubAdapter.psm1'))
$cliText=[IO.File]::ReadAllText((Join-Path $root 'Tools\DevAgent\Invoke-GfxGitHubAdapter.ps1'))
Assert-GfxAdapter ($moduleText -match "Method='GET'" -and $moduleText -match 'AllowAutoRedirect=\$false') 'network transport is explicit GET-only and disables automatic redirects'
Assert-GfxAdapter ($moduleText -notmatch '(?i)Start-Process|Invoke-Expression|cmd\.exe|powershell\.exe|git\.exe|curl\.exe|wget\.exe') 'adapter does not launch processes, shells or external tools'
Assert-GfxAdapter ($moduleText -notmatch '(?i)\$request\.Method\s*=\s*[''\"](?:POST|PATCH|PUT|DELETE)[''\"]') 'adapter source contains no HTTP write-method capability'
Assert-GfxAdapter ($cliText -notmatch '(?i)Start-Process|Invoke-Expression|Invoke-WebRequest|Invoke-RestMethod') 'CLI has no shell or alternate network execution path'

Clear-MockTransport
Write-Host ''
Write-Host ("DGA-GFX-0.4 tests: {0} passed; {1} failed; {2} total." -f $script:Passed,$script:Failed,($script:Passed+$script:Failed))
if($script:Failed -ne 0){exit 1}
exit 0

