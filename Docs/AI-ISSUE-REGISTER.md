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

 
## Milestone 7A local regression repair - 2026-11-25

- User-provided Windows log: Stage 5 24/25 because `Tests\\StdLib\\Collections.sharnou` is missing; Stage 7A 27/28 because the `BranchConditionCodes` case returned 6 of 13 expected output lines. Other displayed gates passed: Engine foundation 5/5, builds 22/22, runtime examples 15/15, Stage 2 25/25, Stage 4 20/20, PE verifier 4/4, Stage 6 9/9.
- PR #15 restores the canonical M6 `StdLib/Collections.sharnou` module, provides a legacy `Tests/StdLib` import shim, and adds a native 13-line branch-boundary reproducer.
- Windows Actions run 45696244484 on PR #15 head `01fd2d7b6bd6ab4d80a920449bc529fa865634e8`: 24/24 Stage 7A, 2/2 collection-import tests, source encoding PASS, Combined result PASS.
- The original local `BranchConditionCodes.sharnou` and expanded local `Test.ps1` were not supplied. The equivalent new test passes; a compiler defect is therefore NOT established. Keep the original local result classified as user-reported failure until those exact files can be compared.
- PR #15 remains open/unmerged. No default-branch source changes or baseline integration are claimed.

 
### BranchConditionCodes failure follow-up - 2026-11-25

- Local failing executable link record: 1 module, 0 functions, 1,171 code bytes, 57 data bytes; local output shows only six labels.
- PR #15's independent 13-output equivalent generated 3,573 code bytes and 275 data bytes; Windows runtime output matched all 13 expected labels.
- Distinct output strings are stored in the generated data section, so the local 57-byte data section strongly suggests the local binary did not contain the seven additional labels. This makes an incomplete/stale test fixture or an untested local syntax path more likely than a general signed-Jcc lowering defect. The exact local source remains required for final root-cause attribution.


## 2026-11-25 user-local Milestone 7A validation

- Source snapshot: PR #15 head `de4e64e3f45bc142391886033c33a825722a6eca`.
- User-reported Windows run: Stage 7A 24/24 (9 positive, 12 negative, 3 native instruction/branch checks); Stage 5 collection-import regression 2/2; Combined result PASS.
- Native build/run: 9/9 control-flow executables built and PE-verified; 9/9 returned exit code 0 with expected output. BranchConditionCodes emitted all 13 expected lines; canonical and legacy collection imports both passed.
- The eight PowerShell `InputObjectNotBound` errors came from piping `Get-ChildItem` results into the parameterless `Test.ps1`; they are not compiler/test-case failures. Run `Get-ChildItem ...` and ` .\Test.ps1` separately.
- Frozen M1-M6 83-case baseline was not run in this log; issue #9 / PR #11 remain separate and unmerged.
- Issue #1 remains open: static review of this compiler snapshot still shows no large-frame stack probing and no PE x64 unwind metadata. Microsoft documents stack probing for fixed allocations at least one page and unwind tables for non-leaf functions. These are static ABI gaps, not failures reported by the current M7A run.
- README and accepted-plan test counts are updated to 9 positive + 12 negative + 3 instruction checks = 24, plus the separate 2-case collection import regression.

## Windows x64 stack-probe and unwind repair - 2026-11-25

- PR [#16](https://github.com/Sharnou/Sharnou-Compiler/pull/16) implements the missing page-by-page stack probe and PE x64 unwind metadata.
- Compiler now emits a private leaf page-probe helper called before fixed stack allocation; `.pdata` / `.xdata` and the exception directory describe the entry function and generated user functions; function epilogues use LEA / POP / RET.
- PE verification now validates six sections, exception-directory coverage, runtime-function entries, both UWOP_ALLOC_LARGE forms, frame/prologue consistency, stack-probe helper bytes and relative branch targets.
- Windows Actions run [45705513598](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45705513598) on PR #16 head `b1365dc17bb5aeaad74462633fadfdc29b56fa3e` passed ASCII/no-BOM, Stage 7A 24/24, Stage 5 collection imports 2/2, stack-probe/unwind 6/6, and Combined result PASS. The 17,000-local native test executable ran with expected output and exit code 0.
- This is **WINDOWS CI PASS**. User-local test evidence remains from the pre-ABI PR #15 snapshot; local retest of PR #16 has not yet been reported. PR #16 remains open/unmerged.
- Issue #1 is partially resolved. Runtime nonvolatile-register sentinels, RSP/call-site alignment and argument-value probes, and a generic checked Windows API marshaller remain open. The 83-case M1-M6 baseline remains separately blocked under issue #9 / PR #11.

 
## Runtime ABI gate completion - 2026-11-26

The following ABI runtime tranche is implemented on the PR #17 integration branch. Code-bearing commit `8c14261c3b2154dc115f935271f93389637246e1` passed Windows CI:

- Stage 7A: 24/24.
- Stage 5 collection imports: 2/2.
- Stack-probe/unwind: 6/6.
- Runtime ABI suite: PASS, including runtime sentinels for RBX/RBP/RSI/RDI/R12-R15, live RSP alignment assertions, argument-value checks for 4/5/6/8 integer arguments, nested argument ordering, and higher-arity Win32 API calls.
- Frozen M1-M6 baseline: 83/83 on the same PR head.
- Combined result: PASS.

Windows evidence:
- Stage 7A / combined run: [45717111101](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45717111101).
- Frozen M1-M6 run: [45717111040](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45717111040).

The compiler now supports up to 16 integer arguments for generated Sharnou functions (four register arguments plus twelve stack arguments), reserves Windows x64 shadow space, and maintains 16-byte call-site alignment. The generic `Emit-Win64CallIat` stack marshaller is used for CreateFileA, ReadFile, CreateWindowExA, PeekMessageA, CreateThread, WriteFile, and both D3D11CreateDeviceAndSwapChain paths. Runtime file/window/thread probes exercise the relevant calls. The M1-M6 runner sets a process-scoped legacy arity compatibility flag only while replaying the historical suite; the normal compiler remains enabled for 16 arguments.

PR #17 remains OPEN and UNMERGED. This is Windows CI evidence, not user-local Windows validation. Issue #1's requested runtime ABI tranche is complete in CI; R25-R4 archive equivalence and human review remain separate provenance/integration gates.

### Next dependency: secure native process broker

The broker security design is now recorded in `Docs/SHARNOU-DEVAGENT-PROCESS-BROKER-SECURITY-DESIGN.md`. It defines a typed `sh_dev_run_tool(tool_id, timeout_ms)` API, immutable tool descriptors, SHA-256 allowlisting, canonical workspace confinement, restricted execution, suspended process creation, Job Object containment, timeout/cancellation, bounded output, and adversarial tests.

The historical PR #7 raw-command process intrinsic remains rejected and must not be reused. Native broker phase 1 is implemented on isolated PR #18; the full production security boundary remains incomplete and model-controlled process execution remains DISABLED.


## Issue #14 - DevAgent autonomous development broker status - 2026-11-26

PR #18 head `2ee44cef7f3d67b4ccdc26aa391a9e789197197b` passed Windows CI:
- Runtime ABI suite PASS: nonvolatile register sentinels, live RSP alignment, argument-value tests and higher-arity Windows API marshalling.
- Frozen M1-M6 regression 83/83 PASS.
- DevAgent broker phase 1 PASS: explicit opt-in, six immutable tool IDs, pinned manifest, per-script runtime hashes, workspace/reparse checks, suspended process creation, Job Object containment, timeout and descendant termination. Manifest tamper, script tamper and junction tests pass.

Evidence: Stage 7A / combined [45724983298](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45724983298); frozen baseline [45724983299](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45724983299); draft PR [#18](https://github.com/Sharnou/Sharnou-Compiler/pull/18).

Status: PHASE 1 IMPLEMENTED; NOT PRODUCTION-SECURE / NOT MODEL-ENABLED. Remaining blockers: native CNG hashing, complete canonical path/ancestor confinement, restricted token or AppContainer with workspace ACLs, clean environment and DLL search policy, bounded stdout/stderr capture, cancellation, and durable evidence journal/restart recovery. Keep model-controlled process execution disabled until every gate passes.



## Issue #14 - latest ABI and secure broker verification - 2026-11-26

This entry supersedes the earlier 2ee44... status note. Integrated PR #18 head `7a15892a944c747f9563961d7c050c909dd3d3a4` passed Windows CI:
- Stage 7A 24/24; Stage 5 collection imports 2/2; stack probe/unwind 6/6.
- Runtime ABI PASS, including RBX/RBP/RSI/RDI/R12-R15 sentinels, live RSP alignment, values/nested ordering for 4/5/6/8/16 integer arguments, and fail-closed rejection of 17 parameters and 17 call arguments.
- Frozen M1-M6 baseline 83/83.
- Native DevAgent broker phase 1 PASS: default-disabled typed API, six immutable test-tool IDs, pinned manifest, CNG SHA-256 before process launch, open file handle retained during execution, image-relative workspace discovery independent of CWD, path and opened-file reparse checks, suspended launch, Job Object limits, timeout and descendant termination.

Evidence: combined Windows run [45772104864](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45772104864); frozen baseline [45772104661](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45772104661); PR [#18](https://github.com/Sharnou/Sharnou-Compiler/pull/18).

Status: PHASE 1 IMPLEMENTED / SECURITY ACCEPTANCE INCOMPLETE. Native CNG hashing and image-relative workspace derivation are implemented and tested. Remaining blockers are complete final-path/ancestor canonicalization, ADS/UNC/device-path rejection, restricted token or AppContainer plus workspace ACLs, clean environment/DLL-search policy, bounded stdout/stderr capture with explicit handle list, cooperative cancellation, and durable evidence journal/restart recovery. The broker is still test-build opt-in; model-generated process execution remains DISABLED. PR #18 stays draft and unmerged.

## 2026-11-26 AppContainer/ACL/output-capture follow-on

- Branch `devagent-appcontainer-acl-output-20261126` contains a narrow, unmerged scaffold tranche after phase-1 PR #18: corrected IAT RVAs for `CreateAppContainerProfile`, `DeriveAppContainerSidFromAppContainerName`, `GetNamedSecurityInfoA`, `SetEntriesInAclA`, and `SetNamedSecurityInfoA`; extended PE verifier expected imports for USERENV/ADVAPI32; added static checks for helper declarations and import target mapping.
- The helper functions do not yet participate in the live `Emit-DevRunTool` path. There is no runtime proof of restricted-token execution, AppContainer process creation, workspace ACL enforcement/revocation, or bounded output capture.
- This is scaffolding only, not completion. The broker remains test-only opt-in and model-facing process execution remains DISABLED.
- Do not merge, promote, or describe this phase as security-accepted. Next work must implement the full suspended child flow with restricted primary token + no-capability AppContainer, exclusive/verified workspace grants, race-safe ACL cleanup and crash recovery, STARTUPINFOEX handle-list stdout/stderr capture with a strict output cap, Job Object termination/wait checks, plus adversarial Windows CI. Sanitized environment/DLL-search policy and durable evidence journaling are still separate hard gates.

## 2026-11-26 - live AppContainer / restricted-token / bounded-output candidate

Branch `devagent-sandbox-runtime-20261126` now wires the previously helper-only AppContainer and ACL work into the live native `Emit-DevRunTool` emitter. The source also includes restricted primary-token creation and token verification before resume, STARTUPINFOEX handle-list isolation, a strict combined stdout/stderr capture buffer, exact 1 MiB read clamping, and Low IL mandatory-label application on the writable Build staging directories.

Source-level checks completed:
- IAT and import lookup arrays were re-audited across all 16 descriptors, including zero terminators; no overlap or unmapped native call target was found.
- The Build-only mandatory-label policy and exact output-cap path have static assertions in `Tests/Test-DevAgentBroker.ps1`.
- New probes cover writing within Build, denied write in Tests, and 1 MiB + 1 byte combined output.

This is not a Windows CI pass. Do not infer runtime isolation from source review. The new branch still requires Windows tests proving: AppContainer token identity, zero capabilities, Build write success / source write denial, output capture exact-cap and overflow termination, Job Object emptiness, cleanup and repeat-run behavior.

Residual hard blockers:
1. Persistent AppContainer profile SID and persistent DACL grants have no per-run identity or durable crash-recovery/rollback transaction. A broker crash can leave stale access.
2. The child inherits the broker environment. A sanitized environment and DLL search hardening are still required.
3. Full canonical final-path and race-free ancestor confinement are not complete.
4. Network denial and explicit cancellation need adversarial runtime tests.
5. Windows runtime CI has not yet passed on this branch.

Status: **IMPLEMENTATION CANDIDATE / NOT SECURITY-ACCEPTED / NOT MODEL-ENABLED**. Keep the test broker behind explicit opt-in. Model-facing process execution stays DISABLED. Do not merge or release based on static checks alone.

## 2026-11-26 abandoned ACL mutex guard

The native broker no longer treats `WAIT_ABANDONED` as an ordinary lock acquisition. It returns `-118`, releases the mutex, and skips AppContainer SID creation, ACL mutation, and child process creation. A static regression assertion checks this branch ordering. This prevents another model tool from running on potentially inconsistent ACL state after a crashed broker.

This is only fail-closed detection. It does not restore ACLs or remove stale package-SID ACEs. Durable ACL transaction journaling and startup recovery remain a security gate. No model-facing execution is enabled.


## 2026-11-27 - Phase 2B.6 production broker integration gate

Phase 2B.6 is IN PROGRESS / BLOCKED on PR #24 branch devagent-acl-transaction-recovery-20261126. The M6 baseline passed 83/83 (45964360562); Stage 7A failed (45964360481) in native post-crash ACL journal recovery.

The failure result -2685 decodes from the emitter's status formula to ERROR_ACCESS_DENIED (5) for both the GENERIC_READ journal open and metadata-only fallback. A separate PowerShell CreateFileA control can open the journal. The exact native path is being added to the CI diagnostic output; no DACL broadening, journal deletion, caller-token fallback, or other security weakening is permitted as a workaround.

Acceptance requires: repair and adversarially validate journal recovery; unique per-execution AppContainer SID/profile with crash cleanup; an explicit bounded allowlisted Unicode environment (lpEnvironment must not be NULL); production integration of the Phase 2B.5 handle allowlist and independent bounded stdout/stderr capture; child DLL-search hardening; final-object/path verification; actual PE import-table validation; and same-head Windows regressions including M6 83/83 and Stage 7A.

**Model-facing and autonomous process execution remain DISABLED.**


## Phase 2B.8 implementation start - 2026-11-27

- Implementation tracker: issue [#25](https://github.com/Sharnou/Sharnou-Compiler/issues/25); specification PR [#26](https://github.com/Sharnou/Sharnou-Compiler/pull/26).
- Reconciled parent candidate: PR #24 at exact head `6344632746cd0666025a0beb0d31f4752d6480f6`. Windows run [46003358917](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46003358917) passes targeted recovery on that head; companion [46003358930](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46003358930) passes M1-M6 83/83. These results do not qualify the full lifecycle.
- PR #24 is the Phase 2B.6 integration parent. No separately recorded complete Phase 2B.7 lifecycle implementation/acceptance was found in the current candidate documentation. Do not assume Phase 2B.7 complete.
- New stacked implementation PR [#28](https://github.com/Sharnou/Sharnou-Compiler/pull/28) adds a Windows-only identity primitive fixture using CNG random IDs, CreateAppContainerProfile with zero capabilities, SID derivation, strict no-adoption of existing profiles, and deletion/recreation proof. It is based on the exact PR #24 head and does not modify PR #24.
- **Fixture status: NOT YET WINDOWS-CI-VERIFIED.** No compiler-emitted broker source or import table was changed in this increment. Stable production AppContainer identity remains a blocker.
- Follow-up blockers: authenticated journal before persisting profile metadata for privileged recovery; production unique identity and profile cleanup; clean Unicode environment; distinct bounded stdout/stderr; child DLL-search policy; exhaustive crash-cut and concurrency tests; independent evidence verifier.
- Keep model-facing process execution DISABLED and all related PRs draft/unmerged.


## Phase 2B.8 qualification update - 2026-11-27

- Windows identity and DPAPI/schema primitive suite passed on code-bearing commit `907281187ffdf9223d4b345a2847c2a1feb883cf`: run [46021589016](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46021589016). Eight actual suspended AppContainer child tokens inspected with unique SIDs, Low IL and zero capabilities; eight profiles normal-deletion verified; DPAPI envelope and strict v2 parser negative cases passed.
- Frozen M1-M6 baseline passed 83/83 on that exact code commit: [46021589107](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46021589107).
- Stage 7A combined run [46021589123](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46021589123) was still running at the last status check. Do not mark full combined suite accepted until final logs are checked.
- New threat-boundary record: `Docs/PHASE-2B8-JOURNAL-TRUST-BOUNDARY.md`. DPAPI CurrentUser plus optional entropy is not per-process writer authentication against another process running as the same user. A different protected trust anchor is required before native journal integration.
- Production broker unchanged: stable shared AppContainer profile, v1 ACL journal, inherited environment, merged stdout/stderr. Clean environment, unique production identity, crash-time profile deletion, native journal integration, DLL hardening and full crash matrix remain open. Model execution remains DISABLED.


### Same-user DPAPI writer-boundary proof - 2026-11-27

- Run [46022134602](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46022134602) passed the latest dedicated Windows identity/journal primitive suite on `a64b81def96b22315b8ab8034bb60c4af1870e32`.
- The fixture explicitly demonstrates same-user DPAPI re-protection: a different valid v2 payload can be protected with the same public optional entropy and unprotected. DPAPI user scope is therefore not sufficient writer-process authentication when malicious same-user processes are in scope.
- The native journal/profile integration gate remains blocked until a separate trust anchor and recovery authority are selected and reviewed. See `Docs/PHASE-2B8-JOURNAL-TRUST-BOUNDARY.md`.


### Phase 2B.8 latest hardening awaiting CI

- Changed the synthetic workspace identity to `FILE_ID_INFO` semantics (64-bit volume serial + 128-bit `FILE_ID_128`) and added an all-zero file-ID rejection case.
- Changed the same-user DPAPI forge test to spawn a distinct Windows PowerShell process; parent then decrypts the child-created envelope. This explicitly proves cross-process same-user minting rather than same-process API reuse.
- Exact-head CI for this revision is pending; do not count these latest changes as verified until the run passes.


### Latest Phase 2B.8 fixture evidence - 2026-11-27

- Run [46024410650](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46024410650) passed the new FILE_ID_INFO schema and separate-process DPAPI writer proof on code commit `fc479378a818bc759f298361c6a298e6c143118e`.
- The v2 test schema uses 64-bit volume serial + full 128-bit FILE_ID_128. A separate same-user PowerShell child minted a different valid DPAPI envelope with public entropy; the parent unprotected it. DPAPI CurrentUser is therefore definitively not per-process writer authentication.
- M1-M6 83/83 passed on latest head `cb0551dd1d272deb3c12aab9b5131cc3fb6ed2fb`, run [46024435843](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46024435843).
- Full Stage 7A combined test run [46024435792](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46024435792) remained in progress at last inspection, including a new actual AppContainer child DPAPI characterization probe.


### Explicit Unicode environment primitive - 2026-11-27

- Run [46025925905](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46025925905) passed the new bounded environment builder fixture: 9 entries / 354 UTF-16 code units; CreateProcessW accepted explicit Unicode block; Windows core variables correct; hidden drive entries validated/preserved; parent secret absent.
- Frozen M1-M6 run [46025925771](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46025925771) passed 83/83 on exact head `6277f28123b28b56e2710f50d7197239fd034529`.
- This does not yet qualify the actual AppContainer/restricted-token `CreateProcessAsUserW` path or modify compiler-emitted broker; do not claim Win32 203 closed for production.
