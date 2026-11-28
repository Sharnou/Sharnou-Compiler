[CmdletBinding()]
param([ValidateSet('Initialize','Inspect','Recover')][string]$Action='Inspect',[string]$StateDirectory=(Join-Path $env:LOCALAPPDATA 'Sharnou\DevAgent\GfxCampaignState'))
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'GfxTaskJournal.psm1') -Force
try{
 switch($Action){'Initialize'{$result=Initialize-GfxTaskJournal -StateDirectory $StateDirectory};'Inspect'{$result=Get-GfxTaskJournalStatus -StateDirectory $StateDirectory};'Recover'{$result=Recover-GfxTaskJournal -StateDirectory $StateDirectory}}
 $result|ConvertTo-Json -Depth 16
 exit 0
}catch{[Console]::Error.WriteLine($_.Exception.Message);exit 10}
