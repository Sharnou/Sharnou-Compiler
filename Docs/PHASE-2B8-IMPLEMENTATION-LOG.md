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

## 2026-11-27 writer-authority architecture decision gate

Added Docs/PHASE-2B8-WRITER-AUTHORITY-SERVICE-DESIGN.md. The recommended production architecture is a dedicated Windows service SID that owns the signing key and the entire durable ACL transaction lifecycle. This is deliberately not a generic signing oracle: the service must itself validate registered workspace roots, fixed tool IDs/hashes, descriptors, profile ownership and state transitions, and must write/recover its own journal.

The service model introduces installation, maintenance, key rotation/loss and operator recovery requirements. These are product/deployment decisions and remain an explicit owner-approval gate before native service code is introduced. No service binary, key, service registration, IPC endpoint or production journal migration has been implemented.

Current completed test increments:
- Unique AppContainer profile/token create/derive/delete fixture: Windows PASS.
- User-scope DPAPI envelope + strict v2 schema + separate same-user process re-protection fixture: Windows PASS.
- Explicit Unicode environment builder using a non-NULL CreateProcessW environment block: Windows PASS on 9 variables / 354 UTF-16 code units, with required values present and a unique parent secret absent. This is a builder/process-creation primitive only; not yet the production CreateProcessAsUserW + AppContainer launch path.
- Existing production broker sandbox DPAPI characterization was changed to use PowerShell's built-in ConvertFrom-SecureString because Add-Type is not available in the restricted child command surface. The parent uses ConvertTo-SecureString to verify whether the child-minted CurrentUser DPAPI envelope is decryptable. Exact combined Stage 7A run 46025926233 was in progress at the last check; do not claim that probe's result until its log is reviewed.

Model-facing/autonomous execution remains disabled. The emitted broker still uses a stable shared AppContainer profile, v1 ACL journal, inherited environment and merged stdout/stderr. The latest tests do not change these production boundaries.


## 2026-11-27 exact-head Windows combined qualification - commit 9191a2929f4e56dd086ff3da0b0566c0feeb497e

All three required Windows workflows have now completed successfully on the same exact branch head. This closes the requested exact-head test-inspection step; it does not constitute Phase 2B.8 security acceptance.

- Dedicated Phase 2B.8 primitive workflow [46030220104](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46030220104): SUCCESS. All six steps passed: ASCII/source-encoding gate; eight unique CNG/AppContainer identities with matching suspended child-token SIDs, Low IL RID 0x1000 and zero capabilities; normal delete/recreate/delete proof; strict synthetic v2 schema negatives; DPAPI envelope tamper checks and cross-process same-user re-protection proof; explicit Unicode environment primitive; restricted-token AppContainer CreateProcessAsUserW launch primitive; separate bounded stdout/stderr primitive.
- Frozen Milestone 6 workflow [46030220042](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46030220042): SUCCESS, **83/83** on the same commit.
- Stage 7A/combined workflow [46030220210](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46030220210): SUCCESS. The combined root Test.ps1 execution ended with `Combined result: PASS` on the same commit, including the Stage 7A native compiler tests, broker tests, identity/journal/environment/AppContainer-launch/output-stream fixtures and M1-M6 baseline.

### What this exact-head evidence does and does not prove

The tests qualify isolated Windows primitives and the existing regression candidate. They do not show that those primitives are wired into the emitted production broker. The current `Stage0/SharnouCompiler.ps1` broker emitter still uses the fixed shared profile `Sharnou.DevAgent.ProcessBroker.v1`, the v1 ACL journal, `CreateProcessAsUserA`, inherited environment (`lpEnvironment=NULL`) and a merged stdout/stderr pipe. The production emitter still has no `DeleteAppContainerProfile` call, per-execution profile state, or child DLL-search policy. The Stage0 source change in this PR is currently limited to pinning the updated test-tool manifest hash.

The AppContainer launch fixture proves that an independently constructed restricted-token launch can use a non-NULL explicit Unicode environment, three exact inherited handles, separate output pipes and a kill-on-close Job Object. It does not change the production emitter. The environment and output fixtures also retain their stated primitive-only boundaries.

### Writer-authority gate remains open

The v2 schema and DPAPI fixture are not an authenticated production journal. The cross-process test proves that another process under the same user can mint a valid CurrentUser DPAPI envelope with the same public optional entropy. Do not consume such metadata as authority to restore ACLs or delete a profile.

The recommended separate-principal Windows authority service and its non-exportable CNG key are specified in `Docs/PHASE-2B8-WRITER-AUTHORITY-SERVICE-DESIGN.md`. That service, key provisioning, typed IPC and installation/upgrade/recovery model are not implemented and require explicit owner acceptance. Until that trust anchor exists and is independently verified, crash-time profile deletion must remain blocked; a same-user DPAPI record or workspace key file is not an acceptable substitute.

### Next implementation gates

1. On an isolated follow-on, add per-execution CNG identity/profile creation to the emitted broker, verify the actual child package SID, and add the new APIs to the generated PE import table and independent verifier.
2. Integrate normal profile deletion only after the Job Object is empty and exact ACL restoration has been read back and verified. A failed deletion must retain failure state and must not be represented as success.
3. Complete and test the service-owned canonical signed journal, key identity/ACL, transaction state machine and typed IPC. Do not migrate the v1 recovery path or authorize crash-time profile deletion until the service trust boundary is accepted.
4. Then implement restart recovery/profile retirement, production explicit Unicode environment, independent bounded stdout/stderr capture and child DLL loader policy.
5. Add crash cuts and multi-process/concurrent-workspace tests at each durable transition; repeat all gates on one immutable Windows-tested commit and independently inspect the emitted PE import table.

**Disposition:** Phase 2B.8 remains IMPLEMENTATION / NOT SECURITY ACCEPTED. PR #28 remains draft and unmerged; PR #24 remains unchanged. Model-facing and autonomous process execution remain DISABLED.

---

## R3 addendum - emitted broker per-execution AppContainer identity (2026-11-27)

This addendum supersedes the earlier 'What this exact-head evidence does and does not prove' statement for the specific R3 implementation below. The earlier section is retained as the historical baseline that preceded R3.

### Code-bearing changes

- The emitted broker now creates an ephemeral zero-capability AppContainer profile per execution. Its name is `Sharnou.DevAgent.<32 lowercase hex>`; the 128-bit suffix is generated by the system-preferred CNG RNG, and an all-zero identifier is rejected.
- Profile creation is new-only. An existing-name collision is not adopted. The returned SID is independently derived from the name and compared with `EqualSid`.
- Before resuming the suspended child, the broker queries the child primary token's `TokenAppContainerSid` and compares the actual `PSID` value in `TOKEN_APPCONTAINER_INFORMATION` with the newly created profile SID. The structure's PSID field is passed by pointer, not dereferenced as the first bytes of a SID.
- A narrow-only one-time migration revokes legacy shared-profile DACL entries from the workspace root, Build staging and broker directory. The legacy SID is never used to create the child token.
- Normal profile deletion is gated on a confirmed-empty Job Object and a completed ACL transaction rollback. ACL rollback now independently reads the same object's security descriptor after `SetSecurityInfo` and byte-compares the DACL and applicable mandatory-label SACL.
- The generated PE import descriptors, lookup/IAT slots, IAT data-directory extent, independent PE verifier and broker static assertions were updated for `BCryptGenRandom`, `DeleteAppContainerProfile` and `EqualSid`.

### Failure found and corrected during native execution

The first end-to-end Windows broker run exposed an access violation in the child-token SID comparison. `TOKEN_APPCONTAINER_INFORMATION` contains a `PSID` pointer; the original emitted sequence dereferenced that pointer and passed SID data where `EqualSid` requires a SID pointer. R3 now moves the returned pointer itself into the first argument register. A static regression assertion pins this distinction, and the subsequent Stage 7A broker fixture passed on the pre-cleanup code-bearing head.

The emitted helper also preserves the caller's nonvolatile RSI and RDI registers while constructing the profile name.

### Exact-head verification status

- Pre-cleanup code-bearing head `baf810de89d7e228c98696aba8c2ee541935d6d0`: Stage 7A [46049431383](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46049431383) **SUCCESS**; frozen Milestone 6 [46049431324](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46049431324) **SUCCESS (83/83)**; Phase 2B.8 qualification [46049431315](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46049431315) **SUCCESS**.
- Cleaned code head `6ebf50a0fc57fc2b73fe37fc37529e523f6baa72`: temporary native stdout trace calls and the temporary capture-error diagnostic branch have been removed. The Phase 2B.8 workflow [46050006716](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46050006716) is **SUCCESS**; frozen M1-M6 baseline [46050006477](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46050006477) is **SUCCESS**; exact-head Stage 7A [46050006454](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46050006454) was still **IN PROGRESS** at the time this addendum was written. Do not treat that run as passed until its final conclusion is inspected.
- The latest Stage 7A result from the cleaned-code head remains the decisive broker runtime gate. A new push after this log update will require a fresh exact-head check.

### Remaining trust boundary

Crash-time profile recovery remains disabled. The v1 workspace journal does not persist an authenticated execution/profile identity, and DPAPI CurrentUser is not a separate writer identity. The owner-approved service design is architecture approval only; the Windows authority service, protected CNG key, typed IPC, installation lifecycle and authenticated journal v2 remain unimplemented.

**Disposition:** R3 normal execution identity and cleanup are implemented in the emitted native broker, but Phase 2B.8 remains **IMPLEMENTATION / NOT SECURITY ACCEPTED**. PR #29 remains draft and unmerged. Model-facing and autonomous process execution remain **DISABLED**.

## R4 addendum - signed journal envelope qualification (2026-11-27)

Starting point: Phase 2B.8 R3 PR #29 exact head `5be8faf1af2440accdb432862ee38a0a1b17ad5c`.

Isolated branch: `phase-2b8-r4-signed-journal-qualification-20261127`.

Code-bearing scope:
- Adds a test-only RSA-3072 CNG signing fixture using RSA-PSS/SHA-256 and a domain-separated signed envelope.
- Pins the verifier to an independently supplied CNG public-key blob; the key identifier is SHA-256 of that public blob.
- Verifies bounded framing, exact envelope length, pinned key identity and signature before invoking the inner strict journal parser.
- Adds negative cases for malformed envelope version/algorithm/lengths, truncation, trailing bytes, key substitution, payload/signature tampering and a trusted signature over a malformed inner record.
- Does not add production service code, key provisioning, journal persistence, native broker journal migration, profile recovery or any model-facing process-execution capability.
- The test key is ephemeral. This fixture does not prove non-exportability or service-SID key ACL enforcement.

The existing v2 payload fixture is explicitly still incomplete as a production service record: canonical path, fixed tool identity/hash, transaction state and monotonic sequence, actual descriptor validation and opened-handle identity checks remain required before service-owned recovery can be implemented.

Windows validation is pending on the final exact branch head. The Phase 2B.8 primitive, Stage 7A combined suite and frozen M1-M6 baseline must all pass on the same head before this test increment is called requalified.

**Security disposition:** test-only envelope qualification; production authenticated journal and restart-time profile recovery remain BLOCKED. Model-facing/autonomous process execution remains DISABLED.
