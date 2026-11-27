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
using System.Collections.Generic;
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
            {
                // The API documents an indeterminate profile state on failure
                // and recommends retrying deletion.
                int retryDeleteHr = DeleteAppContainerProfile(profileName);
                if (retryDeleteHr != 0)
                    throw new InvalidOperationException(
                        "DeleteAppContainerProfile failed twice; HRESULTs=0x" +
                        unchecked((uint)deleteHr).ToString("X8") + "/0x" +
                        unchecked((uint)retryDeleteHr).ToString("X8"));
            }

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
                int cleanupHr = DeleteAppContainerProfile(profileName);
                if (cleanupHr != 0)
                    throw new InvalidOperationException(
                        "Profile recreation failed and cleanup retry also failed; Create HRESULT=0x" +
                        unchecked((uint)recreateHr).ToString("X8") + ", Delete HRESULT=0x" +
                        unchecked((uint)cleanupHr).ToString("X8"));
                throw new InvalidOperationException(
                    "Profile was not proven absent after DeleteAppContainerProfile; Create HRESULT=0x" +
                    unchecked((uint)recreateHr).ToString("X8") +
                    (recreateHr == HResultAlreadyExists ? " (profile still existed; cleanup retry succeeded)." : "."));
            }

            if (sid == IntPtr.Zero)
            {
                DeleteAppContainerProfile(profileName);
                throw new InvalidOperationException("Recreated profile did not return a SID.");
            }

            FreeSid(sid);
            int finalDeleteHr = DeleteAppContainerProfile(profileName);
            if (finalDeleteHr != 0)
            {
                int finalRetryHr = DeleteAppContainerProfile(profileName);
                if (finalRetryHr != 0)
                    throw new InvalidOperationException(
                        "Final profile cleanup failed twice; HRESULTs=0x" +
                        unchecked((uint)finalDeleteHr).ToString("X8") + "/0x" +
                        unchecked((uint)finalRetryHr).ToString("X8"));
            }
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

        [StructLayout(LayoutKind.Sequential)]
        private struct STARTUPINFOW
        {
            public uint cb;
            public IntPtr lpReserved;
            public IntPtr lpDesktop;
            public IntPtr lpTitle;
            public uint dwX, dwY, dwXSize, dwYSize;
            public uint dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
            public ushort wShowWindow, cbReserved2;
            public IntPtr lpReserved2;
            public IntPtr hStdInput, hStdOutput, hStdError;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct STARTUPINFOEXW
        {
            public STARTUPINFOW StartupInfo;
            public IntPtr lpAttributeList;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct SECURITY_CAPABILITIES
        {
            public IntPtr AppContainerSid;
            public IntPtr Capabilities;
            public uint CapabilityCount;
            public uint Reserved;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct PROCESS_INFORMATION
        {
            public IntPtr hProcess;
            public IntPtr hThread;
            public uint dwProcessId;
            public uint dwThreadId;
        }

        [DllImport("userenv.dll", EntryPoint = "CreateEnvironmentBlock",
            ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CreateEnvironmentBlock(
            out IntPtr environmentBlock,
            IntPtr token,
            [MarshalAs(UnmanagedType.Bool)] bool inherit);

        [DllImport("userenv.dll", EntryPoint = "DestroyEnvironmentBlock",
            ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool DestroyEnvironmentBlock(IntPtr environmentBlock);

        [DllImport("kernel32.dll", EntryPoint = "GetEnvironmentStringsW",
            CharSet = CharSet.Unicode, ExactSpelling = true)]
        private static extern IntPtr GetEnvironmentStringsW();

        [DllImport("kernel32.dll", EntryPoint = "FreeEnvironmentStringsW",
            CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool FreeEnvironmentStringsW(IntPtr environmentBlock);

        [DllImport("kernel32.dll", EntryPoint = "InitializeProcThreadAttributeList",
            ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool InitializeProcThreadAttributeList(
            IntPtr attributeList, int attributeCount, uint flags, ref IntPtr size);

        [DllImport("kernel32.dll", EntryPoint = "UpdateProcThreadAttribute",
            ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool UpdateProcThreadAttribute(
            IntPtr attributeList, uint flags, IntPtr attribute, IntPtr value,
            UIntPtr size, IntPtr previousValue, IntPtr returnSize);

        [DllImport("kernel32.dll", EntryPoint = "DeleteProcThreadAttributeList",
            ExactSpelling = true)]
        private static extern void DeleteProcThreadAttributeList(IntPtr attributeList);

        [DllImport("kernel32.dll", EntryPoint = "CreateProcessW",
            CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CreateProcessW(
            string applicationName, StringBuilder commandLine,
            IntPtr processAttributes, IntPtr threadAttributes,
            [MarshalAs(UnmanagedType.Bool)] bool inheritHandles,
            uint creationFlags, IntPtr environment, string currentDirectory,
            ref STARTUPINFOEXW startupInfo, out PROCESS_INFORMATION processInformation);

        [DllImport("kernel32.dll", EntryPoint = "OpenProcessToken",
            ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool OpenProcessToken(
            IntPtr processHandle, uint desiredAccess, out IntPtr tokenHandle);

        [DllImport("advapi32.dll", EntryPoint = "GetTokenInformation",
            ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetTokenInformation(
            IntPtr tokenHandle, int informationClass, IntPtr information,
            uint informationLength, out uint returnLength);

        [DllImport("advapi32.dll", EntryPoint = "GetSidSubAuthorityCount",
            ExactSpelling = true)]
        private static extern IntPtr GetSidSubAuthorityCount(IntPtr sid);

        [DllImport("advapi32.dll", EntryPoint = "GetSidSubAuthority",
            ExactSpelling = true)]
        private static extern IntPtr GetSidSubAuthority(IntPtr sid, uint subAuthority);

        [DllImport("kernel32.dll", EntryPoint = "TerminateProcess",
            ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool TerminateProcess(IntPtr process, uint exitCode);

        [DllImport("kernel32.dll", EntryPoint = "WaitForSingleObject",
            ExactSpelling = true, SetLastError = true)]
        private static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);

        [DllImport("kernel32.dll", EntryPoint = "CloseHandle",
            ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CloseHandle(IntPtr handle);

        private static IntPtr QueryTokenInformation(IntPtr token, int informationClass)
        {
            uint required = 0;
            GetTokenInformation(token, informationClass, IntPtr.Zero, 0, out required);
            int error = Marshal.GetLastWin32Error();
            if (required == 0 || (error != 122 && error != 0))
                throw new Win32Exception(error, "GetTokenInformation sizing query failed for class " + informationClass + ".");
            IntPtr buffer = Marshal.AllocHGlobal(checked((int)required));
            if (!GetTokenInformation(token, informationClass, buffer, required, out required))
            {
                error = Marshal.GetLastWin32Error();
                Marshal.FreeHGlobal(buffer);
                throw new Win32Exception(error, "GetTokenInformation failed for class " + informationClass + ".");
            }
            return buffer;
        }

        public static string CreateSuspendedAppContainerChildAndVerify(string profileName, string expectedSid)
        {
            ValidateProfileName(profileName);
            IntPtr packageSid = IntPtr.Zero;
            IntPtr attributeList = IntPtr.Zero;
            IntPtr attributeBuffer = IntPtr.Zero;
            IntPtr environment = IntPtr.Zero;
            IntPtr securityCapabilitiesPtr = IntPtr.Zero;
            IntPtr childToken = IntPtr.Zero;
            PROCESS_INFORMATION process = new PROCESS_INFORMATION();
            bool childCreated = false;
            bool attributeListInitialized = false;

            try
            {
                int hr = DeriveAppContainerSidFromAppContainerName(profileName, out packageSid);
                if (hr != 0 || packageSid == IntPtr.Zero)
                    throw new InvalidOperationException(
                        "Cannot derive package SID for child-token probe; HRESULT=0x" + unchecked((uint)hr).ToString("X8"));

                string derivedSid = SidToString(packageSid);
                if (!String.Equals(derivedSid, expectedSid, StringComparison.Ordinal))
                    throw new InvalidOperationException("Child-token probe received a mismatched profile SID.");

                IntPtr attributeSize = IntPtr.Zero;
                bool sizingResult = InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref attributeSize);
                int sizingError = Marshal.GetLastWin32Error();
                if (sizingResult || sizingError != 122 || attributeSize.ToInt64() < 1 || attributeSize.ToInt64() > 65536)
                    throw new Win32Exception(sizingError, "InitializeProcThreadAttributeList sizing contract failed.");

                attributeBuffer = Marshal.AllocHGlobal(attributeSize);
                attributeList = attributeBuffer;
                if (!InitializeProcThreadAttributeList(attributeList, 1, 0, ref attributeSize))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "InitializeProcThreadAttributeList failed.");
                attributeListInitialized = true;

                SECURITY_CAPABILITIES securityCapabilities = new SECURITY_CAPABILITIES();
                securityCapabilities.AppContainerSid = packageSid;
                securityCapabilities.Capabilities = IntPtr.Zero;
                securityCapabilities.CapabilityCount = 0;
                securityCapabilities.Reserved = 0;
                // UpdateProcThreadAttribute retains the supplied value pointer until
                // CreateProcessW consumes the attribute list. Keep this allocation
                // alive through process creation; freeing it immediately is unsafe.
                securityCapabilitiesPtr = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(SECURITY_CAPABILITIES)));
                Marshal.StructureToPtr(securityCapabilities, securityCapabilitiesPtr, false);
                IntPtr securityCapabilitiesAttribute = new IntPtr(0x00020009); // PROC_THREAD_ATTRIBUTE_SECURITY_CAPABILITIES
                if (!UpdateProcThreadAttribute(
                    attributeList, 0, securityCapabilitiesAttribute, securityCapabilitiesPtr,
                    new UIntPtr((uint)Marshal.SizeOf(typeof(SECURITY_CAPABILITIES))), IntPtr.Zero, IntPtr.Zero))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "Security-capabilities process attribute failed.");

                string systemDirectory = Environment.SystemDirectory;
                string application = System.IO.Path.Combine(systemDirectory, "cmd.exe");

                // Seed from the OS-generated environment with inheritance disabled,
                // then copy only fixed policy-owned values into a new bounded block.
                // Never pass the original block or inherit arbitrary runner variables.
                IntPtr templateEnvironment = IntPtr.Zero;
                if (!CreateEnvironmentBlock(out templateEnvironment, IntPtr.Zero, false))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateEnvironmentBlock(inherit=false) failed.");

                string systemRoot = null;
                try
                {
                    bool terminated = false;
                    int offsetCharacters = 0;
                    for (int entryIndex = 0; entryIndex < 32768; entryIndex++)
                    {
                        string entry = Marshal.PtrToStringUni(IntPtr.Add(templateEnvironment, checked(offsetCharacters * 2)));
                        if (String.IsNullOrEmpty(entry))
                        {
                            terminated = true;
                            break;
                        }
                        offsetCharacters = checked(offsetCharacters + entry.Length + 1);
                        if (entry[0] == '=') continue; // discard hidden per-drive entries
                        int separator = entry.IndexOf('=');
                        if (separator <= 0) continue;
                        string key = entry.Substring(0, separator);
                        if (String.Equals(key, "SystemRoot", StringComparison.OrdinalIgnoreCase))
                            systemRoot = entry.Substring(separator + 1);
                    }
                    if (systemRoot == null)
                        throw new InvalidOperationException("CreateEnvironmentBlock did not provide SystemRoot.");
                    if (!terminated)
                        throw new InvalidOperationException("CreateEnvironmentBlock lacked a bounded double-NUL terminator.");
                }
                finally
                {
                    if (!DestroyEnvironmentBlock(templateEnvironment))
                        throw new Win32Exception(Marshal.GetLastWin32Error(), "DestroyEnvironmentBlock failed.");
                }

                // Preserve only Windows' special per-drive current-directory
                // entries from the parent environment. They are not ordinary
                // variables; dropping them can cause CreateProcessW error 203
                // on cross-drive hosts. All other parent values are discarded.
                IntPtr parentEnvironment = GetEnvironmentStringsW();
                if (parentEnvironment == IntPtr.Zero)
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "GetEnvironmentStringsW failed.");
                var allowedEnvironmentList = new List<string>();
                var driveEntryNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                try
                {
                    bool parentTerminated = false;
                    int parentOffset = 0;
                    for (int entryIndex = 0; entryIndex < 32768; entryIndex++)
                    {
                        string entry = Marshal.PtrToStringUni(IntPtr.Add(parentEnvironment, checked(parentOffset * 2)));
                        if (String.IsNullOrEmpty(entry))
                        {
                            parentTerminated = true;
                            break;
                        }
                        parentOffset = checked(parentOffset + entry.Length + 1);
                        if (entry.Length < 4 || entry[0] != '=' ||
                            !Char.IsLetter(entry[1]) || entry[2] != ':' || entry[3] != '=')
                            continue;

                        string driveName = entry.Substring(0, 3);
                        string drivePath = entry.Substring(4);
                        string expectedRoot = driveName.Substring(1, 2) + "\\";
                        if (!System.IO.Path.IsPathRooted(drivePath) ||
                            !String.Equals(System.IO.Path.GetPathRoot(drivePath), expectedRoot, StringComparison.OrdinalIgnoreCase))
                            throw new InvalidOperationException("Malformed hidden per-drive current-directory entry.");
                        if (!driveEntryNames.Add(driveName))
                            throw new InvalidOperationException("Duplicate hidden per-drive environment entry.");
                        allowedEnvironmentList.Add(entry);
                    }
                    if (!parentTerminated)
                        throw new InvalidOperationException("Parent environment block lacked a bounded double-NUL terminator.");
                }
                finally
                {
                    if (!FreeEnvironmentStringsW(parentEnvironment))
                        throw new Win32Exception(Marshal.GetLastWin32Error(), "FreeEnvironmentStringsW failed.");
                }
                allowedEnvironmentList.Add("ComSpec=" + application);
                allowedEnvironmentList.Add("PATH=" + systemDirectory);
                allowedEnvironmentList.Add("SystemDrive=" + systemDrive);
                allowedEnvironmentList.Add("SystemRoot=" + systemRoot);
                allowedEnvironmentList.Add("windir=" + systemRoot);
                string[] allowedEnvironment = allowedEnvironmentList.ToArray();
                Array.Sort(allowedEnvironment, StringComparer.OrdinalIgnoreCase);
                string environmentText = String.Join("\0", allowedEnvironment) + "\0\0";
                if (environmentText.Length > 32768)
                    throw new InvalidOperationException("Explicit child environment exceeds the 32768-WCHAR policy bound.");
                char[] environmentChars = environmentText.ToCharArray();
                environment = Marshal.AllocHGlobal(checked(environmentChars.Length * 2));
                for (int environmentIndex = 0; environmentIndex < environmentChars.Length; environmentIndex++)
                    Marshal.WriteInt16(environment, environmentIndex * 2, (short)environmentChars[environmentIndex]);

                StringBuilder commandLine = new StringBuilder("\"" + application + "\" /c exit 0");
                STARTUPINFOEXW startup = new STARTUPINFOEXW();
                startup.StartupInfo.cb = (uint)Marshal.SizeOf(typeof(STARTUPINFOEXW));
                startup.lpAttributeList = attributeList;
                uint creationFlags = 0x00080004 | 0x00000400 | 0x08000000; // EXTENDED_STARTUPINFO_PRESENT | CREATE_SUSPENDED | CREATE_UNICODE_ENVIRONMENT | CREATE_NO_WINDOW

                if (!CreateProcessW(
                    application, commandLine, IntPtr.Zero, IntPtr.Zero, false,
                    creationFlags, environment, systemDirectory, ref startup, out process))
                {
                    int createError = Marshal.GetLastWin32Error();
                    throw new Win32Exception(createError,
                        "CreateProcessW AppContainer child creation failed (Win32=" + createError +
                        "; app=" + application + "; startup.cb=" + startup.StartupInfo.cb +
                        "; startupExSize=" + Marshal.SizeOf(typeof(STARTUPINFOEXW)) + ").");
                }

                childCreated = true;
                if (!OpenProcessToken(process.hProcess, 0x0008, out childToken))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "OpenProcessToken on suspended AppContainer child failed.");

                IntPtr appContainerInfo = IntPtr.Zero;
                IntPtr appContainerFlag = IntPtr.Zero;
                IntPtr capabilitiesInfo = IntPtr.Zero;
                IntPtr integrityInfo = IntPtr.Zero;
                try
                {
                    appContainerFlag = QueryTokenInformation(childToken, 29); // TokenIsAppContainer
                    if (Marshal.ReadInt32(appContainerFlag) != 1)
                        throw new InvalidOperationException("Suspended child token is not marked as an AppContainer.");

                    appContainerInfo = QueryTokenInformation(childToken, 31); // TokenAppContainerSid
                    IntPtr actualSid = Marshal.ReadIntPtr(appContainerInfo);
                    string actualSidText = SidToString(actualSid);
                    if (!String.Equals(actualSidText, expectedSid, StringComparison.Ordinal))
                        throw new InvalidOperationException("Suspended child token package SID differs from the execution profile SID.");

                    capabilitiesInfo = QueryTokenInformation(childToken, 30); // TokenCapabilities (TOKEN_GROUPS)
                    uint capabilityCount = unchecked((uint)Marshal.ReadInt32(capabilitiesInfo));
                    if (capabilityCount != 0)
                        throw new InvalidOperationException("Suspended AppContainer child unexpectedly has capability SIDs: " + capabilityCount);

                    integrityInfo = QueryTokenInformation(childToken, 25); // TokenIntegrityLevel
                    IntPtr integritySid = Marshal.ReadIntPtr(integrityInfo);
                    IntPtr subAuthorityCount = GetSidSubAuthorityCount(integritySid);
                    if (subAuthorityCount == IntPtr.Zero)
                        throw new Win32Exception(Marshal.GetLastWin32Error(), "GetSidSubAuthorityCount failed.");
                    byte count = Marshal.ReadByte(subAuthorityCount);
                    if (count == 0)
                        throw new InvalidOperationException("Child integrity SID has no subauthorities.");
                    IntPtr ridPtr = GetSidSubAuthority(integritySid, (uint)(count - 1));
                    if (ridPtr == IntPtr.Zero)
                        throw new Win32Exception(Marshal.GetLastWin32Error(), "GetSidSubAuthority failed.");
                    uint integrityRid = unchecked((uint)Marshal.ReadInt32(ridPtr));
                    if (integrityRid != 0x1000)
                        throw new InvalidOperationException("AppContainer child integrity RID is not Low (0x1000): 0x" + integrityRid.ToString("X"));

                    return "AppContainer=1;PackageSID=" + actualSidText +
                        ";IntegrityRID=0x" + integrityRid.ToString("X") +
                        ";Capabilities=" + capabilityCount.ToString() +
                        ";Environment=ComSpec,PATH,SystemRoot,windir";
                }
                finally
                {
                    if (integrityInfo != IntPtr.Zero) Marshal.FreeHGlobal(integrityInfo);
                    if (capabilitiesInfo != IntPtr.Zero) Marshal.FreeHGlobal(capabilitiesInfo);
                    if (appContainerInfo != IntPtr.Zero) Marshal.FreeHGlobal(appContainerInfo);
                    if (appContainerFlag != IntPtr.Zero) Marshal.FreeHGlobal(appContainerFlag);
                }
            }
            finally
            {
                if (childToken != IntPtr.Zero) CloseHandle(childToken);
                if (childCreated && process.hProcess != IntPtr.Zero)
                {
                    TerminateProcess(process.hProcess, 0x2BAD);
                    uint wait = WaitForSingleObject(process.hProcess, 10000);
                    if (wait != 0)
                        throw new InvalidOperationException("Suspended AppContainer child did not terminate within 10 seconds.");
                }
                if (process.hThread != IntPtr.Zero) CloseHandle(process.hThread);
                if (process.hProcess != IntPtr.Zero) CloseHandle(process.hProcess);
                if (attributeListInitialized) DeleteProcThreadAttributeList(attributeList);
                if (securityCapabilitiesPtr != IntPtr.Zero) Marshal.FreeHGlobal(securityCapabilitiesPtr);
                if (attributeBuffer != IntPtr.Zero) Marshal.FreeHGlobal(attributeBuffer);
                if (environment != IntPtr.Zero) Marshal.FreeHGlobal(environment);
                if (packageSid != IntPtr.Zero) FreeSid(packageSid);
            }
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
        $sid = [Sharnou.DevAgentExecutionIdentityNative]::CreateNewZeroCapabilityProfile($name)
        # Track only profiles this invocation actually created. A failed
        # ERROR_ALREADY_EXISTS result must never cause cleanup to delete a
        # pre-existing profile belonging to another run.
        $names.Add($name)
        if (-not $sidSet.Add($sid)) {
            throw 'Two distinct execution profile names produced the same AppContainer SID.'
        }
        $sids.Add($sid)

        $derivedSid = [Sharnou.DevAgentExecutionIdentityNative]::DeriveSid($name)
        if (-not [String]::Equals($sid, $derivedSid, [StringComparison]::Ordinal)) {
            throw "Derived AppContainer SID did not match the SID returned at profile creation for $name."
        }

        $childTokenSummary = [Sharnou.DevAgentExecutionIdentityNative]::CreateSuspendedAppContainerChildAndVerify($name, $sid)
        Write-Host ("PASS: suspended child token independently verified: {0}" -f $childTokenSummary) -ForegroundColor Green
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
