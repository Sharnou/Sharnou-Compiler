[CmdletBinding()]
param(
 [ValidateSet('CredentialStatus','ConfigureCredential','RemoveCredential','Repository','Branch','Commit','File','PullRequest','PullRequests','WorkflowRuns','RunArtifacts','CommitEvidence','PullRequestEvidence')]
 [string]$Action='CredentialStatus',
 [string]$BranchName='',
 [string]$Ref='',
 [string]$Path='',
 [int]$PullRequestNumber=0,
 [string]$CommitSha='',
 [long]$RunId=0
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'GfxGitHubAdapter.psm1') -Force
try{
 switch($Action){
  'CredentialStatus' {$result=Get-GfxGitHubCredentialStatus}
  'ConfigureCredential' {
   $token=Read-Host 'Enter a GitHub fine-grained token with read-only repository permissions' -AsSecureString
   try{$result=Set-GfxGitHubCredential -Token $token}finally{if($null -ne $token){$token.Dispose()}}
  }
  'RemoveCredential' {$result=Remove-GfxGitHubCredential}
  'Repository' {$result=Get-GfxGitHubRepository}
  'Branch' {if([string]::IsNullOrWhiteSpace($BranchName)){throw 'BranchName is required.'};$result=Get-GfxGitHubBranch -BranchName $BranchName}
  'Commit' {if([string]::IsNullOrWhiteSpace($Ref)){throw 'Ref is required.'};$result=Get-GfxGitHubCommit -Ref $Ref}
  'File' {if([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Ref)){throw 'Path and Ref are required.'};$result=Get-GfxGitHubFile -Path $Path -Ref $Ref}
  'PullRequest' {if($PullRequestNumber -lt 1){throw 'PullRequestNumber is required.'};$result=Get-GfxGitHubPullRequest -PullRequestNumber $PullRequestNumber}
  'PullRequests' {$result=Get-GfxGitHubPullRequests}
  'WorkflowRuns' {if($CommitSha -notmatch '^[0-9a-f]{40}$'){throw 'CommitSha must be a full SHA.'};$result=Get-GfxGitHubWorkflowRuns -CommitSha $CommitSha}
  'RunArtifacts' {if($RunId -lt 1){throw 'RunId is required.'};$result=Get-GfxGitHubRunArtifacts -RunId $RunId}
  'CommitEvidence' {if($CommitSha -notmatch '^[0-9a-f]{40}$'){throw 'CommitSha must be a full SHA.'};$result=Get-GfxGitHubCommitEvidence -CommitSha $CommitSha}
  'PullRequestEvidence' {if($PullRequestNumber -lt 1){throw 'PullRequestNumber is required.'};$result=Get-GfxGitHubPullRequestEvidence -PullRequestNumber $PullRequestNumber}
 }
 $result|ConvertTo-Json -Depth 24
 exit 0
}catch{
 [Console]::Error.WriteLine($_.Exception.Message)
 exit 10
}
