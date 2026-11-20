[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$compilerPath = Join-Path $repoRoot 'Stage0\SharnouCompiler.ps1'
$verifierPath = Join-Path $repoRoot 'Tools\SharnouPEVerify.ps1'
$buildRoot = Join-Path $repoRoot 'Build\Stage7BTests'
if (-not (Test-Path -LiteralPath $compilerPath -PathType Leaf)) { throw 'Stage 7B compiler is missing.' }
if (-not (Test-Path -LiteralPath $verifierPath -PathType Leaf)) { throw 'Stage 7B PE verifier is missing.' }
if (Test-Path -LiteralPath $buildRoot) { Remove-Item -LiteralPath $buildRoot -Recurse -Force }
$null = New-Item -ItemType Directory -Path $buildRoot -Force
$utf8 = New-Object System.Text.UTF8Encoding($false)
$script:PassedCount = 0
$script:FailedCount = 0
function Record-Stage7BResult {
    param([string] $Name, [bool] $Passed, [string] $Detail = '')
    if ($Passed) { $script:PassedCount++; Write-Host "PASS: $Name" -ForegroundColor Green }
    else { $script:FailedCount++; Write-Host "FAIL: $Name - $Detail" -ForegroundColor Red }
}
function Normalize-Output {
    param([object[]] $Lines)
    return (($Lines | ForEach-Object { [string]$_ }) -join ([string][char]10)).TrimEnd([char[]]@([char]13, [char]10))
}
function Invoke-PositiveCase {
    param([object] $Case)
    $sourcePath = Join-Path $buildRoot $Case.File
    $exePath = [System.IO.Path]::ChangeExtension($sourcePath, '.exe')
    [System.IO.File]::WriteAllText($sourcePath, [string]$Case.Source + [Environment]::NewLine, $utf8)
    & $compilerPath -Source $sourcePath -Output $exePath
    if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) { throw 'Compiler did not create the expected PE32+ executable.' }
    & $verifierPath -Path $exePath
    $lines = @(& $exePath 2>&1)
    $exitCode = $LASTEXITCODE
    $actual = Normalize-Output -Lines $lines
    if ($exitCode -ne 0) { throw "Expected exit code 0; received $exitCode. Output=[$actual]." }
    if (-not [string]::Equals($actual, [string]$Case.Expected, [System.StringComparison]::Ordinal)) {
        throw "Output mismatch. Expected [$($Case.Expected)] but received [$actual]."
    }
}
function Invoke-NegativeCase {
    param([object] $Case)
    $sourcePath = Join-Path $buildRoot $Case.File
    $exePath = [System.IO.Path]::ChangeExtension($sourcePath, '.exe')
    [System.IO.File]::WriteAllText($sourcePath, [string]$Case.Source + [Environment]::NewLine, $utf8)
    $compiled = $false
    $diagnostic = ''
    try { & $compilerPath -Source $sourcePath -Output $exePath; $compiled = $true }
    catch { $diagnostic = [string]$_.Exception.Message }
    if ($compiled) { throw 'Compiler accepted invalid Boolean/control-flow source.' }
    if ($diagnostic -notmatch '(?i)line\s+\d+,\s*column\s+\d+') { throw "Expected a source line/column diagnostic; received [$diagnostic]." }
    if (Test-Path -LiteralPath $exePath) { throw 'Rejected source left an executable behind.' }
}
function Get-TextSection {
    param([byte[]] $Bytes)
    if ($Bytes.Length -lt 0x100 -or $Bytes[0] -ne 0x4D -or $Bytes[1] -ne 0x5A) { throw 'Output is not an MZ image.' }
    $pe = [BitConverter]::ToInt32($Bytes, 0x3C)
    if ($pe -lt 0 -or ($pe + 24) -gt $Bytes.Length -or $Bytes[$pe] -ne 0x50 -or $Bytes[$pe + 1] -ne 0x45) { throw 'PE signature is invalid.' }
    $count = [BitConverter]::ToUInt16($Bytes, $pe + 6)
    $optionalSize = [BitConverter]::ToUInt16($Bytes, $pe + 20)
    $table = $pe + 24 + $optionalSize
    for ($i = 0; $i -lt $count; $i++) {
        $h = $table + ($i * 40)
        $name = [System.Text.Encoding]::ASCII.GetString($Bytes, $h, 8).Trim([char[]]@(0))
        if ($name -eq '.text') {
            $size = [BitConverter]::ToUInt32($Bytes, $h + 16)
            $offset = [BitConverter]::ToUInt32($Bytes, $h + 20)
            if ($size -le 0 -or ($offset + $size) -gt $Bytes.Length) { throw '.text section bounds are invalid.' }
            return [pscustomobject]@{ Offset = [int]$offset; Size = [int]$size }
        }
    }
    throw '.text section is missing.'
}
function Test-TextPattern {
    param([string] $ExePath, [byte[]] $Pattern)
    $bytes = [System.IO.File]::ReadAllBytes($ExePath)
    $section = Get-TextSection -Bytes $bytes
    if ($Pattern.Length -eq 0 -or $Pattern.Length -gt $section.Size) { return $false }
    for ($i = $section.Offset; $i -le ($section.Offset + $section.Size - $Pattern.Length); $i++) {
        $found = $true
        for ($j = 0; $j -lt $Pattern.Length; $j++) {
            if ($bytes[$i + $j] -ne $Pattern[$j]) { $found = $false; break }
        }
        if ($found) { return $true }
    }
    return $false
}
$positiveCases = @(
    [pscustomobject]@{
        Name = 'Boolean variables and assignment'
        File = 'BoolVariables.sharnou'
        Source = @'
let enabled = true;
print(enabled);
enabled = false;
print(enabled);
'@
        Expected = ('1' + [char]10 + '0')
    },
    [pscustomobject]@{
        Name = 'Boolean if and while conditions'
        File = 'BooleanBranches.sharnou'
        Source = @'
if (true) { print("true branch"); } else { print("wrong"); }
if (false) { print("wrong"); } else { print("false branch"); }
'@
        Expected = ('true branch' + [char]10 + 'false branch')
    },
    [pscustomobject]@{
        Name = 'Logical operator precedence and parentheses'
        File = 'LogicalPrecedence.sharnou'
        Source = @'
if (false || true && false) { print("wrong"); } else { print("and first"); }
if ((false || true) && true) { print("parentheses"); } else { print("wrong"); }
'@
        Expected = ('and first' + [char]10 + 'parentheses')
    },
    [pscustomobject]@{
        Name = 'AND short-circuits the right operand'
        File = 'ShortCircuitAndSkips.sharnou'
        Source = @'
if (false && (sh_log("AND-RHS") == 1)) { print("wrong"); } else { print("and skipped"); }
'@
        Expected = 'and skipped'
    },
    [pscustomobject]@{
        Name = 'OR short-circuits the right operand'
        File = 'ShortCircuitOrSkips.sharnou'
        Source = @'
if (true || (sh_log("OR-RHS") == 1)) { print("or skipped"); } else { print("wrong"); }
'@
        Expected = 'or skipped'
    },
    [pscustomobject]@{
        Name = 'AND evaluates the right operand when required'
        File = 'LogicalAndEvaluates.sharnou'
        Source = @'
if (true && (sh_log("AND-RUN") == 1)) { print("and evaluated"); } else { print("wrong"); }
'@
        Expected = ('AND-RUN' + [char]10 + 'and evaluated')
    },
    [pscustomobject]@{
        Name = 'OR evaluates the right operand when required'
        File = 'LogicalOrEvaluates.sharnou'
        Source = @'
if (false || (sh_log("OR-RUN") == 1)) { print("or evaluated"); } else { print("wrong"); }
'@
        Expected = ('OR-RUN' + [char]10 + 'or evaluated')
    },
    [pscustomobject]@{
        Name = 'Constant short-circuit avoids unreachable division'
        File = 'ConstantShortCircuit.sharnou'
        Source = @'
if (false && (1 / 0 == 0)) { print("wrong"); } else { print("and constant safe"); }
if (true || (1 / 0 == 0)) { print("or constant safe"); }
'@
        Expected = ('and constant safe' + [char]10 + 'or constant safe')
    },
    [pscustomobject]@{
        Name = 'Break exits the active loop'
        File = 'BreakExitsLoop.sharnou'
        Source = @'
let count = 0;
while (true) {
    count = count + 1;
    if (count == 4) { break; }
}
print(count);
'@
        Expected = '4'
    },
    [pscustomobject]@{
        Name = 'Continue skips the remaining loop body'
        File = 'ContinueSkipsIteration.sharnou'
        Source = @'
let count = 0;
let total = 0;
while (count < 5) {
    count = count + 1;
    if (count == 3) { continue; }
    total = total + count;
}
print(total);
'@
        Expected = '12'
    },
    [pscustomobject]@{
        Name = 'Nested break and continue target the innermost loop'
        File = 'NestedLoopControl.sharnou'
        Source = @'
let outer = 0;
let hits = 0;
while (outer < 3) {
    outer = outer + 1;
    let inner = 0;
    while (inner < 4) {
        inner = inner + 1;
        if (inner == 2) { continue; }
        if (inner == 4) { break; }
        hits = hits + 1;
    }
}
print(hits);
'@
        Expected = '6'
    },
    [pscustomobject]@{
        Name = 'Nested returns from both if branches'
        File = 'NestedReturnIfElse.sharnou'
        Source = @'
fn choose(value) {
    if (value > 0) { return 10; } else { return 20; }
}
print(choose(1));
print(choose(0));
'@
        Expected = ('10' + [char]10 + '20')
    },
    [pscustomobject]@{
        Name = 'Nested return inside a loop with a fallthrough return'
        File = 'NestedReturnFromLoop.sharnou'
        Source = @'
fn firstPositive(value) {
    while (value < 10) {
        if (value > 0) { return value; }
        value = value + 1;
    }
    return 0;
}
print(firstPositive(-2));
print(firstPositive(4));
'@
        Expected = ('1' + [char]10 + '4')
    },
    [pscustomobject]@{
        Name = 'Nested returns through nested if/else blocks'
        File = 'NestedReturnNestedIf.sharnou'
        Source = @'
fn choose(a, b) {
    if (a > 0) {
        if (b > 0) { return 11; } else { return 12; }
    } else {
        return 20;
    }
}
print(choose(1, 1));
print(choose(1, 0));
print(choose(0, 1));
'@
        Expected = ('11' + [char]10 + '12' + [char]10 + '20')
    }
)
$negativeCases = @(
    [pscustomobject]@{ Name='break is rejected outside a loop'; File='BreakOutsideLoop.sharnou'; Source='break;' },
    [pscustomobject]@{ Name='continue is rejected outside a loop'; File='ContinueOutsideLoop.sharnou'; Source='continue;' },
    [pscustomobject]@{ Name='logical NOT rejects integer operands'; File='NotInteger.sharnou'; Source='let value = !1;' },
    [pscustomobject]@{ Name='logical AND rejects non-Boolean operands'; File='AndInteger.sharnou'; Source='if (true && 1) { print(1); }' },
    [pscustomobject]@{ Name='logical OR rejects non-Boolean operands'; File='OrString.sharnou'; Source='if (false || "text") { print(1); }' },
    [pscustomobject]@{ Name='Boolean values cannot be used in arithmetic'; File='BooleanArithmetic.sharnou'; Source='let value = true + 1;' },
    [pscustomobject]@{ Name='assignment cannot change integer to Boolean'; File='BooleanAssignmentMismatch.sharnou'; Source='let value = 1; value = true;' },
    [pscustomobject]@{ Name='Boolean and integer comparisons are rejected'; File='BooleanIntegerComparison.sharnou'; Source='if (true == 1) { print(1); }' },
    [pscustomobject]@{ Name='Boolean relational comparisons are rejected'; File='BooleanRelationalComparison.sharnou'; Source='if (true < false) { print(1); }' },
    [pscustomobject]@{ Name='function without a return path is rejected'; File='FunctionMissingReturn.sharnou'; Source='fn missing(value) { let other = value + 1; } print(missing(1));' },
    [pscustomobject]@{ Name='one-sided nested return without fallback is rejected'; File='NestedReturnMissingElse.sharnou'; Source='fn missing(value) { if (value > 0) { return 1; } } print(missing(1));' },
    [pscustomobject]@{ Name='return is rejected outside a function'; File='ReturnOutsideFunction.sharnou'; Source='return 1;' },
    [pscustomobject]@{ Name='Boolean literals are reserved keywords'; File='ReservedBooleanKeyword.sharnou'; Source='let true = 1;' }
)
foreach ($case in $positiveCases) {
    $passed = $true; $detail = ''
    try { Invoke-PositiveCase -Case $case } catch { $passed = $false; $detail = [string]$_.Exception.Message }
    Record-Stage7BResult -Name $case.Name -Passed $passed -Detail $detail
}
foreach ($case in $negativeCases) {
    $passed = $true; $detail = ''
    try { Invoke-NegativeCase -Case $case } catch { $passed = $false; $detail = [string]$_.Exception.Message }
    Record-Stage7BResult -Name $case.Name -Passed $passed -Detail $detail
}
$machineChecks = @(
    [pscustomobject]@{ Name='AND emits a conditional short-circuit branch'; File='ShortCircuitAndSkips.exe'; Pattern=[byte[]]@(0x0F,0x84) },
    [pscustomobject]@{ Name='OR emits a conditional short-circuit branch'; File='ShortCircuitOrSkips.exe'; Pattern=[byte[]]@(0x0F,0x85) },
    [pscustomobject]@{ Name='break/continue emit native relative jumps'; File='NestedLoopControl.exe'; Pattern=[byte[]]@(0xE9) },
    [pscustomobject]@{ Name='nested returns emit native RET instructions'; File='NestedReturnNestedIf.exe'; Pattern=[byte[]]@(0xC3) }
)
foreach ($check in $machineChecks) {
    $passed = $true; $detail = ''
    try {
        $exePath = Join-Path $buildRoot $check.File
        if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) { throw "Required executable is missing: $exePath" }
        if (-not (Test-TextPattern -ExePath $exePath -Pattern $check.Pattern)) { throw 'Expected instruction sequence was not found in .text.' }
    } catch { $passed = $false; $detail = [string]$_.Exception.Message }
    Record-Stage7BResult -Name $check.Name -Passed $passed -Detail $detail
}
$total = $positiveCases.Count + $negativeCases.Count + $machineChecks.Count
Write-Host ("Stage 7B tests: {0} passed, {1} failed, {2} total." -f $script:PassedCount, $script:FailedCount, $total)
if ($script:PassedCount -ne $total -or $script:FailedCount -ne 0) { throw 'Stage 7B regression suite failed.' }
Write-Host 'Stage 7B result: PASS' -ForegroundColor Green
