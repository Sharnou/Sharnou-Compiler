Set-StrictMode -Version Latest

function Test-SharnouRvaInRanges {
    param(
        [UInt64] $TargetRva,
        [UInt64] $ImageSize,
        [object[]] $AllowedRanges
    )

    foreach ($range in $AllowedRanges) {
        if ($null -eq $range -or $null -eq $range.StartRva -or $null -eq $range.Size) {
            throw 'Relocation range descriptor is incomplete.'
        }
        $start = [UInt64]$range.StartRva
        $size = [UInt64]$range.Size
        if ($start -ge $ImageSize -or $size -lt 8 -or $size -gt ($ImageSize - $start)) {
            throw 'Relocation range descriptor exceeds the image bounds.'
        }
        $rangeEnd = $start + $size
        if ($TargetRva -ge $start -and $TargetRva -le ($rangeEnd - 8)) {
            return $true
        }
    }
    return $false
}

function New-SharnouBaseRelocationDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [UInt32[]] $TargetRvas,
        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 4294967295)]
        [UInt32] $ImageSize,
        [Parameter(Mandatory = $true)]
        [object[]] $AllowedRanges,
        [ValidateRange(1, 1048576)]
        [int] $MaximumDirectoryBytes = 1048576
    )

    if ($TargetRvas.Count -lt 1) { throw 'At least one DIR64 relocation target is required.' }
    if ($AllowedRanges.Count -lt 1) { throw 'At least one initialized-data relocation range is required.' }

    $pages = [System.Collections.Generic.SortedDictionary[UInt32, System.Collections.Generic.List[UInt16]]]::new()
    $seen = [System.Collections.Generic.HashSet[UInt32]]::new()

    foreach ($rawTarget in $TargetRvas) {
        $target64 = [UInt64]$rawTarget
        if ($target64 -gt [UInt32]::MaxValue -or ($target64 + 8) -gt [UInt64]$ImageSize) {
            throw ("DIR64 target RVA 0x{0:X8} is outside the image." -f $target64)
        }
        $target = [UInt32]$target64
        if (($target % 8) -ne 0) { throw ("DIR64 target RVA 0x{0:X8} is not 8-byte aligned." -f $target) }
        if (-not $seen.Add($target)) { throw ("Duplicate DIR64 target RVA: 0x{0:X8}." -f $target) }
        if (-not (Test-SharnouRvaInRanges -TargetRva $target64 -ImageSize $ImageSize -AllowedRanges $AllowedRanges)) {
            throw ("DIR64 target RVA 0x{0:X8} is not wholly contained in an approved initialized-data range." -f $target)
        }

        $page = [UInt32]($target - ($target % 0x1000))
        $pageOffset = [UInt16]($target - $page)
        $entry = [UInt16](0xA000 -bor $pageOffset)
        if (-not $pages.ContainsKey($page)) {
            $pages.Add($page, [System.Collections.Generic.List[UInt16]]::new())
        }
        $pages[$page].Add($entry)
    }

    $stream = [System.IO.MemoryStream]::new()
    $writer = [System.IO.BinaryWriter]::new($stream, [System.Text.Encoding]::ASCII, $true)
    try {
        foreach ($page in $pages.Keys) {
            $entries = $pages[$page]
            $entries.Sort()
            $blockStart = [int]$stream.Position
            $writer.Write([UInt32]$page)
            $writer.Write([UInt32]0)
            foreach ($entry in $entries) { $writer.Write([UInt16]$entry) }
            if (($entries.Count % 2) -ne 0) { $writer.Write([UInt16]0) }

            $blockSize = [UInt32]($stream.Position - $blockStart)
            if (($blockSize % 4) -ne 0 -or $blockSize -lt 12) {
                throw 'Internal relocation builder error: invalid block alignment or size.'
            }
            $position = $stream.Position
            $stream.Position = $blockStart + 4
            $writer.Write($blockSize)
            $stream.Position = $position
            if ($stream.Length -gt $MaximumDirectoryBytes) {
                throw 'Base relocation directory exceeds its configured maximum size.'
            }
        }
        $bytes = $stream.ToArray()
    }
    finally {
        $writer.Dispose()
        $stream.Dispose()
    }

    $roundTrip = Test-SharnouBaseRelocationDirectory -Bytes $bytes -ImageSize $ImageSize -AllowedRanges $AllowedRanges -ExpectedTargetRvas ([UInt32[]]@($seen | Sort-Object))
    return [pscustomobject]@{
        Bytes = [byte[]]$bytes
        TargetRvas = [UInt32[]]$roundTrip.TargetRvas
        BlockCount = [int]$pages.Count
        DirectorySize = [int]$bytes.Length
    }
}

function Test-SharnouBaseRelocationDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]] $Bytes,
        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 4294967295)]
        [UInt32] $ImageSize,
        [Parameter(Mandatory = $true)]
        [object[]] $AllowedRanges,
        [UInt32[]] $ExpectedTargetRvas = @()
    )

    if ($Bytes.Length -lt 12 -or $Bytes.Length -gt 1048576) {
        throw 'Base relocation directory length is outside the accepted bounds.'
    }
    if ($AllowedRanges.Count -lt 1) { throw 'At least one initialized-data relocation range is required.' }

    $targets = [System.Collections.Generic.List[UInt32]]::new()
    $seen = [System.Collections.Generic.HashSet[UInt32]]::new()
    $offset = 0
    $previousPage = [UInt64]0
    $blockCount = 0

    while ($offset -lt $Bytes.Length) {
        if (($offset + 8) -gt $Bytes.Length) { throw 'Base relocation block header is truncated.' }
        $page = [UInt32][BitConverter]::ToUInt32($Bytes, $offset)
        $blockSize = [UInt32][BitConverter]::ToUInt32($Bytes, $offset + 4)
        if (($page % 0x1000) -ne 0) { throw 'Base relocation block page RVA is not 4 KiB aligned.' }
        if ($blockCount -gt 0 -and [UInt64]$page -le $previousPage) {
            throw 'Base relocation blocks are not in strictly increasing page order.'
        }
        if ($blockSize -lt 12 -or ($blockSize % 4) -ne 0 -or ($offset + [UInt64]$blockSize) -gt $Bytes.Length) {
            throw 'Base relocation block size is invalid, misaligned, or truncated.'
        }

        $entryCount = [int](($blockSize - 8) / 2)
        $blockTargets = [System.Collections.Generic.List[UInt32]]::new()
        $hasAbsolutePadding = $false
        $previousEntryOffset = -1

        for ($entryIndex = 0; $entryIndex -lt $entryCount; $entryIndex++) {
            $entry = [UInt16][BitConverter]::ToUInt16($Bytes, $offset + 8 + ($entryIndex * 2))
            $type = [int]($entry -shr 12)
            $pageOffset = [int]($entry -band 0x0FFF)
            if ($type -eq 0) {
                if ($entry -ne 0 -or $entryIndex -ne ($entryCount - 1) -or $hasAbsolutePadding) {
                    throw 'ABS relocation padding is nonzero, duplicated, or not the final block entry.'
                }
                $hasAbsolutePadding = $true
                continue
            }
            if ($type -ne 10) { throw ("Unsupported base relocation type {0}; only ABS padding and DIR64 are accepted." -f $type) }
            if (($pageOffset % 8) -ne 0 -or $pageOffset -le $previousEntryOffset) {
                throw 'DIR64 relocation entries are unaligned, duplicated, or not sorted.'
            }

            $target64 = [UInt64]$page + [UInt64]$pageOffset
            if (($target64 + 8) -gt [UInt64]$ImageSize) { throw 'DIR64 relocation target exceeds the image bounds.' }
            if (-not (Test-SharnouRvaInRanges -TargetRva $target64 -ImageSize $ImageSize -AllowedRanges $AllowedRanges)) {
                throw 'DIR64 relocation target is outside an approved initialized-data range.'
            }

            $target = [UInt32]$target64
            if (-not $seen.Add($target)) { throw ("Duplicate DIR64 relocation target RVA: 0x{0:X8}." -f $target) }
            $targets.Add($target)
            $blockTargets.Add($target)
            $previousEntryOffset = $pageOffset
        }

        if ($blockTargets.Count -lt 1) { throw 'Base relocation block contains no DIR64 entries.' }
        if (($blockTargets.Count % 2) -ne 0 -and -not $hasAbsolutePadding) {
            throw 'Odd DIR64-entry count requires one ABS alignment entry.'
        }
        if (($blockTargets.Count % 2) -eq 0 -and $hasAbsolutePadding) {
            throw 'Even DIR64-entry count must not contain an ABS padding entry.'
        }

        $previousPage = [UInt64]$page
        $offset += [int]$blockSize
        $blockCount++
    }

    if ($offset -ne $Bytes.Length -or $blockCount -lt 1) {
        throw 'Base relocation directory contains trailing data or no blocks.'
    }

    $sortedTargets = [UInt32[]]@($targets | Sort-Object)
    if ($ExpectedTargetRvas.Count -gt 0) {
        $expected = [UInt32[]]@($ExpectedTargetRvas | Sort-Object)
        if ($expected.Count -ne $sortedTargets.Count) {
            throw 'Base relocation target count does not match the expected set.'
        }
        for ($i = 0; $i -lt $expected.Count; $i++) {
            if ($expected[$i] -ne $sortedTargets[$i]) { throw 'Base relocation target set does not match the expected set.' }
        }
    }

    return [pscustomobject]@{
        Valid = $true
        TargetRvas = $sortedTargets
        BlockCount = $blockCount
        DirectorySize = $Bytes.Length
    }
}
