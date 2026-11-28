Set-StrictMode -Version 2.0

function Read-GfxExactBytes {
 param([Parameter(Mandatory=$true)][IO.Stream]$Stream,[Parameter(Mandatory=$true)][int]$Count,[Parameter(Mandatory=$true)][string]$Name)
 $buffer=New-Object byte[] $Count
 $offset=0
 while($offset -lt $Count){
  $read=$Stream.Read($buffer,$offset,$Count-$offset)
  if($read -le 0){throw "$Name is truncated."}
  $offset+=$read
 }
 return ,$buffer
}

function Skip-GfxJsonWhitespace {
 while($script:GfxJsonPosition -lt $script:GfxJsonText.Length -and [char]::IsWhiteSpace($script:GfxJsonText[$script:GfxJsonPosition])){$script:GfxJsonPosition++}
}

function Read-GfxJsonStringToken {
 if($script:GfxJsonPosition -ge $script:GfxJsonText.Length -or $script:GfxJsonText[$script:GfxJsonPosition] -ne '"'){throw 'Malformed JSON string token.'}
 $start=$script:GfxJsonPosition
 $script:GfxJsonPosition++
 $escaped=$false
 $closed=$false
 while($script:GfxJsonPosition -lt $script:GfxJsonText.Length){
  $ch=$script:GfxJsonText[$script:GfxJsonPosition]
  $script:GfxJsonPosition++
  if($escaped){$escaped=$false;continue}
  if($ch -eq '\'){$escaped=$true;continue}
  if($ch -eq '"'){$closed=$true;break}
 }
 if(-not $closed){throw 'Unterminated JSON string token.'}
 $raw=$script:GfxJsonText.Substring($start,$script:GfxJsonPosition-$start)
 try{$decoded=ConvertFrom-Json -InputObject ("["+$raw+"]") -ErrorAction Stop}catch{throw 'Invalid JSON string token.'}
 return [string]$decoded[0]
}

function Scan-GfxJsonValue {
 param([int]$Depth=0)
 if($Depth -gt 48){throw 'Safetensors header JSON nesting exceeds the supported depth.'}
 Skip-GfxJsonWhitespace
 if($script:GfxJsonPosition -ge $script:GfxJsonText.Length){throw 'Unexpected end of JSON value.'}
 $ch=$script:GfxJsonText[$script:GfxJsonPosition]
 if($ch -eq '{'){
  $script:GfxJsonPosition++
  $keys=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
  Skip-GfxJsonWhitespace
  if($script:GfxJsonPosition -lt $script:GfxJsonText.Length -and $script:GfxJsonText[$script:GfxJsonPosition] -eq '}'){$script:GfxJsonPosition++;return}
  while($true){
   Skip-GfxJsonWhitespace
   $key=Read-GfxJsonStringToken
   if(-not $keys.Add($key)){throw "Duplicate JSON object key '$key' is forbidden."}
   Skip-GfxJsonWhitespace
   if($script:GfxJsonPosition -ge $script:GfxJsonText.Length -or $script:GfxJsonText[$script:GfxJsonPosition] -ne ':'){throw 'JSON object key is not followed by a colon.'}
   $script:GfxJsonPosition++
   Scan-GfxJsonValue -Depth ($Depth+1)
   Skip-GfxJsonWhitespace
   if($script:GfxJsonPosition -ge $script:GfxJsonText.Length){throw 'Unterminated JSON object.'}
   $next=$script:GfxJsonText[$script:GfxJsonPosition]
   if($next -eq '}'){$script:GfxJsonPosition++;break}
   if($next -ne ','){throw 'Malformed JSON object separator.'}
   $script:GfxJsonPosition++
  }
  return
 }
 if($ch -eq '['){
  $script:GfxJsonPosition++
  Skip-GfxJsonWhitespace
  if($script:GfxJsonPosition -lt $script:GfxJsonText.Length -and $script:GfxJsonText[$script:GfxJsonPosition] -eq ']'){$script:GfxJsonPosition++;return}
  while($true){
   Scan-GfxJsonValue -Depth ($Depth+1)
   Skip-GfxJsonWhitespace
   if($script:GfxJsonPosition -ge $script:GfxJsonText.Length){throw 'Unterminated JSON array.'}
   $next=$script:GfxJsonText[$script:GfxJsonPosition]
   if($next -eq ']'){$script:GfxJsonPosition++;break}
   if($next -ne ','){throw 'Malformed JSON array separator.'}
   $script:GfxJsonPosition++
  }
  return
 }
 if($ch -eq '"'){$null=Read-GfxJsonStringToken;return}
 $start=$script:GfxJsonPosition
 while($script:GfxJsonPosition -lt $script:GfxJsonText.Length){
  $current=$script:GfxJsonText[$script:GfxJsonPosition]
  if($current -eq ',' -or $current -eq ']' -or $current -eq '}' -or [char]::IsWhiteSpace($current)){break}
  $script:GfxJsonPosition++
 }
 if($script:GfxJsonPosition -eq $start){throw 'Invalid JSON primitive.'}
}

function Assert-GfxNoDuplicateJsonKeys {
 param([Parameter(Mandatory=$true)][string]$JsonText)
 $script:GfxJsonText=$JsonText
 $script:GfxJsonPosition=0
 try{
  Scan-GfxJsonValue
  Skip-GfxJsonWhitespace
  if($script:GfxJsonPosition -ne $script:GfxJsonText.Length){throw 'Trailing data after safetensors JSON header.'}
 }finally{
  $script:GfxJsonText=$null
  $script:GfxJsonPosition=0
 }
}

function Test-GfxJsonInteger {
 param($Value,[string]$Name,[long]$Minimum=0,[long]$Maximum=[long]::MaxValue)
 if($Value -isnot [int] -and $Value -isnot [long]){throw "$Name must be a JSON integer within the supported signed 64-bit range."}
 $number=[long]$Value
 if($number -lt $Minimum -or $number -gt $Maximum){throw "$Name is outside its permitted range."}
 return $number
}

function Assert-GfxObjectProperties {
 param($Object,[string[]]$Expected,[string]$Name)
 if($null -eq $Object -or $Object -is [Array] -or $Object -is [string]){throw "$Name must be a JSON object."}
 $actual=@($Object.PSObject.Properties | ForEach-Object{$_.Name} | Sort-Object -CaseSensitive)
 $expectedSorted=@($Expected | Sort-Object -CaseSensitive)
 if(($actual -join '|') -cne ($expectedSorted -join '|')){throw "$Name has missing or unsupported properties."}
}

function Read-GfxSafeTensorHeader {
 [CmdletBinding()]
 param(
  [Parameter(Mandatory=$true)][string]$Path,
  [long]$MaxFileBytes=1073741824,
  [int]$MaxHeaderBytes=16777216,
  [int]$MaxTensorCount=4096,
  [int]$MaxRank=8,
  [long]$MaxTensorElements=2147483647
 )
 if($MaxFileBytes -lt 8 -or $MaxHeaderBytes -lt 2 -or $MaxTensorCount -lt 1 -or $MaxRank -lt 1 -or $MaxTensorElements -lt 1){throw 'Reader limits are invalid.'}
 $full=[IO.Path]::GetFullPath($Path)
 if(-not(Test-Path -LiteralPath $full -PathType Leaf)){throw 'Safetensors file was not found.'}
 $info=Get-Item -LiteralPath $full -Force
 if(($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Reparse-point model files are not accepted.'}
 $fileLength=[long]$info.Length
 if($fileLength -lt 8 -or $fileLength -gt $MaxFileBytes){throw 'Safetensors file length is outside the configured bound.'}
 if(-not [BitConverter]::IsLittleEndian){throw 'This reader requires a little-endian host.'}
 $stream=$null
 try{
  $stream=New-Object IO.FileStream($full,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  $lengthBytes=Read-GfxExactBytes -Stream $stream -Count 8 -Name 'Safetensors header-length field'
  $headerLength=[BitConverter]::ToUInt64($lengthBytes,0)
  if($headerLength -lt 2 -or $headerLength -gt [uint64]$MaxHeaderBytes){throw 'Safetensors header length is outside the configured bound.'}
  if($headerLength -gt [uint64]($fileLength-8)){throw 'Safetensors header extends beyond the file.'}
  $headerBytes=Read-GfxExactBytes -Stream $stream -Count ([int]$headerLength) -Name 'Safetensors JSON header'
  if($headerBytes[0] -ne 0x7B){throw 'Safetensors JSON header must begin with an opening brace.'}
  try{$headerText=(New-Object Text.UTF8Encoding($false,$true)).GetString($headerBytes)}catch{throw 'Safetensors header is not valid UTF-8.'}
  Assert-GfxNoDuplicateJsonKeys -JsonText $headerText
  try{$header=ConvertFrom-Json -InputObject $headerText -ErrorAction Stop}catch{throw 'Safetensors header JSON is malformed.'}
  if($null -eq $header -or $header -is [Array] -or $header -is [string]){throw 'Safetensors header root must be an object.'}
  $dataLength=$fileLength-8-[long]$headerLength
  $tensorNames=New-Object 'System.Collections.Generic.List[string]'
  $intervals=New-Object 'System.Collections.Generic.List[object]'
  $summaries=New-Object 'System.Collections.Generic.List[object]'
  foreach($property in $header.PSObject.Properties){
   $name=[string]$property.Name
   if($name -ceq '__metadata__'){
    $metadata=$property.Value
    if($null -eq $metadata -or $metadata -is [Array] -or $metadata -is [string]){throw 'Safetensors __metadata__ must be an object of string values.'}
    foreach($entry in $metadata.PSObject.Properties){if($entry.Value -isnot [string]){throw 'Safetensors metadata values must all be strings.'}}
    continue
   }
   if($tensorNames.Count -ge $MaxTensorCount){throw 'Safetensors tensor count exceeds the configured bound.'}
   if([string]::IsNullOrWhiteSpace($name)){throw 'Safetensors tensor names cannot be empty.'}
   $record=$property.Value
   Assert-GfxObjectProperties -Object $record -Expected @('dtype','shape','data_offsets') -Name ("tensor '$name'")
   if([string]$record.dtype -cne 'BF16'){throw "Tensor '$name' uses unsupported dtype '$($record.dtype)'; this candidate accepts BF16 only."}
   if($record.shape -isnot [Array] -or $record.shape.Count -lt 1 -or $record.shape.Count -gt $MaxRank){throw "Tensor '$name' rank is outside the supported range."}
   $elements=[long]1
   $dimensions=New-Object 'System.Collections.Generic.List[long]'
   for($i=0;$i -lt $record.shape.Count;$i++){
    $dimension=Test-GfxJsonInteger -Value $record.shape[$i] -Name ("tensor '$name' shape dimension") -Minimum 1 -Maximum $MaxTensorElements
    if($elements -gt [long]($MaxTensorElements / $dimension)){throw "Tensor '$name' element count exceeds the configured bound."}
    $elements=$elements*$dimension
    $dimensions.Add($dimension)
   }
   if($record.data_offsets -isnot [Array] -or $record.data_offsets.Count -ne 2){throw "Tensor '$name' must have exactly two data offsets."}
   $start=Test-GfxJsonInteger -Value $record.data_offsets[0] -Name ("tensor '$name' start offset")
   $end=Test-GfxJsonInteger -Value $record.data_offsets[1] -Name ("tensor '$name' end offset")
   if($end -le $start -or $end -gt $dataLength){throw "Tensor '$name' offsets are empty or outside the data buffer."}
   if(($start % 2) -ne 0 -or ($end % 2) -ne 0){throw "Tensor '$name' BF16 offsets are not element-aligned."}
   $expectedBytes=$elements*2
   if(($end-$start) -ne $expectedBytes){throw "Tensor '$name' byte length does not match its BF16 shape."}
   $tensorNames.Add($name)
   $intervals.Add([pscustomobject]@{name=$name;start=$start;end=$end})
   $summaries.Add([pscustomobject]@{name=$name;dtype='BF16';shape=@($dimensions.ToArray());elements=$elements;dataStart=$start;dataEnd=$end;byteCount=$expectedBytes})
  }
  if($tensorNames.Count -eq 0){throw 'Safetensors header contains no tensor records.'}
  $ordered=@($intervals | Sort-Object -Property start,end)
  [long]$cursor=0
  foreach($interval in $ordered){
   if($interval.start -ne $cursor){throw 'Safetensors tensor ranges overlap or leave an unclaimed data gap.'}
   $cursor=[long]$interval.end
  }
  if($cursor -ne $dataLength){throw 'Safetensors data buffer has trailing unclaimed bytes.'}
  return [pscustomobject][ordered]@{
   valid=$true
   format='safetensors-v1'
   fileBytes=$fileLength
   headerBytes=[long]$headerLength
   tensorDataBytes=$dataLength
   tensorCount=$tensorNames.Count
   tensors=@($summaries.ToArray())
   payloadRead=false
   payloadExecuted=false
  }
 }finally{
  if($null -ne $stream){$stream.Dispose()}
 }
}

function Test-GfxPinnedArtifactFile {
 [CmdletBinding()]
 param([Parameter(Mandatory=$true)]$Artifact,[Parameter(Mandatory=$true)][string]$Path)
 Assert-GfxObjectProperties -Object $Artifact -Expected @('path','revision','byteCount','sha256','state') -Name 'artifact lock entry'
 if([string]$Artifact.state -cne 'PINNED'){throw 'Artifact lock entry is not fully pinned.'}
 if([string]$Artifact.path -notmatch '^[A-Za-z0-9._/-]+$' -or $Artifact.path.Contains('..') -or $Artifact.path.StartsWith('/')){throw 'Artifact lock path is unsafe.'}
 if([string]$Artifact.revision -notmatch '^[0-9a-f]{40}$'){throw 'Artifact revision must be a full immutable commit SHA.'}
 $expectedBytes=Test-GfxJsonInteger -Value $Artifact.byteCount -Name 'artifact byteCount' -Minimum 1
 if([string]$Artifact.sha256 -notmatch '^[0-9a-f]{64}$'){throw 'Artifact SHA-256 is invalid.'}
 $full=[IO.Path]::GetFullPath($Path)
 if(-not(Test-Path -LiteralPath $full -PathType Leaf)){throw 'Pinned artifact file was not found.'}
 $info=Get-Item -LiteralPath $full -Force
 if(($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Reparse-point artifact files are not accepted.'}
 if([long]$info.Length -ne $expectedBytes){throw 'Artifact byte count does not match the pinned lock.'}
 $actual=(Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
 if($actual -cne ([string]$Artifact.sha256).ToLowerInvariant()){throw 'Artifact SHA-256 does not match the pinned lock.'}
 return [pscustomobject]@{valid=$true;path=[string]$Artifact.path;revision=[string]$Artifact.revision;byteCount=$expectedBytes;sha256=$actual;verification='LOCAL_SHA256_MATCH'}
}

Export-ModuleMember -Function Read-GfxSafeTensorHeader,Test-GfxPinnedArtifactFile
