[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$compiler = Join-Path $root 'Stage0\SharnouCompiler.ps1'
$verifier = Join-Path $root 'Tools\SharnouPEVerify.ps1'
$exampleRoot = Join-Path $root 'Examples\ControlFlow'
$buildRoot = Join-Path $root 'Build\Stage7A'
$examples = @(
    'IfElse.sharnou',
    'WhileLoop.sharnou',
    'Comparisons.sharnou',
    'NestedControlFlow.sharnou',
    'FunctionControlFlow.sharnou',
    'SignedComparisonEdges.sharnou',
    'WhileFalse.sharnou',
    'ComparisonPrecedence.sharnou'
)
try {
    foreach ($required in @($compiler, $verifier)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required compiler tool is missing: $required" }
    }
    New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
    foreach ($file in $examples) {
        $source = Join-Path $exampleRoot $file
        $output = Join-Path $buildRoot ([IO.Path]::GetFileNameWithoutExtension($file) + '.exe')
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Example is missing: $source" }
        if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output -Force }
        Write-Host "Building $file ..."
        & $compiler -Source $source -Output $output
        if (-not (Test-Path -LiteralPath $output -PathType Leaf)) { throw "Compiler did not produce $output" }
        & $verifier -Path $output
        if ($LASTEXITCODE -ne 0) { throw "PE verification failed for $output." }
        $hash = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
        Write-Host "Build result: PASS - $output - SHA256 $hash" -ForegroundColor Green
    }
    Write-Host 'Build result: PASS' -ForegroundColor Green
} catch {
    Write-Host "Build result: FAIL - $($_.Exception.Message)" -ForegroundColor Red
    throw
}
