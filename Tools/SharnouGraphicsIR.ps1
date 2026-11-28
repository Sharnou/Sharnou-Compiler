[CmdletBinding()]
param(
    [ValidateSet('None', 'Verify', 'Canonicalize')]
    [string] $Action = 'None',
    [string] $InputPath,
    [string] $OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Throw-Sgir {
    param([Parameter(Mandatory = $true)][string] $Code, [Parameter(Mandatory = $true)][string] $Message)
    throw ("SGIR-{0}: {1}" -f $Code, $Message)
}

function Get-SgirPropertyNames {
    param([Parameter(Mandatory = $true)][object] $Value)
    if ($Value -isnot [System.Management.Automation.PSCustomObject]) {
        Throw-Sgir 'S001' 'Expected a JSON object.'
    }
    return @($Value.PSObject.Properties | ForEach-Object { [string]$_.Name })
}

function Assert-SgirObject {
    param(
        [Parameter(Mandatory = $true)][object] $Value,
        [Parameter(Mandatory = $true)][string[]] $Required,
        [Parameter(Mandatory = $true)][string[]] $Allowed,
        [Parameter(Mandatory = $true)][string] $Where
    )
    $names = @(Get-SgirPropertyNames -Value $Value)
    foreach ($name in $Required) {
        if ($names -cnotcontains $name) {
            Throw-Sgir 'S003' ("{0} is missing required property '{1}'." -f $Where, $name)
        }
    }
    foreach ($name in $names) {
        if ($Allowed -cnotcontains $name) {
            Throw-Sgir 'S004' ("{0} contains unknown property '{1}'." -f $Where, $name)
        }
    }
}

function Get-SgirValue {
    param([Parameter(Mandatory = $true)][object] $Object, [Parameter(Mandatory = $true)][string] $Name)
    $property = $Object.PSObject.Properties | Where-Object { $_.Name -ceq $Name } | Select-Object -First 1
    if ($null -ceq $property) { return $null }
    return ,$property.Value
}

function Assert-SgirArray {
    param([object] $Value, [string] $Where)
    if ($null -eq $Value -or $Value -isnot [System.Array]) {
        Throw-Sgir 'S005' ("{0} must be an array." -f $Where)
    }
    foreach ($item in $Value) {
        if ($null -eq $item) { Throw-Sgir 'S006' ("{0} must not contain null values." -f $Where) }
    }
}

function Assert-SgirString {
    param([object] $Value, [string] $Where)
    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        Throw-Sgir 'S007' ("{0} must be a non-empty string." -f $Where)
    }
}

function Assert-SgirInteger {
    param([object] $Value, [string] $Where, [long] $Minimum = 0, [long] $Maximum = 2147483647)
    if ($Value -isnot [byte] -and $Value -isnot [int16] -and $Value -isnot [int32] -and $Value -isnot [int64]) {
        Throw-Sgir 'S008' ("{0} must be an integer; floating-point JSON numbers are forbidden in SGIR/1." -f $Where)
    }
    $number = [long]$Value
    if ($number -lt $Minimum -or $number -gt $Maximum) {
        Throw-Sgir 'S009' ("{0} is outside the allowed range [{1}, {2}]." -f $Where, $Minimum, $Maximum)
    }
}

function Assert-SgirId {
    param([object] $Value, [string] $Where)
    Assert-SgirString -Value $Value -Where $Where
    if ([string]$Value -cnotmatch '^[A-Za-z_][A-Za-z0-9_.-]{0,127}$') {
        Throw-Sgir 'S010' ("{0} is not a valid SGIR identifier." -f $Where)
    }
}

function Assert-SgirUniqueStrings {
    param([object[]] $Values, [string] $Where)
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($value in $Values) {
        Assert-SgirString -Value $value -Where $Where
        if (-not $set.Add([string]$value)) {
            Throw-Sgir 'S011' ("{0} contains duplicate value '{1}'." -f $Where, $value)
        }
    }
}

function Assert-SgirSortedStrings {
    param([object[]] $Values, [string] $Where)
    $previous = $null
    foreach ($value in $Values) {
        if ($null -cne $previous -and [System.StringComparer]::Ordinal.Compare([string]$previous, [string]$value) -ge 0) {
            Throw-Sgir 'S012' ("{0} must be sorted in strictly increasing ordinal order." -f $Where)
        }
        $previous = [string]$value
    }
}

function Assert-NoDuplicateSgirJsonKeys {
    param([Parameter(Mandatory = $true)][string] $Json)

    $stack = New-Object 'System.Collections.Generic.Stack[object]'
    $index = 0
    while ($index -lt $Json.Length) {
        $ch = $Json[$index]
        if ($ch -eq '"') {
            $start = $index
            $index++
            $escaped = $false
            while ($index -lt $Json.Length) {
                $current = $Json[$index]
                if ($escaped) {
                    $escaped = $false
                } elseif ($current -eq '\') {
                    $escaped = $true
                } elseif ($current -eq '"') {
                    break
                }
                $index++
            }
            if ($index -ge $Json.Length) { break }
            $end = $index
            $after = $end + 1
            while ($after -lt $Json.Length -and ($Json[$after] -eq ' ' -or $Json[$after] -eq [char]9 -or $Json[$after] -eq [char]13 -or $Json[$after] -eq [char]10)) {
                $after++
            }
            if ($after -lt $Json.Length -and $Json[$after] -eq ':' -and $stack.Count -gt 0) {
                $token = $Json.Substring($start, $end - $start + 1)
                try { $key = [string]($token | ConvertFrom-Json -ErrorAction Stop) }
                catch { Throw-Sgir 'J001' 'A JSON property name could not be decoded.' }
                $keys = $stack.Peek()
                if (-not $keys.Add($key)) {
                    Throw-Sgir 'J002' ("Duplicate JSON property '{0}' is forbidden." -f $key)
                }
            }
            $index = $end
        } elseif ($ch -eq '{') {
            $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
            $stack.Push($set)
        } elseif ($ch -eq '}') {
            if ($stack.Count -gt 0) { [void]$stack.Pop() }
        }
        $index++
    }
}

function ConvertFrom-SgirJsonText {
    param([Parameter(Mandatory = $true)][string] $Json)
    if ($Json.Length -eq 0 -or $Json.Length -gt 4194304) {
        Throw-Sgir 'J003' 'The SGIR JSON document must contain 1 to 4,194,304 UTF-16 code units.'
    }
    Assert-NoDuplicateSgirJsonKeys -Json $Json
    try {
        $document = ConvertFrom-Json -InputObject $Json -ErrorAction Stop
    } catch {
        Throw-Sgir 'J004' ("Invalid JSON: {0}" -f $_.Exception.Message)
    }
    if ($document -isnot [System.Management.Automation.PSCustomObject]) {
        Throw-Sgir 'S001' 'The SGIR root must be a JSON object.'
    }
    return $document
}

function ConvertTo-SgirJsonString {
    param([Parameter(Mandatory = $true)][string] $Value)
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    for ($i = 0; $i -lt $Value.Length; $i++) {
        $code = [int][char]$Value[$i]
        switch ($code) {
            34 { [void]$builder.Append('\"') }
            92 { [void]$builder.Append('\\') }
            8  { [void]$builder.Append('\b') }
            9  { [void]$builder.Append('\t') }
            10 { [void]$builder.Append('\n') }
            12 { [void]$builder.Append('\f') }
            13 { [void]$builder.Append('\r') }
            default {
                if ($code -lt 32 -or $code -gt 126) {
                    [void]$builder.Append(('\u{0:X4}' -f $code))
                } else {
                    [void]$builder.Append([char]$code)
                }
            }
        }
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function ConvertTo-SgirCanonicalValue {
    param([AllowNull()][object] $Value)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [string]) { return (ConvertTo-SgirJsonString -Value $Value) }
    if ($Value -is [bool]) {
        if ($Value) { return 'true' }
        return 'false'
    }
    if ($Value -is [byte] -or $Value -is [int16] -or $Value -is [int32] -or $Value -is [int64]) {
        return ([Convert]::ToString($Value, [Globalization.CultureInfo]::InvariantCulture))
    }
    if ($Value -is [System.Array]) {
        $parts = New-Object 'System.Collections.Generic.List[string]'
        foreach ($item in $Value) { $parts.Add((ConvertTo-SgirCanonicalValue -Value $item)) }
        return ('[' + [string]::Join(',', $parts.ToArray()) + ']')
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $names = @($Value.PSObject.Properties | ForEach-Object { [string]$_.Name })
        [Array]::Sort($names, [System.StringComparer]::Ordinal)
        $parts = New-Object 'System.Collections.Generic.List[string]'
        foreach ($name in $names) {
            $item = Get-SgirValue -Object $Value -Name $name
            $parts.Add(((ConvertTo-SgirJsonString -Value $name) + ':' + (ConvertTo-SgirCanonicalValue -Value $item)))
        }
        return ('{' + [string]::Join(',', $parts.ToArray()) + '}')
    }
    Throw-Sgir 'J005' ("Unsupported value type in canonical SGIR serializer: {0}." -f $Value.GetType().FullName)
}

function ConvertTo-SgirCanonicalJson {
    param([Parameter(Mandatory = $true)][object] $Document)
    return (ConvertTo-SgirCanonicalValue -Value $Document)
}

function Get-SgirCanonicalHash {
    param([Parameter(Mandatory = $true)][object] $Document)
    $json = ConvertTo-SgirCanonicalJson -Document $Document
    $encoding = [System.Text.UTF8Encoding]::new($false, $true)
    $bytes = $encoding.GetBytes($json)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $digest = $sha.ComputeHash($bytes)
        return ([BitConverter]::ToString($digest).Replace('-', '').ToLowerInvariant())
    } finally {
        $sha.Dispose()
    }
}

function Get-SgirTypeKind {
    param([string] $TypeId, [System.Collections.IDictionary] $TypeMap)
    if ($TypeId -cin @('bool', 'i32', 'u32', 'f32')) { return 'scalar' }
    if (-not $TypeMap.Contains($TypeId)) { Throw-Sgir 'T001' ("Unknown type '{0}'." -f $TypeId) }
    return [string](Get-SgirValue $TypeMap[$TypeId] 'kind')
}

function Assert-SgirTypeReference {
    param([string] $TypeId, [System.Collections.IDictionary] $TypeMap, [string] $Where)
    Assert-SgirString -Value $TypeId -Where $Where
    if ($TypeId -cnotin @('void', 'bool', 'i32', 'u32', 'f32') -and -not $TypeMap.Contains($TypeId)) {
        Throw-Sgir 'T001' ("{0} references unknown type '{1}'." -f $Where, $TypeId)
    }
}


function Visit-SgirTypeGraph {
    param([string] $TypeId, [System.Collections.IDictionary] $TypeMap, [System.Collections.IDictionary] $State)
    if (-not $TypeMap.Contains($TypeId)) { return }
    if ($State.Contains($TypeId) -and $State[$TypeId] -eq 1) {
        Throw-Sgir 'T010' ("Recursive aggregate type cycle reaches '{0}'." -f $TypeId)
    }
    if ($State.Contains($TypeId) -and $State[$TypeId] -eq 2) { return }
    $State[$TypeId] = 1
    $declaration = $TypeMap[$TypeId]
    $kind = [string](Get-SgirValue $declaration 'kind')
    if ($kind -ceq 'struct') {
        foreach ($field in (Get-SgirValue $declaration 'fields')) {
            Visit-SgirTypeGraph -TypeId ([string](Get-SgirValue $field 'type')) -TypeMap $TypeMap -State $State
        }
    } else {
        Visit-SgirTypeGraph -TypeId ([string](Get-SgirValue $declaration 'elementType')) -TypeMap $TypeMap -State $State
    }
    $State[$TypeId] = 2
}

function Assert-SgirAcyclicTypeGraph {
    param([System.Collections.IDictionary] $TypeMap)
    $state = New-Object 'System.Collections.Generic.Dictionary[string,int]' ([System.StringComparer]::Ordinal)
    foreach ($typeId in $TypeMap.Keys) {
        Visit-SgirTypeGraph -TypeId ([string]$typeId) -TypeMap $TypeMap -State $state
    }
}

function Assert-SgirModule {
    param([Parameter(Mandatory = $true)][object] $Document)

    Assert-SgirObject -Value $Document -Where 'module' -Required @('schema','moduleId','target','capabilities','types','resources','entryPoints','functions') -Allowed @('schema','moduleId','target','capabilities','types','resources','entryPoints','functions')
    if ((Get-SgirValue $Document 'schema') -cne 'SGIR/1') { Throw-Sgir 'S002' 'Only schema SGIR/1 is supported.' }
    $moduleId = Get-SgirValue $Document 'moduleId'
    Assert-SgirString $moduleId 'module.moduleId'
    if ($moduleId -cnotmatch '^[a-z0-9][a-z0-9._-]{0,127}$') { Throw-Sgir 'S013' 'module.moduleId must use lowercase ASCII package-name characters.' }

    $target = Get-SgirValue $Document 'target'
    Assert-SgirObject -Value $target -Where 'module.target' -Required @('api','featureLevel','shaderModel') -Allowed @('api','featureLevel','shaderModel')
    if ((Get-SgirValue $target 'api') -cne 'd3d11' -or (Get-SgirValue $target 'featureLevel') -cne '11_0' -or (Get-SgirValue $target 'shaderModel') -cne '5_0') {
        Throw-Sgir 'C001' 'SGIR/1 baseline target is d3d11 / feature level 11_0 / shader model 5_0; other targets require a later schema profile.'
    }

    $capabilities = Get-SgirValue $Document 'capabilities'
    Assert-SgirArray $capabilities 'module.capabilities'
    $capabilityNames = @($capabilities | ForEach-Object { [string]$_ })
    Assert-SgirUniqueStrings $capabilityNames 'module.capabilities'
    $knownCapabilities = @('shader.pixel','shader.vertex','texture.sample.implicit_lod')
    foreach ($capability in $capabilityNames) {
        if ($knownCapabilities -cnotcontains $capability) { Throw-Sgir 'C002' ("Unknown capability '{0}'." -f $capability) }
    }
    Assert-SgirSortedStrings $capabilityNames 'module.capabilities'

    $types = Get-SgirValue $Document 'types'
    Assert-SgirArray $types 'module.types'
    $typeMap = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)
    foreach ($type in $types) {
        $kind = [string](Get-SgirValue $type 'kind')
        switch -CaseSensitive ($kind) {
            'vector' {
                Assert-SgirObject $type @('id','kind','elementType','lanes') @('id','kind','elementType','lanes') 'type.vector'
                Assert-SgirId (Get-SgirValue $type 'id') 'type.id'
                Assert-SgirInteger (Get-SgirValue $type 'lanes') 'type.lanes' 2 4
                if ((Get-SgirValue $type 'elementType') -cnotin @('f32','i32','u32')) { Throw-Sgir 'T002' 'Vector elementType must be f32, i32 or u32.' }
            }
            'matrix' {
                Assert-SgirObject $type @('id','kind','elementType','rows','columns','major') @('id','kind','elementType','rows','columns','major') 'type.matrix'
                Assert-SgirId (Get-SgirValue $type 'id') 'type.id'
                Assert-SgirInteger (Get-SgirValue $type 'rows') 'type.rows' 2 4
                Assert-SgirInteger (Get-SgirValue $type 'columns') 'type.columns' 2 4
                if ((Get-SgirValue $type 'elementType') -cne 'f32') { Throw-Sgir 'T003' 'Matrix elementType must be f32 in SGIR/1.' }
                if ((Get-SgirValue $type 'major') -cnotin @('row','column')) { Throw-Sgir 'T004' 'Matrix major must be row or column.' }
            }
            'struct' {
                Assert-SgirObject $type @('id','kind','fields') @('id','kind','fields') 'type.struct'
                Assert-SgirId (Get-SgirValue $type 'id') 'type.id'
                $fields = Get-SgirValue $type 'fields'
                Assert-SgirArray $fields 'type.fields'
                $fieldIndex = 0
                $fieldNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
                foreach ($field in $fields) {
                    Assert-SgirObject $field @('name','type','index') @('name','type','index') 'type.field'
                    Assert-SgirString (Get-SgirValue $field 'name') 'field.name'
                    if (-not $fieldNames.Add([string](Get-SgirValue $field 'name'))) { Throw-Sgir 'T005' 'Struct field names must be unique.' }
                    Assert-SgirInteger (Get-SgirValue $field 'index') 'field.index' 0 65535
                    if ((Get-SgirValue $field 'index') -ne $fieldIndex) { Throw-Sgir 'T006' 'Struct field indexes must be contiguous and zero-based.' }
                    $fieldIndex++
                }
            }
            'array' {
                Assert-SgirObject $type @('id','kind','elementType','count') @('id','kind','elementType','count') 'type.array'
                Assert-SgirId (Get-SgirValue $type 'id') 'type.id'
                Assert-SgirInteger (Get-SgirValue $type 'count') 'type.count' 1 65536
            }
            default { Throw-Sgir 'T007' ("Unsupported SGIR/1 type kind '{0}'." -f $kind) }
        }
        $id = [string](Get-SgirValue $type 'id')
        if ($id -in @('void','bool','i32','u32','f32') -or $typeMap.ContainsKey($id)) { Throw-Sgir 'T008' ("Duplicate or reserved type ID '{0}'." -f $id) }
        $typeMap.Add($id, $type)
    }
    $typeIds = @($types | ForEach-Object { [string](Get-SgirValue $_ 'id') })
    Assert-SgirSortedStrings $typeIds 'module.types'
    foreach ($type in $types) {
        $kind = [string](Get-SgirValue $type 'kind')
        if ($kind -ceq 'vector' -or $kind -ceq 'matrix' -or $kind -ceq 'array') {
            Assert-SgirTypeReference ([string](Get-SgirValue $type 'elementType')) $typeMap 'type.elementType'
            if ($kind -ceq 'array' -and (Get-SgirValue $type 'elementType') -ceq 'void') { Throw-Sgir 'T009' 'Array element type cannot be void.' }
        } elseif ($kind -ceq 'struct') {
            $fields = Get-SgirValue $type 'fields'
            if ($fields.Count -eq 0) { Throw-Sgir 'T009' 'Struct types must contain at least one field.' }
            foreach ($field in $fields) {
                Assert-SgirTypeReference ([string](Get-SgirValue $field 'type')) $typeMap 'type.field.type'
                if ((Get-SgirValue $field 'type') -ceq 'void') { Throw-Sgir 'T009' 'Struct fields cannot have void type.' }
            }
        }
    }
    Assert-SgirAcyclicTypeGraph -TypeMap $typeMap

    $resources = Get-SgirValue $Document 'resources'
    Assert-SgirArray $resources 'module.resources'
    $resourceIds = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $bindings = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($resource in $resources) {
        $kind = [string](Get-SgirValue $resource 'kind')
        Assert-SgirObject $resource @('id','name','kind','set','binding','type','stages') @('id','name','kind','set','binding','type','stages') 'resource'
        Assert-SgirId (Get-SgirValue $resource 'id') 'resource.id'
        Assert-SgirString (Get-SgirValue $resource 'name') 'resource.name'
        if ($kind -cnotin @('texture2d','sampler','constant_buffer')) { Throw-Sgir 'R001' ("Unsupported resource kind '{0}'." -f $kind) }
        Assert-SgirInteger (Get-SgirValue $resource 'set') 'resource.set' 0 7
        Assert-SgirInteger (Get-SgirValue $resource 'binding') 'resource.binding' 0 127
        $key = '{0}:{1}' -f (Get-SgirValue $resource 'set'), (Get-SgirValue $resource 'binding')
        if (-not $bindings.Add($key)) { Throw-Sgir 'R002' ("Resource binding collision at set {0}, binding {1}." -f (Get-SgirValue $resource 'set'), (Get-SgirValue $resource 'binding')) }
        if (-not $resourceIds.Add([string](Get-SgirValue $resource 'id'))) { Throw-Sgir 'R003' 'Resource IDs must be unique.' }
        $resourceType = [string](Get-SgirValue $resource 'type')
        Assert-SgirTypeReference $resourceType $typeMap 'resource.type'
        if ($kind -eq 'constant_buffer') {
            if (-not $typeMap.ContainsKey($resourceType) -or (Get-SgirValue $typeMap[$resourceType] 'kind') -cne 'struct') { Throw-Sgir 'R004' 'A constant_buffer resource must reference a declared struct type.' }
        } elseif ($resourceType -cne 'void') {
            Throw-Sgir 'R005' 'Texture2D and sampler resources must use type void until resource object types are introduced.'
        }
        $stages = Get-SgirValue $resource 'stages'
        Assert-SgirArray $stages 'resource.stages'
        $stageNames = @($stages | ForEach-Object { [string]$_ })
        Assert-SgirUniqueStrings $stageNames 'resource.stages'
        if ($stageNames.Count -eq 0) { Throw-Sgir 'R006' 'A resource must be visible to at least one shader stage.' }
        foreach ($stageName in $stageNames) { if ($stageName -cnotin @('vertex','pixel')) { Throw-Sgir 'R007' ("Invalid resource stage '{0}'." -f $stageName) } }
        Assert-SgirSortedStrings $stageNames 'resource.stages'
    }
    $resourceIdArray = @($resources | ForEach-Object { [string](Get-SgirValue $_ 'id') })
    Assert-SgirSortedStrings $resourceIdArray 'module.resources'

    $entryPoints = Get-SgirValue $Document 'entryPoints'
    Assert-SgirArray $entryPoints 'module.entryPoints'
    if ($entryPoints.Count -eq 0) { Throw-Sgir 'E014' 'A shader module must declare at least one entry point.' }
    $entryNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $entryFunctionMap = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)
    $stagesPresent = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($entry in $entryPoints) {
        Assert-SgirObject $entry @('name','stage','function','inputs','outputs') @('name','stage','function','inputs','outputs') 'entryPoint'
        Assert-SgirId (Get-SgirValue $entry 'name') 'entryPoint.name'
        Assert-SgirId (Get-SgirValue $entry 'function') 'entryPoint.function'
        $name = [string](Get-SgirValue $entry 'name')
        $stage = [string](Get-SgirValue $entry 'stage')
        if ($stage -cnotin @('vertex','pixel')) { Throw-Sgir 'E001' ("Unsupported entry-point stage '{0}'." -f $stage) }
        if (-not $entryNames.Add($name)) { Throw-Sgir 'E002' ("Duplicate entry-point name '{0}'." -f $name) }
        if ($entryFunctionMap.ContainsKey([string](Get-SgirValue $entry 'function'))) { Throw-Sgir 'E003' 'An SGIR/1 function can be bound to only one entry point.' }
        $entryFunctionMap.Add([string](Get-SgirValue $entry 'function'), $entry)
        [void]$stagesPresent.Add($stage)

        foreach ($direction in @('inputs','outputs')) {
            $interfaces = Get-SgirValue $entry $direction
            Assert-SgirArray $interfaces ("entryPoint.{0}" -f $direction)
            $interfaceIds = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
            $locations = New-Object 'System.Collections.Generic.HashSet[int]'
            $semantics = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
            $lastLocation = -1
            foreach ($interface in $interfaces) {
                Assert-SgirObject $interface @('id','location','semantic','type','interpolation') @('id','location','semantic','type','interpolation') 'stageInterface'
                Assert-SgirId (Get-SgirValue $interface 'id') 'interface.id'
                Assert-SgirInteger (Get-SgirValue $interface 'location') 'interface.location' 0 31
                Assert-SgirString (Get-SgirValue $interface 'semantic') 'interface.semantic'
                Assert-SgirTypeReference ([string](Get-SgirValue $interface 'type')) $typeMap 'interface.type'
                if ((Get-SgirValue $interface 'type') -ceq 'void') { Throw-Sgir 'E004' 'Stage interface values cannot use void type.' }
                if ((Get-SgirValue $interface 'interpolation') -cnotin @('perspective','noperspective','flat')) { Throw-Sgir 'E005' 'Invalid interpolation mode.' }
                if (-not $interfaceIds.Add([string](Get-SgirValue $interface 'id'))) { Throw-Sgir 'E006' 'Interface IDs must be unique within a direction.' }
                if (-not $locations.Add([int](Get-SgirValue $interface 'location'))) { Throw-Sgir 'E007' 'Interface locations must be unique within a direction.' }
                if (-not $semantics.Add([string](Get-SgirValue $interface 'semantic'))) { Throw-Sgir 'E008' 'Interface semantics must be unique within a direction.' }
                $location = [int](Get-SgirValue $interface 'location')
                if ($location -le $lastLocation) { Throw-Sgir 'E009' ("entryPoint.{0} must be sorted by increasing location." -f $direction) }
                $lastLocation = $location
            }
        }
        if ($stage -eq 'vertex') {
            $positionOutputs = @((Get-SgirValue $entry 'outputs') | Where-Object { (Get-SgirValue $_ 'semantic') -ceq 'SV_Position' })
            if ($positionOutputs.Count -ne 1) { Throw-Sgir 'E010' 'A vertex entry point must declare exactly one SV_Position output.' }
        }
        if ($stage -eq 'pixel') {
            $targetOutputs = @((Get-SgirValue $entry 'outputs') | Where-Object { (Get-SgirValue $_ 'semantic') -ceq 'SV_Target0' })
            if ($targetOutputs.Count -lt 1) { Throw-Sgir 'E011' 'A pixel entry point must declare SV_Target0 output.' }
        }
    }
    $entryNameArray = @($entryPoints | ForEach-Object { [string](Get-SgirValue $_ 'name') })
    Assert-SgirSortedStrings $entryNameArray 'module.entryPoints'
    foreach ($stage in $stagesPresent) {
        if ($capabilityNames -cnotcontains ('shader.' + $stage)) { Throw-Sgir 'C003' ("Missing declared capability shader.{0}." -f $stage) }
    }

    $functions = Get-SgirValue $Document 'functions'
    Assert-SgirArray $functions 'module.functions'
    if ($functions.Count -eq 0) { Throw-Sgir 'F014' 'A shader module must declare at least one function.' }
    $functionMap = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)
    foreach ($function in $functions) {
        Assert-SgirObject $function @('id','returnType','entryBlock','parameters','blocks') @('id','returnType','entryBlock','parameters','blocks') 'function'
        Assert-SgirId (Get-SgirValue $function 'id') 'function.id'
        $functionId = [string](Get-SgirValue $function 'id')
        if ($functionMap.ContainsKey($functionId)) { Throw-Sgir 'F001' ("Duplicate function ID '{0}'." -f $functionId) }
        $functionMap.Add($functionId, $function)
        Assert-SgirTypeReference ([string](Get-SgirValue $function 'returnType')) $typeMap 'function.returnType'

        $parameters = Get-SgirValue $function 'parameters'
        Assert-SgirArray $parameters 'function.parameters'
        $parameterIds = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
        $expectedIndex = 0
        foreach ($parameter in $parameters) {
            Assert-SgirObject $parameter @('id','type','index') @('id','type','index') 'function.parameter'
            Assert-SgirId (Get-SgirValue $parameter 'id') 'parameter.id'
            Assert-SgirTypeReference ([string](Get-SgirValue $parameter 'type')) $typeMap 'parameter.type'
            if ((Get-SgirValue $parameter 'type') -ceq 'void') { Throw-Sgir 'F002' 'Function parameters cannot have void type.' }
            Assert-SgirInteger (Get-SgirValue $parameter 'index') 'parameter.index' 0 255
            if ((Get-SgirValue $parameter 'index') -ne $expectedIndex) { Throw-Sgir 'F003' 'Parameter indexes must be contiguous and zero-based.' }
            if (-not $parameterIds.Add([string](Get-SgirValue $parameter 'id'))) { Throw-Sgir 'F004' 'Parameter IDs must be unique within a function.' }
            $expectedIndex++
        }

        $blocks = Get-SgirValue $function 'blocks'
        Assert-SgirArray $blocks 'function.blocks'
        if ($blocks.Count -eq 0) { Throw-Sgir 'F005' 'A function must contain at least one basic block.' }
        $blockMap = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)
        foreach ($block in $blocks) {
            Assert-SgirObject $block @('id','instructions','terminator') @('id','instructions','terminator') 'basicBlock'
            Assert-SgirId (Get-SgirValue $block 'id') 'block.id'
            $blockId = [string](Get-SgirValue $block 'id')
            if ($blockMap.ContainsKey($blockId)) { Throw-Sgir 'F006' ("Duplicate basic-block ID '{0}'." -f $blockId) }
            $blockMap.Add($blockId, $block)
        }
        $blockIds = @($blocks | ForEach-Object { [string](Get-SgirValue $_ 'id') })
        Assert-SgirSortedStrings $blockIds 'function.blocks'
        $entryBlock = [string](Get-SgirValue $function 'entryBlock')
        if (-not $blockMap.ContainsKey($entryBlock)) { Throw-Sgir 'F007' 'entryBlock does not identify a declared basic block.' }

        $definitions = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)
        foreach ($parameter in $parameters) {
            $id = [string](Get-SgirValue $parameter 'id')
            $definitions.Add($id, @{ type = [string](Get-SgirValue $parameter 'type'); block = $null; position = -1; parameter = $true })
        }

        $predecessors = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)
        foreach ($blockId in $blockIds) { $predecessors.Add($blockId, (New-Object 'System.Collections.Generic.List[string]')) }
        foreach ($block in $blocks) {
            $terminator = Get-SgirValue $block 'terminator'
            $op = [string](Get-SgirValue $terminator 'op')
            switch -CaseSensitive ($op) {
                'branch' {
                    Assert-SgirObject $terminator @('op','target') @('op','target') 'terminator.branch'
                    $targetBlock = [string](Get-SgirValue $terminator 'target')
                    if (-not $blockMap.ContainsKey($targetBlock)) { Throw-Sgir 'F008' ("Branch targets unknown block '{0}'." -f $targetBlock) }
                    $predecessors[$targetBlock].Add([string](Get-SgirValue $block 'id'))
                }
                'branch_conditional' {
                    Assert-SgirObject $terminator @('op','condition','trueTarget','falseTarget') @('op','condition','trueTarget','falseTarget') 'terminator.branch_conditional'
                    $trueTarget = [string](Get-SgirValue $terminator 'trueTarget')
                    $falseTarget = [string](Get-SgirValue $terminator 'falseTarget')
                    if (-not $blockMap.ContainsKey($trueTarget) -or -not $blockMap.ContainsKey($falseTarget)) { Throw-Sgir 'F008' 'Conditional branch targets must reference declared basic blocks.' }
                    if ($trueTarget -ceq $falseTarget) { Throw-Sgir 'F009' 'A conditional branch must have distinct true and false targets.' }
                    $predecessors[$trueTarget].Add([string](Get-SgirValue $block 'id'))
                    $predecessors[$falseTarget].Add([string](Get-SgirValue $block 'id'))
                }
                'return' {
                    $returnType = [string](Get-SgirValue $function 'returnType')
                    if ($returnType -ceq 'void') {
                        Assert-SgirObject $terminator @('op') @('op') 'terminator.return'
                    } else {
                        Assert-SgirObject $terminator @('op','value') @('op','value') 'terminator.return'
                    }
                }
                default { Throw-Sgir 'F010' ("Unknown terminator '{0}'." -f $op) }
            }
        }

        $reachable = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
        $queue = New-Object 'System.Collections.Generic.Queue[string]'
        $queue.Enqueue($entryBlock)
        while ($queue.Count -gt 0) {
            $current = $queue.Dequeue()
            if (-not $reachable.Add($current)) { continue }
            $term = Get-SgirValue $blockMap[$current] 'terminator'
            $termOp = [string](Get-SgirValue $term 'op')
            if ($termOp -eq 'branch') { $queue.Enqueue([string](Get-SgirValue $term 'target')) }
            elseif ($termOp -eq 'branch_conditional') {
                $queue.Enqueue([string](Get-SgirValue $term 'trueTarget'))
                $queue.Enqueue([string](Get-SgirValue $term 'falseTarget'))
            }
        }
        if ($reachable.Count -ne $blocks.Count) { Throw-Sgir 'F011' 'Unreachable basic blocks are forbidden in SGIR/1.' }

        $dominators = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)
        foreach ($blockId in $blockIds) {
            $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
            if ($blockId -ceq $entryBlock) { [void]$set.Add($entryBlock) }
            else { foreach ($candidate in $blockIds) { [void]$set.Add($candidate) } }
            $dominators.Add($blockId, $set)
        }
        $changed = $true
        $iteration = 0
        while ($changed) {
            $changed = $false
            $iteration++
            if ($iteration -gt ($blocks.Count * $blocks.Count + 1)) { Throw-Sgir 'F012' 'Dominator analysis did not converge within the structural bound.' }
            foreach ($blockId in $blockIds) {
                if ($blockId -ceq $entryBlock) { continue }
                $preds = $predecessors[$blockId]
                if ($preds.Count -eq 0) { Throw-Sgir 'F013' ("Block '{0}' has no predecessor." -f $blockId) }
                $intersection = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
                foreach ($candidate in $dominators[$preds[0]]) { [void]$intersection.Add($candidate) }
                for ($p = 1; $p -lt $preds.Count; $p++) {
                    $intersectionCopy = @($intersection)
                    foreach ($candidate in $intersectionCopy) {
                        if (-not $dominators[$preds[$p]].Contains($candidate)) { [void]$intersection.Remove($candidate) }
                    }
                }
                [void]$intersection.Add($blockId)
                if ($intersection.Count -ne $dominators[$blockId].Count) { $changed = $true }
                else {
                    foreach ($candidate in $intersection) { if (-not $dominators[$blockId].Contains($candidate)) { $changed = $true; break } }
                }
                if ($changed) { $dominators[$blockId] = $intersection }
            }
        }

        foreach ($block in $blocks) {
            $blockId = [string](Get-SgirValue $block 'id')
            $instructions = Get-SgirValue $block 'instructions'
            Assert-SgirArray $instructions ("block.{0}.instructions" -f $blockId)
            $sawNonPhi = $false
            for ($position = 0; $position -lt $instructions.Count; $position++) {
                $instruction = $instructions[$position]
                $op = [string](Get-SgirValue $instruction 'op')
                switch ($op) {
                    'const' {
                        Assert-SgirObject $instruction @('op','result','type','literal') @('op','result','type','literal') 'instruction.const'
                        Assert-SgirId (Get-SgirValue $instruction 'result') 'instruction.result'
                        $literal = Get-SgirValue $instruction 'literal'
                        $literalType = [string](Get-SgirValue $instruction 'type')
                        if ($literalType -ceq 'bool') {
                            if ($literal -isnot [bool]) { Throw-Sgir 'V001' 'bool constants must use JSON true or false.' }
                        } elseif ($literalType -ceq 'i32') {
                            Assert-SgirInteger $literal 'i32 literal' -2147483648 2147483647
                        } elseif ($literalType -ceq 'u32') {
                            Assert-SgirInteger $literal 'u32 literal' 0 4294967295
                        } elseif ($literalType -ceq 'f32') {
                            Assert-SgirString $literal 'f32 literal bits'
                            if ([string]$literal -cnotmatch '^[0-9A-F]{8}$') { Throw-Sgir 'V002' 'f32 constants must be represented by exactly eight uppercase IEEE-754 bit-hex digits.' }
                        } else { Throw-Sgir 'V003' 'const supports only bool, i32, u32 and f32 scalar types.' }
                    }
                    'load_input' {
                        Assert-SgirObject $instruction @('op','result','type','interface') @('op','result','type','interface') 'instruction.load_input'
                        Assert-SgirId (Get-SgirValue $instruction 'result') 'instruction.result'
                        if (-not $entryFunctionMap.ContainsKey($functionId)) { Throw-Sgir 'V004' 'load_input is allowed only in a function bound to an entry point.' }
                    }
                    'add' { Assert-SgirObject $instruction @('op','result','type','operands') @('op','result','type','operands') 'instruction.add'; Assert-SgirId (Get-SgirValue $instruction 'result') 'instruction.result' }
                    'mul' { Assert-SgirObject $instruction @('op','result','type','operands') @('op','result','type','operands') 'instruction.mul'; Assert-SgirId (Get-SgirValue $instruction 'result') 'instruction.result' }
                    'construct_vector' { Assert-SgirObject $instruction @('op','result','type','operands') @('op','result','type','operands') 'instruction.construct_vector'; Assert-SgirId (Get-SgirValue $instruction 'result') 'instruction.result' }
                    'phi' {
                        Assert-SgirObject $instruction @('op','result','type','incoming') @('op','result','type','incoming') 'instruction.phi'
                        Assert-SgirId (Get-SgirValue $instruction 'result') 'instruction.result'
                        if ($sawNonPhi) { Throw-Sgir 'V005' 'Phi instructions must appear before all non-phi instructions in a block.' }
                    }
                    'store_output' {
                        Assert-SgirObject $instruction @('op','interface','value') @('op','interface','value') 'instruction.store_output'
                        if (-not $entryFunctionMap.ContainsKey($functionId)) { Throw-Sgir 'V006' 'store_output is allowed only in a function bound to an entry point.' }
                        $sawNonPhi = $true
                    }
                    default { Throw-Sgir 'V007' ("Unknown instruction opcode '{0}'." -f $op) }
                }
                if ($op -ne 'phi') { $sawNonPhi = $true }
                if ($op -ne 'store_output') {
                    $resultId = [string](Get-SgirValue $instruction 'result')
                    if ($definitions.ContainsKey($resultId)) { Throw-Sgir 'V008' ("SSA result ID '{0}' is defined more than once." -f $resultId) }
                    $resultType = [string](Get-SgirValue $instruction 'type')
                    Assert-SgirTypeReference $resultType $typeMap 'instruction.type'
                    if ($resultType -ceq 'void') { Throw-Sgir 'V009' 'Instructions cannot produce void values.' }
                    $definitions.Add($resultId, @{ type = $resultType; block = $blockId; position = $position; parameter = $false })
                }
            }
        }

        foreach ($block in $blocks) {
            $blockId = [string](Get-SgirValue $block 'id')
            $instructions = Get-SgirValue $block 'instructions'
            for ($instructionIndex = 0; $instructionIndex -lt $instructions.Count; $instructionIndex++) {
                $instruction = $instructions[$instructionIndex]
                $op = [string](Get-SgirValue $instruction 'op')
                if ($op -eq 'phi') {
                    $type = [string](Get-SgirValue $instruction 'type')
                    $incoming = Get-SgirValue $instruction 'incoming'
                    Assert-SgirArray $incoming 'phi.incoming'
                    $incomingBlockIds = @($incoming | ForEach-Object { [string](Get-SgirValue $_ 'block') })
                    Assert-SgirSortedStrings $incomingBlockIds 'phi.incoming'
                    if ($incoming.Count -ne $predecessors[$blockId].Count) { Throw-Sgir 'V010' 'Phi must contain exactly one incoming value for every predecessor.' }
                    $seenPreds = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
                    foreach ($edge in $incoming) {
                        Assert-SgirObject $edge @('block','value') @('block','value') 'phi.incoming.edge'
                        $pred = [string](Get-SgirValue $edge 'block')
                        $valueId = [string](Get-SgirValue $edge 'value')
                        if (-not $predecessors[$blockId].Contains($pred) -or -not $seenPreds.Add($pred)) { Throw-Sgir 'V011' 'Phi incoming blocks must be unique predecessor blocks.' }
                        if (-not $definitions.ContainsKey($valueId)) { Throw-Sgir 'V012' ("Phi references undefined value '{0}'." -f $valueId) }
                        $definition = $definitions[$valueId]
                        if ($definition.type -cne $type) { Throw-Sgir 'V013' 'Phi incoming value type does not match phi result type.' }
                        if (-not $definition.parameter) {
                            if ($definition.block -ceq $pred) {
                                $predInstructions = Get-SgirValue $blockMap[$pred] 'instructions'
                                if ($definition.position -ge $predInstructions.Count) { Throw-Sgir 'V014' 'Phi input is not available at the predecessor terminator.' }
                            } elseif (-not $dominators[$pred].Contains([string]$definition.block)) {
                                Throw-Sgir 'V015' 'Phi input definition does not dominate its predecessor edge.'
                            }
                        }
                    }
                    foreach ($pred in $predecessors[$blockId]) { if (-not $seenPreds.Contains($pred)) { Throw-Sgir 'V016' 'Phi is missing an incoming predecessor edge.' } }
                } elseif ($op -eq 'const') {
                    continue
                } elseif ($op -eq 'load_input') {
                    $entry = $entryFunctionMap[$functionId]
                    $interfaceId = [string](Get-SgirValue $instruction 'interface')
                    $matches = @((Get-SgirValue $entry 'inputs') | Where-Object { (Get-SgirValue $_ 'id') -ceq $interfaceId })
                    if ($matches.Count -ne 1) { Throw-Sgir 'V017' ("load_input references unknown input interface '{0}'." -f $interfaceId) }
                    if ((Get-SgirValue $matches[0] 'type') -cne (Get-SgirValue $instruction 'type')) { Throw-Sgir 'V018' 'load_input result type does not match its interface type.' }
                } elseif ($op -eq 'add' -or $op -eq 'mul' -or $op -eq 'construct_vector') {
                    $operands = Get-SgirValue $instruction 'operands'
                    Assert-SgirArray $operands ("instruction.{0}.operands" -f $op)
                    $resultType = [string](Get-SgirValue $instruction 'type')
                    if ($op -eq 'construct_vector') {
                        if (-not $typeMap.ContainsKey($resultType) -or (Get-SgirValue $typeMap[$resultType] 'kind') -cne 'vector') { Throw-Sgir 'V019' 'construct_vector result type must be a declared vector.' }
                        $vector = $typeMap[$resultType]
                        if ($operands.Count -ne (Get-SgirValue $vector 'lanes')) { Throw-Sgir 'V020' 'construct_vector operand count must equal vector lane count.' }
                        $expectedOperandType = [string](Get-SgirValue $vector 'elementType')
                    } else {
                        if ($operands.Count -ne 2) { Throw-Sgir 'V021' ("{0} requires exactly two operands." -f $op) }
                        $kind = Get-SgirTypeKind $resultType $typeMap
                        if ($kind -ne 'scalar' -and $kind -ne 'vector') { Throw-Sgir 'V022' ("{0} supports only scalar or vector numeric values." -f $op) }
                        if ($resultType -eq 'bool' -or ($resultType -notin @('i32','u32','f32') -and -not $typeMap.ContainsKey($resultType))) { Throw-Sgir 'V023' 'Arithmetic type must be numeric.' }
                        $expectedOperandType = $resultType
                    }
                    foreach ($operand in $operands) {
                        $operandId = [string]$operand
                        if (-not $definitions.ContainsKey($operandId)) { Throw-Sgir 'V024' ("Instruction references undefined value '{0}'." -f $operandId) }
                        $definition = $definitions[$operandId]
                        if ($definition.type -cne $expectedOperandType) { Throw-Sgir 'V025' 'Instruction operand type does not match its operation.' }
                        if (-not $definition.parameter) {
                            if ($definition.block -ceq $blockId) {
                                if ($definition.position -ge $instructionIndex) { Throw-Sgir 'V026' 'Instruction uses an SSA value before its definition.' }
                            } elseif (-not $dominators[$blockId].Contains([string]$definition.block)) {
                                Throw-Sgir 'V027' 'SSA definition does not dominate its use.'
                            }
                        }
                    }
                } elseif ($op -eq 'store_output') {
                    $entry = $entryFunctionMap[$functionId]
                    $interfaceId = [string](Get-SgirValue $instruction 'interface')
                    $matches = @((Get-SgirValue $entry 'outputs') | Where-Object { (Get-SgirValue $_ 'id') -ceq $interfaceId })
                    if ($matches.Count -ne 1) { Throw-Sgir 'V028' ("store_output references unknown output interface '{0}'." -f $interfaceId) }
                    $valueId = [string](Get-SgirValue $instruction 'value')
                    if (-not $definitions.ContainsKey($valueId)) { Throw-Sgir 'V029' ("store_output references undefined value '{0}'." -f $valueId) }
                    if ($definitions[$valueId].type -cne (Get-SgirValue $matches[0] 'type')) { Throw-Sgir 'V030' 'store_output value type does not match output interface type.' }
                    $definition = $definitions[$valueId]
                    if (-not $definition.parameter) {
                        if ($definition.block -ceq $blockId) {
                            if ($definition.position -ge $instructionIndex) { Throw-Sgir 'V026' 'store_output uses an SSA value before its definition.' }
                        } elseif (-not $dominators[$blockId].Contains([string]$definition.block)) { Throw-Sgir 'V027' 'SSA definition does not dominate store_output.' }
                    }
                }
            }

            $terminator = Get-SgirValue $block 'terminator'
            $op = [string](Get-SgirValue $terminator 'op')
            if ($op -eq 'branch_conditional') {
                $condition = [string](Get-SgirValue $terminator 'condition')
                if (-not $definitions.ContainsKey($condition)) { Throw-Sgir 'V031' 'Conditional branch references undefined condition value.' }
                if ($definitions[$condition].type -cne 'bool') { Throw-Sgir 'V032' 'Conditional branch condition must have bool type.' }
                $definition = $definitions[$condition]
                if (-not $definition.parameter) {
                    $position = (Get-SgirValue $block 'instructions').Count
                    if ($definition.block -ceq $blockId) {
                        if ($definition.position -ge $position) { Throw-Sgir 'V033' 'Branch condition is not defined before the terminator.' }
                    } elseif (-not $dominators[$blockId].Contains([string]$definition.block)) { Throw-Sgir 'V034' 'Branch condition definition does not dominate its use.' }
                }
            } elseif ($op -eq 'return') {
                $returnType = [string](Get-SgirValue $function 'returnType')
                if ($returnType -ne 'void') {
                    $valueId = [string](Get-SgirValue $terminator 'value')
                    if (-not $definitions.ContainsKey($valueId)) { Throw-Sgir 'V035' 'Return references an undefined value.' }
                    if ($definitions[$valueId].type -cne $returnType) { Throw-Sgir 'V036' 'Return value type does not match function return type.' }
                    $definition = $definitions[$valueId]
                    if (-not $definition.parameter) {
                        $returnPosition = (Get-SgirValue $block 'instructions').Count
                        if ($definition.block -ceq $blockId) {
                            if ($definition.position -ge $returnPosition) { Throw-Sgir 'V037' 'Return value is not defined before the terminator.' }
                        } elseif (-not $dominators[$blockId].Contains([string]$definition.block)) {
                            Throw-Sgir 'V038' 'Return value definition does not dominate the return terminator.'
                        }
                    }
                }
            }
        }
    }

    foreach ($entry in $entryPoints) {
        $functionId = [string](Get-SgirValue $entry 'function')
        if (-not $functionMap.ContainsKey($functionId)) { Throw-Sgir 'E012' ("Entry point references unknown function '{0}'." -f $functionId) }
        if ((Get-SgirValue $functionMap[$functionId] 'returnType') -cne 'void') { Throw-Sgir 'E013' 'Graphics entry-point functions must return void in SGIR/1.' }
    }
    $functionIds = @($functions | ForEach-Object { [string](Get-SgirValue $_ 'id') })
    Assert-SgirSortedStrings $functionIds 'module.functions'

    return [pscustomobject]@{
        Valid = $true
        ModuleId = $moduleId
        TypeCount = $types.Count
        ResourceCount = $resources.Count
        EntryPointCount = $entryPoints.Count
        FunctionCount = $functions.Count
        CanonicalSha256 = (Get-SgirCanonicalHash -Document $Document)
    }
}

function Read-SgirModuleFile {
    param([Parameter(Mandatory = $true)][string] $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Throw-Sgir 'J006' ("Input file not found: {0}" -f $Path) }
    $encoding = New-Object System.Text.UTF8Encoding($false, $true)
    $json = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).Path, $encoding)
    return (ConvertFrom-SgirJsonText -Json $json)
}

if ($Action -ne 'None') {
    if ([string]::IsNullOrWhiteSpace($InputPath)) { Throw-Sgir 'J007' '-InputPath is required for command-line use.' }
    $document = Read-SgirModuleFile -Path $InputPath
    $result = Assert-SgirModule -Document $document
    if ($Action -eq 'Canonicalize') {
        if ([string]::IsNullOrWhiteSpace($OutputPath)) { Throw-Sgir 'J008' '-OutputPath is required for Canonicalize.' }
        $canonical = ConvertTo-SgirCanonicalJson -Document $document
        $encoding = New-Object System.Text.UTF8Encoding($false, $true)
        [System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($OutputPath), $canonical + [Environment]::NewLine, $encoding)
    }
    Write-Output ("SGIR/1 VALID: {0}" -f $result.ModuleId)
    Write-Output ("Canonical SHA-256: {0}" -f $result.CanonicalSha256)
    Write-Output ("Types={0}; Resources={1}; EntryPoints={2}; Functions={3}" -f $result.TypeCount, $result.ResourceCount, $result.EntryPointCount, $result.FunctionCount)
}
