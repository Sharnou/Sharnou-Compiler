$script:GfxExpectedIds=@('GFX-0.1','GFX-0.2','GFX-0.3','GFX-0.4','GFX-0.5','GFX-0.6','GFX-A.1','GFX-A.2','GFX-A.3','GFX-0.7','GFX-0.8')
function Add-GfxError{param([System.Collections.ArrayList]$Errors,[string]$Message)$null=$Errors.Add($Message)}
function Get-GfxNames{param($Object)if($null -eq $Object){return @()};return @($Object.PSObject.Properties|ForEach-Object{[string]$_.Name})}
function Test-GfxBool{param($Value)return ($Value -is [bool])}
function Test-GfxInt{param($Value)return (($Value -is [int]) -or ($Value -is [long]))}
function Test-GfxHex{param([string]$Value,[int]$Length)return ($Value -match ('^[0-9a-f]{'+$Length+'}$'))}
function Assert-GfxObject{
 param($Object,[string[]]$Expected,[string]$Path,[System.Collections.ArrayList]$Errors)
 if($null -eq $Object -or $Object -is [string] -or $Object -is [System.Array]){Add-GfxError $Errors "$Path must be an object.";return}
 $actual=Get-GfxNames $Object
 foreach($name in $Expected){if($actual -notcontains $name){Add-GfxError $Errors "$Path is missing '$name'."}}
 foreach($name in $actual){if($Expected -notcontains $name){Add-GfxError $Errors "$Path has unsupported property '$name'."}}
}
function Assert-GfxList{
 param($Value,[string]$Path,[System.Collections.ArrayList]$Errors,[int]$Min=0,[int]$Max=500,[int]$MaxLength=500,[switch]$Unique)
 if($Value -isnot [System.Array]){Add-GfxError $Errors "$Path must be an array.";return}
 if($Value.Count -lt $Min -or $Value.Count -gt $Max){Add-GfxError $Errors "$Path count is outside [$Min,$Max]."}
 $seen=@{};foreach($item in $Value){
  if($item -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$item)){Add-GfxError $Errors "$Path contains an empty or non-string item.";continue}
  if($item.Length -gt $MaxLength){Add-GfxError $Errors "$Path contains an oversized string."}
  if($Unique){if($seen.ContainsKey([string]$item)){Add-GfxError $Errors "$Path contains duplicate '$item'."}else{$seen[[string]$item]=$true}}
 }
}
function Assert-GfxBoundedInt{param($Value,[string]$Path,[int]$Min,[int]$Max,[System.Collections.ArrayList]$Errors)if (-not (Test-GfxInt $Value)){Add-GfxError $Errors "$Path must be an integer.";return};if([long]$Value -lt $Min -or [long]$Value -gt $Max){Add-GfxError $Errors "$Path is outside its permitted range."}}
function Get-GfxTopologicalOrder{
 param($Campaign)
 $items=@($Campaign.milestones);$remaining=@{};$done=@{};$ordered=New-Object System.Collections.ArrayList
 foreach($m in $items){$remaining[[string]$m.id]=@($m.dependsOn).Count}
 while($true){
  $ready=@();foreach($m in $items){$id=[string]$m.id;if (-not $done.ContainsKey($id)-and $remaining.ContainsKey($id)-and $remaining[$id]-eq 0){$ready+=$id}}
  if($ready.Count -eq 0){break}
  foreach($id in $ready){if($done.ContainsKey($id)){continue};$done[$id]=$true;$null=$ordered.Add($id);foreach($m in $items){if(@($m.dependsOn)-contains $id){$child=[string]$m.id;if($remaining.ContainsKey($child)){$remaining[$child]=[int]$remaining[$child]-1}}}}
 }
 return @($ordered.ToArray())
}
function Test-GfxCampaignObject{
 [CmdletBinding()]param([Parameter(Mandatory=$true)]$Campaign,[Parameter(Mandatory=$true)]$Schema)
 $errors=New-Object System.Collections.ArrayList;$root=@('schemaVersion','campaignId','repository','defaultBranch','requestedMode','activation','executionPolicy','generationRequirements','milestones','globalAcceptance','continuousImprovement')
 if($null -eq $Campaign -or $Campaign -is [string] -or $Campaign -is [System.Array]){Add-GfxError $errors 'Campaign root must be an object.';return [pscustomobject][ordered]@{valid=$false;errors=@($errors.ToArray());milestoneCount=0;topologicalOrder=@()}}
 Assert-GfxObject $Campaign $root 'campaign' $errors
 if($Campaign.schemaVersion -ne 'sharnou.devagent.gfx-campaign/1'){Add-GfxError $errors 'Unsupported schemaVersion.'}
 if($Campaign.campaignId -ne 'sharnou.graphics-compiler'){Add-GfxError $errors 'Invalid campaignId.'}
 if($Campaign.repository -ne 'Sharnou/Sharnou-Compiler'){Add-GfxError $errors 'Invalid repository identity.'}
 if($Campaign.defaultBranch -ne 'Sharnou-Compiler'){Add-GfxError $errors 'Invalid default branch.'}
 if($Campaign.requestedMode -ne 'automatic_generate_validate_and_open_draft_prs'){Add-GfxError $errors 'Unsupported requestedMode.'}
 if($null -eq $Schema -or $Schema.'$schema' -ne 'https://json-schema.org/draft/2020-12/schema' -or $Schema.'$id' -ne 'https://sharnou.dev/schemas/devagent/gfx-campaign/v1.json'){Add-GfxError $errors 'Campaign schema identity is invalid.'}
 else{
  if($Schema.additionalProperties -ne $false){Add-GfxError $errors 'Schema must reject additional root properties.'}
  foreach($n in $root){if(@($Schema.required)-notcontains $n){Add-GfxError $errors "Schema required list omits '$n'."}}
  if(@($Schema.required).Count -ne $root.Count){Add-GfxError $errors 'Schema root required count is wrong.'}
  if($Schema.properties.milestones.minItems -ne 11 -or $Schema.properties.milestones.maxItems -ne 11){Add-GfxError $errors 'Schema must require eleven milestones.'}
  if($null -eq $Schema.properties.continuousImprovement){Add-GfxError $errors 'Schema lacks continuousImprovement.'}
  if($null -eq $Schema.'$defs'.milestone.properties.sourceBaseBranch){Add-GfxError $errors 'Schema lacks sourceBaseBranch.'}
 }
 Assert-GfxObject $Campaign.activation @('state','blockingGates','automaticMerge') 'activation' $errors
 if(@('BLOCKED_UNTIL_DEVAGENT_PREREQUISITES_PASS','READY_FOR_OWNER_ACTIVATION','ACTIVE','PAUSED','STOPPED')-notcontains [string]$Campaign.activation.state){Add-GfxError $errors 'Invalid activation state.'}
 Assert-GfxList $Campaign.activation.blockingGates 'activation.blockingGates' $errors 0 100 160 -Unique
 if($Campaign.activation.automaticMerge -ne $false){Add-GfxError $errors 'automaticMerge must remain false.'}
 $policy=@('directDefaultBranchWrites','automaticMerge','automaticRelease','draftPullRequestsOnly','maxConcurrentMilestones','maxRepairAttemptsPerMilestone','maxFilesPerPatch','maxChangedBytesPerPatch','requireIsolatedWorktree','requireBaselineSnapshot','requireExactHeadWindowsEvidence','requireIndependentPatchReview','requireHumanAcceptanceBeforeDownstreamIntegration','allowArbitraryCommands','allowDownloadedExecutableExecution','allowUnapprovedCompilerDependencies')
 Assert-GfxObject $Campaign.executionPolicy $policy 'executionPolicy' $errors
 foreach($n in @('directDefaultBranchWrites','automaticMerge','automaticRelease','allowArbitraryCommands','allowDownloadedExecutableExecution','allowUnapprovedCompilerDependencies')){if($Campaign.executionPolicy.$n -ne $false){Add-GfxError $errors "$n must be false."}}
 foreach($n in @('draftPullRequestsOnly','requireIsolatedWorktree','requireBaselineSnapshot','requireExactHeadWindowsEvidence','requireIndependentPatchReview','requireHumanAcceptanceBeforeDownstreamIntegration')){if($Campaign.executionPolicy.$n -ne $true){Add-GfxError $errors "$n must be true."}}
 Assert-GfxBoundedInt $Campaign.executionPolicy.maxConcurrentMilestones 'maxConcurrentMilestones' 1 2 $errors
 Assert-GfxBoundedInt $Campaign.executionPolicy.maxRepairAttemptsPerMilestone 'maxRepairAttemptsPerMilestone' 1 3 $errors
 Assert-GfxBoundedInt $Campaign.executionPolicy.maxFilesPerPatch 'maxFilesPerPatch' 1 20 $errors
 Assert-GfxBoundedInt $Campaign.executionPolicy.maxChangedBytesPerPatch 'maxChangedBytesPerPatch' 1024 1048576 $errors
 $gen=@('localInProcessInference','typedWorkspacePatchTools','qualifiedProcessBroker','durableJournalAndRestartRecovery','nativeGitHubRepositoryAdapter','exactHeadEvidenceCollector','primarySourceResearch','optionalRemoteProviders')
 Assert-GfxObject $Campaign.generationRequirements $gen 'generationRequirements' $errors
 foreach($n in $gen){if (-not (Test-GfxBool $Campaign.generationRequirements.$n)){Add-GfxError $errors "$n must be Boolean."}}
 $ci=@('enabled','afterMilestone','researchMode','researchDomains','sourceRules','improvementLoop','proposalPolicy','notAutomatic')
 Assert-GfxObject $Campaign.continuousImprovement $ci 'continuousImprovement' $errors
 if($Campaign.continuousImprovement.enabled -ne $true){Add-GfxError $errors 'Continuous improvement must be enabled.'}
 if($Campaign.continuousImprovement.afterMilestone -ne 'GFX-0.8'){Add-GfxError $errors 'Continuous improvement must start after GFX-0.8.'}
 if($Campaign.continuousImprovement.researchMode -ne 'ongoing_primary_source_research'){Add-GfxError $errors 'Invalid ongoing research mode.'}
 Assert-GfxList $Campaign.continuousImprovement.researchDomains 'continuousImprovement.researchDomains' $errors 8 32 160 -Unique
 Assert-GfxList $Campaign.continuousImprovement.improvementLoop 'continuousImprovement.improvementLoop' $errors 5 12 300
 Assert-GfxList $Campaign.continuousImprovement.notAutomatic 'continuousImprovement.notAutomatic' $errors 2 12 300
 Assert-GfxObject $Campaign.continuousImprovement.sourceRules @('preferPrimarySources','recordRetrievedAtUtc','recordVersionAndContentSha256','treatExternalContentAsUntrusted') 'sourceRules' $errors
 foreach($n in @('preferPrimarySources','recordRetrievedAtUtc','recordVersionAndContentSha256','treatExternalContentAsUntrusted')){if($Campaign.continuousImprovement.sourceRules.$n -ne $true){Add-GfxError $errors "$n must be true."}}
 Assert-GfxObject $Campaign.continuousImprovement.proposalPolicy @('createVersionedFollowOnMilestones','requireBaselineAndMeasuredResults','requireIndependentReview','requireHumanAcceptance','automaticMerge','automaticRelease') 'proposalPolicy' $errors
 foreach($n in @('createVersionedFollowOnMilestones','requireBaselineAndMeasuredResults','requireIndependentReview','requireHumanAcceptance')){if($Campaign.continuousImprovement.proposalPolicy.$n -ne $true){Add-GfxError $errors "$n must be true."}}
 foreach($n in @('automaticMerge','automaticRelease')){if($Campaign.continuousImprovement.proposalPolicy.$n -ne $false){Add-GfxError $errors "$n must be false."}}
 if($Campaign.milestones -isnot [System.Array]){Add-GfxError $errors 'milestones must be an array.'}else{
  if($Campaign.milestones.Count -ne 11){Add-GfxError $errors 'Campaign must contain eleven milestones.'}
  $required=@('id','title','workstream','status','dependsOn','agentRoles','allowedPaths','deliverables','acceptanceGates','hardStops','requiresRealWindowsRuntimeEvidence','requiresPhysicalGpuEvidence','requiredOwnerDecisions')
  $allowed=@('id','title','workstream','status','existingPullRequest','existingPullRequestUrl','sourceBaseBranch','sourceBranch','sourceHeadSha','dependsOn','agentRoles','allowedPaths','deliverables','acceptanceGates','hardStops','requiresRealWindowsRuntimeEvidence','requiresPhysicalGpuEvidence','requiredOwnerDecisions')
  $seen=@{}
  foreach($m in $Campaign.milestones){
   $id=[string]$m.id
   $actualFields=Get-GfxNames $m
   foreach($n in $required){if($actualFields -notcontains $n){Add-GfxError $errors "$id omits required '$n'."}}
   foreach($n in $actualFields){if($allowed -notcontains $n){Add-GfxError $errors "$id has unsupported property '$n'."}}
   if($id -notmatch '^GFX-(0\.[1-8]|A\.[1-3])$'){Add-GfxError $errors "Invalid milestone ID '$id'."}
   if($seen.ContainsKey($id)){Add-GfxError $errors "Duplicate milestone ID '$id'."}else{$seen[$id]=$true}
   if($m.title -isnot [string] -or $m.title.Length -lt 4 -or $m.title.Length -gt 160){Add-GfxError $errors "$id title invalid."}
   if(@('shader_compiler','asset_analysis','ide','gpu_runtime')-notcontains [string]$m.workstream){Add-GfxError $errors "$id workstream invalid."}
   if(@('draft_pr_open','draft_pr_open_windows_not_verified','planned','blocked_by_dependencies','ready','generating','patch_ready','testing','windows_qualified','owner_review','accepted','failed','paused')-notcontains [string]$m.status){Add-GfxError $errors "$id status invalid."}
   Assert-GfxList $m.dependsOn "$id.dependsOn" $errors 0 11 16 -Unique
   Assert-GfxList $m.agentRoles "$id.agentRoles" $errors 1 32 80 -Unique
   Assert-GfxList $m.allowedPaths "$id.allowedPaths" $errors 1 64 160 -Unique
   Assert-GfxList $m.deliverables "$id.deliverables" $errors 1 32 500
   Assert-GfxList $m.acceptanceGates "$id.acceptanceGates" $errors 3 32 500
   Assert-GfxList $m.hardStops "$id.hardStops" $errors 2 32 500
   Assert-GfxList $m.requiredOwnerDecisions "$id.requiredOwnerDecisions" $errors 0 16 200 -Unique
   if (-not (Test-GfxBool $m.requiresRealWindowsRuntimeEvidence)){Add-GfxError $errors "$id Windows evidence flag must be Boolean."}
   if (-not (Test-GfxBool $m.requiresPhysicalGpuEvidence)){Add-GfxError $errors "$id GPU evidence flag must be Boolean."}
   if($m.requiresPhysicalGpuEvidence -eq $true -and $m.requiresRealWindowsRuntimeEvidence -ne $true){Add-GfxError $errors "$id GPU evidence requires Windows evidence."}
   $hasPr=$null -ne $m.existingPullRequest
   if($hasPr -or @('draft_pr_open','draft_pr_open_windows_not_verified','accepted','windows_qualified','owner_review')-contains [string]$m.status){
    if (-not $hasPr -or -not (Test-GfxInt $m.existingPullRequest) -or [long]$m.existingPullRequest -lt 1){Add-GfxError $errors "$id PR number must be positive."}
    if($m.existingPullRequestUrl -isnot [string] -or $m.existingPullRequestUrl -notmatch '^https://github\.com/Sharnou/Sharnou-Compiler/pull/[0-9]+$'){Add-GfxError $errors "$id PR URL invalid."}
    elseif($m.existingPullRequestUrl -ne ('https://github.com/Sharnou/Sharnou-Compiler/pull/'+[string]$m.existingPullRequest)){Add-GfxError $errors "$id PR URL number mismatch."}
    if($m.sourceBaseBranch -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$m.sourceBaseBranch) -or $m.sourceBaseBranch.Length -gt 120){Add-GfxError $errors "$id base branch missing or invalid."}
    if($m.sourceBranch -isnot [string] -or $m.sourceBranch -notmatch '^[A-Za-z0-9][A-Za-z0-9._/-]{0,119}$' -or $m.sourceBranch -match '(\.\.|//|/$|@\{|\\)'){Add-GfxError $errors "$id source branch invalid."}
    if($m.sourceHeadSha -isnot [string] -or -not (Test-GfxHex ([string]$m.sourceHeadSha) 40)){Add-GfxError $errors "$id source head SHA invalid."}
   }elseif($null -ne $m.existingPullRequestUrl -or $null -ne $m.sourceBaseBranch -or $null -ne $m.sourceBranch -or $null -ne $m.sourceHeadSha){Add-GfxError $errors "$id has partial PR metadata."}
  }
  foreach($m in $Campaign.milestones){$id=[string]$m.id;foreach($d in @($m.dependsOn)){if($d -eq $id){Add-GfxError $errors "$id depends on itself."};if($d -notin $script:GfxExpectedIds){Add-GfxError $errors "$id references unknown dependency '$d'."}}}
  foreach($id in $script:GfxExpectedIds){if (-not $seen.ContainsKey($id)){Add-GfxError $errors "Missing milestone '$id'."}}
  foreach($id in @($seen.Keys)){if($id -notin $script:GfxExpectedIds){Add-GfxError $errors "Unexpected milestone '$id'."}}
 }
 Assert-GfxList $Campaign.globalAcceptance 'globalAcceptance' $errors 5 32 500
 $order=@();if($Campaign.milestones -is [System.Array]){$order=@(Get-GfxTopologicalOrder $Campaign);if($order.Count -ne $Campaign.milestones.Count){Add-GfxError $errors 'Dependency cycle or unresolved graph node detected.'}}
 return [pscustomobject][ordered]@{valid=($errors.Count -eq 0);errors=@($errors.ToArray());milestoneCount=$(if($Campaign.milestones -is [System.Array]){$Campaign.milestones.Count}else{0});topologicalOrder=@($order)}
}
function Test-GfxEvidenceObject{
 param($Evidence,[string]$Path,[string]$Kind,[System.Collections.ArrayList]$Errors)
 if($Kind -eq 'windows'){$props=@('status','testedHeadSha','passedTests','failedTests','skippedTests','artifactSha256')}else{$props=@('status','testedHeadSha','adapterName','driverVersion','captureSha256')}
 Assert-GfxObject $Evidence $props $Path $Errors
 if(@('NOT_REQUIRED','NOT_RUN','PASS','FAIL')-notcontains [string]$Evidence.status){Add-GfxError $Errors "$Path status invalid."}
 if($Evidence.status -eq 'PASS'){
  if($Evidence.testedHeadSha -isnot [string] -or -not (Test-GfxHex ([string]$Evidence.testedHeadSha) 40)){Add-GfxError $Errors "$Path tested head invalid."}
  if($Kind -eq 'windows'){
   foreach($n in @('passedTests','failedTests','skippedTests')){if (-not (Test-GfxInt $Evidence.$n) -or [long]$Evidence.$n -lt 0){Add-GfxError $Errors "$Path $n must be non-negative."}}
   if($Evidence.passedTests -lt 1 -or $Evidence.failedTests -ne 0 -or $Evidence.skippedTests -ne 0){Add-GfxError $Errors "$Path PASS requires passed tests and zero failed/skipped tests."}
   if($Evidence.artifactSha256 -isnot [string] -or -not (Test-GfxHex ([string]$Evidence.artifactSha256) 64)){Add-GfxError $Errors "$Path artifact SHA-256 invalid."}
  }else{
   if([string]::IsNullOrWhiteSpace([string]$Evidence.adapterName) -or [string]::IsNullOrWhiteSpace([string]$Evidence.driverVersion)){Add-GfxError $Errors "$Path requires adapter and driver evidence."}
   if($Evidence.captureSha256 -isnot [string] -or -not (Test-GfxHex ([string]$Evidence.captureSha256) 64)){Add-GfxError $Errors "$Path capture SHA-256 invalid."}
  }
 }
}
function Test-GfxPullRequestSnapshotObject{
 [CmdletBinding()]param([Parameter(Mandatory=$true)]$Snapshot)
 $errors=New-Object System.Collections.ArrayList
 Assert-GfxObject $Snapshot @('schemaVersion','repository','capturedAtUtc','pullRequests') 'snapshot' $errors
 if($Snapshot.schemaVersion -ne 'sharnou.devagent.gfx-pr-snapshot/1'){Add-GfxError $errors 'Invalid PR snapshot version.'}
 if($Snapshot.repository -ne 'Sharnou/Sharnou-Compiler'){Add-GfxError $errors 'PR snapshot repository mismatch.'}
 $time=[DateTimeOffset]::MinValue;if($Snapshot.capturedAtUtc -isnot [string] -or -not [DateTimeOffset]::TryParse([string]$Snapshot.capturedAtUtc,[ref]$time)){Add-GfxError $errors 'Snapshot timestamp is invalid.'}
 if($Snapshot.pullRequests -isnot [System.Array] -or $Snapshot.pullRequests.Count -gt 11){Add-GfxError $errors 'PR snapshot must be an array of at most eleven records.'}else{
  $seen=@{};foreach($pr in $Snapshot.pullRequests){
   Assert-GfxObject $pr @('number','state','draft','merged','baseBranch','headBranch','headSha','ownerAccepted','windowsEvidence','physicalGpuEvidence') 'snapshot.pullRequests[]' $errors
   if (-not (Test-GfxInt $pr.number) -or [long]$pr.number -lt 1){Add-GfxError $errors 'PR number must be positive.'}else{$k=[string]$pr.number;if($seen.ContainsKey($k)){Add-GfxError $errors "Duplicate PR snapshot $k."}else{$seen[$k]=$true}}
   if(@('open','closed')-notcontains [string]$pr.state){Add-GfxError $errors 'Invalid PR state.'}
   foreach($n in @('draft','merged','ownerAccepted')){if (-not (Test-GfxBool $pr.$n)){Add-GfxError $errors "PR $n must be Boolean."}}
   foreach($n in @('baseBranch','headBranch')){if($pr.$n -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$pr.$n) -or $pr.$n.Length -gt 120){Add-GfxError $errors "PR $n invalid."}}
   if($pr.headSha -isnot [string] -or -not (Test-GfxHex ([string]$pr.headSha) 40)){Add-GfxError $errors 'PR head SHA invalid.'}
   Test-GfxEvidenceObject $pr.windowsEvidence 'windowsEvidence' 'windows' $errors
   Test-GfxEvidenceObject $pr.physicalGpuEvidence 'physicalGpuEvidence' 'gpu' $errors
  }
 }
 return [pscustomobject][ordered]@{valid=($errors.Count -eq 0);errors=@($errors.ToArray());pullRequestCount=$(if($Snapshot.pullRequests -is [System.Array]){$Snapshot.pullRequests.Count}else{0})}
}
function Test-GfxEvidenceForHead{param($Evidence,[string]$Head,[string]$Kind)
 if($Evidence.status -ne 'PASS' -or $Evidence.testedHeadSha -ne $Head){return $false}
 if($Kind -eq 'windows'){return ($Evidence.passedTests -gt 0 -and $Evidence.failedTests -eq 0 -and $Evidence.skippedTests -eq 0 -and (Test-GfxHex ([string]$Evidence.artifactSha256) 64))}
 return (-not [string]::IsNullOrWhiteSpace([string]$Evidence.adapterName) -and -not [string]::IsNullOrWhiteSpace([string]$Evidence.driverVersion) -and (Test-GfxHex ([string]$Evidence.captureSha256) 64))
}
function Get-GfxCampaignPlan{
 [CmdletBinding()]param([Parameter(Mandatory=$true)]$Campaign,[Parameter(Mandatory=$true)]$Validation,$PullRequestSnapshot,$SnapshotValidation)
 if (-not $Validation.valid){throw 'Cannot plan an invalid GFX campaign.'}
 $prs=@{};$snapshotOk=$false;if($null -ne $PullRequestSnapshot -and $null -ne $SnapshotValidation -and $SnapshotValidation.valid){$snapshotOk=$true;foreach($pr in $PullRequestSnapshot.pullRequests){$prs[[string]$pr.number]=$pr}}
 $byId=@{};foreach($m in $Campaign.milestones){$byId[[string]$m.id]=$m}
 $states=@{};$results=New-Object System.Collections.ArrayList;$activation=New-Object System.Collections.ArrayList
 if($Campaign.activation.state -ne 'ACTIVE'){$null=$activation.Add('Campaign activation state is not ACTIVE.')}
 if(@($Campaign.activation.blockingGates).Count -gt 0){$null=$activation.Add('Campaign blockingGates is not empty.')}
 foreach($n in @('localInProcessInference','typedWorkspacePatchTools','qualifiedProcessBroker','durableJournalAndRestartRecovery','nativeGitHubRepositoryAdapter','exactHeadEvidenceCollector','primarySourceResearch')){if($Campaign.generationRequirements.$n -ne $true){$null=$activation.Add("DevAgent prerequisite '$n' is not qualified.")}}
 foreach($id in $Validation.topologicalOrder){
  $m=$byId[$id];$reasons=New-Object System.Collections.ArrayList;$depsOk=$true
  foreach($dep in @($m.dependsOn)){if (-not $states.ContainsKey([string]$dep) -or $states[[string]$dep] -ne 'ACCEPTED'){$depsOk=$false;$null=$reasons.Add("Dependency $dep is not ACCEPTED.")}}
  foreach($decision in @($m.requiredOwnerDecisions)){$null=$reasons.Add("Owner decision required: $decision")}
  $state='BLOCKED'
  if($null -ne $m.existingPullRequest){
   $k=[string]$m.existingPullRequest
   if (-not $snapshotOk){$null=$reasons.Add('A valid live PR snapshot is required; manifest metadata alone is not evidence.')}
   elseif (-not $prs.ContainsKey($k)){$null=$reasons.Add("Snapshot is missing PR #$k.")}
   else{
    $pr=$prs[$k]
    if($pr.state -ne 'open' -or $pr.merged -ne $false){$null=$reasons.Add('PR must be open and unmerged.')}
    if($pr.draft -ne $true){$null=$reasons.Add('PR must remain a draft.')}
    if($pr.baseBranch -ne $m.sourceBaseBranch){$null=$reasons.Add('PR base branch mismatch.')}
    if($pr.headBranch -ne $m.sourceBranch){$null=$reasons.Add('PR head branch mismatch.')}
    if($pr.headSha -ne $m.sourceHeadSha){$null=$reasons.Add('PR head SHA mismatch.')}
    $win=$true;$gpu=$true
    if($m.requiresRealWindowsRuntimeEvidence -eq $true){$win=Test-GfxEvidenceForHead $pr.windowsEvidence $m.sourceHeadSha 'windows';if (-not $win){$null=$reasons.Add('Exact-head Windows evidence is missing, failed, or stale.')}}
    if($m.requiresPhysicalGpuEvidence -eq $true){$gpu=Test-GfxEvidenceForHead $pr.physicalGpuEvidence $m.sourceHeadSha 'gpu';if (-not $gpu){$null=$reasons.Add('Physical-GPU evidence is missing, failed, or stale.')}}
    if($depsOk -and $reasons.Count -eq 0 -and $pr.ownerAccepted -eq $true -and $win -and $gpu){$state='ACCEPTED'}
    elseif($depsOk -and $reasons.Count -eq 0 -and $win -and $gpu){$state='OWNER_REVIEW';$null=$reasons.Add('Technical gates pass; explicit owner acceptance is required.')}
   }
  }else{
   if($m.status -eq 'failed'){$state='FAILED';$null=$reasons.Add('Manifest marks milestone failed.')}
   elseif($m.status -eq 'paused'){$state='PAUSED';$null=$reasons.Add('Manifest marks milestone paused.')}
   else{foreach($reason in $activation){$null=$reasons.Add([string]$reason)};if($depsOk -and $reasons.Count -eq 0){$state='READY'}}
  }
  $states[$id]=$state;$null=$results.Add([pscustomobject][ordered]@{id=$id;title=[string]$m.title;state=$state;dependencies=@($m.dependsOn);reasons=@($reasons.ToArray());existingPullRequest=$m.existingPullRequest})
 }
 return [pscustomobject][ordered]@{
  schemaVersion='sharnou.devagent.gfx-plan/1';campaignId=[string]$Campaign.campaignId;campaignState=[string]$Campaign.activation.state
  activationReady=($activation.Count -eq 0);activationReasons=@($activation.ToArray());topologicalOrder=@($Validation.topologicalOrder)
  readyMilestones=@($results|Where-Object{$_.state -eq 'READY'}|ForEach-Object{$_.id})
  acceptedMilestones=@($results|Where-Object{$_.state -eq 'ACCEPTED'}|ForEach-Object{$_.id})
  blockedMilestones=@($results|Where-Object{$_.state -eq 'BLOCKED'}|ForEach-Object{$_.id})
  milestones=@($results.ToArray())
  continuousImprovement=[pscustomobject][ordered]@{policyDeclared=($Campaign.continuousImprovement.enabled -eq $true);afterMilestone=[string]$Campaign.continuousImprovement.afterMilestone;executionState='DECLARED_NOT_RUNNING'}
 }
}
Export-ModuleMember -Function Test-GfxCampaignObject,Test-GfxPullRequestSnapshotObject,Get-GfxTopologicalOrder,Get-GfxCampaignPlan
