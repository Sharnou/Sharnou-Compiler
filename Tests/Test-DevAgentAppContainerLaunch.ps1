[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'The AppContainer CreateProcessAsUserW qualification requires Windows.'
}

if (-not ('Sharnou.DevAgentAppContainerLaunchNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;

namespace Sharnou
{
    public static class DevAgentAppContainerLaunchNative
    {
        private const uint BCryptUseSystemPreferredRng = 0x00000002;
        private const uint TokenAssignPrimary = 0x0001;
        private const uint TokenDuplicate = 0x0002;
        private const uint TokenQuery = 0x0008;
        private const uint TokenAdjustDefault = 0x0080;
        private const uint DisableMaxPrivilege = 0x00000001;
        private const uint CreateSuspended = 0x00000004;
        private const uint ExtendedStartupInfoPresent = 0x00080000;
        private const uint CreateUnicodeEnvironment = 0x00000400;
        private const uint CreateNoWindow = 0x08000000;
        private const uint HandleFlagInherit = 0x00000001;
        private const uint StartfUseStdHandles = 0x00000100;
        private const uint JobObjectLimitActiveProcess = 0x00000008;
        private const uint JobObjectLimitKillOnJobClose = 0x00002000;
        private const uint FileShareReadWrite = 0x00000003;
        private const uint OpenExisting = 3;
        private const uint FileAttributeNormal = 0x00000080;
        private const uint GenericRead = 0x80000000;
        private const uint ProcThreadAttributeHandleList = 0x00020002;
        private const uint ProcThreadAttributeSecurityCapabilities = 0x00020009;
        private const int JobObjectExtendedLimitInformation = 9;
        private const int JobObjectBasicAccountingInformation = 1;
        private const string ProfilePrefix = "Sharnou.DevAgent.";
        private const int PerStreamLimit = 4096;
        private const int CombinedOutputLimit = 8192;

        [StructLayout(LayoutKind.Sequential)]
        private struct SECURITY_ATTRIBUTES
        {
            public int Length;
            public IntPtr SecurityDescriptor;
            [MarshalAs(UnmanagedType.Bool)]
            public bool InheritHandle;
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
        private struct PROCESS_INFORMATION
        {
            public IntPtr hProcess;
            public IntPtr hThread;
            public uint ProcessId;
            public uint ThreadId;
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
        private struct JOBOBJECT_BASIC_LIMIT_INFORMATION
        {
            public long PerProcessUserTimeLimit;
            public long PerJobUserTimeLimit;
            public uint LimitFlags;
            public UIntPtr MinimumWorkingSetSize;
            public UIntPtr MaximumWorkingSetSize;
            public uint ActiveProcessLimit;
            public UIntPtr Affinity;
            public uint PriorityClass;
            public uint SchedulingClass;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct IO_COUNTERS
        {
            public ulong ReadOperationCount;
            public ulong WriteOperationCount;
            public ulong OtherOperationCount;
            public ulong ReadTransferCount;
            public ulong WriteTransferCount;
            public ulong OtherTransferCount;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION
        {
            public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
            public IO_COUNTERS IoInfo;
            public UIntPtr ProcessMemoryLimit;
            public UIntPtr JobMemoryLimit;
            public UIntPtr PeakProcessMemoryUsed;
            public UIntPtr PeakJobMemoryUsed;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct JOBOBJECT_BASIC_ACCOUNTING_INFORMATION
        {
            public long TotalUserTime;
            public long TotalKernelTime;
            public long ThisPeriodTotalUserTime;
            public long ThisPeriodTotalKernelTime;
            public uint TotalPageFaultCount;
            public uint TotalProcesses;
            public uint ActiveProcesses;
            public uint TotalTerminatedProcesses;
        }

        [DllImport("bcrypt.dll", EntryPoint = "BCryptGenRandom", ExactSpelling = true)]
        private static extern int BCryptGenRandom(IntPtr algorithm, [Out] byte[] buffer, uint length, uint flags);

        [DllImport("kernel32.dll", EntryPoint = "GetEnvironmentStringsW", CharSet = CharSet.Unicode, ExactSpelling = true)]
        private static extern IntPtr GetEnvironmentStringsW();

        [DllImport("kernel32.dll", EntryPoint = "FreeEnvironmentStringsW", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool FreeEnvironmentStringsW(IntPtr environmentBlock);

        [DllImport("userenv.dll", EntryPoint = "CreateAppContainerProfile",
            CharSet = CharSet.Unicode, ExactSpelling = true, PreserveSig = true)]
        private static extern int CreateAppContainerProfile(
            string profileName, string displayName, string description,
            IntPtr capabilities, uint capabilityCount, out IntPtr appContainerSid);

        [DllImport("userenv.dll", EntryPoint = "DeleteAppContainerProfile",
            CharSet = CharSet.Unicode, ExactSpelling = true, PreserveSig = true)]
        private static extern int DeleteAppContainerProfile(string profileName);

        [DllImport("advapi32.dll", EntryPoint = "ConvertSidToStringSidW",
            CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool ConvertSidToStringSid(IntPtr sid, out IntPtr stringSid);

        [DllImport("advapi32.dll", EntryPoint = "FreeSid", ExactSpelling = true)]
        private static extern IntPtr FreeSid(IntPtr sid);

        [DllImport("kernel32.dll", EntryPoint = "LocalFree", ExactSpelling = true)]
        private static extern IntPtr LocalFree(IntPtr memory);

        [DllImport("kernel32.dll", EntryPoint = "GetCurrentProcess", ExactSpelling = true)]
        private static extern IntPtr GetCurrentProcess();

        [DllImport("advapi32.dll", EntryPoint = "OpenProcessToken", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool OpenProcessToken(IntPtr process, uint desiredAccess, out IntPtr token);

        [DllImport("advapi32.dll", EntryPoint = "CreateRestrictedToken", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CreateRestrictedToken(
            IntPtr existingToken, uint flags, uint disableSidCount, IntPtr sidsToDisable,
            uint deletePrivilegeCount, IntPtr privilegesToDelete, uint restrictedSidCount,
            IntPtr sidsToRestrict, out IntPtr newToken);

        [DllImport("advapi32.dll", EntryPoint = "GetTokenInformation", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetTokenInformation(
            IntPtr token, int informationClass, IntPtr information,
            uint informationLength, out uint returnLength);

        [DllImport("advapi32.dll", EntryPoint = "GetSidSubAuthorityCount", ExactSpelling = true)]
        private static extern IntPtr GetSidSubAuthorityCount(IntPtr sid);

        [DllImport("advapi32.dll", EntryPoint = "GetSidSubAuthority", ExactSpelling = true)]
        private static extern IntPtr GetSidSubAuthority(IntPtr sid, uint index);

        [DllImport("kernel32.dll", EntryPoint = "InitializeProcThreadAttributeList", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool InitializeProcThreadAttributeList(
            IntPtr list, int attributeCount, uint flags, ref IntPtr size);

        [DllImport("kernel32.dll", EntryPoint = "UpdateProcThreadAttribute", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool UpdateProcThreadAttribute(
            IntPtr list, uint flags, IntPtr attribute, IntPtr value,
            UIntPtr size, IntPtr previousValue, IntPtr returnSize);

        [DllImport("kernel32.dll", EntryPoint = "DeleteProcThreadAttributeList", ExactSpelling = true)]
        private static extern void DeleteProcThreadAttributeList(IntPtr list);

        [DllImport("advapi32.dll", EntryPoint = "CreateProcessAsUserW",
            CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CreateProcessAsUserW(
            IntPtr token, string applicationName, StringBuilder commandLine,
            IntPtr processAttributes, IntPtr threadAttributes,
            [MarshalAs(UnmanagedType.Bool)] bool inheritHandles,
            uint creationFlags, IntPtr environment, string currentDirectory,
            ref STARTUPINFOEXW startupInfo, out PROCESS_INFORMATION processInformation);

        [DllImport("kernel32.dll", EntryPoint = "CreatePipe", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CreatePipe(
            out IntPtr readPipe, out IntPtr writePipe,
            ref SECURITY_ATTRIBUTES attributes, uint size);

        [DllImport("kernel32.dll", EntryPoint = "SetHandleInformation", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetHandleInformation(IntPtr handle, uint mask, uint flags);

        [DllImport("kernel32.dll", EntryPoint = "GetHandleInformation", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetHandleInformation(IntPtr handle, out uint flags);

        [DllImport("kernel32.dll", EntryPoint = "CreateFileW",
            CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
        private static extern IntPtr CreateFileW(
            string name, uint access, uint share,
            ref SECURITY_ATTRIBUTES attributes, uint disposition,
            uint flags, IntPtr template);

        [DllImport("kernel32.dll", EntryPoint = "CreateJobObjectW",
            CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
        private static extern IntPtr CreateJobObjectW(IntPtr attributes, string name);

        [DllImport("kernel32.dll", EntryPoint = "SetInformationJobObject", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetInformationJobObject(
            IntPtr job, int informationClass,
            ref JOBOBJECT_EXTENDED_LIMIT_INFORMATION information, uint informationLength);

        [DllImport("kernel32.dll", EntryPoint = "AssignProcessToJobObject", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);

        [DllImport("kernel32.dll", EntryPoint = "QueryInformationJobObject", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool QueryInformationJobObject(
            IntPtr job, int informationClass,
            out JOBOBJECT_BASIC_ACCOUNTING_INFORMATION information,
            uint informationLength, IntPtr returnLength);

        [DllImport("kernel32.dll", EntryPoint = "ResumeThread", ExactSpelling = true, SetLastError = true)]
        private static extern uint ResumeThread(IntPtr thread);

        [DllImport("kernel32.dll", EntryPoint = "TerminateJobObject", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool TerminateJobObject(IntPtr job, uint exitCode);

        [DllImport("kernel32.dll", EntryPoint = "TerminateProcess", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool TerminateProcess(IntPtr process, uint exitCode);

        [DllImport("kernel32.dll", EntryPoint = "WaitForSingleObject", ExactSpelling = true, SetLastError = true)]
        private static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);

        [DllImport("kernel32.dll", EntryPoint = "PeekNamedPipe", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool PeekNamedPipe(
            IntPtr pipe, IntPtr buffer, uint bufferSize,
            IntPtr bytesRead, out uint bytesAvailable, IntPtr bytesLeftThisMessage);

        [DllImport("kernel32.dll", EntryPoint = "ReadFile", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool ReadFile(
            IntPtr file, [Out] byte[] buffer, uint bytesToRead,
            out uint bytesRead, IntPtr overlapped);

        [DllImport("kernel32.dll", EntryPoint = "GetExitCodeProcess", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetExitCodeProcess(IntPtr process, out uint exitCode);

        [DllImport("kernel32.dll", EntryPoint = "CloseHandle", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CloseHandle(IntPtr handle);

        private static void Check(bool result, string operation)
        {
            if (!result)
            {
                int error = Marshal.GetLastWin32Error();
                throw new Win32Exception(error, operation + " failed (Win32=" + error + ").");
            }
        }

        private static string NewProfileName()
        {
            byte[] random = new byte[16];
            int status = BCryptGenRandom(IntPtr.Zero, random, (uint)random.Length, BCryptUseSystemPreferredRng);
            if (status != 0) throw new InvalidOperationException("BCryptGenRandom NTSTATUS=0x" + unchecked((uint)status).ToString("X8"));
            StringBuilder result = new StringBuilder(ProfilePrefix, 64);
            for (int i = 0; i < random.Length; i++) result.Append(random[i].ToString("x2"));
            return result.ToString();
        }

        private static string SidToString(IntPtr sid)
        {
            IntPtr text = IntPtr.Zero;
            if (sid == IntPtr.Zero || !ConvertSidToStringSid(sid, out text))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "ConvertSidToStringSidW failed.");
            try
            {
                string value = Marshal.PtrToStringUni(text);
                if (String.IsNullOrEmpty(value) || !value.StartsWith("S-1-15-2-", StringComparison.Ordinal))
                    throw new InvalidOperationException("Native API returned a non-AppContainer package SID.");
                return value;
            }
            finally { if (text != IntPtr.Zero) LocalFree(text); }
        }

        private static IntPtr QueryToken(IntPtr token, int informationClass)
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

        private static uint ReadIntegrityRid(IntPtr token)
        {
            IntPtr info = QueryToken(token, 25);
            try
            {
                IntPtr sid = Marshal.ReadIntPtr(info);
                IntPtr countPointer = GetSidSubAuthorityCount(sid);
                if (countPointer == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "GetSidSubAuthorityCount failed.");
                byte count = Marshal.ReadByte(countPointer);
                if (count == 0) throw new InvalidOperationException("Integrity SID contains no subauthorities.");
                IntPtr rid = GetSidSubAuthority(sid, (uint)(count - 1));
                if (rid == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "GetSidSubAuthority failed.");
                return unchecked((uint)Marshal.ReadInt32(rid));
            }
            finally { Marshal.FreeHGlobal(info); }
        }

        private static List<string> ReadApprovedDriveEntries()
        {
            IntPtr source = GetEnvironmentStringsW();
            if (source == IntPtr.Zero)
                throw new Win32Exception(Marshal.GetLastWin32Error(), "GetEnvironmentStringsW failed.");

            List<string> entries = new List<string>();
            HashSet<string> driveNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            try
            {
                int offset = 0;
                bool terminated = false;
                for (int index = 0; index < 32768; index++)
                {
                    if (offset >= 32767)
                        throw new InvalidOperationException("Parent environment block exceeds its scan bound.");
                    string entry = Marshal.PtrToStringUni(IntPtr.Add(source, checked(offset * 2)));
                    if (String.IsNullOrEmpty(entry))
                    {
                        terminated = true;
                        break;
                    }
                    offset = checked(offset + entry.Length + 1);
                    if (offset > 32768)
                        throw new InvalidOperationException("Parent environment block exceeds its scan bound.");

                    // Preserve only special per-drive current-directory entries;
                    // never copy ordinary ambient environment variables.
                    if (entry.Length < 4 || entry[0] != '=' ||
                        !Char.IsLetter(entry[1]) || entry[2] != ':' || entry[3] != '=')
                        continue;

                    string name = entry.Substring(0, 3);
                    string drivePath = entry.Substring(4);
                    string expectedRoot = name.Substring(1, 2) + "\\";
                    if (!Path.IsPathRooted(drivePath) ||
                        !String.Equals(Path.GetPathRoot(drivePath), expectedRoot, StringComparison.OrdinalIgnoreCase))
                        throw new InvalidOperationException("Malformed hidden per-drive current-directory entry.");
                    if (!driveNames.Add(name))
                        throw new InvalidOperationException("Duplicate hidden per-drive current-directory entry.");
                    if (entry.IndexOf('\0') >= 0)
                        throw new InvalidOperationException("Hidden drive entry contains an embedded NUL.");
                    entries.Add(entry);
                }
                if (!terminated)
                    throw new InvalidOperationException("Parent environment lacks bounded double-NUL termination.");
            }
            finally
            {
                if (!FreeEnvironmentStringsW(source))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "FreeEnvironmentStringsW failed.");
            }
            return entries;
        }

        private static string BuildExplicitEnvironment()
        {
            string systemRoot = Environment.GetEnvironmentVariable("SystemRoot");
            if (String.IsNullOrEmpty(systemRoot) || !Path.IsPathRooted(systemRoot))
                throw new InvalidOperationException("SystemRoot is missing or not absolute.");
            string systemDrive = Path.GetPathRoot(systemRoot).TrimEnd('\\');
            string systemDirectory = Environment.SystemDirectory;
            string windowsTemp = Path.Combine(systemRoot, "Temp");

            // CreateProcessAsUserW returned ERROR_ENVVAR_NOT_FOUND (203) when
            // this explicit block omitted Windows' special per-drive entries.
            // Retain validated drive-current-directory records only; all ordinary
            // broker variables and secret values remain excluded.
            List<string> entries = ReadApprovedDriveEntries();
            entries.AddRange(new string[] {
                "ComSpec=" + Path.Combine(systemDirectory, "cmd.exe"),
                "OS=Windows_NT",
                "PATH=" + systemDirectory,
                "PATHEXT=.COM;.EXE;.BAT;.CMD",
                "SystemDrive=" + systemDrive,
                "SystemRoot=" + systemRoot,
                "TEMP=" + windowsTemp,
                "TMP=" + windowsTemp,
                "windir=" + systemRoot
            });
            entries.Sort(StringComparer.OrdinalIgnoreCase);

            HashSet<string> names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            StringBuilder block = new StringBuilder();
            foreach (string entry in entries)
            {
                int equals = entry[0] == '=' ? entry.IndexOf('=', 1) : entry.IndexOf('=');
                if (equals <= 0)
                    throw new InvalidOperationException("Explicit child environment contains an invalid entry.");
                string name = entry.Substring(0, equals);
                if (!names.Add(name))
                    throw new InvalidOperationException("Explicit child environment contains duplicate name: " + name);
                if (entry.IndexOf('\0') >= 0)
                    throw new InvalidOperationException("Explicit child environment contains an embedded NUL.");
                block.Append(entry);
                block.Append('\0');
            }
            block.Append('\0');
            if (block.Length > 32768)
                throw new InvalidOperationException("Explicit Unicode environment exceeds 32768 UTF-16 code units.");
            return block.ToString();
        }

        private static void VerifyInheritedFlag(IntPtr handle, bool expected)
        {
            uint flags = 0;
            Check(GetHandleInformation(handle, out flags), "GetHandleInformation");
            bool actual = (flags & HandleFlagInherit) != 0;
            if (actual != expected)
                throw new InvalidOperationException("Handle inheritance mismatch: expected " + expected + ", got " + actual + ".");
        }

        private static bool DrainPipe(
            IntPtr pipe, StringBuilder destination, ref bool closed,
            ref int streamBytes, ref int combinedBytes, string streamName)
        {
            if (closed) return false;
            uint available = 0;
            if (!PeekNamedPipe(pipe, IntPtr.Zero, 0, IntPtr.Zero, out available, IntPtr.Zero))
            {
                int error = Marshal.GetLastWin32Error();
                if (error == 109) { closed = true; return false; }
                throw new Win32Exception(error, "PeekNamedPipe(" + streamName + ") failed.");
            }
            if (available == 0) return false;

            bool readAny = false;
            while (available > 0)
            {
                if (streamBytes >= PerStreamLimit || combinedBytes >= CombinedOutputLimit)
                    throw new InvalidOperationException("Output limit exceeded on " + streamName + ".");
                int remainingStream = PerStreamLimit - streamBytes;
                int remainingCombined = CombinedOutputLimit - combinedBytes;
                uint request = Math.Min(available, (uint)Math.Min(1024, Math.Min(remainingStream, remainingCombined)));
                byte[] buffer = new byte[checked((int)request)];
                uint bytesRead = 0;
                if (!ReadFile(pipe, buffer, request, out bytesRead, IntPtr.Zero))
                {
                    int error = Marshal.GetLastWin32Error();
                    if (error == 109) { closed = true; break; }
                    throw new Win32Exception(error, "ReadFile(" + streamName + ") failed.");
                }
                if (bytesRead == 0) break;
                destination.Append(Encoding.UTF8.GetString(buffer, 0, checked((int)bytesRead)));
                streamBytes = checked(streamBytes + (int)bytesRead);
                combinedBytes = checked(combinedBytes + (int)bytesRead);
                readAny = true;
                if (!PeekNamedPipe(pipe, IntPtr.Zero, 0, IntPtr.Zero, out available, IntPtr.Zero))
                {
                    int error = Marshal.GetLastWin32Error();
                    if (error == 109) { closed = true; break; }
                    throw new Win32Exception(error, "PeekNamedPipe(" + streamName + ") failed after read.");
                }
            }
            return readAny;
        }

        private static void VerifyAppContainerToken(IntPtr token, string expectedSid)
        {
            IntPtr appFlag = IntPtr.Zero;
            IntPtr appSidInfo = IntPtr.Zero;
            IntPtr capabilities = IntPtr.Zero;
            IntPtr restrictions = IntPtr.Zero;
            try
            {
                appFlag = QueryToken(token, 29);
                if (Marshal.ReadInt32(appFlag) != 1)
                    throw new InvalidOperationException("CreateProcessAsUserW child token is not an AppContainer.");
                appSidInfo = QueryToken(token, 31);
                string actualSid = SidToString(Marshal.ReadIntPtr(appSidInfo));
                if (!String.Equals(actualSid, expectedSid, StringComparison.Ordinal))
                    throw new InvalidOperationException("CreateProcessAsUserW child package SID does not match the execution profile.");
                capabilities = QueryToken(token, 30);
                uint capCount = unchecked((uint)Marshal.ReadInt32(capabilities));
                if (capCount != 0)
                    throw new InvalidOperationException("AppContainer child has unexpected capabilities: " + capCount);
                restrictions = QueryToken(token, 21);
                if (Marshal.ReadInt32(restrictions) == 0)
                    throw new InvalidOperationException("Restricted-token boundary was not present in the child primary token.");
                uint integrity = ReadIntegrityRid(token);
                if (integrity != 0x1000)
                    throw new InvalidOperationException("AppContainer child integrity RID is not Low: 0x" + integrity.ToString("X"));
            }
            finally
            {
                if (restrictions != IntPtr.Zero) Marshal.FreeHGlobal(restrictions);
                if (capabilities != IntPtr.Zero) Marshal.FreeHGlobal(capabilities);
                if (appSidInfo != IntPtr.Zero) Marshal.FreeHGlobal(appSidInfo);
                if (appFlag != IntPtr.Zero) Marshal.FreeHGlobal(appFlag);
            }
        }

        public static string RunCreateProcessAsUserAppContainerProbe()
        {
            string profileName = NewProfileName();
            ValidateProfileName(profileName);
            IntPtr packageSid = IntPtr.Zero;
            IntPtr sourceToken = IntPtr.Zero;
            IntPtr restrictedToken = IntPtr.Zero;
            IntPtr attributeBuffer = IntPtr.Zero;
            IntPtr attributeList = IntPtr.Zero;
            IntPtr securityCapabilitiesBuffer = IntPtr.Zero;
            IntPtr handleListBuffer = IntPtr.Zero;
            IntPtr environmentBuffer = IntPtr.Zero;
            IntPtr stdinHandle = IntPtr.Zero;
            IntPtr stdoutRead = IntPtr.Zero, stdoutWrite = IntPtr.Zero;
            IntPtr stderrRead = IntPtr.Zero, stderrWrite = IntPtr.Zero;
            IntPtr job = IntPtr.Zero;
            IntPtr childToken = IntPtr.Zero;
            PROCESS_INFORMATION process = new PROCESS_INFORMATION();
            bool profileCreated = false;
            bool attributeListInitialized = false;
            bool processCreated = false;
            bool processAssigned = false;
            bool childResumed = false;
            string priorSecretCanary = Environment.GetEnvironmentVariable("SHARNOU_2B8_SECRET_CANARY");
            if (priorSecretCanary != null)
                throw new InvalidOperationException("The secret-canary environment variable was already defined in the test host.");
            StringBuilder stdout = new StringBuilder();
            StringBuilder stderr = new StringBuilder();
            int stdoutBytes = 0, stderrBytes = 0, combinedBytes = 0;
            bool stdoutClosed = false, stderrClosed = false;

            try
            {
                int createProfileHr = CreateAppContainerProfile(
                    profileName, "Sharnou AppContainer launch probe",
                    "Ephemeral CreateProcessAsUserW explicit-environment test.",
                    IntPtr.Zero, 0, out packageSid);
                if (createProfileHr != 0 || packageSid == IntPtr.Zero)
                    throw new InvalidOperationException("CreateAppContainerProfile failed or returned no SID; HRESULT=0x" +
                        unchecked((uint)createProfileHr).ToString("X8"));
                profileCreated = true;
                string expectedSid = SidToString(packageSid);

                Check(OpenProcessToken(GetCurrentProcess(),
                    TokenAssignPrimary | TokenDuplicate | TokenQuery | TokenAdjustDefault,
                    out sourceToken), "OpenProcessToken");
                Check(CreateRestrictedToken(sourceToken, DisableMaxPrivilege,
                    0, IntPtr.Zero, 0, IntPtr.Zero, 0, IntPtr.Zero, out restrictedToken),
                    "CreateRestrictedToken(DISABLE_MAX_PRIVILEGE)");

                Environment.SetEnvironmentVariable("SHARNOU_2B8_SECRET_CANARY", "must-not-inherit-2b8-canary");
                if (Environment.GetEnvironmentVariable("SHARNOU_2B8_SECRET_CANARY") != "must-not-inherit-2b8-canary")
                    throw new InvalidOperationException("The parent secret-canary setup failed.");

                SECURITY_ATTRIBUTES pipeAttributes = new SECURITY_ATTRIBUTES();
                pipeAttributes.Length = Marshal.SizeOf(typeof(SECURITY_ATTRIBUTES));
                pipeAttributes.SecurityDescriptor = IntPtr.Zero;
                pipeAttributes.InheritHandle = true;

                Check(CreatePipe(out stdoutRead, out stdoutWrite, ref pipeAttributes, 0), "CreatePipe(stdout)");
                Check(CreatePipe(out stderrRead, out stderrWrite, ref pipeAttributes, 0), "CreatePipe(stderr)");
                Check(SetHandleInformation(stdoutRead, HandleFlagInherit, 0), "SetHandleInformation(stdout read)");
                Check(SetHandleInformation(stderrRead, HandleFlagInherit, 0), "SetHandleInformation(stderr read)");
                VerifyInheritedFlag(stdoutRead, false);
                VerifyInheritedFlag(stderrRead, false);
                VerifyInheritedFlag(stdoutWrite, true);
                VerifyInheritedFlag(stderrWrite, true);

                stdinHandle = CreateFileW("NUL", GenericRead, FileShareReadWrite,
                    ref pipeAttributes, OpenExisting, FileAttributeNormal, IntPtr.Zero);
                if (stdinHandle == new IntPtr(-1) || stdinHandle == IntPtr.Zero)
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateFileW(NUL) failed.");
                VerifyInheritedFlag(stdinHandle, true);

                SECURITY_CAPABILITIES securityCapabilities = new SECURITY_CAPABILITIES();
                securityCapabilities.AppContainerSid = packageSid;
                securityCapabilities.Capabilities = IntPtr.Zero;
                securityCapabilities.CapabilityCount = 0;
                securityCapabilities.Reserved = 0;
                securityCapabilitiesBuffer = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(SECURITY_CAPABILITIES)));
                Marshal.StructureToPtr(securityCapabilities, securityCapabilitiesBuffer, false);

                IntPtr listSize = IntPtr.Zero;
                bool sizingResult = InitializeProcThreadAttributeList(IntPtr.Zero, 2, 0, ref listSize);
                int sizingError = Marshal.GetLastWin32Error();
                if (sizingResult || sizingError != 122 || listSize.ToInt64() < 1 || listSize.ToInt64() > 65536)
                    throw new Win32Exception(sizingError, "InitializeProcThreadAttributeList sizing contract failed.");
                attributeBuffer = Marshal.AllocHGlobal(listSize);
                attributeList = attributeBuffer;
                Check(InitializeProcThreadAttributeList(attributeList, 2, 0, ref listSize),
                    "InitializeProcThreadAttributeList");
                attributeListInitialized = true;

                Check(UpdateProcThreadAttribute(attributeList, 0,
                    new IntPtr(unchecked((int)ProcThreadAttributeSecurityCapabilities)),
                    securityCapabilitiesBuffer,
                    new UIntPtr((uint)Marshal.SizeOf(typeof(SECURITY_CAPABILITIES))),
                    IntPtr.Zero, IntPtr.Zero), "UpdateProcThreadAttribute(SECURITY_CAPABILITIES)");

                IntPtr[] inheritedHandles = new IntPtr[] { stdinHandle, stdoutWrite, stderrWrite };
                handleListBuffer = Marshal.AllocHGlobal(checked(inheritedHandles.Length * IntPtr.Size));
                for (int i = 0; i < inheritedHandles.Length; i++)
                    Marshal.WriteIntPtr(handleListBuffer, checked(i * IntPtr.Size), inheritedHandles[i]);
                Check(UpdateProcThreadAttribute(attributeList, 0,
                    new IntPtr(unchecked((int)ProcThreadAttributeHandleList)), handleListBuffer,
                    new UIntPtr((uint)(inheritedHandles.Length * IntPtr.Size)),
                    IntPtr.Zero, IntPtr.Zero), "UpdateProcThreadAttribute(HANDLE_LIST)");

                string environment = BuildExplicitEnvironment();
                environmentBuffer = Marshal.AllocHGlobal(checked(environment.Length * 2));
                for (int i = 0; i < environment.Length; i++)
                    Marshal.WriteInt16(environmentBuffer, checked(i * 2), (short)environment[i]);

                job = CreateJobObjectW(IntPtr.Zero, null);
                if (job == IntPtr.Zero)
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateJobObjectW failed.");
                JOBOBJECT_EXTENDED_LIMIT_INFORMATION jobLimits = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
                jobLimits.BasicLimitInformation.LimitFlags =
                    JobObjectLimitKillOnJobClose | JobObjectLimitActiveProcess;
                jobLimits.BasicLimitInformation.ActiveProcessLimit = 1;
                Check(SetInformationJobObject(job, JobObjectExtendedLimitInformation,
                    ref jobLimits, (uint)Marshal.SizeOf(typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION))),
                    "SetInformationJobObject");

                string systemRoot = Environment.GetEnvironmentVariable("SystemRoot");
                string systemDirectory = Environment.SystemDirectory;
                string powershell = Path.Combine(systemRoot, "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
                if (!File.Exists(powershell))
                    throw new FileNotFoundException("Trusted Windows PowerShell image was not found.", powershell);
                string probeScript =
                    "$ErrorActionPreference='Stop';" +
                    "if([Environment]::GetEnvironmentVariable('SHARNOU_2B8_SECRET_CANARY') -ne $null){" +
                    "[Console]::Error.WriteLine('SECRET_LEAK');exit 91};" +
                    "[Console]::Out.WriteLine(('STDOUT|SystemRoot={0}|windir={1}|SystemDrive={2}|PATH={3}' -f " +
                    "$env:SystemRoot,$env:windir,$env:SystemDrive,$env:PATH));" +
                    "[Console]::Error.WriteLine('STDERR|separate-stream-probe');";
                string encodedCommand = Convert.ToBase64String(Encoding.Unicode.GetBytes(probeScript));
                StringBuilder commandLine = new StringBuilder(
                    String.Concat((char)34, powershell, (char)34, " -NoLogo -NoProfile -NonInteractive -EncodedCommand ", encodedCommand));

                STARTUPINFOEXW startup = new STARTUPINFOEXW();
                startup.StartupInfo.cb = (uint)Marshal.SizeOf(typeof(STARTUPINFOEXW));
                startup.StartupInfo.dwFlags = StartfUseStdHandles;
                startup.StartupInfo.hStdInput = stdinHandle;
                startup.StartupInfo.hStdOutput = stdoutWrite;
                startup.StartupInfo.hStdError = stderrWrite;
                startup.lpAttributeList = attributeList;

                uint flags = ExtendedStartupInfoPresent | CreateSuspended |
                    CreateUnicodeEnvironment | CreateNoWindow;
                string immutableCommandLine = commandLine.ToString();
                if (!CreateProcessAsUserW(restrictedToken, powershell, commandLine,
                    IntPtr.Zero, IntPtr.Zero, true, flags, environmentBuffer,
                    systemDirectory, ref startup, out process))
                {
                    int explicitEnvironmentError = Marshal.GetLastWin32Error();

                    // Diagnostic-only negative control: same token, AppContainer
                    // attributes, STARTUPINFOEX handle list, image and current
                    // directory, but lpEnvironment=NULL. This process is created
                    // suspended and terminated immediately, never resumed. It is
                    // not a permitted execution fallback and cannot satisfy this test.
                    PROCESS_INFORMATION nullEnvironmentControl = new PROCESS_INFORMATION();
                    bool nullEnvironmentControlCreated = CreateProcessAsUserW(
                        restrictedToken, powershell, new StringBuilder(immutableCommandLine),
                        IntPtr.Zero, IntPtr.Zero, true, flags, IntPtr.Zero,
                        systemDirectory, ref startup, out nullEnvironmentControl);
                    int nullEnvironmentControlError = nullEnvironmentControlCreated
                        ? 0 : Marshal.GetLastWin32Error();

                    if (nullEnvironmentControlCreated)
                    {
                        TerminateProcess(nullEnvironmentControl.hProcess, 0x2BAD);
                        uint controlWait = WaitForSingleObject(nullEnvironmentControl.hProcess, 10000);
                        if (nullEnvironmentControl.hThread != IntPtr.Zero) CloseHandle(nullEnvironmentControl.hThread);
                        if (nullEnvironmentControl.hProcess != IntPtr.Zero) CloseHandle(nullEnvironmentControl.hProcess);
                        if (controlWait != 0)
                            throw new InvalidOperationException(
                                "NULL-environment diagnostic child was created but could not be proven terminated.");
                    }

                    throw new Win32Exception(explicitEnvironmentError,
                        "CreateProcessAsUserW with explicit Unicode environment failed (Win32=" +
                        explicitEnvironmentError + "; NULL-environment suspended control=" +
                        (nullEnvironmentControlCreated ? "CREATED_AND_TERMINATED" : ("FAILED_WIN32_" + nullEnvironmentControlError)) +
                        "). The NULL-environment control was diagnostic only and was never resumed.");
                }

                processCreated = true;
                Check(AssignProcessToJobObject(job, process.hProcess), "AssignProcessToJobObject");
                processAssigned = true;

                // Parent drops inheritable copies immediately after successful creation.
                CloseHandle(stdoutWrite); stdoutWrite = IntPtr.Zero;
                CloseHandle(stderrWrite); stderrWrite = IntPtr.Zero;
                CloseHandle(stdinHandle); stdinHandle = IntPtr.Zero;

                Check(OpenProcessToken(process.hProcess, TokenQuery, out childToken),
                    "OpenProcessToken(suspended child)");
                VerifyAppContainerToken(childToken, expectedSid);
                CloseHandle(childToken); childToken = IntPtr.Zero;

                uint previousSuspendCount = ResumeThread(process.hThread);
                if (previousSuspendCount == 0xFFFFFFFF)
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "ResumeThread failed.");
                childResumed = true;

                DateTime deadline = DateTime.UtcNow.AddSeconds(20);
                bool processExited = false;
                while (DateTime.UtcNow < deadline)
                {
                    uint wait = WaitForSingleObject(process.hProcess, 0);
                    if (wait == 0) processExited = true;
                    else if (wait != 258)
                        throw new Win32Exception(Marshal.GetLastWin32Error(), "WaitForSingleObject(child) failed.");

                    DrainPipe(stdoutRead, stdout, ref stdoutClosed, ref stdoutBytes, ref combinedBytes, "stdout");
                    DrainPipe(stderrRead, stderr, ref stderrClosed, ref stderrBytes, ref combinedBytes, "stderr");
                    if (processExited && stdoutClosed && stderrClosed) break;
                    Thread.Sleep(5);
                }
                if (!processExited || !stdoutClosed || !stderrClosed)
                    throw new TimeoutException("AppContainer child did not finish and close both output streams within 20 seconds.");

                uint exitCode;
                Check(GetExitCodeProcess(process.hProcess, out exitCode), "GetExitCodeProcess");
                if (exitCode != 0)
                    throw new InvalidOperationException("AppContainer child returned exit code " + exitCode + ".");

                if (stdout.ToString().IndexOf("STDOUT|SystemRoot=", StringComparison.Ordinal) < 0 ||
                    stdout.ToString().IndexOf("|windir=", StringComparison.Ordinal) < 0 ||
                    stdout.ToString().IndexOf("|SystemDrive=", StringComparison.Ordinal) < 0 ||
                    stdout.ToString().IndexOf("|PATH=", StringComparison.Ordinal) < 0)
                    throw new InvalidOperationException("AppContainer stdout did not contain the required approved environment values.");
                if (stderr.ToString().Trim() != "STDERR|separate-stream-probe")
                    throw new InvalidOperationException("AppContainer stderr was not independently captured exactly.");
                if (stdout.ToString().IndexOf("STDERR|", StringComparison.Ordinal) >= 0 ||
                    stderr.ToString().IndexOf("STDOUT|", StringComparison.Ordinal) >= 0)
                    throw new InvalidOperationException("stdout and stderr were merged or crossed.");
                if (stdout.ToString().IndexOf("must-not-inherit", StringComparison.Ordinal) >= 0 ||
                    stderr.ToString().IndexOf("SECRET_LEAK", StringComparison.Ordinal) >= 0)
                    throw new InvalidOperationException("Secret environment canary was exposed to the AppContainer child.");

                JOBOBJECT_BASIC_ACCOUNTING_INFORMATION accounting;
                Check(QueryInformationJobObject(job, JobObjectBasicAccountingInformation,
                    out accounting, (uint)Marshal.SizeOf(typeof(JOBOBJECT_BASIC_ACCOUNTING_INFORMATION)), IntPtr.Zero),
                    "QueryInformationJobObject");
                if (accounting.ActiveProcesses != 0)
                    throw new InvalidOperationException("Job Object still has active processes after child completion: " + accounting.ActiveProcesses);

                return "CreateProcessAsUserW=PASS;AppContainerSID=" + expectedSid +
                    ";IntegrityRID=0x1000;Capabilities=0;RestrictedToken=1;Environment=ExplicitUnicode;" +
                    "InheritableHandles=3;stdoutBytes=" + stdoutBytes +
                    ";stderrBytes=" + stderrBytes + ";JobActiveProcesses=0";
            }
            finally
            {
                if (processCreated && process.hProcess != IntPtr.Zero && !childResumed)
                {
                    // A failed Job Object assignment means the suspended child is
                    // not owned by the job; terminate the process handle directly.
                    if (processAssigned && job != IntPtr.Zero) TerminateJobObject(job, 0x2BAD);
                    else TerminateProcess(process.hProcess, 0x2BAD);
                    WaitForSingleObject(process.hProcess, 10000);
                }
                else if (processCreated && job != IntPtr.Zero)
                {
                    JOBOBJECT_BASIC_ACCOUNTING_INFORMATION accounting;
                    if (QueryInformationJobObject(job, JobObjectBasicAccountingInformation,
                        out accounting, (uint)Marshal.SizeOf(typeof(JOBOBJECT_BASIC_ACCOUNTING_INFORMATION)), IntPtr.Zero) &&
                        accounting.ActiveProcesses != 0)
                    {
                        TerminateJobObject(job, 0x2BAD);
                        WaitForSingleObject(process.hProcess, 10000);
                    }
                }

                if (childToken != IntPtr.Zero) CloseHandle(childToken);
                if (process.hThread != IntPtr.Zero) CloseHandle(process.hThread);
                if (process.hProcess != IntPtr.Zero) CloseHandle(process.hProcess);
                if (job != IntPtr.Zero) CloseHandle(job);
                if (stdoutRead != IntPtr.Zero) CloseHandle(stdoutRead);
                if (stdoutWrite != IntPtr.Zero) CloseHandle(stdoutWrite);
                if (stderrRead != IntPtr.Zero) CloseHandle(stderrRead);
                if (stderrWrite != IntPtr.Zero) CloseHandle(stderrWrite);
                if (stdinHandle != IntPtr.Zero) CloseHandle(stdinHandle);
                if (attributeListInitialized) DeleteProcThreadAttributeList(attributeList);
                if (handleListBuffer != IntPtr.Zero) Marshal.FreeHGlobal(handleListBuffer);
                if (securityCapabilitiesBuffer != IntPtr.Zero) Marshal.FreeHGlobal(securityCapabilitiesBuffer);
                if (attributeBuffer != IntPtr.Zero) Marshal.FreeHGlobal(attributeBuffer);
                if (environmentBuffer != IntPtr.Zero) Marshal.FreeHGlobal(environmentBuffer);
                if (restrictedToken != IntPtr.Zero) CloseHandle(restrictedToken);
                if (sourceToken != IntPtr.Zero) CloseHandle(sourceToken);
                if (packageSid != IntPtr.Zero) FreeSid(packageSid);
                Environment.SetEnvironmentVariable("SHARNOU_2B8_SECRET_CANARY", priorSecretCanary);
                if (profileCreated)
                {
                    int deleteHr = DeleteAppContainerProfile(profileName);
                    if (deleteHr != 0)
                    {
                        int retryHr = DeleteAppContainerProfile(profileName);
                        if (retryHr != 0)
                            throw new InvalidOperationException("AppContainer profile cleanup failed twice; HRESULTs=0x" +
                                unchecked((uint)deleteHr).ToString("X8") + "/0x" +
                                unchecked((uint)retryHr).ToString("X8"));
                    }
                }
            }
        }

        private static void ValidateProfileName(string profileName)
        {
            if (String.IsNullOrEmpty(profileName) || profileName.Length > 64 ||
                !Regex.IsMatch(profileName, @"^Sharnou\.DevAgent\.[0-9a-f]{32}$", RegexOptions.CultureInvariant))
                throw new ArgumentException("Invalid AppContainer profile name.");
        }
    }
}
'@
}

$summary = [Sharnou.DevAgentAppContainerLaunchNative]::RunCreateProcessAsUserAppContainerProbe()
Write-Host ("PASS: native restricted-token CreateProcessAsUserW AppContainer probe: {0}" -f $summary) -ForegroundColor Green
Write-Host 'PASS: explicit Unicode environment reached the actual AppContainer child; ambient parent variables were not supplied' -ForegroundColor Green
Write-Host 'PASS: STARTUPINFOEX handle list contained exactly NUL stdin, stdout writer and stderr writer; parent readers were non-inheritable' -ForegroundColor Green
Write-Host 'PASS: stdout and stderr were drained independently and did not cross streams' -ForegroundColor Green
Write-Host 'PASS: child was assigned to a kill-on-close Job Object before resume and the job was empty at completion' -ForegroundColor Green
Write-Host 'DevAgent AppContainer launch primitive result: PASS' -ForegroundColor Green
Write-Host 'Qualification boundary: isolated native launch/capture primitive only; compiler-emitted broker integration and authenticated recovery ownership remain pending.' -ForegroundColor Yellow
