# Phase 2B.8 - Implementation Log and PR #24 Reconciliation

**Implementation branch:** `phase-2b8-identity-profile-qualification-20261127`  
**Parent candidate:** PR #24, `devagent-acl-transaction-recovery-20261126`  
**Parent head pinned for this increment:** `6344632746cd0666025a0beb0d31f4752d6480f6`  
**Implementation PR:** #28 (draft; stacked on PR #24)  
**Tracking issue:** #25  
**Security status:** NOT ACCEPTED; model-facing execution DISABLED.

## 1. Reconciliation result

The exact PR #24 head was compared with the current default branch before creating this implementation branch. It is a large, diverged candidate rather than a small, safely mergeable patch. The implementation branch is therefore stacked directly on its exact tested head; PR #24 was not rebased, merged, or modified.

The PR #24 branch implements the Phase 2B.6 native broker/journal integration candidate. The available repository records do not establish a separately accepted, complete Phase 2B.7 execution-lifecycle implementation. Accordingly, this branch does not relabel PR #24 as Phase 2B.7-complete. Phase 2B.7 lifecycle integration remains a predecessor review item and must be reconciled explicitly against the state machine in the Phase 2B.8 specification.

### Evidence confirmed on the exact PR #24 head

Commit: `6344632746cd0666025a0beb0d31f4752d6480f6`

Windows Actions run [46003358917](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46003358917) checks out that exact commit and passes:
- Stage 7A: 24/24.
- Runtime ABI: PASS.
- Native DevAgent broker phase-1: PASS.
- Normal execution restored exact DACL and mandatory-label SDDL for workspace root, trusted broker host, Build and broker directories.
- Forced parent termination preserved the journal and Job Object killed the AppContainer child.
- Trusted broker host remained Medium-or-higher IL; the sandbox child remained AppContainer Low IL.
- Malformed journal signatures, truncation and trailing bytes failed closed.
- The next invocation recovered the abandoned ACL transaction and removed the journal.
- Combined result: PASS.

Companion Windows baseline run [46003358930](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46003358930) passed the frozen M1-M6 regression baseline (83/83).

These are targeted Windows CI results, not a full 2B.6/2B.7/2B.8 security acceptance.

## 2. Residual gaps found in the parent candidate

The compiler-emitted broker still uses the fixed shared profile name `Sharnou.DevAgent.ProcessBroker.v1`. It creates/derives one stable SID and does not own a unique profile lifecycle for each tool execution.

The current journal is version 1 and contains the three original security descriptors. It does not persist a per-execution identity/profile name, and its integrity protection is not yet the authenticated journal boundary required by Phase 2B.8.

Other unresolved production items include:
- profile deletion/recovery after a parent crash;
- clean explicit Unicode environment (the child currently inherits the broker environment);
- separate stdout/stderr pipes and concurrent draining (currently merged);
- complete child DLL-search hardening;
- exhaustive cut-point recovery, cancellation, and concurrent-workspace qualification;
- independent verification of a complete lifecycle evidence bundle.

**Important sequencing decision:** do not add an unauthenticated profile name to the recovery journal and then use it to delete a profile. Before recovery consumes identity metadata for a privileged profile-management action, the journal format and integrity/key boundary must be designed and tested. The identity primitive can be qualified separately without changing the live broker's authority.

## 3. First code-bearing increment in this branch

Added:
- `Tests/Test-DevAgentExecutionIdentity.ps1`
- a call to this fixture from the root `Test.ps1` combined Windows test entry point.

The fixture:
1. Calls Windows CNG `BCryptGenRandom` using `BCRYPT_USE_SYSTEM_PREFERRED_RNG` to create 128-bit execution identity material.
2. Converts that material into a bounded profile name with a fixed prefix and lowercase hexadecimal suffix.
3. Calls `CreateAppContainerProfile` with a null capabilities pointer and zero capability count.
4. Rejects `ERROR_ALREADY_EXISTS`; it never adopts or deletes a profile that this test did not create.
5. Verifies the returned SID is an AppContainer package SID and that `DeriveAppContainerSidFromAppContainerName` produces the same SID.
6. Requires pairwise-distinct names and SIDs across eight generated identities by default.
7. Calls `DeleteAppContainerProfile`, then requires a fresh `CreateAppContainerProfile` with the same name to return success, and finally deletes that verification profile.
8. Attempts cleanup for every profile and fails when a deletion cannot be proven.

The test uses only Windows APIs already supported by the project platform; it does not introduce an external compiler or change the production broker's imported APIs.

## 4. Explicit limitation of this increment

This is a test-only native API qualification fixture. It does **not** yet:
- change `Stage0/SharnouCompiler.ps1` or the emitted broker;
- replace the stable production profile;
- prove a child process has the unique profile SID;
- store identity metadata in a durable authenticated journal;
- recover/delete an orphaned profile after a crash;
- prove separate streams, clean environment, or DLL policy.

No native test was executed by the assistant in this session. The new fixture has not yet received Windows CI evidence. Until its exact-head Windows run passes, the implementation increment is repository-present and awaiting runtime validation.

## 5. Next implementation sequence

1. Obtain Windows CI results for this branch and fix any source/test issues without changing the PR #24 parent.
2. Add an independent Windows test for the unique identity's actual child token and profile ownership, then integrate identity creation into the compiler-emitted broker.
3. Design and validate an authenticated, versioned recovery record/key boundary before journaling profile names. Unknown or unauthenticated metadata must fail closed.
4. Integrate profile deletion into normal cleanup and restart recovery, retaining the journal when the profile is still in use or deletion cannot be confirmed.
5. Implement explicit Unicode environment and distinct bounded stdout/stderr capture as separate reviewed increments.
6. Expand crash injection at every durable and externally visible transition, then run all predecessor and Phase 2B.8 gates on one exact Windows-tested commit.
7. Require independent evidence verification and human security review before any later model-facing authorization proposal.

Model-generated process execution remains DISABLED throughout this work.
