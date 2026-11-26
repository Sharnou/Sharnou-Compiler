[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Combined stdout and stderr exceed the broker's 1 MiB ceiling by exactly one byte.
$half = [byte[]]::new(512 * 1024)
$stdout = [Console]::OpenStandardOutput()
$stderr = [Console]::OpenStandardError()
$stdout.Write($half, 0, $half.Length)
$stderr.Write($half, 0, $half.Length)
$stderr.WriteByte(0x41)
$stdout.Flush()
$stderr.Flush()
