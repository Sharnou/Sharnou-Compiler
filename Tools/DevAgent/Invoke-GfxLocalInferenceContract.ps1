[CmdletBinding()]param([string]$ProfilePath='')
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if([string]::IsNullOrWhiteSpace($ProfilePath)){
 $root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
 $ProfilePath=Join-Path $root 'Projects\DevAgent\Models\SmolLM2-135M-Instruct.profile.v1.json'
}
Import-Module (Join-Path $PSScriptRoot 'GfxLocalInferenceContract.psm1') -Force
try{
 $result=Read-GfxLocalModelProfile -Path $ProfilePath
 $result|ConvertTo-Json -Depth 12
 exit 0
}catch{
 [Console]::Error.WriteLine($_.Exception.Message)
 exit 10
}
