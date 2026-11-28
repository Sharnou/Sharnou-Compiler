[CmdletBinding()]
param([string]$ManifestPath=(Join-Path $PSScriptRoot '..\..\Projects\DevAgent\GfxCampaign.v1.json'),[string]$SchemaPath=(Join-Path $PSScriptRoot '..\..\Schemas\DevAgent\GfxCampaign.v1.schema.json'),[string]$SnapshotPath='')
$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'GfxCampaign.psm1') -Force
function Read-GfxJson{param([string]$Path)
 if (-not (Test-Path -LiteralPath $Path -PathType Leaf)){throw "Input not found: $Path"}
 $f=Get-Item -LiteralPath $Path;if($f.Length -gt 1048576){throw "JSON input exceeds 1 MiB: $Path"}
 return (ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($f.FullName,[Text.Encoding]::UTF8)) -ErrorAction Stop)
}
try{
 $campaign=Read-GfxJson $ManifestPath;$schema=Read-GfxJson $SchemaPath;$v=Test-GfxCampaignObject -Campaign $campaign -Schema $schema
 if (-not $v.valid){[pscustomobject][ordered]@{valid=$false;errors=@($v.errors)}|ConvertTo-Json -Depth 12;exit 2}
 $snap=$null;$sv=$null;if (-not[string]::IsNullOrWhiteSpace($SnapshotPath)){$snap=Read-GfxJson $SnapshotPath;$sv=Test-GfxPullRequestSnapshotObject -Snapshot $snap;if (-not $sv.valid){[pscustomobject][ordered]@{valid=$false;errors=@($sv.errors)}|ConvertTo-Json -Depth 12;exit 3}}
 $plan=Get-GfxCampaignPlan -Campaign $campaign -Validation $v -PullRequestSnapshot $snap -SnapshotValidation $sv
 [pscustomobject][ordered]@{valid=$true;milestoneCount=$v.milestoneCount;topologicalOrder=@($v.topologicalOrder);plan=$plan}|ConvertTo-Json -Depth 20;exit 0
}catch{[Console]::Error.WriteLine($_.Exception.Message);exit 10}
