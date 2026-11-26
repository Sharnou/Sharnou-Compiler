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

## 10. Follow-on implementation checkpoint - 2026-11-26

The follow-on branch `devagent-appcontainer-acl-output-20261126` is currently a **helper-scaffolding checkpoint**, not a sandbox implementation:
- The compiler source declares an AppContainer-profile/SID helper and a DACL merge/revoke helper. Their IAT call targets were corrected to match the USERENV and ADVAPI32 import-table offsets.
- PE verification recognizes the additional system DLLs and API names, and the broker regression contains static assertions for the helper declarations and their target RVAs.
- These helpers are not currently invoked by the live `Emit-DevRunTool` emitter. The active child path therefore remains phase 1 and is not running inside an AppContainer or restricted primary token.
- There is no runtime demonstration yet of AppContainer identity, denied access outside workspace, least-privilege ACLs, ACL revocation, or output-cap enforcement. Presence of API imports or helper declarations is not security evidence.

The next implementation must not expose any model-facing execution path. It must complete the native child-creation transition atomically: create the restricted primary token; attach the no-capability AppContainer SECURITY_CAPABILITIES attribute; use STARTUPINFOEX with an explicit minimal handle list; apply only the required workspace DACL grants; create suspended; assign to the Job Object; resume only after every check succeeds; continuously drain stdout/stderr with a strict byte ceiling; terminate and confirm Job Object emptiness on timeout, overflow or failure; and revoke DACL grants before releasing the serialization lock.

Known design risks requiring explicit resolution before acceptance:
1. A persistent AppContainer profile SID plus temporary DACL ACEs can leave residual access if the broker crashes between grant and revoke. A named mutex serializes normal calls but is not crash recovery. Use a recoverable per-run security principal/ACL transaction or a durable recovery record that fail-closes access after restart.
2. A static workspace-root DACL grant may be inherited by new descendants. Tests must prove the child can write only to the designated Build staging subtree and cannot modify source/tests or any parent directory.
3. Passing a null environment block inherits the caller's environment. A sanitized environment block and DLL search hardening are still required.
4. A pre-opened output file must be protected from reparse points and hard links before granting the AppContainer write ACL. The parent must retain an exclusive non-inherited handle and use that same handle for output persistence; reopening/CREATE_ALWAYS after sandbox execution would create a path race.
5. Every termination path must wait for the Job Object to become empty before revoking ACLs. A failed wait must retain the failure state and must not be interpreted as successful cleanup.

Until the runtime flow and adversarial Windows tests pass, the existing broker remains test-build opt-in only, and model-generated process execution remains DISABLED.

## 11. Live sandbox integration candidate - 2026-11-26

The branch `devagent-sandbox-runtime-20261126` connects the previously staged security primitives into the live `Emit-DevRunTool` emitter. The following is source implementation status, **not runtime acceptance**:

- The broker opens the current process token with the primary-token rights it needs, calls `CreateRestrictedToken(DISABLE_MAX_PRIVILEGE)`, and supplies the resulting restricted primary token to `CreateProcessAsUserA`.
- A profile SID is created/derived under a stable package name. No capabilities are declared in `SECURITY_CAPABILITIES`. The suspended child is assigned to the Job Object, then its primary token is queried for AppContainer identity, restrictions, and zero declared capabilities before the thread resumes.
- `STARTUPINFOEX` is sized with the documented NULL-list sizing call, validates `ERROR_INSUFFICIENT_BUFFER`, caps the attribute list allocation at 4096 bytes, and initializes two attributes: `SECURITY_CAPABILITIES` and `HANDLE_LIST`.
- The handle list explicitly contains only NUL stdin and the pipe writer used for merged stdout/stderr. The read handle and exclusive output-file handle are parent-only.
- The ACL helper opens directories with backup semantics and `OPEN_REPARSE_POINT`, validates the opened handle as a non-reparse directory, obtains the existing DACL with `GetSecurityInfo`, merges the package SID ACE with `SetEntriesInAclA`, and updates that same opened object with `SetSecurityInfo`.
- Package DACL policy is read/execute on the workspace root and read/write/execute on `Build` plus `Build\\DevAgentBroker`.
- AppContainer processes run at Low IL. Mandatory Integrity Control is evaluated before the DACL, so the writable Build folders also receive a Low IL mandatory label with `NO_WRITE_UP` and inheritable OI/CI flags. The source workspace root is intentionally not relabeled.
- Stdout and stderr share one pipe. The parent continuously drains it; each read is limited to the remaining bytes in the 1 MiB buffer. Once the buffer is full, any additional available byte causes whole-job termination and the overflow status. Captured bytes are persisted through the same exclusive output handle, not by reopening the path.
- The child is created suspended, assigned to the Job Object, verified, and then resumed. Timeout, capture overflow, and failure paths terminate the job and wait for it to become empty before common cleanup proceeds.

The native import-table layout was statically re-audited on this branch: 16 descriptors, 66 unique APIs, non-overlapping lookup arrays and IAT arrays including each module's zero terminator, and all emitted IAT calls resolving to declared slots. Static checks do not replace a native PE build or Windows execution.

### Required runtime and residual security acceptance

No Windows Actions result has yet validated this branch. Keep the candidate draft and model-facing process execution disabled until all of the following have positive Windows evidence:
1. Native PE generation and PE verification with the expanded imports.
2. AppContainer identity and restricted-token assertions in the actual child before resume.
3. Positive Build staging write and negative Tests/source write, including parent/child path escapes and reparse/junction attacks.
4. Exact 1 MiB output persistence from a 1 MiB + 1 byte probe, then whole-job termination and Job Object emptiness; also no deadlock under large simultaneous stdout/stderr.
5. Repeat-run, timeout, setup-failure and cleanup behavior with no leaked processes/handles or unintended DACL changes.
6. Network denial and explicit cancellation tests.

Known hard gaps:
- The current package SID is stable and workspace ACL grants are persistent. There is no per-run security identity, transactional grant/revoke, or durable crash-recovery journal yet. A broker crash can leave the package SID's access ACEs behind. This is not an acceptable final production state.
- `CreateProcessAsUserA` currently receives a NULL environment block, which inherits the broker environment. A minimal sanitized environment block and explicit DLL-search policy remain required.
- Canonical final-path resolution and elimination of ancestor TOCTOU races remain incomplete. Current path and handle checks are defense-in-depth, not a complete race-free filesystem capability boundary.
- Network isolation and cancellation are not yet adversarially validated. Declaring zero AppContainer capabilities is not sufficient proof that all network paths are inaccessible.
- No model-generated plan may invoke this broker. It remains explicit-opt-in test tooling only.

Status: **IMPLEMENTATION CANDIDATE / WINDOWS RUNTIME VALIDATION PENDING / NOT SECURITY-ACCEPTED**. No merge, release, or executable publication is authorized by this checkpoint.

## 12. Abandoned ACL mutex: fail closed until recovery exists - 2026-11-26

The broker previously treated `WAIT_ABANDONED (0x80)` as equivalent to `WAIT_OBJECT_0` and continued with the stable AppContainer SID. That is unsafe: Windows reports `WAIT_ABANDONED` when the prior owning thread terminated without releasing the mutex, and explicitly warns that persistent state protected by the mutex must be checked for consistency.

The live emitter now distinguishes the two states:
- `WAIT_OBJECT_0`: normal serialized execution may continue.
- `WAIT_ABANDONED`: return broker status `-118` (ACL recovery required), release the mutex through common cleanup, and do not create/derive the AppContainer SID, mutate ACLs, or launch a child.
- Timeout, failed wait, or unexpected wait return: fail as mutex acquisition failure.

This is a fail-closed guard, **not** crash recovery. The package SID and ACL ACEs can still remain after an owner crash. The broker will refuse future executions when it detects the abandoned mutex; manual ACL/profile recovery is still needed until a protected write-ahead security-descriptor journal and startup recovery path are implemented and adversarially tested.

A static regression assertion verifies the `WAIT_ABANDONED -> -118 -> cleanup` control flow precedes AppContainer SID creation. This does not substitute for a runtime abandoned-mutex test.
