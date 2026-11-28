[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$Path,
 [long]$MaxFileBytes=1073741824,
 [int]$MaxHeaderBytes=16777216
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $root 'Tools\DevAgent\GfxSafeTensorReader.psm1') -Force
$result=Read-GfxSafeTensorHeader -Path $Path -MaxFileBytes $MaxFileBytes -MaxHeaderBytes $MaxHeaderBytes
$result | ConvertTo-Json -Depth 12
