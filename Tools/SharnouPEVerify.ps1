[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string] $Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Fail-PE {
    param([string] $Message)
    throw "PE verification failed: $Message"
}
function Read-U16 {
    param([byte[]] $Bytes, [int] $Offset)
    if ($Offset -lt 0 -or ($Offset + 2) -gt $Bytes.Length) { Fail-PE '16-bit field is outside file bounds.' }
    return [BitConverter]::ToUInt16($Bytes, $Offset)
}
function Read-U32 {
    param([byte[]] $Bytes, [int] $Offset)
    if ($Offset -lt 0 -or ($Offset + 4) -gt $Bytes.Length) { Fail-PE '32-bit field is outside file bounds.' }
    return [BitConverter]::ToUInt32($Bytes, $Offset)
}
function Read-U64 {
    param([byte[]] $Bytes, [int] $Offset)
    if ($Offset -lt 0 -or ($Offset + 8) -gt $Bytes.Length) { Fail-PE '64-bit field is outside file bounds.' }
    return [BitConverter]::ToUInt64($Bytes, $Offset)
}
function Align-Up-PE {
    param([UInt64] $Value, [UInt64] $Alignment)
    if ($Alignment -eq 0) { Fail-PE 'Zero alignment.' }
    return [UInt64]([Math]::Ceiling([double]$Value / [double]$Alignment) * [double]$Alignment)
}
function Convert-RvaToOffset {
    param([UInt64] $Rva, [UInt64] $Size, [object[]] $Sections, [int] $FileSize)
    foreach ($section in $Sections) {
        $start = [UInt64]$section.Rva
        $span = [UInt64]$section.RawSize
        if ($Rva -ge $start -and ($Rva + $Size) -le ($start + $span)) {
            $offset = [UInt64]$section.RawPointer + ($Rva - $start)
            if (($offset + $Size) -gt [UInt64]$FileSize) { Fail-PE 'RVA resolves past end of file.' }
            return [int]$offset
        }
    }
    Fail-PE ("RVA 0x{0:X8} size {1} is not backed by section data." -f $Rva, $Size)
}
function Read-AsciiZAtRva {
    param([UInt64] $Rva, [object[]] $Sections, [byte[]] $Bytes)
    $offset = Convert-RvaToOffset -Rva $Rva -Size 1 -Sections $Sections -FileSize $Bytes.Length
    $end = $Bytes.Length
    foreach ($section in $Sections) {
        if ($Rva -ge [UInt64]$section.Rva -and $Rva -lt ([UInt64]$section.Rva + [UInt64]$section.RawSize)) {
            $end = [int]([UInt64]$section.RawPointer + [UInt64]$section.RawSize)
            break
        }
    }
    $builder = [System.Text.StringBuilder]::new()
    for ($i = $offset; $i -lt $end; $i++) {
        if ($Bytes[$i] -eq 0) { return $builder.ToString() }
        if ($Bytes[$i] -gt 127) { Fail-PE 'Import name contains non-ASCII bytes.' }
        $null = $builder.Append([char]$Bytes[$i])
    }
    Fail-PE 'Unterminated import string.'
}

$file = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
$bytes = [System.IO.File]::ReadAllBytes($file)
if ($bytes.Length -lt 0x400) { Fail-PE 'File is shorter than the PE header region.' }
if ($bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) { Fail-PE 'DOS MZ signature is missing.' }
$pe = [int](Read-U32 -Bytes $bytes -Offset 0x3C)
if ($pe -lt 0 -or ($pe + 24) -gt $bytes.Length) { Fail-PE 'PE header offset is invalid.' }
if ($bytes[$pe] -ne 0x50 -or $bytes[$pe + 1] -ne 0x45 -or $bytes[$pe + 2] -ne 0 -or $bytes[$pe + 3] -ne 0) { Fail-PE 'PE signature is invalid.' }
if ((Read-U16 -Bytes $bytes -Offset ($pe + 4)) -ne 0x8664) { Fail-PE 'COFF machine is not AMD64.' }
$sectionCount = [int](Read-U16 -Bytes $bytes -Offset ($pe + 6))
$optionalSize = [int](Read-U16 -Bytes $bytes -Offset ($pe + 20))
if ($sectionCount -ne 4 -or $optionalSize -lt 240) { Fail-PE 'Expected four sections and a complete PE32+ optional header.' }
$opt = $pe + 24
if ((Read-U16 -Bytes $bytes -Offset $opt) -ne 0x020B) { Fail-PE 'Optional header is not PE32+.' }
$entryRva = [UInt64](Read-U32 -Bytes $bytes -Offset ($opt + 16))
$imageBase = Read-U64 -Bytes $bytes -Offset ($opt + 24)
$sectionAlignment = [UInt64](Read-U32 -Bytes $bytes -Offset ($opt + 32))
$fileAlignment = [UInt64](Read-U32 -Bytes $bytes -Offset ($opt + 36))
$sizeImage = [UInt64](Read-U32 -Bytes $bytes -Offset ($opt + 56))
$sizeHeaders = [UInt64](Read-U32 -Bytes $bytes -Offset ($opt + 60))
$characteristics = [UInt16](Read-U16 -Bytes $bytes -Offset ($opt + 70))
if ($sectionAlignment -ne 0x1000 -or $fileAlignment -ne 0x200) { Fail-PE 'Unexpected PE section or file alignment.' }
if (($characteristics -band 0x0100) -eq 0 -or ($characteristics -band 0x0040) -eq 0) { Fail-PE 'NX or DYNAMIC_BASE is not enabled.' }
if ((Read-U32 -Bytes $bytes -Offset ($opt + 108)) -lt 16) { Fail-PE 'PE data-directory count is less than 16.' }

$sectionTable = $opt + $optionalSize
$sections = [System.Collections.Generic.List[object]]::new()
$seenNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
for ($index = 0; $index -lt $sectionCount; $index++) {
    $h = $sectionTable + ($index * 40)
    if (($h + 40) -gt $bytes.Length) { Fail-PE 'Section header lies outside the file.' }
    $name = [System.Text.Encoding]::ASCII.GetString($bytes, $h, 8).Trim([char[]]@(0))
    $virtualSize = [UInt64](Read-U32 -Bytes $bytes -Offset ($h + 8))
    $rva = [UInt64](Read-U32 -Bytes $bytes -Offset ($h + 12))
    $rawSize = [UInt64](Read-U32 -Bytes $bytes -Offset ($h + 16))
    $rawPointer = [UInt64](Read-U32 -Bytes $bytes -Offset ($h + 20))
    $flags = [UInt32](Read-U32 -Bytes $bytes -Offset ($h + 36))
    if (-not $seenNames.Add($name)) { Fail-PE "Duplicate section '$name'." }
    if (($rva % $sectionAlignment) -ne 0 -or $rawSize -eq 0 -or ($rawSize % $fileAlignment) -ne 0) { Fail-PE "Section '$name' alignment or size is invalid." }
    if ($virtualSize -eq 0 -or $virtualSize -gt $rawSize) { Fail-PE "Section '$name' virtual size is invalid." }
    if (($rawPointer % $fileAlignment) -ne 0 -or $rawPointer -lt $sizeHeaders) { Fail-PE "Section '$name' raw pointer is invalid." }
    if (($rawPointer + $rawSize) -gt [UInt64]$bytes.Length -or ($rva + $virtualSize) -gt $sizeImage) { Fail-PE "Section '$name' exceeds its image bounds." }
    $sections.Add([pscustomobject]@{ Name = $name; VirtualSize = $virtualSize; Rva = $rva; RawSize = $rawSize; RawPointer = $rawPointer; Flags = $flags })
}
foreach ($name in @('.text', '.rdata', '.idata', '.reloc')) { if (-not $seenNames.Contains($name)) { Fail-PE "Missing section '$name'." } }

$text = $sections | Where-Object Name -eq '.text' | Select-Object -First 1
$rdata = $sections | Where-Object Name -eq '.rdata' | Select-Object -First 1
$idata = $sections | Where-Object Name -eq '.idata' | Select-Object -First 1
$reloc = $sections | Where-Object Name -eq '.reloc' | Select-Object -First 1
if ($text.Rva -ne 0x1000) { Fail-PE '.text must start at RVA 0x1000.' }
$expectedRdata = $text.Rva + (Align-Up-PE -Value $text.VirtualSize -Alignment $sectionAlignment)
$expectedIdata = $rdata.Rva + (Align-Up-PE -Value $rdata.VirtualSize -Alignment $sectionAlignment)
$expectedReloc = $idata.Rva + (Align-Up-PE -Value $idata.VirtualSize -Alignment $sectionAlignment)
if ($rdata.Rva -ne $expectedRdata -or $idata.Rva -ne $expectedIdata -or $reloc.Rva -ne $expectedReloc) { Fail-PE 'Section RVAs do not follow the aligned preceding sections.' }
$expectedSizeImage = $reloc.Rva + (Align-Up-PE -Value $reloc.VirtualSize -Alignment $sectionAlignment)
if ($sizeImage -ne $expectedSizeImage) { Fail-PE 'SizeOfImage does not match the final aligned section.' }
foreach ($a in $sections) {
    foreach ($b in $sections) {
        if ($a.Name -eq $b.Name) { continue }
        if ($a.RawPointer -lt ($b.RawPointer + $b.RawSize) -and $b.RawPointer -lt ($a.RawPointer + $a.RawSize)) { Fail-PE "Raw sections '$($a.Name)' and '$($b.Name)' overlap." }
        $aSpan = Align-Up-PE -Value $a.VirtualSize -Alignment $sectionAlignment
        $bSpan = Align-Up-PE -Value $b.VirtualSize -Alignment $sectionAlignment
        if ($a.Rva -lt ($b.Rva + $bSpan) -and $b.Rva -lt ($a.Rva + $aSpan)) { Fail-PE "Virtual sections '$($a.Name)' and '$($b.Name)' overlap." }
    }
}
if (($text.Flags -band 0x60000000) -ne 0x60000000 -or ($text.Flags -band 0x80000000) -ne 0) { Fail-PE '.text must be read/execute and not writable.' }
if (($rdata.Flags -band 0x40000000) -eq 0 -or ($rdata.Flags -band 0xA0000000) -ne 0) { Fail-PE '.rdata must be read-only data.' }
if (($idata.Flags -band [UInt32]3221225472) -ne [UInt32]3221225472) { Fail-PE '.idata must be readable and writable.' }
if (($reloc.Flags -band 0x02000000) -eq 0) { Fail-PE '.reloc must be discardable.' }
if ($entryRva -lt $text.Rva -or $entryRva -ge ($text.Rva + $text.VirtualSize)) { Fail-PE 'Entry point is outside .text.' }

$importRva = [UInt64](Read-U32 -Bytes $bytes -Offset ($opt + 120))
$importSize = [UInt64](Read-U32 -Bytes $bytes -Offset ($opt + 124))
$relocRva = [UInt64](Read-U32 -Bytes $bytes -Offset ($opt + 152))
$relocSize = [UInt64](Read-U32 -Bytes $bytes -Offset ($opt + 156))
$iatRva = [UInt64](Read-U32 -Bytes $bytes -Offset ($opt + 208))
$iatSize = [UInt64](Read-U32 -Bytes $bytes -Offset ($opt + 212))
if ($importSize -lt 20 -or $relocSize -lt 12 -or $iatSize -lt 8) { Fail-PE 'Import, IAT, or relocation directory is missing.' }
if ($importRva -lt $idata.Rva -or ($importRva + $importSize) -gt ($idata.Rva + $idata.VirtualSize)) { Fail-PE 'Import directory is outside .idata.' }
if ($iatRva -lt $idata.Rva -or ($iatRva + $iatSize) -gt ($idata.Rva + $idata.VirtualSize)) { Fail-PE 'IAT directory is outside .idata.' }
if ($relocRva -lt $reloc.Rva -or ($relocRva + $relocSize) -gt ($reloc.Rva + $reloc.VirtualSize)) { Fail-PE 'Relocation directory is outside .reloc.' }
$importOffset = Convert-RvaToOffset -Rva $importRva -Size $importSize -Sections $sections.ToArray() -FileSize $bytes.Length
$foundDlls = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$foundImports = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$descriptorIndex = 0
while ($true) {
    if ($descriptorIndex -gt 15) { Fail-PE 'Import descriptor array has no null terminator.' }
    $d = $importOffset + ($descriptorIndex * 20)
    if (($d + 20) -gt ($importOffset + $importSize)) { Fail-PE 'Import descriptor array is truncated.' }
    $oft = [UInt64](Read-U32 -Bytes $bytes -Offset $d)
    $nameRva = [UInt64](Read-U32 -Bytes $bytes -Offset ($d + 12))
    $firstThunk = [UInt64](Read-U32 -Bytes $bytes -Offset ($d + 16))
    if ($oft -eq 0 -and $nameRva -eq 0 -and $firstThunk -eq 0) {
        $timestamp = Read-U32 -Bytes $bytes -Offset ($d + 4)
        $forwarder = Read-U32 -Bytes $bytes -Offset ($d + 8)
        if ($timestamp -ne 0 -or $forwarder -ne 0) { Fail-PE 'Null import descriptor is not fully zeroed.' }
        break
    }
    if ($nameRva -eq 0 -or $firstThunk -eq 0) { Fail-PE 'Import descriptor has a missing name or IAT.' }
    $dllName = Read-AsciiZAtRva -Rva $nameRva -Sections $sections.ToArray() -Bytes $bytes
    $null = $foundDlls.Add($dllName)
    $lookupRva = if ($oft -ne 0) { $oft } else { $firstThunk }
    $thunkTerminated = $false
    for ($thunkIndex = 0; $thunkIndex -lt 128; $thunkIndex++) {
        $thunkRva = $lookupRva + ([UInt64]$thunkIndex * 8)
        $thunkOffset = Convert-RvaToOffset -Rva $thunkRva -Size 8 -Sections $sections.ToArray() -FileSize $bytes.Length
        $thunkValue = Read-U64 -Bytes $bytes -Offset $thunkOffset
        if ($thunkValue -eq 0) { $thunkTerminated = $true; break }
        if ($thunkValue -gt [UInt32]::MaxValue) { Fail-PE 'Ordinal or invalid import entry is unsupported.' }
        $hintOffset = Convert-RvaToOffset -Rva ([UInt64]$thunkValue) -Size 3 -Sections $sections.ToArray() -FileSize $bytes.Length
        $importName = Read-AsciiZAtRva -Rva ($thunkValue + 2) -Sections $sections.ToArray() -Bytes $bytes
        if ([string]::IsNullOrWhiteSpace($importName)) { Fail-PE 'Import-by-name record has an empty API name.' }
        $null = $foundImports.Add($importName)
        $iatEntryRva = $firstThunk + ([UInt64]$thunkIndex * 8)
        $null = Convert-RvaToOffset -Rva $iatEntryRva -Size 8 -Sections $sections.ToArray() -FileSize $bytes.Length
    }
    if (-not $thunkTerminated) { Fail-PE "Import lookup table for '$dllName' has no null thunk." }
    $descriptorIndex++
}
if ($foundDlls.Count -lt 4) { Fail-PE 'Expected four Windows system DLL import descriptors.' }
foreach ($dll in @('KERNEL32.dll', 'USER32.dll', 'D3D11.dll', 'DXGI.dll')) { if (-not $foundDlls.Contains($dll)) { Fail-PE "Missing required DLL '$dll'." } }
foreach ($api in @('GetStdHandle', 'WriteFile', 'ExitProcess', 'wsprintfA', 'CreateFileA', 'GetFileSizeEx', 'ReadFile', 'CloseHandle', 'GetModuleHandleA', 'CreateThread', 'WaitForSingleObject', 'CreateMutexA', 'ReleaseMutex', 'CreateWindowExA', 'ShowWindow', 'UpdateWindow', 'PeekMessageA', 'TranslateMessage', 'DispatchMessageA', 'DestroyWindow', 'D3D11CreateDeviceAndSwapChain', 'CreateDXGIFactory', 'QueryPerformanceCounter', 'QueryPerformanceFrequency', 'IsWindow')) {
    if (-not $foundImports.Contains($api)) { Fail-PE "Missing required imported API '$api'." }
}
$relocOffset = Convert-RvaToOffset -Rva $relocRva -Size $relocSize -Sections $sections.ToArray() -FileSize $bytes.Length
$pageRva = [UInt64](Read-U32 -Bytes $bytes -Offset $relocOffset)
$blockSize = [UInt64](Read-U32 -Bytes $bytes -Offset ($relocOffset + 4))
if ($blockSize -ne 12 -or $relocSize -ne 12) { Fail-PE 'Expected one 12-byte base-relocation block.' }
$entry = Read-U16 -Bytes $bytes -Offset ($relocOffset + 8)
$padding = Read-U16 -Bytes $bytes -Offset ($relocOffset + 10)
$relocType = $entry -shr 12
$relocTarget = $pageRva + [UInt64]($entry -band 0x0FFF)
if ($relocType -ne 10 -or $relocTarget -ne $rdata.Rva -or $padding -ne 0) { Fail-PE 'Base relocation does not contain one DIR64 relocation for the .rdata anchor.' }
$anchorOffset = Convert-RvaToOffset -Rva $rdata.Rva -Size 8 -Sections $sections.ToArray() -FileSize $bytes.Length
$anchor = Read-U64 -Bytes $bytes -Offset $anchorOffset
if ($anchor -ne ($imageBase + $entryRva)) { Fail-PE 'Relocation anchor does not equal ImageBase + entry-point RVA.' }

Write-Host ("PE verifier: PASS - AMD64 PE32+, 4 sections, {0} DLLs, {1} APIs, dynamic .text supported." -f $foundDlls.Count, $foundImports.Count) -ForegroundColor Green
