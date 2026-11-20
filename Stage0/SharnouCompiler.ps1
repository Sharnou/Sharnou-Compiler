[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string] $Source,
    [Parameter(Mandatory = $true, Position = 1)]
    [string] $Output
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
            if (@('<=', '>=', '==', '!=', '&&', '||') -contains $pair) {
                Add-Token -Kind 'Symbol' -Text $pair -Value $pair -Line $line -Column $column
                $i += 2; $column += 2; continue
            }
        }
        if ('+-*/=();{},<>!:'.Contains([string]$ch)) {
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
function New-BooleanNode { param([bool] $Value, [int] $Line, [int] $Column) return (New-AstNode -Kind 'Boolean' -Type 'Boolean' -Value $Value -Line $Line -Column $Column) }
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
function Resolve-PrimitiveType {
    param([object] $Token)
    if ($Token.Kind -ne 'Identifier') {
        Throw-SourceError -Line $Token.Line -Column $Token.Column -Message 'Expected a primitive type name after type annotation.'
    }
    switch -CaseSensitive ([string]$Token.Text) {
        'i32' { return 'Integer' }
        'bool' { return 'Boolean' }
        'string' { return 'String' }
        default {
            Throw-SourceError -Line $Token.Line -Column $Token.Column -Message ("Unknown primitive type '{0}'; supported types are i32, bool, and string." -f $Token.Text)
        }
    }
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
    if ($token.Kind -eq 'Identifier' -and ($token.Text -ceq 'true' -or $token.Text -ceq 'false')) {
        Move-NextToken | Out-Null
        return (New-BooleanNode -Value ([bool]($token.Text -ceq 'true')) -Line $token.Line -Column $token.Column)
    }
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
    if ($token.Text -ceq '!') {
        $operator = Move-NextToken
        $operand = Parse-Unary
        if ($operand.Type -ne 'Boolean') { Throw-SourceError -Line $operator.Line -Column $operator.Column -Message "Logical NOT requires a Boolean operand." }
        return (New-AstNode -Kind 'Not' -Type 'Boolean' -Operator '!' -Operand $operand -Line $operator.Line -Column $operator.Column)
    }
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
function Parse-ComparisonExpression {
    $left = Parse-AdditiveExpression
    $operatorToken = Get-CurrentToken
    $comparisonOperators = @('<', '>', '<=', '>=', '==', '!=')
    if ($comparisonOperators -contains $operatorToken.Text) {
        $operator = Move-NextToken
        $right = Parse-AdditiveExpression
        if ($left.Type -ne $right.Type -or @('Integer', 'Boolean') -notcontains $left.Type) {
            Throw-SourceError -Line $operator.Line -Column $operator.Column -Message ("Comparison '{0}' requires matching integer or Boolean operands." -f $operator.Text)
        }
        if ($left.Type -eq 'Boolean' -and @('==', '!=') -notcontains $operator.Text) {
            Throw-SourceError -Line $operator.Line -Column $operator.Column -Message 'Boolean values support only == and != comparisons.'
        }
        $next = Get-CurrentToken
        if ($comparisonOperators -contains $next.Text) {
            Throw-SourceError -Line $next.Line -Column $next.Column -Message 'Chained comparisons are not supported; use a nested if or while statement.'
        }
        return (New-AstNode -Kind 'Comparison' -Type 'Boolean' -Operator ([string]$operator.Text) -Left $left -Right $right -Line $operator.Line -Column $operator.Column)
    }
    return $left
}
function Parse-LogicalAndExpression {
    $value = Parse-ComparisonExpression
    while (Test-CurrentText '&&') {
        $operator = Move-NextToken
        $right = Parse-ComparisonExpression
        if ($value.Type -ne 'Boolean' -or $right.Type -ne 'Boolean') { Throw-SourceError -Line $operator.Line -Column $operator.Column -Message 'Logical AND requires Boolean operands.' }
        $value = New-AstNode -Kind 'Logical' -Type 'Boolean' -Operator '&&' -Left $value -Right $right -Line $operator.Line -Column $operator.Column
    }
    return $value
}
function Parse-LogicalOrExpression {
    $value = Parse-LogicalAndExpression
    while (Test-CurrentText '||') {
        $operator = Move-NextToken
        $right = Parse-LogicalAndExpression
        if ($value.Type -ne 'Boolean' -or $right.Type -ne 'Boolean') { Throw-SourceError -Line $operator.Line -Column $operator.Column -Message 'Logical OR requires Boolean operands.' }
        $value = New-AstNode -Kind 'Logical' -Type 'Boolean' -Operator '||' -Left $value -Right $right -Line $operator.Line -Column $operator.Column
    }
    return $value
}
function Parse-Expression {
    return (Parse-LogicalOrExpression)
}
function Get-ConstantValue {
    param([object] $Node)
    if ($Node.Kind -eq 'Integer') { return [pscustomobject]@{ Known = $true; Type = 'Integer'; Value = [long]$Node.Value } }
    if ($Node.Kind -eq 'Boolean') { return [pscustomobject]@{ Known = $true; Type = 'Boolean'; Value = [bool]$Node.Value } }
    if ($Node.Kind -eq 'String') { return [pscustomobject]@{ Known = $true; Type = 'String'; Value = [string]$Node.Value } }
    if ($Node.Kind -eq 'Variable' -or $Node.Kind -eq 'Call') { return [pscustomobject]@{ Known = $false; Type = $Node.Type; Value = $null } }
    if ($Node.Kind -eq 'Unary') {
        $child = Get-ConstantValue -Node $Node.Operand
        if (-not $child.Known) { return [pscustomobject]@{ Known = $false; Type = 'Integer'; Value = $null } }
        $number = [long]$child.Value
        if ($Node.Operator -eq '-') { $number = -$number }
        if ($number -lt [int]::MinValue -or $number -gt [int]::MaxValue) { Throw-SourceError -Line $Node.Line -Column $Node.Column -Message 'Integer result is outside the supported signed 32-bit range.' }
        return [pscustomobject]@{ Known = $true; Type = 'Integer'; Value = $number }
    }
    if ($Node.Kind -eq 'Not') {
        $child = Get-ConstantValue -Node $Node.Operand
        if (-not $child.Known) { return [pscustomobject]@{ Known = $false; Type = 'Boolean'; Value = $null } }
        return [pscustomobject]@{ Known = $true; Type = 'Boolean'; Value = (-not [bool]$child.Value) }
    }
    if ($Node.Kind -eq 'Logical') {
        $left = Get-ConstantValue -Node $Node.Left
        if (-not $left.Known) {
            $null = Get-ConstantValue -Node $Node.Right
            return [pscustomobject]@{ Known = $false; Type = 'Boolean'; Value = $null }
        }
        $leftBoolean = [bool]$left.Value
        if ($Node.Operator -eq '&&' -and -not $leftBoolean) { return [pscustomobject]@{ Known = $true; Type = 'Boolean'; Value = $false } }
        if ($Node.Operator -eq '||' -and $leftBoolean) { return [pscustomobject]@{ Known = $true; Type = 'Boolean'; Value = $true } }
        $right = Get-ConstantValue -Node $Node.Right
        if (-not $right.Known) { return [pscustomobject]@{ Known = $false; Type = 'Boolean'; Value = $null } }
        if ($Node.Operator -eq '&&') { $result = ($leftBoolean -and [bool]$right.Value) }
        elseif ($Node.Operator -eq '||') { $result = ($leftBoolean -or [bool]$right.Value) }
        else { Throw-SourceError -Line $Node.Line -Column $Node.Column -Message ("Unsupported logical operator '{0}'." -f $Node.Operator) }
        return [pscustomobject]@{ Known = $true; Type = 'Boolean'; Value = [bool]$result }
    }
    if ($Node.Kind -eq 'Comparison') {
        $left = Get-ConstantValue -Node $Node.Left
        $right = Get-ConstantValue -Node $Node.Right
        if (-not $left.Known -or -not $right.Known) { return [pscustomobject]@{ Known = $false; Type = 'Boolean'; Value = $null } }
        if ($Node.Left.Type -eq 'Boolean') { $a = [bool]$left.Value; $b = [bool]$right.Value }
        else { $a = [long]$left.Value; $b = [long]$right.Value }
        switch ($Node.Operator) {
            '<'  { $result = ($a -lt $b) }
            '>'  { $result = ($a -gt $b) }
            '<=' { $result = ($a -le $b) }
            '>=' { $result = ($a -ge $b) }
            '==' { $result = ($a -eq $b) }
            '!=' { $result = ($a -ne $b) }
            default { Throw-SourceError -Line $Node.Line -Column $Node.Column -Message ("Unsupported comparison operator '{0}'." -f $Node.Operator) }
        }
        return [pscustomobject]@{ Known = $true; Type = 'Boolean'; Value = [bool]$result }
    }
    if ($Node.Kind -eq 'Binary') {
        $left = Get-ConstantValue -Node $Node.Left
        $right = Get-ConstantValue -Node $Node.Right
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
            if (@('print', 'let', 'fn', 'return', 'import', 'if', 'else', 'while', 'true', 'false', 'break', 'continue') -contains $name) { $script:SourceDisplay = $Module.Path; Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message 'Reserved keyword cannot be used as a function name.' }
            if ($i -ge $tokens.Length -or $tokens[$i].Text -cne '(') { $script:SourceDisplay = $Module.Path; Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message "Expected '(' after function name." }; $i++
            $params = [System.Collections.Generic.List[object]]::new(); $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            if ($i -lt $tokens.Length -and $tokens[$i].Text -cne ')') {
                while ($true) {
                    if ($i -ge $tokens.Length -or $tokens[$i].Kind -ne 'Identifier') { $script:SourceDisplay = $Module.Path; $cur = $tokens[[Math]::Min($i, $tokens.Length - 1)]; Throw-SourceError -Line $cur.Line -Column $cur.Column -Message 'Expected a parameter name.' }
                    $paramToken = $tokens[$i]
                    if (@('print', 'let', 'fn', 'return', 'import', 'if', 'else', 'while', 'true', 'false', 'break', 'continue') -contains $paramToken.Text) { $script:SourceDisplay = $Module.Path; Throw-SourceError -Line $paramToken.Line -Column $paramToken.Column -Message 'Reserved keyword cannot be used as a parameter name.' }
                    if (-not $seen.Add([string]$paramToken.Text)) { $script:SourceDisplay = $Module.Path; Throw-SourceError -Line $paramToken.Line -Column $paramToken.Column -Message ("Duplicate parameter '{0}'." -f $paramToken.Text) }
                    $params.Add($paramToken); $i++
                    if ($i -lt $tokens.Length -and $tokens[$i].Text -ceq ',') { $i++; continue }; break
                }
            }
            if ($i -ge $tokens.Length -or $tokens[$i].Text -cne ')') { $script:SourceDisplay = $Module.Path; Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message "Expected ')' after function parameters." }; $i++
            if ($params.Count -gt 4) { $script:SourceDisplay = $Module.Path; Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message 'Sharnou functions currently support at most four integer parameters (Windows x64 register arguments).'
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
        if (@('Integer', 'Boolean') -notcontains $condition.Type) { Throw-SourceError -Line $token.Line -Column $token.Column -Message 'if condition must be an integer or Boolean expression.' }
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
        if (@('Integer', 'Boolean') -notcontains $condition.Type) { Throw-SourceError -Line $token.Line -Column $token.Column -Message 'while condition must be an integer or Boolean expression.' }
        Validate-ConstantArithmetic -Node $condition
        $null = Expect-Text -Text ')' -Description "')' after while condition"
        $script:LoopDepth++
        $body = Parse-BlockStatement
        $script:LoopDepth--
        return (New-Statement -Kind 'While' -Expression $condition -Statements @($body.Statements) -Line $token.Line -Column $token.Column)
    }
    if ($token.Text -ceq 'break' -or $token.Text -ceq 'continue') {
        if ($script:LoopDepth -le 0) { Throw-SourceError -Line $token.Line -Column $token.Column -Message ("'{0}' is only valid inside a while loop." -f $token.Text) }
        Move-NextToken | Out-Null
        $null = Expect-Text -Text ';' -Description "';' after loop-control statement"
        if ($token.Text -ceq 'break') { return (New-Statement -Kind 'Break' -Line $token.Line -Column $token.Column) }
        return (New-Statement -Kind 'Continue' -Line $token.Line -Column $token.Column)
    }
    if ($token.Text -ceq 'print') {
        Move-NextToken | Out-Null; $null = Expect-Text -Text '(' -Description "'(' after print"; $expression = Parse-Expression; Validate-ConstantArithmetic -Node $expression; $null = Expect-Text -Text ')' -Description "')' after print expression"; $null = Expect-Text -Text ';' -Description "';' after print statement"
        return (New-Statement -Kind 'Print' -Expression $expression -Line $token.Line -Column $token.Column)
    }
    if ($token.Text -ceq 'let') {
        Move-NextToken | Out-Null; $nameToken = Get-CurrentToken
        if ($nameToken.Kind -ne 'Identifier' -or @('print', 'let', 'fn', 'return', 'import', 'if', 'else', 'while', 'true', 'false', 'break', 'continue') -contains $nameToken.Text) { Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message "Expected a variable name after 'let'." }
        Move-NextToken | Out-Null; $name = [string]$nameToken.Text
        $declaredType = $null
        if (Test-CurrentText ':') {
            Move-NextToken | Out-Null
            $typeToken = Get-CurrentToken
            $declaredType = Resolve-PrimitiveType -Token $typeToken
            Move-NextToken | Out-Null
        }
        $null = Expect-Text -Text '=' -Description "'=' in variable declaration"
        $expression = Parse-Expression; Validate-ConstantArithmetic -Node $expression; $null = Expect-Text -Text ';' -Description "';' after variable declaration"
        if ($null -ne $declaredType -and $expression.Type -ne $declaredType) {
            Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message ("Variable '{0}' is declared as {1}, but its initializer has type {2}." -f $name, $declaredType, $expression.Type)
        }
        $variableType = if ($null -ne $declaredType) { [string]$declaredType } else { [string]$expression.Type }
        $symbol = Declare-Variable -Name $name -Type $variableType -Line $nameToken.Line -Column $nameToken.Column
        return (New-Statement -Kind 'Let' -Name $name -Type $symbol.Type -Slot $symbol.Slot -Expression $expression -Line $nameToken.Line -Column $nameToken.Column)
    }
    if ($token.Text -ceq 'return') {
        if ($null -eq $script:CurrentFunction) { Throw-SourceError -Line $token.Line -Column $token.Column -Message 'return is only valid inside a function.' }
        Move-NextToken | Out-Null; $expression = Parse-Expression; Validate-ConstantArithmetic -Node $expression
        if ($expression.Type -ne 'Integer') { Throw-SourceError -Line $token.Line -Column $token.Column -Message 'Function return values must be integers in the current language subset.' }
        $null = Expect-Text -Text ';' -Description "';' after return statement"
        return (New-Statement -Kind 'Return' -Expression $expression -Line $token.Line -Column $token.Column)
    }
    if (@('print', 'let', 'fn', 'return', 'import', 'if', 'else', 'while', 'true', 'false', 'break', 'continue') -contains $token.Text) { Throw-SourceError -Line $token.Line -Column $token.Column -Message 'Reserved keyword cannot be used as a variable name.' }
    $nameToken = Move-NextToken; $name = [string]$nameToken.Text
    if (-not (Test-CurrentText '=')) { $next = Get-CurrentToken; Throw-SourceError -Line $next.Line -Column $next.Column -Message ("Expected '=' after variable name '{0}'; only assignment, declarations, and print statements are supported." -f $name) }
    $symbol = Find-Variable -Name $name
    if ($null -eq $symbol) { Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message ("Cannot assign to undefined variable '{0}'. Use let to declare it first." -f $name) }
    Move-NextToken | Out-Null; $expression = Parse-Expression; Validate-ConstantArithmetic -Node $expression; $null = Expect-Text -Text ';' -Description "';' after assignment"
    if ($symbol.Type -ne $expression.Type) { Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message ("Assignment changes variable '{0}' from {1} to {2}; variable types are fixed after declaration." -f $name, $symbol.Type, $expression.Type) }
    return (New-Statement -Kind 'Assign' -Name $name -Type $symbol.Type -Slot $symbol.Slot -Expression $expression -Line $nameToken.Line -Column $nameToken.Column)
}
function Test-StatementsAlwaysReturn {
    param([object[]] $Statements)
    foreach ($statement in $Statements) {
        if ($statement.Kind -eq 'Return') { return $true }
        if ($statement.Kind -eq 'Block' -and (Test-StatementsAlwaysReturn -Statements $statement.Statements)) { return $true }
        if ($statement.Kind -eq 'If' -and $statement.ElseStatements.Count -gt 0 -and
            (Test-StatementsAlwaysReturn -Statements $statement.Statements) -and
            (Test-StatementsAlwaysReturn -Statements $statement.ElseStatements)) { return $true }
    }
    return $false
}
function Parse-FunctionDeclaration {
    $oldScopes = $script:Scopes; $oldContext = $script:ActiveContext; $oldFunction = $script:CurrentFunction; $oldBlockDepth = $script:BlockDepth; $oldLoopDepth = $script:LoopDepth
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
    $script:Scopes = [System.Collections.Generic.List[object]]::new(); Push-Scope; $script:BlockDepth = 0; $script:LoopDepth = 0; $script:CurrentFunction = $func
    $context = [pscustomobject]@{ Name = $name; SlotCount = 0; TempSlots = 0; ScratchPosition = 0; FrameSize = 0; Statements = [System.Collections.Generic.List[object]]::new() }
    $script:ActiveContext = $context
    for ($i = 0; $i -lt $paramNames.Count; $i++) {
        $pt = $func.Parameters[$i]
        $symbol = Declare-Variable -Name $paramNames[$i] -Type 'Integer' -Line $pt.Line -Column $pt.Column
        if ($symbol.Slot -ne $i) { throw 'Internal parameter slot assignment error.' }
    }
    while (-not (Test-CurrentText '}')) {
        $current = Get-CurrentToken
        if ($current.Kind -eq 'EOF') { Throw-SourceError -Line $open.Line -Column $open.Column -Message 'Unterminated function body; expected }.' }
        $context.Statements.Add((Parse-Statement))
    }
    $null = Expect-Text -Text '}' -Description "'}' after function body"
    if (-not (Test-StatementsAlwaysReturn -Statements $context.Statements.ToArray())) {
        Throw-SourceError -Line $nameToken.Line -Column $nameToken.Column -Message ("Function '{0}' must return an integer on every control-flow path." -f $name)
    }
    $func.Context = $context; $func.BodyStatements = $context.Statements.ToArray(); $func.ReturnExpression = $null
    $script:Scopes = $oldScopes; $script:ActiveContext = $oldContext; $script:CurrentFunction = $oldFunction; $script:BlockDepth = $oldBlockDepth; $script:LoopDepth = $oldLoopDepth
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
    if ($Node.Kind -eq 'Binary' -or $Node.Kind -eq 'Comparison' -or $Node.Kind -eq 'Logical') { $count += (Get-ExpressionNodeCount -Node $Node.Left); $count += (Get-ExpressionNodeCount -Node $Node.Right) }
    elseif ($Node.Kind -eq 'Unary' -or $Node.Kind -eq 'Not') { $count += (Get-ExpressionNodeCount -Node $Node.Operand) }
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
function Get-TempSlotPosition {
    param([int] $Depth)
    return [int](0x80 + ([int]$script:ActiveContext.SlotCount * 16) + ($Depth * 16))
}
function Emit-CreateFileForPath {
    param([int] $PathSlot)
    Emit-LoadRaxFrame -SlotPosition $PathSlot
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC1)) # RCX = path
    Emit-Bytes -Bytes ([byte[]]@(0xBA, 0x00, 0x00, 0x00, 0x80)) # GENERIC_READ
    Emit-Bytes -Bytes ([byte[]]@(0x41, 0xB8, 0x01, 0x00, 0x00, 0x00)) # FILE_SHARE_READ
    Emit-Bytes -Bytes ([byte[]]@(0x45, 0x33, 0xC9)) # lpSecurityAttributes = NULL
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x40))
    Emit-StackArgumentImmediate -Offset 0x20 -Value 3 # OPEN_EXISTING
    Emit-StackArgumentImmediate -Offset 0x28 -Value 0x80 # FILE_ATTRIBUTE_NORMAL
    Emit-StackArgumentImmediate -Offset 0x30 -Value 0
    Emit-CallIat -TargetRva ([UInt32]0x30A0) # CreateFileA
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x40))
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
function Emit-BuiltinCall {
    param([object] $Node)
    $baseDepth = [int]$script:TempDepth
    $argSlots = [System.Collections.Generic.List[int]]::new()
    switch ($Node.Builtin) {
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
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x30)); Emit-StackArgumentImmediate -Offset 0x20 -Value 0
            Emit-CallIat -TargetRva ([UInt32]0x30B0) # ReadFile
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x30)); Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failRead
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
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x30)); Emit-StackArgumentImmediate -Offset 0x20 -Value 0
            Emit-CallIat -TargetRva ([UInt32]0x30B0) # ReadFile
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x30)); Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failRead
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
        'WindowProbe' {
            $titleSlot = $argSlots[0]; $instanceSlot = Get-TempSlotPosition -Depth ($baseDepth + 1); $windowSlot = Get-TempSlotPosition -Depth ($baseDepth + 2)
            $failLabel = New-UniqueLabel -Prefix 'window_create_fail'; $doneLabel = New-UniqueLabel -Prefix 'window_create_done'
            Emit-Bytes -Bytes ([byte[]]@(0x33, 0xC9)); Emit-CallIat -TargetRva ([UInt32]0x30C0) # GetModuleHandleA(NULL)
            Emit-StoreRaxFrame -SlotPosition $instanceSlot
            Emit-Bytes -Bytes ([byte[]]@(0x33, 0xC9)); Emit-DataAddress -DataItem (Register-DataConstant -Value 'STATIC'); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xC2)) # class name -> RDX
            Emit-LoadRaxFrame -SlotPosition $titleSlot; Emit-Bytes -Bytes ([byte[]]@(0x49, 0x89, 0xC0)) # title -> R8
            Emit-Bytes -Bytes ([byte[]]@(0x41, 0xB9, 0x00, 0x00, 0xCF, 0x00)) # hidden WS_OVERLAPPEDWINDOW
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x60))
            Emit-StackArgumentImmediate -Offset 0x20 -Value -2147483648; Emit-StackArgumentImmediate -Offset 0x28 -Value -2147483648
            Emit-StackArgumentImmediate -Offset 0x30 -Value 320; Emit-StackArgumentImmediate -Offset 0x38 -Value 240
            Emit-StackArgumentImmediate -Offset 0x40 -Value 0; Emit-StackArgumentImmediate -Offset 0x48 -Value 0
            Emit-LoadRaxFrame -SlotPosition $instanceSlot; Emit-StackArgumentRax -Offset 0x50; Emit-StackArgumentImmediate -Offset 0x58 -Value 0
            Emit-CallIat -TargetRva ([UInt32]0x30F0) # CreateWindowExA
            Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x60)); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failLabel
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
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x30)); Emit-StackArgumentImmediate -Offset 0x20 -Value 1
    Emit-CallIat -TargetRva ([UInt32]0x3108) # PeekMessageA
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x30)); Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $noneLabel
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
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x30)); Emit-StackArgumentImmediate -Offset 0x20 -Value 1
    Emit-CallIat -TargetRva ([UInt32]0x3108)
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x30)); Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $checkWindow
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
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x60))
    Emit-StackArgumentImmediate -Offset 0x20 -Value -2147483648
    Emit-StackArgumentImmediate -Offset 0x28 -Value -2147483648
    Emit-StackArgumentImmediate -Offset 0x30 -Value 960
    Emit-StackArgumentImmediate -Offset 0x38 -Value 540
    Emit-StackArgumentImmediate -Offset 0x40 -Value 0
    Emit-StackArgumentImmediate -Offset 0x48 -Value 0
    Emit-LoadRaxFrame -SlotPosition ($scratch + 0xD0); Emit-StackArgumentRax -Offset 0x50
    Emit-StackArgumentImmediate -Offset 0x58 -Value 0
    Emit-CallIat -TargetRva ([UInt32]0x30F0)
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x60)); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failLabel
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
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x60))
    Emit-StackArgumentImmediate -Offset 0x20 -Value 0
    Emit-StackArgumentImmediate -Offset 0x28 -Value 0
    Emit-StackArgumentImmediate -Offset 0x30 -Value 7
    Emit-LeaRaxFrame -SlotPosition $scratch; Emit-StackArgumentRax -Offset 0x38
    Emit-LeaRaxFrame -SlotPosition $swapSlot; Emit-StackArgumentRax -Offset 0x40
    Emit-LeaRaxFrame -SlotPosition $deviceSlot; Emit-StackArgumentRax -Offset 0x48
    Emit-LeaRaxFrame -SlotPosition $featureSlot; Emit-StackArgumentRax -Offset 0x50
    Emit-LeaRaxFrame -SlotPosition $contextSlot; Emit-StackArgumentRax -Offset 0x58
    Emit-CallIat -TargetRva ([UInt32]0x3130)
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x60)); Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x89 -Label $deviceCreated
    Mark-CodeLabel -Label $hardwareFailed
    # Retry using the built-in WARP software rasterizer when hardware initialization fails.
    foreach ($slot in @($swapSlot, $deviceSlot, $contextSlot)) { Emit-StoreZero64Frame -SlotPosition $slot }
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xC9, 0xBA, 0x05, 0x00, 0x00, 0x00, 0x45, 0x33, 0xC0, 0x45, 0x33, 0xC9))
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x60))
    Emit-StackArgumentImmediate -Offset 0x20 -Value 0
    Emit-StackArgumentImmediate -Offset 0x28 -Value 0
    Emit-StackArgumentImmediate -Offset 0x30 -Value 7
    Emit-LeaRaxFrame -SlotPosition $scratch; Emit-StackArgumentRax -Offset 0x38
    Emit-LeaRaxFrame -SlotPosition $swapSlot; Emit-StackArgumentRax -Offset 0x40
    Emit-LeaRaxFrame -SlotPosition $deviceSlot; Emit-StackArgumentRax -Offset 0x48
    Emit-LeaRaxFrame -SlotPosition $featureSlot; Emit-StackArgumentRax -Offset 0x50
    Emit-LeaRaxFrame -SlotPosition $contextSlot; Emit-StackArgumentRax -Offset 0x58
    Emit-CallIat -TargetRva ([UInt32]0x3130)
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x60)); Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x88 -Label $failLabel
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
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x30)); Emit-StackArgumentImmediate -Offset 0x20 -Value 0
    Emit-CallIat -TargetRva ([UInt32]0x3078); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x30))
    Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $failLabel
    Emit-LoadEaxFrame -SlotPosition $bytesWrittenSlot; Emit-Bytes -Bytes ([byte[]]@(0x3B, 0x85)); Emit-I32 -Value (Get-FrameDisp -SlotPosition $formatLengthSlot); Emit-JumpConditional -ConditionCode 0x85 -Label $failLabel
    Emit-LoadEaxFrame -SlotPosition $frameCountSlot
}
function Emit-ThreadSyncCore {
    param([int] $BaseDepth)
    $threadSlot = Get-TempSlotPosition -Depth $BaseDepth; $mutexSlot = Get-TempSlotPosition -Depth ($BaseDepth + 1)
    $threadFail = New-UniqueLabel -Prefix 'thread_sync_thread_fail'; $mutexFail = New-UniqueLabel -Prefix 'thread_sync_mutex_fail'; $mutexWaitFail = New-UniqueLabel -Prefix 'thread_sync_mutex_wait_fail'; $releaseFail = New-UniqueLabel -Prefix 'thread_sync_release_fail'; $done = New-UniqueLabel -Prefix 'thread_sync_done'
    Emit-Bytes -Bytes ([byte[]]@(0x33, 0xC9, 0x33, 0xD2)); Emit-LeaR8CodeLabel -Label '__sharnou_worker'; Emit-Bytes -Bytes ([byte[]]@(0x45, 0x33, 0xC9))
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xEC, 0x30)); Emit-StackArgumentImmediate -Offset 0x20 -Value 0
    Emit-LeaRaxFrame -SlotPosition $script:ActiveContext.ScratchPosition; Emit-StackArgumentRax -Offset 0x28
    Emit-CallIat -TargetRva ([UInt32]0x30C8) # CreateThread
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x30)); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label $threadFail
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
        'Boolean' { Emit-Bytes -Bytes ([byte[]]@(0xB8)); if ([bool]$Node.Value) { Emit-I32 -Value 1 } else { Emit-I32 -Value 0 }; return }
        'Variable' {
            if (@('Integer', 'Boolean') -notcontains $Node.Type) { Throw-SourceError -Line $Node.Line -Column $Node.Column -Message 'Internal type error: integer or Boolean expression expected.' }
            Emit-LoadEaxFrame -SlotPosition (0x80 + ([int]$Node.Slot * 16)); return
        }
        'Unary' { Emit-IntegerExpression -Node $Node.Operand; if ($Node.Operator -eq '-') { Emit-Bytes -Bytes ([byte[]]@(0xF7, 0xD8)); Emit-JumpConditional -ConditionCode 0x80 -Label '__runtime_fail' }; return }
        'Not' {
            Emit-IntegerExpression -Node $Node.Operand
            Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0, 0x0F, 0x94, 0xC0, 0x0F, 0xB6, 0xC0))
            return
        }
        'Logical' {
            $shortLabel = New-UniqueLabel -Prefix 'logical_short'
            $doneLabel = New-UniqueLabel -Prefix 'logical_done'
            Emit-IntegerExpression -Node $Node.Left
            Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
            if ($Node.Operator -eq '&&') {
                Emit-JumpConditional -ConditionCode 0x84 -Label $shortLabel
                Emit-IntegerExpression -Node $Node.Right
                Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
                Emit-JumpConditional -ConditionCode 0x84 -Label $shortLabel
                Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x01, 0x00, 0x00, 0x00))
                Emit-Jump -Label $doneLabel
                Mark-CodeLabel -Label $shortLabel
                Emit-Bytes -Bytes ([byte[]]@(0x31, 0xC0))
                Mark-CodeLabel -Label $doneLabel
            } elseif ($Node.Operator -eq '||') {
                Emit-JumpConditional -ConditionCode 0x85 -Label $shortLabel
                Emit-IntegerExpression -Node $Node.Right
                Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0))
                Emit-JumpConditional -ConditionCode 0x85 -Label $shortLabel
                Emit-Bytes -Bytes ([byte[]]@(0x31, 0xC0))
                Emit-Jump -Label $doneLabel
                Mark-CodeLabel -Label $shortLabel
                Emit-Bytes -Bytes ([byte[]]@(0xB8, 0x01, 0x00, 0x00, 0x00))
                Mark-CodeLabel -Label $doneLabel
            } else {
                Throw-SourceError -Line $Node.Line -Column $Node.Column -Message ("Unsupported logical operator '{0}'." -f $Node.Operator)
            }
            return
        }
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
            for ($i = 0; $i -lt $Node.Arguments.Count; $i++) {
                Emit-IntegerExpression -Node $Node.Arguments[$i]
                Emit-StoreEaxFrame -SlotPosition (Get-TempSlotPosition -Depth $script:TempDepth)
                $script:TempDepth++
            }
            for ($i = 0; $i -lt $Node.Arguments.Count; $i++) {
                Emit-LoadEaxFrame -SlotPosition (Get-TempSlotPosition -Depth ($baseDepth + $i))
                switch ($i) {
                    0 { Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC1)) }
                    1 { Emit-Bytes -Bytes ([byte[]]@(0x89, 0xC2)) }
                    2 { Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC0)) }
                    3 { Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC1)) }
                }
            }
            Emit-CallFunction -Name $Node.Name
            $script:TempDepth -= $Node.Arguments.Count
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
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0xC7, 0x44, 0x24, 0x20, 0, 0, 0, 0)); Emit-CallIat -TargetRva ([UInt32]0x3078)
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
    Emit-LoadRcxFrame -SlotPosition 0x78; Emit-LeaRdxFrame -SlotPosition 0x30; Emit-LoadEaxFrame -SlotPosition 0x74; Emit-Bytes -Bytes ([byte[]]@(0x83, 0xC0, 0x02)); Emit-Bytes -Bytes ([byte[]]@(0x41, 0x89, 0xC0)); Emit-LeaR9Frame -SlotPosition 0x70; Emit-Bytes -Bytes ([byte[]]@(0x48, 0xC7, 0x44, 0x24, 0x20, 0, 0, 0, 0)); Emit-CallIat -TargetRva ([UInt32]0x3078); Emit-Bytes -Bytes ([byte[]]@(0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label '__runtime_fail'
}
function Emit-Statement {
    param([object] $Statement)
    switch ($Statement.Kind) {
        'Let' {
            if ($Statement.Type -eq 'String') { Emit-StringExpression -Node $Statement.Expression; $slot = 0x80 + ([int]$Statement.Slot * 16); Emit-StoreRaxFrame -SlotPosition $slot; Emit-StoreEdxFrame -SlotPosition ($slot + 8) }
            else { Emit-IntegerExpression -Node $Statement.Expression; Emit-StoreEaxFrame -SlotPosition (0x80 + ([int]$Statement.Slot * 16)) }
            return
        }
        'Assign' {
            if ($Statement.Type -eq 'String') { Emit-StringExpression -Node $Statement.Expression; $slot = 0x80 + ([int]$Statement.Slot * 16); Emit-StoreRaxFrame -SlotPosition $slot; Emit-StoreEdxFrame -SlotPosition ($slot + 8) }
            else { Emit-IntegerExpression -Node $Statement.Expression; Emit-StoreEaxFrame -SlotPosition (0x80 + ([int]$Statement.Slot * 16)) }
            return
        }
        'Print' { if ($Statement.Expression.Type -eq 'String') { Emit-PrintString -Node $Statement.Expression } else { Emit-PrintInteger -Node $Statement.Expression }; return }
        'Return' {
            Emit-IntegerExpression -Node $Statement.Expression
            Emit-Epilogue
            return
        }
        'Break' {
            if ($script:EmitLoopStack.Count -le 0) { throw 'Internal code-generation error: break has no active loop target.' }
            Emit-Jump -Label $script:EmitLoopStack[$script:EmitLoopStack.Count - 1].Done
            return
        }
        'Continue' {
            if ($script:EmitLoopStack.Count -le 0) { throw 'Internal code-generation error: continue has no active loop target.' }
            Emit-Jump -Label $script:EmitLoopStack[$script:EmitLoopStack.Count - 1].Start
            return
        }
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
            $script:EmitLoopStack.Add([pscustomobject]@{ Start = $loopStart; Done = $loopDone })
            try {
                foreach ($child in $Statement.Statements) { Emit-Statement -Statement $child }
            } finally {
                $script:EmitLoopStack.RemoveAt($script:EmitLoopStack.Count - 1)
            }
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
function Emit-Prologue {
    param([object] $Context, [object] $Function = $null)
    $script:ActiveContext = $Context; $script:TempDepth = 0
    Emit-Bytes -Bytes ([byte[]]@(0x55, 0x48, 0x89, 0xE5, 0x48, 0x81, 0xEC)); Emit-I32 -Value $Context.FrameSize
    if ($null -ne $Function) {
        for ($i = 0; $i -lt $Function.Parameters.Count; $i++) {
            $slotPosition = 0x80 + ($i * 16)
            switch ($i) {
                0 { Emit-StoreEcxFrame -SlotPosition $slotPosition }
                1 { Emit-StoreEdxFrame -SlotPosition $slotPosition }
                2 { Emit-StoreR8dFrame -SlotPosition $slotPosition }
                3 { Emit-StoreR9dFrame -SlotPosition $slotPosition }
            }
        }
    }
    Emit-Bytes -Bytes ([byte[]]@(0xB9, 0xF5, 0xFF, 0xFF, 0xFF, 0x48, 0x83, 0xEC, 0x20)); Emit-CallIat -TargetRva ([UInt32]0x3070); Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xC4, 0x20))
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x85, 0xC0)); Emit-JumpConditional -ConditionCode 0x84 -Label '__runtime_fail'
    Emit-Bytes -Bytes ([byte[]]@(0x48, 0x83, 0xF8, 0xFF)); Emit-JumpConditional -ConditionCode 0x84 -Label '__runtime_fail'
    Emit-StoreRaxFrame -SlotPosition 0x78
}
function Emit-Epilogue { Emit-Bytes -Bytes ([byte[]]@(0x48, 0x89, 0xEC, 0x5D, 0xC3)) }
function Test-ImageBasic {
    param([byte[]] $Image)
    if ($Image.Length -lt 0x400 -or $Image[0] -ne 0x4D -or $Image[1] -ne 0x5A) { throw 'Internal linker validation: invalid DOS header.' }
    $pe = [BitConverter]::ToInt32($Image, 0x3C)
    if ($pe -lt 0 -or ($pe + 24) -gt $Image.Length -or $Image[$pe] -ne 0x50 -or $Image[$pe + 1] -ne 0x45) { throw 'Internal linker validation: invalid PE header/signature.' }
    if ([BitConverter]::ToUInt16($Image, $pe + 4) -ne 0x8664) { throw 'Internal linker validation: target machine is not AMD64.' }
    if ([BitConverter]::ToUInt16($Image, $pe + 24) -ne 0x020B) { throw 'Internal linker validation: optional header is not PE32+.' }
    $count = [BitConverter]::ToUInt16($Image, $pe + 6); if ($count -ne 4) { throw "Internal linker validation: expected four sections, found $count." }
    $table = $pe + 24 + [BitConverter]::ToUInt16($Image, $pe + 20)
    if (($table + ($count * 40)) -gt [BitConverter]::ToUInt32($Image, $pe + 24 + 60)) { throw 'Internal linker validation: section headers exceed SizeOfHeaders.' }
    $optional = $pe + 24
    $optionalSize = [BitConverter]::ToUInt16($Image, $pe + 20)
    $sectionTable = $optional + $optionalSize
    $relocSectionRva = [UInt32]0
    for ($sectionIndex = 0; $sectionIndex -lt $count; $sectionIndex++) {
        $header = $sectionTable + ($sectionIndex * 40)
        $sectionName = [System.Text.Encoding]::ASCII.GetString($Image, $header, 8).Trim([char[]]@(0))
        if ($sectionName -eq '.reloc') { $relocSectionRva = [BitConverter]::ToUInt32($Image, $header + 12); break }
    }
    $relocRva = [BitConverter]::ToUInt32($Image, $optional + 152); $relocSize = [BitConverter]::ToUInt32($Image, $optional + 156)
    if ($relocSectionRva -eq 0 -or $relocRva -ne $relocSectionRva -or $relocSize -ne 12) { throw 'Internal linker validation: base relocation directory is missing or malformed.' }
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
$script:ActiveContext = $script:MainContext; $script:CurrentFunction = $null; $script:BlockDepth = 0; $script:LoopDepth = 0
foreach ($module in $script:Modules) { Parse-Module -Module $module }

Set-FrameSize -Context $script:MainContext -NodeCount (Get-StatementsNodeCount -Statements $script:MainStatements.ToArray())
foreach ($functionObject in $script:Functions.Values) {
    if ($null -eq $functionObject.Context) { throw "Function '$($functionObject.Name)' was declared but not parsed." }
    Set-FrameSize -Context $functionObject.Context -NodeCount (Get-StatementsNodeCount -Statements $functionObject.BodyStatements)
}

$script:Code = [System.Collections.Generic.List[byte]]::new()
$script:CodeFixups = [System.Collections.Generic.List[object]]::new()
$script:CodeLabels = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::Ordinal)
$script:DataItems = [System.Collections.Generic.List[object]]::new()
$script:DataMap = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
$script:DataLength = 8 # reserved absolute entry-point anchor, patched by the base-relocation directory
$script:UniqueLabel = 0
$script:EmitLoopStack = [System.Collections.Generic.List[object]]::new()

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
    Emit-Jump -Label '__runtime_fail'
}
# WINAPI thread callback used by the thread/synchronization smoke-test intrinsic.
Mark-CodeLabel -Label '__sharnou_worker'
Emit-Bytes -Bytes ([byte[]]@(0x31, 0xC0, 0xC3)) # return DWORD 0
$codeBytes = $script:Code.ToArray()
if ($codeBytes.Length -le 0) { throw 'Generated .text section is empty.' }
if ($codeBytes.Length -gt 0x01000000) { throw "Generated .text section is too large: $($codeBytes.Length) bytes; maximum is 16777216." }

# Size each virtual section to a full 4 KiB page and place later sections after it.
# This keeps the legacy RVAs for small code while allowing .text to grow beyond 4096 bytes.
$textRva = [UInt32]0x1000
$textVirtualSpan = Align-Up -Value $codeBytes.Length -Alignment 0x1000
if ($script:DataLength -gt 0x1000) { throw "Generated .rdata section is too large: $($script:DataLength) bytes; maximum is 4096." }
$dataVirtualSpan = Align-Up -Value ([Math]::Max(8, $script:DataLength)) -Alignment 0x1000
$idataVirtualSpan = Align-Up -Value 0x800 -Alignment 0x1000
$relocVirtualSpan = Align-Up -Value 12 -Alignment 0x1000
$dataRva = [UInt32]([long]$textRva + [long]$textVirtualSpan)
$idataRva = [UInt32]([long]$dataRva + [long]$dataVirtualSpan)
$relocRva = [UInt32]([long]$idataRva + [long]$idataVirtualSpan)
$sizeOfImage = [UInt32]([long]$relocRva + [long]$relocVirtualSpan)
if ([UInt64]$sizeOfImage -gt [UInt32]::MaxValue) { throw 'Linked image exceeds the PE32+ 32-bit RVA address space.' }

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
foreach ($item in $script:DataItems) { if ($item.Bytes.Length -gt 0) { Set-Bytes -Buffer $dataBytes -Offset $item.Offset -Bytes $item.Bytes } }

# Dynamically sized RVA layout and independently aligned raw file layout: .text/.rdata/.idata/.reloc.
$textRawSize = Align-Up -Value $codeBytes.Length -Alignment 0x200
$dataRawSize = Align-Up -Value $dataBytes.Length -Alignment 0x200
# Milestone 5 import builder. Existing IAT offsets (0x70, 0x78, 0x80, and 0x90)
# stay stable within .idata. Lookup tables use the disjoint 0x500-0x610 range;
# no lookup table may overlap any IAT slot or import-by-name string. Emit-CallIat rebases target RVAs after section placement.
$idata = [byte[]]::new(0x800)
# Keep the eight 20-byte IMAGE_IMPORT_DESCRIPTOR rows and null terminator above 0x700.
# The fixed IAT slots occupy 0x70..0x178, so descriptor storage must not overlap them.
$descriptorBase = 0x700
$importDirectorySize = 0xB4
if (($descriptorBase + $importDirectorySize) -gt $idata.Length) { throw 'Import descriptor table exceeds .idata storage.' }
$importSets = @(
    [pscustomobject]@{ Descriptor = 0x00; Lookup = 0x500; Iat = 0x70; Dll = 'KERNEL32.dll'; Names = @('GetStdHandle', 'WriteFile', 'ExitProcess') },
    [pscustomobject]@{ Descriptor = 0x14; Lookup = 0x520; Iat = 0x90; Dll = 'USER32.dll'; Names = @('wsprintfA') },
    [pscustomobject]@{ Descriptor = 0x28; Lookup = 0x530; Iat = 0xA0; Dll = 'KERNEL32.dll'; Names = @('CreateFileA', 'GetFileSizeEx', 'ReadFile', 'CloseHandle', 'GetModuleHandleA', 'CreateThread', 'WaitForSingleObject', 'CreateMutexA', 'ReleaseMutex') },
    [pscustomobject]@{ Descriptor = 0x3C; Lookup = 0x580; Iat = 0xF0; Dll = 'USER32.dll'; Names = @('CreateWindowExA', 'ShowWindow', 'UpdateWindow', 'PeekMessageA', 'TranslateMessage', 'DispatchMessageA', 'DestroyWindow') },
    [pscustomobject]@{ Descriptor = 0x50; Lookup = 0x5C0; Iat = 0x130; Dll = 'D3D11.dll'; Names = @('D3D11CreateDeviceAndSwapChain') },
    [pscustomobject]@{ Descriptor = 0x64; Lookup = 0x5D0; Iat = 0x140; Dll = 'DXGI.dll'; Names = @('CreateDXGIFactory') },
    [pscustomobject]@{ Descriptor = 0x78; Lookup = 0x5E0; Iat = 0x150; Dll = 'KERNEL32.dll'; Names = @('QueryPerformanceCounter', 'QueryPerformanceFrequency') },
    [pscustomobject]@{ Descriptor = 0x8C; Lookup = 0x600; Iat = 0x168; Dll = 'USER32.dll'; Names = @('IsWindow') }
)
$apiNameRvas = @{}
$nameCursor = 0x280
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
Set-AsciiZ -Buffer $idata -Offset 0x250 -Value 'KERNEL32.dll'
Set-AsciiZ -Buffer $idata -Offset 0x25D -Value 'USER32.dll'
Set-AsciiZ -Buffer $idata -Offset 0x268 -Value 'D3D11.dll'
Set-AsciiZ -Buffer $idata -Offset 0x272 -Value 'DXGI.dll'
foreach ($set in $importSets) {
    switch ($set.Dll) {
        'KERNEL32.dll' { $nameOffset = 0x250 }
        'USER32.dll' { $nameOffset = 0x25D }
        'D3D11.dll' { $nameOffset = 0x268 }
        'DXGI.dll' { $nameOffset = 0x272 }
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
}

# One DIR64 relocation patches the absolute image-base + entry-point pointer at the dynamic .rdata RVA.
$reloc = [byte[]]::new(0x200)
Set-U32 -Buffer $reloc -Offset 0 -Value $dataRva; Set-U32 -Buffer $reloc -Offset 4 -Value 12; Set-U16 -Buffer $reloc -Offset 8 -Value 0xA000; Set-U16 -Buffer $reloc -Offset 10 -Value 0
if ($idata.Length -gt $idataVirtualSpan) { throw 'Generated .idata section exceeds its reserved virtual span.' }
$headersSize = 0x400
$textRawPointer = $headersSize; $dataRawPointer = $textRawPointer + $textRawSize; $idataRawPointer = $dataRawPointer + $dataRawSize; $relocRawPointer = $idataRawPointer + $idata.Length
$totalSize = $relocRawPointer + $reloc.Length
$image = [byte[]]::new($totalSize)
Set-Bytes -Buffer $image -Offset $textRawPointer -Bytes $codeBytes; Set-Bytes -Buffer $image -Offset $dataRawPointer -Bytes $dataBytes; Set-Bytes -Buffer $image -Offset $idataRawPointer -Bytes $idata; Set-Bytes -Buffer $image -Offset $relocRawPointer -Bytes $reloc

# DOS and PE headers.
$image[0] = 0x4D; $image[1] = 0x5A; Set-U32 -Buffer $image -Offset 0x3C -Value 0x80; Set-Ascii -Buffer $image -Offset 0x80 -Value "PE`0`0"
Set-U16 -Buffer $image -Offset 0x84 -Value 0x8664; Set-U16 -Buffer $image -Offset 0x86 -Value 4; Set-U32 -Buffer $image -Offset 0x88 -Value 0; Set-U32 -Buffer $image -Offset 0x8C -Value 0; Set-U32 -Buffer $image -Offset 0x90 -Value 0; Set-U16 -Buffer $image -Offset 0x94 -Value 240; Set-U16 -Buffer $image -Offset 0x96 -Value 0x0022
$opt = 0x98
Set-U16 -Buffer $image -Offset ($opt + 0) -Value 0x020B; $image[$opt + 2] = 1; $image[$opt + 3] = 0
Set-U32 -Buffer $image -Offset ($opt + 4) -Value $textRawSize; Set-U32 -Buffer $image -Offset ($opt + 8) -Value ($dataRawSize + $idata.Length + $reloc.Length); Set-U32 -Buffer $image -Offset ($opt + 12) -Value 0
Set-U32 -Buffer $image -Offset ($opt + 16) -Value $textRva; Set-U32 -Buffer $image -Offset ($opt + 20) -Value $textRva; Set-U64 -Buffer $image -Offset ($opt + 24) -Value ([UInt64]([Int64]0x140000000))
Set-U32 -Buffer $image -Offset ($opt + 32) -Value 0x1000; Set-U32 -Buffer $image -Offset ($opt + 36) -Value 0x200
Set-U16 -Buffer $image -Offset ($opt + 40) -Value 6; Set-U16 -Buffer $image -Offset ($opt + 42) -Value 0; Set-U16 -Buffer $image -Offset ($opt + 44) -Value 0; Set-U16 -Buffer $image -Offset ($opt + 46) -Value 0; Set-U16 -Buffer $image -Offset ($opt + 48) -Value 6; Set-U16 -Buffer $image -Offset ($opt + 50) -Value 0
Set-U32 -Buffer $image -Offset ($opt + 52) -Value 0; Set-U32 -Buffer $image -Offset ($opt + 56) -Value $sizeOfImage; Set-U32 -Buffer $image -Offset ($opt + 60) -Value $headersSize; Set-U32 -Buffer $image -Offset ($opt + 64) -Value 0
Set-U16 -Buffer $image -Offset ($opt + 68) -Value 3; Set-U16 -Buffer $image -Offset ($opt + 70) -Value 0x0140
Set-U64 -Buffer $image -Offset ($opt + 72) -Value ([UInt64]0x100000); Set-U64 -Buffer $image -Offset ($opt + 80) -Value ([UInt64]0x1000); Set-U64 -Buffer $image -Offset ($opt + 88) -Value ([UInt64]0x100000); Set-U64 -Buffer $image -Offset ($opt + 96) -Value ([UInt64]0x1000)
Set-U32 -Buffer $image -Offset ($opt + 104) -Value 0; Set-U32 -Buffer $image -Offset ($opt + 108) -Value 16
Set-U32 -Buffer $image -Offset ($opt + 120) -Value ([UInt32]([long]$idataRva + [long]$descriptorBase)); Set-U32 -Buffer $image -Offset ($opt + 124) -Value $importDirectorySize
Set-U32 -Buffer $image -Offset ($opt + 152) -Value $relocRva; Set-U32 -Buffer $image -Offset ($opt + 156) -Value 12
Set-U32 -Buffer $image -Offset ($opt + 208) -Value ([UInt32]([long]$idataRva + 0x70)); Set-U32 -Buffer $image -Offset ($opt + 212) -Value 0x108
$sectionText = 0x188
Set-Ascii -Buffer $image -Offset $sectionText -Value '.text'; Set-U32 -Buffer $image -Offset ($sectionText + 8) -Value $codeBytes.Length; Set-U32 -Buffer $image -Offset ($sectionText + 12) -Value $textRva; Set-U32 -Buffer $image -Offset ($sectionText + 16) -Value $textRawSize; Set-U32 -Buffer $image -Offset ($sectionText + 20) -Value $textRawPointer; Set-U32 -Buffer $image -Offset ($sectionText + 36) -Value 0x60000020
$sectionData = 0x1B0
Set-Ascii -Buffer $image -Offset $sectionData -Value '.rdata'; Set-U32 -Buffer $image -Offset ($sectionData + 8) -Value $dataBytes.Length; Set-U32 -Buffer $image -Offset ($sectionData + 12) -Value $dataRva; Set-U32 -Buffer $image -Offset ($sectionData + 16) -Value $dataRawSize; Set-U32 -Buffer $image -Offset ($sectionData + 20) -Value $dataRawPointer; Set-U32 -Buffer $image -Offset ($sectionData + 36) -Value 0x40000040
$sectionImport = 0x1D8
Set-Ascii -Buffer $image -Offset $sectionImport -Value '.idata'; Set-U32 -Buffer $image -Offset ($sectionImport + 8) -Value $idata.Length; Set-U32 -Buffer $image -Offset ($sectionImport + 12) -Value $idataRva; Set-U32 -Buffer $image -Offset ($sectionImport + 16) -Value $idata.Length; Set-U32 -Buffer $image -Offset ($sectionImport + 20) -Value $idataRawPointer; Set-U32 -Buffer $image -Offset ($sectionImport + 36) -Value ([UInt32]([Int64]3221225536))
$sectionReloc = 0x200
Set-Ascii -Buffer $image -Offset $sectionReloc -Value '.reloc'; Set-U32 -Buffer $image -Offset ($sectionReloc + 8) -Value 12; Set-U32 -Buffer $image -Offset ($sectionReloc + 12) -Value $relocRva; Set-U32 -Buffer $image -Offset ($sectionReloc + 16) -Value $reloc.Length; Set-U32 -Buffer $image -Offset ($sectionReloc + 20) -Value $relocRawPointer; Set-U32 -Buffer $image -Offset ($sectionReloc + 36) -Value 0x42000040
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
Write-Host 'Sections: .text, .rdata, .idata, .reloc; imports: KERNEL32.dll, USER32.dll, D3D11.dll, and DXGI.dll'
Write-Host "SHA-256: $sha256"
Write-Warning 'Milestone 6 adds a native D3D11/DXGI solid-clear demo and runtime frame timing. Native rendering must be validated on an interactive Windows desktop. Shader/geometry rendering, device-loss recovery, resize handling, and persistent window/event loops remain unsupported.' 
