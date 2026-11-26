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

    # Stage 7A now implements if statements, so migrate the historical pre-7A negative case
    # into the positive set without changing the hash-pinned original suite or fixture.
    $stage2OriginalPath = Join-Path $workRoot 'Tests\Test-Stage2.ps1'
    $stage2AdaptedPath = Join-Path $workRoot 'Tests\Test-Stage2-Current.ps1'
    $stage2FixtureSource = Join-Path $workRoot 'Tests\Negative\UnsupportedSyntax.sharnou'
    $stage2PositiveDirectory = Join-Path $workRoot 'Tests\Positive'
    $stage2PositiveFixture = Join-Path $stage2PositiveDirectory 'IfStatementNowSupported.sharnou'
    if (-not (Test-Path -LiteralPath $stage2FixtureSource -PathType Leaf)) {
        throw 'The frozen Stage 2 if-statement compatibility fixture is missing.'
    }
    $stage2Text = [System.IO.File]::ReadAllText($stage2OriginalPath)
    $obsoleteNegativeEntry = "    [pscustomobject]@{ Name = 'Unsupported statement syntax'; File = 'UnsupportedSyntax.sharnou' },"
    $positiveMarker = '$positiveCases = @('
    $currentPositiveEntry = "    [pscustomobject]@{ Name = 'If statement supported by Stage 7A'; File = 'IfStatementNowSupported.sharnou'; Expected = 'unsupported' },"
    if (-not $stage2Text.Contains($obsoleteNegativeEntry) -or -not $stage2Text.Contains($positiveMarker)) {
        throw 'The frozen Stage 2 case layout changed; refusing an unreviewed compatibility rewrite.'
    }
    $stage2Text = $stage2Text.Replace($obsoleteNegativeEntry, '')
    $stage2Text = $stage2Text.Replace($positiveMarker, $positiveMarker + [Environment]::NewLine + $currentPositiveEntry)
    [System.IO.File]::WriteAllText($stage2AdaptedPath, $stage2Text, $utf8NoBom)
    $null = New-Item -ItemType Directory -Path $stage2PositiveDirectory -Force
    Copy-Item -LiteralPath $stage2FixtureSource -Destination $stage2PositiveFixture -Force
    Write-Host 'Compatibility update: the frozen if fixture is now a positive Stage 7A case; the archived payload and original test script remain unchanged.'

    $compilerSource = Join-Path $repoRoot 'Stage0\SharnouCompiler.ps1'
    $verifierSource = Join-Path $repoRoot 'Tools\SharnouPEVerify.ps1'
    $graphicsSource = Join-Path $repoRoot 'StdLib\Graphics.sharnou'
    foreach ($required in @($compilerSource, $verifierSource, $graphicsSource)) {
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
    $stdLibDirectory = Join-Path $workRoot 'StdLib'
    $null = New-Item -ItemType Directory -Path $stdLibDirectory -Force
    Copy-Item -LiteralPath $graphicsSource -Destination (Join-Path $stdLibDirectory 'Graphics.sharnou') -Force

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
    # Preserve the historical Stage 4 negative test for the old four-register-only
    # function ABI. The normal compiler run is not restricted by this compatibility mode.
    $previousLegacyArityMode = [Environment]::GetEnvironmentVariable('SHARNOU_BASELINE_M1_M6')
    [Environment]::SetEnvironmentVariable('SHARNOU_BASELINE_M1_M6', '1', 'Process')
    try {
    foreach ($suite in $manifest.suites) {
        $suitePath = Join-Path $workRoot ([string]$suite.path.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
        if ([string]$suite.path -eq 'Tests/Test-Stage2.ps1') {
            $suitePath = $stage2AdaptedPath
        }
        if (-not (Test-Path -LiteralPath $suitePath -PathType Leaf)) {
            throw "Historical regression suite is missing: $suitePath"
        }

        Write-Host ''
        Write-Host ('=== Historical baseline suite: ' + $suite.path + ' (' + $suite.cases + ' cases) ===')
        & $suitePath
        $suiteSucceeded = $?
        $global:LASTEXITCODE = 0
        if (-not $suiteSucceeded) {
            throw "Historical regression suite reported failure: $($suite.path)"
        }
        $caseTotal += [int]$suite.cases
    }
    }
    finally {
        [Environment]::SetEnvironmentVariable('SHARNOU_BASELINE_M1_M6', $previousLegacyArityMode, 'Process')
    }

    if ($caseTotal -ne 83) {
        throw "Historical regression accounting mismatch. Expected 83; recorded $caseTotal."
    }
    Write-Host ''
    $global:LASTEXITCODE = 0
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

