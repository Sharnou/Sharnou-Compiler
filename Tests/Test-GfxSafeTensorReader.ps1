[CmdletBinding()]param()
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'Tools\DevAgent\GfxSafeTensorReader.psm1') -Force
$script:Passed=0;$script:Failed=0
$script:Temp=Join-Path ([IO.Path]::GetTempPath()) ('sharnou-gfx-safe-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($script:Temp) | Out-Null
function Assert-GfxReader {
 param([bool]$Condition,[string]$Name)
 if($Condition){$script:Passed++;Write-Host "PASS: $Name"}else{$script:Failed++;Write-Host "FAIL: $Name"}
}
function Write-GfxFixture {
 param([string]$Name,[string]$Header,[int]$DataBytes=4,[switch]$Truncate)
 $headerBytes=(New-Object Text.UTF8Encoding($false)).GetBytes($Header)
 $prefix=[BitConverter]::GetBytes([UInt64]$headerBytes.Length)
 $all=New-Object byte[] (8+$headerBytes.Length+$DataBytes)
 [Buffer]::BlockCopy($prefix,0,$all,0,8)
 [Buffer]::BlockCopy($headerBytes,0,$all,8,$headerBytes.Length)
 if($Truncate){$all=New-Object byte[] 7}
 $path=Join-Path $script:Temp $Name
 [IO.File]::WriteAllBytes($path,$all)
 return $path
}
function Test-GfxRejected {
 param([string]$Path,[string]$Name,[hashtable]$Limits=@{})
 $rejected=$false
 try{$null=Read-GfxSafeTensorHeader -Path $Path @Limits}catch{$rejected=$true}
 Assert-GfxReader $rejected $Name
}
function New-GfxHeader {
 param([string]$Dtype='BF16',[string]$Shape='[2]',[string]$Offsets='[0,4]')
 return '{"weight":{"dtype":"'+$Dtype+'","shape":'+$Shape+',"data_offsets":'+$Offsets+'}}'
}
$valid=Write-GfxFixture -Name 'valid.safetensors' -Header (New-GfxHeader) -DataBytes 4
$parsed=Read-GfxSafeTensorHeader -Path $valid
Assert-GfxReader ($parsed.valid -and $parsed.format -eq 'safetensors-v1' -and $parsed.tensorCount -eq 1 -and $parsed.tensors[0].byteCount -eq 4) 'valid BF16 header is parsed with exact tensor byte accounting'
Assert-GfxReader ($parsed.payloadRead -eq $false -and $parsed.payloadExecuted -eq $false) 'reader inspects metadata only and never reads or executes tensor payload'
$metadata=Write-GfxFixture -Name 'metadata.safetensors' -Header '{"__metadata__":{"format":"pt"},"weight":{"dtype":"BF16","shape":[2],"data_offsets":[0,4]}}' -DataBytes 4
$metadataResult=Read-GfxSafeTensorHeader -Path $metadata
Assert-GfxReader ($metadataResult.valid -and $metadataResult.tensorCount -eq 1) 'string-only metadata object is accepted'
$bad=Write-GfxFixture -Name 'duplicate.safetensors' -Header '{"weight":{"dtype":"BF16","dtype":"BF16","shape":[2],"data_offsets":[0,4]}}' -DataBytes 4
Test-GfxRejected $bad 'duplicate JSON keys are rejected'
$bad=Write-GfxFixture -Name 'wrong-dtype.safetensors' -Header (New-GfxHeader -Dtype 'F32') -DataBytes 4
Test-GfxRejected $bad 'unsupported tensor dtype is rejected'
$bad=Write-GfxFixture -Name 'wrong-shape-bytes.safetensors' -Header (New-GfxHeader -Shape '[3]') -DataBytes 4
Test-GfxRejected $bad 'tensor byte count must equal checked BF16 shape product'
$bad=Write-GfxFixture -Name 'negative-dimension.safetensors' -Header (New-GfxHeader -Shape '[-2]') -DataBytes 4
Test-GfxRejected $bad 'negative tensor dimensions are rejected'
$bad=Write-GfxFixture -Name 'zero-dimension.safetensors' -Header (New-GfxHeader -Shape '[0]') -DataBytes 4
Test-GfxRejected $bad 'zero tensor dimensions are rejected'
$bad=Write-GfxFixture -Name 'rank.safetensors' -Header (New-GfxHeader -Shape '[1,1,1,1,1,1,1,1,1]' -Offsets '[0,2]') -DataBytes 2
Test-GfxRejected $bad 'tensor rank above configured maximum is rejected'
$bad=Write-GfxFixture -Name 'overflow.safetensors' -Header (New-GfxHeader -Shape '[2147483647,2147483647]' -Offsets '[0,4]') -DataBytes 4
Test-GfxRejected $bad 'tensor element-count overflow and resource abuse are rejected'
$bad=Write-GfxFixture -Name 'odd-offset.safetensors' -Header (New-GfxHeader -Offsets '[1,5]') -DataBytes 6
Test-GfxRejected $bad 'BF16 element-misaligned offsets are rejected'
$bad=Write-GfxFixture -Name 'out-of-range.safetensors' -Header (New-GfxHeader -Offsets '[0,6]') -DataBytes 4
Test-GfxRejected $bad 'tensor offsets beyond end of file are rejected'
$bad=Write-GfxFixture -Name 'trailing.safetensors' -Header (New-GfxHeader) -DataBytes 6
Test-GfxRejected $bad 'unclaimed trailing tensor payload bytes are rejected'
$bad=Write-GfxFixture -Name 'gap.safetensors' -Header '{"a":{"dtype":"BF16","shape":[2],"data_offsets":[0,4]},"b":{"dtype":"BF16","shape":[1],"data_offsets":[6,8]}}' -DataBytes 8
Test-GfxRejected $bad 'unclaimed gaps between tensor ranges are rejected'
$bad=Write-GfxFixture -Name 'overlap.safetensors' -Header '{"a":{"dtype":"BF16","shape":[2],"data_offsets":[0,4]},"b":{"dtype":"BF16","shape":[2],"data_offsets":[2,6]}}' -DataBytes 6
Test-GfxRejected $bad 'overlapping tensor ranges are rejected'
$bad=Write-GfxFixture -Name 'bad-metadata.safetensors' -Header '{"__metadata__":{"format":7},"weight":{"dtype":"BF16","shape":[2],"data_offsets":[0,4]}}' -DataBytes 4
Test-GfxRejected $bad 'non-string metadata values are rejected'
$bad=Write-GfxFixture -Name 'extra-tensor-key.safetensors' -Header '{"weight":{"dtype":"BF16","shape":[2],"data_offsets":[0,4],"executable":"no"}}' -DataBytes 4
Test-GfxRejected $bad 'unknown tensor-record fields are rejected'
$bad=Write-GfxFixture -Name 'malformed.safetensors' -Header '{"weight":' -DataBytes 4
Test-GfxRejected $bad 'malformed JSON header is rejected'
$bad=Write-GfxFixture -Name 'not-object.safetensors' -Header '[]' -DataBytes 4
Test-GfxRejected $bad 'non-object header root is rejected'
$bad=Write-GfxFixture -Name 'truncated.safetensors' -Header (New-GfxHeader) -Truncate
Test-GfxRejected $bad 'truncated eight-byte header prefix is rejected'
Test-GfxRejected $valid 'file-size cap is enforced' @{MaxFileBytes=10}
Test-GfxRejected $valid 'header-size cap is enforced' @{MaxHeaderBytes=2}
$artifactPath=Join-Path $script:Temp 'artifact.bin'
[IO.File]::WriteAllBytes($artifactPath,[byte[]](1,2,3,4))
$hash=(Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
$entry=[pscustomobject]@{path='fixture.bin';revision='0123456789abcdef0123456789abcdef01234567';byteCount=4;sha256=$hash;state='PINNED'}
$evidence=Test-GfxPinnedArtifactFile -Artifact $entry -Path $artifactPath
Assert-GfxReader ($evidence.valid -and $evidence.verification -eq 'LOCAL_SHA256_MATCH') 'pinned artifact exact byte count and SHA-256 are independently verified'
$entry.sha256=('0'*64)
$rejected=$false
try{$null=Test-GfxPinnedArtifactFile -Artifact $entry -Path $artifactPath}catch{$rejected=$true}
Assert-GfxReader $rejected 'artifact digest mismatch is rejected'
$entry.sha256=$hash;$entry.byteCount=5
$rejected=$false
try{$null=Test-GfxPinnedArtifactFile -Artifact $entry -Path $artifactPath}catch{$rejected=$true}
Assert-GfxReader $rejected 'artifact byte-count mismatch is rejected'
$moduleText=[IO.File]::ReadAllText((Join-Path $root 'Tools\DevAgent\GfxSafeTensorReader.psm1'))
Assert-GfxReader ($moduleText -notmatch '(?i)Invoke-WebRequest|Invoke-RestMethod|Start-Process|Invoke-Expression|CreateProcess|LoadLibrary|Assembly::Load') 'reader contains no network, process, shell or dynamic-loader path'
Write-Host ''
Write-Host ("DGA-GFX-0.5B safetensors tests: {0} passed; {1} failed; {2} total." -f $script:Passed,$script:Failed,($script:Passed+$script:Failed))
Remove-Item -LiteralPath $script:Temp -Recurse -Force
if($script:Failed -ne 0){exit 1}
exit 0
