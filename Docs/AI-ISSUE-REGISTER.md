# AI Issue Register - Sharnou Compiler

**Last reviewed:** 2026-11-26
**Live session tracker:** [Issue #8 - AI Development Plan and Live Session State](https://github.com/Sharnou/Sharnou-Compiler/issues/8)

This register separates active blockers from historical findings. Do not close an issue or mark a risk resolved without the stated evidence.

## Active blockers

### B1 - Frozen 83-case M1-M6 baseline not integrated into the default branch

- Tracking issue: [#9 - Restore and pin the exact frozen 83-case Milestone 1-6 regression baseline](https://github.com/Sharnou/Sharnou-Compiler/issues/9).
- Current default HEAD: `f80dae6fc6efccce84bc733a7529664085b3250e`; the five `Tests/BaselineM6` paths are still absent from default.
- PR #6 remains OPEN / UNMERGED at `9dfe1bc09685a6f7deb9d29b5192b1aae0686039`, 15 ahead / 55 behind. Latest branch runs [44700641397](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44700641397) passed 83/83 and [44700641419](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44700641419) passed Stage 7A 23/23. Do not merge PR #6.
- Draft PR #18 at `3cefcd4dc9ecdd68dee137749a1dbd27f145e88c` carries the baseline in a broader integrated candidate. Windows runs [45772673986](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45772673986) and [45772673929](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45772673929) both pass 83/83 on the exact head. PR #18 remains open/draft and has not been integrated.
- Inventory: Stage 2 25, Stage 4 20, PE verifier 4, Stage 5 25, Stage 6 9. The runner reports suite totals, not polarity.
- The candidate manifest explicitly sets `members_verified_against_original_sha256_manifest: false`; the runner verifies the compressed payload and embedded member hashes but does not independently load the original `SHA256SUMS.txt`.
- File-by-file comparison with the separate R25-R4 archive (SHA-256 `CA01AEACB2E35C6E8039E58F15202A01399DAEA3E0A24E7B4D357772C8EF1274`) remains NOT RUN.
- **Status: WINDOWS CI PASS ON OPEN DRAFT PR #18; DEFAULT-BRANCH BASELINE NOT RESTORED; ORIGINAL-MANIFEST AND R25-R4 PROVENANCE GATES OPEN.**

### B2 - User-local Milestone 7A acceptance not yet recorded

- Tracking issue: [#10 - Milestone 7A native control-flow verification](https://github.com/Sharnou/Sharnou-Compiler/issues/10).
- Default-branch run [45638680338](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45638680338) passed 23/23 on `6899a086bb9b212a7a1e714d1e8fba375ae28fb6`; current default HEAD is three documentation commits ahead, with only `Docs/AI-SESSION-STATE.md` changed.
- Draft PR #18 adds one branch-condition-code positive case and passes 24/24 on exact head `3cefcd4dc9ecdd68dee137749a1dbd27f145e88c` in run [45772673929](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45772673929): 9 positive runtime, 12 negative diagnostic, 3 instruction checks.
- **Status: DEFAULT WINDOWS CI PASS 23/23; PR #18 WINDOWS CI PASS 24/24; USER-LOCAL WINDOWS ACCEPTANCE NOT REPORTED.** Keep issue #10 open.

### B3 - Native self-hosting and autonomous DevAgent gates not yet met

- Tracking issue: [#8 - AI Development Plan and Live Session State](https://github.com/Sharnou/Sharnou-Compiler/issues/8); DevAgent track: [#14](https://github.com/Sharnou/Sharnou-Compiler/issues/14).
- The default branch still has no Sharnou-written self-hosted compiler or native `SharnouCompiler.exe` round trip. PR #5's 7B implementation remains unaccepted and is not part of the default branch.
- PR #18 contains a native typed test-tool broker foundation, but it is open/draft and not security-accepted. Local inference, persistent worker, evidence journal, checkpoint/recovery, deployment, and restart proof are absent.
- **Status: BLOCKED BY DEFAULT-BASELINE INTEGRATION, USER-LOCAL ACCEPTANCE, REMAINING ABI CONTRACTS, AND DEVAGENT SECURITY GATES.**

## Historical / carry-forward issues

### H1 - R26.0 baseline and Windows x64 ABI audit

- Tracking issue: [#1 - R26.0: Pin R25-R4 baseline, replay 83-case regression, and audit Windows x64 ABI](https://github.com/Sharnou/Sharnou-Compiler/issues/1).
- PR #18 provides a Windows-tested candidate for large-frame page probing, `.pdata` / `.xdata` unwind metadata, PE exception-directory validation, and runtime ABI sentinels. Run [45772673929](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45772673929) passed stack-probe/unwind 6/6 and Runtime ABI PASS on exact head `3cefcd4dc9ecdd68dee137749a1dbd27f145e88c`.
- Runtime ABI coverage includes integer argument values through 16 arguments, rejection of 17, nonvolatile RBX/RBP/RSI/RDI/R12-R15 sentinels, live RSP alignment, and higher-arity Windows API probes.
- `Emit-Win64CallIat` is a checked stack-argument emitter (up to 12 typed stack descriptors, shadow space, 16-byte frame alignment). The first four register arguments remain manually prepared at call sites; a complete signature registry/type-driven register-and-stack marshaller is not established.
- PE unwind structures are emitted and statically verified, but no explicit OS `RtlVirtualUnwind` / exception-dispatch runtime test was found.
- PR #18 remains OPEN / DRAFT; default compiler/verifier still contain the earlier four-section implementation. User-local validation is NOT RUN.
- **Status: STACK PROBE / UNWIND STRUCTURE / RUNTIME ABI WINDOWS CI PASS ON DRAFT PR #18; FULL ABI ACCEPTANCE OPEN.**

## Resolved user-reported milestones

The user reported end-to-end Windows success for Milestones 1-6. The summary and evidence classifications are in [AI-SESSION-STATE.md](AI-SESSION-STATE.md) and the complete accepted sequence is in [AI-DEVELOPMENT-PLAN.md](AI-DEVELOPMENT-PLAN.md). These entries are not independently revalidated by this register.

## Issue handling rules

1. Every actionable compiler, linker, PE verifier, ABI, runtime, Engine, or test defect gets a GitHub issue with reproduction, expected/actual behavior, exact file/commit, scope, and acceptance tests.
2. When an issue is repaired, link the fixing commit/PR and test evidence; do not close it solely because source changed.
3. Preserve unrelated issues and frozen baselines.
4. Update this register and the live status issue after every AI generation/repair session.
5. Distinguish user-reported success, static inspection, Windows CI success, not-run, and blocked states.


## Live pull request and CI review - 2026-11-20

### B1 status update - 83-case Milestone 6 baseline

- Tracking issue: [#9](https://github.com/Sharnou/Sharnou-Compiler/issues/9).
- PR #6 is open on `automation/restore-m6-83-regression`, head `9dfe1bc09685a6f7deb9d29b5192b1aae0686039`.
- PR #6 records original Milestone 6 package SHA-256 `0b6bf15445a5dfd8cbf93450af7fd2f5fd6239d4ed082ab18b09878a94b8b164`.
- Windows Actions run `44700641397` succeeded; PR evidence reports Stage 2 25, Stage 4 20, PE verifier 4, Stage 5 25, Stage 6 9 = **83/83**.
- The PR preserves archived suite files/fixtures and uses a temporary compatibility adapter for the old Stage 2 `if` negative fixture, which is now a supported construct.
- **Current status: WINDOWS CI PASS ON OPEN FEATURE BRANCH; NOT YET INTEGRATED INTO DEFAULT BRANCH.** Keep issue #9 open until reviewed/integrated and the default branch has the reproducible baseline.

### B2 status update - Milestone 7A

- Tracking issue: [#10](https://github.com/Sharnou/Sharnou-Compiler/issues/10).
- Implementation commit: `943d24d857b89b9b30a426c8fb4025c05413d6a8`.
- Current default branch HEAD: `fc015ba925c001e1f647f3897736f6f4bd64f0dc`.
- Windows Actions run `44813123428` succeeded on `windows-latest`, including encoding validation and the Stage 7A test entry point. The suite declares 8 positive, 12 negative, and 3 instruction checks (23).
- **Current status: WINDOWS CI PASS; USER-LOCAL ACCEPTANCE NOT RECORDED SEPARATELY.** Keep evidence classifications distinct.

### B3 status update - self-hosting / 7B

- PR #5 proposes Boolean values, short-circuit logical operators, break/continue, and nested returns; branch `automation/milestone-7b-boolean-loop-return`; head `0b8dee87b699eabcaaac37f111686231fb29a82c`.
- Windows CI run `44693097619` succeeded; PR reports Stage 7A 23/23 and Stage 7B 32/32.
- PR #5 is open and unmerged. Its additional language semantics are **proposed, not user-accepted by this review**. Do not merge or describe them as accepted scope without the user's decision.
- Native self-hosting remains NOT DEMONSTRATED.

### Open pull requests reviewed

- PR #4: full compiler/Engine roadmap and scheduled validation proposal; open/unmerged.
- PR #5: Stage 7B Boolean/control-flow extension; open/unmerged; Windows CI success.
- PR #6: frozen 83-case baseline restore; open/unmerged; Windows 83/83 pass.
- PR #7: native SharnouDevAgent test orchestrator; draft/open; Windows CI run `44758761226` succeeded through build, execution, regression run, and artifact upload. This utility is not an AI source-generating agent.

### Automation and persistence policy

Two enabled task automations are relevant: daily `Sharnou DevAgent Progress` and weekly `Advance Sharnou Stack`. Their prompts are being updated to read `AGENTS.md`, `AI_START_HERE.md`, the plan/state/issue register, README, and current GitHub issues/PRs before work; then persist session outcomes and issue status after each scheduled run. Three legacy Honour War daily-upgrade tasks remain disabled.

The repository read-first instruction and per-session update rule remain mandatory for manually started AI work. The current connector does not provide an every-chat-turn event trigger or GitHub Projects V2 board mutation; use the versioned Markdown plan map and GitHub Issues as the authoritative roadmap/status system. Do not claim immediate background synchronization between arbitrary chat turns.


## Live status review - 2026-11-20 22:49 Africa/Cairo

- **B1 / Issue #9 remains BLOCKED for the default branch.** PR #6 is open/unmerged on automation/restore-m6-83-regression, head 9dfe1bc09685a6f7deb9d29b5192b1aae0686039. Its Windows CI reports 83/83 and preserves archive SHA-256 0b6bf15445a5dfd8cbf93450af7fd2f5fd6239d4ed082ab18b09878a94b8b164; this is feature-branch CI evidence, not default-branch integration.
- **B2 / Issue #10 remains open for M7A acceptance evidence.** Implementation is present; Windows Actions run 44813123428 is WINDOWS CI PASS. The user has accepted the 7A scope, but has not yet reported a separate local 7A run. Do not mark user-local runtime acceptance.
- **B3 / self-hosting remains blocked by B1/B2 and the required language-gap audit.** No native self-hosted SharnouCompiler.exe is demonstrated.
- **H1 / Issue #1 remains a carry-forward ABI audit.** Recheck unwind metadata, large-frame stack probing, nonvolatile register/stack/argument probes, and generic checked higher-arity Windows API marshalling against current compiler source; these are historical findings, not reproduced failures in this session.
- PR #5 (7B semantics) remains open/unmerged and is not user-accepted scope. PR #7 remains a draft test orchestrator, not an AI source generator. PR #4 remains an open roadmap proposal.
- No new compiler defect was found or newly reproduced; no new source issue was created in this governance-only session.


## Live audit update - 2026-11-21 08:43 Africa/Cairo

### B1 / Issue #9 - frozen 83-case baseline

- PR #6 remains open and unmerged at `9dfe1bc09685a6f7deb9d29b5192b1aae0686039`; GitHub reports it mergeable. Run `44700641397` passed Stage 2 25/25, Stage 4 20/20, PE verifier 4/4, Stage 5 25/25, and Stage 6 9/9 (83/83). Run `44700641419` passed Stage 7A 23/23 on the same PR head.
- PR #6 changes only the five baseline/runner/workflow paths. Its compiler, verifier, Stage 7A test, and Stage 7A workflow blob SHAs are identical to the current default branch. Thus 83 + 7A have passed on one feature-branch commit, but the default branch still lacks the restored baseline files.
- The 83-case log contains 36 positive and 47 negative cases by case intent (not a manifest field). One historical Stage 2 negative `if` case is run as a positive in a temporary adapter; the archived source and fixture remain hash-checked and unchanged.
- The payload SHA and embedded member hashes are verified. The original SHA256SUMS digest is recorded but the runner does not independently load that source manifest. The file-by-file comparison against the separate R25-R4 archive remains pending.
- **Status: WINDOWS CI PASS ON OPEN FEATURE BRANCH; DEFAULT-BRANCH INTEGRATION AND R25-R4 COMPARISON PENDING.**

### B2 / Issue #10 - Milestone 7A

- Default-branch run `44813123428` passed 23/23 at `fc015ba925c001e1f647f3897736f6f4bd64f0dc`; the current branch's compiler/verifier/test/workflow blobs are unchanged from that tested commit.
- PR #6 run `44700641419` also passed 23/23 on the same commit as the 83-case run `44700641397`.
- Inventory: 8 positive runtime cases, 12 negative parser/type cases, and 3 aggregate instruction/branch checks. The user has not reported a separate local 7A run.
- **Status: WINDOWS CI PASS; USER-LOCAL 7A ACCEPTANCE NOT REPORTED.**

### B3 / 7B proposal and self-hosting

- PR #5 remains open/unmerged and unaccepted: `0b8dee87b699eabcaaac37f111686231fb29a82c`; run `44693097619` passed Stage 7A 23/23 and Stage 7B 32/32 (15 positive, 13 negative, 4 instruction checks). It has not been run with the 83-case baseline.
- PR #5 static review finds the intended Boolean typing, precedence, short-circuit branches, innermost loop target stack, and nested return lowering. Expand tests for dynamic-left short-circuit side effects, outer-loop continue while nested, deep logical branch fixups, and Boolean function argument/return rejection. Add standalone `.sharnou` examples and a same-commit 83 + 23 + 32 CI gate before acceptance.
- PR #7 remains a draft native test orchestrator, not an autonomous AI source generator. Run `44758761226` built and ran its native executable with exit code 0; it launches PowerShell tests and explicitly reports native self-hosted SharnouCompiler.exe as not implemented.

### H1 / Issue #1 - current-source ABI re-audit

- Current compiler SHA-256: `c97bd0c4d9ad94b1b4855bbdcd6f843f563f75b35771106ae8976cae2bbda250`; verifier SHA-256: `953a20c2274eee42eee2523c5608fd48e6dc574e4b5465464e910db560d55179`.
- `Stage0/SharnouCompiler.ps1:1305-1316` permits frames up to 0x100000 and emits `push rbp; mov rbp,rsp; sub rsp,imm32` with no `__chkstk` or per-page probe. The PE header sets `SizeOfStackCommit=0x1000` at line 1555.
- The linker emits exactly `.text`, `.rdata`, `.idata`, and `.reloc`; it populates import and relocation directories but not the PE exception directory. No `.pdata` / `.xdata` is emitted. This is **REPOSITORY PRESENT / STATIC REVIEWED**, not a runtime crash reproduction.
- No nonvolatile-register sentinel, unwind, or large-frame runtime test was executed in this run. Higher-arity Windows API marshalling remains manually emitted rather than signature-driven.
- **Status: ABI ACCEPTANCE BLOCKED pending explicit unwind/stack-probe/runtime validation.**

No compiler, verifier, examples, tests, build scripts, or PR branches were changed in this session. Only status documentation and issue bodies are updated.


## Scheduled compiler audit - 2026-11-21 09:11 Africa/Cairo

### B1 / Issue #9 - baseline and Milestone 7A reconciliation

- Default branch HEAD at audit start: `b46e81b3e9643c1c4be8f8c615a79be329779346`; Windows run `44878709265` passed Stage 7A 23/23 on that exact commit.
- PR #6 remains open/unmerged at `9dfe1bc09685a6f7deb9d29b5192b1aae0686039`. Windows runs `44700641397` (83/83) and `44700641419` (7A 23/23) both succeeded on that same PR head. Compiler/verifier/7A test/workflow blobs match default; five baseline paths remain PR-only.
- The 83-case polarity split is 36 positive / 47 negative by case-intent classification; the manifest records only suite totals. Payload and embedded member hashes are checked; original SHA256SUMS is recorded but not independently re-read by the runner. R25-R4 file-by-file equivalence remains pending.
- **Status: WINDOWS CI PASS ON OPEN FEATURE BRANCH; DEFAULT-BRANCH BASELINE INTEGRATION PENDING.**

### B2 / Issue #10 - M7A

- Default HEAD `b46e81b3e9643c1c4be8f8c615a79be329779346`, run `44878709265`: 8 positive, 12 negative, 3 instruction checks; 23/23. PR #6 same-head run `44700641419` also passed 23/23.
- **Status: WINDOWS CI PASS; USER-LOCAL M7A ACCEPTANCE NOT REPORTED SEPARATELY.**

### B3 - 7B candidate blocker

- PR #5 remains open/unmerged/unaccepted. Its run `44693097619` passed 7A 23/23 and candidate 7B 32/32, but did not run the 83-case baseline.
- Static review found a short-circuit validation defect at candidate compiler lines 322-326: when the left logical operand is dynamic, compile-time constant evaluation still traverses the right operand and can reject a division-by-zero expression even when the runtime left value should skip it. Existing tests cover constant-left short-circuit only.
- Add dynamic-left short-circuit tests, deeper nested loop-target tests, Boolean function ABI rejection tests, nested return-path cases, .sharnou examples, and rel32 target decoding. Keep PR #5 as proposal only; do not merge or copy it without user acceptance.

### H1 / Issue #1 - ABI carry-forward

- Unwind metadata, large-frame stack probes, nonvolatile-register/stack/argument probes, and generic checked Windows API marshalling remain unresolved. No ABI runtime test was executed in this run.
- **Status: REPOSITORY PRESENT / STATIC REVIEWED; ABI acceptance remains BLOCKED.**

No new GitHub issue was created because the 7B finding is confined to an unaccepted existing proposal and is recorded against PR #5. Issue #9 and #10 remain open; their status has not changed.


## Scheduled compiler and DevAgent audit - 2026-11-22 08:46 Africa/Cairo

### Repository and PR state

- Repository: `Sharnou/Sharnou-Compiler`; default branch: `Sharnou-Compiler`.
- Default branch HEAD at audit start: `25bc8aac1370b1d6024ae538956c49a6bbba4f07`. Repository metadata confirms the default branch name. The latest commit list shows this as the branch tip.
- PR #6 remains open and unmerged at `9dfe1bc09685a6f7deb9d29b5192b1aae0686039`, branch `automation/restore-m6-83-regression`. GitHub now reports `mergeable=false`. Compare against current default: PR branch 15 commits ahead and 19 behind; merge base `352c65e05524d494970b2d8b52b7089d12d19435`. The PR still adds five baseline/runner/workflow paths. Its compiler, verifier, Stage 7A test, and Test.ps1 Git blobs exactly match current default. Do not merge or rewrite this branch automatically.
- PR #5 remains open/unmerged at `0b8dee87b699eabcaaac37f111686231fb29a82c`, branch `automation/milestone-7b-boolean-loop-return`; GitHub reports `mergeable=false`. Compare against current default: 2 commits ahead and 19 behind, same merge base `352c65e05524d494970b2d8b52b7089d12d19435`. It changes the compiler, Test.ps1, and Stage 7B tests only. It remains an unaccepted proposal.
- PR #7 remains open/draft at `ac3849800412b1208acb540ef090ffb3ac0455ca`, branch `automation/sharnou-dev-agent-native`; GitHub reports `mergeable=false`. It remains a native test orchestrator proposal, not an AI source-generating agent.
- PR #4 remains open/unmerged; PR #2 remains open/unmerged; PR #3 is merged. No PR was modified or merged in this run.
- Issues #1, #8, #9, and #10 remain open.

### Windows Actions evidence

- Default branch run [44880127825](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44880127825): job `windows-stage7a`, conclusion `success`, checked out default HEAD `25bc8aac1370b1d6024ae538956c49a6bbba4f07`. Source encoding passed; Stage 7A logged 23 passed, 0 failed, 23 total; Stage 7A result PASS; Combined result PASS. Source files were unchanged by this documentation-only commit.
- PR #6 run [44700641397](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44700641397): job `windows-m6-83`, conclusion `success`. Logs show Stage 2 25/25, Stage 4 20/20, PE verifier 4/4, Stage 5 25/25, Stage 6 9/9, and historical baseline PASS (83/83).
- PR #6 run [44700641419](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44700641419): job `windows-stage7a`, conclusion `success`; Stage 7A 23/23 and Combined result PASS. Both PR #6 runs are associated with the same current PR head `9dfe1bc09685a6f7deb9d29b5192b1aae0686039`.
- PR #5 run [44693097619](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44693097619): job `windows-stage7a`, conclusion `success`; Stage 7A 23/23 and proposed Stage 7B 32/32 (15 positive, 13 negative, 4 instruction checks). It did not run the 83-case baseline.
- PR #7 run [44758761226](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44758761226): job `windows-stage7a`, conclusion `success`; Stage 7A ran 23/23, then the native DevAgent repeated the Stage 7A suite, confirmed child exit code 7 propagation, reported its own process exit code 0, and uploaded artifact ID `14654214120`. This is a Windows CI test-orchestrator result only.
- The 83-case intent split is recorded as 36 positive / 47 negative by case classification; the manifest itself records suite totals only. No new Windows workflow was dispatched.

### Source identity and static review

- Current default compiler blob: `ee01ef77b068df5d149934fbf463c43b34c54bf3`; recorded SHA-256 remains `c97bd0c4d9ad94b1b4855bbdcd6f843f563f75b35771106ae8976cae2bbda250`.
- Current default PE verifier blob: `3606b57920043882a2277ad41fd0e0578156944a`; recorded SHA-256 remains `953a20c2274eee42eee2523c5608fd48e6dc574e4b5465464e910db560d55179`.
- Current Stage 7A test blob: `80d8df1c9a6da7c8fb6f2b414c2929f07ba44804`; recorded SHA-256 remains `ffd8a3518d8fc943adb97e319a29a8822d4e5c409226597d0010b40da23eae05`. Test.ps1 blob is `699eb04aefdf1149aa5807107ce351f8c2aae676`; workflow blob is `2b982f0165495854b52d346637e457932a5b0271`.
- PR #6 baseline runner blob: `1bc252b197ba244ea9910ad67b4b8b3cd141138d`; manifest blob: `bbf9a2beb87b84bb51261a28268247d96419424c`; baseline workflow blob: `c6a27e24a7d0bad9eaf554bb59c1d81e0f865c47`. The manifest pins the original M6 archive SHA-256 `0b6bf15445a5dfd8cbf93450af7fd2f5fd6239d4ed082ab18b09878a94b8b164` and bundle SHA-256 `3dd1d7417874159c0bc625edbbc1e8cee1ae7d8a6ea42f30b4dd80ba92102748`. The runner validates the bundle and embedded member hashes; it does not independently read the original `SHA256SUMS.txt`, despite the manifest's provenance boolean. File-by-file comparison against the separate R25-R4 archive remains NOT RUN.
- PR #5 compiler blob: `e884d5223bad5e8fdbb048c5414bc547c4d22ada`; Stage 7B test blob: `0c0bdbf2b8ec23b1445329b86d9d94b8653e7aed`. The suite contains 15 positive, 13 negative, and 4 instruction checks.
- Static ABI comparison found the candidate's `Emit-CallFunction`, `Set-FrameSize`, `Emit-Prologue`, and `Emit-Epilogue` unchanged from default. The Windows x64 calling convention and stack-frame layout were not changed by PR #5. Issue #1's unwind metadata, large-frame stack probing, nonvolatile-register/runtime probes, and generic higher-arity API marshalling remain unresolved.
- PR #5's logical code generation uses TEST plus JZ/JNZ short-circuit branches and the existing rel32 fixup pass. Its loop emitter pushes/pops the innermost loop target in a try/finally block. The current machine-code checks search for opcode byte patterns but do not decode and validate every rel32 target.
- **Correction to the 2026-11-21 note:** `Get-ConstantValue` at candidate lines 322-326 evaluates the RHS subtree when the logical left operand is not a compile-time constant. This is static constant-arithmetic validation, not runtime evaluation of the RHS. Because a dynamic left operand can make the RHS reachable, rejecting a constant divide-by-zero in that RHS can be a deliberate fail-closed compile-time policy. The prior note overclassified this as a confirmed short-circuit defect. No runtime defect was reproduced. The actual test gap is that all current short-circuit side-effect cases use constant left operands; add dynamic-variable left operands for both skip and evaluate paths before accepting 7B.
- Additional Stage 7B coverage gaps: explicit negative tests for Boolean function arguments and Boolean return values (the current function ABI is integer-only); dynamic-left AND/OR side-effect tests; and a bounded rel32 target decoder checking branch destinations against emitted .text labels. The existing nested-loop positive does exercise innermost break/continue behavior. Return-path analysis is conservative and does not prove that a loop always returns; current positive loop-return coverage includes a fallthrough return.

### Native compiler and DevAgent state

- Native self-hosted `SharnouCompiler.exe`: NOT BUILT / NOT RUN.
- PR #7 native `SharnouDevAgent.exe`: WINDOWS CI PASS as a test orchestrator only; artifact ID `14654214120`; process exit code 0. It checks workspace files, tests child exit-code propagation, and launches PowerShell Stage 7A tests. It does not generate or edit source.
- Autonomous AI source generation, persistent worker/checkpoint/recovery, Windows-host deployment, and restart/runtime proof: NOT IMPLEMENTED / NOT RUN.

### Changes and next bounded task

- Status-only documentation changes: this issue register and the session-state file. No compiler, verifier, examples, tests, build scripts, workflows, Engine, IDE, or game source changed. No PR was created, modified, rebased, or merged; no workflow was dispatched; no local Windows build/test was run by the assistant.
- Evidence classification: M1-M6 remains USER-REPORTED WINDOWS PASS; default 7A 23/23 and PR #6 83/83 plus 7A 23/23 are WINDOWS CI PASS; PR #5 7B 32/32 is WINDOWS CI PASS on an unaccepted, stale proposal branch; PR #7 is WINDOWS CI PASS as a test orchestrator; 7B source observations are REPOSITORY PRESENT / STATIC REVIEWED; native self-hosting and autonomous AI agent are NOT RUN / NOT IMPLEMENTED.
- Next bounded task: resolve PR #6's stale/non-mergeable integration path through explicit review, preserving the frozen payload and current compiler blobs. After the baseline is integrated or equivalently included in a fresh isolated candidate branch, prepare the corrected 7B test/patch plan and require 83 + 23 + 32 = 138 same-commit Windows results. Keep ABI repair and autonomous agent implementation separately gated.


## PR mergeability re-check correction - 2026-11-22

A repeated live GitHub PR metadata read supersedes the initial mergeability values recorded in the audit above. At default HEAD `c7bd85a108d97800e7f03b338cf60089a18f4f4e`, GitHub reports PR #6, PR #5, PR #7, and PR #4 as `mergeable=true`; they are still OPEN and UNMERGED (PR #7 remains DRAFT). The initial read returned false, but two subsequent reads returned true. Use the repeated latest value; do not describe these PRs as conflict-blocked.

The compare endpoints still report divergence from default: PR #6 is 15 commits ahead / 21 behind, PR #5 is 2 ahead / 21 behind, and PR #7 is 9 ahead / 21 behind, all with merge base `352c65e05524d494970b2d8b52b7089d12d19435`. This is a staleness/integration review concern, not proof of merge conflicts. PR #6 must remain unmerged by this automation regardless of the GitHub mergeable flag. No PR state or source was changed.


## Final PR metadata consistency note - 2026-11-22

The GitHub connector returned alternating `mergeable` values for PRs #6, #5, and #7 across repeated live reads (false, true, false, then true). The field is therefore treated as UNSTABLE / UNKNOWN in this audit; neither value is used to claim a merge conflict or a clean merge. The stable facts are: all three PRs remain OPEN / UNMERGED (PR #7 is DRAFT), their head SHAs remain unchanged, and compare reports divergence from the default branch. At default HEAD `c7bd85a108d97800e7f03b338cf60089a18f4f4e`, PR #6 was 15 ahead / 21 behind, PR #5 2 ahead / 21 behind, and PR #7 9 ahead / 21 behind. The two later documentation-only commits increase the behind count by two; re-query compare before any future branch operation. PR #6 must not be merged by this automation regardless of metadata.


## Final default HEAD and PR divergence snapshot - 2026-11-22

At default HEAD `e965c0e0848855b48b1e7cfe27707e0d369eb56b`, the compare endpoint reported PR #6 15 ahead / 25 behind, PR #5 2 ahead / 25 behind, and PR #7 9 ahead / 25 behind; all are diverged from merge base `352c65e05524d494970b2d8b52b7089d12d19435`. The earlier note's two-commit increment described the state before the two final consistency-note commits; this snapshot supersedes it. The two status-only commits appended after this snapshot add two more commits to default, so expected behind counts become 27. Re-query before future branch operations. GitHub's mergeable field remains UNSTABLE / UNKNOWN due alternating reads. No PR is merged or modified.


## Live status update - 2026-11-22 - issue synchronization

- New baseline integration PR: [#11](https://github.com/Sharnou/Sharnou-Compiler/pull/11), branch `automation/m6-baseline-current-head-20261122`, commit `37451e384e2e7e669c8368882225619cc9a67e67`, based on current default `d79873e1941b22f1f9eb1413d58e874d77d54e17`. It adds five exact file blobs reused from PR #6; no compiler/test implementation files changed.
- PR #11 Windows run [45003405485](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45003405485) was in progress when recorded. Do not report new-head 83-case success until its log is inspected.
- Default branch Stage 7A Windows run [44996610001](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44996610001) passed 23/23 on exact HEAD `d79873e...` (8 positive, 12 negative, 3 instruction checks). This is WINDOWS CI PASS, not separate user-local evidence.
- PR #6 remains open/unmerged and untouched; its old head is 15 ahead / 27 behind current default. PR #11 is the fresh integration path. PR #5 remains an unaccepted Stage 7B proposal; PR #7 remains a draft test orchestrator, not an AI source generator.
- Issue #1 current-source ABI inspection remains static-only and confirms no stack probe, no unwind metadata, no runtime ABI sentinel tests, and no generic API marshaller. Self-hosting remains blocked.
- Daily `Sharnou DevAgent Progress` automation was re-enabled; weekly `Advance Sharnou Stack` remains enabled; old Honour War daily-upgrade automations remain disabled.
- No compiler, PE verifier, Stage 7A test or engine/game source was changed. No PR was merged; no local Windows build/test was executed by the assistant.


### Fresh PR #11 Windows baseline replay - 2026-11-22

- Run [45003405485](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45003405485), job `windows-m6-83` ID `137149638940`, completed with conclusion `success` on exact PR head `37451e384e2e7e669c8368882225619cc9a67e67`.
- Windows logs: Stage 2 25/25; Stage 4 20/20; PE verifier 4/4; Stage 5 25/25; Stage 6 9/9; aggregate 83/83. ASCII/no-BOM check PASS; no FAIL lines in log.
- Classification: **WINDOWS CI PASS ON PR #11**. The default branch still does not contain the baseline because PR #11 remains open/unmerged.
- PR #11 is two documentation-only commits behind the latest default head after session-state/register updates; no compiler/test sources were changed in those two commits.
- The separate R25-R4 archive comparison remains NOT RUN. Do not close issue #9 yet.


### PR #11 post-CI branch synchronization - 2026-11-22

- New PR head: `614a9badfd4aa2b9682bad384147c3b1e6066020`; base: `cbc8ea0e0bb65e1a4bf1de748fb9aad8d30433ae`; compare status ahead 2 / behind 0.
- Run 45003405485: Windows baseline 83/83, conclusion success, on predecessor tree commit 37451e3...
- Run 45003405576: Stage 7A 23/23, conclusion success, on the same predecessor tree commit.
- Branch sync was a non-force merge commit incorporating only two status-document commits from default. The five baseline file blobs and all compiler/verifier/test/fixture blobs are unchanged. No Windows run is claimed on merge commit 614a9...
- PR #11 remains open; do not close issue #9 until normal PR integration and the independent R25-R4 archive comparison are complete.


### Final PR #11 head and status snapshot - 2026-11-22

- Feature branch head: `939a8b63085e0ef8f2f23b01d5122d4c702e7625`; base at last compare: `b90710f05abb85563e6c87885dbd72caba61899d`; PR diff exactly five baseline paths.
- PR #11 Windows evidence: run 45003405485 baseline 83/83; run 45003405576 Stage 7A 23/23; both run on predecessor code/test tree `37451e384e2e7e669c8368882225619cc9a67e67`. Subsequent merge commits add only status docs from default, without changing compiler/verifier/test/fixture/payload blobs. Do not claim CI on `939a8b6...`.
- This status-only documentation commit advances default; PR #11 will be one docs-only commit behind afterward. No source conflict is introduced by the status docs.
- PR #11 remains open/unmerged. Baseline is not yet on default. Issue #9 remains open until normal integration and the separate R25-R4 archive comparison are complete.


### Final same-head Windows CI evidence - 2026-11-22

- PR #11 exact head `3e8dec1475d45ae2537fc30bd398ebe5a7ee7b67`.
- M6 frozen baseline run [45004007198](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45004007198): success, 83/83 (Stage 2 25, Stage 4 20, PE verifier 4, Stage 5 25, Stage 6 9); ASCII/no-BOM PASS.
- Stage 7A run [45004007206](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45004007206): success, 23/23 (8 positive, 12 negative, 3 instruction/branch checks); ASCII/no-BOM PASS.
- Both runs tested the same exact PR head. No FAIL result lines were present.
- PR #11 is OPEN / UNMERGED. It has only five intended baseline additions. The default branch still does not contain those files until normal PR integration.
- Issue #9 remains open until integration and R25-R4 archive comparison. Issue #10 has WINDOWS CI PASS but no separate user-local M7A confirmation. Issue #1 ABI gates remain unresolved and static-only.


### Latest exact-head Windows results - 2026-11-22

PR #11 head `d33778f6f23a006965f25aeb4dfc8e55cdc49d22` passed both workflows:
- [45004124843](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45004124843): frozen M1-M6 83/83, job success. Breakdown: Stage2 25, Stage4 20, PE verifier 4, Stage5 25, Stage6 9. ASCII/no-BOM PASS.
- [45004124879](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45004124879): Stage 7A 23/23, job success (8 positive, 12 negative, 3 instruction/branch checks). ASCII/no-BOM PASS.
- Both run against the same exact PR head; no FAIL test records.
- PR remains OPEN / UNMERGED; only five baseline additions are in its diff. The default branch still lacks the baseline. R25-R4 archive comparison NOT RUN.
- After this status-only docs commit, PR #11 will be one documentation-only commit behind default. Source/test content is unchanged.


### Synchronized PR head c525a44 - final Windows workflow evidence

- [Run 45004279512](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45004279512): M1-M6 baseline **83/83 PASS**, exact PR head `c525a4491f033dc882488ab84fbb312c5e477061`.
- [Run 45004279593](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45004279593): Stage 7A **23/23 PASS**, same exact PR head.
- Both Windows jobs concluded success and passed ASCII/no-BOM checks. No failed test records.
- PR #11 has exactly five intended baseline paths in its diff and was 6 ahead / 0 behind before this status-only default-branch documentation commit. Default branch still lacks baseline until normal PR integration. No PR merge occurred.


## Live 7A / frozen-baseline audit and 7B proposal - 2026-11-22

### Current default branch and Windows results
- Repository `Sharnou/Sharnou-Compiler`, branch `Sharnou-Compiler`, HEAD `45c83e1941fd74ca1ce94a4f0bc9ffe72a43efe3`.
- Default Windows run [45004368571](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45004368571), job `137152555458`, succeeded on this exact HEAD: Stage 7A 23/23 (8 positive, 12 negative, 3 instruction/branch checks); ASCII/no-BOM PASS.
- PR #11 current head `135b7eec7bf13fc147756dfaeeb3f92eab57a250`, OPEN / UNMERGED, is 7 ahead / 0 behind and adds only the five frozen-baseline files. Windows run [45004395351](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45004395351), job `137152637466`, succeeded with Stage 2 25/25, Stage 4 20/20, PE verifier 4/4, Stage 5 25/25, Stage 6 9/9: **83/83**. Same-head Windows run [45004395353](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45004395353), job `137152637335`, succeeded with Stage 7A **23/23**. Both runs tested exact PR #11 head `135b7eec7bf13fc147756dfaeeb3f92eab57a250`, which has the current default compiler and Stage 7A source/test blobs.
- The 83-case M6 suite remains absent from default until normal PR #11 integration. Case-intent classification from the prior audit is 36 positive / 47 negative; this split is not a field in the manifest, which records the exact suite totals.
- Issue #9 remains OPEN: review/integration of PR #11 and the file-by-file R25-R4 archive comparison remain outstanding. Do not merge PR #11 automatically.

### PR inventory and 7B candidate
- PR #6 remains OPEN / UNMERGED, head `9dfe1bc09685a6f7deb9d29b5192b1aae0686039`, now 15 ahead / 37 behind current default.
- PR #5 remains OPEN / UNMERGED, head `0b8dee87b699eabcaaac37f111686231fb29a82c`, 2 ahead / 37 behind; it is an old, unaccepted 7B proposal.
- PR #7 remains OPEN / DRAFT and is a native test orchestrator proposal, not an AI source-writing agent. PR #4 remains open/unmerged. No PR was changed or merged.
- PR #5 workflow [44693097619](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44693097619) succeeded on its older source tree: Stage 7A 23/23 and proposed Stage 7B 32/32 (15 positive, 13 negative, 4 instruction-presence checks). It did not run the 83-case baseline and does not establish current-default acceptance.
- Static review identifies test gaps in that candidate: all short-circuit side-effect cases use constant left operands; no dedicated Boolean function argument/return ABI rejection tests; branch checks search opcode byte patterns but do not decode/validate rel32 targets. The existing nested-loop case tests innermost break/continue, but deeper nested break/continue coverage should be added. The earlier alleged dynamic-left short-circuit bug was not reproduced; compile-time constant validation is not itself runtime evaluation.
- Proposed 7B only (not accepted or implemented): Boolean values and strict typing; !, &&, || with precedence and short-circuit runtime branches; break/continue with innermost-loop target stack; nested returns with conservative return-path analysis. Keep the M7A integer condition behavior compatible, do not coerce integer to Boolean in logical expressions, and reject Boolean function arguments/returns while the function ABI remains integer-only.
- New tests should cover dynamic-variable-left short-circuit skip and evaluate paths, nested loops/conditionals, Boolean typing/negative cases, return-path cases, and a rel32 target decoder. Require M6 83 + M7A 23 + the full 7B suite on one exact commit before acceptance.

### Remaining blockers
- Issue #10 remains OPEN: Windows CI now verifies Stage 7A, but user-local Stage 7A acceptance has not been separately reported.
- Issue #1 ABI risks remain OPEN / static-only: no large-frame stack probe; no PE unwind metadata (.pdata/.xdata); no runtime nonvolatile-register/RSP/stack-argument sentinels; no generic checked API-call marshaller.
- Native self-hosted `SharnouCompiler.exe` is NOT BUILT / NOT RUN. PR #7 DevAgent is only a test orchestrator; autonomous source generation, durable worker/checkpoint/recovery, deployment, and restart/runtime proof are NOT IMPLEMENTED / NOT RUN.
- Current source changes this session: none. Only repository status documentation was updated; no workflows were dispatched.


## Live audit - 2026-11-23

- Default branch HEAD: `12a7daade17ee01519566eea5bc668ecab4a537e`. Latest default Windows run [45006046266](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45006046266) passed Stage 7A 23/23 (8 positive, 12 negative, 3 instruction/branch checks).
- PR #6 remains OPEN / UNMERGED at `9dfe1bc09685a6f7deb9d29b5192b1aae0686039`, 15 ahead / 39 behind. Its same-head Windows runs 44700641397 (83/83, attempt 2) and 44700641419 (7A 23/23, attempt 2) succeeded. Do not merge it.
- PR #11 remains OPEN / UNMERGED at `135b7eec7bf13fc147756dfaeeb3f92eab57a250`, 7 ahead / 2 behind current default. The two commits behind are docs-only; the five-file baseline diff is unchanged. Same-head runs 45004395351 (83/83) and 45004395353 (7A 23/23) succeeded.
- The 83-case totals are Stage 2 25, Stage 4 20, PE verifier 4, Stage 5 25, Stage 6 9; case-intent split 36 positive / 47 negative. The baseline remains PR-only, not part of default.
- Compiler SHA-256 reported by Windows CI: `f1cb1ea2920c62c781f317b52ba281c2a7df72f626638a4aab71ff8d2dd47ead`; PE verifier SHA-256: `8efec55da3a1614f30272227f8d8158710337cb06148fb7f98b8fa2ff013a3de`. Current default and PR #11 compiler/verifier/test/workflow blobs match.
- Baseline provenance gate remains open: the runner checks the compressed bundle and embedded member hashes but does not read the original `SHA256SUMS.txt`; the separate R25-R4 archive comparison is NOT RUN.
- PR #5 remains an unaccepted 7B proposal; run 44693097619 passed 7A 23/23 and 7B 32/32 on its old head, without the 83-case suite. Add dynamic-variable-left short-circuit tests, Boolean function ABI rejection tests, deeper nested-loop tests and rel32 target decoding before any acceptance.
- PR #7 remains a DRAFT native test orchestrator. Run 44758761226 built `SharnouDevAgent.exe` (SHA-256 `9F128ED96972858B13C763B4324813B3D6A1970737F2403C10C70717CE947341`), executed it with exit code 0 and uploaded artifact 14654214120. It does not generate source or connect to an AI service. Its process API has no allowlist, sandbox, timeout, process-tree containment or cancellation; this is a design gate before model-controlled execution.
- Issue #1 ABI risks remain open. Native `SharnouCompiler.exe`, durable autonomous worker/checkpoint/recovery, model/API connectivity, source generation, host deployment and restart proof remain NOT BUILT / NOT IMPLEMENTED / NOT RUN.
- No source changes and no workflow dispatch. 7B remains unaccepted; do not update the accepted development plan. Next: normal review of PR #11, R25-R4 archive comparison, ABI gate, then a fresh isolated 7B branch with 83 + 23 + 7B validation on one exact commit.


## Issue #14 - Autonomous SharnouDevAgent architecture and implementation

- Tracking issue: https://github.com/Sharnou/Sharnou-Compiler/issues/14
- Architecture: `Docs/SHARNOU-DEVAGENT-AUTONOMOUS-ARCHITECTURE.md`.
- User request: advance the native test orchestrator into a local-first autonomous software-development agent with web/local search, read/download/learn, planning/reasoning, specialist agent creation/editing, bug repair and test-backed auto-correction, authorized reverse engineering, and optional OpenAI/Perplexity second opinions.
- Current default branch has no DevAgent process intrinsic. Open draft PR #7 is only a test orchestrator. Its `CreateProcessA` wrapper accepts raw command text and waits indefinitely; no allowlist, timeout/cancellation, Job Object containment, or durable recovery exists. It is not suitable for model-controlled execution.
- Required first gates: resolve the frozen 83-case baseline integration and ABI issue #1; design a typed process broker with allowlisted executables/argument arrays, workspace boundaries, timeout/cancellation, process-tree containment, bounded output, and security tests; then add native WinHTTP/research/download quarantine, content-addressed knowledge store, one in-process local inference runtime, task planning/evidence memory, declarative agent profiles, bounded patch/rollback, and authorized static PE/x64 analysis.
- OpenAI Responses and Perplexity Agent API are optional provider adapters, not local dependencies. API secrets must use Windows Credential Manager/DPAPI, must never enter source/prompts/logs, and private source must not be transmitted without explicit approval.
- Do not grant broad system-level control, privilege escalation, automatic execution of downloaded binaries, arbitrary shell access, or auto-merge/release. Agent manifests cannot grant themselves new permissions.
- Status: ARCHITECTURE RECORDED; SOURCE IMPLEMENTATION NOT STARTED; LOCAL MODEL NOT BUILT; AUTONOMOUS SOURCE REPAIR NOT RUN.


## Live compiler/baseline audit correction - 2026-11-24

This entry supersedes earlier PR #11 ahead/behind counts in the historical entries above; prior records are retained for audit history.

- Current default HEAD at review: `ff24777d241332ffc5a6a43d16cc688ff9f4dff7`. The session-state-only status commit for this run is `1d55cd00d93e60d0c57bf5be180b7afe229d2a3d`.
- PR #11 remains OPEN / UNMERGED at `135b7eec7bf13fc147756dfaeeb3f92eab57a250`, 7 ahead / 9 behind. The nine commits behind are all documentation-only (AI plan, issue register, session state, DevAgent architecture document, README); the five-file baseline diff is unchanged. Its same-head Windows runs 45004395351 (83/83) and 45004395353 (Stage 7A 23/23) both succeeded. Current default and PR #11 compiler/verifier/Test.ps1/Stage 7A test/workflow blobs are identical. Do not merge automatically.
- PR #6 remains OPEN / UNMERGED at `9dfe1bc09685a6f7deb9d29b5192b1aae0686039`, 15 ahead / 46 behind. Its same-head Windows runs 44700641397 (83/83) and 44700641419 (Stage 7A 23/23) succeeded on attempt 2. The five baseline file blobs are identical to PR #11. Do not merge PR #6 by automation.
- The current default Stage 7A workflow run 45291564684 on `ff24777d241332ffc5a6a43d16cc688ff9f4dff7` succeeded: 23/23 (8 positive, 12 negative, 3 instruction/branch checks).
- Baseline provenance remains a blocker: the runner checks the pinned compressed payload and embedded member hashes but does not read the original `SHA256SUMS.txt`, while the manifest says member hashes were checked against that original manifest. The separate R25-R4 archive comparison remains NOT RUN. Preserve the original archive SHA-256 `0b6bf15445a5dfd8cbf93450af7fd2f5fd6239d4ed082ab18b09878a94b8b164`, payload SHA-256 `3dd1d7417874159c0bc625edbbc1e8cee1ae7d8a6ea42f30b4dd80ba92102748`, and R25-R4 SHA-256 `CA01AEACB2E35C6E8039E58F15202A01399DAEA3E0A24E7B4D357772C8EF1274`.
- PR #5 remains OPEN / UNMERGED and unaccepted at `0b8dee87b699eabcaaac37f111686231fb29a82c`, 2 ahead / 46 behind. Run 44693097619 passed 7A 23/23 and proposed 7B 32/32, but did not run the 83-case baseline. Its test gaps remain dynamic-variable-left short-circuit paths, explicit Boolean function argument/return rejection, deeper nested-loop coverage, and rel32 target verification. The `Get-ConstantValue` traversal of a dynamic-left RHS is compile-time constant-arithmetic validation, not a demonstrated runtime short-circuit defect.
- Issue #1 ABI gates remain open: stack probing, unwind metadata, nonvolatile-register/RSP/argument runtime probes, and generic checked Windows API marshalling. Issue #9 remains OPEN until baseline integration and the R25-R4 comparison are complete. Issue #10 remains OPEN because user-local Stage 7A acceptance has not been separately reported.
- PR #7 remains a draft native regression orchestrator, not an AI source-generating agent. Run 44758761226 passed the native test utility with process exit code 0; the process interface still lacks a reviewed allowlist, structured arguments, sandbox/workspace boundary, timeout/cancellation, Job Object containment, and output bound.
- No compiler/source/test/workflow implementation changed. The next dependency remains human review of PR #11, independent baseline provenance comparison, and ABI gate planning before any isolated 7B implementation.


## Live SharnouDevAgent audit - 2026-11-25

### Default-branch and PR inventory

- Default branch starting HEAD: `2dfceaa72b609fd3b8f839605ee5582e7b686151`.
- The default branch contains no DevAgent implementation source, no DevAgent example/test runner, and no process-launch intrinsic. Issue #14 remains the tracking request; issue #12 remains a proposed read-only Windows Binary Reverse Engineer capability.
- PR #7 is the only native DevAgent prototype reviewed. It is OPEN / DRAFT / not mergeable, head `ac3849800412b1208acb540ef090ffb3ac0455ca`, 9 ahead / 50 behind default, and changes 9 files. It is stale and must not be merged or used as the current source base.
- PR #13 is documentation-only and does not implement the reverse-engineering capability.

### PR #7 source and execution audit

- The PR #7 intrinsic `sh_dev_run_process(String)` forwards arbitrary command-line text to `CreateProcessA`, inherits standard handles, and waits with `WaitForSingleObject(INFINITE)`.
- Missing mandatory process controls: registered executable/hash allowlist, structured argument arrays/schema, canonical workspace-root confinement, environment allowlist, output cap, timeout/cancellation, Job Object process-tree containment, and a reviewed restricted execution boundary. This process interface is UNSAFE FOR MODEL-CONTROLLED INPUT and must not be exposed to model output.
- Historical Windows run [44758761226](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44758761226) succeeded only as a fixed native regression orchestrator: it propagated child exit code 7, ran Stage 7A 23/23, exited 0, and uploaded artifact `14654214120`. The log explicitly prints `Self-hosted native SharnouCompiler.exe: NOT YET IMPLEMENTED` before `SharnouDevAgent result: PASS`. That PASS is not AI inference, source generation, autonomous repair, restart recovery, or a self-hosted compiler result.
- The old PR #7 workflow was not rerun in this audit because its process runner still launches arbitrary command strings without the required controls.

### Issue #12 and #14 disposition

- Issue #12's PE/COFF parser, DLL/export catalogue, DXBC/HLSL analysis, and safe System32 capability probes are proposals only; no corresponding default-branch implementation or tests were found.
- Issue #14's local inference runtime, task planner, durable evidence/restart journal, typed tool registry, declarative agent profiles, bounded patch/rollback engine, and autonomous repair loop are NOT IMPLEMENTED / NOT RUN.
- Do not claim SharnouDevAgent is an autonomous AI development agent. The repository currently has a documented architecture plus a stale native test-orchestrator proposal.

### Blocking prerequisites and next gate

- Issue #9 remains open: the frozen 83-case M1-M6 baseline is still outside default in PR #11; human review/integration and original-manifest/R25-R4 provenance reconciliation remain outstanding.
- Issue #1 remains open: large-frame stack probing, Windows x64 unwind metadata (`.pdata`/`.xdata`), runtime nonvolatile-register/RSP/stack-argument probes, and generic checked API-call marshalling remain unresolved.
- The DevAgent architecture makes the baseline and ABI gates prerequisites to model-controlled compiler/process execution. Do not bypass them with PR #7.
- Next implementation must start from a fresh feature branch after those prerequisites, beginning with the typed allowlisted process broker and adversarial security/rollback tests. Research/download quarantine, PE/x64 analysis, local inference, planner/subagents, autonomous repair, and optional providers follow in the documented dependency order.

Classification: REPOSITORY PRESENT / STATIC REVIEWED; historical PR #7 WINDOWS CI PASS for the test-orchestrator demo only; current-default DevAgent NOT PRESENT; autonomous AI NOT IMPLEMENTED / NOT RUN; safe implementation BLOCKED by issues #9 and #1.


## Scheduled live compiler and DevAgent audit - 2026-11-26

- Default branch HEAD `f80dae6fc6efccce84bc733a7529664085b3250e`; default Stage 7A run [45638680338](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45638680338) passed 23/23 at `6899a086bb9b212a7a1e714d1e8fba375ae28fb6`. The three intervening commits changed only the session-state document.
- PR #6 remains open/unmerged at `9dfe1bc09685a6f7deb9d29b5192b1aae0686039`; 15 ahead / 55 behind. Runs 44700641397 (83/83) and 44700641419 (23/23) remain its latest successful Windows evidence.
- PR #18 remains open/draft at `3cefcd4dc9ecdd68dee137749a1dbd27f145e88c`; 149 ahead / 0 behind, 32 changed paths. Exact-head Windows runs 45772673929 (combined) and 45772673986 (baseline) succeeded; push equivalents 45772670498 and 45772670450 also succeeded.
- Combined exact-head results: Stage 7A 24/24 (9 positive, 12 negative, 3 instruction checks); collection imports 2/2; stack-probe/unwind 6/6; Runtime ABI PASS; 14 named broker assertions PASS; M1-M6 83/83; Combined result PASS. Compiler SHA-256 `855d4e67b47030557efd7a58945c102eb8b2419cb866ae31e487e74ffe304141`; verifier SHA-256 `db360b5ca511119cce5362aa6ce2e74fc4b4d81bcdfbbf668930eb1f9da691df`.
- Earlier run 45771836551 failed only at the broker fixture output comparison on prior head `4f03b25841dd3e35e48abb6713024a075fdcd08b`; the later single-separator image-suffix correction at `7a15892a...` is followed by successful exact-head runs.
- The PR18 security design document was updated in the latest docs-only commits to match native CNG and image-derived workspace discovery. The broker still changes process-wide current directory and does not restore it; this needs explicit serialization or removal before concurrent use.
- The default branch has no source changes from this audit. Only the session-state and issue-register status documents are changed; no compiler, test, workflow, runtime, Engine, IDE, or game source is changed. The development plan remains unchanged because 7B and autonomous-agent scope are not newly accepted.


## Scheduled live blocker and DevAgent update - 2026-11-27 08:08 Africa/Cairo

### Baseline and ABI
- Default HEAD at review: 8893ef5156b271132a4104300beb55cac5a74923. Latest default Stage 7A run 45638680338 passed 23/23 on 6899a086bb9b212a7a1e714d1e8fba375ae28fb6; the five commits to current HEAD changed only the session-state and issue-register documents.
- PR #6 remains OPEN / UNMERGED at 9dfe1bc09685a6f7deb9d29b5192b1aae0686039, 15 ahead / 57 behind. Its latest runs 44700641397 (83/83) and 44700641419 (Stage 7A 23/23) succeeded. Do not merge it automatically.
- PR #18 carries the baseline and ABI candidate but remains OPEN / DRAFT / UNMERGED at a8e0ebcf3bfa453cf0011fee673522743e9d300e, 197 ahead / 2 behind, 48 changed paths, 7,846 additions / 117 deletions; mergeable=false. Its exact-head run 45918027479 passed the baseline 83/83. The baseline remains absent from default.
- The baseline runner records members_verified_against_original_sha256_manifest=false; it does not independently load the original SHA256SUMS.txt. The separate R25-R4 archive comparison remains NOT RUN. Keep issue #9 OPEN.
- PR #18 Windows run 45918027351 passed Stage 7A 24/24 (9 positive, 12 negative, 3 instruction checks), collection imports 2/2, stack-probe/unwind 6/6, Runtime ABI, DevAgent broker phase-1, M1-M6 83/83 and Combined result. These are feature-branch results, not default-branch acceptance.
- Issue #1 remains OPEN. The candidate's stack-probe/unwind suite passed 6/6 and Runtime ABI passed, but no OS RtlVirtualUnwind/exception-dispatch runtime test was found. Emit-Win64CallIat supports typed stack descriptors up to 12 arguments; the first four register arguments remain manually prepared, so a complete signature-driven API marshaller is still missing.

### DevAgent security boundary
- PR #18 Phase 2B.2-2B.4 remain test-only PowerShell/.NET P/Invoke fixtures, not production broker integration. Latest runs: 45918027341 (integrated fixture SUCCESS; 11 profile/token, 30 ACL and 41 Job Object assertions), 45918027348 (ACL 30/30), 45918027377 (Job Object/AppContainer 41/41), and 45918027504 (workspace transaction/security 46/46). ABI contract run 45918027532 succeeded.
- The Phase 2B.4 fixture verifies a real AppContainer token, exact package SID, Low-or-lower integrity, zero capabilities, Job Object membership and fail-closed resume ordering for fixed System32 whoami.exe. It does not accept model/user-selected commands, paths or arguments.
- Explicit custom CreateProcessW environment creation failed with Win32 203 on prior head a2e3aae9... (runs 45917660587 and 45917660542). Current successful fixture uses lpEnvironment=NULL and inherits the runner environment for the fixed whoami test. The clean production environment remains BLOCKED.
- The production Phase-1 broker still uses CreateProcessA with the caller token and inherited environment, no AppContainer integration, and no stdout/stderr handle capture. It also changes process-wide current directory without restoring it. Do not expose it to model-generated plans.
- Next bounded proposal: Phase 2B.5 test-only STARTUPINFOEX handle allowlist and bounded concurrent stdout/stderr capture. Use the exact child write-handle list, non-inheritable parent read handles, STARTF_USESTDHANDLES, concurrent stream drains, a combined byte cap and Job Object termination on overflow. The handle-list attribute requires bInheritHandles=TRUE. Keep clean-environment remediation as a separate production gate. No source implementation or workflow dispatch was authorized in this run.

### Disposition
- Issue #9: OPEN; baseline integration and provenance remain pending.
- Issue #1: OPEN; partial ABI CI evidence on PR #18, full generic marshalling/OS unwind acceptance pending.
- Issue #14: OPEN; Phase 2B.4 test-only fixture passes; clean environment and Phase 2B.5 output isolation remain pending.
- Milestone 7B remains unaccepted; PR #5 is still proposal-only.
- No compiler/test/build/runtime/Engine/IDE/game source changed; no PR or workflow was modified. Keep the accepted development plan unchanged.


## Stage 7B candidate re-audit - 2026-11-27 08:08 Africa/Cairo

PR #5 remains OPEN / UNMERGED at 0b8dee87b699eabcaaac37f111686231fb29a82c, 2 ahead / 59 behind current default, with three changed paths (compiler, root test runner, Stage 7B test). Exact-head Windows run [44693097619](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44693097619) passed Stage 7A 23/23 and Stage 7B 32/32 (15 positive, 13 negative, 4 instruction checks), but did not run the 83-case baseline. Do not merge or copy this stale candidate automatically.

Static review found a short-circuit constant-evaluation gap: when the left operand of a logical node is dynamic, Get-ConstantValue still traverses the right subtree. This is compile-time constant-arithmetic validation, not runtime RHS execution, but it can reject an expression whose RHS should be skipped at runtime (for example a dynamic Boolean left operand and a constant divide-by-zero RHS). The positive tests only use literal left operands for the short-circuit skip/evaluate cases. The four machine-code checks test opcode presence and do not decode rel32 destinations.

Proposal-only test expansion: four dynamic-variable-left AND/OR skip/evaluate cases; two explicit Boolean function argument/return ABI rejection cases while function ABI remains integer-only; one three-level nested-loop target case; and rel32 destination decoding for the four existing machine checks. This yields a 39-case Stage 7B suite (20 positive, 15 negative, 4 instruction checks) and a 145-case same-commit gate (83 baseline + 23 Stage 7A + 39 Stage 7B). Preserve the original 83 cases unchanged. Milestone 7B remains unaccepted and unimplemented; use a fresh isolated branch only after explicit scope approval and baseline/provenance prerequisites.

## Scheduled audit - 2026-11-27

### User-approved scope change

The user explicitly approved the required implementation scope for compiler milestones 7B-7E and Engine/Honour War milestones 8-13, plus the autonomous Sharnou AI development agent and advanced Internet/OpenAI/Perplexity bug-research escalation. This supersedes earlier historical entries that described 7B as unaccepted scope. It is scope approval only: no existing PR is approved for merge and no implementation is accepted by this scope statement. The master plan records the exact acceptance criteria in section 12.

### Current compiler and DevAgent candidate state

- Default branch before this run's status writes: HEAD d71855e... (re-fetched at run start). A status-only plan commit was created: 0d72e58940d2fe295da4539eea2cf4f98a77ec48. The default Stage 7A Windows workflow [45963690266](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45963690266) passed 23/23 on that exact documentation-only commit.
- PR #24 remains OPEN / DRAFT / UNMERGED, branch devagent-acl-transaction-recovery-20261126, latest head 21d00a80f51f3df7ebde4a16c18702d601402a25, base 8893ef5156b271132a4104300beb55cac5a74923, GitHub mergeable=false. Do not merge or rebase automatically.
- PR #24 changes this run: Stage0/SharnouCompiler.ps1 (journal validation diagnostics and metadata-only path probe) and Tests/Test-DevAgentBroker.ps1 (unsigned diagnostic constant conversion and expected first-signature rejection code). These are isolated branch changes; no compiler source was written to default.
- M1-M6 baseline workflow [45963617323](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45963617323) passed 83/83 on candidate head 21d00a80f51f3df7ebde4a16c18702d601402a25: Stage 2 25/25, Stage 4 20/20, PE verifier 4/4, Stage 5 25/25, Stage 6 9/9.
- Candidate Stage 7A workflow [45963617259](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45963617259) was IN_PROGRESS at the latest check. Do not infer a conclusion from an unfinished job.
- Prior exact-head run [45963052813](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45963052813) failed crash recovery with status -2405. The test's PowerShell CreateFile probes and direct journal read succeeded; journal magic/version and descriptor lengths were valid. The native GetFileAttributesA call on the broker-constructed journal path returned Win32 ERROR_ACCESS_DENIED (5). Workspace root, Build and broker directory SDDL remained transient after failure, so rollback was not proven.
- Earlier diagnostic-only candidate runs: [45961851035](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45961851035) failed because PowerShell could not convert the signed 0x80000000 literal to UInt32; [45962179131](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45962179131) exposed a more precise first-signature status (-450), requiring the corresponding malformed-input expectation to be updated. These were test/diagnostic failures, not successful crash-recovery evidence.
- The latest commit adds a native metadata-only CreateFile probe after the generic-read open fails. Run 45963617259 is expected to reveal whether the native process can open the same path with zero desired access. Its result is pending. No root cause is claimed yet.

### Security and autonomous-agent disposition

- PR #18 Phase 2B.4 remains a test-only AppContainer/Job Object fixture, not production broker integration. The explicit custom environment block failure (Win32 203) remains an independent production blocker.
- PR #24 crash-safe ACL recovery is not accepted until the exact DACL/mandatory-label rollback is demonstrated after forced parent death and the journal is safely retired.
- Bounded concurrent output/handle isolation and clean environment are still required before model-facing process execution. Model-generated process execution remains DISABLED.
- PR #7 is a historical native test orchestrator, not an autonomous AI source-generating agent. No persistent SharnouDevAgent, provider adapter, durable autonomous worker, self-hosted compiler, or deployment proof exists.
- OpenAI and Perplexity API credentials and a persistent Windows host remain external prerequisites for live provider/worker deployment. Credential-free mocks and local/offline work must remain possible.

### Next dependency-ordered work

1. Inspect the final Windows log for run 45963617259 and decode the metadata-only probe result.
2. Fix the actual native journal path/open defect; do not weaken ACL policy to make the test pass.
3. Re-run crash recovery, malformed-journal, Job Object termination, exact rollback, journal-retirement and reparse-point adversarial tests on the same candidate head.
4. Reconcile the candidate with current default through a new isolated branch if necessary; PR #24 is stale and must remain draft/unmerged.
5. Return to the accepted compiler dependency sequence: frozen baseline provenance and ABI acceptance, 7B-7E implementation and tests, native runtime/security prerequisites, then the Sharnou-compiled autonomous agent. Engine 8-13 follow the approved dependency order.

### Follow-up diagnostic commit - 2026-11-27

PR #24 candidate head advanced to bd411c2fc777006f9b1160ab8d3d5992c2a15afa. Stage0/SharnouCompiler.ps1 now emits the exact native journal path to redirected stdout on the read-open failure path, using already-imported GetStdHandle and WriteFile APIs; no new import was added. The metadata-only CreateFile probe remains immediately after this path echo. This is temporary diagnostic code, not production behavior.

- M1-M6 run [45964360562](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45964360562): WINDOWS CI PASS 83/83 on exact head bd411c2fc777006f9b1160ab8d3d5992c2a15afa.
- Stage 7A/broker run [45964360481](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45964360481): IN PROGRESS at the latest check; no conclusion claimed.
- Required next evidence: inspect the final log for ACL_RECOVERY_NATIVE_PATH, compare it byte-for-byte with the PowerShell-computed journal path, then decide whether the defect is path construction or process token/ACL access. Do not weaken ACLs to force a pass.


## Phase 2B.8 R5.1.a/b exact-head qualification update - 2026-11-28

- PR #33 R5.1.a remains OPEN / DRAFT at `2583faec76d5e469962756d17d2ffabecd6fcd98`. Windows Server 2025 run [46066382172](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46066382172) completed SUCCESS: PE relocation suite 21/21; Stage 7A 24/24; frozen M1-M6 baseline 83/83; combined PASS. Artifact 15231785189, SHA-256 `698ebd55dfb66b529cd8b001aa986e4832e995e8f37a68f7906c7db19546b725`.
- PR #35 R5.1.b remains OPEN / DRAFT at `ab00219f1aa9783c148035b754eebce7269f6fbb`, stacked on PR #33. Windows Server 2025 run [46070065850](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46070065850) completed SUCCESS: focused typed callback-pointer/Win64 ABI probe PASS; Stage 7A 24/24; frozen M1-M6 83/83; combined result and exact-head manifest PASS. Artifact 15232513039, SHA-256 `b246b9e588d06c956ce59ea6583b7da99f1d9a02f3e35df50e8a5fc9a99ed10f`. The callback test does not emit a numeric test total.
- PR #35 manifest explicitly sets `native_scm_service_implemented=false`. The test-only callback intrinsic is opt-in and absent from the default compiler catalog; these runs do not establish an SCM executable or service lifecycle.
- PR #36 remains OPEN / DRAFT and design-only for R5.2/R5.3. R5.1.c real Sharnou-generated SCM host and R5.1.d actual SCM lifecycle/failure/cleanup qualification remain mandatory prerequisites. Do not implement R5.2 service identity/key or R5.3 pipe transport before both R5.1.c and R5.1.d pass.
- The Low-IL AppContainer DPAPI protection subtest remains INCONCLUSIVE because the Windows PowerShell runner could not load `System.Security` (FileNotFoundException). It is not a pass and remains open.
- **Next bounded task:** R5.1.c inert Sharnou-generated service image, actual PE import/relocation/exception verification, and disposable Windows SCM lifecycle smoke tests. Keep model-facing/autonomous execution disabled; Phase 2B.8 remains NOT SECURITY ACCEPTED.


### B5 - DevAgent cannot yet execute the automatic GFX campaign

- Tracking: issue #14 (autonomous SharnouDevAgent); GFX program issue #40.
- DGA-GFX-0.1 adds Projects/DevAgent/GfxCampaign.v1.json, Schemas/DevAgent/GfxCampaign.v1.schema.json, and Docs/DEVAGENT-GFX-MILESTONE-AUTOMATION.md on isolated branch devagent-gfx-campaign-automation-20261128.
- The manifest contains exactly eleven milestones: GFX-0.1 through GFX-0.8 and GFX-A.1 through GFX-A.3, with dependencies, path allowlists, specialist roles, outputs, hard stops and exact evidence policies.
- **Status: CAMPAIGN CONTRACT PRESENT / NATIVE AUTOMATION NOT IMPLEMENTED.** Default branch still lacks a production DevAgent local inference runtime, typed patch/rollback engine, durable journal/restart recovery, accepted model-facing broker and native GitHub/Actions adapter. Existing PR #7 is not safe for model-produced commands.
- GFX-0.1/0.2 remain draft PRs #39/#41; GFX-0.2 has no confirmed exact-head Windows pass/artifact. No downstream GFX milestone is READY or accepted.
- Next implementation order: DGA-0.2 deterministic manifest/DAG/evidence validator; DGA-0.3 durable task journal; DGA-0.4 read-only native repository/Actions adapter; DGA-0.5 actual local inference; DGA-0.6 typed patch transactions; DGA-0.7 broker/security qualification; DGA-0.8 specialist/review/repair/evidence loop; DGA-0.9 campaign scheduler and draft-PR writer.
- Campaign policy forbids direct default-branch writes, arbitrary model commands, auto merge/release, unapproved dependencies and any bypass of Phase 2B.8. Model-facing and autonomous execution remain DISABLED.


#### B5 follow-up - DGA-GFX-0.1 draft PR and manifest reconciliation

Draft PR #42 is open at head 3434994d90f603adf82d8460f0977af8b59eb15a, based on default HEAD 36b07383cb0ee1996298724202454eb8aec57d98. It contains seven documentation/schema/manifest files.

Static checks confirmed both JSON documents parse, all eleven milestone IDs exist, all dependency references resolve, the DAG is acyclic and the declared top-level/milestone property names match the schema. This is not full JSON Schema validation and not Windows/PowerShell execution. The campaign activation remains BLOCKED; DGA-0.2 is the next implementation task.


## DGA-GFX-0.2 implementation and qualification

- Branch devagent-gfx-campaign-planner-20261128 adds the deterministic PowerShell validator, topological planner, optional live-PR snapshot contract, evidence/acceptance gates, CLI and test suite. It is stacked on DGA-GFX-0.1 PR #42.
- The candidate validates both the existing GFX PR chain and exact base branch identities: #39 targets Sharnou-Compiler; #41 targets the GFX-0.1 architecture feature branch.
- A separate Windows PowerShell 5.1 workflow is added to execute positive/negative validator tests and emit the campaign plan.
- The campaign continuousImprovement policy explicitly persists after GFX-0.8 and requires source provenance, benchmark baselines, versioned follow-on work, independent review and owner acceptance.
- Current qualification: static construction checks only. Windows test result is pending; do not mark DGA-0.2 accepted until exact-head CI is green.
- No autonomous source generation, local inference, process launch, network research, patch transaction, Git write, automatic merge or release is enabled by this increment.
