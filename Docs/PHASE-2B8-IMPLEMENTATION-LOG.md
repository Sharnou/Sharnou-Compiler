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


## 2026-11-27 Windows qualification update - identity and journal-v2 schema primitives

### Exact code revision and evidence

- Code-bearing commit: `907281187ffdf9223d4b345a2847c2a1feb883cf`.
- Dedicated Windows Server 2025 run [46021589016](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46021589016): **SUCCESS**.
- Frozen M1-M6 baseline run [46021589107](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46021589107): **SUCCESS, 83/83**.
- Stage 7A/combined suite run [46021589123](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46021589123): source-encoding gate passed; combined native test step remained in progress at the time of this update. Do not report this exact run as final PASS until its final job conclusion/logs are inspected.
- Earlier exact baseline branch revision `bfb7f573ca795f2b06a36ee1952f3cb9a31880f9` had Stage 7A combined suite success in run [46020834321](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46020834321) and M1-M6 83/83 in run [46020834312](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46020834312). That revision preceded the strict schema parser additions.

### New independently verified Windows results

Identity fixture:
- Eight freshly generated 128-bit CNG execution identifiers created eight new zero-capability AppContainer profiles.
- Eight actual suspended child processes were created with the matching AppContainer security capability; their primary tokens were inspected before resume.
- Each child token was AppContainer, its package SID exactly matched its generated profile, integrity RID was `0x1000` (Low), and TokenCapabilities reported zero groups.
- Eight profile names and SIDs were pairwise distinct.
- All eight profiles passed delete -> successful fresh recreate -> final delete cleanup verification.
- The child-token test intentionally uses the inherited environment only for a suspended, never-resumed process probe. It does **not** qualify the production clean Unicode environment.

Journal primitive:
- DPAPI current-user envelope protected/unprotected the canonical version-2 test record and rejected three modified envelope locations.
- Strict v2 parser accepted the canonical record and rejected an unsupported version, truncation, trailing bytes, profile-name length overflow and missing workspace volume identity.
- The envelope did not contain the journal magic, profile name or package SID in cleartext.
- The current record schema fixture is 279 bytes before DPAPI protection, including a 64-bit volume serial and full 128-bit `FILE_ID_128` value.
- This is still a primitive and schema fixture, not native broker integration.

### Security design decision added

`Docs/PHASE-2B8-JOURNAL-TRUST-BOUNDARY.md` records the essential DPAPI limitation: user-scope DPAPI plus public optional entropy can detect byte tampering by actors unable to invoke the same protection context, but it does not prove the writer process against another process running as the same user. A same-user process can call CryptProtectData with the same entropy. Therefore no profile-deletion authority is to be driven by the current DPAPI fixture alone.

A separately approved writer-authentication trust anchor is now an explicit prerequisite before the native broker journal is changed. Candidate directions include a dedicated service identity/key broker; these are not yet selected or implemented.

### Still not implemented / security-blocking

- No changes have been made to `Stage0/SharnouCompiler.ps1` or the compiler-emitted broker.
- The production broker still uses the stable shared AppContainer profile and v1 ACL journal.
- No production journal is DPAPI-protected or authenticated with a distinct writer identity.
- No profile name/SID recovery or profile deletion after parent crash is implemented.
- Clean explicit Unicode environment remains unresolved; previous attempts surfaced Win32 203. The identity token test was kept separate from that gate rather than weakening the test or claiming success.
- Separate stdout/stderr, child DLL loader policy, exhaustive crash cut points, cancellation/concurrency and same-head full acceptance remain open.

Model-facing and autonomous process execution remain DISABLED.


## 2026-11-27 trust-boundary adversarial proof update

Latest fixture code commit: `a64b81def96b22315b8ab8034bb60c4af1870e32`.

Windows Server 2025 dedicated run [46022134602](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46022134602) completed **SUCCESS**. In addition to prior profile-token and strict schema checks, the journal fixture now:
- rejects empty execution GUID, malformed AppContainer package SID, descriptor-count mismatch, too-short descriptor, unsupported policy version, unsupported journal version, truncation, trailing data, invalid profile-name length and missing workspace volume identity;
- demonstrates the key threat-model limitation by creating a different structurally valid v2 record in a separate PowerShell process running as the same user, protecting it with the same public optional entropy using DPAPI, and successfully unprotecting it again.

This is an expected PASS and a security warning: the same-user principal can mint a different valid DPAPI envelope. Therefore this DPAPI mechanism alone cannot authenticate which broker process wrote the journal. The trust-boundary document prohibits production use as writer authentication until a distinct writer trust anchor is chosen.

At this run:
- Eight AppContainer identities/SIDs were pairwise distinct.
- Each corresponding suspended child token had the exact package SID, AppContainer flag, Low IL RID 0x1000 and zero capability groups.
- All eight normal profile deletions passed delete/recreate/delete verification.
- DPAPI tamper, wrong entropy, cleartext absence, same-user re-protection and strict v2 schema tests passed.

The fixture remains non-production: no compiler-emitted broker integration, no crash-profile cleanup and no complete journal recovery path has been changed.


## 2026-11-27 schema and separate-process writer proof hardening

The test-only v2 schema now models Windows `FILE_ID_INFO` correctly: an unsigned 64-bit volume serial plus the full 16-byte `FILE_ID_128`, rather than a legacy 64-bit file index. Parser tests reject a zero volume serial and an all-zero 128-bit file identifier. The current test fixture has increased by 12 bytes accordingly.

The DPAPI writer-boundary proof now launches a separate Windows PowerShell process under the same user, asks it to protect a different canonical journal payload with the public optional entropy, and verifies that the parent process can unprotect the resulting envelope. This is a real cross-process demonstration; it is not a same-process simulation. It remains a test of the user-scope DPAPI property, not production journal integration.


## 2026-11-27 FILE_ID_INFO and separate-process DPAPI qualification

The latest identity/journal primitive code commit is `fc479378a818bc759f298361c6a298e6c143118e`. Dedicated Windows Server 2025 run [46024410650](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46024410650) completed **SUCCESS** and independently verified:

- Eight new CNG-generated execution identifiers and zero-capability AppContainer profiles.
- Eight real suspended child processes; before resume, each process token reported AppContainer=1, the exact expected package SID, Low IL RID `0x1000`, and zero capability groups.
- All eight profiles passed delete -> fresh recreation -> final delete.
- The strict v2 parser accepted the canonical record and rejected unsupported version, truncation, trailing bytes, profile length overflow, missing volume identity, all-zero 128-bit FILE_ID_128, empty execution ID, malformed AppContainer SID, descriptor count/length mismatch and unsupported policy version.
- The canonical fixture is 279 bytes and stores a 64-bit volume serial plus full 128-bit FILE_ID_128, matching the Windows FILE_ID_INFO shape.
- A separate PowerShell process running under the same Windows user minted a different valid DPAPI envelope with the same public optional entropy. The test process decrypted the child-generated envelope and matched the exact alternate payload. This demonstrates a real cross-process same-user writer: CurrentUser DPAPI does not authenticate one process as the unique writer.

The frozen M1-M6 baseline passed 83/83 on the latest workflow head `cb0551dd1d272deb3c12aab9b5131cc3fb6ed2fb` in run [46024435843](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46024435843).

The full Stage 7A combined workflow [46024435792](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46024435792) had passed checkout and source-encoding and remained in its native combined test step at the last status check. It includes the new AppContainer-originated DPAPI characterization in `SandboxProbe.ps1`; the parent harness attempts to decrypt any sandbox-created envelope using the broker's CurrentUser context. This run's final result is required before classifying that adversarial boundary.


## 2026-11-27 bounded explicit environment primitive qualification

Added `Tests/Test-DevAgentEnvironmentBlock.ps1` and wired it into both root `Test.ps1` and the dedicated Phase 2B.8 Windows workflow.

Exact candidate: `6277f28123b28b56e2710f50d7197239fd034529`.

Dedicated Windows Server 2025 run [46025925905](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46025925905) completed **SUCCESS**, including:
- Explicit Unicode environment builder produced a bounded 9-entry / 354 UTF-16-code-unit environment.
- Child process launched through `CreateProcessW` with `CREATE_UNICODE_ENVIRONMENT` and a non-NULL caller-constructed environment block.
- Required `SystemRoot`, `windir`, `SystemDrive` and `PATH` values were present.
- Validated hidden per-drive current-directory entries were preserved while ordinary inherited variables were discarded.
- A unique parent secret variable was absent from the child.

Frozen M1-M6 baseline run [46025925771](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46025925771) passed **83/83** on the same candidate.

This qualifies the explicit environment construction and ordinary Windows `CreateProcessW` path on the Windows runner. It does **not** yet verify the same environment with `CreateProcessAsUserW` + `SECURITY_CAPABILITIES` for the AppContainer child, and it does not change the compiler-emitted broker. The production emitter still passes `lpEnvironment=NULL`; Win32 error 203 remains unclosed for the production API path until the exact AppContainer/restricted-token process creation path is tested and integrated.
