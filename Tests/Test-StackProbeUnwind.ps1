[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$compilerPath = Join-Path $repoRoot 'Stage0\SharnouCompiler.ps1'
$verifierPath = Join-Path $repoRoot 'Tools\SharnouPEVerify.ps1'
$buildRoot = Join-Path $repoRoot 'Build\StackProbeUnwind'
$sourcePath = Join-Path $buildRoot 'StackProbeMultiPage.sharnou'
$outputPath = Join-Path $buildRoot 'StackProbeMultiPage.exe'
$encoding = [Text.UTF8Encoding]::new($false)
$nl = [string][char]10

function Read-U16At {
    param([byte[]] $Bytes, [int] $Offset)
    return [BitConverter]::ToUInt16($Bytes, $Offset)
}
function Read-U32At {
    param([byte[]] $Bytes, [int] $Offset)
    return [BitConverter]::ToUInt32($Bytes, $Offset)
}
function Find-Bytes {
    param([byte[]] $Bytes, [int] $Start, [int] $Length, [byte[]] $Pattern)
    if ($Pattern.Length -eq 0 -or $Length -lt $Pattern.Length) { return -1 }
    $last = $Start + $Length - $Pattern.Length
    for ($i = $Start; $i -le $last; $i++) {
        $match = $true
        for ($j = 0; $j -lt $Pattern.Length; $j++) {
            if ($Bytes[$i + $j] -ne $Pattern[$j]) { $match = $false; break }
        }
        if ($match) { return $i }
    }
    return -1
}
function Assert-VerifierRejects {
    param([string] $Path, [string] $Name)
    $rejected = $false
    try {
        & $verifierPath -Path $Path | Out-Null
    } catch {
        $rejected = $true
    }
    if (-not $rejected) { throw "PE verifier accepted corrupted image: $Name" }
    Write-Host "PASS: verifier rejects $Name" -ForegroundColor Green
}

try {
    foreach ($required in @($compilerPath, $verifierPath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required tool is missing: $required" }
    }
    New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null

    # 17,000 locals force a >512 KiB frame (UWOP_ALLOC_LARGE, OpInfo=1)
    # while the user function retains a smaller scaled allocation record.
    $source = [Text.StringBuilder]::new()
    $null = $source.AppendLine('fn increment(value) {')
    $null = $source.AppendLine('    let adjusted = value + 1;')
    $null = $source.AppendLine('    return adjusted;')
    $null = $source.AppendLine('}')
    $localCount = 17000
    for ($index = 0; $index -lt $localCount; $index++) {
        $null = $source.AppendLine(('let value{0:D5} = {0};' -f $index))
    }
    $lastName = 'value{0:D5}' -f ($localCount - 1)
    $null = $source.AppendLine(("print({0});" -f $lastName))
    $null = $source.AppendLine(("print(increment({0}));" -f $lastName))
    [IO.File]::WriteAllText($sourcePath, $source.ToString(), $encoding)

    if (Test-Path -LiteralPath $outputPath) { Remove-Item -LiteralPath $outputPath -Force }
    & $compilerPath -Source $sourcePath -Output $outputPath
    if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) { throw 'Compiler did not produce the multi-page stack-probe executable.' }
    & $verifierPath -Path $outputPath
    Write-Host 'PASS: generated multi-page PE passed the strict structural verifier' -ForegroundColor Green

    $lines = @(& $outputPath 2>&1)
    $exitCode = $LASTEXITCODE
    $actual = (($lines | ForEach-Object { [string]$_ }) -join $nl).TrimEnd([char[]]@([char]13, [char]10))
    $expected = ('{0}' -f ($localCount - 1)) + $nl + ('{0}' -f $localCount)
    if ($exitCode -ne 0) { throw "Multi-page stack-probe executable exited with code $exitCode. Output=[$actual]." }
    if (-not [string]::Equals($actual, $expected, [StringComparison]::Ordinal)) {
        throw "Multi-page stack-probe output mismatch. Expected=[$expected] Actual=[$actual]."
    }
    Write-Host 'PASS: multi-page stack probing executes and preserves function arguments' -ForegroundColor Green

    $image = [IO.File]::ReadAllBytes($outputPath)
    $pe = [int](Read-U32At -Bytes $image -Offset 0x3C)
    $sectionCount = [int](Read-U16At -Bytes $image -Offset ($pe + 6))
    if ($sectionCount -ne 6) { throw "Expected six PE sections, found $sectionCount." }
    $optional = $pe + 24
    $optionalSize = [int](Read-U16At -Bytes $image -Offset ($pe + 20))
    $exceptionRva = [UInt32](Read-U32At -Bytes $image -Offset ($optional + 136))
    $exceptionSize = [UInt32](Read-U32At -Bytes $image -Offset ($optional + 140))
    if ($exceptionRva -eq 0 -or $exceptionSize -ne 24 -or ($exceptionSize % 12) -ne 0) {
        throw "Expected two 12-byte RUNTIME_FUNCTION records; RVA=$exceptionRva size=$exceptionSize."
    }
    $sectionTable = $optional + $optionalSize
    $sections = @{}
    for ($i = 0; $i -lt $sectionCount; $i++) {
        $header = $sectionTable + ($i * 40)
        $name = [Text.Encoding]::ASCII.GetString($image, $header, 8).Trim([char[]]@(0))
        $sections[$name] = [pscustomobject]@{
            VirtualSize = [UInt32](Read-U32At -Bytes $image -Offset ($header + 8))
            Rva = [UInt32](Read-U32At -Bytes $image -Offset ($header + 12))
            RawSize = [UInt32](Read-U32At -Bytes $image -Offset ($header + 16))
            RawPointer = [UInt32](Read-U32At -Bytes $image -Offset ($header + 20))
        }
    }
    foreach ($name in @('.text', '.pdata', '.xdata')) {
        if (-not $sections.ContainsKey($name)) { throw "Required PE section is missing: $name" }
    }
    if ($exceptionRva -ne $sections['.pdata'].Rva -or $exceptionSize -ne $sections['.pdata'].VirtualSize) {
        throw 'Exception directory does not cover the complete .pdata table.'
    }
    $pdataOffset = [int]($sections['.pdata'].RawPointer + ($exceptionRva - $sections['.pdata'].Rva))
    $frameSizes = [System.Collections.Generic.List[int]]::new()
    $unwindOffsets = [System.Collections.Generic.List[int]]::new()
    for ($i = 0; $i -lt 2; $i++) {
        $entry = $pdataOffset + ($i * 12)
        $begin = [UInt32](Read-U32At -Bytes $image -Offset $entry)
        $end = [UInt32](Read-U32At -Bytes $image -Offset ($entry + 4))
        $unwindRva = [UInt32](Read-U32At -Bytes $image -Offset ($entry + 8))
        if ($begin -lt $sections['.text'].Rva -or $end -le $begin -or $end -gt ($sections['.text'].Rva + $sections['.text'].VirtualSize)) {
            throw "RUNTIME_FUNCTION $i has an invalid code range."
        }
        if ($unwindRva -lt $sections['.xdata'].Rva -or $unwindRva -ge ($sections['.xdata'].Rva + $sections['.xdata'].VirtualSize)) {
            throw "RUNTIME_FUNCTION $i points outside .xdata."
        }
        $unwindOffset = [int]($sections['.xdata'].RawPointer + ($unwindRva - $sections['.xdata'].Rva))
        $unwindOffsets.Add($unwindOffset)
        if ($image[$unwindOffset] -ne 1 -or $image[$unwindOffset + 1] -ne 21 -or $image[$unwindOffset + 3] -ne 0x05) {
            throw "RUNTIME_FUNCTION $i has an unexpected UNWIND_INFO header."
        }
        $opInfo = [int]($image[$unwindOffset + 5] -shr 4)
        if ($opInfo -eq 0) {
            $frameSize = [int](Read-U16At -Bytes $image -Offset ($unwindOffset + 6)) * 8
        } elseif ($opInfo -eq 1) {
            $frameSize = [int](Read-U32At -Bytes $image -Offset ($unwindOffset + 6))
        } else {
            throw "RUNTIME_FUNCTION $i has an invalid UWOP_ALLOC_LARGE OpInfo."
        }
        $frameSizes.Add($frameSize)
    }
    if (-not ($frameSizes | Where-Object { $_ -gt 0x7FFF8 })) { throw 'The large-frame 32-bit UWOP_ALLOC_LARGE form was not exercised.' }
    if (-not ($frameSizes | Where-Object { $_ -le 0x7FFF8 -and $_ -ge 0x1000 })) { throw 'The scaled UWOP_ALLOC_LARGE form was not exercised.' }

    $textOffset = [int]($sections['.text'].RawPointer)
    $legalEpilogue = [byte[]]@(0x48, 0x8D, 0x65, 0x00, 0x5D, 0xC3)
    if ((Find-Bytes -Bytes $image -Start $textOffset -Length ([int]$sections['.text'].RawSize) -Pattern $legalEpilogue) -lt 0) {
        throw 'A legal LEA RSP,[RBP+0]; POP RBP; RET epilogue was not found.'
    }
    Write-Host 'PASS: .pdata/.xdata contain entry and user-function unwind records (both ALLOC_LARGE encodings)' -ForegroundColor Green
    Write-Host 'PASS: generated user-function epilogue follows the Windows x64 unwind pattern' -ForegroundColor Green

    $badDirectoryPath = Join-Path $buildRoot 'CorruptExceptionDirectory.exe'
    $badUnwindPath = Join-Path $buildRoot 'CorruptUnwindInfo.exe'
    try {
        $badDirectory = $image.Clone()
        [BitConverter]::GetBytes([UInt32]11).CopyTo($badDirectory, $optional + 140)
        [IO.File]::WriteAllBytes($badDirectoryPath, $badDirectory)
        Assert-VerifierRejects -Path $badDirectoryPath -Name 'truncated exception directory'

        $badUnwind = $image.Clone()
        $badUnwind[$unwindOffsets[0]] = 0x02
        [IO.File]::WriteAllBytes($badUnwindPath, $badUnwind)
        Assert-VerifierRejects -Path $badUnwindPath -Name 'unsupported unwind-info version'
    } finally {
        foreach ($temporary in @($badDirectoryPath, $badUnwindPath)) {
            if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
        }
    }

    Write-Host 'Stack probe and unwind tests: 6 passed, 0 failed, 6 total.' -ForegroundColor Green
    Write-Host 'Stack probe and unwind result: PASS' -ForegroundColor Green
}
catch {
    Write-Host "Stack probe and unwind result: FAIL - $($_.Exception.Message)" -ForegroundColor Red
    throw
}
