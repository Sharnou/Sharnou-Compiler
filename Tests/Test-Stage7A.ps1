[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$compilerPath = Join-Path $repoRoot 'Stage0\SharnouCompiler.ps1'
$verifierPath = Join-Path $repoRoot 'Tools\SharnouPEVerify.ps1'
$exampleRoot = Join-Path $repoRoot 'Examples\ControlFlow'
$buildRoot = Join-Path $repoRoot 'Build\Stage7A'
$encoding = [Text.UTF8Encoding]::new($false)
$nl = [string][char]10

$positiveCases = @(
    [pscustomobject]@{ Name = 'if and else branches'; File = 'IfElse.sharnou'; Expected = ('greater' + $nl + 'equal' + $nl + 'not equal branch') },
    [pscustomobject]@{ Name = 'while loop termination and mutation'; File = 'WhileLoop.sharnou'; Expected = ('10' + $nl + '5') },
    [pscustomobject]@{ Name = 'all six signed comparisons'; File = 'Comparisons.sharnou'; Expected = ('1' + $nl + '0' + $nl + '1' + $nl + '1' + $nl + '1' + $nl + '1') },
    [pscustomobject]@{ Name = 'nested if inside while'; File = 'NestedControlFlow.sharnou'; Expected = ('15' + $nl + 'bounded') },
    [pscustomobject]@{ Name = 'control flow inside user functions'; File = 'FunctionControlFlow.sharnou'; Expected = ('10' + $nl + '7') },
    [pscustomobject]@{ Name = 'signed integer comparison boundaries'; File = 'SignedComparisonEdges.sharnou'; Expected = ('signed less' + $nl + 'minimum inclusive' + $nl + 'signed greater' + $nl + 'maximum inclusive' + $nl + 'not equal') },
    [pscustomobject]@{ Name = 'zero-iteration loop'; File = 'WhileFalse.sharnou'; Expected = 'zero iterations' },
    [pscustomobject]@{ Name = 'arithmetic precedence before comparison'; File = 'ComparisonPrecedence.sharnou'; Expected = 'arithmetic before comparison' }
)
$negativeCases = @(
    [pscustomobject]@{ Name = 'if condition requires parentheses'; Source = 'if 1 < 2 { print(1); }' },
    [pscustomobject]@{ Name = 'if condition rejects strings'; Source = 'if ("text") { print(1); }' },
    [pscustomobject]@{ Name = 'while condition rejects strings'; Source = 'while ("text") { print(1); }' },
    [pscustomobject]@{ Name = 'comparison rejects string operands'; Source = 'if ("a" == "b") { print(1); }' },
    [pscustomobject]@{ Name = 'chained comparisons are rejected'; Source = 'if (1 < 2 < 3) { print(1); }' },
    [pscustomobject]@{ Name = 'orphan else is rejected'; Source = 'else { print(1); }' },
    [pscustomobject]@{ Name = 'unterminated if block is rejected'; Source = 'if (1 < 2) { print(1);' },
    [pscustomobject]@{ Name = 'missing while condition parenthesis'; Source = 'while (1 < 2 { print(1); }' },
    [pscustomobject]@{ Name = 'standalone bang is rejected'; Source = 'if (1 ! 0) { print(1); }' },
    [pscustomobject]@{ Name = 'control-flow keyword cannot be a variable'; Source = 'let while = 2;' },
    [pscustomobject]@{ Name = 'division by zero in condition is rejected'; Source = 'if (1 / 0 > 1) { print(1); }' },
    [pscustomobject]@{ Name = 'else-if shorthand is rejected'; Source = 'if (1) { print(1); } else if (0) { print(0); }' }
)

$script:PassedCount = [int]0
$script:FailedCount = [int]0
function Record-Result {
    param([string] $Name, [bool] $Passed, [string] $Detail = '')
    if ($Passed) {
        $script:PassedCount = [int]($script:PassedCount + 1)
        Write-Host "PASS: $Name" -ForegroundColor Green
    } else {
        $script:FailedCount = [int]($script:FailedCount + 1)
        if ([string]::IsNullOrWhiteSpace($Detail)) { $Detail = 'No diagnostic was captured.' }
        Write-Host ("FAIL: {0} - {1}" -f $Name, $Detail) -ForegroundColor Red
    }
}
function Find-BytePattern {
    param([byte[]] $Bytes, [int] $Start, [int] $Length, [byte[]] $Pattern)
    if ($Pattern.Length -eq 0 -or $Length -lt $Pattern.Length) { return $false }
    $last = $Start + $Length - $Pattern.Length
    for ($i = $Start; $i -le $last; $i++) {
        $equal = $true
        for ($j = 0; $j -lt $Pattern.Length; $j++) {
            if ($Bytes[$i + $j] -ne $Pattern[$j]) { $equal = $false; break }
        }
        if ($equal) { return $true }
    }
    return $false
}
function Get-TextSection {
    param([byte[]] $Bytes)
    if ($Bytes.Length -lt 0x100 -or $Bytes[0] -ne 0x4D -or $Bytes[1] -ne 0x5A) { throw 'Generated output is not an MZ image.' }
    $pe = [BitConverter]::ToInt32($Bytes, 0x3C)
    if ($pe -lt 0 -or ($pe + 24) -gt $Bytes.Length -or $Bytes[$pe] -ne 0x50 -or $Bytes[$pe + 1] -ne 0x45) { throw 'Generated PE signature is invalid.' }
    $sectionCount = [BitConverter]::ToUInt16($Bytes, $pe + 6)
    $optionalSize = [BitConverter]::ToUInt16($Bytes, $pe + 20)
    $table = $pe + 24 + $optionalSize
    for ($i = 0; $i -lt $sectionCount; $i++) {
        $h = $table + ($i * 40)
        $name = [Text.Encoding]::ASCII.GetString($Bytes, $h, 8).Trim([char[]]@(0))
        if ($name -eq '.text') {
            $size = [BitConverter]::ToUInt32($Bytes, $h + 16)
            $offset = [BitConverter]::ToUInt32($Bytes, $h + 20)
            if ($size -eq 0 -or ($offset + $size) -gt $Bytes.Length) { throw '.text raw range is invalid.' }
            return [pscustomobject]@{ Offset = [int]$offset; Size = [int]$size }
        }
    }
    throw '.text section was not found.'
}
function Invoke-PositiveCase {
    param([object] $Case)
    $source = Join-Path $exampleRoot $Case.File
    $output = Join-Path $buildRoot ([IO.Path]::GetFileNameWithoutExtension($Case.File) + '.exe')
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Example is missing: $source" }
    if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output -Force }
    & $compilerPath -Source $source -Output $output
    if (-not (Test-Path -LiteralPath $output -PathType Leaf)) { throw 'Compiler did not produce an executable.' }
    & $verifierPath -Path $output
    if ($LASTEXITCODE -ne 0) { throw "PE verifier returned $LASTEXITCODE." }
    $lines = @(& $output 2>&1)
    $exitCode = $LASTEXITCODE
    $actual = (($lines | ForEach-Object { [string]$_ }) -join [Environment]::NewLine).TrimEnd([char[]]@([char]13, [char]10))
    if ($exitCode -ne 0) { throw "Program exit code was $exitCode; output=[$actual]." }
    if (-not [string]::Equals($actual, [string]$Case.Expected, [StringComparison]::Ordinal)) {
        throw ("Output mismatch. Expected [{0}], received [{1}]." -f $Case.Expected, $actual)
    }
}
try {
    foreach ($required in @($compilerPath, $verifierPath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required tool is missing: $required" }
    }
    New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
    Write-Host '=== Milestone 7A positive runtime cases ==='
    foreach ($case in $positiveCases) {
        $passed = $true; $detail = ''
        try { Invoke-PositiveCase -Case $case } catch { $passed = $false; $detail = [string]$_.Exception.Message }
        Record-Result -Name $case.Name -Passed $passed -Detail $detail
    }

    Write-Host ''
    Write-Host '=== Milestone 7A negative parser/type cases ==='
    $negativeIndex = 0
    foreach ($case in $negativeCases) {
        $negativeIndex++
        $source = Join-Path $buildRoot ("negative-{0:D2}.sharnou" -f $negativeIndex)
        $output = Join-Path $buildRoot ("negative-{0:D2}.exe" -f $negativeIndex)
        $passed = $true; $detail = ''
        try {
            [IO.File]::WriteAllText($source, [string]$case.Source + [Environment]::NewLine, $encoding)
            if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output -Force }
            $diagnostic = ''
            $compiled = $false
            try { & $compilerPath -Source $source -Output $output; $compiled = $true } catch { $diagnostic = [string]$_.Exception.Message }
            if ($compiled) { throw 'Compiler accepted source that must be rejected.' }
            if ($diagnostic -notmatch '(?i)line\s+\d+,\s*column\s+\d+') { throw "Missing line/column diagnostic. Actual error: $diagnostic" }
            if (Test-Path -LiteralPath $output) { throw 'Failed compilation left an executable behind.' }
        } catch {
            $passed = $false
            $detail = [string]$_.Exception.Message
        }
        Record-Result -Name $case.Name -Passed $passed -Detail $detail
    }

    Write-Host ''
    Write-Host '=== Native instruction encoding checks ==='
    $comparisonExe = Join-Path $buildRoot 'Comparisons.exe'
    $whileExe = Join-Path $buildRoot 'WhileLoop.exe'
    $comparisonBytes = [IO.File]::ReadAllBytes($comparisonExe)
    $comparisonText = Get-TextSection -Bytes $comparisonBytes
    $patterns = @(
        [pscustomobject]@{ Name = 'SETL encoding for <'; Bytes = [byte[]]@(0x0F, 0x9C, 0xC0) },
        [pscustomobject]@{ Name = 'SETG encoding for >'; Bytes = [byte[]]@(0x0F, 0x9F, 0xC0) },
        [pscustomobject]@{ Name = 'SETLE encoding for <='; Bytes = [byte[]]@(0x0F, 0x9E, 0xC0) },
        [pscustomobject]@{ Name = 'SETGE encoding for >='; Bytes = [byte[]]@(0x0F, 0x9D, 0xC0) },
        [pscustomobject]@{ Name = 'SETE encoding for =='; Bytes = [byte[]]@(0x0F, 0x94, 0xC0) },
        [pscustomobject]@{ Name = 'SETNE encoding for !='; Bytes = [byte[]]@(0x0F, 0x95, 0xC0) }
    )
    $comparisonPassed = $true; $comparisonDetail = ''
    try {
        foreach ($pattern in $patterns) {
            if (-not (Find-BytePattern -Bytes $comparisonBytes -Start $comparisonText.Offset -Length $comparisonText.Size -Pattern $pattern.Bytes)) {
                throw "Missing expected instruction: $($pattern.Name)."
            }
        }
    } catch { $comparisonPassed = $false; $comparisonDetail = [string]$_.Exception.Message }
    Record-Result -Name 'All six signed SETcc comparison instructions are emitted' -Passed $comparisonPassed -Detail $comparisonDetail

    $branchPassed = $true; $branchDetail = ''
    try {
        $image = [IO.File]::ReadAllBytes((Join-Path $buildRoot 'IfElse.exe'))
        $text = Get-TextSection -Bytes $image
        if (-not (Find-BytePattern -Bytes $image -Start $text.Offset -Length $text.Size -Pattern ([byte[]]@(0x85, 0xC0, 0x0F, 0x84)))) {
            throw 'Expected TEST EAX,EAX followed by near JZ was not found.'
        }
    } catch { $branchPassed = $false; $branchDetail = [string]$_.Exception.Message }
    Record-Result -Name 'If/else emits TEST plus conditional near branch' -Passed $branchPassed -Detail $branchDetail

    $loopPassed = $true; $loopDetail = ''
    try {
        $image = [IO.File]::ReadAllBytes($whileExe)
        $text = Get-TextSection -Bytes $image
        if (-not (Find-BytePattern -Bytes $image -Start $text.Offset -Length $text.Size -Pattern ([byte[]]@(0xE9)))) { throw 'Expected near JMP loop-back instruction was not found.' }
        if (-not (Find-BytePattern -Bytes $image -Start $text.Offset -Length $text.Size -Pattern ([byte[]]@(0x0F, 0x84)))) { throw 'Expected JZ loop-exit instruction was not found.' }
    } catch { $loopPassed = $false; $loopDetail = [string]$_.Exception.Message }
    Record-Result -Name 'While emits a conditional exit and a backward JMP' -Passed $loopPassed -Detail $loopDetail

    $expectedTotal = [int]($positiveCases.Count + $negativeCases.Count + 3)
    $actualTotal = [int]($script:PassedCount + $script:FailedCount)
    Write-Host ''
    Write-Host ("Stage 7A tests: {0} passed, {1} failed, {2} total." -f $script:PassedCount, $script:FailedCount, $actualTotal)
    if ($actualTotal -ne $expectedTotal) { throw "Test accounting mismatch: expected $expectedTotal result records, got $actualTotal." }
    if ($script:FailedCount -ne 0) { throw 'One or more Milestone 7A cases failed.' }
    Write-Host 'Stage 7A test result: PASS' -ForegroundColor Green
} catch {
    Write-Host "Stage 7A test result: FAIL - $($_.Exception.Message)" -ForegroundColor Red
    throw
}
