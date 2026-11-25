[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$compilerPath = Join-Path $repoRoot 'Stage0\SharnouCompiler.ps1'
$verifierPath = Join-Path $repoRoot 'Tools\SharnouPEVerify.ps1'
$fixturePath = Join-Path $PSScriptRoot 'RuntimeABI\RuntimeABICalls.sharnou'
$buildRoot = Join-Path $repoRoot 'Build\RuntimeABI'
$outputPath = Join-Path $buildRoot 'RuntimeABICalls.exe'
$nl = [string][char]10
$expected = @('204', '120', '54321', '654321', '10', '1', '0', '32', '65', '1', '16', '102', '1', '1', '1') -join $nl

function Test-ByteSequence {
    param([byte[]] $Haystack, [byte[]] $Needle)
    if ($Needle.Length -eq 0 -or $Needle.Length -gt $Haystack.Length) { return $false }
    for ($i = 0; $i -le ($Haystack.Length - $Needle.Length); $i++) {
        $match = $true
        for ($j = 0; $j -lt $Needle.Length; $j++) {
            if ($Haystack[$i + $j] -ne $Needle[$j]) { $match = $false; break }
        }
        if ($match) { return $true }
    }
    return $false
}
function Read-U16At {
    param([byte[]] $Bytes, [int] $Offset)
    return [BitConverter]::ToUInt16($Bytes, $Offset)
}
function Read-U32At {
    param([byte[]] $Bytes, [int] $Offset)
    return [BitConverter]::ToUInt32($Bytes, $Offset)
}

try {
    foreach ($required in @($compilerPath, $verifierPath, $fixturePath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required ABI test input is missing: $required" }
    }
    New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
    if (Test-Path -LiteralPath $outputPath) { Remove-Item -LiteralPath $outputPath -Force }
    & $compilerPath -Source $fixturePath -Output $outputPath
    if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) { throw 'Compiler did not produce the runtime ABI fixture.' }
    & $verifierPath -Path $outputPath

    $lines = @(& $outputPath 2>&1)
    $exitCode = $LASTEXITCODE
    $actual = (($lines | ForEach-Object { [string]$_ }) -join $nl).TrimEnd([char[]]@([char]13, [char]10))
    if ($exitCode -ne 0) { throw "Runtime ABI fixture exited with code $exitCode. Output=[$actual]." }
    if (-not [string]::Equals($actual, $expected, [StringComparison]::Ordinal)) {
        throw "Runtime ABI output mismatch. Expected=[$expected] Actual=[$actual]."
    }
    Write-Host 'PASS: runtime argument-value checks for 4, 5, 6 and 8 integer arguments' -ForegroundColor Green
    Write-Host 'PASS: nested higher-arity Sharnou function call and argument ordering' -ForegroundColor Green
    Write-Host 'PASS: RSI/RDI-using string and memory intrinsics preserve their runtime results' -ForegroundColor Green
    Write-Host 'PASS: hidden-window and thread/synchronization Win32 API probes' -ForegroundColor Green

    $image = [IO.File]::ReadAllBytes($outputPath)
    $pe = [int](Read-U32At -Bytes $image -Offset 0x3C)
    $sectionCount = [int](Read-U16At -Bytes $image -Offset ($pe + 6))
    $optional = $pe + 24
    $optionalSize = [int](Read-U16At -Bytes $image -Offset ($pe + 20))
    $sectionTable = $optional + $optionalSize
    $text = $null
    for ($i = 0; $i -lt $sectionCount; $i++) {
        $header = $sectionTable + ($i * 40)
        $name = [Text.Encoding]::ASCII.GetString($image, $header, 8).Trim([char[]]@(0))
        if ($name -eq '.text') {
            $text = [byte[]]::new([int](Read-U32At -Bytes $image -Offset ($header + 16)))
            [Buffer]::BlockCopy($image, [int](Read-U32At -Bytes $image -Offset ($header + 20)), $text, 0, $text.Length)
            break
        }
    }
    if ($null -eq $text) { throw 'Generated PE has no .text section.' }

    $checks = @(
        [pscustomobject]@{ Name = '64-byte aligned outgoing frame for 8-argument call'; Bytes = [byte[]]@(0x48, 0x81, 0xEC, 0x40, 0x00, 0x00, 0x00) },
        [pscustomobject]@{ Name = '96-byte outgoing frame for 12-argument Windows API'; Bytes = [byte[]]@(0x48, 0x81, 0xEC, 0x60, 0x00, 0x00, 0x00) },
        [pscustomobject]@{ Name = '96-byte Windows API call-frame restoration'; Bytes = [byte[]]@(0x48, 0x81, 0xC4, 0x60, 0x00, 0x00, 0x00) },
        [pscustomobject]@{ Name = '64-byte outgoing frame restoration'; Bytes = [byte[]]@(0x48, 0x81, 0xC4, 0x40, 0x00, 0x00, 0x00) },
        [pscustomobject]@{ Name = 'first incoming stack argument at RBP+0x30'; Bytes = [byte[]]@(0x8B, 0x85, 0x30, 0x00, 0x00, 0x00) },
        [pscustomobject]@{ Name = 'fourth incoming stack argument at RBP+0x48'; Bytes = [byte[]]@(0x8B, 0x85, 0x48, 0x00, 0x00, 0x00) },
        [pscustomobject]@{ Name = 'outgoing stack argument slot at RSP+0x20'; Bytes = [byte[]]@(0x48, 0x89, 0x44, 0x24, 0x20) },
        [pscustomobject]@{ Name = 'runtime RBX sentinel load'; Bytes = [byte[]]@(0x48, 0xBB, 0x44, 0x33, 0x22, 0x11) },
        [pscustomobject]@{ Name = 'runtime R12 sentinel load'; Bytes = [byte[]]@(0x49, 0xBC, 0x77, 0x66, 0x55, 0x44) },
        [pscustomobject]@{ Name = 'nonvolatile RSI save'; Bytes = [byte[]]@(0x48, 0x89, 0xB5) },
        [pscustomobject]@{ Name = 'nonvolatile RSI restore'; Bytes = [byte[]]@(0x48, 0x8B, 0xB5) },
        [pscustomobject]@{ Name = 'nonvolatile RDI save'; Bytes = [byte[]]@(0x48, 0x89, 0xBD) },
        [pscustomobject]@{ Name = 'nonvolatile RDI restore'; Bytes = [byte[]]@(0x48, 0x8B, 0xBD) },
        [pscustomobject]@{ Name = 'REP CMPSB string comparison path'; Bytes = [byte[]]@(0xF3, 0xA6) }
    )
    foreach ($check in $checks) {
        if (-not (Test-ByteSequence -Haystack $text -Needle $check.Bytes)) { throw "Native ABI encoding check failed: $($check.Name)." }
        Write-Host "PASS: $($check.Name)" -ForegroundColor Green
    }
    Write-Host 'Runtime ABI result: PASS' -ForegroundColor Green
}
catch {
    Write-Host "Runtime ABI result: FAIL - $($_.Exception.Message)" -ForegroundColor Red
    throw
}
