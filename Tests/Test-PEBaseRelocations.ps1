[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot '..\Tools\SharnouPERelocations.ps1'
$modulePath = [IO.Path]::GetFullPath($modulePath)
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
    throw "PE relocation module is missing: $modulePath"
}
. $modulePath

$script:Passed = 0
$script:Failed = 0

function Record-Pass {
    param([string] $Name)
    $script:Passed++
    Write-Host "PASS: $Name" -ForegroundColor Green
}

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Throws {
    param([string] $Name, [scriptblock] $Action)
    $rejected = $false
    try {
        & $Action
    }
    catch {
        $rejected = $true
    }
    if (-not $rejected) {
        throw "Expected rejection did not occur: $Name"
    }
    Record-Pass "rejected $Name"
}

function Get-Hex {
    param([byte[]] $Bytes)
    return (($Bytes | ForEach-Object { $_.ToString('X2') }) -join '')
}

$range = @([pscustomobject]@{ StartRva = [UInt32]0x2000; Size = [UInt32]0x4000 })
$imageSize = [UInt32]0x8000

# The legacy one-pointer relocation directory must remain byte-for-byte identical.
$baseline = New-SharnouBaseRelocationDirectory -TargetRvas ([UInt32[]]@(0x2000)) -ImageSize $imageSize -AllowedRanges $range
$baselineHex = Get-Hex -Bytes $baseline.Bytes
Assert-True ($baselineHex -eq '002000000C00000000A00000') "Legacy relocation bytes changed: $baselineHex"
Assert-True ($baseline.BlockCount -eq 1) 'Legacy relocation block count must remain one.'
Assert-True ($baseline.DirectorySize -eq 12) 'Legacy one-entry directory must remain 12 bytes.'
Record-Pass 'legacy single-pointer relocation output remains byte-for-byte stable'

# Multiple DIR64 targets in one page, with sorted entries and ABS alignment padding.
$samePage = New-SharnouBaseRelocationDirectory -TargetRvas ([UInt32[]]@(0x2010, 0x2000, 0x2008)) -ImageSize $imageSize -AllowedRanges $range
Assert-True ((Get-Hex -Bytes $samePage.Bytes) -eq '002000001000000000A008A010A00000') 'Three-entry page block bytes are not canonical.'
Assert-True ($samePage.DirectorySize -eq 16) 'Three DIR64 entries require a 16-byte aligned block.'
Assert-True ($samePage.TargetRvas.Count -eq 3) 'Three relocation targets were not retained.'
Record-Pass 'multiple DIR64 targets share a page with canonical ordering and padding'

# A target at the final 8-byte slot of a page and targets on the next page.
$multiplePages = New-SharnouBaseRelocationDirectory -TargetRvas ([UInt32[]]@(0x3018, 0x2FF8, 0x3000)) -ImageSize $imageSize -AllowedRanges $range
Assert-True ($multiplePages.BlockCount -eq 2) 'Targets on two pages must produce two relocation blocks.'
Assert-True ($multiplePages.DirectorySize -eq 24) 'Two single-entry page blocks must occupy 24 bytes.'
Assert-True ((Get-Hex -Bytes $multiplePages.Bytes) -eq '002000000C000000F8AF0000003000000C00000000A018A0') 'Multiple-page relocation blocks are not page-sorted/canonical.'
Record-Pass 'multiple page blocks are sorted and page-end targets are valid'

# The independent parser must recover the exact target set.
$parsed = Test-SharnouBaseRelocationDirectory -Bytes $multiplePages.Bytes -ImageSize $imageSize -AllowedRanges $range -ExpectedTargetRvas ([UInt32[]]@(0x2FF8, 0x3000, 0x3018))
Assert-True ($parsed.Valid -and $parsed.BlockCount -eq 2 -and $parsed.TargetRvas.Count -eq 3) 'Relocation directory parser failed to recover the expected target set.'
Record-Pass 'independent parser recovers the exact multi-page target set'

# Deterministic output is independent of caller order.
$reordered = New-SharnouBaseRelocationDirectory -TargetRvas ([UInt32[]]@(0x2008, 0x2010, 0x2000)) -ImageSize $imageSize -AllowedRanges $range
Assert-True ((Get-Hex -Bytes $reordered.Bytes) -eq (Get-Hex -Bytes $samePage.Bytes)) 'Relocation directory depends on input target order.'
Record-Pass 'relocation output is deterministic under input reordering'

# Malformed and hostile target input must fail closed.
Assert-Throws 'empty target list' {
    New-SharnouBaseRelocationDirectory -TargetRvas ([UInt32[]]@()) -ImageSize $imageSize -AllowedRanges $range
}
Assert-Throws 'duplicate target' {
    New-SharnouBaseRelocationDirectory -TargetRvas ([UInt32[]]@(0x2000, 0x2000)) -ImageSize $imageSize -AllowedRanges $range
}
Assert-Throws 'unaligned target' {
    New-SharnouBaseRelocationDirectory -TargetRvas ([UInt32[]]@(0x2004)) -ImageSize $imageSize -AllowedRanges $range
}
Assert-Throws 'target outside image' {
    New-SharnouBaseRelocationDirectory -TargetRvas ([UInt32[]]@(0x8000)) -ImageSize $imageSize -AllowedRanges $range
}
Assert-Throws 'target outside approved data range' {
    New-SharnouBaseRelocationDirectory -TargetRvas ([UInt32[]]@(0x1000)) -ImageSize $imageSize -AllowedRanges $range
}
Assert-Throws 'invalid approved data range' {
    New-SharnouBaseRelocationDirectory -TargetRvas ([UInt32[]]@(0x2000)) -ImageSize $imageSize -AllowedRanges @([pscustomobject]@{ StartRva = [UInt32]0x7000; Size = [UInt32]0x2000 })
}
Assert-Throws 'directory size limit' {
    New-SharnouBaseRelocationDirectory -TargetRvas ([UInt32[]]@(0x2000, 0x2008)) -ImageSize $imageSize -AllowedRanges $range -MaximumDirectoryBytes 8
}

# Parser rejects malformed page, type, target order, block size and truncation.
$badPage = [byte[]]$multiplePages.Bytes.Clone()
[BitConverter]::GetBytes([UInt32]0x2001).CopyTo($badPage, 0)
Assert-Throws 'unaligned relocation page RVA' {
    Test-SharnouBaseRelocationDirectory -Bytes $badPage -ImageSize $imageSize -AllowedRanges $range
}

$badType = [byte[]]$baseline.Bytes.Clone()
[BitConverter]::GetBytes([UInt16]0x3000).CopyTo($badType, 8)
Assert-Throws 'unsupported relocation type' {
    Test-SharnouBaseRelocationDirectory -Bytes $badType -ImageSize $imageSize -AllowedRanges $range
}

$duplicateEntry = [byte[]]$samePage.Bytes.Clone()
[BitConverter]::GetBytes([UInt16]0xA000).CopyTo($duplicateEntry, 10)
Assert-Throws 'duplicate or unsorted DIR64 entry' {
    Test-SharnouBaseRelocationDirectory -Bytes $duplicateEntry -ImageSize $imageSize -AllowedRanges $range
}

$badPadding = [byte[]]$baseline.Bytes.Clone()
[BitConverter]::GetBytes([UInt16]0x0001).CopyTo($badPadding, 10)
Assert-Throws 'nonzero ABS alignment entry' {
    Test-SharnouBaseRelocationDirectory -Bytes $badPadding -ImageSize $imageSize -AllowedRanges $range
}

$badBlockSize = [byte[]]$baseline.Bytes.Clone()
[BitConverter]::GetBytes([UInt32]10).CopyTo($badBlockSize, 4)
Assert-Throws 'misaligned relocation block size' {
    Test-SharnouBaseRelocationDirectory -Bytes $badBlockSize -ImageSize $imageSize -AllowedRanges $range
}

$truncated = [byte[]]::new($baseline.Bytes.Length - 1)
[Array]::Copy($baseline.Bytes, $truncated, $truncated.Length)
Assert-Throws 'truncated relocation block' {
    Test-SharnouBaseRelocationDirectory -Bytes $truncated -ImageSize $imageSize -AllowedRanges $range
}

$trailing = [byte[]]::new($baseline.Bytes.Length + 1)
[Array]::Copy($baseline.Bytes, $trailing, $baseline.Bytes.Length)
Assert-Throws 'trailing relocation directory byte' {
    Test-SharnouBaseRelocationDirectory -Bytes $trailing -ImageSize $imageSize -AllowedRanges $range
}

Assert-Throws 'unexpected target-set mismatch' {
    Test-SharnouBaseRelocationDirectory -Bytes $multiplePages.Bytes -ImageSize $imageSize -AllowedRanges $range -ExpectedTargetRvas ([UInt32[]]@(0x2FF8))
}

Write-Host ("PE relocation tests: {0} PASS, {1} FAIL" -f $script:Passed, $script:Failed)
if ($script:Failed -ne 0) { throw 'PE relocation regression suite failed.' }
