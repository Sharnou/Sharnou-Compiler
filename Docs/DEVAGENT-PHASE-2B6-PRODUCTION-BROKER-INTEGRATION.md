# DevAgent Phase 2B.6 - Production Native Secure Process Broker Integration

Status: IN PROGRESS / NOT SECURITY-ACCEPTED
Date: 2026-11-27
Target: Windows x64, compiler-emitted Sharnou PE32+ DevAgent broker
Parent candidate: PR #24, branch devagent-acl-transaction-recovery-20261126
Parent head at milestone start: bd411c2fc777006f9b1160ab8d3d5992c2a15afa

## 1. Objective and acceptance boundary

Phase 2B.6 is the production-integration tranche. It must turn the isolated AppContainer, workspace ACL, Job Object, handle-allowlist, and bounded-output proofs into one compiler-emitted process broker whose actual PE import table, launch token, filesystem transaction, environment, and child lifetime are verified together.

This milestone does not enable model-facing process execution. It does not enable autonomous execution. The public typed tool API remains build-opt-in and unavailable to model-generated plans until all gates below pass and an owner explicitly approves a limited allowlisted canary.

The initial PR #24 native broker candidate failed its Windows crash-recovery test. The journal-recovery defect described below is now corrected and has passed the dedicated post-crash replay plus same-head Windows regression. Phase 2B.6 remains in progress and is not a production security acceptance.

## 2. Evidence at the start of Phase 2B.6

The parent PR #24 candidate currently has the following Windows evidence:

- Milestone 6 historical baseline: PASS, 83/83, run 45964360562.
- Stage 7A native compiler regression: FAIL, run 45964360481.
- The failing test reproduces a real parent-process crash while a child runs, observes the committed ACL journal, confirms Job Object kill-on-close terminated the child, then launches a new broker instance to replay the journal.
- Recovery did not restore the original SDDL on the workspace root, Build, or Build\DevAgentBroker. The journal remained available.

The failed native recovery status is -2685. The emitter encodes an open failure as:

  result = -400 - (1000 + readWin32 * 256 + metadataWin32)

Therefore -2685 decodes to readWin32=5 and metadataWin32=5 (ERROR_ACCESS_DENIED for both the GENERIC_READ CreateFileA attempt and its metadata-only fallback). A separate PowerShell P/Invoke control successfully opened the same journal using the expected access/share/disposition/flags. This narrows the fault to a difference in the native broker's effective path or open call context; it does not prove that the DACL is the root cause.

The diagnostic patch now forwards ACL_RECOVERY_NATIVE_PATH, emits the decoded Win32 fields, and records read-only native token/integrity information. The observed native path was the expected workspace-root journal path; the issue was not a malformed journal pathname or a missing DACL grant.

## 2A. Native integrity root cause and validated recovery-host relocation - 2026-11-27

A follow-up native diagnostic established that the broker process launched for recovery was running at Low Integrity:

- The failed Stage 7A run 45999117333 reported `appcontainer=0`, `restricted=0`, `elevation=1`, and `integrityRid=4096` from the broker's own primary token.
- The same process received `ERROR_ACCESS_DENIED (5)` from native `GetFileAttributesA` for the exact journal path, before the `CreateFileA` recovery open. The PowerShell control in the test runner could still read the journal.
- The image path used by that candidate was `Build\DevAgentBroker\DevAgentBroker.exe`. The same transaction applies an inheritable Low-IL mandatory label to both `Build` and `Build\DevAgentBroker`. A parent crash leaves those directory labels committed; relaunching the broker from an image in that tree can therefore start the recovery host at Low IL.
- The failure was caused by the recovery host image residing below an inheritable Low-IL label. Mandatory Integrity Control is evaluated before the DACL; the broker process therefore ran at Low IL and could not read the Medium-IL workspace-root journal, despite the journal DACL granting Administrators full access. The path and journal contents were valid. This is consistent with Windows MIC semantics: the executable image's integrity level constrains the process integrity level, and MIC is evaluated before the DACL. citeturn211718search0

The fix moves the recovery host image to `\.sharnou-devagent-host\DevAgentBroker.exe`, under the workspace root and outside both Low-IL writable staging directories. The workspace-root AppContainer grant remains read/execute only; a sandbox probe must fail when trying to create a file in the trusted host directory. Writable child staging remains limited to `Build` and `Build\DevAgentBroker`. The workspace DACLs were not broadened, the Low-IL labels were not removed, and no caller-token or unrestricted-process fallback was introduced.

The Windows test checks that the host directory and image do not carry a Low-IL label, that the live broker process is at least Medium IL, and that the launched child remains an AppContainer at Low IL. It includes the host directory in the exact SDDL baseline/rollback comparison and proves the AppContainer cannot write to the host directory.

**Validated on the same exact commit `0c77eeba222a1c34175d5e49b6f279e056642cbf`:**
- Stage 7A run [46000983816](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46000983816): PASS. `Runtime ABI result: PASS`; PE verifier reports AMD64 PE32+, six sections, seven DLLs and 72 APIs; DevAgent broker tests report PASS.
- M6 baseline run [46000983846](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46000983846): PASS, frozen baseline 83/83.
- The crash test killed the broker parent, confirmed Job Object termination of the AppContainer child, then successfully launched a fresh trusted broker. It restored exact DACL and mandatory-label SDDL for workspace root, trusted host, Build, and Build\\DevAgentBroker, and removed the committed journal. The trusted host process integrity was `0x3000` (High); the sandbox child remained AppContainer Low IL (`0x1000`).
- The intermediate `-126` test result was the dedicated post-recovery fixed-directory reparse rejection code, not a recovery error. The regression assertion was updated to expect this fail-closed status; the subsequent same-head Stage 7A run passed.

This closes the reproduced journal-read/replay failure for the tested Windows crash scenario. It does **not** complete all of Workstream A or Phase 2B.6.

## 3. Workstream A - crash-safe ACL recovery

A.1. **PASS for the reproduced crash-recovery scenario** on `0c77eeba222a1c34175d5e49b6f279e056642cbf`: host-image relocation preserved a High-IL recovery broker, journal replay restored exact DACL/mandatory-label SDDL, and the journal was retired only after restoration. Do not weaken workspace DACLs, add broad Users/Everyone ACEs, increase child privileges, or discard the journal.

A.2. Validate the journal as a regular, single-link, non-reparse file opened by handle. Verify the final path and file identity are within the canonical workspace root before consuming the contents. Retain the journal on every malformed, inaccessible, truncated, version-mismatched, or restore-failure path.

A.3. Keep the write-ahead ordering invariant: capture exact original descriptors; flush and close the temporary journal; atomically commit the journal with write-through semantics; only then expand ACLs. On recovery, restore parent before descendants, verify exact descriptor restoration, then retire the journal.

A.4. Extend crash injection to every transaction boundary: after journal commit; after each root/Build/broker ACL change; before process creation; after suspended process creation; after Job Object assignment; after resume; during capture; during rollback; and during journal retirement. For each injected termination, the next broker invocation must restore exact baseline DACL and mandatory-label SDDL, terminate all children, and leave no orphaned transaction state.

A.5. Test concurrent broker invocations, WAIT_OBJECT_0, WAIT_ABANDONED, WAIT_TIMEOUT, malformed journal contents, hard-link/reparse substitution, sharing conflicts, and interrupted recovery. No new child may start until recovery has completed and the mutex is safely owned.

## 4. Workstream B - per-execution AppContainer identity

The current candidate derives a stable profile SID from a fixed AppContainer profile name. That is not a per-execution security identity and allows a profile identity to outlive one tool invocation.

B.1. Generate a cryptographically unpredictable execution identifier and use it in a unique, policy-valid AppContainer profile name (maximum 64 characters). Create a zero-capability profile and verify the resulting SID and token before the child is resumed.

B.2. Extend the durable ACL journal format to record the execution identifier and AppContainer profile name needed for crash cleanup. The journal version must be explicitly versioned; older, unknown, or malformed versions fail closed and are never silently reinterpreted.

B.3. After the child Job Object is empty, restore exact workspace descriptors, close profile-related handles, and delete the per-execution AppContainer profile. If profile deletion fails, retain an operator-visible cleanup record and refuse to reuse that identity. Recovery must also be able to finish cleanup after the broker parent crashes.

B.4. Adversarially prove that two concurrent or sequential invocations receive distinct SIDs, cannot access one another's staging data, and cannot retain access after cleanup.

## 5. Workstream C - clean explicit environment

The current CreateProcessAsUserA call passes lpEnvironment=NULL. Windows then supplies the calling process environment. This is not an acceptable production boundary.

C.1. Replace inherited environment with a deterministic, explicit, bounded Unicode environment. Prefer a native allowlist builder that accepts only policy-owned values and paths rooted in the validated Windows installation or per-execution workspace. It must not copy arbitrary caller variables, provider tokens, credentials, untrusted PATH entries, or secrets.

C.2. If CreateEnvironmentBlock is used as an input source, call it with inheritance disabled, filter its results into the explicit allowlist, and release the returned block with DestroyEnvironmentBlock. Do not treat the returned block as the final allowlist without validation.

C.3. Use a Unicode process-creation path for the Unicode environment and set CREATE_UNICODE_ENVIRONMENT. Validate the double-NUL terminator, total character/byte limit, duplicate names, embedded NULs, variable-name syntax, and allowed variable set before CreateProcessAsUserW.

C.4. The child must report a bounded test-only environment fingerprint and explicit presence/absence checks. Tests must prove that a unique secret variable in the broker environment is absent in the child and that required SystemRoot, WindowsPowerShell, and staging variables are correct. Never log environment values or secret material.

C.5. Resolve and retain the explicit Win32 203 failure as a regression case. Do not replace it with lpEnvironment=NULL.

## 6. Workstream D - production handle allowlist and output capture

The Phase 2B.5 Windows fixture passed 121 assertions, but that proof is not equivalent to production-emitter integration. The PR #24 candidate currently assigns the same anonymous pipe writer to stdout and stderr.

D.1. Integrate the verified STARTUPINFOEX handle-list policy into the actual native emitter. Use non-inheritable parent read endpoints and an exact child allowlist containing only NUL stdin, stdout writer, and stderr writer. Verify every allowlisted endpoint has HANDLE_FLAG_INHERIT set and every parent-only endpoint is non-inheritable.

D.2. Drain stdout and stderr independently and concurrently. Preserve stream identity, use bounded reads, and enforce one combined output ceiling. Output at the exact boundary is accepted; the first byte beyond it triggers whole-Job Object termination. Mark partial output explicitly incomplete.

D.3. Exercise timeout, cancellation, read failure, closed-pipe, output overflow, descendant creation, and broker shutdown. Every failure path must terminate the entire Job Object and wait for process/descendant exit before releasing the ACL transaction.

D.4. Keep capture storage exclusive and handle-based. Reject reparse points, directories, and hard links. Never reopen an untrusted output path after execution; persist through the already validated handle and verify the final file identity and byte count.

## 7. Workstream E - loader and executable integrity

E.1. Resolve the executable by absolute path from the trusted Windows system directory and verify the actual image identity before launch. Script hashes are pinned and verified before process creation; keep the verified file handle open through child completion.

E.2. Harden DLL loading for the child, not merely the broker parent. SetDefaultDllDirectories affects the calling process only; a call in the parent is not evidence that the child has the same loader policy. Use a validated child bootstrap or other supported process-start mechanism, then adversarially test poisoned current-directory and PATH locations with a same-named DLL.

E.3. Test UNC, device, ADS, reparse, junction, symlink, hard-link, path-race, and wrong-volume inputs. Ensure the actual opened object and final resolved path stay within the approved root.

E.4. The final generated executable's import table is the source of truth. Every introduced API must appear in the actual PE import table with the correct DLL/name and IAT target. The verifier must reject undeclared, duplicate, overlapping, missing, and incorrectly mapped imports. No manifest-only or source-only claim is sufficient.

## 8. Required same-head Windows acceptance

The exact commit must pass all of the following on Windows Server 2025, with a second supported Windows runner version added before general availability:

1. Native ABI and PE import-table verification.
2. Frozen Milestone 6 baseline 83/83.
3. Stage 7A and Runtime ABI.
4. AppContainer identity, zero-capability, restricted-token and pre-resume verification.
5. Exact ACL write-ahead, rollback, restart and crash-injection matrix.
6. Explicit clean environment, including inherited-secret absence and Win32 203 regression.
7. Production STARTUPINFOEX allowlist and separate bounded stdout/stderr capture.
8. Loader/DLL-search poisoning and filesystem final-object adversarial tests.
9. Job Object emptiness, handle cleanup, profile deletion, journal retirement, and repeat-run tests.
10. Same-head repeat runs proving no stale ACE, SID, profile, child, journal, temp file, or captured-output residue.

A passing static assertion, a test-only fixture, or a PE that merely links is not acceptance.

## 9. Security state and enablement rule

Phase 2B.6 remains disabled for model-facing and autonomous process execution until every acceptance gate above is green on the exact same commit and the owner explicitly approves a limited allowlisted canary.

No fallback to caller-token execution, inherited environment, stable shared AppContainer SID, broad workspace ACL, unlimited output, or raw command interface is permitted. If any identity, ACL, environment, output, import-table, path, or cleanup check is inconclusive, the broker must fail closed and preserve recovery evidence.

Phase 2B.6 is not a release milestone and does not authorize production model execution.
