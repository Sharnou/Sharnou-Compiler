[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $CandidateDirectory,
    [Parameter(Mandatory = $true)][string] $Tag
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -ne 5 -or [IntPtr]::Size -ne 8) {
    throw 'Release validation requires 64-bit Windows PowerShell 5.1.'
}
$manifestPath = Join-Path $CandidateDirectory 'release-manifest.json'
$changelogPath = Join-Path $CandidateDirectory 'CHANGELOG.md'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Missing manifest: $manifestPath" }
if (-not (Test-Path -LiteralPath $changelogPath -PathType Leaf)) { throw "Missing changelog: $changelogPath" }

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ([string]$manifest.release_tag -cne $Tag) { throw 'Manifest tag does not match requested release tag.' }
$zipPath = Join-Path $CandidateDirectory ([string]$manifest.asset_name)
$shaPath = Join-Path $CandidateDirectory ($manifest.asset_name + '.sha256')
if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) { throw "Release ZIP is missing: $zipPath" }
if (-not (Test-Path -LiteralPath $shaPath -PathType Leaf)) { throw "SHA-256 sidecar is missing: $shaPath" }

$actualHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToUpperInvariant()
$expectedHash = ([string]$manifest.asset_sha256).ToUpperInvariant()
if ($actualHash -cne $expectedHash) { throw "Archive SHA-256 mismatch. Expected $expectedHash; actual $actualHash." }
$sidecar = (Get-Content -LiteralPath $shaPath -Raw).Trim()
$sidecarPattern = '^' + [regex]::Escape($expectedHash) + '\s+' + [regex]::Escape([IO.Path]::GetFileName($zipPath)) + '$'
if ($sidecar -notmatch $sidecarPattern) { throw 'SHA-256 sidecar content does not match the release archive.' }

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    if ($archive.Entries.Count -ne [int]$manifest.archive_entries) {
        throw ("ZIP entry count mismatch. Expected {0}; actual {1}." -f $manifest.archive_entries, $archive.Entries.Count)
    }
    $names = @($archive.Entries | ForEach-Object { $_.FullName })
    foreach ($required in @('Stage0/SharnouCompiler-6A7A-Merged.ps1','R26.0-R2/Test-R26R2.ps1','R26.0-R2/RELEASE-MANIFEST.json')) {
        if ($names -cnotcontains $required) { throw "Required package entry is missing: $required" }
    }
    $entry = $archive.GetEntry([string]$manifest.bootstrap_compiler.path)
    if ($null -eq $entry) { throw 'Frozen bootstrap compiler is missing from archive.' }
    $stream = $entry.Open()
    $memory = New-Object System.IO.MemoryStream
    try {
        $stream.CopyTo($memory)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { $embeddedHash = ([BitConverter]::ToString($sha.ComputeHash($memory.ToArray()))).Replace('-','') }
        finally { $sha.Dispose() }
    }
    finally {
        $stream.Dispose()
        $memory.Dispose()
    }
    if ($embeddedHash -cne ([string]$manifest.bootstrap_compiler.sha256).ToUpperInvariant()) {
        throw "Embedded compiler SHA-256 mismatch: $embeddedHash"
    }
}
finally { $archive.Dispose() }

$extractRoot = Join-Path $env:TEMP ('SharnouCompilerRelease-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $extractRoot -Force | Out-Null
try {
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractRoot -Force
    $runner = Join-Path $extractRoot ([string]$manifest.validation.runner)
    if (-not (Test-Path -LiteralPath $runner -PathType Leaf)) { throw "Validation runner missing after extraction: $runner" }

    $logPath = Join-Path $env:TEMP ($Tag + '-validation-' + [Guid]::NewGuid().ToString('N') + '.log')
    $childPowerShell = Join-Path $PSHOME 'powershell.exe'
    & $childPowerShell -NoProfile -ExecutionPolicy Bypass -File $runner *> $logPath
    $runnerExit = $LASTEXITCODE
    $runnerText = Get-Content -LiteralPath $logPath -Raw
    if ($runnerExit -ne 0) { throw ("Windows validation runner failed with exit code {0}. Log: {1}. Output: {2}" -f $runnerExit, $logPath, $runnerText) }

    foreach ($marker in @($manifest.validation.required_output_markers)) {
        if (-not $runnerText.Contains([string]$marker)) {
            throw "Validation output is missing required PASS marker '$marker'. Log: $logPath"
        }
    }
    Write-Host "PASS: Windows PowerShell 5.1 validation for $Tag." -ForegroundColor Green
    Write-Host "PASS: ZIP SHA-256 $actualHash"
    Write-Host "PASS: ZIP entries $($manifest.archive_entries)"
    Write-Host "PASS: frozen compiler $embeddedHash"
    Write-Host "Validation log: $logPath"
}
finally {
    Remove-Item -LiteralPath $extractRoot -Recurse -Force -ErrorAction SilentlyContinue
}
