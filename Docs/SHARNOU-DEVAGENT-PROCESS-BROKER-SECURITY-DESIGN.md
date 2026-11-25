# SharnouDevAgent Native Process Broker - Security Design

Status: PHASE 1 IMPLEMENTED / SECURITY ACCEPTANCE INCOMPLETE
Owner: Sharnou Compiler
Target: Windows x64, native Sharnou-generated PE32+
Date: 2026-11-26

## Current implementation status - 2026-11-26

Status: PHASE 1 IMPLEMENTED; WINDOWS CI PASS on PR #18 head `2ee44cef7f3d67b4ccdc26aa391a9e789197197b`. This is not yet security-accepted and must not be exposed to model-generated plans.

Validation runs: Stage 7A / combined [45724983298](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45724983298); frozen M1-M6 baseline [45724983299](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45724983299). The combined run passed Stage 7A 24/24, collection imports 2/2, stack-probe/unwind 6/6, Runtime ABI, broker phase-1 adversarial tests, and the integrated M1-M6 83/83 baseline.

Implemented in the dependent DevAgent broker candidate:

- Public API is typed: `sh_dev_run_tool(tool_id: Integer, timeout_ms: Integer) -> Integer`. It is registered only when the compiler is invoked with `-EnableDevAgentTools`; default compiler builds reject the capability.
- Six fixed compiler-owned tool IDs. The caller cannot supply a command string, executable path, script path, arguments, or working directory.
- A SHA-256-pinned `Tests/DevAgentBroker/tool-manifest.json`; the compiler refuses to build the broker fixture if the manifest digest differs from its embedded pin.
- Each fixed PowerShell command verifies the selected script's SHA-256 before invoking it. The Windows test harness includes a tamper replay that must return status 91 without executing the modified script.
- The broker resolves PowerShell from the absolute System32 path returned by `GetSystemDirectoryA`; it does not search PATH.
- Workspace checks require the current directory and fixed workspace directories/files to exist with the expected file/directory type, and reject `FILE_ATTRIBUTE_REPARSE_POINT` on the checked paths. A junction adversarial test expects rejection before process creation.
- Child processes are created suspended with `bInheritHandles=FALSE`, assigned to a Job Object before resume, and subject to kill-on-job-close, active-process, process-memory, job-memory, and bounded wait-time policies.
- Runtime tests cover unknown IDs, invalid timeout, explicit opt-in, fixed tool execution, exit-code propagation, runtime script-hash mismatch, timeout, descendant termination, and reparse-point rejection.

Important implementation deviations and remaining acceptance gates:

1. Script hashing currently uses a fixed PowerShell wrapper with `Get-FileHash` before script invocation. Native Windows CNG hashing inside the broker remains a future hardening step.
2. Workspace validation is a fixed-layout/reparse-point gate, not yet full canonicalization of every ancestor, image-relative root discovery, ADS/UNC/device-path rejection, or a complete filesystem sandbox.
3. The child still uses the caller's token. Restricted-token, low-integrity/AppContainer, and workspace-only ACL enforcement are NOT implemented.
4. A clean environment block and explicit DLL search policy are NOT implemented.
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

- ABI prerequisites: implementation and Windows CI evidence are being completed on PR #17.
- Native process broker: NOT IMPLEMENTED.
- Model access to process execution: DISABLED.
- The historical PR #7 `sh_dev_run_process(String)` prototype is rejected because it accepts raw command text, inherits standard handles, waits indefinitely, and has no allowlist or process-tree containment.
- Do not mark DevAgent autonomous or production-ready until the process broker and every adversarial gate above pass on the same Windows commit.
