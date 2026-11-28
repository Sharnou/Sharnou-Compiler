# Phase 2B.8 R5.2 / R5.3 - Service identity, protected CNG key, and authenticated local IPC

**Status:** DESIGN / ACCEPTANCE CONTRACT ONLY. No service identity has been provisioned, no production key exists, and no named-pipe listener is implemented by this document.  
**Date:** 2026-11-27  
**Design branch base:** R5.1.b corrected exact-head commit `ab00219f1aa9783c148035b754eebce7269f6fbb`.

## 0. Dependency and qualification boundary

R5.1.a is accepted for its bounded multi-target DIR64 relocation scope. R5.1.b has now passed its corrected exact-head Windows qualification:

- Exact tested source: `ab00219f1aa9783c148035b754eebce7269f6fbb`.
- Windows Server 2025 x64 run: [46070065850](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46070065850).
- Focused callback/relocation test: PASS.
- Combined compiler, PE, ABI, broker, identity/journal fixture and frozen M1-M6 suite: PASS; M1-M6 is 83/83.
- Exact-head acceptance manifest: PASS.
- Evidence artifact: `r5-1b-callback-abi-evidence`, ID `15232513039`, ZIP SHA-256 `b246b9e588d06c956ce59ea6583b7da99f1d9a02f3e35df50e8a5fc9a99ed10f`. The bundle was downloaded and inspected.

The combined transcript still records the Low-IL AppContainer DPAPI protection subtest as **INCONCLUSIVE** because Windows PowerShell could not load `System.Security` (FileNotFoundException). This is not a pass and remains an open Phase 2B.8 evidence gap.

**R5.1.c and R5.1.d are still mandatory prerequisites.** They must produce and qualify the actual Sharnou-generated SCM service executable, its real service identity configuration point, and its stop/restart behavior. R5.2 implementation must not start against a protocol mock, callback probe, or service test fixture. This document prepares the architecture and acceptance contracts only; it does not waive R5.1.c/.d.

### Ordered dependency graph

```text
R5.1.a relocations (accepted) ----+
                                  +--> R5.1.c real SCM service host
R5.1.b callback ABI (accepted) ---+          |
                                             v
                                      R5.1.d lifecycle acceptance
                                             |
                                             v
                                      R5.2 service SID + CNG key
                                             |
                                             v
                                      R5.3 authenticated local pipe
                                             |
                                             v
                                      R5.4 service-owned signed journal
                                             |
                                             v
                                      R5.5 transaction operations
                                             |
                                             v
                                      R5.6 crash/restart/recovery
                                             |
                                             v
                                      R5.7 independent security review
```

A R5.2/R5.3 design pass is not an implementation pass and cannot authorize service rollout, a production journal, child process creation, or execution authority.

---

# 1. R5.2 - Dedicated service identity and non-exportable machine CNG key

## 1.1 Security objective

Establish a Windows identity that is unique to the native authority service and a persistent machine-scope signing key whose private operation is available to that identity only.

The service identity and key form the writer trust anchor for R5.4's authenticated journal. They must not create a generic signing service. The service must never accept caller-supplied bytes and return an arbitrary signature.

### Required invariants

1. The service runs in its own process, under a dedicated virtual service account, not LocalSystem and not an interactive user.
2. The SCM-configured service SID is enabled and restricted in the actual service process token.
3. The service independently verifies the expected identity before entering SERVICE_RUNNING.
4. The private key is persisted at machine scope, with signing-only usage and no private export policy.
5. The key's protected DACL grants the minimum provider-validated private-operation access to the service SID; SYSTEM retains recovery ownership.
6. A normal user process, another same-user process, the DevAgent client, and an AppContainer child cannot open or use the private key.
7. The service cannot silently create, overwrite, replace, or regenerate a missing or mismatched production key.
8. Key provisioning is an explicit install/maintenance action performed outside ServiceMain.
9. No IPC operation exposes generic signing, MAC, decryption, key export, or key deletion.

The software KSP key is protected by CNG access control and export policy. This is not a claim of TPM-backed or hardware-isolated storage, and it does not claim resistance to a fully privileged local administrator, SYSTEM, kernel compromise, or offline machine compromise.

## 1.2 Stable service identity

Use one stable, versioned service name:

- SCM service name: `SharnouDevAgentAuthority`.
- Virtual service account: `NT SERVICE\\SharnouDevAgentAuthority`.
- Service type: `SERVICE_WIN32_OWN_PROCESS`.
- Service SID mode: `SERVICE_SID_TYPE_RESTRICTED` (value 0x3).
- One service per process. Do not share a host process with unrelated services.

The installer/provisioner configures the service account and SID mode through the SCM configuration APIs. The service must not attempt to reconfigure its own identity at runtime.

The SID is resolved using the Windows account/SID APIs for the exact configured service name. Never hard-code a textual SID or copy one from a developer machine. The verifier must query the SCM configuration and resolve the service principal independently.

### Runtime token attestation

Before reporting SERVICE_RUNNING, the service must open its own process token and inspect, at minimum:

- TokenUser.
- TokenGroups.
- TokenRestrictedSids.
- TokenPrivileges.
- TokenSessionId.
- TokenIntegrityLevel.

Required checks:

1. The SCM configuration reports the expected service name, own-process service type, virtual account, and restricted service SID mode.
2. The configured account resolves to the expected SID and the running process TokenUser matches that configured account identity.
3. The expected service SID is present in TokenGroups with the required enabled attributes.
4. With restricted SID mode, the expected service SID is also present in TokenRestrictedSids.
5. The process is in Session 0 and is not running as LocalSystem, an interactive user, or an administrator account.
6. No unexpected enabled privileged groups or privileges are present. The exact allowed token shape is measured on the supported Windows builds and pinned in the verifier; do not assume a token layout from one CI runner.
7. The process image resolves to the protected installation directory, has no reparse-point substitution, and matches the installed executable identity/hash recorded by the installer.

A failed or ambiguous identity check prevents SERVICE_RUNNING. It must be a distinct, logged startup failure, not a fallback to LocalService or LocalSystem.

### Restricted-token resource design

SERVICE_SID_TYPE_RESTRICTED adds the service SID to the process token's restricted SID list. Every protected resource required by the service must therefore be tested with the real restricted token and its actual DACL. Do not respond to an access-denied result by granting broad access to Users, Authenticated Users, Everyone, or all service processes.

The key, pipe, service configuration, installation directory, and future journal directory each receive independent ACL verification. Passing one ACL test does not imply another resource is protected.

## 1.3 Machine-scope key profile

Baseline provider and key profile:

| Property | Required value |
|---|---|
| Provider | Microsoft Software Key Storage Provider |
| Scope | Machine (`NCRYPT_MACHINE_KEY_FLAG`) |
| Algorithm | RSA |
| Modulus length | 3072 bits |
| Intended operation | Signature only |
| Signature scheme | RSA-PSS with SHA-256, consistent with the existing authenticated-journal envelope design |
| Export policy | Zero private-export flags |
| Persistence | Persisted, versioned key name |
| Key identifier | SHA-256 of the canonical exported public-key blob |
| Security descriptor support | Must be positively confirmed by the provider |
| Failure policy | Quarantine/fail closed; never auto-create a replacement |

The baseline key name is versioned, for example:

`Sharnou.DevAgentAuthority.JournalSigning.v1`

The final constant must be centralized and included in the protected installation manifest. R5.4 must use the same key-ID derivation and RSA-PSS/SHA-256 domain-separated envelope contract already described in the authenticated-journal design.

The Software KSP is the baseline for compatibility and repeatable Windows CI. If hardware-backed protection is later required, it is a separate provider/compatibility qualification; do not silently substitute a provider or claim hardware protection for a software key.

## 1.4 Provisioning must be out-of-process

**Do not call NCryptCreatePersistedKey from the service's ServiceMain/startup path.** Microsoft's API documentation explicitly warns that a service must not call this function from its StartService function because a deadlock can occur.

Provisioning is therefore a separate, administrator-controlled install/maintenance operation, implemented by a Sharnou-generated native provisioning helper after the service configuration/SID has been created and before normal service operation. It must not be an IPC operation.

The provisioning sequence is:

1. Verify the service is stopped and its SCM identity/SID configuration is correct.
2. Resolve the service SID from the installed service name.
3. Open the configured KSP and query its key security-descriptor support.
4. If the provider does not positively report support for key security descriptors, stop. Do not fall back to a filesystem ACL guess.
5. Create the named persisted key with machine scope and without the overwrite flag. If the key already exists, return an explicit EXISTS/RECONCILIATION result; never overwrite it.
6. Set the RSA length, signing-only key usage, zero export policy, and protected key DACL before finalization.
7. Set/verify SYSTEM ownership and a protected DACL. Grant the service SID only the minimum provider-validated rights necessary to open and sign. Do not grant broad access to interactive users, the broker, AppContainer children, or generic authenticated principals.
8. Finalize the key.
9. Close and reopen it through the provider.
10. Read back algorithm, key length, key usage, export policy, machine-scope property, owner and DACL. Compare the retrieved values with the exact approved policy.
11. Export only the public key, derive the key ID, and write the public key identity/active key metadata into a protected machine configuration store.
12. Run a fixed, domain-separated service self-test. The service signs only its internal fixed challenge; the verifier validates it using the public key. This is not a caller-accessible signing API.
13. Start the service and independently inspect its process token and key access.

All native CNG status values must be captured without lossy conversion to Win32 last-error values. A failed property write, unsupported property, unexpected provider behavior, or read-back mismatch aborts provisioning and leaves the service stopped.

## 1.5 Key startup verification and use boundary

### Critical CNG execution-context constraint

Microsoft's NCrypt API documentation warns that a service must not call several key-storage operations from its StartService function because a deadlock can occur. This warning is not limited to key creation: it also appears on NCryptOpenKey and NCryptSignHash. Consequently, R5.2 must not place provider calls in ServiceMain or HandlerEx, and must not assume that moving only key creation into the installer is sufficient.

The proposed service-side design is a dedicated, bounded `KeyOpsWorker` thread:

1. ServiceMain first publishes START_PENDING with a finite checkpoint/wait hint.
2. ServiceMain starts the worker and waits on a dedicated readiness event with a fixed deadline. ServiceMain performs no NCrypt/KSP calls.
3. The worker opens the configured provider and exact persisted machine key, reads back and verifies the required properties and security descriptor, and completes the fixed internal signing self-test.
4. The worker retains ownership of the opaque NCrypt handles. Handles are not copied into caller-controlled state or exposed over IPC.
5. The worker signals success/failure to ServiceMain. Only after success may ServiceMain publish SERVICE_RUNNING.
6. A timeout, provider failure, property mismatch, or worker failure causes bounded worker cancellation/join and fail-closed startup. The service must not fall back to a new key, a user-scoped key, or an ephemeral key.

This worker-thread pattern is a **design candidate, not an assumed Microsoft guarantee**. Its actual behavior must be qualified inside the real R5.1.c/d own-process SCM service on every supported Windows target. If KSP calls from the worker still block or deadlock while the service is starting, stop and return to architecture review; do not move the calls back into ServiceMain and do not quietly add an alternate helper process or weaken the security boundary.

The worker is also the only place permitted to execute R5.4's future service-owned signing operation. It must accept only a typed, validated, service-owned journal transaction object through a bounded internal queue. The worker must not expose an arbitrary-byte signing, SignHash, MAC, decryption, export, or deletion interface to the named-pipe dispatcher. Before R5.4 exists, R5.2 uses only a fixed internal challenge for the signing self-test.

### Permitted startup responsibilities

The service lifecycle code may:

- Start and stop the worker using bounded events and waits.
- Publish START_PENDING/RUNNING/STOP_PENDING/STOPPED through the SCM status API.
- Verify worker readiness and propagate a typed startup failure.
- Hold an opaque worker-owned readiness result; it must not directly inspect or manipulate a provider handle.

The KeyOpsWorker may:

- Open the configured Microsoft Software KSP.
- Open only the exact versioned persisted machine key using machine scope and silent operation.
- Read and validate the public key, key identifier, algorithm, key length, key usage, export policy, owner and DACL.
- Perform the fixed, domain-separated internal challenge signature and close/reopen verification.
- Retain the private key handle exclusively within the worker for later service-owned signing.

The service may not create, overwrite, regenerate, or delete the key during startup. Those operations remain in a separate administrator-controlled Sharnou-generated provisioning/maintenance helper, never in ServiceMain or the pipe protocol.

The private operation remains reserved for R5.4 canonical journal signing and accepts a validated service-owned transaction object, not arbitrary caller bytes. The named-pipe protocol must not expose a Sign, SignHash, MAC, ExportPrivateKey, DeleteKey, or equivalent operation.

## 1.6 Key ACL contract

### Provider access-mask rule

Microsoft documents `NCRYPT_SECURITY_DESCR_PROPERTY` and provider support detection through `NCRYPT_SECURITY_DESCR_SUPPORT_PROPERTY`, but does not publish a Software KSP generic-rights mapping or a complete per-operation ACE access-mask contract. Therefore, the implementation must not infer CNG key rights from file/directory rights. In particular, do not use `FILE_GENERIC_READ`, `FILE_GENERIC_WRITE`, or `FILE_ALL_ACCESS` as an assumed mapping for a persisted KSP key.

R5.2 must:
- Positively query `NCRYPT_SECURITY_DESCR_SUPPORT_PROPERTY`; fail closed if unsupported or indeterminate.
- Set and read back the persistent key DACL through `NCRYPT_SECURITY_DESCR_PROPERTY` using the documented security-information selector.
- Test the exact candidate ACE set against the real restricted service token on Windows Server 2025: provisioner administration, service key-open, service fixed-challenge signing, normal user denial, second same-user non-service process denial, and AppContainer denial.
- Record the raw NCrypt status, actual security descriptor, provider identity/version, OS build and token identity for every case.
- Pin the minimum tested ACE mask only after the positive and negative operations pass on the supported Windows builds. Any undocumented/provider-specific behavior remains an explicit compatibility constraint, not a guessed constant.

The key DACL must be:

- Explicit and protected from unintended inheritance.
- Owned by SYSTEM.
- Sufficient for the service SID to open/use the key for its approved signing operation.
- Insufficient for normal user, same-user non-service process, broker, and AppContainer child to open/use the private key.
- Free of grants to Everyone, Authenticated Users, Interactive Users, or broad local-user groups.

Do not guess the minimum CNG key access mask. Establish it experimentally on the supported KSP by testing the actual required private operation under the real restricted service token. Pin the exact DACL ACEs and masks after that test. If the KSP reports that key security descriptors are unsupported, or if the exact DACL cannot be read back, R5.2 is blocked.

The production installer and independent verifier must also inspect the protected SCM service configuration, service executable path, installation directory ACL, key provider/name, and key DACL. A correct key DACL is not sufficient if an untrusted principal can replace the service executable or its configuration.

## 1.7 Key lifecycle and recovery

Use versioned keys and an explicit lifecycle:

- **First provisioning:** create only when the key is absent and the installer is in an explicit first-install state.
- **Existing key:** open and verify; never overwrite.
- **Missing key:** quarantine the authority and retain any journal data. Never generate a fresh key and attempt to treat old records as valid.
- **Unexpected public key ID or algorithm:** quarantine.
- **Unexpected DACL/export policy/usage:** quarantine; do not auto-repair by broadening ACLs.
- **Rotation:** provision a new versioned key; publish its public key ID in protected metadata; verify both old and new public keys; use the new key for new records only after the explicit rotation transition; retain old verification material until every old-key journal is retired or explicitly quarantined.
- **Rollback:** never silently make an older key active after newer-key use.
- **Uninstall:** preserve key and journals by default. Destruction requires a separate explicit administrative recovery/purge operation after the journal inventory has been reconciled.
- **Machine restore/key loss:** stop the service and require operator recovery; do not downgrade to DPAPI or an ephemeral key.

R5.2 may test rotation and loss using disposable test keys. Production journal re-signing and old-key retirement semantics are implemented in R5.4, not in R5.2.

## 1.8 R5.2 test and acceptance matrix

Tests must use the real SCM service and actual machine-persisted KSP key, not an in-memory or DPAPI fixture.

| Area | Required positive/negative evidence |
|---|---|
| SCM identity | QueryServiceConfig/QueryServiceConfig2 confirms exact service account, own-process type and restricted SID mode |
| Process token | Actual running process token contains expected user/service SID and restricted SID; Session 0 and privilege shape verified |
| Protected executable | Image path/final file identity/hash and directory/service-config ACL verified |
| Key creation | Machine-scope persisted RSA-3072 signing key created only by out-of-process provisioner; existing name is not overwritten |
| Key properties | Algorithm, length, usage, export policy and provider security-descriptor support queried and checked |
| Key DACL | Exact owner/DACL read back and compared; inherited/broad ACEs rejected; provider-specific access masks experimentally validated without assuming file-object rights |
| CNG call context | NCryptOpenKey and NCryptSignHash execute only on the dedicated KeyOpsWorker; real SCM startup deadline and no-deadlock test passes |
| Service private operation | Actual service process signs fixed internal challenge and external verifier validates it |
| Non-exportability | Private export fails even for the service identity; public export succeeds |
| Client denial | Normal user, second same-user process, DevAgent broker and Low-IL AppContainer child cannot open/use private key |
| Tampering | Wrong service SID, wrong account, wrong key ID, changed DACL, export-policy mismatch, missing key and replaced key all prevent SERVICE_RUNNING |
| No silent recovery | Existing/missing/mismatched key never triggers automatic create/overwrite |
| Lifecycle | Rotation rehearsal, key-loss quarantine, uninstall-preservation and rollback tests |
| Regression | Exact-head Windows combined suite plus independent artifact verification |

Acceptance requires raw token/SID evidence, actual key provider properties, exact key security descriptor, successful fixed-challenge public verification, negative private-export/open tests, executable/config hashes, exact tested source SHA and the complete Windows transcript.

A single-user happy-path signing test is not sufficient. R5.2 cannot pass if the service identity or key DACL was inferred from configuration rather than inspected from the real running process/key.

---

# 2. R5.3 - Authenticated local named-pipe IPC

## 2.1 Security objective

Connect the already-existing R5.0 typed protocol to the actual R5.1/R5.2 service through a local Windows named pipe.

R5.3 implements the real transport, operating-system client authentication, immutable per-request principal binding, bounded framing, bounded I/O, authorization dispatch, cancellation and shutdown. It does not add transaction execution or a generic privileged-operation surface.

The pipe DACL is defense in depth only. The service must assume that any process running as an allowlisted interactive user may connect, including a malicious process running as the same user. Client process ID or executable path is not proof of trusted client code.

## 2.2 Endpoint and server security descriptor

Use one versioned local endpoint:

`\\.\pipe\Sharnou.DevAgentAuthority.v1`

Create the pipe with a non-NULL, explicitly built SECURITY_ATTRIBUTES/security descriptor. The default named-pipe DACL is prohibited because Microsoft's documented default grants read access to Everyone and Anonymous.

The protected DACL contains only:

- SYSTEM: service/maintenance control.
- The service SID: server-side pipe creation and required server access.
- Explicitly provisioned client user SID(s) or a dedicated administrator-managed client group: only the client read/write rights required to connect and exchange messages.

Do not grant FILE_CREATE_PIPE_INSTANCE to clients. Do not grant Everyone, Authenticated Users, Interactive Users, Anonymous, or broad local-user groups. Add explicit deny rules for ANONYMOUS LOGON and NETWORK as defense in depth.

The server must also set `PIPE_REJECT_REMOTE_CLIENTS`; DACL rules alone are not the remote-client control. The initial server instance must use `FILE_FLAG_FIRST_PIPE_INSTANCE` so a pre-created pipe with the same name is detected as a startup failure instead of being silently trusted.

The server must verify the created pipe's security descriptor with GetSecurityInfo and compare the actual DACL to the expected descriptor before accepting clients. A NULL descriptor, missing service SID ACE, broad allow ACE, unexpected deny/allow ACE ordering, or unexpected inherited ACE is fatal.

The allowed client principal list is maintained in protected machine configuration, provisioned by an administrator. It is a list of SIDs, not usernames, display names, process names, or client-supplied identities. No implicit `Authenticated Users` fallback is permitted.

## 2.3 Pipe modes and bounded I/O

Use CreateNamedPipeW with these properties:

| Setting | Required behavior |
|---|---|
| Access | Duplex |
| I/O | FILE_FLAG_OVERLAPPED |
| Instance count | 1 initially; concurrency increases require a separate measured gate |
| Pipe type | PIPE_TYPE_MESSAGE |
| Server read mode | PIPE_READMODE_MESSAGE |
| Wait mode | PIPE_WAIT with overlapped I/O and explicit deadlines |
| Remote mode | PIPE_REJECT_REMOTE_CLIENTS |
| First instance | FILE_FLAG_FIRST_PIPE_INSTANCE on the initial creation |
| Default security | Never NULL; explicit protected DACL |

Do not use PIPE_NOWAIT as a substitute for asynchronous I/O. Use overlapped operations with dedicated events, deadlines, CancelIoEx, and completion draining before a buffer or OVERLAPPED structure is reused.

For protocol v1, the complete request is one pipe message containing the existing 40-byte header plus the declared payload. The maximum message is exactly 16,424 bytes (40 + 16,384). Use a fixed-capacity receive buffer of that size; do not allocate memory based on the untrusted payload length. If ReadFile reports ERROR_MORE_DATA at the maximum capacity, reject and disconnect the client. The R5.0 parser then validates the complete frame length, magic, version, opcode, flags, request ID, payload length, status and operation-specific payload.

The wire protocol remains R5.0 protocol v1:

- 40-byte little-endian header.
- `SHARIPC1` magic.
- Version 1.
- Existing operation IDs and payload schemas.
- 16 KiB payload maximum.
- Exact frame length; no trailing bytes.
- No native-structure reinterpretation of an untrusted byte buffer.

Do not silently change field offsets, endianness, opcodes, or payload meanings. Any incompatible change requires a new protocol version and a separately qualified parser.

Initial bounded resource policy:

- One live client instance.
- One request dispatcher; no unbounded thread-per-client behavior.
- One fixed receive buffer and one fixed response buffer.
- Maximum 64 requests per connection.
- 30-second idle connection lifetime.
- 5-second read and write operation deadlines.
- A bounded connect/shutdown wait controlled by the SCM stop event.
- Close/disconnect after framing violation, authorization failure, timeout, or partial-response failure.

These constants are initial qualification values, not claims of optimal throughput. They may be changed only with explicit load/DoS evidence and a new exact-head test. Stopping the service must cancel pending ConnectNamedPipe/ReadFile/WriteFile operations, wait for their completion, disconnect and close the pipe, and only then report SERVICE_STOPPED.

## 2.4 Windows client authentication

Authenticate the peer using the named-pipe connection and Windows access token, not a custom password, caller-supplied SID, bearer token stored in a file, or trust in the PID.

For each complete message:

1. Read the bounded message.
2. Call ImpersonateNamedPipeClient and check its return value.
3. If impersonation fails, execute no request and close the connection.
4. Open the thread token for query only.
5. Read TokenUser, TokenGroups, TokenStatistics (AuthenticationId), TokenSessionId, TokenIntegrityLevel, and TokenIsAppContainer.
6. Obtain GetNamedPipeClientProcessId and GetNamedPipeClientSessionId for correlation and diagnostics.
7. Build an immutable authenticated-principal context.
8. Call RevertToSelf in a finally-equivalent cleanup path.
9. If revert fails, do not dispatch or reuse the worker thread; enter a fatal fail-closed state and stop the service.
10. Only after successful revert may service-owned privileged dispatch occur.

Use the least impersonation level sufficient to inspect the caller token (SecurityIdentification). Do not use the impersonated client token to perform service-owned privileged filesystem, key, profile, ACL, or process operations.

### Immutable AuthenticatedClientContext

The service-created context contains:

- Authenticated TokenUser SID.
- Authenticated logon SID.
- TokenStatistics AuthenticationId (LUID).
- TokenSessionId.
- TokenIntegrityLevel.
- TokenIsAppContainer.
- Named-pipe client PID and session ID.
- Connection generation/identifier.
- Request ID and exact frame digest.

No field is copied from the request payload. The dispatcher receives this context explicitly alongside the parsed request; it must not read an ambient global client identity.

The initial authorization policy must reject anonymous/network identities, unapproved user SIDs, AppContainer children, invalid logon/session bindings and missing token data. A standard interactive user must be able to use the client without elevation. The exact allowlisted user SID is provisioned in protected machine policy.

The PID and image path are diagnostic/correlation attributes only. Do not treat a PID, executable name, path, or unsigned image hash as proof that a request came from the trusted DevAgent binary. The approved security boundary assumes same-user processes can connect; the service therefore must validate every operation semantically and must not become a confused deputy.

## 2.5 Authorization binding to each operation

Every dispatch call is a function of both the immutable authenticated principal and the parsed typed request:

`AuthorizeRequest(AuthenticatedClientContext, ParsedRequest, ServiceOwnedState)`

The implementation must enforce operation-specific rules:

| Operation | Authorization binding |
|---|---|
| RegisterWorkspace | Authenticated user must be allowed to register the selected workspace under service policy. The service opens and identifies the workspace itself. |
| BeginExecution | Authenticated user SID must own/ be authorized for the registered workspace; WorkspaceId and ToolId must resolve in service-owned policy. |
| LaunchBoundChild | Authenticated principal must own the service-created ExecutionId and the service-owned execution must be in a launchable state. |
| CancelExecution | Principal must own the execution; service terminates only its own Job Object. Caller-supplied PID/handle is never accepted. |
| QueryExecution | Principal must own or be explicitly authorized to observe the execution; return only bounded status. |

The service creates WorkspaceId, ExecutionId, AppContainer profile names, Job Objects and all authoritative object identities. Client-provided SID, path identity, PID, descriptor, profile name, status, completion claim or policy version never overrides service-owned state.

R5.3 builds the real transport and authorization dispatcher. Business operations that are not implemented until R5.5 must return an explicit stable NOT_SUPPORTED result with no side effect. This is not a successful mock operation. Do not simulate workspace registration, execution, signing, cancellation, profile deletion or cleanup in the pipe layer.

No request operation may sign arbitrary data, ask for a MAC, export/delete the key, restore an arbitrary security descriptor, delete an arbitrary profile, launch an arbitrary command, pass through an arbitrary executable path, or claim that cleanup has completed.

## 2.6 Request IDs, replay and idempotency boundary

The existing 128-bit RequestId must be non-empty and unique within the connection. Maintain a bounded per-connection request-ID cache:

- A repeated ID with a different frame digest is a protocol violation; disconnect.
- A repeated ID for a mutating request must not execute the operation a second time.
- A read-only duplicate may return the exact cached response if the response is still in the bounded cache.
- Cache eviction and connection reset must be explicit and tested.

R5.3 does not claim durable replay protection across service restarts. Durable idempotency and transaction replay protection belong to R5.4's service-owned journal and R5.5 state machine. Do not claim the in-memory connection cache closes that later requirement.

## 2.7 Error and shutdown behavior

- Malformed frame: close connection; no dispatch.
- Unsupported protocol version/opcode: typed protocol error; no dispatch.
- Payload length mismatch/trailing bytes: close connection; no dispatch.
- Impersonation failure: no dispatch.
- RevertToSelf failure: fatal service fail-closed path.
- Unauthorized principal: deny and close or return a minimal denial without disclosing protected object state.
- Slow/partial client: bounded timeout and disconnect.
- Oversized message/flood: bounded buffer, immediate disconnect, rate-limited audit.
- Client disconnect during request: cancel pending I/O and release connection resources; no implicit transaction success.
- Service STOP/SHUTDOWN: stop accepting, cancel pending I/O, wait for outstanding operation/worker completion, disconnect and close all handles, then report SERVICE_STOPPED.

Never run privileged operations while impersonating the client. Never dispatch after an authentication, timeout, parse, or revert failure.

## 2.8 R5.3 Windows acceptance matrix

| Category | Required tests |
|---|---|
| Real endpoint | Client connects to the service's actual CreateNamedPipeW endpoint; no test-only server |
| Pipe DACL | Read back exact protected DACL; broad/default/inherited ACEs rejected |
| Hijack | Pre-create same pipe name; service must fail FILE_FLAG_FIRST_PIPE_INSTANCE startup |
| Remote access | Attempt a real remote connection from a separate Windows host; verify PIPE_REJECT_REMOTE_CLIENTS rejects it |
| Allowed client | Explicit standard-user SID succeeds without elevation |
| Unauthorized client | Different local user, anonymous/network identity and unapproved SID are rejected |
| Same-user threat | Second same-user process can connect if policy allows the user but cannot invoke an unapproved operation or obtain arbitrary signing/cleanup authority |
| Sandbox isolation | Low-IL AppContainer child cannot connect or access the machine key |
| Token binding | Validate user SID, logon SID, AuthenticationId, session ID, integrity and AppContainer flag against the actual client token |
| Impersonation | ImpersonateNamedPipeClient failure leads to zero dispatch; RevertToSelf is always observed and required |
| Framing | Valid v1 frame; short header; invalid magic/version/opcode; flags/status nonzero; empty ID; too-small/too-large payload; truncation; trailing byte; malformed UTF-16; wrong schema |
| Message boundaries | Split/fragmented writes, ERROR_MORE_DATA, multiple frames, client write after disconnect, partial response |
| Resource bounds | Maximum frame, maximum requests, connection idle timeout, read/write timeout, slowloris, oversized flood and bounded memory |
| Replay | Same request ID same digest; same ID different digest; duplicate mutating request; cache full/eviction |
| Shutdown | Stop during ConnectNamedPipe, ReadFile, WriteFile and idle wait; all I/O cancelled/drained and handles closed |
| Restart | Stop/start service, stale client reconnect, service pipe recreated with exact DACL |
| Regression | Exact-head Windows combined suite, frozen M1-M6, exact PE imports and evidence artifact |

Remote-client rejection is not accepted based only on a same-process loopback test. It requires an actual second-host attempt or must remain explicitly NOT QUALIFIED.

The artifact must include the exact source SHA, generated service executable SHA-256, actual import table, actual pipe DACL, server process/service SID token evidence, client token evidence for each principal class, raw frame transcripts, negative-test matrix, resource/time bounds, SCM state transitions and complete combined regression logs.

---

# 3. Risks, failure modes and explicit non-goals

| Risk | Required control |
|---|---|
| Service SID configured but absent from actual token | Inspect TokenGroups and TokenRestrictedSids from the real service process; otherwise do not start |
| Restricted token cannot access CNG key | Use the exact service SID ACE; test with the real restricted process token; never broaden to all users |
| Key generated under the wrong identity/scope | Independent provider/property/key-DACL read-back; fail on mismatch |
| Key silently replaced after loss | No auto-create/overwrite at startup; quarantine and require operator recovery |
| Key exposed through a signing oracle | No generic crypto IPC; private operation accepts only validated service-owned journal objects |
| Service image replacement | Protected installation path/service configuration ACL and independent image hash/final-file validation |
| Pipe default DACL exposes endpoint | Explicit protected DACL and actual DACL read-back |
| Remote named-pipe access | PIPE_REJECT_REMOTE_CLIENTS plus NETWORK denial and an actual remote-host test |
| PID spoofing/reuse or false executable identity | Use OS token identity for authorization; PID/image are diagnostic only |
| Failed impersonation falls back to service identity | No dispatch on impersonation failure; check RevertToSelf and fail closed |
| Slow client exhausts service | One bounded instance initially, overlapped I/O, fixed buffers, deadlines and cancellation |
| Duplicate request executes twice | Per-connection ID/digest cache in R5.3; durable idempotency/state in R5.4/R5.5 |
| Same-user confused deputy | Operation-specific authorization over service-owned resources; no arbitrary signing or caller-controlled cleanup |

Explicitly out of scope for R5.2/R5.3:

- Production journal creation/signing or recovery (R5.4+).
- Workspace ACL mutation, AppContainer profile lifecycle and Job Object transactions (R5.5+).
- Crash recovery/concurrency/orphan cleanup (R5.6).
- Arbitrary process execution, command strings, raw executable paths or model-facing tools.
- Autonomous or model-facing execution.
- Production installation rollout, signing/release, or unattended key recovery.

## 4. Milestone acceptance gates

R5.2 is accepted only after R5.1.c/.d are accepted and all actual service-token, key-property, key-DACL, private-operation and negative-access tests pass on the exact source head.

R5.3 is accepted only after R5.2 is accepted and the actual service hosts the real pipe endpoint; client identity is captured from Windows tokens; every request is bound to that identity; bounded framing, timeout, cancellation, remote rejection and shutdown are verified.

No source-level declaration, PowerShell parser fixture, intended ACL, expected import list, or successful mock connection counts as runtime evidence. The generated executable, running service token, actual CNG provider object, actual key security descriptor, actual pipe security descriptor and raw Windows test results determine acceptance.

Model-facing process execution remains DISABLED. Autonomous execution remains DISABLED. Phase 2B.8 remains NOT SECURITY ACCEPTED.

---

## 5. Microsoft platform references

- [SERVICE_SID_INFO](https://learn.microsoft.com/en-us/windows/win32/api/winsvc/ns-winsvc-service_sid_info)
- [NCryptCreatePersistedKey](https://learn.microsoft.com/en-us/windows/win32/api/ncrypt/nf-ncrypt-ncryptcreatepersistedkey)
- [NCryptOpenKey](https://learn.microsoft.com/en-us/windows/win32/api/ncrypt/nf-ncrypt-ncryptopenkey)
- [NCryptSignHash](https://learn.microsoft.com/en-us/windows/win32/api/ncrypt/nf-ncrypt-ncryptsignhash)
- [Key Storage Property Identifiers](https://learn.microsoft.com/en-us/windows/win32/seccng/key-storage-property-identifiers)
- [NCryptSetProperty](https://learn.microsoft.com/en-us/windows/win32/api/ncrypt/nf-ncrypt-ncryptsetproperty)
- [NCryptSetProperty](https://learn.microsoft.com/en-us/windows/win32/api/ncrypt/nf-ncrypt-ncryptsetproperty)
- [NCryptGetProperty](https://learn.microsoft.com/en-us/windows/win32/api/ncrypt/nf-ncrypt-ncryptgetproperty)
- [Named Pipe Security and Access Rights](https://learn.microsoft.com/en-us/windows/win32/ipc/named-pipe-security-and-access-rights)
- [CreateNamedPipeW](https://learn.microsoft.com/en-us/windows/win32/api/namedpipeapi/nf-namedpipeapi-createnamedpipew)
- [ImpersonateNamedPipeClient](https://learn.microsoft.com/en-us/windows/win32/api/namedpipeapi/nf-namedpipeapi-impersonatenamedpipeclient)
- [GetNamedPipeClientProcessId](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-getnamedpipeclientprocessid)
- [GetNamedPipeClientSessionId](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-getnamedpipeclientsessionid)
- [Named Pipe Type, Read, and Wait Modes](https://learn.microsoft.com/en-us/windows/win32/ipc/named-pipe-type-read-and-wait-modes)
