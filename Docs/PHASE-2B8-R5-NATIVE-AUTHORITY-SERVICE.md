# Phase 2B.8 R5 - Native Windows Execution Authority Service

**Milestone:** R5 - Native Windows Execution Authority Service  
**Increment:** R5.0 - typed IPC contract and fail-closed framing parser  
**Status:** IMPLEMENTATION CANDIDATE / PROTOCOL FIXTURE ONLY / NOT SECURITY ACCEPTED  
**Base:** R4 exact-head Windows-tested candidate b0d3ff96deadd04072d7f63ccb4b2c85b42a5c15  
**Date:** 2026-11-27

## 1. Purpose and trust boundary

R5 moves durable execution authority out of the interactive DevAgent broker and into a dedicated Windows service. The service must become the sole owner of the non-exportable machine-scope CNG key operation, authenticated transaction journal, registered workspace identity, AppContainer profile lifecycle, workspace ACL mutation/restoration, restricted child and Job Object lifecycle, bounded output, cancellation, cleanup, quarantine and restart recovery.

The service is not a generic cryptographic or privileged-operation oracle. A client can request only policy-bounded typed operations. It cannot supply authoritative descriptors, SIDs, profile names, process handles, arbitrary paths, raw commands, signing bytes, profile-delete instructions or cleanup-complete claims.

**R5.0 does not implement a Windows service executable, SCM registration, named-pipe listener, production key, production journal, process launch or recovery.** The C# parser in the PowerShell test is test-only; it is not production service code and must not be copied into the emitted service.

## 2. Ordered implementation increments

| Increment | Scope | Required evidence |
|---|---|---|
| **R5.0** | Typed request frame, exact opcode schemas, strict length/UTF-16/path-form validation | Windows positive and negative parser cases; no process or privilege side effect |
| **R5.1** | Native SCM service host emitted by Sharnou Compiler; service main, control handler, status transitions and clean shutdown | Actual generated PE imports verified; service install/start/stop/delete tests |
| **R5.2** | Dedicated service SID and machine-scope non-exportable CNG key provisioning/access boundary | Running service token and key ACL inspection; private operation denied to broker, child and another same-user process |
| **R5.3** | Local named-pipe transport; remote clients rejected; client identity/session checks; bounded reads/writes | Remote rejection, unauthorized same-user client, message truncation/flood, disconnect and service shutdown tests |
| **R5.4** | Service-owned transaction store, canonical signed v2 journal, durable write-ahead transitions and key-ID pinning | Real flush/atomic commit, forged journal rejection before mutation, key rotation/loss quarantine |
| **R5.5** | Registered workspace operations and policy-owned AppContainer/ACL/job transactions | Opened-handle/path/file-ID binding, exact descriptor capture/restore, no generic restore/delete/sign operations |
| **R5.6** | Crash recovery, concurrency, service restart and operator recovery | Crash cuts at every durable/external transition, idempotent restore, job emptiness, exact ACL/SACL and profile retirement |
| **R5.7** | Independent native-import/evidence verifier and security review | Actual PE import table, service SID/key ACL, journal proof, Windows 10 + Server evidence and independent review |

R5 is not accepted until R5.1-R5.7 and Phase 2B.8 lifecycle acceptance pass. R5.0 is only the typed protocol tranche.

## 3. IPC transport and framing contract v1

The intended production transport is a local named pipe. The listener must use the Windows mode that rejects remote clients. Its DACL is defense in depth only: assume any process running as the interactive user can connect. The service must independently authenticate and authorize every request and validate all referenced server-owned objects.

The format is byte-oriented, little-endian, fixed-header, length-bounded and exact-length. Never marshal an untrusted byte buffer directly as a native structure.

### 3.1 Fixed 40-byte header

| Offset | Size | Field | Request requirement |
|---:|---:|---|---|
| 0 | 8 | Magic | ASCII SHARIPC1 |
| 8 | 2 | Protocol version | 1 |
| 10 | 2 | Operation | One of the opcodes in section 3.2 |
| 12 | 4 | Flags | 0; all other bits reserved |
| 16 | 16 | Request ID | Non-empty opaque 128-bit identifier |
| 32 | 4 | Payload length | Exact byte count, 0..16,384 |
| 36 | 4 | Status | 0 in a request; response-only field |

Frame length must equal 40 + payload_length exactly. Reject short header, short payload, trailing byte, unsupported version/opcode, nonzero request flags/status, empty request ID, or payload over 16,384 bytes before dispatch.

The service reads the fixed header first, validates the bounded payload size before allocation, then reads exactly the declared payload. Never issue an unbounded pipe read or trust the client to send a complete message. R5.3 will define transport timeouts and disconnect behavior.

### 3.2 Request opcodes

| Value | Operation | Payload | Service authority rule |
|---:|---|---|---|
| 1 | RegisterWorkspace | u32 char_count + exactly that many UTF-16LE code units | Registration request only. The service opens the path itself, resolves final path and file identity, rejects reparse/UNC/device/ADS/traversal escapes, and applies owner registration policy. |
| 2 | BeginExecution | 32 bytes: WorkspaceId[16], ToolId u32, TimeoutMs u32, PolicyVersion u32, Reserved u32 | Workspace ID and tool ID must resolve in the service registry. Only registered fixed tools are allowed. Timeout and policy version are range-checked. |
| 3 | LaunchBoundChild | ExecutionId[16] | Launch only a service-owned execution in the correct state. Command, image, arguments, environment and handles come from service policy, never from caller-supplied raw strings. |
| 4 | CancelExecution | ExecutionId[16] | Terminate the service-owned Job Object after ownership/state validation; never trust a caller PID. |
| 5 | QueryExecution | ExecutionId[16] | Read-only bounded status. No state transition or key material is exposed. |

There is no request opcode for signing bytes, MACing arbitrary data, deleting an arbitrary AppContainer profile, restoring arbitrary descriptors, selecting an arbitrary executable, or declaring transaction completion. Workspace IDs, execution IDs and request IDs must be non-empty. The service creates execution IDs and profile names; a caller cannot choose either.

### 3.3 Typed payload validation

**RegisterWorkspace**

- Payload length equals 4 + 2 * char_count.
- char_count is 1..4096; UTF-16LE must be valid and contain no embedded NUL.
- Request syntax must be an absolute local drive path (X:\...). Reject UNC, \\?\, \\.\, relative paths, device namespaces, alternate-data-stream colons beyond the drive separator and control characters.
- These syntactic checks are only an early rejection gate. The service opens the candidate itself, inspects the opened object, resolves its final path and volume/file identity, rejects reparse points/links according to policy, and associates registration with the authenticated owner. A syntactically acceptable path is not automatically trusted.

**BeginExecution**

- WorkspaceId: 16 opaque bytes, not all zero.
- ToolId: fixed registry values 1..6 in protocol v1. The service maps the ID to an immutable manifest entry and verifies its pinned SHA-256 at execution time.
- TimeoutMs: 100..600,000 inclusive.
- PolicyVersion: exactly 1 for protocol v1.
- Reserved: exactly 0.
- Exact payload length: 32 bytes.

**LaunchBoundChild, CancelExecution, QueryExecution**

- Exactly 16 bytes, containing a non-empty service-issued ExecutionId.
- The service independently verifies caller/session authorization and current service-owned state for every request.
- Duplicate, stale, cross-workspace and out-of-order requests fail closed.

## 4. Service-owned lifecycle

The production service enforces the monotonic state machine:

REGISTERED -> PREPARING -> JOURNALED -> PROFILE_CREATED -> ACL_APPLIED -> CHILD_SUSPENDED -> JOB_ASSIGNED -> RUNNING -> QUIESCING -> RESTORING -> COMMITTED

Any failed precondition or unprovable cleanup enters QUARANTINED. A client cannot set or advance state. Each transition is authenticated, persisted before the next external mutation and replay-checked against a monotonic sequence. Recovery never accepts a client-supplied state, descriptor, profile name, SID or cleanup result as authority.

Before a child can resume, the service must prove: registered workspace file identity; durably committed signed journal; correct per-execution AppContainer token/SID with no unapproved capabilities; exact ACL mutation and descriptor preservation; explicit Unicode environment; exact inheritable-handle allowlist; pinned child image/tool hash; DLL loader policy; Job Object assignment/limits; bounded separate output channels.

Cleanup requires Job Object emptiness, exact DACL/SACL read-back equality, handle retirement and deletion of only the profile created by the transaction. Any failure retains the journal and quarantines the workspace.

## 5. Key and journal invariants

- The CNG private key is machine-scope, non-exportable and ACL-restricted to the dedicated service SID plus explicitly approved recovery principals.
- The broker, AppContainer child and other same-user processes cannot export, use or replace the private key.
- The service pins public-key identifiers and verifies signatures before parsing privileged journal fields. A valid signature does not replace semantic validation against service-opened handles, registered policy and legal state transitions.
- Missing/replaced key, unknown key ID, invalid signature, file-identity mismatch, descriptor mismatch or unsupported state causes quarantine. Never generate a replacement key and silently accept an old journal.
- The service owns journal writes, flush/atomic-commit ordering, recovery, profile retirement and journal deletion. The broker may hold only opaque IDs and typed response data.
- Journal files live under a service-protected directory outside user-writable workspaces. A workspace may contain a non-authoritative reference, never the authority record.

## 6. Native implementation constraints

The production service host and transport must be a genuine Sharnou AMD64 PE32+ image. No C# Add-Type, PowerShell host process, MSVC, Clang, Visual Studio, MSBuild, external assembler/linker, downloaded compiler or fake PE is allowed in the production path. Test-only PowerShell/.NET interop may be used under Tests/.

Every native service API addition requires, in the same reviewed change:
1. Correct import descriptor, lookup table, IAT slot and DLL-name generation.
2. Correct emitter IAT offsets and x64 argument-register/stack marshalling.
3. Stack alignment, shadow space, nonvolatile preservation and unwind metadata for every non-leaf callback.
4. PE-verifier updates against actual generated import descriptors/thunks.
5. A generated image whose actual import table matches the intended service host; the import table, not a plan manifest, is authoritative.
6. SCM integration tests proving service start/stop/controls, startup failure behavior, recovery startup ordering and bounded shutdown.

The existing sh_dev_run_tool builtin remains opt-in. R5.0 does not expand it into an arbitrary process launcher.

## 7. R5.0 acceptance and explicit limitations

R5.0 is accepted only as a protocol-contract test tranche after the Windows fixture passes every positive and negative case on one exact commit. It does not create a pipe, connect to SCM, install a service, generate a service executable, use a CNG private key or mutate a workspace.

Required cases cover valid typed requests; invalid magic/version/opcode/flags/status/request ID; malformed and oversized lengths; truncation/trailing bytes; unknown tool/policy; out-of-range timeout; zero workspace/execution IDs; invalid UTF-16; UNC/device/relative/ADS paths; and exact payload schemas.

R5.1 must build the native Sharnou SCM service-host bootstrap, with a genuine generated PE and SCM lifecycle tests. The authority service remains absent until that host and the later key/IPC/journal/lifecycle increments are implemented.

**Model-facing process execution: DISABLED. Autonomous execution: DISABLED. Phase 2B.8: NOT SECURITY ACCEPTED.**
