# AI Issue Register - Sharnou Compiler

**Last reviewed:** 2026-11-22
**Live session tracker:** [Issue #8 - AI Development Plan and Live Session State](https://github.com/Sharnou/Sharnou-Compiler/issues/8)

This register separates active blockers from historical findings. Do not close an issue or mark a risk resolved without the stated evidence.

## Active blockers

### B1 - Exact 83-case Milestone 1-6 regression baseline missing from current branch

- Tracking issue: [#9 - Restore and pin the exact frozen 83-case Milestone 1-6 regression baseline](https://github.com/Sharnou/Sharnou-Compiler/issues/9)
- User reports the cumulative 83 cases passed locally through Milestone 6.
- The 83-case suite is not yet present on the default branch.
- Fresh integration PR [#11](https://github.com/Sharnou/Sharnou-Compiler/pull/11) adds only the five exact frozen baseline file blobs from PR #6, but is based directly on current default HEAD `d79873e1941b22f1f9eb1413d58e874d77d54e17`.
- PR #11 head: `37451e384e2e7e669c8368882225619cc9a67e67`; branch `automation/m6-baseline-current-head-20261122`.
- New Windows baseline run [45003405485](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45003405485) completed SUCCESS on PR #11 predecessor head `37451e384e2e7e669c8368882225619cc9a67e67`; its log reports Stage 2 25/25, Stage 4 20/20, PE verifier 4/4, Stage 5 25/25, Stage 6 9/9, aggregate 83/83, and ASCII/no-BOM PASS. Stage 7A run [45003405576](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45003405576) also passed 23/23 on that same predecessor. PR branch is now synchronized with latest default docs at head `614a9badfd4aa2b9682bad384147c3b1e6066020`, compare 2 ahead / 0 behind; only five baseline paths differ. The sync added status-only documentation as second parent; compiler/verifier/tests/fixtures/payload are unchanged. These are WINDOWS CI PASS results for the unchanged code/test tree, not a run on the merge commit.
- M6 package SHA-256: `0b6bf15445a5dfd8cbf93450af7fd2f5fd6239d4ed082ab18b09878a94b8b164`; compressed payload SHA-256: `3dd1d7417874159c0bc625edbbc1e8cee1ae7d8a6ea42f30b4dd80ba92102748`.
- Required next: obtain 83/83 on PR #11, review/integrate through normal PR process, then compare the M6 archive member-by-member against the separate R25-R4 archive (SHA-256 `CA01AEACB2E35C6E8039E58F15202A01399DAEA3E0A24E7B4D357772C8EF1274`). Do not assume equal case counts mean identical suites.
- **Status: PR #11 WINDOWS CI PASS 83/83; branch synchronized and ready for normal review; DEFAULT-BRANCH BASELINE NOT YET RESTORED; R25-R4 COMPARISON NOT RUN.**

### B2 - Milestone 7A Windows acceptance not yet recorded

- Tracking issue: [#10 - Milestone 7A native control-flow verification](https://github.com/Sharnou/Sharnou-Compiler/issues/10)
- Implementation commit: `943d24d857b89b9b30a426c8fb4025c05413d6a8`.
- Test file: `Tests/Test-Stage7A.ps1`.
- Current test inventory: eight positive examples, twelve negative cases, and native instruction/branch encoding checks.
- Default-branch Windows run [44996610001](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44996610001) passed on exact HEAD `d79873e1941b22f1f9eb1413d58e874d77d54e17`: 8 positive runtime cases + 12 negative diagnostic cases + 3 instruction/branch checks = 23/23; job `windows-stage7a` succeeded.
- Log includes ASCII/no-BOM PASS, `Stage 7A test result: PASS`, and `Combined result: PASS`.
- **Status: WINDOWS CI PASS 23/23; USER-LOCAL WINDOWS ACCEPTANCE NOT REPORTED.** Keep issue #10 open pending the separate frozen 83-case baseline and any user-local acceptance record.

### B3 - Self-hosting gate not yet met

- Tracking issue: [#8 - AI Development Plan and Live Session State](https://github.com/Sharnou/Sharnou-Compiler/issues/8)
- Do not generate the full compiler-in-Sharnou implementation until the default-branch 83-case baseline is restored/replayed, 7A evidence is reconciled, and the ABI blockers in issue #1 have passed runtime validation.
- Next design activity after those gates: inspect the actual compiler source and write a construct-by-construct language feature gap inventory for Milestone 7B.
- **Status: BLOCKED BY B1 AND B2.**

## Historical / carry-forward issues

### H1 - R26.0 baseline and Windows x64 ABI audit

- Tracking issue: [#1 - R26.0: Pin R25-R4 baseline, replay 83-case regression, and audit Windows x64 ABI](https://github.com/Sharnou/Sharnou-Compiler/issues/1)
- This issue records a separate pinned R25-R4 archive and includes historical audit findings:
  - Missing PE unwind metadata (`.pdata` / `.xdata`) for non-leaf generated functions.
  - Missing large-frame stack probing; historical inspection saw a `0x1140` frame with a `0x1000` stack commit and no probe.
  - Nonvolatile-register sentinels and runtime RSP/argument-value probes had not been run.
  - Higher-arity Windows API calls were manually marshalled; a generic checked call builder was still needed.
- Current default-branch re-audit at HEAD `d79873e1941b22f1f9eb1413d58e874d77d54e17` re-confirmed these risks in the present source: compiler blob `ee01ef77b068df5d149934fbf463c43b34c54bf3` (content SHA-256 `c97bd0c4d9ad94b1b4855bbdcd6f843f563f75b35771106ae8976cae2bbda250`); verifier blob `3606b57920043882a2277ad41fd0e0578156944a`.
- `Set-FrameSize` permits frames up to 0x100000; `Emit-Prologue` subtracts the frame size without stack probing; PE stack commit remains 0x1000.
- No exception directory, `.pdata`, or `.xdata` is emitted or validated. The verifier has no unwind-table gate.
- No runtime nonvolatile-register/RSP/stack-argument sentinel suite was run. Higher-arity Windows API marshalling remains manual, with no generic signature-driven checked call builder.
- Classification: **REPOSITORY PRESENT / STATIC REVIEWED**. No runtime ABI failure was reproduced in this session.
- Required gates: large-frame stack probe design/runtime test; x64 unwind metadata generation plus PE validation and unwind-walk tests; nonvolatile register, RSP alignment and argument-slot runtime probes; generic checked Windows API argument marshalling.
- Keep issue #1 open until its baseline and ABI acceptance gates are satisfied.

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
