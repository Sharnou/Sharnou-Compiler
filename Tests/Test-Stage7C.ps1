[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$compilerPath = Join-Path $repoRoot 'Stage0\SharnouCompiler.ps1'
$verifierPath = Join-Path $repoRoot 'Tools\SharnouPEVerify.ps1'
$buildRoot = Join-Path $repoRoot 'Build\Stage7CTests'
if (-not (Test-Path -LiteralPath $compilerPath -PathType Leaf)) { throw 'Stage 7C compiler is missing.' }
if (-not (Test-Path -LiteralPath $verifierPath -PathType Leaf)) { throw 'Stage 7C PE verifier is missing.' }
if (Test-Path -LiteralPath $buildRoot) { Remove-Item -LiteralPath $buildRoot -Recurse -Force }
$null = New-Item -ItemType Directory -Path $buildRoot -Force
$utf8 = New-Object System.Text.UTF8Encoding($false)
$script:PassedCount = 0
$script:FailedCount = 0

function Record-Stage7CResult {
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
    $global:LASTEXITCODE = 0
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
    if ($compiled) { throw 'Compiler accepted an invalid primitive type declaration or assignment.' }
    if ($diagnostic -notmatch '(?i)line\s+\d+,\s*column\s+\d+') { throw "Expected a source line/column diagnostic; received [$diagnostic]." }
    if (Test-Path -LiteralPath $exePath) { throw 'Rejected source left an executable behind.' }
}

$positiveCases = @(
    [pscustomobject]@{
        Name = 'Explicit i32, bool and string declarations'
        File = 'ExplicitPrimitiveLocals.sharnou'
        Source = @'
let count: i32 = 2;
let ready: bool = true;
let label: string = "Sharnou";
print(count);
print(ready);
print(label);
'@
        Expected = ('2' + [char]10 + '1' + [char]10 + 'Sharnou')
    },
    [pscustomobject]@{
        Name = 'Explicit primitive assignments preserve declared types'
        File = 'ExplicitPrimitiveAssignments.sharnou'
        Source = @'
let count: i32 = 0;
let enabled: bool = true;
let label: string = "start";
while (enabled) {
    count = count + 1;
    enabled = false;
}
label = "done";
if (enabled) { print("wrong"); } else { print(label); }
print(count);
'@
        Expected = ('done' + [char]10 + '1')
    },
    [pscustomobject]@{
        Name = 'Explicit primitive declarations in nested scopes'
        File = 'ExplicitPrimitiveScope.sharnou'
        Source = @'
if (true) {
    let localCount: i32 = 7;
    let localReady: bool = false;
    print(localCount);
    print(localReady);
}
'@
        Expected = ('7' + [char]10 + '0')
    },
    [pscustomobject]@{
        Name = 'Explicit Boolean type composes with logical operators'
        File = 'ExplicitBooleanLogic.sharnou'
        Source = @'
let enabled: bool = false;
if (!enabled && (true || false)) { print("typed boolean"); }
'@
        Expected = 'typed boolean'
    }
)

$negativeCases = @(
    [pscustomobject]@{ Name = 'i32 rejects Boolean initializer'; File = 'I32RejectsBoolean.sharnou'; Source = 'let value: i32 = true;' },
    [pscustomobject]@{ Name = 'bool rejects integer initializer'; File = 'BoolRejectsInteger.sharnou'; Source = 'let value: bool = 1;' },
    [pscustomobject]@{ Name = 'string rejects integer initializer'; File = 'StringRejectsInteger.sharnou'; Source = 'let value: string = 1;' },
    [pscustomobject]@{ Name = 'unknown primitive type is rejected'; File = 'UnknownPrimitiveType.sharnou'; Source = 'let value: f64 = 1;' },
    [pscustomobject]@{ Name = 'missing primitive type name is rejected'; File = 'MissingPrimitiveType.sharnou'; Source = 'let value: = 1;' },
    [pscustomobject]@{ Name = 'assignment cannot violate an explicit Boolean type'; File = 'ExplicitTypeAssignmentMismatch.sharnou'; Source = ('let enabled: bool = true;' + [Environment]::NewLine + 'enabled = 1;') },
    [pscustomobject]@{ Name = 'explicit declaration still requires an initializer'; File = 'ExplicitTypeMissingInitializer.sharnou'; Source = 'let value: i32;' }
)

Write-Host '=== Stage 7C.1 explicit primitive local type tests ==='
foreach ($case in $positiveCases) {
    try { Invoke-PositiveCase -Case $case; Record-Stage7CResult -Name $case.Name -Passed $true }
    catch { $global:LASTEXITCODE = 0; Record-Stage7CResult -Name $case.Name -Passed $false -Detail $_.Exception.Message }
}
foreach ($case in $negativeCases) {
    try { Invoke-NegativeCase -Case $case; Record-Stage7CResult -Name $case.Name -Passed $true }
    catch { $global:LASTEXITCODE = 0; Record-Stage7CResult -Name $case.Name -Passed $false -Detail $_.Exception.Message }
}
Write-Host ''
Write-Host ("Stage 7C.1 tests: {0} passed, {1} failed, {2} total." -f $script:PassedCount, $script:FailedCount, ($script:PassedCount + $script:FailedCount))
if ($script:FailedCount -ne 0) { throw 'One or more Stage 7C.1 tests failed.' }
Write-Host 'Stage 7C.1 result: PASS' -ForegroundColor Green
