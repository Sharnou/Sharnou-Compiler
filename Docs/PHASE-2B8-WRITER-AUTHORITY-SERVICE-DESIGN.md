# Phase 2B.8 - Trusted Writer and Execution Authority Architecture

**Status:** OWNER-APPROVED ARCHITECTURE - IMPLEMENTATION PENDING  
**Date:** 2026-11-27  
**Scope:** durable ACL journal, AppContainer profile lifecycle and crash recovery.

## 1. Owner decision recorded - 2026-11-27

The owner approved the recommended dedicated Windows service authority architecture and its deployment/security boundary for implementation planning:

- Dedicated service identity with an explicit service SID.
- Non-exportable machine-scope CNG signing key whose private operation ACL is restricted to that service SID (plus separately approved maintenance/recovery principals).
- Service-owned durable journal, workspace ACL transaction, AppContainer profile creation/deletion, Job Object ownership and crash recovery.
- Typed, bounded IPC in which the service validates transaction semantics itself; no generic signing, arbitrary descriptor restore, or arbitrary profile-delete oracle.
- Explicit installation, upgrade, key rotation/loss, uninstall and operator recovery lifecycle.

This approval selects the architecture; it does not assert that a Windows service, key, installer, IPC endpoint, or production authenticated journal has been implemented. The service design and all acceptance gates below remain binding. Crash-time profile recovery stays disabled until those gates are implemented and independently verified.

## Owner approval and implementation boundary

The test evidence proves two important facts:

1. User-scope DPAPI protects an envelope from direct byte tampering when the attacker cannot invoke the same user DPAPI context.
2. A different process running as the same user can create another valid DPAPI envelope using the same public optional entropy. The parent process successfully decrypted that child-created envelope.

Consequently, DPAPI CurrentUser and a constant entropy string cannot identify the trusted writer. They must not authorize profile deletion, ACL restoration, or journal retirement in a threat model that includes another same-user process.

**Recommended architecture:** move durable ACL transaction ownership and recovery into a dedicated Windows service running under a dedicated service SID. The service owns the journal, its non-exportable signing key, workspace ACL changes, AppContainer profile create/delete, Job Object lifecycle, and recovery. The existing compiler-emitted broker becomes a restricted client/launcher rather than the owner of durable security state.

This recommendation is a design boundary, not an implemented service and not authorization to enable autonomous execution.

## 2. Why a generic signing service is insufficient

Do not expose any IPC operation resembling:

- Sign arbitrary bytes.
- MAC arbitrary bytes.
- Encrypt arbitrary caller-supplied journal payload.
- Delete an arbitrary AppContainer profile by caller-supplied name.
- Restore caller-supplied security descriptors to caller-supplied paths.

A same-user malicious process can connect as the same logon principal and request those operations. A service SID or non-exportable private key does not help if the service acts as an unrestricted signing oracle or a confused deputy.

The service must own and validate the transaction semantics. Its private-key operation is reachable only after the service itself has validated the workspace, policy, descriptors, execution identifier, profile ownership and state transition.

## 3. Service security principal and key

- Install a dedicated service identity, for example `NT SERVICE\SharnouDevAgentAuthority`, with an explicitly configured service SID.
- Configure the service SID as restricted where supported by the selected service-host model. Keep the service's required privileges to the minimum set needed for workspace ACL management and process/job control.
- Provision a machine-scope CNG signing key with a non-exportable private key. The key's private operation access control must name the dedicated service SID; Administrators may retain recovery/maintenance access according to the approved installation policy.
- Do not store private key material, a DPAPI master secret, or a symmetric MAC key in the workspace, broker directory, tool manifest, environment, command line, or child process.
- The service must verify its own service SID and key identity at startup. Missing, replaced, inaccessible or unusable key material puts the authority into quarantine; it must not generate a replacement key and then accept old journals as valid.
- Key rotation must retain the previous verification key until all journals signed by it are closed or explicitly quarantined. Key loss, service reinstall, profile reset and machine restore require an operator-visible recovery procedure.

## 4. Typed IPC contract - no signing oracle

Use a local-only authenticated IPC endpoint (for example a named pipe with remote clients rejected). The pipe DACL is defense in depth, not the authorization boundary: assume any process running as an authorized interactive user can connect.

The client API should be typed and bounded. Initial operations:

1. `RegisterWorkspace`: administrator/owner-approved workspace root; service opens the root itself, rejects reparse/device/UNC/ADS forms, records final path, volume serial, full 128-bit FILE_ID_INFO identity, owner and policy. No caller-supplied file ID is trusted.
2. `BeginExecution`: caller supplies only a registered workspace handle/identifier and a fixed tool ID. Service verifies the active policy version and pinned tool hash, generates its own 128-bit execution ID and AppContainer profile name, creates the profile with zero capabilities, derives and verifies the package SID, captures the exact original DACL/SACL descriptors from service-opened handles, writes and authenticates the journal, flushes and commits it, then applies the scoped ACL grants.
3. `LaunchBoundChild`: service constructs the complete command from a fixed tool manifest; no raw command string or arbitrary executable path. It creates the child suspended with the per-execution AppContainer token, restricted privileges, explicit Unicode environment and exact handle allowlist; assigns it to a service-owned Job Object before resume. The child never receives the journal key or authority pipe handle.
4. `CancelExecution`: service terminates the Job Object and waits until it is empty; it does not trust a client-provided PID as the authority boundary.
5. `CompleteExecution`: service verifies Job Object emptiness, persists bounded separate stdout/stderr, restores and verifies exact descriptors, deletes the per-execution AppContainer profile, records a completed transaction and retires the journal only after every cleanup step has succeeded.
6. `QueryExecution`: exposes bounded status and diagnostics. It cannot disclose key material or mutate transaction state.

The service must independently enforce state transitions and policy for every operation. A client-provided status, result, descriptor, SID, process identifier or "cleanup complete" claim is advisory only.

## 5. Authenticated durable journal v2

The service constructs the canonical v2 record itself. Minimum fields:

- Fixed magic, explicit format version and security-policy version.
- Cryptographically random execution GUID.
- Unique AppContainer profile name and exact package SID.
- Registered workspace volume serial and full 128-bit FILE_ID_INFO identifier.
- Canonical final workspace path, tied to the opened workspace file identity.
- Exact original root, Build and broker directory security descriptors, each independently length-bounded and validated.
- Fixed tool ID, exact pinned tool digest, service key identifier and transaction state.
- Monotonic state/cut-point sequence number.

Serialize with strict field ordering, exact length fields, size ceilings and no trailing data. Authenticate the exact canonical byte sequence using the service-owned signing key. A verifier must pin the public-key identity and validate the signature before parsing or acting on privileged metadata. Signature verification alone does not make a maliciously signed record safe; the service must also validate workspace identity, descriptor semantics and allowed state transitions.

The journal resides in a service-owned protected transaction directory, not in a user-writable workspace. The workspace root may contain only a non-authoritative transaction reference. The service journal is written to an exclusive temporary file, fully written, flushed, closed, atomically committed with write-through semantics, and only then may ACL grants be expanded.

## 6. Crash recovery and profile ownership

The service, not the user-mode client, is the durable transaction owner. On startup and periodically:

1. Acquire the service transaction lock for each workspace.
2. Open journal by handle; verify regular file, single link, no reparse point, final path and service-owned directory identity.
3. Verify journal signature and key ID before parsing identity metadata.
4. Verify workspace volume/file identity and descriptor structure before mutation.
5. Terminate or confirm absence of every execution Job Object recorded by the service's own execution table.
6. Restore parent descriptor before descendants; read back and compare exact DACL/SACL state.
7. Derive the AppContainer SID from the authenticated profile name and compare it with the authenticated SID. Delete only the profile owned by that transaction and only after ACL restoration and Job Object emptiness.
8. Record cleanup completion durably; retire the journal only after exact descriptor restoration, child emptiness, handle cleanup and profile deletion are all verified.

If a journal is invalid, signature verification fails, workspace identity differs, a profile is still in use, a descriptor cannot be restored or a profile deletion fails, retain the journal and quarantine the workspace. Never fall back to the current v1 journal parser and never broaden DACLs to make recovery easier.

## 7. Service installation and compatibility gate

A Windows service changes deployment and operational requirements:

- Requires an installer/update path with an explicit service registration and rollback story.
- Requires service versioning, startup recovery, upgrade/downgrade policy and uninstaller behavior.
- Requires an operator recovery method when the machine key or service profile is lost.
- Must be qualified on Windows 10 and the supported Windows Server runner, including service shutdown during active work.
- Must not enable any model-facing execution merely because the service is installed.

Before implementation, the owner must accept that the DevAgent security authority is an installed Windows service and approve the installer/service maintenance model. This is a product/deployment decision, not a code-level default to apply silently.

## 8. Acceptance gates

1. Service SID and private-key ACL independently verified from the running service token.
2. Non-exportability and key access denial from the broker, AppContainer child and another same-user process.
3. No arbitrary signing/decryption/profile-delete IPC surface.
4. Separate same-user client can connect but cannot cause unauthorized workspace, descriptor, SID, profile or state changes.
5. Service writes/signs a canonical record; a same-user forged record fails signature verification before any ACL or profile operation.
6. Crash injection after journal commit, each ACL mutation, profile creation, child creation, Job Object assignment, resume, output capture, rollback, profile deletion and journal retirement.
7. Restart recovery restores exact DACL/SACL, terminates all children, deletes only the correct profile and retires the journal only after verification.
8. Concurrent workspace and service restart tests, plus Windows 10 / Windows Server compatibility.
9. Independent verifier reads the actual service executable imports, key access, service SID, journal signatures and emitted broker launch policy.
10. Owner security review and explicit limited-canary approval.

Until these gates pass, model-facing and autonomous process execution remain disabled.
