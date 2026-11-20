[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptRoot)
$manifestPath = Join-Path $scriptRoot 'manifest.json'
$payloadPath = Join-Path $scriptRoot 'M6-83Cases.payload.json.gz.b64'

$expectedSourceArchiveSha256 = '0b6bf15445a5dfd8cbf93450af7fd2f5fd6239d4ed082ab18b09878a94b8b164'
$expectedBundleSha256 = '3dd1d7417874159c0bc625edbbc1e8cee1ae7d8a6ea42f30b4dd80ba92102748'

function Get-Sha256Hex {
    param([Parameter(Mandatory = $true)][byte[]] $Bytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-FileSha256 {
    param([Parameter(Mandatory = $true)][string] $Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$workRoot = $null
try {
    foreach ($required in @($manifestPath, $payloadPath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Milestone 6 baseline input is missing: $required"
        }
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ([int]$manifest.total_cases -ne 83) {
        throw "Baseline manifest case total must be 83; found $($manifest.total_cases)."
    }
    if ([string]$manifest.source_archive.sha256 -ne $expectedSourceArchiveSha256) {
        throw 'The frozen Milestone 6 source archive identity does not match the approved SHA-256.'
    }
    if ([string]$manifest.bundle.sha256 -ne $expectedBundleSha256) {
        throw 'The Milestone 6 bundle manifest SHA-256 does not match the pinned value.'
    }

    $encodedPayload = (Get-Content -LiteralPath $payloadPath -Raw).Trim()
    $compressedBytes = [Convert]::FromBase64String($encodedPayload)
    $actualBundleSha256 = Get-Sha256Hex -Bytes $compressedBytes
    if ($actualBundleSha256 -ne $expectedBundleSha256) {
        throw "Milestone 6 bundle SHA-256 mismatch. Expected $expectedBundleSha256; received $actualBundleSha256."
    }
    if ($compressedBytes.Length -ne [int]$manifest.bundle.compressed_size_bytes) {
        throw "Milestone 6 bundle size mismatch. Expected $($manifest.bundle.compressed_size_bytes); received $($compressedBytes.Length)."
    }

    $inputStream = [System.IO.MemoryStream]::new($compressedBytes)
    $gzipStream = [System.IO.Compression.GZipStream]::new(
        $inputStream,
        [System.IO.Compression.CompressionMode]::Decompress
    )
    $reader = [System.IO.StreamReader]::new($gzipStream, [System.Text.Encoding]::UTF8)
    try {
        $payloadJson = $reader.ReadToEnd()
    }
    finally {
        $reader.Dispose()
        $gzipStream.Dispose()
        $inputStream.Dispose()
    }

    $payload = $payloadJson | ConvertFrom-Json
    foreach ($fixture in $payload.files) {
        if ([string]$fixture.path -like '*UnsupportedSyntax.sharnou') {
            Write-Host ('Archived unsupported syntax fixture path: ' + $fixture.path)
            Write-Host ('Archived unsupported syntax fixture source: ' + [string]$fixture.content)
        }
    }
    if ($payload.files.Count -ne [int]$manifest.bundle.file_count) {
        throw "Baseline member count mismatch. Expected $($manifest.bundle.file_count); received $($payload.files.Count)."
    }

    $workRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('Sharnou-M6-Baseline-' + [Guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $workRoot -Force
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)

    foreach ($member in $payload.files) {
        $relativePath = [string]$member.path
        if ([System.IO.Path]::IsPathRooted($relativePath) -or $relativePath -match '(^|[\/])\.\.([\/]|$)') {
            throw "Unsafe baseline member path: $relativePath"
        }
        if ($relativePath -notmatch '^(Tests|Examples|StdLib)[\/]') {
            throw "Unexpected baseline member root: $relativePath"
        }

        $destination = Join-Path $workRoot ($relativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
        $destinationDirectory = Split-Path -Parent $destination
        $null = New-Item -ItemType Directory -Path $destinationDirectory -Force
        [System.IO.File]::WriteAllText($destination, [string]$member.content, $utf8NoBom)

        $actualMemberSha256 = Get-FileSha256 -Path $destination
        if ($actualMemberSha256 -ne [string]$member.sha256) {
            throw "Restored baseline member hash mismatch: $relativePath"
        }
    }

    if (-not (Test-Path -LiteralPath (Join-Path $workRoot 'Tests\Test-Stage2.ps1') -PathType Leaf)) {
        throw 'Stage 2 baseline suite was not restored.'
    }

    # Emit the frozen Stage 2 negative-case definition when the historical suite fails.
    # This keeps diagnosis tied to the original archived test instead of guessing from its label.
    $stage2Script = Join-Path $workRoot 'Tests\Test-Stage2.ps1'
    $stage2Source = Get-Content -LiteralPath $stage2Script
    $stage2Structure = Select-String -InputObject $stage2Source -Pattern @('$positiveCases', '$negativeCases', 'Invoke-PositiveCase', 'Invoke-NegativeCase', 'foreach ($case') -SimpleMatch -Context 2, 5
    foreach ($entry in $stage2Structure) {
        Write-Host ('Stage 2 harness structure at line ' + $entry.LineNumber + ':')
        Write-Host ($entry.Context.PreContext -join [Environment]::NewLine)
        Write-Host $entry.Line
        Write-Host ($entry.Context.PostContext -join [Environment]::NewLine)
    }
    $stage2Matches = Select-String -LiteralPath $stage2Script -Pattern 'Unsupported statement syntax' -Context 12, 20
    $stage2Matches = Select-String -LiteralPath $stage2Script -Pattern 'Unsupported statement syntax' -Context 12, 20
    $unsupportedSyntaxPath = Join-Path $workRoot 'Tests\UnsupportedSyntax.sharnou'
    if (Test-Path -LiteralPath $unsupportedSyntaxPath -PathType Leaf) {
        Write-Host 'Archived UnsupportedSyntax.sharnou source:'
        Write-Host (Get-Content -LiteralPath $unsupportedSyntaxPath -Raw)
    }
    foreach ($match in $stage2Matches) {
        Write-Host ('Stage 2 diagnostic context at line ' + $match.LineNumber + ':')
        Write-Host ($match.Context.PreContext -join [Environment]::NewLine)
        Write-Host $match.Line
        Write-Host ($match.Context.PostContext -join [Environment]::NewLine)
    }

    $compilerSource = Join-Path $repoRoot 'Stage0\SharnouCompiler.ps1'
    $verifierSource = Join-Path $repoRoot 'Tools\SharnouPEVerify.ps1'
    foreach ($required in @($compilerSource, $verifierSource)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Current repository tool is missing: $required"
        }
    }

    $compilerDirectory = Join-Path $workRoot 'Stage0'
    $verifierDirectory = Join-Path $workRoot 'Tools'
    $null = New-Item -ItemType Directory -Path $compilerDirectory -Force
    $null = New-Item -ItemType Directory -Path $verifierDirectory -Force
    $compilerPath = Join-Path $compilerDirectory 'SharnouCompiler.ps1'
    $verifierPath = Join-Path $verifierDirectory 'SharnouPEVerify.ps1'
    Copy-Item -LiteralPath $compilerSource -Destination $compilerPath -Force
    Copy-Item -LiteralPath $verifierSource -Destination $verifierPath -Force

    Write-Host ('Current Stage 0 compiler SHA-256: ' + (Get-FileSha256 -Path $compilerSource))
    Write-Host ('Current PE verifier SHA-256: ' + (Get-FileSha256 -Path $verifierSource))
    Write-Host ('Frozen Milestone 6 archive SHA-256: ' + $expectedSourceArchiveSha256)
    Write-Host ('Restored historical suite members: ' + $payload.files.Count)

    $buildDirectory = Join-Path $workRoot 'Build'
    $null = New-Item -ItemType Directory -Path $buildDirectory -Force
    $helloSource = Join-Path $workRoot 'Examples\Hello.sharnou'
    $helloExecutable = Join-Path $buildDirectory 'Hello.exe'
    & $compilerPath -Source $helloSource -Output $helloExecutable
    if (-not (Test-Path -LiteralPath $helloExecutable -PathType Leaf)) {
        throw 'Current compiler did not produce the PE verifier positive-test input.'
    }

    $caseTotal = 0
    foreach ($suite in $manifest.suites) {
        $suitePath = Join-Path $workRoot ([string]$suite.path.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
        if (-not (Test-Path -LiteralPath $suitePath -PathType Leaf)) {
            throw "Historical regression suite is missing: $suitePath"
        }

        Write-Host ''
        Write-Host ('=== Historical baseline suite: ' + $suite.path + ' (' + $suite.cases + ' cases) ===')
        & $suitePath
        if (-not $?) {
            throw "Historical regression suite reported failure: $($suite.path)"
        }
        $caseTotal += [int]$suite.cases
    }

    if ($caseTotal -ne 83) {
        throw "Historical regression accounting mismatch. Expected 83; recorded $caseTotal."
    }
    Write-Host ''
    Write-Host 'Milestone 6 historical regression baseline: PASS (83/83).' -ForegroundColor Green
}
catch {
    Write-Host ('Milestone 6 historical regression baseline: FAIL - ' + $_.Exception.Message) -ForegroundColor Red
    throw
}
finally {
    if ($workRoot -and (Test-Path -LiteralPath $workRoot -PathType Container)) {
        Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

