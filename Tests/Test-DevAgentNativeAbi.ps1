[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
function Assert-Contract { param([bool]$Condition,[string]$Message) if (-not $Condition) { throw $Message } }
function Convert-HexToInt { param([string]$Value) return [Convert]::ToInt32($Value.Substring(2),16) }
function Get-AlignUp { param([int]$Value,[int]$Alignment) return [int](($Value + $Alignment - 1) -band (-$Alignment)) }

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$manifestPath = Join-Path $PSScriptRoot 'DevAgentBroker\native-abi-manifest.json'
$compilerPath = Join-Path $repoRoot 'Stage0\SharnouCompiler.ps1'
Assert-Contract ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) 'This ABI contract test requires Windows.'
Assert-Contract ([Environment]::Is64BitOperatingSystem -and [Environment]::Is64BitProcess) 'The ABI contract must execute in a 64-bit process on a 64-bit OS.'
Assert-Contract (Test-Path -LiteralPath $manifestPath -PathType Leaf) 'Native ABI manifest is missing.'
Assert-Contract (Test-Path -LiteralPath $compilerPath -PathType Leaf) 'Sharnou compiler source is missing.'
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Contract ([int]$manifest.schemaVersion -eq 1) 'Unsupported native ABI manifest schema.'
Assert-Contract ([int]$manifest.target.pointerSize -eq 8 -and [int]$manifest.target.defaultPacking -eq 8) 'Manifest is not the expected x64 / pack-8 contract.'
$compiler = [IO.File]::ReadAllText($compilerPath)
$newline = [string][char]10

# Compare the complete observed import descriptor / lookup / IAT map.
$importStart = $compiler.IndexOf('$importSets = @(', [StringComparison]::Ordinal)
Assert-Contract ($importStart -ge 0) 'Compiler import-set declaration was not found.'
$importTail = $compiler.Substring($importStart)
$importEnd = $importTail.IndexOf($newline + ')', [StringComparison]::Ordinal)
Assert-Contract ($importEnd -ge 0) 'Compiler import-set declaration is unterminated.'
$importBlock = $importTail.Substring(0,$importEnd + 2)
$actualGroups = New-Object 'System.Collections.Generic.List[object]'
$groupPattern = "Descriptor\s*=\s*(0x[0-9A-Fa-f]+);\s*Lookup\s*=\s*(0x[0-9A-Fa-f]+);\s*Iat\s*=\s*(0x[0-9A-Fa-f]+);\s*Dll\s*=\s*'([^']+)';\s*Names\s*=\s*@\((.*?)\)"
foreach ($match in [regex]::Matches($importBlock,$groupPattern,[Text.RegularExpressions.RegexOptions]::Singleline)) {
    $names = New-Object 'System.Collections.Generic.List[string]'
    foreach ($nameMatch in [regex]::Matches($match.Groups[5].Value,"'([^']+)'")) { $names.Add($nameMatch.Groups[1].Value) }
    $actualGroups.Add([pscustomobject]@{
        descriptor=$match.Groups[1].Value.ToUpperInvariant()
        lookup=$match.Groups[2].Value.ToUpperInvariant()
        iat=$match.Groups[3].Value.ToUpperInvariant()
        dll=$match.Groups[4].Value
        names=$names.ToArray()
    })
}
Assert-Contract ($actualGroups.Count -eq [int]$manifest.currentImportTable.descriptorCount) ("Observed import descriptor count mismatch: expected {0}; actual {1}" -f $manifest.currentImportTable.descriptorCount,$actualGroups.Count)
Assert-Contract ($actualGroups.Count -eq @($manifest.currentImportTable.groups).Count) 'Manifest import group count does not match its descriptor count.'
for ($i=0; $i -lt $actualGroups.Count; $i++) {
    $actual=$actualGroups[$i]; $expected=$manifest.currentImportTable.groups[$i]
    Assert-Contract ($actual.descriptor -ceq ([string]$expected.descriptor).ToUpperInvariant()) ("Import group $i descriptor RVA mismatch.")
    Assert-Contract ($actual.lookup -ceq ([string]$expected.lookup).ToUpperInvariant()) ("Import group $i lookup RVA mismatch.")
    Assert-Contract ($actual.iat -ceq ([string]$expected.iat).ToUpperInvariant()) ("Import group $i IAT RVA mismatch.")
    Assert-Contract ($actual.dll -ceq [string]$expected.dll) ("Import group $i DLL mismatch.")
    Assert-Contract (($actual.names -join '|') -ceq (@($expected.names) -join '|')) ("Import group $i import-name order mismatch.")
}
$descriptorBaseMatch=[regex]::Match($compiler,'\$descriptorBase\s*=\s*(0x[0-9A-Fa-f]+)')
$directorySizeMatch=[regex]::Match($compiler,'\$importDirectorySize\s*=\s*(0x[0-9A-Fa-f]+)')
Assert-Contract ($descriptorBaseMatch.Success -and (Convert-HexToInt $descriptorBaseMatch.Groups[1].Value) -eq (Convert-HexToInt ([string]$manifest.currentImportTable.descriptorBase))) 'Import descriptor base changed without an ABI manifest update.'
Assert-Contract ($directorySizeMatch.Success -and (Convert-HexToInt $directorySizeMatch.Groups[1].Value) -eq (Convert-HexToInt ([string]$manifest.currentImportTable.directorySize))) 'Import directory size changed without an ABI manifest update.'

$iatStart=$compiler.IndexOf('$script:StdLibIatOffsets = @{',[StringComparison]::Ordinal)
Assert-Contract ($iatStart -ge 0) 'StdLib IAT-offset map was not found.'
$iatTail=$compiler.Substring($iatStart)
$iatEnd=$iatTail.IndexOf($newline + '}',[StringComparison]::Ordinal)
Assert-Contract ($iatEnd -ge 0) 'StdLib IAT-offset map is unterminated.'
$iatBlock=$iatTail.Substring(0,$iatEnd+2)
$actualIat=@{}
foreach($entry in [regex]::Matches($iatBlock,"'([^']+)'\s*=\s*\[UInt32\]0x([0-9A-Fa-f]+)")){
    $actualIat[$entry.Groups[1].Value]=[Convert]::ToInt32($entry.Groups[2].Value,16)
}
foreach($group in $manifest.currentImportTable.groups){
    $base=Convert-HexToInt ([string]$group.iat)
    for($index=0;$index -lt @($group.names).Count;$index++){
        $name=[string]$group.names[$index]
        Assert-Contract ($actualIat.ContainsKey($name)) ("IAT offset is missing for {0}" -f $name)
        Assert-Contract ($actualIat[$name] -eq ($base + ($index*8))) ("IAT offset mismatch for {0}" -f $name)
    }
}
$currentNames=@($actualGroups | ForEach-Object { $_.names } | Select-Object -Unique)
foreach($apiGroup in $manifest.plannedImports){
    foreach($api in $apiGroup.names){
        Assert-Contract ($currentNames -notcontains [string]$api) ("Planned Phase 2B import unexpectedly already exists in the current import map: {0}" -f $api)
    }
}

# Compute aggregate layouts using the Windows x64 default ABI (pointer size 8, pack 8).
$typeInfo=@{
    DWORD=@{Size=4;Alignment=4}; WORD=@{Size=2;Alignment=2}
    PTR=@{Size=8;Alignment=8}; PTRSIZE=@{Size=8;Alignment=8}
    I64=@{Size=8;Alignment=8}; U64=@{Size=8;Alignment=8}
}
$layoutCount=0
foreach($structure in $manifest.structureLayouts){
    $cursor=0; $maxAlignment=1
    foreach($field in $structure.fields){
        $fieldName=[string]$field[0]; $fieldType=[string]$field[1]; $expectedOffset=[int]$field[2]
        Assert-Contract ($typeInfo.ContainsKey($fieldType)) ("Structure {0} uses unknown layout field type {1}" -f $structure.name,$fieldType)
        $info=$typeInfo[$fieldType]
        $offset=Get-AlignUp -Value $cursor -Alignment ([int]$info.Alignment)
        Assert-Contract ($offset -eq $expectedOffset) ("{0}.{1} offset mismatch: computed {2}, manifest {3}" -f $structure.name,$fieldName,$offset,$expectedOffset)
        $cursor=$offset+[int]$info.Size
        if([int]$info.Alignment -gt $maxAlignment){$maxAlignment=[int]$info.Alignment}
        $layoutCount++
    }
    $computedSize=Get-AlignUp -Value $cursor -Alignment $maxAlignment
    Assert-Contract ($computedSize -eq [int]$structure.size) ("{0} size mismatch: computed {1}, manifest {2}" -f $structure.name,$computedSize,$structure.size)
    Assert-Contract ($maxAlignment -eq [int]$structure.alignment) ("{0} alignment mismatch." -f $structure.name)
    $typeInfo[[string]$structure.name]=@{Size=$computedSize;Alignment=$maxAlignment}
}

# Inspect declarations and field order in the installed Windows SDK.
$programFilesX86=[Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
$sdkInclude=Join-Path $programFilesX86 'Windows Kits\10\Include'
Assert-Contract (Test-Path -LiteralPath $sdkInclude -PathType Container) 'Windows 10 SDK include root is unavailable on this runner.'
$sdkVersions=@(Get-ChildItem -LiteralPath $sdkInclude -Directory | Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } | Sort-Object { [Version]$_.Name } -Descending)
Assert-Contract ($sdkVersions.Count -gt 0) 'No versioned Windows SDK include directory was found.'
$sdkVersion=$sdkVersions[0].Name
$headerCache=@{}
$headerPaths=@('um\winnt.h','um\winbase.h','um\processthreadsapi.h','um\userenv.h','um\securitybaseapi.h','um\heapapi.h','um\errhandlingapi.h')
foreach($relative in $headerPaths){
    $full=Join-Path (Join-Path $sdkInclude $sdkVersion) $relative
    Assert-Contract (Test-Path -LiteralPath $full -PathType Leaf) ("Required Windows SDK header is missing: {0}" -f $relative)
    $headerCache[$relative]=[IO.File]::ReadAllText($full)
}
$combinedHeaders=$headerCache.Values -join $newline
foreach($structure in $manifest.structureLayouts){
    $type=[string]$structure.name
    $typePattern='(?is)typedef\s+struct\s+_'+[regex]::Escape($type)+'\s*\{(?<body>.*?)\}\s*'+[regex]::Escape($type)+'\b'
    $typeMatch=[regex]::Match($combinedHeaders,$typePattern)
    Assert-Contract $typeMatch.Success ("Windows SDK declaration for {0} was not found." -f $type)
    $body=$typeMatch.Groups['body'].Value
    if ($type -eq 'SECURITY_CAPABILITIES') {
        # winnt.h expresses the two pointer members in nested conditional-compilation
        # arms. A raw first-text-occurrence comparison crosses mutually exclusive
        # branches and is not a valid C ABI field-order test for this declaration.
        # Require the four typed declarations to be present; separately validate the
        # expected x64 offsets/sizes with the pack-8 layout model below.
        Assert-Contract ([regex]::IsMatch($body,'(?m)\b(?:PISID|PSID)\s+AppContainerSid\s*;')) 'SECURITY_CAPABILITIES AppContainerSid declaration is missing.'
        Assert-Contract ([regex]::IsMatch($body,'(?m)\bPSID_AND_ATTRIBUTES\s+Capabilities\s*;')) 'SECURITY_CAPABILITIES Capabilities declaration is missing.'
        Assert-Contract ([regex]::IsMatch($body,'(?m)\bDWORD\s+CapabilityCount\s*;')) 'SECURITY_CAPABILITIES CapabilityCount declaration is missing.'
        Assert-Contract ([regex]::IsMatch($body,'(?m)\bDWORD\s+Reserved\s*;')) 'SECURITY_CAPABILITIES Reserved declaration is missing.'
        continue
    }
    $lastIndex=-1
    foreach($field in $structure.fields){
        $fieldName=[string]$field[0]
        $fieldMatch=[regex]::Match($body,'\b'+[regex]::Escape($fieldName)+'\b')
        Assert-Contract $fieldMatch.Success ("Windows SDK field {0}.{1} was not found." -f $type,$fieldName)
        Assert-Contract ($fieldMatch.Index -gt $lastIndex) ("Windows SDK field order mismatch for {0}.{1}" -f $type,$fieldName)
        $lastIndex=$fieldMatch.Index
    }
}
$apiHeaders=@{
    'InitializeProcThreadAttributeList'='um\processthreadsapi.h'
    'UpdateProcThreadAttribute'='um\processthreadsapi.h'
    'DeleteProcThreadAttributeList'='um\processthreadsapi.h'
    'CreateProcessW'='um\processthreadsapi.h'
    'GetProcessHeap'='um\heapapi.h'
    'HeapAlloc'='um\heapapi.h'
    'HeapFree'='um\heapapi.h'
    'GetLastError'='um\errhandlingapi.h'
    'CreateAppContainerProfile'='um\userenv.h'
    'DeleteAppContainerProfile'='um\userenv.h'
    'OpenProcessToken'='um\processthreadsapi.h'
    'GetTokenInformation'='um\securitybaseapi.h'
    'FreeSid'='um\securitybaseapi.h'
    'IsValidSid'='um\securitybaseapi.h'
    'EqualSid'='um\securitybaseapi.h'
    'GetSidSubAuthorityCount'='um\securitybaseapi.h'
    'GetSidSubAuthority'='um\securitybaseapi.h'
}
foreach($api in $apiHeaders.Keys){
    $header=$headerCache[$apiHeaders[$api]]
    Assert-Contract ([regex]::IsMatch($header,'\b'+[regex]::Escape($api)+'\s*\(')) ("Windows SDK function declaration missing: {0} ({1})" -f $api,$apiHeaders[$api])
}

foreach($api in $manifest.plannedApiSignatures){
    $matchingGroups=@($manifest.plannedImports | Where-Object { $_.dll -ceq $api.dll -and @($_.names) -contains [string]$api.name })
    Assert-Contract ($matchingGroups.Count -eq 1) ("API-to-DLL mapping is missing or ambiguous for {0}" -f $api.name)
    Assert-Contract ([string]$api.returnType -ne '' -and @($api.parameters).Count -ge 1) ("API signature is incomplete for {0}" -f $api.name)
    $expectedHeader=([string]$api.header).Replace('/','\')
    Assert-Contract ([string]$api.name -ceq [string]$api.name.Trim()) ("API name contains invalid surrounding whitespace: {0}" -f $api.name)
    Assert-Contract ($apiHeaders[[string]$api.name] -ceq $expectedHeader) ("API declaration header mapping differs for {0}" -f $api.name)
}
    $header=$headerCache[$expectedHeader]
    $prototypeMatch=[regex]::Match($header,'\b'+[regex]::Escape([string]$api.name)+'\s*\(')
    Assert-Contract $prototypeMatch.Success ("SDK prototype not found for {0}" -f $api.name)
    $declarationStart=$header.LastIndexOf(';',[int]$prototypeMatch.Index)
    $declarationPrefixStart=[Math]::Max(0,$declarationStart+1)
    $declarationPrefix=$header.Substring($declarationPrefixStart,[int]$prototypeMatch.Index-$declarationPrefixStart)
    Assert-Contract ([regex]::IsMatch($declarationPrefix,'\b'+[regex]::Escape([string]$api.returnType)+'\b')) ("SDK return type mismatch for {0}: expected {1}" -f $api.name,$api.returnType)
    $openParen=$header.IndexOf('(',[int]$prototypeMatch.Index)
    Assert-Contract ($openParen -ge 0) ("SDK prototype opening parenthesis missing for {0}" -f $api.name)
    $depth=0; $closeParen=-1
    for($scan=$openParen;$scan -lt $header.Length;$scan++){
        if($header[$scan] -eq '('){$depth++}
        elseif($header[$scan] -eq ')'){
            $depth--
            if($depth -eq 0){$closeParen=$scan;break}
        }
    }
    Assert-Contract ($closeParen -gt $openParen) ("SDK prototype parameter list is unterminated for {0}" -f $api.name)
    $parameterText=$header.Substring($openParen+1,$closeParen-$openParen-1)
    $normalizedParameters=[regex]::Replace($parameterText,'\s+','')
    $parameterCursor=0
    foreach($parameterType in $api.parameters){
        $normalizedType=[regex]::Replace([string]$parameterType,'\s+','')
        $parameterIndex=$normalizedParameters.IndexOf($normalizedType,$parameterCursor,[StringComparison]::Ordinal)
        Assert-Contract ($parameterIndex -ge $parameterCursor) ("SDK parameter type/order mismatch for {0}: expected {1}" -f $api.name,$parameterType)
        $parameterCursor=$parameterIndex+$normalizedType.Length
    }


Assert-Contract ([int]$manifest.tokenInformation[0].value -eq 25) 'TokenIntegrityLevel class value mismatch.'
Assert-Contract ([int]$manifest.tokenInformation[1].value -eq 29) 'TokenIsAppContainer class value mismatch.'
Assert-Contract ([int]$manifest.tokenInformation[2].value -eq 31) 'TokenAppContainerSid class value mismatch.'
Assert-Contract ((Convert-HexToInt ([string]$manifest.constants.PROC_THREAD_ATTRIBUTE_SECURITY_CAPABILITIES)) -eq 0x20009) 'SECURITY_CAPABILITIES process-attribute value mismatch.'
Assert-Contract ((Convert-HexToInt ([string]$manifest.constants.PROC_THREAD_ATTRIBUTE_HANDLE_LIST)) -eq 0x20002) 'HANDLE_LIST process-attribute value mismatch.'
Assert-Contract ((Convert-HexToInt ([string]$manifest.constants.EXTENDED_STARTUPINFO_PRESENT)) -eq 0x80000) 'EXTENDED_STARTUPINFO_PRESENT value mismatch.'
Assert-Contract ((Convert-HexToInt ([string]$manifest.constants.CREATE_SUSPENDED)) -eq 4) 'CREATE_SUSPENDED value mismatch.'
Assert-Contract ((Convert-HexToInt ([string]$manifest.constants.CREATE_UNICODE_ENVIRONMENT)) -eq 0x400) 'CREATE_UNICODE_ENVIRONMENT value mismatch.'
Assert-Contract ((Convert-HexToInt ([string]$manifest.constants.PROCESS_QUERY_LIMITED_INFORMATION)) -eq 0x1000) 'PROCESS_QUERY_LIMITED_INFORMATION value mismatch.'
Assert-Contract ([int]$manifest.constants.ERROR_INSUFFICIENT_BUFFER -eq 122) 'ERROR_INSUFFICIENT_BUFFER value mismatch.'
Assert-Contract ([int]$manifest.constants.ERROR_ALREADY_EXISTS -eq 183) 'ERROR_ALREADY_EXISTS value mismatch.'
$alreadyExistsHresult = [string]$manifest.constants.HRESULT_FROM_WIN32_ERROR_ALREADY_EXISTS
Assert-Contract ($alreadyExistsHresult -ceq '0x800700B7') 'HRESULT_FROM_WIN32(ERROR_ALREADY_EXISTS) value mismatch.'
Assert-Contract ((Convert-HexToInt ([string]$manifest.constants.S_OK)) -eq 0) 'S_OK value mismatch.'

Write-Host 'Windows SDK ABI contract: PASS'
Write-Host ("Windows SDK version: {0}" -f $sdkVersion)
Write-Host ("x64 structure fields/offsets checked: {0}" -f $layoutCount)
Write-Host ("x64 aggregate structures checked: {0}" -f @($manifest.structureLayouts).Count)
Write-Host ("Existing PE import groups checked: {0}" -f $actualGroups.Count)
Write-Host ("Existing IAT entries checked: {0}" -f $actualIat.Count)
Write-Host ("Planned API declarations checked: {0}" -f $apiHeaders.Count)
Write-Host 'Token information classes checked: 3'
Write-Host 'Evidence boundary: declaration/layout contract only; no native process or executable was created.'
