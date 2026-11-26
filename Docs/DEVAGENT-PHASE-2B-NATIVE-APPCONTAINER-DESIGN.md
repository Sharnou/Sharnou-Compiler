# DevAgent Phase 2B - Native AppContainer Process Boundary

Status: DESIGN / PRODUCTION BROKER INTEGRATION NOT IMPLEMENTED. Phase 2B.2 now has a Windows-CI-validated test-only AppContainer fixture. This document does not authorize model-facing process execution and the fixture is not a production sandbox.

Target: Windows x64, Sharnou-generated PE32+, Windows PowerShell 5.1 test host.
Prerequisite: Phase 2A workspace transaction prototype, Windows adversarial suite 44/44.
Security posture: DevAgent process execution remains disabled for model-generated plans.

## 1. Findings from the current candidate

The current native emitter in `Stage0/SharnouCompiler.ps1` still calls `CreateProcessA` with the caller's token, inherited environment, no STARTUPINFOEX attribute list, and no bounded output channel. It only applies Job Object limits after creating the child suspended. The Phase 2A PowerShell workspace manager is a separate prototype and is not called by the native emitter.

The Phase 2A implementation currently grants FullControl to the execution SID. That is too broad for the intended native boundary. Before integration, replace this with operation-specific rights: the child receives only the minimum Modify/Create/Write rights needed inside its per-execution scratch workspace, and read-only access to immutable inputs. It must not receive rights to the journal root, broker image, compiler source, tool manifest, or shared workspace parent.

A string matching the AppContainer SID namespace (S-1-15-2-...) is not proof that Windows created an AppContainer profile or process. Only the SID returned by the documented profile API and verified against the created process token is acceptable.

## 2. Supported AppContainer launch mechanism

Use the documented Windows process-attribute route:

1. Create a unique per-execution profile with `CreateAppContainerProfile`. Use a bounded compiler-owned profile moniker containing a fixed product prefix and cryptographically random execution identifier. Never accept a profile name or SID from model output.
2. Retain the returned package SID and validate it as a real SID. Do not synthesize or accept a string-only SID. A unique profile-name collision returning HRESULT_FROM_WIN32(ERROR_ALREADY_EXISTS) fails closed; this execution does not adopt or delete that profile.
3. Construct `SECURITY_CAPABILITIES` with that package SID and an empty capability list. No network, filesystem, device, location, microphone, camera, or other capability is granted by default.
4. Build `STARTUPINFOEXW` and a process attribute list. Add `PROC_THREAD_ATTRIBUTE_SECURITY_CAPABILITIES` using `UpdateProcThreadAttribute`. Use the correct attribute-list size probe / allocation / initialization / deletion lifecycle.
5. Launch the absolute System32 PowerShell image with `CreateProcessW`, a writable per-call wide-character command-line buffer copied from an immutable compiler-owned argument template, `EXTENDED_STARTUPINFO_PRESENT | CREATE_SUSPENDED | CREATE_UNICODE_ENVIRONMENT`, and an explicitly constructed clean environment block. `CreateProcessW` may modify the command-line buffer in place. Do not search PATH and do not inherit the caller environment.
6. Keep the child suspended. Assign it to the already-configured Job Object. If any operation fails, terminate the child/job and close all acquired handles before returning.
7. Verify the actual process token before resume: `TokenIsAppContainer == TRUE`, `TokenAppContainerSid` exactly equals the profile SID, and the integrity level is no higher than the configured low-integrity policy. Any mismatch is fatal.
8. Resume only after the AppContainer identity, workspace ACL, Job Object, handle list, and process policy have all been verified.

The AppContainer security-capabilities process attribute is the documented mechanism that causes Windows to create the child as an AppContainer process. Do not infer this from the SID prefix or from successful process creation alone.

## 3. Restricted-token decision - separate acceptance gate

Do not casually combine `CreateRestrictedToken` and the AppContainer attribute in the raw emitter. The documented AppContainer launch path uses `SECURITY_CAPABILITIES` in `STARTUPINFOEX`; a separate restricted primary-token path introduces token access rights, token-type/assignability constraints, and `CreateProcessAsUserW` privilege requirements.

Phase 2B must first implement and prove the AppContainer process boundary using the documented attribute path. A second, isolated experiment must determine whether an additional restricted primary token can be composed with that path on the supported Windows runner without requiring privilege elevation. The experiment must record exact API return values, last-error/HRESULT values, token information before and after, and process-token verification. If composition requires privileges unavailable to the broker, do not add privilege enabling or elevation; retain the AppContainer-only boundary and mark the separate restricted-token gate blocked pending a supported design.

No silent fallback to the caller token is allowed under any failure condition.

## 4. Per-execution workspace ACL binding

The workspace transaction must be bound to the genuine package SID returned by Windows, not to a caller-provided SID string.

Required order:

1. Acquire the execution lease and write a durable PREPARING record.
2. Create the per-execution directory beneath the pre-provisioned protected workspace root.
3. Capture and durably journal the exact original owner/group/DACL before mutation.
4. Apply a protected DACL granting the supervisor and SYSTEM the required administrative rights, and the package SID only the minimum required rights on the execution directory and its descendants. Do not grant the package SID FullControl.
5. Read back and verify the effective DACL and inheritance state before process creation.
6. Create the AppContainer child suspended and verify its token SID.
7. Only then resume the child.
8. On normal exit, timeout, crash recovery, or broker shutdown, terminate/wait for the complete Job Object before restoring the exact original security descriptor.
9. Verify owner/group/DACL equality after restoration, persist RESTORED, then remove the workspace and profile-owned artifacts only after all handles/processes are closed.

The journal directory remains inaccessible to the child. The child must never be able to modify its own journal, change the workspace DACL, change ownership, or create sibling execution directories.

## 5. Native API and structure inventory

The emitter/import-table work must account for these APIs (DLL ownership must be verified against the Windows SDK import libraries and actual runner):

- USERENV.dll: `CreateAppContainerProfile`, `DeleteAppContainerProfile` (only for a profile created and owned by this execution).
- KERNEL32.dll: `InitializeProcThreadAttributeList`, `UpdateProcThreadAttribute`, `DeleteProcThreadAttributeList`, `CreateProcessW`, `GetCurrentProcess`, `OpenProcessToken`, `GetProcessId`, `ResumeThread`, `TerminateProcess`, `CloseHandle`, `WaitForSingleObject`, `GetExitCodeProcess`, `GetLastError`, `HeapAlloc`, `HeapFree`, `GetEnvironmentStringsW` only if needed for safe filtering (prefer a constructed allowlist block).
- ADVAPI32.dll: `OpenProcessToken`, `GetTokenInformation`, `SetSecurityInfo` / `GetSecurityInfo` or the selected documented ACL API, and token APIs only in the separately gated restricted-token experiment.
- Structures/constants requiring explicit x64 layout assertions: `STARTUPINFOEXW`, `STARTUPINFOW`, `PROCESS_INFORMATION`, `SECURITY_CAPABILITIES`, `SID_AND_ATTRIBUTES`, `JOBOBJECT_EXTENDED_LIMIT_INFORMATION`, `TOKEN_MANDATORY_LABEL`, and the selected token information buffers.

Avoid duplicate import entries for APIs already present in the PE import table. The existing import table builder deduplicates by API name; new DLL ownership and IAT RVAs must still be audited. Do not hard-code guessed structure offsets without independent x64 layout tests.

## 6. Output capture and inherited-handle contract

AppContainer integration does not complete the broker by itself. Before any model-facing enablement:

- Keep `bInheritHandles=FALSE` when no child handles are required.
- When `PROC_THREAD_ATTRIBUTE_HANDLE_LIST` is supplied, `CreateProcessW` MUST receive `bInheritHandles=TRUE`; Microsoft documents this as a requirement. Every listed handle must be inheritable. The allowlist must contain only child-side stdout/stderr write handles; parent read handles and unrelated handles must remain non-inheritable. Never combine the handle-list attribute with `bInheritHandles=FALSE`.
- Set `STARTF_USESTDHANDLES` in `STARTUPINFOEXW.StartupInfo.dwFlags` and bind stdout/stderr to the approved pipe handles.
- Drain both streams concurrently while the child runs; enforce a combined hard byte cap and terminate the whole job on overflow.
- Never buffer unbounded output in memory, write child output to an untrusted path, or interpret output as instructions.
- Close the attribute list and every pipe/process/thread/job/token/SID/profile handle/resource on every success and failure path.

## 7. Required Windows adversarial acceptance tests

The new native test suite must prove all of the following on Windows Server 2025 x64 and the supported Windows 10/11 targets:

1. A real profile is created; the returned SID is valid; the child token reports AppContainer and the exact same SID.
2. A SID-shaped string without a profile cannot satisfy the process-token assertion.
3. The child has zero capabilities and cannot access network resources.
4. The child cannot read/write the journal, broker image, compiler source, manifest, shared workspace parent, or another execution's directory.
5. The child can perform only the explicitly required reads/writes in its own scratch workspace.
6. The workspace ACL contains no package FullControl ACE, no inherited broad ACE, and no unexpected principal.
7. Failure injection at profile creation, SID validation, ACL mutation, attribute-list initialization/update, process creation, token verification, job assignment, and resume leaves no live child and restores the exact original ACL.
8. A profile is deleted only if this execution created it and all processes/handles are closed. A pre-existing profile is never deleted.
9. Handle inheritance contains only the approved pipe handles; unrelated inheritable handles are not visible to the child.
10. Output flooding terminates the Job Object at the combined byte cap; simultaneous stdout/stderr cannot deadlock the broker.
11. Timeout and broker termination kill descendants and leave recoverable journal state.
12. No code path resumes or reports success after any security check fails.

Each test must include positive controls and negative controls. Record Windows build, architecture, PowerShell version, compiler commit, test binary SHA-256, and exact test totals. A test that merely checks import names, SID string format, or generated bytes is not runtime proof.

## 8. Implementation sequence and stop conditions

- 2B.1: Native API/ABI inventory, import-table map, x64 structure-layout fixtures, and fail-closed token-verification test design.
- 2B.2: Native profile lifecycle and AppContainer attribute construction, initially in a test-only fixture that cannot execute arbitrary tools.
- 2B.3: Native workspace ACL binding using the genuine package SID, with least-privilege rights and crash rollback.
- 2B.4: Suspended process creation, Job Object assignment, token verification, then resume.
- 2B.5: STARTUPINFOEX handle allowlist and bounded dual-stream output capture.
- 2B.6: Full adversarial Windows acceptance matrix and independent regression runs.

Stop immediately if the required USERENV/ADVAPI32 imports or Windows SDK declarations are unavailable, if the generated PE import table is ambiguous, if token verification cannot be performed, if ACL rollback is not exact, or if any test indicates unrestricted-token fallback. Do not add a local compiler dependency, do not invoke MSVC/LLVM/MinGW/CMake/MSBuild, and do not generate placeholder executables or claim a sandbox from static validation.

## 9. Microsoft references

- Launch an AppContainer: https://learn.microsoft.com/en-us/windows/win32/secauthz/implementing-an-appcontainer
- CreateAppContainerProfile: https://learn.microsoft.com/windows/win32/api/userenv/nf-userenv-createappcontainerprofile
- SECURITY_CAPABILITIES: https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-security_capabilities
- UpdateProcThreadAttribute: https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-updateprocthreadattribute
- Restricted Tokens: https://learn.microsoft.com/en-us/windows/win32/secauthz/restricted-tokens
- CreateRestrictedToken: https://learn.microsoft.com/en-us/windows/win32/api/securitybaseapi/nf-securitybaseapi-createrestrictedtoken


## 10. Phase 2B.1 - native API and x64 ABI contract

Status: PHASE 2B.1 CONTRACT VALIDATED ON WINDOWS. GitHub Actions run 45909933391 passed on code commit af28b73cb04dd51e3f9e5477c3b63def27ece60b using Windows Server 2025 / Windows SDK 10.0.26100.0. No native imports or process-creation emitter instructions have been added in this phase.

Candidate artifacts:
- `Tests/DevAgentBroker/native-abi-manifest.json`: observed import-table groups, planned Win32 API-to-DLL map, API signatures, token information class IDs, process-attribute constants, and x64 structure field/offset/size expectations.
- `Tests/Test-DevAgentNativeAbi.ps1`: compares the manifest to the compiler's actual existing import descriptor and IAT maps; checks planned API declarations and structure field order against the installed Windows SDK; computes expected x64 layouts using pointer size 8 and default packing 8.
- `.github/workflows/devagent-native-abi-contract.yml`: Windows x64 SDK contract workflow.

Evidence boundary: this phase checks consistency of the ABI model against the installed SDK declarations and the compiler's current import map. It does not perform native `sizeof`/`offsetof` execution, does not compile C/C++, does not create a PE, does not modify the compiler's PE import table, and does not create a process or AppContainer. Phase 2B.2 must add a native runtime layout probe or an equally authoritative native ABI measurement before any emitter consumes these offsets.

Two correctness constraints were elevated into the contract:
1. `CreateProcessW` may modify its command-line buffer. The broker must pass a writable per-call buffer copied from a compiler-owned immutable argument template; read-only storage is unsafe.
2. If `PROC_THREAD_ATTRIBUTE_HANDLE_LIST` is supplied, `CreateProcessW` requires `bInheritHandles=TRUE`. This is not compatible with the current no-inheritance setting. The future output-capture implementation must explicitly create inheritable child write handles, keep all other handles non-inheritable, and pass an exact handle list. With no inherited handles, keep `bInheritHandles=FALSE`.

Windows token verification contract:
- `TokenIsAppContainer` is class 29 and must return DWORD 1.
- `TokenAppContainerSid` is class 31 and returns `TOKEN_APPCONTAINER_INFORMATION`; its non-null SID must be valid and equal to the SID returned for this execution's newly created profile.
- `TokenIntegrityLevel` is class 25 and must be no higher than `SECURITY_MANDATORY_LOW_RID` (0x1000).
- Open the child process token with `OpenProcessToken(processHandle, TOKEN_QUERY)`; the process handle must support `PROCESS_QUERY_LIMITED_INFORMATION`.
- Do not call `FreeSid` on the SID pointer contained in a `GetTokenInformation` result buffer. Only free the profile SID allocation returned by `CreateAppContainerProfile`.

Profile ownership contract:
- `CreateAppContainerProfile` returning `S_OK` is the only path that establishes profile ownership for this execution.
- `HRESULT_FROM_WIN32(ERROR_ALREADY_EXISTS)` is not ownership. This execution must fail closed, must not silently adopt the profile, and must never delete it.
- The returned profile SID is allocated by the API and must be released with `FreeSid` after its final use.

Attribute-list initialization contract:
- Call `InitializeProcThreadAttributeList` once with a NULL list to obtain the required size. The expected first result is failure with `GetLastError()==ERROR_INSUFFICIENT_BUFFER`; an unexpected error is a hard failure.
- Bound the returned size, allocate from `GetProcessHeap`, initialize the list, add each required attribute using `UpdateProcThreadAttribute`, and call `DeleteProcThreadAttributeList` only after successful initialization. Release the allocation with `HeapFree` on every path.
- `STARTUPINFOEXW.StartupInfo.cb` must equal `sizeof(STARTUPINFOEXW)` (112 bytes on x64), not `sizeof(STARTUPINFOW)` (104 bytes).
- `SECURITY_CAPABILITIES` must reference the real package SID and use `Capabilities=NULL`, `CapabilityCount=0`, `Reserved=0` unless a reviewed capability is separately approved.

Source references:
- AppContainer launch: https://learn.microsoft.com/en-us/windows/win32/secauthz/implementing-an-appcontainer
- CreateAppContainerProfile ownership and result semantics: https://learn.microsoft.com/en-us/windows/win32/api/userenv/nf-userenv-createappcontainerprofile
- STARTUPINFOEXW layout: https://learn.microsoft.com/en-us/windows/win32/api/winbase/ns-winbase-startupinfoexw
- Attribute-list sizing/initialization: https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-initializeprocthreadattributelist
- Handle-list inheritance requirement: https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-updateprocthreadattribute
- Writable CreateProcessW command line: https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw
- Token information and AppContainer SID: https://learn.microsoft.com/en-us/windows/win32/api/securitybaseapi/nf-securitybaseapi-gettokeninformation


Windows Phase 2B.1 contract evidence (2026-11-26): run 45909475426 completed successfully. The runner checked 53 x64 structure fields across 10 aggregate structures, all 12 existing PE import groups, all 44 existing IAT entries, all 17 planned API declarations including declared return types and ordered parameter-type sequences, and three token-information class values. The test checked the actual installed Windows SDK headers and calculated the ABI layouts under the Windows x64 pointer-size-8 / default-pack-8 model. It explicitly did not compile a native probe, execute sizeof/offsetof code, create a PE, or launch a process. The SDK uses conditional-compilation arms inside SECURITY_CAPABILITIES; the test validates each member declaration and models the field layout separately rather than comparing mutually exclusive preprocessor branches as if they were one sequential C declaration.


The ABI contract test was strengthened after initial Windows failures: it now compares the ordered parameter-type tokens and declared return type for each planned API against the correct SDK header, in addition to checking the import-group DLL mapping and declaration presence. The final Windows run 45909933391 passed all these checks. The 17 API declarations are a future import manifest only; they have not been inserted into the PE import table or compiler emitter in Phase 2B.1.


## 11. Phase 2B.2 - runtime x64 interop probe and test-only AppContainer fixture

Status: WINDOWS CI PASS for the isolated test fixture on commit `7804e3663cdd6325a39b61204e4e526b7bb0c0a5`. Workflow: [run 45912115900](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45912115900). Runner: Microsoft Windows Server 2025, OS version 10.0.26100.0, 64-bit Windows PowerShell 5.1.26100.33822.

Implemented files:
- `Tests/DevAgentBroker/NativeInterop.ps1`: test-only in-memory Reflection.Emit support for explicit P/Invoke signatures, runtime struct layout types, unmanaged allocations, and explicit CLR marshaller overload selection.
- `Tests/DevAgentBroker/native-abi-manifest.json`: adds the 18 explicitly reviewed test-fixture API declarations and the test execution/evidence boundary.
- `Tests/Test-DevAgentNativeAbiRuntime.ps1`: performs runtime `Marshal.SizeOf(Type)` and `Marshal.OffsetOf(Type,String)` checks for all 10 manifested x64 structures and 53 field offsets.
- `Tests/Test-DevAgentAppContainerFixture.ps1`: creates a uniquely named AppContainer profile, tests profile collision, builds a process attribute list, supplies a zero-capability `SECURITY_CAPABILITIES` structure, launches only the absolute System32 `whoami.exe` image suspended, reads the real process token, and terminates the child without resuming its primary thread.
- `.github/workflows/devagent-native-appcontainer-fixture.yml`: executes the two fixtures on `windows-2025`.

Runtime ABI result:
- 64-bit pointers: 8 bytes.
- Structure sizes: 10/10 matched.
- Member offsets: 53/53 matched.
- Critical layouts measured at runtime: `SECURITY_CAPABILITIES=24`, `STARTUPINFOEXW=112`, `PROCESS_INFORMATION=24`.
- This measurement is performed by the .NET Framework CLR unmanaged interop marshaler at runtime. It is an independent runtime layout measurement, **not** a native Sharnou compiler `sizeof`/`offsetof` executable and not a C/C++ helper build.

AppContainer fixture result: **11 assertions passed**.
- 18 native P/Invoke entrypoints were bound in memory without `Add-Type`, a C# compiler, or an external toolchain.
- `CreateAppContainerProfile` returned a valid OS-generated package SID.
- A second create with the same profile name returned `HRESULT_FROM_WIN32(ERROR_ALREADY_EXISTS)`; the duplicate path did not acquire ownership.
- `InitializeProcThreadAttributeList` size query and initialization succeeded (48-byte runtime size on this runner).
- `PROC_THREAD_ATTRIBUTE_SECURITY_CAPABILITIES` accepted the 24-byte structure with the exact returned SID and zero capability entries.
- `CreateProcessW` created a fixed System32 `whoami.exe` child with `EXTENDED_STARTUPINFO_PRESENT | CREATE_SUSPENDED | CREATE_UNICODE_ENVIRONMENT`, no inherited handles, and no user/model-selected arguments or paths.
- Before resuming the primary thread, the fixture opened the actual child token and verified `TokenIsAppContainer=1`, the package SID was valid and exactly equal to the profile SID, the integrity RID was no higher than Low (`0x1000`), and `TokenCapabilities` count was zero.
- Negative control: the ordinary PowerShell parent token reported `TokenIsAppContainer=0` and a NULL AppContainer SID.
- `GetExitCodeProcess` confirmed the child remained active while suspended; the fixture then terminated and reaped it without importing or calling `ResumeThread`.
- The execution-owned profile was deleted only after the child and all handles were closed.

Run output evidence:
- Fixed child image SHA-256: `23240EF9F8B0A9A324110B1C2331DE31DC1B0E08F5359CB707E51A939AF56CD3`.
- Profile SID from the recorded run: `S-1-15-2-2453041417-291811665-2106074910-2650472592-495154603-1960595871-3433844368`.
- AppContainer fixture source SHA-256: `407E3E820DF23716E57B9E677D2A4EF16484FBD016A1A401E3A481817B0CE436`.
- Interop helper SHA-256: `0B23042E5C6AB408D48D69A8E327F8130347720F8BCAC495879DC66BAC254949`.
- Runtime layout test SHA-256: `A9E1DEBE7CE7E0487DE9928F0B4538DDD3D4596591B363515C63951D1B1EF937`.
- Manifest SHA-256: `CE1FBE1A289CF7908D9B09EBE91E95965082CC573DA099FD75C0BDF69D3DE381`.

Fixture-only limitations and remaining gates:
- The test passes a NULL environment pointer, inheriting the workflow runner environment. This fixture never resumes the child, so user-mode code does not execute; a clean explicit environment block remains a production launch requirement and was not validated here.
- This test creates the process through an in-memory P/Invoke adapter under PowerShell, not through the Sharnou-generated PE or `Emit-DevRunTool`. No production PE import table, compiler source, or process broker emitter was modified.
- No AppContainer workspace ACL binding, restricted primary-token composition, Job Object binding for this fixture, handle-list inheritance, bounded stdout/stderr capture, or network-denial access attempt was tested here.
- A zero `TokenCapabilities` list is verified; this is not a full adversarial network/resource-access test.
- The primary thread was deliberately never resumed. This proves token establishment and pre-entry inspection, not execution of the child inside the AppContainer.
- Model-facing execution remains DISABLED. PR #18 remains draft/open/unmerged.

Phase 2B.3 must next bind the genuine profile SID to a per-execution workspace DACL using least-privilege rights, then prove exact ACL restoration and crash recovery. It must not yet enable model-facing execution.
