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
                if (profileLength != 48)
                    throw new InvalidDataException("AppContainer profile name length is invalid.");
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

                uint volumeSerial = reader.ReadUInt32();
                ulong workspaceFileId = reader.ReadUInt64();
                if (volumeSerial == 0 || workspaceFileId == 0)
                    throw new InvalidDataException("Canonical workspace file identity is missing.");

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
        $writer.Write([uint32]12345) # synthetic volume serial for parser qualification
        $writer.Write([uint64]0x123456789ABCDEF0) # synthetic file ID for parser qualification
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
$packageSid = 'S-1-15-2-123456789-234567890-345678901-456789012'
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
[BitConverter]::GetBytes([uint32]0).CopyTo($badWorkspaceIdentity, $workspaceVolumeOffset)
$parserRejectCases.Add(@{ Name = 'missing workspace volume identity'; Bytes = $badWorkspaceIdentity })

foreach ($case in $parserRejectCases) {
    $rejected = $false
    try {
        [Sharnou.DevAgentDpapiJournalNative]::ValidateCanonicalJournalV2([byte[]]$case.Bytes)
    }
    catch [IO.InvalidDataException] {
        $rejected = $true
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

$plainHash = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($plaintext)).Replace('-', '')
$envelopeHash = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($protected)).Replace('-', '')
Write-Host ("PASS: DPAPI current-user envelope round-tripped exact canonical v2 journal payload ({0} bytes)" -f $plaintext.Length) -ForegroundColor Green
Write-Host 'PASS: DPAPI optional entropy binds the envelope to the Sharnou journal context' -ForegroundColor Green
Write-Host 'PASS: cleartext execution identity, package SID and journal magic are absent from the protected envelope' -ForegroundColor Green
Write-Host ("DPAPI fixture SHA-256: plaintext={0}; envelope={1}" -f $plainHash, $envelopeHash)
Write-Host 'DevAgent authenticated-journal primitive result: PASS' -ForegroundColor Green
Write-Host 'Qualification boundary: DPAPI user-scope envelope primitive only; native broker journal integration, path/ACL binding and restart recovery remain pending.' -ForegroundColor Yellow
