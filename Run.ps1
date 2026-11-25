[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$buildRoot = Join-Path $root 'Build\Stage7A'
$nl = [string][char]10
$cases = @(
    [pscustomobject]@{ Name = 'IfElse'; Expected = ('greater' + $nl + 'equal' + $nl + 'not equal branch') },
    [pscustomobject]@{ Name = 'WhileLoop'; Expected = ('10' + $nl + '5') },
    [pscustomobject]@{ Name = 'Comparisons'; Expected = ('1' + $nl + '0' + $nl + '1' + $nl + '1' + $nl + '1' + $nl + '1') },
    [pscustomobject]@{ Name = 'NestedControlFlow'; Expected = ('15' + $nl + 'bounded') },
    [pscustomobject]@{ Name = 'FunctionControlFlow'; Expected = ('10' + $nl + '7') },
    [pscustomobject]@{ Name = 'SignedComparisonEdges'; Expected = ('signed less' + $nl + 'minimum inclusive' + $nl + 'signed greater' + $nl + 'maximum inclusive' + $nl + 'not equal') },
    [pscustomobject]@{ Name = 'BranchConditionCodes'; Expected = ('lt' + $nl + 'gt-false' + $nl + 'le' + $nl + 'ge' + $nl + 'eq' + $nl + 'ne-false' + $nl + 'lt-false-edge' + $nl + 'gt-false-edge' + $nl + 'le-false-edge' + $nl + 'ge-false-edge' + $nl + 'eq-false-edge' + $nl + 'ne-true-edge' + $nl + 'gt-true-edge') },
    [pscustomobject]@{ Name = 'WhileFalse'; Expected = 'zero iterations' },
    [pscustomobject]@{ Name = 'ComparisonPrecedence'; Expected = 'arithmetic before comparison' }
)
try {
    foreach ($case in $cases) {
        $exe = Join-Path $buildRoot ($case.Name + '.exe')
        if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "Executable is missing: $exe. Run .\Build.ps1 first." }
        $lines = @(& $exe 2>&1)
        $exitCode = $LASTEXITCODE
        $actual = (($lines | ForEach-Object { [string]$_ }) -join $nl).TrimEnd([char[]]@([char]13, [char]10))
        if ($exitCode -ne 0) { throw "$($case.Name) exited with code $exitCode. Output=[$actual]." }
        if (-not [string]::Equals($actual, $case.Expected, [StringComparison]::Ordinal)) {
            throw "$($case.Name) output mismatch. Expected=[$($case.Expected)] Actual=[$actual]."
        }
        Write-Host "PASS: $($case.Name) (exit 0)" -ForegroundColor Green
    }
    Write-Host 'Run result: PASS' -ForegroundColor Green
} catch {
    Write-Host "Run result: FAIL - $($_.Exception.Message)" -ForegroundColor Red
    throw
}
