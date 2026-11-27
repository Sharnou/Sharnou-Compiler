[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$compiler = Join-Path $repoRoot 'Stage0\SharnouCompiler.ps1'
$verifier = Join-Path $repoRoot 'Tools\SharnouPEVerify.ps1'
$relocationTools = Join-Path $repoRoot 'Tools\SharnouPERelocations.ps1'
foreach ($required in @($compiler, $verifier, $relocationTools)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required callback ABI tool is missing: $required"
    }
}
. $relocationTools

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("Sharnou-R51B-Callback-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$source = Join-Path $testRoot 'CallbackProbe.sharnou'
$output = Join-Path $testRoot 'CallbackProbe.exe'
$encoding = [Text.ASCIIEncoding]::new()

function Convert-RvaToRawOffset {
    param([UInt32] $Rva, [object[]] $Sections)
    foreach ($section in $Sections) {
        if ($Rva -ge [UInt32]$section.Rva -and
            ([UInt64]$Rva + 8) -le ([UInt64]$section.Rva + [UInt64]$section.RawSize)) {
            return [int]([UInt64]$section.RawPointer + ([UInt64]$Rva - [UInt64]$section.Rva))
        }
    }
    throw ("RVA 0x{0:X8} is not backed by raw section data." -f $Rva)
}

try {
    [IO.File]::WriteAllText($source, "let callbackProbeResult = sh_win64_callback_abi_probe();" + [Environment]::NewLine, $encoding)
    & $compiler -Source $source -Output $output -EnableWin64CallbackTests
    if (-not (Test-Path -LiteralPath $output -PathType Leaf)) {
        throw 'Sharnou compiler did not produce the Win64 callback ABI probe executable.'
    }

    & $verifier -Path $output
    $image = [IO.File]::ReadAllBytes($output)
    if ($image.Length -lt 0x400 -or $image[0] -ne 0x4D -or $image[1] -ne 0x5A) {
        throw 'Callback probe output is not a PE image.'
    }
    $pe = [BitConverter]::ToInt32($image, 0x3C)
    if ($pe -lt 0 -or ($pe + 24) -gt $image.Length) { throw 'PE header offset is invalid.' }
    if ([BitConverter]::ToUInt16($image, $pe + 4) -ne 0x8664 -or
        [BitConverter]::ToUInt16($image, $pe + 24) -ne 0x020B) {
        throw 'Callback probe is not an AMD64 PE32+ image.'
    }

    $optional = $pe + 24
    $imageBase = [UInt64][BitConverter]::ToUInt64($image, $optional + 24)
    $imageSize = [UInt32][BitConverter]::ToUInt32($image, $optional + 56)
    $entryRva = [UInt32][BitConverter]::ToUInt32($image, $optional + 16)
    $relocRva = [UInt32][BitConverter]::ToUInt32($image, $optional + 152)
    $relocSize = [UInt32][BitConverter]::ToUInt32($image, $optional + 156)
    $sectionCount = [BitConverter]::ToUInt16($image, $pe + 6)
    $optionalSize = [BitConverter]::ToUInt16($image, $pe + 20)
    $sectionTable = $optional + $optionalSize
    $sections = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $sectionCount; $i++) {
        $header = $sectionTable + ($i * 40)
        $sections.Add([pscustomobject]@{
            Name = [Text.Encoding]::ASCII.GetString($image, $header, 8).Trim([char[]]@(0))
            VirtualSize = [UInt32][BitConverter]::ToUInt32($image, $header + 8)
            Rva = [UInt32][BitConverter]::ToUInt32($image, $header + 12)
            RawSize = [UInt32][BitConverter]::ToUInt32($image, $header + 16)
            RawPointer = [UInt32][BitConverter]::ToUInt32($image, $header + 20)
        })
    }

    $rdata = $sections | Where-Object Name -eq '.rdata' | Select-Object -First 1
    $text = $sections | Where-Object Name -eq '.text' | Select-Object -First 1
    $reloc = $sections | Where-Object Name -eq '.reloc' | Select-Object -First 1
    if ($null -eq $rdata -or $null -eq $text -or $null -eq $reloc) {
        throw 'Callback probe PE is missing required sections.'
    }
    if ($relocRva -ne $reloc.Rva -or $relocSize -lt 12 -or $relocSize -gt $reloc.VirtualSize) {
        throw 'Callback probe relocation directory does not match its .reloc section.'
    }
    $relocOffset = Convert-RvaToRawOffset -Rva $relocRva -Sections @($reloc)
    $relocBytes = [byte[]]::new([int]$relocSize)
    [Array]::Copy($image, $relocOffset, $relocBytes, 0, [int]$relocSize)
    $parsed = Test-SharnouBaseRelocationDirectory -Bytes $relocBytes -ImageSize $imageSize -AllowedRanges @([pscustomobject]@{ StartRva = [UInt32]$rdata.Rva; Size = [UInt32]$rdata.VirtualSize })
    if ($parsed.TargetRvas.Count -ne 3) {
        throw ("Expected entry anchor plus two callback pointer relocations; found {0}." -f $parsed.TargetRvas.Count)
    }
    if (-not ($parsed.TargetRvas -contains [UInt32]$rdata.Rva)) {
        throw '.rdata entry-point anchor relocation is absent.'
    }

    $pointerTargets = @($parsed.TargetRvas | Where-Object { $_ -ne [UInt32]$rdata.Rva })
    if ($pointerTargets.Count -ne 2) { throw 'Expected exactly two typed callback pointer slots.' }
    $callbackRvas = [System.Collections.Generic.List[UInt32]]::new()
    foreach ($pointerRva in $pointerTargets) {
        $pointerOffset = Convert-RvaToRawOffset -Rva ([UInt32]$pointerRva) -Sections @($rdata)
        $pointerVa = [UInt64][BitConverter]::ToUInt64($image, $pointerOffset)
        if ($pointerVa -lt ($imageBase + [UInt64]$text.Rva) -or
            $pointerVa -ge ($imageBase + [UInt64]$text.Rva + [UInt64]$text.VirtualSize)) {
            throw ("Typed callback pointer 0x{0:X16} does not resolve into .text." -f $pointerVa)
        }
        $callbackRvas.Add([UInt32]($pointerVa - $imageBase))
    }
    if ($callbackRvas[0] -eq $callbackRvas[1]) { throw 'ServiceMain and HandlerEx callback pointers alias the same code address.' }

    $anchorOffset = Convert-RvaToRawOffset -Rva ([UInt32]$rdata.Rva) -Sections @($rdata)
    $anchorVa = [UInt64][BitConverter]::ToUInt64($image, $anchorOffset)
    if ($anchorVa -ne ($imageBase + [UInt64]$entryRva)) {
        throw 'The original .rdata entry-point anchor changed while adding callback relocations.'
    }

    Write-Host 'PASS: callback pointer table contains two distinct relocated .text addresses.'
    Write-Host 'PASS: service-main and HandlerEx callback pointers are 64-bit aligned and point into the generated image.'
    Write-Host 'PASS: the legacy entry-point anchor remains correctly relocated.'

    $programOutput = @(& $output 2>&1)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw ("Generated callback ABI executable failed with exit code {0}; output=[{1}]." -f $exitCode, ($programOutput -join [Environment]::NewLine))
    }
    Write-Host 'PASS: generated executable invoked SERVICE_MAIN_FUNCTIONW and HANDLER_FUNCTION_EX through relocated function pointers.'
    Write-Host 'Win64 callback ABI tests: PASS'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
