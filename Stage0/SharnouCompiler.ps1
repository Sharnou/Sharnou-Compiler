[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string] $Source,
    [Parameter(Mandatory = $true, Position = 1)]
    [string] $Output,
    [switch] $EnableDevAgentTools,
    [switch] $EnableWin64CallbackTests,
    [switch] $EnableNativeScmServiceHost,
    [string] $NativeScmServiceName = 'SharnouAuthorityHost'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:NativeScmServiceMode = [bool]$EnableNativeScmServiceHost
$script:NativeScmServiceName = [string]$NativeScmServiceName
if ($script:NativeScmServiceMode) {
    if ($EnableDevAgentTools -or $EnableWin64CallbackTests) {
        throw 'Native SCM service compilation cannot be combined with DevAgent or callback-test compiler modes.'
    }
    if ([string]::IsNullOrWhiteSpace($script:NativeScmServiceName) -or
        $script:NativeScmServiceName.Length -gt 256 -or
        $script:NativeScmServiceName -notmatch '^[A-Za-z0-9_.-]+ = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\Tools\SharnouPERelocations.ps1'))
if (-not (Test-Path -LiteralPath $relocationModulePath -PathType Leaf)) {
    throw "Sharnou PE relocation module is missing: $relocationModulePath"
}
. $relocationModulePath

function Set-Bytes {
    param([byte[]] $Buffer, [int] $Offset, [byte[]] $Bytes)
    if ($Offset -lt 0 -or ($Offset + $Bytes.Length) -gt $Buffer.Length) {
        throw "Write outside output image: offset=$Offset length=$($Bytes.Length)."
    }
    if ($Bytes.Length -gt 0) { [System.Buffer]::BlockCopy($Bytes, 0, $Buffer, $Offset, $Bytes.Length) }
}
function Set-U16 { param([byte[]] $Buffer, [int] $Offset, [UInt16] $Value) Set-Bytes -Buffer $Buffer -Offset $Offset -Bytes ([BitConverter]::GetBytes($Value)) }
function Set-U32 { param([byte[]] $Buffer, [int] $Offset, [UInt32] $Value) Set-Bytes -Buffer $Buffer -Offset $Offset -Bytes ([BitConverter]::GetBytes($Value)) }
function Set-U64 { param([byte[]] $Buffer, [int] $Offset, [UInt64] $Value) Set-Bytes -Buffer $Buffer -Offset $Offset -Bytes ([BitConverter]::GetBytes($Value)) }
function Set-Ascii { param([byte[]] $Buffer, [int] $Offset, [string] $Value) Set-Bytes -Buffer $Buffer -Offset $Offset -Bytes ([System.Text.Encoding]::ASCII.GetBytes($Value)) }
function Set-AsciiZ {
    param([byte[]] $Buffer, [int] $Offset, [string] $Value)
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($Value)
    if ($Offset -lt 0 -or ($Offset + $bytes.Length) -ge $Buffer.Length) { throw 'Null-terminated ASCII string would exceed the output image.' }
    Set-Bytes -Buffer $Buffer -Offset $Offset -Bytes $bytes
    $Buffer[$Offset + $bytes.Length] = 0
}
function Throw-SourceError {
    param([int] $Line, [int] $Column, [string] $Message)
    throw ("{0}({1},{2}): error: {3} (line {1}, column {2})" -f $script:SourceDisplay, $Line, $Column, $Message)
}
function Add-Token {
    param([string] $Kind, [string] $Text, [object] $Value, [int] $Line, [int] $Column)
    $script:Tokens.Add([pscustomobject]@{ Kind = $Kind; Text = $Text; Value = $Value; Line = $Line; Column = $Column; File = $script:SourceDisplay })
}
function Initialize-Tokens {
    param([string] $Text)
    $script:Tokens = [System.Collections.Generic.List[object]]::new()
    $i = 0
    $line = 1
    $column = 1
    while ($i -lt $Text.Length) {
        $ch = $Text[$i]
        $code = [int]$ch
        if ($code -gt 127) { Throw-SourceError -Line $line -Column $column -Message 'Source files must contain ASCII characters only.' }
        if ([char]::IsWhiteSpace($ch)) {
            if ($ch -eq "`r") {
                $i++
                if ($i -lt $Text.Length -and $Text[$i] -eq "`n") { $i++ }
                $line++; $column = 1
            } elseif ($ch -eq "`n") { $i++; $line++; $column = 1 }
            else { $i++; $column++ }
            continue
        }
        if ($ch -eq '/' -and ($i + 1) -lt $Text.Length -and $Text[$i + 1] -eq '/') {
            $i += 2; $column += 2
            while ($i -lt $Text.Length -and $Text[$i] -ne "`r" -and $Text[$i] -ne "`n") { $i++; $column++ }
            continue
        }
        if ($ch -eq '/' -and ($i + 1) -lt $Text.Length -and $Text[$i + 1] -eq '*') {
            $commentLine = $line; $commentColumn = $column; $i += 2; $column += 2; $closed = $false
            while ($i -lt $Text.Length) {
                if ($Text[$i] -eq '*' -and ($i + 1) -lt $Text.Length -and $Text[$i + 1] -eq '/') { $i += 2; $column += 2; $closed = $true; break }
                if ($Text[$i] -eq "`r") { $i++; if ($i -lt $Text.Length -and $Text[$i] -eq "`n") { $i++ }; $line++; $column = 1; continue }
                if ($Text[$i] -eq "`n") { $i++; $line++; $column = 1; continue }
                $i++; $column++
            }
            if (-not $closed) { Throw-SourceError -Line $commentLine -Column $commentColumn -Message 'Unterminated block comment; expected */.' }
            continue
        }
        if ($ch -eq '"') {
            $stringLine = $line; $stringColumn = $column; $i++; $column++; $builder = [System.Text.StringBuilder]::new(); $closed = $false
            while ($i -lt $Text.Length) {
                $current = $Text[$i]; $currentCode = [int]$current
                if ($currentCode -gt 127) { Throw-SourceError -Line $line -Column $column -Message 'String literals must use ASCII characters only.' }
                if ($current -eq '"') { $i++; $column++; $closed = $true; break }
                if ($current -eq "`r" -or $current -eq "`n") { Throw-SourceError -Line $line -Column $column -Message 'Unescaped newline in string literal.' }
                if ($current -eq '\') {
                    $escapeLine = $line; $escapeColumn = $column; $i++; $column++
                    if ($i -ge $Text.Length) { Throw-SourceError -Line $escapeLine -Column $escapeColumn -Message 'Incomplete string escape.' }
                    $escaped = $Text[$i]
                    switch ([string]$escaped) {
                        '\' { $null = $builder.Append('\') }
                        '"' { $null = $builder.Append('"') }
                        'n' { $null = $builder.Append("`n") }
                        'r' { $null = $builder.Append("`r") }
                        't' { $null = $builder.Append("`t") }
                        default { Throw-SourceError -Line $escapeLine -Column $escapeColumn -Message ("Unsupported string escape '{0}'. Supported escapes: backslash, quote, n, r, and t." -f $escaped) }
                    }
                    $i++; $column++; continue
                }
                if ($currentCode -lt 0x20 -or $currentCode -gt 0x7E) { Throw-SourceError -Line $line -Column $column -Message 'String literals may contain printable ASCII only; use escapes for tab and control characters.' }
                $null = $builder.Append($current); $i++; $column++
            }
            if (-not $closed) { Throw-SourceError -Line $stringLine -Column $stringColumn -Message 'Unterminated string literal; expected a closing quote.' }
            Add-Token -Kind 'String' -Text '<string>' -Value $builder.ToString() -Line $stringLine -Column $stringColumn
            continue
        }
        if ([char]::IsDigit($ch)) {
            $start = $i; $startColumn = $column
            while ($i -lt $Text.Length -and [char]::IsDigit($Text[$i])) { if ([int]$Text[$i] -gt 127) { Throw-SourceError -Line $line -Column $column -Message 'Integer literals must use ASCII decimal digits.' }; $i++; $column++ }
            $numberText = $Text.Substring($start, $i - $start)
            Add-Token -Kind 'Integer' -Text $numberText -Value $numberText -Line $line -Column $startColumn
            continue
        }
        if ([char]::IsLetter($ch) -or $ch -eq '_') {
            $start = $i; $startColumn = $column
            while ($i -lt $Text.Length) {
                $current = $Text[$i]; $currentCode = [int]$current
                if ($currentCode -gt 127) { Throw-SourceError -Line $line -Column $column -Message 'Identifiers must use ASCII letters, digits, and underscores.' }
                if (-not ([char]::IsLetterOrDigit($current) -or $current -eq '_')) { break }
                $i++; $column++
            }
            $identifier = $Text.Substring($start, $i - $start)
            Add-Token -Kind 'Identifier' -Text $identifier -Value $identifier -Line $line -Column $startColumn
            continue
        }
        if (($i + 1) -lt $Text.Length) {
            $pair = $Text.Substring($i, 2)
            if (@('<=', '>=', '==', '!=') -contains $pair) {
                Add-Token -Kind 'Symbol' -Text $pair -Value $pair -Line $line -Column $column
                $i += 2; $column += 2; continue
            }
        }
        if ('+-*/=();{},<>'.Contains([string]$ch)) {
            Add-Token -Kind 'Symbol' -Text ([string]$ch) -Value ([string]$ch) -Line $line -Column $column
            $i++; $column++; continue
        }
        Throw-SourceError -Line $line -Column $column -Message ("Unexpected character '{0}'." -f $ch)
    }
    Add-Token -Kind 'EOF' -Text '<end of file>' -Value $null -Line $line -Column $column
}
function Get-CurrentToken { return $script:Tokens[$script:TokenIndex] }
function Move-NextToken { $token = $script:Tokens[$script:TokenIndex]; if ($token.Kind -ne 'EOF') { $script:TokenIndex++ }; return $token }
function Test-CurrentText { param([string] $Text) return ((Get-CurrentToken).Text -ceq $Text) }
function Expect-Text {
    param([string] $Text, [string] $Description)
    $token = Get-CurrentToken
    if ($token.Text -cne $Text) { Throw-SourceError -Line $token.Line -Column $token.Column -Message ("Expected {0}; found '{1}'." -f $Description, $token.Text) }
    return (Move-NextToken)
}
function New-AstNode {
    param([string] $Kind, [string] $Type, [object] $Value = $null, [string] $Name = '', [int] $Slot = -1, [string] $Operator = '', [object] $Left = $null, [object] $Right = $null, [object] $Operand = $null, [object[]] $Arguments = @(), [object[]] $Statements = @(), [string] $Builtin = '', [int] $Line = 1, [int] $Column = 1)
    return [pscustomobject]@{ Kind = $Kind; Type = $Type; Value = $Value; Name = $Name; Slot = $Slot; Operator = $Operator; Left = $Left; Right = $Right; Operand = $Operand; Arguments = $Arguments; Statements = $Statements; Builtin = $Builtin; Line = $Line; Column = $Column }
}
function New-Statement {
    param([string] $Kind, [string] $Name = '', [string] $Type = '', [int] $Slot = -1, [object] $Expression = $null, [object[]] $Statements = @(), [object[]] $ElseStatements = @(), [int] $Line = 1, [int] $Column = 1)
    return [pscustomobject]@{ Kind = $Kind; Name = $Name; Type = $Type; Slot = $Slot; Expression = $Expression; Statements = $Statements; ElseStatements = $ElseStatements; Line = $Line; Column = $Column }
}
function New-IntegerNode { param([long] $Value, [int] $Line, [int] $Column) return (New-AstNode -Kind 'Integer' -Type 'Integer' -Value $Value -Line $Line -Column $Column) }
function New-StringNode { param([string] $Value, [int] $Line, [int] $Column) return (New-AstNode -Kind 'String' -Type 'String' -Value $Value -Line $Line -Column $Column) }
function Push-Scope { $script:Scopes.Add([System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)) }
function Pop-Scope { if ($script:Scopes.Count -le 0) { throw 'Internal scope underflow.' }; $script:Scopes.RemoveAt($script:Scopes.Count - 1) }
function Find-Variable {
    param([string] $Name)
    for ($i = $script:Scopes.Count - 1; $i -ge 0; $i--) { if ($script:Scopes[$i].ContainsKey($Name)) { return $script:Scopes[$i][$Name] } }
    return $null
}
function Declare-Variable {
    param([string] $Name, [string] $Type, [int] $Line, [int] $Column)
    if ($script:Scopes.Count -eq 0) { throw 'Internal parser error: no active lexical scope.' }
    $scope = $script:Scopes[$script:Scopes.Count - 1]
    if ($scope.ContainsKey($Name)) { Throw-SourceError -Line $Line -Column $Column -Message ("Variable '{0}' is already declared in this scope." -f $Name) }
    $slot = [int]$script:ActiveContext.SlotCount
    $symbol = [pscustomobject]@{ Name = $Name; Type = $Type; Slot = $slot }
    $scope.Add($Name, $symbol)
    $script:ActiveContext.SlotCount = [int]($script:ActiveContext.SlotCount + 1)
    return $symbol
}
function Parse-Primary {
    $token = Get-CurrentToken
    if ($token.Kind -eq 'Integer') {
        Move-NextToken | Out-Null
        $number = [long]0
        $parsed = [long]::TryParse([string]$token.Text, [System.Globalization.NumberStyles]::None, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$number)
        if (-not $parsed -or $number -gt [int]::MaxValue) { Throw-SourceError -Line $token.Line -Column $token.Column -Message 'Integer literal is outside the supported signed 32-bit range.' }
        return (New-IntegerNode -Value $number -Line $token.Line -Column $token.Column)
    }
    if ($token.Kind -eq 'String') { Move-NextToken | Out-Null; return (New-StringNode -Value ([string]$token.Value) -Line $token.Line -Column $token.Column) }
    if ($token.Kind -eq 'Identifier') {
        Move-NextToken | Out-Null
        $name = [string]$token.Text
        if (Test-CurrentText '(') {
            $null = Move-NextToken
            $callArguments = [System.Collections.Generic.List[object]]::new()
            if (-not (Test-CurrentText ')')) {
                while ($true) {
                    $callArguments.Add((Parse-Expression))
                    if (Test-CurrentText ',') { Move-NextToken | Out-Null; continue }
                    break
                }
            }
            $null = Expect-Text -Text ')' -Description "')' after function arguments"
            $target = $null
            $isBuiltin = $false
            if ($script:Functions.ContainsKey($name)) { $target = $script:Functions[$name] }
            elseif ($script:Builtins.ContainsKey($name)) { $target = $script:Builtins[$name]; $isBuiltin = $true }
            else { Throw-SourceError -Line $token.Line -Column $token.Column -Message ("Undefined function or standard-library intrinsic '{0}'." -f $name) }
            if ($isBuiltin) { $expectedParameters = @($target.ParameterTypes) }
            else { $expectedParameters = @($target.Parameters | ForEach-Object { 'Integer' }) }
            if ($callArguments.Count -ne $expectedParameters.Count) { Throw-SourceError -Line $token.Line -Column $token.Column -Message ("Function '{0}' expects {1} argument(s), but received {2}." -f $name, $expectedParameters.Count, $callArguments.Count) }
            for ($argIndex = 0; $argIndex -lt $callArguments.Count; $argIndex++) {
                if ($callArguments[$argIndex].Type -ne $expectedParameters[$argIndex]) { Throw-SourceError -Line $callArguments[$argIndex].Line -Column $callArguments[$argIndex].Column -Message ("Argument {0} of '{1}' must be {2}, not {3}." -f ($argIndex + 1), $name, $expectedParameters[$argIndex], $callArguments[$argIndex].Type) }
            }
            $builtinName = ''
            $returnType = 'Integer'
            if ($isBuiltin) { $builtinName = [string]$target.Builtin; $returnType = [string]$target.ReturnType }
            return (New-AstNode -Kind 'Call' -Type $returnType -Name $name -Builtin $builtinName -Arguments ($callArguments.ToArray()) -Line $token.Line -Column $token.Column)
        }
        $symbol = Find-Variable -Name $name
        if ($null -eq $symbol) { Throw-SourceError -Line $token.Line -Column $token.Column -Message ("Undefined variable '{0}'." -f $name) }
        return (New-AstNode -Kind 'Variable' -Type $symbol.Type -Name $name -Slot $symbol.Slot -Line $token.Line -Column $token.Column)
    }
    if ($token.Text -ceq '(') { Move-NextToken | Out-Null; $value = Parse-Expression; $null = Expect-Text -Text ')' -Description "')'"; return $value }
    Throw-SourceError -Line $token.Line -Column $token.Column -Message ("Expected an integer, string, variable, function call, or parenthesized expression; found '{0}'." -f $token.Text)
}
function Parse-Unary {
    $token = Get-CurrentToken
    if ($token.Text -ceq '+' -or $token.Text -ceq '-') {
        $operator = Move-NextToken; $next = Get-CurrentToken
        if ($operator.Text -ceq '-' -and $next.Kind -eq 'Integer' -and $next.Text -ceq '2147483648') { Move-NextToken | Out-Null; return (New-IntegerNode -Value ([long]([int]::MinValue)) -Line $operator.Line -Column $operator.Column) }
        $operand = Parse-Unary
        if ($operand.Type -ne 'Integer') { Throw-SourceError -Line $operator.Line -Column $operator.Column -Message ("Unary operator '{0}' requires an integer operand." -f $operator.Text) }
        return (New-AstNode -Kind 'Unary' -Type 'Integer' -Operator ([string]$operator.Text) -Operand $operand -Line $operator.Line -Column $operator.Column)
    }
    return (Parse-Primary)
}
function Parse-Term {
    $value = Parse-Unary
    while ((Test-CurrentText '*') -or (Test-CurrentText '/')) {
        $operator = Move-NextToken; $right = Parse-Unary
        if ($value.Type -ne 'Integer' -or $right.Type -ne 'Integer') { Throw-SourceError -Line $operator.Line -Column $operator.Column -Message ("Operator '{0}' requires integer operands." -f $operator.Text) }
        $value = New-AstNode -Kind 'Binary' -Type 'Integer' -Operator ([string]$operator.Text) -Left $value -Right $right -Line $operator.Line -Column $operator.Column
    }
    return $value
}
function Parse-AdditiveExpression {
    $value = Parse-Term
    while ((Test-CurrentText '+') -or (Test-CurrentText '-')) {
        $operator = Move-NextToken; $right = Parse-Term
        if ($value.Type -ne 'Integer' -or $right.Type -ne 'Integer') { Throw-SourceError -Line $operator.Line -Column $operator.Column -Message ("Operator '{0}' requires integer operands." -f $operator.Text) }
        $value = New-AstNode -Kind 'Binary' -Type 'Integer' -Operator ([string]$operator.Text) -Left $value -Right $right -Line $operator.Line -Column $operator.Column
    }
    return $value
}
function Parse-Expression {
    $left = Parse-AdditiveExpression
    $operatorToken = Get-CurrentToken
    $comparisonOperators = @('<', '>', '<=', '>=', '==', '!=')
    if ($comparisonOperators -contains $operatorToken.Text) {
        $operator = Move-NextToken
        $right = Parse-AdditiveExpression
        if ($left.Type -ne 'Integer' -or $right.Type -ne 'Integer') {
            Throw-SourceError -Line $operator.Line -Column $operator.Column -Message ("Comparison '{0}' requires integer operands." -f $operator.Text)
        }
        $next = Get-CurrentToken
        if ($comparisonOperators -contains $next.Text) {
            Throw-SourceError -Line $next.Line -Column $next.Column -Message 'Chained comparisons are not supported; use a nested if or while statement.'
        }
        return (New-AstNode -Kind 'Comparison' -Type 'Integer' -Operator ([string]$operator.Text) -Left $left -Right $right -Line $operator.Line -Column $operator.Column)
    }
    return $left
}
function Get-ConstantValue {
    param([object] $Node)
    if ($Node.Kind -eq 'Integer') { return [pscustomobject]@{ Known = $true; Type = 'Integer'; Value = [long]$Node.Value } }
    if ($Node.Kind -eq 'String') { return [pscustomobject]@{ Known = $true; Type = 'String'; Value = [string]$Node.Value } }
    if ($Node.Kind -eq 'Variable' -or $Node.Kind -eq 'Call') { return [pscustomobject]@{ Known = $false; Type = $Node.Type; Value = $null } }
    if ($Node.Kind -eq 'Unary') {
        $child = Get-ConstantValue -Node $Node.Operand
        if (-not $child.Known) { return [pscustomobject]@{ Known = $false; Type = 'Integer'; Value = $null } }
        $number = [long]$child.Value; if ($Node.Operator -eq '-') { $number = -$number }
        if ($number -lt [int]::MinValue -or $number -gt [int]::MaxValue) { Throw-SourceError -Line $Node.Line -Column $Node.Column -Message 'Integer result is outside the supported signed 32-bit range.' }
        return [pscustomobject]@{ Known = $true; Type = 'Integer'; Value = $number }
    }
    if ($Node.Kind -eq 'Comparison') {
        $left = Get-ConstantValue -Node $Node.Left
        $right = Get-ConstantValue -Node $Node.Right
        if (-not $left.Known -or -not $right.Known) {
            return [pscustomobject]@{ Known = $false; Type = 'Integer'; Value = $null }
        }
        $a = [long]$left.Value
        $b = [long]$right.Value
        switch ($Node.Operator) {
            '<'  { $result = ($a -lt $b) }
            '>'  { $result = ($a -gt $b) }
            '<=' { $result = ($a -le $b) }
            '>=' { $result = ($a -ge $b) }
            '==' { $result = ($a -eq $b) }
            '!=' { $result = ($a -ne $b) }
            default { Throw-SourceError -Line $Node.Line -Column $Node.Column -Message ("Unsupported comparison operator '{0}'." -f $Node.Operator) }
        }
        return [pscustomobject]@{ Known = $true; Type = 'Integer'; Value = [long]([int]$result) }
    }
    if ($Node.Kind -eq 'Binary') {
        $left = Get-ConstantValue -Node $Node.Left; $right = Get-ConstantValue -Node $Node.Right
        if (-not $left.Known -or -not $right.Known) { return [pscustomobject]@{ Known = $false; Type = 'Integer'; Value = $null } }
        $a = [long]$left.Value; $b = [long]$right.Value
        switch ($Node.Operator) {
            '+' { $number = $a + $b }
            '-' { $number = $a - $b }
            '*' { $number = $a * $b }
            '/' { if ($b -eq 0) { Throw-SourceError -Line $Node.Line -Column $Node.Column -Message 'Division by zero is not allowed.' }; $number = [long][Math]::Truncate(([double]$a / [double]$b)) }
            default { Throw-SourceError -Line $Node.Line -Column $Node.Column -Message ("Unsupported operator '{0}'." -f $Node.Operator) }
        }
        if ($number -lt [int]::MinValue -or $number -gt [int]::MaxValue) { Throw-SourceError -Line $Node.Line -Column $Node.Column -Message 'Integer result is outside the supported signed 32-bit range.' }
        return [pscustomobject]@{ Known = $true; Type = 'Integer'; Value = $number }
    }
    return [pscustomobject]@{ Known = $false; Type = $Node.Type; Value = $null }
}
function Validate-ConstantArithmetic { param([object] $Node) $null = Get-ConstantValue -Node $Node }
function Load-Module {
    param([string] $Path, [bool] $IsRoot = $false)
    $full = [System.IO.Path]::GetFullPath($Path)
    if ($script:ModuleMap.ContainsKey($full)) {
        $existing = $script:ModuleMap[$full]
        if ($existing.State -eq 'Loading') { throw "Cyclic module import detected at: $full" }
        if ($IsRoot) { $existing.IsRoot = $true }
        return $existing
    }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Imported module was not found: $full" }
    $module = [pscustomobject]@{ Path = $full; Tokens = $null; Imports = [System.Collections.Generic.List[string]]::new(); BodyStartIndex = 0; IsRoot = $IsRoot; State = 'Loading' }
    $script:ModuleMap.Add($full, $module); $script:Modules.Add($module)
    $script:SourceDisplay = $full
    $sourceText = [System.IO.File]::ReadAllText($full, [System.Text.Encoding]::UTF8)
    Initialize-Tokens -Text $sourceText
    $module.Tokens = $script:Tokens.ToArray()
    $index = 0
    while ($index -lt $module.Tokens.Length -and $module.Tokens[$index].Kind -ne 'EOF') {
        $script:SourceDisplay = $full
        $token = $module.Tokens[$index]
        if ($token.Kind -ne 'Identifier' -or $token.Text -cne 'import') { break }
        if (($index + 2) -ge $module.Tokens.Length) {
            Throw-SourceError -Line $token.Line -Column $token.Column -Message "Expected import 'relative-module.sharnou'; at the start of a module."
        }
        if ($module.Tokens[$index + 1].Kind -ne 'String' -or $module.Tokens[$index + 2].Text -cne ';') {
            Throw-SourceError -Line $token.Line -Column $token.Column -Message "Expected import 'relative-module.sharnou'; at the start of a module."
        }
        $importName = [string]$module.Tokens[$index + 1].Value
        if ([System.IO.Path]::IsPathRooted($importName)) { Throw-SourceError -Line $module.Tokens[$index + 1].Line -Column $module.Tokens[$index + 1].Column -Message 'Module imports must be relative paths.' }
        $target = [System.IO.Path]::GetFullPath((Join-Path ([System.IO.Path]::GetDirectoryName($full)) $importName))
        $module.Imports.Add($target)
        $null = Load-Module -Path $target -IsRoot $false
        $index += 3
    }
    $module.BodyStartIndex = $index
    $module.State = 'Loaded'
    return $module
}
function Collect-FunctionHeaders {
    param([object] $Module)
    $tokens = $Module.Tokens; $i = [int]$Module.BodyStartIndex; $depth = 0
    while ($i -lt $tokens.Length -and $tokens[$i].Kind -ne 'EOF') {
        $token = $tokens[$i]
        if ($depth -eq 0 -and $token.Kind -eq 'Identifier' -and $token.Text -ceq 'fn') {
            $functionStart = $i; $fnToken = $token; $i++
            if ($i -ge $tokens.Length -or $tokens[$i].Kind -ne 'Identifier') { $script:SourceDisplay = $Module.Path; Throw-SourceError -Line $fnToken.Line -Column $fnToken.Column -Message 'Expected a function name after fn.' }
            $nameToken = $tokens[$i]; $name = [string]$nameToken.Text; $i++
            if (@('print', 'let', 'fn', 'return', 'import', 'if', 'else', 'while') -contains $name) { $script:SourceDisplay = $Module.Path; Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message 'Reserved keyword cannot be used as a function name.' }
            if ($i -ge $tokens.Length -or $tokens[$i].Text -cne '(') { $script:SourceDisplay = $Module.Path; Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message "Expected '(' after function name." }; $i++
            $params = [System.Collections.Generic.List[object]]::new(); $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            if ($i -lt $tokens.Length -and $tokens[$i].Text -cne ')') {
                while ($true) {
                    if ($i -ge $tokens.Length -or $tokens[$i].Kind -ne 'Identifier') { $script:SourceDisplay = $Module.Path; $cur = $tokens[[Math]::Min($i, $tokens.Length - 1)]; Throw-SourceError -Line $cur.Line -Column $cur.Column -Message 'Expected a parameter name.' }
                    $paramToken = $tokens[$i]
                    if (@('print', 'let', 'fn', 'return', 'import', 'if', 'else', 'while') -contains $paramToken.Text) { $script:SourceDisplay = $Module.Path; Throw-SourceError -Line $paramToken.Line -Column $paramToken.Column -Message 'Reserved keyword cannot be used as a parameter name.' }
                    if (-not $seen.Add([string]$paramToken.Text)) { $script:SourceDisplay = $Module.Path; Throw-SourceError -Line $paramToken.Line -Column $paramToken.Column -Message ("Duplicate parameter '{0}'." -f $paramToken.Text) }
                    $params.Add($paramToken); $i++
                    if ($i -lt $tokens.Length -and $tokens[$i].Text -ceq ',') { $i++; continue }; break
                }
            }
            if ($i -ge $tokens.Length -or $tokens[$i].Text -cne ')') { $script:SourceDisplay = $Module.Path; Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message "Expected ')' after function parameters." }; $i++
            $legacyBaselineMode = [string]::Equals([Environment]::GetEnvironmentVariable('SHARNOU_BASELINE_M1_M6'), '1', [StringComparison]::Ordinal)
            if ($params.Count -gt 16 -or ($legacyBaselineMode -and $params.Count -gt 4)) {
                $script:SourceDisplay = $Module.Path
                if ($legacyBaselineMode) {
                    Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message 'Historical M1-M6 compatibility mode permits at most four integer function parameters.'
                }
                Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message 'Sharnou functions support at most 16 integer parameters (four register arguments and twelve stack arguments under the Windows x64 ABI).'
            }
            if ($i -ge $tokens.Length -or $tokens[$i].Text -cne '{') { $script:SourceDisplay = $Module.Path; Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message "Expected '{' to start the function body." }
            $bodyOpen = $i; $i++; $braceDepth = 1
            while ($i -lt $tokens.Length -and $braceDepth -gt 0) {
                if ($tokens[$i].Text -ceq '{') { $braceDepth++ }
                elseif ($tokens[$i].Text -ceq '}') { $braceDepth-- }
                $i++
            }
            if ($braceDepth -ne 0) { $script:SourceDisplay = $Module.Path; Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message 'Unterminated function body; expected }.' }
            $bodyClose = $i - 1
            if ($script:Builtins.ContainsKey($name)) { $script:SourceDisplay = $Module.Path; Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message ("Function name '{0}' is reserved for a Sharnou standard-library intrinsic." -f $name) }; if ($script:Functions.ContainsKey($name)) { $script:SourceDisplay = $Module.Path; Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message ("Function '{0}' is already defined in another module or scope." -f $name) }
            $index = $script:FunctionIndex; $script:FunctionIndex++
            $functionObject = [pscustomobject]@{ Name = $name; ModulePath = $Module.Path; Module = $Module; HeaderIndex = [int]$functionStart; BodyOpenIndex = $bodyOpen; BodyCloseIndex = $bodyClose; Parameters = $params.ToArray(); Label = ("__sharnou_fn_{0}_{1}" -f $index, $name); Context = $null; BodyStatements = @(); ReturnExpression = $null; Index = $index }
            $script:Functions.Add($name, $functionObject)
            continue
        }
        if ($token.Text -ceq '{') { $depth++ }
        elseif ($token.Text -ceq '}') { $depth-- }
        $i++
    }
}
function Parse-BlockStatement {
    $open = Expect-Text -Text '{' -Description "'{' to start a lexical block"
    Push-Scope; $script:BlockDepth++
    $statements = [System.Collections.Generic.List[object]]::new()
    while (-not (Test-CurrentText '}')) {
        $token = Get-CurrentToken
        if ($token.Kind -eq 'EOF') { Throw-SourceError -Line $open.Line -Column $open.Column -Message 'Unterminated block; expected }.' }
        $statements.Add((Parse-Statement))
    }
    $null = Expect-Text -Text '}' -Description "'}' to close a lexical block"
    $script:BlockDepth--; Pop-Scope
    return (New-Statement -Kind 'Block' -Statements ($statements.ToArray()) -Line $open.Line -Column $open.Column)
}
function Parse-Statement {
    $token = Get-CurrentToken
    if ($token.Text -ceq '{') { return (Parse-BlockStatement) }
    if ($token.Kind -ne 'Identifier') { Throw-SourceError -Line $token.Line -Column $token.Column -Message ("Expected a statement; found '{0}'." -f $token.Text) }
    if ($token.Text -ceq 'import' -or $token.Text -ceq 'fn') { Throw-SourceError -Line $token.Line -Column $token.Column -Message 'Imports and function definitions are only valid at module scope.' }
    if ($token.Text -ceq 'if') {
        Move-NextToken | Out-Null
        $null = Expect-Text -Text '(' -Description "'(' after if"
        $condition = Parse-Expression
        if ($condition.Type -ne 'Integer') { Throw-SourceError -Line $token.Line -Column $token.Column -Message 'if condition must be an integer expression or comparison.' }
        Validate-ConstantArithmetic -Node $condition
        $null = Expect-Text -Text ')' -Description "')' after if condition"
        $thenBlock = Parse-BlockStatement
        $elseStatements = @()
        if (Test-CurrentText 'else') {
            Move-NextToken | Out-Null
            $elseBlock = Parse-BlockStatement
            $elseStatements = @($elseBlock.Statements)
        }
        return (New-Statement -Kind 'If' -Expression $condition -Statements @($thenBlock.Statements) -ElseStatements $elseStatements -Line $token.Line -Column $token.Column)
    }
    if ($token.Text -ceq 'while') {
        Move-NextToken | Out-Null
        $null = Expect-Text -Text '(' -Description "'(' after while"
        $condition = Parse-Expression
        if ($condition.Type -ne 'Integer') { Throw-SourceError -Line $token.Line -Column $token.Column -Message 'while condition must be an integer expression or comparison.' }
        Validate-ConstantArithmetic -Node $condition
        $null = Expect-Text -Text ')' -Description "')' after while condition"
        $body = Parse-BlockStatement
        return (New-Statement -Kind 'While' -Expression $condition -Statements @($body.Statements) -Line $token.Line -Column $token.Column)
    }
    if ($token.Text -ceq 'print') {
        Move-NextToken | Out-Null; $null = Expect-Text -Text '(' -Description "'(' after print"; $expression = Parse-Expression; Validate-ConstantArithmetic -Node $expression; $null = Expect-Text -Text ')' -Description "')' after print expression"; $null = Expect-Text -Text ';' -Description "';' after print statement"
        return (New-Statement -Kind 'Print' -Expression $expression -Line $token.Line -Column $token.Column)
    }
    if ($token.Text -ceq 'let') {
        Move-NextToken | Out-Null; $nameToken = Get-CurrentToken
        if ($nameToken.Kind -ne 'Identifier' -or @('print', 'let', 'fn', 'return', 'import', 'if', 'else', 'while') -contains $nameToken.Text) { Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message "Expected a variable name after 'let'." }
        Move-NextToken | Out-Null; $name = [string]$nameToken.Text
        $null = Expect-Text -Text '=' -Description "'=' in variable declaration"
        $expression = Parse-Expression; Validate-ConstantArithmetic -Node $expression; $null = Expect-Text -Text ';' -Description "';' after variable declaration"
        $symbol = Declare-Variable -Name $name -Type $expression.Type -Line $nameToken.Line -Column $nameToken.Column
        return (New-Statement -Kind 'Let' -Name $name -Type $symbol.Type -Slot $symbol.Slot -Expression $expression -Line $nameToken.Line -Column $nameToken.Column)
    }
    if ($token.Text -ceq 'return') {
        if ($null -eq $script:CurrentFunction) { Throw-SourceError -Line $token.Line -Column $token.Column -Message 'return is only valid inside a function.' }
        if ($script:BlockDepth -ne 0) { Throw-SourceError -Line $token.Line -Column $token.Column -Message 'return must appear at the top level of a function body in the current language subset.' }
        Move-NextToken | Out-Null; $expression = Parse-Expression; Validate-ConstantArithmetic -Node $expression
        if ($expression.Type -ne 'Integer') { Throw-SourceError -Line $token.Line -Column $token.Column -Message 'Function return values must be integers in the current language subset.' }
        $null = Expect-Text -Text ';' -Description "';' after return statement"
        return (New-Statement -Kind 'Return' -Expression $expression -Line $token.Line -Column $token.Column)
    }
    if (@('print', 'let', 'fn', 'return', 'import', 'if', 'else', 'while') -contains $token.Text) { Throw-SourceError -Line $token.Line -Column $token.Column -Message 'Reserved keyword cannot be used as a variable name.' }
    $nameToken = Move-NextToken; $name = [string]$nameToken.Text
    if (-not (Test-CurrentText '=')) { $next = Get-CurrentToken; Throw-SourceError -Line $next.Line -Column $next.Column -Message ("Expected '=' after variable name '{0}'; only assignment, declarations, and print statements are supported." -f $name) }
    $symbol = Find-Variable -Name $name
    if ($null -eq $symbol) { Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message ("Cannot assign to undefined variable '{0}'. Use let to declare it first." -f $name) }
    Move-NextToken | Out-Null; $expression = Parse-Expression; Validate-ConstantArithmetic -Node $expression; $null = Expect-Text -Text ';' -Description "';' after assignment"
    if ($symbol.Type -ne $expression.Type) { Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message ("Assignment changes variable '{0}' from {1} to {2}; variable types are fixed after declaration." -f $name, $symbol.Type, $expression.Type) }
    return (New-Statement -Kind 'Assign' -Name $name -Type $symbol.Type -Slot $symbol.Slot -Expression $expression -Line $nameToken.Line -Column $nameToken.Column)
}
function Parse-FunctionDeclaration {
    $oldScopes = $script:Scopes; $oldContext = $script:ActiveContext; $oldFunction = $script:CurrentFunction; $oldBlockDepth = $script:BlockDepth
    $fnToken = Move-NextToken; $nameToken = Move-NextToken; $name = [string]$nameToken.Text
    if (-not $script:Functions.ContainsKey($name)) { Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message ("Function '{0}' was not registered during declaration scan." -f $name) }
    $func = $script:Functions[$name]
    if (-not [string]::Equals($func.ModulePath, $script:CurrentModule.Path, [System.StringComparison]::OrdinalIgnoreCase)) { Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message 'Internal module/function ownership mismatch.' }
    $null = Expect-Text -Text '(' -Description "'(' after function name"
    $paramNames = [System.Collections.Generic.List[string]]::new()
    if (-not (Test-CurrentText ')')) {
        while ($true) {
            $paramToken = Get-CurrentToken
            if ($paramToken.Kind -ne 'Identifier') { Throw-SourceError -Line $paramToken.Line -Column $paramToken.Column -Message 'Expected a parameter name.' }
            $paramNames.Add([string]$paramToken.Text); Move-NextToken | Out-Null
            if (Test-CurrentText ',') { Move-NextToken | Out-Null; continue }; break
        }
    }
    $null = Expect-Text -Text ')' -Description "')' after parameters"
    if ($paramNames.Count -ne $func.Parameters.Count) { Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message 'Function header changed between declaration scan and parse.' }
    for ($i = 0; $i -lt $paramNames.Count; $i++) { if ($paramNames[$i] -cne $func.Parameters[$i].Text) { Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message 'Function parameter list changed between declaration scan and parse.' } }
    $open = Expect-Text -Text '{' -Description "'{' before function body"
    $script:Scopes = [System.Collections.Generic.List[object]]::new(); Push-Scope; $script:BlockDepth = 0; $script:CurrentFunction = $func
    $context = [pscustomobject]@{ Name = $name; SlotCount = 0; TempSlots = 0; ScratchPosition = 0; FrameSize = 0; Statements = [System.Collections.Generic.List[object]]::new() }
    $script:ActiveContext = $context
    for ($i = 0; $i -lt $paramNames.Count; $i++) {
        $pt = $func.Parameters[$i]
        $symbol = Declare-Variable -Name $paramNames[$i] -Type 'Integer' -Line $pt.Line -Column $pt.Column
        if ($symbol.Slot -ne $i) { throw 'Internal parameter slot assignment error.' }
    }
    $returnExpression = $null
    while (-not (Test-CurrentText '}')) {
        $current = Get-CurrentToken
        if ($current.Kind -eq 'EOF') { Throw-SourceError -Line $open.Line -Column $open.Column -Message 'Unterminated function body; expected }.' }
        $statement = Parse-Statement
        if ($statement.Kind -eq 'Return') {
            $returnExpression = $statement.Expression
            if (-not (Test-CurrentText '}')) { $next = Get-CurrentToken; Throw-SourceError -Line $next.Line -Column $next.Column -Message 'return must be the final statement in a function in the current language subset.' }
            break
        }
        $context.Statements.Add($statement)
    }
    $null = Expect-Text -Text '}' -Description "'}' after function body"
    if ($null -eq $returnExpression) { Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message ("Function '{0}' must end with 'return integerExpression;'." -f $name) }
    $func.Context = $context; $func.BodyStatements = $context.Statements.ToArray(); $func.ReturnExpression = $returnExpression
    $script:Scopes = $oldScopes; $script:ActiveContext = $oldContext; $script:CurrentFunction = $oldFunction; $script:BlockDepth = $oldBlockDepth
}
function Parse-Module {
    param([object] $Module)
    $script:CurrentModule = $Module; $script:SourceDisplay = $Module.Path; $script:Tokens = $Module.Tokens; $script:TokenIndex = [int]$Module.BodyStartIndex
    while ((Get-CurrentToken).Kind -ne 'EOF') {
        $token = Get-CurrentToken
        if ($token.Kind -eq 'Identifier' -and $token.Text -ceq 'fn') { Parse-FunctionDeclaration; continue }
        if (-not $Module.IsRoot) { Throw-SourceError -Line $token.Line -Column $token.Column -Message 'Imported modules may contain function definitions and imports only; executable statements belong in the root source.' }
        $statement = Parse-Statement
        $script:MainStatements.Add($statement)
    }
}
function Get-ExpressionNodeCount {
    param([object] $Node)
    if ($null -eq $Node) { return 0 }
    $count = 1
    if ($Node.Kind -eq 'Binary' -or $Node.Kind -eq 'Comparison') { $count += (Get-ExpressionNodeCount -Node $Node.Left); $count += (Get-ExpressionNodeCount -Node $Node.Right) }
    elseif ($Node.Kind -eq 'Unary') { $count += (Get-ExpressionNodeCount -Node $Node.Operand) }
    elseif ($Node.Kind -eq 'Call') { foreach ($arg in $Node.Arguments) { $count += (Get-ExpressionNodeCount -Node $arg) } }
    return [int]$count
}
function Get-StatementsNodeCount {
    param([object[]] $Statements, [object] $ReturnExpression = $null)
    $count = 0
    foreach ($statement in $Statements) {
        if ($null -ne $statement.Expression) { $count += (Get-ExpressionNodeCount -Node $statement.Expression) }
        if ($null -ne $statement.Statements -and $statement.Statements.Count -gt 0) { $count += (Get-StatementsNodeCount -Statements $statement.Statements) }
        if ($null -ne $statement.ElseStatements -and $statement.ElseStatements.Count -gt 0) { $count += (Get-StatementsNodeCount -Statements $statement.ElseStatements) }
    }
    if ($null -ne $ReturnExpression) { $count += (Get-ExpressionNodeCount -Node $ReturnExpression) }
    return [int]$count
}
function Align-Up {
    param([int] $Value, [int] $Alignment)
    if ($Value -lt 0 -or $Alignment -le 0) { throw 'Invalid alignment request.' }
    return [int]([Math]::Ceiling([double]$Value / [double]$Alignment) * $Alignment)
}
function Emit-Bytes { param([byte[]] $Bytes) $script:Code.AddRange($Bytes) }
function Emit-I32 { param([long] $Value) if ($Value -lt [int]::MinValue -or $Value -gt [int]::MaxValue) { throw "Internal signed 32-bit immediate or displacement is out of range: $Value" }; $script:Code.AddRange([BitConverter]::GetBytes([int32]$Value)) }
function Emit-CallIat {
    param([UInt32] $TargetRva)
    # Call sites pass the stable Milestone 4 import RVA (base 0x3000).
    # Defer the displacement until the linker has selected the final .idata RVA.
    if ($TargetRva -lt 0x3000 -or $TargetRva -ge 0x4000) { throw ("Invalid canonical IAT target RVA: 0x{0:X8}." -f $TargetRva) }
    Emit-Bytes -Bytes ([byte[]]@(0xFF, 0x15))
    $dispOffset = $script:Code.Count
    Emit-I32 -Value 0
    $script:CodeFixups.Add([pscustomobject]@{ Kind = 'Iat'; DispOffset = $dispOffset; TargetOffset = [int]([long]$TargetRva - 0x3000) })
}
function Emit-DataAddress {
    param([object] $DataItem)
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8D, 0x05)); $dispOffset = $script:Code.Count; Emit-I32 -Value 0
    $script:CodeFixups.Add([pscustomobject]@{ Kind = 'Data'; DispOffset = $dispOffset; Target = $DataItem })
}
function Emit-CallDataPointer {
    param([object] $DataItem)
    if ($null -eq $DataItem -or $DataItem.Bytes.Length -ne 8) {
        throw 'Typed callback pointer call requires an eight-byte data pointer item.'
    }
    Emit-Bytes -Bytes ([byte[]]@(0xFF, 0x15))
    $dispOffset = $script:Code.Count
    Emit-I32 -Value 0
    $script:CodeFixups.Add([pscustomobject]@{ Kind = 'Data'; DispOffset = $dispOffset; Target = $DataItem })
}
function Emit-LoadDataPointer {
    param([object] $DataItem)
    if ($null -eq $DataItem -or $DataItem.Bytes.Length -ne 8) {
        throw 'Typed callback pointer load requires an eight-byte data pointer item.'
    }
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8B, 0x05))
    $dispOffset = $script:Code.Count
    Emit-I32 -Value 0
    $script:CodeFixups.Add([pscustomobject]@{ Kind = 'Data'; DispOffset = $dispOffset; Target = $DataItem })
}
function Emit-JumpConditional {
    param([byte] $ConditionCode, [string] $Label)
    Emit-Bytes -Bytes ([byte[]]@(0x0F, $ConditionCode)); $dispOffset = $script:Code.Count; Emit-I32 -Value 0
    $script:CodeFixups.Add([pscustomobject]@{ Kind = 'Code'; DispOffset = $dispOffset; Target = $Label })
}
function Emit-Jump {
    param([string] $Label)
    Emit-Bytes -Bytes ([byte[]]@(0xE9)); $dispOffset = $script:Code.Count; Emit-I32 -Value 0
    $script:CodeFixups.Add([pscustomobject]@{ Kind = 'Code'; DispOffset = $dispOffset; Target = $Label })
}
function New-UniqueLabel {
    param([string] $Prefix)
    $label = '__' + $Prefix + '_' + [string]$script:UniqueLabel
    $script:UniqueLabel++
    return $label
}
function Emit-StackArgumentImmediate {
    param([int] $Offset, [long] $Value)
    if ($Offset -lt 0x20 -or $Offset -gt 0x78 -or ($Offset % 8) -ne 0) { throw "Invalid Windows x64 stack argument offset: $Offset" }
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0xC7, 0x44, 0x24, [byte]$Offset)); Emit-I32 -Value $Value
}
function Emit-StackArgumentRax {
    param([int] $Offset)
    if ($Offset -lt 0x20 -or $Offset -gt 0x78 -or ($Offset % 8) -ne 0) { throw "Invalid Windows x64 stack argument offset: $Offset" }
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0x44, 0x24, [byte]$Offset))
}
function Emit-Win64CallIat {
    param([UInt32] $TargetRva, [object[]] $StackArguments = @())
    if ($StackArguments.Count -gt 12) { throw "Windows x64 IAT calls support at most 12 stack arguments; received $($StackArguments.Count)." }
    # Reserve shadow space plus all stack arguments, rounded to 16 bytes.
    $callFrameSize = Align-Up -Value (0x20 + ($StackArguments.Count * 8)) -Alignment 0x10
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x81, 0xEC))
    Emit-I32 -Value $callFrameSize
    for ($i = 0; $i -lt $StackArguments.Count; $i++) {
        $argument = $StackArguments[$i]
        switch ([string]$argument.Kind) {
            'Immediate' {
                Emit-Bytes -Bytes ([byte[]]@(0x48, 0xB8))
                Emit-Bytes -Bytes ([BitConverter]::GetBytes([Int64]$argument.Value))
            }
            'FrameAddress' { Emit-LeaRaxFrame -SlotPosition ([int]$argument.SlotPosition) }
            'FrameQword' { Emit-LoadRaxFrame -SlotPosition ([int]$argument.SlotPosition) }
            'FrameDword' { Emit-LoadEaxFrame -SlotPosition ([int]$argument.SlotPosition) }
            'DataAddress' { Emit-DataAddress -DataItem $argument.DataItem }
            'CodeAddress' { Emit-LeaRaxCodeLabel -Label ([string]$argument.Label) }
            default { throw "Unsupported Windows x64 stack-argument descriptor kind: '$($argument.Kind)'." }
        }
        Emit-StackArgumentRax -Offset (0x20 + ($i * 8))
    }
    Emit-CallIat -TargetRva $TargetRva
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x81, 0xC4))
    Emit-I32 -Value $callFrameSize
}
function Emit-LoadRdiFrame { param([int] $SlotPosition) Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8B, 0xBD)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $SlotPosition) }
function Emit-StoreRdiFrame { param([int] $SlotPosition) Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xBD)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $SlotPosition) }
function Emit-LoadRsiFrame { param([int] $SlotPosition) Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8B, 0xB5)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $SlotPosition) }
function Emit-StoreRsiFrame { param([int] $SlotPosition) Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xB5)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $SlotPosition) }
function Emit-LeaRaxFrame { param([int] $SlotPosition) Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8D, 0x85)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $SlotPosition) }
function Emit-LeaR8CodeLabel {
    param([string] $Label)
    Emit-Bytes -Bytes ([byte[]]@(0x4C, 0x8D, 0x05)); $dispOffset = $script:Code.Count; Emit-I32 -Value 0
    $script:CodeFixups.Add([pscustomobject]@{ Kind = 'Code'; DispOffset = $dispOffset; Target = $Label })
}
function Emit-LeaRaxCodeLabel {
    param([string] $Label)
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8D, 0x05))
    $dispOffset = $script:Code.Count
    Emit-I32 -Value 0
    $script:CodeFixups.Add([pscustomobject]@{ Kind = 'Code'; DispOffset = $dispOffset; Target = $Label })
}
function Emit-CallFunction {
    param([string] $Name)
    if (-not $script:Functions.ContainsKey($Name)) { throw "Internal linker error: unresolved function symbol '$Name'." }
    Emit-Bytes -Bytes ([byte[]]@(0xE8)); $dispOffset = $script:Code.Count; Emit-I32 -Value 0
    $script:CodeFixups.Add([pscustomobject]@{ Kind = 'Call'; DispOffset = $dispOffset; Target = $script:Functions[$Name].Label })
}
function Mark-CodeLabel { param([string] $Label) if ($script:CodeLabels.ContainsKey($Label)) { throw "Duplicate internal code label: $Label" }; $script:CodeLabels.Add($Label, $script:Code.Count) }
function Get-FrameDisp {
    param([int] $SlotPosition)
    $disp = [long]$SlotPosition - [long]$script:ActiveContext.FrameSize
    if ($disp -ge 0 -or $disp -lt [int]::MinValue) { throw "Invalid stack-frame slot position: $SlotPosition" }
    return [int32]$disp
}
function Emit-LoadEaxFrame { param([int] $SlotPosition) Emit-Bytes -Bytes ([byte[]]@(0x8B, 0x85)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $SlotPosition) }
function Emit-StoreEaxFrame { param([int] $SlotPosition) Emit-Bytes -Bytes ([byte[]]@(0x89, 0x85)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $SlotPosition) }
function Emit-LoadEdxFrame { param([int] $SlotPosition) Emit-Bytes -Bytes ([byte[]]@(0x8B, 0x95)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $SlotPosition) }
function Emit-StoreEdxFrame { param([int] $SlotPosition) Emit-Bytes -Bytes ([byte[]]@(0x89, 0x95)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $SlotPosition) }
function Emit-StoreEcxFrame { param([int] $SlotPosition) Emit-Bytes -Bytes ([byte[]]@(0x89, 0x8D)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $SlotPosition) }
function Emit-StoreR8dFrame { param([int] $SlotPosition) Emit-Bytes -Bytes ([byte[]]@(0x44, 0x89, 0x85)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $SlotPosition) }
function Emit-StoreR9dFrame { param([int] $SlotPosition) Emit-Bytes -Bytes ([byte[]]@(0x44, 0x89, 0x8D)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $SlotPosition) }
function Emit-LoadRaxFrame { param([int] $SlotPosition) Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8B, 0x85)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $SlotPosition) }
function Emit-StoreRaxFrame { param([int] $SlotPosition) Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0x85)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $SlotPosition) }
function Emit-LoadRcxFrame { param([int] $SlotPosition) Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8B, 0x8D)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $SlotPosition) }
function Emit-LeaRcxFrame { param([int] $SlotPosition) Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8D, 0x8D)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $SlotPosition) }
function Emit-LeaRdxFrame { param([int] $SlotPosition) Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8D, 0x95)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $SlotPosition) }
function Emit-LeaR9Frame { param([int] $SlotPosition) Emit-Bytes -Bytes ([byte[]]@(0x4C, 0x8D, 0x8D)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $SlotPosition) }
function Emit-StoreBits32Frame {
    param([int] $SlotPosition, [UInt32] $Value)
    Emit-Bytes -Bytes ([byte[]]@(0xC7, 0x85))
    Emit-I32 -Value (Get-FrameDisp -SlotPosition $SlotPosition)
    $script:Code.AddRange([BitConverter]::GetBytes([UInt32]$Value))
}
function Emit-StoreZero64Frame {
    param([int] $SlotPosition)
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0xC7, 0x85))
    Emit-I32 -Value (Get-FrameDisp -SlotPosition $SlotPosition)
    Emit-I32 -Value 0
}
function Emit-StoreImm64Frame {
    param([int] $SlotPosition, [UInt64] $Value)
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0xB8))
    $script:Code.AddRange([BitConverter]::GetBytes([UInt64]$Value))
    Emit-StoreRaxFrame -SlotPosition $SlotPosition
}
function Register-DataConstant {
    param([string] $Value)
    if ($script:DataMap.ContainsKey($Value)) { return $script:DataMap[$Value] }
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($Value); $itemBytes = [byte[]]::new($bytes.Length + 1)
    if ($bytes.Length -gt 0) { [System.Buffer]::BlockCopy($bytes, 0, $itemBytes, 0, $bytes.Length) }
    $item = [pscustomobject]@{ Value = $Value; Offset = $script:DataLength; Bytes = $itemBytes }
    $script:DataItems.Add($item); $script:DataMap.Add($Value, $item); $script:DataLength += $itemBytes.Length
    return $item
}
function Register-WideDataConstant {
    param([string] $Value)
    $key = 'WIDE:' + $Value
    if ($script:DataMap.ContainsKey($key)) { return $script:DataMap[$key] }
    $bytes = [System.Text.Encoding]::Unicode.GetBytes($Value + [char]0)
    $itemBytes = [byte[]]::new($bytes.Length)
    if ($bytes.Length -gt 0) { [System.Buffer]::BlockCopy($bytes, 0, $itemBytes, 0, $bytes.Length) }
    $item = [pscustomobject]@{ Value = $key; Offset = $script:DataLength; Bytes = $itemBytes }
    $script:DataItems.Add($item); $script:DataMap.Add($key, $item); $script:DataLength += $itemBytes.Length
    return $item
}
function Register-ByteDataConstant {
    param([string] $Key, [byte[]] $Bytes)
    if ($script:DataMap.ContainsKey($Key)) { return $script:DataMap[$Key] }
    $itemBytes = [byte[]]::new($Bytes.Length)
    if ($Bytes.Length -gt 0) { [System.Buffer]::BlockCopy($Bytes, 0, $itemBytes, 0, $Bytes.Length) }
    $item = [pscustomobject]@{ Value = $Key; Offset = $script:DataLength; Bytes = $itemBytes }
    $script:DataItems.Add($item); $script:DataMap.Add($Key, $item); $script:DataLength += $itemBytes.Length
    return $item
}
function Register-DataPointerFixup {
    param(
        [Parameter(Mandatory = $true)][string] $Key,
        [Parameter(Mandatory = $true)][object] $DataItem,
        [int] $SlotOffset = 0,
        [Parameter(Mandatory = $true)][ValidateSet('Code', 'Data')][string] $TargetKind,
        [string] $Label,
        [object] $TargetItem,
        [string] $Signature
    )

    if ($null -eq $DataItem -or $null -eq $DataItem.Bytes -or
        $SlotOffset -lt 0 -or ($SlotOffset + 8) -gt $DataItem.Bytes.Length) {
        throw "Data-pointer fixup '$Key' does not identify a complete eight-byte slot."
    }
    if (([UInt64]$DataItem.Offset + [UInt64]$SlotOffset) % 8 -ne 0) {
        throw "Data-pointer fixup '$Key' is not eight-byte aligned."
    }
    if (@($script:DataPointerFixups | Where-Object { $_.Key -ceq $Key }).Count -ne 0) {
        throw "Duplicate data-pointer fixup key: $Key"
    }
    if ($TargetKind -eq 'Code') {
        if ([string]::IsNullOrEmpty($Label) -or -not $Label.StartsWith('__', [StringComparison]::Ordinal)) {
            throw "Code-pointer fixup '$Key' must target a compiler-owned internal label."
        }
        if ($Signature -cnotin @('SERVICE_MAIN_FUNCTIONW', 'HANDLER_FUNCTION_EX')) {
            throw "Code-pointer fixup '$Key' uses an unsupported callback signature."
        }
    } else {
        if ($null -eq $TargetItem -or $null -eq $TargetItem.Bytes -or $TargetItem.Bytes.Length -lt 1) {
            throw "Data-pointer fixup '$Key' has no initialized data target."
        }
    }

    $script:DataPointerFixups.Add([pscustomobject]@{
        Key = $Key
        DataItem = $DataItem
        SlotOffset = $SlotOffset
        TargetKind = $TargetKind
        Label = $Label
        TargetItem = $TargetItem
        Signature = $Signature
        TargetRva = [UInt32]0
    })
}
function Register-CodeCallbackPointer {
    param(
        [Parameter(Mandatory = $true)][string] $Key,
        [Parameter(Mandatory = $true)][string] $Label,
        [Parameter(Mandatory = $true)][ValidateSet('SERVICE_MAIN_FUNCTIONW', 'HANDLER_FUNCTION_EX')][string] $Signature
    )

    $existing = @($script:DataPointerFixups | Where-Object { $_.Key -ceq $Key })
    if ($existing.Count -gt 0) {
        if ($existing.Count -ne 1 -or $existing[0].Label -cne $Label -or $existing[0].Signature -cne $Signature -or $existing[0].TargetKind -cne 'Code') {
            throw "Callback pointer key '$Key' was registered with conflicting target metadata."
        }
        return $existing[0].DataItem
    }
    if ($script:DataMap.ContainsKey($Key)) { throw "Callback pointer data key collides with an existing constant: $Key" }
    if (-not $Label.StartsWith('__', [StringComparison]::Ordinal)) {
        throw 'Typed callback targets must use a compiler-owned internal code label.'
    }

    $padding = (8 - ($script:DataLength % 8)) % 8
    if ($padding -gt 0) {
        if (($script:DataLength + $padding + 8) -gt 0x1000) { throw 'Callback pointer table exceeds .rdata capacity.' }
        $paddingBytes = [byte[]]::new($padding)
        $paddingItem = [pscustomobject]@{ Value = $Key + ':ALIGN'; Offset = $script:DataLength; Bytes = $paddingBytes }
        $script:DataItems.Add($paddingItem)
        $script:DataMap.Add($paddingItem.Value, $paddingItem)
        $script:DataLength += $padding
    }

    if (($script:DataLength + 8) -gt 0x1000) { throw 'Callback pointer table exceeds .rdata capacity.' }
    $pointerBytes = [byte[]]::new(8)
    $item = [pscustomobject]@{ Value = $Key; Offset = $script:DataLength; Bytes = $pointerBytes }
    $script:DataItems.Add($item)
    $script:DataMap.Add($Key, $item)
    $script:DataLength += 8
    Register-DataPointerFixup -Key $Key -DataItem $item -SlotOffset 0 -TargetKind Code -Label $Label -Signature $Signature
    return $item
}
function Get-TempSlotPosition {
    param([int] $Depth)
    return [int](0x80 + ([int]$script:ActiveContext.SlotCount * 16) + ($Depth * 16))
}
function Emit-CreateFileForPath {
    param([int] $PathSlot, [switch] $OpenReparsePoint)
    Emit-LoadRaxFrame -SlotPosition $PathSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1)) # RCX = path
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x00, 0x00, 0x00, 0x80)) # GENERIC_READ
    Emit-Bytes -Bytes ([byte[]]@(0x41, 0xB8, 0x01, 0x00, 0x00, 0x00)) # FILE_SHARE_READ
    Emit-Bytes -Bytes ([byte[]]@(0x45, 0x33, 0xC9)) # lpSecurityAttributes = NULL
    $fileFlags = [UInt32]0x80 # FILE_ATTRIBUTE_NORMAL
    if ($OpenReparsePoint) { $fileFlags = [UInt32]0x00200080 } # FILE_FLAG_OPEN_REPARSE_POINT
    Emit-Win64CallIat -TargetRva ([UInt32]0x30A0) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 3 },
        @{ Kind = 'Immediate'; Value = $fileFlags },
        @{ Kind = 'Immediate'; Value = 0 }
    ) # CreateFileA
}
function Emit-BuiltinArguments {
    param([object] $Node, [int] $BaseDepth)
    for ($i = 0; $i -lt $Node.Arguments.Count; $i++) {
        $argument = $Node.Arguments[$i]
        if ($argument.Type -eq 'String') {
            Emit-StringExpression -Node $argument
            $slot = Get-TempSlotPosition -Depth $script:TempDepth
            Emit-StoreRaxFrame -SlotPosition $slot
            Emit-StoreEdxFrame -SlotPosition ($slot + 8)
        } else {
            Emit-IntegerExpression -Node $argument
            Emit-StoreEaxFrame -SlotPosition (Get-TempSlotPosition -Depth $script:TempDepth)
        }
        $script:TempDepth++
    }
}
function Emit-CopyDataConstantToFrame {
    param([object] $DataItem, [int] $SlotPosition, [int] $Length)
    if ($Length -lt 0 -or $Length -gt 1023) { throw "Invalid fixed command/data copy length: $Length" }
    Emit-DataAddress -DataItem $DataItem
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC6)) # RSI = immutable source
    Emit-LeaRaxFrame -SlotPosition $SlotPosition
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC7)) # RDI = mutable destination
    Emit-Bytes -Bytes ([byte[]]@(0xB9))
    Emit-I32 -Value $Length
    Emit-Bytes -Bytes ([byte[]]@(0xF3, 0xA4, 0xC6, 0x07, 0x00)) # REP MOVSB; append NUL
}
function Emit-NonvolatileRegisterProbe {
    param([object] $Node, [int] $BaseDepth)
    $targetName = 'abi_nonvolatile_target'
    if (-not $script:Functions.ContainsKey($targetName)) {
        Throw-SourceError -Line $Node.Line -Column $Node.Column -Message "The ABI sentinel probe requires a zero-argument function named '$targetName'."
    }
    if ($script:Functions[$targetName].Parameters.Count -ne 0) {
        Throw-SourceError -Line $Node.Line -Column $Node.Column -Message "The ABI sentinel target '$targetName' must not declare parameters."
    }
    $slots = @()
    for ($i = 0; $i -lt 8; $i++) { $slots += (Get-TempSlotPosition -Depth ($BaseDepth + $i)) }
    # Save the complete Windows x64 nonvolatile register set, including the
    # active RBP frame pointer, into caller-owned frame slots.
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xAD)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $slots[0]) # RBP
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0x9D)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $slots[1]) # RBX
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xB5)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $slots[2]) # RSI
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xBD)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $slots[3]) # RDI
    Emit-Bytes -Bytes ([byte[]]@(0x4C, 0x89, 0xA5)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $slots[4]) # R12
    Emit-Bytes -Bytes ([byte[]]@(0x4C, 0x89, 0xAD)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $slots[5]) # R13
    Emit-Bytes -Bytes ([byte[]]@(0x4C, 0x89, 0xB5)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $slots[6]) # R14
    Emit-Bytes -Bytes ([byte[]]@(0x4C, 0x89, 0xBD)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $slots[7]) # R15

    $sentinels = @([UInt32]0x11223344, [UInt32]0x22334455, [UInt32]0x33445566, [UInt32]0x44556677, [UInt32]0x55667788, [UInt32]0x66778899, [UInt32]0x778899AA)
    $loadOpcodes = @(
        [byte[]]@(0x48, 0xBB), [byte[]]@(0x48, 0xBE), [byte[]]@(0x48, 0xBF),
        [byte[]]@(0x49, 0xBC), [byte[]]@(0x49, 0xBD), [byte[]]@(0x49, 0xBE), [byte[]]@(0x49, 0xBF)
    )
    for ($i = 0; $i -lt $sentinels.Count; $i++) {
        Emit-Bytes -Bytes $loadOpcodes[$i]
        Emit-Bytes -Bytes ([BitConverter]::GetBytes([UInt64]$sentinels[$i]))
    }
    # Verify live RSP is 16-byte aligned before the call, after reserving
    # shadow space, and after return. Exercise a generated function containing
    # RSI/RDI-using intrinsics while all nonvolatile registers hold sentinels.
    $fail = New-UniqueLabel -Prefix 'abi_nonvolatile_fail'
    $done = New-UniqueLabel -Prefix 'abi_nonvolatile_done'
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xE0, 0x83, 0xE0, 0x0F, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $fail
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x20))
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xE0, 0x83, 0xE0, 0x0F, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $fail
    Emit-CallFunction -Name $targetName
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20))
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xE0, 0x83, 0xE0, 0x0F, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $fail

    $compareOpcodes = @(
        [byte[]]@(0x48, 0x81, 0xFB), [byte[]]@(0x48, 0x81, 0xFE), [byte[]]@(0x48, 0x81, 0xFF),
        [byte[]]@(0x49, 0x81, 0xFC), [byte[]]@(0x49, 0x81, 0xFD), [byte[]]@(0x49, 0x81, 0xFE), [byte[]]@(0x49, 0x81, 0xFF)
    )
    for ($i = 0; $i -lt $sentinels.Count; $i++) {
        Emit-Bytes -Bytes $compareOpcodes[$i]
        Emit-I32 -Value ([Int64]$sentinels[$i])
        Emit-JumpConditional -ConditionCode 0x85 -Label $fail
    }
    # RBP is the live frame pointer: compare it to the saved caller value.
    Emit-LoadRaxFrame -SlotPosition $slots[0]
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x39, 0xC5))
    Emit-JumpConditional -ConditionCode 0x85 -Label $fail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x01, 0x00, 0x00, 0x00))
    Emit-Jump -Label $done
    Mark-CodeLabel -Label $fail
    Emit-Bytes -Bytes ([byte[]]@(0x31, 0xC0))
    Mark-CodeLabel -Label $done

    # Restore the caller's original nonvolatile values before returning.
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8B, 0x9D)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $slots[1])
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8B, 0xB5)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $slots[2])
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8B, 0xBD)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $slots[3])
    Emit-Bytes -Bytes ([byte[]]@(0x4C, 0x8B, 0xA5)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $slots[4])
    Emit-Bytes -Bytes ([byte[]]@(0x4C, 0x8B, 0xAD)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $slots[5])
    Emit-Bytes -Bytes ([byte[]]@(0x4C, 0x8B, 0xB5)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $slots[6])
    Emit-Bytes -Bytes ([byte[]]@(0x4C, 0x8B, 0xBD)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $slots[7])
}
function Emit-DevBrokerPathCheck {
    param(
        [object] $DataItem = $null,
        [int] $FrameSlot = -1,
        [bool] $IsDirectory,
        [string] $FailureLabel
    )
    if ($FrameSlot -ge 0) {
        Emit-LeaRaxFrame -SlotPosition $FrameSlot
    }
    else {
        if ($null -eq $DataItem) { throw 'DevAgent path check requires a fixed path.' }
        Emit-DataAddress -DataItem $DataItem
    }
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31C8) -StackArguments @() # GetFileAttributesA
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0xFF, 0xFF, 0xFF, 0xFF))
    Emit-JumpConditional -ConditionCode 0x84 -Label $FailureLabel # INVALID_FILE_ATTRIBUTES
    if ($IsDirectory) {
        Emit-Bytes -Bytes ([byte[]]@(0xA9, 0x10, 0x00, 0x00, 0x00))
        Emit-JumpConditional -ConditionCode 0x84 -Label $FailureLabel # must be a directory
    }
    else {
        Emit-Bytes -Bytes ([byte[]]@(0xA9, 0x10, 0x00, 0x00, 0x00))
        Emit-JumpConditional -ConditionCode 0x85 -Label $FailureLabel # must not be a directory
    }
    Emit-Bytes -Bytes ([byte[]]@(0xA9, 0x00, 0x04, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x85 -Label $FailureLabel # reject FILE_ATTRIBUTE_REPARSE_POINT
}
function Emit-DevBrokerVerifyScript {
    param(
        [object] $PathItem = $null,
        [int] $FrameSlot = -1,
        [string] $ExpectedSha256,
        [int] $PersistentFileHandleSlot,
        [string] $FailureLabel
    )
    if ($ExpectedSha256.Length -ne 64) { throw 'DevAgent script SHA-256 must contain 64 hexadecimal characters.' }
    $scratch = [int]$script:ActiveContext.ScratchPosition
    $pathSlot = $scratch + 0x640
    $sizeSlot = $scratch + 0x648
    $bytesReadSlot = $scratch + 0x650
    $bufferSlot = $scratch + 0x658
    $algorithmSlot = $scratch + 0x660
    $digestSlot = $scratch + 0x680
    $hashFail = New-UniqueLabel -Prefix 'dev_hash_fail'
    $skipAlgorithmCleanup = New-UniqueLabel -Prefix 'dev_hash_skip_algorithm_cleanup'
    $skipBufferCleanup = New-UniqueLabel -Prefix 'dev_hash_skip_buffer_cleanup'
    $skipFileCleanup = New-UniqueLabel -Prefix 'dev_hash_skip_file_cleanup'
    $done = New-UniqueLabel -Prefix 'dev_hash_done'

    Emit-StoreZero64Frame -SlotPosition $PersistentFileHandleSlot
    Emit-StoreZero64Frame -SlotPosition $sizeSlot
    Emit-StoreZero64Frame -SlotPosition $bytesReadSlot
    Emit-StoreZero64Frame -SlotPosition $bufferSlot
    Emit-StoreZero64Frame -SlotPosition $algorithmSlot
    if ($FrameSlot -ge 0) {
        Emit-LeaRaxFrame -SlotPosition $FrameSlot
    } elseif ($null -ne $PathItem) {
        Emit-DataAddress -DataItem $PathItem
    } else {
        throw 'DevAgent script verification requires an absolute frame-backed or fixed path.'
    }
    Emit-StoreRaxFrame -SlotPosition $pathSlot

    # Open for read only and deny concurrent write/delete; retain handle through child completion.
    Emit-CreateFileForPath -PathSlot $pathSlot -OpenReparsePoint
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xF8, 0xFF))
    Emit-JumpConditional -ConditionCode 0x84 -Label $hashFail
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $hashFail
    Emit-StoreRaxFrame -SlotPosition $PersistentFileHandleSlot

    # Inspect the opened object itself, not only the path string. OPEN_REPARSE_POINT
    # prevents CreateFileA from silently following a final-component symbolic link.
    $fileInformationSlot = $scratch + 0x6A0
    Emit-StoreZero64Frame -SlotPosition $fileInformationSlot
    Emit-LoadRcxFrame -SlotPosition $PersistentFileHandleSlot
    Emit-LeaRaxFrame -SlotPosition $fileInformationSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3208) -StackArguments @() # GetFileInformationByHandle
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $hashFail
    Emit-Bytes -Bytes ([byte[]]@(0x8B, 0x85))
    Emit-I32 -Value (Get-FrameDisp -SlotPosition $fileInformationSlot) # dwFileAttributes
    Emit-Bytes -Bytes ([byte[]]@(0xF7, 0xC0))
    Emit-I32 -Value 0x410 # reject FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT
    Emit-JumpConditional -ConditionCode 0x85 -Label $hashFail

    # Bound the exact script size to 1 MiB.
    Emit-LoadRcxFrame -SlotPosition $PersistentFileHandleSlot
    Emit-LeaRaxFrame -SlotPosition $sizeSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-Win64CallIat -TargetRva ([UInt32]0x30A8) -StackArguments @() # GetFileSizeEx
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $hashFail
    Emit-LoadRaxFrame -SlotPosition $sizeSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $hashFail
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x3D))
    Emit-I32 -Value 0x100000
    Emit-JumpConditional -ConditionCode 0x87 -Label $hashFail

    # Allocate and read one bounded buffer. Short reads fail closed.
    Emit-Bytes -Bytes ([byte[]]@(0x31, 0xC9))
    Emit-LoadEaxFrame -SlotPosition $sizeSlot
    Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC2, 0x41, 0xB8, 0x00, 0x30, 0x00, 0x00, 0x41, 0xB9, 0x04, 0x00, 0x00, 0x00))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31D0) -StackArguments @() # VirtualAlloc
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $hashFail
    Emit-StoreRaxFrame -SlotPosition $bufferSlot

    Emit-LoadRcxFrame -SlotPosition $PersistentFileHandleSlot
    Emit-LoadRaxFrame -SlotPosition $bufferSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-LoadEaxFrame -SlotPosition $sizeSlot
    Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC0))
    Emit-LeaRaxFrame -SlotPosition $bytesReadSlot
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x30B0) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 0 }
    ) # ReadFile
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $hashFail
    Emit-LoadEaxFrame -SlotPosition $bytesReadSlot
    Emit-Bytes -Bytes ([byte[]]@(0x3B, 0x85))
    Emit-I32 -Value (Get-FrameDisp -SlotPosition $sizeSlot)
    Emit-JumpConditional -ConditionCode 0x85 -Label $hashFail

    # BCryptOpenAlgorithmProvider(&algorithm, L"SHA256", NULL, 0).
    Emit-LeaRaxFrame -SlotPosition $algorithmSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    $sha256Name = Register-WideDataConstant -Value 'SHA256'
    Emit-DataAddress -DataItem $sha256Name
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2, 0x45, 0x33, 0xC0, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31E8) -StackArguments @()
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $hashFail

    # BCryptHash(algorithm, NULL, 0, input, inputSize, digest, 32).
    Emit-LoadRcxFrame -SlotPosition $algorithmSlot
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xD2, 0x45, 0x33, 0xC0))
    Emit-LoadRaxFrame -SlotPosition $bufferSlot
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31F0) -StackArguments @(
        @{ Kind = 'FrameDword'; SlotPosition = $sizeSlot },
        @{ Kind = 'FrameAddress'; SlotPosition = $digestSlot },
        @{ Kind = 'Immediate'; Value = 32 }
    )
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $hashFail

    Emit-LoadRcxFrame -SlotPosition $algorithmSlot
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xD2))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31F8) -StackArguments @()
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $hashFail
    Emit-StoreZero64Frame -SlotPosition $algorithmSlot

    Emit-LoadRcxFrame -SlotPosition $bufferSlot
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xD2, 0x41, 0xB8, 0x00, 0x80, 0x00, 0x00))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31D8) -StackArguments @()
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $hashFail
    Emit-StoreZero64Frame -SlotPosition $bufferSlot

    $hashBytes = [byte[]]::new(32)
    for ($i = 0; $i -lt 32; $i++) { $hashBytes[$i] = [Convert]::ToByte($ExpectedSha256.Substring($i * 2, 2), 16) }
    $expectedDigest = Register-ByteDataConstant -Key ('SHA256:' + $ExpectedSha256) -Bytes $hashBytes
    Emit-LeaRaxFrame -SlotPosition $digestSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC6))
    Emit-DataAddress -DataItem $expectedDigest
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC7, 0xB9, 0x20, 0x00, 0x00, 0x00, 0xFC, 0xF3, 0xA6))
    Emit-JumpConditional -ConditionCode 0x85 -Label $hashFail
    Emit-Jump -Label $done

    Mark-CodeLabel -Label $hashFail
    Emit-LoadRcxFrame -SlotPosition $algorithmSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
    Emit-JumpConditional -ConditionCode 0x84 -Label $skipAlgorithmCleanup
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xD2))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31F8) -StackArguments @()
    Mark-CodeLabel -Label $skipAlgorithmCleanup

    Emit-LoadRcxFrame -SlotPosition $bufferSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
    Emit-JumpConditional -ConditionCode 0x84 -Label $skipBufferCleanup
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xD2, 0x41, 0xB8, 0x00, 0x80, 0x00, 0x00))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31D8) -StackArguments @()
    Mark-CodeLabel -Label $skipBufferCleanup

    Emit-LoadRcxFrame -SlotPosition $PersistentFileHandleSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
    Emit-JumpConditional -ConditionCode 0x84 -Label $skipFileCleanup
    Emit-Win64CallIat -TargetRva ([UInt32]0x30B8) -StackArguments @()
    Emit-StoreZero64Frame -SlotPosition $PersistentFileHandleSlot
    Mark-CodeLabel -Label $skipFileCleanup
    Emit-Jump -Label $FailureLabel
    Mark-CodeLabel -Label $done
}

function Emit-DevBrokerRevokeLegacyAppContainerSid {
    param([int] $SidSlot, [string] $FailureLabel)
    $nameItem = Register-WideDataConstant -Value 'Sharnou.DevAgent.ProcessBroker.v1'
    $displayItem = Register-WideDataConstant -Value 'Sharnou Legacy Broker Profile (ACL Migration)'
    $descriptionItem = Register-WideDataConstant -Value 'Legacy zero-capability profile retained only for one-time workspace ACL revocation.'
    $alreadyExists = New-UniqueLabel -Prefix 'dev_legacy_appcontainer_exists'
    $done = New-UniqueLabel -Prefix 'dev_legacy_appcontainer_ready'
    Emit-StoreZero64Frame -SlotPosition $SidSlot
    Emit-DataAddress -DataItem $nameItem
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-DataAddress -DataItem $displayItem
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-DataAddress -DataItem $descriptionItem
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3278) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 0 },
        @{ Kind = 'FrameAddress'; SlotPosition = $SidSlot }
    ) # Create legacy profile only to derive its existing package SID
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $done
    Emit-Bytes -Bytes ([byte[]]@(0x3D))
    Emit-I32 -Value -2147024713 # HRESULT_FROM_WIN32(ERROR_ALREADY_EXISTS)
    Emit-JumpConditional -ConditionCode 0x84 -Label $alreadyExists
    Emit-Jump -Label $FailureLabel

    Mark-CodeLabel -Label $alreadyExists
    Emit-DataAddress -DataItem $nameItem
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-LeaRaxFrame -SlotPosition $SidSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3280) -StackArguments @() # DeriveAppContainerSidFromAppContainerName
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $FailureLabel

    Mark-CodeLabel -Label $done
    Emit-LoadRaxFrame -SlotPosition $SidSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $FailureLabel
}

function Emit-DevBrokerEnsureAppContainerSid {
    param(
        [int] $SidSlot,
        [int] $ProfileNameSlot,
        [int] $RandomSlot,
        [int] $DerivedSidSlot,
        [int] $ProfileCreatedSlot,
        [string] $FailureLabel
    )
    $prefixItem = Register-WideDataConstant -Value 'Sharnou.DevAgent.'
    $hexItem = Register-WideDataConstant -Value '0123456789abcdef'
    $displayItem = Register-WideDataConstant -Value 'Sharnou DevAgent execution'
    $descriptionItem = Register-WideDataConstant -Value 'Ephemeral zero-capability per-execution identity.'
    $hexLoop = New-UniqueLabel -Prefix 'dev_appcontainer_hex_loop'
    $randomCheckLoop = New-UniqueLabel -Prefix 'dev_appcontainer_random_check'
    $randomNonzero = New-UniqueLabel -Prefix 'dev_appcontainer_random_nonzero'
    $derivedSidFailure = New-UniqueLabel -Prefix 'dev_appcontainer_derived_sid_failure'
    $sidReady = New-UniqueLabel -Prefix 'dev_appcontainer_sid_ready'
    $helperFailure = New-UniqueLabel -Prefix 'dev_appcontainer_helper_failure'
    $helperDone = New-UniqueLabel -Prefix 'dev_appcontainer_helper_done'
    $savedRdiSlot = $RandomSlot + 0x20
    $savedRsiSlot = $RandomSlot + 0x28

    # This helper uses RSI/RDI for string construction; preserve the caller's
    # nonvolatile registers before any generated code or nested Win32 calls.
    Emit-StoreRdiFrame -SlotPosition $savedRdiSlot
    Emit-StoreRsiFrame -SlotPosition $savedRsiSlot
    Emit-StoreZero64Frame -SlotPosition $SidSlot
    Emit-StoreZero64Frame -SlotPosition $DerivedSidSlot
    Emit-StoreBits32Frame -SlotPosition $ProfileCreatedSlot -Value 0

    # A fresh 128-bit execution identifier comes from the system-preferred CNG RNG.
    # It is never derived from a process ID, timestamp, workspace path or user input.
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xC9)) # hAlgorithm = NULL
    Emit-LeaRaxFrame -SlotPosition $RandomSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2, 0x41, 0xB8, 0x10, 0x00, 0x00, 0x00, 0x41, 0xB9, 0x02, 0x00, 0x00, 0x00))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3330) -StackArguments @() # BCryptGenRandom(BCRYPT_USE_SYSTEM_PREFERRED_RNG)
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $FailureLabel

    # Reject the all-zero output even though it is cryptographically negligible.
    Emit-LeaRaxFrame -SlotPosition $RandomSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC6, 0x33, 0xC0, 0xB9))
    Emit-I32 -Value 16
    Mark-CodeLabel -Label $randomCheckLoop
    Emit-Bytes -Bytes ([byte[]]@(0x0A, 0x06, 0x48, 0xFF, 0xC6, 0xFF, 0xC9))
    Emit-JumpConditional -ConditionCode 0x85 -Label $randomCheckLoop
    Emit-Bytes -Bytes ([byte[]]@(0x84, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $randomNonzero
    Emit-Jump -Label $helperFailure
    Mark-CodeLabel -Label $randomNonzero

    # Build the bounded canonical profile name:
    # Sharnou.DevAgent.<32 lowercase hexadecimal characters>.
    Emit-DataAddress -DataItem $prefixItem
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC6)) # RSI = UTF-16 prefix
    Emit-LeaRaxFrame -SlotPosition $ProfileNameSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC7, 0xB9))
    Emit-I32 -Value 34 # 17 UTF-16 characters, excluding the terminator
    Emit-Bytes -Bytes ([byte[]]@(0xFC, 0xF3, 0xA4)) # CLD; REP MOVSB
    Emit-DataAddress -DataItem $hexItem
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC3)) # R11 = UTF-16 hexadecimal lookup table
    Emit-LeaRaxFrame -SlotPosition $RandomSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC6, 0x41, 0xBA, 0x10, 0x00, 0x00, 0x00)) # RSI=random, R10D=16
    Mark-CodeLabel -Label $hexLoop
    Emit-Bytes -Bytes ([byte[]]@(
        0x0F, 0xB6, 0x06,             # movzx eax, byte ptr [rsi]
        0x89, 0xC2,                   # mov edx,eax
        0xC1, 0xE8, 0x04,             # shr eax,4
        0x41, 0x0F, 0xB7, 0x04, 0x43, # movzx eax,word ptr [r11+rax*2]
        0x66, 0x89, 0x07,             # mov word ptr [rdi],ax
        0x48, 0x83, 0xC7, 0x02,       # add rdi,2
        0x83, 0xE2, 0x0F,             # and edx,0xf
        0x41, 0x0F, 0xB7, 0x04, 0x53, # movzx eax,word ptr [r11+rdx*2]
        0x66, 0x89, 0x07,             # mov word ptr [rdi],ax
        0x48, 0x83, 0xC7, 0x02,       # add rdi,2
        0x48, 0xFF, 0xC6,             # inc rsi
        0x41, 0xFF, 0xCA              # dec r10d
    ))
    Emit-JumpConditional -ConditionCode 0x85 -Label $hexLoop
    Emit-Bytes -Bytes ([byte[]]@(0x66, 0xC7, 0x07, 0x00, 0x00)) # UTF-16 NUL

    # CreateAppContainerProfile must create a new identity. There is deliberately
    # no ERROR_ALREADY_EXISTS adoption/derive fallback: collisions fail closed.
    Emit-LeaRaxFrame -SlotPosition $ProfileNameSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-DataAddress -DataItem $displayItem
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-DataAddress -DataItem $descriptionItem
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3278) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 0 },
        @{ Kind = 'FrameAddress'; SlotPosition = $SidSlot }
    ) # CreateAppContainerProfile, zero capabilities
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $FailureLabel
    Emit-StoreBits32Frame -SlotPosition $ProfileCreatedSlot -Value 1
    Emit-LoadRaxFrame -SlotPosition $SidSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $FailureLabel

    # Independently derive the SID from this exact name and require identical SID identity.
    Emit-LeaRaxFrame -SlotPosition $ProfileNameSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-LeaRaxFrame -SlotPosition $DerivedSidSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3280) -StackArguments @() # DeriveAppContainerSidFromAppContainerName
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $derivedSidFailure
    Emit-LoadRaxFrame -SlotPosition $DerivedSidSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $derivedSidFailure
    Emit-LoadRaxFrame -SlotPosition $SidSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-LoadRaxFrame -SlotPosition $DerivedSidSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3350) -StackArguments @() # EqualSid
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $derivedSidFailure
    Emit-Jump -Label $sidReady

    Mark-CodeLabel -Label $derivedSidFailure
    Emit-LoadRcxFrame -SlotPosition $DerivedSidSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
    $skipDerivedFree = New-UniqueLabel -Prefix 'dev_appcontainer_skip_derived_free'
    Emit-JumpConditional -ConditionCode 0x84 -Label $skipDerivedFree
    Emit-Win64CallIat -TargetRva ([UInt32]0x32A8) -StackArguments @() # FreeSid
    Emit-StoreZero64Frame -SlotPosition $DerivedSidSlot
    Mark-CodeLabel -Label $skipDerivedFree
    Emit-Jump -Label $helperFailure

    Mark-CodeLabel -Label $sidReady
    Emit-LoadRcxFrame -SlotPosition $DerivedSidSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x32A8) -StackArguments @() # FreeSid
    Emit-StoreZero64Frame -SlotPosition $DerivedSidSlot
    Emit-LoadRdiFrame -SlotPosition $savedRdiSlot
    Emit-LoadRsiFrame -SlotPosition $savedRsiSlot
    Emit-Jump -Label $helperDone

    Mark-CodeLabel -Label $helperFailure
    Emit-LoadRdiFrame -SlotPosition $savedRdiSlot
    Emit-LoadRsiFrame -SlotPosition $savedRsiSlot
    Emit-Jump -Label $FailureLabel
    Mark-CodeLabel -Label $helperDone
}
function Emit-DevBrokerDeleteOwnedAppContainerProfile {
    param(
        [int] $ProfileNameSlot,
        [int] $ProfileCreatedSlot,
        [int] $ChildActiveSlot,
        [int] $TransactionActiveSlot,
        [int] $ResultSlot
    )
    $skip = New-UniqueLabel -Prefix 'dev_appcontainer_delete_skip'
    $deleted = New-UniqueLabel -Prefix 'dev_appcontainer_delete_success'
    $failed = New-UniqueLabel -Prefix 'dev_appcontainer_delete_failed'
    Emit-LoadEaxFrame -SlotPosition $ChildActiveSlot
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $skip
    Emit-LoadEaxFrame -SlotPosition $TransactionActiveSlot
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $skip
    Emit-LoadEaxFrame -SlotPosition $ProfileCreatedSlot
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $skip

    # The child token, process, thread and Job Object handles have already been
    # closed. Retry the indeterminate-profile failure once, but never report success
    # when Windows could not confirm deletion.
    Emit-LeaRaxFrame -SlotPosition $ProfileNameSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3340) -StackArguments @() # DeleteAppContainerProfile
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $deleted
    Emit-LeaRaxFrame -SlotPosition $ProfileNameSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3340) -StackArguments @() # retry DeleteAppContainerProfile
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed
    Mark-CodeLabel -Label $deleted
    Emit-StoreBits32Frame -SlotPosition $ProfileCreatedSlot -Value 0
    Emit-Jump -Label $skip

    Mark-CodeLabel -Label $failed
    Emit-Bytes -Bytes ([byte[]]@(0xB8))
    Emit-I32 -Value -134 # profile cleanup failed; never treat the execution as successful
    Emit-StoreEaxFrame -SlotPosition $ResultSlot
    Mark-CodeLabel -Label $skip
}

function Emit-DevBrokerUpdateAcl {
    param(
        [int] $PathSlot,
        [int] $SidSlot,
        [UInt32] $AccessMask,
        [UInt32] $AccessMode,
        [bool] $SetLowIntegrityLabel = $false,
        [string] $FailureLabel
    )
    $scratch = [int]$script:ActiveContext.ScratchPosition
    $handleSlot = $scratch + 0xD10
    $fileInfoSlot = $scratch + 0xD18
    $oldAclSlot = $scratch + 0xD50
    $securityDescriptorSlot = $scratch + 0xD58
    $newAclSlot = $scratch + 0xD60
    $explicitSlot = $scratch + 0xD70
    $failedSlot = $scratch + 0xDA0
    $mandatoryLabelAclSlot = $scratch + 0xDA8
    $failed = New-UniqueLabel -Prefix 'dev_acl_handle_failed'
    $done = New-UniqueLabel -Prefix 'dev_acl_handle_done'
    Emit-StoreZero64Frame -SlotPosition $handleSlot
    Emit-StoreZero64Frame -SlotPosition $oldAclSlot
    Emit-StoreZero64Frame -SlotPosition $securityDescriptorSlot
    Emit-StoreZero64Frame -SlotPosition $newAclSlot
    Emit-StoreBits32Frame -SlotPosition $failedSlot -Value 0
    for ($i = 0; $i -lt 7; $i++) { Emit-StoreZero64Frame -SlotPosition ($fileInfoSlot + ($i * 8)) }

    # Open the directory itself with READ_CONTROL | WRITE_DAC | WRITE_OWNER and
    # OPEN_REPARSE_POINT. WRITE_OWNER is needed for LABEL_SECURITY_INFORMATION.
    Emit-LeaRaxFrame -SlotPosition $PathSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1, 0xBA, 0x00, 0x00, 0x0E, 0x00, 0x41, 0xB8, 0x07, 0x00, 0x00, 0x00, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x30A0) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 3 },          # OPEN_EXISTING
        @{ Kind = 'Immediate'; Value = 0x02200080 }, # BACKUP_SEMANTICS | OPEN_REPARSE_POINT | NORMAL
        @{ Kind = 'Immediate'; Value = 0 }
    ) # CreateFileA(directory)
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xF8, 0xFF))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-StoreRaxFrame -SlotPosition $handleSlot

    # Validate the exact opened directory object; path-string checks are not enough.
    Emit-LoadRcxFrame -SlotPosition $handleSlot
    Emit-LeaRaxFrame -SlotPosition $fileInfoSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3208) -StackArguments @() # GetFileInformationByHandle
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-LoadEaxFrame -SlotPosition $fileInfoSlot
    Emit-Bytes -Bytes ([byte[]]@(0xA9, 0x10, 0x00, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed # FILE_ATTRIBUTE_DIRECTORY required
    Emit-Bytes -Bytes ([byte[]]@(0xA9, 0x00, 0x04, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed # FILE_ATTRIBUTE_REPARSE_POINT forbidden

    # GetSecurityInfo(handle, SE_FILE_OBJECT, DACL_SECURITY_INFORMATION, NULL, NULL, &oldDacl, NULL, &sd).
    Emit-LoadRcxFrame -SlotPosition $handleSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x01, 0x00, 0x00, 0x00, 0x41, 0xB8, 0x04, 0x00, 0x00, 0x00, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x32C8) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 0 }, # ppsidGroup
        @{ Kind = 'FrameAddress'; SlotPosition = $oldAclSlot },
        @{ Kind = 'Immediate'; Value = 0 }, # ppSacl
        @{ Kind = 'FrameAddress'; SlotPosition = $securityDescriptorSlot }
    ) # GetSecurityInfo
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed
    Emit-LoadRaxFrame -SlotPosition $oldAclSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed # a NULL DACL is never accepted

    # EXPLICIT_ACCESS_A (48 bytes), package SID trustee. SET_ACCESS is idempotent.
    Emit-StoreBits32Frame -SlotPosition $explicitSlot -Value $AccessMask
    Emit-StoreBits32Frame -SlotPosition ($explicitSlot + 4) -Value $AccessMode
    Emit-StoreBits32Frame -SlotPosition ($explicitSlot + 8) -Value 3 # OBJECT_INHERIT_ACE | CONTAINER_INHERIT_ACE
    Emit-StoreZero64Frame -SlotPosition ($explicitSlot + 16) # pMultipleTrustee
    Emit-StoreBits32Frame -SlotPosition ($explicitSlot + 24) -Value 0 # NO_MULTIPLE_TRUSTEE
    Emit-StoreBits32Frame -SlotPosition ($explicitSlot + 28) -Value 0 # TRUSTEE_IS_SID
    Emit-StoreBits32Frame -SlotPosition ($explicitSlot + 32) -Value 1 # TRUSTEE_IS_USER
    Emit-LoadRaxFrame -SlotPosition $SidSlot
    Emit-StoreRaxFrame -SlotPosition ($explicitSlot + 40)

    Emit-Bytes -Bytes ([byte[]]@(0xB9, 0x01, 0x00, 0x00, 0x00)) # count = 1
    Emit-LeaRaxFrame -SlotPosition $explicitSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2)) # RDX = EXPLICIT_ACCESS
    Emit-LoadRaxFrame -SlotPosition $oldAclSlot
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0)) # R8 = old DACL
    Emit-LeaR9Frame -SlotPosition $newAclSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x3298) -StackArguments @() # SetEntriesInAclA
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed

    # A low-integrity AppContainer is subject to MIC before DACL evaluation.
    # SetSecurityInfo(LABEL_SECURITY_INFORMATION) installs an inheritable Low IL
    # SYSTEM_MANDATORY_LABEL_ACE on Build staging only; workspace source remains
    # at its existing integrity level and is read-only in the package DACL.
    if ($SetLowIntegrityLabel) {
        # ACL header: revision 2, size 28, one ACE. ACE: SYSTEM_MANDATORY_LABEL,
        # OI|CI, size 20, NO_WRITE_UP, SID S-1-16-4096 (Low Mandatory Level).
        Emit-StoreImm64Frame -SlotPosition $mandatoryLabelAclSlot -Value ([UInt64]0x00000001001C0002)
        Emit-StoreBits32Frame -SlotPosition ($mandatoryLabelAclSlot + 8) -Value 0x00140311
        Emit-StoreBits32Frame -SlotPosition ($mandatoryLabelAclSlot + 12) -Value 1
        Emit-StoreImm64Frame -SlotPosition ($mandatoryLabelAclSlot + 16) -Value ([UInt64]0x1000000000000101)
        Emit-StoreBits32Frame -SlotPosition ($mandatoryLabelAclSlot + 24) -Value 0x00001000
        $securityInformation = 0x14 # DACL_SECURITY_INFORMATION | LABEL_SECURITY_INFORMATION
        $saclArgument = @{ Kind = 'FrameAddress'; SlotPosition = $mandatoryLabelAclSlot }
    }
    else {
        $securityInformation = 0x04 # DACL_SECURITY_INFORMATION only
        $saclArgument = @{ Kind = 'Immediate'; Value = 0 }
    }

    Emit-LoadRcxFrame -SlotPosition $handleSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x01, 0x00, 0x00, 0x00, 0x41, 0xB8))
    Emit-I32 -Value $securityInformation
    Emit-Bytes -Bytes ([byte[]]@(0x45, 0x33, 0xC9)) # pOwner = NULL
    Emit-Win64CallIat -TargetRva ([UInt32]0x32D0) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 0 }, # pSidGroup
        @{ Kind = 'FrameQword'; SlotPosition = $newAclSlot },
        $saclArgument
    ) # SetSecurityInfo
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed
    Emit-Jump -Label $done

    Mark-CodeLabel -Label $failed
    Emit-StoreBits32Frame -SlotPosition $failedSlot -Value 1
    Mark-CodeLabel -Label $done

    # LocalFree both allocations returned by the security APIs; close the directory handle.
    foreach ($slot in @($newAclSlot, $securityDescriptorSlot)) {
        $skipFree = New-UniqueLabel -Prefix 'dev_acl_handle_skip_free'
        Emit-LoadRcxFrame -SlotPosition $slot
        Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
        Emit-JumpConditional -ConditionCode 0x84 -Label $skipFree
        Emit-Win64CallIat -TargetRva ([UInt32]0x3260) -StackArguments @() # LocalFree
        Mark-CodeLabel -Label $skipFree
    }
    $skipClose = New-UniqueLabel -Prefix 'dev_acl_handle_skip_close'
    Emit-LoadRcxFrame -SlotPosition $handleSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
    Emit-JumpConditional -ConditionCode 0x84 -Label $skipClose
    Emit-Win64CallIat -TargetRva ([UInt32]0x30B8) -StackArguments @() # CloseHandle
    Mark-CodeLabel -Label $skipClose

    Emit-LoadEaxFrame -SlotPosition $failedSlot
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $FailureLabel
}

function Emit-DevBrokerCaptureSecurityDescriptor {
    param(
        [int] $PathSlot,
        [int] $DescriptorSlot,
        [int] $LengthSlot,
        [string] $FailureLabel
    )
    $scratch = [int]$script:ActiveContext.ScratchPosition
    $handleSlot = $scratch + 0xD10
    $fileInfoSlot = $scratch + 0xD18
    $daclSlot = $scratch + 0xD50
    $saclSlot = $scratch + 0xD58
    $failed = New-UniqueLabel -Prefix 'dev_acl_snapshot_failed'
    $done = New-UniqueLabel -Prefix 'dev_acl_snapshot_done'
    Emit-StoreZero64Frame -SlotPosition $handleSlot
    Emit-StoreZero64Frame -SlotPosition $DescriptorSlot
    Emit-StoreZero64Frame -SlotPosition $daclSlot
    Emit-StoreZero64Frame -SlotPosition $saclSlot
    Emit-StoreBits32Frame -SlotPosition $LengthSlot -Value 0
    for ($i = 0; $i -lt 7; $i++) { Emit-StoreZero64Frame -SlotPosition ($fileInfoSlot + ($i * 8)) }

    Emit-LeaRaxFrame -SlotPosition $PathSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1, 0xBA, 0x00, 0x00, 0x02, 0x00, 0x45, 0x33, 0xC0, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x30A0) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 3 },
        @{ Kind = 'Immediate'; Value = 0x02200080 },
        @{ Kind = 'Immediate'; Value = 0 }
    )
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xF8, 0xFF))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-StoreRaxFrame -SlotPosition $handleSlot

    Emit-LoadRcxFrame -SlotPosition $handleSlot
    Emit-LeaRaxFrame -SlotPosition $fileInfoSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3208) -StackArguments @()
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-LoadEaxFrame -SlotPosition $fileInfoSlot
    Emit-Bytes -Bytes ([byte[]]@(0xA9, 0x10, 0x00, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-Bytes -Bytes ([byte[]]@(0xA9, 0x00, 0x04, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed

    # Capture DACL plus the mandatory integrity label. LABEL_SECURITY_INFORMATION
    # is queried with READ_CONTROL; no general SACL privilege is requested.
    Emit-LoadRcxFrame -SlotPosition $handleSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x01, 0x00, 0x00, 0x00, 0x41, 0xB8, 0x14, 0x00, 0x00, 0x00, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x32C8) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 0 },
        @{ Kind = 'FrameAddress'; SlotPosition = $daclSlot },
        @{ Kind = 'FrameAddress'; SlotPosition = $saclSlot },
        @{ Kind = 'FrameAddress'; SlotPosition = $DescriptorSlot }
    )
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed
    Emit-LoadRaxFrame -SlotPosition $daclSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-LoadRcxFrame -SlotPosition $DescriptorSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x32F8) -StackArguments @()
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-LoadRcxFrame -SlotPosition $DescriptorSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x32F0) -StackArguments @()
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x14, 0x00, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x82 -Label $failed
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x00, 0x40, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x87 -Label $failed
    Emit-StoreEaxFrame -SlotPosition $LengthSlot
    Emit-Jump -Label $done

    Mark-CodeLabel -Label $failed
    Mark-CodeLabel -Label $done
    Emit-LoadRcxFrame -SlotPosition $handleSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
    $skipClose = New-UniqueLabel -Prefix 'dev_acl_snapshot_skip_close'
    Emit-JumpConditional -ConditionCode 0x84 -Label $skipClose
    Emit-Win64CallIat -TargetRva ([UInt32]0x30B8) -StackArguments @()
    Mark-CodeLabel -Label $skipClose
    # The caller owns any returned security descriptor and frees it in common cleanup.
    Emit-LoadRcxFrame -SlotPosition $DescriptorSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
    Emit-JumpConditional -ConditionCode 0x84 -Label $FailureLabel
    Emit-LoadEaxFrame -SlotPosition $LengthSlot
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $FailureLabel
}

function Emit-DevBrokerRestoreSecurityDescriptor {
    param(
        [int] $PathSlot,
        [int] $DescriptorSlot,
        [bool] $RestoreLabel = $false,
        [string] $FailureLabel
    )
    $scratch = [int]$script:ActiveContext.ScratchPosition
    $handleSlot = $scratch + 0xD10
    $fileInfoSlot = $scratch + 0xD18
    $daclPresentSlot = $scratch + 0xD50
    $daclSlot = $scratch + 0xD58
    $daclDefaultedSlot = $scratch + 0xD60
    $saclPresentSlot = $scratch + 0xD68
    $saclSlot = $scratch + 0xD70
    $saclDefaultedSlot = $scratch + 0xD78
    $restoreStageSlot = $scratch + 0xE80
    $restoreErrorSlot = $scratch + 0xE84
    $actualDaclSlot = $scratch + 0xE88
    $actualSaclSlot = $scratch + 0xE90
    $actualDescriptorSlot = $scratch + 0xE98
    $failed = New-UniqueLabel -Prefix 'dev_acl_restore_failed'
    $done = New-UniqueLabel -Prefix 'dev_acl_restore_done'
    Emit-StoreZero64Frame -SlotPosition $handleSlot
    foreach ($slot in @($daclPresentSlot, $daclSlot, $daclDefaultedSlot, $saclPresentSlot, $saclSlot, $saclDefaultedSlot,
        $actualDaclSlot, $actualSaclSlot, $actualDescriptorSlot)) {
        Emit-StoreZero64Frame -SlotPosition $slot
    }
    for ($i = 0; $i -lt 7; $i++) { Emit-StoreZero64Frame -SlotPosition ($fileInfoSlot + ($i * 8)) }

    Emit-StoreBits32Frame -SlotPosition $restoreStageSlot -Value 1 # CreateFileA
    Emit-LeaRaxFrame -SlotPosition $PathSlot
    # Match the normal ACL-update handle: READ_CONTROL | WRITE_DAC | WRITE_OWNER,
    # with full share access so Windows can propagate restored inheritable ACEs.
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1, 0xBA, 0x00, 0x00, 0x0E, 0x00, 0x41, 0xB8, 0x07, 0x00, 0x00, 0x00, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x30A0) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 3 },
        @{ Kind = 'Immediate'; Value = 0x02200080 },
        @{ Kind = 'Immediate'; Value = 0 }
    )
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xF8, 0xFF))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-StoreRaxFrame -SlotPosition $handleSlot

    Emit-StoreBits32Frame -SlotPosition $restoreStageSlot -Value 2 # GetFileInformationByHandle + directory/reparse validation
    Emit-LoadRcxFrame -SlotPosition $handleSlot
    Emit-LeaRaxFrame -SlotPosition $fileInfoSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3208) -StackArguments @()
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-LoadEaxFrame -SlotPosition $fileInfoSlot
    Emit-Bytes -Bytes ([byte[]]@(0xA9, 0x10, 0x00, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-Bytes -Bytes ([byte[]]@(0xA9, 0x00, 0x04, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed

    Emit-StoreBits32Frame -SlotPosition $restoreStageSlot -Value 3 # IsValidSecurityDescriptor
    Emit-LoadRcxFrame -SlotPosition $DescriptorSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x32F8) -StackArguments @()
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed

    Emit-StoreBits32Frame -SlotPosition $restoreStageSlot -Value 4 # GetSecurityDescriptorDacl
    Emit-LoadRcxFrame -SlotPosition $DescriptorSlot
    Emit-LeaRaxFrame -SlotPosition $daclPresentSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-LeaRaxFrame -SlotPosition $daclSlot
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0))
    Emit-LeaRaxFrame -SlotPosition $daclDefaultedSlot
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x32E0) -StackArguments @()
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-LoadEaxFrame -SlotPosition $daclPresentSlot
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-LoadRaxFrame -SlotPosition $daclSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed

    if ($RestoreLabel) {
        Emit-StoreBits32Frame -SlotPosition $restoreStageSlot -Value 5 # GetSecurityDescriptorSacl
        Emit-LoadRcxFrame -SlotPosition $DescriptorSlot
        Emit-LeaRaxFrame -SlotPosition $saclPresentSlot
        Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
        Emit-LeaRaxFrame -SlotPosition $saclSlot
        Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0))
        Emit-LeaRaxFrame -SlotPosition $saclDefaultedSlot
        Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC1))
        Emit-Win64CallIat -TargetRva ([UInt32]0x32E8) -StackArguments @()
        Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
        Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    }

    Emit-StoreBits32Frame -SlotPosition $restoreStageSlot -Value 6 # SetSecurityInfo
    Emit-LoadRcxFrame -SlotPosition $handleSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x01, 0x00, 0x00, 0x00, 0x41, 0xB8))
    if ($RestoreLabel) {
        Emit-I32 -Value 0x14 # DACL_SECURITY_INFORMATION | LABEL_SECURITY_INFORMATION
        $restoreSaclArgument = @{ Kind = 'FrameQword'; SlotPosition = $saclSlot }
    }
    else {
        Emit-I32 -Value 0x04 # DACL_SECURITY_INFORMATION only; root label is never changed
        $restoreSaclArgument = @{ Kind = 'Immediate'; Value = 0 }
    }
    Emit-Bytes -Bytes ([byte[]]@(0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x32D0) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 0 },
        @{ Kind = 'FrameQword'; SlotPosition = $daclSlot },
        $restoreSaclArgument
    )
    Emit-StoreEaxFrame -SlotPosition $restoreErrorSlot # SetSecurityInfo returns a Win32 error code directly
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed

    # Read the descriptor back from the same opened object. Compare the complete
    # DACL byte sequence, and the SACL/mandatory-label bytes for Build directories,
    # before declaring restoration complete.
    Emit-StoreBits32Frame -SlotPosition $restoreStageSlot -Value 70 # GetSecurityInfo readback
    Emit-LoadRcxFrame -SlotPosition $handleSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x01, 0x00, 0x00, 0x00, 0x41, 0xB8, 0x14, 0x00, 0x00, 0x00, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x32C8) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 0 },
        @{ Kind = 'FrameAddress'; SlotPosition = $actualDaclSlot },
        @{ Kind = 'FrameAddress'; SlotPosition = $actualSaclSlot },
        @{ Kind = 'FrameAddress'; SlotPosition = $actualDescriptorSlot }
    ) # GetSecurityInfo(DACL + LABEL)
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed
    Emit-StoreBits32Frame -SlotPosition $restoreStageSlot -Value 71 # readback API succeeded

    # DACL must be byte-for-byte identical, including ACE order and flags.
    Emit-StoreBits32Frame -SlotPosition $restoreStageSlot -Value 72 # validate DACL pointers
    Emit-LoadRaxFrame -SlotPosition $daclSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC6, 0x48, 0x85, 0xF6))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-LoadRaxFrame -SlotPosition $actualDaclSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC7, 0x48, 0x85, 0xFF))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-StoreBits32Frame -SlotPosition $restoreStageSlot -Value 73 # validate DACL length
    Emit-Bytes -Bytes ([byte[]]@(0x0F, 0xB7, 0x46, 0x02, 0x0F, 0xB7, 0x57, 0x02, 0x39, 0xD0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed
    Emit-StoreBits32Frame -SlotPosition $restoreStageSlot -Value 74 # compare DACL bytes
    Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC1, 0xFC, 0xF3, 0xA6)) # CLD; REPE CMPSB
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed

    if ($RestoreLabel) {
        # NULL SACL is a legitimate original state. Treat NULL/NULL as an exact
        # match; reject only a presence mismatch or different SACL bytes.
        $compareSacl = New-UniqueLabel -Prefix 'dev_acl_restore_compare_sacl'
        $skipSaclCompare = New-UniqueLabel -Prefix 'dev_acl_restore_skip_sacl_compare'
        Emit-StoreBits32Frame -SlotPosition $restoreStageSlot -Value 75 # inspect expected SACL presence
        Emit-LoadRaxFrame -SlotPosition $saclSlot
        Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
        Emit-JumpConditional -ConditionCode 0x84 -Label $skipSaclCompare # expected NULL

        # Expected SACL is present: actual readback must also be present.
        Emit-StoreBits32Frame -SlotPosition $restoreStageSlot -Value 76 # actual SACL must be present
        Emit-LoadRaxFrame -SlotPosition $actualSaclSlot
        Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
        Emit-JumpConditional -ConditionCode 0x85 -Label $compareSacl
        Emit-Jump -Label $failed

        Mark-CodeLabel -Label $skipSaclCompare
        # Expected NULL: actual must also be NULL.
        Emit-StoreBits32Frame -SlotPosition $restoreStageSlot -Value 77 # actual SACL must also be NULL
        Emit-LoadRaxFrame -SlotPosition $actualSaclSlot
        Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
        Emit-JumpConditional -ConditionCode 0x85 -Label $failed
        $saclPresenceMatched = New-UniqueLabel -Prefix 'dev_acl_restore_sacl_presence_matched'
        Emit-Jump -Label $saclPresenceMatched

        Mark-CodeLabel -Label $compareSacl
        # Both SACLs are present: exact size and byte comparison is required.
        Emit-StoreBits32Frame -SlotPosition $restoreStageSlot -Value 78 # validate SACL lengths
        Emit-LoadRaxFrame -SlotPosition $saclSlot
        Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC6))
        Emit-LoadRaxFrame -SlotPosition $actualSaclSlot
        Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC7, 0x0F, 0xB7, 0x46, 0x02, 0x0F, 0xB7, 0x57, 0x02, 0x39, 0xD0))
        Emit-JumpConditional -ConditionCode 0x85 -Label $failed
        Emit-StoreBits32Frame -SlotPosition $restoreStageSlot -Value 79 # compare SACL bytes
        Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC1, 0xFC, 0xF3, 0xA6)) # CLD; REPE CMPSB
        Emit-JumpConditional -ConditionCode 0x85 -Label $failed
        Mark-CodeLabel -Label $saclPresenceMatched
    }

    Emit-StoreBits32Frame -SlotPosition $daclPresentSlot -Value 1
    Emit-StoreBits32Frame -SlotPosition $restoreStageSlot -Value 0
    Emit-Jump -Label $done

    Mark-CodeLabel -Label $failed
    Emit-StoreBits32Frame -SlotPosition $daclPresentSlot -Value 0
    Mark-CodeLabel -Label $done
    Emit-LoadRcxFrame -SlotPosition $actualDescriptorSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
    $skipFreeReadback = New-UniqueLabel -Prefix 'dev_acl_restore_skip_free_readback'
    Emit-JumpConditional -ConditionCode 0x84 -Label $skipFreeReadback
    Emit-Win64CallIat -TargetRva ([UInt32]0x3260) -StackArguments @() # LocalFree readback descriptor
    Emit-StoreZero64Frame -SlotPosition $actualDescriptorSlot
    Mark-CodeLabel -Label $skipFreeReadback
    Emit-LoadRcxFrame -SlotPosition $handleSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
    $skipClose = New-UniqueLabel -Prefix 'dev_acl_restore_skip_close'
    Emit-JumpConditional -ConditionCode 0x84 -Label $skipClose
    Emit-Win64CallIat -TargetRva ([UInt32]0x30B8) -StackArguments @()
    Mark-CodeLabel -Label $skipClose
    Emit-LoadEaxFrame -SlotPosition $daclPresentSlot
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $FailureLabel
}

function Emit-DevBrokerWriteAclJournal {
    param(
        [int] $JournalPathSlot,
        [int] $TempPathSlot,
        [int] $WorkspaceRootSlot,
        [int] $BuildPathSlot,
        [int] $BrokerDirectorySlot,
        [int] $JournalHandleSlot,
        [int] $JournalWrittenSlot,
        [int] $HeaderSlot,
        [int] $RootDescriptorSlot,
        [int] $BuildDescriptorSlot,
        [int] $BrokerDescriptorSlot,
        [int] $RootLengthSlot,
        [int] $BuildLengthSlot,
        [int] $BrokerLengthSlot,
        [int] $TransactionActiveSlot,
        [string] $FailureLabel
    )
    $scratch = [int]$script:ActiveContext.ScratchPosition
    $failed = New-UniqueLabel -Prefix 'dev_acl_journal_write_failed'
    $done = New-UniqueLabel -Prefix 'dev_acl_journal_write_done'
    Emit-DevBrokerCaptureSecurityDescriptor -PathSlot $WorkspaceRootSlot -DescriptorSlot $RootDescriptorSlot -LengthSlot $RootLengthSlot -FailureLabel $FailureLabel
    Emit-DevBrokerCaptureSecurityDescriptor -PathSlot $BuildPathSlot -DescriptorSlot $BuildDescriptorSlot -LengthSlot $BuildLengthSlot -FailureLabel $FailureLabel
    Emit-DevBrokerCaptureSecurityDescriptor -PathSlot $BrokerDirectorySlot -DescriptorSlot $BrokerDescriptorSlot -LengthSlot $BrokerLengthSlot -FailureLabel $FailureLabel

    # Fixed, versioned header followed by three bounded self-relative descriptors.
    Emit-StoreBits32Frame -SlotPosition $HeaderSlot -Value 0x52414853
    Emit-StoreBits32Frame -SlotPosition ($HeaderSlot + 4) -Value 0x314C4341
    Emit-StoreBits32Frame -SlotPosition ($HeaderSlot + 8) -Value 1
    Emit-StoreBits32Frame -SlotPosition ($HeaderSlot + 12) -Value 0
    Emit-LoadEaxFrame -SlotPosition $RootLengthSlot
    Emit-StoreEaxFrame -SlotPosition ($HeaderSlot + 16)
    Emit-LoadEaxFrame -SlotPosition $BuildLengthSlot
    Emit-StoreEaxFrame -SlotPosition ($HeaderSlot + 20)
    Emit-LoadEaxFrame -SlotPosition $BrokerLengthSlot
    Emit-StoreEaxFrame -SlotPosition ($HeaderSlot + 24)
    Emit-StoreBits32Frame -SlotPosition ($HeaderSlot + 28) -Value 0

    # A stale .tmp file means a prior write never reached the atomic commit point.
    Emit-LeaRaxFrame -SlotPosition $TempPathSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3310) -StackArguments @() # DeleteFileA (ignore missing)
    Emit-LeaRaxFrame -SlotPosition $TempPathSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1, 0xBA, 0x00, 0x00, 0x00, 0x40, 0x45, 0x33, 0xC0, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x30A0) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 1 },
        @{ Kind = 'Immediate'; Value = 0x80200002 },
        @{ Kind = 'Immediate'; Value = 0 }
    ) # CREATE_NEW | HIDDEN | OPEN_REPARSE_POINT | WRITE_THROUGH
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xF8, 0xFF))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-StoreRaxFrame -SlotPosition $JournalHandleSlot

    # Header write.
    Emit-LoadRcxFrame -SlotPosition $JournalHandleSlot
    Emit-LeaRaxFrame -SlotPosition $HeaderSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2, 0x41, 0xB8, 0x20, 0x00, 0x00, 0x00))
    Emit-LeaRaxFrame -SlotPosition $JournalWrittenSlot
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3078) -StackArguments @(@{ Kind = 'Immediate'; Value = 0 })
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-LoadEaxFrame -SlotPosition $JournalWrittenSlot
    Emit-Bytes -Bytes ([byte[]]@(0x83, 0xF8, 0x20))
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed

    foreach ($record in @(
        @{ Descriptor = $RootDescriptorSlot; Length = $RootLengthSlot },
        @{ Descriptor = $BuildDescriptorSlot; Length = $BuildLengthSlot },
        @{ Descriptor = $BrokerDescriptorSlot; Length = $BrokerLengthSlot }
    )) {
        Emit-LoadRcxFrame -SlotPosition $JournalHandleSlot
        Emit-LoadRaxFrame -SlotPosition $record.Descriptor
        Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
        Emit-LoadEaxFrame -SlotPosition $record.Length
        Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC0))
        Emit-LeaRaxFrame -SlotPosition $JournalWrittenSlot
        Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC1))
        Emit-Win64CallIat -TargetRva ([UInt32]0x3078) -StackArguments @(@{ Kind = 'Immediate'; Value = 0 })
        Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
        Emit-JumpConditional -ConditionCode 0x84 -Label $failed
        Emit-LoadEaxFrame -SlotPosition $JournalWrittenSlot
        Emit-Bytes -Bytes ([byte[]]@(0x3B, 0x85))
        Emit-I32 -Value (Get-FrameDisp -SlotPosition $record.Length)
        Emit-JumpConditional -ConditionCode 0x85 -Label $failed
    }

    Emit-LoadRcxFrame -SlotPosition $JournalHandleSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x3320) -StackArguments @() # FlushFileBuffers
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-LoadRcxFrame -SlotPosition $JournalHandleSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x30B8) -StackArguments @() # CloseHandle
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-StoreZero64Frame -SlotPosition $JournalHandleSlot

    # Same-volume rename is the transaction commit point. ACL changes are forbidden before it.
    Emit-LeaRaxFrame -SlotPosition $TempPathSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-LeaRaxFrame -SlotPosition $JournalPathSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2, 0x41, 0xB8, 0x08, 0x00, 0x00, 0x00))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3318) -StackArguments @() # MoveFileExA(MOVEFILE_WRITE_THROUGH)
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-StoreBits32Frame -SlotPosition $TransactionActiveSlot -Value 1
    Emit-Jump -Label $done

    Mark-CodeLabel -Label $failed
    Emit-LoadRcxFrame -SlotPosition $JournalHandleSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
    $skipClose = New-UniqueLabel -Prefix 'dev_acl_journal_skip_close'
    Emit-JumpConditional -ConditionCode 0x84 -Label $skipClose
    Emit-Win64CallIat -TargetRva ([UInt32]0x30B8) -StackArguments @()
    Emit-StoreZero64Frame -SlotPosition $JournalHandleSlot
    Mark-CodeLabel -Label $skipClose
    Emit-LeaRaxFrame -SlotPosition $TempPathSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3310) -StackArguments @()
    Emit-Jump -Label $FailureLabel
    Mark-CodeLabel -Label $done
}

function Emit-DevBrokerWriteDiagnosticPath {
    param([int] $PathSlot, [int] $PathLengthSlot)
    $scratch = [int]$script:ActiveContext.ScratchPosition
    $stdoutHandleSlot = $scratch + 0xD60
    $bytesWrittenSlot = $scratch + 0xD68
    $prefixItem = Register-DataConstant -Value 'ACL_RECOVERY_NATIVE_PATH|'
    $newlineItem = Register-ByteDataConstant -Key 'ACL_RECOVERY_NATIVE_PATH_NEWLINE' -Bytes ([byte[]]@(13, 10))
    $skip = New-UniqueLabel -Prefix 'dev_acl_recovery_path_diagnostic_skip'

    Emit-Bytes -Bytes ([byte[]]@(0xB9, 0xF5, 0xFF, 0xFF, 0xFF)) # STD_OUTPUT_HANDLE
    Emit-Win64CallIat -TargetRva ([UInt32]0x3070) -StackArguments @() # GetStdHandle
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xF8, 0xFF))
    Emit-JumpConditional -ConditionCode 0x84 -Label $skip
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $skip
    Emit-StoreRaxFrame -SlotPosition $stdoutHandleSlot

    Emit-LoadRcxFrame -SlotPosition $stdoutHandleSlot
    Emit-DataAddress -DataItem $prefixItem
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2, 0x41, 0xB8))
    Emit-I32 -Value ([int]($prefixItem.Bytes.Length - 1))
    Emit-LeaR9Frame -SlotPosition $bytesWrittenSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x3078) -StackArguments @(@{ Kind = 'Immediate'; Value = 0 }) # WriteFile

    Emit-LoadRcxFrame -SlotPosition $stdoutHandleSlot
    Emit-LeaRaxFrame -SlotPosition $PathSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-LoadEaxFrame -SlotPosition $PathLengthSlot
    Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC0)) # R8D = path length
    Emit-LeaR9Frame -SlotPosition $bytesWrittenSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x3078) -StackArguments @(@{ Kind = 'Immediate'; Value = 0 }) # WriteFile

    Emit-LoadRcxFrame -SlotPosition $stdoutHandleSlot
    Emit-DataAddress -DataItem $newlineItem
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2, 0x41, 0xB8, 0x02, 0x00, 0x00, 0x00))
    Emit-LeaR9Frame -SlotPosition $bytesWrittenSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x3078) -StackArguments @(@{ Kind = 'Immediate'; Value = 0 }) # WriteFile
    Mark-CodeLabel -Label $skip
}

function Emit-DevBrokerWriteRecoveryTokenDiagnostic {
    $scratch = [int]$script:ActiveContext.ScratchPosition
    $tokenHandleSlot = $scratch + 0xE80
    $tokenInfoSlot = $scratch + 0xE88
    $tokenReturnLengthSlot = $scratch + 0xE8C
    $appContainerSlot = $scratch + 0xE90
    $restrictedSlot = $scratch + 0xE94
    $elevationSlot = $scratch + 0xE98
    $openErrorSlot = $scratch + 0xE9C
    $queryErrorSlot = $scratch + 0xEA0
    $integrityInfoSlot = $scratch + 0xEA8
    $integrityReturnLengthSlot = $scratch + 0xF28
    $integrityRidSlot = $scratch + 0xF2C
    $textBufferSlot = $scratch + 0xF40
    $textLengthSlot = $scratch + 0xFC0
    $stdoutHandleSlot = $scratch + 0xD60
    $bytesWrittenSlot = $scratch + 0xD68
    $openFailed = New-UniqueLabel -Prefix 'dev_acl_recovery_token_open_failed'
    $queryLoopDone = New-UniqueLabel -Prefix 'dev_acl_recovery_token_queries_done'
    $formatReady = New-UniqueLabel -Prefix 'dev_acl_recovery_token_format_ready'
    Emit-StoreZero64Frame -SlotPosition $tokenHandleSlot
    foreach ($slot in @($tokenInfoSlot, $tokenReturnLengthSlot, $queryErrorSlot, $integrityInfoSlot, $integrityReturnLengthSlot, $integrityRidSlot)) {
        Emit-StoreZero64Frame -SlotPosition $slot
    }
    foreach ($slot in @($appContainerSlot, $restrictedSlot, $elevationSlot, $openErrorSlot)) {
        Emit-StoreBits32Frame -SlotPosition $slot -Value 0
    }

    # Query the broker's own primary token, not the PowerShell test harness token.
    # GetCurrentProcess() is the documented pseudo-handle value (HANDLE)-1.
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0xC7, 0xC1, 0xFF, 0xFF, 0xFF, 0xFF, 0xBA, 0x08, 0x00, 0x00, 0x00))
    Emit-Bytes -Bytes ([byte[]]@(0x4C, 0x8D, 0x85))
    Emit-I32 -Value (Get-FrameDisp -SlotPosition $tokenHandleSlot)
    Emit-Win64CallIat -TargetRva ([UInt32]0x32B0) -StackArguments @() # OpenProcessToken(TOKEN_QUERY)
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $openFailed
    Emit-StoreBits32Frame -SlotPosition $openErrorSlot -Value 0

    foreach ($query in @(
        @{ Class = 29; ValueSlot = $appContainerSlot }, # TokenIsAppContainer
        @{ Class = 21; ValueSlot = $restrictedSlot },   # TokenHasRestrictions
        @{ Class = 20; ValueSlot = $elevationSlot }     # TokenElevation
    )) {
        $queryFailed = New-UniqueLabel -Prefix 'dev_acl_recovery_token_query_failed'
        $queryDone = New-UniqueLabel -Prefix 'dev_acl_recovery_token_query_done'
        Emit-StoreZero64Frame -SlotPosition $tokenInfoSlot
        Emit-StoreZero64Frame -SlotPosition $tokenReturnLengthSlot
        Emit-LoadRcxFrame -SlotPosition $tokenHandleSlot
        Emit-Bytes -Bytes ([byte[]]@(0xBA))
        Emit-I32 -Value ([int]$query.Class)
        Emit-Bytes -Bytes ([byte[]]@(0x4C, 0x8D, 0x85))
        Emit-I32 -Value (Get-FrameDisp -SlotPosition $tokenInfoSlot)
        Emit-Bytes -Bytes ([byte[]]@(0x41, 0xB9, 0x04, 0x00, 0x00, 0x00))
        Emit-Win64CallIat -TargetRva ([UInt32]0x32D8) -StackArguments @(
            @{ Kind = 'FrameAddress'; SlotPosition = $tokenReturnLengthSlot }
        ) # GetTokenInformation(DWORD)
        Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
        Emit-JumpConditional -ConditionCode 0x84 -Label $queryFailed
        Emit-LoadEaxFrame -SlotPosition $tokenInfoSlot
        Emit-StoreEaxFrame -SlotPosition ([int]$query.ValueSlot)
        Emit-Jump -Label $queryDone
        Mark-CodeLabel -Label $queryFailed
        Emit-Win64CallIat -TargetRva ([UInt32]0x3268) -StackArguments @() # GetLastError
        Emit-StoreEaxFrame -SlotPosition $queryErrorSlot
        Emit-StoreBits32Frame -SlotPosition ([int]$query.ValueSlot) -Value 0
        Mark-CodeLabel -Label $queryDone
    }

    # TokenIntegrityLevel returns TOKEN_MANDATORY_LABEL (SID_AND_ATTRIBUTES).
    # Extract the final SID sub-authority RID: 0x1000 low, 0x2000 medium,
    # 0x3000 high, 0x4000 system.
    $integrityFailed = New-UniqueLabel -Prefix 'dev_acl_recovery_token_integrity_failed'
    $integrityDone = New-UniqueLabel -Prefix 'dev_acl_recovery_token_integrity_done'
    Emit-StoreZero64Frame -SlotPosition $integrityInfoSlot
    Emit-StoreZero64Frame -SlotPosition $integrityReturnLengthSlot
    Emit-LoadRcxFrame -SlotPosition $tokenHandleSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x19, 0x00, 0x00, 0x00)) # TokenIntegrityLevel = 25
    Emit-Bytes -Bytes ([byte[]]@(0x4C, 0x8D, 0x85))
    Emit-I32 -Value (Get-FrameDisp -SlotPosition $integrityInfoSlot)
    Emit-Bytes -Bytes ([byte[]]@(0x41, 0xB9, 0x80, 0x00, 0x00, 0x00)) # 128-byte TOKEN_MANDATORY_LABEL plus SID buffer
    Emit-Win64CallIat -TargetRva ([UInt32]0x32D8) -StackArguments @(
        @{ Kind = 'FrameAddress'; SlotPosition = $integrityReturnLengthSlot }
    ) # GetTokenInformation
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $integrityFailed
    Emit-LoadRaxFrame -SlotPosition $integrityInfoSlot # RAX = SID pointer
    Emit-Bytes -Bytes ([byte[]]@(0x0F, 0xB6, 0x48, 0x01, 0x85, 0xC9)) # MOVZX ECX,[RAX+1]; TEST ECX,ECX
    Emit-JumpConditional -ConditionCode 0x84 -Label $integrityFailed
    Emit-Bytes -Bytes ([byte[]]@(0xFF, 0xC9, 0x48, 0x8D, 0x44, 0x88, 0x08, 0x8B, 0x00)) # RID at SID+8+(count-1)*4
    Emit-StoreEaxFrame -SlotPosition $integrityRidSlot
    Emit-Jump -Label $integrityDone
    Mark-CodeLabel -Label $integrityFailed
    Emit-Win64CallIat -TargetRva ([UInt32]0x3268) -StackArguments @() # GetLastError
    Emit-StoreEaxFrame -SlotPosition $queryErrorSlot
    Emit-StoreBits32Frame -SlotPosition $integrityRidSlot -Value 0
    Mark-CodeLabel -Label $integrityDone

    Emit-LoadRcxFrame -SlotPosition $tokenHandleSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x30B8) -StackArguments @() # CloseHandle
    Emit-Jump -Label $formatReady

    Mark-CodeLabel -Label $openFailed
    Emit-Win64CallIat -TargetRva ([UInt32]0x3268) -StackArguments @() # GetLastError
    Emit-StoreEaxFrame -SlotPosition $openErrorSlot
    Mark-CodeLabel -Label $formatReady

    $formatItem = Register-DataConstant -Value "ACL_RECOVERY_TOKEN|appcontainer=%u|restricted=%u|elevation=%u|integrityRid=%u|openError=%u|queryError=%u`r`n"
    Emit-LeaRaxFrame -SlotPosition $textBufferSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-DataAddress -DataItem $formatItem
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-LoadEaxFrame -SlotPosition $appContainerSlot
    Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC0))
    Emit-LoadEaxFrame -SlotPosition $restrictedSlot
    Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3090) -StackArguments @(
        @{ Kind = 'FrameDword'; SlotPosition = $elevationSlot },
        @{ Kind = 'FrameDword'; SlotPosition = $integrityRidSlot },
        @{ Kind = 'FrameDword'; SlotPosition = $openErrorSlot },
        @{ Kind = 'FrameDword'; SlotPosition = $queryErrorSlot }
    ) # wsprintfA
    Emit-StoreEaxFrame -SlotPosition $textLengthSlot

    Emit-Bytes -Bytes ([byte[]]@(0xB9, 0xF5, 0xFF, 0xFF, 0xFF)) # STD_OUTPUT_HANDLE
    Emit-Win64CallIat -TargetRva ([UInt32]0x3070) -StackArguments @() # GetStdHandle
    Emit-StoreRaxFrame -SlotPosition $stdoutHandleSlot
    Emit-LoadRcxFrame -SlotPosition $stdoutHandleSlot
    Emit-LeaRaxFrame -SlotPosition $textBufferSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-LoadEaxFrame -SlotPosition $textLengthSlot
    Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC0))
    Emit-LeaR9Frame -SlotPosition $bytesWrittenSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x3078) -StackArguments @(@{ Kind = 'Immediate'; Value = 0 }) # WriteFile
}

function Emit-DevBrokerWriteRecoveryAttributeDiagnostic {
    param([int] $JournalPathSlot)
    $scratch = [int]$script:ActiveContext.ScratchPosition
    $attributeSlot = $scratch + 0xD70
    $errorSlot = $scratch + 0xD74
    # Keep the formatted diagnostic buffer disjoint from the DWORD length slot
    # and from the live recovery-stage value at D90.
    # Use a dedicated 128-byte area at the top of the reserved frame scratch.
    $textBufferSlot = $scratch + 0xF00
    $textLengthSlot = $scratch + 0xF80
    $stdoutHandleSlot = $scratch + 0xD60
    $bytesWrittenSlot = $scratch + 0xD68
    $attributeFailed = New-UniqueLabel -Prefix 'dev_acl_recovery_getattr_failed'
    $formatted = New-UniqueLabel -Prefix 'dev_acl_recovery_getattr_formatted'
    $formatItem = Register-DataConstant -Value "ACL_RECOVERY_GETATTR|attrs=0x%08X|error=%u`r`n"

    # Emit a fixed marker first using the same GetStdHandle/WriteFile path
    # already proven by the native path diagnostic. This isolates formatting/API
    # diagnostics from whether this emitted helper is actually entered.
    $markerItem = Register-DataConstant -Value 'ACL_RECOVERY_GETATTR|begin'
    Emit-Bytes -Bytes ([byte[]]@(0xB9, 0xF5, 0xFF, 0xFF, 0xFF)) # STD_OUTPUT_HANDLE
    Emit-Win64CallIat -TargetRva ([UInt32]0x3070) -StackArguments @()
    Emit-StoreRaxFrame -SlotPosition $stdoutHandleSlot
    Emit-LoadRcxFrame -SlotPosition $stdoutHandleSlot
    Emit-DataAddress -DataItem $markerItem
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2, 0x41, 0xB8))
    Emit-I32 -Value ($markerItem.Bytes.Length - 1)
    Emit-LeaR9Frame -SlotPosition $bytesWrittenSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x3078) -StackArguments @(@{ Kind = 'Immediate'; Value = 0 }) # WriteFile

    # Read-only path/metadata probe. This does not alter ACLs or open the journal.
    Emit-LeaRaxFrame -SlotPosition $JournalPathSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31C8) -StackArguments @() # GetFileAttributesA
    Emit-StoreEaxFrame -SlotPosition $attributeSlot
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0xFF, 0xFF, 0xFF, 0xFF))
    Emit-JumpConditional -ConditionCode 0x84 -Label $attributeFailed
    Emit-StoreBits32Frame -SlotPosition $errorSlot -Value 0
    Emit-Jump -Label $formatted
    Mark-CodeLabel -Label $attributeFailed
    Emit-Win64CallIat -TargetRva ([UInt32]0x3268) -StackArguments @() # GetLastError
    Emit-StoreEaxFrame -SlotPosition $errorSlot
    Mark-CodeLabel -Label $formatted

    Emit-LeaRaxFrame -SlotPosition $textBufferSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-DataAddress -DataItem $formatItem
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-LoadEaxFrame -SlotPosition $attributeSlot
    Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC0)) # R8D = attributes
    Emit-LoadEaxFrame -SlotPosition $errorSlot
    Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC1)) # R9D = Win32 error
    Emit-Win64CallIat -TargetRva ([UInt32]0x3090) -StackArguments @() # wsprintfA
    Emit-StoreEaxFrame -SlotPosition $textLengthSlot

    Emit-Bytes -Bytes ([byte[]]@(0xB9, 0xF5, 0xFF, 0xFF, 0xFF)) # STD_OUTPUT_HANDLE
    Emit-Win64CallIat -TargetRva ([UInt32]0x3070) -StackArguments @() # GetStdHandle
    Emit-StoreRaxFrame -SlotPosition $stdoutHandleSlot
    Emit-LoadRcxFrame -SlotPosition $stdoutHandleSlot
    Emit-LeaRaxFrame -SlotPosition $textBufferSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-LoadEaxFrame -SlotPosition $textLengthSlot
    Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC0))
    Emit-LeaR9Frame -SlotPosition $bytesWrittenSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x3078) -StackArguments @(@{ Kind = 'Immediate'; Value = 0 }) # WriteFile
}

function Emit-DevBrokerRecoverAclJournal {
    param(
        [int] $JournalPathSlot,
        [int] $PathLengthSlot,
        [int] $TempPathSlot,
        [int] $WorkspaceRootSlot,
        [int] $BuildPathSlot,
        [int] $BrokerDirectorySlot,
        [int] $JournalHandleSlot,
        [int] $JournalReadCountSlot,
        [int] $HeaderSlot,
        [int] $JournalBufferSlot,
        [int] $RootLengthSlot,
        [int] $BuildLengthSlot,
        [int] $BrokerLengthSlot,
        [int] $RootDescriptorSlot,
        [int] $BuildDescriptorSlot,
        [int] $BrokerDescriptorSlot,
        [string] $FailureLabel
    )
    $scratch = [int]$script:ActiveContext.ScratchPosition
    $fileInfoSlot = $scratch + 0xD18
    $expectedSizeSlot = $scratch + 0xD50
    $recoveryStageSlot = $scratch + 0xD90
    $failed = New-UniqueLabel -Prefix 'dev_acl_recovery_failed'
    $notFound = New-UniqueLabel -Prefix 'dev_acl_recovery_not_found'
    $restoreReady = New-UniqueLabel -Prefix 'dev_acl_recovery_restore_ready'
    $done = New-UniqueLabel -Prefix 'dev_acl_recovery_done'
    Emit-StoreZero64Frame -SlotPosition $JournalHandleSlot
    Emit-StoreZero64Frame -SlotPosition $JournalBufferSlot
    Emit-StoreBits32Frame -SlotPosition $JournalReadCountSlot -Value 0
    Emit-StoreBits32Frame -SlotPosition $recoveryStageSlot -Value 0
    for ($i = 0; $i -lt 7; $i++) { Emit-StoreZero64Frame -SlotPosition ($fileInfoSlot + ($i * 8)) }

    Emit-StoreBits32Frame -SlotPosition $recoveryStageSlot -Value 1 # open committed journal
    Emit-LeaRaxFrame -SlotPosition $JournalPathSlot
    # FILE_SHARE_READ permits independent readers while denying concurrent writes/deletes.
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1, 0xBA, 0x00, 0x00, 0x00, 0x80, 0x41, 0xB8, 0x01, 0x00, 0x00, 0x00, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x30A0) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 3 },
        @{ Kind = 'Immediate'; Value = 0x00200080 },
        @{ Kind = 'Immediate'; Value = 0 }
    )
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xF8, 0xFF))
    Emit-JumpConditional -ConditionCode 0x84 -Label $notFound
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $notFound
    Emit-StoreRaxFrame -SlotPosition $JournalHandleSlot
    Emit-StoreBits32Frame -SlotPosition $recoveryStageSlot -Value 2 # query journal file information
    Emit-Jump -Label $restoreReady

    Mark-CodeLabel -Label $notFound
    Emit-Win64CallIat -TargetRva ([UInt32]0x3268) -StackArguments @() # GetLastError after failed CreateFile
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x02, 0x00, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x84 -Label $done
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x03, 0x00, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x84 -Label $done
    # Preserve the original read-open error and emit the exact native path
    # to redirected stdout before the metadata-only probe.
    Emit-StoreEaxFrame -SlotPosition $expectedSizeSlot
    Emit-DevBrokerWriteDiagnosticPath -PathSlot $JournalPathSlot -PathLengthSlot $PathLengthSlot
    Emit-DevBrokerWriteRecoveryTokenDiagnostic
    Emit-DevBrokerWriteRecoveryAttributeDiagnostic -JournalPathSlot $JournalPathSlot
    Emit-LeaRaxFrame -SlotPosition $JournalPathSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1, 0x33, 0xD2, 0x41, 0xB8, 0x01, 0x00, 0x00, 0x00, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x30A0) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 3 },
        @{ Kind = 'Immediate'; Value = 0x00200080 },
        @{ Kind = 'Immediate'; Value = 0 }
    ) # CreateFileA metadata-only diagnostic
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xF8, 0xFF))
    $metadataProbeFailed = New-UniqueLabel -Prefix 'dev_acl_recovery_metadata_probe_failed'
    Emit-JumpConditional -ConditionCode 0x84 -Label $metadataProbeFailed
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $metadataProbeFailed
    Emit-StoreRaxFrame -SlotPosition $JournalHandleSlot
    Emit-LoadRcxFrame -SlotPosition $JournalHandleSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x30B8) -StackArguments @() # CloseHandle
    Emit-StoreZero64Frame -SlotPosition $JournalHandleSlot
    Emit-StoreBits32Frame -SlotPosition ($scratch + 0xD58) -Value 0
    $metadataProbeDone = New-UniqueLabel -Prefix 'dev_acl_recovery_metadata_probe_done'
    Emit-Jump -Label $metadataProbeDone
    Mark-CodeLabel -Label $metadataProbeFailed
    Emit-Win64CallIat -TargetRva ([UInt32]0x3268) -StackArguments @() # GetLastError for metadata-only probe
    Emit-StoreEaxFrame -SlotPosition ($scratch + 0xD58)
    Mark-CodeLabel -Label $metadataProbeDone
    # Encode original read error and metadata-only error as 1000 + read*256 + metadata.
    Emit-LoadEaxFrame -SlotPosition $expectedSizeSlot
    Emit-Bytes -Bytes ([byte[]]@(0xC1, 0xE0, 0x08))
    Emit-LoadEdxFrame -SlotPosition ($scratch + 0xD58)
    Emit-Bytes -Bytes ([byte[]]@(0x01, 0xD0, 0x05))
    Emit-I32 -Value 1000
    Emit-StoreEaxFrame -SlotPosition $recoveryStageSlot
    Emit-Jump -Label $FailureLabel

    Mark-CodeLabel -Label $restoreReady
    Emit-LoadRcxFrame -SlotPosition $JournalHandleSlot
    Emit-LeaRaxFrame -SlotPosition $fileInfoSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3208) -StackArguments @()
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-StoreBits32Frame -SlotPosition $recoveryStageSlot -Value 3 # validate journal file attributes, links and size
    Emit-LoadEaxFrame -SlotPosition $fileInfoSlot
    Emit-Bytes -Bytes ([byte[]]@(0xA9, 0x10, 0x00, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed
    Emit-Bytes -Bytes ([byte[]]@(0xA9, 0x00, 0x04, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed
    Emit-LoadEaxFrame -SlotPosition ($fileInfoSlot + 40)
    Emit-Bytes -Bytes ([byte[]]@(0x83, 0xF8, 0x01))
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed

    # Read and validate the 32-byte journal header before allocating bounded storage.
    Emit-StoreBits32Frame -SlotPosition $recoveryStageSlot -Value 4 # read fixed header
    Emit-LoadRcxFrame -SlotPosition $JournalHandleSlot
    Emit-LeaRaxFrame -SlotPosition $HeaderSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2, 0x41, 0xB8, 0x20, 0x00, 0x00, 0x00))
    Emit-LeaRaxFrame -SlotPosition $JournalReadCountSlot
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x30B0) -StackArguments @(@{ Kind = 'Immediate'; Value = 0 })
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-LoadEaxFrame -SlotPosition $JournalReadCountSlot
    Emit-Bytes -Bytes ([byte[]]@(0x83, 0xF8, 0x20))
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed
    # Distinguish the three header checks in the negative diagnostic status.
    Emit-StoreBits32Frame -SlotPosition $recoveryStageSlot -Value 50 # first signature DWORD
    Emit-LoadEaxFrame -SlotPosition $HeaderSlot
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x53, 0x48, 0x41, 0x52))
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed
    Emit-StoreBits32Frame -SlotPosition $recoveryStageSlot -Value 51 # second signature DWORD
    Emit-LoadEaxFrame -SlotPosition ($HeaderSlot + 4)
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x41, 0x43, 0x4C, 0x31))
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed
    Emit-StoreBits32Frame -SlotPosition $recoveryStageSlot -Value 52 # version
    Emit-LoadEaxFrame -SlotPosition ($HeaderSlot + 8)
    Emit-Bytes -Bytes ([byte[]]@(0x83, 0xF8, 0x01))
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed

    Emit-StoreBits32Frame -SlotPosition $recoveryStageSlot -Value 6 # validate descriptor lengths
    foreach ($record in @(
        @{ HeaderOffset = 16; LengthSlot = $RootLengthSlot },
        @{ HeaderOffset = 20; LengthSlot = $BuildLengthSlot },
        @{ HeaderOffset = 24; LengthSlot = $BrokerLengthSlot }
    )) {
        Emit-LoadEaxFrame -SlotPosition ($HeaderSlot + $record.HeaderOffset)
        Emit-Bytes -Bytes ([byte[]]@(0x83, 0xF8, 0x14))
        Emit-JumpConditional -ConditionCode 0x82 -Label $failed
        Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x00, 0x40, 0x00, 0x00))
        Emit-JumpConditional -ConditionCode 0x87 -Label $failed
        Emit-StoreEaxFrame -SlotPosition $record.LengthSlot
    }

    Emit-LoadEaxFrame -SlotPosition $RootLengthSlot
    Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC2))
    Emit-LoadEaxFrame -SlotPosition $BuildLengthSlot
    Emit-Bytes -Bytes ([byte[]]@(0x01, 0xD0, 0x89, 0xC2))
    Emit-LoadEaxFrame -SlotPosition $BrokerLengthSlot
    Emit-Bytes -Bytes ([byte[]]@(0x01, 0xD0, 0x83, 0xC0, 0x20))
    Emit-StoreEaxFrame -SlotPosition $expectedSizeSlot
    Emit-StoreBits32Frame -SlotPosition $recoveryStageSlot -Value 7 # validate exact journal file length
    Emit-LoadEaxFrame -SlotPosition ($fileInfoSlot + 32)
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed
    Emit-LoadEaxFrame -SlotPosition ($fileInfoSlot + 36)
    Emit-Bytes -Bytes ([byte[]]@(0x3B, 0x85))
    Emit-I32 -Value (Get-FrameDisp -SlotPosition $expectedSizeSlot)
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed

    Emit-StoreBits32Frame -SlotPosition $recoveryStageSlot -Value 8 # allocate bounded descriptor buffer
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xC9, 0xBA, 0x00, 0xC0, 0x00, 0x00, 0x41, 0xB8, 0x00, 0x30, 0x00, 0x00, 0x41, 0xB9, 0x04, 0x00, 0x00, 0x00))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31D0) -StackArguments @() # VirtualAlloc(48 KiB)
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-StoreRaxFrame -SlotPosition $JournalBufferSlot

    $records = @(
        @{ Length = $RootLengthSlot; Offset = 0; Descriptor = $RootDescriptorSlot },
        @{ Length = $BuildLengthSlot; Offset = 0x4000; Descriptor = $BuildDescriptorSlot },
        @{ Length = $BrokerLengthSlot; Offset = 0x8000; Descriptor = $BrokerDescriptorSlot }
    )
    $recordStage = 9
    foreach ($record in $records) {
        Emit-StoreBits32Frame -SlotPosition $recoveryStageSlot -Value $recordStage # read exact descriptor bytes
        Emit-LoadRcxFrame -SlotPosition $JournalHandleSlot
        Emit-LoadRaxFrame -SlotPosition $JournalBufferSlot
        if ($record.Offset -ne 0) {
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0x05))
            Emit-I32 -Value $record.Offset
        }
        Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
        Emit-LoadEaxFrame -SlotPosition $record.Length
        Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC0))
        Emit-LeaRaxFrame -SlotPosition $JournalReadCountSlot
        Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC1))
        Emit-Win64CallIat -TargetRva ([UInt32]0x30B0) -StackArguments @(@{ Kind = 'Immediate'; Value = 0 })
        Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
        Emit-JumpConditional -ConditionCode 0x84 -Label $failed
        Emit-LoadEaxFrame -SlotPosition $JournalReadCountSlot
        Emit-Bytes -Bytes ([byte[]]@(0x3B, 0x85))
        Emit-I32 -Value (Get-FrameDisp -SlotPosition $record.Length)
        Emit-JumpConditional -ConditionCode 0x85 -Label $failed

        Emit-StoreBits32Frame -SlotPosition $recoveryStageSlot -Value ($recordStage + 1) # validate self-relative descriptor and exact length
        Emit-LoadRaxFrame -SlotPosition $JournalBufferSlot
        if ($record.Offset -ne 0) {
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0x05))
            Emit-I32 -Value $record.Offset
        }
        Emit-StoreRaxFrame -SlotPosition $record.Descriptor
        Emit-LoadRcxFrame -SlotPosition $record.Descriptor
        Emit-Win64CallIat -TargetRva ([UInt32]0x32F8) -StackArguments @()
        Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
        Emit-JumpConditional -ConditionCode 0x84 -Label $failed
        Emit-LoadRcxFrame -SlotPosition $record.Descriptor
        Emit-Win64CallIat -TargetRva ([UInt32]0x32F0) -StackArguments @()
        Emit-Bytes -Bytes ([byte[]]@(0x3B, 0x85))
        Emit-I32 -Value (Get-FrameDisp -SlotPosition $record.Length)
        Emit-JumpConditional -ConditionCode 0x85 -Label $failed
        $recordStage += 2
    }

    # Restore parents before descendants so each child snapshot wins after inheritance propagation.
    Emit-StoreBits32Frame -SlotPosition $recoveryStageSlot -Value 15 # restore workspace root
    Emit-DevBrokerRestoreSecurityDescriptor -PathSlot $WorkspaceRootSlot -DescriptorSlot $RootDescriptorSlot -FailureLabel $failed
    Emit-StoreBits32Frame -SlotPosition $recoveryStageSlot -Value 16 # restore Build
    Emit-DevBrokerRestoreSecurityDescriptor -PathSlot $BuildPathSlot -DescriptorSlot $BuildDescriptorSlot -RestoreLabel $true -FailureLabel $failed
    Emit-StoreBits32Frame -SlotPosition $recoveryStageSlot -Value 17 # restore broker directory
    Emit-DevBrokerRestoreSecurityDescriptor -PathSlot $BrokerDirectorySlot -DescriptorSlot $BrokerDescriptorSlot -RestoreLabel $true -FailureLabel $failed

    Emit-StoreBits32Frame -SlotPosition $recoveryStageSlot -Value 18 # close journal handle
    Emit-LoadRcxFrame -SlotPosition $JournalHandleSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x30B8) -StackArguments @()
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-StoreZero64Frame -SlotPosition $JournalHandleSlot
    Emit-StoreBits32Frame -SlotPosition $recoveryStageSlot -Value 19 # retire committed journal
    Emit-LeaRaxFrame -SlotPosition $JournalPathSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3310) -StackArguments @() # DeleteFileA after complete restore
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-Jump -Label $done

    Mark-CodeLabel -Label $failed
    Emit-LoadRcxFrame -SlotPosition $JournalHandleSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
    $skipClose = New-UniqueLabel -Prefix 'dev_acl_recovery_skip_close'
    Emit-JumpConditional -ConditionCode 0x84 -Label $skipClose
    Emit-Win64CallIat -TargetRva ([UInt32]0x30B8) -StackArguments @()
    Emit-StoreZero64Frame -SlotPosition $JournalHandleSlot
    Mark-CodeLabel -Label $skipClose
    foreach ($slot in @($RootDescriptorSlot, $BuildDescriptorSlot, $BrokerDescriptorSlot)) {
        Emit-StoreZero64Frame -SlotPosition $slot
    }
    Emit-LoadRcxFrame -SlotPosition $JournalBufferSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
    $skipFree = New-UniqueLabel -Prefix 'dev_acl_recovery_skip_free'
    Emit-JumpConditional -ConditionCode 0x84 -Label $skipFree
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xD2, 0x41, 0xB8, 0x00, 0x80, 0x00, 0x00))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31D8) -StackArguments @()
    Emit-StoreZero64Frame -SlotPosition $JournalBufferSlot
    Mark-CodeLabel -Label $skipFree
    Emit-Jump -Label $FailureLabel

    Mark-CodeLabel -Label $done
    # Pointers into the VirtualAlloc buffer must be cleared before it is freed;
    # common cleanup must never mistake these interior pointers for LocalAlloc blocks.
    $noBuffer = New-UniqueLabel -Prefix 'dev_acl_recovery_no_buffer'
    Emit-LoadRaxFrame -SlotPosition $JournalBufferSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $noBuffer
    foreach ($slot in @($RootDescriptorSlot, $BuildDescriptorSlot, $BrokerDescriptorSlot)) {
        Emit-StoreZero64Frame -SlotPosition $slot
    }
    Emit-LoadRcxFrame -SlotPosition $JournalBufferSlot
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xD2, 0x41, 0xB8, 0x00, 0x80, 0x00, 0x00))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31D8) -StackArguments @()
    Emit-StoreZero64Frame -SlotPosition $JournalBufferSlot
    Mark-CodeLabel -Label $noBuffer
    # No active journal means no ACL mutation is pending; remove an abandoned pre-commit temp.
    Emit-LeaRaxFrame -SlotPosition $TempPathSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3310) -StackArguments @() # DeleteFileA
}

function Emit-DevBrokerBuildWorkspacePath {
    param([int] $RootSlot, [int] $RootLengthSlot, [object] $SuffixItem, [int] $SuffixLength, [int] $DestinationSlot)
    if ($SuffixLength -lt 1 -or $SuffixLength -gt 240) { throw 'Invalid DevAgent workspace path suffix length.' }
    Emit-LeaRaxFrame -SlotPosition $DestinationSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC7)) # RDI = destination
    Emit-LeaRaxFrame -SlotPosition $RootSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC6, 0xFC)) # RSI = root; CLD
    Emit-LoadEaxFrame -SlotPosition $RootLengthSlot
    Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC1, 0xF3, 0xA4)) # copy root length
    Emit-DataAddress -DataItem $SuffixItem
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC6, 0xB9))
    Emit-I32 -Value $SuffixLength
    Emit-Bytes -Bytes ([byte[]]@(0xF3, 0xA4, 0xC6, 0x07, 0x00)) # suffix + NUL
}
function Emit-DevBrokerCheckDirectoryChain {
    param([int] $PathSlot, [string] $FailureLabel)
    $driveUpper = New-UniqueLabel -Prefix 'dev_path_drive_upper'
    $scanColon = New-UniqueLabel -Prefix 'dev_path_scan_colon'
    $colonDone = New-UniqueLabel -Prefix 'dev_path_colon_done'
    $scanComponents = New-UniqueLabel -Prefix 'dev_path_scan_components'
    $nextComponent = New-UniqueLabel -Prefix 'dev_path_next_component'
    $checkFinal = New-UniqueLabel -Prefix 'dev_path_check_final'

    # Require a drive-qualified DOS absolute path. UNC/device paths fail closed.
    Emit-Bytes -Bytes ([byte[]]@(0x0F, 0xB6, 0x85))
    Emit-I32 -Value (Get-FrameDisp -SlotPosition $PathSlot)
    Emit-Bytes -Bytes ([byte[]]@(0x3C, 0x41))
    Emit-JumpConditional -ConditionCode 0x82 -Label $FailureLabel
    Emit-Bytes -Bytes ([byte[]]@(0x3C, 0x5A))
    Emit-JumpConditional -ConditionCode 0x86 -Label $driveUpper
    Emit-Bytes -Bytes ([byte[]]@(0x3C, 0x61))
    Emit-JumpConditional -ConditionCode 0x82 -Label $FailureLabel
    Emit-Bytes -Bytes ([byte[]]@(0x3C, 0x7A))
    Emit-JumpConditional -ConditionCode 0x87 -Label $FailureLabel
    Mark-CodeLabel -Label $driveUpper
    Emit-Bytes -Bytes ([byte[]]@(0x80, 0xBD))
    Emit-I32 -Value (Get-FrameDisp -SlotPosition ($PathSlot + 1))
    Emit-Bytes -Bytes ([byte[]]@(0x3A))
    Emit-JumpConditional -ConditionCode 0x85 -Label $FailureLabel
    Emit-Bytes -Bytes ([byte[]]@(0x80, 0xBD))
    Emit-I32 -Value (Get-FrameDisp -SlotPosition ($PathSlot + 2))
    Emit-Bytes -Bytes ([byte[]]@(0x5C))
    Emit-JumpConditional -ConditionCode 0x85 -Label $FailureLabel

    # Reject alternate data streams in every character after the drive prefix.
    Emit-LeaRaxFrame -SlotPosition ($PathSlot + 2)
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC6))
    Mark-CodeLabel -Label $scanColon
    Emit-Bytes -Bytes ([byte[]]@(0x8A, 0x06, 0x84, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $colonDone
    Emit-Bytes -Bytes ([byte[]]@(0x3C, 0x3A))
    Emit-JumpConditional -ConditionCode 0x84 -Label $FailureLabel
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0xFF, 0xC6))
    Emit-Jump -Label $scanColon
    Mark-CodeLabel -Label $colonDone

    # Validate C:\ itself before walking subsequent components.
    Emit-LeaRaxFrame -SlotPosition ($PathSlot + 3)
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC6))
    # Use a dedicated byte slot rather than relying on a caller register across API calls.
    $savedByteSlot = [int]$script:ActiveContext.ScratchPosition + 0xDF0
    Emit-StoreZero64Frame -SlotPosition $savedByteSlot
    $rootAttributesSlot = [int]$script:ActiveContext.ScratchPosition + 0xDF8
    Emit-Bytes -Bytes ([byte[]]@(0x8A, 0x06, 0x88, 0x85))
    Emit-I32 -Value (Get-FrameDisp -SlotPosition $savedByteSlot)
    Emit-Bytes -Bytes ([byte[]]@(0xC6, 0x06, 0x00)) # temporarily end at C:\
    Emit-LeaRaxFrame -SlotPosition $PathSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31C8) -StackArguments @() # GetFileAttributesA(C:\)
    Emit-StoreEaxFrame -SlotPosition $rootAttributesSlot
    Emit-LoadEaxFrame -SlotPosition $savedByteSlot
    Emit-Bytes -Bytes ([byte[]]@(0x88, 0x06)) # restore first component byte
    Emit-LoadEaxFrame -SlotPosition $rootAttributesSlot
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0xFF, 0xFF, 0xFF, 0xFF))
    Emit-JumpConditional -ConditionCode 0x84 -Label $FailureLabel
    Emit-Bytes -Bytes ([byte[]]@(0xA9, 0x10, 0x00, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x84 -Label $FailureLabel
    Emit-Bytes -Bytes ([byte[]]@(0xA9, 0x00, 0x04, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x85 -Label $FailureLabel

    # Every intermediate component must be a non-reparse directory.
    Emit-LeaRaxFrame -SlotPosition ($PathSlot + 3)
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC6))
    Mark-CodeLabel -Label $scanComponents
    Emit-Bytes -Bytes ([byte[]]@(0x8A, 0x06, 0x84, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $checkFinal
    Emit-Bytes -Bytes ([byte[]]@(0x3C, 0x5C))
    Emit-JumpConditional -ConditionCode 0x85 -Label $nextComponent
    Emit-Bytes -Bytes ([byte[]]@(0xC6, 0x06, 0x00))
    Emit-LeaRaxFrame -SlotPosition $PathSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31C8) -StackArguments @()
    Emit-Bytes -Bytes ([byte[]]@(0xC6, 0x06, 0x5C))
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0xFF, 0xFF, 0xFF, 0xFF))
    Emit-JumpConditional -ConditionCode 0x84 -Label $FailureLabel
    Emit-Bytes -Bytes ([byte[]]@(0xA9, 0x10, 0x00, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x84 -Label $FailureLabel
    Emit-Bytes -Bytes ([byte[]]@(0xA9, 0x00, 0x04, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x85 -Label $FailureLabel
    Mark-CodeLabel -Label $nextComponent
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0xFF, 0xC6))
    Emit-Jump -Label $scanComponents
    Mark-CodeLabel -Label $checkFinal
    Emit-LeaRaxFrame -SlotPosition $PathSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31C8) -StackArguments @()
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0xFF, 0xFF, 0xFF, 0xFF))
    Emit-JumpConditional -ConditionCode 0x84 -Label $FailureLabel
    Emit-Bytes -Bytes ([byte[]]@(0xA9, 0x10, 0x00, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x84 -Label $FailureLabel
    Emit-Bytes -Bytes ([byte[]]@(0xA9, 0x00, 0x04, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x85 -Label $FailureLabel
}
function Emit-DevRunTool {
    param([int] $ToolSlot, [int] $TimeoutSlot, [int] $BaseDepth)
    $scratch = [int]$script:ActiveContext.ScratchPosition

    # Fixed frame layout. All child-visible paths/handles are broker-owned.
    $applicationSlot = $scratch + 0x000
    $modulePathSlot = $scratch + 0x120
    $workspaceRootSlot = $modulePathSlot
    $commandLineSlot = $scratch + 0x360
    $startupSlot = $scratch + 0x580
    $processSlot = $scratch + 0x600
    $jobInfoSlot = $scratch + 0x640
    $buildPathSlot = $scratch + 0x700
    $brokerDirectorySlot = $scratch + 0x820
    $outputPathSlot = $scratch + 0x940
    $attributeListSlot = $scratch + 0xA50
    $pipeReadSlot = $scratch + 0xA58
    $pipeWriteSlot = $scratch + 0xA60
    $nulHandleSlot = $scratch + 0xA68
    $attributeSizeSlot = $scratch + 0xA70
    $securityCapabilitiesSlot = $scratch + 0xA78
    $pipeSecuritySlot = $scratch + 0xA98
    $handleListSlot = $scratch + 0xAB0
    $outputBufferSlot = $scratch + 0xAC0
    $outputCountSlot = $scratch + 0xAC8
    $availableSlot = $scratch + 0xACC
    $readCountSlot = $scratch + 0xAD0
    $remainingMsSlot = $scratch + 0xAD4
    $outputFileHandleSlot = $scratch + 0xAD8
    $outputWrittenSlot = $scratch + 0xAE0
    $pipeClosedSlot = $scratch + 0xAE4
    $appContainerSidSlot = $scratch + 0xAE8
    $mutexHandleSlot = $scratch + 0xAF0
    $profileCreatedSlot = $scratch + 0xE7C
    $profileNameSlot = $scratch + 0xF00
    $profileRandomSlot = $scratch + 0xF80
    $derivedProfileSidSlot = $scratch + 0xF90
    $legacyAppContainerSidSlot = $scratch + 0xF98
    $mutexAcquiredSlot = $scratch + 0xAF8
    $attributeListReadySlot = $scratch + 0xAFC
    $childActiveSlot = $scratch + 0xB00
    $sourceTokenSlot = $scratch + 0xB08
    $restrictedTokenSlot = $scratch + 0xB10
    $childTokenSlot = $scratch + 0xB18
    $tokenInformationSlot = $scratch + 0xB38
    $tokenLengthSlot = $scratch + 0xB88
    $rootLengthSlot = $scratch + 0xB7C
    $modulePathLengthSlot = $scratch + 0xB80
    $pathScratchSlot = $scratch + 0xC00
    $outputFileInfoSlot = $scratch + 0xDA8
    $journalHeaderSlot = $scratch + 0xE10
    $journalHandleSlot = $scratch + 0xE30
    $journalWrittenSlot = $scratch + 0xE38
    $rootDescriptorSlot = $scratch + 0xE40
    $buildDescriptorSlot = $scratch + 0xE48
    $brokerDescriptorSlot = $scratch + 0xE50
    $rootDescriptorLengthSlot = $scratch + 0xE58
    $buildDescriptorLengthSlot = $scratch + 0xE5C
    $brokerDescriptorLengthSlot = $scratch + 0xE60
    $journalBufferSlot = $scratch + 0xE68
    $journalReadCountSlot = $scratch + 0xE70
    $transactionActiveSlot = $scratch + 0xE78
    $journalPathSlot = $pathScratchSlot
    $journalPathLengthSlot = $scratch + 0xD5C
    $journalTempPathSlot = $outputPathSlot

    $jobHandleSlot = Get-TempSlotPosition -Depth ($BaseDepth + 2)
    $saveRdiSlot = Get-TempSlotPosition -Depth ($BaseDepth + 3)
    $saveRsiSlot = Get-TempSlotPosition -Depth ($BaseDepth + 4)
    $resultSlot = Get-TempSlotPosition -Depth ($BaseDepth + 5)
    $exitCodeSlot = Get-TempSlotPosition -Depth ($BaseDepth + 6)
    $hashFileHandleSlot = Get-TempSlotPosition -Depth ($BaseDepth + 7)

    # Initialize every pointer, handle, and state flag before any branch reaches cleanup.
    foreach ($slot in @(
        $jobHandleSlot, $hashFileHandleSlot, $attributeListSlot, $pipeReadSlot,
        $pipeWriteSlot, $nulHandleSlot, $outputBufferSlot, $outputFileHandleSlot,
        $appContainerSidSlot, $legacyAppContainerSidSlot, $mutexHandleSlot, $sourceTokenSlot,
        $restrictedTokenSlot, $childTokenSlot, $journalHandleSlot,
        $rootDescriptorSlot, $buildDescriptorSlot, $brokerDescriptorSlot,
        $journalBufferSlot
    )) { Emit-StoreZero64Frame -SlotPosition $slot }
    foreach ($slot in @($journalWrittenSlot, $rootDescriptorLengthSlot, $buildDescriptorLengthSlot,
        $brokerDescriptorLengthSlot, $journalReadCountSlot, $transactionActiveSlot, $profileCreatedSlot)) {
        Emit-StoreBits32Frame -SlotPosition $slot -Value 0
    }
    Emit-StoreZero64Frame -SlotPosition $journalHeaderSlot
    for ($i = 0; $i -lt 3; $i++) { Emit-StoreZero64Frame -SlotPosition ($processSlot + ($i * 8)) }
    foreach ($slot in @(
        $mutexAcquiredSlot, $attributeListReadySlot, $childActiveSlot,
        $outputCountSlot, $availableSlot, $readCountSlot, $remainingMsSlot,
        $outputWrittenSlot, $pipeClosedSlot
    )) { Emit-StoreBits32Frame -SlotPosition $slot -Value 0 }
    Emit-StoreBits32Frame -SlotPosition $resultSlot -Value 0
    Emit-StoreZero64Frame -SlotPosition $tokenLengthSlot
    Emit-StoreZero64Frame -SlotPosition $modulePathLengthSlot
    Emit-StoreZero64Frame -SlotPosition $rootLengthSlot

    $unknownTool = New-UniqueLabel -Prefix 'dev_tool_unknown'
    $invalidTimeout = New-UniqueLabel -Prefix 'dev_tool_timeout_invalid'
    $toolLabels = @(
        (New-UniqueLabel -Prefix 'dev_tool_stage7a'),
        (New-UniqueLabel -Prefix 'dev_tool_runtime_abi'),
        (New-UniqueLabel -Prefix 'dev_tool_baseline_m1_m6'),
        (New-UniqueLabel -Prefix 'dev_tool_stack_unwind'),
        (New-UniqueLabel -Prefix 'dev_tool_timeout_probe'),
        (New-UniqueLabel -Prefix 'dev_tool_success_probe'),
        (New-UniqueLabel -Prefix 'dev_tool_sandbox_probe'),
        (New-UniqueLabel -Prefix 'dev_tool_output_overflow_probe'),
        (New-UniqueLabel -Prefix 'dev_tool_acl_crash_probe')
    )
    $commandReady = New-UniqueLabel -Prefix 'dev_tool_command_ready'
    $hashVerified = New-UniqueLabel -Prefix 'dev_tool_hash_verified'
    $hashFail = New-UniqueLabel -Prefix 'dev_tool_hash_fail'
    $pathFail = New-UniqueLabel -Prefix 'dev_tool_path_fail'
    $directoryFail = New-UniqueLabel -Prefix 'dev_tool_directory_fail'
    # Temporary fail-site codes isolate the repeated-invocation path preflight.
    $directoryFailImage = New-UniqueLabel -Prefix 'dev_tool_directory_fail_image'
    $directoryFailRoot = New-UniqueLabel -Prefix 'dev_tool_directory_fail_root'
    $directoryFailCwd = New-UniqueLabel -Prefix 'dev_tool_directory_fail_cwd'
    $directoryFailBuild = New-UniqueLabel -Prefix 'dev_tool_directory_fail_build'
    $directoryFailBroker = New-UniqueLabel -Prefix 'dev_tool_directory_fail_broker'
    $directoryFailFixed = New-UniqueLabel -Prefix 'dev_tool_directory_fail_fixed'
    $directoryFailCompiler = New-UniqueLabel -Prefix 'dev_tool_directory_fail_compiler'
    $mutexFail = New-UniqueLabel -Prefix 'dev_tool_mutex_fail'
    $appContainerFail = New-UniqueLabel -Prefix 'dev_tool_appcontainer_fail'
    $legacyAppContainerFail = New-UniqueLabel -Prefix 'dev_tool_legacy_appcontainer_fail'
    $aclFail = New-UniqueLabel -Prefix 'dev_tool_acl_fail'
    $aclRecoveryFail = New-UniqueLabel -Prefix 'dev_tool_acl_recovery_fail'
    $journalFail = New-UniqueLabel -Prefix 'dev_tool_acl_journal_fail'
    $aclRollbackFail = New-UniqueLabel -Prefix 'dev_tool_acl_rollback_fail'
    $aclRollbackRootFail = New-UniqueLabel -Prefix 'dev_tool_acl_rollback_root_fail'
    $aclRollbackBuildFail = New-UniqueLabel -Prefix 'dev_tool_acl_rollback_build_fail'
    $aclRollbackBrokerFail = New-UniqueLabel -Prefix 'dev_tool_acl_rollback_broker_fail'
    $aclRollbackJournalFail = New-UniqueLabel -Prefix 'dev_tool_acl_rollback_journal_fail'
    $tokenFail = New-UniqueLabel -Prefix 'dev_tool_token_fail'
    $pipeFail = New-UniqueLabel -Prefix 'dev_tool_pipe_fail'
    $attributeFail = New-UniqueLabel -Prefix 'dev_tool_attribute_fail'
    $jobFail = New-UniqueLabel -Prefix 'dev_tool_job_fail'
    $jobConfigFail = New-UniqueLabel -Prefix 'dev_tool_job_config_fail'
    $createFail = New-UniqueLabel -Prefix 'dev_tool_create_fail'
    $assignFail = New-UniqueLabel -Prefix 'dev_tool_assign_fail'
    $resumeFail = New-UniqueLabel -Prefix 'dev_tool_resume_fail'
    $waitFail = New-UniqueLabel -Prefix 'dev_tool_wait_fail'
    $timeoutFail = New-UniqueLabel -Prefix 'dev_tool_timeout'
    $outputOverflow = New-UniqueLabel -Prefix 'dev_tool_output_overflow'
    $outputFail = New-UniqueLabel -Prefix 'dev_tool_output_fail'
    $captureLoop = New-UniqueLabel -Prefix 'dev_tool_capture_loop'
    $capturePipeClosed = New-UniqueLabel -Prefix 'dev_tool_capture_pipe_closed'
    $capturePipeEof = New-UniqueLabel -Prefix 'dev_tool_capture_pipe_eof'
    $processDone = New-UniqueLabel -Prefix 'dev_tool_process_done'
    $finalDrain = New-UniqueLabel -Prefix 'dev_tool_final_drain'
    $finalPipeEof = New-UniqueLabel -Prefix 'dev_tool_final_pipe_eof'
    $captureDone = New-UniqueLabel -Prefix 'dev_tool_capture_done'
    $cleanup = New-UniqueLabel -Prefix 'dev_tool_cleanup'
    $done = New-UniqueLabel -Prefix 'dev_tool_done'

    $powerShellSuffix = '\WindowsPowerShell\v1.0\powershell.exe'
    $powerShellSuffixItem = Register-DataConstant -Value $powerShellSuffix
    $powerShellSuffixLength = [System.Text.Encoding]::ASCII.GetByteCount($powerShellSuffix)
    # Keep the trusted recovery host outside Low-IL writable Build staging.
    # A crash must not relabel the image used by the next recovery invocation.
    $imageSuffix = '\.sharnou-devagent-host\DevAgentBroker.exe'
    $imageSuffixItem = Register-DataConstant -Value $imageSuffix
    $imageSuffixLength = [System.Text.Encoding]::ASCII.GetByteCount($imageSuffix)
    $buildSuffix = '\Build'
    $buildSuffixItem = Register-DataConstant -Value $buildSuffix
    $buildSuffixLength = [System.Text.Encoding]::ASCII.GetByteCount($buildSuffix)
    $brokerSuffix = '\Build\DevAgentBroker'
    $brokerSuffixItem = Register-DataConstant -Value $brokerSuffix
    $brokerSuffixLength = [System.Text.Encoding]::ASCII.GetByteCount($brokerSuffix)
    $captureSuffix = '\Build\DevAgentBroker\captured-output.bin'
    $captureSuffixItem = Register-DataConstant -Value $captureSuffix
    $captureSuffixLength = [System.Text.Encoding]::ASCII.GetByteCount($captureSuffix)
    $journalSuffix = '\.sharnou-devagent-acl.journal'
    $journalSuffixItem = Register-DataConstant -Value $journalSuffix
    $journalSuffixLength = [System.Text.Encoding]::ASCII.GetByteCount($journalSuffix)
    $journalTempSuffix = '\.sharnou-devagent-acl.journal.tmp'
    $journalTempSuffixItem = Register-DataConstant -Value $journalTempSuffix
    $journalTempSuffixLength = [System.Text.Encoding]::ASCII.GetByteCount($journalTempSuffix)

    $manifestPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\Tests\DevAgentBroker\tool-manifest.json'))
    $expectedManifestSha256 = 'C74D82D29C73034A63E6A34113CFD9ED243BB4356D8B1318BEE7100E0E09AAFE'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'Pinned DevAgent tool manifest is missing.' }
    $actualManifestSha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash
    if ($actualManifestSha256 -cne $expectedManifestSha256) {
        throw "Pinned DevAgent tool manifest SHA-256 mismatch: expected=$expectedManifestSha256 actual=$actualManifestSha256"
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $fixedToolPaths = @(
        [pscustomobject]@{ Id = 1; Path = 'Tests\Test-Stage7A.ps1' },
        [pscustomobject]@{ Id = 2; Path = 'Tests\Test-RuntimeABI.ps1' },
        [pscustomobject]@{ Id = 3; Path = 'Tests\BaselineM6\Test-Milestone6Baseline.ps1' },
        [pscustomobject]@{ Id = 4; Path = 'Tests\Test-StackProbeUnwind.ps1' },
        [pscustomobject]@{ Id = 5; Path = 'Tests\DevAgentBroker\TimeoutProbe.ps1' },
        [pscustomobject]@{ Id = 6; Path = 'Tests\DevAgentBroker\SuccessProbe.ps1' },
        [pscustomobject]@{ Id = 7; Path = 'Tests\DevAgentBroker\SandboxProbe.ps1' },
        [pscustomobject]@{ Id = 8; Path = 'Tests\DevAgentBroker\OverflowProbe.ps1' },
        [pscustomobject]@{ Id = 9; Path = 'Tests\DevAgentBroker\CrashProbe.ps1' }
    )
    if ([int]$manifest.version -ne 1 -or @($manifest.tools).Count -ne $fixedToolPaths.Count) {
        throw 'Pinned DevAgent tool manifest version or fixed tool count is invalid.'
    }
    foreach ($fixedTool in $fixedToolPaths) {
        $entry = @($manifest.tools | Where-Object { [int]$_.id -eq $fixedTool.Id })
        $toolPath = Join-Path $PSScriptRoot ('..\' + $fixedTool.Path)
        if (-not (Test-Path -LiteralPath $toolPath -PathType Leaf)) { throw "Pinned DevAgent tool is missing: $($fixedTool.Path)" }
        $toolHash = (Get-FileHash -LiteralPath $toolPath -Algorithm SHA256).Hash
        if ($entry.Count -ne 1 -or [string]$entry[0].path -cne $fixedTool.Path -or [string]$entry[0].sha256 -cne $toolHash) {
            throw "Pinned DevAgent tool manifest path/hash mismatch for tool ID $($fixedTool.Id)."
        }
        $fixedTool | Add-Member -NotePropertyName Sha256 -NotePropertyValue ([string]$entry[0].sha256) -Force
        $fixedTool | Add-Member -NotePropertyName SuffixItem -NotePropertyValue (Register-DataConstant -Value ('\' + $fixedTool.Path)) -Force
        $fixedTool | Add-Member -NotePropertyName SuffixLength -NotePropertyValue ([System.Text.Encoding]::ASCII.GetByteCount('\' + $fixedTool.Path)) -Force
    }

    # Construct a bounded command line around the selected absolute path only after
    # it is canonicalized and hash-verified. The child never resolves a CWD-relative script.
    $commandPrefix = 'powershell.exe -NoLogo -NoProfile -NonInteractive -Command "$ErrorActionPreference=''Stop'';& '''
    $commandSuffix = ''';if($null -ne $global:SHARNOU_TOOL_EXIT_CODE){exit [int]$global:SHARNOU_TOOL_EXIT_CODE}"'
    $commandPrefixItem = Register-DataConstant -Value $commandPrefix
    $commandSuffixItem = Register-DataConstant -Value $commandSuffix
    $commandPrefixLength = [System.Text.Encoding]::ASCII.GetByteCount($commandPrefix)
    $commandSuffixLength = [System.Text.Encoding]::ASCII.GetByteCount($commandSuffix)
    $maxToolSuffixLength = [int](($fixedToolPaths | Measure-Object -Property SuffixLength -Maximum).Maximum)
    if (($commandPrefixLength + 200 + $maxToolSuffixLength + $commandSuffixLength) -ge 0x220) {
        throw 'Absolute-path DevAgent command exceeds the fixed STARTUPINFO command buffer.'
    }

    # REP MOVSB uses nonvolatile RSI/RDI; preserve both for the Sharnou caller.
    Emit-StoreRdiFrame -SlotPosition $saveRdiSlot
    Emit-StoreRsiFrame -SlotPosition $saveRsiSlot

    # Validate tool ID and timeout before any filesystem or process side effect.
    Emit-LoadEaxFrame -SlotPosition $TimeoutSlot
    Emit-Bytes -Bytes ([byte[]]@(0x3D))
    Emit-I32 -Value 1000
    Emit-JumpConditional -ConditionCode 0x82 -Label $invalidTimeout
    Emit-Bytes -Bytes ([byte[]]@(0x3D))
    Emit-I32 -Value 300000
    Emit-JumpConditional -ConditionCode 0x87 -Label $invalidTimeout
    Emit-LoadEaxFrame -SlotPosition $ToolSlot
    for ($i = 0; $i -lt $toolLabels.Count; $i++) {
        Emit-Bytes -Bytes ([byte[]]@(0x3D))
        Emit-I32 -Value ($i + 1)
        Emit-JumpConditional -ConditionCode 0x84 -Label $toolLabels[$i]
    }
    Emit-Jump -Label $unknownTool
    for ($i = 0; $i -lt $fixedToolPaths.Count; $i++) {
        Mark-CodeLabel -Label $toolLabels[$i]
        Emit-Jump -Label $commandReady
    }
    Mark-CodeLabel -Label $unknownTool
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x9C, 0xFF, 0xFF, 0xFF)) # -100: unknown tool ID
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup
    Mark-CodeLabel -Label $invalidTimeout
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x9B, 0xFF, 0xFF, 0xFF)) # -101: timeout outside [1000,300000]
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup
    Mark-CodeLabel -Label $commandReady

    # Resolve PowerShell from the absolute Windows System directory; never search PATH.
    Emit-LeaRaxFrame -SlotPosition $applicationSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1, 0xBA, 0x04, 0x01, 0x00, 0x00))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3178) -StackArguments @() # GetSystemDirectoryA
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $pathFail
    Emit-Bytes -Bytes ([byte[]]@(0x3D))
    Emit-I32 -Value (220 - $powerShellSuffixLength)
    Emit-JumpConditional -ConditionCode 0x87 -Label $pathFail
    Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC6)) # ESI = System32 length
    Emit-LeaRaxFrame -SlotPosition $applicationSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC7, 0x48, 0x01, 0xF7)) # RDI = end of System32 path
    Emit-DataAddress -DataItem $powerShellSuffixItem
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC6, 0xB9))
    Emit-I32 -Value $powerShellSuffixLength
    Emit-Bytes -Bytes ([byte[]]@(0xF3, 0xA4, 0xC6, 0x07, 0x00)) # append fixed suffix and NUL

    # Derive the workspace root from this executable's absolute image path.
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xC9)) # HMODULE = NULL
    Emit-LeaRaxFrame -SlotPosition $workspaceRootSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2, 0x41, 0xB8, 0x04, 0x01, 0x00, 0x00))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3218) -StackArguments @() # GetModuleFileNameA
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $directoryFailImage
    Emit-Bytes -Bytes ([byte[]]@(0x3D))
    Emit-I32 -Value 259
    Emit-JumpConditional -ConditionCode 0x87 -Label $directoryFailImage
    Emit-StoreEaxFrame -SlotPosition $modulePathLengthSlot
    Emit-Bytes -Bytes ([byte[]]@(0x3D))
    Emit-I32 -Value $imageSuffixLength
    Emit-JumpConditional -ConditionCode 0x82 -Label $directoryFailImage

    # Require the trusted host image to live outside Low-IL writable Build staging.
    Emit-LeaRaxFrame -SlotPosition $workspaceRootSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC7))
    Emit-LoadEaxFrame -SlotPosition $modulePathLengthSlot
    Emit-Bytes -Bytes ([byte[]]@(0x2D))
    Emit-I32 -Value $imageSuffixLength
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x63, 0xC0, 0x48, 0x01, 0xC7))
    Emit-DataAddress -DataItem $imageSuffixItem
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC6, 0xB9))
    Emit-I32 -Value $imageSuffixLength
    Emit-Bytes -Bytes ([byte[]]@(0xFC, 0xF3, 0xA6)) # CLD; REPE CMPSB
    Emit-JumpConditional -ConditionCode 0x85 -Label $directoryFailImage
    Emit-LoadEaxFrame -SlotPosition $modulePathLengthSlot
    Emit-Bytes -Bytes ([byte[]]@(0x2D))
    Emit-I32 -Value $imageSuffixLength
    Emit-StoreEaxFrame -SlotPosition $rootLengthSlot
    Emit-Bytes -Bytes ([byte[]]@(0xC6, 0x84, 0x05))
    Emit-I32 -Value (Get-FrameDisp -SlotPosition $workspaceRootSlot)
    Emit-Bytes -Bytes ([byte[]]@(0x00)) # terminate workspace root

    # Validate only the broker image's workspace root before recovery. A previous
    # execution can be interrupted after narrowing descendant directory DACLs;
    # validating Build/Tests here would then block the very rollback needed to
    # restore those directories. Descendant checks are deliberately post-recovery.
    Emit-DevBrokerCheckDirectoryChain -PathSlot $workspaceRootSlot -FailureLabel $directoryFailRoot
    Emit-DevBrokerPathCheck -FrameSlot $workspaceRootSlot -IsDirectory $true -FailureLabel $directoryFailRoot

    # Construct absolute child paths from the checked root without opening the
    # descendants. The recovery helper uses handle-based OPEN_REPARSE_POINT checks
    # and the durable snapshot before any ordinary descendant preflight occurs.
    Emit-DevBrokerBuildWorkspacePath -RootSlot $workspaceRootSlot -RootLengthSlot $rootLengthSlot -SuffixItem $buildSuffixItem -SuffixLength $buildSuffixLength -DestinationSlot $buildPathSlot
    Emit-DevBrokerBuildWorkspacePath -RootSlot $workspaceRootSlot -RootLengthSlot $rootLengthSlot -SuffixItem $brokerSuffixItem -SuffixLength $brokerSuffixLength -DestinationSlot $brokerDirectorySlot
    Emit-DevBrokerBuildWorkspacePath -RootSlot $workspaceRootSlot -RootLengthSlot $rootLengthSlot -SuffixItem $captureSuffixItem -SuffixLength $captureSuffixLength -DestinationSlot $outputPathSlot

    # Journal files live in the checked workspace root. The temporary file is
    # atomically renamed only after all three original descriptors are flushed.
    Emit-DevBrokerBuildWorkspacePath -RootSlot $workspaceRootSlot -RootLengthSlot $rootLengthSlot -SuffixItem $journalSuffixItem -SuffixLength $journalSuffixLength -DestinationSlot $journalPathSlot
    Emit-DevBrokerBuildWorkspacePath -RootSlot $workspaceRootSlot -RootLengthSlot $rootLengthSlot -SuffixItem $journalTempSuffixItem -SuffixLength $journalTempSuffixLength -DestinationSlot $journalTempPathSlot

    # Serialize each ACL transaction across broker instances and recover abandoned work first.
    $mutexNameItem = Register-DataConstant -Value 'Local\SharnouDevAgentBroker.Sandbox.v3'
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xC9, 0x33, 0xD2))
    Emit-DataAddress -DataItem $mutexNameItem
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0))
    Emit-Win64CallIat -TargetRva ([UInt32]0x30D8) -StackArguments @() # CreateMutexA
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $mutexFail
    Emit-StoreRaxFrame -SlotPosition $mutexHandleSlot
    Emit-LoadRcxFrame -SlotPosition $mutexHandleSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x30, 0x75, 0x00, 0x00)) # wait <= 30000 ms
    Emit-Win64CallIat -TargetRva ([UInt32]0x30D0) -StackArguments @() # WaitForSingleObject
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    $mutexAcquired = New-UniqueLabel -Prefix 'dev_tool_mutex_acquired'
    $mutexAbandoned = New-UniqueLabel -Prefix 'dev_tool_mutex_abandoned'
    $mutexReady = New-UniqueLabel -Prefix 'dev_tool_mutex_ready'
    Emit-JumpConditional -ConditionCode 0x84 -Label $mutexAcquired
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x80, 0x00, 0x00, 0x00)) # WAIT_ABANDONED = prior owner terminated
    Emit-JumpConditional -ConditionCode 0x84 -Label $mutexAbandoned
    Emit-Jump -Label $mutexFail # WAIT_TIMEOUT / WAIT_FAILED / unexpected status
    Mark-CodeLabel -Label $mutexAcquired
    Emit-StoreBits32Frame -SlotPosition $mutexAcquiredSlot -Value 1
    Emit-Jump -Label $mutexReady

    # An abandoned mutex proves that the previous transaction may have died
    # while AppContainer ACLs were installed. Do not reuse the stable package SID
    # or launch another child until a durable ACL recovery transaction exists.
    Mark-CodeLabel -Label $mutexAbandoned
    Emit-StoreBits32Frame -SlotPosition $mutexAcquiredSlot -Value 1
    Emit-Jump -Label $mutexReady # WAIT_ABANDONED grants ownership; recover before any new child

    Mark-CodeLabel -Label $mutexReady
    Emit-LoadEaxFrame -SlotPosition $rootLengthSlot
    Emit-Bytes -Bytes ([byte[]]@(0x05))
    Emit-I32 -Value $journalSuffixLength
    Emit-StoreEaxFrame -SlotPosition $journalPathLengthSlot
    Emit-DevBrokerRecoverAclJournal -JournalPathSlot $journalPathSlot -PathLengthSlot $journalPathLengthSlot -TempPathSlot $journalTempPathSlot -WorkspaceRootSlot $workspaceRootSlot -BuildPathSlot $buildPathSlot -BrokerDirectorySlot $brokerDirectorySlot -JournalHandleSlot $journalHandleSlot -JournalReadCountSlot $journalReadCountSlot -HeaderSlot $journalHeaderSlot -JournalBufferSlot $journalBufferSlot -RootLengthSlot $rootDescriptorLengthSlot -BuildLengthSlot $buildDescriptorLengthSlot -BrokerLengthSlot $brokerDescriptorLengthSlot -RootDescriptorSlot $rootDescriptorSlot -BuildDescriptorSlot $buildDescriptorSlot -BrokerDescriptorSlot $brokerDescriptorSlot -FailureLabel $aclRecoveryFail

    # Recovery has restored the pre-run descriptors, so descendant path checks
    # can now execute without being blocked by a crashed AppContainer's stale
    # temporary ACL. The recovery helper already failed closed if any opened
    # directory was missing, a reparse point, or could not be restored.
    Emit-DevBrokerPathCheck -FrameSlot $buildPathSlot -IsDirectory $true -FailureLabel $directoryFailBuild
    Emit-DevBrokerPathCheck -FrameSlot $brokerDirectorySlot -IsDirectory $true -FailureLabel $directoryFailBroker
    foreach ($directorySuffix in @('\Stage0', '\Tests', '\Tests\BaselineM6', '\Tests\DevAgentBroker')) {
        $directoryItem = Register-DataConstant -Value $directorySuffix
        $directoryLength = [System.Text.Encoding]::ASCII.GetByteCount($directorySuffix)
        Emit-DevBrokerBuildWorkspacePath -RootSlot $workspaceRootSlot -RootLengthSlot $rootLengthSlot -SuffixItem $directoryItem -SuffixLength $directoryLength -DestinationSlot $pathScratchSlot
        Emit-DevBrokerPathCheck -FrameSlot $pathScratchSlot -IsDirectory $true -FailureLabel $directoryFailFixed
    }
    $compilerSuffixItem = Register-DataConstant -Value '\Stage0\SharnouCompiler.ps1'
    $compilerSuffixLength = [System.Text.Encoding]::ASCII.GetByteCount('\Stage0\SharnouCompiler.ps1')
    Emit-DevBrokerBuildWorkspacePath -RootSlot $workspaceRootSlot -RootLengthSlot $rootLengthSlot -SuffixItem $compilerSuffixItem -SuffixLength $compilerSuffixLength -DestinationSlot $pathScratchSlot
    Emit-DevBrokerPathCheck -FrameSlot $pathScratchSlot -IsDirectory $false -FailureLabel $directoryFailCompiler

    # pathScratchSlot aliases journalPathSlot. The descendant checks above use
    # it as a temporary buffer, so reconstruct the durable journal destination
    # after those checks and before the next transaction writes its snapshot.
    Emit-DevBrokerBuildWorkspacePath -RootSlot $workspaceRootSlot -RootLengthSlot $rootLengthSlot -SuffixItem $journalSuffixItem -SuffixLength $journalSuffixLength -DestinationSlot $journalPathSlot

    Emit-LeaRaxFrame -SlotPosition $workspaceRootSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3220) -StackArguments @() # SetCurrentDirectoryA
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $directoryFailCwd

    # Verify the selected tool only after crash recovery has restored source-tree
    # DACLs. A killed prior broker may leave the AppContainer ACE in place until
    # this point; do not make manifest/script access a prerequisite for rollback.
    # Hash only the selected immutable script by absolute path; keep its opened file handle.
    $verifyLabels = @()
    for ($i = 0; $i -lt $fixedToolPaths.Count; $i++) { $verifyLabels += New-UniqueLabel -Prefix 'dev_tool_verify_hash' }
    Emit-LoadEaxFrame -SlotPosition $ToolSlot
    for ($i = 0; $i -lt $fixedToolPaths.Count; $i++) {
        Emit-Bytes -Bytes ([byte[]]@(0x3D))
        Emit-I32 -Value $fixedToolPaths[$i].Id
        Emit-JumpConditional -ConditionCode 0x84 -Label $verifyLabels[$i]
    }
    Emit-Jump -Label $unknownTool
    for ($i = 0; $i -lt $fixedToolPaths.Count; $i++) {
        Mark-CodeLabel -Label $verifyLabels[$i]
        Emit-DevBrokerBuildWorkspacePath -RootSlot $workspaceRootSlot -RootLengthSlot $rootLengthSlot -SuffixItem $fixedToolPaths[$i].SuffixItem -SuffixLength $fixedToolPaths[$i].SuffixLength -DestinationSlot $pathScratchSlot
        Emit-LoadEaxFrame -SlotPosition $rootLengthSlot
        Emit-Bytes -Bytes ([byte[]]@(0x05))
        Emit-I32 -Value $fixedToolPaths[$i].SuffixLength
        Emit-StoreEaxFrame -SlotPosition $modulePathLengthSlot
        Emit-DevBrokerVerifyScript -FrameSlot $pathScratchSlot -ExpectedSha256 $fixedToolPaths[$i].Sha256 -PersistentFileHandleSlot $hashFileHandleSlot -FailureLabel $hashFail
        Emit-Jump -Label $hashVerified
    }
    Mark-CodeLabel -Label $hashFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x91, 0xFF, 0xFF, 0xFF)) # -111: selected script hash failed
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup
    Mark-CodeLabel -Label $hashVerified

    # Build commandLineSlot = fixed prefix + the exact SHA-256-verified absolute script path + suffix.
    Emit-DataAddress -DataItem $commandPrefixItem
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC6)) # RSI = command prefix
    Emit-LeaRaxFrame -SlotPosition $commandLineSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC7)) # RDI = command buffer
    Emit-Bytes -Bytes ([byte[]]@(0xB9))
    Emit-I32 -Value $commandPrefixLength
    Emit-Bytes -Bytes ([byte[]]@(0xFC, 0xF3, 0xA4)) # CLD; copy prefix

    Emit-LeaRaxFrame -SlotPosition $pathScratchSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC6)) # RSI = verified absolute path
    Emit-LeaRaxFrame -SlotPosition $commandLineSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC7, 0x48, 0x81, 0xC7))
    Emit-I32 -Value $commandPrefixLength # RDI = command buffer + prefix length
    Emit-LoadEaxFrame -SlotPosition $modulePathLengthSlot
    Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC1, 0xFC, 0xF3, 0xA4)) # copy exact path bytes (no NUL)

    Emit-DataAddress -DataItem $commandSuffixItem
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC6)) # RSI = command suffix
    Emit-LeaRaxFrame -SlotPosition $commandLineSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC7, 0x48, 0x81, 0xC7))
    Emit-I32 -Value $commandPrefixLength
    Emit-LoadEaxFrame -SlotPosition $modulePathLengthSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x63, 0xC0, 0x48, 0x01, 0xC7)) # RDI += absolute path length
    Emit-Bytes -Bytes ([byte[]]@(0xB9))
    Emit-I32 -Value $commandSuffixLength
    Emit-Bytes -Bytes ([byte[]]@(0xFC, 0xF3, 0xA4, 0xC6, 0x07, 0x00)) # copy suffix + NUL


    # pathScratchSlot is also journalPathSlot. Hash-path construction borrowed it,
    # so rebuild the committed journal target before the next transaction starts.
    Emit-DevBrokerBuildWorkspacePath -RootSlot $workspaceRootSlot -RootLengthSlot $rootLengthSlot -SuffixItem $journalSuffixItem -SuffixLength $journalSuffixLength -DestinationSlot $journalPathSlot

    # One-time migration: remove any ACL grants left for the former shared package SID.
    # REVOKE_ACCESS only narrows DACL permissions; no access is expanded here. The
    # journal snapshot is then captured from the post-migration state, before grants
    # for the fresh per-execution SID are applied.
    Emit-DevBrokerRevokeLegacyAppContainerSid -SidSlot $legacyAppContainerSidSlot -FailureLabel $legacyAppContainerFail
    Emit-DevBrokerUpdateAcl -PathSlot $workspaceRootSlot -SidSlot $legacyAppContainerSidSlot -AccessMask ([UInt32]0) -AccessMode 4 -FailureLabel $aclFail
    Emit-DevBrokerUpdateAcl -PathSlot $buildPathSlot -SidSlot $legacyAppContainerSidSlot -AccessMask ([UInt32]0) -AccessMode 4 -SetLowIntegrityLabel $false -FailureLabel $aclFail
    Emit-DevBrokerUpdateAcl -PathSlot $brokerDirectorySlot -SidSlot $legacyAppContainerSidSlot -AccessMask ([UInt32]0) -AccessMode 4 -SetLowIntegrityLabel $false -FailureLabel $aclFail

    # A separate fresh identity is created for the actual child; the stable legacy
    # SID is never placed in SECURITY_CAPABILITIES or used for a process token.
    Emit-DevBrokerEnsureAppContainerSid -SidSlot $appContainerSidSlot -ProfileNameSlot $profileNameSlot -RandomSlot $profileRandomSlot -DerivedSidSlot $derivedProfileSidSlot -ProfileCreatedSlot $profileCreatedSlot -FailureLabel $appContainerFail

    Emit-DevBrokerWriteAclJournal -JournalPathSlot $journalPathSlot -TempPathSlot $journalTempPathSlot -WorkspaceRootSlot $workspaceRootSlot -BuildPathSlot $buildPathSlot -BrokerDirectorySlot $brokerDirectorySlot -JournalHandleSlot $journalHandleSlot -JournalWrittenSlot $journalWrittenSlot -HeaderSlot $journalHeaderSlot -RootDescriptorSlot $rootDescriptorSlot -BuildDescriptorSlot $buildDescriptorSlot -BrokerDescriptorSlot $brokerDescriptorSlot -RootLengthSlot $rootDescriptorLengthSlot -BuildLengthSlot $buildDescriptorLengthSlot -BrokerLengthSlot $brokerDescriptorLengthSlot -TransactionActiveSlot $transactionActiveSlot -FailureLabel $journalFail

    # Only now may the execution SID gain read access to source and write access to staging.
    Emit-DevBrokerUpdateAcl -PathSlot $workspaceRootSlot -SidSlot $appContainerSidSlot -AccessMask ([UInt32]0x001200A9) -AccessMode 2 -FailureLabel $aclFail
    Emit-DevBrokerUpdateAcl -PathSlot $buildPathSlot -SidSlot $appContainerSidSlot -AccessMask ([UInt32]0x001201FF) -AccessMode 2 -SetLowIntegrityLabel $true -FailureLabel $aclFail
    Emit-DevBrokerUpdateAcl -PathSlot $brokerDirectorySlot -SidSlot $appContainerSidSlot -AccessMask ([UInt32]0x001201FF) -AccessMode 2 -SetLowIntegrityLabel $true -FailureLabel $aclFail

    # Rebuild this path because outputPathSlot held the temporary ACL journal name.
    Emit-DevBrokerBuildWorkspacePath -RootSlot $workspaceRootSlot -RootLengthSlot $rootLengthSlot -SuffixItem $captureSuffixItem -SuffixLength $captureSuffixLength -DestinationSlot $outputPathSlot

    # Create a new exclusive capture file before launch. CREATE_NEW cannot reopen an old
    # reparse point or hard link; the held non-inheritable handle is reused for persistence.
    Emit-LeaRaxFrame -SlotPosition $outputPathSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3310) -StackArguments @() # DeleteFileA; stale files are removed only before CREATE_NEW
    Emit-LeaRaxFrame -SlotPosition $outputPathSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1, 0xBA, 0x80, 0x00, 0x00, 0x40, 0x45, 0x33, 0xC0, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x30A0) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 1 },  # CREATE_NEW
        @{ Kind = 'Immediate'; Value = 0x00200080 }, # OPEN_REPARSE_POINT | FILE_ATTRIBUTE_NORMAL
        @{ Kind = 'Immediate'; Value = 0 }
    ) # CreateFileA(captured-output.bin), share mode = 0
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xF8, 0xFF))
    Emit-JumpConditional -ConditionCode 0x84 -Label $outputFail
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $outputFail
    Emit-StoreRaxFrame -SlotPosition $outputFileHandleSlot
    for ($i = 0; $i -lt 7; $i++) { Emit-StoreZero64Frame -SlotPosition ($outputFileInfoSlot + ($i * 8)) }
    Emit-LoadRcxFrame -SlotPosition $outputFileHandleSlot
    Emit-LeaRaxFrame -SlotPosition $outputFileInfoSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3208) -StackArguments @() # GetFileInformationByHandle
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $outputFail
    Emit-LoadEaxFrame -SlotPosition $outputFileInfoSlot
    Emit-Bytes -Bytes ([byte[]]@(0xA9, 0x10, 0x04, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x85 -Label $outputFail # reject directory and reparse-point attributes
    Emit-LoadEaxFrame -SlotPosition ($outputFileInfoSlot + 40)
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x01, 0x00, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x85 -Label $outputFail # a fresh capture file must have exactly one link

    # Build a restricted primary token and a no-capability AppContainer SECURITY_CAPABILITIES.
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0xC7, 0xC1, 0xFF, 0xFF, 0xFF, 0xFF)) # GetCurrentProcess()
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x8B, 0x00, 0x00, 0x00)) # TOKEN_ASSIGN_PRIMARY|DUPLICATE|QUERY|ADJUST_DEFAULT
    Emit-LeaRaxFrame -SlotPosition $sourceTokenSlot
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0))
    Emit-Win64CallIat -TargetRva ([UInt32]0x32B0) -StackArguments @() # OpenProcessToken
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $tokenFail
    Emit-LoadRcxFrame -SlotPosition $sourceTokenSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x01, 0x00, 0x00, 0x00, 0x45, 0x33, 0xC0, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x32B8) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 0 }, # DeletePrivilegeCount
        @{ Kind = 'Immediate'; Value = 0 }, # PrivilegesToDelete
        @{ Kind = 'Immediate'; Value = 0 }, # RestrictedSidCount
        @{ Kind = 'Immediate'; Value = 0 }, # SIDsToRestrict
        @{ Kind = 'FrameAddress'; SlotPosition = $restrictedTokenSlot }
    ) # CreateRestrictedToken(DISABLE_MAX_PRIVILEGE)
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $tokenFail
    Emit-LoadRaxFrame -SlotPosition $restrictedTokenSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $tokenFail

    Emit-LoadRaxFrame -SlotPosition $appContainerSidSlot
    Emit-StoreRaxFrame -SlotPosition $securityCapabilitiesSlot
    Emit-StoreZero64Frame -SlotPosition ($securityCapabilitiesSlot + 8) # Capability SID_AND_ATTRIBUTES pointer = NULL
    Emit-StoreBits32Frame -SlotPosition ($securityCapabilitiesSlot + 16) -Value 0 # CapabilityCount
    Emit-StoreBits32Frame -SlotPosition ($securityCapabilitiesSlot + 20) -Value 0 # Reserved

    # Create inherited anonymous-pipe endpoints and a NUL standard-input handle.
    Emit-StoreBits32Frame -SlotPosition $pipeSecuritySlot -Value 24 # sizeof(SECURITY_ATTRIBUTES)
    Emit-StoreZero64Frame -SlotPosition ($pipeSecuritySlot + 8)
    Emit-StoreBits32Frame -SlotPosition ($pipeSecuritySlot + 16) -Value 1 # bInheritHandle
    Emit-LeaRaxFrame -SlotPosition $pipeReadSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-LeaRaxFrame -SlotPosition $pipeWriteSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-LeaRaxFrame -SlotPosition $pipeSecuritySlot
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3230) -StackArguments @() # CreatePipe
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $pipeFail
    Emit-LoadRcxFrame -SlotPosition $pipeReadSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x01, 0x00, 0x00, 0x00, 0x45, 0x33, 0xC0))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3238) -StackArguments @() # SetHandleInformation(read, HANDLE_FLAG_INHERIT, 0)
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $pipeFail

    $nulItem = Register-DataConstant -Value 'NUL'
    Emit-DataAddress -DataItem $nulItem
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1, 0xBA, 0x00, 0x00, 0x00, 0x80, 0x41, 0xB8, 0x03, 0x00, 0x00, 0x00))
    Emit-LeaR9Frame -SlotPosition $pipeSecuritySlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x30A0) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 3 }, # OPEN_EXISTING
        @{ Kind = 'Immediate'; Value = 0x80 }, # FILE_ATTRIBUTE_NORMAL
        @{ Kind = 'Immediate'; Value = 0 }
    ) # CreateFileA(NUL), inheritable
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xF8, 0xFF))
    Emit-JumpConditional -ConditionCode 0x84 -Label $pipeFail
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $pipeFail
    Emit-StoreRaxFrame -SlotPosition $nulHandleSlot

    # Allocate the hard-capped output buffer and a STARTUPINFOEX attribute list.
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xC9, 0xBA, 0x00, 0x00, 0x10, 0x00, 0x41, 0xB8, 0x00, 0x30, 0x00, 0x00, 0x41, 0xB9, 0x04, 0x00, 0x00, 0x00))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31D0) -StackArguments @() # VirtualAlloc(1MiB, MEM_COMMIT|RESERVE, PAGE_READWRITE)
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $outputFail
    Emit-StoreRaxFrame -SlotPosition $outputBufferSlot

    # Query the exact size required for two process attributes. The documented
    # first call uses a NULL list and must fail with ERROR_INSUFFICIENT_BUFFER (122).
    Emit-StoreZero64Frame -SlotPosition $attributeSizeSlot
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xC9, 0xBA, 0x02, 0x00, 0x00, 0x00, 0x45, 0x33, 0xC0))
    Emit-LeaR9Frame -SlotPosition $attributeSizeSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x3248) -StackArguments @() # InitializeProcThreadAttributeList(NULL,2,0,&size)
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $attributeFail # the sizing call must return FALSE
    Emit-Win64CallIat -TargetRva ([UInt32]0x3268) -StackArguments @() # GetLastError
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x7A, 0x00, 0x00, 0x00)) # ERROR_INSUFFICIENT_BUFFER
    Emit-JumpConditional -ConditionCode 0x85 -Label $attributeFail
    Emit-LoadEaxFrame -SlotPosition $attributeSizeSlot
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x01, 0x00, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x82 -Label $attributeFail # size must be nonzero
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x00, 0x10, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x87 -Label $attributeFail # hard allocation ceiling = 4096 bytes

    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xC9)) # lpAddress = NULL
    Emit-LoadEaxFrame -SlotPosition $attributeSizeSlot
    Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC2, 0x41, 0xB8, 0x00, 0x30, 0x00, 0x00, 0x41, 0xB9, 0x04, 0x00, 0x00, 0x00))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31D0) -StackArguments @() # VirtualAlloc(exact attribute-list size)
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $attributeFail
    Emit-StoreRaxFrame -SlotPosition $attributeListSlot
    Emit-LoadRcxFrame -SlotPosition $attributeListSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x02, 0x00, 0x00, 0x00, 0x45, 0x33, 0xC0))
    Emit-LeaR9Frame -SlotPosition $attributeSizeSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x3248) -StackArguments @() # InitializeProcThreadAttributeList(actual buffer)
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $attributeFail
    Emit-StoreBits32Frame -SlotPosition $attributeListReadySlot -Value 1

    # PROC_THREAD_ATTRIBUTE_SECURITY_CAPABILITIES: AppContainer SID and zero capabilities.
    Emit-LoadRaxFrame -SlotPosition $appContainerSidSlot
    Emit-StoreRaxFrame -SlotPosition $securityCapabilitiesSlot
    Emit-LoadRcxFrame -SlotPosition $attributeListSlot
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xD2, 0x41, 0xB8, 0x09, 0x00, 0x02, 0x00))
    Emit-LeaR9Frame -SlotPosition $securityCapabilitiesSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x3250) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 24 }, # sizeof(SECURITY_CAPABILITIES)
        @{ Kind = 'Immediate'; Value = 0 },
        @{ Kind = 'Immediate'; Value = 0 }
    ) # UpdateProcThreadAttribute(SECURITY_CAPABILITIES)
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $attributeFail

    # The inherited-handle allowlist contains exactly NUL stdin and the pipe writer.
    Emit-LoadRaxFrame -SlotPosition $nulHandleSlot
    Emit-StoreRaxFrame -SlotPosition $handleListSlot
    Emit-LoadRaxFrame -SlotPosition $pipeWriteSlot
    Emit-StoreRaxFrame -SlotPosition ($handleListSlot + 8)
    Emit-LoadRcxFrame -SlotPosition $attributeListSlot
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xD2, 0x41, 0xB8, 0x02, 0x00, 0x02, 0x00))
    Emit-LeaR9Frame -SlotPosition $handleListSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x3250) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 16 }, # sizeof(HANDLE[2])
        @{ Kind = 'Immediate'; Value = 0 },
        @{ Kind = 'Immediate'; Value = 0 }
    ) # UpdateProcThreadAttribute(HANDLE_LIST)
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $attributeFail

    # STARTUPINFOEXA: stdin=NUL, stdout=stderr=one pipe writer, exact attribute list.
    for ($i = 0; $i -lt 14; $i++) { Emit-StoreZero64Frame -SlotPosition ($startupSlot + ($i * 8)) }
    Emit-StoreBits32Frame -SlotPosition $startupSlot -Value 112 # sizeof(STARTUPINFOEXA)
    Emit-StoreBits32Frame -SlotPosition ($startupSlot + 60) -Value 0x100 # STARTF_USESTDHANDLES
    Emit-LoadRaxFrame -SlotPosition $nulHandleSlot
    Emit-StoreRaxFrame -SlotPosition ($startupSlot + 80)
    Emit-LoadRaxFrame -SlotPosition $pipeWriteSlot
    Emit-StoreRaxFrame -SlotPosition ($startupSlot + 88)
    Emit-LoadRaxFrame -SlotPosition $pipeWriteSlot
    Emit-StoreRaxFrame -SlotPosition ($startupSlot + 96)
    Emit-LoadRaxFrame -SlotPosition $attributeListSlot
    Emit-StoreRaxFrame -SlotPosition ($startupSlot + 104)

    # JOB_OBJECT_EXTENDED_LIMIT_INFORMATION: KILL_ON_JOB_CLOSE | ACTIVE_PROCESS | PROCESS_MEMORY | JOB_MEMORY (0x2308).
    for ($i = 0; $i -lt 18; $i++) { Emit-StoreZero64Frame -SlotPosition ($jobInfoSlot + ($i * 8)) }
    Emit-StoreBits32Frame -SlotPosition ($jobInfoSlot + 16) -Value 0x2308
    Emit-StoreBits32Frame -SlotPosition ($jobInfoSlot + 40) -Value 4 # ActiveProcessLimit
    Emit-StoreImm64Frame -SlotPosition ($jobInfoSlot + 112) -Value ([UInt64](256 * 1024 * 1024))
    Emit-StoreImm64Frame -SlotPosition ($jobInfoSlot + 120) -Value ([UInt64](512 * 1024 * 1024))

    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xC9, 0x33, 0xD2))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3190) -StackArguments @() # CreateJobObjectA
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $jobFail
    Emit-StoreRaxFrame -SlotPosition $jobHandleSlot
    Emit-LoadRcxFrame -SlotPosition $jobHandleSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x09, 0x00, 0x00, 0x00))
    Emit-LeaRaxFrame -SlotPosition $jobInfoSlot
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0, 0x41, 0xB9, 0x90, 0x00, 0x00, 0x00))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3198) -StackArguments @() # SetInformationJobObject
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $jobConfigFail

    # Create the restricted-token/AppContainer child suspended; only the explicit handle list is inherited.
    Emit-LoadRaxFrame -SlotPosition $restrictedTokenSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1)) # RCX = token
    Emit-LeaRaxFrame -SlotPosition $applicationSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2)) # RDX = absolute System32 powershell.exe
    Emit-LeaRaxFrame -SlotPosition $commandLineSlot
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0, 0x45, 0x33, 0xC9)) # R8 = command line; R9 = NULL process attrs
    Emit-Win64CallIat -TargetRva ([UInt32]0x32C0) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 0 }, # lpThreadAttributes
        @{ Kind = 'Immediate'; Value = 1 }, # bInheritHandles TRUE, constrained by HANDLE_LIST
        @{ Kind = 'Immediate'; Value = 0x00080004 }, # EXTENDED_STARTUPINFO_PRESENT | CREATE_SUSPENDED
        @{ Kind = 'Immediate'; Value = 0 }, # inherited environment remains a separate hardening gate
        @{ Kind = 'FrameAddress'; SlotPosition = $workspaceRootSlot },
        @{ Kind = 'FrameAddress'; SlotPosition = $startupSlot },
        @{ Kind = 'FrameAddress'; SlotPosition = $processSlot }
    ) # CreateProcessAsUserA
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $createFail

    # Parent closes its inheritable copies immediately; only the child owns the pipe writer after this point.
    foreach ($slot in @($pipeWriteSlot, $nulHandleSlot)) {
        Emit-LoadRcxFrame -SlotPosition $slot
        Emit-Win64CallIat -TargetRva ([UInt32]0x30B8) -StackArguments @() # CloseHandle
        Emit-StoreZero64Frame -SlotPosition $slot
    }

    # The process must join the Job Object while suspended.
    Emit-LoadRcxFrame -SlotPosition $jobHandleSlot
    Emit-LoadRaxFrame -SlotPosition $processSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31A0) -StackArguments @() # AssignProcessToJobObject
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $assignFail
    Emit-StoreBits32Frame -SlotPosition $childActiveSlot -Value 1

    # Verify the actual primary token before the first instruction can execute.
    Emit-LoadRaxFrame -SlotPosition $processSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1, 0xBA, 0x08, 0x00, 0x00, 0x00))
    Emit-LeaRaxFrame -SlotPosition $childTokenSlot
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0))
    Emit-Win64CallIat -TargetRva ([UInt32]0x32B0) -StackArguments @() # OpenProcessToken(TOKEN_QUERY)
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $tokenFail

    # TokenIsAppContainer must be TRUE.
    for ($i = 0; $i -lt 8; $i++) { Emit-StoreZero64Frame -SlotPosition ($tokenInformationSlot + ($i * 8)) }
    Emit-StoreZero64Frame -SlotPosition $tokenLengthSlot
    Emit-LoadRcxFrame -SlotPosition $childTokenSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x1D, 0x00, 0x00, 0x00)) # TokenIsAppContainer = 29
    Emit-LeaRaxFrame -SlotPosition $tokenInformationSlot
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0, 0x41, 0xB9, 0x04, 0x00, 0x00, 0x00))
    Emit-Win64CallIat -TargetRva ([UInt32]0x32D8) -StackArguments @(
        @{ Kind = 'FrameAddress'; SlotPosition = $tokenLengthSlot }
    ) # GetTokenInformation
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $tokenFail
    Emit-LoadEaxFrame -SlotPosition $tokenInformationSlot
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $tokenFail

    # The actual primary token must contain this execution's exact package SID,
    # not merely any AppContainer SID with zero capabilities. Probe the required
    # TOKEN_APPCONTAINER_INFORMATION size instead of assuming a fixed ABI length.
    for ($i = 0; $i -lt 8; $i++) { Emit-StoreZero64Frame -SlotPosition ($tokenInformationSlot + ($i * 8)) }
    Emit-StoreZero64Frame -SlotPosition $tokenLengthSlot
    Emit-LoadRcxFrame -SlotPosition $childTokenSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x1F, 0x00, 0x00, 0x00, 0x45, 0x33, 0xC0, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x32D8) -StackArguments @(
        @{ Kind = 'FrameAddress'; SlotPosition = $tokenLengthSlot }
    ) # GetTokenInformation(TokenAppContainerSid) sizing query
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $tokenFail # sizing call must fail for zero-length output
    Emit-Win64CallIat -TargetRva ([UInt32]0x3268) -StackArguments @() # GetLastError
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x7A, 0x00, 0x00, 0x00)) # ERROR_INSUFFICIENT_BUFFER
    Emit-JumpConditional -ConditionCode 0x85 -Label $tokenFail
    Emit-LoadEaxFrame -SlotPosition $tokenLengthSlot
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x08, 0x00, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x82 -Label $tokenFail # require at least a PSID pointer
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x40, 0x00, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x87 -Label $tokenFail # bounded stack buffer = 64 bytes

    Emit-LoadRcxFrame -SlotPosition $childTokenSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x1F, 0x00, 0x00, 0x00))
    Emit-LeaRaxFrame -SlotPosition $tokenInformationSlot
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0))
    Emit-LoadEaxFrame -SlotPosition $tokenLengthSlot
    Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x32D8) -StackArguments @(
        @{ Kind = 'FrameAddress'; SlotPosition = $tokenLengthSlot }
    ) # GetTokenInformation(TOKEN_APPCONTAINER_INFORMATION)
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $tokenFail
    Emit-LoadRaxFrame -SlotPosition $tokenInformationSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1)) # RCX = PSID pointer stored in TOKEN_APPCONTAINER_INFORMATION
    Emit-LoadRaxFrame -SlotPosition $appContainerSidSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2)) # RDX = newly created profile SID
    Emit-Win64CallIat -TargetRva ([UInt32]0x3350) -StackArguments @() # EqualSid
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $tokenFail

    # TokenHasRestrictions must be TRUE (the parent token's maximum privileges were disabled).
    for ($i = 0; $i -lt 8; $i++) { Emit-StoreZero64Frame -SlotPosition ($tokenInformationSlot + ($i * 8)) }
    Emit-StoreZero64Frame -SlotPosition $tokenLengthSlot
    Emit-LoadRcxFrame -SlotPosition $childTokenSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x15, 0x00, 0x00, 0x00)) # TokenHasRestrictions = 21
    Emit-LeaRaxFrame -SlotPosition $tokenInformationSlot
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0, 0x41, 0xB9, 0x04, 0x00, 0x00, 0x00))
    Emit-Win64CallIat -TargetRva ([UInt32]0x32D8) -StackArguments @(
        @{ Kind = 'FrameAddress'; SlotPosition = $tokenLengthSlot }
    )
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $tokenFail
    Emit-LoadEaxFrame -SlotPosition $tokenInformationSlot
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $tokenFail

    # TokenCapabilities must report zero capabilities; there is no network capability grant.
    for ($i = 0; $i -lt 8; $i++) { Emit-StoreZero64Frame -SlotPosition ($tokenInformationSlot + ($i * 8)) }
    Emit-StoreZero64Frame -SlotPosition $tokenLengthSlot
    Emit-LoadRcxFrame -SlotPosition $childTokenSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x1E, 0x00, 0x00, 0x00)) # TokenCapabilities = 30
    Emit-LeaRaxFrame -SlotPosition $tokenInformationSlot
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0, 0x41, 0xB9, 0x40, 0x00, 0x00, 0x00))
    Emit-Win64CallIat -TargetRva ([UInt32]0x32D8) -StackArguments @(
        @{ Kind = 'FrameAddress'; SlotPosition = $tokenLengthSlot }
    )
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $tokenFail
    Emit-LoadEaxFrame -SlotPosition $tokenInformationSlot # TOKEN_GROUPS.GroupCount
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $tokenFail

    Emit-LoadRaxFrame -SlotPosition ($processSlot + 8)
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31A8) -StackArguments @() # ResumeThread
    Emit-Bytes -Bytes ([byte[]]@(0x83, 0xF8, 0xFF))
    Emit-JumpConditional -ConditionCode 0x84 -Label $resumeFail

    # Poll completion independently of pipe traffic. Each wait is 10 ms, keeping timeout accounting bounded.
    Emit-LoadEaxFrame -SlotPosition $TimeoutSlot
    Emit-StoreEaxFrame -SlotPosition $remainingMsSlot
    Mark-CodeLabel -Label $captureLoop
    Emit-LoadRaxFrame -SlotPosition $processSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1, 0xBA, 0x0A, 0x00, 0x00, 0x00))
    Emit-Win64CallIat -TargetRva ([UInt32]0x30D0) -StackArguments @() # WaitForSingleObject(process,10)
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $processDone
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x02, 0x01, 0x00, 0x00)) # WAIT_TIMEOUT
    Emit-JumpConditional -ConditionCode 0x85 -Label $waitFail
    Emit-LoadEaxFrame -SlotPosition $remainingMsSlot
    Emit-Bytes -Bytes ([byte[]]@(0x83, 0xE8, 0x0A))
    Emit-StoreEaxFrame -SlotPosition $remainingMsSlot
    Emit-Bytes -Bytes ([byte[]]@(0x83, 0xF8, 0x00))
    Emit-JumpConditional -ConditionCode 0x8E -Label $timeoutFail

    Emit-LoadEaxFrame -SlotPosition $pipeClosedSlot
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $capturePipeClosed
    Emit-LoadRcxFrame -SlotPosition $pipeReadSlot
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xD2, 0x45, 0x33, 0xC0, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3240) -StackArguments @(
        @{ Kind = 'FrameAddress'; SlotPosition = $availableSlot },
        @{ Kind = 'Immediate'; Value = 0 }
    ) # PeekNamedPipe
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $capturePipeEof
    Emit-LoadEaxFrame -SlotPosition $availableSlot
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $captureLoop

    # Read only the remaining capacity. If outputCount is already 1 MiB and
    # another byte is available, the following read attempt takes the overflow path.
    Emit-LoadEaxFrame -SlotPosition $outputCountSlot
    Emit-Bytes -Bytes ([byte[]]@(0x3D))
    Emit-I32 -Value 0x100000
    Emit-JumpConditional -ConditionCode 0x83 -Label $outputOverflow # count >= cap and available > 0
    $mainCapReadReady = New-UniqueLabel -Prefix 'dev_output_main_cap_read_ready'
    Emit-Bytes -Bytes ([byte[]]@(0xB9))
    Emit-I32 -Value 0x100000 # ECX = hard cap
    Emit-Bytes -Bytes ([byte[]]@(0x2B, 0x8D))
    Emit-I32 -Value (Get-FrameDisp -SlotPosition $outputCountSlot) # ECX -= captured bytes
    Emit-LoadEaxFrame -SlotPosition $availableSlot
    Emit-Bytes -Bytes ([byte[]]@(0x3B, 0xC1)) # compare available bytes to remaining capacity
    Emit-JumpConditional -ConditionCode 0x86 -Label $mainCapReadReady # available <= remaining
    Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC8)) # EAX = ECX (read only remaining capacity)
    Emit-StoreEaxFrame -SlotPosition $availableSlot
    Mark-CodeLabel -Label $mainCapReadReady

    Emit-LoadRcxFrame -SlotPosition $pipeReadSlot
    Emit-LoadRaxFrame -SlotPosition $outputBufferSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-LoadEaxFrame -SlotPosition $outputCountSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x63, 0xC0, 0x48, 0x01, 0xC2))
    Emit-LoadEaxFrame -SlotPosition $availableSlot
    Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC0))
    Emit-LeaRaxFrame -SlotPosition $readCountSlot
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x30B0) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 0 }
    ) # ReadFile
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $waitFail
    Emit-LoadEaxFrame -SlotPosition $readCountSlot
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $waitFail
    Emit-LoadEaxFrame -SlotPosition $outputCountSlot
    Emit-Bytes -Bytes ([byte[]]@(0x03, 0x85))
    Emit-I32 -Value (Get-FrameDisp -SlotPosition $readCountSlot)
    Emit-StoreEaxFrame -SlotPosition $outputCountSlot
    Emit-Jump -Label $captureLoop

    Mark-CodeLabel -Label $capturePipeClosed
    Emit-Jump -Label $captureLoop

    Mark-CodeLabel -Label $capturePipeEof
    Emit-Win64CallIat -TargetRva ([UInt32]0x3268) -StackArguments @() # GetLastError
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x6D, 0x00, 0x00, 0x00)) # ERROR_BROKEN_PIPE = 109
    Emit-JumpConditional -ConditionCode 0x85 -Label $waitFail
    Emit-StoreBits32Frame -SlotPosition $pipeClosedSlot -Value 1
    Emit-Jump -Label $captureLoop

    Mark-CodeLabel -Label $processDone
    # Terminate any descendants and wait on the Job Object itself until every process has exited.
    Emit-LoadRcxFrame -SlotPosition $jobHandleSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x02, 0x00, 0xAD, 0xDE))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31B0) -StackArguments @() # TerminateJobObject
    Emit-LoadRcxFrame -SlotPosition $jobHandleSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0xFF, 0xFF, 0xFF, 0xFF))
    Emit-Win64CallIat -TargetRva ([UInt32]0x30D0) -StackArguments @() # WaitForSingleObject(job,INFINITE)
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $waitFail
    Emit-StoreBits32Frame -SlotPosition $childActiveSlot -Value 0
    Emit-Jump -Label $finalDrain

    # The Job Object is empty before the final pipe drain begins.
    Mark-CodeLabel -Label $finalDrain
    Emit-LoadEaxFrame -SlotPosition $pipeClosedSlot
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $captureDone
    Emit-LoadRcxFrame -SlotPosition $pipeReadSlot
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xD2, 0x45, 0x33, 0xC0, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3240) -StackArguments @(
        @{ Kind = 'FrameAddress'; SlotPosition = $availableSlot },
        @{ Kind = 'Immediate'; Value = 0 }
    ) # PeekNamedPipe
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $finalPipeEof
    Emit-LoadEaxFrame -SlotPosition $availableSlot
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $captureDone

    # Final drain uses the same exact-cap rule after the Job Object is empty.
    Emit-LoadEaxFrame -SlotPosition $outputCountSlot
    Emit-Bytes -Bytes ([byte[]]@(0x3D))
    Emit-I32 -Value 0x100000
    Emit-JumpConditional -ConditionCode 0x83 -Label $outputOverflow
    $finalCapReadReady = New-UniqueLabel -Prefix 'dev_output_final_cap_read_ready'
    Emit-Bytes -Bytes ([byte[]]@(0xB9))
    Emit-I32 -Value 0x100000 # ECX = hard cap
    Emit-Bytes -Bytes ([byte[]]@(0x2B, 0x8D))
    Emit-I32 -Value (Get-FrameDisp -SlotPosition $outputCountSlot) # ECX -= captured bytes
    Emit-LoadEaxFrame -SlotPosition $availableSlot
    Emit-Bytes -Bytes ([byte[]]@(0x3B, 0xC1))
    Emit-JumpConditional -ConditionCode 0x86 -Label $finalCapReadReady
    Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC8))
    Emit-StoreEaxFrame -SlotPosition $availableSlot
    Mark-CodeLabel -Label $finalCapReadReady

    Emit-LoadRcxFrame -SlotPosition $pipeReadSlot
    Emit-LoadRaxFrame -SlotPosition $outputBufferSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-LoadEaxFrame -SlotPosition $outputCountSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x63, 0xC0, 0x48, 0x01, 0xC2))
    Emit-LoadEaxFrame -SlotPosition $availableSlot
    Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC0))
    Emit-LeaRaxFrame -SlotPosition $readCountSlot
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x30B0) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 0 }
    ) # ReadFile
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $outputFail
    Emit-LoadEaxFrame -SlotPosition $readCountSlot
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $outputFail
    Emit-LoadEaxFrame -SlotPosition $outputCountSlot
    Emit-Bytes -Bytes ([byte[]]@(0x03, 0x85))
    Emit-I32 -Value (Get-FrameDisp -SlotPosition $readCountSlot)
    Emit-StoreEaxFrame -SlotPosition $outputCountSlot
    Emit-Jump -Label $finalDrain

    Mark-CodeLabel -Label $finalPipeEof
    Emit-Win64CallIat -TargetRva ([UInt32]0x3268) -StackArguments @() # GetLastError
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x6D, 0x00, 0x00, 0x00)) # ERROR_BROKEN_PIPE = 109
    Emit-JumpConditional -ConditionCode 0x85 -Label $outputFail
    Emit-Jump -Label $captureDone

    Mark-CodeLabel -Label $captureDone
    Emit-LoadRcxFrame -SlotPosition $processSlot
    Emit-LeaRaxFrame -SlotPosition $exitCodeSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31B8) -StackArguments @() # GetExitCodeProcess
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $waitFail
    Emit-LoadEaxFrame -SlotPosition $exitCodeSlot
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $outputOverflow
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x8E, 0xFF, 0xFF, 0xFF)) # -114: output byte ceiling exceeded
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $timeoutFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x92, 0xFF, 0xFF, 0xFF)) # -110: timeout
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $waitFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x93, 0xFF, 0xFF, 0xFF)) # -109: wait/pipe/exit-code failure
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $assignFail
    Emit-LoadRcxFrame -SlotPosition $processSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x02, 0x00, 0xAD, 0xDE))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31C0) -StackArguments @() # TerminateProcess; child was never assigned to the Job
    Emit-LoadRcxFrame -SlotPosition $processSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0xFF, 0xFF, 0xFF, 0xFF))
    Emit-Win64CallIat -TargetRva ([UInt32]0x30D0) -StackArguments @() # wait for suspended process termination
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x95, 0xFF, 0xFF, 0xFF)) # -107: Job Object assignment failed
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $resumeFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x94, 0xFF, 0xFF, 0xFF)) # -108: ResumeThread failed
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $createFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x96, 0xFF, 0xFF, 0xFF)) # -106: CreateProcessAsUserA failed
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $jobConfigFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x97, 0xFF, 0xFF, 0xFF)) # -105: Job Object configuration failed
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $jobFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x98, 0xFF, 0xFF, 0xFF)) # -104: CreateJobObjectA failed
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $pipeFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x8C, 0xFF, 0xFF, 0xFF)) # -116: pipe/NUL setup failed
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $attributeFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x8C, 0xFF, 0xFF, 0xFF)) # -116: startup attribute setup failed
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $outputFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x8D, 0xFF, 0xFF, 0xFF)) # -115: output capture file/buffer failed
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $tokenFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x90, 0xFF, 0xFF, 0xFF)) # -112: restricted token verification failed
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $aclFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x8F, 0xFF, 0xFF, 0xFF)) # -113: workspace ACL update failed
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $aclRecoveryFail
    Emit-LoadEaxFrame -SlotPosition ($scratch + 0xD90)
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    $genericRecoveryFailure = New-UniqueLabel -Prefix 'dev_tool_acl_recovery_generic_failure'
    Emit-JumpConditional -ConditionCode 0x84 -Label $genericRecoveryFailure
    Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC2, 0xB8, 0x70, 0xFE, 0xFF, 0xFF, 0x29, 0xD0)) # -400 - stage; diagnostic-only recovery failure
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup
    Mark-CodeLabel -Label $genericRecoveryFailure
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x89, 0xFF, 0xFF, 0xFF)) # -119: journal validation failure before descriptor restore
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $journalFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x88, 0xFF, 0xFF, 0xFF)) # -120: durable ACL journal could not be committed
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $appContainerFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x77, 0xFF, 0xFF, 0xFF)) # -137: per-execution profile creation/SID derivation failed
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $legacyAppContainerFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x78, 0xFF, 0xFF, 0xFF)) # -136: legacy shared-profile ACL migration SID resolution failed
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $mutexFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x8B, 0xFF, 0xFF, 0xFF)) # -117: ACL/output serialization failed
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $pathFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x9A, 0xFF, 0xFF, 0xFF)) # -102: System32 PowerShell resolution failed
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $directoryFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x99, 0xFF, 0xFF, 0xFF)) # -103: legacy/default workspace path failure
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    # Diagnostic-only statuses: -121 image, -122 root, -123 CWD,
    # -124 Build, -125 broker directory, -126 fixed test dirs, -127 compiler script.
    foreach ($failure in @(
        @{ Label = $directoryFailImage; Code = -121 },
        @{ Label = $directoryFailRoot; Code = -122 },
        @{ Label = $directoryFailCwd; Code = -123 },
        @{ Label = $directoryFailBuild; Code = -124 },
        @{ Label = $directoryFailBroker; Code = -125 },
        @{ Label = $directoryFailFixed; Code = -126 },
        @{ Label = $directoryFailCompiler; Code = -127 }
    )) {
        Mark-CodeLabel -Label $failure.Label
        $failureValue = [Int32]$failure.Code
        $failureBytes = [BitConverter]::GetBytes($failureValue)
        Emit-Bytes -Bytes ([byte[]]@(0xB8) + $failureBytes)
        Emit-StoreEaxFrame -SlotPosition $resultSlot
        Emit-Jump -Label $cleanup
    }
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $cleanup
    # On every post-create failure, stop the complete job and confirm it is empty before returning.
    Emit-LoadEaxFrame -SlotPosition $childActiveSlot
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    $skipCleanupKill = New-UniqueLabel -Prefix 'dev_tool_skip_cleanup_kill'
    Emit-JumpConditional -ConditionCode 0x84 -Label $skipCleanupKill
    Emit-LoadRcxFrame -SlotPosition $jobHandleSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x05, 0x00, 0xAD, 0xDE))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31B0) -StackArguments @() # TerminateJobObject
    Emit-LoadRcxFrame -SlotPosition $jobHandleSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0xFF, 0xFF, 0xFF, 0xFF))
    Emit-Win64CallIat -TargetRva ([UInt32]0x30D0) -StackArguments @() # WaitForSingleObject(job,INFINITE)
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    $cleanupWaitOk = New-UniqueLabel -Prefix 'dev_tool_cleanup_wait_ok'
    Emit-JumpConditional -ConditionCode 0x84 -Label $cleanupWaitOk
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x93, 0xFF, 0xFF, 0xFF))
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $skipCleanupKill
    Mark-CodeLabel -Label $cleanupWaitOk
    Emit-StoreBits32Frame -SlotPosition $childActiveSlot -Value 0
    Mark-CodeLabel -Label $skipCleanupKill

    # Persist at most the captured 1 MiB through the same exclusive, non-inherited file handle.
    Emit-LoadRaxFrame -SlotPosition $outputFileHandleSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    $skipPersist = New-UniqueLabel -Prefix 'dev_tool_skip_output_persist'
    Emit-JumpConditional -ConditionCode 0x84 -Label $skipPersist
    Emit-LoadRaxFrame -SlotPosition $outputBufferSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $skipPersist
    Emit-LoadRcxFrame -SlotPosition $outputFileHandleSlot
    Emit-LoadRaxFrame -SlotPosition $outputBufferSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-LoadEaxFrame -SlotPosition $outputCountSlot
    Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC0))
    Emit-LeaRaxFrame -SlotPosition $outputWrittenSlot
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3078) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 0 }
    ) # WriteFile
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    $outputPersistOk = New-UniqueLabel -Prefix 'dev_tool_output_persist_ok'
    Emit-JumpConditional -ConditionCode 0x85 -Label $outputPersistOk
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x8D, 0xFF, 0xFF, 0xFF)) # -115
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $skipPersist
    Mark-CodeLabel -Label $outputPersistOk
    Emit-LoadEaxFrame -SlotPosition $outputWrittenSlot
    Emit-Bytes -Bytes ([byte[]]@(0x3B, 0x85))
    Emit-I32 -Value (Get-FrameDisp -SlotPosition $outputCountSlot)
    $outputLengthOk = New-UniqueLabel -Prefix 'dev_tool_output_length_ok'
    Emit-JumpConditional -ConditionCode 0x84 -Label $outputLengthOk
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x8D, 0xFF, 0xFF, 0xFF)) # -115: short output write
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Mark-CodeLabel -Label $outputLengthOk
    Mark-CodeLabel -Label $skipPersist

    # Close every acquired handle and release the serialization mutex last.
    foreach ($slot in @($pipeReadSlot, $pipeWriteSlot, $nulHandleSlot, $outputFileHandleSlot)) {
        $skipClose = New-UniqueLabel -Prefix 'dev_tool_skip_close_handle'
        Emit-LoadRcxFrame -SlotPosition $slot
        Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
        Emit-JumpConditional -ConditionCode 0x84 -Label $skipClose
        Emit-Win64CallIat -TargetRva ([UInt32]0x30B8) -StackArguments @() # CloseHandle
        Mark-CodeLabel -Label $skipClose
    }
    foreach ($slot in @(($processSlot + 8), $processSlot)) {
        $skipCloseProcess = New-UniqueLabel -Prefix 'dev_tool_skip_close_process'
        Emit-LoadRcxFrame -SlotPosition $slot
        Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
        Emit-JumpConditional -ConditionCode 0x84 -Label $skipCloseProcess
        Emit-Win64CallIat -TargetRva ([UInt32]0x30B8) -StackArguments @() # CloseHandle
        Mark-CodeLabel -Label $skipCloseProcess
    }
    foreach ($slot in @($jobHandleSlot, $hashFileHandleSlot, $sourceTokenSlot, $restrictedTokenSlot, $childTokenSlot)) {
        $skipCloseOther = New-UniqueLabel -Prefix 'dev_tool_skip_close_other'
        Emit-LoadRcxFrame -SlotPosition $slot
        Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
        Emit-JumpConditional -ConditionCode 0x84 -Label $skipCloseOther
        Emit-Win64CallIat -TargetRva ([UInt32]0x30B8) -StackArguments @() # CloseHandle
        Mark-CodeLabel -Label $skipCloseOther
    }

    Emit-LoadEaxFrame -SlotPosition $attributeListReadySlot
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    $skipDeleteAttributes = New-UniqueLabel -Prefix 'dev_tool_skip_delete_attributes'
    Emit-JumpConditional -ConditionCode 0x84 -Label $skipDeleteAttributes
    Emit-LoadRcxFrame -SlotPosition $attributeListSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x3258) -StackArguments @() # DeleteProcThreadAttributeList
    Mark-CodeLabel -Label $skipDeleteAttributes

    foreach ($slot in @($attributeListSlot, $outputBufferSlot)) {
        $skipFreeMemory = New-UniqueLabel -Prefix 'dev_tool_skip_free_memory'
        Emit-LoadRcxFrame -SlotPosition $slot
        Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
        Emit-JumpConditional -ConditionCode 0x84 -Label $skipFreeMemory
        Emit-Bytes -Bytes ([byte[]]@(0x33, 0xD2, 0x41, 0xB8, 0x00, 0x80, 0x00, 0x00))
        Emit-Win64CallIat -TargetRva ([UInt32]0x31D8) -StackArguments @() # VirtualFree(MEM_RELEASE)
        Mark-CodeLabel -Label $skipFreeMemory
    }

    # Roll back only after the Job Object is known empty. If the wait failed,
    # retain the committed journal; closing the job handle requests kill-on-close,
    # and the next invocation performs authoritative recovery before any child launch.
    $skipAclRollback = New-UniqueLabel -Prefix 'dev_tool_skip_acl_rollback'
    Emit-LoadEaxFrame -SlotPosition $childActiveSlot
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $skipAclRollback
    Emit-LoadEaxFrame -SlotPosition $transactionActiveSlot
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $skipAclRollback

    Emit-DevBrokerRestoreSecurityDescriptor -PathSlot $workspaceRootSlot -DescriptorSlot $rootDescriptorSlot -FailureLabel $aclRollbackRootFail
    Emit-DevBrokerRestoreSecurityDescriptor -PathSlot $buildPathSlot -DescriptorSlot $buildDescriptorSlot -RestoreLabel $true -FailureLabel $aclRollbackBuildFail
    Emit-DevBrokerRestoreSecurityDescriptor -PathSlot $brokerDirectorySlot -DescriptorSlot $brokerDescriptorSlot -RestoreLabel $true -FailureLabel $aclRollbackBrokerFail

    Emit-LeaRaxFrame -SlotPosition $journalPathSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3310) -StackArguments @() # delete active journal only after all three descriptors are restored
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $aclRollbackJournalFail
    Emit-StoreBits32Frame -SlotPosition $transactionActiveSlot -Value 0
    Emit-Jump -Label $skipAclRollback

    Mark-CodeLabel -Label $aclRollbackRootFail
    Emit-LoadEaxFrame -SlotPosition ($scratch + 0xE80)
    Emit-Bytes -Bytes ([byte[]]@(0x83, 0xF8, 0x06))
    $rootSetSecurityFailed = New-UniqueLabel -Prefix 'dev_tool_root_set_security_failed'
    $rootRestoreStatusReady = New-UniqueLabel -Prefix 'dev_tool_root_restore_status_ready'
    Emit-JumpConditional -ConditionCode 0x84 -Label $rootSetSecurityFailed
    Emit-LoadEaxFrame -SlotPosition ($scratch + 0xE80)
    Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC2, 0xB8, 0x38, 0xFF, 0xFF, 0xFF, 0x29, 0xD0)) # -200 - pre-SetSecurityInfo stage
    Emit-Jump -Label $rootRestoreStatusReady
    Mark-CodeLabel -Label $rootSetSecurityFailed
    Emit-LoadEaxFrame -SlotPosition ($scratch + 0xE84)
    Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC2, 0xB8, 0x48, 0xF4, 0xFF, 0xFF, 0x29, 0xD0)) # -3000 - Win32 SetSecurityInfo error
    Mark-CodeLabel -Label $rootRestoreStatusReady
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $skipAclRollback

    Mark-CodeLabel -Label $aclRollbackBuildFail
    Emit-LoadEaxFrame -SlotPosition ($scratch + 0xE80)
    Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC2, 0xB8, 0x24, 0xFF, 0xFF, 0xFF, 0x29, 0xD0)) # -220 - restore stage
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $skipAclRollback

    Mark-CodeLabel -Label $aclRollbackBrokerFail
    Emit-LoadEaxFrame -SlotPosition ($scratch + 0xE80)
    Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC2, 0xB8, 0x10, 0xFF, 0xFF, 0xFF, 0x29, 0xD0)) # -240 - restore stage
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $skipAclRollback

    Mark-CodeLabel -Label $aclRollbackJournalFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x7C, 0xFF, 0xFF, 0xFF)) # -132: ACL journal could not be retired after restore
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $skipAclRollback

    Mark-CodeLabel -Label $aclRollbackFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x80, 0xFF, 0xFF, 0xFF)) # -128: generic ACL rollback failure
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Mark-CodeLabel -Label $skipAclRollback

    # Delete the unique profile only after the Job Object is empty and all committed
    # ACL changes have been restored and the journal retired. A crash leaves an
    # orphaned profile until the separate authenticated service recovery path exists.
    Emit-DevBrokerDeleteOwnedAppContainerProfile -ProfileNameSlot $profileNameSlot -ProfileCreatedSlot $profileCreatedSlot -ChildActiveSlot $childActiveSlot -TransactionActiveSlot $transactionActiveSlot -ResultSlot $resultSlot

    # GetSecurityInfo descriptors are LocalFree allocations; recovery-buffer
    # interior pointers were cleared by RecoverAclJournal and must not be freed here.
    foreach ($slot in @($rootDescriptorSlot, $buildDescriptorSlot, $brokerDescriptorSlot)) {
        $skipFreeDescriptor = New-UniqueLabel -Prefix 'dev_tool_skip_free_acl_descriptor'
        Emit-LoadRcxFrame -SlotPosition $slot
        Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
        Emit-JumpConditional -ConditionCode 0x84 -Label $skipFreeDescriptor
        Emit-Win64CallIat -TargetRva ([UInt32]0x3260) -StackArguments @() # LocalFree
        Emit-StoreZero64Frame -SlotPosition $slot
        Mark-CodeLabel -Label $skipFreeDescriptor
    }

    Emit-LoadRcxFrame -SlotPosition $appContainerSidSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
    $skipFreeSid = New-UniqueLabel -Prefix 'dev_tool_skip_free_sid'
    Emit-JumpConditional -ConditionCode 0x84 -Label $skipFreeSid
    Emit-Win64CallIat -TargetRva ([UInt32]0x32A8) -StackArguments @() # FreeSid
    Mark-CodeLabel -Label $skipFreeSid

    Emit-LoadRcxFrame -SlotPosition $legacyAppContainerSidSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
    $skipFreeLegacySid = New-UniqueLabel -Prefix 'dev_tool_skip_free_legacy_sid'
    Emit-JumpConditional -ConditionCode 0x84 -Label $skipFreeLegacySid
    Emit-Win64CallIat -TargetRva ([UInt32]0x32A8) -StackArguments @() # FreeSid
    Emit-StoreZero64Frame -SlotPosition $legacyAppContainerSidSlot
    Mark-CodeLabel -Label $skipFreeLegacySid

    Emit-LoadEaxFrame -SlotPosition $mutexAcquiredSlot
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    $skipReleaseMutex = New-UniqueLabel -Prefix 'dev_tool_skip_release_mutex'
    Emit-JumpConditional -ConditionCode 0x84 -Label $skipReleaseMutex
    Emit-LoadRcxFrame -SlotPosition $mutexHandleSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x30E0) -StackArguments @() # ReleaseMutex
    Mark-CodeLabel -Label $skipReleaseMutex
    $skipCloseMutex = New-UniqueLabel -Prefix 'dev_tool_skip_close_mutex'
    Emit-LoadRcxFrame -SlotPosition $mutexHandleSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
    Emit-JumpConditional -ConditionCode 0x84 -Label $skipCloseMutex
    Emit-Win64CallIat -TargetRva ([UInt32]0x30B8) -StackArguments @()
    Mark-CodeLabel -Label $skipCloseMutex

    Emit-LoadRdiFrame -SlotPosition $saveRdiSlot
    Emit-LoadRsiFrame -SlotPosition $saveRsiSlot
    Emit-LoadEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $done
    Mark-CodeLabel -Label $done
}
function Emit-BuiltinCall {
    param([object] $Node)
    $baseDepth = [int]$script:TempDepth
    $argSlots = [System.Collections.Generic.List[int]]::new()
    switch ($Node.Builtin) {
        'Win64CallbackProbe' {
            $serviceMainPointer = Register-CodeCallbackPointer -Key 'CALLBACK:SERVICE_MAIN_FUNCTIONW' -Label '__r51_service_main_abi_probe' -Signature 'SERVICE_MAIN_FUNCTIONW'
            $handlerExPointer = Register-CodeCallbackPointer -Key 'CALLBACK:HANDLER_FUNCTION_EX' -Label '__r51_handler_ex_abi_probe' -Signature 'HANDLER_FUNCTION_EX'
            $failLabel = New-UniqueLabel -Prefix 'win64_callback_probe_fail'
            $doneLabel = New-UniqueLabel -Prefix 'win64_callback_probe_done'

            # SERVICE_MAIN_FUNCTIONW is VOID: RCX=argc (DWORD), RDX=argv-vector pointer (LPWSTR*).
            # Pass a writable one-entry pointer vector so the void callback can report its test result
            # through the documented LPWSTR* argument rather than relying on an undefined return value.
            Emit-StoreZero64Frame -SlotPosition $script:ActiveContext.ScratchPosition
            Emit-Bytes -Bytes ([byte[]]@(0xB9, 0xDF, 0x9B, 0x57, 0x13))
            Emit-LeaRaxFrame -SlotPosition $script:ActiveContext.ScratchPosition
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2, 0x48, 0x83, 0xEC, 0x20))
            Emit-CallDataPointer -DataItem $serviceMainPointer
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20))
            Emit-LoadRaxFrame -SlotPosition $script:ActiveContext.ScratchPosition
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0xB9))
            $script:Code.AddRange([BitConverter]::GetBytes([UInt64]::Parse('0000000051A7C0DE', [System.Globalization.NumberStyles]::HexNumber)))
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0x39, 0xC8))
            Emit-JumpConditional -ConditionCode 0x85 -Label $failLabel

            # HandlerEx: four ABI registers, including both full-width pointer arguments.
            Emit-Bytes -Bytes ([byte[]]@(0xB9, 0x78, 0x56, 0x34, 0x12, 0xBA, 0x21, 0x43, 0x65, 0x87))
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0xB8))
            $script:Code.AddRange([BitConverter]::GetBytes([UInt64]::Parse('1122334455667788', [System.Globalization.NumberStyles]::HexNumber)))
            Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0, 0x48, 0xB8))
            $script:Code.AddRange([BitConverter]::GetBytes([UInt64]::Parse('8877665544332211', [System.Globalization.NumberStyles]::HexNumber)))
            Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC1, 0x48, 0x83, 0xEC, 0x20))
            Emit-CallDataPointer -DataItem $handlerExPointer
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20, 0x3D, 0xDE, 0xC0, 0xA7, 0x51))
            Emit-JumpConditional -ConditionCode 0x85 -Label $failLabel
            Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x01, 0x00, 0x00, 0x00))
            Emit-Jump -Label $doneLabel
            Mark-CodeLabel -Label $failLabel
            Emit-Jump -Label '__runtime_fail'
            Mark-CodeLabel -Label $doneLabel
            $script:TempDepth = $baseDepth
            return
        }
        'AbiNonvolatileProbe' {
            Emit-NonvolatileRegisterProbe -Node $Node -BaseDepth $baseDepth
            $script:TempDepth = $baseDepth
            return
        }
        'StringLength' {
            Emit-StringExpression -Node $Node.Arguments[0]
            Emit-Bytes -Bytes ([byte[]]@(0x89, 0xD0)) # EAX = EDX (UTF-8/ASCII byte length)
            return
        }
        'Log' {
            Emit-PrintString -Node $Node.Arguments[0]
            Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x01, 0x00, 0x00, 0x00))
            return
        }
        'StringEqual' {
            Emit-BuiltinArguments -Node $Node -BaseDepth $baseDepth
            $leftSlot = Get-TempSlotPosition -Depth $baseDepth
            $rightSlot = Get-TempSlotPosition -Depth ($baseDepth + 1)
            $saveRsiSlot = Get-TempSlotPosition -Depth ($baseDepth + 2)
            $saveRdiSlot = Get-TempSlotPosition -Depth ($baseDepth + 3)
            $notEqual = New-UniqueLabel -Prefix 'string_equal_false'
            $emptyEqual = New-UniqueLabel -Prefix 'string_equal_empty'
            $done = New-UniqueLabel -Prefix 'string_equal_done'
            Emit-LoadEaxFrame -SlotPosition ($leftSlot + 8)
            Emit-Bytes -Bytes ([byte[]]@(0x8B, 0x8D)); Emit-I32 -Value (Get-FrameDisp -SlotPosition ($rightSlot + 8))
            Emit-Bytes -Bytes ([byte[]]@(0x39, 0xC8)); Emit-JumpConditional -ConditionCode 0x85 -Label $notEqual
            Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $emptyEqual
            Emit-StoreRsiFrame -SlotPosition $saveRsiSlot; Emit-StoreRdiFrame -SlotPosition $saveRdiSlot
            Emit-LoadRsiFrame -SlotPosition $leftSlot; Emit-LoadRdiFrame -SlotPosition $rightSlot
            Emit-Bytes -Bytes ([byte[]]@(0x8B, 0x8D)); Emit-I32 -Value (Get-FrameDisp -SlotPosition ($leftSlot + 8))
            Emit-Bytes -Bytes ([byte[]]@(0xF3, 0xA6, 0x0F, 0x94, 0xC0, 0x0F, 0xB6, 0xC0)) # REPE CMPSB; SETE AL; MOVZX EAX,AL
            Emit-LoadRdiFrame -SlotPosition $saveRdiSlot; Emit-LoadRsiFrame -SlotPosition $saveRsiSlot
            Emit-Jump -Label $done
            Mark-CodeLabel -Label $emptyEqual; Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x01, 0x00, 0x00, 0x00)); Emit-Jump -Label $done
            Mark-CodeLabel -Label $notEqual; Emit-Bytes -Bytes ([byte[]]@(0x31, 0xC0))
            Mark-CodeLabel -Label $done
            $script:TempDepth = $baseDepth
            return
        }
    }
    Emit-BuiltinArguments -Node $Node -BaseDepth $baseDepth
    for ($i = 0; $i -lt $Node.Arguments.Count; $i++) { $argSlots.Add((Get-TempSlotPosition -Depth ($baseDepth + $i))) }
    switch ($Node.Builtin) {
        'MemoryByteAt' {
            $indexSlot = $argSlots[0]
            $invalidLabel = New-UniqueLabel -Prefix 'memory_byte_invalid'
            $doneLabel = New-UniqueLabel -Prefix 'memory_byte_done'
            Emit-LoadEaxFrame -SlotPosition $indexSlot
            Emit-Bytes -Bytes ([byte[]]@(0x83, 0xF8, 0x00)); Emit-JumpConditional -ConditionCode 0x8C -Label $invalidLabel
            Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x00, 0x10, 0x00, 0x00)); Emit-JumpConditional -ConditionCode 0x8D -Label $invalidLabel
            Emit-Bytes -Bytes ([byte[]]@(0x0F, 0xB6, 0x84, 0x05)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $script:ActiveContext.ScratchPosition) # movzx eax, byte ptr [rbp + rax + scratch_disp]
            Emit-Jump -Label $doneLabel
            Mark-CodeLabel -Label $invalidLabel; Emit-Bytes -Bytes ([byte[]]@(0xB8, 0xFF, 0xFF, 0xFF, 0xFF))
            Mark-CodeLabel -Label $doneLabel
        }
        'MemoryFill' {
            $lengthSlot = $argSlots[0]; $valueSlot = $argSlots[1]
            $invalidLabel = New-UniqueLabel -Prefix 'memory_fill_invalid'
            $doneLabel = New-UniqueLabel -Prefix 'memory_fill_done'
            Emit-LoadEaxFrame -SlotPosition $lengthSlot
            Emit-Bytes -Bytes ([byte[]]@(0x83, 0xF8, 0x00)); Emit-JumpConditional -ConditionCode 0x8C -Label $invalidLabel
            Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x00, 0x10, 0x00, 0x00)); Emit-JumpConditional -ConditionCode 0x8F -Label $invalidLabel
            Emit-LoadEaxFrame -SlotPosition $valueSlot
            Emit-Bytes -Bytes ([byte[]]@(0x83, 0xF8, 0x00)); Emit-JumpConditional -ConditionCode 0x8C -Label $invalidLabel
            Emit-Bytes -Bytes ([byte[]]@(0x3D, 0xFF, 0x00, 0x00, 0x00)); Emit-JumpConditional -ConditionCode 0x8F -Label $invalidLabel
            Emit-StoreRdiFrame -SlotPosition (Get-TempSlotPosition -Depth ($baseDepth + 2)) # preserve nonvolatile RDI
            Emit-LeaRaxFrame -SlotPosition $script:ActiveContext.ScratchPosition
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC7)) # RDI = scratch buffer
            Emit-LoadEaxFrame -SlotPosition $lengthSlot; Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC1)) # ECX = length
            Emit-LoadEaxFrame -SlotPosition $valueSlot
            Emit-Bytes -Bytes ([byte[]]@(0xF3, 0xAA)) # REP STOSB; runtime memory fill
            Emit-LoadRdiFrame -SlotPosition (Get-TempSlotPosition -Depth ($baseDepth + 2))
            Emit-LoadEaxFrame -SlotPosition $lengthSlot
            Emit-Jump -Label $doneLabel
            Mark-CodeLabel -Label $invalidLabel
            Emit-Bytes -Bytes ([byte[]]@(0xB8, 0xFF, 0xFF, 0xFF, 0xFF)) # -1 invalid request
            Mark-CodeLabel -Label $doneLabel
        }
        'FileExists' {
            $pathSlot = $argSlots[0]; $handleSlot = Get-TempSlotPosition -Depth ($baseDepth + 1)
            $failLabel = New-UniqueLabel -Prefix 'file_exists_fail'; $doneLabel = New-UniqueLabel -Prefix 'file_exists_done'
            Emit-CreateFileForPath -PathSlot $pathSlot
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xF8, 0xFF)); Emit-JumpConditional -ConditionCode 0x84 -Label $failLabel
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failLabel
            Emit-StoreRaxFrame -SlotPosition $handleSlot
            Emit-LoadRcxFrame -SlotPosition $handleSlot; Emit-CallIat -TargetRva ([UInt32]0x30B8) # CloseHandle
            Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x01, 0x00, 0x00, 0x00)); Emit-Jump -Label $doneLabel
            Mark-CodeLabel -Label $failLabel; Emit-Bytes -Bytes ([byte[]]@(0x31, 0xC0))
            Mark-CodeLabel -Label $doneLabel
        }
        'FileSize' {
            $pathSlot = $argSlots[0]; $handleSlot = Get-TempSlotPosition -Depth ($baseDepth + 1); $sizeSlot = Get-TempSlotPosition -Depth ($baseDepth + 2)
            $failOpen = New-UniqueLabel -Prefix 'file_size_open_fail'; $failHandle = New-UniqueLabel -Prefix 'file_size_read_fail'; $doneLabel = New-UniqueLabel -Prefix 'file_size_done'
            Emit-CreateFileForPath -PathSlot $pathSlot
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xF8, 0xFF)); Emit-JumpConditional -ConditionCode 0x84 -Label $failOpen
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failOpen
            Emit-StoreRaxFrame -SlotPosition $handleSlot
            Emit-LoadRcxFrame -SlotPosition $handleSlot; Emit-LeaRdxFrame -SlotPosition $script:ActiveContext.ScratchPosition; Emit-CallIat -TargetRva ([UInt32]0x30A8) # GetFileSizeEx
            Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failHandle
            Emit-Bytes -Bytes ([byte[]]@(0x8B, 0x8D)); Emit-I32 -Value (Get-FrameDisp -SlotPosition ($script:ActiveContext.ScratchPosition + 4)); Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC9)); Emit-JumpConditional -ConditionCode 0x85 -Label $failHandle
            Emit-LoadEaxFrame -SlotPosition $script:ActiveContext.ScratchPosition; Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x88 -Label $failHandle
            Emit-StoreEaxFrame -SlotPosition $sizeSlot
            Emit-LoadRcxFrame -SlotPosition $handleSlot; Emit-CallIat -TargetRva ([UInt32]0x30B8)
            Emit-LoadEaxFrame -SlotPosition $sizeSlot; Emit-Jump -Label $doneLabel
            Mark-CodeLabel -Label $failHandle; Emit-LoadRcxFrame -SlotPosition $handleSlot; Emit-CallIat -TargetRva ([UInt32]0x30B8)
            Mark-CodeLabel -Label $failOpen; Emit-Bytes -Bytes ([byte[]]@(0xB8, 0xFF, 0xFF, 0xFF, 0xFF))
            Mark-CodeLabel -Label $doneLabel
        }
        'AssetReadCount' {
            $pathSlot = $argSlots[0]; $capacitySlot = $argSlots[1]; $handleSlot = Get-TempSlotPosition -Depth ($baseDepth + 2); $countSlot = Get-TempSlotPosition -Depth ($baseDepth + 3)
            $invalid = New-UniqueLabel -Prefix 'asset_read_invalid'; $failOpen = New-UniqueLabel -Prefix 'asset_read_open_fail'; $failRead = New-UniqueLabel -Prefix 'asset_read_fail'; $doneLabel = New-UniqueLabel -Prefix 'asset_read_done'
            Emit-LoadEaxFrame -SlotPosition $capacitySlot; Emit-Bytes -Bytes ([byte[]]@(0x83, 0xF8, 0x00)); Emit-JumpConditional -ConditionCode 0x8C -Label $invalid
            Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x00, 0x10, 0x00, 0x00)); Emit-JumpConditional -ConditionCode 0x8F -Label $invalid
            Emit-CreateFileForPath -PathSlot $pathSlot
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xF8, 0xFF)); Emit-JumpConditional -ConditionCode 0x84 -Label $failOpen
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failOpen
            Emit-StoreRaxFrame -SlotPosition $handleSlot
            Emit-LoadRcxFrame -SlotPosition $handleSlot; Emit-LeaRdxFrame -SlotPosition $script:ActiveContext.ScratchPosition
            Emit-LoadEaxFrame -SlotPosition $capacitySlot; Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC0))
            Emit-LeaRaxFrame -SlotPosition ($script:ActiveContext.ScratchPosition + 0x1000); Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC1))
            Emit-Win64CallIat -TargetRva ([UInt32]0x30B0) -StackArguments @(
                @{ Kind = 'Immediate'; Value = 0 }
            ) # ReadFile; Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failRead
            Emit-Bytes -Bytes ([byte[]]@(0x8B, 0x85)); Emit-I32 -Value (Get-FrameDisp -SlotPosition ($script:ActiveContext.ScratchPosition + 0x1000)); Emit-StoreEaxFrame -SlotPosition $countSlot
            Emit-LoadRcxFrame -SlotPosition $handleSlot; Emit-CallIat -TargetRva ([UInt32]0x30B8); Emit-LoadEaxFrame -SlotPosition $countSlot; Emit-Jump -Label $doneLabel
            Mark-CodeLabel -Label $failRead; Emit-LoadRcxFrame -SlotPosition $handleSlot; Emit-CallIat -TargetRva ([UInt32]0x30B8); Emit-Jump -Label $failOpen
            Mark-CodeLabel -Label $failOpen; Emit-Bytes -Bytes ([byte[]]@(0xB8, 0xFF, 0xFF, 0xFF, 0xFF)); Emit-Jump -Label $doneLabel
            Mark-CodeLabel -Label $invalid; Emit-Bytes -Bytes ([byte[]]@(0xB8, 0xFF, 0xFF, 0xFF, 0xFF))
            Mark-CodeLabel -Label $doneLabel
        }
        'AssetReadByte' {
            $pathSlot = $argSlots[0]; $indexSlot = $argSlots[1]
            $handleSlot = Get-TempSlotPosition -Depth ($baseDepth + 2)
            $byteSlot = Get-TempSlotPosition -Depth ($baseDepth + 3)
            $invalid = New-UniqueLabel -Prefix 'asset_byte_invalid'
            $failOpen = New-UniqueLabel -Prefix 'asset_byte_open_fail'
            $failRead = New-UniqueLabel -Prefix 'asset_byte_read_fail'
            $doneLabel = New-UniqueLabel -Prefix 'asset_byte_done'
            Emit-LoadEaxFrame -SlotPosition $indexSlot
            Emit-Bytes -Bytes ([byte[]]@(0x83, 0xF8, 0x00)); Emit-JumpConditional -ConditionCode 0x8C -Label $invalid
            Emit-Bytes -Bytes ([byte[]]@(0x3D, 0xFF, 0x0F, 0x00, 0x00)); Emit-JumpConditional -ConditionCode 0x8F -Label $invalid # index must be <= 4095
            Emit-CreateFileForPath -PathSlot $pathSlot
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xF8, 0xFF)); Emit-JumpConditional -ConditionCode 0x84 -Label $failOpen
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failOpen
            Emit-StoreRaxFrame -SlotPosition $handleSlot
            Emit-LoadRcxFrame -SlotPosition $handleSlot; Emit-LeaRdxFrame -SlotPosition $script:ActiveContext.ScratchPosition
            Emit-LoadEaxFrame -SlotPosition $indexSlot; Emit-Bytes -Bytes ([byte[]]@(0x83, 0xC0, 0x01, 0x41, 0x89, 0xC0)) # read index + 1 bytes
            Emit-LeaRaxFrame -SlotPosition ($script:ActiveContext.ScratchPosition + 0x1000); Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC1))
            Emit-Win64CallIat -TargetRva ([UInt32]0x30B0) -StackArguments @(
                @{ Kind = 'Immediate'; Value = 0 }
            ) # ReadFile; Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failRead
            Emit-LoadEaxFrame -SlotPosition ($script:ActiveContext.ScratchPosition + 0x1000)
            Emit-Bytes -Bytes ([byte[]]@(0x8B, 0x8D)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $indexSlot); Emit-Bytes -Bytes ([byte[]]@(0x83, 0xC1, 0x01, 0x39, 0xC8)); Emit-JumpConditional -ConditionCode 0x82 -Label $failRead # fail if read count < index + 1
            Emit-LoadEaxFrame -SlotPosition $indexSlot
            Emit-Bytes -Bytes ([byte[]]@(0x0F, 0xB6, 0x84, 0x05)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $script:ActiveContext.ScratchPosition)
            Emit-StoreEaxFrame -SlotPosition $byteSlot
            Emit-LoadRcxFrame -SlotPosition $handleSlot; Emit-CallIat -TargetRva ([UInt32]0x30B8)
            Emit-LoadEaxFrame -SlotPosition $byteSlot; Emit-Jump -Label $doneLabel
            Mark-CodeLabel -Label $failRead; Emit-LoadRcxFrame -SlotPosition $handleSlot; Emit-CallIat -TargetRva ([UInt32]0x30B8); Emit-Jump -Label $failOpen
            Mark-CodeLabel -Label $failOpen; Emit-Bytes -Bytes ([byte[]]@(0xB8, 0xFF, 0xFF, 0xFF, 0xFF)); Emit-Jump -Label $doneLabel
            Mark-CodeLabel -Label $invalid; Emit-Bytes -Bytes ([byte[]]@(0xB8, 0xFF, 0xFF, 0xFF, 0xFF))
            Mark-CodeLabel -Label $doneLabel
        }
        'D3D11RenderDemo' { Emit-D3D11RenderDemo -BaseDepth $baseDepth -ArgumentSlots $argSlots }
        'DevRunTool' { Emit-DevRunTool -ToolSlot $argSlots[0] -TimeoutSlot $argSlots[1] -BaseDepth $baseDepth }
        'WindowProbe' {
            $titleSlot = $argSlots[0]; $instanceSlot = Get-TempSlotPosition -Depth ($baseDepth + 1); $windowSlot = Get-TempSlotPosition -Depth ($baseDepth + 2)
            $failLabel = New-UniqueLabel -Prefix 'window_create_fail'; $doneLabel = New-UniqueLabel -Prefix 'window_create_done'
            Emit-Bytes -Bytes ([byte[]]@(0x33, 0xC9)); Emit-CallIat -TargetRva ([UInt32]0x30C0) # GetModuleHandleA(NULL)
            Emit-StoreRaxFrame -SlotPosition $instanceSlot
            Emit-Bytes -Bytes ([byte[]]@(0x33, 0xC9)); Emit-DataAddress -DataItem (Register-DataConstant -Value 'STATIC'); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2)) # class name -> RDX
            Emit-LoadRaxFrame -SlotPosition $titleSlot; Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0)) # title -> R8
            Emit-Bytes -Bytes ([byte[]]@(0x41, 0xB9, 0x00, 0x00, 0xCF, 0x00)) # hidden WS_OVERLAPPEDWINDOW
            Emit-Win64CallIat -TargetRva ([UInt32]0x30F0) -StackArguments @(
                @{ Kind = 'Immediate'; Value = -2147483648 },
                @{ Kind = 'Immediate'; Value = -2147483648 },
                @{ Kind = 'Immediate'; Value = 320 },
                @{ Kind = 'Immediate'; Value = 240 },
                @{ Kind = 'Immediate'; Value = 0 },
                @{ Kind = 'Immediate'; Value = 0 },
                @{ Kind = 'FrameQword'; SlotPosition = $instanceSlot },
                @{ Kind = 'Immediate'; Value = 0 }
            ) # CreateWindowExA; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failLabel
            Emit-StoreRaxFrame -SlotPosition $windowSlot
            # Keep the test window hidden, update it, and non-blockingly dispatch one queued message.
            Emit-LoadRcxFrame -SlotPosition $windowSlot; Emit-Bytes -Bytes ([byte[]]@(0x33, 0xD2)); Emit-CallIat -TargetRva ([UInt32]0x30F8) # ShowWindow(SW_HIDE)
            Emit-LoadRcxFrame -SlotPosition $windowSlot; Emit-CallIat -TargetRva ([UInt32]0x3100) # UpdateWindow
            Emit-WindowPumpCore
            Emit-LoadRcxFrame -SlotPosition $windowSlot; Emit-CallIat -TargetRva ([UInt32]0x3120) # DestroyWindow
            Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x01, 0x00, 0x00, 0x00)); Emit-Jump -Label $doneLabel
            Mark-CodeLabel -Label $failLabel; Emit-Bytes -Bytes ([byte[]]@(0x31, 0xC0))
            Mark-CodeLabel -Label $doneLabel
        }
        'WindowPump' { Emit-WindowPumpCore }
        'ThreadSyncProbe' { Emit-ThreadSyncCore -BaseDepth $baseDepth }
        default { Throw-SourceError -Line $Node.Line -Column $Node.Column -Message ("Unsupported standard-library intrinsic '{0}'." -f $Node.Builtin) }
    }
    $script:TempDepth = $baseDepth
}
function Emit-WindowPumpCore {
    $noneLabel = New-UniqueLabel -Prefix 'window_pump_none'; $doneLabel = New-UniqueLabel -Prefix 'window_pump_done'
    Emit-LeaRaxFrame -SlotPosition $script:ActiveContext.ScratchPosition; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xD2, 0x45, 0x33, 0xC0, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3108) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 1 }
    ) # PeekMessageA; Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $noneLabel
    Emit-LeaRaxFrame -SlotPosition $script:ActiveContext.ScratchPosition; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1)); Emit-CallIat -TargetRva ([UInt32]0x3110) # TranslateMessage
    Emit-LeaRaxFrame -SlotPosition $script:ActiveContext.ScratchPosition; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1)); Emit-CallIat -TargetRva ([UInt32]0x3118) # DispatchMessageA
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x01, 0x00, 0x00, 0x00)); Emit-Jump -Label $doneLabel
    Mark-CodeLabel -Label $noneLabel; Emit-Bytes -Bytes ([byte[]]@(0x31, 0xC0))
    Mark-CodeLabel -Label $doneLabel
}
function Emit-D3D11MessagePump {
    param([int] $MessageSlot, [int] $WindowSlot, [string] $LoopDoneLabel)
    $checkWindow = New-UniqueLabel -Prefix 'd3d11_message_check_window'
    $dispatch = New-UniqueLabel -Prefix 'd3d11_message_dispatch'
    # PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)
    Emit-LeaRaxFrame -SlotPosition $MessageSlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xD2, 0x45, 0x33, 0xC0, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3108) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 1 }
    ) # PeekMessageA; Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $checkWindow
    # MSG.message is the DWORD at offset 8 on x64. WM_QUIT terminates the demo loop.
    Emit-Bytes -Bytes ([byte[]]@(0x81, 0xBD)); Emit-I32 -Value (Get-FrameDisp -SlotPosition ($MessageSlot + 8)); Emit-I32 -Value 0x12
    Emit-JumpConditional -ConditionCode 0x85 -Label $dispatch
    Emit-Jump -Label $LoopDoneLabel
    Mark-CodeLabel -Label $dispatch
    Emit-LeaRaxFrame -SlotPosition $MessageSlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1, 0x48, 0x83, 0xEC, 0x20)); Emit-CallIat -TargetRva ([UInt32]0x3110); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20))
    Emit-LeaRaxFrame -SlotPosition $MessageSlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1, 0x48, 0x83, 0xEC, 0x20)); Emit-CallIat -TargetRva ([UInt32]0x3118); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20))
    Mark-CodeLabel -Label $checkWindow
    Emit-LoadRcxFrame -SlotPosition $WindowSlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x20)); Emit-CallIat -TargetRva ([UInt32]0x3168); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20))
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $LoopDoneLabel
}
function Emit-D3D11RenderDemo {
    param([int] $BaseDepth, [object] $ArgumentSlots)
    $titleSlot = [int]$ArgumentSlots[0]
    $framesSlot = [int]$ArgumentSlots[1]
    $scratch = [int]$script:ActiveContext.ScratchPosition
    $windowSlot = $scratch + 0x80
    $swapSlot = $scratch + 0x88
    $deviceSlot = $scratch + 0x90
    $contextSlot = $scratch + 0x98
    $backBufferSlot = $scratch + 0xA0
    $rtvSlot = $scratch + 0xA8
    $factorySlot = $scratch + 0xB0
    $featureSlot = $scratch + 0xB8
    $colorSlot = $scratch + 0xC0
    $factoryGuidSlot = $scratch + 0xE0
    $textureGuidSlot = $scratch + 0xF0
    $messageSlot = $scratch + 0x110
    $qpcStartSlot = $scratch + 0x150
    $qpcEndSlot = $scratch + 0x158
    $qpcFreqSlot = $scratch + 0x160
    $elapsedSlot = $scratch + 0x168
    $frameCountSlot = $scratch + 0x16C
    $bytesWrittenSlot = $scratch + 0x170
    $stdoutSlot = $scratch + 0x178
    $formatBufferSlot = $scratch + 0x200
    $formatLengthSlot = $scratch + 0x280
    $failLabel = '__runtime_fail'
    $deviceCreated = New-UniqueLabel -Prefix 'd3d11_device_created'
    $hardwareFailed = New-UniqueLabel -Prefix 'd3d11_hardware_failed'
    $loopStart = New-UniqueLabel -Prefix 'd3d11_render_loop'
    $loopDone = New-UniqueLabel -Prefix 'd3d11_render_done'
    $statsWritten = New-UniqueLabel -Prefix 'd3d11_stats_written'

    # The frame count is runtime input to this intrinsic; constrain the test loop to 1..240 frames.
    Emit-LoadEaxFrame -SlotPosition $framesSlot
    Emit-Bytes -Bytes ([byte[]]@(0x83, 0xF8, 0x01)); Emit-JumpConditional -ConditionCode 0x8C -Label $failLabel
    Emit-Bytes -Bytes ([byte[]]@(0x3D)); Emit-I32 -Value 240; Emit-JumpConditional -ConditionCode 0x8F -Label $failLabel

    # Initialize all output pointers and the 72-byte DXGI_SWAP_CHAIN_DESC.
    foreach ($slot in @($windowSlot, $swapSlot, $deviceSlot, $contextSlot, $backBufferSlot, $rtvSlot, $factorySlot)) { Emit-StoreZero64Frame -SlotPosition $slot }
    Emit-StoreBits32Frame -SlotPosition $featureSlot -Value ([UInt32]0)
    for ($i = 0; $i -lt 18; $i++) { Emit-StoreBits32Frame -SlotPosition ($scratch + ($i * 4)) -Value ([UInt32]0) }
    # DXGI_SWAP_CHAIN_DESC: 960x540, 60/1 Hz, R8G8B8A8_UNORM, sample count 1,
    # render-target output usage, 2 buffers, HWND set after window creation, windowed, discard.
    Emit-StoreBits32Frame -SlotPosition ($scratch + 0) -Value ([UInt32]960)
    Emit-StoreBits32Frame -SlotPosition ($scratch + 4) -Value ([UInt32]540)
    Emit-StoreBits32Frame -SlotPosition ($scratch + 8) -Value ([UInt32]60)
    Emit-StoreBits32Frame -SlotPosition ($scratch + 12) -Value ([UInt32]1)
    Emit-StoreBits32Frame -SlotPosition ($scratch + 16) -Value ([UInt32]28)
    Emit-StoreBits32Frame -SlotPosition ($scratch + 28) -Value ([UInt32]1)
    Emit-StoreBits32Frame -SlotPosition ($scratch + 36) -Value ([UInt32]0x20)
    Emit-StoreBits32Frame -SlotPosition ($scratch + 40) -Value ([UInt32]2)
    Emit-StoreBits32Frame -SlotPosition ($scratch + 56) -Value ([UInt32]1)
    # IID_IDXGIFactory = {7B7166EC-21C7-44AE-B21A-C9AE321AE369}.
    Emit-StoreBits32Frame -SlotPosition $factoryGuidSlot -Value ([UInt32]0x7B7166EC)
    Emit-StoreBits32Frame -SlotPosition ($factoryGuidSlot + 4) -Value ([UInt32]0x44AE21C7)
    Emit-StoreImm64Frame -SlotPosition ($factoryGuidSlot + 8) -Value ([UInt64]0x69E31A32AEC91AB2)
    # IID_ID3D11Texture2D = {6F15AAF2-D208-4E89-9AB4-489535D34F9C}.
    Emit-StoreBits32Frame -SlotPosition $textureGuidSlot -Value ([UInt32]0x6F15AAF2)
    Emit-StoreBits32Frame -SlotPosition ($textureGuidSlot + 4) -Value ([UInt32]0x4E89D208)
    Emit-StoreImm64Frame -SlotPosition ($textureGuidSlot + 8) -Value ([UInt64]::Parse('9C4FD3359548B49A', [System.Globalization.NumberStyles]::HexNumber))
    # Clear color: dark blue, stored as native IEEE-754 FLOAT bits.
    Emit-StoreBits32Frame -SlotPosition $colorSlot -Value ([UInt32]0x3D75C28F)
    Emit-StoreBits32Frame -SlotPosition ($colorSlot + 4) -Value ([UInt32]0x3DF5C28F)
    Emit-StoreBits32Frame -SlotPosition ($colorSlot + 8) -Value ([UInt32]0x3E75C28F)
    Emit-StoreBits32Frame -SlotPosition ($colorSlot + 12) -Value ([UInt32]0x3F800000)

    # Make a visible, top-level window using the built-in STATIC window class.
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xC9, 0x48, 0x83, 0xEC, 0x20)); Emit-CallIat -TargetRva ([UInt32]0x30C0); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20)) # GetModuleHandleA(NULL)
    Emit-StoreRaxFrame -SlotPosition ($scratch + 0xD0) # hInstance
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xC9)); Emit-DataAddress -DataItem (Register-DataConstant -Value 'STATIC'); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-LoadRaxFrame -SlotPosition $titleSlot; Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0))
    Emit-Bytes -Bytes ([byte[]]@(0x41, 0xB9, 0x00, 0x00, 0xCF, 0x10)) # WS_OVERLAPPEDWINDOW | WS_VISIBLE
    Emit-Win64CallIat -TargetRva ([UInt32]0x30F0) -StackArguments @(
        @{ Kind = 'Immediate'; Value = -2147483648 },
        @{ Kind = 'Immediate'; Value = -2147483648 },
        @{ Kind = 'Immediate'; Value = 960 },
        @{ Kind = 'Immediate'; Value = 540 },
        @{ Kind = 'Immediate'; Value = 0 },
        @{ Kind = 'Immediate'; Value = 0 },
        @{ Kind = 'FrameQword'; SlotPosition = ($scratch + 0xD0) },
        @{ Kind = 'Immediate'; Value = 0 }
    ); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failLabel
    Emit-StoreRaxFrame -SlotPosition $windowSlot
    Emit-LoadRaxFrame -SlotPosition $windowSlot; Emit-StoreRaxFrame -SlotPosition ($scratch + 48) # desc.OutputWindow
    Emit-LoadRcxFrame -SlotPosition $windowSlot; Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x05, 0x00, 0x00, 0x00, 0x48, 0x83, 0xEC, 0x20)); Emit-CallIat -TargetRva ([UInt32]0x30F8); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20)) # ShowWindow(SW_SHOW)
    Emit-LoadRcxFrame -SlotPosition $windowSlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x20)); Emit-CallIat -TargetRva ([UInt32]0x3100); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20)) # UpdateWindow

    # Explicit DXGI factory probe: import CreateDXGIFactory from DXGI.dll, then release it.
    Emit-LeaRaxFrame -SlotPosition $factoryGuidSlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-LeaRaxFrame -SlotPosition $factorySlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x20)); Emit-CallIat -TargetRva ([UInt32]0x3140); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20))
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x88 -Label $failLabel
    Emit-LoadRaxFrame -SlotPosition $factorySlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failLabel
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x20)); Emit-LoadRcxFrame -SlotPosition $factorySlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8B, 0x01, 0xFF, 0x50, 0x10)); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20)) # IUnknown::Release
    Emit-StoreZero64Frame -SlotPosition $factorySlot

    # Fill output slots with NULL before the device-and-swap-chain call.
    foreach ($slot in @($swapSlot, $deviceSlot, $contextSlot)) { Emit-StoreZero64Frame -SlotPosition $slot }
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xC9, 0xBA, 0x01, 0x00, 0x00, 0x00, 0x45, 0x33, 0xC0, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3130) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 0 },
        @{ Kind = 'Immediate'; Value = 0 },
        @{ Kind = 'Immediate'; Value = 7 },
        @{ Kind = 'FrameAddress'; SlotPosition = $scratch },
        @{ Kind = 'FrameAddress'; SlotPosition = $swapSlot },
        @{ Kind = 'FrameAddress'; SlotPosition = $deviceSlot },
        @{ Kind = 'FrameAddress'; SlotPosition = $featureSlot },
        @{ Kind = 'FrameAddress'; SlotPosition = $contextSlot }
    ); Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x89 -Label $deviceCreated
    Mark-CodeLabel -Label $hardwareFailed
    # Retry using the built-in WARP software rasterizer when hardware initialization fails.
    foreach ($slot in @($swapSlot, $deviceSlot, $contextSlot)) { Emit-StoreZero64Frame -SlotPosition $slot }
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xC9, 0xBA, 0x05, 0x00, 0x00, 0x00, 0x45, 0x33, 0xC0, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3130) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 0 },
        @{ Kind = 'Immediate'; Value = 0 },
        @{ Kind = 'Immediate'; Value = 7 },
        @{ Kind = 'FrameAddress'; SlotPosition = $scratch },
        @{ Kind = 'FrameAddress'; SlotPosition = $swapSlot },
        @{ Kind = 'FrameAddress'; SlotPosition = $deviceSlot },
        @{ Kind = 'FrameAddress'; SlotPosition = $featureSlot },
        @{ Kind = 'FrameAddress'; SlotPosition = $contextSlot }
    ); Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x88 -Label $failLabel
    Mark-CodeLabel -Label $deviceCreated
    foreach ($slot in @($swapSlot, $deviceSlot, $contextSlot)) { Emit-LoadRaxFrame -SlotPosition $slot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failLabel }

    # IDXGISwapChain::GetBuffer(0, IID_ID3D11Texture2D, &backBuffer).
    Emit-LoadRcxFrame -SlotPosition $swapSlot; Emit-Bytes -Bytes ([byte[]]@(0x33, 0xD2))
    Emit-LeaRaxFrame -SlotPosition $textureGuidSlot; Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0))
    Emit-LeaRaxFrame -SlotPosition $backBufferSlot; Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC1))
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x20)); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8B, 0x01, 0xFF, 0x50, 0x48)); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20)) # IDXGISwapChain::GetBuffer, vtable slot 9
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x88 -Label $failLabel
    Emit-LoadRaxFrame -SlotPosition $backBufferSlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failLabel

    # ID3D11Device::CreateRenderTargetView(backBuffer, NULL, &rtv).
    # ID3D11Device inherits IUnknown directly: CreateRenderTargetView is slot 9, byte offset 0x48.
    Emit-LoadRcxFrame -SlotPosition $deviceSlot; Emit-LoadRaxFrame -SlotPosition $backBufferSlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-Bytes -Bytes ([byte[]]@(0x45, 0x33, 0xC0))
    Emit-LeaRaxFrame -SlotPosition $rtvSlot; Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC1))
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x20)); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8B, 0x01, 0xFF, 0x50, 0x48)); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20))
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x88 -Label $failLabel
    Emit-LoadRaxFrame -SlotPosition $rtvSlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failLabel
    # Release the back-buffer reference; the render-target view owns its resource reference.
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x20)); Emit-LoadRcxFrame -SlotPosition $backBufferSlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8B, 0x01, 0xFF, 0x50, 0x10)); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20)); Emit-StoreZero64Frame -SlotPosition $backBufferSlot

    # ID3D11DeviceContext::OMSetRenderTargets(1, &rtv, NULL).
    Emit-LoadRcxFrame -SlotPosition $contextSlot; Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x01, 0x00, 0x00, 0x00))
    Emit-LeaRaxFrame -SlotPosition $rtvSlot; Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0, 0x45, 0x33, 0xC9))
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x20)); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8B, 0x01, 0xFF, 0x90)); Emit-I32 -Value 0x108; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20))
    # Frame timing uses QueryPerformanceFrequency/Counter around the actual clear-and-present loop.
    Emit-LeaRaxFrame -SlotPosition $qpcFreqSlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1)); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x20)); Emit-CallIat -TargetRva ([UInt32]0x3158); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20))
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failLabel
    Emit-LeaRaxFrame -SlotPosition $qpcStartSlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1)); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x20)); Emit-CallIat -TargetRva ([UInt32]0x3150); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20))
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failLabel
    Emit-StoreBits32Frame -SlotPosition $frameCountSlot -Value ([UInt32]0)
    Mark-CodeLabel -Label $loopStart
    Emit-LoadEaxFrame -SlotPosition $frameCountSlot; Emit-Bytes -Bytes ([byte[]]@(0x8B, 0x8D)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $framesSlot)
    Emit-Bytes -Bytes ([byte[]]@(0x39, 0xC8)); Emit-JumpConditional -ConditionCode 0x8D -Label $loopDone
    Emit-D3D11MessagePump -MessageSlot $messageSlot -WindowSlot $windowSlot -LoopDoneLabel $loopDone
    # ID3D11DeviceContext::ClearRenderTargetView(rtv, RGBA).
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x20)); Emit-LoadRcxFrame -SlotPosition $contextSlot; Emit-LoadRaxFrame -SlotPosition $rtvSlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2)) # RDX receives the full 64-bit render-target-view pointer
    Emit-Bytes -Bytes ([byte[]]@(0x4C, 0x8D, 0x85)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $colorSlot)
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8B, 0x01, 0xFF, 0x90)); Emit-I32 -Value 0x190; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20)) # ClearRenderTargetView is vtable slot 50
    # IDXGISwapChain::Present(1, 0). Require exact S_OK, not DXGI_STATUS_OCCLUDED.
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x20)); Emit-LoadRcxFrame -SlotPosition $swapSlot; Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x01, 0x00, 0x00, 0x00, 0x45, 0x33, 0xC0, 0x48, 0x8B, 0x01, 0xFF, 0x50, 0x40)); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20))
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x85 -Label $failLabel
    Emit-Bytes -Bytes ([byte[]]@(0xFF, 0x85)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $frameCountSlot)
    Emit-Jump -Label $loopStart
    Mark-CodeLabel -Label $loopDone
    Emit-LoadEaxFrame -SlotPosition $frameCountSlot; Emit-Bytes -Bytes ([byte[]]@(0x3B, 0x85)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $framesSlot); Emit-JumpConditional -ConditionCode 0x85 -Label $failLabel

    Emit-LeaRaxFrame -SlotPosition $qpcEndSlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1)); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x20)); Emit-CallIat -TargetRva ([UInt32]0x3150); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20))
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failLabel
    # elapsed_ms = (1000 * (QPC_end - QPC_start)) / QPC_frequency.
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8B, 0x85)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $qpcEndSlot)
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x2B, 0x85)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $qpcStartSlot)
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x69, 0xC0, 0xE8, 0x03, 0x00, 0x00, 0x48, 0x99, 0x48, 0x8B, 0x8D))
    Emit-I32 -Value (Get-FrameDisp -SlotPosition $qpcFreqSlot)
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9)); Emit-JumpConditional -ConditionCode 0x84 -Label $failLabel
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0xF7, 0xF9, 0x89, 0x85)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $elapsedSlot)

    # Release COM objects and destroy the window only after the rendering loop has completed.
    foreach ($comSlot in @($rtvSlot, $contextSlot, $swapSlot, $deviceSlot)) { Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x20)); Emit-LoadRcxFrame -SlotPosition $comSlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8B, 0x01, 0xFF, 0x50, 0x10)); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20)) }
    Emit-LoadRcxFrame -SlotPosition $windowSlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x20)); Emit-CallIat -TargetRva ([UInt32]0x3120); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20))

    # Emit a machine-generated runtime report only after all checkpoints succeeded.
    $format = Register-DataConstant -Value ("D3D11: window=PASS device=PASS swapchain=PASS rtv=PASS frames=%u elapsed_ms=%u`r`n")
    Emit-LeaRaxFrame -SlotPosition $formatBufferSlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-DataAddress -DataItem $format; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-LoadEaxFrame -SlotPosition $frameCountSlot; Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC0))
    Emit-LoadEaxFrame -SlotPosition $elapsedSlot; Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC1))
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x20)); Emit-CallIat -TargetRva ([UInt32]0x3090); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20)); Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x8E -Label $failLabel; Emit-StoreEaxFrame -SlotPosition $formatLengthSlot
    Emit-Bytes -Bytes ([byte[]]@(0xB9, 0xF5, 0xFF, 0xFF, 0xFF, 0x48, 0x83, 0xEC, 0x20)); Emit-CallIat -TargetRva ([UInt32]0x3070); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20))
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failLabel
    Emit-StoreRaxFrame -SlotPosition $stdoutSlot
    Emit-LoadRaxFrame -SlotPosition $stdoutSlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-LeaRaxFrame -SlotPosition $formatBufferSlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-LoadEaxFrame -SlotPosition $formatLengthSlot; Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC0))
    Emit-LeaRaxFrame -SlotPosition $bytesWrittenSlot; Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3078) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 0 }
    )
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failLabel
    Emit-LoadEaxFrame -SlotPosition $bytesWrittenSlot; Emit-Bytes -Bytes ([byte[]]@(0x3B, 0x85)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $formatLengthSlot); Emit-JumpConditional -ConditionCode 0x85 -Label $failLabel
    Emit-LoadEaxFrame -SlotPosition $frameCountSlot
}
function Emit-ThreadSyncCore {
    param([int] $BaseDepth)
    $threadSlot = Get-TempSlotPosition -Depth $BaseDepth; $mutexSlot = Get-TempSlotPosition -Depth ($BaseDepth + 1)
    $threadFail = New-UniqueLabel -Prefix 'thread_sync_thread_fail'; $mutexFail = New-UniqueLabel -Prefix 'thread_sync_mutex_fail'; $mutexWaitFail = New-UniqueLabel -Prefix 'thread_sync_mutex_wait_fail'; $releaseFail = New-UniqueLabel -Prefix 'thread_sync_release_fail'; $done = New-UniqueLabel -Prefix 'thread_sync_done'
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xC9, 0x33, 0xD2)); Emit-LeaR8CodeLabel -Label '__sharnou_worker'; Emit-Bytes -Bytes ([byte[]]@(0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x30C8) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 0 },
        @{ Kind = 'FrameAddress'; SlotPosition = $script:ActiveContext.ScratchPosition }
    ) # CreateThread; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $threadFail
    Emit-StoreRaxFrame -SlotPosition $threadSlot; Emit-LoadRcxFrame -SlotPosition $threadSlot; Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x88, 0x13, 0x00, 0x00)); Emit-CallIat -TargetRva ([UInt32]0x30D0) # WaitForSingleObject
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x85 -Label $threadFail
    Emit-LoadRcxFrame -SlotPosition $threadSlot; Emit-CallIat -TargetRva ([UInt32]0x30B8) # CloseHandle
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xC9, 0x33, 0xD2, 0x45, 0x33, 0xC0)); Emit-CallIat -TargetRva ([UInt32]0x30D8) # CreateMutexA
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $mutexFail
    Emit-StoreRaxFrame -SlotPosition $mutexSlot; Emit-LoadRcxFrame -SlotPosition $mutexSlot; Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x88, 0x13, 0x00, 0x00)); Emit-CallIat -TargetRva ([UInt32]0x30D0)
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x85 -Label $mutexWaitFail
    Emit-LoadRcxFrame -SlotPosition $mutexSlot; Emit-CallIat -TargetRva ([UInt32]0x30E0); Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $releaseFail
    Emit-LoadRcxFrame -SlotPosition $mutexSlot; Emit-CallIat -TargetRva ([UInt32]0x30B8); Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x01, 0x00, 0x00, 0x00)); Emit-Jump -Label $done
    Mark-CodeLabel -Label $threadFail; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0)); $cleanupThread = New-UniqueLabel -Prefix 'thread_sync_close_thread'; Emit-JumpConditional -ConditionCode 0x84 -Label $cleanupThread; Emit-LoadRcxFrame -SlotPosition $threadSlot; Emit-CallIat -TargetRva ([UInt32]0x30B8); Mark-CodeLabel -Label $cleanupThread; Emit-Bytes -Bytes ([byte[]]@(0x31, 0xC0)); Emit-Jump -Label $done
    Mark-CodeLabel -Label $mutexWaitFail; Emit-LoadRcxFrame -SlotPosition $mutexSlot; Emit-CallIat -TargetRva ([UInt32]0x30B8); Emit-Bytes -Bytes ([byte[]]@(0x31, 0xC0)); Emit-Jump -Label $done
    Mark-CodeLabel -Label $releaseFail; Emit-LoadRcxFrame -SlotPosition $mutexSlot; Emit-CallIat -TargetRva ([UInt32]0x30B8); Emit-Bytes -Bytes ([byte[]]@(0x31, 0xC0)); Emit-Jump -Label $done
    Mark-CodeLabel -Label $mutexFail; Emit-Bytes -Bytes ([byte[]]@(0x31, 0xC0))
    Mark-CodeLabel -Label $done
}
function Emit-IntegerExpression {
    param([object] $Node)
    switch ($Node.Kind) {
        'Integer' { Emit-Bytes -Bytes ([byte[]]@(0xB8)); Emit-I32 -Value ([long]$Node.Value); return }
        'Variable' {
            if ($Node.Type -ne 'Integer') { Throw-SourceError -Line $Node.Line -Column $Node.Column -Message 'Internal type error: integer expression expected.' }
            Emit-LoadEaxFrame -SlotPosition (0x80 + ([int]$Node.Slot * 16)); return
        }
        'Unary' { Emit-IntegerExpression -Node $Node.Operand; if ($Node.Operator -eq '-') { Emit-Bytes -Bytes ([byte[]]@(0xF7, 0xD8)); Emit-JumpConditional -ConditionCode 0x80 -Label '__runtime_fail' }; return }
        'Comparison' {
            Emit-IntegerExpression -Node $Node.Left
            $tempSlot = Get-TempSlotPosition -Depth $script:TempDepth
            Emit-StoreEaxFrame -SlotPosition $tempSlot
            $script:TempDepth++
            Emit-IntegerExpression -Node $Node.Right
            $script:TempDepth--
            Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC1)) # mov ecx,eax
            Emit-LoadEaxFrame -SlotPosition $tempSlot
            Emit-Bytes -Bytes ([byte[]]@(0x39, 0xC8)) # cmp eax,ecx
            switch ($Node.Operator) {
                '<'  { Emit-Bytes -Bytes ([byte[]]@(0x0F, 0x9C, 0xC0)) } # setl al
                '>'  { Emit-Bytes -Bytes ([byte[]]@(0x0F, 0x9F, 0xC0)) } # setg al
                '<=' { Emit-Bytes -Bytes ([byte[]]@(0x0F, 0x9E, 0xC0)) } # setle al
                '>=' { Emit-Bytes -Bytes ([byte[]]@(0x0F, 0x9D, 0xC0)) } # setge al
                '==' { Emit-Bytes -Bytes ([byte[]]@(0x0F, 0x94, 0xC0)) } # sete al
                '!=' { Emit-Bytes -Bytes ([byte[]]@(0x0F, 0x95, 0xC0)) } # setne al
                default { Throw-SourceError -Line $Node.Line -Column $Node.Column -Message ("Unsupported comparison operator '{0}'." -f $Node.Operator) }
            }
            Emit-Bytes -Bytes ([byte[]]@(0x0F, 0xB6, 0xC0)) # movzx eax,al (normalize to 0 or 1)
            return
        }
        'Binary' {
            Emit-IntegerExpression -Node $Node.Left
            $tempSlot = Get-TempSlotPosition -Depth $script:TempDepth; Emit-StoreEaxFrame -SlotPosition $tempSlot; $script:TempDepth++
            Emit-IntegerExpression -Node $Node.Right; $script:TempDepth--
            Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC1)); Emit-LoadEaxFrame -SlotPosition $tempSlot
            switch ($Node.Operator) {
                '+' { Emit-Bytes -Bytes ([byte[]]@(0x01, 0xC8)); Emit-JumpConditional -ConditionCode 0x80 -Label '__runtime_fail' }
                '-' { Emit-Bytes -Bytes ([byte[]]@(0x29, 0xC8)); Emit-JumpConditional -ConditionCode 0x80 -Label '__runtime_fail' }
                '*' { Emit-Bytes -Bytes ([byte[]]@(0x0F, 0xAF, 0xC1)); Emit-JumpConditional -ConditionCode 0x80 -Label '__runtime_fail' }
                '/' {
                    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC9)); Emit-JumpConditional -ConditionCode 0x84 -Label '__runtime_fail'
                    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x00, 0x00, 0x00, 0x80))
                    $continueLabel = '__divide_continue_' + [string]$script:UniqueLabel; $script:UniqueLabel++
                    Emit-JumpConditional -ConditionCode 0x85 -Label $continueLabel
                    Emit-Bytes -Bytes ([byte[]]@(0x83, 0xF9, 0xFF)); Emit-JumpConditional -ConditionCode 0x84 -Label '__runtime_fail'
                    Mark-CodeLabel -Label $continueLabel; Emit-Bytes -Bytes ([byte[]]@(0x99, 0xF7, 0xF9))
                }
                default { Throw-SourceError -Line $Node.Line -Column $Node.Column -Message ("Unsupported arithmetic operator '{0}'." -f $Node.Operator) }
            }
            return
        }
        'Call' {
            if (-not [string]::IsNullOrEmpty([string]$Node.Builtin)) { Emit-BuiltinCall -Node $Node; return }
            $baseDepth = [int]$script:TempDepth
            $argumentCount = [int]$Node.Arguments.Count
            if ($argumentCount -gt 16) {
                Throw-SourceError -Line $Node.Line -Column $Node.Column -Message "Function calls support at most 16 integer arguments under the current Windows x64 ABI subset."
            }
            # Evaluate every argument before touching ABI registers or outgoing stack slots.
            for ($i = 0; $i -lt $argumentCount; $i++) {
                Emit-IntegerExpression -Node $Node.Arguments[$i]
                Emit-StoreEaxFrame -SlotPosition (Get-TempSlotPosition -Depth $script:TempDepth)
                $script:TempDepth++
            }
            # Every Windows x64 call reserves 32 bytes of shadow space. Additional
            # arguments occupy 8-byte slots beginning at [RSP+0x20]. The total is
            # rounded to 16 bytes so RSP remains call-site aligned.
            $stackArgumentCount = [Math]::Max(0, $argumentCount - 4)
            $callFrameSize = Align-Up -Value (0x20 + ($stackArgumentCount * 8)) -Alignment 0x10
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0x81, 0xEC))
            Emit-I32 -Value $callFrameSize
            for ($i = 0; $i -lt [Math]::Min(4, $argumentCount); $i++) {
                Emit-LoadEaxFrame -SlotPosition (Get-TempSlotPosition -Depth ($baseDepth + $i))
                switch ($i) {
                    0 { Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC1)) }
                    1 { Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC2)) }
                    2 { Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC0)) }
                    3 { Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC1)) }
                }
            }
            for ($i = 4; $i -lt $argumentCount; $i++) {
                Emit-LoadEaxFrame -SlotPosition (Get-TempSlotPosition -Depth ($baseDepth + $i))
                Emit-StackArgumentRax -Offset (0x20 + (($i - 4) * 8))
            }
            Emit-CallFunction -Name $Node.Name
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0x81, 0xC4))
            Emit-I32 -Value $callFrameSize
            $script:TempDepth -= $argumentCount
            return
        }
        default { Throw-SourceError -Line $Node.Line -Column $Node.Column -Message 'Internal code-generation error: unsupported integer expression node.' }
    }
}
function Emit-StringExpression {
    param([object] $Node)
    switch ($Node.Kind) {
        'String' { $item = Register-DataConstant -Value ([string]$Node.Value); Emit-DataAddress -DataItem $item; Emit-Bytes -Bytes ([byte[]]@(0xBA)); Emit-I32 -Value ([System.Text.Encoding]::ASCII.GetByteCount([string]$Node.Value)); return }
        'Variable' { if ($Node.Type -ne 'String') { Throw-SourceError -Line $Node.Line -Column $Node.Column -Message 'Internal type error: string expression expected.' }; $slotPosition = 0x80 + ([int]$Node.Slot * 16); Emit-LoadRaxFrame -SlotPosition $slotPosition; Emit-LoadEdxFrame -SlotPosition ($slotPosition + 8); return }
        default { Throw-SourceError -Line $Node.Line -Column $Node.Column -Message 'Internal code-generation error: unsupported string expression node.' }
    }
}
function Emit-WriteCall {
    Emit-LoadRcxFrame -SlotPosition 0x78; Emit-LeaR9Frame -SlotPosition 0x70
    Emit-Win64CallIat -TargetRva ([UInt32]0x3078) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 0 }
    )
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label '__runtime_fail'
}
function Emit-PrintString {
    param([object] $Node)
    Emit-StringExpression -Node $Node; Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xD0)); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2)); Emit-WriteCall
    $newlineItem = Register-DataConstant -Value "`r`n"; Emit-DataAddress -DataItem $newlineItem; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2)); Emit-Bytes -Bytes ([byte[]]@(0x41, 0xB8, 0x02, 0x00, 0x00, 0x00)); Emit-WriteCall
}
function Emit-PrintInteger {
    param([object] $Node)
    Emit-IntegerExpression -Node $Node; $formatItem = Register-DataConstant -Value '%d'; Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC0)); Emit-LeaRcxFrame -SlotPosition 0x30; Emit-DataAddress -DataItem $formatItem; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2)); Emit-CallIat -TargetRva ([UInt32]0x3090)
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x8E -Label '__runtime_fail'; Emit-StoreEaxFrame -SlotPosition 0x74
    Emit-LoadEaxFrame -SlotPosition 0x74; Emit-LeaRdxFrame -SlotPosition 0x30; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x01, 0xC2)); Emit-Bytes -Bytes ([byte[]]@(0xC6, 0x02, 0x0D)); Emit-Bytes -Bytes ([byte[]]@(0xC6, 0x42, 0x01, 0x0A))
    Emit-LoadRcxFrame -SlotPosition 0x78; Emit-LeaRdxFrame -SlotPosition 0x30; Emit-LoadEaxFrame -SlotPosition 0x74; Emit-Bytes -Bytes ([byte[]]@(0x83, 0xC0, 0x02)); Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC0)); Emit-LeaR9Frame -SlotPosition 0x70; Emit-Win64CallIat -TargetRva ([UInt32]0x3078) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 0 }
    ); Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label '__runtime_fail'
}
function Emit-Statement {
    param([object] $Statement)
    switch ($Statement.Kind) {
        'Let' {
            if ($Statement.Type -eq 'Integer') { Emit-IntegerExpression -Node $Statement.Expression; Emit-StoreEaxFrame -SlotPosition (0x80 + ([int]$Statement.Slot * 16)) }
            else { Emit-StringExpression -Node $Statement.Expression; $slot = 0x80 + ([int]$Statement.Slot * 16); Emit-StoreRaxFrame -SlotPosition $slot; Emit-StoreEdxFrame -SlotPosition ($slot + 8) }
            return
        }
        'Assign' {
            if ($Statement.Type -eq 'Integer') { Emit-IntegerExpression -Node $Statement.Expression; Emit-StoreEaxFrame -SlotPosition (0x80 + ([int]$Statement.Slot * 16)) }
            else { Emit-StringExpression -Node $Statement.Expression; $slot = 0x80 + ([int]$Statement.Slot * 16); Emit-StoreRaxFrame -SlotPosition $slot; Emit-StoreEdxFrame -SlotPosition ($slot + 8) }
            return
        }
        'Print' { if ($Statement.Expression.Type -eq 'Integer') { Emit-PrintInteger -Node $Statement.Expression } else { Emit-PrintString -Node $Statement.Expression }; return }
        'Block' { foreach ($child in $Statement.Statements) { Emit-Statement -Statement $child }; return }
        'If' {
            $elseLabel = New-UniqueLabel -Prefix 'if_else'
            $doneLabel = New-UniqueLabel -Prefix 'if_done'
            Emit-IntegerExpression -Node $Statement.Expression
            Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)) # test eax,eax
            if ($Statement.ElseStatements.Count -gt 0) {
                Emit-JumpConditional -ConditionCode 0x84 -Label $elseLabel # jz else
                foreach ($child in $Statement.Statements) { Emit-Statement -Statement $child }
                Emit-Jump -Label $doneLabel
                Mark-CodeLabel -Label $elseLabel
                foreach ($child in $Statement.ElseStatements) { Emit-Statement -Statement $child }
                Mark-CodeLabel -Label $doneLabel
            } else {
                Emit-JumpConditional -ConditionCode 0x84 -Label $doneLabel
                foreach ($child in $Statement.Statements) { Emit-Statement -Statement $child }
                Mark-CodeLabel -Label $doneLabel
            }
            return
        }
        'While' {
            $loopStart = New-UniqueLabel -Prefix 'while_start'
            $loopDone = New-UniqueLabel -Prefix 'while_done'
            Mark-CodeLabel -Label $loopStart
            Emit-IntegerExpression -Node $Statement.Expression
            Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)) # test eax,eax
            Emit-JumpConditional -ConditionCode 0x84 -Label $loopDone # jz done
            foreach ($child in $Statement.Statements) { Emit-Statement -Statement $child }
            Emit-Jump -Label $loopStart
            Mark-CodeLabel -Label $loopDone
            return
        }
        default { Throw-SourceError -Line $Statement.Line -Column $Statement.Column -Message ("Unsupported statement kind '{0}'." -f $Statement.Kind) }
    }
}
function Set-FrameSize {
    param([object] $Context, [int] $NodeCount)
    $Context.TempSlots = [Math]::Max(8, ($NodeCount + 8))
    $Context.ScratchPosition = [int](0x80 + ([int]$Context.SlotCount * 16) + ([int]$Context.TempSlots * 16))
    $required = [int]($Context.ScratchPosition + 0x1010)
    $Context.FrameSize = Align-Up -Value $required -Alignment 0x10
    if ($Context.FrameSize -gt 0x100000) { throw "Function or main frame is too large: $($Context.FrameSize) bytes." }
}
function Emit-StackProbe {
    param([int] $FrameSize)
    if ($FrameSize -le 0 -or ($FrameSize % 16) -ne 0) { throw "Invalid stack-probe frame size: $FrameSize" }
    # Windows x64 uses a special stack-probe helper contract: RAX carries the
    # allocation size; the helper preserves RAX and argument registers, and
    # may clobber only R10, R11, and flags. RSP remains unchanged until it
    # returns, after which the ordinary fixed SUB RSP is unwind-described.
    Emit-Bytes -Bytes ([byte[]]@(0xB8)); Emit-I32 -Value $FrameSize # mov eax,FrameSize
    Emit-Bytes -Bytes ([byte[]]@(0xE8))
    $dispOffset = $script:Code.Count
    Emit-I32 -Value 0
    $script:CodeFixups.Add([pscustomobject]@{ Kind = 'Code'; DispOffset = $dispOffset; Target = '__sharnou_chkstk' })
}
function Emit-Prologue {
    param([object] $Context, [object] $Function = $null)
    $script:ActiveContext = $Context; $script:TempDepth = 0
    $Context | Add-Member -NotePropertyName PrologueSize -NotePropertyValue 0 -Force
    $Context | Add-Member -NotePropertyName StackAllocCodeOffset -NotePropertyValue 0 -Force
    $prologueStart = $script:Code.Count
    Emit-Bytes -Bytes ([byte[]]@(0x55, 0x48, 0x89, 0xE5)) # push rbp; mov rbp,rsp
    Emit-StackProbe -FrameSize ([int]$Context.FrameSize)
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x81, 0xEC)); Emit-I32 -Value $Context.FrameSize # sub rsp,imm32
    $Context.PrologueSize = [int]($script:Code.Count - $prologueStart)
    $Context.StackAllocCodeOffset = $Context.PrologueSize
    if ($Context.PrologueSize -gt 255) { throw "Generated unwind prologue exceeds 255 bytes: $($Context.PrologueSize)." }
    if ($null -ne $Function) {
        if ($Function.Parameters.Count -gt 16) {
            throw "Function '$($Function.Name)' exceeds the supported Windows x64 integer-argument limit of 16."
        }
        for ($i = 0; $i -lt [Math]::Min(4, $Function.Parameters.Count); $i++) {
            $slotPosition = 0x80 + ($i * 16)
            switch ($i) {
                0 { Emit-StoreEcxFrame -SlotPosition $slotPosition }
                1 { Emit-StoreEdxFrame -SlotPosition $slotPosition }
                2 { Emit-StoreR8dFrame -SlotPosition $slotPosition }
                3 { Emit-StoreR9dFrame -SlotPosition $slotPosition }
            }
        }
        # Windows x64 arguments 5..16 are passed in 8-byte stack slots.
        # After PUSH RBP, the first stack argument is at [RBP+0x30].
        for ($i = 4; $i -lt $Function.Parameters.Count; $i++) {
            $slotPosition = 0x80 + ($i * 16)
            $incomingOffset = 0x30 + (($i - 4) * 8)
            Emit-Bytes -Bytes ([byte[]]@(0x8B, 0x85)) # mov eax,dword ptr [rbp+disp32]
            Emit-I32 -Value $incomingOffset
            Emit-StoreEaxFrame -SlotPosition $slotPosition
        }
    }
    Emit-Bytes -Bytes ([byte[]]@(0xB9, 0xF5, 0xFF, 0xFF, 0xFF, 0x48, 0x83, 0xEC, 0x20)); Emit-CallIat -TargetRva ([UInt32]0x3070); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20))
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label '__runtime_fail'
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xF8, 0xFF)); Emit-JumpConditional -ConditionCode 0x84 -Label '__runtime_fail'
    Emit-StoreRaxFrame -SlotPosition 0x78
}
function New-UnwindInfoBytes {
    param([object] $Context)
    $frameSize = [int]$Context.FrameSize
    if ($frameSize -lt 0x1000 -or ($frameSize % 16) -ne 0) { throw "Unwind metadata received an invalid frame size: $frameSize." }
    $allocInfo = if ($frameSize -le 0x7FFF8) { 0 } else { 1 }
    $countOfCodes = if ($allocInfo -eq 0) { 4 } else { 5 }
    $bytes = [System.Collections.Generic.List[byte]]::new()
    $bytes.Add([byte]1) # version 1, flags 0
    $bytes.Add([byte]$Context.PrologueSize)
    $bytes.Add([byte]$countOfCodes)
    $bytes.Add([byte]0x05) # frame register RBP, frame offset 0
    $bytes.Add([byte]$Context.StackAllocCodeOffset)
    $bytes.Add([byte](($allocInfo -shl 4) -bor 0x01)) # UWOP_ALLOC_LARGE
    if ($allocInfo -eq 0) {
        $scaledSize = [UInt16]($frameSize / 8)
        $bytes.AddRange([BitConverter]::GetBytes($scaledSize))
    } else {
        $bytes.AddRange([BitConverter]::GetBytes([UInt32]$frameSize))
    }
    $bytes.Add([byte]4); $bytes.Add([byte]0x03) # UWOP_SET_FPREG
    $bytes.Add([byte]1); $bytes.Add([byte]0x50) # UWOP_PUSH_NONVOL RBP
    if (($countOfCodes % 2) -ne 0) { $bytes.Add([byte]0); $bytes.Add([byte]0) }
    return ,$bytes.ToArray()
}
function Emit-Epilogue { Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8D, 0x65, 0x00, 0x5D, 0xC3)) } # lea rsp,[rbp+0]; pop rbp; ret (legal x64 epilogue)
function Test-ImageBasic {
    param([byte[]] $Image)
    if ($Image.Length -lt 0x400 -or $Image[0] -ne 0x4D -or $Image[1] -ne 0x5A) { throw 'Internal linker validation: invalid DOS header.' }
    $pe = [BitConverter]::ToInt32($Image, 0x3C)
    if ($pe -lt 0 -or ($pe + 24) -gt $Image.Length -or $Image[$pe] -ne 0x50 -or $Image[$pe + 1] -ne 0x45) { throw 'Internal linker validation: invalid PE header/signature.' }
    if ([BitConverter]::ToUInt16($Image, $pe + 4) -ne 0x8664) { throw 'Internal linker validation: target machine is not AMD64.' }
    if ([BitConverter]::ToUInt16($Image, $pe + 24) -ne 0x020B) { throw 'Internal linker validation: optional header is not PE32+.' }
    $count = [BitConverter]::ToUInt16($Image, $pe + 6); if ($count -ne 6) { throw "Internal linker validation: expected six sections, found $count." }
    $table = $pe + 24 + [BitConverter]::ToUInt16($Image, $pe + 20)
    if (($table + ($count * 40)) -gt [BitConverter]::ToUInt32($Image, $pe + 24 + 60)) { throw 'Internal linker validation: section headers exceed SizeOfHeaders.' }
    $optional = $pe + 24
    $optionalSize = [BitConverter]::ToUInt16($Image, $pe + 20)
    $sectionTable = $optional + $optionalSize
    $rdataSection = $null
    $relocSection = $null
    for ($sectionIndex = 0; $sectionIndex -lt $count; $sectionIndex++) {
        $header = $sectionTable + ($sectionIndex * 40)
        $sectionName = [System.Text.Encoding]::ASCII.GetString($Image, $header, 8).Trim([char[]]@(0))
        $section = [pscustomobject]@{
            Name = $sectionName
            VirtualSize = [UInt32][BitConverter]::ToUInt32($Image, $header + 8)
            Rva = [UInt32][BitConverter]::ToUInt32($Image, $header + 12)
            RawSize = [UInt32][BitConverter]::ToUInt32($Image, $header + 16)
            RawPointer = [UInt32][BitConverter]::ToUInt32($Image, $header + 20)
        }
        if ($sectionName -eq '.rdata') { $rdataSection = $section }
        if ($sectionName -eq '.reloc') { $relocSection = $section }
    }
    $relocRva = [UInt32][BitConverter]::ToUInt32($Image, $optional + 152)
    $relocSize = [UInt32][BitConverter]::ToUInt32($Image, $optional + 156)
    if ($null -eq $rdataSection -or $null -eq $relocSection -or $relocRva -ne $relocSection.Rva -or $relocSize -lt 12 -or $relocSize -gt $relocSection.VirtualSize) {
        throw 'Internal linker validation: base relocation directory or containing section is missing/malformed.'
    }
    $relocFileOffset = [UInt64]$relocSection.RawPointer
    if (($relocFileOffset + $relocSize) -gt [UInt64]$Image.Length -or $relocSize -gt $relocSection.RawSize) {
        throw 'Internal linker validation: base relocation directory is not backed by file data.'
    }
    $relocBytes = [byte[]]::new([int]$relocSize)
    [System.Buffer]::BlockCopy($Image, [int]$relocFileOffset, $relocBytes, 0, [int]$relocSize)
    $allowedRanges = @([pscustomobject]@{ StartRva = $rdataSection.Rva; Size = $rdataSection.VirtualSize })
    $relocationResult = Test-SharnouBaseRelocationDirectory -Bytes $relocBytes -ImageSize ([UInt32][BitConverter]::ToUInt32($Image, $optional + 56)) -AllowedRanges $allowedRanges -ExpectedTargetRvas $script:ExpectedRelocationTargetRvas
    if (-not ($relocationResult.TargetRvas -contains [UInt32]$rdataSection.Rva)) {
        throw 'Internal linker validation: .rdata absolute entry-point anchor has no DIR64 relocation.'
    }
    $exceptionRva = [BitConverter]::ToUInt32($Image, $optional + 136)
    $exceptionSize = [BitConverter]::ToUInt32($Image, $optional + 140)
    if ($exceptionRva -eq 0 -or $exceptionSize -lt 12 -or ($exceptionSize % 12) -ne 0) {
        throw 'Internal linker validation: x64 exception/unwind directory is missing or malformed.'
    }
}

if (-not [Environment]::Is64BitOperatingSystem) { throw 'The Sharnou compiler emits x64 PE32+ executables and requires 64-bit Windows.' }
$sourceItem = Get-Item -LiteralPath $Source -ErrorAction Stop
if ($sourceItem.PSIsContainer) { throw "Source path is not a file: $Source" }
$sourceFullPath = $sourceItem.FullName; $outputFullPath = [System.IO.Path]::GetFullPath($Output)
if ([string]::Equals($sourceFullPath, $outputFullPath, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'The output path must not overwrite the source file.' }
if (Test-Path -LiteralPath $outputFullPath) { Remove-Item -LiteralPath $outputFullPath -Force }

$script:Functions = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
$script:Builtins = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
$builtinDefinitions = @(
    [pscustomobject]@{ Name = 'sh_abi_nonvolatile_probe'; Builtin = 'AbiNonvolatileProbe'; ParameterTypes = @(); ReturnType = 'Integer' },
    [pscustomobject]@{ Name = 'sh_string_length'; Builtin = 'StringLength'; ParameterTypes = @('String'); ReturnType = 'Integer' },
    [pscustomobject]@{ Name = 'sh_string_equal'; Builtin = 'StringEqual'; ParameterTypes = @('String', 'String'); ReturnType = 'Integer' },
    [pscustomobject]@{ Name = 'sh_log'; Builtin = 'Log'; ParameterTypes = @('String'); ReturnType = 'Integer' },
    [pscustomobject]@{ Name = 'sh_memory_fill'; Builtin = 'MemoryFill'; ParameterTypes = @('Integer', 'Integer'); ReturnType = 'Integer' },
    [pscustomobject]@{ Name = 'sh_memory_byte_at'; Builtin = 'MemoryByteAt'; ParameterTypes = @('Integer'); ReturnType = 'Integer' },
    [pscustomobject]@{ Name = 'sh_file_exists'; Builtin = 'FileExists'; ParameterTypes = @('String'); ReturnType = 'Integer' },
    [pscustomobject]@{ Name = 'sh_file_size'; Builtin = 'FileSize'; ParameterTypes = @('String'); ReturnType = 'Integer' },
    [pscustomobject]@{ Name = 'sh_asset_read_count'; Builtin = 'AssetReadCount'; ParameterTypes = @('String', 'Integer'); ReturnType = 'Integer' },
    [pscustomobject]@{ Name = 'sh_asset_read_byte'; Builtin = 'AssetReadByte'; ParameterTypes = @('String', 'Integer'); ReturnType = 'Integer' },
    [pscustomobject]@{ Name = 'sh_window_probe'; Builtin = 'WindowProbe'; ParameterTypes = @('String'); ReturnType = 'Integer' },
    [pscustomobject]@{ Name = 'sh_window_pump_once'; Builtin = 'WindowPump'; ParameterTypes = @(); ReturnType = 'Integer' },
    [pscustomobject]@{ Name = 'sh_thread_sync_probe'; Builtin = 'ThreadSyncProbe'; ParameterTypes = @(); ReturnType = 'Integer' },
    [pscustomobject]@{ Name = 'sh_d3d11_render_demo'; Builtin = 'D3D11RenderDemo'; ParameterTypes = @('String', 'Integer'); ReturnType = 'Integer' }
)
if ($EnableDevAgentTools) {
    $builtinDefinitions += [pscustomobject]@{ Name = 'sh_dev_run_tool'; Builtin = 'DevRunTool'; ParameterTypes = @('Integer', 'Integer'); ReturnType = 'Integer' }
}
if ($EnableWin64CallbackTests) {
    $builtinDefinitions += [pscustomobject]@{ Name = 'sh_win64_callback_abi_probe'; Builtin = 'Win64CallbackProbe'; ParameterTypes = @(); ReturnType = 'Integer' }
}
foreach ($definition in $builtinDefinitions) { $script:Builtins.Add($definition.Name, $definition) }
$script:Modules = [System.Collections.Generic.List[object]]::new()
$script:ModuleMap = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
$script:FunctionIndex = 0
$script:SourceDisplay = $sourceFullPath
$rootModule = Load-Module -Path $sourceFullPath -IsRoot $true
foreach ($module in $script:Modules) { $script:SourceDisplay = $module.Path; Collect-FunctionHeaders -Module $module }

$script:MainStatements = [System.Collections.Generic.List[object]]::new()
$script:MainContext = [pscustomobject]@{ Name = '__entry'; SlotCount = 0; TempSlots = 0; ScratchPosition = 0; FrameSize = 0; Statements = $script:MainStatements }
$script:Scopes = [System.Collections.Generic.List[object]]::new(); Push-Scope
$script:ActiveContext = $script:MainContext; $script:CurrentFunction = $null; $script:BlockDepth = 0
foreach ($module in $script:Modules) { Parse-Module -Module $module }

Set-FrameSize -Context $script:MainContext -NodeCount (Get-StatementsNodeCount -Statements $script:MainStatements.ToArray())
foreach ($functionObject in $script:Functions.Values) {
    if ($null -eq $functionObject.Context) { throw "Function '$($functionObject.Name)' was declared but not parsed." }
    Set-FrameSize -Context $functionObject.Context -NodeCount (Get-StatementsNodeCount -Statements $functionObject.BodyStatements -ReturnExpression $functionObject.ReturnExpression)
}

$script:Code = [System.Collections.Generic.List[byte]]::new()
$script:CodeFixups = [System.Collections.Generic.List[object]]::new()
$script:CodeLabels = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::Ordinal)
$script:DataItems = [System.Collections.Generic.List[object]]::new()
$script:DataMap = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
$script:DataPointerFixups = [System.Collections.Generic.List[object]]::new()
$script:DataLength = 8 # reserved absolute entry-point anchor, patched by the base-relocation directory
$script:UniqueLabel = 0

# Entry point: main code owns a stack frame; every function gets its own frame.
Mark-CodeLabel -Label '__entry'
Emit-Prologue -Context $script:MainContext
foreach ($statement in $script:MainStatements) { Emit-Statement -Statement $statement }
Emit-Bytes -Bytes ([byte[]]@(0x31, 0xC9, 0x48, 0x83, 0xEC, 0x20)); Emit-CallIat -TargetRva ([UInt32]0x3080); Emit-Bytes -Bytes ([byte[]]@(0xCC))
Mark-CodeLabel -Label '__runtime_fail'
Emit-Bytes -Bytes ([byte[]]@(0xB9, 0x01, 0x00, 0x00, 0x00, 0x48, 0x83, 0xEC, 0x20)); Emit-CallIat -TargetRva ([UInt32]0x3080); Emit-Bytes -Bytes ([byte[]]@(0xCC))

foreach ($functionObject in ($script:Functions.Values | Sort-Object Index)) {
    Mark-CodeLabel -Label $functionObject.Label
    Emit-Prologue -Context $functionObject.Context -Function $functionObject
    foreach ($statement in $functionObject.BodyStatements) { Emit-Statement -Statement $statement }
    $script:ActiveContext = $functionObject.Context; $script:TempDepth = 0
    Emit-IntegerExpression -Node $functionObject.ReturnExpression
    Emit-Epilogue
}
# Windows x64 stack-probe helper. This is a leaf routine using only R10/R11
# and flags; RAX (the requested allocation size), argument registers, RSP, and
# all nonvolatile registers are preserved. Leaf routines require no .pdata row.
$stackProbeOffset = [int]$script:Code.Count
Mark-CodeLabel -Label '__sharnou_chkstk'
Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xE2)) # mov r10,rsp (includes the call return address)
Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC3)) # mov r11,rax
Emit-Bytes -Bytes ([byte[]]@(0x49, 0x83, 0xEB, 0x08)) # sub r11,8 (adjust for the call return address)
$probeLoopLabel = New-UniqueLabel -Prefix 'chkstk_loop'
$probeTailLabel = New-UniqueLabel -Prefix 'chkstk_tail'
$probeDoneLabel = New-UniqueLabel -Prefix 'chkstk_done'
Mark-CodeLabel -Label $probeLoopLabel
Emit-Bytes -Bytes ([byte[]]@(0x49, 0x81, 0xFB, 0x00, 0x10, 0x00, 0x00)) # cmp r11,1000h
Emit-JumpConditional -ConditionCode 0x82 -Label $probeTailLabel
Emit-Bytes -Bytes ([byte[]]@(0x49, 0x81, 0xEA, 0x00, 0x10, 0x00, 0x00)) # sub r10,1000h
Emit-Bytes -Bytes ([byte[]]@(0x41, 0xF6, 0x02, 0x00)) # test byte ptr [r10],0
Emit-Bytes -Bytes ([byte[]]@(0x49, 0x81, 0xEB, 0x00, 0x10, 0x00, 0x00)) # sub r11,1000h
Emit-Jump -Label $probeLoopLabel
Mark-CodeLabel -Label $probeTailLabel
Emit-Bytes -Bytes ([byte[]]@(0x4D, 0x85, 0xDB)) # test r11,r11
Emit-JumpConditional -ConditionCode 0x84 -Label $probeDoneLabel
Emit-Bytes -Bytes ([byte[]]@(0x4D, 0x29, 0xDA)) # sub r10,r11
Emit-Bytes -Bytes ([byte[]]@(0x41, 0xF6, 0x02, 0x00)) # test byte ptr [r10],0
Mark-CodeLabel -Label $probeDoneLabel
Emit-Bytes -Bytes ([byte[]]@(0xC3)) # ret; RAX is deliberately unchanged

# WINAPI thread callback used by the thread/synchronization smoke-test intrinsic.
$workerOffset = [int]$script:Code.Count
Mark-CodeLabel -Label '__sharnou_worker'
Emit-Bytes -Bytes ([byte[]]@(0x31, 0xC0, 0xC3)) # return DWORD 0

# Explicit Win64 callback ABI probes are leaf functions. The first probe uses
# the exact SERVICE_MAIN_FUNCTIONW parameter widths; the second uses the exact
# HANDLER_FUNCTION_EX four-register layout. They preserve all nonvolatile state.
if ($script:DataPointerFixups.Count -gt 0) {
    $callbackMarker = [byte[]]@(0xDE, 0xC0, 0xA7, 0x51)

    Mark-CodeLabel -Label '__r51_service_main_abi_probe'
    $serviceMainFail = New-UniqueLabel -Prefix 'service_main_abi_fail'
    Emit-Bytes -Bytes ([byte[]]@(0x81, 0xF9, 0xDF, 0x9B, 0x57, 0x13)) # cmp ecx,13579BDFh
    Emit-JumpConditional -ConditionCode 0x85 -Label $serviceMainFail
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xD2)) # test rdx,rdx; require non-null LPWSTR*.
    Emit-JumpConditional -ConditionCode 0x84 -Label $serviceMainFail
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0xB8))
    $script:Code.AddRange([BitConverter]::GetBytes([UInt64]::Parse('0000000051A7C0DE', [System.Globalization.NumberStyles]::HexNumber)))
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0x02)) # write a test LPWSTR value into argv[0].
    Emit-Bytes -Bytes ([byte[]]@(0x31, 0xC0, 0xC3)) # VOID callback; return value is intentionally ignored.
    Mark-CodeLabel -Label $serviceMainFail
    Emit-Bytes -Bytes ([byte[]]@(0x31, 0xC0, 0xC3))

    Mark-CodeLabel -Label '__r51_handler_ex_abi_probe'
    $handlerExFail = New-UniqueLabel -Prefix 'handler_ex_abi_fail'
    Emit-Bytes -Bytes ([byte[]]@(0x81, 0xF9, 0x78, 0x56, 0x34, 0x12)) # cmp ecx,12345678h
    Emit-JumpConditional -ConditionCode 0x85 -Label $handlerExFail
    Emit-Bytes -Bytes ([byte[]]@(0x81, 0xFA, 0x21, 0x43, 0x65, 0x87)) # cmp edx,87654321h
    Emit-JumpConditional -ConditionCode 0x85 -Label $handlerExFail
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0xB8))
    $script:Code.AddRange([BitConverter]::GetBytes([UInt64]::Parse('1122334455667788', [System.Globalization.NumberStyles]::HexNumber)))
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x39, 0xC0)) # cmp r8,rax (full-width LPVOID).
    Emit-JumpConditional -ConditionCode 0x85 -Label $handlerExFail
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0xB8))
    $script:Code.AddRange([BitConverter]::GetBytes([UInt64]::Parse('8877665544332211', [System.Globalization.NumberStyles]::HexNumber)))
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x39, 0xC1)) # cmp r9,rax (full-width LPVOID).
    Emit-JumpConditional -ConditionCode 0x85 -Label $handlerExFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8)); $script:Code.AddRange($callbackMarker); Emit-Bytes -Bytes ([byte[]]@(0xC3))
    Mark-CodeLabel -Label $handlerExFail
    Emit-Bytes -Bytes ([byte[]]@(0x31, 0xC0, 0xC3))
}

# The stack-probe helper and worker/callback probes are true leaf routines and
# need no RUNTIME_FUNCTION rows. Frame-owning functions retain x64 unwind data.
$orderedFunctions = @($script:Functions.Values | Sort-Object Index)
$runtimeFunctionSpecs = [System.Collections.Generic.List[object]]::new()
$entryEndOffset = if ($orderedFunctions.Count -gt 0) { [int]$script:CodeLabels[$orderedFunctions[0].Label] } else { $stackProbeOffset }
$runtimeFunctionSpecs.Add([pscustomobject]@{ StartOffset = [int]$script:CodeLabels['__entry']; EndOffset = $entryEndOffset; Context = $script:MainContext; UnwindBytes = $null; UnwindOffset = 0 })
for ($functionIndex = 0; $functionIndex -lt $orderedFunctions.Count; $functionIndex++) {
    $functionObject = $orderedFunctions[$functionIndex]
    $startOffset = [int]$script:CodeLabels[$functionObject.Label]
    $endOffset = if (($functionIndex + 1) -lt $orderedFunctions.Count) { [int]$script:CodeLabels[$orderedFunctions[$functionIndex + 1].Label] } else { $stackProbeOffset }
    if ($endOffset -le $startOffset) { throw "Invalid generated function range for '$($functionObject.Name)'." }
    $runtimeFunctionSpecs.Add([pscustomobject]@{ StartOffset = $startOffset; EndOffset = $endOffset; Context = $functionObject.Context; UnwindBytes = $null; UnwindOffset = 0 })
}
foreach ($runtimeFunction in $runtimeFunctionSpecs) {
    $runtimeFunction.UnwindBytes = New-UnwindInfoBytes -Context $runtimeFunction.Context
}
$xdataLength = 0
foreach ($runtimeFunction in $runtimeFunctionSpecs) {
    $xdataLength = Align-Up -Value $xdataLength -Alignment 4
    $runtimeFunction.UnwindOffset = $xdataLength
    $xdataLength += $runtimeFunction.UnwindBytes.Length
}
$pdataLength = $runtimeFunctionSpecs.Count * 12
if ($pdataLength -le 0 -or $xdataLength -le 0) { throw 'Generated PE unwind tables cannot be empty.' }

$codeBytes = $script:Code.ToArray()
if ($codeBytes.Length -le 0) { throw 'Generated .text section is empty.' }
if ($codeBytes.Length -gt 0x01000000) { throw "Generated .text section is too large: $($codeBytes.Length) bytes; maximum is 16777216." }

# Size each virtual section to a full 4 KiB page and place later sections after it.
# This keeps the legacy RVAs for small code while allowing .text to grow beyond 4096 bytes.
$textRva = [UInt32]0x1000
$textVirtualSpan = Align-Up -Value $codeBytes.Length -Alignment 0x1000
if ($script:DataLength -gt 0x1000) { throw "Generated .rdata section is too large: $($script:DataLength) bytes; maximum is 4096." }
$dataVirtualSpan = Align-Up -Value ([Math]::Max(8, $script:DataLength)) -Alignment 0x1000
$idataVirtualSpan = Align-Up -Value 0x1000 -Alignment 0x1000
$dataRva = [UInt32]([long]$textRva + [long]$textVirtualSpan)
$relocationImageBoundary = [UInt32]([long]$dataRva + [long]$dataVirtualSpan)
$relocationTargets = [System.Collections.Generic.List[UInt32]]::new()
$relocationTargets.Add($dataRva) # Existing .rdata absolute entry-point anchor.
foreach ($callbackFixup in $script:DataPointerFixups) {
    if (-not $script:CodeLabels.ContainsKey([string]$callbackFixup.Label)) {
        throw "Unresolved typed callback code label: $($callbackFixup.Label)"
    }
    $callbackOffset = [Int64]$script:CodeLabels[[string]$callbackFixup.Label]
    if ($callbackOffset -lt 0 -or $callbackOffset -ge $codeBytes.Length) {
        throw "Typed callback target is outside .text: $($callbackFixup.Label)"
    }
    $callbackFixup.TargetRva = [UInt32]([Int64]$textRva + $callbackOffset)
    $pointerRva = [UInt64]$dataRva + [UInt64]$callbackFixup.DataItem.Offset
    if ($pointerRva -gt [UInt32]::MaxValue) { throw 'Typed callback pointer data RVA exceeds the PE RVA range.' }
    $relocationTargets.Add([UInt32]$pointerRva)
}
$script:ExpectedRelocationTargetRvas = [UInt32[]]@($relocationTargets)
$relocationDirectory = New-SharnouBaseRelocationDirectory -TargetRvas $script:ExpectedRelocationTargetRvas -ImageSize $relocationImageBoundary -AllowedRanges @([pscustomobject]@{ StartRva = $dataRva; Size = [Math]::Max(8, $script:DataLength) })
$relocVirtualSpan = Align-Up -Value $relocationDirectory.DirectorySize -Alignment 0x1000
$pdataVirtualSpan = Align-Up -Value $pdataLength -Alignment 0x1000
$xdataVirtualSpan = Align-Up -Value $xdataLength -Alignment 0x1000
$idataRva = [UInt32]([long]$dataRva + [long]$dataVirtualSpan)
$relocRva = [UInt32]([long]$idataRva + [long]$idataVirtualSpan)
$pdataRva = [UInt32]([long]$relocRva + [long]$relocVirtualSpan)
$xdataRva = [UInt32]([long]$pdataRva + [long]$pdataVirtualSpan)
$sizeOfImage = [UInt32]([long]$xdataRva + [long]$xdataVirtualSpan)
if ([UInt64]$sizeOfImage -gt [UInt32]::MaxValue) { throw 'Linked image exceeds the PE32+ 32-bit RVA address space.' }

# Build sorted x64 RUNTIME_FUNCTION entries and their 4-byte-aligned UNWIND_INFO records.
$pdataBytes = [byte[]]::new($pdataLength)
$xdataBytes = [byte[]]::new($xdataLength)
for ($runtimeIndex = 0; $runtimeIndex -lt $runtimeFunctionSpecs.Count; $runtimeIndex++) {
    $runtimeFunction = $runtimeFunctionSpecs[$runtimeIndex]
    $recordOffset = $runtimeIndex * 12
    Set-U32 -Buffer $pdataBytes -Offset $recordOffset -Value ([UInt32]([long]$textRva + [long]$runtimeFunction.StartOffset))
    Set-U32 -Buffer $pdataBytes -Offset ($recordOffset + 4) -Value ([UInt32]([long]$textRva + [long]$runtimeFunction.EndOffset))
    Set-U32 -Buffer $pdataBytes -Offset ($recordOffset + 8) -Value ([UInt32]([long]$xdataRva + [long]$runtimeFunction.UnwindOffset))
    [System.Buffer]::BlockCopy($runtimeFunction.UnwindBytes, 0, $xdataBytes, $runtimeFunction.UnwindOffset, $runtimeFunction.UnwindBytes.Length)
}

# Patch RIP-relative data references, IAT calls, conditional branches, and internal rel32 calls.
foreach ($fixup in $script:CodeFixups) {
    if ($fixup.Kind -eq 'Data') { $targetRva = [long]$dataRva + [long]$fixup.Target.Offset }
    elseif ($fixup.Kind -eq 'Iat') { $targetRva = [long]$idataRva + [long]$fixup.TargetOffset }
    elseif ($fixup.Kind -eq 'Code' -or $fixup.Kind -eq 'Call') {
        if (-not $script:CodeLabels.ContainsKey([string]$fixup.Target)) { throw "Unresolved internal linker symbol: $($fixup.Target)" }
        $targetRva = [long]$textRva + [long]$script:CodeLabels[[string]$fixup.Target]
    } else { throw "Unknown code fixup kind: $($fixup.Kind)" }
    $nextRva = [long]0x1000 + [long]$fixup.DispOffset + 4; $displacement = $targetRva - $nextRva
    if ($displacement -lt [int]::MinValue -or $displacement -gt [int]::MaxValue) { throw "RIP-relative/call displacement is out of range: $displacement" }
    $dispBytes = [BitConverter]::GetBytes([int32]$displacement)
    for ($j = 0; $j -lt 4; $j++) { $script:Code[$fixup.DispOffset + $j] = $dispBytes[$j] }
}
$codeBytes = $script:Code.ToArray()
$dataBytes = [byte[]]::new([Math]::Max(8, $script:DataLength))
# Relocated pointer used by the linker's relocation/verification self-check.
Set-U64 -Buffer $dataBytes -Offset 0 -Value ([UInt64]([Int64]0x140001000))
foreach ($callbackFixup in $script:DataPointerFixups) {
    if ($callbackFixup.DataItem.Bytes.Length -ne 8 -or $callbackFixup.TargetRva -eq 0) {
        throw "Typed callback pointer fixup is incomplete: $($callbackFixup.Key)"
    }
    $callbackVa = [UInt64]([UInt64]0x140000000 + [UInt64]$callbackFixup.TargetRva)
    Set-U64 -Buffer $callbackFixup.DataItem.Bytes -Offset 0 -Value $callbackVa
}
foreach ($item in $script:DataItems) { if ($item.Bytes.Length -gt 0) { Set-Bytes -Buffer $dataBytes -Offset $item.Offset -Bytes $item.Bytes } }

# Dynamically sized RVA layout and independently aligned raw file layout: .text/.rdata/.idata/.reloc.
$textRawSize = Align-Up -Value $codeBytes.Length -Alignment 0x200
$dataRawSize = Align-Up -Value $dataBytes.Length -Alignment 0x200
# Milestone 5 import builder. Existing IAT offsets (0x70, 0x78, 0x80, and 0x90)
# stay stable within .idata. Lookup tables use the disjoint 0x500-0x610 range;
# no lookup table may overlap any IAT slot or import-by-name string. Emit-CallIat rebases target RVAs after section placement.
$idata = [byte[]]::new(0x1000)
# Import descriptors have a dedicated .idata range, disjoint from lookups, IAT and names.
$descriptorBase = 0xA00
$importDirectorySize = 0x190
if (($descriptorBase + $importDirectorySize) -gt $idata.Length) { throw 'Import descriptor table exceeds .idata storage.' }
$importSets = @(
    [pscustomobject]@{ Descriptor = 0x00; Lookup = 0xC00; Iat = 0x70; Dll = 'KERNEL32.dll'; Names = @('GetStdHandle', 'WriteFile', 'ExitProcess') },
    [pscustomobject]@{ Descriptor = 0x14; Lookup = 0xC20; Iat = 0x90; Dll = 'USER32.dll'; Names = @('wsprintfA') },
    [pscustomobject]@{ Descriptor = 0x28; Lookup = 0xC30; Iat = 0xA0; Dll = 'KERNEL32.dll'; Names = @('CreateFileA', 'GetFileSizeEx', 'ReadFile', 'CloseHandle', 'GetModuleHandleA', 'CreateThread', 'WaitForSingleObject', 'CreateMutexA', 'ReleaseMutex') },
    [pscustomobject]@{ Descriptor = 0x3C; Lookup = 0xC80; Iat = 0xF0; Dll = 'USER32.dll'; Names = @('CreateWindowExA', 'ShowWindow', 'UpdateWindow', 'PeekMessageA', 'TranslateMessage', 'DispatchMessageA', 'DestroyWindow') },
    [pscustomobject]@{ Descriptor = 0x50; Lookup = 0xCC0; Iat = 0x130; Dll = 'D3D11.dll'; Names = @('D3D11CreateDeviceAndSwapChain') },
    [pscustomobject]@{ Descriptor = 0x64; Lookup = 0xCD0; Iat = 0x140; Dll = 'DXGI.dll'; Names = @('CreateDXGIFactory') },
    [pscustomobject]@{ Descriptor = 0x78; Lookup = 0xCE0; Iat = 0x150; Dll = 'KERNEL32.dll'; Names = @('QueryPerformanceCounter', 'QueryPerformanceFrequency') },
    [pscustomobject]@{ Descriptor = 0x8C; Lookup = 0xCF8; Iat = 0x168; Dll = 'USER32.dll'; Names = @('IsWindow') },
    [pscustomobject]@{ Descriptor = 0xA0; Lookup = 0xD08; Iat = 0x178; Dll = 'KERNEL32.dll'; Names = @('GetSystemDirectoryA', 'GetCurrentDirectoryA', 'CreateProcessA', 'CreateJobObjectA', 'SetInformationJobObject', 'AssignProcessToJobObject', 'ResumeThread', 'TerminateJobObject', 'GetExitCodeProcess', 'TerminateProcess', 'GetFileAttributesA', 'VirtualAlloc', 'VirtualFree') },
    [pscustomobject]@{ Descriptor = 0xB4; Lookup = 0xD78; Iat = 0x1E8; Dll = 'BCRYPT.dll'; Names = @('BCryptOpenAlgorithmProvider', 'BCryptHash', 'BCryptCloseAlgorithmProvider') },
    [pscustomobject]@{ Descriptor = 0xC8; Lookup = 0xD98; Iat = 0x208; Dll = 'KERNEL32.dll'; Names = @('GetFileInformationByHandle') },
    [pscustomobject]@{ Descriptor = 0xDC; Lookup = 0xDA8; Iat = 0x218; Dll = 'KERNEL32.dll'; Names = @('GetModuleFileNameA', 'SetCurrentDirectoryA') },
    [pscustomobject]@{ Descriptor = 0xF0; Lookup = 0xDC0; Iat = 0x230; Dll = 'KERNEL32.dll'; Names = @('CreatePipe', 'SetHandleInformation', 'PeekNamedPipe', 'InitializeProcThreadAttributeList', 'UpdateProcThreadAttribute', 'DeleteProcThreadAttributeList', 'LocalFree', 'GetLastError') },
    [pscustomobject]@{ Descriptor = 0x104; Lookup = 0xE08; Iat = 0x278; Dll = 'USERENV.dll'; Names = @('CreateAppContainerProfile', 'DeriveAppContainerSidFromAppContainerName') },
    [pscustomobject]@{ Descriptor = 0x118; Lookup = 0xE20; Iat = 0x290; Dll = 'ADVAPI32.dll'; Names = @('GetNamedSecurityInfoA', 'SetEntriesInAclA', 'SetNamedSecurityInfoA', 'FreeSid', 'OpenProcessToken', 'CreateRestrictedToken', 'CreateProcessAsUserA', 'GetSecurityInfo', 'SetSecurityInfo', 'GetTokenInformation', 'GetSecurityDescriptorDacl', 'GetSecurityDescriptorSacl', 'GetSecurityDescriptorLength', 'IsValidSecurityDescriptor') },
    [pscustomobject]@{ Descriptor = 0x12C; Lookup = 0xE98; Iat = 0x308; Dll = 'KERNEL32.dll'; Names = @('GetFullPathNameA', 'DeleteFileA', 'MoveFileExA', 'FlushFileBuffers') },
    [pscustomobject]@{ Descriptor = 0x140; Lookup = 0xEC0; Iat = 0x330; Dll = 'BCRYPT.dll'; Names = @('BCryptGenRandom') },
    [pscustomobject]@{ Descriptor = 0x154; Lookup = 0xED0; Iat = 0x340; Dll = 'USERENV.dll'; Names = @('DeleteAppContainerProfile') },
    [pscustomobject]@{ Descriptor = 0x168; Lookup = 0xEE0; Iat = 0x350; Dll = 'ADVAPI32.dll'; Names = @('EqualSid') }
)
if (($descriptorBase + $importDirectorySize) -gt $idata.Length) { throw 'Import descriptor table exceeds .idata storage.' }
$apiNameRvas = @{}
$nameCursor = 0x3A0
foreach ($set in $importSets) {
    foreach ($apiName in $set.Names) {
        if (-not $apiNameRvas.ContainsKey($apiName)) {
            $apiNameRvas[$apiName] = [UInt32]([long]$idataRva + [long]$nameCursor)
            Set-U16 -Buffer $idata -Offset $nameCursor -Value 0
            Set-AsciiZ -Buffer $idata -Offset ($nameCursor + 2) -Value $apiName
            $nameCursor += 2 + [System.Text.Encoding]::ASCII.GetByteCount($apiName) + 1
            if (($nameCursor % 2) -ne 0) { $nameCursor++ }
        }
    }
}
if ($nameCursor -gt $descriptorBase) {
    throw ("Import-by-name strings overlap the import descriptor table: end=0x{0:X}, descriptorBase=0x{1:X}." -f $nameCursor, $descriptorBase)
}
Set-AsciiZ -Buffer $idata -Offset 0xF00 -Value 'KERNEL32.dll'
Set-AsciiZ -Buffer $idata -Offset 0xF10 -Value 'USER32.dll'
Set-AsciiZ -Buffer $idata -Offset 0xF20 -Value 'D3D11.dll'
Set-AsciiZ -Buffer $idata -Offset 0xF30 -Value 'DXGI.dll'
Set-AsciiZ -Buffer $idata -Offset 0xF40 -Value 'BCRYPT.dll'
Set-AsciiZ -Buffer $idata -Offset 0xF50 -Value 'USERENV.dll'
Set-AsciiZ -Buffer $idata -Offset 0xF60 -Value 'ADVAPI32.dll'
foreach ($set in $importSets) {
    switch ($set.Dll) {
        'KERNEL32.dll' { $nameOffset = 0xF00 }
        'USER32.dll' { $nameOffset = 0xF10 }
        'D3D11.dll' { $nameOffset = 0xF20 }
        'DXGI.dll' { $nameOffset = 0xF30 }
        'BCRYPT.dll' { $nameOffset = 0xF40 }
        'USERENV.dll' { $nameOffset = 0xF50 }
        'ADVAPI32.dll' { $nameOffset = 0xF60 }
        default { throw "Internal linker error: unsupported import DLL '$($set.Dll)'" }
    }
        $descriptorOffset = [int]($descriptorBase + $set.Descriptor)
    Set-U32 -Buffer $idata -Offset $descriptorOffset -Value ([UInt32]([long]$idataRva + [long]$set.Lookup))
    Set-U32 -Buffer $idata -Offset ($descriptorOffset + 4) -Value 0
    Set-U32 -Buffer $idata -Offset ($descriptorOffset + 8) -Value 0
    Set-U32 -Buffer $idata -Offset ($descriptorOffset + 12) -Value ([UInt32]([long]$idataRva + [long]$nameOffset))
    Set-U32 -Buffer $idata -Offset ($descriptorOffset + 16) -Value ([UInt32]([long]$idataRva + [long]$set.Iat))
    for ($apiIndex = 0; $apiIndex -lt $set.Names.Count; $apiIndex++) {
        $hintRva = [UInt64]$apiNameRvas[$set.Names[$apiIndex]]
        Set-U64 -Buffer $idata -Offset ($set.Lookup + ($apiIndex * 8)) -Value ([UInt64]$hintRva)
        Set-U64 -Buffer $idata -Offset ($set.Iat + ($apiIndex * 8)) -Value ([UInt64]$hintRva)
    }
}
$script:StdLibIatOffsets = @{
    'GetStdHandle' = [UInt32]0x70; 'WriteFile' = [UInt32]0x78; 'ExitProcess' = [UInt32]0x80; 'wsprintfA' = [UInt32]0x90
    'CreateFileA' = [UInt32]0xA0; 'GetFileSizeEx' = [UInt32]0xA8; 'ReadFile' = [UInt32]0xB0; 'CloseHandle' = [UInt32]0xB8
    'GetModuleHandleA' = [UInt32]0xC0; 'CreateThread' = [UInt32]0xC8; 'WaitForSingleObject' = [UInt32]0xD0; 'CreateMutexA' = [UInt32]0xD8
    'ReleaseMutex' = [UInt32]0xE0; 'CreateWindowExA' = [UInt32]0xF0; 'ShowWindow' = [UInt32]0xF8; 'UpdateWindow' = [UInt32]0x100
    'PeekMessageA' = [UInt32]0x108; 'TranslateMessage' = [UInt32]0x110; 'DispatchMessageA' = [UInt32]0x118; 'DestroyWindow' = [UInt32]0x120
    'D3D11CreateDeviceAndSwapChain' = [UInt32]0x130; 'CreateDXGIFactory' = [UInt32]0x140
    'QueryPerformanceCounter' = [UInt32]0x150; 'QueryPerformanceFrequency' = [UInt32]0x158; 'IsWindow' = [UInt32]0x168
    'GetSystemDirectoryA' = [UInt32]0x178; 'GetCurrentDirectoryA' = [UInt32]0x180; 'CreateProcessA' = [UInt32]0x188
    'CreateJobObjectA' = [UInt32]0x190; 'SetInformationJobObject' = [UInt32]0x198; 'AssignProcessToJobObject' = [UInt32]0x1A0
    'ResumeThread' = [UInt32]0x1A8; 'TerminateJobObject' = [UInt32]0x1B0; 'GetExitCodeProcess' = [UInt32]0x1B8; 'TerminateProcess' = [UInt32]0x1C0; 'GetFileAttributesA' = [UInt32]0x1C8
    'VirtualAlloc' = [UInt32]0x1D0; 'VirtualFree' = [UInt32]0x1D8
    'BCryptOpenAlgorithmProvider' = [UInt32]0x1E8; 'BCryptHash' = [UInt32]0x1F0; 'BCryptCloseAlgorithmProvider' = [UInt32]0x1F8
    'GetFileInformationByHandle' = [UInt32]0x208
    'GetModuleFileNameA' = [UInt32]0x218; 'SetCurrentDirectoryA' = [UInt32]0x220
    'CreatePipe' = [UInt32]0x230; 'SetHandleInformation' = [UInt32]0x238; 'PeekNamedPipe' = [UInt32]0x240
    'InitializeProcThreadAttributeList' = [UInt32]0x248; 'UpdateProcThreadAttribute' = [UInt32]0x250; 'DeleteProcThreadAttributeList' = [UInt32]0x258; 'LocalFree' = [UInt32]0x260; 'GetLastError' = [UInt32]0x268
    'CreateAppContainerProfile' = [UInt32]0x278; 'DeriveAppContainerSidFromAppContainerName' = [UInt32]0x280
    'GetNamedSecurityInfoA' = [UInt32]0x290; 'SetEntriesInAclA' = [UInt32]0x298; 'SetNamedSecurityInfoA' = [UInt32]0x2A0; 'FreeSid' = [UInt32]0x2A8
    'OpenProcessToken' = [UInt32]0x2B0; 'CreateRestrictedToken' = [UInt32]0x2B8; 'CreateProcessAsUserA' = [UInt32]0x2C0; 'GetSecurityInfo' = [UInt32]0x2C8; 'SetSecurityInfo' = [UInt32]0x2D0; 'GetTokenInformation' = [UInt32]0x2D8
    'GetSecurityDescriptorDacl' = [UInt32]0x2E0; 'GetSecurityDescriptorSacl' = [UInt32]0x2E8; 'GetSecurityDescriptorLength' = [UInt32]0x2F0; 'IsValidSecurityDescriptor' = [UInt32]0x2F8
    'GetFullPathNameA' = [UInt32]0x308; 'DeleteFileA' = [UInt32]0x310; 'MoveFileExA' = [UInt32]0x318; 'FlushFileBuffers' = [UInt32]0x320
    'BCryptGenRandom' = [UInt32]0x330; 'DeleteAppContainerProfile' = [UInt32]0x340; 'EqualSid' = [UInt32]0x350
}

# Emit a PE base-relocation directory whose size follows the actual DIR64 target set.
$relocRawSize = Align-Up -Value $relocationDirectory.DirectorySize -Alignment 0x200
$reloc = [byte[]]::new($relocRawSize)
Set-Bytes -Buffer $reloc -Offset 0 -Bytes $relocationDirectory.Bytes
if ($idata.Length -gt $idataVirtualSpan) { throw 'Generated .idata section exceeds its reserved virtual span.' }
$headersSize = 0x400
$pdataRawSize = Align-Up -Value $pdataBytes.Length -Alignment 0x200
$xdataRawSize = Align-Up -Value $xdataBytes.Length -Alignment 0x200
$textRawPointer = $headersSize
$dataRawPointer = $textRawPointer + $textRawSize
$idataRawPointer = $dataRawPointer + $dataRawSize
$relocRawPointer = $idataRawPointer + $idata.Length
$pdataRawPointer = $relocRawPointer + $reloc.Length
$xdataRawPointer = $pdataRawPointer + $pdataRawSize
$totalSize = $xdataRawPointer + $xdataRawSize
$image = [byte[]]::new($totalSize)
Set-Bytes -Buffer $image -Offset $textRawPointer -Bytes $codeBytes
Set-Bytes -Buffer $image -Offset $dataRawPointer -Bytes $dataBytes
Set-Bytes -Buffer $image -Offset $idataRawPointer -Bytes $idata
Set-Bytes -Buffer $image -Offset $relocRawPointer -Bytes $reloc
Set-Bytes -Buffer $image -Offset $pdataRawPointer -Bytes $pdataBytes
Set-Bytes -Buffer $image -Offset $xdataRawPointer -Bytes $xdataBytes

# DOS and PE headers.
$image[0] = 0x4D; $image[1] = 0x5A; Set-U32 -Buffer $image -Offset 0x3C -Value 0x80; Set-Ascii -Buffer $image -Offset 0x80 -Value "PE`0`0"
Set-U16 -Buffer $image -Offset 0x84 -Value 0x8664; Set-U16 -Buffer $image -Offset 0x86 -Value 6; Set-U32 -Buffer $image -Offset 0x88 -Value 0; Set-U32 -Buffer $image -Offset 0x8C -Value 0; Set-U32 -Buffer $image -Offset 0x90 -Value 0; Set-U16 -Buffer $image -Offset 0x94 -Value 240; Set-U16 -Buffer $image -Offset 0x96 -Value 0x0022
$opt = 0x98
Set-U16 -Buffer $image -Offset ($opt + 0) -Value 0x020B; $image[$opt + 2] = 1; $image[$opt + 3] = 0
Set-U32 -Buffer $image -Offset ($opt + 4) -Value $textRawSize; Set-U32 -Buffer $image -Offset ($opt + 8) -Value ($dataRawSize + $idata.Length + $reloc.Length + $pdataRawSize + $xdataRawSize); Set-U32 -Buffer $image -Offset ($opt + 12) -Value 0
Set-U32 -Buffer $image -Offset ($opt + 16) -Value $textRva; Set-U32 -Buffer $image -Offset ($opt + 20) -Value $textRva; Set-U64 -Buffer $image -Offset ($opt + 24) -Value ([UInt64]([Int64]0x140000000))
Set-U32 -Buffer $image -Offset ($opt + 32) -Value 0x1000; Set-U32 -Buffer $image -Offset ($opt + 36) -Value 0x200
Set-U16 -Buffer $image -Offset ($opt + 40) -Value 6; Set-U16 -Buffer $image -Offset ($opt + 42) -Value 0; Set-U16 -Buffer $image -Offset ($opt + 44) -Value 0; Set-U16 -Buffer $image -Offset ($opt + 46) -Value 0; Set-U16 -Buffer $image -Offset ($opt + 48) -Value 6; Set-U16 -Buffer $image -Offset ($opt + 50) -Value 0
Set-U32 -Buffer $image -Offset ($opt + 52) -Value 0; Set-U32 -Buffer $image -Offset ($opt + 56) -Value $sizeOfImage; Set-U32 -Buffer $image -Offset ($opt + 60) -Value $headersSize; Set-U32 -Buffer $image -Offset ($opt + 64) -Value 0
Set-U16 -Buffer $image -Offset ($opt + 68) -Value 3; Set-U16 -Buffer $image -Offset ($opt + 70) -Value 0x0140
Set-U64 -Buffer $image -Offset ($opt + 72) -Value ([UInt64]0x100000); Set-U64 -Buffer $image -Offset ($opt + 80) -Value ([UInt64]0x1000); Set-U64 -Buffer $image -Offset ($opt + 88) -Value ([UInt64]0x100000); Set-U64 -Buffer $image -Offset ($opt + 96) -Value ([UInt64]0x1000)
Set-U32 -Buffer $image -Offset ($opt + 104) -Value 0; Set-U32 -Buffer $image -Offset ($opt + 108) -Value 16
Set-U32 -Buffer $image -Offset ($opt + 120) -Value ([UInt32]([long]$idataRva + [long]$descriptorBase)); Set-U32 -Buffer $image -Offset ($opt + 124) -Value $importDirectorySize
Set-U32 -Buffer $image -Offset ($opt + 136) -Value $pdataRva; Set-U32 -Buffer $image -Offset ($opt + 140) -Value $pdataBytes.Length
Set-U32 -Buffer $image -Offset ($opt + 152) -Value $relocRva; Set-U32 -Buffer $image -Offset ($opt + 156) -Value $relocationDirectory.DirectorySize
Set-U32 -Buffer $image -Offset ($opt + 208) -Value ([UInt32]([long]$idataRva + 0x70)); Set-U32 -Buffer $image -Offset ($opt + 212) -Value 0x2F0
$sectionText = 0x188
Set-Ascii -Buffer $image -Offset $sectionText -Value '.text'; Set-U32 -Buffer $image -Offset ($sectionText + 8) -Value $codeBytes.Length; Set-U32 -Buffer $image -Offset ($sectionText + 12) -Value $textRva; Set-U32 -Buffer $image -Offset ($sectionText + 16) -Value $textRawSize; Set-U32 -Buffer $image -Offset ($sectionText + 20) -Value $textRawPointer; Set-U32 -Buffer $image -Offset ($sectionText + 36) -Value 0x60000020
$sectionData = 0x1B0
Set-Ascii -Buffer $image -Offset $sectionData -Value '.rdata'; Set-U32 -Buffer $image -Offset ($sectionData + 8) -Value $dataBytes.Length; Set-U32 -Buffer $image -Offset ($sectionData + 12) -Value $dataRva; Set-U32 -Buffer $image -Offset ($sectionData + 16) -Value $dataRawSize; Set-U32 -Buffer $image -Offset ($sectionData + 20) -Value $dataRawPointer; Set-U32 -Buffer $image -Offset ($sectionData + 36) -Value 0x40000040
$sectionImport = 0x1D8
Set-Ascii -Buffer $image -Offset $sectionImport -Value '.idata'; Set-U32 -Buffer $image -Offset ($sectionImport + 8) -Value $idata.Length; Set-U32 -Buffer $image -Offset ($sectionImport + 12) -Value $idataRva; Set-U32 -Buffer $image -Offset ($sectionImport + 16) -Value $idata.Length; Set-U32 -Buffer $image -Offset ($sectionImport + 20) -Value $idataRawPointer; Set-U32 -Buffer $image -Offset ($sectionImport + 36) -Value ([UInt32]([Int64]3221225536))
$sectionReloc = 0x200
Set-Ascii -Buffer $image -Offset $sectionReloc -Value '.reloc'; Set-U32 -Buffer $image -Offset ($sectionReloc + 8) -Value $relocationDirectory.DirectorySize; Set-U32 -Buffer $image -Offset ($sectionReloc + 12) -Value $relocRva; Set-U32 -Buffer $image -Offset ($sectionReloc + 16) -Value $reloc.Length; Set-U32 -Buffer $image -Offset ($sectionReloc + 20) -Value $relocRawPointer; Set-U32 -Buffer $image -Offset ($sectionReloc + 36) -Value 0x42000040
$sectionPdata = 0x228
Set-Ascii -Buffer $image -Offset $sectionPdata -Value '.pdata'; Set-U32 -Buffer $image -Offset ($sectionPdata + 8) -Value $pdataBytes.Length; Set-U32 -Buffer $image -Offset ($sectionPdata + 12) -Value $pdataRva; Set-U32 -Buffer $image -Offset ($sectionPdata + 16) -Value $pdataRawSize; Set-U32 -Buffer $image -Offset ($sectionPdata + 20) -Value $pdataRawPointer; Set-U32 -Buffer $image -Offset ($sectionPdata + 36) -Value 0x40000040
$sectionXdata = 0x250
Set-Ascii -Buffer $image -Offset $sectionXdata -Value '.xdata'; Set-U32 -Buffer $image -Offset ($sectionXdata + 8) -Value $xdataBytes.Length; Set-U32 -Buffer $image -Offset ($sectionXdata + 12) -Value $xdataRva; Set-U32 -Buffer $image -Offset ($sectionXdata + 16) -Value $xdataRawSize; Set-U32 -Buffer $image -Offset ($sectionXdata + 20) -Value $xdataRawPointer; Set-U32 -Buffer $image -Offset ($sectionXdata + 36) -Value 0x40000040
Test-ImageBasic -Image $image

$outputDirectory = [System.IO.Path]::GetDirectoryName($outputFullPath)
[System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
$verifierPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\Tools\SharnouPEVerify.ps1'))
try {
    [System.IO.File]::WriteAllBytes($outputFullPath, $image)
    if (-not (Test-Path -LiteralPath $verifierPath -PathType Leaf)) { throw "PE verifier is missing: $verifierPath" }
    & $verifierPath -Path $outputFullPath
} catch {
    if (Test-Path -LiteralPath $outputFullPath) { Remove-Item -LiteralPath $outputFullPath -Force -ErrorAction SilentlyContinue }
    throw ("Linked image failed post-write validation: {0}" -f $_.Exception.Message)
}
$sha256 = (Get-FileHash -LiteralPath $outputFullPath -Algorithm SHA256).Hash
Write-Host "Created native x64 PE32+ executable: $outputFullPath"
Write-Host ("Link result: modules={0}, functions={1}, codeBytes={2}, dataBytes={3}" -f $script:Modules.Count, $script:Functions.Count, $codeBytes.Length, $dataBytes.Length)
Write-Host 'Sections: .text, .rdata, .idata, .reloc, .pdata, .xdata; imports: KERNEL32.dll, USER32.dll, D3D11.dll, and DXGI.dll'
Write-Host "SHA-256: $sha256"
Write-Warning 'Milestone 6 adds a native D3D11/DXGI solid-clear demo and runtime frame timing. Native rendering must be validated on an interactive Windows desktop. Shader/geometry rendering, device-loss recovery, resize handling, and persistent window/event loops remain unsupported.' 
) {
        throw 'Native SCM service name must contain 1-256 ASCII letters, digits, period, underscore, or hyphen characters.'
    }
} elseif ($NativeScmServiceName -cne 'SharnouAuthorityHost') {
    throw 'NativeScmServiceName can only be changed when EnableNativeScmServiceHost is specified.'
}
$relocationModulePath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\Tools\SharnouPERelocations.ps1'))
if (-not (Test-Path -LiteralPath $relocationModulePath -PathType Leaf)) {
    throw "Sharnou PE relocation module is missing: $relocationModulePath"
}
. $relocationModulePath

function Set-Bytes {
    param([byte[]] $Buffer, [int] $Offset, [byte[]] $Bytes)
    if ($Offset -lt 0 -or ($Offset + $Bytes.Length) -gt $Buffer.Length) {
        throw "Write outside output image: offset=$Offset length=$($Bytes.Length)."
    }
    if ($Bytes.Length -gt 0) { [System.Buffer]::BlockCopy($Bytes, 0, $Buffer, $Offset, $Bytes.Length) }
}
function Set-U16 { param([byte[]] $Buffer, [int] $Offset, [UInt16] $Value) Set-Bytes -Buffer $Buffer -Offset $Offset -Bytes ([BitConverter]::GetBytes($Value)) }
function Set-U32 { param([byte[]] $Buffer, [int] $Offset, [UInt32] $Value) Set-Bytes -Buffer $Buffer -Offset $Offset -Bytes ([BitConverter]::GetBytes($Value)) }
function Set-U64 { param([byte[]] $Buffer, [int] $Offset, [UInt64] $Value) Set-Bytes -Buffer $Buffer -Offset $Offset -Bytes ([BitConverter]::GetBytes($Value)) }
function Set-Ascii { param([byte[]] $Buffer, [int] $Offset, [string] $Value) Set-Bytes -Buffer $Buffer -Offset $Offset -Bytes ([System.Text.Encoding]::ASCII.GetBytes($Value)) }
function Set-AsciiZ {
    param([byte[]] $Buffer, [int] $Offset, [string] $Value)
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($Value)
    if ($Offset -lt 0 -or ($Offset + $bytes.Length) -ge $Buffer.Length) { throw 'Null-terminated ASCII string would exceed the output image.' }
    Set-Bytes -Buffer $Buffer -Offset $Offset -Bytes $bytes
    $Buffer[$Offset + $bytes.Length] = 0
}
function Throw-SourceError {
    param([int] $Line, [int] $Column, [string] $Message)
    throw ("{0}({1},{2}): error: {3} (line {1}, column {2})" -f $script:SourceDisplay, $Line, $Column, $Message)
}
function Add-Token {
    param([string] $Kind, [string] $Text, [object] $Value, [int] $Line, [int] $Column)
    $script:Tokens.Add([pscustomobject]@{ Kind = $Kind; Text = $Text; Value = $Value; Line = $Line; Column = $Column; File = $script:SourceDisplay })
}
function Initialize-Tokens {
    param([string] $Text)
    $script:Tokens = [System.Collections.Generic.List[object]]::new()
    $i = 0
    $line = 1
    $column = 1
    while ($i -lt $Text.Length) {
        $ch = $Text[$i]
        $code = [int]$ch
        if ($code -gt 127) { Throw-SourceError -Line $line -Column $column -Message 'Source files must contain ASCII characters only.' }
        if ([char]::IsWhiteSpace($ch)) {
            if ($ch -eq "`r") {
                $i++
                if ($i -lt $Text.Length -and $Text[$i] -eq "`n") { $i++ }
                $line++; $column = 1
            } elseif ($ch -eq "`n") { $i++; $line++; $column = 1 }
            else { $i++; $column++ }
            continue
        }
        if ($ch -eq '/' -and ($i + 1) -lt $Text.Length -and $Text[$i + 1] -eq '/') {
            $i += 2; $column += 2
            while ($i -lt $Text.Length -and $Text[$i] -ne "`r" -and $Text[$i] -ne "`n") { $i++; $column++ }
            continue
        }
        if ($ch -eq '/' -and ($i + 1) -lt $Text.Length -and $Text[$i + 1] -eq '*') {
            $commentLine = $line; $commentColumn = $column; $i += 2; $column += 2; $closed = $false
            while ($i -lt $Text.Length) {
                if ($Text[$i] -eq '*' -and ($i + 1) -lt $Text.Length -and $Text[$i + 1] -eq '/') { $i += 2; $column += 2; $closed = $true; break }
                if ($Text[$i] -eq "`r") { $i++; if ($i -lt $Text.Length -and $Text[$i] -eq "`n") { $i++ }; $line++; $column = 1; continue }
                if ($Text[$i] -eq "`n") { $i++; $line++; $column = 1; continue }
                $i++; $column++
            }
            if (-not $closed) { Throw-SourceError -Line $commentLine -Column $commentColumn -Message 'Unterminated block comment; expected */.' }
            continue
        }
        if ($ch -eq '"') {
            $stringLine = $line; $stringColumn = $column; $i++; $column++; $builder = [System.Text.StringBuilder]::new(); $closed = $false
            while ($i -lt $Text.Length) {
                $current = $Text[$i]; $currentCode = [int]$current
                if ($currentCode -gt 127) { Throw-SourceError -Line $line -Column $column -Message 'String literals must use ASCII characters only.' }
                if ($current -eq '"') { $i++; $column++; $closed = $true; break }
                if ($current -eq "`r" -or $current -eq "`n") { Throw-SourceError -Line $line -Column $column -Message 'Unescaped newline in string literal.' }
                if ($current -eq '\') {
                    $escapeLine = $line; $escapeColumn = $column; $i++; $column++
                    if ($i -ge $Text.Length) { Throw-SourceError -Line $escapeLine -Column $escapeColumn -Message 'Incomplete string escape.' }
                    $escaped = $Text[$i]
                    switch ([string]$escaped) {
                        '\' { $null = $builder.Append('\') }
                        '"' { $null = $builder.Append('"') }
                        'n' { $null = $builder.Append("`n") }
                        'r' { $null = $builder.Append("`r") }
                        't' { $null = $builder.Append("`t") }
                        default { Throw-SourceError -Line $escapeLine -Column $escapeColumn -Message ("Unsupported string escape '{0}'. Supported escapes: backslash, quote, n, r, and t." -f $escaped) }
                    }
                    $i++; $column++; continue
                }
                if ($currentCode -lt 0x20 -or $currentCode -gt 0x7E) { Throw-SourceError -Line $line -Column $column -Message 'String literals may contain printable ASCII only; use escapes for tab and control characters.' }
                $null = $builder.Append($current); $i++; $column++
            }
            if (-not $closed) { Throw-SourceError -Line $stringLine -Column $stringColumn -Message 'Unterminated string literal; expected a closing quote.' }
            Add-Token -Kind 'String' -Text '<string>' -Value $builder.ToString() -Line $stringLine -Column $stringColumn
            continue
        }
        if ([char]::IsDigit($ch)) {
            $start = $i; $startColumn = $column
            while ($i -lt $Text.Length -and [char]::IsDigit($Text[$i])) { if ([int]$Text[$i] -gt 127) { Throw-SourceError -Line $line -Column $column -Message 'Integer literals must use ASCII decimal digits.' }; $i++; $column++ }
            $numberText = $Text.Substring($start, $i - $start)
            Add-Token -Kind 'Integer' -Text $numberText -Value $numberText -Line $line -Column $startColumn
            continue
        }
        if ([char]::IsLetter($ch) -or $ch -eq '_') {
            $start = $i; $startColumn = $column
            while ($i -lt $Text.Length) {
                $current = $Text[$i]; $currentCode = [int]$current
                if ($currentCode -gt 127) { Throw-SourceError -Line $line -Column $column -Message 'Identifiers must use ASCII letters, digits, and underscores.' }
                if (-not ([char]::IsLetterOrDigit($current) -or $current -eq '_')) { break }
                $i++; $column++
            }
            $identifier = $Text.Substring($start, $i - $start)
            Add-Token -Kind 'Identifier' -Text $identifier -Value $identifier -Line $line -Column $startColumn
            continue
        }
        if (($i + 1) -lt $Text.Length) {
            $pair = $Text.Substring($i, 2)
            if (@('<=', '>=', '==', '!=') -contains $pair) {
                Add-Token -Kind 'Symbol' -Text $pair -Value $pair -Line $line -Column $column
                $i += 2; $column += 2; continue
            }
        }
        if ('+-*/=();{},<>'.Contains([string]$ch)) {
            Add-Token -Kind 'Symbol' -Text ([string]$ch) -Value ([string]$ch) -Line $line -Column $column
            $i++; $column++; continue
        }
        Throw-SourceError -Line $line -Column $column -Message ("Unexpected character '{0}'." -f $ch)
    }
    Add-Token -Kind 'EOF' -Text '<end of file>' -Value $null -Line $line -Column $column
}
function Get-CurrentToken { return $script:Tokens[$script:TokenIndex] }
function Move-NextToken { $token = $script:Tokens[$script:TokenIndex]; if ($token.Kind -ne 'EOF') { $script:TokenIndex++ }; return $token }
function Test-CurrentText { param([string] $Text) return ((Get-CurrentToken).Text -ceq $Text) }
function Expect-Text {
    param([string] $Text, [string] $Description)
    $token = Get-CurrentToken
    if ($token.Text -cne $Text) { Throw-SourceError -Line $token.Line -Column $token.Column -Message ("Expected {0}; found '{1}'." -f $Description, $token.Text) }
    return (Move-NextToken)
}
function New-AstNode {
    param([string] $Kind, [string] $Type, [object] $Value = $null, [string] $Name = '', [int] $Slot = -1, [string] $Operator = '', [object] $Left = $null, [object] $Right = $null, [object] $Operand = $null, [object[]] $Arguments = @(), [object[]] $Statements = @(), [string] $Builtin = '', [int] $Line = 1, [int] $Column = 1)
    return [pscustomobject]@{ Kind = $Kind; Type = $Type; Value = $Value; Name = $Name; Slot = $Slot; Operator = $Operator; Left = $Left; Right = $Right; Operand = $Operand; Arguments = $Arguments; Statements = $Statements; Builtin = $Builtin; Line = $Line; Column = $Column }
}
function New-Statement {
    param([string] $Kind, [string] $Name = '', [string] $Type = '', [int] $Slot = -1, [object] $Expression = $null, [object[]] $Statements = @(), [object[]] $ElseStatements = @(), [int] $Line = 1, [int] $Column = 1)
    return [pscustomobject]@{ Kind = $Kind; Name = $Name; Type = $Type; Slot = $Slot; Expression = $Expression; Statements = $Statements; ElseStatements = $ElseStatements; Line = $Line; Column = $Column }
}
function New-IntegerNode { param([long] $Value, [int] $Line, [int] $Column) return (New-AstNode -Kind 'Integer' -Type 'Integer' -Value $Value -Line $Line -Column $Column) }
function New-StringNode { param([string] $Value, [int] $Line, [int] $Column) return (New-AstNode -Kind 'String' -Type 'String' -Value $Value -Line $Line -Column $Column) }
function Push-Scope { $script:Scopes.Add([System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)) }
function Pop-Scope { if ($script:Scopes.Count -le 0) { throw 'Internal scope underflow.' }; $script:Scopes.RemoveAt($script:Scopes.Count - 1) }
function Find-Variable {
    param([string] $Name)
    for ($i = $script:Scopes.Count - 1; $i -ge 0; $i--) { if ($script:Scopes[$i].ContainsKey($Name)) { return $script:Scopes[$i][$Name] } }
    return $null
}
function Declare-Variable {
    param([string] $Name, [string] $Type, [int] $Line, [int] $Column)
    if ($script:Scopes.Count -eq 0) { throw 'Internal parser error: no active lexical scope.' }
    $scope = $script:Scopes[$script:Scopes.Count - 1]
    if ($scope.ContainsKey($Name)) { Throw-SourceError -Line $Line -Column $Column -Message ("Variable '{0}' is already declared in this scope." -f $Name) }
    $slot = [int]$script:ActiveContext.SlotCount
    $symbol = [pscustomobject]@{ Name = $Name; Type = $Type; Slot = $slot }
    $scope.Add($Name, $symbol)
    $script:ActiveContext.SlotCount = [int]($script:ActiveContext.SlotCount + 1)
    return $symbol
}
function Parse-Primary {
    $token = Get-CurrentToken
    if ($token.Kind -eq 'Integer') {
        Move-NextToken | Out-Null
        $number = [long]0
        $parsed = [long]::TryParse([string]$token.Text, [System.Globalization.NumberStyles]::None, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$number)
        if (-not $parsed -or $number -gt [int]::MaxValue) { Throw-SourceError -Line $token.Line -Column $token.Column -Message 'Integer literal is outside the supported signed 32-bit range.' }
        return (New-IntegerNode -Value $number -Line $token.Line -Column $token.Column)
    }
    if ($token.Kind -eq 'String') { Move-NextToken | Out-Null; return (New-StringNode -Value ([string]$token.Value) -Line $token.Line -Column $token.Column) }
    if ($token.Kind -eq 'Identifier') {
        Move-NextToken | Out-Null
        $name = [string]$token.Text
        if (Test-CurrentText '(') {
            $null = Move-NextToken
            $callArguments = [System.Collections.Generic.List[object]]::new()
            if (-not (Test-CurrentText ')')) {
                while ($true) {
                    $callArguments.Add((Parse-Expression))
                    if (Test-CurrentText ',') { Move-NextToken | Out-Null; continue }
                    break
                }
            }
            $null = Expect-Text -Text ')' -Description "')' after function arguments"
            $target = $null
            $isBuiltin = $false
            if ($script:Functions.ContainsKey($name)) { $target = $script:Functions[$name] }
            elseif ($script:Builtins.ContainsKey($name)) { $target = $script:Builtins[$name]; $isBuiltin = $true }
            else { Throw-SourceError -Line $token.Line -Column $token.Column -Message ("Undefined function or standard-library intrinsic '{0}'." -f $name) }
            if ($isBuiltin) { $expectedParameters = @($target.ParameterTypes) }
            else { $expectedParameters = @($target.Parameters | ForEach-Object { 'Integer' }) }
            if ($callArguments.Count -ne $expectedParameters.Count) { Throw-SourceError -Line $token.Line -Column $token.Column -Message ("Function '{0}' expects {1} argument(s), but received {2}." -f $name, $expectedParameters.Count, $callArguments.Count) }
            for ($argIndex = 0; $argIndex -lt $callArguments.Count; $argIndex++) {
                if ($callArguments[$argIndex].Type -ne $expectedParameters[$argIndex]) { Throw-SourceError -Line $callArguments[$argIndex].Line -Column $callArguments[$argIndex].Column -Message ("Argument {0} of '{1}' must be {2}, not {3}." -f ($argIndex + 1), $name, $expectedParameters[$argIndex], $callArguments[$argIndex].Type) }
            }
            $builtinName = ''
            $returnType = 'Integer'
            if ($isBuiltin) { $builtinName = [string]$target.Builtin; $returnType = [string]$target.ReturnType }
            return (New-AstNode -Kind 'Call' -Type $returnType -Name $name -Builtin $builtinName -Arguments ($callArguments.ToArray()) -Line $token.Line -Column $token.Column)
        }
        $symbol = Find-Variable -Name $name
        if ($null -eq $symbol) { Throw-SourceError -Line $token.Line -Column $token.Column -Message ("Undefined variable '{0}'." -f $name) }
        return (New-AstNode -Kind 'Variable' -Type $symbol.Type -Name $name -Slot $symbol.Slot -Line $token.Line -Column $token.Column)
    }
    if ($token.Text -ceq '(') { Move-NextToken | Out-Null; $value = Parse-Expression; $null = Expect-Text -Text ')' -Description "')'"; return $value }
    Throw-SourceError -Line $token.Line -Column $token.Column -Message ("Expected an integer, string, variable, function call, or parenthesized expression; found '{0}'." -f $token.Text)
}
function Parse-Unary {
    $token = Get-CurrentToken
    if ($token.Text -ceq '+' -or $token.Text -ceq '-') {
        $operator = Move-NextToken; $next = Get-CurrentToken
        if ($operator.Text -ceq '-' -and $next.Kind -eq 'Integer' -and $next.Text -ceq '2147483648') { Move-NextToken | Out-Null; return (New-IntegerNode -Value ([long]([int]::MinValue)) -Line $operator.Line -Column $operator.Column) }
        $operand = Parse-Unary
        if ($operand.Type -ne 'Integer') { Throw-SourceError -Line $operator.Line -Column $operator.Column -Message ("Unary operator '{0}' requires an integer operand." -f $operator.Text) }
        return (New-AstNode -Kind 'Unary' -Type 'Integer' -Operator ([string]$operator.Text) -Operand $operand -Line $operator.Line -Column $operator.Column)
    }
    return (Parse-Primary)
}
function Parse-Term {
    $value = Parse-Unary
    while ((Test-CurrentText '*') -or (Test-CurrentText '/')) {
        $operator = Move-NextToken; $right = Parse-Unary
        if ($value.Type -ne 'Integer' -or $right.Type -ne 'Integer') { Throw-SourceError -Line $operator.Line -Column $operator.Column -Message ("Operator '{0}' requires integer operands." -f $operator.Text) }
        $value = New-AstNode -Kind 'Binary' -Type 'Integer' -Operator ([string]$operator.Text) -Left $value -Right $right -Line $operator.Line -Column $operator.Column
    }
    return $value
}
function Parse-AdditiveExpression {
    $value = Parse-Term
    while ((Test-CurrentText '+') -or (Test-CurrentText '-')) {
        $operator = Move-NextToken; $right = Parse-Term
        if ($value.Type -ne 'Integer' -or $right.Type -ne 'Integer') { Throw-SourceError -Line $operator.Line -Column $operator.Column -Message ("Operator '{0}' requires integer operands." -f $operator.Text) }
        $value = New-AstNode -Kind 'Binary' -Type 'Integer' -Operator ([string]$operator.Text) -Left $value -Right $right -Line $operator.Line -Column $operator.Column
    }
    return $value
}
function Parse-Expression {
    $left = Parse-AdditiveExpression
    $operatorToken = Get-CurrentToken
    $comparisonOperators = @('<', '>', '<=', '>=', '==', '!=')
    if ($comparisonOperators -contains $operatorToken.Text) {
        $operator = Move-NextToken
        $right = Parse-AdditiveExpression
        if ($left.Type -ne 'Integer' -or $right.Type -ne 'Integer') {
            Throw-SourceError -Line $operator.Line -Column $operator.Column -Message ("Comparison '{0}' requires integer operands." -f $operator.Text)
        }
        $next = Get-CurrentToken
        if ($comparisonOperators -contains $next.Text) {
            Throw-SourceError -Line $next.Line -Column $next.Column -Message 'Chained comparisons are not supported; use a nested if or while statement.'
        }
        return (New-AstNode -Kind 'Comparison' -Type 'Integer' -Operator ([string]$operator.Text) -Left $left -Right $right -Line $operator.Line -Column $operator.Column)
    }
    return $left
}
function Get-ConstantValue {
    param([object] $Node)
    if ($Node.Kind -eq 'Integer') { return [pscustomobject]@{ Known = $true; Type = 'Integer'; Value = [long]$Node.Value } }
    if ($Node.Kind -eq 'String') { return [pscustomobject]@{ Known = $true; Type = 'String'; Value = [string]$Node.Value } }
    if ($Node.Kind -eq 'Variable' -or $Node.Kind -eq 'Call') { return [pscustomobject]@{ Known = $false; Type = $Node.Type; Value = $null } }
    if ($Node.Kind -eq 'Unary') {
        $child = Get-ConstantValue -Node $Node.Operand
        if (-not $child.Known) { return [pscustomobject]@{ Known = $false; Type = 'Integer'; Value = $null } }
        $number = [long]$child.Value; if ($Node.Operator -eq '-') { $number = -$number }
        if ($number -lt [int]::MinValue -or $number -gt [int]::MaxValue) { Throw-SourceError -Line $Node.Line -Column $Node.Column -Message 'Integer result is outside the supported signed 32-bit range.' }
        return [pscustomobject]@{ Known = $true; Type = 'Integer'; Value = $number }
    }
    if ($Node.Kind -eq 'Comparison') {
        $left = Get-ConstantValue -Node $Node.Left
        $right = Get-ConstantValue -Node $Node.Right
        if (-not $left.Known -or -not $right.Known) {
            return [pscustomobject]@{ Known = $false; Type = 'Integer'; Value = $null }
        }
        $a = [long]$left.Value
        $b = [long]$right.Value
        switch ($Node.Operator) {
            '<'  { $result = ($a -lt $b) }
            '>'  { $result = ($a -gt $b) }
            '<=' { $result = ($a -le $b) }
            '>=' { $result = ($a -ge $b) }
            '==' { $result = ($a -eq $b) }
            '!=' { $result = ($a -ne $b) }
            default { Throw-SourceError -Line $Node.Line -Column $Node.Column -Message ("Unsupported comparison operator '{0}'." -f $Node.Operator) }
        }
        return [pscustomobject]@{ Known = $true; Type = 'Integer'; Value = [long]([int]$result) }
    }
    if ($Node.Kind -eq 'Binary') {
        $left = Get-ConstantValue -Node $Node.Left; $right = Get-ConstantValue -Node $Node.Right
        if (-not $left.Known -or -not $right.Known) { return [pscustomobject]@{ Known = $false; Type = 'Integer'; Value = $null } }
        $a = [long]$left.Value; $b = [long]$right.Value
        switch ($Node.Operator) {
            '+' { $number = $a + $b }
            '-' { $number = $a - $b }
            '*' { $number = $a * $b }
            '/' { if ($b -eq 0) { Throw-SourceError -Line $Node.Line -Column $Node.Column -Message 'Division by zero is not allowed.' }; $number = [long][Math]::Truncate(([double]$a / [double]$b)) }
            default { Throw-SourceError -Line $Node.Line -Column $Node.Column -Message ("Unsupported operator '{0}'." -f $Node.Operator) }
        }
        if ($number -lt [int]::MinValue -or $number -gt [int]::MaxValue) { Throw-SourceError -Line $Node.Line -Column $Node.Column -Message 'Integer result is outside the supported signed 32-bit range.' }
        return [pscustomobject]@{ Known = $true; Type = 'Integer'; Value = $number }
    }
    return [pscustomobject]@{ Known = $false; Type = $Node.Type; Value = $null }
}
function Validate-ConstantArithmetic { param([object] $Node) $null = Get-ConstantValue -Node $Node }
function Load-Module {
    param([string] $Path, [bool] $IsRoot = $false)
    $full = [System.IO.Path]::GetFullPath($Path)
    if ($script:ModuleMap.ContainsKey($full)) {
        $existing = $script:ModuleMap[$full]
        if ($existing.State -eq 'Loading') { throw "Cyclic module import detected at: $full" }
        if ($IsRoot) { $existing.IsRoot = $true }
        return $existing
    }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Imported module was not found: $full" }
    $module = [pscustomobject]@{ Path = $full; Tokens = $null; Imports = [System.Collections.Generic.List[string]]::new(); BodyStartIndex = 0; IsRoot = $IsRoot; State = 'Loading' }
    $script:ModuleMap.Add($full, $module); $script:Modules.Add($module)
    $script:SourceDisplay = $full
    $sourceText = [System.IO.File]::ReadAllText($full, [System.Text.Encoding]::UTF8)
    Initialize-Tokens -Text $sourceText
    $module.Tokens = $script:Tokens.ToArray()
    $index = 0
    while ($index -lt $module.Tokens.Length -and $module.Tokens[$index].Kind -ne 'EOF') {
        $script:SourceDisplay = $full
        $token = $module.Tokens[$index]
        if ($token.Kind -ne 'Identifier' -or $token.Text -cne 'import') { break }
        if (($index + 2) -ge $module.Tokens.Length) {
            Throw-SourceError -Line $token.Line -Column $token.Column -Message "Expected import 'relative-module.sharnou'; at the start of a module."
        }
        if ($module.Tokens[$index + 1].Kind -ne 'String' -or $module.Tokens[$index + 2].Text -cne ';') {
            Throw-SourceError -Line $token.Line -Column $token.Column -Message "Expected import 'relative-module.sharnou'; at the start of a module."
        }
        $importName = [string]$module.Tokens[$index + 1].Value
        if ([System.IO.Path]::IsPathRooted($importName)) { Throw-SourceError -Line $module.Tokens[$index + 1].Line -Column $module.Tokens[$index + 1].Column -Message 'Module imports must be relative paths.' }
        $target = [System.IO.Path]::GetFullPath((Join-Path ([System.IO.Path]::GetDirectoryName($full)) $importName))
        $module.Imports.Add($target)
        $null = Load-Module -Path $target -IsRoot $false
        $index += 3
    }
    $module.BodyStartIndex = $index
    $module.State = 'Loaded'
    return $module
}
function Collect-FunctionHeaders {
    param([object] $Module)
    $tokens = $Module.Tokens; $i = [int]$Module.BodyStartIndex; $depth = 0
    while ($i -lt $tokens.Length -and $tokens[$i].Kind -ne 'EOF') {
        $token = $tokens[$i]
        if ($depth -eq 0 -and $token.Kind -eq 'Identifier' -and $token.Text -ceq 'fn') {
            $functionStart = $i; $fnToken = $token; $i++
            if ($i -ge $tokens.Length -or $tokens[$i].Kind -ne 'Identifier') { $script:SourceDisplay = $Module.Path; Throw-SourceError -Line $fnToken.Line -Column $fnToken.Column -Message 'Expected a function name after fn.' }
            $nameToken = $tokens[$i]; $name = [string]$nameToken.Text; $i++
            if (@('print', 'let', 'fn', 'return', 'import', 'if', 'else', 'while') -contains $name) { $script:SourceDisplay = $Module.Path; Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message 'Reserved keyword cannot be used as a function name.' }
            if ($i -ge $tokens.Length -or $tokens[$i].Text -cne '(') { $script:SourceDisplay = $Module.Path; Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message "Expected '(' after function name." }; $i++
            $params = [System.Collections.Generic.List[object]]::new(); $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            if ($i -lt $tokens.Length -and $tokens[$i].Text -cne ')') {
                while ($true) {
                    if ($i -ge $tokens.Length -or $tokens[$i].Kind -ne 'Identifier') { $script:SourceDisplay = $Module.Path; $cur = $tokens[[Math]::Min($i, $tokens.Length - 1)]; Throw-SourceError -Line $cur.Line -Column $cur.Column -Message 'Expected a parameter name.' }
                    $paramToken = $tokens[$i]
                    if (@('print', 'let', 'fn', 'return', 'import', 'if', 'else', 'while') -contains $paramToken.Text) { $script:SourceDisplay = $Module.Path; Throw-SourceError -Line $paramToken.Line -Column $paramToken.Column -Message 'Reserved keyword cannot be used as a parameter name.' }
                    if (-not $seen.Add([string]$paramToken.Text)) { $script:SourceDisplay = $Module.Path; Throw-SourceError -Line $paramToken.Line -Column $paramToken.Column -Message ("Duplicate parameter '{0}'." -f $paramToken.Text) }
                    $params.Add($paramToken); $i++
                    if ($i -lt $tokens.Length -and $tokens[$i].Text -ceq ',') { $i++; continue }; break
                }
            }
            if ($i -ge $tokens.Length -or $tokens[$i].Text -cne ')') { $script:SourceDisplay = $Module.Path; Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message "Expected ')' after function parameters." }; $i++
            $legacyBaselineMode = [string]::Equals([Environment]::GetEnvironmentVariable('SHARNOU_BASELINE_M1_M6'), '1', [StringComparison]::Ordinal)
            if ($params.Count -gt 16 -or ($legacyBaselineMode -and $params.Count -gt 4)) {
                $script:SourceDisplay = $Module.Path
                if ($legacyBaselineMode) {
                    Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message 'Historical M1-M6 compatibility mode permits at most four integer function parameters.'
                }
                Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message 'Sharnou functions support at most 16 integer parameters (four register arguments and twelve stack arguments under the Windows x64 ABI).'
            }
            if ($i -ge $tokens.Length -or $tokens[$i].Text -cne '{') { $script:SourceDisplay = $Module.Path; Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message "Expected '{' to start the function body." }
            $bodyOpen = $i; $i++; $braceDepth = 1
            while ($i -lt $tokens.Length -and $braceDepth -gt 0) {
                if ($tokens[$i].Text -ceq '{') { $braceDepth++ }
                elseif ($tokens[$i].Text -ceq '}') { $braceDepth-- }
                $i++
            }
            if ($braceDepth -ne 0) { $script:SourceDisplay = $Module.Path; Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message 'Unterminated function body; expected }.' }
            $bodyClose = $i - 1
            if ($script:Builtins.ContainsKey($name)) { $script:SourceDisplay = $Module.Path; Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message ("Function name '{0}' is reserved for a Sharnou standard-library intrinsic." -f $name) }; if ($script:Functions.ContainsKey($name)) { $script:SourceDisplay = $Module.Path; Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message ("Function '{0}' is already defined in another module or scope." -f $name) }
            $index = $script:FunctionIndex; $script:FunctionIndex++
            $functionObject = [pscustomobject]@{ Name = $name; ModulePath = $Module.Path; Module = $Module; HeaderIndex = [int]$functionStart; BodyOpenIndex = $bodyOpen; BodyCloseIndex = $bodyClose; Parameters = $params.ToArray(); Label = ("__sharnou_fn_{0}_{1}" -f $index, $name); Context = $null; BodyStatements = @(); ReturnExpression = $null; Index = $index }
            $script:Functions.Add($name, $functionObject)
            continue
        }
        if ($token.Text -ceq '{') { $depth++ }
        elseif ($token.Text -ceq '}') { $depth-- }
        $i++
    }
}
function Parse-BlockStatement {
    $open = Expect-Text -Text '{' -Description "'{' to start a lexical block"
    Push-Scope; $script:BlockDepth++
    $statements = [System.Collections.Generic.List[object]]::new()
    while (-not (Test-CurrentText '}')) {
        $token = Get-CurrentToken
        if ($token.Kind -eq 'EOF') { Throw-SourceError -Line $open.Line -Column $open.Column -Message 'Unterminated block; expected }.' }
        $statements.Add((Parse-Statement))
    }
    $null = Expect-Text -Text '}' -Description "'}' to close a lexical block"
    $script:BlockDepth--; Pop-Scope
    return (New-Statement -Kind 'Block' -Statements ($statements.ToArray()) -Line $open.Line -Column $open.Column)
}
function Parse-Statement {
    $token = Get-CurrentToken
    if ($token.Text -ceq '{') { return (Parse-BlockStatement) }
    if ($token.Kind -ne 'Identifier') { Throw-SourceError -Line $token.Line -Column $token.Column -Message ("Expected a statement; found '{0}'." -f $token.Text) }
    if ($token.Text -ceq 'import' -or $token.Text -ceq 'fn') { Throw-SourceError -Line $token.Line -Column $token.Column -Message 'Imports and function definitions are only valid at module scope.' }
    if ($token.Text -ceq 'if') {
        Move-NextToken | Out-Null
        $null = Expect-Text -Text '(' -Description "'(' after if"
        $condition = Parse-Expression
        if ($condition.Type -ne 'Integer') { Throw-SourceError -Line $token.Line -Column $token.Column -Message 'if condition must be an integer expression or comparison.' }
        Validate-ConstantArithmetic -Node $condition
        $null = Expect-Text -Text ')' -Description "')' after if condition"
        $thenBlock = Parse-BlockStatement
        $elseStatements = @()
        if (Test-CurrentText 'else') {
            Move-NextToken | Out-Null
            $elseBlock = Parse-BlockStatement
            $elseStatements = @($elseBlock.Statements)
        }
        return (New-Statement -Kind 'If' -Expression $condition -Statements @($thenBlock.Statements) -ElseStatements $elseStatements -Line $token.Line -Column $token.Column)
    }
    if ($token.Text -ceq 'while') {
        Move-NextToken | Out-Null
        $null = Expect-Text -Text '(' -Description "'(' after while"
        $condition = Parse-Expression
        if ($condition.Type -ne 'Integer') { Throw-SourceError -Line $token.Line -Column $token.Column -Message 'while condition must be an integer expression or comparison.' }
        Validate-ConstantArithmetic -Node $condition
        $null = Expect-Text -Text ')' -Description "')' after while condition"
        $body = Parse-BlockStatement
        return (New-Statement -Kind 'While' -Expression $condition -Statements @($body.Statements) -Line $token.Line -Column $token.Column)
    }
    if ($token.Text -ceq 'print') {
        Move-NextToken | Out-Null; $null = Expect-Text -Text '(' -Description "'(' after print"; $expression = Parse-Expression; Validate-ConstantArithmetic -Node $expression; $null = Expect-Text -Text ')' -Description "')' after print expression"; $null = Expect-Text -Text ';' -Description "';' after print statement"
        return (New-Statement -Kind 'Print' -Expression $expression -Line $token.Line -Column $token.Column)
    }
    if ($token.Text -ceq 'let') {
        Move-NextToken | Out-Null; $nameToken = Get-CurrentToken
        if ($nameToken.Kind -ne 'Identifier' -or @('print', 'let', 'fn', 'return', 'import', 'if', 'else', 'while') -contains $nameToken.Text) { Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message "Expected a variable name after 'let'." }
        Move-NextToken | Out-Null; $name = [string]$nameToken.Text
        $null = Expect-Text -Text '=' -Description "'=' in variable declaration"
        $expression = Parse-Expression; Validate-ConstantArithmetic -Node $expression; $null = Expect-Text -Text ';' -Description "';' after variable declaration"
        $symbol = Declare-Variable -Name $name -Type $expression.Type -Line $nameToken.Line -Column $nameToken.Column
        return (New-Statement -Kind 'Let' -Name $name -Type $symbol.Type -Slot $symbol.Slot -Expression $expression -Line $nameToken.Line -Column $nameToken.Column)
    }
    if ($token.Text -ceq 'return') {
        if ($null -eq $script:CurrentFunction) { Throw-SourceError -Line $token.Line -Column $token.Column -Message 'return is only valid inside a function.' }
        if ($script:BlockDepth -ne 0) { Throw-SourceError -Line $token.Line -Column $token.Column -Message 'return must appear at the top level of a function body in the current language subset.' }
        Move-NextToken | Out-Null; $expression = Parse-Expression; Validate-ConstantArithmetic -Node $expression
        if ($expression.Type -ne 'Integer') { Throw-SourceError -Line $token.Line -Column $token.Column -Message 'Function return values must be integers in the current language subset.' }
        $null = Expect-Text -Text ';' -Description "';' after return statement"
        return (New-Statement -Kind 'Return' -Expression $expression -Line $token.Line -Column $token.Column)
    }
    if (@('print', 'let', 'fn', 'return', 'import', 'if', 'else', 'while') -contains $token.Text) { Throw-SourceError -Line $token.Line -Column $token.Column -Message 'Reserved keyword cannot be used as a variable name.' }
    $nameToken = Move-NextToken; $name = [string]$nameToken.Text
    if (-not (Test-CurrentText '=')) { $next = Get-CurrentToken; Throw-SourceError -Line $next.Line -Column $next.Column -Message ("Expected '=' after variable name '{0}'; only assignment, declarations, and print statements are supported." -f $name) }
    $symbol = Find-Variable -Name $name
    if ($null -eq $symbol) { Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message ("Cannot assign to undefined variable '{0}'. Use let to declare it first." -f $name) }
    Move-NextToken | Out-Null; $expression = Parse-Expression; Validate-ConstantArithmetic -Node $expression; $null = Expect-Text -Text ';' -Description "';' after assignment"
    if ($symbol.Type -ne $expression.Type) { Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message ("Assignment changes variable '{0}' from {1} to {2}; variable types are fixed after declaration." -f $name, $symbol.Type, $expression.Type) }
    return (New-Statement -Kind 'Assign' -Name $name -Type $symbol.Type -Slot $symbol.Slot -Expression $expression -Line $nameToken.Line -Column $nameToken.Column)
}
function Parse-FunctionDeclaration {
    $oldScopes = $script:Scopes; $oldContext = $script:ActiveContext; $oldFunction = $script:CurrentFunction; $oldBlockDepth = $script:BlockDepth
    $fnToken = Move-NextToken; $nameToken = Move-NextToken; $name = [string]$nameToken.Text
    if (-not $script:Functions.ContainsKey($name)) { Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message ("Function '{0}' was not registered during declaration scan." -f $name) }
    $func = $script:Functions[$name]
    if (-not [string]::Equals($func.ModulePath, $script:CurrentModule.Path, [System.StringComparison]::OrdinalIgnoreCase)) { Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message 'Internal module/function ownership mismatch.' }
    $null = Expect-Text -Text '(' -Description "'(' after function name"
    $paramNames = [System.Collections.Generic.List[string]]::new()
    if (-not (Test-CurrentText ')')) {
        while ($true) {
            $paramToken = Get-CurrentToken
            if ($paramToken.Kind -ne 'Identifier') { Throw-SourceError -Line $paramToken.Line -Column $paramToken.Column -Message 'Expected a parameter name.' }
            $paramNames.Add([string]$paramToken.Text); Move-NextToken | Out-Null
            if (Test-CurrentText ',') { Move-NextToken | Out-Null; continue }; break
        }
    }
    $null = Expect-Text -Text ')' -Description "')' after parameters"
    if ($paramNames.Count -ne $func.Parameters.Count) { Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message 'Function header changed between declaration scan and parse.' }
    for ($i = 0; $i -lt $paramNames.Count; $i++) { if ($paramNames[$i] -cne $func.Parameters[$i].Text) { Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message 'Function parameter list changed between declaration scan and parse.' } }
    $open = Expect-Text -Text '{' -Description "'{' before function body"
    $script:Scopes = [System.Collections.Generic.List[object]]::new(); Push-Scope; $script:BlockDepth = 0; $script:CurrentFunction = $func
    $context = [pscustomobject]@{ Name = $name; SlotCount = 0; TempSlots = 0; ScratchPosition = 0; FrameSize = 0; Statements = [System.Collections.Generic.List[object]]::new() }
    $script:ActiveContext = $context
    for ($i = 0; $i -lt $paramNames.Count; $i++) {
        $pt = $func.Parameters[$i]
        $symbol = Declare-Variable -Name $paramNames[$i] -Type 'Integer' -Line $pt.Line -Column $pt.Column
        if ($symbol.Slot -ne $i) { throw 'Internal parameter slot assignment error.' }
    }
    $returnExpression = $null
    while (-not (Test-CurrentText '}')) {
        $current = Get-CurrentToken
        if ($current.Kind -eq 'EOF') { Throw-SourceError -Line $open.Line -Column $open.Column -Message 'Unterminated function body; expected }.' }
        $statement = Parse-Statement
        if ($statement.Kind -eq 'Return') {
            $returnExpression = $statement.Expression
            if (-not (Test-CurrentText '}')) { $next = Get-CurrentToken; Throw-SourceError -Line $next.Line -Column $next.Column -Message 'return must be the final statement in a function in the current language subset.' }
            break
        }
        $context.Statements.Add($statement)
    }
    $null = Expect-Text -Text '}' -Description "'}' after function body"
    if ($null -eq $returnExpression) { Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message ("Function '{0}' must end with 'return integerExpression;'." -f $name) }
    $func.Context = $context; $func.BodyStatements = $context.Statements.ToArray(); $func.ReturnExpression = $returnExpression
    $script:Scopes = $oldScopes; $script:ActiveContext = $oldContext; $script:CurrentFunction = $oldFunction; $script:BlockDepth = $oldBlockDepth
}
function Parse-Module {
    param([object] $Module)
    $script:CurrentModule = $Module; $script:SourceDisplay = $Module.Path; $script:Tokens = $Module.Tokens; $script:TokenIndex = [int]$Module.BodyStartIndex
    while ((Get-CurrentToken).Kind -ne 'EOF') {
        $token = Get-CurrentToken
        if ($token.Kind -eq 'Identifier' -and $token.Text -ceq 'fn') { Parse-FunctionDeclaration; continue }
        if (-not $Module.IsRoot) { Throw-SourceError -Line $token.Line -Column $token.Column -Message 'Imported modules may contain function definitions and imports only; executable statements belong in the root source.' }
        $statement = Parse-Statement
        $script:MainStatements.Add($statement)
    }
}
function Get-ExpressionNodeCount {
    param([object] $Node)
    if ($null -eq $Node) { return 0 }
    $count = 1
    if ($Node.Kind -eq 'Binary' -or $Node.Kind -eq 'Comparison') { $count += (Get-ExpressionNodeCount -Node $Node.Left); $count += (Get-ExpressionNodeCount -Node $Node.Right) }
    elseif ($Node.Kind -eq 'Unary') { $count += (Get-ExpressionNodeCount -Node $Node.Operand) }
    elseif ($Node.Kind -eq 'Call') { foreach ($arg in $Node.Arguments) { $count += (Get-ExpressionNodeCount -Node $arg) } }
    return [int]$count
}
function Get-StatementsNodeCount {
    param([object[]] $Statements, [object] $ReturnExpression = $null)
    $count = 0
    foreach ($statement in $Statements) {
        if ($null -ne $statement.Expression) { $count += (Get-ExpressionNodeCount -Node $statement.Expression) }
        if ($null -ne $statement.Statements -and $statement.Statements.Count -gt 0) { $count += (Get-StatementsNodeCount -Statements $statement.Statements) }
        if ($null -ne $statement.ElseStatements -and $statement.ElseStatements.Count -gt 0) { $count += (Get-StatementsNodeCount -Statements $statement.ElseStatements) }
    }
    if ($null -ne $ReturnExpression) { $count += (Get-ExpressionNodeCount -Node $ReturnExpression) }
    return [int]$count
}
function Align-Up {
    param([int] $Value, [int] $Alignment)
    if ($Value -lt 0 -or $Alignment -le 0) { throw 'Invalid alignment request.' }
    return [int]([Math]::Ceiling([double]$Value / [double]$Alignment) * $Alignment)
}
function Emit-Bytes { param([byte[]] $Bytes) $script:Code.AddRange($Bytes) }
function Emit-I32 { param([long] $Value) if ($Value -lt [int]::MinValue -or $Value -gt [int]::MaxValue) { throw "Internal signed 32-bit immediate or displacement is out of range: $Value" }; $script:Code.AddRange([BitConverter]::GetBytes([int32]$Value)) }
function Emit-CallIat {
    param([UInt32] $TargetRva)
    # Call sites pass the stable Milestone 4 import RVA (base 0x3000).
    # Defer the displacement until the linker has selected the final .idata RVA.
    if ($TargetRva -lt 0x3000 -or $TargetRva -ge 0x4000) { throw ("Invalid canonical IAT target RVA: 0x{0:X8}." -f $TargetRva) }
    Emit-Bytes -Bytes ([byte[]]@(0xFF, 0x15))
    $dispOffset = $script:Code.Count
    Emit-I32 -Value 0
    $script:CodeFixups.Add([pscustomobject]@{ Kind = 'Iat'; DispOffset = $dispOffset; TargetOffset = [int]([long]$TargetRva - 0x3000) })
}
function Emit-DataAddress {
    param([object] $DataItem)
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8D, 0x05)); $dispOffset = $script:Code.Count; Emit-I32 -Value 0
    $script:CodeFixups.Add([pscustomobject]@{ Kind = 'Data'; DispOffset = $dispOffset; Target = $DataItem })
}
function Emit-CallDataPointer {
    param([object] $DataItem)
    if ($null -eq $DataItem -or $DataItem.Bytes.Length -ne 8) {
        throw 'Typed callback pointer call requires an eight-byte data pointer item.'
    }
    Emit-Bytes -Bytes ([byte[]]@(0xFF, 0x15))
    $dispOffset = $script:Code.Count
    Emit-I32 -Value 0
    $script:CodeFixups.Add([pscustomobject]@{ Kind = 'Data'; DispOffset = $dispOffset; Target = $DataItem })
}
function Emit-JumpConditional {
    param([byte] $ConditionCode, [string] $Label)
    Emit-Bytes -Bytes ([byte[]]@(0x0F, $ConditionCode)); $dispOffset = $script:Code.Count; Emit-I32 -Value 0
    $script:CodeFixups.Add([pscustomobject]@{ Kind = 'Code'; DispOffset = $dispOffset; Target = $Label })
}
function Emit-Jump {
    param([string] $Label)
    Emit-Bytes -Bytes ([byte[]]@(0xE9)); $dispOffset = $script:Code.Count; Emit-I32 -Value 0
    $script:CodeFixups.Add([pscustomobject]@{ Kind = 'Code'; DispOffset = $dispOffset; Target = $Label })
}
function New-UniqueLabel {
    param([string] $Prefix)
    $label = '__' + $Prefix + '_' + [string]$script:UniqueLabel
    $script:UniqueLabel++
    return $label
}
function Emit-StackArgumentImmediate {
    param([int] $Offset, [long] $Value)
    if ($Offset -lt 0x20 -or $Offset -gt 0x78 -or ($Offset % 8) -ne 0) { throw "Invalid Windows x64 stack argument offset: $Offset" }
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0xC7, 0x44, 0x24, [byte]$Offset)); Emit-I32 -Value $Value
}
function Emit-StackArgumentRax {
    param([int] $Offset)
    if ($Offset -lt 0x20 -or $Offset -gt 0x78 -or ($Offset % 8) -ne 0) { throw "Invalid Windows x64 stack argument offset: $Offset" }
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0x44, 0x24, [byte]$Offset))
}
function Emit-Win64CallIat {
    param([UInt32] $TargetRva, [object[]] $StackArguments = @())
    if ($StackArguments.Count -gt 12) { throw "Windows x64 IAT calls support at most 12 stack arguments; received $($StackArguments.Count)." }
    # Reserve shadow space plus all stack arguments, rounded to 16 bytes.
    $callFrameSize = Align-Up -Value (0x20 + ($StackArguments.Count * 8)) -Alignment 0x10
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x81, 0xEC))
    Emit-I32 -Value $callFrameSize
    for ($i = 0; $i -lt $StackArguments.Count; $i++) {
        $argument = $StackArguments[$i]
        switch ([string]$argument.Kind) {
            'Immediate' {
                Emit-Bytes -Bytes ([byte[]]@(0x48, 0xB8))
                Emit-Bytes -Bytes ([BitConverter]::GetBytes([Int64]$argument.Value))
            }
            'FrameAddress' { Emit-LeaRaxFrame -SlotPosition ([int]$argument.SlotPosition) }
            'FrameQword' { Emit-LoadRaxFrame -SlotPosition ([int]$argument.SlotPosition) }
            'FrameDword' { Emit-LoadEaxFrame -SlotPosition ([int]$argument.SlotPosition) }
            'DataAddress' { Emit-DataAddress -DataItem $argument.DataItem }
            'CodeAddress' { Emit-LeaRaxCodeLabel -Label ([string]$argument.Label) }
            default { throw "Unsupported Windows x64 stack-argument descriptor kind: '$($argument.Kind)'." }
        }
        Emit-StackArgumentRax -Offset (0x20 + ($i * 8))
    }
    Emit-CallIat -TargetRva $TargetRva
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x81, 0xC4))
    Emit-I32 -Value $callFrameSize
}
function Emit-LoadRdiFrame { param([int] $SlotPosition) Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8B, 0xBD)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $SlotPosition) }
function Emit-StoreRdiFrame { param([int] $SlotPosition) Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xBD)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $SlotPosition) }
function Emit-LoadRsiFrame { param([int] $SlotPosition) Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8B, 0xB5)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $SlotPosition) }
function Emit-StoreRsiFrame { param([int] $SlotPosition) Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xB5)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $SlotPosition) }
function Emit-LeaRaxFrame { param([int] $SlotPosition) Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8D, 0x85)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $SlotPosition) }
function Emit-LeaR8CodeLabel {
    param([string] $Label)
    Emit-Bytes -Bytes ([byte[]]@(0x4C, 0x8D, 0x05)); $dispOffset = $script:Code.Count; Emit-I32 -Value 0
    $script:CodeFixups.Add([pscustomobject]@{ Kind = 'Code'; DispOffset = $dispOffset; Target = $Label })
}
function Emit-LeaRaxCodeLabel {
    param([string] $Label)
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8D, 0x05))
    $dispOffset = $script:Code.Count
    Emit-I32 -Value 0
    $script:CodeFixups.Add([pscustomobject]@{ Kind = 'Code'; DispOffset = $dispOffset; Target = $Label })
}
function Emit-CallFunction {
    param([string] $Name)
    if (-not $script:Functions.ContainsKey($Name)) { throw "Internal linker error: unresolved function symbol '$Name'." }
    Emit-Bytes -Bytes ([byte[]]@(0xE8)); $dispOffset = $script:Code.Count; Emit-I32 -Value 0
    $script:CodeFixups.Add([pscustomobject]@{ Kind = 'Call'; DispOffset = $dispOffset; Target = $script:Functions[$Name].Label })
}
function Mark-CodeLabel { param([string] $Label) if ($script:CodeLabels.ContainsKey($Label)) { throw "Duplicate internal code label: $Label" }; $script:CodeLabels.Add($Label, $script:Code.Count) }
function Get-FrameDisp {
    param([int] $SlotPosition)
    $disp = [long]$SlotPosition - [long]$script:ActiveContext.FrameSize
    if ($disp -ge 0 -or $disp -lt [int]::MinValue) { throw "Invalid stack-frame slot position: $SlotPosition" }
    return [int32]$disp
}
function Emit-LoadEaxFrame { param([int] $SlotPosition) Emit-Bytes -Bytes ([byte[]]@(0x8B, 0x85)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $SlotPosition) }
function Emit-StoreEaxFrame { param([int] $SlotPosition) Emit-Bytes -Bytes ([byte[]]@(0x89, 0x85)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $SlotPosition) }
function Emit-LoadEdxFrame { param([int] $SlotPosition) Emit-Bytes -Bytes ([byte[]]@(0x8B, 0x95)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $SlotPosition) }
function Emit-StoreEdxFrame { param([int] $SlotPosition) Emit-Bytes -Bytes ([byte[]]@(0x89, 0x95)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $SlotPosition) }
function Emit-StoreEcxFrame { param([int] $SlotPosition) Emit-Bytes -Bytes ([byte[]]@(0x89, 0x8D)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $SlotPosition) }
function Emit-StoreR8dFrame { param([int] $SlotPosition) Emit-Bytes -Bytes ([byte[]]@(0x44, 0x89, 0x85)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $SlotPosition) }
function Emit-StoreR9dFrame { param([int] $SlotPosition) Emit-Bytes -Bytes ([byte[]]@(0x44, 0x89, 0x8D)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $SlotPosition) }
function Emit-LoadRaxFrame { param([int] $SlotPosition) Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8B, 0x85)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $SlotPosition) }
function Emit-StoreRaxFrame { param([int] $SlotPosition) Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0x85)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $SlotPosition) }
function Emit-LoadRcxFrame { param([int] $SlotPosition) Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8B, 0x8D)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $SlotPosition) }
function Emit-LeaRcxFrame { param([int] $SlotPosition) Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8D, 0x8D)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $SlotPosition) }
function Emit-LeaRdxFrame { param([int] $SlotPosition) Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8D, 0x95)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $SlotPosition) }
function Emit-LeaR9Frame { param([int] $SlotPosition) Emit-Bytes -Bytes ([byte[]]@(0x4C, 0x8D, 0x8D)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $SlotPosition) }
function Emit-StoreBits32Frame {
    param([int] $SlotPosition, [UInt32] $Value)
    Emit-Bytes -Bytes ([byte[]]@(0xC7, 0x85))
    Emit-I32 -Value (Get-FrameDisp -SlotPosition $SlotPosition)
    $script:Code.AddRange([BitConverter]::GetBytes([UInt32]$Value))
}
function Emit-StoreZero64Frame {
    param([int] $SlotPosition)
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0xC7, 0x85))
    Emit-I32 -Value (Get-FrameDisp -SlotPosition $SlotPosition)
    Emit-I32 -Value 0
}
function Emit-StoreImm64Frame {
    param([int] $SlotPosition, [UInt64] $Value)
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0xB8))
    $script:Code.AddRange([BitConverter]::GetBytes([UInt64]$Value))
    Emit-StoreRaxFrame -SlotPosition $SlotPosition
}
function Register-DataConstant {
    param([string] $Value)
    if ($script:DataMap.ContainsKey($Value)) { return $script:DataMap[$Value] }
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($Value); $itemBytes = [byte[]]::new($bytes.Length + 1)
    if ($bytes.Length -gt 0) { [System.Buffer]::BlockCopy($bytes, 0, $itemBytes, 0, $bytes.Length) }
    $item = [pscustomobject]@{ Value = $Value; Offset = $script:DataLength; Bytes = $itemBytes }
    $script:DataItems.Add($item); $script:DataMap.Add($Value, $item); $script:DataLength += $itemBytes.Length
    return $item
}
function Register-WideDataConstant {
    param([string] $Value)
    $key = 'WIDE:' + $Value
    if ($script:DataMap.ContainsKey($key)) { return $script:DataMap[$key] }
    $bytes = [System.Text.Encoding]::Unicode.GetBytes($Value + [char]0)
    $itemBytes = [byte[]]::new($bytes.Length)
    if ($bytes.Length -gt 0) { [System.Buffer]::BlockCopy($bytes, 0, $itemBytes, 0, $bytes.Length) }
    $item = [pscustomobject]@{ Value = $key; Offset = $script:DataLength; Bytes = $itemBytes }
    $script:DataItems.Add($item); $script:DataMap.Add($key, $item); $script:DataLength += $itemBytes.Length
    return $item
}
function Register-ByteDataConstant {
    param([string] $Key, [byte[]] $Bytes)
    if ($script:DataMap.ContainsKey($Key)) { return $script:DataMap[$Key] }
    $itemBytes = [byte[]]::new($Bytes.Length)
    if ($Bytes.Length -gt 0) { [System.Buffer]::BlockCopy($Bytes, 0, $itemBytes, 0, $Bytes.Length) }
    $item = [pscustomobject]@{ Value = $Key; Offset = $script:DataLength; Bytes = $itemBytes }
    $script:DataItems.Add($item); $script:DataMap.Add($Key, $item); $script:DataLength += $itemBytes.Length
    return $item
}
function Register-CodeCallbackPointer {
    param(
        [Parameter(Mandatory = $true)][string] $Key,
        [Parameter(Mandatory = $true)][string] $Label,
        [Parameter(Mandatory = $true)][ValidateSet('SERVICE_MAIN_FUNCTIONW', 'HANDLER_FUNCTION_EX')][string] $Signature
    )

    $existing = @($script:DataPointerFixups | Where-Object { $_.Key -ceq $Key })
    if ($existing.Count -gt 0) {
        if ($existing.Count -ne 1 -or $existing[0].Label -cne $Label -or $existing[0].Signature -cne $Signature) {
            throw "Callback pointer key '$Key' was registered with conflicting target metadata."
        }
        return $existing[0].DataItem
    }
    if ($script:DataMap.ContainsKey($Key)) { throw "Callback pointer data key collides with an existing constant: $Key" }
    if (-not $Label.StartsWith('__', [StringComparison]::Ordinal)) {
        throw 'Typed callback targets must use a compiler-owned internal code label.'
    }

    $signatureContract = switch ($Signature) {
        'SERVICE_MAIN_FUNCTIONW' { 'VOID WINAPI (DWORD, LPWSTR*)' }
        'HANDLER_FUNCTION_EX' { 'DWORD WINAPI (DWORD, DWORD, LPVOID, LPVOID)' }
        default { throw "Unsupported Windows callback signature: $Signature" }
    }
    $padding = (8 - ($script:DataLength % 8)) % 8
    if ($padding -gt 0) {
        if (($script:DataLength + $padding + 8) -gt 0x1000) { throw 'Callback pointer table exceeds .rdata capacity.' }
        $paddingBytes = [byte[]]::new($padding)
        $paddingItem = [pscustomobject]@{ Value = $Key + ':ALIGN'; Offset = $script:DataLength; Bytes = $paddingBytes }
        $script:DataItems.Add($paddingItem)
        $script:DataMap.Add($paddingItem.Value, $paddingItem)
        $script:DataLength += $padding
    }

    if (($script:DataLength + 8) -gt 0x1000) { throw 'Callback pointer table exceeds .rdata capacity.' }
    $pointerBytes = [byte[]]::new(8)
    $item = [pscustomobject]@{ Value = $Key; Offset = $script:DataLength; Bytes = $pointerBytes }
    $script:DataItems.Add($item)
    $script:DataMap.Add($Key, $item)
    $script:DataLength += 8
    $script:DataPointerFixups.Add([pscustomobject]@{
        Key = $Key
        Label = $Label
        Signature = $Signature
        Contract = $signatureContract
        DataItem = $item
        TargetRva = [UInt32]0
    })
    return $item
}
function Get-TempSlotPosition {
    param([int] $Depth)
    return [int](0x80 + ([int]$script:ActiveContext.SlotCount * 16) + ($Depth * 16))
}
function Emit-CreateFileForPath {
    param([int] $PathSlot, [switch] $OpenReparsePoint)
    Emit-LoadRaxFrame -SlotPosition $PathSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1)) # RCX = path
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x00, 0x00, 0x00, 0x80)) # GENERIC_READ
    Emit-Bytes -Bytes ([byte[]]@(0x41, 0xB8, 0x01, 0x00, 0x00, 0x00)) # FILE_SHARE_READ
    Emit-Bytes -Bytes ([byte[]]@(0x45, 0x33, 0xC9)) # lpSecurityAttributes = NULL
    $fileFlags = [UInt32]0x80 # FILE_ATTRIBUTE_NORMAL
    if ($OpenReparsePoint) { $fileFlags = [UInt32]0x00200080 } # FILE_FLAG_OPEN_REPARSE_POINT
    Emit-Win64CallIat -TargetRva ([UInt32]0x30A0) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 3 },
        @{ Kind = 'Immediate'; Value = $fileFlags },
        @{ Kind = 'Immediate'; Value = 0 }
    ) # CreateFileA
}
function Emit-BuiltinArguments {
    param([object] $Node, [int] $BaseDepth)
    for ($i = 0; $i -lt $Node.Arguments.Count; $i++) {
        $argument = $Node.Arguments[$i]
        if ($argument.Type -eq 'String') {
            Emit-StringExpression -Node $argument
            $slot = Get-TempSlotPosition -Depth $script:TempDepth
            Emit-StoreRaxFrame -SlotPosition $slot
            Emit-StoreEdxFrame -SlotPosition ($slot + 8)
        } else {
            Emit-IntegerExpression -Node $argument
            Emit-StoreEaxFrame -SlotPosition (Get-TempSlotPosition -Depth $script:TempDepth)
        }
        $script:TempDepth++
    }
}
function Emit-CopyDataConstantToFrame {
    param([object] $DataItem, [int] $SlotPosition, [int] $Length)
    if ($Length -lt 0 -or $Length -gt 1023) { throw "Invalid fixed command/data copy length: $Length" }
    Emit-DataAddress -DataItem $DataItem
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC6)) # RSI = immutable source
    Emit-LeaRaxFrame -SlotPosition $SlotPosition
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC7)) # RDI = mutable destination
    Emit-Bytes -Bytes ([byte[]]@(0xB9))
    Emit-I32 -Value $Length
    Emit-Bytes -Bytes ([byte[]]@(0xF3, 0xA4, 0xC6, 0x07, 0x00)) # REP MOVSB; append NUL
}
function Emit-NonvolatileRegisterProbe {
    param([object] $Node, [int] $BaseDepth)
    $targetName = 'abi_nonvolatile_target'
    if (-not $script:Functions.ContainsKey($targetName)) {
        Throw-SourceError -Line $Node.Line -Column $Node.Column -Message "The ABI sentinel probe requires a zero-argument function named '$targetName'."
    }
    if ($script:Functions[$targetName].Parameters.Count -ne 0) {
        Throw-SourceError -Line $Node.Line -Column $Node.Column -Message "The ABI sentinel target '$targetName' must not declare parameters."
    }
    $slots = @()
    for ($i = 0; $i -lt 8; $i++) { $slots += (Get-TempSlotPosition -Depth ($BaseDepth + $i)) }
    # Save the complete Windows x64 nonvolatile register set, including the
    # active RBP frame pointer, into caller-owned frame slots.
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xAD)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $slots[0]) # RBP
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0x9D)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $slots[1]) # RBX
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xB5)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $slots[2]) # RSI
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xBD)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $slots[3]) # RDI
    Emit-Bytes -Bytes ([byte[]]@(0x4C, 0x89, 0xA5)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $slots[4]) # R12
    Emit-Bytes -Bytes ([byte[]]@(0x4C, 0x89, 0xAD)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $slots[5]) # R13
    Emit-Bytes -Bytes ([byte[]]@(0x4C, 0x89, 0xB5)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $slots[6]) # R14
    Emit-Bytes -Bytes ([byte[]]@(0x4C, 0x89, 0xBD)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $slots[7]) # R15

    $sentinels = @([UInt32]0x11223344, [UInt32]0x22334455, [UInt32]0x33445566, [UInt32]0x44556677, [UInt32]0x55667788, [UInt32]0x66778899, [UInt32]0x778899AA)
    $loadOpcodes = @(
        [byte[]]@(0x48, 0xBB), [byte[]]@(0x48, 0xBE), [byte[]]@(0x48, 0xBF),
        [byte[]]@(0x49, 0xBC), [byte[]]@(0x49, 0xBD), [byte[]]@(0x49, 0xBE), [byte[]]@(0x49, 0xBF)
    )
    for ($i = 0; $i -lt $sentinels.Count; $i++) {
        Emit-Bytes -Bytes $loadOpcodes[$i]
        Emit-Bytes -Bytes ([BitConverter]::GetBytes([UInt64]$sentinels[$i]))
    }
    # Verify live RSP is 16-byte aligned before the call, after reserving
    # shadow space, and after return. Exercise a generated function containing
    # RSI/RDI-using intrinsics while all nonvolatile registers hold sentinels.
    $fail = New-UniqueLabel -Prefix 'abi_nonvolatile_fail'
    $done = New-UniqueLabel -Prefix 'abi_nonvolatile_done'
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xE0, 0x83, 0xE0, 0x0F, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $fail
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x20))
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xE0, 0x83, 0xE0, 0x0F, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $fail
    Emit-CallFunction -Name $targetName
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20))
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xE0, 0x83, 0xE0, 0x0F, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $fail

    $compareOpcodes = @(
        [byte[]]@(0x48, 0x81, 0xFB), [byte[]]@(0x48, 0x81, 0xFE), [byte[]]@(0x48, 0x81, 0xFF),
        [byte[]]@(0x49, 0x81, 0xFC), [byte[]]@(0x49, 0x81, 0xFD), [byte[]]@(0x49, 0x81, 0xFE), [byte[]]@(0x49, 0x81, 0xFF)
    )
    for ($i = 0; $i -lt $sentinels.Count; $i++) {
        Emit-Bytes -Bytes $compareOpcodes[$i]
        Emit-I32 -Value ([Int64]$sentinels[$i])
        Emit-JumpConditional -ConditionCode 0x85 -Label $fail
    }
    # RBP is the live frame pointer: compare it to the saved caller value.
    Emit-LoadRaxFrame -SlotPosition $slots[0]
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x39, 0xC5))
    Emit-JumpConditional -ConditionCode 0x85 -Label $fail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x01, 0x00, 0x00, 0x00))
    Emit-Jump -Label $done
    Mark-CodeLabel -Label $fail
    Emit-Bytes -Bytes ([byte[]]@(0x31, 0xC0))
    Mark-CodeLabel -Label $done

    # Restore the caller's original nonvolatile values before returning.
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8B, 0x9D)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $slots[1])
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8B, 0xB5)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $slots[2])
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8B, 0xBD)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $slots[3])
    Emit-Bytes -Bytes ([byte[]]@(0x4C, 0x8B, 0xA5)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $slots[4])
    Emit-Bytes -Bytes ([byte[]]@(0x4C, 0x8B, 0xAD)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $slots[5])
    Emit-Bytes -Bytes ([byte[]]@(0x4C, 0x8B, 0xB5)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $slots[6])
    Emit-Bytes -Bytes ([byte[]]@(0x4C, 0x8B, 0xBD)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $slots[7])
}
function Emit-DevBrokerPathCheck {
    param(
        [object] $DataItem = $null,
        [int] $FrameSlot = -1,
        [bool] $IsDirectory,
        [string] $FailureLabel
    )
    if ($FrameSlot -ge 0) {
        Emit-LeaRaxFrame -SlotPosition $FrameSlot
    }
    else {
        if ($null -eq $DataItem) { throw 'DevAgent path check requires a fixed path.' }
        Emit-DataAddress -DataItem $DataItem
    }
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31C8) -StackArguments @() # GetFileAttributesA
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0xFF, 0xFF, 0xFF, 0xFF))
    Emit-JumpConditional -ConditionCode 0x84 -Label $FailureLabel # INVALID_FILE_ATTRIBUTES
    if ($IsDirectory) {
        Emit-Bytes -Bytes ([byte[]]@(0xA9, 0x10, 0x00, 0x00, 0x00))
        Emit-JumpConditional -ConditionCode 0x84 -Label $FailureLabel # must be a directory
    }
    else {
        Emit-Bytes -Bytes ([byte[]]@(0xA9, 0x10, 0x00, 0x00, 0x00))
        Emit-JumpConditional -ConditionCode 0x85 -Label $FailureLabel # must not be a directory
    }
    Emit-Bytes -Bytes ([byte[]]@(0xA9, 0x00, 0x04, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x85 -Label $FailureLabel # reject FILE_ATTRIBUTE_REPARSE_POINT
}
function Emit-DevBrokerVerifyScript {
    param(
        [object] $PathItem = $null,
        [int] $FrameSlot = -1,
        [string] $ExpectedSha256,
        [int] $PersistentFileHandleSlot,
        [string] $FailureLabel
    )
    if ($ExpectedSha256.Length -ne 64) { throw 'DevAgent script SHA-256 must contain 64 hexadecimal characters.' }
    $scratch = [int]$script:ActiveContext.ScratchPosition
    $pathSlot = $scratch + 0x640
    $sizeSlot = $scratch + 0x648
    $bytesReadSlot = $scratch + 0x650
    $bufferSlot = $scratch + 0x658
    $algorithmSlot = $scratch + 0x660
    $digestSlot = $scratch + 0x680
    $hashFail = New-UniqueLabel -Prefix 'dev_hash_fail'
    $skipAlgorithmCleanup = New-UniqueLabel -Prefix 'dev_hash_skip_algorithm_cleanup'
    $skipBufferCleanup = New-UniqueLabel -Prefix 'dev_hash_skip_buffer_cleanup'
    $skipFileCleanup = New-UniqueLabel -Prefix 'dev_hash_skip_file_cleanup'
    $done = New-UniqueLabel -Prefix 'dev_hash_done'

    Emit-StoreZero64Frame -SlotPosition $PersistentFileHandleSlot
    Emit-StoreZero64Frame -SlotPosition $sizeSlot
    Emit-StoreZero64Frame -SlotPosition $bytesReadSlot
    Emit-StoreZero64Frame -SlotPosition $bufferSlot
    Emit-StoreZero64Frame -SlotPosition $algorithmSlot
    if ($FrameSlot -ge 0) {
        Emit-LeaRaxFrame -SlotPosition $FrameSlot
    } elseif ($null -ne $PathItem) {
        Emit-DataAddress -DataItem $PathItem
    } else {
        throw 'DevAgent script verification requires an absolute frame-backed or fixed path.'
    }
    Emit-StoreRaxFrame -SlotPosition $pathSlot

    # Open for read only and deny concurrent write/delete; retain handle through child completion.
    Emit-CreateFileForPath -PathSlot $pathSlot -OpenReparsePoint
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xF8, 0xFF))
    Emit-JumpConditional -ConditionCode 0x84 -Label $hashFail
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $hashFail
    Emit-StoreRaxFrame -SlotPosition $PersistentFileHandleSlot

    # Inspect the opened object itself, not only the path string. OPEN_REPARSE_POINT
    # prevents CreateFileA from silently following a final-component symbolic link.
    $fileInformationSlot = $scratch + 0x6A0
    Emit-StoreZero64Frame -SlotPosition $fileInformationSlot
    Emit-LoadRcxFrame -SlotPosition $PersistentFileHandleSlot
    Emit-LeaRaxFrame -SlotPosition $fileInformationSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3208) -StackArguments @() # GetFileInformationByHandle
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $hashFail
    Emit-Bytes -Bytes ([byte[]]@(0x8B, 0x85))
    Emit-I32 -Value (Get-FrameDisp -SlotPosition $fileInformationSlot) # dwFileAttributes
    Emit-Bytes -Bytes ([byte[]]@(0xF7, 0xC0))
    Emit-I32 -Value 0x410 # reject FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT
    Emit-JumpConditional -ConditionCode 0x85 -Label $hashFail

    # Bound the exact script size to 1 MiB.
    Emit-LoadRcxFrame -SlotPosition $PersistentFileHandleSlot
    Emit-LeaRaxFrame -SlotPosition $sizeSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-Win64CallIat -TargetRva ([UInt32]0x30A8) -StackArguments @() # GetFileSizeEx
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $hashFail
    Emit-LoadRaxFrame -SlotPosition $sizeSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $hashFail
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x3D))
    Emit-I32 -Value 0x100000
    Emit-JumpConditional -ConditionCode 0x87 -Label $hashFail

    # Allocate and read one bounded buffer. Short reads fail closed.
    Emit-Bytes -Bytes ([byte[]]@(0x31, 0xC9))
    Emit-LoadEaxFrame -SlotPosition $sizeSlot
    Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC2, 0x41, 0xB8, 0x00, 0x30, 0x00, 0x00, 0x41, 0xB9, 0x04, 0x00, 0x00, 0x00))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31D0) -StackArguments @() # VirtualAlloc
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $hashFail
    Emit-StoreRaxFrame -SlotPosition $bufferSlot

    Emit-LoadRcxFrame -SlotPosition $PersistentFileHandleSlot
    Emit-LoadRaxFrame -SlotPosition $bufferSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-LoadEaxFrame -SlotPosition $sizeSlot
    Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC0))
    Emit-LeaRaxFrame -SlotPosition $bytesReadSlot
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x30B0) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 0 }
    ) # ReadFile
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $hashFail
    Emit-LoadEaxFrame -SlotPosition $bytesReadSlot
    Emit-Bytes -Bytes ([byte[]]@(0x3B, 0x85))
    Emit-I32 -Value (Get-FrameDisp -SlotPosition $sizeSlot)
    Emit-JumpConditional -ConditionCode 0x85 -Label $hashFail

    # BCryptOpenAlgorithmProvider(&algorithm, L"SHA256", NULL, 0).
    Emit-LeaRaxFrame -SlotPosition $algorithmSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    $sha256Name = Register-WideDataConstant -Value 'SHA256'
    Emit-DataAddress -DataItem $sha256Name
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2, 0x45, 0x33, 0xC0, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31E8) -StackArguments @()
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $hashFail

    # BCryptHash(algorithm, NULL, 0, input, inputSize, digest, 32).
    Emit-LoadRcxFrame -SlotPosition $algorithmSlot
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xD2, 0x45, 0x33, 0xC0))
    Emit-LoadRaxFrame -SlotPosition $bufferSlot
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31F0) -StackArguments @(
        @{ Kind = 'FrameDword'; SlotPosition = $sizeSlot },
        @{ Kind = 'FrameAddress'; SlotPosition = $digestSlot },
        @{ Kind = 'Immediate'; Value = 32 }
    )
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $hashFail

    Emit-LoadRcxFrame -SlotPosition $algorithmSlot
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xD2))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31F8) -StackArguments @()
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $hashFail
    Emit-StoreZero64Frame -SlotPosition $algorithmSlot

    Emit-LoadRcxFrame -SlotPosition $bufferSlot
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xD2, 0x41, 0xB8, 0x00, 0x80, 0x00, 0x00))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31D8) -StackArguments @()
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $hashFail
    Emit-StoreZero64Frame -SlotPosition $bufferSlot

    $hashBytes = [byte[]]::new(32)
    for ($i = 0; $i -lt 32; $i++) { $hashBytes[$i] = [Convert]::ToByte($ExpectedSha256.Substring($i * 2, 2), 16) }
    $expectedDigest = Register-ByteDataConstant -Key ('SHA256:' + $ExpectedSha256) -Bytes $hashBytes
    Emit-LeaRaxFrame -SlotPosition $digestSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC6))
    Emit-DataAddress -DataItem $expectedDigest
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC7, 0xB9, 0x20, 0x00, 0x00, 0x00, 0xFC, 0xF3, 0xA6))
    Emit-JumpConditional -ConditionCode 0x85 -Label $hashFail
    Emit-Jump -Label $done

    Mark-CodeLabel -Label $hashFail
    Emit-LoadRcxFrame -SlotPosition $algorithmSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
    Emit-JumpConditional -ConditionCode 0x84 -Label $skipAlgorithmCleanup
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xD2))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31F8) -StackArguments @()
    Mark-CodeLabel -Label $skipAlgorithmCleanup

    Emit-LoadRcxFrame -SlotPosition $bufferSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
    Emit-JumpConditional -ConditionCode 0x84 -Label $skipBufferCleanup
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xD2, 0x41, 0xB8, 0x00, 0x80, 0x00, 0x00))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31D8) -StackArguments @()
    Mark-CodeLabel -Label $skipBufferCleanup

    Emit-LoadRcxFrame -SlotPosition $PersistentFileHandleSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
    Emit-JumpConditional -ConditionCode 0x84 -Label $skipFileCleanup
    Emit-Win64CallIat -TargetRva ([UInt32]0x30B8) -StackArguments @()
    Emit-StoreZero64Frame -SlotPosition $PersistentFileHandleSlot
    Mark-CodeLabel -Label $skipFileCleanup
    Emit-Jump -Label $FailureLabel
    Mark-CodeLabel -Label $done
}

function Emit-DevBrokerRevokeLegacyAppContainerSid {
    param([int] $SidSlot, [string] $FailureLabel)
    $nameItem = Register-WideDataConstant -Value 'Sharnou.DevAgent.ProcessBroker.v1'
    $displayItem = Register-WideDataConstant -Value 'Sharnou Legacy Broker Profile (ACL Migration)'
    $descriptionItem = Register-WideDataConstant -Value 'Legacy zero-capability profile retained only for one-time workspace ACL revocation.'
    $alreadyExists = New-UniqueLabel -Prefix 'dev_legacy_appcontainer_exists'
    $done = New-UniqueLabel -Prefix 'dev_legacy_appcontainer_ready'
    Emit-StoreZero64Frame -SlotPosition $SidSlot
    Emit-DataAddress -DataItem $nameItem
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-DataAddress -DataItem $displayItem
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-DataAddress -DataItem $descriptionItem
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3278) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 0 },
        @{ Kind = 'FrameAddress'; SlotPosition = $SidSlot }
    ) # Create legacy profile only to derive its existing package SID
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $done
    Emit-Bytes -Bytes ([byte[]]@(0x3D))
    Emit-I32 -Value -2147024713 # HRESULT_FROM_WIN32(ERROR_ALREADY_EXISTS)
    Emit-JumpConditional -ConditionCode 0x84 -Label $alreadyExists
    Emit-Jump -Label $FailureLabel

    Mark-CodeLabel -Label $alreadyExists
    Emit-DataAddress -DataItem $nameItem
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-LeaRaxFrame -SlotPosition $SidSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3280) -StackArguments @() # DeriveAppContainerSidFromAppContainerName
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $FailureLabel

    Mark-CodeLabel -Label $done
    Emit-LoadRaxFrame -SlotPosition $SidSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $FailureLabel
}

function Emit-DevBrokerEnsureAppContainerSid {
    param(
        [int] $SidSlot,
        [int] $ProfileNameSlot,
        [int] $RandomSlot,
        [int] $DerivedSidSlot,
        [int] $ProfileCreatedSlot,
        [string] $FailureLabel
    )
    $prefixItem = Register-WideDataConstant -Value 'Sharnou.DevAgent.'
    $hexItem = Register-WideDataConstant -Value '0123456789abcdef'
    $displayItem = Register-WideDataConstant -Value 'Sharnou DevAgent execution'
    $descriptionItem = Register-WideDataConstant -Value 'Ephemeral zero-capability per-execution identity.'
    $hexLoop = New-UniqueLabel -Prefix 'dev_appcontainer_hex_loop'
    $randomCheckLoop = New-UniqueLabel -Prefix 'dev_appcontainer_random_check'
    $randomNonzero = New-UniqueLabel -Prefix 'dev_appcontainer_random_nonzero'
    $derivedSidFailure = New-UniqueLabel -Prefix 'dev_appcontainer_derived_sid_failure'
    $sidReady = New-UniqueLabel -Prefix 'dev_appcontainer_sid_ready'
    $helperFailure = New-UniqueLabel -Prefix 'dev_appcontainer_helper_failure'
    $helperDone = New-UniqueLabel -Prefix 'dev_appcontainer_helper_done'
    $savedRdiSlot = $RandomSlot + 0x20
    $savedRsiSlot = $RandomSlot + 0x28

    # This helper uses RSI/RDI for string construction; preserve the caller's
    # nonvolatile registers before any generated code or nested Win32 calls.
    Emit-StoreRdiFrame -SlotPosition $savedRdiSlot
    Emit-StoreRsiFrame -SlotPosition $savedRsiSlot
    Emit-StoreZero64Frame -SlotPosition $SidSlot
    Emit-StoreZero64Frame -SlotPosition $DerivedSidSlot
    Emit-StoreBits32Frame -SlotPosition $ProfileCreatedSlot -Value 0

    # A fresh 128-bit execution identifier comes from the system-preferred CNG RNG.
    # It is never derived from a process ID, timestamp, workspace path or user input.
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xC9)) # hAlgorithm = NULL
    Emit-LeaRaxFrame -SlotPosition $RandomSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2, 0x41, 0xB8, 0x10, 0x00, 0x00, 0x00, 0x41, 0xB9, 0x02, 0x00, 0x00, 0x00))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3330) -StackArguments @() # BCryptGenRandom(BCRYPT_USE_SYSTEM_PREFERRED_RNG)
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $FailureLabel

    # Reject the all-zero output even though it is cryptographically negligible.
    Emit-LeaRaxFrame -SlotPosition $RandomSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC6, 0x33, 0xC0, 0xB9))
    Emit-I32 -Value 16
    Mark-CodeLabel -Label $randomCheckLoop
    Emit-Bytes -Bytes ([byte[]]@(0x0A, 0x06, 0x48, 0xFF, 0xC6, 0xFF, 0xC9))
    Emit-JumpConditional -ConditionCode 0x85 -Label $randomCheckLoop
    Emit-Bytes -Bytes ([byte[]]@(0x84, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $randomNonzero
    Emit-Jump -Label $helperFailure
    Mark-CodeLabel -Label $randomNonzero

    # Build the bounded canonical profile name:
    # Sharnou.DevAgent.<32 lowercase hexadecimal characters>.
    Emit-DataAddress -DataItem $prefixItem
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC6)) # RSI = UTF-16 prefix
    Emit-LeaRaxFrame -SlotPosition $ProfileNameSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC7, 0xB9))
    Emit-I32 -Value 34 # 17 UTF-16 characters, excluding the terminator
    Emit-Bytes -Bytes ([byte[]]@(0xFC, 0xF3, 0xA4)) # CLD; REP MOVSB
    Emit-DataAddress -DataItem $hexItem
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC3)) # R11 = UTF-16 hexadecimal lookup table
    Emit-LeaRaxFrame -SlotPosition $RandomSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC6, 0x41, 0xBA, 0x10, 0x00, 0x00, 0x00)) # RSI=random, R10D=16
    Mark-CodeLabel -Label $hexLoop
    Emit-Bytes -Bytes ([byte[]]@(
        0x0F, 0xB6, 0x06,             # movzx eax, byte ptr [rsi]
        0x89, 0xC2,                   # mov edx,eax
        0xC1, 0xE8, 0x04,             # shr eax,4
        0x41, 0x0F, 0xB7, 0x04, 0x43, # movzx eax,word ptr [r11+rax*2]
        0x66, 0x89, 0x07,             # mov word ptr [rdi],ax
        0x48, 0x83, 0xC7, 0x02,       # add rdi,2
        0x83, 0xE2, 0x0F,             # and edx,0xf
        0x41, 0x0F, 0xB7, 0x04, 0x53, # movzx eax,word ptr [r11+rdx*2]
        0x66, 0x89, 0x07,             # mov word ptr [rdi],ax
        0x48, 0x83, 0xC7, 0x02,       # add rdi,2
        0x48, 0xFF, 0xC6,             # inc rsi
        0x41, 0xFF, 0xCA              # dec r10d
    ))
    Emit-JumpConditional -ConditionCode 0x85 -Label $hexLoop
    Emit-Bytes -Bytes ([byte[]]@(0x66, 0xC7, 0x07, 0x00, 0x00)) # UTF-16 NUL

    # CreateAppContainerProfile must create a new identity. There is deliberately
    # no ERROR_ALREADY_EXISTS adoption/derive fallback: collisions fail closed.
    Emit-LeaRaxFrame -SlotPosition $ProfileNameSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-DataAddress -DataItem $displayItem
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-DataAddress -DataItem $descriptionItem
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3278) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 0 },
        @{ Kind = 'FrameAddress'; SlotPosition = $SidSlot }
    ) # CreateAppContainerProfile, zero capabilities
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $FailureLabel
    Emit-StoreBits32Frame -SlotPosition $ProfileCreatedSlot -Value 1
    Emit-LoadRaxFrame -SlotPosition $SidSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $FailureLabel

    # Independently derive the SID from this exact name and require identical SID identity.
    Emit-LeaRaxFrame -SlotPosition $ProfileNameSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-LeaRaxFrame -SlotPosition $DerivedSidSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3280) -StackArguments @() # DeriveAppContainerSidFromAppContainerName
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $derivedSidFailure
    Emit-LoadRaxFrame -SlotPosition $DerivedSidSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $derivedSidFailure
    Emit-LoadRaxFrame -SlotPosition $SidSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-LoadRaxFrame -SlotPosition $DerivedSidSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3350) -StackArguments @() # EqualSid
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $derivedSidFailure
    Emit-Jump -Label $sidReady

    Mark-CodeLabel -Label $derivedSidFailure
    Emit-LoadRcxFrame -SlotPosition $DerivedSidSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
    $skipDerivedFree = New-UniqueLabel -Prefix 'dev_appcontainer_skip_derived_free'
    Emit-JumpConditional -ConditionCode 0x84 -Label $skipDerivedFree
    Emit-Win64CallIat -TargetRva ([UInt32]0x32A8) -StackArguments @() # FreeSid
    Emit-StoreZero64Frame -SlotPosition $DerivedSidSlot
    Mark-CodeLabel -Label $skipDerivedFree
    Emit-Jump -Label $helperFailure

    Mark-CodeLabel -Label $sidReady
    Emit-LoadRcxFrame -SlotPosition $DerivedSidSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x32A8) -StackArguments @() # FreeSid
    Emit-StoreZero64Frame -SlotPosition $DerivedSidSlot
    Emit-LoadRdiFrame -SlotPosition $savedRdiSlot
    Emit-LoadRsiFrame -SlotPosition $savedRsiSlot
    Emit-Jump -Label $helperDone

    Mark-CodeLabel -Label $helperFailure
    Emit-LoadRdiFrame -SlotPosition $savedRdiSlot
    Emit-LoadRsiFrame -SlotPosition $savedRsiSlot
    Emit-Jump -Label $FailureLabel
    Mark-CodeLabel -Label $helperDone
}
function Emit-DevBrokerDeleteOwnedAppContainerProfile {
    param(
        [int] $ProfileNameSlot,
        [int] $ProfileCreatedSlot,
        [int] $ChildActiveSlot,
        [int] $TransactionActiveSlot,
        [int] $ResultSlot
    )
    $skip = New-UniqueLabel -Prefix 'dev_appcontainer_delete_skip'
    $deleted = New-UniqueLabel -Prefix 'dev_appcontainer_delete_success'
    $failed = New-UniqueLabel -Prefix 'dev_appcontainer_delete_failed'
    Emit-LoadEaxFrame -SlotPosition $ChildActiveSlot
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $skip
    Emit-LoadEaxFrame -SlotPosition $TransactionActiveSlot
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $skip
    Emit-LoadEaxFrame -SlotPosition $ProfileCreatedSlot
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $skip

    # The child token, process, thread and Job Object handles have already been
    # closed. Retry the indeterminate-profile failure once, but never report success
    # when Windows could not confirm deletion.
    Emit-LeaRaxFrame -SlotPosition $ProfileNameSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3340) -StackArguments @() # DeleteAppContainerProfile
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $deleted
    Emit-LeaRaxFrame -SlotPosition $ProfileNameSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3340) -StackArguments @() # retry DeleteAppContainerProfile
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed
    Mark-CodeLabel -Label $deleted
    Emit-StoreBits32Frame -SlotPosition $ProfileCreatedSlot -Value 0
    Emit-Jump -Label $skip

    Mark-CodeLabel -Label $failed
    Emit-Bytes -Bytes ([byte[]]@(0xB8))
    Emit-I32 -Value -134 # profile cleanup failed; never treat the execution as successful
    Emit-StoreEaxFrame -SlotPosition $ResultSlot
    Mark-CodeLabel -Label $skip
}

function Emit-DevBrokerUpdateAcl {
    param(
        [int] $PathSlot,
        [int] $SidSlot,
        [UInt32] $AccessMask,
        [UInt32] $AccessMode,
        [bool] $SetLowIntegrityLabel = $false,
        [string] $FailureLabel
    )
    $scratch = [int]$script:ActiveContext.ScratchPosition
    $handleSlot = $scratch + 0xD10
    $fileInfoSlot = $scratch + 0xD18
    $oldAclSlot = $scratch + 0xD50
    $securityDescriptorSlot = $scratch + 0xD58
    $newAclSlot = $scratch + 0xD60
    $explicitSlot = $scratch + 0xD70
    $failedSlot = $scratch + 0xDA0
    $mandatoryLabelAclSlot = $scratch + 0xDA8
    $failed = New-UniqueLabel -Prefix 'dev_acl_handle_failed'
    $done = New-UniqueLabel -Prefix 'dev_acl_handle_done'
    Emit-StoreZero64Frame -SlotPosition $handleSlot
    Emit-StoreZero64Frame -SlotPosition $oldAclSlot
    Emit-StoreZero64Frame -SlotPosition $securityDescriptorSlot
    Emit-StoreZero64Frame -SlotPosition $newAclSlot
    Emit-StoreBits32Frame -SlotPosition $failedSlot -Value 0
    for ($i = 0; $i -lt 7; $i++) { Emit-StoreZero64Frame -SlotPosition ($fileInfoSlot + ($i * 8)) }

    # Open the directory itself with READ_CONTROL | WRITE_DAC | WRITE_OWNER and
    # OPEN_REPARSE_POINT. WRITE_OWNER is needed for LABEL_SECURITY_INFORMATION.
    Emit-LeaRaxFrame -SlotPosition $PathSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1, 0xBA, 0x00, 0x00, 0x0E, 0x00, 0x41, 0xB8, 0x07, 0x00, 0x00, 0x00, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x30A0) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 3 },          # OPEN_EXISTING
        @{ Kind = 'Immediate'; Value = 0x02200080 }, # BACKUP_SEMANTICS | OPEN_REPARSE_POINT | NORMAL
        @{ Kind = 'Immediate'; Value = 0 }
    ) # CreateFileA(directory)
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xF8, 0xFF))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-StoreRaxFrame -SlotPosition $handleSlot

    # Validate the exact opened directory object; path-string checks are not enough.
    Emit-LoadRcxFrame -SlotPosition $handleSlot
    Emit-LeaRaxFrame -SlotPosition $fileInfoSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3208) -StackArguments @() # GetFileInformationByHandle
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-LoadEaxFrame -SlotPosition $fileInfoSlot
    Emit-Bytes -Bytes ([byte[]]@(0xA9, 0x10, 0x00, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed # FILE_ATTRIBUTE_DIRECTORY required
    Emit-Bytes -Bytes ([byte[]]@(0xA9, 0x00, 0x04, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed # FILE_ATTRIBUTE_REPARSE_POINT forbidden

    # GetSecurityInfo(handle, SE_FILE_OBJECT, DACL_SECURITY_INFORMATION, NULL, NULL, &oldDacl, NULL, &sd).
    Emit-LoadRcxFrame -SlotPosition $handleSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x01, 0x00, 0x00, 0x00, 0x41, 0xB8, 0x04, 0x00, 0x00, 0x00, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x32C8) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 0 }, # ppsidGroup
        @{ Kind = 'FrameAddress'; SlotPosition = $oldAclSlot },
        @{ Kind = 'Immediate'; Value = 0 }, # ppSacl
        @{ Kind = 'FrameAddress'; SlotPosition = $securityDescriptorSlot }
    ) # GetSecurityInfo
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed
    Emit-LoadRaxFrame -SlotPosition $oldAclSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed # a NULL DACL is never accepted

    # EXPLICIT_ACCESS_A (48 bytes), package SID trustee. SET_ACCESS is idempotent.
    Emit-StoreBits32Frame -SlotPosition $explicitSlot -Value $AccessMask
    Emit-StoreBits32Frame -SlotPosition ($explicitSlot + 4) -Value $AccessMode
    Emit-StoreBits32Frame -SlotPosition ($explicitSlot + 8) -Value 3 # OBJECT_INHERIT_ACE | CONTAINER_INHERIT_ACE
    Emit-StoreZero64Frame -SlotPosition ($explicitSlot + 16) # pMultipleTrustee
    Emit-StoreBits32Frame -SlotPosition ($explicitSlot + 24) -Value 0 # NO_MULTIPLE_TRUSTEE
    Emit-StoreBits32Frame -SlotPosition ($explicitSlot + 28) -Value 0 # TRUSTEE_IS_SID
    Emit-StoreBits32Frame -SlotPosition ($explicitSlot + 32) -Value 1 # TRUSTEE_IS_USER
    Emit-LoadRaxFrame -SlotPosition $SidSlot
    Emit-StoreRaxFrame -SlotPosition ($explicitSlot + 40)

    Emit-Bytes -Bytes ([byte[]]@(0xB9, 0x01, 0x00, 0x00, 0x00)) # count = 1
    Emit-LeaRaxFrame -SlotPosition $explicitSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2)) # RDX = EXPLICIT_ACCESS
    Emit-LoadRaxFrame -SlotPosition $oldAclSlot
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0)) # R8 = old DACL
    Emit-LeaR9Frame -SlotPosition $newAclSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x3298) -StackArguments @() # SetEntriesInAclA
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed

    # A low-integrity AppContainer is subject to MIC before DACL evaluation.
    # SetSecurityInfo(LABEL_SECURITY_INFORMATION) installs an inheritable Low IL
    # SYSTEM_MANDATORY_LABEL_ACE on Build staging only; workspace source remains
    # at its existing integrity level and is read-only in the package DACL.
    if ($SetLowIntegrityLabel) {
        # ACL header: revision 2, size 28, one ACE. ACE: SYSTEM_MANDATORY_LABEL,
        # OI|CI, size 20, NO_WRITE_UP, SID S-1-16-4096 (Low Mandatory Level).
        Emit-StoreImm64Frame -SlotPosition $mandatoryLabelAclSlot -Value ([UInt64]0x00000001001C0002)
        Emit-StoreBits32Frame -SlotPosition ($mandatoryLabelAclSlot + 8) -Value 0x00140311
        Emit-StoreBits32Frame -SlotPosition ($mandatoryLabelAclSlot + 12) -Value 1
        Emit-StoreImm64Frame -SlotPosition ($mandatoryLabelAclSlot + 16) -Value ([UInt64]0x1000000000000101)
        Emit-StoreBits32Frame -SlotPosition ($mandatoryLabelAclSlot + 24) -Value 0x00001000
        $securityInformation = 0x14 # DACL_SECURITY_INFORMATION | LABEL_SECURITY_INFORMATION
        $saclArgument = @{ Kind = 'FrameAddress'; SlotPosition = $mandatoryLabelAclSlot }
    }
    else {
        $securityInformation = 0x04 # DACL_SECURITY_INFORMATION only
        $saclArgument = @{ Kind = 'Immediate'; Value = 0 }
    }

    Emit-LoadRcxFrame -SlotPosition $handleSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x01, 0x00, 0x00, 0x00, 0x41, 0xB8))
    Emit-I32 -Value $securityInformation
    Emit-Bytes -Bytes ([byte[]]@(0x45, 0x33, 0xC9)) # pOwner = NULL
    Emit-Win64CallIat -TargetRva ([UInt32]0x32D0) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 0 }, # pSidGroup
        @{ Kind = 'FrameQword'; SlotPosition = $newAclSlot },
        $saclArgument
    ) # SetSecurityInfo
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed
    Emit-Jump -Label $done

    Mark-CodeLabel -Label $failed
    Emit-StoreBits32Frame -SlotPosition $failedSlot -Value 1
    Mark-CodeLabel -Label $done

    # LocalFree both allocations returned by the security APIs; close the directory handle.
    foreach ($slot in @($newAclSlot, $securityDescriptorSlot)) {
        $skipFree = New-UniqueLabel -Prefix 'dev_acl_handle_skip_free'
        Emit-LoadRcxFrame -SlotPosition $slot
        Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
        Emit-JumpConditional -ConditionCode 0x84 -Label $skipFree
        Emit-Win64CallIat -TargetRva ([UInt32]0x3260) -StackArguments @() # LocalFree
        Mark-CodeLabel -Label $skipFree
    }
    $skipClose = New-UniqueLabel -Prefix 'dev_acl_handle_skip_close'
    Emit-LoadRcxFrame -SlotPosition $handleSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
    Emit-JumpConditional -ConditionCode 0x84 -Label $skipClose
    Emit-Win64CallIat -TargetRva ([UInt32]0x30B8) -StackArguments @() # CloseHandle
    Mark-CodeLabel -Label $skipClose

    Emit-LoadEaxFrame -SlotPosition $failedSlot
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $FailureLabel
}

function Emit-DevBrokerCaptureSecurityDescriptor {
    param(
        [int] $PathSlot,
        [int] $DescriptorSlot,
        [int] $LengthSlot,
        [string] $FailureLabel
    )
    $scratch = [int]$script:ActiveContext.ScratchPosition
    $handleSlot = $scratch + 0xD10
    $fileInfoSlot = $scratch + 0xD18
    $daclSlot = $scratch + 0xD50
    $saclSlot = $scratch + 0xD58
    $failed = New-UniqueLabel -Prefix 'dev_acl_snapshot_failed'
    $done = New-UniqueLabel -Prefix 'dev_acl_snapshot_done'
    Emit-StoreZero64Frame -SlotPosition $handleSlot
    Emit-StoreZero64Frame -SlotPosition $DescriptorSlot
    Emit-StoreZero64Frame -SlotPosition $daclSlot
    Emit-StoreZero64Frame -SlotPosition $saclSlot
    Emit-StoreBits32Frame -SlotPosition $LengthSlot -Value 0
    for ($i = 0; $i -lt 7; $i++) { Emit-StoreZero64Frame -SlotPosition ($fileInfoSlot + ($i * 8)) }

    Emit-LeaRaxFrame -SlotPosition $PathSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1, 0xBA, 0x00, 0x00, 0x02, 0x00, 0x45, 0x33, 0xC0, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x30A0) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 3 },
        @{ Kind = 'Immediate'; Value = 0x02200080 },
        @{ Kind = 'Immediate'; Value = 0 }
    )
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xF8, 0xFF))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-StoreRaxFrame -SlotPosition $handleSlot

    Emit-LoadRcxFrame -SlotPosition $handleSlot
    Emit-LeaRaxFrame -SlotPosition $fileInfoSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3208) -StackArguments @()
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-LoadEaxFrame -SlotPosition $fileInfoSlot
    Emit-Bytes -Bytes ([byte[]]@(0xA9, 0x10, 0x00, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-Bytes -Bytes ([byte[]]@(0xA9, 0x00, 0x04, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed

    # Capture DACL plus the mandatory integrity label. LABEL_SECURITY_INFORMATION
    # is queried with READ_CONTROL; no general SACL privilege is requested.
    Emit-LoadRcxFrame -SlotPosition $handleSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x01, 0x00, 0x00, 0x00, 0x41, 0xB8, 0x14, 0x00, 0x00, 0x00, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x32C8) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 0 },
        @{ Kind = 'FrameAddress'; SlotPosition = $daclSlot },
        @{ Kind = 'FrameAddress'; SlotPosition = $saclSlot },
        @{ Kind = 'FrameAddress'; SlotPosition = $DescriptorSlot }
    )
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed
    Emit-LoadRaxFrame -SlotPosition $daclSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-LoadRcxFrame -SlotPosition $DescriptorSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x32F8) -StackArguments @()
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-LoadRcxFrame -SlotPosition $DescriptorSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x32F0) -StackArguments @()
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x14, 0x00, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x82 -Label $failed
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x00, 0x40, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x87 -Label $failed
    Emit-StoreEaxFrame -SlotPosition $LengthSlot
    Emit-Jump -Label $done

    Mark-CodeLabel -Label $failed
    Mark-CodeLabel -Label $done
    Emit-LoadRcxFrame -SlotPosition $handleSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
    $skipClose = New-UniqueLabel -Prefix 'dev_acl_snapshot_skip_close'
    Emit-JumpConditional -ConditionCode 0x84 -Label $skipClose
    Emit-Win64CallIat -TargetRva ([UInt32]0x30B8) -StackArguments @()
    Mark-CodeLabel -Label $skipClose
    # The caller owns any returned security descriptor and frees it in common cleanup.
    Emit-LoadRcxFrame -SlotPosition $DescriptorSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
    Emit-JumpConditional -ConditionCode 0x84 -Label $FailureLabel
    Emit-LoadEaxFrame -SlotPosition $LengthSlot
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $FailureLabel
}

function Emit-DevBrokerRestoreSecurityDescriptor {
    param(
        [int] $PathSlot,
        [int] $DescriptorSlot,
        [bool] $RestoreLabel = $false,
        [string] $FailureLabel
    )
    $scratch = [int]$script:ActiveContext.ScratchPosition
    $handleSlot = $scratch + 0xD10
    $fileInfoSlot = $scratch + 0xD18
    $daclPresentSlot = $scratch + 0xD50
    $daclSlot = $scratch + 0xD58
    $daclDefaultedSlot = $scratch + 0xD60
    $saclPresentSlot = $scratch + 0xD68
    $saclSlot = $scratch + 0xD70
    $saclDefaultedSlot = $scratch + 0xD78
    $restoreStageSlot = $scratch + 0xE80
    $restoreErrorSlot = $scratch + 0xE84
    $actualDaclSlot = $scratch + 0xE88
    $actualSaclSlot = $scratch + 0xE90
    $actualDescriptorSlot = $scratch + 0xE98
    $failed = New-UniqueLabel -Prefix 'dev_acl_restore_failed'
    $done = New-UniqueLabel -Prefix 'dev_acl_restore_done'
    Emit-StoreZero64Frame -SlotPosition $handleSlot
    foreach ($slot in @($daclPresentSlot, $daclSlot, $daclDefaultedSlot, $saclPresentSlot, $saclSlot, $saclDefaultedSlot,
        $actualDaclSlot, $actualSaclSlot, $actualDescriptorSlot)) {
        Emit-StoreZero64Frame -SlotPosition $slot
    }
    for ($i = 0; $i -lt 7; $i++) { Emit-StoreZero64Frame -SlotPosition ($fileInfoSlot + ($i * 8)) }

    Emit-StoreBits32Frame -SlotPosition $restoreStageSlot -Value 1 # CreateFileA
    Emit-LeaRaxFrame -SlotPosition $PathSlot
    # Match the normal ACL-update handle: READ_CONTROL | WRITE_DAC | WRITE_OWNER,
    # with full share access so Windows can propagate restored inheritable ACEs.
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1, 0xBA, 0x00, 0x00, 0x0E, 0x00, 0x41, 0xB8, 0x07, 0x00, 0x00, 0x00, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x30A0) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 3 },
        @{ Kind = 'Immediate'; Value = 0x02200080 },
        @{ Kind = 'Immediate'; Value = 0 }
    )
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xF8, 0xFF))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-StoreRaxFrame -SlotPosition $handleSlot

    Emit-StoreBits32Frame -SlotPosition $restoreStageSlot -Value 2 # GetFileInformationByHandle + directory/reparse validation
    Emit-LoadRcxFrame -SlotPosition $handleSlot
    Emit-LeaRaxFrame -SlotPosition $fileInfoSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3208) -StackArguments @()
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-LoadEaxFrame -SlotPosition $fileInfoSlot
    Emit-Bytes -Bytes ([byte[]]@(0xA9, 0x10, 0x00, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-Bytes -Bytes ([byte[]]@(0xA9, 0x00, 0x04, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed

    Emit-StoreBits32Frame -SlotPosition $restoreStageSlot -Value 3 # IsValidSecurityDescriptor
    Emit-LoadRcxFrame -SlotPosition $DescriptorSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x32F8) -StackArguments @()
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed

    Emit-StoreBits32Frame -SlotPosition $restoreStageSlot -Value 4 # GetSecurityDescriptorDacl
    Emit-LoadRcxFrame -SlotPosition $DescriptorSlot
    Emit-LeaRaxFrame -SlotPosition $daclPresentSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-LeaRaxFrame -SlotPosition $daclSlot
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0))
    Emit-LeaRaxFrame -SlotPosition $daclDefaultedSlot
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x32E0) -StackArguments @()
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-LoadEaxFrame -SlotPosition $daclPresentSlot
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-LoadRaxFrame -SlotPosition $daclSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed

    if ($RestoreLabel) {
        Emit-StoreBits32Frame -SlotPosition $restoreStageSlot -Value 5 # GetSecurityDescriptorSacl
        Emit-LoadRcxFrame -SlotPosition $DescriptorSlot
        Emit-LeaRaxFrame -SlotPosition $saclPresentSlot
        Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
        Emit-LeaRaxFrame -SlotPosition $saclSlot
        Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0))
        Emit-LeaRaxFrame -SlotPosition $saclDefaultedSlot
        Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC1))
        Emit-Win64CallIat -TargetRva ([UInt32]0x32E8) -StackArguments @()
        Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
        Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    }

    Emit-StoreBits32Frame -SlotPosition $restoreStageSlot -Value 6 # SetSecurityInfo
    Emit-LoadRcxFrame -SlotPosition $handleSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x01, 0x00, 0x00, 0x00, 0x41, 0xB8))
    if ($RestoreLabel) {
        Emit-I32 -Value 0x14 # DACL_SECURITY_INFORMATION | LABEL_SECURITY_INFORMATION
        $restoreSaclArgument = @{ Kind = 'FrameQword'; SlotPosition = $saclSlot }
    }
    else {
        Emit-I32 -Value 0x04 # DACL_SECURITY_INFORMATION only; root label is never changed
        $restoreSaclArgument = @{ Kind = 'Immediate'; Value = 0 }
    }
    Emit-Bytes -Bytes ([byte[]]@(0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x32D0) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 0 },
        @{ Kind = 'FrameQword'; SlotPosition = $daclSlot },
        $restoreSaclArgument
    )
    Emit-StoreEaxFrame -SlotPosition $restoreErrorSlot # SetSecurityInfo returns a Win32 error code directly
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed

    # Read the descriptor back from the same opened object. Compare the complete
    # DACL byte sequence, and the SACL/mandatory-label bytes for Build directories,
    # before declaring restoration complete.
    Emit-StoreBits32Frame -SlotPosition $restoreStageSlot -Value 70 # GetSecurityInfo readback
    Emit-LoadRcxFrame -SlotPosition $handleSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x01, 0x00, 0x00, 0x00, 0x41, 0xB8, 0x14, 0x00, 0x00, 0x00, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x32C8) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 0 },
        @{ Kind = 'FrameAddress'; SlotPosition = $actualDaclSlot },
        @{ Kind = 'FrameAddress'; SlotPosition = $actualSaclSlot },
        @{ Kind = 'FrameAddress'; SlotPosition = $actualDescriptorSlot }
    ) # GetSecurityInfo(DACL + LABEL)
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed
    Emit-StoreBits32Frame -SlotPosition $restoreStageSlot -Value 71 # readback API succeeded

    # DACL must be byte-for-byte identical, including ACE order and flags.
    Emit-StoreBits32Frame -SlotPosition $restoreStageSlot -Value 72 # validate DACL pointers
    Emit-LoadRaxFrame -SlotPosition $daclSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC6, 0x48, 0x85, 0xF6))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-LoadRaxFrame -SlotPosition $actualDaclSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC7, 0x48, 0x85, 0xFF))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-StoreBits32Frame -SlotPosition $restoreStageSlot -Value 73 # validate DACL length
    Emit-Bytes -Bytes ([byte[]]@(0x0F, 0xB7, 0x46, 0x02, 0x0F, 0xB7, 0x57, 0x02, 0x39, 0xD0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed
    Emit-StoreBits32Frame -SlotPosition $restoreStageSlot -Value 74 # compare DACL bytes
    Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC1, 0xFC, 0xF3, 0xA6)) # CLD; REPE CMPSB
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed

    if ($RestoreLabel) {
        # NULL SACL is a legitimate original state. Treat NULL/NULL as an exact
        # match; reject only a presence mismatch or different SACL bytes.
        $compareSacl = New-UniqueLabel -Prefix 'dev_acl_restore_compare_sacl'
        $skipSaclCompare = New-UniqueLabel -Prefix 'dev_acl_restore_skip_sacl_compare'
        Emit-StoreBits32Frame -SlotPosition $restoreStageSlot -Value 75 # inspect expected SACL presence
        Emit-LoadRaxFrame -SlotPosition $saclSlot
        Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
        Emit-JumpConditional -ConditionCode 0x84 -Label $skipSaclCompare # expected NULL

        # Expected SACL is present: actual readback must also be present.
        Emit-StoreBits32Frame -SlotPosition $restoreStageSlot -Value 76 # actual SACL must be present
        Emit-LoadRaxFrame -SlotPosition $actualSaclSlot
        Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
        Emit-JumpConditional -ConditionCode 0x85 -Label $compareSacl
        Emit-Jump -Label $failed

        Mark-CodeLabel -Label $skipSaclCompare
        # Expected NULL: actual must also be NULL.
        Emit-StoreBits32Frame -SlotPosition $restoreStageSlot -Value 77 # actual SACL must also be NULL
        Emit-LoadRaxFrame -SlotPosition $actualSaclSlot
        Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
        Emit-JumpConditional -ConditionCode 0x85 -Label $failed
        $saclPresenceMatched = New-UniqueLabel -Prefix 'dev_acl_restore_sacl_presence_matched'
        Emit-Jump -Label $saclPresenceMatched

        Mark-CodeLabel -Label $compareSacl
        # Both SACLs are present: exact size and byte comparison is required.
        Emit-StoreBits32Frame -SlotPosition $restoreStageSlot -Value 78 # validate SACL lengths
        Emit-LoadRaxFrame -SlotPosition $saclSlot
        Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC6))
        Emit-LoadRaxFrame -SlotPosition $actualSaclSlot
        Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC7, 0x0F, 0xB7, 0x46, 0x02, 0x0F, 0xB7, 0x57, 0x02, 0x39, 0xD0))
        Emit-JumpConditional -ConditionCode 0x85 -Label $failed
        Emit-StoreBits32Frame -SlotPosition $restoreStageSlot -Value 79 # compare SACL bytes
        Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC1, 0xFC, 0xF3, 0xA6)) # CLD; REPE CMPSB
        Emit-JumpConditional -ConditionCode 0x85 -Label $failed
        Mark-CodeLabel -Label $saclPresenceMatched
    }

    Emit-StoreBits32Frame -SlotPosition $daclPresentSlot -Value 1
    Emit-StoreBits32Frame -SlotPosition $restoreStageSlot -Value 0
    Emit-Jump -Label $done

    Mark-CodeLabel -Label $failed
    Emit-StoreBits32Frame -SlotPosition $daclPresentSlot -Value 0
    Mark-CodeLabel -Label $done
    Emit-LoadRcxFrame -SlotPosition $actualDescriptorSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
    $skipFreeReadback = New-UniqueLabel -Prefix 'dev_acl_restore_skip_free_readback'
    Emit-JumpConditional -ConditionCode 0x84 -Label $skipFreeReadback
    Emit-Win64CallIat -TargetRva ([UInt32]0x3260) -StackArguments @() # LocalFree readback descriptor
    Emit-StoreZero64Frame -SlotPosition $actualDescriptorSlot
    Mark-CodeLabel -Label $skipFreeReadback
    Emit-LoadRcxFrame -SlotPosition $handleSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
    $skipClose = New-UniqueLabel -Prefix 'dev_acl_restore_skip_close'
    Emit-JumpConditional -ConditionCode 0x84 -Label $skipClose
    Emit-Win64CallIat -TargetRva ([UInt32]0x30B8) -StackArguments @()
    Mark-CodeLabel -Label $skipClose
    Emit-LoadEaxFrame -SlotPosition $daclPresentSlot
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $FailureLabel
}

function Emit-DevBrokerWriteAclJournal {
    param(
        [int] $JournalPathSlot,
        [int] $TempPathSlot,
        [int] $WorkspaceRootSlot,
        [int] $BuildPathSlot,
        [int] $BrokerDirectorySlot,
        [int] $JournalHandleSlot,
        [int] $JournalWrittenSlot,
        [int] $HeaderSlot,
        [int] $RootDescriptorSlot,
        [int] $BuildDescriptorSlot,
        [int] $BrokerDescriptorSlot,
        [int] $RootLengthSlot,
        [int] $BuildLengthSlot,
        [int] $BrokerLengthSlot,
        [int] $TransactionActiveSlot,
        [string] $FailureLabel
    )
    $scratch = [int]$script:ActiveContext.ScratchPosition
    $failed = New-UniqueLabel -Prefix 'dev_acl_journal_write_failed'
    $done = New-UniqueLabel -Prefix 'dev_acl_journal_write_done'
    Emit-DevBrokerCaptureSecurityDescriptor -PathSlot $WorkspaceRootSlot -DescriptorSlot $RootDescriptorSlot -LengthSlot $RootLengthSlot -FailureLabel $FailureLabel
    Emit-DevBrokerCaptureSecurityDescriptor -PathSlot $BuildPathSlot -DescriptorSlot $BuildDescriptorSlot -LengthSlot $BuildLengthSlot -FailureLabel $FailureLabel
    Emit-DevBrokerCaptureSecurityDescriptor -PathSlot $BrokerDirectorySlot -DescriptorSlot $BrokerDescriptorSlot -LengthSlot $BrokerLengthSlot -FailureLabel $FailureLabel

    # Fixed, versioned header followed by three bounded self-relative descriptors.
    Emit-StoreBits32Frame -SlotPosition $HeaderSlot -Value 0x52414853
    Emit-StoreBits32Frame -SlotPosition ($HeaderSlot + 4) -Value 0x314C4341
    Emit-StoreBits32Frame -SlotPosition ($HeaderSlot + 8) -Value 1
    Emit-StoreBits32Frame -SlotPosition ($HeaderSlot + 12) -Value 0
    Emit-LoadEaxFrame -SlotPosition $RootLengthSlot
    Emit-StoreEaxFrame -SlotPosition ($HeaderSlot + 16)
    Emit-LoadEaxFrame -SlotPosition $BuildLengthSlot
    Emit-StoreEaxFrame -SlotPosition ($HeaderSlot + 20)
    Emit-LoadEaxFrame -SlotPosition $BrokerLengthSlot
    Emit-StoreEaxFrame -SlotPosition ($HeaderSlot + 24)
    Emit-StoreBits32Frame -SlotPosition ($HeaderSlot + 28) -Value 0

    # A stale .tmp file means a prior write never reached the atomic commit point.
    Emit-LeaRaxFrame -SlotPosition $TempPathSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3310) -StackArguments @() # DeleteFileA (ignore missing)
    Emit-LeaRaxFrame -SlotPosition $TempPathSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1, 0xBA, 0x00, 0x00, 0x00, 0x40, 0x45, 0x33, 0xC0, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x30A0) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 1 },
        @{ Kind = 'Immediate'; Value = 0x80200002 },
        @{ Kind = 'Immediate'; Value = 0 }
    ) # CREATE_NEW | HIDDEN | OPEN_REPARSE_POINT | WRITE_THROUGH
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xF8, 0xFF))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-StoreRaxFrame -SlotPosition $JournalHandleSlot

    # Header write.
    Emit-LoadRcxFrame -SlotPosition $JournalHandleSlot
    Emit-LeaRaxFrame -SlotPosition $HeaderSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2, 0x41, 0xB8, 0x20, 0x00, 0x00, 0x00))
    Emit-LeaRaxFrame -SlotPosition $JournalWrittenSlot
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3078) -StackArguments @(@{ Kind = 'Immediate'; Value = 0 })
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-LoadEaxFrame -SlotPosition $JournalWrittenSlot
    Emit-Bytes -Bytes ([byte[]]@(0x83, 0xF8, 0x20))
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed

    foreach ($record in @(
        @{ Descriptor = $RootDescriptorSlot; Length = $RootLengthSlot },
        @{ Descriptor = $BuildDescriptorSlot; Length = $BuildLengthSlot },
        @{ Descriptor = $BrokerDescriptorSlot; Length = $BrokerLengthSlot }
    )) {
        Emit-LoadRcxFrame -SlotPosition $JournalHandleSlot
        Emit-LoadRaxFrame -SlotPosition $record.Descriptor
        Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
        Emit-LoadEaxFrame -SlotPosition $record.Length
        Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC0))
        Emit-LeaRaxFrame -SlotPosition $JournalWrittenSlot
        Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC1))
        Emit-Win64CallIat -TargetRva ([UInt32]0x3078) -StackArguments @(@{ Kind = 'Immediate'; Value = 0 })
        Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
        Emit-JumpConditional -ConditionCode 0x84 -Label $failed
        Emit-LoadEaxFrame -SlotPosition $JournalWrittenSlot
        Emit-Bytes -Bytes ([byte[]]@(0x3B, 0x85))
        Emit-I32 -Value (Get-FrameDisp -SlotPosition $record.Length)
        Emit-JumpConditional -ConditionCode 0x85 -Label $failed
    }

    Emit-LoadRcxFrame -SlotPosition $JournalHandleSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x3320) -StackArguments @() # FlushFileBuffers
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-LoadRcxFrame -SlotPosition $JournalHandleSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x30B8) -StackArguments @() # CloseHandle
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-StoreZero64Frame -SlotPosition $JournalHandleSlot

    # Same-volume rename is the transaction commit point. ACL changes are forbidden before it.
    Emit-LeaRaxFrame -SlotPosition $TempPathSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-LeaRaxFrame -SlotPosition $JournalPathSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2, 0x41, 0xB8, 0x08, 0x00, 0x00, 0x00))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3318) -StackArguments @() # MoveFileExA(MOVEFILE_WRITE_THROUGH)
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-StoreBits32Frame -SlotPosition $TransactionActiveSlot -Value 1
    Emit-Jump -Label $done

    Mark-CodeLabel -Label $failed
    Emit-LoadRcxFrame -SlotPosition $JournalHandleSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
    $skipClose = New-UniqueLabel -Prefix 'dev_acl_journal_skip_close'
    Emit-JumpConditional -ConditionCode 0x84 -Label $skipClose
    Emit-Win64CallIat -TargetRva ([UInt32]0x30B8) -StackArguments @()
    Emit-StoreZero64Frame -SlotPosition $JournalHandleSlot
    Mark-CodeLabel -Label $skipClose
    Emit-LeaRaxFrame -SlotPosition $TempPathSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3310) -StackArguments @()
    Emit-Jump -Label $FailureLabel
    Mark-CodeLabel -Label $done
}

function Emit-DevBrokerWriteDiagnosticPath {
    param([int] $PathSlot, [int] $PathLengthSlot)
    $scratch = [int]$script:ActiveContext.ScratchPosition
    $stdoutHandleSlot = $scratch + 0xD60
    $bytesWrittenSlot = $scratch + 0xD68
    $prefixItem = Register-DataConstant -Value 'ACL_RECOVERY_NATIVE_PATH|'
    $newlineItem = Register-ByteDataConstant -Key 'ACL_RECOVERY_NATIVE_PATH_NEWLINE' -Bytes ([byte[]]@(13, 10))
    $skip = New-UniqueLabel -Prefix 'dev_acl_recovery_path_diagnostic_skip'

    Emit-Bytes -Bytes ([byte[]]@(0xB9, 0xF5, 0xFF, 0xFF, 0xFF)) # STD_OUTPUT_HANDLE
    Emit-Win64CallIat -TargetRva ([UInt32]0x3070) -StackArguments @() # GetStdHandle
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xF8, 0xFF))
    Emit-JumpConditional -ConditionCode 0x84 -Label $skip
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $skip
    Emit-StoreRaxFrame -SlotPosition $stdoutHandleSlot

    Emit-LoadRcxFrame -SlotPosition $stdoutHandleSlot
    Emit-DataAddress -DataItem $prefixItem
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2, 0x41, 0xB8))
    Emit-I32 -Value ([int]($prefixItem.Bytes.Length - 1))
    Emit-LeaR9Frame -SlotPosition $bytesWrittenSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x3078) -StackArguments @(@{ Kind = 'Immediate'; Value = 0 }) # WriteFile

    Emit-LoadRcxFrame -SlotPosition $stdoutHandleSlot
    Emit-LeaRaxFrame -SlotPosition $PathSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-LoadEaxFrame -SlotPosition $PathLengthSlot
    Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC0)) # R8D = path length
    Emit-LeaR9Frame -SlotPosition $bytesWrittenSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x3078) -StackArguments @(@{ Kind = 'Immediate'; Value = 0 }) # WriteFile

    Emit-LoadRcxFrame -SlotPosition $stdoutHandleSlot
    Emit-DataAddress -DataItem $newlineItem
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2, 0x41, 0xB8, 0x02, 0x00, 0x00, 0x00))
    Emit-LeaR9Frame -SlotPosition $bytesWrittenSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x3078) -StackArguments @(@{ Kind = 'Immediate'; Value = 0 }) # WriteFile
    Mark-CodeLabel -Label $skip
}

function Emit-DevBrokerWriteRecoveryTokenDiagnostic {
    $scratch = [int]$script:ActiveContext.ScratchPosition
    $tokenHandleSlot = $scratch + 0xE80
    $tokenInfoSlot = $scratch + 0xE88
    $tokenReturnLengthSlot = $scratch + 0xE8C
    $appContainerSlot = $scratch + 0xE90
    $restrictedSlot = $scratch + 0xE94
    $elevationSlot = $scratch + 0xE98
    $openErrorSlot = $scratch + 0xE9C
    $queryErrorSlot = $scratch + 0xEA0
    $integrityInfoSlot = $scratch + 0xEA8
    $integrityReturnLengthSlot = $scratch + 0xF28
    $integrityRidSlot = $scratch + 0xF2C
    $textBufferSlot = $scratch + 0xF40
    $textLengthSlot = $scratch + 0xFC0
    $stdoutHandleSlot = $scratch + 0xD60
    $bytesWrittenSlot = $scratch + 0xD68
    $openFailed = New-UniqueLabel -Prefix 'dev_acl_recovery_token_open_failed'
    $queryLoopDone = New-UniqueLabel -Prefix 'dev_acl_recovery_token_queries_done'
    $formatReady = New-UniqueLabel -Prefix 'dev_acl_recovery_token_format_ready'
    Emit-StoreZero64Frame -SlotPosition $tokenHandleSlot
    foreach ($slot in @($tokenInfoSlot, $tokenReturnLengthSlot, $queryErrorSlot, $integrityInfoSlot, $integrityReturnLengthSlot, $integrityRidSlot)) {
        Emit-StoreZero64Frame -SlotPosition $slot
    }
    foreach ($slot in @($appContainerSlot, $restrictedSlot, $elevationSlot, $openErrorSlot)) {
        Emit-StoreBits32Frame -SlotPosition $slot -Value 0
    }

    # Query the broker's own primary token, not the PowerShell test harness token.
    # GetCurrentProcess() is the documented pseudo-handle value (HANDLE)-1.
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0xC7, 0xC1, 0xFF, 0xFF, 0xFF, 0xFF, 0xBA, 0x08, 0x00, 0x00, 0x00))
    Emit-Bytes -Bytes ([byte[]]@(0x4C, 0x8D, 0x85))
    Emit-I32 -Value (Get-FrameDisp -SlotPosition $tokenHandleSlot)
    Emit-Win64CallIat -TargetRva ([UInt32]0x32B0) -StackArguments @() # OpenProcessToken(TOKEN_QUERY)
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $openFailed
    Emit-StoreBits32Frame -SlotPosition $openErrorSlot -Value 0

    foreach ($query in @(
        @{ Class = 29; ValueSlot = $appContainerSlot }, # TokenIsAppContainer
        @{ Class = 21; ValueSlot = $restrictedSlot },   # TokenHasRestrictions
        @{ Class = 20; ValueSlot = $elevationSlot }     # TokenElevation
    )) {
        $queryFailed = New-UniqueLabel -Prefix 'dev_acl_recovery_token_query_failed'
        $queryDone = New-UniqueLabel -Prefix 'dev_acl_recovery_token_query_done'
        Emit-StoreZero64Frame -SlotPosition $tokenInfoSlot
        Emit-StoreZero64Frame -SlotPosition $tokenReturnLengthSlot
        Emit-LoadRcxFrame -SlotPosition $tokenHandleSlot
        Emit-Bytes -Bytes ([byte[]]@(0xBA))
        Emit-I32 -Value ([int]$query.Class)
        Emit-Bytes -Bytes ([byte[]]@(0x4C, 0x8D, 0x85))
        Emit-I32 -Value (Get-FrameDisp -SlotPosition $tokenInfoSlot)
        Emit-Bytes -Bytes ([byte[]]@(0x41, 0xB9, 0x04, 0x00, 0x00, 0x00))
        Emit-Win64CallIat -TargetRva ([UInt32]0x32D8) -StackArguments @(
            @{ Kind = 'FrameAddress'; SlotPosition = $tokenReturnLengthSlot }
        ) # GetTokenInformation(DWORD)
        Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
        Emit-JumpConditional -ConditionCode 0x84 -Label $queryFailed
        Emit-LoadEaxFrame -SlotPosition $tokenInfoSlot
        Emit-StoreEaxFrame -SlotPosition ([int]$query.ValueSlot)
        Emit-Jump -Label $queryDone
        Mark-CodeLabel -Label $queryFailed
        Emit-Win64CallIat -TargetRva ([UInt32]0x3268) -StackArguments @() # GetLastError
        Emit-StoreEaxFrame -SlotPosition $queryErrorSlot
        Emit-StoreBits32Frame -SlotPosition ([int]$query.ValueSlot) -Value 0
        Mark-CodeLabel -Label $queryDone
    }

    # TokenIntegrityLevel returns TOKEN_MANDATORY_LABEL (SID_AND_ATTRIBUTES).
    # Extract the final SID sub-authority RID: 0x1000 low, 0x2000 medium,
    # 0x3000 high, 0x4000 system.
    $integrityFailed = New-UniqueLabel -Prefix 'dev_acl_recovery_token_integrity_failed'
    $integrityDone = New-UniqueLabel -Prefix 'dev_acl_recovery_token_integrity_done'
    Emit-StoreZero64Frame -SlotPosition $integrityInfoSlot
    Emit-StoreZero64Frame -SlotPosition $integrityReturnLengthSlot
    Emit-LoadRcxFrame -SlotPosition $tokenHandleSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x19, 0x00, 0x00, 0x00)) # TokenIntegrityLevel = 25
    Emit-Bytes -Bytes ([byte[]]@(0x4C, 0x8D, 0x85))
    Emit-I32 -Value (Get-FrameDisp -SlotPosition $integrityInfoSlot)
    Emit-Bytes -Bytes ([byte[]]@(0x41, 0xB9, 0x80, 0x00, 0x00, 0x00)) # 128-byte TOKEN_MANDATORY_LABEL plus SID buffer
    Emit-Win64CallIat -TargetRva ([UInt32]0x32D8) -StackArguments @(
        @{ Kind = 'FrameAddress'; SlotPosition = $integrityReturnLengthSlot }
    ) # GetTokenInformation
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $integrityFailed
    Emit-LoadRaxFrame -SlotPosition $integrityInfoSlot # RAX = SID pointer
    Emit-Bytes -Bytes ([byte[]]@(0x0F, 0xB6, 0x48, 0x01, 0x85, 0xC9)) # MOVZX ECX,[RAX+1]; TEST ECX,ECX
    Emit-JumpConditional -ConditionCode 0x84 -Label $integrityFailed
    Emit-Bytes -Bytes ([byte[]]@(0xFF, 0xC9, 0x48, 0x8D, 0x44, 0x88, 0x08, 0x8B, 0x00)) # RID at SID+8+(count-1)*4
    Emit-StoreEaxFrame -SlotPosition $integrityRidSlot
    Emit-Jump -Label $integrityDone
    Mark-CodeLabel -Label $integrityFailed
    Emit-Win64CallIat -TargetRva ([UInt32]0x3268) -StackArguments @() # GetLastError
    Emit-StoreEaxFrame -SlotPosition $queryErrorSlot
    Emit-StoreBits32Frame -SlotPosition $integrityRidSlot -Value 0
    Mark-CodeLabel -Label $integrityDone

    Emit-LoadRcxFrame -SlotPosition $tokenHandleSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x30B8) -StackArguments @() # CloseHandle
    Emit-Jump -Label $formatReady

    Mark-CodeLabel -Label $openFailed
    Emit-Win64CallIat -TargetRva ([UInt32]0x3268) -StackArguments @() # GetLastError
    Emit-StoreEaxFrame -SlotPosition $openErrorSlot
    Mark-CodeLabel -Label $formatReady

    $formatItem = Register-DataConstant -Value "ACL_RECOVERY_TOKEN|appcontainer=%u|restricted=%u|elevation=%u|integrityRid=%u|openError=%u|queryError=%u`r`n"
    Emit-LeaRaxFrame -SlotPosition $textBufferSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-DataAddress -DataItem $formatItem
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-LoadEaxFrame -SlotPosition $appContainerSlot
    Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC0))
    Emit-LoadEaxFrame -SlotPosition $restrictedSlot
    Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3090) -StackArguments @(
        @{ Kind = 'FrameDword'; SlotPosition = $elevationSlot },
        @{ Kind = 'FrameDword'; SlotPosition = $integrityRidSlot },
        @{ Kind = 'FrameDword'; SlotPosition = $openErrorSlot },
        @{ Kind = 'FrameDword'; SlotPosition = $queryErrorSlot }
    ) # wsprintfA
    Emit-StoreEaxFrame -SlotPosition $textLengthSlot

    Emit-Bytes -Bytes ([byte[]]@(0xB9, 0xF5, 0xFF, 0xFF, 0xFF)) # STD_OUTPUT_HANDLE
    Emit-Win64CallIat -TargetRva ([UInt32]0x3070) -StackArguments @() # GetStdHandle
    Emit-StoreRaxFrame -SlotPosition $stdoutHandleSlot
    Emit-LoadRcxFrame -SlotPosition $stdoutHandleSlot
    Emit-LeaRaxFrame -SlotPosition $textBufferSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-LoadEaxFrame -SlotPosition $textLengthSlot
    Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC0))
    Emit-LeaR9Frame -SlotPosition $bytesWrittenSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x3078) -StackArguments @(@{ Kind = 'Immediate'; Value = 0 }) # WriteFile
}

function Emit-DevBrokerWriteRecoveryAttributeDiagnostic {
    param([int] $JournalPathSlot)
    $scratch = [int]$script:ActiveContext.ScratchPosition
    $attributeSlot = $scratch + 0xD70
    $errorSlot = $scratch + 0xD74
    # Keep the formatted diagnostic buffer disjoint from the DWORD length slot
    # and from the live recovery-stage value at D90.
    # Use a dedicated 128-byte area at the top of the reserved frame scratch.
    $textBufferSlot = $scratch + 0xF00
    $textLengthSlot = $scratch + 0xF80
    $stdoutHandleSlot = $scratch + 0xD60
    $bytesWrittenSlot = $scratch + 0xD68
    $attributeFailed = New-UniqueLabel -Prefix 'dev_acl_recovery_getattr_failed'
    $formatted = New-UniqueLabel -Prefix 'dev_acl_recovery_getattr_formatted'
    $formatItem = Register-DataConstant -Value "ACL_RECOVERY_GETATTR|attrs=0x%08X|error=%u`r`n"

    # Emit a fixed marker first using the same GetStdHandle/WriteFile path
    # already proven by the native path diagnostic. This isolates formatting/API
    # diagnostics from whether this emitted helper is actually entered.
    $markerItem = Register-DataConstant -Value 'ACL_RECOVERY_GETATTR|begin'
    Emit-Bytes -Bytes ([byte[]]@(0xB9, 0xF5, 0xFF, 0xFF, 0xFF)) # STD_OUTPUT_HANDLE
    Emit-Win64CallIat -TargetRva ([UInt32]0x3070) -StackArguments @()
    Emit-StoreRaxFrame -SlotPosition $stdoutHandleSlot
    Emit-LoadRcxFrame -SlotPosition $stdoutHandleSlot
    Emit-DataAddress -DataItem $markerItem
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2, 0x41, 0xB8))
    Emit-I32 -Value ($markerItem.Bytes.Length - 1)
    Emit-LeaR9Frame -SlotPosition $bytesWrittenSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x3078) -StackArguments @(@{ Kind = 'Immediate'; Value = 0 }) # WriteFile

    # Read-only path/metadata probe. This does not alter ACLs or open the journal.
    Emit-LeaRaxFrame -SlotPosition $JournalPathSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31C8) -StackArguments @() # GetFileAttributesA
    Emit-StoreEaxFrame -SlotPosition $attributeSlot
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0xFF, 0xFF, 0xFF, 0xFF))
    Emit-JumpConditional -ConditionCode 0x84 -Label $attributeFailed
    Emit-StoreBits32Frame -SlotPosition $errorSlot -Value 0
    Emit-Jump -Label $formatted
    Mark-CodeLabel -Label $attributeFailed
    Emit-Win64CallIat -TargetRva ([UInt32]0x3268) -StackArguments @() # GetLastError
    Emit-StoreEaxFrame -SlotPosition $errorSlot
    Mark-CodeLabel -Label $formatted

    Emit-LeaRaxFrame -SlotPosition $textBufferSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-DataAddress -DataItem $formatItem
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-LoadEaxFrame -SlotPosition $attributeSlot
    Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC0)) # R8D = attributes
    Emit-LoadEaxFrame -SlotPosition $errorSlot
    Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC1)) # R9D = Win32 error
    Emit-Win64CallIat -TargetRva ([UInt32]0x3090) -StackArguments @() # wsprintfA
    Emit-StoreEaxFrame -SlotPosition $textLengthSlot

    Emit-Bytes -Bytes ([byte[]]@(0xB9, 0xF5, 0xFF, 0xFF, 0xFF)) # STD_OUTPUT_HANDLE
    Emit-Win64CallIat -TargetRva ([UInt32]0x3070) -StackArguments @() # GetStdHandle
    Emit-StoreRaxFrame -SlotPosition $stdoutHandleSlot
    Emit-LoadRcxFrame -SlotPosition $stdoutHandleSlot
    Emit-LeaRaxFrame -SlotPosition $textBufferSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-LoadEaxFrame -SlotPosition $textLengthSlot
    Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC0))
    Emit-LeaR9Frame -SlotPosition $bytesWrittenSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x3078) -StackArguments @(@{ Kind = 'Immediate'; Value = 0 }) # WriteFile
}

function Emit-DevBrokerRecoverAclJournal {
    param(
        [int] $JournalPathSlot,
        [int] $PathLengthSlot,
        [int] $TempPathSlot,
        [int] $WorkspaceRootSlot,
        [int] $BuildPathSlot,
        [int] $BrokerDirectorySlot,
        [int] $JournalHandleSlot,
        [int] $JournalReadCountSlot,
        [int] $HeaderSlot,
        [int] $JournalBufferSlot,
        [int] $RootLengthSlot,
        [int] $BuildLengthSlot,
        [int] $BrokerLengthSlot,
        [int] $RootDescriptorSlot,
        [int] $BuildDescriptorSlot,
        [int] $BrokerDescriptorSlot,
        [string] $FailureLabel
    )
    $scratch = [int]$script:ActiveContext.ScratchPosition
    $fileInfoSlot = $scratch + 0xD18
    $expectedSizeSlot = $scratch + 0xD50
    $recoveryStageSlot = $scratch + 0xD90
    $failed = New-UniqueLabel -Prefix 'dev_acl_recovery_failed'
    $notFound = New-UniqueLabel -Prefix 'dev_acl_recovery_not_found'
    $restoreReady = New-UniqueLabel -Prefix 'dev_acl_recovery_restore_ready'
    $done = New-UniqueLabel -Prefix 'dev_acl_recovery_done'
    Emit-StoreZero64Frame -SlotPosition $JournalHandleSlot
    Emit-StoreZero64Frame -SlotPosition $JournalBufferSlot
    Emit-StoreBits32Frame -SlotPosition $JournalReadCountSlot -Value 0
    Emit-StoreBits32Frame -SlotPosition $recoveryStageSlot -Value 0
    for ($i = 0; $i -lt 7; $i++) { Emit-StoreZero64Frame -SlotPosition ($fileInfoSlot + ($i * 8)) }

    Emit-StoreBits32Frame -SlotPosition $recoveryStageSlot -Value 1 # open committed journal
    Emit-LeaRaxFrame -SlotPosition $JournalPathSlot
    # FILE_SHARE_READ permits independent readers while denying concurrent writes/deletes.
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1, 0xBA, 0x00, 0x00, 0x00, 0x80, 0x41, 0xB8, 0x01, 0x00, 0x00, 0x00, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x30A0) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 3 },
        @{ Kind = 'Immediate'; Value = 0x00200080 },
        @{ Kind = 'Immediate'; Value = 0 }
    )
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xF8, 0xFF))
    Emit-JumpConditional -ConditionCode 0x84 -Label $notFound
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $notFound
    Emit-StoreRaxFrame -SlotPosition $JournalHandleSlot
    Emit-StoreBits32Frame -SlotPosition $recoveryStageSlot -Value 2 # query journal file information
    Emit-Jump -Label $restoreReady

    Mark-CodeLabel -Label $notFound
    Emit-Win64CallIat -TargetRva ([UInt32]0x3268) -StackArguments @() # GetLastError after failed CreateFile
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x02, 0x00, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x84 -Label $done
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x03, 0x00, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x84 -Label $done
    # Preserve the original read-open error and emit the exact native path
    # to redirected stdout before the metadata-only probe.
    Emit-StoreEaxFrame -SlotPosition $expectedSizeSlot
    Emit-DevBrokerWriteDiagnosticPath -PathSlot $JournalPathSlot -PathLengthSlot $PathLengthSlot
    Emit-DevBrokerWriteRecoveryTokenDiagnostic
    Emit-DevBrokerWriteRecoveryAttributeDiagnostic -JournalPathSlot $JournalPathSlot
    Emit-LeaRaxFrame -SlotPosition $JournalPathSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1, 0x33, 0xD2, 0x41, 0xB8, 0x01, 0x00, 0x00, 0x00, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x30A0) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 3 },
        @{ Kind = 'Immediate'; Value = 0x00200080 },
        @{ Kind = 'Immediate'; Value = 0 }
    ) # CreateFileA metadata-only diagnostic
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xF8, 0xFF))
    $metadataProbeFailed = New-UniqueLabel -Prefix 'dev_acl_recovery_metadata_probe_failed'
    Emit-JumpConditional -ConditionCode 0x84 -Label $metadataProbeFailed
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $metadataProbeFailed
    Emit-StoreRaxFrame -SlotPosition $JournalHandleSlot
    Emit-LoadRcxFrame -SlotPosition $JournalHandleSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x30B8) -StackArguments @() # CloseHandle
    Emit-StoreZero64Frame -SlotPosition $JournalHandleSlot
    Emit-StoreBits32Frame -SlotPosition ($scratch + 0xD58) -Value 0
    $metadataProbeDone = New-UniqueLabel -Prefix 'dev_acl_recovery_metadata_probe_done'
    Emit-Jump -Label $metadataProbeDone
    Mark-CodeLabel -Label $metadataProbeFailed
    Emit-Win64CallIat -TargetRva ([UInt32]0x3268) -StackArguments @() # GetLastError for metadata-only probe
    Emit-StoreEaxFrame -SlotPosition ($scratch + 0xD58)
    Mark-CodeLabel -Label $metadataProbeDone
    # Encode original read error and metadata-only error as 1000 + read*256 + metadata.
    Emit-LoadEaxFrame -SlotPosition $expectedSizeSlot
    Emit-Bytes -Bytes ([byte[]]@(0xC1, 0xE0, 0x08))
    Emit-LoadEdxFrame -SlotPosition ($scratch + 0xD58)
    Emit-Bytes -Bytes ([byte[]]@(0x01, 0xD0, 0x05))
    Emit-I32 -Value 1000
    Emit-StoreEaxFrame -SlotPosition $recoveryStageSlot
    Emit-Jump -Label $FailureLabel

    Mark-CodeLabel -Label $restoreReady
    Emit-LoadRcxFrame -SlotPosition $JournalHandleSlot
    Emit-LeaRaxFrame -SlotPosition $fileInfoSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3208) -StackArguments @()
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-StoreBits32Frame -SlotPosition $recoveryStageSlot -Value 3 # validate journal file attributes, links and size
    Emit-LoadEaxFrame -SlotPosition $fileInfoSlot
    Emit-Bytes -Bytes ([byte[]]@(0xA9, 0x10, 0x00, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed
    Emit-Bytes -Bytes ([byte[]]@(0xA9, 0x00, 0x04, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed
    Emit-LoadEaxFrame -SlotPosition ($fileInfoSlot + 40)
    Emit-Bytes -Bytes ([byte[]]@(0x83, 0xF8, 0x01))
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed

    # Read and validate the 32-byte journal header before allocating bounded storage.
    Emit-StoreBits32Frame -SlotPosition $recoveryStageSlot -Value 4 # read fixed header
    Emit-LoadRcxFrame -SlotPosition $JournalHandleSlot
    Emit-LeaRaxFrame -SlotPosition $HeaderSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2, 0x41, 0xB8, 0x20, 0x00, 0x00, 0x00))
    Emit-LeaRaxFrame -SlotPosition $JournalReadCountSlot
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x30B0) -StackArguments @(@{ Kind = 'Immediate'; Value = 0 })
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-LoadEaxFrame -SlotPosition $JournalReadCountSlot
    Emit-Bytes -Bytes ([byte[]]@(0x83, 0xF8, 0x20))
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed
    # Distinguish the three header checks in the negative diagnostic status.
    Emit-StoreBits32Frame -SlotPosition $recoveryStageSlot -Value 50 # first signature DWORD
    Emit-LoadEaxFrame -SlotPosition $HeaderSlot
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x53, 0x48, 0x41, 0x52))
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed
    Emit-StoreBits32Frame -SlotPosition $recoveryStageSlot -Value 51 # second signature DWORD
    Emit-LoadEaxFrame -SlotPosition ($HeaderSlot + 4)
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x41, 0x43, 0x4C, 0x31))
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed
    Emit-StoreBits32Frame -SlotPosition $recoveryStageSlot -Value 52 # version
    Emit-LoadEaxFrame -SlotPosition ($HeaderSlot + 8)
    Emit-Bytes -Bytes ([byte[]]@(0x83, 0xF8, 0x01))
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed

    Emit-StoreBits32Frame -SlotPosition $recoveryStageSlot -Value 6 # validate descriptor lengths
    foreach ($record in @(
        @{ HeaderOffset = 16; LengthSlot = $RootLengthSlot },
        @{ HeaderOffset = 20; LengthSlot = $BuildLengthSlot },
        @{ HeaderOffset = 24; LengthSlot = $BrokerLengthSlot }
    )) {
        Emit-LoadEaxFrame -SlotPosition ($HeaderSlot + $record.HeaderOffset)
        Emit-Bytes -Bytes ([byte[]]@(0x83, 0xF8, 0x14))
        Emit-JumpConditional -ConditionCode 0x82 -Label $failed
        Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x00, 0x40, 0x00, 0x00))
        Emit-JumpConditional -ConditionCode 0x87 -Label $failed
        Emit-StoreEaxFrame -SlotPosition $record.LengthSlot
    }

    Emit-LoadEaxFrame -SlotPosition $RootLengthSlot
    Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC2))
    Emit-LoadEaxFrame -SlotPosition $BuildLengthSlot
    Emit-Bytes -Bytes ([byte[]]@(0x01, 0xD0, 0x89, 0xC2))
    Emit-LoadEaxFrame -SlotPosition $BrokerLengthSlot
    Emit-Bytes -Bytes ([byte[]]@(0x01, 0xD0, 0x83, 0xC0, 0x20))
    Emit-StoreEaxFrame -SlotPosition $expectedSizeSlot
    Emit-StoreBits32Frame -SlotPosition $recoveryStageSlot -Value 7 # validate exact journal file length
    Emit-LoadEaxFrame -SlotPosition ($fileInfoSlot + 32)
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed
    Emit-LoadEaxFrame -SlotPosition ($fileInfoSlot + 36)
    Emit-Bytes -Bytes ([byte[]]@(0x3B, 0x85))
    Emit-I32 -Value (Get-FrameDisp -SlotPosition $expectedSizeSlot)
    Emit-JumpConditional -ConditionCode 0x85 -Label $failed

    Emit-StoreBits32Frame -SlotPosition $recoveryStageSlot -Value 8 # allocate bounded descriptor buffer
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xC9, 0xBA, 0x00, 0xC0, 0x00, 0x00, 0x41, 0xB8, 0x00, 0x30, 0x00, 0x00, 0x41, 0xB9, 0x04, 0x00, 0x00, 0x00))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31D0) -StackArguments @() # VirtualAlloc(48 KiB)
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-StoreRaxFrame -SlotPosition $JournalBufferSlot

    $records = @(
        @{ Length = $RootLengthSlot; Offset = 0; Descriptor = $RootDescriptorSlot },
        @{ Length = $BuildLengthSlot; Offset = 0x4000; Descriptor = $BuildDescriptorSlot },
        @{ Length = $BrokerLengthSlot; Offset = 0x8000; Descriptor = $BrokerDescriptorSlot }
    )
    $recordStage = 9
    foreach ($record in $records) {
        Emit-StoreBits32Frame -SlotPosition $recoveryStageSlot -Value $recordStage # read exact descriptor bytes
        Emit-LoadRcxFrame -SlotPosition $JournalHandleSlot
        Emit-LoadRaxFrame -SlotPosition $JournalBufferSlot
        if ($record.Offset -ne 0) {
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0x05))
            Emit-I32 -Value $record.Offset
        }
        Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
        Emit-LoadEaxFrame -SlotPosition $record.Length
        Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC0))
        Emit-LeaRaxFrame -SlotPosition $JournalReadCountSlot
        Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC1))
        Emit-Win64CallIat -TargetRva ([UInt32]0x30B0) -StackArguments @(@{ Kind = 'Immediate'; Value = 0 })
        Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
        Emit-JumpConditional -ConditionCode 0x84 -Label $failed
        Emit-LoadEaxFrame -SlotPosition $JournalReadCountSlot
        Emit-Bytes -Bytes ([byte[]]@(0x3B, 0x85))
        Emit-I32 -Value (Get-FrameDisp -SlotPosition $record.Length)
        Emit-JumpConditional -ConditionCode 0x85 -Label $failed

        Emit-StoreBits32Frame -SlotPosition $recoveryStageSlot -Value ($recordStage + 1) # validate self-relative descriptor and exact length
        Emit-LoadRaxFrame -SlotPosition $JournalBufferSlot
        if ($record.Offset -ne 0) {
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0x05))
            Emit-I32 -Value $record.Offset
        }
        Emit-StoreRaxFrame -SlotPosition $record.Descriptor
        Emit-LoadRcxFrame -SlotPosition $record.Descriptor
        Emit-Win64CallIat -TargetRva ([UInt32]0x32F8) -StackArguments @()
        Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
        Emit-JumpConditional -ConditionCode 0x84 -Label $failed
        Emit-LoadRcxFrame -SlotPosition $record.Descriptor
        Emit-Win64CallIat -TargetRva ([UInt32]0x32F0) -StackArguments @()
        Emit-Bytes -Bytes ([byte[]]@(0x3B, 0x85))
        Emit-I32 -Value (Get-FrameDisp -SlotPosition $record.Length)
        Emit-JumpConditional -ConditionCode 0x85 -Label $failed
        $recordStage += 2
    }

    # Restore parents before descendants so each child snapshot wins after inheritance propagation.
    Emit-StoreBits32Frame -SlotPosition $recoveryStageSlot -Value 15 # restore workspace root
    Emit-DevBrokerRestoreSecurityDescriptor -PathSlot $WorkspaceRootSlot -DescriptorSlot $RootDescriptorSlot -FailureLabel $failed
    Emit-StoreBits32Frame -SlotPosition $recoveryStageSlot -Value 16 # restore Build
    Emit-DevBrokerRestoreSecurityDescriptor -PathSlot $BuildPathSlot -DescriptorSlot $BuildDescriptorSlot -RestoreLabel $true -FailureLabel $failed
    Emit-StoreBits32Frame -SlotPosition $recoveryStageSlot -Value 17 # restore broker directory
    Emit-DevBrokerRestoreSecurityDescriptor -PathSlot $BrokerDirectorySlot -DescriptorSlot $BrokerDescriptorSlot -RestoreLabel $true -FailureLabel $failed

    Emit-StoreBits32Frame -SlotPosition $recoveryStageSlot -Value 18 # close journal handle
    Emit-LoadRcxFrame -SlotPosition $JournalHandleSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x30B8) -StackArguments @()
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-StoreZero64Frame -SlotPosition $JournalHandleSlot
    Emit-StoreBits32Frame -SlotPosition $recoveryStageSlot -Value 19 # retire committed journal
    Emit-LeaRaxFrame -SlotPosition $JournalPathSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3310) -StackArguments @() # DeleteFileA after complete restore
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $failed
    Emit-Jump -Label $done

    Mark-CodeLabel -Label $failed
    Emit-LoadRcxFrame -SlotPosition $JournalHandleSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
    $skipClose = New-UniqueLabel -Prefix 'dev_acl_recovery_skip_close'
    Emit-JumpConditional -ConditionCode 0x84 -Label $skipClose
    Emit-Win64CallIat -TargetRva ([UInt32]0x30B8) -StackArguments @()
    Emit-StoreZero64Frame -SlotPosition $JournalHandleSlot
    Mark-CodeLabel -Label $skipClose
    foreach ($slot in @($RootDescriptorSlot, $BuildDescriptorSlot, $BrokerDescriptorSlot)) {
        Emit-StoreZero64Frame -SlotPosition $slot
    }
    Emit-LoadRcxFrame -SlotPosition $JournalBufferSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
    $skipFree = New-UniqueLabel -Prefix 'dev_acl_recovery_skip_free'
    Emit-JumpConditional -ConditionCode 0x84 -Label $skipFree
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xD2, 0x41, 0xB8, 0x00, 0x80, 0x00, 0x00))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31D8) -StackArguments @()
    Emit-StoreZero64Frame -SlotPosition $JournalBufferSlot
    Mark-CodeLabel -Label $skipFree
    Emit-Jump -Label $FailureLabel

    Mark-CodeLabel -Label $done
    # Pointers into the VirtualAlloc buffer must be cleared before it is freed;
    # common cleanup must never mistake these interior pointers for LocalAlloc blocks.
    $noBuffer = New-UniqueLabel -Prefix 'dev_acl_recovery_no_buffer'
    Emit-LoadRaxFrame -SlotPosition $JournalBufferSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $noBuffer
    foreach ($slot in @($RootDescriptorSlot, $BuildDescriptorSlot, $BrokerDescriptorSlot)) {
        Emit-StoreZero64Frame -SlotPosition $slot
    }
    Emit-LoadRcxFrame -SlotPosition $JournalBufferSlot
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xD2, 0x41, 0xB8, 0x00, 0x80, 0x00, 0x00))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31D8) -StackArguments @()
    Emit-StoreZero64Frame -SlotPosition $JournalBufferSlot
    Mark-CodeLabel -Label $noBuffer
    # No active journal means no ACL mutation is pending; remove an abandoned pre-commit temp.
    Emit-LeaRaxFrame -SlotPosition $TempPathSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3310) -StackArguments @() # DeleteFileA
}

function Emit-DevBrokerBuildWorkspacePath {
    param([int] $RootSlot, [int] $RootLengthSlot, [object] $SuffixItem, [int] $SuffixLength, [int] $DestinationSlot)
    if ($SuffixLength -lt 1 -or $SuffixLength -gt 240) { throw 'Invalid DevAgent workspace path suffix length.' }
    Emit-LeaRaxFrame -SlotPosition $DestinationSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC7)) # RDI = destination
    Emit-LeaRaxFrame -SlotPosition $RootSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC6, 0xFC)) # RSI = root; CLD
    Emit-LoadEaxFrame -SlotPosition $RootLengthSlot
    Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC1, 0xF3, 0xA4)) # copy root length
    Emit-DataAddress -DataItem $SuffixItem
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC6, 0xB9))
    Emit-I32 -Value $SuffixLength
    Emit-Bytes -Bytes ([byte[]]@(0xF3, 0xA4, 0xC6, 0x07, 0x00)) # suffix + NUL
}
function Emit-DevBrokerCheckDirectoryChain {
    param([int] $PathSlot, [string] $FailureLabel)
    $driveUpper = New-UniqueLabel -Prefix 'dev_path_drive_upper'
    $scanColon = New-UniqueLabel -Prefix 'dev_path_scan_colon'
    $colonDone = New-UniqueLabel -Prefix 'dev_path_colon_done'
    $scanComponents = New-UniqueLabel -Prefix 'dev_path_scan_components'
    $nextComponent = New-UniqueLabel -Prefix 'dev_path_next_component'
    $checkFinal = New-UniqueLabel -Prefix 'dev_path_check_final'

    # Require a drive-qualified DOS absolute path. UNC/device paths fail closed.
    Emit-Bytes -Bytes ([byte[]]@(0x0F, 0xB6, 0x85))
    Emit-I32 -Value (Get-FrameDisp -SlotPosition $PathSlot)
    Emit-Bytes -Bytes ([byte[]]@(0x3C, 0x41))
    Emit-JumpConditional -ConditionCode 0x82 -Label $FailureLabel
    Emit-Bytes -Bytes ([byte[]]@(0x3C, 0x5A))
    Emit-JumpConditional -ConditionCode 0x86 -Label $driveUpper
    Emit-Bytes -Bytes ([byte[]]@(0x3C, 0x61))
    Emit-JumpConditional -ConditionCode 0x82 -Label $FailureLabel
    Emit-Bytes -Bytes ([byte[]]@(0x3C, 0x7A))
    Emit-JumpConditional -ConditionCode 0x87 -Label $FailureLabel
    Mark-CodeLabel -Label $driveUpper
    Emit-Bytes -Bytes ([byte[]]@(0x80, 0xBD))
    Emit-I32 -Value (Get-FrameDisp -SlotPosition ($PathSlot + 1))
    Emit-Bytes -Bytes ([byte[]]@(0x3A))
    Emit-JumpConditional -ConditionCode 0x85 -Label $FailureLabel
    Emit-Bytes -Bytes ([byte[]]@(0x80, 0xBD))
    Emit-I32 -Value (Get-FrameDisp -SlotPosition ($PathSlot + 2))
    Emit-Bytes -Bytes ([byte[]]@(0x5C))
    Emit-JumpConditional -ConditionCode 0x85 -Label $FailureLabel

    # Reject alternate data streams in every character after the drive prefix.
    Emit-LeaRaxFrame -SlotPosition ($PathSlot + 2)
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC6))
    Mark-CodeLabel -Label $scanColon
    Emit-Bytes -Bytes ([byte[]]@(0x8A, 0x06, 0x84, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $colonDone
    Emit-Bytes -Bytes ([byte[]]@(0x3C, 0x3A))
    Emit-JumpConditional -ConditionCode 0x84 -Label $FailureLabel
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0xFF, 0xC6))
    Emit-Jump -Label $scanColon
    Mark-CodeLabel -Label $colonDone

    # Validate C:\ itself before walking subsequent components.
    Emit-LeaRaxFrame -SlotPosition ($PathSlot + 3)
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC6))
    # Use a dedicated byte slot rather than relying on a caller register across API calls.
    $savedByteSlot = [int]$script:ActiveContext.ScratchPosition + 0xDF0
    Emit-StoreZero64Frame -SlotPosition $savedByteSlot
    $rootAttributesSlot = [int]$script:ActiveContext.ScratchPosition + 0xDF8
    Emit-Bytes -Bytes ([byte[]]@(0x8A, 0x06, 0x88, 0x85))
    Emit-I32 -Value (Get-FrameDisp -SlotPosition $savedByteSlot)
    Emit-Bytes -Bytes ([byte[]]@(0xC6, 0x06, 0x00)) # temporarily end at C:\
    Emit-LeaRaxFrame -SlotPosition $PathSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31C8) -StackArguments @() # GetFileAttributesA(C:\)
    Emit-StoreEaxFrame -SlotPosition $rootAttributesSlot
    Emit-LoadEaxFrame -SlotPosition $savedByteSlot
    Emit-Bytes -Bytes ([byte[]]@(0x88, 0x06)) # restore first component byte
    Emit-LoadEaxFrame -SlotPosition $rootAttributesSlot
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0xFF, 0xFF, 0xFF, 0xFF))
    Emit-JumpConditional -ConditionCode 0x84 -Label $FailureLabel
    Emit-Bytes -Bytes ([byte[]]@(0xA9, 0x10, 0x00, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x84 -Label $FailureLabel
    Emit-Bytes -Bytes ([byte[]]@(0xA9, 0x00, 0x04, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x85 -Label $FailureLabel

    # Every intermediate component must be a non-reparse directory.
    Emit-LeaRaxFrame -SlotPosition ($PathSlot + 3)
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC6))
    Mark-CodeLabel -Label $scanComponents
    Emit-Bytes -Bytes ([byte[]]@(0x8A, 0x06, 0x84, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $checkFinal
    Emit-Bytes -Bytes ([byte[]]@(0x3C, 0x5C))
    Emit-JumpConditional -ConditionCode 0x85 -Label $nextComponent
    Emit-Bytes -Bytes ([byte[]]@(0xC6, 0x06, 0x00))
    Emit-LeaRaxFrame -SlotPosition $PathSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31C8) -StackArguments @()
    Emit-Bytes -Bytes ([byte[]]@(0xC6, 0x06, 0x5C))
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0xFF, 0xFF, 0xFF, 0xFF))
    Emit-JumpConditional -ConditionCode 0x84 -Label $FailureLabel
    Emit-Bytes -Bytes ([byte[]]@(0xA9, 0x10, 0x00, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x84 -Label $FailureLabel
    Emit-Bytes -Bytes ([byte[]]@(0xA9, 0x00, 0x04, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x85 -Label $FailureLabel
    Mark-CodeLabel -Label $nextComponent
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0xFF, 0xC6))
    Emit-Jump -Label $scanComponents
    Mark-CodeLabel -Label $checkFinal
    Emit-LeaRaxFrame -SlotPosition $PathSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31C8) -StackArguments @()
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0xFF, 0xFF, 0xFF, 0xFF))
    Emit-JumpConditional -ConditionCode 0x84 -Label $FailureLabel
    Emit-Bytes -Bytes ([byte[]]@(0xA9, 0x10, 0x00, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x84 -Label $FailureLabel
    Emit-Bytes -Bytes ([byte[]]@(0xA9, 0x00, 0x04, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x85 -Label $FailureLabel
}
function Emit-DevRunTool {
    param([int] $ToolSlot, [int] $TimeoutSlot, [int] $BaseDepth)
    $scratch = [int]$script:ActiveContext.ScratchPosition

    # Fixed frame layout. All child-visible paths/handles are broker-owned.
    $applicationSlot = $scratch + 0x000
    $modulePathSlot = $scratch + 0x120
    $workspaceRootSlot = $modulePathSlot
    $commandLineSlot = $scratch + 0x360
    $startupSlot = $scratch + 0x580
    $processSlot = $scratch + 0x600
    $jobInfoSlot = $scratch + 0x640
    $buildPathSlot = $scratch + 0x700
    $brokerDirectorySlot = $scratch + 0x820
    $outputPathSlot = $scratch + 0x940
    $attributeListSlot = $scratch + 0xA50
    $pipeReadSlot = $scratch + 0xA58
    $pipeWriteSlot = $scratch + 0xA60
    $nulHandleSlot = $scratch + 0xA68
    $attributeSizeSlot = $scratch + 0xA70
    $securityCapabilitiesSlot = $scratch + 0xA78
    $pipeSecuritySlot = $scratch + 0xA98
    $handleListSlot = $scratch + 0xAB0
    $outputBufferSlot = $scratch + 0xAC0
    $outputCountSlot = $scratch + 0xAC8
    $availableSlot = $scratch + 0xACC
    $readCountSlot = $scratch + 0xAD0
    $remainingMsSlot = $scratch + 0xAD4
    $outputFileHandleSlot = $scratch + 0xAD8
    $outputWrittenSlot = $scratch + 0xAE0
    $pipeClosedSlot = $scratch + 0xAE4
    $appContainerSidSlot = $scratch + 0xAE8
    $mutexHandleSlot = $scratch + 0xAF0
    $profileCreatedSlot = $scratch + 0xE7C
    $profileNameSlot = $scratch + 0xF00
    $profileRandomSlot = $scratch + 0xF80
    $derivedProfileSidSlot = $scratch + 0xF90
    $legacyAppContainerSidSlot = $scratch + 0xF98
    $mutexAcquiredSlot = $scratch + 0xAF8
    $attributeListReadySlot = $scratch + 0xAFC
    $childActiveSlot = $scratch + 0xB00
    $sourceTokenSlot = $scratch + 0xB08
    $restrictedTokenSlot = $scratch + 0xB10
    $childTokenSlot = $scratch + 0xB18
    $tokenInformationSlot = $scratch + 0xB38
    $tokenLengthSlot = $scratch + 0xB88
    $rootLengthSlot = $scratch + 0xB7C
    $modulePathLengthSlot = $scratch + 0xB80
    $pathScratchSlot = $scratch + 0xC00
    $outputFileInfoSlot = $scratch + 0xDA8
    $journalHeaderSlot = $scratch + 0xE10
    $journalHandleSlot = $scratch + 0xE30
    $journalWrittenSlot = $scratch + 0xE38
    $rootDescriptorSlot = $scratch + 0xE40
    $buildDescriptorSlot = $scratch + 0xE48
    $brokerDescriptorSlot = $scratch + 0xE50
    $rootDescriptorLengthSlot = $scratch + 0xE58
    $buildDescriptorLengthSlot = $scratch + 0xE5C
    $brokerDescriptorLengthSlot = $scratch + 0xE60
    $journalBufferSlot = $scratch + 0xE68
    $journalReadCountSlot = $scratch + 0xE70
    $transactionActiveSlot = $scratch + 0xE78
    $journalPathSlot = $pathScratchSlot
    $journalPathLengthSlot = $scratch + 0xD5C
    $journalTempPathSlot = $outputPathSlot

    $jobHandleSlot = Get-TempSlotPosition -Depth ($BaseDepth + 2)
    $saveRdiSlot = Get-TempSlotPosition -Depth ($BaseDepth + 3)
    $saveRsiSlot = Get-TempSlotPosition -Depth ($BaseDepth + 4)
    $resultSlot = Get-TempSlotPosition -Depth ($BaseDepth + 5)
    $exitCodeSlot = Get-TempSlotPosition -Depth ($BaseDepth + 6)
    $hashFileHandleSlot = Get-TempSlotPosition -Depth ($BaseDepth + 7)

    # Initialize every pointer, handle, and state flag before any branch reaches cleanup.
    foreach ($slot in @(
        $jobHandleSlot, $hashFileHandleSlot, $attributeListSlot, $pipeReadSlot,
        $pipeWriteSlot, $nulHandleSlot, $outputBufferSlot, $outputFileHandleSlot,
        $appContainerSidSlot, $legacyAppContainerSidSlot, $mutexHandleSlot, $sourceTokenSlot,
        $restrictedTokenSlot, $childTokenSlot, $journalHandleSlot,
        $rootDescriptorSlot, $buildDescriptorSlot, $brokerDescriptorSlot,
        $journalBufferSlot
    )) { Emit-StoreZero64Frame -SlotPosition $slot }
    foreach ($slot in @($journalWrittenSlot, $rootDescriptorLengthSlot, $buildDescriptorLengthSlot,
        $brokerDescriptorLengthSlot, $journalReadCountSlot, $transactionActiveSlot, $profileCreatedSlot)) {
        Emit-StoreBits32Frame -SlotPosition $slot -Value 0
    }
    Emit-StoreZero64Frame -SlotPosition $journalHeaderSlot
    for ($i = 0; $i -lt 3; $i++) { Emit-StoreZero64Frame -SlotPosition ($processSlot + ($i * 8)) }
    foreach ($slot in @(
        $mutexAcquiredSlot, $attributeListReadySlot, $childActiveSlot,
        $outputCountSlot, $availableSlot, $readCountSlot, $remainingMsSlot,
        $outputWrittenSlot, $pipeClosedSlot
    )) { Emit-StoreBits32Frame -SlotPosition $slot -Value 0 }
    Emit-StoreBits32Frame -SlotPosition $resultSlot -Value 0
    Emit-StoreZero64Frame -SlotPosition $tokenLengthSlot
    Emit-StoreZero64Frame -SlotPosition $modulePathLengthSlot
    Emit-StoreZero64Frame -SlotPosition $rootLengthSlot

    $unknownTool = New-UniqueLabel -Prefix 'dev_tool_unknown'
    $invalidTimeout = New-UniqueLabel -Prefix 'dev_tool_timeout_invalid'
    $toolLabels = @(
        (New-UniqueLabel -Prefix 'dev_tool_stage7a'),
        (New-UniqueLabel -Prefix 'dev_tool_runtime_abi'),
        (New-UniqueLabel -Prefix 'dev_tool_baseline_m1_m6'),
        (New-UniqueLabel -Prefix 'dev_tool_stack_unwind'),
        (New-UniqueLabel -Prefix 'dev_tool_timeout_probe'),
        (New-UniqueLabel -Prefix 'dev_tool_success_probe'),
        (New-UniqueLabel -Prefix 'dev_tool_sandbox_probe'),
        (New-UniqueLabel -Prefix 'dev_tool_output_overflow_probe'),
        (New-UniqueLabel -Prefix 'dev_tool_acl_crash_probe')
    )
    $commandReady = New-UniqueLabel -Prefix 'dev_tool_command_ready'
    $hashVerified = New-UniqueLabel -Prefix 'dev_tool_hash_verified'
    $hashFail = New-UniqueLabel -Prefix 'dev_tool_hash_fail'
    $pathFail = New-UniqueLabel -Prefix 'dev_tool_path_fail'
    $directoryFail = New-UniqueLabel -Prefix 'dev_tool_directory_fail'
    # Temporary fail-site codes isolate the repeated-invocation path preflight.
    $directoryFailImage = New-UniqueLabel -Prefix 'dev_tool_directory_fail_image'
    $directoryFailRoot = New-UniqueLabel -Prefix 'dev_tool_directory_fail_root'
    $directoryFailCwd = New-UniqueLabel -Prefix 'dev_tool_directory_fail_cwd'
    $directoryFailBuild = New-UniqueLabel -Prefix 'dev_tool_directory_fail_build'
    $directoryFailBroker = New-UniqueLabel -Prefix 'dev_tool_directory_fail_broker'
    $directoryFailFixed = New-UniqueLabel -Prefix 'dev_tool_directory_fail_fixed'
    $directoryFailCompiler = New-UniqueLabel -Prefix 'dev_tool_directory_fail_compiler'
    $mutexFail = New-UniqueLabel -Prefix 'dev_tool_mutex_fail'
    $appContainerFail = New-UniqueLabel -Prefix 'dev_tool_appcontainer_fail'
    $legacyAppContainerFail = New-UniqueLabel -Prefix 'dev_tool_legacy_appcontainer_fail'
    $aclFail = New-UniqueLabel -Prefix 'dev_tool_acl_fail'
    $aclRecoveryFail = New-UniqueLabel -Prefix 'dev_tool_acl_recovery_fail'
    $journalFail = New-UniqueLabel -Prefix 'dev_tool_acl_journal_fail'
    $aclRollbackFail = New-UniqueLabel -Prefix 'dev_tool_acl_rollback_fail'
    $aclRollbackRootFail = New-UniqueLabel -Prefix 'dev_tool_acl_rollback_root_fail'
    $aclRollbackBuildFail = New-UniqueLabel -Prefix 'dev_tool_acl_rollback_build_fail'
    $aclRollbackBrokerFail = New-UniqueLabel -Prefix 'dev_tool_acl_rollback_broker_fail'
    $aclRollbackJournalFail = New-UniqueLabel -Prefix 'dev_tool_acl_rollback_journal_fail'
    $tokenFail = New-UniqueLabel -Prefix 'dev_tool_token_fail'
    $pipeFail = New-UniqueLabel -Prefix 'dev_tool_pipe_fail'
    $attributeFail = New-UniqueLabel -Prefix 'dev_tool_attribute_fail'
    $jobFail = New-UniqueLabel -Prefix 'dev_tool_job_fail'
    $jobConfigFail = New-UniqueLabel -Prefix 'dev_tool_job_config_fail'
    $createFail = New-UniqueLabel -Prefix 'dev_tool_create_fail'
    $assignFail = New-UniqueLabel -Prefix 'dev_tool_assign_fail'
    $resumeFail = New-UniqueLabel -Prefix 'dev_tool_resume_fail'
    $waitFail = New-UniqueLabel -Prefix 'dev_tool_wait_fail'
    $timeoutFail = New-UniqueLabel -Prefix 'dev_tool_timeout'
    $outputOverflow = New-UniqueLabel -Prefix 'dev_tool_output_overflow'
    $outputFail = New-UniqueLabel -Prefix 'dev_tool_output_fail'
    $captureLoop = New-UniqueLabel -Prefix 'dev_tool_capture_loop'
    $capturePipeClosed = New-UniqueLabel -Prefix 'dev_tool_capture_pipe_closed'
    $capturePipeEof = New-UniqueLabel -Prefix 'dev_tool_capture_pipe_eof'
    $processDone = New-UniqueLabel -Prefix 'dev_tool_process_done'
    $finalDrain = New-UniqueLabel -Prefix 'dev_tool_final_drain'
    $finalPipeEof = New-UniqueLabel -Prefix 'dev_tool_final_pipe_eof'
    $captureDone = New-UniqueLabel -Prefix 'dev_tool_capture_done'
    $cleanup = New-UniqueLabel -Prefix 'dev_tool_cleanup'
    $done = New-UniqueLabel -Prefix 'dev_tool_done'

    $powerShellSuffix = '\WindowsPowerShell\v1.0\powershell.exe'
    $powerShellSuffixItem = Register-DataConstant -Value $powerShellSuffix
    $powerShellSuffixLength = [System.Text.Encoding]::ASCII.GetByteCount($powerShellSuffix)
    # Keep the trusted recovery host outside Low-IL writable Build staging.
    # A crash must not relabel the image used by the next recovery invocation.
    $imageSuffix = '\.sharnou-devagent-host\DevAgentBroker.exe'
    $imageSuffixItem = Register-DataConstant -Value $imageSuffix
    $imageSuffixLength = [System.Text.Encoding]::ASCII.GetByteCount($imageSuffix)
    $buildSuffix = '\Build'
    $buildSuffixItem = Register-DataConstant -Value $buildSuffix
    $buildSuffixLength = [System.Text.Encoding]::ASCII.GetByteCount($buildSuffix)
    $brokerSuffix = '\Build\DevAgentBroker'
    $brokerSuffixItem = Register-DataConstant -Value $brokerSuffix
    $brokerSuffixLength = [System.Text.Encoding]::ASCII.GetByteCount($brokerSuffix)
    $captureSuffix = '\Build\DevAgentBroker\captured-output.bin'
    $captureSuffixItem = Register-DataConstant -Value $captureSuffix
    $captureSuffixLength = [System.Text.Encoding]::ASCII.GetByteCount($captureSuffix)
    $journalSuffix = '\.sharnou-devagent-acl.journal'
    $journalSuffixItem = Register-DataConstant -Value $journalSuffix
    $journalSuffixLength = [System.Text.Encoding]::ASCII.GetByteCount($journalSuffix)
    $journalTempSuffix = '\.sharnou-devagent-acl.journal.tmp'
    $journalTempSuffixItem = Register-DataConstant -Value $journalTempSuffix
    $journalTempSuffixLength = [System.Text.Encoding]::ASCII.GetByteCount($journalTempSuffix)

    $manifestPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\Tests\DevAgentBroker\tool-manifest.json'))
    $expectedManifestSha256 = 'C74D82D29C73034A63E6A34113CFD9ED243BB4356D8B1318BEE7100E0E09AAFE'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'Pinned DevAgent tool manifest is missing.' }
    $actualManifestSha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash
    if ($actualManifestSha256 -cne $expectedManifestSha256) {
        throw "Pinned DevAgent tool manifest SHA-256 mismatch: expected=$expectedManifestSha256 actual=$actualManifestSha256"
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $fixedToolPaths = @(
        [pscustomobject]@{ Id = 1; Path = 'Tests\Test-Stage7A.ps1' },
        [pscustomobject]@{ Id = 2; Path = 'Tests\Test-RuntimeABI.ps1' },
        [pscustomobject]@{ Id = 3; Path = 'Tests\BaselineM6\Test-Milestone6Baseline.ps1' },
        [pscustomobject]@{ Id = 4; Path = 'Tests\Test-StackProbeUnwind.ps1' },
        [pscustomobject]@{ Id = 5; Path = 'Tests\DevAgentBroker\TimeoutProbe.ps1' },
        [pscustomobject]@{ Id = 6; Path = 'Tests\DevAgentBroker\SuccessProbe.ps1' },
        [pscustomobject]@{ Id = 7; Path = 'Tests\DevAgentBroker\SandboxProbe.ps1' },
        [pscustomobject]@{ Id = 8; Path = 'Tests\DevAgentBroker\OverflowProbe.ps1' },
        [pscustomobject]@{ Id = 9; Path = 'Tests\DevAgentBroker\CrashProbe.ps1' }
    )
    if ([int]$manifest.version -ne 1 -or @($manifest.tools).Count -ne $fixedToolPaths.Count) {
        throw 'Pinned DevAgent tool manifest version or fixed tool count is invalid.'
    }
    foreach ($fixedTool in $fixedToolPaths) {
        $entry = @($manifest.tools | Where-Object { [int]$_.id -eq $fixedTool.Id })
        $toolPath = Join-Path $PSScriptRoot ('..\' + $fixedTool.Path)
        if (-not (Test-Path -LiteralPath $toolPath -PathType Leaf)) { throw "Pinned DevAgent tool is missing: $($fixedTool.Path)" }
        $toolHash = (Get-FileHash -LiteralPath $toolPath -Algorithm SHA256).Hash
        if ($entry.Count -ne 1 -or [string]$entry[0].path -cne $fixedTool.Path -or [string]$entry[0].sha256 -cne $toolHash) {
            throw "Pinned DevAgent tool manifest path/hash mismatch for tool ID $($fixedTool.Id)."
        }
        $fixedTool | Add-Member -NotePropertyName Sha256 -NotePropertyValue ([string]$entry[0].sha256) -Force
        $fixedTool | Add-Member -NotePropertyName SuffixItem -NotePropertyValue (Register-DataConstant -Value ('\' + $fixedTool.Path)) -Force
        $fixedTool | Add-Member -NotePropertyName SuffixLength -NotePropertyValue ([System.Text.Encoding]::ASCII.GetByteCount('\' + $fixedTool.Path)) -Force
    }

    # Construct a bounded command line around the selected absolute path only after
    # it is canonicalized and hash-verified. The child never resolves a CWD-relative script.
    $commandPrefix = 'powershell.exe -NoLogo -NoProfile -NonInteractive -Command "$ErrorActionPreference=''Stop'';& '''
    $commandSuffix = ''';if($null -ne $global:SHARNOU_TOOL_EXIT_CODE){exit [int]$global:SHARNOU_TOOL_EXIT_CODE}"'
    $commandPrefixItem = Register-DataConstant -Value $commandPrefix
    $commandSuffixItem = Register-DataConstant -Value $commandSuffix
    $commandPrefixLength = [System.Text.Encoding]::ASCII.GetByteCount($commandPrefix)
    $commandSuffixLength = [System.Text.Encoding]::ASCII.GetByteCount($commandSuffix)
    $maxToolSuffixLength = [int](($fixedToolPaths | Measure-Object -Property SuffixLength -Maximum).Maximum)
    if (($commandPrefixLength + 200 + $maxToolSuffixLength + $commandSuffixLength) -ge 0x220) {
        throw 'Absolute-path DevAgent command exceeds the fixed STARTUPINFO command buffer.'
    }

    # REP MOVSB uses nonvolatile RSI/RDI; preserve both for the Sharnou caller.
    Emit-StoreRdiFrame -SlotPosition $saveRdiSlot
    Emit-StoreRsiFrame -SlotPosition $saveRsiSlot

    # Validate tool ID and timeout before any filesystem or process side effect.
    Emit-LoadEaxFrame -SlotPosition $TimeoutSlot
    Emit-Bytes -Bytes ([byte[]]@(0x3D))
    Emit-I32 -Value 1000
    Emit-JumpConditional -ConditionCode 0x82 -Label $invalidTimeout
    Emit-Bytes -Bytes ([byte[]]@(0x3D))
    Emit-I32 -Value 300000
    Emit-JumpConditional -ConditionCode 0x87 -Label $invalidTimeout
    Emit-LoadEaxFrame -SlotPosition $ToolSlot
    for ($i = 0; $i -lt $toolLabels.Count; $i++) {
        Emit-Bytes -Bytes ([byte[]]@(0x3D))
        Emit-I32 -Value ($i + 1)
        Emit-JumpConditional -ConditionCode 0x84 -Label $toolLabels[$i]
    }
    Emit-Jump -Label $unknownTool
    for ($i = 0; $i -lt $fixedToolPaths.Count; $i++) {
        Mark-CodeLabel -Label $toolLabels[$i]
        Emit-Jump -Label $commandReady
    }
    Mark-CodeLabel -Label $unknownTool
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x9C, 0xFF, 0xFF, 0xFF)) # -100: unknown tool ID
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup
    Mark-CodeLabel -Label $invalidTimeout
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x9B, 0xFF, 0xFF, 0xFF)) # -101: timeout outside [1000,300000]
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup
    Mark-CodeLabel -Label $commandReady

    # Resolve PowerShell from the absolute Windows System directory; never search PATH.
    Emit-LeaRaxFrame -SlotPosition $applicationSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1, 0xBA, 0x04, 0x01, 0x00, 0x00))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3178) -StackArguments @() # GetSystemDirectoryA
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $pathFail
    Emit-Bytes -Bytes ([byte[]]@(0x3D))
    Emit-I32 -Value (220 - $powerShellSuffixLength)
    Emit-JumpConditional -ConditionCode 0x87 -Label $pathFail
    Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC6)) # ESI = System32 length
    Emit-LeaRaxFrame -SlotPosition $applicationSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC7, 0x48, 0x01, 0xF7)) # RDI = end of System32 path
    Emit-DataAddress -DataItem $powerShellSuffixItem
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC6, 0xB9))
    Emit-I32 -Value $powerShellSuffixLength
    Emit-Bytes -Bytes ([byte[]]@(0xF3, 0xA4, 0xC6, 0x07, 0x00)) # append fixed suffix and NUL

    # Derive the workspace root from this executable's absolute image path.
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xC9)) # HMODULE = NULL
    Emit-LeaRaxFrame -SlotPosition $workspaceRootSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2, 0x41, 0xB8, 0x04, 0x01, 0x00, 0x00))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3218) -StackArguments @() # GetModuleFileNameA
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $directoryFailImage
    Emit-Bytes -Bytes ([byte[]]@(0x3D))
    Emit-I32 -Value 259
    Emit-JumpConditional -ConditionCode 0x87 -Label $directoryFailImage
    Emit-StoreEaxFrame -SlotPosition $modulePathLengthSlot
    Emit-Bytes -Bytes ([byte[]]@(0x3D))
    Emit-I32 -Value $imageSuffixLength
    Emit-JumpConditional -ConditionCode 0x82 -Label $directoryFailImage

    # Require the trusted host image to live outside Low-IL writable Build staging.
    Emit-LeaRaxFrame -SlotPosition $workspaceRootSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC7))
    Emit-LoadEaxFrame -SlotPosition $modulePathLengthSlot
    Emit-Bytes -Bytes ([byte[]]@(0x2D))
    Emit-I32 -Value $imageSuffixLength
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x63, 0xC0, 0x48, 0x01, 0xC7))
    Emit-DataAddress -DataItem $imageSuffixItem
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC6, 0xB9))
    Emit-I32 -Value $imageSuffixLength
    Emit-Bytes -Bytes ([byte[]]@(0xFC, 0xF3, 0xA6)) # CLD; REPE CMPSB
    Emit-JumpConditional -ConditionCode 0x85 -Label $directoryFailImage
    Emit-LoadEaxFrame -SlotPosition $modulePathLengthSlot
    Emit-Bytes -Bytes ([byte[]]@(0x2D))
    Emit-I32 -Value $imageSuffixLength
    Emit-StoreEaxFrame -SlotPosition $rootLengthSlot
    Emit-Bytes -Bytes ([byte[]]@(0xC6, 0x84, 0x05))
    Emit-I32 -Value (Get-FrameDisp -SlotPosition $workspaceRootSlot)
    Emit-Bytes -Bytes ([byte[]]@(0x00)) # terminate workspace root

    # Validate only the broker image's workspace root before recovery. A previous
    # execution can be interrupted after narrowing descendant directory DACLs;
    # validating Build/Tests here would then block the very rollback needed to
    # restore those directories. Descendant checks are deliberately post-recovery.
    Emit-DevBrokerCheckDirectoryChain -PathSlot $workspaceRootSlot -FailureLabel $directoryFailRoot
    Emit-DevBrokerPathCheck -FrameSlot $workspaceRootSlot -IsDirectory $true -FailureLabel $directoryFailRoot

    # Construct absolute child paths from the checked root without opening the
    # descendants. The recovery helper uses handle-based OPEN_REPARSE_POINT checks
    # and the durable snapshot before any ordinary descendant preflight occurs.
    Emit-DevBrokerBuildWorkspacePath -RootSlot $workspaceRootSlot -RootLengthSlot $rootLengthSlot -SuffixItem $buildSuffixItem -SuffixLength $buildSuffixLength -DestinationSlot $buildPathSlot
    Emit-DevBrokerBuildWorkspacePath -RootSlot $workspaceRootSlot -RootLengthSlot $rootLengthSlot -SuffixItem $brokerSuffixItem -SuffixLength $brokerSuffixLength -DestinationSlot $brokerDirectorySlot
    Emit-DevBrokerBuildWorkspacePath -RootSlot $workspaceRootSlot -RootLengthSlot $rootLengthSlot -SuffixItem $captureSuffixItem -SuffixLength $captureSuffixLength -DestinationSlot $outputPathSlot

    # Journal files live in the checked workspace root. The temporary file is
    # atomically renamed only after all three original descriptors are flushed.
    Emit-DevBrokerBuildWorkspacePath -RootSlot $workspaceRootSlot -RootLengthSlot $rootLengthSlot -SuffixItem $journalSuffixItem -SuffixLength $journalSuffixLength -DestinationSlot $journalPathSlot
    Emit-DevBrokerBuildWorkspacePath -RootSlot $workspaceRootSlot -RootLengthSlot $rootLengthSlot -SuffixItem $journalTempSuffixItem -SuffixLength $journalTempSuffixLength -DestinationSlot $journalTempPathSlot

    # Serialize each ACL transaction across broker instances and recover abandoned work first.
    $mutexNameItem = Register-DataConstant -Value 'Local\SharnouDevAgentBroker.Sandbox.v3'
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xC9, 0x33, 0xD2))
    Emit-DataAddress -DataItem $mutexNameItem
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0))
    Emit-Win64CallIat -TargetRva ([UInt32]0x30D8) -StackArguments @() # CreateMutexA
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $mutexFail
    Emit-StoreRaxFrame -SlotPosition $mutexHandleSlot
    Emit-LoadRcxFrame -SlotPosition $mutexHandleSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x30, 0x75, 0x00, 0x00)) # wait <= 30000 ms
    Emit-Win64CallIat -TargetRva ([UInt32]0x30D0) -StackArguments @() # WaitForSingleObject
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    $mutexAcquired = New-UniqueLabel -Prefix 'dev_tool_mutex_acquired'
    $mutexAbandoned = New-UniqueLabel -Prefix 'dev_tool_mutex_abandoned'
    $mutexReady = New-UniqueLabel -Prefix 'dev_tool_mutex_ready'
    Emit-JumpConditional -ConditionCode 0x84 -Label $mutexAcquired
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x80, 0x00, 0x00, 0x00)) # WAIT_ABANDONED = prior owner terminated
    Emit-JumpConditional -ConditionCode 0x84 -Label $mutexAbandoned
    Emit-Jump -Label $mutexFail # WAIT_TIMEOUT / WAIT_FAILED / unexpected status
    Mark-CodeLabel -Label $mutexAcquired
    Emit-StoreBits32Frame -SlotPosition $mutexAcquiredSlot -Value 1
    Emit-Jump -Label $mutexReady

    # An abandoned mutex proves that the previous transaction may have died
    # while AppContainer ACLs were installed. Do not reuse the stable package SID
    # or launch another child until a durable ACL recovery transaction exists.
    Mark-CodeLabel -Label $mutexAbandoned
    Emit-StoreBits32Frame -SlotPosition $mutexAcquiredSlot -Value 1
    Emit-Jump -Label $mutexReady # WAIT_ABANDONED grants ownership; recover before any new child

    Mark-CodeLabel -Label $mutexReady
    Emit-LoadEaxFrame -SlotPosition $rootLengthSlot
    Emit-Bytes -Bytes ([byte[]]@(0x05))
    Emit-I32 -Value $journalSuffixLength
    Emit-StoreEaxFrame -SlotPosition $journalPathLengthSlot
    Emit-DevBrokerRecoverAclJournal -JournalPathSlot $journalPathSlot -PathLengthSlot $journalPathLengthSlot -TempPathSlot $journalTempPathSlot -WorkspaceRootSlot $workspaceRootSlot -BuildPathSlot $buildPathSlot -BrokerDirectorySlot $brokerDirectorySlot -JournalHandleSlot $journalHandleSlot -JournalReadCountSlot $journalReadCountSlot -HeaderSlot $journalHeaderSlot -JournalBufferSlot $journalBufferSlot -RootLengthSlot $rootDescriptorLengthSlot -BuildLengthSlot $buildDescriptorLengthSlot -BrokerLengthSlot $brokerDescriptorLengthSlot -RootDescriptorSlot $rootDescriptorSlot -BuildDescriptorSlot $buildDescriptorSlot -BrokerDescriptorSlot $brokerDescriptorSlot -FailureLabel $aclRecoveryFail

    # Recovery has restored the pre-run descriptors, so descendant path checks
    # can now execute without being blocked by a crashed AppContainer's stale
    # temporary ACL. The recovery helper already failed closed if any opened
    # directory was missing, a reparse point, or could not be restored.
    Emit-DevBrokerPathCheck -FrameSlot $buildPathSlot -IsDirectory $true -FailureLabel $directoryFailBuild
    Emit-DevBrokerPathCheck -FrameSlot $brokerDirectorySlot -IsDirectory $true -FailureLabel $directoryFailBroker
    foreach ($directorySuffix in @('\Stage0', '\Tests', '\Tests\BaselineM6', '\Tests\DevAgentBroker')) {
        $directoryItem = Register-DataConstant -Value $directorySuffix
        $directoryLength = [System.Text.Encoding]::ASCII.GetByteCount($directorySuffix)
        Emit-DevBrokerBuildWorkspacePath -RootSlot $workspaceRootSlot -RootLengthSlot $rootLengthSlot -SuffixItem $directoryItem -SuffixLength $directoryLength -DestinationSlot $pathScratchSlot
        Emit-DevBrokerPathCheck -FrameSlot $pathScratchSlot -IsDirectory $true -FailureLabel $directoryFailFixed
    }
    $compilerSuffixItem = Register-DataConstant -Value '\Stage0\SharnouCompiler.ps1'
    $compilerSuffixLength = [System.Text.Encoding]::ASCII.GetByteCount('\Stage0\SharnouCompiler.ps1')
    Emit-DevBrokerBuildWorkspacePath -RootSlot $workspaceRootSlot -RootLengthSlot $rootLengthSlot -SuffixItem $compilerSuffixItem -SuffixLength $compilerSuffixLength -DestinationSlot $pathScratchSlot
    Emit-DevBrokerPathCheck -FrameSlot $pathScratchSlot -IsDirectory $false -FailureLabel $directoryFailCompiler

    # pathScratchSlot aliases journalPathSlot. The descendant checks above use
    # it as a temporary buffer, so reconstruct the durable journal destination
    # after those checks and before the next transaction writes its snapshot.
    Emit-DevBrokerBuildWorkspacePath -RootSlot $workspaceRootSlot -RootLengthSlot $rootLengthSlot -SuffixItem $journalSuffixItem -SuffixLength $journalSuffixLength -DestinationSlot $journalPathSlot

    Emit-LeaRaxFrame -SlotPosition $workspaceRootSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3220) -StackArguments @() # SetCurrentDirectoryA
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $directoryFailCwd

    # Verify the selected tool only after crash recovery has restored source-tree
    # DACLs. A killed prior broker may leave the AppContainer ACE in place until
    # this point; do not make manifest/script access a prerequisite for rollback.
    # Hash only the selected immutable script by absolute path; keep its opened file handle.
    $verifyLabels = @()
    for ($i = 0; $i -lt $fixedToolPaths.Count; $i++) { $verifyLabels += New-UniqueLabel -Prefix 'dev_tool_verify_hash' }
    Emit-LoadEaxFrame -SlotPosition $ToolSlot
    for ($i = 0; $i -lt $fixedToolPaths.Count; $i++) {
        Emit-Bytes -Bytes ([byte[]]@(0x3D))
        Emit-I32 -Value $fixedToolPaths[$i].Id
        Emit-JumpConditional -ConditionCode 0x84 -Label $verifyLabels[$i]
    }
    Emit-Jump -Label $unknownTool
    for ($i = 0; $i -lt $fixedToolPaths.Count; $i++) {
        Mark-CodeLabel -Label $verifyLabels[$i]
        Emit-DevBrokerBuildWorkspacePath -RootSlot $workspaceRootSlot -RootLengthSlot $rootLengthSlot -SuffixItem $fixedToolPaths[$i].SuffixItem -SuffixLength $fixedToolPaths[$i].SuffixLength -DestinationSlot $pathScratchSlot
        Emit-LoadEaxFrame -SlotPosition $rootLengthSlot
        Emit-Bytes -Bytes ([byte[]]@(0x05))
        Emit-I32 -Value $fixedToolPaths[$i].SuffixLength
        Emit-StoreEaxFrame -SlotPosition $modulePathLengthSlot
        Emit-DevBrokerVerifyScript -FrameSlot $pathScratchSlot -ExpectedSha256 $fixedToolPaths[$i].Sha256 -PersistentFileHandleSlot $hashFileHandleSlot -FailureLabel $hashFail
        Emit-Jump -Label $hashVerified
    }
    Mark-CodeLabel -Label $hashFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x91, 0xFF, 0xFF, 0xFF)) # -111: selected script hash failed
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup
    Mark-CodeLabel -Label $hashVerified

    # Build commandLineSlot = fixed prefix + the exact SHA-256-verified absolute script path + suffix.
    Emit-DataAddress -DataItem $commandPrefixItem
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC6)) # RSI = command prefix
    Emit-LeaRaxFrame -SlotPosition $commandLineSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC7)) # RDI = command buffer
    Emit-Bytes -Bytes ([byte[]]@(0xB9))
    Emit-I32 -Value $commandPrefixLength
    Emit-Bytes -Bytes ([byte[]]@(0xFC, 0xF3, 0xA4)) # CLD; copy prefix

    Emit-LeaRaxFrame -SlotPosition $pathScratchSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC6)) # RSI = verified absolute path
    Emit-LeaRaxFrame -SlotPosition $commandLineSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC7, 0x48, 0x81, 0xC7))
    Emit-I32 -Value $commandPrefixLength # RDI = command buffer + prefix length
    Emit-LoadEaxFrame -SlotPosition $modulePathLengthSlot
    Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC1, 0xFC, 0xF3, 0xA4)) # copy exact path bytes (no NUL)

    Emit-DataAddress -DataItem $commandSuffixItem
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC6)) # RSI = command suffix
    Emit-LeaRaxFrame -SlotPosition $commandLineSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC7, 0x48, 0x81, 0xC7))
    Emit-I32 -Value $commandPrefixLength
    Emit-LoadEaxFrame -SlotPosition $modulePathLengthSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x63, 0xC0, 0x48, 0x01, 0xC7)) # RDI += absolute path length
    Emit-Bytes -Bytes ([byte[]]@(0xB9))
    Emit-I32 -Value $commandSuffixLength
    Emit-Bytes -Bytes ([byte[]]@(0xFC, 0xF3, 0xA4, 0xC6, 0x07, 0x00)) # copy suffix + NUL


    # pathScratchSlot is also journalPathSlot. Hash-path construction borrowed it,
    # so rebuild the committed journal target before the next transaction starts.
    Emit-DevBrokerBuildWorkspacePath -RootSlot $workspaceRootSlot -RootLengthSlot $rootLengthSlot -SuffixItem $journalSuffixItem -SuffixLength $journalSuffixLength -DestinationSlot $journalPathSlot

    # One-time migration: remove any ACL grants left for the former shared package SID.
    # REVOKE_ACCESS only narrows DACL permissions; no access is expanded here. The
    # journal snapshot is then captured from the post-migration state, before grants
    # for the fresh per-execution SID are applied.
    Emit-DevBrokerRevokeLegacyAppContainerSid -SidSlot $legacyAppContainerSidSlot -FailureLabel $legacyAppContainerFail
    Emit-DevBrokerUpdateAcl -PathSlot $workspaceRootSlot -SidSlot $legacyAppContainerSidSlot -AccessMask ([UInt32]0) -AccessMode 4 -FailureLabel $aclFail
    Emit-DevBrokerUpdateAcl -PathSlot $buildPathSlot -SidSlot $legacyAppContainerSidSlot -AccessMask ([UInt32]0) -AccessMode 4 -SetLowIntegrityLabel $false -FailureLabel $aclFail
    Emit-DevBrokerUpdateAcl -PathSlot $brokerDirectorySlot -SidSlot $legacyAppContainerSidSlot -AccessMask ([UInt32]0) -AccessMode 4 -SetLowIntegrityLabel $false -FailureLabel $aclFail

    # A separate fresh identity is created for the actual child; the stable legacy
    # SID is never placed in SECURITY_CAPABILITIES or used for a process token.
    Emit-DevBrokerEnsureAppContainerSid -SidSlot $appContainerSidSlot -ProfileNameSlot $profileNameSlot -RandomSlot $profileRandomSlot -DerivedSidSlot $derivedProfileSidSlot -ProfileCreatedSlot $profileCreatedSlot -FailureLabel $appContainerFail

    Emit-DevBrokerWriteAclJournal -JournalPathSlot $journalPathSlot -TempPathSlot $journalTempPathSlot -WorkspaceRootSlot $workspaceRootSlot -BuildPathSlot $buildPathSlot -BrokerDirectorySlot $brokerDirectorySlot -JournalHandleSlot $journalHandleSlot -JournalWrittenSlot $journalWrittenSlot -HeaderSlot $journalHeaderSlot -RootDescriptorSlot $rootDescriptorSlot -BuildDescriptorSlot $buildDescriptorSlot -BrokerDescriptorSlot $brokerDescriptorSlot -RootLengthSlot $rootDescriptorLengthSlot -BuildLengthSlot $buildDescriptorLengthSlot -BrokerLengthSlot $brokerDescriptorLengthSlot -TransactionActiveSlot $transactionActiveSlot -FailureLabel $journalFail

    # Only now may the execution SID gain read access to source and write access to staging.
    Emit-DevBrokerUpdateAcl -PathSlot $workspaceRootSlot -SidSlot $appContainerSidSlot -AccessMask ([UInt32]0x001200A9) -AccessMode 2 -FailureLabel $aclFail
    Emit-DevBrokerUpdateAcl -PathSlot $buildPathSlot -SidSlot $appContainerSidSlot -AccessMask ([UInt32]0x001201FF) -AccessMode 2 -SetLowIntegrityLabel $true -FailureLabel $aclFail
    Emit-DevBrokerUpdateAcl -PathSlot $brokerDirectorySlot -SidSlot $appContainerSidSlot -AccessMask ([UInt32]0x001201FF) -AccessMode 2 -SetLowIntegrityLabel $true -FailureLabel $aclFail

    # Rebuild this path because outputPathSlot held the temporary ACL journal name.
    Emit-DevBrokerBuildWorkspacePath -RootSlot $workspaceRootSlot -RootLengthSlot $rootLengthSlot -SuffixItem $captureSuffixItem -SuffixLength $captureSuffixLength -DestinationSlot $outputPathSlot

    # Create a new exclusive capture file before launch. CREATE_NEW cannot reopen an old
    # reparse point or hard link; the held non-inheritable handle is reused for persistence.
    Emit-LeaRaxFrame -SlotPosition $outputPathSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3310) -StackArguments @() # DeleteFileA; stale files are removed only before CREATE_NEW
    Emit-LeaRaxFrame -SlotPosition $outputPathSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1, 0xBA, 0x80, 0x00, 0x00, 0x40, 0x45, 0x33, 0xC0, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x30A0) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 1 },  # CREATE_NEW
        @{ Kind = 'Immediate'; Value = 0x00200080 }, # OPEN_REPARSE_POINT | FILE_ATTRIBUTE_NORMAL
        @{ Kind = 'Immediate'; Value = 0 }
    ) # CreateFileA(captured-output.bin), share mode = 0
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xF8, 0xFF))
    Emit-JumpConditional -ConditionCode 0x84 -Label $outputFail
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $outputFail
    Emit-StoreRaxFrame -SlotPosition $outputFileHandleSlot
    for ($i = 0; $i -lt 7; $i++) { Emit-StoreZero64Frame -SlotPosition ($outputFileInfoSlot + ($i * 8)) }
    Emit-LoadRcxFrame -SlotPosition $outputFileHandleSlot
    Emit-LeaRaxFrame -SlotPosition $outputFileInfoSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3208) -StackArguments @() # GetFileInformationByHandle
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $outputFail
    Emit-LoadEaxFrame -SlotPosition $outputFileInfoSlot
    Emit-Bytes -Bytes ([byte[]]@(0xA9, 0x10, 0x04, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x85 -Label $outputFail # reject directory and reparse-point attributes
    Emit-LoadEaxFrame -SlotPosition ($outputFileInfoSlot + 40)
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x01, 0x00, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x85 -Label $outputFail # a fresh capture file must have exactly one link

    # Build a restricted primary token and a no-capability AppContainer SECURITY_CAPABILITIES.
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0xC7, 0xC1, 0xFF, 0xFF, 0xFF, 0xFF)) # GetCurrentProcess()
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x8B, 0x00, 0x00, 0x00)) # TOKEN_ASSIGN_PRIMARY|DUPLICATE|QUERY|ADJUST_DEFAULT
    Emit-LeaRaxFrame -SlotPosition $sourceTokenSlot
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0))
    Emit-Win64CallIat -TargetRva ([UInt32]0x32B0) -StackArguments @() # OpenProcessToken
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $tokenFail
    Emit-LoadRcxFrame -SlotPosition $sourceTokenSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x01, 0x00, 0x00, 0x00, 0x45, 0x33, 0xC0, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x32B8) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 0 }, # DeletePrivilegeCount
        @{ Kind = 'Immediate'; Value = 0 }, # PrivilegesToDelete
        @{ Kind = 'Immediate'; Value = 0 }, # RestrictedSidCount
        @{ Kind = 'Immediate'; Value = 0 }, # SIDsToRestrict
        @{ Kind = 'FrameAddress'; SlotPosition = $restrictedTokenSlot }
    ) # CreateRestrictedToken(DISABLE_MAX_PRIVILEGE)
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $tokenFail
    Emit-LoadRaxFrame -SlotPosition $restrictedTokenSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $tokenFail

    Emit-LoadRaxFrame -SlotPosition $appContainerSidSlot
    Emit-StoreRaxFrame -SlotPosition $securityCapabilitiesSlot
    Emit-StoreZero64Frame -SlotPosition ($securityCapabilitiesSlot + 8) # Capability SID_AND_ATTRIBUTES pointer = NULL
    Emit-StoreBits32Frame -SlotPosition ($securityCapabilitiesSlot + 16) -Value 0 # CapabilityCount
    Emit-StoreBits32Frame -SlotPosition ($securityCapabilitiesSlot + 20) -Value 0 # Reserved

    # Create inherited anonymous-pipe endpoints and a NUL standard-input handle.
    Emit-StoreBits32Frame -SlotPosition $pipeSecuritySlot -Value 24 # sizeof(SECURITY_ATTRIBUTES)
    Emit-StoreZero64Frame -SlotPosition ($pipeSecuritySlot + 8)
    Emit-StoreBits32Frame -SlotPosition ($pipeSecuritySlot + 16) -Value 1 # bInheritHandle
    Emit-LeaRaxFrame -SlotPosition $pipeReadSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-LeaRaxFrame -SlotPosition $pipeWriteSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-LeaRaxFrame -SlotPosition $pipeSecuritySlot
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3230) -StackArguments @() # CreatePipe
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $pipeFail
    Emit-LoadRcxFrame -SlotPosition $pipeReadSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x01, 0x00, 0x00, 0x00, 0x45, 0x33, 0xC0))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3238) -StackArguments @() # SetHandleInformation(read, HANDLE_FLAG_INHERIT, 0)
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $pipeFail

    $nulItem = Register-DataConstant -Value 'NUL'
    Emit-DataAddress -DataItem $nulItem
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1, 0xBA, 0x00, 0x00, 0x00, 0x80, 0x41, 0xB8, 0x03, 0x00, 0x00, 0x00))
    Emit-LeaR9Frame -SlotPosition $pipeSecuritySlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x30A0) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 3 }, # OPEN_EXISTING
        @{ Kind = 'Immediate'; Value = 0x80 }, # FILE_ATTRIBUTE_NORMAL
        @{ Kind = 'Immediate'; Value = 0 }
    ) # CreateFileA(NUL), inheritable
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xF8, 0xFF))
    Emit-JumpConditional -ConditionCode 0x84 -Label $pipeFail
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $pipeFail
    Emit-StoreRaxFrame -SlotPosition $nulHandleSlot

    # Allocate the hard-capped output buffer and a STARTUPINFOEX attribute list.
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xC9, 0xBA, 0x00, 0x00, 0x10, 0x00, 0x41, 0xB8, 0x00, 0x30, 0x00, 0x00, 0x41, 0xB9, 0x04, 0x00, 0x00, 0x00))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31D0) -StackArguments @() # VirtualAlloc(1MiB, MEM_COMMIT|RESERVE, PAGE_READWRITE)
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $outputFail
    Emit-StoreRaxFrame -SlotPosition $outputBufferSlot

    # Query the exact size required for two process attributes. The documented
    # first call uses a NULL list and must fail with ERROR_INSUFFICIENT_BUFFER (122).
    Emit-StoreZero64Frame -SlotPosition $attributeSizeSlot
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xC9, 0xBA, 0x02, 0x00, 0x00, 0x00, 0x45, 0x33, 0xC0))
    Emit-LeaR9Frame -SlotPosition $attributeSizeSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x3248) -StackArguments @() # InitializeProcThreadAttributeList(NULL,2,0,&size)
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $attributeFail # the sizing call must return FALSE
    Emit-Win64CallIat -TargetRva ([UInt32]0x3268) -StackArguments @() # GetLastError
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x7A, 0x00, 0x00, 0x00)) # ERROR_INSUFFICIENT_BUFFER
    Emit-JumpConditional -ConditionCode 0x85 -Label $attributeFail
    Emit-LoadEaxFrame -SlotPosition $attributeSizeSlot
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x01, 0x00, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x82 -Label $attributeFail # size must be nonzero
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x00, 0x10, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x87 -Label $attributeFail # hard allocation ceiling = 4096 bytes

    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xC9)) # lpAddress = NULL
    Emit-LoadEaxFrame -SlotPosition $attributeSizeSlot
    Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC2, 0x41, 0xB8, 0x00, 0x30, 0x00, 0x00, 0x41, 0xB9, 0x04, 0x00, 0x00, 0x00))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31D0) -StackArguments @() # VirtualAlloc(exact attribute-list size)
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $attributeFail
    Emit-StoreRaxFrame -SlotPosition $attributeListSlot
    Emit-LoadRcxFrame -SlotPosition $attributeListSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x02, 0x00, 0x00, 0x00, 0x45, 0x33, 0xC0))
    Emit-LeaR9Frame -SlotPosition $attributeSizeSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x3248) -StackArguments @() # InitializeProcThreadAttributeList(actual buffer)
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $attributeFail
    Emit-StoreBits32Frame -SlotPosition $attributeListReadySlot -Value 1

    # PROC_THREAD_ATTRIBUTE_SECURITY_CAPABILITIES: AppContainer SID and zero capabilities.
    Emit-LoadRaxFrame -SlotPosition $appContainerSidSlot
    Emit-StoreRaxFrame -SlotPosition $securityCapabilitiesSlot
    Emit-LoadRcxFrame -SlotPosition $attributeListSlot
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xD2, 0x41, 0xB8, 0x09, 0x00, 0x02, 0x00))
    Emit-LeaR9Frame -SlotPosition $securityCapabilitiesSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x3250) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 24 }, # sizeof(SECURITY_CAPABILITIES)
        @{ Kind = 'Immediate'; Value = 0 },
        @{ Kind = 'Immediate'; Value = 0 }
    ) # UpdateProcThreadAttribute(SECURITY_CAPABILITIES)
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $attributeFail

    # The inherited-handle allowlist contains exactly NUL stdin and the pipe writer.
    Emit-LoadRaxFrame -SlotPosition $nulHandleSlot
    Emit-StoreRaxFrame -SlotPosition $handleListSlot
    Emit-LoadRaxFrame -SlotPosition $pipeWriteSlot
    Emit-StoreRaxFrame -SlotPosition ($handleListSlot + 8)
    Emit-LoadRcxFrame -SlotPosition $attributeListSlot
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xD2, 0x41, 0xB8, 0x02, 0x00, 0x02, 0x00))
    Emit-LeaR9Frame -SlotPosition $handleListSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x3250) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 16 }, # sizeof(HANDLE[2])
        @{ Kind = 'Immediate'; Value = 0 },
        @{ Kind = 'Immediate'; Value = 0 }
    ) # UpdateProcThreadAttribute(HANDLE_LIST)
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $attributeFail

    # STARTUPINFOEXA: stdin=NUL, stdout=stderr=one pipe writer, exact attribute list.
    for ($i = 0; $i -lt 14; $i++) { Emit-StoreZero64Frame -SlotPosition ($startupSlot + ($i * 8)) }
    Emit-StoreBits32Frame -SlotPosition $startupSlot -Value 112 # sizeof(STARTUPINFOEXA)
    Emit-StoreBits32Frame -SlotPosition ($startupSlot + 60) -Value 0x100 # STARTF_USESTDHANDLES
    Emit-LoadRaxFrame -SlotPosition $nulHandleSlot
    Emit-StoreRaxFrame -SlotPosition ($startupSlot + 80)
    Emit-LoadRaxFrame -SlotPosition $pipeWriteSlot
    Emit-StoreRaxFrame -SlotPosition ($startupSlot + 88)
    Emit-LoadRaxFrame -SlotPosition $pipeWriteSlot
    Emit-StoreRaxFrame -SlotPosition ($startupSlot + 96)
    Emit-LoadRaxFrame -SlotPosition $attributeListSlot
    Emit-StoreRaxFrame -SlotPosition ($startupSlot + 104)

    # JOB_OBJECT_EXTENDED_LIMIT_INFORMATION: KILL_ON_JOB_CLOSE | ACTIVE_PROCESS | PROCESS_MEMORY | JOB_MEMORY (0x2308).
    for ($i = 0; $i -lt 18; $i++) { Emit-StoreZero64Frame -SlotPosition ($jobInfoSlot + ($i * 8)) }
    Emit-StoreBits32Frame -SlotPosition ($jobInfoSlot + 16) -Value 0x2308
    Emit-StoreBits32Frame -SlotPosition ($jobInfoSlot + 40) -Value 4 # ActiveProcessLimit
    Emit-StoreImm64Frame -SlotPosition ($jobInfoSlot + 112) -Value ([UInt64](256 * 1024 * 1024))
    Emit-StoreImm64Frame -SlotPosition ($jobInfoSlot + 120) -Value ([UInt64](512 * 1024 * 1024))

    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xC9, 0x33, 0xD2))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3190) -StackArguments @() # CreateJobObjectA
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $jobFail
    Emit-StoreRaxFrame -SlotPosition $jobHandleSlot
    Emit-LoadRcxFrame -SlotPosition $jobHandleSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x09, 0x00, 0x00, 0x00))
    Emit-LeaRaxFrame -SlotPosition $jobInfoSlot
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0, 0x41, 0xB9, 0x90, 0x00, 0x00, 0x00))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3198) -StackArguments @() # SetInformationJobObject
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $jobConfigFail

    # Create the restricted-token/AppContainer child suspended; only the explicit handle list is inherited.
    Emit-LoadRaxFrame -SlotPosition $restrictedTokenSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1)) # RCX = token
    Emit-LeaRaxFrame -SlotPosition $applicationSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2)) # RDX = absolute System32 powershell.exe
    Emit-LeaRaxFrame -SlotPosition $commandLineSlot
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0, 0x45, 0x33, 0xC9)) # R8 = command line; R9 = NULL process attrs
    Emit-Win64CallIat -TargetRva ([UInt32]0x32C0) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 0 }, # lpThreadAttributes
        @{ Kind = 'Immediate'; Value = 1 }, # bInheritHandles TRUE, constrained by HANDLE_LIST
        @{ Kind = 'Immediate'; Value = 0x00080004 }, # EXTENDED_STARTUPINFO_PRESENT | CREATE_SUSPENDED
        @{ Kind = 'Immediate'; Value = 0 }, # inherited environment remains a separate hardening gate
        @{ Kind = 'FrameAddress'; SlotPosition = $workspaceRootSlot },
        @{ Kind = 'FrameAddress'; SlotPosition = $startupSlot },
        @{ Kind = 'FrameAddress'; SlotPosition = $processSlot }
    ) # CreateProcessAsUserA
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $createFail

    # Parent closes its inheritable copies immediately; only the child owns the pipe writer after this point.
    foreach ($slot in @($pipeWriteSlot, $nulHandleSlot)) {
        Emit-LoadRcxFrame -SlotPosition $slot
        Emit-Win64CallIat -TargetRva ([UInt32]0x30B8) -StackArguments @() # CloseHandle
        Emit-StoreZero64Frame -SlotPosition $slot
    }

    # The process must join the Job Object while suspended.
    Emit-LoadRcxFrame -SlotPosition $jobHandleSlot
    Emit-LoadRaxFrame -SlotPosition $processSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31A0) -StackArguments @() # AssignProcessToJobObject
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $assignFail
    Emit-StoreBits32Frame -SlotPosition $childActiveSlot -Value 1

    # Verify the actual primary token before the first instruction can execute.
    Emit-LoadRaxFrame -SlotPosition $processSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1, 0xBA, 0x08, 0x00, 0x00, 0x00))
    Emit-LeaRaxFrame -SlotPosition $childTokenSlot
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0))
    Emit-Win64CallIat -TargetRva ([UInt32]0x32B0) -StackArguments @() # OpenProcessToken(TOKEN_QUERY)
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $tokenFail

    # TokenIsAppContainer must be TRUE.
    for ($i = 0; $i -lt 8; $i++) { Emit-StoreZero64Frame -SlotPosition ($tokenInformationSlot + ($i * 8)) }
    Emit-StoreZero64Frame -SlotPosition $tokenLengthSlot
    Emit-LoadRcxFrame -SlotPosition $childTokenSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x1D, 0x00, 0x00, 0x00)) # TokenIsAppContainer = 29
    Emit-LeaRaxFrame -SlotPosition $tokenInformationSlot
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0, 0x41, 0xB9, 0x04, 0x00, 0x00, 0x00))
    Emit-Win64CallIat -TargetRva ([UInt32]0x32D8) -StackArguments @(
        @{ Kind = 'FrameAddress'; SlotPosition = $tokenLengthSlot }
    ) # GetTokenInformation
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $tokenFail
    Emit-LoadEaxFrame -SlotPosition $tokenInformationSlot
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $tokenFail

    # The actual primary token must contain this execution's exact package SID,
    # not merely any AppContainer SID with zero capabilities. Probe the required
    # TOKEN_APPCONTAINER_INFORMATION size instead of assuming a fixed ABI length.
    for ($i = 0; $i -lt 8; $i++) { Emit-StoreZero64Frame -SlotPosition ($tokenInformationSlot + ($i * 8)) }
    Emit-StoreZero64Frame -SlotPosition $tokenLengthSlot
    Emit-LoadRcxFrame -SlotPosition $childTokenSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x1F, 0x00, 0x00, 0x00, 0x45, 0x33, 0xC0, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x32D8) -StackArguments @(
        @{ Kind = 'FrameAddress'; SlotPosition = $tokenLengthSlot }
    ) # GetTokenInformation(TokenAppContainerSid) sizing query
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $tokenFail # sizing call must fail for zero-length output
    Emit-Win64CallIat -TargetRva ([UInt32]0x3268) -StackArguments @() # GetLastError
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x7A, 0x00, 0x00, 0x00)) # ERROR_INSUFFICIENT_BUFFER
    Emit-JumpConditional -ConditionCode 0x85 -Label $tokenFail
    Emit-LoadEaxFrame -SlotPosition $tokenLengthSlot
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x08, 0x00, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x82 -Label $tokenFail # require at least a PSID pointer
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x40, 0x00, 0x00, 0x00))
    Emit-JumpConditional -ConditionCode 0x87 -Label $tokenFail # bounded stack buffer = 64 bytes

    Emit-LoadRcxFrame -SlotPosition $childTokenSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x1F, 0x00, 0x00, 0x00))
    Emit-LeaRaxFrame -SlotPosition $tokenInformationSlot
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0))
    Emit-LoadEaxFrame -SlotPosition $tokenLengthSlot
    Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x32D8) -StackArguments @(
        @{ Kind = 'FrameAddress'; SlotPosition = $tokenLengthSlot }
    ) # GetTokenInformation(TOKEN_APPCONTAINER_INFORMATION)
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $tokenFail
    Emit-LoadRaxFrame -SlotPosition $tokenInformationSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1)) # RCX = PSID pointer stored in TOKEN_APPCONTAINER_INFORMATION
    Emit-LoadRaxFrame -SlotPosition $appContainerSidSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2)) # RDX = newly created profile SID
    Emit-Win64CallIat -TargetRva ([UInt32]0x3350) -StackArguments @() # EqualSid
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $tokenFail

    # TokenHasRestrictions must be TRUE (the parent token's maximum privileges were disabled).
    for ($i = 0; $i -lt 8; $i++) { Emit-StoreZero64Frame -SlotPosition ($tokenInformationSlot + ($i * 8)) }
    Emit-StoreZero64Frame -SlotPosition $tokenLengthSlot
    Emit-LoadRcxFrame -SlotPosition $childTokenSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x15, 0x00, 0x00, 0x00)) # TokenHasRestrictions = 21
    Emit-LeaRaxFrame -SlotPosition $tokenInformationSlot
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0, 0x41, 0xB9, 0x04, 0x00, 0x00, 0x00))
    Emit-Win64CallIat -TargetRva ([UInt32]0x32D8) -StackArguments @(
        @{ Kind = 'FrameAddress'; SlotPosition = $tokenLengthSlot }
    )
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $tokenFail
    Emit-LoadEaxFrame -SlotPosition $tokenInformationSlot
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $tokenFail

    # TokenCapabilities must report zero capabilities; there is no network capability grant.
    for ($i = 0; $i -lt 8; $i++) { Emit-StoreZero64Frame -SlotPosition ($tokenInformationSlot + ($i * 8)) }
    Emit-StoreZero64Frame -SlotPosition $tokenLengthSlot
    Emit-LoadRcxFrame -SlotPosition $childTokenSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x1E, 0x00, 0x00, 0x00)) # TokenCapabilities = 30
    Emit-LeaRaxFrame -SlotPosition $tokenInformationSlot
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0, 0x41, 0xB9, 0x40, 0x00, 0x00, 0x00))
    Emit-Win64CallIat -TargetRva ([UInt32]0x32D8) -StackArguments @(
        @{ Kind = 'FrameAddress'; SlotPosition = $tokenLengthSlot }
    )
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $tokenFail
    Emit-LoadEaxFrame -SlotPosition $tokenInformationSlot # TOKEN_GROUPS.GroupCount
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $tokenFail

    Emit-LoadRaxFrame -SlotPosition ($processSlot + 8)
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31A8) -StackArguments @() # ResumeThread
    Emit-Bytes -Bytes ([byte[]]@(0x83, 0xF8, 0xFF))
    Emit-JumpConditional -ConditionCode 0x84 -Label $resumeFail

    # Poll completion independently of pipe traffic. Each wait is 10 ms, keeping timeout accounting bounded.
    Emit-LoadEaxFrame -SlotPosition $TimeoutSlot
    Emit-StoreEaxFrame -SlotPosition $remainingMsSlot
    Mark-CodeLabel -Label $captureLoop
    Emit-LoadRaxFrame -SlotPosition $processSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1, 0xBA, 0x0A, 0x00, 0x00, 0x00))
    Emit-Win64CallIat -TargetRva ([UInt32]0x30D0) -StackArguments @() # WaitForSingleObject(process,10)
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $processDone
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x02, 0x01, 0x00, 0x00)) # WAIT_TIMEOUT
    Emit-JumpConditional -ConditionCode 0x85 -Label $waitFail
    Emit-LoadEaxFrame -SlotPosition $remainingMsSlot
    Emit-Bytes -Bytes ([byte[]]@(0x83, 0xE8, 0x0A))
    Emit-StoreEaxFrame -SlotPosition $remainingMsSlot
    Emit-Bytes -Bytes ([byte[]]@(0x83, 0xF8, 0x00))
    Emit-JumpConditional -ConditionCode 0x8E -Label $timeoutFail

    Emit-LoadEaxFrame -SlotPosition $pipeClosedSlot
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $capturePipeClosed
    Emit-LoadRcxFrame -SlotPosition $pipeReadSlot
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xD2, 0x45, 0x33, 0xC0, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3240) -StackArguments @(
        @{ Kind = 'FrameAddress'; SlotPosition = $availableSlot },
        @{ Kind = 'Immediate'; Value = 0 }
    ) # PeekNamedPipe
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $capturePipeEof
    Emit-LoadEaxFrame -SlotPosition $availableSlot
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $captureLoop

    # Read only the remaining capacity. If outputCount is already 1 MiB and
    # another byte is available, the following read attempt takes the overflow path.
    Emit-LoadEaxFrame -SlotPosition $outputCountSlot
    Emit-Bytes -Bytes ([byte[]]@(0x3D))
    Emit-I32 -Value 0x100000
    Emit-JumpConditional -ConditionCode 0x83 -Label $outputOverflow # count >= cap and available > 0
    $mainCapReadReady = New-UniqueLabel -Prefix 'dev_output_main_cap_read_ready'
    Emit-Bytes -Bytes ([byte[]]@(0xB9))
    Emit-I32 -Value 0x100000 # ECX = hard cap
    Emit-Bytes -Bytes ([byte[]]@(0x2B, 0x8D))
    Emit-I32 -Value (Get-FrameDisp -SlotPosition $outputCountSlot) # ECX -= captured bytes
    Emit-LoadEaxFrame -SlotPosition $availableSlot
    Emit-Bytes -Bytes ([byte[]]@(0x3B, 0xC1)) # compare available bytes to remaining capacity
    Emit-JumpConditional -ConditionCode 0x86 -Label $mainCapReadReady # available <= remaining
    Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC8)) # EAX = ECX (read only remaining capacity)
    Emit-StoreEaxFrame -SlotPosition $availableSlot
    Mark-CodeLabel -Label $mainCapReadReady

    Emit-LoadRcxFrame -SlotPosition $pipeReadSlot
    Emit-LoadRaxFrame -SlotPosition $outputBufferSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-LoadEaxFrame -SlotPosition $outputCountSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x63, 0xC0, 0x48, 0x01, 0xC2))
    Emit-LoadEaxFrame -SlotPosition $availableSlot
    Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC0))
    Emit-LeaRaxFrame -SlotPosition $readCountSlot
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x30B0) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 0 }
    ) # ReadFile
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $waitFail
    Emit-LoadEaxFrame -SlotPosition $readCountSlot
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $waitFail
    Emit-LoadEaxFrame -SlotPosition $outputCountSlot
    Emit-Bytes -Bytes ([byte[]]@(0x03, 0x85))
    Emit-I32 -Value (Get-FrameDisp -SlotPosition $readCountSlot)
    Emit-StoreEaxFrame -SlotPosition $outputCountSlot
    Emit-Jump -Label $captureLoop

    Mark-CodeLabel -Label $capturePipeClosed
    Emit-Jump -Label $captureLoop

    Mark-CodeLabel -Label $capturePipeEof
    Emit-Win64CallIat -TargetRva ([UInt32]0x3268) -StackArguments @() # GetLastError
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x6D, 0x00, 0x00, 0x00)) # ERROR_BROKEN_PIPE = 109
    Emit-JumpConditional -ConditionCode 0x85 -Label $waitFail
    Emit-StoreBits32Frame -SlotPosition $pipeClosedSlot -Value 1
    Emit-Jump -Label $captureLoop

    Mark-CodeLabel -Label $processDone
    # Terminate any descendants and wait on the Job Object itself until every process has exited.
    Emit-LoadRcxFrame -SlotPosition $jobHandleSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x02, 0x00, 0xAD, 0xDE))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31B0) -StackArguments @() # TerminateJobObject
    Emit-LoadRcxFrame -SlotPosition $jobHandleSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0xFF, 0xFF, 0xFF, 0xFF))
    Emit-Win64CallIat -TargetRva ([UInt32]0x30D0) -StackArguments @() # WaitForSingleObject(job,INFINITE)
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $waitFail
    Emit-StoreBits32Frame -SlotPosition $childActiveSlot -Value 0
    Emit-Jump -Label $finalDrain

    # The Job Object is empty before the final pipe drain begins.
    Mark-CodeLabel -Label $finalDrain
    Emit-LoadEaxFrame -SlotPosition $pipeClosedSlot
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $captureDone
    Emit-LoadRcxFrame -SlotPosition $pipeReadSlot
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xD2, 0x45, 0x33, 0xC0, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3240) -StackArguments @(
        @{ Kind = 'FrameAddress'; SlotPosition = $availableSlot },
        @{ Kind = 'Immediate'; Value = 0 }
    ) # PeekNamedPipe
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $finalPipeEof
    Emit-LoadEaxFrame -SlotPosition $availableSlot
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $captureDone

    # Final drain uses the same exact-cap rule after the Job Object is empty.
    Emit-LoadEaxFrame -SlotPosition $outputCountSlot
    Emit-Bytes -Bytes ([byte[]]@(0x3D))
    Emit-I32 -Value 0x100000
    Emit-JumpConditional -ConditionCode 0x83 -Label $outputOverflow
    $finalCapReadReady = New-UniqueLabel -Prefix 'dev_output_final_cap_read_ready'
    Emit-Bytes -Bytes ([byte[]]@(0xB9))
    Emit-I32 -Value 0x100000 # ECX = hard cap
    Emit-Bytes -Bytes ([byte[]]@(0x2B, 0x8D))
    Emit-I32 -Value (Get-FrameDisp -SlotPosition $outputCountSlot) # ECX -= captured bytes
    Emit-LoadEaxFrame -SlotPosition $availableSlot
    Emit-Bytes -Bytes ([byte[]]@(0x3B, 0xC1))
    Emit-JumpConditional -ConditionCode 0x86 -Label $finalCapReadReady
    Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC8))
    Emit-StoreEaxFrame -SlotPosition $availableSlot
    Mark-CodeLabel -Label $finalCapReadReady

    Emit-LoadRcxFrame -SlotPosition $pipeReadSlot
    Emit-LoadRaxFrame -SlotPosition $outputBufferSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-LoadEaxFrame -SlotPosition $outputCountSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x63, 0xC0, 0x48, 0x01, 0xC2))
    Emit-LoadEaxFrame -SlotPosition $availableSlot
    Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC0))
    Emit-LeaRaxFrame -SlotPosition $readCountSlot
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x30B0) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 0 }
    ) # ReadFile
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $outputFail
    Emit-LoadEaxFrame -SlotPosition $readCountSlot
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $outputFail
    Emit-LoadEaxFrame -SlotPosition $outputCountSlot
    Emit-Bytes -Bytes ([byte[]]@(0x03, 0x85))
    Emit-I32 -Value (Get-FrameDisp -SlotPosition $readCountSlot)
    Emit-StoreEaxFrame -SlotPosition $outputCountSlot
    Emit-Jump -Label $finalDrain

    Mark-CodeLabel -Label $finalPipeEof
    Emit-Win64CallIat -TargetRva ([UInt32]0x3268) -StackArguments @() # GetLastError
    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x6D, 0x00, 0x00, 0x00)) # ERROR_BROKEN_PIPE = 109
    Emit-JumpConditional -ConditionCode 0x85 -Label $outputFail
    Emit-Jump -Label $captureDone

    Mark-CodeLabel -Label $captureDone
    Emit-LoadRcxFrame -SlotPosition $processSlot
    Emit-LeaRaxFrame -SlotPosition $exitCodeSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31B8) -StackArguments @() # GetExitCodeProcess
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $waitFail
    Emit-LoadEaxFrame -SlotPosition $exitCodeSlot
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $outputOverflow
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x8E, 0xFF, 0xFF, 0xFF)) # -114: output byte ceiling exceeded
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $timeoutFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x92, 0xFF, 0xFF, 0xFF)) # -110: timeout
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $waitFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x93, 0xFF, 0xFF, 0xFF)) # -109: wait/pipe/exit-code failure
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $assignFail
    Emit-LoadRcxFrame -SlotPosition $processSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x02, 0x00, 0xAD, 0xDE))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31C0) -StackArguments @() # TerminateProcess; child was never assigned to the Job
    Emit-LoadRcxFrame -SlotPosition $processSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0xFF, 0xFF, 0xFF, 0xFF))
    Emit-Win64CallIat -TargetRva ([UInt32]0x30D0) -StackArguments @() # wait for suspended process termination
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x95, 0xFF, 0xFF, 0xFF)) # -107: Job Object assignment failed
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $resumeFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x94, 0xFF, 0xFF, 0xFF)) # -108: ResumeThread failed
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $createFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x96, 0xFF, 0xFF, 0xFF)) # -106: CreateProcessAsUserA failed
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $jobConfigFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x97, 0xFF, 0xFF, 0xFF)) # -105: Job Object configuration failed
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $jobFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x98, 0xFF, 0xFF, 0xFF)) # -104: CreateJobObjectA failed
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $pipeFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x8C, 0xFF, 0xFF, 0xFF)) # -116: pipe/NUL setup failed
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $attributeFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x8C, 0xFF, 0xFF, 0xFF)) # -116: startup attribute setup failed
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $outputFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x8D, 0xFF, 0xFF, 0xFF)) # -115: output capture file/buffer failed
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $tokenFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x90, 0xFF, 0xFF, 0xFF)) # -112: restricted token verification failed
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $aclFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x8F, 0xFF, 0xFF, 0xFF)) # -113: workspace ACL update failed
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $aclRecoveryFail
    Emit-LoadEaxFrame -SlotPosition ($scratch + 0xD90)
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    $genericRecoveryFailure = New-UniqueLabel -Prefix 'dev_tool_acl_recovery_generic_failure'
    Emit-JumpConditional -ConditionCode 0x84 -Label $genericRecoveryFailure
    Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC2, 0xB8, 0x70, 0xFE, 0xFF, 0xFF, 0x29, 0xD0)) # -400 - stage; diagnostic-only recovery failure
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup
    Mark-CodeLabel -Label $genericRecoveryFailure
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x89, 0xFF, 0xFF, 0xFF)) # -119: journal validation failure before descriptor restore
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $journalFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x88, 0xFF, 0xFF, 0xFF)) # -120: durable ACL journal could not be committed
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $appContainerFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x77, 0xFF, 0xFF, 0xFF)) # -137: per-execution profile creation/SID derivation failed
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $legacyAppContainerFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x78, 0xFF, 0xFF, 0xFF)) # -136: legacy shared-profile ACL migration SID resolution failed
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $mutexFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x8B, 0xFF, 0xFF, 0xFF)) # -117: ACL/output serialization failed
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $pathFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x9A, 0xFF, 0xFF, 0xFF)) # -102: System32 PowerShell resolution failed
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $directoryFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x99, 0xFF, 0xFF, 0xFF)) # -103: legacy/default workspace path failure
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    # Diagnostic-only statuses: -121 image, -122 root, -123 CWD,
    # -124 Build, -125 broker directory, -126 fixed test dirs, -127 compiler script.
    foreach ($failure in @(
        @{ Label = $directoryFailImage; Code = -121 },
        @{ Label = $directoryFailRoot; Code = -122 },
        @{ Label = $directoryFailCwd; Code = -123 },
        @{ Label = $directoryFailBuild; Code = -124 },
        @{ Label = $directoryFailBroker; Code = -125 },
        @{ Label = $directoryFailFixed; Code = -126 },
        @{ Label = $directoryFailCompiler; Code = -127 }
    )) {
        Mark-CodeLabel -Label $failure.Label
        $failureValue = [Int32]$failure.Code
        $failureBytes = [BitConverter]::GetBytes($failureValue)
        Emit-Bytes -Bytes ([byte[]]@(0xB8) + $failureBytes)
        Emit-StoreEaxFrame -SlotPosition $resultSlot
        Emit-Jump -Label $cleanup
    }
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $cleanup

    Mark-CodeLabel -Label $cleanup
    # On every post-create failure, stop the complete job and confirm it is empty before returning.
    Emit-LoadEaxFrame -SlotPosition $childActiveSlot
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    $skipCleanupKill = New-UniqueLabel -Prefix 'dev_tool_skip_cleanup_kill'
    Emit-JumpConditional -ConditionCode 0x84 -Label $skipCleanupKill
    Emit-LoadRcxFrame -SlotPosition $jobHandleSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x05, 0x00, 0xAD, 0xDE))
    Emit-Win64CallIat -TargetRva ([UInt32]0x31B0) -StackArguments @() # TerminateJobObject
    Emit-LoadRcxFrame -SlotPosition $jobHandleSlot
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0xFF, 0xFF, 0xFF, 0xFF))
    Emit-Win64CallIat -TargetRva ([UInt32]0x30D0) -StackArguments @() # WaitForSingleObject(job,INFINITE)
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    $cleanupWaitOk = New-UniqueLabel -Prefix 'dev_tool_cleanup_wait_ok'
    Emit-JumpConditional -ConditionCode 0x84 -Label $cleanupWaitOk
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x93, 0xFF, 0xFF, 0xFF))
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $skipCleanupKill
    Mark-CodeLabel -Label $cleanupWaitOk
    Emit-StoreBits32Frame -SlotPosition $childActiveSlot -Value 0
    Mark-CodeLabel -Label $skipCleanupKill

    # Persist at most the captured 1 MiB through the same exclusive, non-inherited file handle.
    Emit-LoadRaxFrame -SlotPosition $outputFileHandleSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    $skipPersist = New-UniqueLabel -Prefix 'dev_tool_skip_output_persist'
    Emit-JumpConditional -ConditionCode 0x84 -Label $skipPersist
    Emit-LoadRaxFrame -SlotPosition $outputBufferSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $skipPersist
    Emit-LoadRcxFrame -SlotPosition $outputFileHandleSlot
    Emit-LoadRaxFrame -SlotPosition $outputBufferSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-LoadEaxFrame -SlotPosition $outputCountSlot
    Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC0))
    Emit-LeaRaxFrame -SlotPosition $outputWrittenSlot
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3078) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 0 }
    ) # WriteFile
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    $outputPersistOk = New-UniqueLabel -Prefix 'dev_tool_output_persist_ok'
    Emit-JumpConditional -ConditionCode 0x85 -Label $outputPersistOk
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x8D, 0xFF, 0xFF, 0xFF)) # -115
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $skipPersist
    Mark-CodeLabel -Label $outputPersistOk
    Emit-LoadEaxFrame -SlotPosition $outputWrittenSlot
    Emit-Bytes -Bytes ([byte[]]@(0x3B, 0x85))
    Emit-I32 -Value (Get-FrameDisp -SlotPosition $outputCountSlot)
    $outputLengthOk = New-UniqueLabel -Prefix 'dev_tool_output_length_ok'
    Emit-JumpConditional -ConditionCode 0x84 -Label $outputLengthOk
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x8D, 0xFF, 0xFF, 0xFF)) # -115: short output write
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Mark-CodeLabel -Label $outputLengthOk
    Mark-CodeLabel -Label $skipPersist

    # Close every acquired handle and release the serialization mutex last.
    foreach ($slot in @($pipeReadSlot, $pipeWriteSlot, $nulHandleSlot, $outputFileHandleSlot)) {
        $skipClose = New-UniqueLabel -Prefix 'dev_tool_skip_close_handle'
        Emit-LoadRcxFrame -SlotPosition $slot
        Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
        Emit-JumpConditional -ConditionCode 0x84 -Label $skipClose
        Emit-Win64CallIat -TargetRva ([UInt32]0x30B8) -StackArguments @() # CloseHandle
        Mark-CodeLabel -Label $skipClose
    }
    foreach ($slot in @(($processSlot + 8), $processSlot)) {
        $skipCloseProcess = New-UniqueLabel -Prefix 'dev_tool_skip_close_process'
        Emit-LoadRcxFrame -SlotPosition $slot
        Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
        Emit-JumpConditional -ConditionCode 0x84 -Label $skipCloseProcess
        Emit-Win64CallIat -TargetRva ([UInt32]0x30B8) -StackArguments @() # CloseHandle
        Mark-CodeLabel -Label $skipCloseProcess
    }
    foreach ($slot in @($jobHandleSlot, $hashFileHandleSlot, $sourceTokenSlot, $restrictedTokenSlot, $childTokenSlot)) {
        $skipCloseOther = New-UniqueLabel -Prefix 'dev_tool_skip_close_other'
        Emit-LoadRcxFrame -SlotPosition $slot
        Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
        Emit-JumpConditional -ConditionCode 0x84 -Label $skipCloseOther
        Emit-Win64CallIat -TargetRva ([UInt32]0x30B8) -StackArguments @() # CloseHandle
        Mark-CodeLabel -Label $skipCloseOther
    }

    Emit-LoadEaxFrame -SlotPosition $attributeListReadySlot
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    $skipDeleteAttributes = New-UniqueLabel -Prefix 'dev_tool_skip_delete_attributes'
    Emit-JumpConditional -ConditionCode 0x84 -Label $skipDeleteAttributes
    Emit-LoadRcxFrame -SlotPosition $attributeListSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x3258) -StackArguments @() # DeleteProcThreadAttributeList
    Mark-CodeLabel -Label $skipDeleteAttributes

    foreach ($slot in @($attributeListSlot, $outputBufferSlot)) {
        $skipFreeMemory = New-UniqueLabel -Prefix 'dev_tool_skip_free_memory'
        Emit-LoadRcxFrame -SlotPosition $slot
        Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
        Emit-JumpConditional -ConditionCode 0x84 -Label $skipFreeMemory
        Emit-Bytes -Bytes ([byte[]]@(0x33, 0xD2, 0x41, 0xB8, 0x00, 0x80, 0x00, 0x00))
        Emit-Win64CallIat -TargetRva ([UInt32]0x31D8) -StackArguments @() # VirtualFree(MEM_RELEASE)
        Mark-CodeLabel -Label $skipFreeMemory
    }

    # Roll back only after the Job Object is known empty. If the wait failed,
    # retain the committed journal; closing the job handle requests kill-on-close,
    # and the next invocation performs authoritative recovery before any child launch.
    $skipAclRollback = New-UniqueLabel -Prefix 'dev_tool_skip_acl_rollback'
    Emit-LoadEaxFrame -SlotPosition $childActiveSlot
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x85 -Label $skipAclRollback
    Emit-LoadEaxFrame -SlotPosition $transactionActiveSlot
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $skipAclRollback

    Emit-DevBrokerRestoreSecurityDescriptor -PathSlot $workspaceRootSlot -DescriptorSlot $rootDescriptorSlot -FailureLabel $aclRollbackRootFail
    Emit-DevBrokerRestoreSecurityDescriptor -PathSlot $buildPathSlot -DescriptorSlot $buildDescriptorSlot -RestoreLabel $true -FailureLabel $aclRollbackBuildFail
    Emit-DevBrokerRestoreSecurityDescriptor -PathSlot $brokerDirectorySlot -DescriptorSlot $brokerDescriptorSlot -RestoreLabel $true -FailureLabel $aclRollbackBrokerFail

    Emit-LeaRaxFrame -SlotPosition $journalPathSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3310) -StackArguments @() # delete active journal only after all three descriptors are restored
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    Emit-JumpConditional -ConditionCode 0x84 -Label $aclRollbackJournalFail
    Emit-StoreBits32Frame -SlotPosition $transactionActiveSlot -Value 0
    Emit-Jump -Label $skipAclRollback

    Mark-CodeLabel -Label $aclRollbackRootFail
    Emit-LoadEaxFrame -SlotPosition ($scratch + 0xE80)
    Emit-Bytes -Bytes ([byte[]]@(0x83, 0xF8, 0x06))
    $rootSetSecurityFailed = New-UniqueLabel -Prefix 'dev_tool_root_set_security_failed'
    $rootRestoreStatusReady = New-UniqueLabel -Prefix 'dev_tool_root_restore_status_ready'
    Emit-JumpConditional -ConditionCode 0x84 -Label $rootSetSecurityFailed
    Emit-LoadEaxFrame -SlotPosition ($scratch + 0xE80)
    Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC2, 0xB8, 0x38, 0xFF, 0xFF, 0xFF, 0x29, 0xD0)) # -200 - pre-SetSecurityInfo stage
    Emit-Jump -Label $rootRestoreStatusReady
    Mark-CodeLabel -Label $rootSetSecurityFailed
    Emit-LoadEaxFrame -SlotPosition ($scratch + 0xE84)
    Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC2, 0xB8, 0x48, 0xF4, 0xFF, 0xFF, 0x29, 0xD0)) # -3000 - Win32 SetSecurityInfo error
    Mark-CodeLabel -Label $rootRestoreStatusReady
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $skipAclRollback

    Mark-CodeLabel -Label $aclRollbackBuildFail
    Emit-LoadEaxFrame -SlotPosition ($scratch + 0xE80)
    Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC2, 0xB8, 0x24, 0xFF, 0xFF, 0xFF, 0x29, 0xD0)) # -220 - restore stage
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $skipAclRollback

    Mark-CodeLabel -Label $aclRollbackBrokerFail
    Emit-LoadEaxFrame -SlotPosition ($scratch + 0xE80)
    Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC2, 0xB8, 0x10, 0xFF, 0xFF, 0xFF, 0x29, 0xD0)) # -240 - restore stage
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $skipAclRollback

    Mark-CodeLabel -Label $aclRollbackJournalFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x7C, 0xFF, 0xFF, 0xFF)) # -132: ACL journal could not be retired after restore
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $skipAclRollback

    Mark-CodeLabel -Label $aclRollbackFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x80, 0xFF, 0xFF, 0xFF)) # -128: generic ACL rollback failure
    Emit-StoreEaxFrame -SlotPosition $resultSlot
    Mark-CodeLabel -Label $skipAclRollback

    # Delete the unique profile only after the Job Object is empty and all committed
    # ACL changes have been restored and the journal retired. A crash leaves an
    # orphaned profile until the separate authenticated service recovery path exists.
    Emit-DevBrokerDeleteOwnedAppContainerProfile -ProfileNameSlot $profileNameSlot -ProfileCreatedSlot $profileCreatedSlot -ChildActiveSlot $childActiveSlot -TransactionActiveSlot $transactionActiveSlot -ResultSlot $resultSlot

    # GetSecurityInfo descriptors are LocalFree allocations; recovery-buffer
    # interior pointers were cleared by RecoverAclJournal and must not be freed here.
    foreach ($slot in @($rootDescriptorSlot, $buildDescriptorSlot, $brokerDescriptorSlot)) {
        $skipFreeDescriptor = New-UniqueLabel -Prefix 'dev_tool_skip_free_acl_descriptor'
        Emit-LoadRcxFrame -SlotPosition $slot
        Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
        Emit-JumpConditional -ConditionCode 0x84 -Label $skipFreeDescriptor
        Emit-Win64CallIat -TargetRva ([UInt32]0x3260) -StackArguments @() # LocalFree
        Emit-StoreZero64Frame -SlotPosition $slot
        Mark-CodeLabel -Label $skipFreeDescriptor
    }

    Emit-LoadRcxFrame -SlotPosition $appContainerSidSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
    $skipFreeSid = New-UniqueLabel -Prefix 'dev_tool_skip_free_sid'
    Emit-JumpConditional -ConditionCode 0x84 -Label $skipFreeSid
    Emit-Win64CallIat -TargetRva ([UInt32]0x32A8) -StackArguments @() # FreeSid
    Mark-CodeLabel -Label $skipFreeSid

    Emit-LoadRcxFrame -SlotPosition $legacyAppContainerSidSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
    $skipFreeLegacySid = New-UniqueLabel -Prefix 'dev_tool_skip_free_legacy_sid'
    Emit-JumpConditional -ConditionCode 0x84 -Label $skipFreeLegacySid
    Emit-Win64CallIat -TargetRva ([UInt32]0x32A8) -StackArguments @() # FreeSid
    Emit-StoreZero64Frame -SlotPosition $legacyAppContainerSidSlot
    Mark-CodeLabel -Label $skipFreeLegacySid

    Emit-LoadEaxFrame -SlotPosition $mutexAcquiredSlot
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
    $skipReleaseMutex = New-UniqueLabel -Prefix 'dev_tool_skip_release_mutex'
    Emit-JumpConditional -ConditionCode 0x84 -Label $skipReleaseMutex
    Emit-LoadRcxFrame -SlotPosition $mutexHandleSlot
    Emit-Win64CallIat -TargetRva ([UInt32]0x30E0) -StackArguments @() # ReleaseMutex
    Mark-CodeLabel -Label $skipReleaseMutex
    $skipCloseMutex = New-UniqueLabel -Prefix 'dev_tool_skip_close_mutex'
    Emit-LoadRcxFrame -SlotPosition $mutexHandleSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9))
    Emit-JumpConditional -ConditionCode 0x84 -Label $skipCloseMutex
    Emit-Win64CallIat -TargetRva ([UInt32]0x30B8) -StackArguments @()
    Mark-CodeLabel -Label $skipCloseMutex

    Emit-LoadRdiFrame -SlotPosition $saveRdiSlot
    Emit-LoadRsiFrame -SlotPosition $saveRsiSlot
    Emit-LoadEaxFrame -SlotPosition $resultSlot
    Emit-Jump -Label $done
    Mark-CodeLabel -Label $done
}
function Emit-BuiltinCall {
    param([object] $Node)
    $baseDepth = [int]$script:TempDepth
    $argSlots = [System.Collections.Generic.List[int]]::new()
    switch ($Node.Builtin) {
        'Win64CallbackProbe' {
            $serviceMainPointer = Register-CodeCallbackPointer -Key 'CALLBACK:SERVICE_MAIN_FUNCTIONW' -Label '__r51_service_main_abi_probe' -Signature 'SERVICE_MAIN_FUNCTIONW'
            $handlerExPointer = Register-CodeCallbackPointer -Key 'CALLBACK:HANDLER_FUNCTION_EX' -Label '__r51_handler_ex_abi_probe' -Signature 'HANDLER_FUNCTION_EX'
            $failLabel = New-UniqueLabel -Prefix 'win64_callback_probe_fail'
            $doneLabel = New-UniqueLabel -Prefix 'win64_callback_probe_done'

            # SERVICE_MAIN_FUNCTIONW is VOID: RCX=argc (DWORD), RDX=argv-vector pointer (LPWSTR*).
            # Pass a writable one-entry pointer vector so the void callback can report its test result
            # through the documented LPWSTR* argument rather than relying on an undefined return value.
            Emit-StoreZero64Frame -SlotPosition $script:ActiveContext.ScratchPosition
            Emit-Bytes -Bytes ([byte[]]@(0xB9, 0xDF, 0x9B, 0x57, 0x13))
            Emit-LeaRaxFrame -SlotPosition $script:ActiveContext.ScratchPosition
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2, 0x48, 0x83, 0xEC, 0x20))
            Emit-CallDataPointer -DataItem $serviceMainPointer
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20))
            Emit-LoadRaxFrame -SlotPosition $script:ActiveContext.ScratchPosition
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0xB9))
            $script:Code.AddRange([BitConverter]::GetBytes([UInt64]::Parse('0000000051A7C0DE', [System.Globalization.NumberStyles]::HexNumber)))
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0x39, 0xC8))
            Emit-JumpConditional -ConditionCode 0x85 -Label $failLabel

            # HandlerEx: four ABI registers, including both full-width pointer arguments.
            Emit-Bytes -Bytes ([byte[]]@(0xB9, 0x78, 0x56, 0x34, 0x12, 0xBA, 0x21, 0x43, 0x65, 0x87))
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0xB8))
            $script:Code.AddRange([BitConverter]::GetBytes([UInt64]::Parse('1122334455667788', [System.Globalization.NumberStyles]::HexNumber)))
            Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0, 0x48, 0xB8))
            $script:Code.AddRange([BitConverter]::GetBytes([UInt64]::Parse('8877665544332211', [System.Globalization.NumberStyles]::HexNumber)))
            Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC1, 0x48, 0x83, 0xEC, 0x20))
            Emit-CallDataPointer -DataItem $handlerExPointer
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20, 0x3D, 0xDE, 0xC0, 0xA7, 0x51))
            Emit-JumpConditional -ConditionCode 0x85 -Label $failLabel
            Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x01, 0x00, 0x00, 0x00))
            Emit-Jump -Label $doneLabel
            Mark-CodeLabel -Label $failLabel
            Emit-Jump -Label '__runtime_fail'
            Mark-CodeLabel -Label $doneLabel
            $script:TempDepth = $baseDepth
            return
        }
        'AbiNonvolatileProbe' {
            Emit-NonvolatileRegisterProbe -Node $Node -BaseDepth $baseDepth
            $script:TempDepth = $baseDepth
            return
        }
        'StringLength' {
            Emit-StringExpression -Node $Node.Arguments[0]
            Emit-Bytes -Bytes ([byte[]]@(0x89, 0xD0)) # EAX = EDX (UTF-8/ASCII byte length)
            return
        }
        'Log' {
            Emit-PrintString -Node $Node.Arguments[0]
            Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x01, 0x00, 0x00, 0x00))
            return
        }
        'StringEqual' {
            Emit-BuiltinArguments -Node $Node -BaseDepth $baseDepth
            $leftSlot = Get-TempSlotPosition -Depth $baseDepth
            $rightSlot = Get-TempSlotPosition -Depth ($baseDepth + 1)
            $saveRsiSlot = Get-TempSlotPosition -Depth ($baseDepth + 2)
            $saveRdiSlot = Get-TempSlotPosition -Depth ($baseDepth + 3)
            $notEqual = New-UniqueLabel -Prefix 'string_equal_false'
            $emptyEqual = New-UniqueLabel -Prefix 'string_equal_empty'
            $done = New-UniqueLabel -Prefix 'string_equal_done'
            Emit-LoadEaxFrame -SlotPosition ($leftSlot + 8)
            Emit-Bytes -Bytes ([byte[]]@(0x8B, 0x8D)); Emit-I32 -Value (Get-FrameDisp -SlotPosition ($rightSlot + 8))
            Emit-Bytes -Bytes ([byte[]]@(0x39, 0xC8)); Emit-JumpConditional -ConditionCode 0x85 -Label $notEqual
            Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $emptyEqual
            Emit-StoreRsiFrame -SlotPosition $saveRsiSlot; Emit-StoreRdiFrame -SlotPosition $saveRdiSlot
            Emit-LoadRsiFrame -SlotPosition $leftSlot; Emit-LoadRdiFrame -SlotPosition $rightSlot
            Emit-Bytes -Bytes ([byte[]]@(0x8B, 0x8D)); Emit-I32 -Value (Get-FrameDisp -SlotPosition ($leftSlot + 8))
            Emit-Bytes -Bytes ([byte[]]@(0xF3, 0xA6, 0x0F, 0x94, 0xC0, 0x0F, 0xB6, 0xC0)) # REPE CMPSB; SETE AL; MOVZX EAX,AL
            Emit-LoadRdiFrame -SlotPosition $saveRdiSlot; Emit-LoadRsiFrame -SlotPosition $saveRsiSlot
            Emit-Jump -Label $done
            Mark-CodeLabel -Label $emptyEqual; Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x01, 0x00, 0x00, 0x00)); Emit-Jump -Label $done
            Mark-CodeLabel -Label $notEqual; Emit-Bytes -Bytes ([byte[]]@(0x31, 0xC0))
            Mark-CodeLabel -Label $done
            $script:TempDepth = $baseDepth
            return
        }
    }
    Emit-BuiltinArguments -Node $Node -BaseDepth $baseDepth
    for ($i = 0; $i -lt $Node.Arguments.Count; $i++) { $argSlots.Add((Get-TempSlotPosition -Depth ($baseDepth + $i))) }
    switch ($Node.Builtin) {
        'MemoryByteAt' {
            $indexSlot = $argSlots[0]
            $invalidLabel = New-UniqueLabel -Prefix 'memory_byte_invalid'
            $doneLabel = New-UniqueLabel -Prefix 'memory_byte_done'
            Emit-LoadEaxFrame -SlotPosition $indexSlot
            Emit-Bytes -Bytes ([byte[]]@(0x83, 0xF8, 0x00)); Emit-JumpConditional -ConditionCode 0x8C -Label $invalidLabel
            Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x00, 0x10, 0x00, 0x00)); Emit-JumpConditional -ConditionCode 0x8D -Label $invalidLabel
            Emit-Bytes -Bytes ([byte[]]@(0x0F, 0xB6, 0x84, 0x05)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $script:ActiveContext.ScratchPosition) # movzx eax, byte ptr [rbp + rax + scratch_disp]
            Emit-Jump -Label $doneLabel
            Mark-CodeLabel -Label $invalidLabel; Emit-Bytes -Bytes ([byte[]]@(0xB8, 0xFF, 0xFF, 0xFF, 0xFF))
            Mark-CodeLabel -Label $doneLabel
        }
        'MemoryFill' {
            $lengthSlot = $argSlots[0]; $valueSlot = $argSlots[1]
            $invalidLabel = New-UniqueLabel -Prefix 'memory_fill_invalid'
            $doneLabel = New-UniqueLabel -Prefix 'memory_fill_done'
            Emit-LoadEaxFrame -SlotPosition $lengthSlot
            Emit-Bytes -Bytes ([byte[]]@(0x83, 0xF8, 0x00)); Emit-JumpConditional -ConditionCode 0x8C -Label $invalidLabel
            Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x00, 0x10, 0x00, 0x00)); Emit-JumpConditional -ConditionCode 0x8F -Label $invalidLabel
            Emit-LoadEaxFrame -SlotPosition $valueSlot
            Emit-Bytes -Bytes ([byte[]]@(0x83, 0xF8, 0x00)); Emit-JumpConditional -ConditionCode 0x8C -Label $invalidLabel
            Emit-Bytes -Bytes ([byte[]]@(0x3D, 0xFF, 0x00, 0x00, 0x00)); Emit-JumpConditional -ConditionCode 0x8F -Label $invalidLabel
            Emit-StoreRdiFrame -SlotPosition (Get-TempSlotPosition -Depth ($baseDepth + 2)) # preserve nonvolatile RDI
            Emit-LeaRaxFrame -SlotPosition $script:ActiveContext.ScratchPosition
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC7)) # RDI = scratch buffer
            Emit-LoadEaxFrame -SlotPosition $lengthSlot; Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC1)) # ECX = length
            Emit-LoadEaxFrame -SlotPosition $valueSlot
            Emit-Bytes -Bytes ([byte[]]@(0xF3, 0xAA)) # REP STOSB; runtime memory fill
            Emit-LoadRdiFrame -SlotPosition (Get-TempSlotPosition -Depth ($baseDepth + 2))
            Emit-LoadEaxFrame -SlotPosition $lengthSlot
            Emit-Jump -Label $doneLabel
            Mark-CodeLabel -Label $invalidLabel
            Emit-Bytes -Bytes ([byte[]]@(0xB8, 0xFF, 0xFF, 0xFF, 0xFF)) # -1 invalid request
            Mark-CodeLabel -Label $doneLabel
        }
        'FileExists' {
            $pathSlot = $argSlots[0]; $handleSlot = Get-TempSlotPosition -Depth ($baseDepth + 1)
            $failLabel = New-UniqueLabel -Prefix 'file_exists_fail'; $doneLabel = New-UniqueLabel -Prefix 'file_exists_done'
            Emit-CreateFileForPath -PathSlot $pathSlot
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xF8, 0xFF)); Emit-JumpConditional -ConditionCode 0x84 -Label $failLabel
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failLabel
            Emit-StoreRaxFrame -SlotPosition $handleSlot
            Emit-LoadRcxFrame -SlotPosition $handleSlot; Emit-CallIat -TargetRva ([UInt32]0x30B8) # CloseHandle
            Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x01, 0x00, 0x00, 0x00)); Emit-Jump -Label $doneLabel
            Mark-CodeLabel -Label $failLabel; Emit-Bytes -Bytes ([byte[]]@(0x31, 0xC0))
            Mark-CodeLabel -Label $doneLabel
        }
        'FileSize' {
            $pathSlot = $argSlots[0]; $handleSlot = Get-TempSlotPosition -Depth ($baseDepth + 1); $sizeSlot = Get-TempSlotPosition -Depth ($baseDepth + 2)
            $failOpen = New-UniqueLabel -Prefix 'file_size_open_fail'; $failHandle = New-UniqueLabel -Prefix 'file_size_read_fail'; $doneLabel = New-UniqueLabel -Prefix 'file_size_done'
            Emit-CreateFileForPath -PathSlot $pathSlot
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xF8, 0xFF)); Emit-JumpConditional -ConditionCode 0x84 -Label $failOpen
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failOpen
            Emit-StoreRaxFrame -SlotPosition $handleSlot
            Emit-LoadRcxFrame -SlotPosition $handleSlot; Emit-LeaRdxFrame -SlotPosition $script:ActiveContext.ScratchPosition; Emit-CallIat -TargetRva ([UInt32]0x30A8) # GetFileSizeEx
            Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failHandle
            Emit-Bytes -Bytes ([byte[]]@(0x8B, 0x8D)); Emit-I32 -Value (Get-FrameDisp -SlotPosition ($script:ActiveContext.ScratchPosition + 4)); Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC9)); Emit-JumpConditional -ConditionCode 0x85 -Label $failHandle
            Emit-LoadEaxFrame -SlotPosition $script:ActiveContext.ScratchPosition; Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x88 -Label $failHandle
            Emit-StoreEaxFrame -SlotPosition $sizeSlot
            Emit-LoadRcxFrame -SlotPosition $handleSlot; Emit-CallIat -TargetRva ([UInt32]0x30B8)
            Emit-LoadEaxFrame -SlotPosition $sizeSlot; Emit-Jump -Label $doneLabel
            Mark-CodeLabel -Label $failHandle; Emit-LoadRcxFrame -SlotPosition $handleSlot; Emit-CallIat -TargetRva ([UInt32]0x30B8)
            Mark-CodeLabel -Label $failOpen; Emit-Bytes -Bytes ([byte[]]@(0xB8, 0xFF, 0xFF, 0xFF, 0xFF))
            Mark-CodeLabel -Label $doneLabel
        }
        'AssetReadCount' {
            $pathSlot = $argSlots[0]; $capacitySlot = $argSlots[1]; $handleSlot = Get-TempSlotPosition -Depth ($baseDepth + 2); $countSlot = Get-TempSlotPosition -Depth ($baseDepth + 3)
            $invalid = New-UniqueLabel -Prefix 'asset_read_invalid'; $failOpen = New-UniqueLabel -Prefix 'asset_read_open_fail'; $failRead = New-UniqueLabel -Prefix 'asset_read_fail'; $doneLabel = New-UniqueLabel -Prefix 'asset_read_done'
            Emit-LoadEaxFrame -SlotPosition $capacitySlot; Emit-Bytes -Bytes ([byte[]]@(0x83, 0xF8, 0x00)); Emit-JumpConditional -ConditionCode 0x8C -Label $invalid
            Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x00, 0x10, 0x00, 0x00)); Emit-JumpConditional -ConditionCode 0x8F -Label $invalid
            Emit-CreateFileForPath -PathSlot $pathSlot
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xF8, 0xFF)); Emit-JumpConditional -ConditionCode 0x84 -Label $failOpen
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failOpen
            Emit-StoreRaxFrame -SlotPosition $handleSlot
            Emit-LoadRcxFrame -SlotPosition $handleSlot; Emit-LeaRdxFrame -SlotPosition $script:ActiveContext.ScratchPosition
            Emit-LoadEaxFrame -SlotPosition $capacitySlot; Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC0))
            Emit-LeaRaxFrame -SlotPosition ($script:ActiveContext.ScratchPosition + 0x1000); Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC1))
            Emit-Win64CallIat -TargetRva ([UInt32]0x30B0) -StackArguments @(
                @{ Kind = 'Immediate'; Value = 0 }
            ) # ReadFile; Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failRead
            Emit-Bytes -Bytes ([byte[]]@(0x8B, 0x85)); Emit-I32 -Value (Get-FrameDisp -SlotPosition ($script:ActiveContext.ScratchPosition + 0x1000)); Emit-StoreEaxFrame -SlotPosition $countSlot
            Emit-LoadRcxFrame -SlotPosition $handleSlot; Emit-CallIat -TargetRva ([UInt32]0x30B8); Emit-LoadEaxFrame -SlotPosition $countSlot; Emit-Jump -Label $doneLabel
            Mark-CodeLabel -Label $failRead; Emit-LoadRcxFrame -SlotPosition $handleSlot; Emit-CallIat -TargetRva ([UInt32]0x30B8); Emit-Jump -Label $failOpen
            Mark-CodeLabel -Label $failOpen; Emit-Bytes -Bytes ([byte[]]@(0xB8, 0xFF, 0xFF, 0xFF, 0xFF)); Emit-Jump -Label $doneLabel
            Mark-CodeLabel -Label $invalid; Emit-Bytes -Bytes ([byte[]]@(0xB8, 0xFF, 0xFF, 0xFF, 0xFF))
            Mark-CodeLabel -Label $doneLabel
        }
        'AssetReadByte' {
            $pathSlot = $argSlots[0]; $indexSlot = $argSlots[1]
            $handleSlot = Get-TempSlotPosition -Depth ($baseDepth + 2)
            $byteSlot = Get-TempSlotPosition -Depth ($baseDepth + 3)
            $invalid = New-UniqueLabel -Prefix 'asset_byte_invalid'
            $failOpen = New-UniqueLabel -Prefix 'asset_byte_open_fail'
            $failRead = New-UniqueLabel -Prefix 'asset_byte_read_fail'
            $doneLabel = New-UniqueLabel -Prefix 'asset_byte_done'
            Emit-LoadEaxFrame -SlotPosition $indexSlot
            Emit-Bytes -Bytes ([byte[]]@(0x83, 0xF8, 0x00)); Emit-JumpConditional -ConditionCode 0x8C -Label $invalid
            Emit-Bytes -Bytes ([byte[]]@(0x3D, 0xFF, 0x0F, 0x00, 0x00)); Emit-JumpConditional -ConditionCode 0x8F -Label $invalid # index must be <= 4095
            Emit-CreateFileForPath -PathSlot $pathSlot
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xF8, 0xFF)); Emit-JumpConditional -ConditionCode 0x84 -Label $failOpen
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failOpen
            Emit-StoreRaxFrame -SlotPosition $handleSlot
            Emit-LoadRcxFrame -SlotPosition $handleSlot; Emit-LeaRdxFrame -SlotPosition $script:ActiveContext.ScratchPosition
            Emit-LoadEaxFrame -SlotPosition $indexSlot; Emit-Bytes -Bytes ([byte[]]@(0x83, 0xC0, 0x01, 0x41, 0x89, 0xC0)) # read index + 1 bytes
            Emit-LeaRaxFrame -SlotPosition ($script:ActiveContext.ScratchPosition + 0x1000); Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC1))
            Emit-Win64CallIat -TargetRva ([UInt32]0x30B0) -StackArguments @(
                @{ Kind = 'Immediate'; Value = 0 }
            ) # ReadFile; Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failRead
            Emit-LoadEaxFrame -SlotPosition ($script:ActiveContext.ScratchPosition + 0x1000)
            Emit-Bytes -Bytes ([byte[]]@(0x8B, 0x8D)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $indexSlot); Emit-Bytes -Bytes ([byte[]]@(0x83, 0xC1, 0x01, 0x39, 0xC8)); Emit-JumpConditional -ConditionCode 0x82 -Label $failRead # fail if read count < index + 1
            Emit-LoadEaxFrame -SlotPosition $indexSlot
            Emit-Bytes -Bytes ([byte[]]@(0x0F, 0xB6, 0x84, 0x05)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $script:ActiveContext.ScratchPosition)
            Emit-StoreEaxFrame -SlotPosition $byteSlot
            Emit-LoadRcxFrame -SlotPosition $handleSlot; Emit-CallIat -TargetRva ([UInt32]0x30B8)
            Emit-LoadEaxFrame -SlotPosition $byteSlot; Emit-Jump -Label $doneLabel
            Mark-CodeLabel -Label $failRead; Emit-LoadRcxFrame -SlotPosition $handleSlot; Emit-CallIat -TargetRva ([UInt32]0x30B8); Emit-Jump -Label $failOpen
            Mark-CodeLabel -Label $failOpen; Emit-Bytes -Bytes ([byte[]]@(0xB8, 0xFF, 0xFF, 0xFF, 0xFF)); Emit-Jump -Label $doneLabel
            Mark-CodeLabel -Label $invalid; Emit-Bytes -Bytes ([byte[]]@(0xB8, 0xFF, 0xFF, 0xFF, 0xFF))
            Mark-CodeLabel -Label $doneLabel
        }
        'D3D11RenderDemo' { Emit-D3D11RenderDemo -BaseDepth $baseDepth -ArgumentSlots $argSlots }
        'DevRunTool' { Emit-DevRunTool -ToolSlot $argSlots[0] -TimeoutSlot $argSlots[1] -BaseDepth $baseDepth }
        'WindowProbe' {
            $titleSlot = $argSlots[0]; $instanceSlot = Get-TempSlotPosition -Depth ($baseDepth + 1); $windowSlot = Get-TempSlotPosition -Depth ($baseDepth + 2)
            $failLabel = New-UniqueLabel -Prefix 'window_create_fail'; $doneLabel = New-UniqueLabel -Prefix 'window_create_done'
            Emit-Bytes -Bytes ([byte[]]@(0x33, 0xC9)); Emit-CallIat -TargetRva ([UInt32]0x30C0) # GetModuleHandleA(NULL)
            Emit-StoreRaxFrame -SlotPosition $instanceSlot
            Emit-Bytes -Bytes ([byte[]]@(0x33, 0xC9)); Emit-DataAddress -DataItem (Register-DataConstant -Value 'STATIC'); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2)) # class name -> RDX
            Emit-LoadRaxFrame -SlotPosition $titleSlot; Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0)) # title -> R8
            Emit-Bytes -Bytes ([byte[]]@(0x41, 0xB9, 0x00, 0x00, 0xCF, 0x00)) # hidden WS_OVERLAPPEDWINDOW
            Emit-Win64CallIat -TargetRva ([UInt32]0x30F0) -StackArguments @(
                @{ Kind = 'Immediate'; Value = -2147483648 },
                @{ Kind = 'Immediate'; Value = -2147483648 },
                @{ Kind = 'Immediate'; Value = 320 },
                @{ Kind = 'Immediate'; Value = 240 },
                @{ Kind = 'Immediate'; Value = 0 },
                @{ Kind = 'Immediate'; Value = 0 },
                @{ Kind = 'FrameQword'; SlotPosition = $instanceSlot },
                @{ Kind = 'Immediate'; Value = 0 }
            ) # CreateWindowExA; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failLabel
            Emit-StoreRaxFrame -SlotPosition $windowSlot
            # Keep the test window hidden, update it, and non-blockingly dispatch one queued message.
            Emit-LoadRcxFrame -SlotPosition $windowSlot; Emit-Bytes -Bytes ([byte[]]@(0x33, 0xD2)); Emit-CallIat -TargetRva ([UInt32]0x30F8) # ShowWindow(SW_HIDE)
            Emit-LoadRcxFrame -SlotPosition $windowSlot; Emit-CallIat -TargetRva ([UInt32]0x3100) # UpdateWindow
            Emit-WindowPumpCore
            Emit-LoadRcxFrame -SlotPosition $windowSlot; Emit-CallIat -TargetRva ([UInt32]0x3120) # DestroyWindow
            Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x01, 0x00, 0x00, 0x00)); Emit-Jump -Label $doneLabel
            Mark-CodeLabel -Label $failLabel; Emit-Bytes -Bytes ([byte[]]@(0x31, 0xC0))
            Mark-CodeLabel -Label $doneLabel
        }
        'WindowPump' { Emit-WindowPumpCore }
        'ThreadSyncProbe' { Emit-ThreadSyncCore -BaseDepth $baseDepth }
        default { Throw-SourceError -Line $Node.Line -Column $Node.Column -Message ("Unsupported standard-library intrinsic '{0}'." -f $Node.Builtin) }
    }
    $script:TempDepth = $baseDepth
}
function Emit-WindowPumpCore {
    $noneLabel = New-UniqueLabel -Prefix 'window_pump_none'; $doneLabel = New-UniqueLabel -Prefix 'window_pump_done'
    Emit-LeaRaxFrame -SlotPosition $script:ActiveContext.ScratchPosition; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xD2, 0x45, 0x33, 0xC0, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3108) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 1 }
    ) # PeekMessageA; Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $noneLabel
    Emit-LeaRaxFrame -SlotPosition $script:ActiveContext.ScratchPosition; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1)); Emit-CallIat -TargetRva ([UInt32]0x3110) # TranslateMessage
    Emit-LeaRaxFrame -SlotPosition $script:ActiveContext.ScratchPosition; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1)); Emit-CallIat -TargetRva ([UInt32]0x3118) # DispatchMessageA
    Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x01, 0x00, 0x00, 0x00)); Emit-Jump -Label $doneLabel
    Mark-CodeLabel -Label $noneLabel; Emit-Bytes -Bytes ([byte[]]@(0x31, 0xC0))
    Mark-CodeLabel -Label $doneLabel
}
function Emit-D3D11MessagePump {
    param([int] $MessageSlot, [int] $WindowSlot, [string] $LoopDoneLabel)
    $checkWindow = New-UniqueLabel -Prefix 'd3d11_message_check_window'
    $dispatch = New-UniqueLabel -Prefix 'd3d11_message_dispatch'
    # PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)
    Emit-LeaRaxFrame -SlotPosition $MessageSlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xD2, 0x45, 0x33, 0xC0, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3108) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 1 }
    ) # PeekMessageA; Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $checkWindow
    # MSG.message is the DWORD at offset 8 on x64. WM_QUIT terminates the demo loop.
    Emit-Bytes -Bytes ([byte[]]@(0x81, 0xBD)); Emit-I32 -Value (Get-FrameDisp -SlotPosition ($MessageSlot + 8)); Emit-I32 -Value 0x12
    Emit-JumpConditional -ConditionCode 0x85 -Label $dispatch
    Emit-Jump -Label $LoopDoneLabel
    Mark-CodeLabel -Label $dispatch
    Emit-LeaRaxFrame -SlotPosition $MessageSlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1, 0x48, 0x83, 0xEC, 0x20)); Emit-CallIat -TargetRva ([UInt32]0x3110); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20))
    Emit-LeaRaxFrame -SlotPosition $MessageSlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1, 0x48, 0x83, 0xEC, 0x20)); Emit-CallIat -TargetRva ([UInt32]0x3118); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20))
    Mark-CodeLabel -Label $checkWindow
    Emit-LoadRcxFrame -SlotPosition $WindowSlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x20)); Emit-CallIat -TargetRva ([UInt32]0x3168); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20))
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $LoopDoneLabel
}
function Emit-D3D11RenderDemo {
    param([int] $BaseDepth, [object] $ArgumentSlots)
    $titleSlot = [int]$ArgumentSlots[0]
    $framesSlot = [int]$ArgumentSlots[1]
    $scratch = [int]$script:ActiveContext.ScratchPosition
    $windowSlot = $scratch + 0x80
    $swapSlot = $scratch + 0x88
    $deviceSlot = $scratch + 0x90
    $contextSlot = $scratch + 0x98
    $backBufferSlot = $scratch + 0xA0
    $rtvSlot = $scratch + 0xA8
    $factorySlot = $scratch + 0xB0
    $featureSlot = $scratch + 0xB8
    $colorSlot = $scratch + 0xC0
    $factoryGuidSlot = $scratch + 0xE0
    $textureGuidSlot = $scratch + 0xF0
    $messageSlot = $scratch + 0x110
    $qpcStartSlot = $scratch + 0x150
    $qpcEndSlot = $scratch + 0x158
    $qpcFreqSlot = $scratch + 0x160
    $elapsedSlot = $scratch + 0x168
    $frameCountSlot = $scratch + 0x16C
    $bytesWrittenSlot = $scratch + 0x170
    $stdoutSlot = $scratch + 0x178
    $formatBufferSlot = $scratch + 0x200
    $formatLengthSlot = $scratch + 0x280
    $failLabel = '__runtime_fail'
    $deviceCreated = New-UniqueLabel -Prefix 'd3d11_device_created'
    $hardwareFailed = New-UniqueLabel -Prefix 'd3d11_hardware_failed'
    $loopStart = New-UniqueLabel -Prefix 'd3d11_render_loop'
    $loopDone = New-UniqueLabel -Prefix 'd3d11_render_done'
    $statsWritten = New-UniqueLabel -Prefix 'd3d11_stats_written'

    # The frame count is runtime input to this intrinsic; constrain the test loop to 1..240 frames.
    Emit-LoadEaxFrame -SlotPosition $framesSlot
    Emit-Bytes -Bytes ([byte[]]@(0x83, 0xF8, 0x01)); Emit-JumpConditional -ConditionCode 0x8C -Label $failLabel
    Emit-Bytes -Bytes ([byte[]]@(0x3D)); Emit-I32 -Value 240; Emit-JumpConditional -ConditionCode 0x8F -Label $failLabel

    # Initialize all output pointers and the 72-byte DXGI_SWAP_CHAIN_DESC.
    foreach ($slot in @($windowSlot, $swapSlot, $deviceSlot, $contextSlot, $backBufferSlot, $rtvSlot, $factorySlot)) { Emit-StoreZero64Frame -SlotPosition $slot }
    Emit-StoreBits32Frame -SlotPosition $featureSlot -Value ([UInt32]0)
    for ($i = 0; $i -lt 18; $i++) { Emit-StoreBits32Frame -SlotPosition ($scratch + ($i * 4)) -Value ([UInt32]0) }
    # DXGI_SWAP_CHAIN_DESC: 960x540, 60/1 Hz, R8G8B8A8_UNORM, sample count 1,
    # render-target output usage, 2 buffers, HWND set after window creation, windowed, discard.
    Emit-StoreBits32Frame -SlotPosition ($scratch + 0) -Value ([UInt32]960)
    Emit-StoreBits32Frame -SlotPosition ($scratch + 4) -Value ([UInt32]540)
    Emit-StoreBits32Frame -SlotPosition ($scratch + 8) -Value ([UInt32]60)
    Emit-StoreBits32Frame -SlotPosition ($scratch + 12) -Value ([UInt32]1)
    Emit-StoreBits32Frame -SlotPosition ($scratch + 16) -Value ([UInt32]28)
    Emit-StoreBits32Frame -SlotPosition ($scratch + 28) -Value ([UInt32]1)
    Emit-StoreBits32Frame -SlotPosition ($scratch + 36) -Value ([UInt32]0x20)
    Emit-StoreBits32Frame -SlotPosition ($scratch + 40) -Value ([UInt32]2)
    Emit-StoreBits32Frame -SlotPosition ($scratch + 56) -Value ([UInt32]1)
    # IID_IDXGIFactory = {7B7166EC-21C7-44AE-B21A-C9AE321AE369}.
    Emit-StoreBits32Frame -SlotPosition $factoryGuidSlot -Value ([UInt32]0x7B7166EC)
    Emit-StoreBits32Frame -SlotPosition ($factoryGuidSlot + 4) -Value ([UInt32]0x44AE21C7)
    Emit-StoreImm64Frame -SlotPosition ($factoryGuidSlot + 8) -Value ([UInt64]0x69E31A32AEC91AB2)
    # IID_ID3D11Texture2D = {6F15AAF2-D208-4E89-9AB4-489535D34F9C}.
    Emit-StoreBits32Frame -SlotPosition $textureGuidSlot -Value ([UInt32]0x6F15AAF2)
    Emit-StoreBits32Frame -SlotPosition ($textureGuidSlot + 4) -Value ([UInt32]0x4E89D208)
    Emit-StoreImm64Frame -SlotPosition ($textureGuidSlot + 8) -Value ([UInt64]::Parse('9C4FD3359548B49A', [System.Globalization.NumberStyles]::HexNumber))
    # Clear color: dark blue, stored as native IEEE-754 FLOAT bits.
    Emit-StoreBits32Frame -SlotPosition $colorSlot -Value ([UInt32]0x3D75C28F)
    Emit-StoreBits32Frame -SlotPosition ($colorSlot + 4) -Value ([UInt32]0x3DF5C28F)
    Emit-StoreBits32Frame -SlotPosition ($colorSlot + 8) -Value ([UInt32]0x3E75C28F)
    Emit-StoreBits32Frame -SlotPosition ($colorSlot + 12) -Value ([UInt32]0x3F800000)

    # Make a visible, top-level window using the built-in STATIC window class.
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xC9, 0x48, 0x83, 0xEC, 0x20)); Emit-CallIat -TargetRva ([UInt32]0x30C0); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20)) # GetModuleHandleA(NULL)
    Emit-StoreRaxFrame -SlotPosition ($scratch + 0xD0) # hInstance
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xC9)); Emit-DataAddress -DataItem (Register-DataConstant -Value 'STATIC'); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-LoadRaxFrame -SlotPosition $titleSlot; Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0))
    Emit-Bytes -Bytes ([byte[]]@(0x41, 0xB9, 0x00, 0x00, 0xCF, 0x10)) # WS_OVERLAPPEDWINDOW | WS_VISIBLE
    Emit-Win64CallIat -TargetRva ([UInt32]0x30F0) -StackArguments @(
        @{ Kind = 'Immediate'; Value = -2147483648 },
        @{ Kind = 'Immediate'; Value = -2147483648 },
        @{ Kind = 'Immediate'; Value = 960 },
        @{ Kind = 'Immediate'; Value = 540 },
        @{ Kind = 'Immediate'; Value = 0 },
        @{ Kind = 'Immediate'; Value = 0 },
        @{ Kind = 'FrameQword'; SlotPosition = ($scratch + 0xD0) },
        @{ Kind = 'Immediate'; Value = 0 }
    ); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failLabel
    Emit-StoreRaxFrame -SlotPosition $windowSlot
    Emit-LoadRaxFrame -SlotPosition $windowSlot; Emit-StoreRaxFrame -SlotPosition ($scratch + 48) # desc.OutputWindow
    Emit-LoadRcxFrame -SlotPosition $windowSlot; Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x05, 0x00, 0x00, 0x00, 0x48, 0x83, 0xEC, 0x20)); Emit-CallIat -TargetRva ([UInt32]0x30F8); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20)) # ShowWindow(SW_SHOW)
    Emit-LoadRcxFrame -SlotPosition $windowSlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x20)); Emit-CallIat -TargetRva ([UInt32]0x3100); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20)) # UpdateWindow

    # Explicit DXGI factory probe: import CreateDXGIFactory from DXGI.dll, then release it.
    Emit-LeaRaxFrame -SlotPosition $factoryGuidSlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-LeaRaxFrame -SlotPosition $factorySlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x20)); Emit-CallIat -TargetRva ([UInt32]0x3140); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20))
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x88 -Label $failLabel
    Emit-LoadRaxFrame -SlotPosition $factorySlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failLabel
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x20)); Emit-LoadRcxFrame -SlotPosition $factorySlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8B, 0x01, 0xFF, 0x50, 0x10)); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20)) # IUnknown::Release
    Emit-StoreZero64Frame -SlotPosition $factorySlot

    # Fill output slots with NULL before the device-and-swap-chain call.
    foreach ($slot in @($swapSlot, $deviceSlot, $contextSlot)) { Emit-StoreZero64Frame -SlotPosition $slot }
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xC9, 0xBA, 0x01, 0x00, 0x00, 0x00, 0x45, 0x33, 0xC0, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3130) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 0 },
        @{ Kind = 'Immediate'; Value = 0 },
        @{ Kind = 'Immediate'; Value = 7 },
        @{ Kind = 'FrameAddress'; SlotPosition = $scratch },
        @{ Kind = 'FrameAddress'; SlotPosition = $swapSlot },
        @{ Kind = 'FrameAddress'; SlotPosition = $deviceSlot },
        @{ Kind = 'FrameAddress'; SlotPosition = $featureSlot },
        @{ Kind = 'FrameAddress'; SlotPosition = $contextSlot }
    ); Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x89 -Label $deviceCreated
    Mark-CodeLabel -Label $hardwareFailed
    # Retry using the built-in WARP software rasterizer when hardware initialization fails.
    foreach ($slot in @($swapSlot, $deviceSlot, $contextSlot)) { Emit-StoreZero64Frame -SlotPosition $slot }
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xC9, 0xBA, 0x05, 0x00, 0x00, 0x00, 0x45, 0x33, 0xC0, 0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3130) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 0 },
        @{ Kind = 'Immediate'; Value = 0 },
        @{ Kind = 'Immediate'; Value = 7 },
        @{ Kind = 'FrameAddress'; SlotPosition = $scratch },
        @{ Kind = 'FrameAddress'; SlotPosition = $swapSlot },
        @{ Kind = 'FrameAddress'; SlotPosition = $deviceSlot },
        @{ Kind = 'FrameAddress'; SlotPosition = $featureSlot },
        @{ Kind = 'FrameAddress'; SlotPosition = $contextSlot }
    ); Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x88 -Label $failLabel
    Mark-CodeLabel -Label $deviceCreated
    foreach ($slot in @($swapSlot, $deviceSlot, $contextSlot)) { Emit-LoadRaxFrame -SlotPosition $slot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failLabel }

    # IDXGISwapChain::GetBuffer(0, IID_ID3D11Texture2D, &backBuffer).
    Emit-LoadRcxFrame -SlotPosition $swapSlot; Emit-Bytes -Bytes ([byte[]]@(0x33, 0xD2))
    Emit-LeaRaxFrame -SlotPosition $textureGuidSlot; Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0))
    Emit-LeaRaxFrame -SlotPosition $backBufferSlot; Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC1))
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x20)); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8B, 0x01, 0xFF, 0x50, 0x48)); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20)) # IDXGISwapChain::GetBuffer, vtable slot 9
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x88 -Label $failLabel
    Emit-LoadRaxFrame -SlotPosition $backBufferSlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failLabel

    # ID3D11Device::CreateRenderTargetView(backBuffer, NULL, &rtv).
    # ID3D11Device inherits IUnknown directly: CreateRenderTargetView is slot 9, byte offset 0x48.
    Emit-LoadRcxFrame -SlotPosition $deviceSlot; Emit-LoadRaxFrame -SlotPosition $backBufferSlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-Bytes -Bytes ([byte[]]@(0x45, 0x33, 0xC0))
    Emit-LeaRaxFrame -SlotPosition $rtvSlot; Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC1))
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x20)); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8B, 0x01, 0xFF, 0x50, 0x48)); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20))
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x88 -Label $failLabel
    Emit-LoadRaxFrame -SlotPosition $rtvSlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failLabel
    # Release the back-buffer reference; the render-target view owns its resource reference.
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x20)); Emit-LoadRcxFrame -SlotPosition $backBufferSlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8B, 0x01, 0xFF, 0x50, 0x10)); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20)); Emit-StoreZero64Frame -SlotPosition $backBufferSlot

    # ID3D11DeviceContext::OMSetRenderTargets(1, &rtv, NULL).
    Emit-LoadRcxFrame -SlotPosition $contextSlot; Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x01, 0x00, 0x00, 0x00))
    Emit-LeaRaxFrame -SlotPosition $rtvSlot; Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0, 0x45, 0x33, 0xC9))
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x20)); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8B, 0x01, 0xFF, 0x90)); Emit-I32 -Value 0x108; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20))
    # Frame timing uses QueryPerformanceFrequency/Counter around the actual clear-and-present loop.
    Emit-LeaRaxFrame -SlotPosition $qpcFreqSlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1)); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x20)); Emit-CallIat -TargetRva ([UInt32]0x3158); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20))
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failLabel
    Emit-LeaRaxFrame -SlotPosition $qpcStartSlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1)); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x20)); Emit-CallIat -TargetRva ([UInt32]0x3150); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20))
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failLabel
    Emit-StoreBits32Frame -SlotPosition $frameCountSlot -Value ([UInt32]0)
    Mark-CodeLabel -Label $loopStart
    Emit-LoadEaxFrame -SlotPosition $frameCountSlot; Emit-Bytes -Bytes ([byte[]]@(0x8B, 0x8D)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $framesSlot)
    Emit-Bytes -Bytes ([byte[]]@(0x39, 0xC8)); Emit-JumpConditional -ConditionCode 0x8D -Label $loopDone
    Emit-D3D11MessagePump -MessageSlot $messageSlot -WindowSlot $windowSlot -LoopDoneLabel $loopDone
    # ID3D11DeviceContext::ClearRenderTargetView(rtv, RGBA).
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x20)); Emit-LoadRcxFrame -SlotPosition $contextSlot; Emit-LoadRaxFrame -SlotPosition $rtvSlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2)) # RDX receives the full 64-bit render-target-view pointer
    Emit-Bytes -Bytes ([byte[]]@(0x4C, 0x8D, 0x85)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $colorSlot)
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8B, 0x01, 0xFF, 0x90)); Emit-I32 -Value 0x190; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20)) # ClearRenderTargetView is vtable slot 50
    # IDXGISwapChain::Present(1, 0). Require exact S_OK, not DXGI_STATUS_OCCLUDED.
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x20)); Emit-LoadRcxFrame -SlotPosition $swapSlot; Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x01, 0x00, 0x00, 0x00, 0x45, 0x33, 0xC0, 0x48, 0x8B, 0x01, 0xFF, 0x50, 0x40)); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20))
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x85 -Label $failLabel
    Emit-Bytes -Bytes ([byte[]]@(0xFF, 0x85)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $frameCountSlot)
    Emit-Jump -Label $loopStart
    Mark-CodeLabel -Label $loopDone
    Emit-LoadEaxFrame -SlotPosition $frameCountSlot; Emit-Bytes -Bytes ([byte[]]@(0x3B, 0x85)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $framesSlot); Emit-JumpConditional -ConditionCode 0x85 -Label $failLabel

    Emit-LeaRaxFrame -SlotPosition $qpcEndSlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1)); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x20)); Emit-CallIat -TargetRva ([UInt32]0x3150); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20))
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failLabel
    # elapsed_ms = (1000 * (QPC_end - QPC_start)) / QPC_frequency.
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8B, 0x85)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $qpcEndSlot)
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x2B, 0x85)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $qpcStartSlot)
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x69, 0xC0, 0xE8, 0x03, 0x00, 0x00, 0x48, 0x99, 0x48, 0x8B, 0x8D))
    Emit-I32 -Value (Get-FrameDisp -SlotPosition $qpcFreqSlot)
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC9)); Emit-JumpConditional -ConditionCode 0x84 -Label $failLabel
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0xF7, 0xF9, 0x89, 0x85)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $elapsedSlot)

    # Release COM objects and destroy the window only after the rendering loop has completed.
    foreach ($comSlot in @($rtvSlot, $contextSlot, $swapSlot, $deviceSlot)) { Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x20)); Emit-LoadRcxFrame -SlotPosition $comSlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8B, 0x01, 0xFF, 0x50, 0x10)); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20)) }
    Emit-LoadRcxFrame -SlotPosition $windowSlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x20)); Emit-CallIat -TargetRva ([UInt32]0x3120); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20))

    # Emit a machine-generated runtime report only after all checkpoints succeeded.
    $format = Register-DataConstant -Value ("D3D11: window=PASS device=PASS swapchain=PASS rtv=PASS frames=%u elapsed_ms=%u`r`n")
    Emit-LeaRaxFrame -SlotPosition $formatBufferSlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-DataAddress -DataItem $format; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-LoadEaxFrame -SlotPosition $frameCountSlot; Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC0))
    Emit-LoadEaxFrame -SlotPosition $elapsedSlot; Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC1))
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x20)); Emit-CallIat -TargetRva ([UInt32]0x3090); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20)); Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x8E -Label $failLabel; Emit-StoreEaxFrame -SlotPosition $formatLengthSlot
    Emit-Bytes -Bytes ([byte[]]@(0xB9, 0xF5, 0xFF, 0xFF, 0xFF, 0x48, 0x83, 0xEC, 0x20)); Emit-CallIat -TargetRva ([UInt32]0x3070); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20))
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failLabel
    Emit-StoreRaxFrame -SlotPosition $stdoutSlot
    Emit-LoadRaxFrame -SlotPosition $stdoutSlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1))
    Emit-LeaRaxFrame -SlotPosition $formatBufferSlot; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2))
    Emit-LoadEaxFrame -SlotPosition $formatLengthSlot; Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC0))
    Emit-LeaRaxFrame -SlotPosition $bytesWrittenSlot; Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC1))
    Emit-Win64CallIat -TargetRva ([UInt32]0x3078) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 0 }
    )
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failLabel
    Emit-LoadEaxFrame -SlotPosition $bytesWrittenSlot; Emit-Bytes -Bytes ([byte[]]@(0x3B, 0x85)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $formatLengthSlot); Emit-JumpConditional -ConditionCode 0x85 -Label $failLabel
    Emit-LoadEaxFrame -SlotPosition $frameCountSlot
}
function Emit-ThreadSyncCore {
    param([int] $BaseDepth)
    $threadSlot = Get-TempSlotPosition -Depth $BaseDepth; $mutexSlot = Get-TempSlotPosition -Depth ($BaseDepth + 1)
    $threadFail = New-UniqueLabel -Prefix 'thread_sync_thread_fail'; $mutexFail = New-UniqueLabel -Prefix 'thread_sync_mutex_fail'; $mutexWaitFail = New-UniqueLabel -Prefix 'thread_sync_mutex_wait_fail'; $releaseFail = New-UniqueLabel -Prefix 'thread_sync_release_fail'; $done = New-UniqueLabel -Prefix 'thread_sync_done'
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xC9, 0x33, 0xD2)); Emit-LeaR8CodeLabel -Label '__sharnou_worker'; Emit-Bytes -Bytes ([byte[]]@(0x45, 0x33, 0xC9))
    Emit-Win64CallIat -TargetRva ([UInt32]0x30C8) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 0 },
        @{ Kind = 'FrameAddress'; SlotPosition = $script:ActiveContext.ScratchPosition }
    ) # CreateThread; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $threadFail
    Emit-StoreRaxFrame -SlotPosition $threadSlot; Emit-LoadRcxFrame -SlotPosition $threadSlot; Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x88, 0x13, 0x00, 0x00)); Emit-CallIat -TargetRva ([UInt32]0x30D0) # WaitForSingleObject
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x85 -Label $threadFail
    Emit-LoadRcxFrame -SlotPosition $threadSlot; Emit-CallIat -TargetRva ([UInt32]0x30B8) # CloseHandle
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xC9, 0x33, 0xD2, 0x45, 0x33, 0xC0)); Emit-CallIat -TargetRva ([UInt32]0x30D8) # CreateMutexA
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $mutexFail
    Emit-StoreRaxFrame -SlotPosition $mutexSlot; Emit-LoadRcxFrame -SlotPosition $mutexSlot; Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x88, 0x13, 0x00, 0x00)); Emit-CallIat -TargetRva ([UInt32]0x30D0)
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x85 -Label $mutexWaitFail
    Emit-LoadRcxFrame -SlotPosition $mutexSlot; Emit-CallIat -TargetRva ([UInt32]0x30E0); Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $releaseFail
    Emit-LoadRcxFrame -SlotPosition $mutexSlot; Emit-CallIat -TargetRva ([UInt32]0x30B8); Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x01, 0x00, 0x00, 0x00)); Emit-Jump -Label $done
    Mark-CodeLabel -Label $threadFail; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0)); $cleanupThread = New-UniqueLabel -Prefix 'thread_sync_close_thread'; Emit-JumpConditional -ConditionCode 0x84 -Label $cleanupThread; Emit-LoadRcxFrame -SlotPosition $threadSlot; Emit-CallIat -TargetRva ([UInt32]0x30B8); Mark-CodeLabel -Label $cleanupThread; Emit-Bytes -Bytes ([byte[]]@(0x31, 0xC0)); Emit-Jump -Label $done
    Mark-CodeLabel -Label $mutexWaitFail; Emit-LoadRcxFrame -SlotPosition $mutexSlot; Emit-CallIat -TargetRva ([UInt32]0x30B8); Emit-Bytes -Bytes ([byte[]]@(0x31, 0xC0)); Emit-Jump -Label $done
    Mark-CodeLabel -Label $releaseFail; Emit-LoadRcxFrame -SlotPosition $mutexSlot; Emit-CallIat -TargetRva ([UInt32]0x30B8); Emit-Bytes -Bytes ([byte[]]@(0x31, 0xC0)); Emit-Jump -Label $done
    Mark-CodeLabel -Label $mutexFail; Emit-Bytes -Bytes ([byte[]]@(0x31, 0xC0))
    Mark-CodeLabel -Label $done
}
function Emit-IntegerExpression {
    param([object] $Node)
    switch ($Node.Kind) {
        'Integer' { Emit-Bytes -Bytes ([byte[]]@(0xB8)); Emit-I32 -Value ([long]$Node.Value); return }
        'Variable' {
            if ($Node.Type -ne 'Integer') { Throw-SourceError -Line $Node.Line -Column $Node.Column -Message 'Internal type error: integer expression expected.' }
            Emit-LoadEaxFrame -SlotPosition (0x80 + ([int]$Node.Slot * 16)); return
        }
        'Unary' { Emit-IntegerExpression -Node $Node.Operand; if ($Node.Operator -eq '-') { Emit-Bytes -Bytes ([byte[]]@(0xF7, 0xD8)); Emit-JumpConditional -ConditionCode 0x80 -Label '__runtime_fail' }; return }
        'Comparison' {
            Emit-IntegerExpression -Node $Node.Left
            $tempSlot = Get-TempSlotPosition -Depth $script:TempDepth
            Emit-StoreEaxFrame -SlotPosition $tempSlot
            $script:TempDepth++
            Emit-IntegerExpression -Node $Node.Right
            $script:TempDepth--
            Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC1)) # mov ecx,eax
            Emit-LoadEaxFrame -SlotPosition $tempSlot
            Emit-Bytes -Bytes ([byte[]]@(0x39, 0xC8)) # cmp eax,ecx
            switch ($Node.Operator) {
                '<'  { Emit-Bytes -Bytes ([byte[]]@(0x0F, 0x9C, 0xC0)) } # setl al
                '>'  { Emit-Bytes -Bytes ([byte[]]@(0x0F, 0x9F, 0xC0)) } # setg al
                '<=' { Emit-Bytes -Bytes ([byte[]]@(0x0F, 0x9E, 0xC0)) } # setle al
                '>=' { Emit-Bytes -Bytes ([byte[]]@(0x0F, 0x9D, 0xC0)) } # setge al
                '==' { Emit-Bytes -Bytes ([byte[]]@(0x0F, 0x94, 0xC0)) } # sete al
                '!=' { Emit-Bytes -Bytes ([byte[]]@(0x0F, 0x95, 0xC0)) } # setne al
                default { Throw-SourceError -Line $Node.Line -Column $Node.Column -Message ("Unsupported comparison operator '{0}'." -f $Node.Operator) }
            }
            Emit-Bytes -Bytes ([byte[]]@(0x0F, 0xB6, 0xC0)) # movzx eax,al (normalize to 0 or 1)
            return
        }
        'Binary' {
            Emit-IntegerExpression -Node $Node.Left
            $tempSlot = Get-TempSlotPosition -Depth $script:TempDepth; Emit-StoreEaxFrame -SlotPosition $tempSlot; $script:TempDepth++
            Emit-IntegerExpression -Node $Node.Right; $script:TempDepth--
            Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC1)); Emit-LoadEaxFrame -SlotPosition $tempSlot
            switch ($Node.Operator) {
                '+' { Emit-Bytes -Bytes ([byte[]]@(0x01, 0xC8)); Emit-JumpConditional -ConditionCode 0x80 -Label '__runtime_fail' }
                '-' { Emit-Bytes -Bytes ([byte[]]@(0x29, 0xC8)); Emit-JumpConditional -ConditionCode 0x80 -Label '__runtime_fail' }
                '*' { Emit-Bytes -Bytes ([byte[]]@(0x0F, 0xAF, 0xC1)); Emit-JumpConditional -ConditionCode 0x80 -Label '__runtime_fail' }
                '/' {
                    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC9)); Emit-JumpConditional -ConditionCode 0x84 -Label '__runtime_fail'
                    Emit-Bytes -Bytes ([byte[]]@(0x3D, 0x00, 0x00, 0x00, 0x80))
                    $continueLabel = '__divide_continue_' + [string]$script:UniqueLabel; $script:UniqueLabel++
                    Emit-JumpConditional -ConditionCode 0x85 -Label $continueLabel
                    Emit-Bytes -Bytes ([byte[]]@(0x83, 0xF9, 0xFF)); Emit-JumpConditional -ConditionCode 0x84 -Label '__runtime_fail'
                    Mark-CodeLabel -Label $continueLabel; Emit-Bytes -Bytes ([byte[]]@(0x99, 0xF7, 0xF9))
                }
                default { Throw-SourceError -Line $Node.Line -Column $Node.Column -Message ("Unsupported arithmetic operator '{0}'." -f $Node.Operator) }
            }
            return
        }
        'Call' {
            if (-not [string]::IsNullOrEmpty([string]$Node.Builtin)) { Emit-BuiltinCall -Node $Node; return }
            $baseDepth = [int]$script:TempDepth
            $argumentCount = [int]$Node.Arguments.Count
            if ($argumentCount -gt 16) {
                Throw-SourceError -Line $Node.Line -Column $Node.Column -Message "Function calls support at most 16 integer arguments under the current Windows x64 ABI subset."
            }
            # Evaluate every argument before touching ABI registers or outgoing stack slots.
            for ($i = 0; $i -lt $argumentCount; $i++) {
                Emit-IntegerExpression -Node $Node.Arguments[$i]
                Emit-StoreEaxFrame -SlotPosition (Get-TempSlotPosition -Depth $script:TempDepth)
                $script:TempDepth++
            }
            # Every Windows x64 call reserves 32 bytes of shadow space. Additional
            # arguments occupy 8-byte slots beginning at [RSP+0x20]. The total is
            # rounded to 16 bytes so RSP remains call-site aligned.
            $stackArgumentCount = [Math]::Max(0, $argumentCount - 4)
            $callFrameSize = Align-Up -Value (0x20 + ($stackArgumentCount * 8)) -Alignment 0x10
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0x81, 0xEC))
            Emit-I32 -Value $callFrameSize
            for ($i = 0; $i -lt [Math]::Min(4, $argumentCount); $i++) {
                Emit-LoadEaxFrame -SlotPosition (Get-TempSlotPosition -Depth ($baseDepth + $i))
                switch ($i) {
                    0 { Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC1)) }
                    1 { Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC2)) }
                    2 { Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC0)) }
                    3 { Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC1)) }
                }
            }
            for ($i = 4; $i -lt $argumentCount; $i++) {
                Emit-LoadEaxFrame -SlotPosition (Get-TempSlotPosition -Depth ($baseDepth + $i))
                Emit-StackArgumentRax -Offset (0x20 + (($i - 4) * 8))
            }
            Emit-CallFunction -Name $Node.Name
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0x81, 0xC4))
            Emit-I32 -Value $callFrameSize
            $script:TempDepth -= $argumentCount
            return
        }
        default { Throw-SourceError -Line $Node.Line -Column $Node.Column -Message 'Internal code-generation error: unsupported integer expression node.' }
    }
}
function Emit-StringExpression {
    param([object] $Node)
    switch ($Node.Kind) {
        'String' { $item = Register-DataConstant -Value ([string]$Node.Value); Emit-DataAddress -DataItem $item; Emit-Bytes -Bytes ([byte[]]@(0xBA)); Emit-I32 -Value ([System.Text.Encoding]::ASCII.GetByteCount([string]$Node.Value)); return }
        'Variable' { if ($Node.Type -ne 'String') { Throw-SourceError -Line $Node.Line -Column $Node.Column -Message 'Internal type error: string expression expected.' }; $slotPosition = 0x80 + ([int]$Node.Slot * 16); Emit-LoadRaxFrame -SlotPosition $slotPosition; Emit-LoadEdxFrame -SlotPosition ($slotPosition + 8); return }
        default { Throw-SourceError -Line $Node.Line -Column $Node.Column -Message 'Internal code-generation error: unsupported string expression node.' }
    }
}
function Emit-WriteCall {
    Emit-LoadRcxFrame -SlotPosition 0x78; Emit-LeaR9Frame -SlotPosition 0x70
    Emit-Win64CallIat -TargetRva ([UInt32]0x3078) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 0 }
    )
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label '__runtime_fail'
}
function Emit-PrintString {
    param([object] $Node)
    Emit-StringExpression -Node $Node; Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xD0)); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2)); Emit-WriteCall
    $newlineItem = Register-DataConstant -Value "`r`n"; Emit-DataAddress -DataItem $newlineItem; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2)); Emit-Bytes -Bytes ([byte[]]@(0x41, 0xB8, 0x02, 0x00, 0x00, 0x00)); Emit-WriteCall
}
function Emit-PrintInteger {
    param([object] $Node)
    Emit-IntegerExpression -Node $Node; $formatItem = Register-DataConstant -Value '%d'; Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC0)); Emit-LeaRcxFrame -SlotPosition 0x30; Emit-DataAddress -DataItem $formatItem; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2)); Emit-CallIat -TargetRva ([UInt32]0x3090)
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x8E -Label '__runtime_fail'; Emit-StoreEaxFrame -SlotPosition 0x74
    Emit-LoadEaxFrame -SlotPosition 0x74; Emit-LeaRdxFrame -SlotPosition 0x30; Emit-Bytes -Bytes ([byte[]]@(0x48, 0x01, 0xC2)); Emit-Bytes -Bytes ([byte[]]@(0xC6, 0x02, 0x0D)); Emit-Bytes -Bytes ([byte[]]@(0xC6, 0x42, 0x01, 0x0A))
    Emit-LoadRcxFrame -SlotPosition 0x78; Emit-LeaRdxFrame -SlotPosition 0x30; Emit-LoadEaxFrame -SlotPosition 0x74; Emit-Bytes -Bytes ([byte[]]@(0x83, 0xC0, 0x02)); Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC0)); Emit-LeaR9Frame -SlotPosition 0x70; Emit-Win64CallIat -TargetRva ([UInt32]0x3078) -StackArguments @(
        @{ Kind = 'Immediate'; Value = 0 }
    ); Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label '__runtime_fail'
}
function Emit-Statement {
    param([object] $Statement)
    switch ($Statement.Kind) {
        'Let' {
            if ($Statement.Type -eq 'Integer') { Emit-IntegerExpression -Node $Statement.Expression; Emit-StoreEaxFrame -SlotPosition (0x80 + ([int]$Statement.Slot * 16)) }
            else { Emit-StringExpression -Node $Statement.Expression; $slot = 0x80 + ([int]$Statement.Slot * 16); Emit-StoreRaxFrame -SlotPosition $slot; Emit-StoreEdxFrame -SlotPosition ($slot + 8) }
            return
        }
        'Assign' {
            if ($Statement.Type -eq 'Integer') { Emit-IntegerExpression -Node $Statement.Expression; Emit-StoreEaxFrame -SlotPosition (0x80 + ([int]$Statement.Slot * 16)) }
            else { Emit-StringExpression -Node $Statement.Expression; $slot = 0x80 + ([int]$Statement.Slot * 16); Emit-StoreRaxFrame -SlotPosition $slot; Emit-StoreEdxFrame -SlotPosition ($slot + 8) }
            return
        }
        'Print' { if ($Statement.Expression.Type -eq 'Integer') { Emit-PrintInteger -Node $Statement.Expression } else { Emit-PrintString -Node $Statement.Expression }; return }
        'Block' { foreach ($child in $Statement.Statements) { Emit-Statement -Statement $child }; return }
        'If' {
            $elseLabel = New-UniqueLabel -Prefix 'if_else'
            $doneLabel = New-UniqueLabel -Prefix 'if_done'
            Emit-IntegerExpression -Node $Statement.Expression
            Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)) # test eax,eax
            if ($Statement.ElseStatements.Count -gt 0) {
                Emit-JumpConditional -ConditionCode 0x84 -Label $elseLabel # jz else
                foreach ($child in $Statement.Statements) { Emit-Statement -Statement $child }
                Emit-Jump -Label $doneLabel
                Mark-CodeLabel -Label $elseLabel
                foreach ($child in $Statement.ElseStatements) { Emit-Statement -Statement $child }
                Mark-CodeLabel -Label $doneLabel
            } else {
                Emit-JumpConditional -ConditionCode 0x84 -Label $doneLabel
                foreach ($child in $Statement.Statements) { Emit-Statement -Statement $child }
                Mark-CodeLabel -Label $doneLabel
            }
            return
        }
        'While' {
            $loopStart = New-UniqueLabel -Prefix 'while_start'
            $loopDone = New-UniqueLabel -Prefix 'while_done'
            Mark-CodeLabel -Label $loopStart
            Emit-IntegerExpression -Node $Statement.Expression
            Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)) # test eax,eax
            Emit-JumpConditional -ConditionCode 0x84 -Label $loopDone # jz done
            foreach ($child in $Statement.Statements) { Emit-Statement -Statement $child }
            Emit-Jump -Label $loopStart
            Mark-CodeLabel -Label $loopDone
            return
        }
        default { Throw-SourceError -Line $Statement.Line -Column $Statement.Column -Message ("Unsupported statement kind '{0}'." -f $Statement.Kind) }
    }
}
function Set-FrameSize {
    param([object] $Context, [int] $NodeCount)
    $Context.TempSlots = [Math]::Max(8, ($NodeCount + 8))
    $Context.ScratchPosition = [int](0x80 + ([int]$Context.SlotCount * 16) + ([int]$Context.TempSlots * 16))
    $required = [int]($Context.ScratchPosition + 0x1010)
    $Context.FrameSize = Align-Up -Value $required -Alignment 0x10
    if ($Context.FrameSize -gt 0x100000) { throw "Function or main frame is too large: $($Context.FrameSize) bytes." }
}
function Emit-StackProbe {
    param([int] $FrameSize)
    if ($FrameSize -le 0 -or ($FrameSize % 16) -ne 0) { throw "Invalid stack-probe frame size: $FrameSize" }
    # Windows x64 uses a special stack-probe helper contract: RAX carries the
    # allocation size; the helper preserves RAX and argument registers, and
    # may clobber only R10, R11, and flags. RSP remains unchanged until it
    # returns, after which the ordinary fixed SUB RSP is unwind-described.
    Emit-Bytes -Bytes ([byte[]]@(0xB8)); Emit-I32 -Value $FrameSize # mov eax,FrameSize
    Emit-Bytes -Bytes ([byte[]]@(0xE8))
    $dispOffset = $script:Code.Count
    Emit-I32 -Value 0
    $script:CodeFixups.Add([pscustomobject]@{ Kind = 'Code'; DispOffset = $dispOffset; Target = '__sharnou_chkstk' })
}
function Emit-Prologue {
    param([object] $Context, [object] $Function = $null)
    $script:ActiveContext = $Context; $script:TempDepth = 0
    $Context | Add-Member -NotePropertyName PrologueSize -NotePropertyValue 0 -Force
    $Context | Add-Member -NotePropertyName StackAllocCodeOffset -NotePropertyValue 0 -Force
    $prologueStart = $script:Code.Count
    Emit-Bytes -Bytes ([byte[]]@(0x55, 0x48, 0x89, 0xE5)) # push rbp; mov rbp,rsp
    Emit-StackProbe -FrameSize ([int]$Context.FrameSize)
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x81, 0xEC)); Emit-I32 -Value $Context.FrameSize # sub rsp,imm32
    $Context.PrologueSize = [int]($script:Code.Count - $prologueStart)
    $Context.StackAllocCodeOffset = $Context.PrologueSize
    if ($Context.PrologueSize -gt 255) { throw "Generated unwind prologue exceeds 255 bytes: $($Context.PrologueSize)." }
    if ($null -ne $Function) {
        if ($Function.Parameters.Count -gt 16) {
            throw "Function '$($Function.Name)' exceeds the supported Windows x64 integer-argument limit of 16."
        }
        for ($i = 0; $i -lt [Math]::Min(4, $Function.Parameters.Count); $i++) {
            $slotPosition = 0x80 + ($i * 16)
            switch ($i) {
                0 { Emit-StoreEcxFrame -SlotPosition $slotPosition }
                1 { Emit-StoreEdxFrame -SlotPosition $slotPosition }
                2 { Emit-StoreR8dFrame -SlotPosition $slotPosition }
                3 { Emit-StoreR9dFrame -SlotPosition $slotPosition }
            }
        }
        # Windows x64 arguments 5..16 are passed in 8-byte stack slots.
        # After PUSH RBP, the first stack argument is at [RBP+0x30].
        for ($i = 4; $i -lt $Function.Parameters.Count; $i++) {
            $slotPosition = 0x80 + ($i * 16)
            $incomingOffset = 0x30 + (($i - 4) * 8)
            Emit-Bytes -Bytes ([byte[]]@(0x8B, 0x85)) # mov eax,dword ptr [rbp+disp32]
            Emit-I32 -Value $incomingOffset
            Emit-StoreEaxFrame -SlotPosition $slotPosition
        }
    }
    Emit-Bytes -Bytes ([byte[]]@(0xB9, 0xF5, 0xFF, 0xFF, 0xFF, 0x48, 0x83, 0xEC, 0x20)); Emit-CallIat -TargetRva ([UInt32]0x3070); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20))
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label '__runtime_fail'
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xF8, 0xFF)); Emit-JumpConditional -ConditionCode 0x84 -Label '__runtime_fail'
    Emit-StoreRaxFrame -SlotPosition 0x78
}
function New-UnwindInfoBytes {
    param([object] $Context)
    $frameSize = [int]$Context.FrameSize
    if ($frameSize -lt 0x1000 -or ($frameSize % 16) -ne 0) { throw "Unwind metadata received an invalid frame size: $frameSize." }
    $allocInfo = if ($frameSize -le 0x7FFF8) { 0 } else { 1 }
    $countOfCodes = if ($allocInfo -eq 0) { 4 } else { 5 }
    $bytes = [System.Collections.Generic.List[byte]]::new()
    $bytes.Add([byte]1) # version 1, flags 0
    $bytes.Add([byte]$Context.PrologueSize)
    $bytes.Add([byte]$countOfCodes)
    $bytes.Add([byte]0x05) # frame register RBP, frame offset 0
    $bytes.Add([byte]$Context.StackAllocCodeOffset)
    $bytes.Add([byte](($allocInfo -shl 4) -bor 0x01)) # UWOP_ALLOC_LARGE
    if ($allocInfo -eq 0) {
        $scaledSize = [UInt16]($frameSize / 8)
        $bytes.AddRange([BitConverter]::GetBytes($scaledSize))
    } else {
        $bytes.AddRange([BitConverter]::GetBytes([UInt32]$frameSize))
    }
    $bytes.Add([byte]4); $bytes.Add([byte]0x03) # UWOP_SET_FPREG
    $bytes.Add([byte]1); $bytes.Add([byte]0x50) # UWOP_PUSH_NONVOL RBP
    if (($countOfCodes % 2) -ne 0) { $bytes.Add([byte]0); $bytes.Add([byte]0) }
    return ,$bytes.ToArray()
}
function Emit-Epilogue { Emit-Bytes -Bytes ([byte[]]@(0x48, 0x8D, 0x65, 0x00, 0x5D, 0xC3)) } # lea rsp,[rbp+0]; pop rbp; ret (legal x64 epilogue)
function Test-ImageBasic {
    param([byte[]] $Image)
    if ($Image.Length -lt 0x400 -or $Image[0] -ne 0x4D -or $Image[1] -ne 0x5A) { throw 'Internal linker validation: invalid DOS header.' }
    $pe = [BitConverter]::ToInt32($Image, 0x3C)
    if ($pe -lt 0 -or ($pe + 24) -gt $Image.Length -or $Image[$pe] -ne 0x50 -or $Image[$pe + 1] -ne 0x45) { throw 'Internal linker validation: invalid PE header/signature.' }
    if ([BitConverter]::ToUInt16($Image, $pe + 4) -ne 0x8664) { throw 'Internal linker validation: target machine is not AMD64.' }
    if ([BitConverter]::ToUInt16($Image, $pe + 24) -ne 0x020B) { throw 'Internal linker validation: optional header is not PE32+.' }
    $count = [BitConverter]::ToUInt16($Image, $pe + 6); if ($count -ne 6) { throw "Internal linker validation: expected six sections, found $count." }
    $table = $pe + 24 + [BitConverter]::ToUInt16($Image, $pe + 20)
    if (($table + ($count * 40)) -gt [BitConverter]::ToUInt32($Image, $pe + 24 + 60)) { throw 'Internal linker validation: section headers exceed SizeOfHeaders.' }
    $optional = $pe + 24
    $optionalSize = [BitConverter]::ToUInt16($Image, $pe + 20)
    $sectionTable = $optional + $optionalSize
    $rdataSection = $null
    $relocSection = $null
    for ($sectionIndex = 0; $sectionIndex -lt $count; $sectionIndex++) {
        $header = $sectionTable + ($sectionIndex * 40)
        $sectionName = [System.Text.Encoding]::ASCII.GetString($Image, $header, 8).Trim([char[]]@(0))
        $section = [pscustomobject]@{
            Name = $sectionName
            VirtualSize = [UInt32][BitConverter]::ToUInt32($Image, $header + 8)
            Rva = [UInt32][BitConverter]::ToUInt32($Image, $header + 12)
            RawSize = [UInt32][BitConverter]::ToUInt32($Image, $header + 16)
            RawPointer = [UInt32][BitConverter]::ToUInt32($Image, $header + 20)
        }
        if ($sectionName -eq '.rdata') { $rdataSection = $section }
        if ($sectionName -eq '.reloc') { $relocSection = $section }
    }
    $relocRva = [UInt32][BitConverter]::ToUInt32($Image, $optional + 152)
    $relocSize = [UInt32][BitConverter]::ToUInt32($Image, $optional + 156)
    if ($null -eq $rdataSection -or $null -eq $relocSection -or $relocRva -ne $relocSection.Rva -or $relocSize -lt 12 -or $relocSize -gt $relocSection.VirtualSize) {
        throw 'Internal linker validation: base relocation directory or containing section is missing/malformed.'
    }
    $relocFileOffset = [UInt64]$relocSection.RawPointer
    if (($relocFileOffset + $relocSize) -gt [UInt64]$Image.Length -or $relocSize -gt $relocSection.RawSize) {
        throw 'Internal linker validation: base relocation directory is not backed by file data.'
    }
    $relocBytes = [byte[]]::new([int]$relocSize)
    [System.Buffer]::BlockCopy($Image, [int]$relocFileOffset, $relocBytes, 0, [int]$relocSize)
    $allowedRanges = @([pscustomobject]@{ StartRva = $rdataSection.Rva; Size = $rdataSection.VirtualSize })
    $relocationResult = Test-SharnouBaseRelocationDirectory -Bytes $relocBytes -ImageSize ([UInt32][BitConverter]::ToUInt32($Image, $optional + 56)) -AllowedRanges $allowedRanges -ExpectedTargetRvas $script:ExpectedRelocationTargetRvas
    if (-not ($relocationResult.TargetRvas -contains [UInt32]$rdataSection.Rva)) {
        throw 'Internal linker validation: .rdata absolute entry-point anchor has no DIR64 relocation.'
    }
    $exceptionRva = [BitConverter]::ToUInt32($Image, $optional + 136)
    $exceptionSize = [BitConverter]::ToUInt32($Image, $optional + 140)
    if ($exceptionRva -eq 0 -or $exceptionSize -lt 12 -or ($exceptionSize % 12) -ne 0) {
        throw 'Internal linker validation: x64 exception/unwind directory is missing or malformed.'
    }
}

if (-not [Environment]::Is64BitOperatingSystem) { throw 'The Sharnou compiler emits x64 PE32+ executables and requires 64-bit Windows.' }
$sourceItem = Get-Item -LiteralPath $Source -ErrorAction Stop
if ($sourceItem.PSIsContainer) { throw "Source path is not a file: $Source" }
$sourceFullPath = $sourceItem.FullName; $outputFullPath = [System.IO.Path]::GetFullPath($Output)
if ([string]::Equals($sourceFullPath, $outputFullPath, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'The output path must not overwrite the source file.' }
if (Test-Path -LiteralPath $outputFullPath) { Remove-Item -LiteralPath $outputFullPath -Force }

$script:Functions = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
$script:Builtins = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
$builtinDefinitions = @(
    [pscustomobject]@{ Name = 'sh_abi_nonvolatile_probe'; Builtin = 'AbiNonvolatileProbe'; ParameterTypes = @(); ReturnType = 'Integer' },
    [pscustomobject]@{ Name = 'sh_string_length'; Builtin = 'StringLength'; ParameterTypes = @('String'); ReturnType = 'Integer' },
    [pscustomobject]@{ Name = 'sh_string_equal'; Builtin = 'StringEqual'; ParameterTypes = @('String', 'String'); ReturnType = 'Integer' },
    [pscustomobject]@{ Name = 'sh_log'; Builtin = 'Log'; ParameterTypes = @('String'); ReturnType = 'Integer' },
    [pscustomobject]@{ Name = 'sh_memory_fill'; Builtin = 'MemoryFill'; ParameterTypes = @('Integer', 'Integer'); ReturnType = 'Integer' },
    [pscustomobject]@{ Name = 'sh_memory_byte_at'; Builtin = 'MemoryByteAt'; ParameterTypes = @('Integer'); ReturnType = 'Integer' },
    [pscustomobject]@{ Name = 'sh_file_exists'; Builtin = 'FileExists'; ParameterTypes = @('String'); ReturnType = 'Integer' },
    [pscustomobject]@{ Name = 'sh_file_size'; Builtin = 'FileSize'; ParameterTypes = @('String'); ReturnType = 'Integer' },
    [pscustomobject]@{ Name = 'sh_asset_read_count'; Builtin = 'AssetReadCount'; ParameterTypes = @('String', 'Integer'); ReturnType = 'Integer' },
    [pscustomobject]@{ Name = 'sh_asset_read_byte'; Builtin = 'AssetReadByte'; ParameterTypes = @('String', 'Integer'); ReturnType = 'Integer' },
    [pscustomobject]@{ Name = 'sh_window_probe'; Builtin = 'WindowProbe'; ParameterTypes = @('String'); ReturnType = 'Integer' },
    [pscustomobject]@{ Name = 'sh_window_pump_once'; Builtin = 'WindowPump'; ParameterTypes = @(); ReturnType = 'Integer' },
    [pscustomobject]@{ Name = 'sh_thread_sync_probe'; Builtin = 'ThreadSyncProbe'; ParameterTypes = @(); ReturnType = 'Integer' },
    [pscustomobject]@{ Name = 'sh_d3d11_render_demo'; Builtin = 'D3D11RenderDemo'; ParameterTypes = @('String', 'Integer'); ReturnType = 'Integer' }
)
if ($EnableDevAgentTools) {
    $builtinDefinitions += [pscustomobject]@{ Name = 'sh_dev_run_tool'; Builtin = 'DevRunTool'; ParameterTypes = @('Integer', 'Integer'); ReturnType = 'Integer' }
}
if ($EnableWin64CallbackTests) {
    $builtinDefinitions += [pscustomobject]@{ Name = 'sh_win64_callback_abi_probe'; Builtin = 'Win64CallbackProbe'; ParameterTypes = @(); ReturnType = 'Integer' }
}
foreach ($definition in $builtinDefinitions) { $script:Builtins.Add($definition.Name, $definition) }
$script:Modules = [System.Collections.Generic.List[object]]::new()
$script:ModuleMap = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
$script:FunctionIndex = 0
$script:SourceDisplay = $sourceFullPath
$rootModule = Load-Module -Path $sourceFullPath -IsRoot $true
foreach ($module in $script:Modules) { $script:SourceDisplay = $module.Path; Collect-FunctionHeaders -Module $module }

$script:MainStatements = [System.Collections.Generic.List[object]]::new()
$script:MainContext = [pscustomobject]@{ Name = '__entry'; SlotCount = 0; TempSlots = 0; ScratchPosition = 0; FrameSize = 0; Statements = $script:MainStatements }
$script:Scopes = [System.Collections.Generic.List[object]]::new(); Push-Scope
$script:ActiveContext = $script:MainContext; $script:CurrentFunction = $null; $script:BlockDepth = 0
foreach ($module in $script:Modules) { Parse-Module -Module $module }

Set-FrameSize -Context $script:MainContext -NodeCount (Get-StatementsNodeCount -Statements $script:MainStatements.ToArray())
foreach ($functionObject in $script:Functions.Values) {
    if ($null -eq $functionObject.Context) { throw "Function '$($functionObject.Name)' was declared but not parsed." }
    Set-FrameSize -Context $functionObject.Context -NodeCount (Get-StatementsNodeCount -Statements $functionObject.BodyStatements -ReturnExpression $functionObject.ReturnExpression)
}

$script:Code = [System.Collections.Generic.List[byte]]::new()
$script:CodeFixups = [System.Collections.Generic.List[object]]::new()
$script:CodeLabels = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::Ordinal)
$script:DataItems = [System.Collections.Generic.List[object]]::new()
$script:DataMap = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
$script:DataPointerFixups = [System.Collections.Generic.List[object]]::new()
$script:DataLength = 8 # reserved absolute entry-point anchor, patched by the base-relocation directory
$script:UniqueLabel = 0

# Entry point: main code owns a stack frame; every function gets its own frame.
Mark-CodeLabel -Label '__entry'
Emit-Prologue -Context $script:MainContext
foreach ($statement in $script:MainStatements) { Emit-Statement -Statement $statement }
Emit-Bytes -Bytes ([byte[]]@(0x31, 0xC9, 0x48, 0x83, 0xEC, 0x20)); Emit-CallIat -TargetRva ([UInt32]0x3080); Emit-Bytes -Bytes ([byte[]]@(0xCC))
Mark-CodeLabel -Label '__runtime_fail'
Emit-Bytes -Bytes ([byte[]]@(0xB9, 0x01, 0x00, 0x00, 0x00, 0x48, 0x83, 0xEC, 0x20)); Emit-CallIat -TargetRva ([UInt32]0x3080); Emit-Bytes -Bytes ([byte[]]@(0xCC))

foreach ($functionObject in ($script:Functions.Values | Sort-Object Index)) {
    Mark-CodeLabel -Label $functionObject.Label
    Emit-Prologue -Context $functionObject.Context -Function $functionObject
    foreach ($statement in $functionObject.BodyStatements) { Emit-Statement -Statement $statement }
    $script:ActiveContext = $functionObject.Context; $script:TempDepth = 0
    Emit-IntegerExpression -Node $functionObject.ReturnExpression
    Emit-Epilogue
}
# Windows x64 stack-probe helper. This is a leaf routine using only R10/R11
# and flags; RAX (the requested allocation size), argument registers, RSP, and
# all nonvolatile registers are preserved. Leaf routines require no .pdata row.
$stackProbeOffset = [int]$script:Code.Count
Mark-CodeLabel -Label '__sharnou_chkstk'
Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xE2)) # mov r10,rsp (includes the call return address)
Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC3)) # mov r11,rax
Emit-Bytes -Bytes ([byte[]]@(0x49, 0x83, 0xEB, 0x08)) # sub r11,8 (adjust for the call return address)
$probeLoopLabel = New-UniqueLabel -Prefix 'chkstk_loop'
$probeTailLabel = New-UniqueLabel -Prefix 'chkstk_tail'
$probeDoneLabel = New-UniqueLabel -Prefix 'chkstk_done'
Mark-CodeLabel -Label $probeLoopLabel
Emit-Bytes -Bytes ([byte[]]@(0x49, 0x81, 0xFB, 0x00, 0x10, 0x00, 0x00)) # cmp r11,1000h
Emit-JumpConditional -ConditionCode 0x82 -Label $probeTailLabel
Emit-Bytes -Bytes ([byte[]]@(0x49, 0x81, 0xEA, 0x00, 0x10, 0x00, 0x00)) # sub r10,1000h
Emit-Bytes -Bytes ([byte[]]@(0x41, 0xF6, 0x02, 0x00)) # test byte ptr [r10],0
Emit-Bytes -Bytes ([byte[]]@(0x49, 0x81, 0xEB, 0x00, 0x10, 0x00, 0x00)) # sub r11,1000h
Emit-Jump -Label $probeLoopLabel
Mark-CodeLabel -Label $probeTailLabel
Emit-Bytes -Bytes ([byte[]]@(0x4D, 0x85, 0xDB)) # test r11,r11
Emit-JumpConditional -ConditionCode 0x84 -Label $probeDoneLabel
Emit-Bytes -Bytes ([byte[]]@(0x4D, 0x29, 0xDA)) # sub r10,r11
Emit-Bytes -Bytes ([byte[]]@(0x41, 0xF6, 0x02, 0x00)) # test byte ptr [r10],0
Mark-CodeLabel -Label $probeDoneLabel
Emit-Bytes -Bytes ([byte[]]@(0xC3)) # ret; RAX is deliberately unchanged

# WINAPI thread callback used by the thread/synchronization smoke-test intrinsic.
$workerOffset = [int]$script:Code.Count
Mark-CodeLabel -Label '__sharnou_worker'
Emit-Bytes -Bytes ([byte[]]@(0x31, 0xC0, 0xC3)) # return DWORD 0

# Explicit Win64 callback ABI probes are leaf functions. The first probe uses
# the exact SERVICE_MAIN_FUNCTIONW parameter widths; the second uses the exact
# HANDLER_FUNCTION_EX four-register layout. They preserve all nonvolatile state.
if ($script:DataPointerFixups.Count -gt 0) {
    $callbackMarker = [byte[]]@(0xDE, 0xC0, 0xA7, 0x51)

    Mark-CodeLabel -Label '__r51_service_main_abi_probe'
    $serviceMainFail = New-UniqueLabel -Prefix 'service_main_abi_fail'
    Emit-Bytes -Bytes ([byte[]]@(0x81, 0xF9, 0xDF, 0x9B, 0x57, 0x13)) # cmp ecx,13579BDFh
    Emit-JumpConditional -ConditionCode 0x85 -Label $serviceMainFail
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xD2)) # test rdx,rdx; require non-null LPWSTR*.
    Emit-JumpConditional -ConditionCode 0x84 -Label $serviceMainFail
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0xB8))
    $script:Code.AddRange([BitConverter]::GetBytes([UInt64]::Parse('0000000051A7C0DE', [System.Globalization.NumberStyles]::HexNumber)))
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0x02)) # write a test LPWSTR value into argv[0].
    Emit-Bytes -Bytes ([byte[]]@(0x31, 0xC0, 0xC3)) # VOID callback; return value is intentionally ignored.
    Mark-CodeLabel -Label $serviceMainFail
    Emit-Bytes -Bytes ([byte[]]@(0x31, 0xC0, 0xC3))

    Mark-CodeLabel -Label '__r51_handler_ex_abi_probe'
    $handlerExFail = New-UniqueLabel -Prefix 'handler_ex_abi_fail'
    Emit-Bytes -Bytes ([byte[]]@(0x81, 0xF9, 0x78, 0x56, 0x34, 0x12)) # cmp ecx,12345678h
    Emit-JumpConditional -ConditionCode 0x85 -Label $handlerExFail
    Emit-Bytes -Bytes ([byte[]]@(0x81, 0xFA, 0x21, 0x43, 0x65, 0x87)) # cmp edx,87654321h
    Emit-JumpConditional -ConditionCode 0x85 -Label $handlerExFail
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0xB8))
    $script:Code.AddRange([BitConverter]::GetBytes([UInt64]::Parse('1122334455667788', [System.Globalization.NumberStyles]::HexNumber)))
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x39, 0xC0)) # cmp r8,rax (full-width LPVOID).
    Emit-JumpConditional -ConditionCode 0x85 -Label $handlerExFail
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0xB8))
    $script:Code.AddRange([BitConverter]::GetBytes([UInt64]::Parse('8877665544332211', [System.Globalization.NumberStyles]::HexNumber)))
    Emit-Bytes -Bytes ([byte[]]@(0x49, 0x39, 0xC1)) # cmp r9,rax (full-width LPVOID).
    Emit-JumpConditional -ConditionCode 0x85 -Label $handlerExFail
    Emit-Bytes -Bytes ([byte[]]@(0xB8)); $script:Code.AddRange($callbackMarker); Emit-Bytes -Bytes ([byte[]]@(0xC3))
    Mark-CodeLabel -Label $handlerExFail
    Emit-Bytes -Bytes ([byte[]]@(0x31, 0xC0, 0xC3))
}

# The stack-probe helper and worker/callback probes are true leaf routines and
# need no RUNTIME_FUNCTION rows. Frame-owning functions retain x64 unwind data.
$orderedFunctions = @($script:Functions.Values | Sort-Object Index)
$runtimeFunctionSpecs = [System.Collections.Generic.List[object]]::new()
$entryEndOffset = if ($orderedFunctions.Count -gt 0) { [int]$script:CodeLabels[$orderedFunctions[0].Label] } else { $stackProbeOffset }
$runtimeFunctionSpecs.Add([pscustomobject]@{ StartOffset = [int]$script:CodeLabels['__entry']; EndOffset = $entryEndOffset; Context = $script:MainContext; UnwindBytes = $null; UnwindOffset = 0 })
for ($functionIndex = 0; $functionIndex -lt $orderedFunctions.Count; $functionIndex++) {
    $functionObject = $orderedFunctions[$functionIndex]
    $startOffset = [int]$script:CodeLabels[$functionObject.Label]
    $endOffset = if (($functionIndex + 1) -lt $orderedFunctions.Count) { [int]$script:CodeLabels[$orderedFunctions[$functionIndex + 1].Label] } else { $stackProbeOffset }
    if ($endOffset -le $startOffset) { throw "Invalid generated function range for '$($functionObject.Name)'." }
    $runtimeFunctionSpecs.Add([pscustomobject]@{ StartOffset = $startOffset; EndOffset = $endOffset; Context = $functionObject.Context; UnwindBytes = $null; UnwindOffset = 0 })
}
foreach ($runtimeFunction in $runtimeFunctionSpecs) {
    $runtimeFunction.UnwindBytes = New-UnwindInfoBytes -Context $runtimeFunction.Context
}
$xdataLength = 0
foreach ($runtimeFunction in $runtimeFunctionSpecs) {
    $xdataLength = Align-Up -Value $xdataLength -Alignment 4
    $runtimeFunction.UnwindOffset = $xdataLength
    $xdataLength += $runtimeFunction.UnwindBytes.Length
}
$pdataLength = $runtimeFunctionSpecs.Count * 12
if ($pdataLength -le 0 -or $xdataLength -le 0) { throw 'Generated PE unwind tables cannot be empty.' }

$codeBytes = $script:Code.ToArray()
if ($codeBytes.Length -le 0) { throw 'Generated .text section is empty.' }
if ($codeBytes.Length -gt 0x01000000) { throw "Generated .text section is too large: $($codeBytes.Length) bytes; maximum is 16777216." }

# Size each virtual section to a full 4 KiB page and place later sections after it.
# This keeps the legacy RVAs for small code while allowing .text to grow beyond 4096 bytes.
$textRva = [UInt32]0x1000
$textVirtualSpan = Align-Up -Value $codeBytes.Length -Alignment 0x1000
if ($script:DataLength -gt 0x1000) { throw "Generated .rdata section is too large: $($script:DataLength) bytes; maximum is 4096." }
$dataVirtualSpan = Align-Up -Value ([Math]::Max(8, $script:DataLength)) -Alignment 0x1000
$idataVirtualSpan = Align-Up -Value 0x1000 -Alignment 0x1000
$dataRva = [UInt32]([long]$textRva + [long]$textVirtualSpan)
$relocationImageBoundary = [UInt32]([long]$dataRva + [long]$dataVirtualSpan)
$relocationTargets = [System.Collections.Generic.List[UInt32]]::new()
$relocationTargets.Add($dataRva) # Existing .rdata absolute entry-point anchor.
foreach ($callbackFixup in $script:DataPointerFixups) {
    if (-not $script:CodeLabels.ContainsKey([string]$callbackFixup.Label)) {
        throw "Unresolved typed callback code label: $($callbackFixup.Label)"
    }
    $callbackOffset = [Int64]$script:CodeLabels[[string]$callbackFixup.Label]
    if ($callbackOffset -lt 0 -or $callbackOffset -ge $codeBytes.Length) {
        throw "Typed callback target is outside .text: $($callbackFixup.Label)"
    }
    $callbackFixup.TargetRva = [UInt32]([Int64]$textRva + $callbackOffset)
    $pointerRva = [UInt64]$dataRva + [UInt64]$callbackFixup.DataItem.Offset
    if ($pointerRva -gt [UInt32]::MaxValue) { throw 'Typed callback pointer data RVA exceeds the PE RVA range.' }
    $relocationTargets.Add([UInt32]$pointerRva)
}
$script:ExpectedRelocationTargetRvas = [UInt32[]]@($relocationTargets)
$relocationDirectory = New-SharnouBaseRelocationDirectory -TargetRvas $script:ExpectedRelocationTargetRvas -ImageSize $relocationImageBoundary -AllowedRanges @([pscustomobject]@{ StartRva = $dataRva; Size = [Math]::Max(8, $script:DataLength) })
$relocVirtualSpan = Align-Up -Value $relocationDirectory.DirectorySize -Alignment 0x1000
$pdataVirtualSpan = Align-Up -Value $pdataLength -Alignment 0x1000
$xdataVirtualSpan = Align-Up -Value $xdataLength -Alignment 0x1000
$idataRva = [UInt32]([long]$dataRva + [long]$dataVirtualSpan)
$relocRva = [UInt32]([long]$idataRva + [long]$idataVirtualSpan)
$pdataRva = [UInt32]([long]$relocRva + [long]$relocVirtualSpan)
$xdataRva = [UInt32]([long]$pdataRva + [long]$pdataVirtualSpan)
$sizeOfImage = [UInt32]([long]$xdataRva + [long]$xdataVirtualSpan)
if ([UInt64]$sizeOfImage -gt [UInt32]::MaxValue) { throw 'Linked image exceeds the PE32+ 32-bit RVA address space.' }

# Build sorted x64 RUNTIME_FUNCTION entries and their 4-byte-aligned UNWIND_INFO records.
$pdataBytes = [byte[]]::new($pdataLength)
$xdataBytes = [byte[]]::new($xdataLength)
for ($runtimeIndex = 0; $runtimeIndex -lt $runtimeFunctionSpecs.Count; $runtimeIndex++) {
    $runtimeFunction = $runtimeFunctionSpecs[$runtimeIndex]
    $recordOffset = $runtimeIndex * 12
    Set-U32 -Buffer $pdataBytes -Offset $recordOffset -Value ([UInt32]([long]$textRva + [long]$runtimeFunction.StartOffset))
    Set-U32 -Buffer $pdataBytes -Offset ($recordOffset + 4) -Value ([UInt32]([long]$textRva + [long]$runtimeFunction.EndOffset))
    Set-U32 -Buffer $pdataBytes -Offset ($recordOffset + 8) -Value ([UInt32]([long]$xdataRva + [long]$runtimeFunction.UnwindOffset))
    [System.Buffer]::BlockCopy($runtimeFunction.UnwindBytes, 0, $xdataBytes, $runtimeFunction.UnwindOffset, $runtimeFunction.UnwindBytes.Length)
}

# Patch RIP-relative data references, IAT calls, conditional branches, and internal rel32 calls.
foreach ($fixup in $script:CodeFixups) {
    if ($fixup.Kind -eq 'Data') { $targetRva = [long]$dataRva + [long]$fixup.Target.Offset }
    elseif ($fixup.Kind -eq 'Iat') { $targetRva = [long]$idataRva + [long]$fixup.TargetOffset }
    elseif ($fixup.Kind -eq 'Code' -or $fixup.Kind -eq 'Call') {
        if (-not $script:CodeLabels.ContainsKey([string]$fixup.Target)) { throw "Unresolved internal linker symbol: $($fixup.Target)" }
        $targetRva = [long]$textRva + [long]$script:CodeLabels[[string]$fixup.Target]
    } else { throw "Unknown code fixup kind: $($fixup.Kind)" }
    $nextRva = [long]0x1000 + [long]$fixup.DispOffset + 4; $displacement = $targetRva - $nextRva
    if ($displacement -lt [int]::MinValue -or $displacement -gt [int]::MaxValue) { throw "RIP-relative/call displacement is out of range: $displacement" }
    $dispBytes = [BitConverter]::GetBytes([int32]$displacement)
    for ($j = 0; $j -lt 4; $j++) { $script:Code[$fixup.DispOffset + $j] = $dispBytes[$j] }
}
$codeBytes = $script:Code.ToArray()
$dataBytes = [byte[]]::new([Math]::Max(8, $script:DataLength))
# Relocated pointer used by the linker's relocation/verification self-check.
Set-U64 -Buffer $dataBytes -Offset 0 -Value ([UInt64]([Int64]0x140001000))
foreach ($callbackFixup in $script:DataPointerFixups) {
    if ($callbackFixup.DataItem.Bytes.Length -ne 8 -or $callbackFixup.TargetRva -eq 0) {
        throw "Typed callback pointer fixup is incomplete: $($callbackFixup.Key)"
    }
    $callbackVa = [UInt64]([UInt64]0x140000000 + [UInt64]$callbackFixup.TargetRva)
    Set-U64 -Buffer $callbackFixup.DataItem.Bytes -Offset 0 -Value $callbackVa
}
foreach ($item in $script:DataItems) { if ($item.Bytes.Length -gt 0) { Set-Bytes -Buffer $dataBytes -Offset $item.Offset -Bytes $item.Bytes } }

# Dynamically sized RVA layout and independently aligned raw file layout: .text/.rdata/.idata/.reloc.
$textRawSize = Align-Up -Value $codeBytes.Length -Alignment 0x200
$dataRawSize = Align-Up -Value $dataBytes.Length -Alignment 0x200
# Milestone 5 import builder. Existing IAT offsets (0x70, 0x78, 0x80, and 0x90)
# stay stable within .idata. Lookup tables use the disjoint 0x500-0x610 range;
# no lookup table may overlap any IAT slot or import-by-name string. Emit-CallIat rebases target RVAs after section placement.
$idata = [byte[]]::new(0x1000)
# Import descriptors have a dedicated .idata range, disjoint from lookups, IAT and names.
$descriptorBase = 0xA00
$importDirectorySize = 0x190
if (($descriptorBase + $importDirectorySize) -gt $idata.Length) { throw 'Import descriptor table exceeds .idata storage.' }
$importSets = @(
    [pscustomobject]@{ Descriptor = 0x00; Lookup = 0xC00; Iat = 0x70; Dll = 'KERNEL32.dll'; Names = @('GetStdHandle', 'WriteFile', 'ExitProcess') },
    [pscustomobject]@{ Descriptor = 0x14; Lookup = 0xC20; Iat = 0x90; Dll = 'USER32.dll'; Names = @('wsprintfA') },
    [pscustomobject]@{ Descriptor = 0x28; Lookup = 0xC30; Iat = 0xA0; Dll = 'KERNEL32.dll'; Names = @('CreateFileA', 'GetFileSizeEx', 'ReadFile', 'CloseHandle', 'GetModuleHandleA', 'CreateThread', 'WaitForSingleObject', 'CreateMutexA', 'ReleaseMutex') },
    [pscustomobject]@{ Descriptor = 0x3C; Lookup = 0xC80; Iat = 0xF0; Dll = 'USER32.dll'; Names = @('CreateWindowExA', 'ShowWindow', 'UpdateWindow', 'PeekMessageA', 'TranslateMessage', 'DispatchMessageA', 'DestroyWindow') },
    [pscustomobject]@{ Descriptor = 0x50; Lookup = 0xCC0; Iat = 0x130; Dll = 'D3D11.dll'; Names = @('D3D11CreateDeviceAndSwapChain') },
    [pscustomobject]@{ Descriptor = 0x64; Lookup = 0xCD0; Iat = 0x140; Dll = 'DXGI.dll'; Names = @('CreateDXGIFactory') },
    [pscustomobject]@{ Descriptor = 0x78; Lookup = 0xCE0; Iat = 0x150; Dll = 'KERNEL32.dll'; Names = @('QueryPerformanceCounter', 'QueryPerformanceFrequency') },
    [pscustomobject]@{ Descriptor = 0x8C; Lookup = 0xCF8; Iat = 0x168; Dll = 'USER32.dll'; Names = @('IsWindow') },
    [pscustomobject]@{ Descriptor = 0xA0; Lookup = 0xD08; Iat = 0x178; Dll = 'KERNEL32.dll'; Names = @('GetSystemDirectoryA', 'GetCurrentDirectoryA', 'CreateProcessA', 'CreateJobObjectA', 'SetInformationJobObject', 'AssignProcessToJobObject', 'ResumeThread', 'TerminateJobObject', 'GetExitCodeProcess', 'TerminateProcess', 'GetFileAttributesA', 'VirtualAlloc', 'VirtualFree') },
    [pscustomobject]@{ Descriptor = 0xB4; Lookup = 0xD78; Iat = 0x1E8; Dll = 'BCRYPT.dll'; Names = @('BCryptOpenAlgorithmProvider', 'BCryptHash', 'BCryptCloseAlgorithmProvider') },
    [pscustomobject]@{ Descriptor = 0xC8; Lookup = 0xD98; Iat = 0x208; Dll = 'KERNEL32.dll'; Names = @('GetFileInformationByHandle') },
    [pscustomobject]@{ Descriptor = 0xDC; Lookup = 0xDA8; Iat = 0x218; Dll = 'KERNEL32.dll'; Names = @('GetModuleFileNameA', 'SetCurrentDirectoryA') },
    [pscustomobject]@{ Descriptor = 0xF0; Lookup = 0xDC0; Iat = 0x230; Dll = 'KERNEL32.dll'; Names = @('CreatePipe', 'SetHandleInformation', 'PeekNamedPipe', 'InitializeProcThreadAttributeList', 'UpdateProcThreadAttribute', 'DeleteProcThreadAttributeList', 'LocalFree', 'GetLastError') },
    [pscustomobject]@{ Descriptor = 0x104; Lookup = 0xE08; Iat = 0x278; Dll = 'USERENV.dll'; Names = @('CreateAppContainerProfile', 'DeriveAppContainerSidFromAppContainerName') },
    [pscustomobject]@{ Descriptor = 0x118; Lookup = 0xE20; Iat = 0x290; Dll = 'ADVAPI32.dll'; Names = @('GetNamedSecurityInfoA', 'SetEntriesInAclA', 'SetNamedSecurityInfoA', 'FreeSid', 'OpenProcessToken', 'CreateRestrictedToken', 'CreateProcessAsUserA', 'GetSecurityInfo', 'SetSecurityInfo', 'GetTokenInformation', 'GetSecurityDescriptorDacl', 'GetSecurityDescriptorSacl', 'GetSecurityDescriptorLength', 'IsValidSecurityDescriptor') },
    [pscustomobject]@{ Descriptor = 0x12C; Lookup = 0xE98; Iat = 0x308; Dll = 'KERNEL32.dll'; Names = @('GetFullPathNameA', 'DeleteFileA', 'MoveFileExA', 'FlushFileBuffers') },
    [pscustomobject]@{ Descriptor = 0x140; Lookup = 0xEC0; Iat = 0x330; Dll = 'BCRYPT.dll'; Names = @('BCryptGenRandom') },
    [pscustomobject]@{ Descriptor = 0x154; Lookup = 0xED0; Iat = 0x340; Dll = 'USERENV.dll'; Names = @('DeleteAppContainerProfile') },
    [pscustomobject]@{ Descriptor = 0x168; Lookup = 0xEE0; Iat = 0x350; Dll = 'ADVAPI32.dll'; Names = @('EqualSid') }
)
if (($descriptorBase + $importDirectorySize) -gt $idata.Length) { throw 'Import descriptor table exceeds .idata storage.' }
$apiNameRvas = @{}
$nameCursor = 0x3A0
foreach ($set in $importSets) {
    foreach ($apiName in $set.Names) {
        if (-not $apiNameRvas.ContainsKey($apiName)) {
            $apiNameRvas[$apiName] = [UInt32]([long]$idataRva + [long]$nameCursor)
            Set-U16 -Buffer $idata -Offset $nameCursor -Value 0
            Set-AsciiZ -Buffer $idata -Offset ($nameCursor + 2) -Value $apiName
            $nameCursor += 2 + [System.Text.Encoding]::ASCII.GetByteCount($apiName) + 1
            if (($nameCursor % 2) -ne 0) { $nameCursor++ }
        }
    }
}
if ($nameCursor -gt $descriptorBase) {
    throw ("Import-by-name strings overlap the import descriptor table: end=0x{0:X}, descriptorBase=0x{1:X}." -f $nameCursor, $descriptorBase)
}
Set-AsciiZ -Buffer $idata -Offset 0xF00 -Value 'KERNEL32.dll'
Set-AsciiZ -Buffer $idata -Offset 0xF10 -Value 'USER32.dll'
Set-AsciiZ -Buffer $idata -Offset 0xF20 -Value 'D3D11.dll'
Set-AsciiZ -Buffer $idata -Offset 0xF30 -Value 'DXGI.dll'
Set-AsciiZ -Buffer $idata -Offset 0xF40 -Value 'BCRYPT.dll'
Set-AsciiZ -Buffer $idata -Offset 0xF50 -Value 'USERENV.dll'
Set-AsciiZ -Buffer $idata -Offset 0xF60 -Value 'ADVAPI32.dll'
foreach ($set in $importSets) {
    switch ($set.Dll) {
        'KERNEL32.dll' { $nameOffset = 0xF00 }
        'USER32.dll' { $nameOffset = 0xF10 }
        'D3D11.dll' { $nameOffset = 0xF20 }
        'DXGI.dll' { $nameOffset = 0xF30 }
        'BCRYPT.dll' { $nameOffset = 0xF40 }
        'USERENV.dll' { $nameOffset = 0xF50 }
        'ADVAPI32.dll' { $nameOffset = 0xF60 }
        default { throw "Internal linker error: unsupported import DLL '$($set.Dll)'" }
    }
        $descriptorOffset = [int]($descriptorBase + $set.Descriptor)
    Set-U32 -Buffer $idata -Offset $descriptorOffset -Value ([UInt32]([long]$idataRva + [long]$set.Lookup))
    Set-U32 -Buffer $idata -Offset ($descriptorOffset + 4) -Value 0
    Set-U32 -Buffer $idata -Offset ($descriptorOffset + 8) -Value 0
    Set-U32 -Buffer $idata -Offset ($descriptorOffset + 12) -Value ([UInt32]([long]$idataRva + [long]$nameOffset))
    Set-U32 -Buffer $idata -Offset ($descriptorOffset + 16) -Value ([UInt32]([long]$idataRva + [long]$set.Iat))
    for ($apiIndex = 0; $apiIndex -lt $set.Names.Count; $apiIndex++) {
        $hintRva = [UInt64]$apiNameRvas[$set.Names[$apiIndex]]
        Set-U64 -Buffer $idata -Offset ($set.Lookup + ($apiIndex * 8)) -Value ([UInt64]$hintRva)
        Set-U64 -Buffer $idata -Offset ($set.Iat + ($apiIndex * 8)) -Value ([UInt64]$hintRva)
    }
}
$script:StdLibIatOffsets = @{
    'GetStdHandle' = [UInt32]0x70; 'WriteFile' = [UInt32]0x78; 'ExitProcess' = [UInt32]0x80; 'wsprintfA' = [UInt32]0x90
    'CreateFileA' = [UInt32]0xA0; 'GetFileSizeEx' = [UInt32]0xA8; 'ReadFile' = [UInt32]0xB0; 'CloseHandle' = [UInt32]0xB8
    'GetModuleHandleA' = [UInt32]0xC0; 'CreateThread' = [UInt32]0xC8; 'WaitForSingleObject' = [UInt32]0xD0; 'CreateMutexA' = [UInt32]0xD8
    'ReleaseMutex' = [UInt32]0xE0; 'CreateWindowExA' = [UInt32]0xF0; 'ShowWindow' = [UInt32]0xF8; 'UpdateWindow' = [UInt32]0x100
    'PeekMessageA' = [UInt32]0x108; 'TranslateMessage' = [UInt32]0x110; 'DispatchMessageA' = [UInt32]0x118; 'DestroyWindow' = [UInt32]0x120
    'D3D11CreateDeviceAndSwapChain' = [UInt32]0x130; 'CreateDXGIFactory' = [UInt32]0x140
    'QueryPerformanceCounter' = [UInt32]0x150; 'QueryPerformanceFrequency' = [UInt32]0x158; 'IsWindow' = [UInt32]0x168
    'GetSystemDirectoryA' = [UInt32]0x178; 'GetCurrentDirectoryA' = [UInt32]0x180; 'CreateProcessA' = [UInt32]0x188
    'CreateJobObjectA' = [UInt32]0x190; 'SetInformationJobObject' = [UInt32]0x198; 'AssignProcessToJobObject' = [UInt32]0x1A0
    'ResumeThread' = [UInt32]0x1A8; 'TerminateJobObject' = [UInt32]0x1B0; 'GetExitCodeProcess' = [UInt32]0x1B8; 'TerminateProcess' = [UInt32]0x1C0; 'GetFileAttributesA' = [UInt32]0x1C8
    'VirtualAlloc' = [UInt32]0x1D0; 'VirtualFree' = [UInt32]0x1D8
    'BCryptOpenAlgorithmProvider' = [UInt32]0x1E8; 'BCryptHash' = [UInt32]0x1F0; 'BCryptCloseAlgorithmProvider' = [UInt32]0x1F8
    'GetFileInformationByHandle' = [UInt32]0x208
    'GetModuleFileNameA' = [UInt32]0x218; 'SetCurrentDirectoryA' = [UInt32]0x220
    'CreatePipe' = [UInt32]0x230; 'SetHandleInformation' = [UInt32]0x238; 'PeekNamedPipe' = [UInt32]0x240
    'InitializeProcThreadAttributeList' = [UInt32]0x248; 'UpdateProcThreadAttribute' = [UInt32]0x250; 'DeleteProcThreadAttributeList' = [UInt32]0x258; 'LocalFree' = [UInt32]0x260; 'GetLastError' = [UInt32]0x268
    'CreateAppContainerProfile' = [UInt32]0x278; 'DeriveAppContainerSidFromAppContainerName' = [UInt32]0x280
    'GetNamedSecurityInfoA' = [UInt32]0x290; 'SetEntriesInAclA' = [UInt32]0x298; 'SetNamedSecurityInfoA' = [UInt32]0x2A0; 'FreeSid' = [UInt32]0x2A8
    'OpenProcessToken' = [UInt32]0x2B0; 'CreateRestrictedToken' = [UInt32]0x2B8; 'CreateProcessAsUserA' = [UInt32]0x2C0; 'GetSecurityInfo' = [UInt32]0x2C8; 'SetSecurityInfo' = [UInt32]0x2D0; 'GetTokenInformation' = [UInt32]0x2D8
    'GetSecurityDescriptorDacl' = [UInt32]0x2E0; 'GetSecurityDescriptorSacl' = [UInt32]0x2E8; 'GetSecurityDescriptorLength' = [UInt32]0x2F0; 'IsValidSecurityDescriptor' = [UInt32]0x2F8
    'GetFullPathNameA' = [UInt32]0x308; 'DeleteFileA' = [UInt32]0x310; 'MoveFileExA' = [UInt32]0x318; 'FlushFileBuffers' = [UInt32]0x320
    'BCryptGenRandom' = [UInt32]0x330; 'DeleteAppContainerProfile' = [UInt32]0x340; 'EqualSid' = [UInt32]0x350
}

# Emit a PE base-relocation directory whose size follows the actual DIR64 target set.
$relocRawSize = Align-Up -Value $relocationDirectory.DirectorySize -Alignment 0x200
$reloc = [byte[]]::new($relocRawSize)
Set-Bytes -Buffer $reloc -Offset 0 -Bytes $relocationDirectory.Bytes
if ($idata.Length -gt $idataVirtualSpan) { throw 'Generated .idata section exceeds its reserved virtual span.' }
$headersSize = 0x400
$pdataRawSize = Align-Up -Value $pdataBytes.Length -Alignment 0x200
$xdataRawSize = Align-Up -Value $xdataBytes.Length -Alignment 0x200
$textRawPointer = $headersSize
$dataRawPointer = $textRawPointer + $textRawSize
$idataRawPointer = $dataRawPointer + $dataRawSize
$relocRawPointer = $idataRawPointer + $idata.Length
$pdataRawPointer = $relocRawPointer + $reloc.Length
$xdataRawPointer = $pdataRawPointer + $pdataRawSize
$totalSize = $xdataRawPointer + $xdataRawSize
$image = [byte[]]::new($totalSize)
Set-Bytes -Buffer $image -Offset $textRawPointer -Bytes $codeBytes
Set-Bytes -Buffer $image -Offset $dataRawPointer -Bytes $dataBytes
Set-Bytes -Buffer $image -Offset $idataRawPointer -Bytes $idata
Set-Bytes -Buffer $image -Offset $relocRawPointer -Bytes $reloc
Set-Bytes -Buffer $image -Offset $pdataRawPointer -Bytes $pdataBytes
Set-Bytes -Buffer $image -Offset $xdataRawPointer -Bytes $xdataBytes

# DOS and PE headers.
$image[0] = 0x4D; $image[1] = 0x5A; Set-U32 -Buffer $image -Offset 0x3C -Value 0x80; Set-Ascii -Buffer $image -Offset 0x80 -Value "PE`0`0"
Set-U16 -Buffer $image -Offset 0x84 -Value 0x8664; Set-U16 -Buffer $image -Offset 0x86 -Value 6; Set-U32 -Buffer $image -Offset 0x88 -Value 0; Set-U32 -Buffer $image -Offset 0x8C -Value 0; Set-U32 -Buffer $image -Offset 0x90 -Value 0; Set-U16 -Buffer $image -Offset 0x94 -Value 240; Set-U16 -Buffer $image -Offset 0x96 -Value 0x0022
$opt = 0x98
Set-U16 -Buffer $image -Offset ($opt + 0) -Value 0x020B; $image[$opt + 2] = 1; $image[$opt + 3] = 0
Set-U32 -Buffer $image -Offset ($opt + 4) -Value $textRawSize; Set-U32 -Buffer $image -Offset ($opt + 8) -Value ($dataRawSize + $idata.Length + $reloc.Length + $pdataRawSize + $xdataRawSize); Set-U32 -Buffer $image -Offset ($opt + 12) -Value 0
Set-U32 -Buffer $image -Offset ($opt + 16) -Value $textRva; Set-U32 -Buffer $image -Offset ($opt + 20) -Value $textRva; Set-U64 -Buffer $image -Offset ($opt + 24) -Value ([UInt64]([Int64]0x140000000))
Set-U32 -Buffer $image -Offset ($opt + 32) -Value 0x1000; Set-U32 -Buffer $image -Offset ($opt + 36) -Value 0x200
Set-U16 -Buffer $image -Offset ($opt + 40) -Value 6; Set-U16 -Buffer $image -Offset ($opt + 42) -Value 0; Set-U16 -Buffer $image -Offset ($opt + 44) -Value 0; Set-U16 -Buffer $image -Offset ($opt + 46) -Value 0; Set-U16 -Buffer $image -Offset ($opt + 48) -Value 6; Set-U16 -Buffer $image -Offset ($opt + 50) -Value 0
Set-U32 -Buffer $image -Offset ($opt + 52) -Value 0; Set-U32 -Buffer $image -Offset ($opt + 56) -Value $sizeOfImage; Set-U32 -Buffer $image -Offset ($opt + 60) -Value $headersSize; Set-U32 -Buffer $image -Offset ($opt + 64) -Value 0
Set-U16 -Buffer $image -Offset ($opt + 68) -Value 3; Set-U16 -Buffer $image -Offset ($opt + 70) -Value 0x0140
Set-U64 -Buffer $image -Offset ($opt + 72) -Value ([UInt64]0x100000); Set-U64 -Buffer $image -Offset ($opt + 80) -Value ([UInt64]0x1000); Set-U64 -Buffer $image -Offset ($opt + 88) -Value ([UInt64]0x100000); Set-U64 -Buffer $image -Offset ($opt + 96) -Value ([UInt64]0x1000)
Set-U32 -Buffer $image -Offset ($opt + 104) -Value 0; Set-U32 -Buffer $image -Offset ($opt + 108) -Value 16
Set-U32 -Buffer $image -Offset ($opt + 120) -Value ([UInt32]([long]$idataRva + [long]$descriptorBase)); Set-U32 -Buffer $image -Offset ($opt + 124) -Value $importDirectorySize
Set-U32 -Buffer $image -Offset ($opt + 136) -Value $pdataRva; Set-U32 -Buffer $image -Offset ($opt + 140) -Value $pdataBytes.Length
Set-U32 -Buffer $image -Offset ($opt + 152) -Value $relocRva; Set-U32 -Buffer $image -Offset ($opt + 156) -Value $relocationDirectory.DirectorySize
Set-U32 -Buffer $image -Offset ($opt + 208) -Value ([UInt32]([long]$idataRva + 0x70)); Set-U32 -Buffer $image -Offset ($opt + 212) -Value 0x2F0
$sectionText = 0x188
Set-Ascii -Buffer $image -Offset $sectionText -Value '.text'; Set-U32 -Buffer $image -Offset ($sectionText + 8) -Value $codeBytes.Length; Set-U32 -Buffer $image -Offset ($sectionText + 12) -Value $textRva; Set-U32 -Buffer $image -Offset ($sectionText + 16) -Value $textRawSize; Set-U32 -Buffer $image -Offset ($sectionText + 20) -Value $textRawPointer; Set-U32 -Buffer $image -Offset ($sectionText + 36) -Value 0x60000020
$sectionData = 0x1B0
Set-Ascii -Buffer $image -Offset $sectionData -Value '.rdata'; Set-U32 -Buffer $image -Offset ($sectionData + 8) -Value $dataBytes.Length; Set-U32 -Buffer $image -Offset ($sectionData + 12) -Value $dataRva; Set-U32 -Buffer $image -Offset ($sectionData + 16) -Value $dataRawSize; Set-U32 -Buffer $image -Offset ($sectionData + 20) -Value $dataRawPointer; Set-U32 -Buffer $image -Offset ($sectionData + 36) -Value 0x40000040
$sectionImport = 0x1D8
Set-Ascii -Buffer $image -Offset $sectionImport -Value '.idata'; Set-U32 -Buffer $image -Offset ($sectionImport + 8) -Value $idata.Length; Set-U32 -Buffer $image -Offset ($sectionImport + 12) -Value $idataRva; Set-U32 -Buffer $image -Offset ($sectionImport + 16) -Value $idata.Length; Set-U32 -Buffer $image -Offset ($sectionImport + 20) -Value $idataRawPointer; Set-U32 -Buffer $image -Offset ($sectionImport + 36) -Value ([UInt32]([Int64]3221225536))
$sectionReloc = 0x200
Set-Ascii -Buffer $image -Offset $sectionReloc -Value '.reloc'; Set-U32 -Buffer $image -Offset ($sectionReloc + 8) -Value $relocationDirectory.DirectorySize; Set-U32 -Buffer $image -Offset ($sectionReloc + 12) -Value $relocRva; Set-U32 -Buffer $image -Offset ($sectionReloc + 16) -Value $reloc.Length; Set-U32 -Buffer $image -Offset ($sectionReloc + 20) -Value $relocRawPointer; Set-U32 -Buffer $image -Offset ($sectionReloc + 36) -Value 0x42000040
$sectionPdata = 0x228
Set-Ascii -Buffer $image -Offset $sectionPdata -Value '.pdata'; Set-U32 -Buffer $image -Offset ($sectionPdata + 8) -Value $pdataBytes.Length; Set-U32 -Buffer $image -Offset ($sectionPdata + 12) -Value $pdataRva; Set-U32 -Buffer $image -Offset ($sectionPdata + 16) -Value $pdataRawSize; Set-U32 -Buffer $image -Offset ($sectionPdata + 20) -Value $pdataRawPointer; Set-U32 -Buffer $image -Offset ($sectionPdata + 36) -Value 0x40000040
$sectionXdata = 0x250
Set-Ascii -Buffer $image -Offset $sectionXdata -Value '.xdata'; Set-U32 -Buffer $image -Offset ($sectionXdata + 8) -Value $xdataBytes.Length; Set-U32 -Buffer $image -Offset ($sectionXdata + 12) -Value $xdataRva; Set-U32 -Buffer $image -Offset ($sectionXdata + 16) -Value $xdataRawSize; Set-U32 -Buffer $image -Offset ($sectionXdata + 20) -Value $xdataRawPointer; Set-U32 -Buffer $image -Offset ($sectionXdata + 36) -Value 0x40000040
Test-ImageBasic -Image $image

$outputDirectory = [System.IO.Path]::GetDirectoryName($outputFullPath)
[System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
$verifierPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\Tools\SharnouPEVerify.ps1'))
try {
    [System.IO.File]::WriteAllBytes($outputFullPath, $image)
    if (-not (Test-Path -LiteralPath $verifierPath -PathType Leaf)) { throw "PE verifier is missing: $verifierPath" }
    & $verifierPath -Path $outputFullPath
} catch {
    if (Test-Path -LiteralPath $outputFullPath) { Remove-Item -LiteralPath $outputFullPath -Force -ErrorAction SilentlyContinue }
    throw ("Linked image failed post-write validation: {0}" -f $_.Exception.Message)
}
$sha256 = (Get-FileHash -LiteralPath $outputFullPath -Algorithm SHA256).Hash
Write-Host "Created native x64 PE32+ executable: $outputFullPath"
Write-Host ("Link result: modules={0}, functions={1}, codeBytes={2}, dataBytes={3}" -f $script:Modules.Count, $script:Functions.Count, $codeBytes.Length, $dataBytes.Length)
Write-Host 'Sections: .text, .rdata, .idata, .reloc, .pdata, .xdata; imports: KERNEL32.dll, USER32.dll, D3D11.dll, and DXGI.dll'
Write-Host "SHA-256: $sha256"
Write-Warning 'Milestone 6 adds a native D3D11/DXGI solid-clear demo and runtime frame timing. Native rendering must be validated on an interactive Windows desktop. Shader/geometry rendering, device-loss recovery, resize handling, and persistent window/event loops remain unsupported.' 
