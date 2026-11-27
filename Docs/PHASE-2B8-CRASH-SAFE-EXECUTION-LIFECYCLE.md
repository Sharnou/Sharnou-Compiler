# Phase 2B.8 - Fully Qualified Crash-Safe Execution Lifecycle

**Status:** SPECIFICATION ACTIVE; FIRST IDENTITY-PRIMITIVE TEST INCREMENT UNDER REVIEW  
**Track:** Sharnou DevAgent native process broker / Windows security  
**Prerequisite:** Phase 2B.6 journal-recovery correction and Phase 2B.7 lifecycle integration must be reviewed on one exact candidate head.  
**Security posture:** TEST-ONLY. Model-generated process execution remains DISABLED.

## 1. Objective

Convert the repaired native ACL-journal recovery path into a fully qualified, per-execution lifecycle whose security state is established before child creation, remains bounded while the child runs, and is deterministically restored after normal exit, timeout, cancellation, parent crash, machine restart, or hostile workspace mutation.

Phase 2B.8 is not a green-counter milestone. It requires independently inspectable Windows evidence for every lifecycle transition and every recovery outcome. A successful test must prove the state of the operating system (token, AppContainer identity, Job Object, handles, ACLs, labels, journal, process tree and captured output), not merely that helper functions returned success.

## 2. Non-goals and hard constraints

- Do not enable model-facing or autonomous process execution.
- Do not accept arbitrary command strings, executable paths, scripts, argument vectors, working directories, environment blocks, or network destinations from a model or untrusted caller.
- Keep the broker test-only and behind explicit opt-in until every acceptance gate in this document passes and a separate owner review authorizes a later enablement milestone.
- No privilege elevation, security-descriptor weakening, broad workspace grants, inherited ambient handles, inherited user environment, or fallback to an unrestricted token.
- Do not use MSVC, Clang, Visual Studio, MSBuild, external assemblers/linkers, downloaded toolchains, or package installation as a hidden build fallback.
- Do not merge PRs, publish binaries, or enable scheduled/background execution as part of this milestone.
- Preserve the existing compiler, PE, ABI, and frozen regression gates. Do not rewrite historical fixtures to manufacture a pass.

## 3. Required lifecycle state machine

Every execution receives a cryptographically strong, collision-resistant execution ID and follows this monotonic state machine:

1. **REQUEST_VALIDATED** - fixed registered tool identity, immutable argument schema, timeout, resource budget, workspace scope and network policy validated. Reject unknown fields and noncanonical paths.
2. **WORKSPACE_RESERVED** - acquire per-workspace serialization/lease; establish canonical root and record volume/file identity. Reject reparse points, ADS, UNC/device namespaces and path escapes.
3. **JOURNAL_PREPARED** - persist a versioned, authenticated/integrity-protected transaction record containing execution ID, parent/child identities when known, original security descriptors, intended ACL mutations, profile identity, handle policy, policy version and recovery phase. Flush file and containing directory where supported; atomically publish before the first security mutation.
4. **IDENTITY_CREATED** - create a unique per-execution AppContainer profile/SID (or a separately reviewed equivalent isolation identity), with zero capabilities by default. Record exact SID and profile name in the journal. No shared stable package identity between concurrent runs.
5. **WORKSPACE_ACL_APPLIED** - apply least-privilege ACLs to only the execution workspace and required staging/output locations. Preserve original owner, DACL, SACL/mandatory-label state and inheritance semantics in the journal. Verify effective access with the actual child token before launch.
6. **PROCESS_CONFIGURED** - create the child suspended with restricted primary token/AppContainer, explicit handle allowlist, bounded clean Unicode environment, explicit DLL search policy, canonical executable image and controlled current directory. Apply Job Object limits before resume.
7. **RUNNING** - resume only after every preceding invariant is independently checked. Enforce wall-clock timeout, cancellation, process/memory/CPU limits, network denial by default, and concurrent bounded stdout/stderr draining.
8. **QUIESCING** - on normal exit, timeout, cancellation, output overflow, broker shutdown or policy violation, stop accepting new work for the execution, terminate the complete Job Object tree when required, and prove the job is empty.
9. **RESTORING** - restore all original security descriptors in deterministic parent/descendant order; remove temporary labels and grants; close execution-owned handles; delete the per-execution AppContainer profile only after no process/token/profile reference remains. Recovery must be idempotent.
10. **COMMITTED** - verify exact pre-run security state, no surviving descendants, no leaked inheritable handles, no temporary profile, and no temporary workspace mutation. Retire the journal only after all checks pass.
11. **QUARANTINED** - if any invariant cannot be proven, retain the durable journal and recovery evidence, prevent new executions in the affected workspace, and fail closed. Never delete the journal or silently continue after partial rollback.

All transitions must be journaled before externally visible mutations. Re-entry after a crash must use the journal as the source of truth, not infer completion from the presence/absence of a process or temporary file.

## 4. Security and reliability work packages

### 4.1 Unique execution identity and profile lifecycle

- Generate a unique, nonpredictable profile identity for every execution; bind it to the execution ID.
- Verify the resulting AppContainer SID and token properties from the actual child token: AppContainer flag, exact package SID, Low integrity (or stricter approved policy), zero capabilities unless explicitly allowlisted, and no unintended groups/privileges.
- Ensure concurrent executions never share profile identity or workspace grants.
- On normal exit and every failure path, prove process termination and profile deletion.
- On broker crash/reboot, recover orphaned profiles from authenticated journal records; do not delete a profile if any process or token still references it.
- Add collision, stale-profile, SID substitution, profile-creation failure, profile-delete failure and concurrent-run tests.

### 4.2 Durable journal integrity and recovery

- Define a bounded, versioned binary or canonical serialized format with explicit lengths, byte order, reserved-field validation and strict maximum sizes.
- Authenticate/integrity-protect records using a Windows-protected key boundary; do not store key material in the workspace or beside the journal.
- Reject bad signature/MAC, wrong execution ID, wrong workspace file identity, unsupported version, truncation, trailing bytes, duplicate fields, integer overflow, invalid SDDL and path substitution before any rollback mutation.
- Use write-ahead ordering and flush semantics. Test power-loss-equivalent cut points after each durable write and each ACL/profile/process transition.
- Recovery must be idempotent across repeated invocation, tolerate a second crash during recovery, and retain the journal on any incomplete restoration.
- A workspace-wide mutex/lease must handle abandoned ownership and prevent a new child launch until recovery is complete.

### 4.3 Token, ACL and workspace confinement

- Apply ACLs to exact file identities and validated descendants; reject junctions, symlinks, mount points, reparse tags, ADS, device paths, UNC paths and ancestor swaps.
- Verify exact DACL and mandatory-label SDDL before launch and after cleanup; include owner, group, inheritance flags and relevant SACL state in the comparison.
- Prove the child cannot read/write outside its execution workspace or mutate broker binaries, journals, tool registry, policy, compiler source, credentials or sibling execution workspaces.
- Keep the trusted broker host outside the Low-IL child-writable tree. Verify host integrity level and executable provenance.
- A failed ACL apply/restore must block launch or quarantine the workspace; never broaden access as a fallback.

### 4.4 Process creation, handles and environment

- Use CreateProcessW with an explicit, bounded Unicode environment block; do not inherit the runner/user environment.
- Define an allowlist of non-secret variables required by the fixed tool. Reject duplicate names, malformed UTF-16, oversized blocks and inherited secrets.
- Use STARTUPINFOEX with PROC_THREAD_ATTRIBUTE_HANDLE_LIST; explicitly enumerate only the child stdin/stdout/stderr and required capability handles. Parent-side pipe read handles remain non-inheritable.
- Drain stdout and stderr concurrently to avoid pipe deadlock. Enforce per-stream and combined byte limits, deterministic truncation metadata, and termination of the entire job on overflow.
- Pin the executable by canonical final path, file identity and SHA-256; verify the final opened file object and image provenance immediately before launch.
- Set an explicit DLL search policy (safe search flags / controlled System32 and approved application directories); test malicious same-name DLLs in the working directory and PATH.
- Eliminate process-wide current-directory mutation. If unavoidable for a legacy API, serialize it across the entire process and restore it on every exit path; preferred outcome is no SetCurrentDirectory call.
- Keep network denied by default. Any future network exception requires a separate explicit policy and egress test.

### 4.5 Cancellation, timeout and resource accounting

- Define one monotonic deadline covering setup, execution and cleanup; no unbounded wait or unbounded retry.
- Cancellation must be race-safe before creation, while suspended, during execution, and while restoring.
- Job Object policy must bound active processes, memory and CPU where supported; record actual configured and observed limits.
- Timeout, cancellation and output overflow must terminate descendants and enter the same restoration state machine.
- A cleanup timeout must quarantine the workspace and preserve the journal, not abandon restoration.

### 4.6 Concurrency and broker lifetime

- Test multiple simultaneous executions in distinct workspaces and attempted overlapping executions in one workspace.
- Verify unique identities, no cross-workspace ACL grants, no output interleaving, no journal collision and no process-global CWD/environment mutation.
- Exercise broker parent termination at every state boundary and during each restoration step.
- Exercise abandoned mutex recovery, concurrent recovery attempts, duplicate cleanup requests and restart during recovery.
- Prove a new execution cannot start while an earlier workspace is QUARANTINED or has an unresolved journal.

## 5. Required adversarial Windows test matrix

The Windows test harness must emit one named result per assertion, preserve raw logs, and fail the workflow on any missing/unknown result.

| Suite | Required scenarios | Acceptance |
|---|---|---|
| State-machine | Every legal transition; illegal transition; duplicate transition; unknown state | 100% expected transitions; all illegal transitions fail closed |
| Journal | Bad MAC/signature, truncation at every field boundary, trailing bytes, duplicate fields, overflow, unsupported version, wrong workspace identity | Rejected before any ACL/process mutation |
| Crash injection | Broker termination after every journal flush, ACL change, profile create, suspended child create, Job assignment, resume, child exit and each restore operation | Restart recovery reaches exact original state or durable QUARANTINED state |
| ACL/SACL | Exact before/after owner, DACL, inheritance and mandatory-label comparison; restore failure injection | Exact match required; otherwise journal retained and workspace blocked |
| AppContainer | Unique SID per execution, zero capabilities, Low IL, no unintended privileges, stale profile cleanup, profile deletion failure | Every child token independently inspected; no leaked profile/process |
| Process tree | Parent death, child/grandchild spawn attempt, timeout, cancellation, broker shutdown | Job Object empty; no surviving descendant |
| Handles/output | Handle allowlist inspection, attempted handle leakage, simultaneous stdout/stderr flood, output cap boundary, broken pipe | No unintended inherited handle; exact cap; no deadlock; overflow kills job |
| Environment/DLL | Environment allowlist, secret canary absence, malformed Unicode, PATH poisoning, DLL planting | Child sees only approved variables; malicious DLL is not loaded |
| Filesystem | Junction/symlink/ADS/UNC/device path, ancestor swap, sibling workspace, broker/journal tampering | Reject before mutation or child launch |
| Concurrency | Parallel isolated runs, same-workspace contention, abandoned mutex, simultaneous recovery | No cross-run access; deterministic serialization/recovery |
| Regression | Frozen M1-M6, Stage 7A, collection imports, ABI, broker prior suites | All required same-head suites pass without altering frozen fixtures |

Minimum fault injection: one crash point before and after every externally visible mutation and every durable journal transition. The harness must calculate and report the number of injected cut points so coverage cannot be inferred from a hand-written list.

## 6. Evidence and independent verification

Each Windows run must attach a machine-readable evidence bundle containing:

- Repository, branch, exact commit SHA, PR number and workflow/run/job IDs.
- OS edition/build, architecture, PowerShell version and relevant Windows API availability.
- Compiler, verifier, broker and test-harness SHA-256 values.
- Journal schema/version and policy version.
- Execution IDs, profile names/SIDs (non-sensitive test identities), process IDs, token inspection output, Job Object limits and final active-process count.
- Before/after security descriptor snapshots and exact comparison result for every protected path.
- Handle allowlist, environment allowlist (values redacted where sensitive), output byte counts, exit codes and durations.
- Every injected crash point, expected state, observed state, recovery attempt count and journal disposition.
- Raw stdout/stderr, structured assertion results and workflow exit code.
- A verifier independent of the broker implementation that checks evidence schema, hashes, state transitions, ACL equivalence, profile cleanup and process-tree emptiness.

Do not expose secrets, real user profiles, credentials or private host data in artifacts. Use disposable CI workspaces and synthetic canaries.

## 7. Acceptance gates

Phase 2B.8 is accepted only when all gates pass on the same exact Windows-tested commit:

1. **G0 - Source and predecessor audit:** Phase 2B.6 correction and Phase 2B.7 lifecycle code are reviewed; no diagnostic-only code or stale branch assumptions remain.
2. **G1 - Identity:** unique per-execution AppContainer identity, verified child token, zero unintended capabilities and crash-safe profile cleanup.
3. **G2 - Journal:** integrity-protected, write-ahead journal; exhaustive corruption and crash-cut testing; idempotent restart recovery.
4. **G3 - Workspace:** exact ACL/SACL/mandatory-label restoration and adversarial path/ancestor confinement.
5. **G4 - Process boundary:** suspended creation, restricted/AppContainer token, Job Object containment, explicit handle list, clean environment and DLL policy before resume.
6. **G5 - I/O and cancellation:** bounded concurrent stdout/stderr, deterministic overflow handling, timeout/cancellation and complete descendant termination.
7. **G6 - Concurrency:** isolated parallel executions, safe workspace serialization, no process-global state leakage.
8. **G7 - Regression:** all required prior broker, ABI, Stage 7A and frozen-baseline gates pass on the same head.
9. **G8 - Independent evidence:** evidence verifier passes; raw logs and artifact hashes are available; no missing assertions or unaccounted crash points.
10. **G9 - Security review:** explicit human review signs off the threat model, residual risks and exact commit. This does not itself authorize model-facing execution.

Any skipped test, unsupported Windows environment, missing artifact, unknown assertion, partial rollback, leaked profile, surviving process, altered ACL, inherited secret, or unverifiable journal is a BLOCKED result—not a warning.

## 8. Exit criteria and next milestone boundary

Deliverables:
- Native lifecycle implementation integrated with the existing broker behind test-only opt-in.
- Versioned journal and recovery specification.
- Unique per-run identity/profile manager.
- Exact workspace security snapshot/restore implementation.
- Process launch policy for token, environment, DLL search, handles and Job Object.
- Bounded concurrent output and cancellation implementation.
- Crash-injection/adversarial Windows test harness.
- Independent evidence verifier and reproducible evidence bundle.
- Updated security design, session state, issue register and PR review checklist.

Phase 2B.8 completion means the lifecycle is **qualified for controlled, fixed-tool test execution only**. Model-generated commands, arbitrary user-selected tools, autonomous source modification, network-enabled children and production enablement remain prohibited. A later milestone must separately specify policy authorization, model-facing typed capabilities, owner approvals and staged rollout.

## 9. Known predecessor facts to preserve

- The Phase 2B.6 recovery correction has targeted Windows CI evidence for exact DACL/mandatory-label restoration, parent termination with Job Object child termination, trusted broker Medium-or-higher integrity versus Low-IL AppContainer child, and fail-closed malformed-journal rejection.
- Those targeted results do not by themselves prove unique per-execution AppContainer identities, crash-safe profile deletion, a clean environment, DLL-search hardening, production stdout/stderr capture, full concurrency safety or exhaustive crash-point recovery.
- The predecessor candidate remains draft/unmerged. Review the current PR head and all exact-head Windows runs before implementation; do not assume any earlier commit or run is the current candidate.
- No source implementation, workflow dispatch, merge or model-execution enablement is authorized merely by this milestone specification.

## 10. Session completion record

When implementation begins, append the exact starting commit, feature branch, changed paths, code/test hashes, Windows run IDs, per-suite counts, crash-cut coverage, independent verifier result, and unresolved blockers here. Until then, status remains **SPECIFICATION GENERATED; IMPLEMENTATION NOT STARTED; NOT SECURITY ACCEPTED**.
