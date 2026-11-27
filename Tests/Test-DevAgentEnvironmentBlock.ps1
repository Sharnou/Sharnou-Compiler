[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'The DevAgent explicit environment qualification requires Windows.'
}

if (-not ('Sharnou.DevAgentEnvironmentBlockNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace Sharnou
{
    public static class DevAgentEnvironmentBlockNative
    {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
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
        private struct PROCESS_INFORMATION
        {
            public IntPtr hProcess;
            public IntPtr hThread;
            public uint dwProcessId;
            public uint dwThreadId;
        }

        [DllImport("kernel32.dll", EntryPoint = "GetEnvironmentStringsW",
            CharSet = CharSet.Unicode, ExactSpelling = true)]
        private static extern IntPtr GetEnvironmentStringsW();

        [DllImport("kernel32.dll", EntryPoint = "FreeEnvironmentStringsW",
            CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool FreeEnvironmentStringsW(IntPtr environmentBlock);

        [DllImport("kernel32.dll", EntryPoint = "CreateProcessW",
            CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CreateProcessW(
            string applicationName, StringBuilder commandLine,
            IntPtr processAttributes, IntPtr threadAttributes,
            [MarshalAs(UnmanagedType.Bool)] bool inheritHandles,
            uint creationFlags, IntPtr environment, string currentDirectory,
            ref STARTUPINFOW startupInfo, out PROCESS_INFORMATION processInformation);

        [DllImport("kernel32.dll", EntryPoint = "WaitForSingleObject",
            ExactSpelling = true, SetLastError = true)]
        private static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);

        [DllImport("kernel32.dll", EntryPoint = "GetExitCodeProcess",
            ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetExitCodeProcess(IntPtr process, out uint exitCode);

        [DllImport("kernel32.dll", EntryPoint = "TerminateProcess",
            ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool TerminateProcess(IntPtr process, uint exitCode);

        [DllImport("kernel32.dll", EntryPoint = "CloseHandle",
            ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CloseHandle(IntPtr handle);

        private static string ReadVariable(string name)
        {
            string value = Environment.GetEnvironmentVariable(name);
            if (String.IsNullOrEmpty(value))
                throw new InvalidOperationException("Required Windows environment value is missing: " + name);
            if (value.IndexOf('\0') >= 0)
                throw new InvalidOperationException("Environment value contains an embedded NUL: " + name);
            return value;
        }

        private static void AddVariable(List<string> entries, HashSet<string> names, string name, string value)
        {
            if (String.IsNullOrEmpty(name) || name.IndexOf('=') >= 0 || name.IndexOf('\0') >= 0)
                throw new InvalidOperationException("Environment variable name is invalid.");
            if (String.IsNullOrEmpty(value) || value.IndexOf('\0') >= 0)
                throw new InvalidOperationException("Environment variable value is empty or contains NUL: " + name);
            if (!names.Add(name))
                throw new InvalidOperationException("Duplicate environment variable: " + name);
            entries.Add(name + "=" + value);
        }

        private static List<string> ReadApprovedDriveEntries()
        {
            IntPtr block = GetEnvironmentStringsW();
            if (block == IntPtr.Zero)
                throw new Win32Exception(Marshal.GetLastWin32Error(), "GetEnvironmentStringsW failed.");

            List<string> entries = new List<string>();
            HashSet<string> driveNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            try
            {
                int offset = 0;
                bool terminated = false;
                for (int index = 0; index < 32768; index++)
                {
                    string entry = Marshal.PtrToStringUni(IntPtr.Add(block, checked(offset * 2)));
                    if (String.IsNullOrEmpty(entry))
                    {
                        terminated = true;
                        break;
                    }
                    offset = checked(offset + entry.Length + 1);

                    // Only the special per-drive working-directory entries are
                    // inherited as data. All ordinary parent variables are discarded.
                    if (entry.Length < 4 || entry[0] != '=' ||
                        !Char.IsLetter(entry[1]) || entry[2] != ':' || entry[3] != '=')
                        continue;

                    string name = entry.Substring(0, 3);
                    string path = entry.Substring(4);
                    string expectedRoot = name.Substring(1, 2) + "\\";
                    if (!System.IO.Path.IsPathRooted(path) ||
                        !String.Equals(System.IO.Path.GetPathRoot(path), expectedRoot, StringComparison.OrdinalIgnoreCase))
                        throw new InvalidOperationException("Malformed hidden drive-current-directory entry.");
                    if (!driveNames.Add(name))
                        throw new InvalidOperationException("Duplicate hidden drive-current-directory entry.");
                    entries.Add(entry);
                }
                if (!terminated)
                    throw new InvalidOperationException("Windows environment block lacks bounded double-NUL termination.");
            }
            finally
            {
                if (!FreeEnvironmentStringsW(block))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "FreeEnvironmentStringsW failed.");
            }
            return entries;
        }

        public static string RunExplicitEnvironmentProbe(string scriptPath, string outputPath, string secretName)
        {
            if (String.IsNullOrEmpty(scriptPath) || !System.IO.Path.IsPathRooted(scriptPath) ||
                String.IsNullOrEmpty(outputPath) || !System.IO.Path.IsPathRooted(outputPath))
                throw new ArgumentException("Probe paths must be absolute.");

            string systemRoot = ReadVariable("SystemRoot");
            string systemDirectory = Environment.SystemDirectory;
            string powershell = System.IO.Path.Combine(
                systemRoot, "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
            string currentDirectory = systemDirectory;
            string temp = System.IO.Path.GetDirectoryName(scriptPath);
            string systemDrive = System.IO.Path.GetPathRoot(systemRoot).TrimEnd('\\');
            if (!System.IO.File.Exists(powershell) || String.IsNullOrEmpty(systemDrive) ||
                systemDrive.Length != 2 || String.IsNullOrEmpty(temp))
                throw new InvalidOperationException("Trusted Windows paths could not be derived.");

            List<string> entries = ReadApprovedDriveEntries();
            HashSet<string> names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (string entry in entries)
            {
                // Special drive entries have their own name space and are unique
                // in ReadApprovedDriveEntries; ordinary names are tracked below.
                if (entry.Length >= 4 && entry[0] == '=' && entry[2] == ':' && entry[3] == '=')
                    continue;
                throw new InvalidOperationException("Unexpected non-drive entry in inherited allowlist.");
            }

            AddVariable(entries, names, "ComSpec", System.IO.Path.Combine(systemDirectory, "cmd.exe"));
            AddVariable(entries, names, "PATH", systemDirectory);
            AddVariable(entries, names, "SystemDrive", systemDrive);
            AddVariable(entries, names, "SystemRoot", systemRoot);
            AddVariable(entries, names, "windir", systemRoot);
            AddVariable(entries, names, "TEMP", temp);
            AddVariable(entries, names, "TMP", temp);
            AddVariable(entries, names, "OS", "Windows_NT");
            AddVariable(entries, names, "PATHEXT", ".COM;.EXE;.BAT;.CMD");

            entries.Sort(StringComparer.OrdinalIgnoreCase);
            StringBuilder environment = new StringBuilder();
            foreach (string entry in entries)
            {
                if (String.IsNullOrEmpty(entry) || entry.IndexOf('\0') >= 0)
                    throw new InvalidOperationException("Explicit environment contains an invalid entry.");
                environment.Append(entry);
                environment.Append('\0');
            }
            environment.Append('\0');
            if (environment.Length > 32768)
                throw new InvalidOperationException("Explicit environment exceeds 32768 UTF-16 code units.");

            IntPtr environmentMemory = Marshal.AllocHGlobal(checked(environment.Length * 2));
            try
            {
                for (int i = 0; i < environment.Length; i++)
                    Marshal.WriteInt16(environmentMemory, checked(i * 2), (short)environment[i]);

                STARTUPINFOW startup = new STARTUPINFOW();
                startup.cb = (uint)Marshal.SizeOf(typeof(STARTUPINFOW));
                PROCESS_INFORMATION process;
                string arguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"" +
                    scriptPath + "\" \"" + outputPath + "\" \"" + secretName + "\"";
                StringBuilder commandLine = new StringBuilder("\"" + powershell + "\" " + arguments);

                // CREATE_UNICODE_ENVIRONMENT | CREATE_NO_WINDOW. The environment
                // block is explicitly supplied; NULL/inherited environment is forbidden.
                const uint flags = 0x00000400 | 0x08000000;
                if (!CreateProcessW(
                    powershell, commandLine, IntPtr.Zero, IntPtr.Zero, false,
                    flags, environmentMemory, currentDirectory, ref startup, out process))
                {
                    int error = Marshal.GetLastWin32Error();
                    throw new Win32Exception(error,
                        "CreateProcessW failed for explicit environment (Win32=" + error +
                        ", entries=" + entries.Count + ", chars=" + environment.Length + ").");
                }

                try
                {
                    uint wait = WaitForSingleObject(process.hProcess, 15000);
                    if (wait != 0)
                    {
                        TerminateProcess(process.hProcess, 0x2BAD);
                        WaitForSingleObject(process.hProcess, 5000);
                        throw new InvalidOperationException("Explicit-environment child timed out or wait failed: " + wait);
                    }
                    uint exitCode;
                    if (!GetExitCodeProcess(process.hProcess, out exitCode))
                        throw new Win32Exception(Marshal.GetLastWin32Error(), "GetExitCodeProcess failed.");
                    if (exitCode != 0)
                        throw new InvalidOperationException("Explicit-environment child returned exit code " + exitCode + ".");
                    return "Entries=" + entries.Count.ToString() + ";Characters=" + environment.Length.ToString();
                }
                finally
                {
                    if (process.hThread != IntPtr.Zero) CloseHandle(process.hThread);
                    if (process.hProcess != IntPtr.Zero) CloseHandle(process.hProcess);
                }
            }
            finally
            {
                Marshal.FreeHGlobal(environmentMemory);
            }
        }
    }
}
'@
}

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$probeRoot = Join-Path ([IO.Path]::GetTempPath()) ('Sharnou-ExplicitEnv-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($probeRoot)
$scriptPath = Join-Path $probeRoot 'Probe.ps1'
$outputPath = Join-Path $probeRoot 'result.txt'
$secretName = 'SHARNOU_PHASE_2B8_PRIVATE_SECRET'
$secretValue = 'must-not-cross-process-boundary-7f19a6'
$probeScript = @'
param([string] $OutputPath, [string] $SecretName)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$secret = [Environment]::GetEnvironmentVariable($SecretName)
$result = @(
    'SystemRoot=' + $env:SystemRoot
    'windir=' + $env:windir
    'SystemDrive=' + $env:SystemDrive
    'PATH=' + $env:PATH
    'SecretPresent=' + [string]($null -ne $secret)
)
[IO.File]::WriteAllText($OutputPath, ($result -join "`r`n"), [Text.Encoding]::ASCII)
'@

try {
    [IO.File]::WriteAllText($scriptPath, $probeScript, [Text.Encoding]::ASCII)
    [Environment]::SetEnvironmentVariable($secretName, $secretValue, [EnvironmentVariableTarget]::Process)
    try {
        $summary = [Sharnou.DevAgentEnvironmentBlockNative]::RunExplicitEnvironmentProbe($scriptPath, $outputPath, $secretName)
        if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
            throw 'Explicit-environment child did not create its result file.'
        }
        $result = [IO.File]::ReadAllText($outputPath, [Text.Encoding]::ASCII)
        if ($result -notmatch '(?m)^SystemRoot=.+$' -or
            $result -notmatch '(?m)^windir=.+$' -or
            $result -notmatch '(?m)^SystemDrive=.+$' -or
            $result -notmatch '(?m)^PATH=.+$') {
            throw "Explicit-environment child did not receive required Windows variables: $result"
        }
        if ($result -notmatch '(?m)^SecretPresent=False$') {
            throw 'A unique secret variable from the broker/test parent leaked into the explicit child environment.'
        }
        if ($result.Contains($secretValue)) {
            throw 'The private test secret value appeared in child output.'
        }
        Write-Host ("PASS: bounded explicit Unicode environment launched the child ({0})" -f $summary) -ForegroundColor Green
        Write-Host 'PASS: required SystemRoot, windir, SystemDrive and PATH values were correct and present' -ForegroundColor Green
        Write-Host 'PASS: hidden per-drive current-directory entries were validated and preserved without copying ordinary inherited variables' -ForegroundColor Green
        Write-Host 'PASS: unique parent secret variable was absent from child environment' -ForegroundColor Green
        Write-Host 'DevAgent explicit environment primitive result: PASS' -ForegroundColor Green
    }
    finally {
        [Environment]::SetEnvironmentVariable($secretName, $null, [EnvironmentVariableTarget]::Process)
    }
}
finally {
    Remove-Item -LiteralPath $probeRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'Qualification boundary: process environment builder primitive only; broker integration and AppContainer-specific launch qualification remain pending.' -ForegroundColor Yellow
