[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'The DevAgent protected-journal primitive test requires Windows.'
}

if (-not ('Sharnou.DevAgentDpapiJournalNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.RegularExpressions;

namespace Sharnou
{
    public static class DevAgentDpapiJournalNative
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct DATA_BLOB
        {
            public int cbData;
            public IntPtr pbData;
        }

        private const uint CryptProtectUiForbidden = 0x00000001;
        private const int MaxBlobBytes = 65536;

        [DllImport("crypt32.dll", EntryPoint = "CryptProtectData",
            CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CryptProtectData(
            ref DATA_BLOB dataIn,
            string description,
            ref DATA_BLOB optionalEntropy,
            IntPtr reserved,
            IntPtr prompt,
            uint flags,
            out DATA_BLOB dataOut);

        [DllImport("crypt32.dll", EntryPoint = "CryptUnprotectData",
            CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CryptUnprotectData(
            ref DATA_BLOB dataIn,
            out IntPtr description,
            ref DATA_BLOB optionalEntropy,
            IntPtr reserved,
            IntPtr prompt,
            uint flags,
            out DATA_BLOB dataOut);

        [DllImport("kernel32.dll", EntryPoint = "LocalFree", ExactSpelling = true)]
        private static extern IntPtr LocalFree(IntPtr memory);

        private static DATA_BLOB AllocateBlob(byte[] bytes)
        {
            if (bytes == null || bytes.Length == 0 || bytes.Length > MaxBlobBytes)
                throw new ArgumentOutOfRangeException("bytes", "Journal test blob must be 1..65536 bytes.");
            DATA_BLOB blob = new DATA_BLOB();
            blob.cbData = bytes.Length;
            blob.pbData = Marshal.AllocHGlobal(bytes.Length);
            Marshal.Copy(bytes, 0, blob.pbData, bytes.Length);
            return blob;
        }

        private static void FreeInput(ref DATA_BLOB blob)
        {
            if (blob.pbData != IntPtr.Zero)
            {
                Marshal.FreeHGlobal(blob.pbData);
                blob.pbData = IntPtr.Zero;
            }
            blob.cbData = 0;
        }

        public static byte[] Protect(byte[] plaintext, byte[] entropy)
        {
            DATA_BLOB input = AllocateBlob(plaintext);
            DATA_BLOB optionalEntropy = AllocateBlob(entropy);
            DATA_BLOB output = new DATA_BLOB();
            try
            {
                // Deliberately omit CRYPTPROTECT_LOCAL_MACHINE. The protected
                // record is bound to the same user context and machine.
                if (!CryptProtectData(
                    ref input,
                    "Sharnou DevAgent authenticated ACL journal v2",
                    ref optionalEntropy,
                    IntPtr.Zero,
                    IntPtr.Zero,
                    CryptProtectUiForbidden,
                    out output))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "CryptProtectData failed.");

                if (output.pbData == IntPtr.Zero || output.cbData <= 0 || output.cbData > MaxBlobBytes)
                    throw new InvalidOperationException("CryptProtectData returned an invalid bounded output blob.");

                byte[] result = new byte[output.cbData];
                Marshal.Copy(output.pbData, result, 0, result.Length);
                return result;
            }
            finally
            {
                if (output.pbData != IntPtr.Zero) LocalFree(output.pbData);
                FreeInput(ref optionalEntropy);
                FreeInput(ref input);
            }
        }

        public static bool TryUnprotect(byte[] protectedBlob, byte[] entropy, out byte[] plaintext, out int error)
        {
            plaintext = null;
            error = 0;
            DATA_BLOB input = AllocateBlob(protectedBlob);
            DATA_BLOB optionalEntropy = AllocateBlob(entropy);
            DATA_BLOB output = new DATA_BLOB();
            IntPtr description = IntPtr.Zero;
            try
            {
                if (!CryptUnprotectData(
                    ref input,
                    out description,
                    ref optionalEntropy,
                    IntPtr.Zero,
                    IntPtr.Zero,
                    CryptProtectUiForbidden,
                    out output))
                {
                    error = Marshal.GetLastWin32Error();
                    return false;
                }

                if (output.pbData == IntPtr.Zero || output.cbData <= 0 || output.cbData > MaxBlobBytes)
                {
                    error = 13; // ERROR_INVALID_DATA
                    return false;
                }

                plaintext = new byte[output.cbData];
                Marshal.Copy(output.pbData, plaintext, 0, plaintext.Length);
                return true;
            }
            finally
            {
                if (description != IntPtr.Zero) LocalFree(description);
                if (output.pbData != IntPtr.Zero) LocalFree(output.pbData);
                FreeInput(ref optionalEntropy);
                FreeInput(ref input);
            }
        }

        public static void ValidateCanonicalJournalV2(byte[] record)
        {
            if (record == null || record.Length < 80 || record.Length > 16384)
                throw new InvalidDataException("Journal payload length is outside 80..16384 bytes.");

            using (MemoryStream stream = new MemoryStream(record, false))
            using (BinaryReader reader = new BinaryReader(stream, System.Text.Encoding.ASCII, true))
            {
                byte[] magic = reader.ReadBytes(8);
                if (magic.Length != 8 || System.Text.Encoding.ASCII.GetString(magic) != "SHARJNL2")
                    throw new InvalidDataException("Journal magic is invalid.");

                uint version = reader.ReadUInt32();
                if (version != 2)
                    throw new InvalidDataException("Unsupported journal version.");

                byte[] executionBytes = reader.ReadBytes(16);
                if (executionBytes.Length != 16 || new Guid(executionBytes) == Guid.Empty)
                    throw new InvalidDataException("Execution identifier is invalid.");

                uint profileLength = reader.ReadUInt32();
                if (profileLength < 1 || profileLength > 64)
                    throw new InvalidDataException("AppContainer profile name length is outside 1..64: " + profileLength + ".");
                byte[] profileBytes = reader.ReadBytes(checked((int)profileLength));
                if (profileBytes.Length != profileLength)
                    throw new InvalidDataException("AppContainer profile name is truncated.");
                string profileName = System.Text.Encoding.ASCII.GetString(profileBytes);
                if (!Regex.IsMatch(profileName, @"^Sharnou\.DevAgent\.[0-9a-f]{32}$", RegexOptions.CultureInvariant))
                    throw new InvalidDataException("AppContainer profile name is not canonical.");

                uint sidLength = reader.ReadUInt32();
                if (sidLength < 11 || sidLength > 256)
                    throw new InvalidDataException("AppContainer SID length is outside policy bounds.");
                byte[] sidBytes = reader.ReadBytes(checked((int)sidLength));
                if (sidBytes.Length != sidLength)
                    throw new InvalidDataException("AppContainer SID is truncated.");
                string packageSid = System.Text.Encoding.ASCII.GetString(sidBytes);
                if (!Regex.IsMatch(packageSid, @"^S-1-15-2-(0|[1-9][0-9]*)-(0|[1-9][0-9]*)-(0|[1-9][0-9]*)-(0|[1-9][0-9]*)-(0|[1-9][0-9]*)-(0|[1-9][0-9]*)-(0|[1-9][0-9]*)$", RegexOptions.CultureInvariant))
                    throw new InvalidDataException("AppContainer package SID is not canonical.");

                // FILE_ID_INFO contains a 64-bit volume serial plus a
                // 128-bit FILE_ID_128. Do not reduce the workspace identity
                // to the legacy 64-bit file-index pair.
                ulong volumeSerial = reader.ReadUInt64();
                byte[] workspaceFileId = reader.ReadBytes(16);
                if (volumeSerial == 0 || workspaceFileId.Length != 16)
                    throw new InvalidDataException("Canonical workspace volume/file identity is missing.");
                bool fileIdHasNonZeroByte = false;
                for (int fileIdIndex = 0; fileIdIndex < workspaceFileId.Length; fileIdIndex++)
                    if (workspaceFileId[fileIdIndex] != 0) fileIdHasNonZeroByte = true;
                if (!fileIdHasNonZeroByte)
                    throw new InvalidDataException("Canonical 128-bit workspace file ID is empty.");

                uint descriptorCount = reader.ReadUInt32();
                if (descriptorCount != 3)
                    throw new InvalidDataException("Journal must contain exactly three protected directory descriptors.");

                for (int i = 0; i < 3; i++)
                {
                    uint descriptorLength = reader.ReadUInt32();
                    if (descriptorLength < 20 || descriptorLength > 4096)
                        throw new InvalidDataException("Security descriptor length is outside policy bounds.");
                    byte[] descriptor = reader.ReadBytes(checked((int)descriptorLength));
                    if (descriptor.Length != descriptorLength)
                        throw new InvalidDataException("Security descriptor is truncated.");
                }

                uint policyVersion = reader.ReadUInt32();
                if (policyVersion != 2)
                    throw new InvalidDataException("Unsupported security policy version.");

                if (stream.Position != stream.Length)
                    throw new InvalidDataException("Journal contains trailing bytes.");
            }
        }
    }
}
'@
}

function New-JournalFixturePayload {
    param(
        [Parameter(Mandatory = $true)][string] $ProfileName,
        [Parameter(Mandatory = $true)][string] $PackageSid
    )

    $stream = New-Object IO.MemoryStream
    $writer = New-Object IO.BinaryWriter($stream, [Text.Encoding]::UTF8, $true)
    try {
        $writer.Write([Text.Encoding]::ASCII.GetBytes('SHARJNL2'))
        $writer.Write([uint32]2)
        $writer.Write([Guid]::NewGuid().ToByteArray())
        $writer.Write([uint32]$ProfileName.Length)
        $writer.Write([Text.Encoding]::ASCII.GetBytes($ProfileName))
        $sidBytes = [Text.Encoding]::ASCII.GetBytes($PackageSid)
        $writer.Write([uint32]$sidBytes.Length)
        $writer.Write($sidBytes)
        $writer.Write([uint64]0x0123456789ABCDEF) # synthetic FILE_ID_INFO volume serial
        [byte[]]$workspaceFileId = 1..16 | ForEach-Object { [byte]$_ }
        $writer.Write($workspaceFileId) # full 128-bit FILE_ID_128
        $writer.Write([uint32]3) # three protected directory descriptors
        foreach ($descriptor in @(
            [Text.Encoding]::ASCII.GetBytes('ROOT-DESCRIPTOR-FIXTURE'),
            [Text.Encoding]::ASCII.GetBytes('BUILD-DESCRIPTOR-FIXTURE'),
            [Text.Encoding]::ASCII.GetBytes('BROKER-DESCRIPTOR-FIXTURE')
        )) {
            $writer.Write([uint32]$descriptor.Length)
            $writer.Write($descriptor)
        }
        $writer.Write([uint32]2) # security policy version
        $writer.Flush()
        return $stream.ToArray()
    }
    finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

function Test-ByteSequence {
    param([byte[]] $Haystack, [byte[]] $Needle)
    if ($Needle.Length -eq 0 -or $Haystack.Length -lt $Needle.Length) { return $false }
    for ($i = 0; $i -le ($Haystack.Length - $Needle.Length); $i++) {
        $same = $true
        for ($j = 0; $j -lt $Needle.Length; $j++) {
            if ($Haystack[$i + $j] -ne $Needle[$j]) { $same = $false; break }
        }
        if ($same) { return $true }
    }
    return $false
}

$profileName = 'Sharnou.DevAgent.0123456789abcdef0123456789abcdef'
$packageSid = 'S-1-15-2-123456789-234567890-345678901-456789012-567890123-678901234-789012345'
$entropy = [Text.Encoding]::UTF8.GetBytes('Sharnou.DevAgent.AuthenticatedJournal.v2|user-scope')
$wrongEntropy = [Text.Encoding]::UTF8.GetBytes('Sharnou.DevAgent.AuthenticatedJournal.v2|wrong-context')
[byte[]]$plaintext = New-JournalFixturePayload -ProfileName $profileName -PackageSid $packageSid

if ($plaintext.Length -gt 16384) {
    throw "Canonical test journal exceeds the 16 KiB plaintext limit: $($plaintext.Length)"
}

[Sharnou.DevAgentDpapiJournalNative]::ValidateCanonicalJournalV2($plaintext)
Write-Host 'PASS: strict v2 journal parser accepted canonical execution/profile/workspace/descriptor record' -ForegroundColor Green

$parserRejectCases = New-Object 'System.Collections.Generic.List[object]'
$badVersion = [byte[]]$plaintext.Clone()
[BitConverter]::GetBytes([uint32]99).CopyTo($badVersion, 8)
$parserRejectCases.Add(@{ Name = 'unsupported version'; Bytes = $badVersion })
$truncated = New-Object byte[] ($plaintext.Length - 1)
[Array]::Copy($plaintext, $truncated, $truncated.Length)
$parserRejectCases.Add(@{ Name = 'truncated record'; Bytes = $truncated })
$trailing = New-Object byte[] ($plaintext.Length + 1)
[Array]::Copy($plaintext, $trailing, $plaintext.Length)
$trailing[$trailing.Length - 1] = 0
$parserRejectCases.Add(@{ Name = 'trailing byte'; Bytes = $trailing })
$badProfileLength = [byte[]]$plaintext.Clone()
[BitConverter]::GetBytes([uint32]65).CopyTo($badProfileLength, 28)
$parserRejectCases.Add(@{ Name = 'profile-name length overflow'; Bytes = $badProfileLength })
$badWorkspaceIdentity = [byte[]]$plaintext.Clone()
# Workspace volume serial follows the fixed 32-byte header, profile name,
# SID length and SID bytes. Locate it from the canonical lengths, not a magic offset.
$profileLength = [BitConverter]::ToUInt32($plaintext, 28)
$sidLengthOffset = 32 + [int]$profileLength
$sidLength = [BitConverter]::ToUInt32($plaintext, $sidLengthOffset)
$workspaceVolumeOffset = $sidLengthOffset + 4 + [int]$sidLength
[BitConverter]::GetBytes([uint64]0).CopyTo($badWorkspaceIdentity, $workspaceVolumeOffset)
$parserRejectCases.Add(@{ Name = 'missing workspace volume identity'; Bytes = $badWorkspaceIdentity })
$badWorkspaceFileId = [byte[]]$plaintext.Clone()
[Array]::Clear($badWorkspaceFileId, ($workspaceVolumeOffset + 8), 16)
$parserRejectCases.Add(@{ Name = 'empty 128-bit workspace file identity'; Bytes = $badWorkspaceFileId })
$emptyExecutionId = [byte[]]$plaintext.Clone()
for ($i = 12; $i -lt 28; $i++) { $emptyExecutionId[$i] = 0 }
$parserRejectCases.Add(@{ Name = 'empty execution identifier'; Bytes = $emptyExecutionId })
$badPackageSid = [byte[]]$plaintext.Clone()
$sidStart = $sidLengthOffset + 4
$badPackageSid[$sidStart] = [byte][char]'X'
$parserRejectCases.Add(@{ Name = 'malformed package SID'; Bytes = $badPackageSid })
$descriptorCountOffset = $workspaceVolumeOffset + 24
$badDescriptorCount = [byte[]]$plaintext.Clone()
[BitConverter]::GetBytes([uint32]2).CopyTo($badDescriptorCount, $descriptorCountOffset)
$parserRejectCases.Add(@{ Name = 'descriptor count mismatch'; Bytes = $badDescriptorCount })
$badDescriptorLength = [byte[]]$plaintext.Clone()
[BitConverter]::GetBytes([uint32]19).CopyTo($badDescriptorLength, ($descriptorCountOffset + 4))
$parserRejectCases.Add(@{ Name = 'descriptor length below minimum'; Bytes = $badDescriptorLength })
$badPolicyVersion = [byte[]]$plaintext.Clone()
[BitConverter]::GetBytes([uint32]1).CopyTo($badPolicyVersion, ($badPolicyVersion.Length - 4))
$parserRejectCases.Add(@{ Name = 'unsupported security policy version'; Bytes = $badPolicyVersion })

foreach ($case in $parserRejectCases) {
    $rejected = $false
    try {
        [Sharnou.DevAgentDpapiJournalNative]::ValidateCanonicalJournalV2([byte[]]$case.Bytes)
    }
    catch {
        $parserException = $_.Exception
        while ($null -ne $parserException.InnerException) {
            $parserException = $parserException.InnerException
        }
        if (($parserException -is [IO.InvalidDataException]) -or
            ($parserException -is [IO.EndOfStreamException])) {
            $rejected = $true
        }
        else {
            throw
        }
    }
    if (-not $rejected) {
        throw "Strict journal parser accepted invalid case: $($case.Name)"
    }
    Write-Host ("PASS: strict v2 journal parser rejected {0}" -f $case.Name) -ForegroundColor Green
}

[byte[]]$protected = [Sharnou.DevAgentDpapiJournalNative]::Protect($plaintext, $entropy)
if ($protected.Length -lt 32 -or $protected.Length -gt 65536) {
    throw "DPAPI envelope length is outside the 32..65536-byte bounds: $($protected.Length)"
}

[byte[]]$roundTrip = $null
$errorCode = 0
if (-not [Sharnou.DevAgentDpapiJournalNative]::TryUnprotect($protected, $entropy, [ref]$roundTrip, [ref]$errorCode)) {
    throw "DPAPI journal round-trip failed with Win32 error $errorCode."
}
if (-not [Convert]::ToBase64String($roundTrip).Equals([Convert]::ToBase64String($plaintext), [StringComparison]::Ordinal)) {
    throw 'DPAPI journal round-trip did not reproduce the exact canonical payload.'
}

foreach ($position in @(0, [int][Math]::Floor($protected.Length / 2), ($protected.Length - 1))) {
    [byte[]]$tampered = $protected.Clone()
    $tampered[$position] = [byte]($tampered[$position] -bxor 0x01)
    [byte[]]$tamperedPlaintext = $null
    $tamperError = 0
    $unprotected = [Sharnou.DevAgentDpapiJournalNative]::TryUnprotect($tampered, $entropy, [ref]$tamperedPlaintext, [ref]$tamperError)
    if ($unprotected -and [Convert]::ToBase64String($tamperedPlaintext).Equals([Convert]::ToBase64String($plaintext), [StringComparison]::Ordinal)) {
        throw "Tampered DPAPI envelope at byte $position reproduced the original plaintext."
    }
    Write-Host ("PASS: tampered DPAPI envelope at byte {0} was rejected or failed exact plaintext verification (Win32={1})" -f $position, $tamperError) -ForegroundColor Green
}

[byte[]]$wrongContextPlaintext = $null
$wrongContextError = 0
$wrongContextResult = [Sharnou.DevAgentDpapiJournalNative]::TryUnprotect($protected, $wrongEntropy, [ref]$wrongContextPlaintext, [ref]$wrongContextError)
if ($wrongContextResult -and [Convert]::ToBase64String($wrongContextPlaintext).Equals([Convert]::ToBase64String($plaintext), [StringComparison]::Ordinal)) {
    throw 'A journal protected with different optional entropy reproduced the original plaintext.'
}

if ((Test-ByteSequence -Haystack $protected -Needle ([Text.Encoding]::ASCII.GetBytes('SHARJNL2'))) -or
    (Test-ByteSequence -Haystack $protected -Needle ([Text.Encoding]::ASCII.GetBytes($profileName))) -or
    (Test-ByteSequence -Haystack $protected -Needle ([Text.Encoding]::ASCII.GetBytes($packageSid)))) {
    throw 'Protected test envelope contains cleartext journal markers or identity metadata.'
}

# Prove that a genuinely separate process running as the same Windows user
# can mint a different valid envelope using the public optional entropy. DPAPI
# binds to the user profile, not to this particular broker process.
[byte[]]$sameUserForgedPayload = $plaintext.Clone()
$sameUserForgedPayload[12] = [byte]($sameUserForgedPayload[12] -bxor 0x01)
[Sharnou.DevAgentDpapiJournalNative]::ValidateCanonicalJournalV2($sameUserForgedPayload)

$forgeRoot = Join-Path ([IO.Path]::GetTempPath()) ('Sharnou-DPAPI-Writer-Probe-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($forgeRoot)
$forgePayloadPath = Join-Path $forgeRoot 'payload.bin'
$forgeEntropyPath = Join-Path $forgeRoot 'entropy.bin'
$forgeEnvelopePath = Join-Path $forgeRoot 'envelope.bin'
$forgeScriptPath = Join-Path $forgeRoot 'forge.ps1'
$forgeChildScript = @'
param([string] $PayloadPath, [string] $EntropyPath, [string] $EnvelopePath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security -ErrorAction Stop
[byte[]]$payload = [IO.File]::ReadAllBytes($PayloadPath)
[byte[]]$entropy = [IO.File]::ReadAllBytes($EntropyPath)
[byte[]]$envelope = [System.Security.Cryptography.ProtectedData]::Protect(
    $payload, $entropy, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
[IO.File]::WriteAllBytes($EnvelopePath, $envelope)
Write-Output ('CHILD_DPAPI_PROTECT_SUCCESS|bytes={0}' -f $envelope.Length)
'@
try {
    [IO.File]::WriteAllBytes($forgePayloadPath, $sameUserForgedPayload)
    [IO.File]::WriteAllBytes($forgeEntropyPath, $entropy)
    [IO.File]::WriteAllText($forgeScriptPath, $forgeChildScript, [Text.Encoding]::ASCII)

    $forgeProcessInfo = New-Object Diagnostics.ProcessStartInfo
    $forgeProcessInfo.FileName = Join-Path $PSHOME 'powershell.exe'
    $forgeProcessInfo.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
        $forgeScriptPath + '" "' + $forgePayloadPath + '" "' + $forgeEntropyPath + '" "' + $forgeEnvelopePath + '"'
    $forgeProcessInfo.UseShellExecute = $false
    $forgeProcessInfo.CreateNoWindow = $true
    $forgeProcessInfo.RedirectStandardOutput = $true
    $forgeProcessInfo.RedirectStandardError = $true

    $forgeProcess = [Diagnostics.Process]::Start($forgeProcessInfo)
    if (-not $forgeProcess.WaitForExit(15000)) {
        $forgeProcess.Kill()
        throw 'Separate same-user DPAPI writer process exceeded the 15-second timeout.'
    }
    $forgeStdout = $forgeProcess.StandardOutput.ReadToEnd()
    $forgeStderr = $forgeProcess.StandardError.ReadToEnd()
    if ($forgeProcess.ExitCode -ne 0) {
        throw ("Separate same-user DPAPI writer failed (exit={0}): {1} {2}" -f
            $forgeProcess.ExitCode, $forgeStdout, $forgeStderr)
    }
    if (-not (Test-Path -LiteralPath $forgeEnvelopePath -PathType Leaf)) {
        throw 'Separate same-user DPAPI writer exited successfully without producing an envelope.'
    }
    [byte[]]$sameUserForgedEnvelope = [IO.File]::ReadAllBytes($forgeEnvelopePath)
    if ($sameUserForgedEnvelope.Length -lt 32 -or $sameUserForgedEnvelope.Length -gt 65536) {
        throw "Separate same-user DPAPI envelope length is outside policy bounds: $($sameUserForgedEnvelope.Length)"
    }

    [byte[]]$sameUserForgedRoundTrip = $null
    $sameUserForgedError = 0
    if (-not [Sharnou.DevAgentDpapiJournalNative]::TryUnprotect($sameUserForgedEnvelope, $entropy, [ref]$sameUserForgedRoundTrip, [ref]$sameUserForgedError)) {
        throw "Trusted test process could not decrypt the separate same-user writer envelope: $sameUserForgedError"
    }
    if (-not [Convert]::ToBase64String($sameUserForgedRoundTrip).Equals([Convert]::ToBase64String($sameUserForgedPayload), [StringComparison]::Ordinal)) {
        throw 'Separate same-user DPAPI writer envelope did not reproduce the exact forged payload.'
    }
    Write-Host 'PASS: separate process under the same user can mint a different valid DPAPI envelope with public entropy; DPAPI is not writer-process authentication' -ForegroundColor Green
}
finally {
    Remove-Item -LiteralPath $forgeRoot -Recurse -Force -ErrorAction SilentlyContinue
}


if (-not ('Sharnou.DevAgentJournalSigningKey' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace Sharnou
{
    // Test-only ephemeral signer. It intentionally exports only the public
    // CNG blob; this fixture does not model service key persistence or ACLs.
    public sealed class DevAgentJournalSigningKey : IDisposable
    {
        private const int RsaBits = 3072;
        private const int SignatureBytes = 384;
        private readonly RSACng _key;

        public DevAgentJournalSigningKey()
        {
            _key = new RSACng(RsaBits);
        }

        public byte[] ExportPublicKeyBlob()
        {
            return _key.Key.Export(CngKeyBlobFormat.GenericPublicBlob);
        }

        public byte[] Sign(byte[] payload)
        {
            if (payload == null || payload.Length < 80 || payload.Length > 16384)
                throw new ArgumentOutOfRangeException("payload", "Signed journal payload must be 80..16384 bytes.");

            byte[] publicBlob = ExportPublicKeyBlob();
            byte[] keyId;
            using (SHA256 sha = SHA256.Create())
                keyId = sha.ComputeHash(publicBlob);

            byte[] prefix;
            using (MemoryStream stream = new MemoryStream())
            using (BinaryWriter writer = new BinaryWriter(stream, Encoding.ASCII, true))
            {
                writer.Write(Encoding.ASCII.GetBytes("SHASIG1!"));
                writer.Write((uint)1);
                writer.Write((uint)1);
                writer.Write(keyId);
                writer.Write((uint)payload.Length);
                writer.Write((uint)SignatureBytes);
                writer.Write(payload);
                writer.Flush();
                prefix = stream.ToArray();
            }

            byte[] signingInput = DevAgentSignedJournalVerifier.CreateSigningInput(prefix);
            byte[] signature = _key.SignData(
                signingInput,
                HashAlgorithmName.SHA256,
                RSASignaturePadding.Pss);
            if (signature == null || signature.Length != SignatureBytes)
                throw new CryptographicException("CNG returned a noncanonical RSA-3072 signature length.");

            byte[] envelope = new byte[prefix.Length + signature.Length];
            Buffer.BlockCopy(prefix, 0, envelope, 0, prefix.Length);
            Buffer.BlockCopy(signature, 0, envelope, prefix.Length, signature.Length);
            return envelope;
        }

        public void Dispose()
        {
            _key.Dispose();
        }
    }

    public static class DevAgentSignedJournalVerifier
    {
        private const int HeaderBytes = 56;
        private const int SignatureBytes = 384;
        private const int MinimumPayloadBytes = 80;
        private const int MaximumPayloadBytes = 16384;
        private const int MaximumEnvelopeBytes = HeaderBytes + MaximumPayloadBytes + SignatureBytes;
        private static readonly byte[] Magic = Encoding.ASCII.GetBytes("SHASIG1!");
        private static readonly byte[] Domain = Encoding.ASCII.GetBytes(
            "Sharnou.DevAgent.AuthenticatedJournal.Signature.v1\0");

        internal static byte[] CreateSigningInput(byte[] signedPrefix)
        {
            byte[] input = new byte[Domain.Length + signedPrefix.Length];
            Buffer.BlockCopy(Domain, 0, input, 0, Domain.Length);
            Buffer.BlockCopy(signedPrefix, 0, input, Domain.Length, signedPrefix.Length);
            return input;
        }

        private static bool FixedTimeEquals(byte[] left, byte[] right)
        {
            if (left == null || right == null || left.Length != right.Length)
                return false;
            int difference = 0;
            for (int i = 0; i < left.Length; i++)
                difference |= left[i] ^ right[i];
            return difference == 0;
        }

        public static byte[] VerifyAndValidate(byte[] envelope, byte[] pinnedPublicKeyBlob)
        {
            if (envelope == null ||
                envelope.Length < HeaderBytes + MinimumPayloadBytes + SignatureBytes ||
                envelope.Length > MaximumEnvelopeBytes)
                throw new InvalidDataException("Signed journal envelope length is outside policy bounds.");

            if (pinnedPublicKeyBlob == null || pinnedPublicKeyBlob.Length < 32 || pinnedPublicKeyBlob.Length > 4096)
                throw new InvalidDataException("Pinned CNG public key blob is outside policy bounds.");

            for (int i = 0; i < Magic.Length; i++)
                if (envelope[i] != Magic[i])
                    throw new InvalidDataException("Signed journal magic is invalid.");

            uint version = BitConverter.ToUInt32(envelope, 8);
            uint algorithm = BitConverter.ToUInt32(envelope, 12);
            if (version != 1)
                throw new InvalidDataException("Unsupported signed journal envelope version.");
            if (algorithm != 1)
                throw new InvalidDataException("Unsupported signed journal signature algorithm.");

            uint payloadLength = BitConverter.ToUInt32(envelope, 48);
            uint signatureLength = BitConverter.ToUInt32(envelope, 52);
            if (payloadLength < MinimumPayloadBytes || payloadLength > MaximumPayloadBytes)
                throw new InvalidDataException("Signed journal payload length is outside policy bounds.");
            if (signatureLength != SignatureBytes)
                throw new InvalidDataException("RSA-3072 signature length is not canonical.");

            long expectedLength = (long)HeaderBytes + payloadLength + signatureLength;
            if (expectedLength != envelope.Length)
                throw new InvalidDataException("Signed journal envelope is truncated or has trailing bytes.");

            byte[] claimedKeyId = new byte[32];
            Buffer.BlockCopy(envelope, 16, claimedKeyId, 0, claimedKeyId.Length);
            byte[] pinnedKeyId;
            using (SHA256 sha = SHA256.Create())
                pinnedKeyId = sha.ComputeHash(pinnedPublicKeyBlob);

            if (!FixedTimeEquals(claimedKeyId, pinnedKeyId))
                throw new CryptographicException("Journal key identifier does not match the pinned authority public key.");

            int prefixLength = checked(HeaderBytes + (int)payloadLength);
            byte[] signedPrefix = new byte[prefixLength];
            Buffer.BlockCopy(envelope, 0, signedPrefix, 0, prefixLength);
            byte[] signingInput = CreateSigningInput(signedPrefix);
            byte[] signature = new byte[SignatureBytes];
            Buffer.BlockCopy(envelope, prefixLength, signature, 0, signature.Length);

            using (CngKey publicCngKey = CngKey.Import(
                pinnedPublicKeyBlob,
                CngKeyBlobFormat.GenericPublicBlob))
            using (RSACng publicKey = new RSACng(publicCngKey))
            {
                if (publicKey.KeySize != 3072)
                    throw new CryptographicException("Pinned authority key is not RSA-3072.");
                if (!publicKey.VerifyData(
                    signingInput,
                    signature,
                    HashAlgorithmName.SHA256,
                    RSASignaturePadding.Pss))
                    throw new CryptographicException("Signed journal signature verification failed.");
            }

            byte[] payload = new byte[(int)payloadLength];
            Buffer.BlockCopy(envelope, HeaderBytes, payload, 0, payload.Length);
            DevAgentDpapiJournalNative.ValidateCanonicalJournalV2(payload);
            return payload;
        }
    }
}
'@
}

function Assert-SignedJournalRejected {
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][byte[]] $Envelope,
        [Parameter(Mandatory = $true)][byte[]] $PinnedPublicKeyBlob,
        [Parameter(Mandatory = $true)][ValidateSet('InvalidData', 'Cryptographic')][string] $ExpectedKind
    )

    $rejected = $false
    try {
        [Sharnou.DevAgentSignedJournalVerifier]::VerifyAndValidate(
            [byte[]]$Envelope,
            [byte[]]$PinnedPublicKeyBlob) | Out-Null
    }
    catch {
        $exception = $_.Exception
        while ($null -ne $exception.InnerException) { $exception = $exception.InnerException }
        if ($ExpectedKind -eq 'InvalidData' -and
            (($exception -is [IO.InvalidDataException]) -or ($exception -is [IO.EndOfStreamException]))) {
            $rejected = $true
        }
        elseif ($ExpectedKind -eq 'Cryptographic' -and
            ($exception -is [Security.Cryptography.CryptographicException])) {
            $rejected = $true
        }
        else {
            throw ("Signed-journal case '{0}' failed with an unexpected exception: {1}" -f $Name, $exception.GetType().FullName)
        }
    }
    if (-not $rejected) {
        throw "Signed-journal verifier accepted invalid case: $Name"
    }
    Write-Host ("PASS: signed-journal verifier rejected {0}" -f $Name) -ForegroundColor Green
}

$trustedSigner = [Sharnou.DevAgentJournalSigningKey]::new()
$attackerSigner = [Sharnou.DevAgentJournalSigningKey]::new()
try {
    [byte[]]$trustedPublicKey = $trustedSigner.ExportPublicKeyBlob()
    [byte[]]$signedEnvelope = $trustedSigner.Sign($plaintext)
    [byte[]]$verifiedPayload = [Sharnou.DevAgentSignedJournalVerifier]::VerifyAndValidate(
        $signedEnvelope,
        $trustedPublicKey)
    if (-not [Convert]::ToBase64String($verifiedPayload).Equals(
        [Convert]::ToBase64String($plaintext),
        [StringComparison]::Ordinal)) {
        throw 'Signed journal verification did not return the exact canonical v2 payload.'
    }
    Write-Host 'PASS: pinned RSA-3072 CNG public key verified the domain-separated RSA-PSS/SHA-256 journal envelope' -ForegroundColor Green
    Write-Host 'PASS: inner journal metadata was parsed only after the outer signature verified' -ForegroundColor Green

    $badEnvelopeVersion = [byte[]]$signedEnvelope.Clone()
    [BitConverter]::GetBytes([uint32]2).CopyTo($badEnvelopeVersion, 8)
    Assert-SignedJournalRejected -Name 'unsupported envelope version' -Envelope $badEnvelopeVersion -PinnedPublicKeyBlob $trustedPublicKey -ExpectedKind InvalidData

    $badAlgorithm = [byte[]]$signedEnvelope.Clone()
    [BitConverter]::GetBytes([uint32]99).CopyTo($badAlgorithm, 12)
    Assert-SignedJournalRejected -Name 'unsupported signature algorithm' -Envelope $badAlgorithm -PinnedPublicKeyBlob $trustedPublicKey -ExpectedKind InvalidData

    $badPayloadLength = [byte[]]$signedEnvelope.Clone()
    [BitConverter]::GetBytes([uint32]16385).CopyTo($badPayloadLength, 48)
    Assert-SignedJournalRejected -Name 'payload length above policy maximum' -Envelope $badPayloadLength -PinnedPublicKeyBlob $trustedPublicKey -ExpectedKind InvalidData

    $badSignatureLength = [byte[]]$signedEnvelope.Clone()
    [BitConverter]::GetBytes([uint32]383).CopyTo($badSignatureLength, 52)
    Assert-SignedJournalRejected -Name 'noncanonical RSA signature length' -Envelope $badSignatureLength -PinnedPublicKeyBlob $trustedPublicKey -ExpectedKind InvalidData

    $badKeyId = [byte[]]$signedEnvelope.Clone()
    $badKeyId[16] = [byte]($badKeyId[16] -bxor 0x01)
    Assert-SignedJournalRejected -Name 'pinned key identifier mismatch' -Envelope $badKeyId -PinnedPublicKeyBlob $trustedPublicKey -ExpectedKind Cryptographic

    $truncatedSigned = New-Object byte[] ($signedEnvelope.Length - 1)
    [Array]::Copy($signedEnvelope, $truncatedSigned, $truncatedSigned.Length)
    Assert-SignedJournalRejected -Name 'truncated signed envelope' -Envelope $truncatedSigned -PinnedPublicKeyBlob $trustedPublicKey -ExpectedKind InvalidData

    $trailingSigned = New-Object byte[] ($signedEnvelope.Length + 1)
    [Array]::Copy($signedEnvelope, $trailingSigned, $signedEnvelope.Length)
    Assert-SignedJournalRejected -Name 'trailing signed-envelope byte' -Envelope $trailingSigned -PinnedPublicKeyBlob $trustedPublicKey -ExpectedKind InvalidData

    $tamperedSignedPayload = [byte[]]$signedEnvelope.Clone()
    $tamperedSignedPayload[56 + 8] = [byte]($tamperedSignedPayload[56 + 8] -bxor 0x01)
    Assert-SignedJournalRejected -Name 'modified inner journal version without a new signature' -Envelope $tamperedSignedPayload -PinnedPublicKeyBlob $trustedPublicKey -ExpectedKind Cryptographic

    $tamperedSignature = [byte[]]$signedEnvelope.Clone()
    $tamperedSignature[$tamperedSignature.Length - 1] = [byte]($tamperedSignature[$tamperedSignature.Length - 1] -bxor 0x01)
    Assert-SignedJournalRejected -Name 'modified RSA signature byte' -Envelope $tamperedSignature -PinnedPublicKeyBlob $trustedPublicKey -ExpectedKind Cryptographic

    [byte[]]$attackerEnvelope = $attackerSigner.Sign($plaintext)
    Assert-SignedJournalRejected -Name 'same-user attacker key not present in trusted key pin set' -Envelope $attackerEnvelope -PinnedPublicKeyBlob $trustedPublicKey -ExpectedKind Cryptographic

    $signedMalformedPayload = [byte[]]$plaintext.Clone()
    [BitConverter]::GetBytes([uint32]99).CopyTo($signedMalformedPayload, 8)
    [byte[]]$signedMalformedEnvelope = $trustedSigner.Sign($signedMalformedPayload)
    Assert-SignedJournalRejected -Name 'trusted signature over malformed inner journal schema' -Envelope $signedMalformedEnvelope -PinnedPublicKeyBlob $trustedPublicKey -ExpectedKind InvalidData
}
finally {
    $trustedSigner.Dispose()
    $attackerSigner.Dispose()
}


$plainHash = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($plaintext)).Replace('-', '')
$envelopeHash = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($protected)).Replace('-', '')
Write-Host ("PASS: DPAPI current-user envelope round-tripped exact canonical v2 journal payload ({0} bytes)" -f $plaintext.Length) -ForegroundColor Green
Write-Host 'PASS: DPAPI optional entropy binds the envelope to the Sharnou journal context' -ForegroundColor Green
Write-Host 'PASS: cleartext execution identity, package SID and journal magic are absent from the protected envelope' -ForegroundColor Green
Write-Host ("DPAPI fixture SHA-256: plaintext={0}; envelope={1}" -f $plainHash, $envelopeHash)
Write-Host 'DevAgent authenticated-journal primitive result: PASS' -ForegroundColor Green
Write-Host 'Qualification boundary: DPAPI user-scope envelope primitive only; native broker journal integration, path/ACL binding and restart recovery remain pending.' -ForegroundColor Yellow
