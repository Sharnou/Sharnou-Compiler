[CmdletBinding()]param()
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'Tools\DevAgent\GfxLocalInferenceContract.psm1') -Force
$script:Passed=0;$script:Failed=0
function Assert-GfxLocal {
 param([bool]$Condition,[string]$Name)
 if($Condition){$script:Passed++;Write-Host "PASS: $Name"}else{$script:Failed++;Write-Host "FAIL: $Name"}
}
function Copy-Profile {
 param($Value)
 return (ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $Value -Depth 24))
}
function Test-Rejected {
 param($Value,[string]$Name)
 $rejected=$false
 try{$null=Test-GfxLocalModelProfile -Profile $Value}catch{$rejected=$true}
 Assert-GfxLocal $rejected $Name
}
$manifestPath=Join-Path $root 'Projects\DevAgent\Models\SmolLM2-135M-Instruct.profile.v1.json'
$schemaPath=Join-Path $root 'Schemas\DevAgent\GfxLocalModel.v1.schema.json'
$profile=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($manifestPath)) -ErrorAction Stop
$schema=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($schemaPath)) -ErrorAction Stop
Assert-GfxLocal ($schema.'$id' -eq 'https://sharnou.dev/schemas/devagent/gfx-local-model/v1.json' -and $schema.additionalProperties -eq $false) 'versioned schema identity and strict root properties'
$report=Test-GfxLocalModelProfile -Profile $profile
Assert-GfxLocal $report.valid 'reference model profile satisfies the contract'
Assert-GfxLocal ($report.readiness -eq 'BLOCKED' -and $report.blockers.Count -ge 7) 'manifest validation cannot promote an unimplemented runtime'
Assert-GfxLocal ($profile.status -eq 'CANDIDATE_NOT_ACTIVATABLE') 'reference model remains a non-activatable candidate'
Assert-GfxLocal ($profile.source.referenceRevision -match '^[0-9a-f]{40}$') 'reference config is pinned to a full immutable revision'
Assert-GfxLocal ($profile.artifacts.weights.state -eq 'UNPINNED' -and $null -eq $profile.artifacts.weights.sha256) 'model weights are not falsely represented as downloaded or hashed'
Assert-GfxLocal ($profile.artifacts.tokenizer.state -eq 'UNPINNED' -and @($profile.artifacts.tokenizer.files).Count -eq 0) 'tokenizer artifacts remain explicitly unpinned'
Assert-GfxLocal ($profile.qualification.nativeInferenceImplemented -eq $false -and $profile.qualification.offlineInferencePassed -eq $false) 'no inference or offline runtime pass is claimed'

$bad=Copy-Profile $profile;$bad.policy.processLaunchAllowed=$true
Test-Rejected $bad 'process-launch capability escalation is rejected'
$bad=Copy-Profile $profile;$bad.policy.networkAllowedAtInference=$true
Test-Rejected $bad 'network access during inference is rejected'
$bad=Copy-Profile $profile;$bad.policy.repositoryWriteAllowed=$true
Test-Rejected $bad 'repository-write authority is rejected'
$bad=Copy-Profile $profile;$bad.policy.dynamicLibraryLoadingAllowed=$true
Test-Rejected $bad 'dynamic-library loading is rejected'
$bad=Copy-Profile $profile;$bad.policy.toolAuthority='GITHUB_WRITE'
Test-Rejected $bad 'model tool authority escalation is rejected'
$bad=Copy-Profile $profile;$bad.policy.modelMayMarkAccepted=$true
Test-Rejected $bad 'model self-acceptance is rejected'
$bad=Copy-Profile $profile;$bad.runtime.executionMode='OUT_OF_PROCESS'
Test-Rejected $bad 'out-of-process inference runtime is rejected'
$bad=Copy-Profile $profile;$bad.runtime.requiresNetwork=$true
Test-Rejected $bad 'network-dependent model inference is rejected'
$bad=Copy-Profile $profile;$bad.runtime.maxContextTokens=8192
Test-Rejected $bad 'unqualified full-context allocation is rejected'
$bad=Copy-Profile $profile;$bad.runtime.maxOutputTokens=4096
Test-Rejected $bad 'unbounded output token budget is rejected'
$bad=Copy-Profile $profile;$bad.runtime.maxWorkingSetBytes=2147483648
Test-Rejected $bad 'working-set budget above 1 GiB is rejected'
$bad=Copy-Profile $profile;$bad.architecture.numKeyValueHeads=9
Test-Rejected $bad 'model tensor architecture mismatch is rejected'
$bad=Copy-Profile $profile;$bad.architecture.tensorDtype='F32'
Test-Rejected $bad 'unsupported model tensor precision is rejected'
$bad=Copy-Profile $profile;$bad.source.referenceRevision='main'
Test-Rejected $bad 'mutable branch references are rejected'
$bad=Copy-Profile $profile;$bad.source.license='UNKNOWN'
Test-Rejected $bad 'unapproved license identity is rejected'
$bad=Copy-Profile $profile;$bad.artifacts.weights.sha256=('a'*64)
Test-Rejected $bad 'unverified model digest claims are rejected'
$bad=Copy-Profile $profile;$bad.artifacts.tokenizer.files=@('../tokenizer.json')
Test-Rejected $bad 'unverified artifact path claims are rejected'
$bad=Copy-Profile $profile;$bad.qualification.nativeInferenceImplemented=$true
Test-Rejected $bad 'manifest cannot self-assert native inference implementation'
$bad=Copy-Profile $profile
Add-Member -InputObject $bad -NotePropertyName unexpectedAuthority -NotePropertyValue 'enabled'
Test-Rejected $bad 'unknown root properties are rejected'

$loaded=Read-GfxLocalModelProfile -Path $manifestPath
Assert-GfxLocal ($loaded.valid -and $loaded.readiness -eq 'BLOCKED') 'on-disk profile is parsed and remains blocked'
$moduleText=[IO.File]::ReadAllText((Join-Path $root 'Tools\DevAgent\GfxLocalInferenceContract.psm1'))
$cliText=[IO.File]::ReadAllText((Join-Path $root 'Tools\DevAgent\Invoke-GfxLocalInferenceContract.ps1'))
Assert-GfxLocal ($moduleText -notmatch '(?i)Start-Process|Invoke-Expression|Invoke-WebRequest|Invoke-RestMethod|CreateProcess|LoadLibrary|Assembly::Load') 'contract module contains no process, network or dynamic-loader path'
Assert-GfxLocal ($cliText -notmatch '(?i)Start-Process|Invoke-Expression|Invoke-WebRequest|Invoke-RestMethod') 'contract CLI contains no process or network path'

Write-Host ''
Write-Host ("DGA-GFX-0.5A contract tests: {0} passed; {1} failed; {2} total." -f $script:Passed,$script:Failed,($script:Passed+$script:Failed))
if($script:Failed -ne 0){exit 1}
exit 0
