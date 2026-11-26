[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'DevAgentBroker\NativeInterop.ps1')

function Assert-NativeAbi {
    param([bool] $Condition,[string] $Message)
    if (-not $Condition) { throw $Message }
}

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$manifestPath = Join-Path $PSScriptRoot 'DevAgentBroker\native-abi-manifest.json'
if (-not [Environment]::Is64BitOperatingSystem -or -not [Environment]::Is64BitProcess) {
    throw 'The native ABI runtime probe requires 64-bit Windows PowerShell on a 64-bit Windows OS.'
}
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'Native ABI manifest is missing.' }

$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([int]$manifest.schemaVersion -ne 1) { throw 'Unsupported native ABI manifest schema.' }
if ([int]$manifest.target.pointerSize -ne 8 -or [int]$manifest.target.defaultPacking -ne 8) {
    throw 'The manifest does not describe the required Windows x64 / pack-8 ABI.'
}
if ([IntPtr]::Size -ne 8 -or [UIntPtr]::Size -ne 8) { throw 'Managed native pointer width is not eight bytes.' }

$module = New-SharnouNativeInteropModule -Name 'Sharnou.DevAgent.NativeAbiRuntime'
$types = New-SharnouRuntimeStructTypes -Module $module -StructureManifest @($manifest.structureLayouts)
$sizeChecks = 0
$offsetChecks = 0
foreach ($structure in $manifest.structureLayouts) {
    $name = [string]$structure.name
    $type = $types[$name]
    if ($null -eq $type) { throw "Runtime structure type was not emitted: $name." }
    $actualSize = [Runtime.InteropServices.Marshal]::SizeOf($type)
    $expectedSize = [int]$structure.size
    if ($actualSize -ne $expectedSize) {
        throw ("Marshal.SizeOf mismatch for {0}: expected {1}, actual {2}." -f $name,$expectedSize,$actualSize)
    }
    $sizeChecks++
    foreach ($field in $structure.fields) {
        $fieldName = [string]$field[0]
        $expectedOffset = [Int64]$field[2]
        $actualOffset = [Runtime.InteropServices.Marshal]::OffsetOf($type,$fieldName).ToInt64()
        if ($actualOffset -ne $expectedOffset) {
            throw ("Marshal.OffsetOf mismatch for {0}.{1}: expected {2}, actual {3}." -f $name,$fieldName,$expectedOffset,$actualOffset)
        }
        $offsetChecks++
    }
}

# These three structures are consumed directly by the Phase 2B.2 API calls.
if ([Runtime.InteropServices.Marshal]::SizeOf($types['SECURITY_CAPABILITIES']) -ne 24) {
    throw 'SECURITY_CAPABILITIES runtime size is not 24 bytes.'
}
if ([Runtime.InteropServices.Marshal]::OffsetOf($types['STARTUPINFOEXW'],'lpAttributeList').ToInt64() -ne 104) {
    throw 'STARTUPINFOEXW.lpAttributeList runtime offset is not 104.'
}
if ([Runtime.InteropServices.Marshal]::SizeOf($types['PROCESS_INFORMATION']) -ne 24) {
    throw 'PROCESS_INFORMATION runtime size is not 24 bytes.'
}

Write-Host 'Windows x64 interop ABI runtime probe: PASS'
Write-Host ("Pointer width: {0} bytes" -f [IntPtr]::Size)
Write-Host ("Runtime structure sizes checked: {0}" -f $sizeChecks)
Write-Host ("Runtime field offsets checked: {0}" -f $offsetChecks)
Write-Host 'Critical API layouts: SECURITY_CAPABILITIES=24, STARTUPINFOEXW=112, PROCESS_INFORMATION=24'
Write-Host 'Measurement source: CLR unmanaged interop marshaler at runtime; no C/C++ compiler or external toolchain was invoked.'
