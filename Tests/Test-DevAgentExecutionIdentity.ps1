[CmdletBinding()]
param(
    [ValidateRange(2, 32)]
    [int] $ProfileCount = 8
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'The DevAgent execution-identity qualification requires Windows.'
}

if (-not ('Sharnou.DevAgentExecutionIdentityNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
using System.Text.RegularExpressions;

namespace Sharnou
{
    public static class DevAgentExecutionIdentityNative
    {
        private const uint BCryptUseSystemPreferredRng = 0x00000002;
        private const int HResultAlreadyExists = unchecked((int)0x800700B7);
        private const string ProfilePrefix = "Sharnou.DevAgent.";

        [DllImport("bcrypt.dll", EntryPoint = "BCryptGenRandom", ExactSpelling = true)]
        private static extern int BCryptGenRandom(
            IntPtr algorithm,
            [Out] byte[] buffer,
            uint bufferLength,
            uint flags);

        [DllImport("userenv.dll", EntryPoint = "CreateAppContainerProfile",
            CharSet = CharSet.Unicode, ExactSpelling = true, PreserveSig = true)]
        private static extern int CreateAppContainerProfile(
            string profileName,
            string displayName,
            string description,
            IntPtr capabilities,
            uint capabilityCount,
            out IntPtr appContainerSid);

        [DllImport("userenv.dll", EntryPoint = "DeriveAppContainerSidFromAppContainerName",
            CharSet = CharSet.Unicode, ExactSpelling = true, PreserveSig = true)]
        private static extern int DeriveAppContainerSidFromAppContainerName(
            string profileName,
            out IntPtr appContainerSid);

        [DllImport("userenv.dll", EntryPoint = "DeleteAppContainerProfile",
            CharSet = CharSet.Unicode, ExactSpelling = true, PreserveSig = true)]
        private static extern int DeleteAppContainerProfile(string profileName);

        [DllImport("advapi32.dll", EntryPoint = "ConvertSidToStringSidW",
            CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool ConvertSidToStringSid(
            IntPtr sid,
            out IntPtr stringSid);

        [DllImport("advapi32.dll", EntryPoint = "FreeSid", ExactSpelling = true)]
        private static extern IntPtr FreeSid(IntPtr sid);

        [DllImport("kernel32.dll", EntryPoint = "LocalFree", ExactSpelling = true)]
        private static extern IntPtr LocalFree(IntPtr memory);

        public static string NewProfileName()
        {
            byte[] random = new byte[16];
            int status = BCryptGenRandom(
                IntPtr.Zero, random, (uint)random.Length, BCryptUseSystemPreferredRng);
            if (status != 0)
                throw new InvalidOperationException(
                    "BCryptGenRandom failed with NTSTATUS 0x" + unchecked((uint)status).ToString("X8"));

            bool allZero = true;
            for (int i = 0; i < random.Length; i++)
                if (random[i] != 0) allZero = false;
            if (allZero)
                throw new InvalidOperationException("The system RNG returned an all-zero execution identifier.");

            StringBuilder name = new StringBuilder(ProfilePrefix, 64);
            for (int i = 0; i < random.Length; i++)
                name.Append(random[i].ToString("x2"));

            string result = name.ToString();
            ValidateProfileName(result);
            return result;
        }

        private static void ValidateProfileName(string profileName)
        {
            if (String.IsNullOrEmpty(profileName) ||
                profileName.Length > 64 ||
                !Regex.IsMatch(profileName, @"^Sharnou\.DevAgent\.[0-9a-f]{32}$",
                    RegexOptions.CultureInvariant))
                throw new ArgumentException("Profile name is outside the fixed Sharnou execution-identity format.");
        }

        private static string SidToString(IntPtr sid)
        {
            if (sid == IntPtr.Zero)
                throw new InvalidOperationException("The AppContainer API returned a null SID.");

            IntPtr text = IntPtr.Zero;
            if (!ConvertSidToStringSid(sid, out text))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "ConvertSidToStringSidW failed.");
            try
            {
                string value = Marshal.PtrToStringUni(text);
                if (String.IsNullOrEmpty(value) || !value.StartsWith("S-1-15-2-", StringComparison.Ordinal))
                    throw new InvalidOperationException("The returned SID is not an AppContainer package SID.");
                return value;
            }
            finally
            {
                if (text != IntPtr.Zero) LocalFree(text);
            }
        }

        public static string CreateNewZeroCapabilityProfile(string profileName)
        {
            ValidateProfileName(profileName);
            IntPtr sid = IntPtr.Zero;
            int hr = CreateAppContainerProfile(
                profileName,
                "Sharnou DevAgent execution " + profileName.Substring(ProfilePrefix.Length),
                "Ephemeral zero-capability identity qualification fixture.",
                IntPtr.Zero,
                0,
                out sid);

            if (hr != 0)
            {
                if (sid != IntPtr.Zero) FreeSid(sid);
                throw new InvalidOperationException(
                    "CreateAppContainerProfile did not create a new profile; HRESULT=0x" +
                    unchecked((uint)hr).ToString("X8") +
                    (hr == HResultAlreadyExists ? " (existing profile is never adopted)." : "."));
            }

            if (sid == IntPtr.Zero)
            {
                // A successful HRESULT without a SID is an invalid native result.
                DeleteAppContainerProfile(profileName);
                throw new InvalidOperationException("CreateAppContainerProfile succeeded without returning a SID.");
            }

            try
            {
                return SidToString(sid);
            }
            catch
            {
                // Do not leave an untracked profile if SID inspection fails.
                int cleanupHr = DeleteAppContainerProfile(profileName);
                if (cleanupHr != 0)
                    throw new InvalidOperationException(
                        "SID verification failed and profile cleanup also failed; HRESULT=0x" +
                        unchecked((uint)cleanupHr).ToString("X8"));
                throw;
            }
            finally
            {
                FreeSid(sid);
            }
        }

        public static string DeriveSid(string profileName)
        {
            ValidateProfileName(profileName);
            IntPtr sid = IntPtr.Zero;
            int hr = DeriveAppContainerSidFromAppContainerName(profileName, out sid);
            if (hr != 0)
            {
                if (sid != IntPtr.Zero) FreeSid(sid);
                throw new InvalidOperationException(
                    "DeriveAppContainerSidFromAppContainerName failed; HRESULT=0x" +
                    unchecked((uint)hr).ToString("X8"));
            }
            try { return SidToString(sid); }
            finally { if (sid != IntPtr.Zero) FreeSid(sid); }
        }

        public static void DeleteAndProveProfileCanBeRecreated(string profileName)
        {
            ValidateProfileName(profileName);
            int deleteHr = DeleteAppContainerProfile(profileName);
            if (deleteHr != 0)
                throw new InvalidOperationException(
                    "DeleteAppContainerProfile failed; HRESULT=0x" +
                    unchecked((uint)deleteHr).ToString("X8"));

            // A second Create must return S_OK. ERROR_ALREADY_EXISTS means the
            // profile survived cleanup, so the lifecycle test fails closed.
            IntPtr sid = IntPtr.Zero;
            int recreateHr = CreateAppContainerProfile(
                profileName,
                "Sharnou DevAgent execution cleanup verification",
                "Temporary profile recreated only to verify deletion semantics.",
                IntPtr.Zero,
                0,
                out sid);

            if (recreateHr != 0)
            {
                if (sid != IntPtr.Zero) FreeSid(sid);
                throw new InvalidOperationException(
                    "Profile was not absent after DeleteAppContainerProfile; Create HRESULT=0x" +
                    unchecked((uint)recreateHr).ToString("X8") +
                    (recreateHr == HResultAlreadyExists ? " (profile still existed)." : "."));
            }

            if (sid == IntPtr.Zero)
            {
                DeleteAppContainerProfile(profileName);
                throw new InvalidOperationException("Recreated profile did not return a SID.");
            }

            FreeSid(sid);
            int finalDeleteHr = DeleteAppContainerProfile(profileName);
            if (finalDeleteHr != 0)
                throw new InvalidOperationException(
                    "Final profile cleanup failed; HRESULT=0x" +
                    unchecked((uint)finalDeleteHr).ToString("X8"));
        }

        public static void BestEffortDelete(string profileName)
        {
            ValidateProfileName(profileName);
            int hr = DeleteAppContainerProfile(profileName);
            if (hr != 0)
                throw new InvalidOperationException(
                    "Best-effort profile cleanup failed; HRESULT=0x" +
                    unchecked((uint)hr).ToString("X8"));
        }
    }
}
'@
}

$names = New-Object 'System.Collections.Generic.List[string]'
$sids = New-Object 'System.Collections.Generic.List[string]'
$nameSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$sidSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)

try {
    for ($index = 0; $index -lt $ProfileCount; $index++) {
        $name = [Sharnou.DevAgentExecutionIdentityNative]::NewProfileName()
        if (-not $nameSet.Add($name)) {
            throw 'The CNG random generator produced a duplicate execution profile name.'
        }
        if ($name.Length -gt 64 -or $name -notmatch '^Sharnou\.DevAgent\.[0-9a-f]{32}$') {
            throw "Generated profile name violates the bounded native format: $name"
        }
        $names.Add($name)

        $sid = [Sharnou.DevAgentExecutionIdentityNative]::CreateNewZeroCapabilityProfile($name)
        if (-not $sidSet.Add($sid)) {
            throw 'Two distinct execution profile names produced the same AppContainer SID.'
        }
        $sids.Add($sid)

        $derivedSid = [Sharnou.DevAgentExecutionIdentityNative]::DeriveSid($name)
        if (-not [String]::Equals($sid, $derivedSid, [StringComparison]::Ordinal)) {
            throw "Derived AppContainer SID did not match the SID returned at profile creation for $name."
        }

        Write-Host ("PASS: unique 128-bit CNG execution ID created a new zero-capability AppContainer profile ({0})" -f $index) -ForegroundColor Green
    }

    if ($names.Count -ne $ProfileCount -or $sids.Count -ne $ProfileCount -or $sidSet.Count -ne $ProfileCount) {
        throw 'Execution identity cardinality mismatch.'
    }

    Write-Host ("PASS: {0} generated execution identities and AppContainer SIDs are pairwise distinct" -f $ProfileCount) -ForegroundColor Green
    Write-Host ("PASS: {0} AppContainer SID derivations match their exact profile names" -f $ProfileCount) -ForegroundColor Green
}
finally {
    # Attempt every cleanup even when one profile deletion fails. Report all
    # failures together so one stuck profile does not strand the remaining set.
    $cleanupFailures = New-Object 'System.Collections.Generic.List[string]'
    foreach ($name in $names) {
        try {
            [Sharnou.DevAgentExecutionIdentityNative]::DeleteAndProveProfileCanBeRecreated($name)
            Write-Host 'PASS: AppContainer profile deletion was verified by successful fresh recreation' -ForegroundColor Green
        }
        catch {
            $cleanupFailures.Add(('{0}: {1}' -f $name, $_.Exception.Message))
        }
    }
    if ($cleanupFailures.Count -gt 0) {
        throw ('One or more execution profiles could not be proven removed: ' + ($cleanupFailures -join ' | '))
    }
}

Write-Host 'DevAgent execution identity primitive result: PASS' -ForegroundColor Green
Write-Host 'Qualification boundary: profile identity/create/derive/delete primitive only; native broker integration and crash recovery remain pending.' -ForegroundColor Yellow
