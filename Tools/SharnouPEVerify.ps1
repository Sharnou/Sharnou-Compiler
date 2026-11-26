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
if ($sectionCount -ne 6 -or $optionalSize -lt 240) { Fail-PE 'Expected six sections including x64 unwind tables and a complete PE32+ optional header.' }
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
foreach ($name in @('.text', '.rdata', '.idata', '.reloc', '.pdata', '.xdata')) { if (-not $seenNames.Contains($name)) { Fail-PE "Missing section '$name'." } }

$text = $sections | Where-Object Name -eq '.text' | Select-Object -First 1
$rdata = $sections | Where-Object Name -eq '.rdata' | Select-Object -First 1
$idata = $sections | Where-Object Name -eq '.idata' | Select-Object -First 1
$reloc = $sections | Where-Object Name -eq '.reloc' | Select-Object -First 1
$pdata = $sections | Where-Object Name -eq '.pdata' | Select-Object -First 1
$xdata = $sections | Where-Object Name -eq '.xdata' | Select-Object -First 1
if ($text.Rva -ne 0x1000) { Fail-PE '.text must start at RVA 0x1000.' }
$expectedRdata = $text.Rva + (Align-Up-PE -Value $text.VirtualSize -Alignment $sectionAlignment)
$expectedIdata = $rdata.Rva + (Align-Up-PE -Value $rdata.VirtualSize -Alignment $sectionAlignment)
$expectedReloc = $idata.Rva + (Align-Up-PE -Value $idata.VirtualSize -Alignment $sectionAlignment)
$expectedPdata = $reloc.Rva + (Align-Up-PE -Value $reloc.VirtualSize -Alignment $sectionAlignment)
$expectedXdata = $pdata.Rva + (Align-Up-PE -Value $pdata.VirtualSize -Alignment $sectionAlignment)
if ($rdata.Rva -ne $expectedRdata -or $idata.Rva -ne $expectedIdata -or $reloc.Rva -ne $expectedReloc -or $pdata.Rva -ne $expectedPdata -or $xdata.Rva -ne $expectedXdata) { Fail-PE 'Section RVAs do not follow the aligned preceding sections.' }
$expectedSizeImage = $xdata.Rva + (Align-Up-PE -Value $xdata.VirtualSize -Alignment $sectionAlignment)
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
foreach ($section in @($pdata, $xdata)) { if (($section.Flags -band 0x40000000) -eq 0 -or ($section.Flags -band 0xA0000000) -ne 0) { Fail-PE "$($section.Name) must be read-only initialized data." } }
if ($entryRva -lt $text.Rva -or $entryRva -ge ($text.Rva + $text.VirtualSize)) { Fail-PE 'Entry point is outside .text.' }

$exceptionRva = [UInt64](Read-U32 -Bytes $bytes -Offset ($opt + 136))
$exceptionSize = [UInt64](Read-U32 -Bytes $bytes -Offset ($opt + 140))
if ($exceptionRva -ne [UInt64]$pdata.Rva -or $exceptionSize -ne [UInt64]$pdata.VirtualSize -or $exceptionSize -lt 12 -or ($exceptionSize % 12) -ne 0) {
    Fail-PE 'x64 exception directory must cover the complete .pdata runtime-function table.'
}
$exceptionOffset = Convert-RvaToOffset -Rva $exceptionRva -Size $exceptionSize -Sections $sections.ToArray() -FileSize $bytes.Length
$runtimeFunctionCount = [int]($exceptionSize / 12)
$previousEndRva = [UInt64]0
$stackProbeInstructionPrefix = [byte[]]@(0x55, 0x48, 0x89, 0xE5, 0xB8)
$stackAllocOpcode = [byte[]]@(0x48, 0x81, 0xEC)
$stackProbeCompare = [byte[]]@(0x49, 0x81, 0xFB, 0x00, 0x10, 0x00, 0x00)
$stackProbeSubPointer = [byte[]]@(0x49, 0x81, 0xEA, 0x00, 0x10, 0x00, 0x00)
$stackProbeTouch = [byte[]]@(0x41, 0xF6, 0x02, 0x00)
$stackProbeSubRemaining = [byte[]]@(0x49, 0x81, 0xEB, 0x00, 0x10, 0x00, 0x00)
$stackProbeSubTail = [byte[]]@(0x4D, 0x29, 0xDA)
$previousEndRva = [UInt64]0
$stackProbeHelperRva = [Int64]-1
for ($runtimeIndex = 0; $runtimeIndex -lt $runtimeFunctionCount; $runtimeIndex++) {
    $runtimeOffset = $exceptionOffset + ($runtimeIndex * 12)
    $beginRva = [UInt64](Read-U32 -Bytes $bytes -Offset $runtimeOffset)
    $endRva = [UInt64](Read-U32 -Bytes $bytes -Offset ($runtimeOffset + 4))
    $unwindRva = [UInt64](Read-U32 -Bytes $bytes -Offset ($runtimeOffset + 8))
    if ($beginRva -lt $text.Rva -or $endRva -le $beginRva -or $endRva -gt ($text.Rva + $text.VirtualSize)) {
        Fail-PE ("RUNTIME_FUNCTION {0} has an invalid .text range." -f $runtimeIndex)
    }
    if ($runtimeIndex -gt 0 -and $beginRva -lt $previousEndRva) { Fail-PE 'RUNTIME_FUNCTION entries are not sorted and non-overlapping.' }
    $previousEndRva = $endRva
    if ($unwindRva -lt $xdata.Rva -or ($unwindRva + 4) -gt ($xdata.Rva + $xdata.VirtualSize)) { Fail-PE 'RUNTIME_FUNCTION unwind RVA is outside .xdata.' }
    $unwindOffset = Convert-RvaToOffset -Rva $unwindRva -Size 4 -Sections $sections.ToArray() -FileSize $bytes.Length
    $versionFlags = [int]$bytes[$unwindOffset]
    $version = $versionFlags -band 0x07
    $flags = $versionFlags -shr 3
    $prologSize = [int]$bytes[$unwindOffset + 1]
    $countOfCodes = [int]$bytes[$unwindOffset + 2]
    $frameRegister = [int]($bytes[$unwindOffset + 3] -band 0x0F)
    $frameOffset = [int]($bytes[$unwindOffset + 3] -shr 4)
    if ($version -ne 1 -or $flags -ne 0) { Fail-PE 'Only version-1, non-chained x64 UNWIND_INFO is supported.' }
    if ($prologSize -ne 21 -or $prologSize -ge ($endRva - $beginRva)) { Fail-PE 'UNWIND_INFO prologue size is invalid.' }
    if ($frameRegister -ne 5 -or $frameOffset -ne 0) { Fail-PE 'UNWIND_INFO must describe the generated RBP frame register.' }
    if ($countOfCodes -notin @(4, 5)) { Fail-PE 'UNWIND_INFO has an unsupported unwind-code slot count.' }
    $physicalCodeSlots = [int]([Math]::Ceiling([double]$countOfCodes / 2.0) * 2)
    $unwindSize = 4 + ($physicalCodeSlots * 2)
    if (($unwindRva + $unwindSize) -gt ($xdata.Rva + $xdata.VirtualSize)) { Fail-PE 'UNWIND_INFO code array exceeds .xdata.' }
    $allocCodeOffset = [int]$bytes[$unwindOffset + 4]
    $allocOpInfo = [int]($bytes[$unwindOffset + 5] -shr 4)
    $allocOperation = [int]($bytes[$unwindOffset + 5] -band 0x0F)
    if ($allocCodeOffset -ne $prologSize -or $allocOperation -ne 1 -or $allocOpInfo -notin @(0, 1)) { Fail-PE 'UNWIND_INFO must begin with the final UWOP_ALLOC_LARGE operation.' }
    if ($allocOpInfo -eq 0) {
        if ($countOfCodes -ne 4) { Fail-PE 'UWOP_ALLOC_LARGE scaled form has an invalid slot count.' }
        $frameSize = [int](Read-U16 -Bytes $bytes -Offset ($unwindOffset + 6)) * 8
        $setFrameCodeOffset = $unwindOffset + 8
        $pushCodeOffset = $unwindOffset + 10
    } else {
        if ($countOfCodes -ne 5) { Fail-PE 'UWOP_ALLOC_LARGE 32-bit form has an invalid slot count.' }
        $frameSize = [int](Read-U32 -Bytes $bytes -Offset ($unwindOffset + 6))
        $setFrameCodeOffset = $unwindOffset + 10
        $pushCodeOffset = $unwindOffset + 12
    }
    if ($frameSize -lt 0x1000 -or $frameSize -gt 0x100000 -or ($frameSize % 16) -ne 0) { Fail-PE 'UNWIND_INFO frame allocation is outside the compiler frame policy.' }
    if ($allocOpInfo -eq 0 -and $frameSize -gt 0x7FFF8) { Fail-PE 'UWOP_ALLOC_LARGE scaled form overflows its 16-bit size slot.' }
    if ($allocOpInfo -eq 1 -and $frameSize -le 0x7FFF8) { Fail-PE 'UWOP_ALLOC_LARGE 32-bit form is non-canonical for this frame size.' }
    if ([int]$bytes[$setFrameCodeOffset] -ne 4 -or [int]$bytes[$setFrameCodeOffset + 1] -ne 0x03) { Fail-PE 'UNWIND_INFO is missing UWOP_SET_FPREG at the generated prologue offset.' }
    if ([int]$bytes[$pushCodeOffset] -ne 1 -or [int]$bytes[$pushCodeOffset + 1] -ne 0x50) { Fail-PE 'UNWIND_INFO is missing UWOP_PUSH_NONVOL RBP.' }
    if (($countOfCodes % 2) -ne 0) {
        if ($bytes[$unwindOffset + 4 + ($countOfCodes * 2)] -ne 0 -or $bytes[$unwindOffset + 5 + ($countOfCodes * 2)] -ne 0) { Fail-PE 'UNWIND_INFO alignment padding is not zero.' }
    }

    # Validate the generated prologue: save RBP, pass the fixed allocation in
    # RAX, call the private leaf probe helper, then perform one fixed SUB RSP.
    $textOffset = Convert-RvaToOffset -Rva $beginRva -Size ([UInt64]$prologSize) -Sections $sections.ToArray() -FileSize $bytes.Length
    for ($byteIndex = 0; $byteIndex -lt $stackProbeInstructionPrefix.Length; $byteIndex++) {
        if ($bytes[$textOffset + $byteIndex] -ne $stackProbeInstructionPrefix[$byteIndex]) { Fail-PE 'Function prologue does not start with the expected frame-pointer and stack-probe instructions.' }
    }
    $encodedFrameSize = [BitConverter]::ToInt32($bytes, $textOffset + 5)
    if ($encodedFrameSize -ne $frameSize -or $bytes[$textOffset + 9] -ne 0xE8) { Fail-PE 'Stack-probe call or allocation immediate is invalid.' }
    for ($byteIndex = 0; $byteIndex -lt $stackAllocOpcode.Length; $byteIndex++) {
        if ($bytes[$textOffset + 14 + $byteIndex] -ne $stackAllocOpcode[$byteIndex]) { Fail-PE 'Fixed stack allocation opcode is invalid.' }
    }
    $allocImmediate = [BitConverter]::ToInt32($bytes, $textOffset + 17)
    if ($allocImmediate -ne $frameSize) { Fail-PE 'Final SUB RSP allocation and UNWIND_INFO frame sizes do not match.' }
    $callDisplacement = [BitConverter]::ToInt32($bytes, $textOffset + 10)
    $currentProbeTarget = [Int64]$beginRva + 14 + [Int64]$callDisplacement
    if ($stackProbeHelperRva -lt 0) { $stackProbeHelperRva = $currentProbeTarget }
    elseif ($currentProbeTarget -ne $stackProbeHelperRva) { Fail-PE 'Generated functions do not share the same stack-probe helper.' }
}
if ($runtimeFunctionCount -lt 1) { Fail-PE 'At least the PE entry point must have unwind metadata.' }
if ($stackProbeHelperRva -lt [Int64]$previousEndRva -or $stackProbeHelperRva -ge ([Int64]$text.Rva + [Int64]$text.VirtualSize)) { Fail-PE 'Stack-probe helper is not located after the managed function ranges inside .text.' }

# The private x64 stack-probe helper is a leaf routine. It preserves RAX,
# register arguments, nonvolatile registers, and RSP; only R10/R11 and flags
# are volatile. Validate every opcode and rel32 target in its page-walk loop.
$probeHelperOffset = Convert-RvaToOffset -Rva ([UInt64]$stackProbeHelperRva) -Size 63 -Sections $sections.ToArray() -FileSize $bytes.Length
$helperPatterns = @(
    [pscustomobject]@{ Offset = 0; Bytes = [byte[]]@(0x49, 0x89, 0xE2) },
    [pscustomobject]@{ Offset = 3; Bytes = [byte[]]@(0x49, 0x89, 0xC3) },
    [pscustomobject]@{ Offset = 6; Bytes = [byte[]]@(0x49, 0x83, 0xEB, 0x08) },
    [pscustomobject]@{ Offset = 10; Bytes = $stackProbeCompare },
    [pscustomobject]@{ Offset = 17; Bytes = [byte[]]@(0x0F, 0x82) },
    [pscustomobject]@{ Offset = 23; Bytes = $stackProbeSubPointer },
    [pscustomobject]@{ Offset = 30; Bytes = $stackProbeTouch },
    [pscustomobject]@{ Offset = 34; Bytes = $stackProbeSubRemaining },
    [pscustomobject]@{ Offset = 41; Bytes = [byte[]]@(0xE9) },
    [pscustomobject]@{ Offset = 46; Bytes = [byte[]]@(0x4D, 0x85, 0xDB) },
    [pscustomobject]@{ Offset = 49; Bytes = [byte[]]@(0x0F, 0x84) },
    [pscustomobject]@{ Offset = 55; Bytes = $stackProbeSubTail },
    [pscustomobject]@{ Offset = 58; Bytes = $stackProbeTouch },
    [pscustomobject]@{ Offset = 62; Bytes = [byte[]]@(0xC3) }
)
foreach ($pattern in $helperPatterns) {
    for ($byteIndex = 0; $byteIndex -lt $pattern.Bytes.Length; $byteIndex++) {
        if ($bytes[$probeHelperOffset + $pattern.Offset + $byteIndex] -ne $pattern.Bytes[$byteIndex]) { Fail-PE 'Private stack-probe helper instruction sequence is malformed.' }
    }
}
$probeBelowDisp = [BitConverter]::ToInt32($bytes, $probeHelperOffset + 19)
$probeBelowTarget = 23 + $probeBelowDisp
$probeLoopDisp = [BitConverter]::ToInt32($bytes, $probeHelperOffset + 42)
$probeLoopTarget = 46 + $probeLoopDisp
$probeDoneDisp = [BitConverter]::ToInt32($bytes, $probeHelperOffset + 51)
$probeDoneTarget = 55 + $probeDoneDisp
if ($probeBelowTarget -ne 46 -or $probeLoopTarget -ne 10 -or $probeDoneTarget -ne 62) { Fail-PE 'Private stack-probe helper branch fixups do not target the page loop, tail probe, and return correctly.' }

if ($runtimeFunctionCount -lt 1) { Fail-PE 'At least the PE entry point must have unwind metadata.' }

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
    if ($nameRva -eq 0 -or $firstThunk -eq 0) {
        Fail-PE ("Import descriptor index {0} has missing fields: OFT=0x{1:X8}, NameRva=0x{2:X8}, FirstThunk=0x{3:X8}, descriptorOffset=0x{4:X}." -f $descriptorIndex, $oft, $nameRva, $firstThunk, ($descriptorIndex * 20))
    }
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
if ($foundDlls.Count -lt 5) { Fail-PE 'Expected five Windows system DLL import descriptors.' }
foreach ($dll in @('KERNEL32.dll', 'USER32.dll', 'D3D11.dll', 'DXGI.dll', 'BCRYPT.dll', 'USERENV.dll', 'ADVAPI32.dll')) { if (-not $foundDlls.Contains($dll)) { Fail-PE "Missing required DLL '$dll'." } }
foreach ($api in @('GetStdHandle', 'WriteFile', 'ExitProcess', 'wsprintfA', 'CreateFileA', 'GetFileSizeEx', 'ReadFile', 'CloseHandle', 'GetModuleHandleA', 'CreateThread', 'WaitForSingleObject', 'CreateMutexA', 'ReleaseMutex', 'CreateWindowExA', 'ShowWindow', 'UpdateWindow', 'PeekMessageA', 'TranslateMessage', 'DispatchMessageA', 'DestroyWindow', 'D3D11CreateDeviceAndSwapChain', 'CreateDXGIFactory', 'QueryPerformanceCounter', 'QueryPerformanceFrequency', 'IsWindow', 'GetSystemDirectoryA', 'GetCurrentDirectoryA', 'CreateProcessA', 'CreateJobObjectA', 'SetInformationJobObject', 'AssignProcessToJobObject', 'ResumeThread', 'TerminateJobObject', 'GetExitCodeProcess', 'TerminateProcess', 'GetFileAttributesA', 'VirtualAlloc', 'VirtualFree', 'BCryptOpenAlgorithmProvider', 'BCryptHash', 'BCryptCloseAlgorithmProvider', 'GetFileInformationByHandle', 'GetModuleFileNameA', 'SetCurrentDirectoryA', 'CreatePipe', 'SetHandleInformation', 'PeekNamedPipe', 'InitializeProcThreadAttributeList', 'UpdateProcThreadAttribute', 'DeleteProcThreadAttributeList', 'GetLastError', 'CreateAppContainerProfile', 'DeriveAppContainerSidFromAppContainerName', 'GetNamedSecurityInfoA', 'SetEntriesInAclA', 'SetNamedSecurityInfoA', 'FreeSid', 'OpenProcessToken', 'CreateRestrictedToken', 'CreateProcessAsUserA', 'GetFullPathNameA')) {
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

Write-Host ("PE verifier: PASS - AMD64 PE32+, 6 sections, {0} DLLs, {1} APIs, x64 unwind and stack probing verified." -f $foundDlls.Count, $foundImports.Count) -ForegroundColor Green
