[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$WeightsPath
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $root 'Tools\DevAgent\GfxSafeTensorReader.psm1') -Force
$lockPath=Join-Path $root 'Projects\DevAgent\Models\SmolLM2-135M-Instruct.artifact-lock.v1.json'
$lock=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($lockPath)) -ErrorAction Stop
$weightEvidence=Test-GfxPinnedArtifactFile -Artifact $lock.artifacts.weights -Path $WeightsPath
$header=Read-GfxSafeTensorHeader -Path $WeightsPath
[pscustomobject][ordered]@{
 artifact=$weightEvidence
 safetensors=$header
 tokenizerState=$lock.artifacts.tokenizer.state
 chatTemplateState=$lock.artifacts.tokenizerConfig.state
 licenseState=$lock.artifacts.license.state
 readiness='BLOCKED'
 blockers=@('TOKENIZER_SHA256_NOT_PINNED','CHAT_TEMPLATE_SHA256_NOT_PINNED','LICENSE_FILE_NOT_VERIFIED','NATIVE_SHARNOU_MODEL_READER_NOT_IMPLEMENTED','NATIVE_INFERENCE_NOT_IMPLEMENTED')
} | ConvertTo-Json -Depth 16
