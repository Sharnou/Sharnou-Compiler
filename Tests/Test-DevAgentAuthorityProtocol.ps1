[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not [BitConverter]::IsLittleEndian) {
    throw 'The authority IPC v1 wire format requires a little-endian Windows host.'
}

if (-not ('Sharnou.DevAgentAuthorityProtocolV1' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;

namespace Sharnou
{
    public sealed class DevAgentAuthorityRequest
    {
        public ushort Operation;
        public Guid RequestId;
        public byte[] Payload;
    }

    // Test-only protocol contract parser. This is not production service code.
    public static class DevAgentAuthorityProtocolV1
    {
        public const int HeaderBytes = 40;
        public const int MaximumPayloadBytes = 16384;
        private static readonly byte[] Magic = Encoding.ASCII.GetBytes("SHARIPC1");

        private static bool IsZero(byte[] value)
        {
            int aggregate = 0;
            for (int i = 0; i < value.Length; i++) aggregate |= value[i];
            return aggregate == 0;
        }

        private static uint ReadU32(byte[] bytes, int offset)
        {
            return BitConverter.ToUInt32(bytes, offset);
        }

        private static ushort ReadU16(byte[] bytes, int offset)
        {
            return BitConverter.ToUInt16(bytes, offset);
        }

        private static void Require(bool condition, string message)
        {
            if (!condition) throw new InvalidDataException(message);
        }

        private static void ValidateWorkspacePath(byte[] payload)
        {
            Require(payload.Length >= 6, "RegisterWorkspace payload is too short.");
            uint characterCount = ReadU32(payload, 0);
            Require(characterCount >= 1 && characterCount <= 4096,
                "RegisterWorkspace character count is outside 1..4096.");
            long expectedLength = 4L + ((long)characterCount * 2L);
            Require(expectedLength == payload.Length,
                "RegisterWorkspace UTF-16 length does not exactly match the frame payload.");

            byte[] pathBytes = new byte[checked((int)characterCount * 2)];
            Buffer.BlockCopy(payload, 4, pathBytes, 0, pathBytes.Length);
            string path;
            try
            {
                UnicodeEncoding strictUtf16 = new UnicodeEncoding(false, false, true);
                path = strictUtf16.GetString(pathBytes);
            }
            catch (DecoderFallbackException)
            {
                throw new InvalidDataException("RegisterWorkspace path contains invalid UTF-16.");
            }

            Require(path.Length >= 3, "RegisterWorkspace path is too short.");
            Require(path.IndexOf('\0') < 0, "RegisterWorkspace path contains an embedded NUL.");
            for (int i = 0; i < path.Length; i++)
                Require(!Char.IsControl(path[i]), "RegisterWorkspace path contains a control character.");

            Require(Char.IsLetter(path[0]) && path[1] == ':' && path[2] == '\\',
                "RegisterWorkspace requires an absolute local drive path.");
            Require(!path.StartsWith("\\\\", StringComparison.Ordinal),
                "UNC paths are not allowed.");
            Require(!path.StartsWith("\\\\?\\", StringComparison.Ordinal) &&
                    !path.StartsWith("\\\\.\\", StringComparison.Ordinal),
                "Device and extended-length path namespaces are not allowed.");

            for (int i = 2; i < path.Length; i++)
            {
                if (path[i] == ':')
                    throw new InvalidDataException("Alternate data stream syntax is not allowed.");
            }

            string[] components = path.Substring(3).Split('\\');
            for (int i = 0; i < components.Length; i++)
                Require(components[i] != "." && components[i] != "..",
                    "Dot-segment traversal is not accepted in a registration request.");
        }

        private static void ValidateBeginExecution(byte[] payload)
        {
            Require(payload.Length == 32, "BeginExecution payload must be exactly 32 bytes.");
            byte[] workspaceId = new byte[16];
            Buffer.BlockCopy(payload, 0, workspaceId, 0, workspaceId.Length);
            Require(!IsZero(workspaceId), "BeginExecution workspace ID must be non-empty.");

            uint toolId = ReadU32(payload, 16);
            uint timeoutMs = ReadU32(payload, 20);
            uint policyVersion = ReadU32(payload, 24);
            uint reserved = ReadU32(payload, 28);

            Require(toolId >= 1 && toolId <= 6, "BeginExecution tool ID is not in the fixed v1 registry range.");
            Require(timeoutMs >= 100 && timeoutMs <= 600000,
                "BeginExecution timeout is outside 100..600000 milliseconds.");
            Require(policyVersion == 1, "BeginExecution policy version is unsupported.");
            Require(reserved == 0, "BeginExecution reserved field must be zero.");
        }

        private static void ValidateExecutionId(byte[] payload, string operation)
        {
            Require(payload.Length == 16, operation + " payload must be exactly 16 bytes.");
            Require(!IsZero(payload), operation + " execution ID must be non-empty.");
        }

        public static DevAgentAuthorityRequest ValidateRequest(byte[] frame)
        {
            Require(frame != null, "Frame cannot be null.");
            Require(frame.Length >= HeaderBytes, "Frame is shorter than the 40-byte header.");

            for (int i = 0; i < Magic.Length; i++)
                Require(frame[i] == Magic[i], "IPC frame magic is invalid.");

            Require(ReadU16(frame, 8) == 1, "Unsupported IPC protocol version.");
            ushort operation = ReadU16(frame, 10);
            Require(operation >= 1 && operation <= 5, "Unknown IPC request operation.");
            Require(ReadU32(frame, 12) == 0, "Request flags must be zero.");

            byte[] requestIdBytes = new byte[16];
            Buffer.BlockCopy(frame, 16, requestIdBytes, 0, requestIdBytes.Length);
            Require(!IsZero(requestIdBytes), "Request ID must be non-empty.");

            uint payloadLength = ReadU32(frame, 32);
            Require(payloadLength <= MaximumPayloadBytes, "IPC payload exceeds the 16 KiB maximum.");
            Require(ReadU32(frame, 36) == 0, "Request status field must be zero.");

            long expectedLength = (long)HeaderBytes + payloadLength;
            Require(expectedLength == frame.Length,
                "IPC frame is truncated or contains trailing bytes.");

            byte[] payload = new byte[(int)payloadLength];
            if (payload.Length > 0)
                Buffer.BlockCopy(frame, HeaderBytes, payload, 0, payload.Length);

            switch (operation)
            {
                case 1: ValidateWorkspacePath(payload); break;
                case 2: ValidateBeginExecution(payload); break;
                case 3: ValidateExecutionId(payload, "LaunchBoundChild"); break;
                case 4: ValidateExecutionId(payload, "CancelExecution"); break;
                case 5: ValidateExecutionId(payload, "QueryExecution"); break;
                default: throw new InvalidDataException("Unknown IPC request operation.");
            }

            DevAgentAuthorityRequest request = new DevAgentAuthorityRequest();
            request.Operation = operation;
            request.RequestId = new Guid(requestIdBytes);
            request.Payload = payload;
            return request;
        }
    }
}
'@
}

function New-AuthorityFrame {
    param(
        [Parameter(Mandatory = $true)][ValidateRange(1, 65535)][int] $Operation,
        [Parameter(Mandatory = $true)][byte[]] $Payload,
        [Guid] $RequestId = ([Guid]::NewGuid()),
        [uint16] $Version = 1,
        [uint32] $Flags = 0,
        [uint32] $Status = 0,
        [string] $MagicText = 'SHARIPC1'
    )
    if ($Payload -eq $null) { throw 'Payload cannot be null.' }
    $stream = New-Object IO.MemoryStream
    $writer = New-Object IO.BinaryWriter($stream, [Text.Encoding]::ASCII, $true)
    try {
        $writer.Write([Text.Encoding]::ASCII.GetBytes($MagicText))
        $writer.Write([uint16]$Version)
        $writer.Write([uint16]$Operation)
        $writer.Write([uint32]$Flags)
        $writer.Write($RequestId.ToByteArray())
        $writer.Write([uint32]$Payload.Length)
        $writer.Write([uint32]$Status)
        $writer.Write($Payload)
        $writer.Flush()
        return ,$stream.ToArray()
    }
    finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

function New-BeginExecutionPayload {
    param(
        [Guid] $WorkspaceId = ([Guid]::NewGuid()),
        [uint32] $ToolId = 1,
        [uint32] $TimeoutMs = 30000,
        [uint32] $PolicyVersion = 1,
        [uint32] $Reserved = 0
    )
    $stream = New-Object IO.MemoryStream
    $writer = New-Object IO.BinaryWriter($stream, [Text.Encoding]::ASCII, $true)
    try {
        $writer.Write($WorkspaceId.ToByteArray())
        $writer.Write($ToolId)
        $writer.Write($TimeoutMs)
        $writer.Write($PolicyVersion)
        $writer.Write($Reserved)
        $writer.Flush()
        return ,$stream.ToArray()
    }
    finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

function New-WorkspacePayload {
    param([Parameter(Mandatory = $true)][string] $Path)
    $bytes = [Text.Encoding]::Unicode.GetBytes($Path)
    $stream = New-Object IO.MemoryStream
    $writer = New-Object IO.BinaryWriter($stream, [Text.Encoding]::ASCII, $true)
    try {
        $writer.Write([uint32]$Path.Length)
        $writer.Write($bytes)
        $writer.Flush()
        return ,$stream.ToArray()
    }
    finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

function Assert-AuthorityRequestAccepted {
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][byte[]] $Frame,
        [Parameter(Mandatory = $true)][int] $ExpectedOperation
    )
    $parsed = [Sharnou.DevAgentAuthorityProtocolV1]::ValidateRequest($Frame)
    if ($parsed.Operation -ne $ExpectedOperation) {
        throw "Authority protocol accepted '$Name' with the wrong operation value."
    }
    if ($parsed.RequestId -eq [Guid]::Empty) {
        throw "Authority protocol accepted '$Name' with an empty request identifier."
    }
    Write-Host ("PASS: authority IPC parser accepted {0}" -f $Name) -ForegroundColor Green
}

function Assert-AuthorityRequestRejected {
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][byte[]] $Frame
    )
    $rejected = $false
    try {
        [Sharnou.DevAgentAuthorityProtocolV1]::ValidateRequest($Frame) | Out-Null
    }
    catch {
        $exception = $_.Exception
        while ($null -ne $exception.InnerException) { $exception = $exception.InnerException }
        if ($exception -is [IO.InvalidDataException]) { $rejected = $true }
        else { throw }
    }
    if (-not $rejected) {
        throw "Authority IPC parser accepted invalid request: $Name"
    }
    Write-Host ("PASS: authority IPC parser rejected {0}" -f $Name) -ForegroundColor Green
}

$workspaceId = [Guid]::NewGuid()
$executionId = [Guid]::NewGuid()
$validBegin = New-AuthorityFrame -Operation 2 -Payload (New-BeginExecutionPayload -WorkspaceId $workspaceId)
Assert-AuthorityRequestAccepted -Name 'fixed-tool BeginExecution request' -Frame $validBegin -ExpectedOperation 2

$validLaunch = New-AuthorityFrame -Operation 3 -Payload $executionId.ToByteArray()
Assert-AuthorityRequestAccepted -Name 'service-issued LaunchBoundChild request' -Frame $validLaunch -ExpectedOperation 3

$validCancel = New-AuthorityFrame -Operation 4 -Payload $executionId.ToByteArray()
Assert-AuthorityRequestAccepted -Name 'CancelExecution request' -Frame $validCancel -ExpectedOperation 4

$validQuery = New-AuthorityFrame -Operation 5 -Payload $executionId.ToByteArray()
Assert-AuthorityRequestAccepted -Name 'read-only QueryExecution request' -Frame $validQuery -ExpectedOperation 5

$validWorkspace = New-AuthorityFrame -Operation 1 -Payload (New-WorkspacePayload -Path 'C:\Sharnou\DevAgentWorkspaces\Workspace-A')
Assert-AuthorityRequestAccepted -Name 'local drive RegisterWorkspace request' -Frame $validWorkspace -ExpectedOperation 1

$badMagic = [byte[]]$validQuery.Clone()
$badMagic[0] = 0x58
Assert-AuthorityRequestRejected -Name 'invalid magic' -Frame $badMagic

$badVersion = [byte[]]$validQuery.Clone()
[BitConverter]::GetBytes([uint16]2).CopyTo($badVersion, 8)
Assert-AuthorityRequestRejected -Name 'unsupported protocol version' -Frame $badVersion

$badOperation = New-AuthorityFrame -Operation 99 -Payload $executionId.ToByteArray()
Assert-AuthorityRequestRejected -Name 'unknown opcode' -Frame $badOperation

$badFlags = New-AuthorityFrame -Operation 5 -Payload $executionId.ToByteArray() -Flags 1
Assert-AuthorityRequestRejected -Name 'reserved request flags' -Frame $badFlags

$badStatus = New-AuthorityFrame -Operation 5 -Payload $executionId.ToByteArray() -Status 1
Assert-AuthorityRequestRejected -Name 'nonzero request status' -Frame $badStatus

$emptyRequest = New-AuthorityFrame -Operation 5 -Payload $executionId.ToByteArray() -RequestId ([Guid]::Empty)
Assert-AuthorityRequestRejected -Name 'empty request ID' -Frame $emptyRequest

Assert-AuthorityRequestRejected -Name 'truncated fixed header' -Frame (New-Object byte[] 39)

$shortPayload = New-Object byte[] ($validQuery.Length - 1)
[Array]::Copy($validQuery, $shortPayload, $shortPayload.Length)
Assert-AuthorityRequestRejected -Name 'truncated declared payload' -Frame $shortPayload

$trailing = New-Object byte[] ($validQuery.Length + 1)
[Array]::Copy($validQuery, $trailing, $validQuery.Length)
Assert-AuthorityRequestRejected -Name 'trailing frame byte' -Frame $trailing

$badLength = [byte[]]$validQuery.Clone()
[BitConverter]::GetBytes([uint32]16385).CopyTo($badLength, 32)
Assert-AuthorityRequestRejected -Name 'payload above 16 KiB' -Frame $badLength

Assert-AuthorityRequestRejected -Name 'wrong LaunchBoundChild payload size' -Frame (
    New-AuthorityFrame -Operation 3 -Payload ([byte[]]@(1,2,3)))

Assert-AuthorityRequestRejected -Name 'empty CancelExecution ID' -Frame (
    New-AuthorityFrame -Operation 4 -Payload ([byte[]]::new(16)))

Assert-AuthorityRequestRejected -Name 'empty workspace ID' -Frame (
    New-AuthorityFrame -Operation 2 -Payload (New-BeginExecutionPayload -WorkspaceId ([Guid]::Empty)))

Assert-AuthorityRequestRejected -Name 'tool ID outside fixed registry' -Frame (
    New-AuthorityFrame -Operation 2 -Payload (New-BeginExecutionPayload -ToolId 7))

Assert-AuthorityRequestRejected -Name 'timeout below minimum' -Frame (
    New-AuthorityFrame -Operation 2 -Payload (New-BeginExecutionPayload -TimeoutMs 99))

Assert-AuthorityRequestRejected -Name 'timeout above maximum' -Frame (
    New-AuthorityFrame -Operation 2 -Payload (New-BeginExecutionPayload -TimeoutMs 600001))

Assert-AuthorityRequestRejected -Name 'unsupported policy version' -Frame (
    New-AuthorityFrame -Operation 2 -Payload (New-BeginExecutionPayload -PolicyVersion 2))

Assert-AuthorityRequestRejected -Name 'nonzero reserved BeginExecution field' -Frame (
    New-AuthorityFrame -Operation 2 -Payload (New-BeginExecutionPayload -Reserved 1))

Assert-AuthorityRequestRejected -Name 'wrong BeginExecution payload size' -Frame (
    New-AuthorityFrame -Operation 2 -Payload ([byte[]]::new(31)))

Assert-AuthorityRequestRejected -Name 'UNC workspace path' -Frame (
    New-AuthorityFrame -Operation 1 -Payload (New-WorkspacePayload -Path '\\remote\share\work'))

Assert-AuthorityRequestRejected -Name 'extended device workspace path' -Frame (
    New-AuthorityFrame -Operation 1 -Payload (New-WorkspacePayload -Path '\\?\C:\work'))

Assert-AuthorityRequestRejected -Name 'device namespace workspace path' -Frame (
    New-AuthorityFrame -Operation 1 -Payload (New-WorkspacePayload -Path '\\.\C:\work'))

Assert-AuthorityRequestRejected -Name 'relative workspace path' -Frame (
    New-AuthorityFrame -Operation 1 -Payload (New-WorkspacePayload -Path 'relative\work'))

Assert-AuthorityRequestRejected -Name 'alternate data stream workspace path' -Frame (
    New-AuthorityFrame -Operation 1 -Payload (New-WorkspacePayload -Path 'C:\work\trusted:stream'))

Assert-AuthorityRequestRejected -Name 'dot-segment workspace traversal' -Frame (
    New-AuthorityFrame -Operation 1 -Payload (New-WorkspacePayload -Path 'C:\work\..\outside'))

$badCountPayload = [byte[]]@(5,0,0,0,0x43,0,0x3A,0,0x5C,0)
Assert-AuthorityRequestRejected -Name 'RegisterWorkspace UTF-16 character count mismatch' -Frame (
    New-AuthorityFrame -Operation 1 -Payload $badCountPayload)

$embeddedNullPayload = New-WorkspacePayload -Path ("C:\work\" + [char]0 + "folder")
Assert-AuthorityRequestRejected -Name 'embedded NUL in workspace path' -Frame (
    New-AuthorityFrame -Operation 1 -Payload $embeddedNullPayload)

$invalidUtf16 = New-Object byte[] 8
[BitConverter]::GetBytes([uint32]2).CopyTo($invalidUtf16, 0)
[BitConverter]::GetBytes([char]'C').CopyTo($invalidUtf16, 4)
[BitConverter]::GetBytes([char]0xD800).CopyTo($invalidUtf16, 6)
Assert-AuthorityRequestRejected -Name 'invalid UTF-16 surrogate in workspace path' -Frame (
    New-AuthorityFrame -Operation 1 -Payload $invalidUtf16)

Write-Host 'DevAgent authority IPC v1 protocol fixture: PASS' -ForegroundColor Green
Write-Host 'Boundary: test-only framing/schema parser; no named pipe, SCM service, production key, journal write, child launch or recovery is implemented.' -ForegroundColor Yellow
