[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$compilerPath = Join-Path $repoRoot 'Stage0\SharnouCompiler.ps1'
$verifierPath = Join-Path $repoRoot 'Tools\SharnouPEVerify.ps1'
$fixtureRoot = Join-Path $PSScriptRoot 'Stage5\Positive'
$buildRoot = Join-Path $repoRoot 'Build\Stage5CollectionImport'
$nl = [string][char]10
$expected = '10' + $nl + '30'
$cases = @(
    [pscustomobject]@{ Name = 'canonical StdLib import path'; File = 'Vec4Collection.sharnou' },
    [pscustomobject]@{ Name = 'legacy Tests\StdLib import path'; File = 'Vec4CollectionLegacyPath.sharnou' }
)

try {
    foreach ($required in @($compilerPath, $verifierPath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Required tool is missing: $required"
        }
    }
    New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null

    $passed = 0
    $failed = 0
    Write-Host '=== Milestone 5 collection-module import regression ==='
    foreach ($case in $cases) {
        $source = Join-Path $fixtureRoot $case.File
        $output = Join-Path $buildRoot ([IO.Path]::GetFileNameWithoutExtension($case.File) + '.exe')
        try {
            if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
                throw "Collection fixture is missing: $source"
            }
            if (Test-Path -LiteralPath $output) {
                Remove-Item -LiteralPath $output -Force
            }
            & $compilerPath -Source $source -Output $output
            if (-not (Test-Path -LiteralPath $output -PathType Leaf)) {
                throw 'Compiler did not produce an executable.'
            }
            & $verifierPath -Path $output
            $lines = @(& $output 2>&1)
            $exitCode = $LASTEXITCODE
            $actual = (($lines | ForEach-Object { [string]$_ }) -join $nl).TrimEnd([char[]]@([char]13, [char]10))
            if ($exitCode -ne 0) {
                throw "Executable returned exit code $exitCode."
            }
            if (-not [string]::Equals($actual, $expected, [StringComparison]::Ordinal)) {
                throw "Output mismatch. Expected [$expected], received [$actual]."
            }
            $passed++
            Write-Host "PASS: $($case.Name)" -ForegroundColor Green
        }
        catch {
            $failed++
            Write-Host "FAIL: $($case.Name) - $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host ("Stage 5 collection import tests: {0} passed, {1} failed, {2} total." -f $passed, $failed, ($passed + $failed))
    if ($failed -ne 0) {
        throw 'One or more Stage 5 collection import tests failed.'
    }
    Write-Host 'Stage 5 collection import result: PASS' -ForegroundColor Green
}
catch {
    Write-Host "Stage 5 collection import result: FAIL - $($_.Exception.Message)" -ForegroundColor Red
    throw
}
