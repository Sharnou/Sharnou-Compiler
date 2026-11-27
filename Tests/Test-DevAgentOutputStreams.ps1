[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'The DevAgent split-stream qualification requires Windows.'
}

if (-not ('Sharnou.DevAgentSplitStreamNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;

namespace Sharnou
{
    public static class DevAgentSplitStreamNative
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct SECURITY_ATTRIBUTES
        {
            public int nLength;
            public IntPtr lpSecurityDescriptor;
            [MarshalAs(UnmanagedType.Bool)]
            public bool bInheritHandle;
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
            public uint dwProcessId;
            public uint dwThreadId;
        }

        [DllImport("kernel32.dll", EntryPoint = "CreatePipe", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CreatePipe(
            out IntPtr readPipe, out IntPtr writePipe,
            ref SECURITY_ATTRIBUTES pipeAttributes, uint size);

        [DllImport("kernel32.dll", EntryPoint = "SetHandleInformation", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetHandleInformation(IntPtr handle, uint mask, uint flags);

        [DllImport("kernel32.dll", EntryPoint = "CreateFileW", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
        private static extern IntPtr CreateFileW(
            string name, uint access, uint share, ref SECURITY_ATTRIBUTES attributes,
            uint creationDisposition, uint flags, IntPtr template);

        [DllImport("kernel32.dll", EntryPoint = "InitializeProcThreadAttributeList", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool InitializeProcThreadAttributeList(
            IntPtr attributeList, int attributeCount, uint flags, ref IntPtr size);

        [DllImport("kernel32.dll", EntryPoint = "UpdateProcThreadAttribute", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool UpdateProcThreadAttribute(
            IntPtr attributeList, uint flags, IntPtr attribute, IntPtr value,
            UIntPtr size, IntPtr previousValue, IntPtr returnSize);

        [DllImport("kernel32.dll", EntryPoint = "DeleteProcThreadAttributeList", ExactSpelling = true)]
        private static extern void DeleteProcThreadAttributeList(IntPtr attributeList);

        [DllImport("kernel32.dll", EntryPoint = "CreateProcessW", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CreateProcessW(
            string applicationName, StringBuilder commandLine,
            IntPtr processAttributes, IntPtr threadAttributes,
            [MarshalAs(UnmanagedType.Bool)] bool inheritHandles,
            uint creationFlags, IntPtr environment, string currentDirectory,
            ref STARTUPINFOEXW startupInfo, out PROCESS_INFORMATION processInformation);

        [DllImport("kernel32.dll", EntryPoint = "ReadFile", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool ReadFile(
            IntPtr handle, [Out] byte[] buffer, uint bytesToRead,
            out uint bytesRead, IntPtr overlapped);

        [DllImport("kernel32.dll", EntryPoint = "WaitForSingleObject", ExactSpelling = true, SetLastError = true)]
        private static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);

        [DllImport("kernel32.dll", EntryPoint = "GetExitCodeProcess", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetExitCodeProcess(IntPtr process, out uint exitCode);

        [DllImport("kernel32.dll", EntryPoint = "TerminateProcess", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool TerminateProcess(IntPtr process, uint exitCode);

        [DllImport("kernel32.dll", EntryPoint = "CloseHandle", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CloseHandle(IntPtr handle);

        private static byte[] ReadPipeToEnd(IntPtr pipe)
        {
            List<byte> result = new List<byte>();
            byte[] buffer = new byte[4096];
            while (true)
            {
                uint count;
                if (!ReadFile(pipe, buffer, (uint)buffer.Length, out count, IntPtr.Zero))
                {
                    int error = Marshal.GetLastWin32Error();
                    if (error == 109) break; // ERROR_BROKEN_PIPE / writer closed
                    throw new Win32Exception(error, "ReadFile on child output pipe failed.");
                }
                if (count == 0) break;
                for (int i = 0; i < count; i++) result.Add(buffer[i]);
                if (result.Count > 1024 * 1024)
                    throw new InvalidOperationException("Split-stream fixture exceeded its 1 MiB per-stream test bound.");
            }
            return result.ToArray();
        }

        public static string Run(string scriptPath, int bytesPerStream)
        {
            if (String.IsNullOrEmpty(scriptPath) || !Path.IsPathRooted(scriptPath) || bytesPerStream < 4096 || bytesPerStream > 262144)
                throw new ArgumentOutOfRangeException("scriptPath/bytesPerStream", "Invalid split-stream fixture arguments.");

            string systemDirectory = Environment.SystemDirectory;
            string powershell = Path.Combine(systemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe");
            if (!File.Exists(powershell))
                throw new FileNotFoundException("System PowerShell executable is missing.", powershell);

            SECURITY_ATTRIBUTES security = new SECURITY_ATTRIBUTES();
            security.nLength = Marshal.SizeOf(typeof(SECURITY_ATTRIBUTES));
            security.lpSecurityDescriptor = IntPtr.Zero;
            security.bInheritHandle = true;

            IntPtr stdoutRead = IntPtr.Zero, stdoutWrite = IntPtr.Zero;
            IntPtr stderrRead = IntPtr.Zero, stderrWrite = IntPtr.Zero;
            IntPtr stdinHandle = IntPtr.Zero;
            IntPtr attributeList = IntPtr.Zero, attributeBuffer = IntPtr.Zero, handleListBuffer = IntPtr.Zero;
            bool attributeListInitialized = false;
            PROCESS_INFORMATION process = new PROCESS_INFORMATION();
            bool childCreated = false;
            Task<byte[]> stdoutTask = null, stderrTask = null;

            try
            {
                if (!CreatePipe(out stdoutRead, out stdoutWrite, ref security, 0))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "CreatePipe(stdout) failed.");
                if (!CreatePipe(out stderrRead, out stderrWrite, ref security, 0))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "CreatePipe(stderr) failed.");

                if (!SetHandleInformation(stdoutRead, 1, 0) || !SetHandleInformation(stderrRead, 1, 0))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "Parent pipe read-end inheritance could not be disabled.");

                stdinHandle = CreateFileW("NUL", 0x80000000, 0x00000003, ref security, 3, 0x80, IntPtr.Zero);
                if (stdinHandle == new IntPtr(-1) || stdinHandle == IntPtr.Zero)
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "Inheritable NUL stdin open failed.");

                IntPtr attributeSize = IntPtr.Zero;
                bool sizingResult = InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref attributeSize);
                int sizingError = Marshal.GetLastWin32Error();
                if (sizingResult || sizingError != 122 || attributeSize.ToInt64() < 1 || attributeSize.ToInt64() > 65536)
                    throw new Win32Exception(sizingError, "Attribute-list sizing contract failed.");

                attributeBuffer = Marshal.AllocHGlobal(attributeSize);
                attributeList = attributeBuffer;
                if (!InitializeProcThreadAttributeList(attributeList, 1, 0, ref attributeSize))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "InitializeProcThreadAttributeList failed.");
                attributeListInitialized = true;

                // Exact child handle allowlist: NUL stdin, stdout writer, stderr writer.
                IntPtr[] handles = new IntPtr[] { stdinHandle, stdoutWrite, stderrWrite };
                handleListBuffer = Marshal.AllocHGlobal(checked(handles.Length * IntPtr.Size));
                for (int i = 0; i < handles.Length; i++)
                    Marshal.WriteIntPtr(handleListBuffer, i * IntPtr.Size, handles[i]);

                IntPtr handleListAttribute = new IntPtr(0x00020002); // PROC_THREAD_ATTRIBUTE_HANDLE_LIST
                if (!UpdateProcThreadAttribute(
                    attributeList, 0, handleListAttribute, handleListBuffer,
                    new UIntPtr((uint)(handles.Length * IntPtr.Size)), IntPtr.Zero, IntPtr.Zero))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "PROC_THREAD_ATTRIBUTE_HANDLE_LIST update failed.");

                STARTUPINFOEXW startup = new STARTUPINFOEXW();
                startup.StartupInfo.cb = (uint)Marshal.SizeOf(typeof(STARTUPINFOEXW));
                startup.StartupInfo.dwFlags = 0x00000100; // STARTF_USESTDHANDLES
                startup.StartupInfo.hStdInput = stdinHandle;
                startup.StartupInfo.hStdOutput = stdoutWrite;
                startup.StartupInfo.hStdError = stderrWrite;
                startup.lpAttributeList = attributeList;

                StringBuilder commandLine = new StringBuilder(
                    "\"" + powershell + "\" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"" +
                    scriptPath + "\" " + bytesPerStream.ToString());
                const uint flags = 0x00080000 | 0x08000000; // EXTENDED_STARTUPINFO_PRESENT | CREATE_NO_WINDOW
                if (!CreateProcessW(
                    powershell, commandLine, IntPtr.Zero, IntPtr.Zero, true,
                    flags, IntPtr.Zero, systemDirectory, ref startup, out process))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateProcessW with the exact three-handle list failed.");
                childCreated = true;

                CloseHandle(stdoutWrite); stdoutWrite = IntPtr.Zero;
                CloseHandle(stderrWrite); stderrWrite = IntPtr.Zero;
                CloseHandle(stdinHandle); stdinHandle = IntPtr.Zero;

                // Drain both streams at the same time. A sequential drain can
                // deadlock when the child fills the stream not currently read.
                stdoutTask = Task.Factory.StartNew(
                    () => ReadPipeToEnd(stdoutRead), TaskCreationOptions.LongRunning);
                stderrTask = Task.Factory.StartNew(
                    () => ReadPipeToEnd(stderrRead), TaskCreationOptions.LongRunning);

                if (WaitForSingleObject(process.hProcess, 15000) != 0)
                {
                    TerminateProcess(process.hProcess, 0x2BAD);
                    WaitForSingleObject(process.hProcess, 5000);
                    throw new InvalidOperationException("Split stdout/stderr child exceeded the 15-second timeout.");
                }

                if (!Task.WaitAll(new Task[] { stdoutTask, stderrTask }, 10000))
                    throw new InvalidOperationException("Concurrent stdout/stderr drain did not finish after child exit.");

                uint exitCode;
                if (!GetExitCodeProcess(process.hProcess, out exitCode))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "GetExitCodeProcess failed.");
                if (exitCode != 0)
                    throw new InvalidOperationException("Split stdout/stderr child exit code was " + exitCode + ".");

                byte[] stdoutBytes = stdoutTask.Result;
                byte[] stderrBytes = stderrTask.Result;
                string stdoutText = Encoding.ASCII.GetString(stdoutBytes);
                string stderrText = Encoding.ASCII.GetString(stderrBytes);
                string expectedOut = "OUT:" + new String('O', bytesPerStream);
                string expectedErr = "ERR:" + new String('E', bytesPerStream);
                if (!String.Equals(stdoutText, expectedOut, StringComparison.Ordinal))
                    throw new InvalidOperationException("stdout stream identity/content mismatch (bytes=" + stdoutBytes.Length + ").");
                if (!String.Equals(stderrText, expectedErr, StringComparison.Ordinal))
                    throw new InvalidOperationException("stderr stream identity/content mismatch (bytes=" + stderrBytes.Length + ").");
                if (stdoutText.IndexOf("ERR:", StringComparison.Ordinal) >= 0 ||
                    stderrText.IndexOf("OUT:", StringComparison.Ordinal) >= 0)
                    throw new InvalidOperationException("stdout and stderr were merged or crossed.");

                return "stdoutBytes=" + stdoutBytes.Length.ToString() +
                    ";stderrBytes=" + stderrBytes.Length.ToString() +
                    ";inheritedHandles=3";
            }
            finally
            {
                if (childCreated && process.hProcess != IntPtr.Zero)
                {
                    if (WaitForSingleObject(process.hProcess, 0) != 0)
                    {
                        TerminateProcess(process.hProcess, 0x2BAD);
                        WaitForSingleObject(process.hProcess, 5000);
                    }
                }
                if (process.hThread != IntPtr.Zero) CloseHandle(process.hThread);
                if (process.hProcess != IntPtr.Zero) CloseHandle(process.hProcess);
                if (stdoutRead != IntPtr.Zero) CloseHandle(stdoutRead);
                if (stdoutWrite != IntPtr.Zero) CloseHandle(stdoutWrite);
                if (stderrRead != IntPtr.Zero) CloseHandle(stderrRead);
                if (stderrWrite != IntPtr.Zero) CloseHandle(stderrWrite);
                if (stdinHandle != IntPtr.Zero && stdinHandle != new IntPtr(-1)) CloseHandle(stdinHandle);
                if (attributeListInitialized) DeleteProcThreadAttributeList(attributeList);
                if (handleListBuffer != IntPtr.Zero) Marshal.FreeHGlobal(handleListBuffer);
                if (attributeBuffer != IntPtr.Zero) Marshal.FreeHGlobal(attributeBuffer);
            }
        }
    }
}
'@
}

$probeRoot = Join-Path ([IO.Path]::GetTempPath()) ('Sharnou-SplitStreams-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($probeRoot)
$scriptPath = Join-Path $probeRoot 'SplitStreams.ps1'
$childScript = @'
param([int] $BytesPerStream)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::Out.Write('OUT:')
[Console]::Out.Write(('O' * $BytesPerStream))
[Console]::Error.Write('ERR:')
[Console]::Error.Write(('E' * $BytesPerStream))
'@

try {
    [IO.File]::WriteAllText($scriptPath, $childScript, [Text.Encoding]::ASCII)
    $summary = [Sharnou.DevAgentSplitStreamNative]::Run($scriptPath, 65536)
    Write-Host ("PASS: stdout and stderr remained separate under concurrent 64 KiB writes ({0})" -f $summary) -ForegroundColor Green
    Write-Host 'PASS: exact STARTUPINFOEX handle list contains only NUL stdin, stdout writer and stderr writer' -ForegroundColor Green
    Write-Host 'PASS: parent-only pipe read handles are non-inheritable' -ForegroundColor Green
    Write-Host 'PASS: both output streams drained concurrently without pipe deadlock or cross-stream bytes' -ForegroundColor Green
    Write-Host 'DevAgent split-stream primitive result: PASS' -ForegroundColor Green
}
finally {
    Remove-Item -LiteralPath $probeRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'Qualification boundary: native separate-pipe/handle-allowlist primitive only; production broker still merges stdout/stderr until emitter integration and same-head adversarial testing pass.' -ForegroundColor Yellow
