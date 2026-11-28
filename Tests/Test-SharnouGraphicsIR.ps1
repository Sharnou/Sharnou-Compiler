[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$toolPath = Join-Path $PSScriptRoot '..\Tools\SharnouGraphicsIR.ps1'
$fixturePath = Join-Path $PSScriptRoot '..\Examples\GraphicsIR\triangle-minimal.sgir.json'
. (Resolve-Path -LiteralPath $toolPath).Path

$script:Passed = 0
$script:Failed = 0

function Assert-Test {
    param([string] $Name, [bool] $Condition, [string] $Detail = '')
    if ($Condition) {
        $script:Passed++
        Write-Host ("PASS: {0}" -f $Name)
    } else {
        $script:Failed++
        Write-Host ("FAIL: {0} {1}" -f $Name, $Detail) -ForegroundColor Red
    }
}

function Invoke-ExpectedFailure {
    param([string] $Name, [string] $Json, [string] $ExpectedCode)
    $matched = $false
    try {
        $document = ConvertFrom-SgirJsonText -Json $Json
        $null = Assert-SgirModule -Document $document
    } catch {
        $matched = $_.Exception.Message -match ("SGIR-" + [regex]::Escape($ExpectedCode) + ':')
        if (-not $matched) {
            Assert-Test -Name $Name -Condition $false -Detail $_.Exception.Message
            return
        }
    }
    Assert-Test -Name $Name -Condition $matched -Detail ("Expected SGIR-{0}." -f $ExpectedCode)
}

$fixture = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $fixturePath).Path, [System.Text.Encoding]::UTF8)
$document = ConvertFrom-SgirJsonText -Json $fixture
$result = Assert-SgirModule -Document $document
Assert-Test -Name 'valid vertex module, typed interfaces, cbuffer and phi CFG' -Condition ($result.Valid -and $result.EntryPointCount -eq 1 -and $result.FunctionCount -eq 2)
Assert-Test -Name 'canonical SHA-256 is lowercase 64-hex' -Condition ($result.CanonicalSha256 -cmatch '^[0-9a-f]{64}$')

$compact = ($fixture -replace '\s+', ' ')
$compactDocument = ConvertFrom-SgirJsonText -Json $compact
$compactHash = Get-SgirCanonicalHash -Document $compactDocument
Assert-Test -Name 'canonical hash ignores JSON whitespace' -Condition ($compactHash -ceq $result.CanonicalSha256)

$reordered = [ordered]@{}
$properties = @($document.PSObject.Properties)
for ($i = $properties.Count - 1; $i -ge 0; $i--) {
    $reordered[$properties[$i].Name] = $properties[$i].Value
}
$reorderedJson = ConvertTo-Json -InputObject $reordered -Depth 100 -Compress
$reorderedDocument = ConvertFrom-SgirJsonText -Json $reorderedJson
Assert-Test -Name 'canonical hash ignores object property insertion order' -Condition ((Get-SgirCanonicalHash -Document $reorderedDocument) -ceq $result.CanonicalSha256)

Invoke-ExpectedFailure -Name 'reject duplicate JSON property names' -Json ($fixture.Replace('"schema": "SGIR/1",','"schema": "SGIR/1", "schema": "SGIR/1",')) -ExpectedCode 'J002'
Invoke-ExpectedFailure -Name 'reject malformed JSON' -Json '{"schema":"SGIR/1"' -ExpectedCode 'J004'
Invoke-ExpectedFailure -Name 'reject unknown module properties' -Json ($fixture.Replace('"moduleId": "sharnou.example.triangle",','"rogue": true, "moduleId": "sharnou.example.triangle",')) -ExpectedCode 'S004'
Invoke-ExpectedFailure -Name 'reject unsupported IR version' -Json ($fixture.Replace('"schema": "SGIR/1"','"schema": "SGIR/2"')) -ExpectedCode 'S002'
Invoke-ExpectedFailure -Name 'reject out-of-range vector width' -Json ($fixture.Replace('"lanes": 4','"lanes": 5')) -ExpectedCode 'S009'
Invoke-ExpectedFailure -Name 'reject missing vertex position output' -Json ($fixture.Replace('"semantic": "SV_Position"','"semantic": "POSITION_OUT"')) -ExpectedCode 'E010'
Invoke-ExpectedFailure -Name 'reject unknown CFG branch target' -Json ($fixture.Replace('"trueTarget": "left"','"trueTarget": "missing_block"')) -ExpectedCode 'F008'
Invoke-ExpectedFailure -Name 'reject unreachable basic block' -Json ($fixture.Replace('"trueTarget": "left"','"trueTarget": "join"')) -ExpectedCode 'F011'
Invoke-ExpectedFailure -Name 'reject malformed phi predecessor list' -Json ($fixture.Replace('"block": "right"','"block": "zz"')) -ExpectedCode 'V011'
Invoke-ExpectedFailure -Name 'reject malformed IEEE-754 bit pattern' -Json ($fixture.Replace('"literal": "3F800000"','"literal": "3F8000GG"')) -ExpectedCode 'V002'
Invoke-ExpectedFailure -Name 'reject non-Boolean constant representation' -Json ($fixture.Replace('"literal": true','"literal": 1')) -ExpectedCode 'V001'
Invoke-ExpectedFailure -Name 'reject unknown instruction opcode' -Json ($fixture.Replace('"op": "load_input"','"op": "load_gpu_magic"')) -ExpectedCode 'V007'
$badInputType = ConvertFrom-SgirJsonText -Json $fixture
$vertexFunctionForType = @($badInputType.functions | Where-Object { $_.id -ceq 'fn_vs' })[0]
$vertexFunctionForType.blocks[0].instructions[0].type = 'f32'
$badInputTypeJson = ConvertTo-Json -InputObject $badInputType -Depth 100 -Compress
Invoke-ExpectedFailure -Name 'reject mismatched load-input interface type' -Json $badInputTypeJson -ExpectedCode 'V018'

$duplicateResource = ConvertFrom-SgirJsonText -Json $fixture
$duplicateResource.resources = @($duplicateResource.resources) + @($duplicateResource.resources)
$duplicateResourceJson = ConvertTo-Json -InputObject $duplicateResource -Depth 100 -Compress
Invoke-ExpectedFailure -Name 'reject resource register collisions' -Json $duplicateResourceJson -ExpectedCode 'R002'

$undefinedPhi = ConvertFrom-SgirJsonText -Json $fixture
$chooseFunction = @($undefinedPhi.functions | Where-Object { $_.id -ceq 'fn_choose' })[0]
$joinBlock = @($chooseFunction.blocks | Where-Object { $_.id -ceq 'join' })[0]
$joinBlock.instructions[0].incoming[0].value = 'undefined_value'
$undefinedPhiJson = ConvertTo-Json -InputObject $undefinedPhi -Depth 100 -Compress
Invoke-ExpectedFailure -Name 'reject undefined phi input' -Json $undefinedPhiJson -ExpectedCode 'V012'

$nonDominating = ConvertFrom-SgirJsonText -Json $fixture
$chooseFunction = @($nonDominating.functions | Where-Object { $_.id -ceq 'fn_choose' })[0]
$rightBlock = @($chooseFunction.blocks | Where-Object { $_.id -ceq 'right' })[0]
$rightBlock.instructions = @($rightBlock.instructions) + @([pscustomobject]@{
    op = 'add'
    result = 'bad_sum'
    type = 'i32'
    operands = @('left_value','right_value')
})
$nonDominatingJson = ConvertTo-Json -InputObject $nonDominating -Depth 100 -Compress
Invoke-ExpectedFailure -Name 'reject SSA value not dominating its use' -Json $nonDominatingJson -ExpectedCode 'V027'

$badOutput = ConvertFrom-SgirJsonText -Json $fixture
$vertexFunction = @($badOutput.functions | Where-Object { $_.id -ceq 'fn_vs' })[0]
$vertexFunction.blocks[0].instructions[1].value = 'missing_value'
$badOutputJson = ConvertTo-Json -InputObject $badOutput -Depth 100 -Compress
Invoke-ExpectedFailure -Name 'reject undefined stage output value' -Json $badOutputJson -ExpectedCode 'V029'

$wrongReturn = ConvertFrom-SgirJsonText -Json $fixture
$chooseFunction = @($wrongReturn.functions | Where-Object { $_.id -ceq 'fn_choose' })[0]
$chooseFunction.returnType = 'f32'
$wrongReturnJson = ConvertTo-Json -InputObject $wrongReturn -Depth 100 -Compress
Invoke-ExpectedFailure -Name 'reject return type mismatch' -Json $wrongReturnJson -ExpectedCode 'V036'


$typeCycle = ConvertFrom-SgirJsonText -Json $fixture
$frameType = @($typeCycle.types | Where-Object { $_.id -ceq 'frame_data' })[0]
$frameType.fields[0].type = 'frame_data'
$typeCycleJson = ConvertTo-Json -InputObject $typeCycle -Depth 100 -Compress
Invoke-ExpectedFailure -Name 'reject recursive aggregate type cycles' -Json $typeCycleJson -ExpectedCode 'T010'

$badReturnDominance = ConvertFrom-SgirJsonText -Json $fixture
$chooseForReturn = @($badReturnDominance.functions | Where-Object { $_.id -ceq 'fn_choose' })[0]
$joinForReturn = @($chooseForReturn.blocks | Where-Object { $_.id -ceq 'join' })[0]
$joinForReturn.terminator.value = 'left_value'
$badReturnDominanceJson = ConvertTo-Json -InputObject $badReturnDominance -Depth 100 -Compress
Invoke-ExpectedFailure -Name 'reject return value not dominated by its definition' -Json $badReturnDominanceJson -ExpectedCode 'V038'

$nullArrayDocument = ConvertFrom-SgirJsonText -Json $fixture
$nullArrayDocument.resources = $null
$nullArrayJson = ConvertTo-Json -InputObject $nullArrayDocument -Depth 100 -Compress
Invoke-ExpectedFailure -Name 'reject null where an array is required' -Json $nullArrayJson -ExpectedCode 'S005'

$tempDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('Sharnou-SGIR-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempDirectory -Force | Out-Null
try {
    $canonicalPath = Join-Path $tempDirectory 'canonical.sgir.json'
    & $toolPath -Action Canonicalize -InputPath $fixturePath -OutputPath $canonicalPath | Out-Null
    $bytes = [System.IO.File]::ReadAllBytes($canonicalPath)
    $hasUtf8Bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $canonicalText = [System.IO.File]::ReadAllText($canonicalPath, (New-Object System.Text.UTF8Encoding($false, $true)))
    Assert-Test -Name 'canonical output is UTF-8 without BOM' -Condition (-not $hasUtf8Bom)
    Assert-Test -Name 'canonical output has stable one-line JSON plus newline' -Condition ($canonicalText.EndsWith([Environment]::NewLine) -and $canonicalText.Trim().StartsWith('{'))
    $canonicalRoundTrip = Read-SgirModuleFile -Path $canonicalPath
    $roundTripResult = Assert-SgirModule -Document $canonicalRoundTrip
    Assert-Test -Name 'canonical output round-trips through verifier' -Condition ($roundTripResult.CanonicalSha256 -ceq $result.CanonicalSha256)
} finally {
    Remove-Item -LiteralPath $tempDirectory -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ("SGIR/1 tests: {0} passed; {1} failed." -f $script:Passed, $script:Failed)
if ($script:Failed -ne 0) { throw 'SGIR/1 test suite failed.' }
