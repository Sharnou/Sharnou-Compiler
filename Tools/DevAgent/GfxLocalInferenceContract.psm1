function Assert-GfxLocalObjectKeys {
 param([Parameter(Mandatory=$true)]$Object,[Parameter(Mandatory=$true)][string[]]$Expected,[Parameter(Mandatory=$true)][string]$Name)
 if($null -eq $Object -or $Object -is [Array] -or $Object -is [string]){throw "$Name must be a JSON object."}
 $actual=@($Object.PSObject.Properties | ForEach-Object{$_.Name} | Sort-Object -CaseSensitive)
 $expectedSorted=@($Expected|Sort-Object -CaseSensitive)
 if(($actual -join '|') -cne ($expectedSorted -join '|')){throw "$Name has missing or unsupported properties."}
}
function Assert-GfxLocalEqual {
 param($Actual,$Expected,[string]$Name)
 if($Actual -cne $Expected){throw "$Name failed its fixed contract check."}
}
function Assert-GfxLocalArtifact {
 param($Artifact,[string]$ExpectedFormat,[string]$Name,[string]$ExpectedState)
 Assert-GfxLocalObjectKeys -Object $Artifact -Expected @('state','format','revision','files','sha256','byteCount') -Name $Name
 Assert-GfxLocalEqual $Artifact.state $ExpectedState "$Name.state"
 Assert-GfxLocalEqual $Artifact.format $ExpectedFormat "$Name.format"
 if($null -ne $Artifact.revision -or $null -ne $Artifact.sha256 -or $null -ne $Artifact.byteCount){throw "$Name must remain unpinned in this contract-only increment."}
 if(@($Artifact.files).Count -ne 0){throw "$Name must not claim unverified artifact filenames."}
}
function Test-GfxLocalModelProfile {
 [CmdletBinding()]param([Parameter(Mandatory=$true)]$Profile)
 Assert-GfxLocalObjectKeys -Object $Profile -Expected @('schemaVersion','profileId','status','source','architecture','artifacts','runtime','policy','qualification') -Name 'profile'
 Assert-GfxLocalEqual $Profile.schemaVersion '1.0.0' 'schemaVersion'
 Assert-GfxLocalEqual $Profile.profileId 'smollm2-135m-instruct' 'profileId'
 Assert-GfxLocalEqual $Profile.status 'CANDIDATE_NOT_ACTIVATABLE' 'status'

 Assert-GfxLocalObjectKeys -Object $Profile.source -Expected @('repository','referenceRevision','license','licenseEvidenceUrl') -Name 'source'
 Assert-GfxLocalEqual $Profile.source.repository 'HuggingFaceTB/SmolLM2-135M-Instruct' 'source.repository'
 if([string]$Profile.source.referenceRevision -notmatch '^[0-9a-f]{40}$'){throw 'source.referenceRevision must be a full immutable commit SHA.'}
 Assert-GfxLocalEqual $Profile.source.license 'Apache-2.0' 'source.license'
 Assert-GfxLocalEqual $Profile.source.licenseEvidenceUrl 'https://huggingface.co/HuggingFaceTB/SmolLM2-135M-Instruct' 'source.licenseEvidenceUrl'

 Assert-GfxLocalObjectKeys -Object $Profile.architecture -Expected @('modelType','transformersArchitecture','hiddenSize','intermediateSize','numHiddenLayers','numAttentionHeads','numKeyValueHeads','vocabSize','maxPositionEmbeddings','rmsNormEpsilon','ropeTheta','hiddenActivation','tensorDtype') -Name 'architecture'
 $fixedArchitecture=@{
  modelType='llama';transformersArchitecture='LlamaForCausalLM';hiddenSize=576;intermediateSize=1536
  numHiddenLayers=30;numAttentionHeads=9;numKeyValueHeads=3;vocabSize=49152
  maxPositionEmbeddings=8192;rmsNormEpsilon=0.00001;ropeTheta=100000;hiddenActivation='silu';tensorDtype='BF16'
 }
 foreach($key in $fixedArchitecture.Keys){if($Profile.architecture.$key -cne $fixedArchitecture[$key]){throw "architecture.$key differs from the pinned reference profile."}}

 Assert-GfxLocalObjectKeys -Object $Profile.artifacts -Expected @('weights','tokenizer','chatTemplate') -Name 'artifacts'
 Assert-GfxLocalArtifact $Profile.artifacts.weights 'safetensors-v1' 'artifacts.weights' 'UNPINNED'
 Assert-GfxLocalArtifact $Profile.artifacts.tokenizer 'huggingface-tokenizer-json' 'artifacts.tokenizer' 'UNPINNED'
 Assert-GfxLocalArtifact $Profile.artifacts.chatTemplate 'tokenizer-config-chat-template' 'artifacts.chatTemplate' 'UNVERIFIED'

 Assert-GfxLocalObjectKeys -Object $Profile.runtime -Expected @('backend','executionMode','weightPrecision','accumulationPrecision','quantization','maxContextTokens','maxOutputTokens','maxInputUtf8Bytes','maxWorkingSetBytes','maxInferenceMilliseconds','requiresNetwork') -Name 'runtime'
 Assert-GfxLocalEqual $Profile.runtime.backend 'SHARNOU_NATIVE_CPU' 'runtime.backend'
 Assert-GfxLocalEqual $Profile.runtime.executionMode 'IN_PROCESS' 'runtime.executionMode'
 Assert-GfxLocalEqual $Profile.runtime.weightPrecision 'BF16' 'runtime.weightPrecision'
 Assert-GfxLocalEqual $Profile.runtime.accumulationPrecision 'FP32' 'runtime.accumulationPrecision'
 Assert-GfxLocalEqual $Profile.runtime.quantization 'NONE' 'runtime.quantization'
 if([int]$Profile.runtime.maxContextTokens -lt 1 -or [int]$Profile.runtime.maxContextTokens -gt 1024){throw 'runtime.maxContextTokens is outside the initial bound.'}
 if([int]$Profile.runtime.maxOutputTokens -lt 1 -or [int]$Profile.runtime.maxOutputTokens -gt 128){throw 'runtime.maxOutputTokens is outside the initial bound.'}
 if([long]$Profile.runtime.maxInputUtf8Bytes -lt 1 -or [long]$Profile.runtime.maxInputUtf8Bytes -gt 32768){throw 'runtime.maxInputUtf8Bytes is outside the initial bound.'}
 if([long]$Profile.runtime.maxWorkingSetBytes -lt 1048576 -or [long]$Profile.runtime.maxWorkingSetBytes -gt 1073741824){throw 'runtime.maxWorkingSetBytes is outside the initial bound.'}
 if([long]$Profile.runtime.maxInferenceMilliseconds -lt 1 -or [long]$Profile.runtime.maxInferenceMilliseconds -gt 300000){throw 'runtime.maxInferenceMilliseconds is outside the initial bound.'}
 if($Profile.runtime.requiresNetwork -ne $false){throw 'runtime.requiresNetwork must be false.'}

 Assert-GfxLocalObjectKeys -Object $Profile.policy -Expected @('processLaunchAllowed','networkAllowedAtInference','repositoryWriteAllowed','dynamicLibraryLoadingAllowed','toolAuthority','modelMayChangePolicy','modelMayMarkAccepted','remoteSourceSubmissionAllowed') -Name 'policy'
 foreach($key in @('processLaunchAllowed','networkAllowedAtInference','repositoryWriteAllowed','dynamicLibraryLoadingAllowed','modelMayChangePolicy','modelMayMarkAccepted','remoteSourceSubmissionAllowed')){
  if($Profile.policy.$key -ne $false){throw "policy.$key must remain false."}
 }
 Assert-GfxLocalEqual $Profile.policy.toolAuthority 'NONE' 'policy.toolAuthority'

 Assert-GfxLocalObjectKeys -Object $Profile.qualification -Expected @('weightsPinned','tokenizerPinned','chatTemplatePinned','licenseFileVerified','goldenVectorsPassed','nativeInferenceImplemented','offlineInferencePassed','windowsExactHeadPassed') -Name 'qualification'
 foreach($key in @('weightsPinned','tokenizerPinned','chatTemplatePinned','licenseFileVerified','goldenVectorsPassed','nativeInferenceImplemented','offlineInferencePassed','windowsExactHeadPassed')){
  if($Profile.qualification.$key -ne $false){throw "qualification.$key cannot be asserted by the contract-only increment."}
 }
 return [pscustomobject][ordered]@{
  valid=$true
  readiness='BLOCKED'
  profileId=[string]$Profile.profileId
  modelRepository=[string]$Profile.source.repository
  backend=[string]$Profile.runtime.backend
  blockers=@(
   'WEIGHTS_NOT_PINNED',
   'TOKENIZER_AND_CHAT_TEMPLATE_NOT_PINNED',
   'LICENSE_FILE_NOT_INDEPENDENTLY_VERIFIED',
   'NATIVE_TENSOR_AND_TRANSFORMER_RUNTIME_NOT_IMPLEMENTED',
   'GOLDEN_REFERENCE_VECTORS_NOT_AVAILABLE',
   'OFFLINE_NATIVE_INFERENCE_NOT_RUN',
   'WINDOWS_EXACT_HEAD_INFERENCE_QUALIFICATION_NOT_RUN'
  )
 }
}
function Read-GfxLocalModelProfile {
 [CmdletBinding()]param([Parameter(Mandatory=$true)][string]$Path)
 $full=[IO.Path]::GetFullPath($Path)
 if(-not(Test-Path -LiteralPath $full -PathType Leaf)){throw 'Model profile file was not found.'}
 $bytes=[IO.File]::ReadAllBytes($full)
 if($bytes.Length -eq 0 -or ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)){throw 'Model profile must be non-empty UTF-8 without a BOM.'}
 foreach($byte in $bytes){if($byte -gt 127){throw 'Model profile must remain ASCII in this version.'}}
 try{$json=(New-Object Text.UTF8Encoding($false,$true)).GetString($bytes);$profile=ConvertFrom-Json -InputObject $json -ErrorAction Stop}catch{throw 'Model profile JSON is malformed or invalid UTF-8.'}
 $result=Test-GfxLocalModelProfile -Profile $profile
 return $result
}
Export-ModuleMember -Function Test-GfxLocalModelProfile,Read-GfxLocalModelProfile
