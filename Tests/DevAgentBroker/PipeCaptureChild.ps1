[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('Streams','Boundary','Flood','Timeout','Descendant')]
    [string]$Mode,
    [Int64]$SentinelHandle = 0,
    [string]$ReportPath = '',
    [string]$PidPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$stdout = [Console]::OpenStandardOutput()
$stderr = [Console]::OpenStandardError()

function Write-ExactBytes {
    param(
        [System.IO.Stream]$Stream,
        [int]$Count,
        [byte]$Value
    )
    $buffer = New-Object byte[] 4096
    for ($i = 0; $i -lt $buffer.Length; $i++) { $buffer[$i] = $Value }
    $remaining = $Count
    while ($remaining -gt 0) {
        $amount = [Math]::Min($remaining,$buffer.Length)
        $Stream.Write($buffer,0,$amount)
        $Stream.Flush()
        $remaining -= $amount
    }
}

function Write-AsciiLine {
    param([System.IO.Stream]$Stream,[string]$Value)
    $bytes = [Text.Encoding]::ASCII.GetBytes($Value + [char]10)
    $Stream.Write($bytes,0,$bytes.Length)
    $Stream.Flush()
}

if ($SentinelHandle -gt 0 -and -not [string]::IsNullOrEmpty($ReportPath)) {
    $status = 'DENIED'
    $probe = $null
    try {
        $probe = [System.IO.FileStream]::new(
            ([IntPtr]([Int64]$SentinelHandle)),
            [System.IO.FileAccess]::Read
        )
        $expectedMarker = [byte[]]@(0x53,0x48,0x41,0x52,0x4E,0x4F,0x55,0x2D,0x42,0x52,0x4F,0x4B,0x45,0x52,0x2D,0x32,0x42,0x2E,0x35,0x2D,0x4E,0x4F,0x2D,0x49,0x4E,0x48,0x45,0x52,0x49,0x54,0x21,0x7F)
        $actualMarker = New-Object byte[] $expectedMarker.Length
        $readCount = $probe.Read($actualMarker,0,$actualMarker.Length)
        if ($readCount -eq $expectedMarker.Length -and
            [Convert]::ToBase64String($actualMarker) -ceq [Convert]::ToBase64String($expectedMarker)) {
            $status = 'INHERITED'
        } else {
            $status = 'UNEXPECTED_VALUE'
        }
    }
    catch {
        $status = 'DENIED'
    }
    finally {
        if ($null -ne $probe) { $probe.Dispose() }
    }
    [IO.File]::WriteAllText($ReportPath,$status,[Text.Encoding]::ASCII)
}

switch ($Mode) {
    'Streams' {
        Write-AsciiLine -Stream $stdout -Value 'stdout-ok'
        Write-AsciiLine -Stream $stderr -Value 'stderr-ok'
    }
    'Boundary' {
        Write-ExactBytes -Stream $stdout -Count 32768 -Value 65
        Write-ExactBytes -Stream $stderr -Count 32768 -Value 66
    }
    'Flood' {
        Write-ExactBytes -Stream $stdout -Count 65536 -Value 67
        Write-ExactBytes -Stream $stderr -Count 65536 -Value 68
    }
    'Timeout' {
        Write-AsciiLine -Stream $stdout -Value 'timeout-started'
        Write-AsciiLine -Stream $stderr -Value 'timeout-stderr'
        Start-Sleep -Seconds 30
    }
    'Descendant' {
        $powershell = Join-Path $PSHOME 'powershell.exe'
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $powershell
        $startInfo.Arguments = '-NoLogo -NoProfile -NonInteractive -Command "Start-Sleep -Seconds 30"'
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $descendant = [Diagnostics.Process]::Start($startInfo)
        if (-not [string]::IsNullOrEmpty($PidPath)) {
            [IO.File]::WriteAllText($PidPath,[string]$descendant.Id,[Text.Encoding]::ASCII)
        }
        Write-AsciiLine -Stream $stdout -Value ('descendant-started:' + $descendant.Id)
        Start-Sleep -Seconds 30
    }
}
