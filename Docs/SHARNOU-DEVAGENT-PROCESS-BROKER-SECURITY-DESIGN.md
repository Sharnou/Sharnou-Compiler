# SharnouDevAgent Native Process Broker - Security Design

Status: PHASE 1 IMPLEMENTED / SECURITY ACCEPTANCE INCOMPLETE
Owner: Sharnou Compiler
Target: Windows x64, native Sharnou-generated PE32+
Date: 2026-11-26

## Current implementation status - 2026-11-26

Status: PHASE 1 IMPLEMENTED; WINDOWS CI PASS on PR #18 head `7a15892a944c747f9563961d7c050c909dd3d3a4`. This is not yet security-accepted and must not be exposed to model-generated plans.

Validation runs: Stage 7A / combined [45772104864](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45772104864); frozen M1-M6 baseline [45772104661](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45772104661). The combined run passed Stage 7A 24/24, collection imports 2/2, stack-probe/unwind 6/6, Runtime ABI including 16-argument calls and 17-argument rejection, broker phase-1 security tests, and the integrated M1-M6 83/83 baseline.

Implemented in the dependent DevAgent broker candidate:

- Public API is typed: `sh_dev_run_tool(tool_id: Integer, timeout_ms: Integer) -> Integer`. It is registered only when the compiler is invoked with `-EnableDevAgentTools`; default compiler builds reject the capability.
- Six fixed compiler-owned tool IDs. The caller cannot supply a command string, executable path, script path, arguments, or working directory.
- A SHA-256-pinned `Tests/DevAgentBroker/tool-manifest.json`; the compiler refuses to build the broker fixture if the manifest digest differs from its embedded pin.
- Native Windows CNG SHA-256 verification is invoked for the selected script before `CreateProcessA`. The verified script handle is held open through child completion to block write/delete replacement; the final file object is opened with `FILE_FLAG_OPEN_REPARSE_POINT` and its attributes are checked via `GetFileInformationByHandle`.
- The broker resolves PowerShell from the absolute System32 path returned by `GetSystemDirectoryA`; it does not search PATH.
- The workspace root is derived from the broker image path using `GetModuleFileNameA` and a fixed `Build\\DevAgentBroker\\DevAgentBroker.exe` suffix. The broker switches its own current directory to that image-derived root, then checks fixed workspace directories and tool paths for expected types and reparse-point attributes. A Windows test launches from an unrelated temporary working directory and verifies that the broker still resolves the repository root.
- Child processes are created suspended with `bInheritHandles=FALSE`, assigned to a Job Object before resume, and subject to kill-on-job-close, active-process, process-memory, job-memory, and bounded wait-time policies.
- Runtime tests cover unknown IDs, invalid timeout, explicit opt-in, pinned-manifest tamper, native script-hash tamper, fixed tool execution, exit-code propagation, foreign-current-directory launch, directory-junction rejection, timeout, and descendant termination.

Important implementation deviations and remaining acceptance gates:

1. Native CNG script hashing is implemented and Windows-tested. The tool-manifest SHA-256 is pinned into the compiler; a modified manifest fails before PE generation and modified script bytes fail before child creation.
2. Workspace discovery is now image-relative and independent of inherited current directory. Checked directories and the opened script object reject reparse points. Full canonicalization of every ancestor, final-path resolution for the executable image, and explicit ADS/UNC/device-path rejection are NOT yet complete.
3. The child still uses the caller's token. Restricted-token, low-integrity/AppContainer, and workspace-only ACL enforcement are NOT implemented.
4. A clean environment block and explicit DLL search policy are NOT implemented; `CreateProcessA` currently inherits the caller environment.
5. Bounded stdout/stderr capture with STARTUPINFOEX handle-list isolation and a hard output cap are NOT implemented. The current phase does not claim output containment.
6. Cooperative cancellation, durable evidence journaling, restart recovery, and policy-versioned audit records are NOT implemented.

The broker remains unavailable to model-generated plans. Phase 1 is a controlled test-tool execution foundation, not a production sandbox. Do not enable autonomous process execution until every remaining gate in this document passes.

## 1. Security boundary

The process broker is the only component permitted to create operating-system processes for DevAgent. It is not a general shell and must never accept a command string, executable path, working directory, environment block, or arbitrary argument array from model output.

The only public operation planned for the Sharnou runtime is:

`sh_dev_run_tool(tool_id: Integer, timeout_ms: Integer) -> Integer`

Both values are validated. `tool_id` selects an immutable compiler-owned tool descriptor. The caller cannot supply executable names, script names, paths, flags, or environment variables. Unknown IDs fail closed. The broker is unavailable to model-generated plans until every acceptance gate in this document passes.

## 2. Immutable tool descriptors

Each approved descriptor must contain:

- Numeric tool ID and stable name.
- Exact absolute executable identity and expected executable policy.
- Exact relative script path and SHA-256 digest.
- Exact ordered argument vector; no concatenation of untrusted text.
- Canonical workspace root requirement and working directory.
- Minimum and maximum timeout; hard maximum 300,000 ms.
- Maximum output bytes; initial policy 1 MiB combined stdout/stderr.
- Maximum process count and memory limits.
- Required file read/write roots and no other filesystem grants.
- Whether network access is prohibited (default: prohibited).

Initial candidates are test-only tools: Stage 7A, Runtime ABI, stack-probe/unwind, collection import, and frozen M1-M6 baseline. The manifest is compiler-owned and cannot be extended by an agent profile or a downloaded file.

## 3. Process creation sequence

1. Validate the tool ID and timeout range before touching the OS.
2. Resolve the approved workspace root from the launched DevAgent image location, not from an agent-supplied path or inherited current directory.
3. Canonicalize the target script path and every parent component. Reject path traversal, alternate data streams, UNC paths, device paths, reparse points, and paths outside the approved workspace.
4. Verify the exact script SHA-256 using the Windows CNG SHA-256 provider before execution. Hash mismatch is a hard failure.
5. Resolve the PowerShell host by an absolute System32-derived path. Never search PATH and never invoke cmd.exe, a shell, or a user-selected executable.
6. Construct the command line from the immutable argument vector using the Windows CreateProcess quoting rules. The application name is supplied separately as an absolute path.
7. Build a clean environment block from an explicit allowlist. Do not inherit credentials, provider tokens, arbitrary PATH entries, or caller-supplied environment variables.
8. Create the child suspended. Set bInheritHandles=FALSE unless an explicit STARTUPINFOEX handle list is used for the bounded output channel.
9. Create and configure a Job Object before resuming the child. Required limits: KILL_ON_JOB_CLOSE, active-process ceiling, per-process and job memory ceilings, and a wall-clock timeout enforced by the broker.
10. Assign the suspended process to the Job Object. If assignment fails, terminate and close the process without resuming it.
11. Resume the primary thread only after all preceding checks pass.
12. Drain stdout/stderr continuously through an explicitly allowlisted pipe handle list. Count bytes; terminate the job immediately if the combined output cap is exceeded.
13. Poll completion and cancellation. On timeout, cancellation, output overflow, or broker shutdown, terminate the entire Job Object and wait for process termination.
14. Read the actual process exit code, close every process/thread/pipe/job handle, and return a typed status plus bounded captured output.
15. Append an evidence record containing tool ID, script hash, start/end time, timeout, exit status, output digest, and policy version. Never log secrets or full environment contents.

## 4. Restricted execution

The broker must not run children with the caller's unrestricted token by default. The implementation must evaluate a restricted primary token with disabled privileges and a low-integrity or AppContainer boundary. The resulting token must have only the minimum rights needed to read approved compiler inputs and write the designated Build/DevAgent staging directory.

If Windows policy or runner configuration prevents creation of the restricted token, the broker must refuse execution rather than silently fall back to the unrestricted user token.

No automatic privilege elevation, service installation, scheduled task creation, persistence, registry autorun, or security-control modification is permitted.

## 5. Output and handle policy

- No arbitrary handle inheritance.
- Use STARTUPINFOEX and PROC_THREAD_ATTRIBUTE_HANDLE_LIST for the output channel.
- Parent-side read handle is non-inheritable.
- Only the intended child stdout/stderr write handle is inherited.
- Output is drained while the child runs to avoid pipe deadlock.
- Combined output is capped at 1 MiB initially; exceeding the cap terminates the job.
- The broker must not retain child handles after completion.
- No output is interpreted as executable instructions.

## 6. Failure contract

Use stable negative status codes for: invalid tool ID, invalid timeout, workspace mismatch, path/reparse rejection, script hash mismatch, executable resolution failure, restricted-token failure, job creation/configuration failure, process creation failure, job assignment failure, resume failure, timeout, cancellation, output overflow, wait failure, and exit-code retrieval failure.

All failure paths must close acquired handles in reverse acquisition order. Any child that has been created must be terminated before the broker returns a failure. A failed broker call must never be reported as a successful tool result.

## 7. Required adversarial tests

The broker is not security-accepted until native Windows tests demonstrate:

1. Unknown tool IDs and out-of-range timeouts are rejected.
2. Raw command strings, arbitrary executable paths, and arbitrary arguments are not representable in the API.
3. Script hash mismatch blocks process creation.
4. Modified executable identity blocks process creation.
5. Relative traversal, absolute paths, UNC paths, ADS, device paths, symlinks and junction/reparse-point escapes are rejected.
6. PATH, environment-variable, working-directory and DLL search-order poisoning do not change the launched image or arguments.
7. A suspended child is assigned to the Job Object before it can execute.
8. A child that spawns grandchildren is fully terminated on timeout and cancellation.
9. Output beyond the cap terminates the entire process tree without deadlock or unbounded disk use.
10. Process count and memory limits are enforced.
11. The child cannot read/write outside its declared workspace roots and cannot access the network.
12. Parent and child handles are closed on every success/failure path.
13. Repeated runs do not leak handles, processes, temp files or memory.
14. Broker restart and interrupted-run recovery preserve the evidence journal and do not replay a non-idempotent action automatically.

## 8. Explicit non-goals

The broker is not permitted to execute arbitrary PowerShell, cmd.exe, downloaded binaries, model-generated scripts, or arbitrary user-selected programs. It does not authorize automatic source edits, merges, releases, credential access, remote administration, or system-wide changes.

## 9. Current implementation status

- Runtime ABI: Windows CI PASS on integrated PR #18 head `7a15892a944c747f9563961d7c050c909dd3d3a4`: Stage 7A 24/24, collection imports 2/2, stack/unwind 6/6, 16-argument ABI tests, 17-argument rejection, and frozen M1-M6 83/83.
- Native process broker: PHASE 1 IMPLEMENTED and Windows-tested. Typed test-tool API is opt-in only, default disabled; fixed tool IDs; pinned manifest and native CNG script verification; image-derived workspace root; reparse-point checks; suspended process creation; Job Object process-tree containment; timeouts and memory/process limits.
- Model access to process execution: DISABLED. The broker may be used only by explicitly opted-in test builds; it must not be exposed to model-generated plans.
- The historical PR #7 `sh_dev_run_process(String)` prototype remains rejected because it accepts raw command text, inherits standard handles, waits indefinitely, and has no allowlist or process-tree containment.
- Remaining production-security gates: full canonical filesystem and executable-image final-path validation; ADS/UNC/device-path rejection; restricted token/AppContainer and workspace-only ACLs; clean environment and explicit DLL search policy; bounded stdout/stderr capture with handle allowlist; cancellation; durable audit journal/restart recovery.
- Do not mark DevAgent autonomous or production-ready until every remaining adversarial gate above passes on the same Windows commit.


## 2026-11-26 - Phase 2A: crash-safe per-execution workspace transaction candidate

Status: IMPLEMENTED IN THE PR #18 CANDIDATE BRANCH; WINDOWS ADVERSARIAL CI PENDING. This is a PowerShell 5.1 transaction prototype and test harness. It is not yet wired into the native process-broker emitter and does not complete the restricted-token/AppContainer gate.

Candidate files:
- Tests/DevAgentBroker/WorkspaceTransaction.ps1
- Tests/DevAgentBroker/WorkspaceCrashChild.ps1
- Tests/Test-DevAgentWorkspaceSecurity.ps1
- .github/workflows/devagent-workspace-security.yml

Transaction contract:
1. Each execution receives a random 128-bit directory ID and a dedicated exec-<id> workspace. The caller supplies an execution SID (the planned AppContainer/package SID) and a supervisor SID.
2. The dedicated workspace root must already have a protected DACL granting FullControl only to the supervisor and SYSTEM; the manager validates this precondition and never mutates that shared root. The dedicated journal root is hardened to the same supervisor/SYSTEM allowlist.
3. The exclusive lease is created first. A durable PREPARING intent is committed atomically before workspace creation.
4. After mkdir, the complete owner/group/DACL SDDL is captured. The journal advances to ACL_PENDING and is flushed before any restrictive DACL mutation.
5. The per-execution DACL is protected from inheritance and contains only three FullControl principals: supervisor, that execution SID, and SYSTEM. The descriptor is verified before the journal advances to ACTIVE.
6. Completion or recovery first commits RESTORING, restores the original DACL, verifies the complete owner/group/DACL SDDL, commits RESTORED, and only then deletes the execution tree and journal.
7. Recovery acquires the per-execution exclusive lease. Live executions are skipped. Replaying PREPARING, ACL_PENDING, ACTIVE, RESTORING, or RESTORED is designed to be idempotent. An empty PREPARING directory can be deleted; a non-empty one without a captured descriptor fails closed.
8. Journal writes use a same-directory temporary file, Flush(true), and atomic File.Move/File.Replace. Abandoned temporary and lease files are reclaimed only after obtaining the execution lease.

Adversarial Windows test plan:
- Two concurrent executions must have disjoint ACL identities and unique paths; active leases must block recovery.
- Kill a worker process after directory creation, after ACL application, during rollback before ACL restore, and after ACL restore but before the final journal state. Recovery must restore the saved descriptor and safely finish cleanup.
- A nested junction targeting an external sentinel directory must be unlinked without traversing or deleting its target.
- Malformed journals, journal path redirection, execution-slot junctions, and orphan atomic-write artifacts must fail closed or be safely reclaimed.
- Verify shared parent ACLs remain byte-for-byte unchanged and no journal/lease/temp artifacts remain after successful recovery.

Boundaries and limitations:
- The tests use valid AppContainer-shaped SIDs as ACL principals, but they do not create or validate a restricted primary token or an AppContainer process. ACL identity separation is not proof of process isolation.
- The native broker still launches under the caller token. No token restriction, low-integrity label, AppContainer capability policy, network denial, clean environment, DLL search policy, bounded stdout/stderr capture, cancellation, or durable audit-evidence chain is implemented by this component.
- This PowerShell prototype checks reparse-point attributes and never intentionally traverses a detected link during cleanup, but it does not provide handle-relative, race-free filesystem traversal. Native final-path and file-identity checks using opened handles remain mandatory.
- The journal captures owner, group, and DACL, but does not read or modify SACL/audit entries. Owner and group are preserved; rollback applies the saved DACL and verifies the complete saved owner/group/DACL descriptor.
- Flush(true) and atomic rename protect process-termination recovery; this candidate does not claim power-loss durability of parent-directory metadata.
- The existing native broker still changes its process current directory to the image-derived workspace root. The new transaction manager does not alter or fix that native behavior.

Do not enable model-generated process execution. Treat this phase as a testable rollback foundation only. Acceptance requires the new adversarial Windows workflow to pass on one exact commit, followed by native restricted-token/AppContainer integration and the remaining broker gates.


Phase 2A implementation hardening notes:
- Both security roots must be absolute local drive paths; relative, UNC, NT namespace, device, and ADS forms are rejected before canonicalization.
- The workspace root is a precondition: it must already be a protected supervisor/SYSTEM-only directory. A failed preflight does not modify either root.
- Journal JSON is capped at 64 KiB on write and on both recovery reads.
- Synthetic execution test SIDs use the AppContainer SID namespace prefix S-1-15-2-; this is a format gate only, not proof that Windows created the SID from an AppContainer profile.
- Crash tests include the PREPARING state after mkdir, ACL_PENDING after the DACL write, RESTORING before/after DACL restoration, RESTORED before deletion, and active-work tree cleanup with a nested external junction.


Windows CI finding and correction (2026-11-26): the first adversarial runner reached the journal transition and exposed that .NET Framework File.Replace rejects a null backup path. The journal writer now supplies a unique same-directory backup filename, deletes it after a successful swap, and recovery reclaims a leftover backup only while holding the execution lease. The adversarial suite seeds a simulated interrupted-replace backup and verifies recovery removes it. This correction is committed for a fresh Windows replay; it is not considered validated until that replay completes.
