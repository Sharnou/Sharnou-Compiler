Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-SharnouNativeInteropModule {
    param([string] $Name = 'Sharnou.DevAgent.NativeInterop')
    $assemblyName = New-Object System.Reflection.AssemblyName($Name + '.' + [Guid]::NewGuid().ToString('N'))
    $assemblyBuilder = [AppDomain]::CurrentDomain.DefineDynamicAssembly(
        $assemblyName,
        [System.Reflection.Emit.AssemblyBuilderAccess]::Run
    )
    return $assemblyBuilder.DefineDynamicModule($Name)
}

function New-SharnouRuntimeStructTypes {
    param(
        [System.Reflection.Emit.ModuleBuilder] $Module,
        [object[]] $StructureManifest
    )
    $typeMap = @{
        DWORD = [UInt32]
        WORD = [UInt16]
        PTR = [IntPtr]
        PTRSIZE = [UIntPtr]
        I64 = [Int64]
        U64 = [UInt64]
    }
    $createdTypes = @{}
    foreach ($structure in $StructureManifest) {
        $typeName = [string]$structure.name
        $attributes = [System.Reflection.TypeAttributes]::Public -bor
            [System.Reflection.TypeAttributes]::SequentialLayout -bor
            [System.Reflection.TypeAttributes]::Sealed
        $builder = $Module.DefineType(
            $typeName,
            $attributes,
            [ValueType],
            [System.Reflection.Emit.PackingSize]::Size8
        )
        foreach ($field in $structure.fields) {
            $fieldName = [string]$field[0]
            $fieldTypeName = [string]$field[1]
            if ($typeMap.ContainsKey($fieldTypeName)) {
                $fieldType = $typeMap[$fieldTypeName]
            } elseif ($createdTypes.ContainsKey($fieldTypeName)) {
                $fieldType = $createdTypes[$fieldTypeName]
            } else {
                throw "Native ABI manifest has an unresolved structure dependency: $typeName.$fieldName ($fieldTypeName)."
            }
            [void]$builder.DefineField(
                $fieldName,
                $fieldType,
                [System.Reflection.FieldAttributes]::Public
            )
        }
        $createdTypes[$typeName] = $builder.CreateType()
        $typeMap[$typeName] = $createdTypes[$typeName]
    }
    return $createdTypes
}

function Add-SharnouPInvokeMethod {
    param(
        [System.Reflection.Emit.TypeBuilder] $TypeBuilder,
        [string] $Name,
        [string] $DllName,
        [type] $ReturnType,
        [type[]] $ParameterTypes,
        [bool] $SetLastError = $false
    )
    $methodAttributes = [System.Reflection.MethodAttributes]::Public -bor
        [System.Reflection.MethodAttributes]::Static -bor
        [System.Reflection.MethodAttributes]::PinvokeImpl
    $method = $TypeBuilder.DefinePInvokeMethod(
        $Name,
        $DllName,
        $Name,
        $methodAttributes,
        [System.Reflection.CallingConventions]::Standard,
        $ReturnType,
        $ParameterTypes,
        [System.Runtime.InteropServices.CallingConvention]::Winapi,
        [System.Runtime.InteropServices.CharSet]::Unicode
    )
    $method.SetImplementationFlags([System.Reflection.MethodImplAttributes]::PreserveSig)
    if ($SetLastError) {
        $attributeType = [System.Runtime.InteropServices.DllImportAttribute]
        $constructor = $attributeType.GetConstructor([type[]]@([string]))
        $setLastErrorField = $attributeType.GetField('SetLastError')
        $exactSpellingField = $attributeType.GetField('ExactSpelling')
        $customAttribute = [System.Reflection.Emit.CustomAttributeBuilder]::new(
            $constructor,
            [object[]]@($DllName),
            [System.Reflection.FieldInfo[]]@($setLastErrorField,$exactSpellingField),
            [object[]]@($true,$true)
        )
        $method.SetCustomAttribute($customAttribute)
    }
    return $method
}

function New-SharnouNativeApiType {
    param(
        [System.Reflection.Emit.ModuleBuilder] $Module,
        [object[]] $ApiManifest
    )
    $attributes = [System.Reflection.TypeAttributes]::Public -bor
        [System.Reflection.TypeAttributes]::Abstract -bor
        [System.Reflection.TypeAttributes]::Sealed
    $builder = $Module.DefineType('SharnouNativeWin32Api', $attributes)
    foreach ($api in $ApiManifest) {
        $parameterTypes = New-Object 'System.Collections.Generic.List[Type]'
        foreach ($parameterName in $api.parameters) {
            switch ([string]$parameterName) {
                'VOID' { }
                'BOOL' { $parameterTypes.Add([Boolean]) }
                'HRESULT' { $parameterTypes.Add([Int32]) }
                'DWORD' { $parameterTypes.Add([UInt32]) }
                'DWORD_PTR' { $parameterTypes.Add([UIntPtr]) }
                'SIZE_T' { $parameterTypes.Add([UIntPtr]) }
                'HANDLE' { $parameterTypes.Add([IntPtr]) }
                'HWND' { $parameterTypes.Add([IntPtr]) }
                'LPVOID' { $parameterTypes.Add([IntPtr]) }
                'PVOID' { $parameterTypes.Add([IntPtr]) }
                'LPCVOID' { $parameterTypes.Add([IntPtr]) }
                'LPWSTR' { $parameterTypes.Add([IntPtr]) }
                'LPCWSTR' { $parameterTypes.Add([IntPtr]) }
                'PCWSTR' { $parameterTypes.Add([IntPtr]) }
                'PSID' { $parameterTypes.Add([IntPtr]) }
                'PSID_AND_ATTRIBUTES' { $parameterTypes.Add([IntPtr]) }
                'PSID*' { $parameterTypes.Add([IntPtr]) }
                'PHANDLE' { $parameterTypes.Add([IntPtr]) }
                'PDWORD' { $parameterTypes.Add([IntPtr]) }
                'PSIZE_T' { $parameterTypes.Add([IntPtr]) }
                'LPSECURITY_ATTRIBUTES' { $parameterTypes.Add([IntPtr]) }
                'LPSTARTUPINFOW' { $parameterTypes.Add([IntPtr]) }
                'LPPROCESS_INFORMATION' { $parameterTypes.Add([IntPtr]) }
                'LPPROC_THREAD_ATTRIBUTE_LIST' { $parameterTypes.Add([IntPtr]) }
                'TOKEN_INFORMATION_CLASS' { $parameterTypes.Add([Int32]) }
                default { throw "Unsupported native API parameter type '$parameterName' for $($api.name)." }
            }
        }
        $returnType = switch ([string]$api.returnType) {
            'BOOL' { [Boolean] }
            'HRESULT' { [Int32] }
            'DWORD' { [UInt32] }
            'HANDLE' { [IntPtr] }
            'PUCHAR' { [IntPtr] }
            'PDWORD' { [IntPtr] }
            'PVOID' { [IntPtr] }
            'VOID' { [Void] }
            default { throw "Unsupported native API return type '$($api.returnType)' for $($api.name)." }
        }
        [void](Add-SharnouPInvokeMethod -TypeBuilder $builder -Name ([string]$api.name) -DllName ([string]$api.dll) -ReturnType $returnType -ParameterTypes $parameterTypes.ToArray() -SetLastError ([bool]$api.setLastError))
    }
    return $builder.CreateType()
}

function Invoke-SharnouNativeApi {
    param(
        [type] $ApiType,
        [string] $Name,
        [object[]] $Arguments
    )
    $method = $ApiType.GetMethod($Name)
    if ($null -eq $method) { throw "Native API entrypoint was not declared: $Name." }
    return $method.Invoke($null, $Arguments)
}

function New-SharnouTrackedBuffer {
    param(
        [int] $ByteCount,
        [System.Collections.Generic.List[IntPtr]] $Allocations
    )
    if ($ByteCount -lt 1 -or $ByteCount -gt 65536) { throw "Unmanaged allocation size is outside the approved probe bound: $ByteCount." }
    $pointer = [Runtime.InteropServices.Marshal]::AllocHGlobal($ByteCount)
    if ($pointer -eq [IntPtr]::Zero) { throw "AllocHGlobal returned NULL for $ByteCount bytes." }
    $zeroes = [byte[]]::new($ByteCount)
    [Runtime.InteropServices.Marshal]::Copy($zeroes, 0, $pointer, $ByteCount)
    $Allocations.Add($pointer)
    return $pointer
}

function New-SharnouTrackedUnicodeString {
    param(
        [string] $Value,
        [System.Collections.Generic.List[IntPtr]] $Allocations
    )
    $pointer = [Runtime.InteropServices.Marshal]::StringToHGlobalUni($Value)
    if ($pointer -eq [IntPtr]::Zero) { throw 'StringToHGlobalUni returned NULL.' }
    $Allocations.Add($pointer)
    return $pointer
}


function Get-SharnouMarshalSize {
    param([type] $NativeType)
    $method = [Runtime.InteropServices.Marshal].GetMethod('SizeOf',[type[]]@([type]))
    if ($null -eq $method) { throw 'Marshal.SizeOf(Type) overload is unavailable.' }
    return [int]$method.Invoke($null,[object[]]@($NativeType))
}

function Get-SharnouMarshalOffset {
    param([type] $NativeType,[string] $FieldName)
    $method = [Runtime.InteropServices.Marshal].GetMethod('OffsetOf',[type[]]@([type],[string]))
    if ($null -eq $method) { throw 'Marshal.OffsetOf(Type,String) overload is unavailable.' }
    return [int64]$method.Invoke($null,[object[]]@($NativeType,$FieldName)).ToInt64()
}


function New-SharnouTrackedEnvironmentBlock {
    param(
        [string[]] $Entries,
        [System.Collections.Generic.List[IntPtr]] $Allocations
    )
    if ($Entries.Count -lt 1 -or $Entries.Count -gt 64) {
        throw 'Environment block entry count is outside the approved probe bounds.'
    }
    $ordered = [string[]]$Entries.Clone()
    [Array]::Sort($ordered,[StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $ordered) {
        if ($entry -notmatch '^[^=]+=') { throw "Invalid environment block entry: $entry" }
        if ($entry.IndexOf([char]0) -ge 0) { throw 'Environment block entry contains an embedded NUL.' }
    }
    $blockText = ($ordered -join [char]0) + [char]0 + [char]0
    $bytes = [Text.Encoding]::Unicode.GetBytes($blockText)
    if ($bytes.Length -lt 4 -or $bytes.Length -gt 32768 -or $bytes[$bytes.Length-1] -ne 0 -or $bytes[$bytes.Length-2] -ne 0 -or $bytes[$bytes.Length-3] -ne 0 -or $bytes[$bytes.Length-4] -ne 0) {
        throw 'Environment block is not a bounded UTF-16 double-NUL-terminated block.'
    }
    $pointer = [Runtime.InteropServices.Marshal]::AllocHGlobal($bytes.Length)
    if ($pointer -eq [IntPtr]::Zero) { throw 'AllocHGlobal returned NULL for the environment block.' }
    [Runtime.InteropServices.Marshal]::Copy($bytes,0,$pointer,$bytes.Length)
    $Allocations.Add($pointer)
    return $pointer
}
