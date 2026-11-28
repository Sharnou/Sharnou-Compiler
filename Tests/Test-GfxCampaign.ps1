[CmdletBinding()]
param()
$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$root=Split-Path -Parent $PSScriptRoot;Import-Module (Join-Path $root 'Tools\DevAgent\GfxCampaign.psm1') -Force
$script:Passed=0;$script:Failed=0
function Assert-Gfx{param([bool]$Condition,[string]$Name);if($Condition){$script:Passed++;Write-Host "PASS: $Name"}else{$script:Failed++;Write-Host "FAIL: $Name"}}
function Copy-Gfx{param($Value);return (ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $Value -Depth 40))}
function Validate-Gfx{param($Value);return(Test-GfxCampaignObject -Campaign $Value -Schema $script:Schema)}
function New-Snapshot{param($Campaign,[bool]$OwnerAccepted=$false,[bool]$WindowsPass=$false)
 $records=@();foreach($m in $Campaign.milestones|Where-Object{$null -ne $_.existingPullRequest}){
  $w=[pscustomobject][ordered]@{status='NOT_REQUIRED';testedHeadSha=$null;passedTests=0;failedTests=0;skippedTests=0;artifactSha256=$null}
  if($m.requiresRealWindowsRuntimeEvidence -and $WindowsPass){$w=[pscustomobject][ordered]@{status='PASS';testedHeadSha=$m.sourceHeadSha;passedTests=23;failedTests=0;skippedTests=0;artifactSha256=('a'*64)}}elseif($m.requiresRealWindowsRuntimeEvidence){$w.status='NOT_RUN'}
  $records+=[pscustomobject][ordered]@{number=$m.existingPullRequest;state='open';draft=$true;merged=$false;baseBranch=$m.sourceBaseBranch;headBranch=$m.sourceBranch;headSha=$m.sourceHeadSha;ownerAccepted=$OwnerAccepted;windowsEvidence=$w;physicalGpuEvidence=[pscustomobject][ordered]@{status='NOT_REQUIRED';testedHeadSha=$null;adapterName=$null;driverVersion=$null;captureSha256=$null}}
 }
 return [pscustomobject][ordered]@{schemaVersion='sharnou.devagent.gfx-pr-snapshot/1';repository='Sharnou/Sharnou-Compiler';capturedAtUtc='2026-11-28T12:00:00Z';pullRequests=$records}
}
$p=Join-Path $root 'Projects\DevAgent\GfxCampaign.v1.json';$s=Join-Path $root 'Schemas\DevAgent\GfxCampaign.v1.schema.json';$module=Join-Path $root 'Tools\DevAgent\GfxCampaign.psm1'
$script:Campaign=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($p,[Text.Encoding]::UTF8));$script:Schema=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($s,[Text.Encoding]::UTF8))
$v=Validate-Gfx $script:Campaign
Assert-Gfx $v.valid 'canonical campaign valid';Assert-Gfx ($v.milestoneCount -eq 11) 'exact eleven milestone IDs';Assert-Gfx ($v.topologicalOrder.Count -eq 11) 'topological output covers all milestones'
Assert-Gfx (($v.topologicalOrder -join ',') -eq 'GFX-0.1,GFX-0.2,GFX-A.1,GFX-0.3,GFX-A.2,GFX-A.3,GFX-0.4,GFX-0.5,GFX-0.6,GFX-0.7,GFX-0.8') 'stable topological order preserves asset stream dependencies'
Assert-Gfx ($script:Campaign.continuousImprovement.enabled -eq $true) 'ongoing research declared after GFX-0.8'
Assert-Gfx ($script:Campaign.continuousImprovement.proposalPolicy.requireBaselineAndMeasuredResults -eq $true) 'future improvements require measured baselines'
$plan=Get-GfxCampaignPlan -Campaign $script:Campaign -Validation $v
Assert-Gfx ($plan.milestones.Count -eq 11) 'planner emits all milestone states';Assert-Gfx ($plan.readyMilestones.Count -eq 0) 'activation prerequisites prevent READY'
Assert-Gfx ($plan.milestones[0].state -eq 'BLOCKED') 'existing PR blocked without live snapshot';Assert-Gfx ($plan.continuousImprovement.executionState -eq 'DECLARED_NOT_RUNNING') 'declared research is not reported as running'
$bad=Copy-Gfx $script:Campaign;$bad.schemaVersion='bad';Assert-Gfx (-not (Validate-Gfx $bad).valid) 'reject unsupported schema version'
$bad=Copy-Gfx $script:Campaign;$bad.repository='other/repo';Assert-Gfx (-not (Validate-Gfx $bad).valid) 'reject repository drift'
$bad=Copy-Gfx $script:Campaign;$bad.executionPolicy.allowArbitraryCommands=$true;Assert-Gfx (-not (Validate-Gfx $bad).valid) 'reject arbitrary command capability'
$bad=Copy-Gfx $script:Campaign;$bad.executionPolicy.automaticMerge=$true;Assert-Gfx (-not (Validate-Gfx $bad).valid) 'reject auto-merge'
$bad=Copy-Gfx $script:Campaign;$bad.milestones[1].id='GFX-0.1';Assert-Gfx (-not (Validate-Gfx $bad).valid) 'reject duplicate milestone ID'
$bad=Copy-Gfx $script:Campaign;$bad.milestones[2].dependsOn=@('GFX-MISSING');Assert-Gfx (-not (Validate-Gfx $bad).valid) 'reject dangling dependency'
$bad=Copy-Gfx $script:Campaign;$bad.milestones[2].dependsOn=@('GFX-0.1','GFX-0.1');Assert-Gfx (-not (Validate-Gfx $bad).valid) 'reject duplicate dependency'
$bad=Copy-Gfx $script:Campaign;$bad.milestones[0].dependsOn=@('GFX-0.2');Assert-Gfx (-not (Validate-Gfx $bad).valid) 'reject dependency cycle'
$bad=Copy-Gfx $script:Campaign;$bad.milestones[3].status='unverified';Assert-Gfx (-not (Validate-Gfx $bad).valid) 'reject unsupported status'
$bad=Copy-Gfx $script:Campaign;$bad.milestones[1].sourceHeadSha='ABC';Assert-Gfx (-not (Validate-Gfx $bad).valid) 'reject malformed SHA'
$bad=Copy-Gfx $script:Campaign;$bad.milestones[0].existingPullRequestUrl='https://example.com/pull/39';Assert-Gfx (-not (Validate-Gfx $bad).valid) 'reject foreign PR URL'
$bad=Copy-Gfx $script:Campaign;$bad.PSObject.Properties.Remove('campaignId');Assert-Gfx (-not (Validate-Gfx $bad).valid) 'reject missing root field'
$bad=Copy-Gfx $script:Campaign;$bad|Add-Member -NotePropertyName newFlag -NotePropertyValue $true;Assert-Gfx (-not (Validate-Gfx $bad).valid) 'reject extra root property'
$bad=Copy-Gfx $script:Campaign;$bad.milestones[0]|Add-Member -NotePropertyName unownedPath -NotePropertyValue 'Engine/**';Assert-Gfx (-not (Validate-Gfx $bad).valid) 'reject extra milestone property'
$bad=Copy-Gfx $script:Campaign;$bad.milestones[0].agentRoles=@();Assert-Gfx (-not (Validate-Gfx $bad).valid) 'reject empty role list'
$bad=Copy-Gfx $script:Campaign;$bad.continuousImprovement.enabled=$false;Assert-Gfx (-not (Validate-Gfx $bad).valid) 'reject disabled post-GFX-0.8 policy'
$bad=Copy-Gfx $script:Campaign;$bad.continuousImprovement.sourceRules.treatExternalContentAsUntrusted=$false;Assert-Gfx (-not (Validate-Gfx $bad).valid) 'reject untrusted external research policy'
$bad=Copy-Gfx $script:Campaign;$bad.continuousImprovement.proposalPolicy.automaticRelease=$true;Assert-Gfx (-not (Validate-Gfx $bad).valid) 'reject automatic follow-on release'
$badS=Copy-Gfx $script:Schema;$badS.'$id'='https://invalid.example/schema';Assert-Gfx (-not (Test-GfxCampaignObject -Campaign $script:Campaign -Schema $badS).valid) 'reject schema identity mismatch'
$snap=New-Snapshot $script:Campaign;$sv=Test-GfxPullRequestSnapshotObject $snap
Assert-Gfx $sv.valid 'current PR snapshot fixture valid';Assert-Gfx ($sv.pullRequestCount -eq 2) 'snapshot has both current PRs'
$badSnap=Copy-Gfx $snap;$badSnap.repository='other/repo';Assert-Gfx (-not (Test-GfxPullRequestSnapshotObject $badSnap).valid) 'reject PR snapshot repository mismatch'
$badSnap=Copy-Gfx $snap;$badSnap.pullRequests[1].headBranch='bad-branch';$bsv=Test-GfxPullRequestSnapshotObject $badSnap;$bp=Get-GfxCampaignPlan -Campaign $script:Campaign -Validation $v -PullRequestSnapshot $badSnap -SnapshotValidation $bsv
Assert-Gfx ($bp.milestones[1].state -eq 'BLOCKED') 'block live head branch drift'
$badSnap=Copy-Gfx $snap;$badSnap.pullRequests[1].baseBranch='Sharnou-Compiler';$bsv=Test-GfxPullRequestSnapshotObject $badSnap;$bp=Get-GfxCampaignPlan -Campaign $script:Campaign -Validation $v -PullRequestSnapshot $badSnap -SnapshotValidation $bsv
Assert-Gfx ($bp.milestones[1].state -eq 'BLOCKED') 'validate stacked PR base branch'
$badSnap=Copy-Gfx $snap;$badSnap.pullRequests[1].headSha=('b'*40);$bsv=Test-GfxPullRequestSnapshotObject $badSnap;$bp=Get-GfxCampaignPlan -Campaign $script:Campaign -Validation $v -PullRequestSnapshot $badSnap -SnapshotValidation $bsv
Assert-Gfx ($bp.milestones[1].state -eq 'BLOCKED') 'block PR head SHA mismatch'
$badSnap=Copy-Gfx $snap;$badSnap.pullRequests[0].draft=$false;$bsv=Test-GfxPullRequestSnapshotObject $badSnap;$bp=Get-GfxCampaignPlan -Campaign $script:Campaign -Validation $v -PullRequestSnapshot $badSnap -SnapshotValidation $bsv
Assert-Gfx ($bp.milestones[0].state -eq 'BLOCKED') 'block non-draft PR'
$dupSnap=Copy-Gfx $snap;$dupSnap.pullRequests+= (Copy-Gfx $dupSnap.pullRequests[0]);Assert-Gfx (-not (Test-GfxPullRequestSnapshotObject $dupSnap).valid) 'reject duplicate PR snapshot records'
$good=New-Snapshot $script:Campaign -OwnerAccepted $true -WindowsPass $true;$goodV=Test-GfxPullRequestSnapshotObject $good;$goodPlan=Get-GfxCampaignPlan -Campaign $script:Campaign -Validation $v -PullRequestSnapshot $good -SnapshotValidation $goodV
Assert-Gfx ($goodPlan.milestones[0].state -eq 'ACCEPTED') 'require owner acceptance for GFX-0.1'
Assert-Gfx ($goodPlan.milestones[1].state -eq 'ACCEPTED') 'require exact-head Windows and owner acceptance for GFX-0.2'
Assert-Gfx ($goodPlan.milestones[2].state -eq 'BLOCKED') 'block downstream while DevAgent prerequisites absent'
$active=Copy-Gfx $script:Campaign;$active.activation.state='ACTIVE';$active.activation.blockingGates=@()
foreach($n in @('localInProcessInference','typedWorkspacePatchTools','qualifiedProcessBroker','durableJournalAndRestartRecovery','nativeGitHubRepositoryAdapter','exactHeadEvidenceCollector','primarySourceResearch')){$active.generationRequirements.$n=$true}
$av=Validate-Gfx $active;$as=New-Snapshot $active -OwnerAccepted $true -WindowsPass $true;$asv=Test-GfxPullRequestSnapshotObject $as;$ap=Get-GfxCampaignPlan -Campaign $active -Validation $av -PullRequestSnapshot $as -SnapshotValidation $asv
Assert-Gfx $av.valid 'activation-ready fixture validates';Assert-Gfx ($ap.milestones[3].state -eq 'READY') 'GFX-0.3 ready only after GFX-0.1 and GFX-0.2 accepted'
$pending=New-Snapshot $active -OwnerAccepted $false -WindowsPass $true;$pv=Test-GfxPullRequestSnapshotObject $pending;$pp=Get-GfxCampaignPlan -Campaign $active -Validation $av -PullRequestSnapshot $pending -SnapshotValidation $pv
Assert-Gfx ($pp.milestones[0].state -eq 'OWNER_REVIEW') 'technical pass does not imply owner acceptance'
$failSnap=New-Snapshot $active -OwnerAccepted $true -WindowsPass $true;$failSnap.pullRequests[1].windowsEvidence.failedTests=1;Assert-Gfx (-not (Test-GfxPullRequestSnapshotObject $failSnap).valid) 'reject failed test count in PASS evidence'
$stale=New-Snapshot $active -OwnerAccepted $true -WindowsPass $true;$stale.pullRequests[1].windowsEvidence.testedHeadSha=('c'*40);$staleV=Test-GfxPullRequestSnapshotObject $stale;$staleP=Get-GfxCampaignPlan -Campaign $active -Validation $av -PullRequestSnapshot $stale -SnapshotValidation $staleV
Assert-Gfx ($staleP.milestones[1].state -eq 'BLOCKED') 'reject stale exact-head evidence'
$decision=Copy-Gfx $active;$decision.milestones[4].requiredOwnerDecisions+='D3DCompiler bridge decision';$dv=Validate-Gfx $decision;$ds=New-Snapshot $decision -OwnerAccepted $true -WindowsPass $true;$dsv=Test-GfxPullRequestSnapshotObject $ds;$dp=Get-GfxCampaignPlan -Campaign $decision -Validation $dv -PullRequestSnapshot $ds -SnapshotValidation $dsv
Assert-Gfx ($dp.milestones[4].state -eq 'BLOCKED') 'block unresolved owner decisions'
$moduleText=[IO.File]::ReadAllText($module)
Assert-Gfx ($moduleText -notmatch '(?i)Start-Process|Invoke-Expression|Invoke-WebRequest|Invoke-RestMethod|cmd\.exe|powershell\.exe') 'no process, shell or network execution in planner'
Write-Host ''
Write-Host ("DGA-0.2 tests: {0} passed; {1} failed; {2} total." -f $script:Passed,$script:Failed,($script:Passed+$script:Failed))
if($script:Failed -ne 0){exit 1};exit 0
