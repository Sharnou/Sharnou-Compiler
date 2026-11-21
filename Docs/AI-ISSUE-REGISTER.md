# AI Issue Register - Sharnou Compiler

**Last reviewed:** 2026-11-20 22:49 Africa/Cairo
**Live session tracker:** [Issue #8 - AI Development Plan and Live Session State](https://github.com/Sharnou/Sharnou-Compiler/issues/8)

This register separates active blockers from historical findings. Do not close an issue or mark a risk resolved without the stated evidence.

## Active blockers

### B1 - Exact 83-case Milestone 1-6 regression baseline missing from current branch

- Tracking issue: [#9 - Restore and pin the exact frozen 83-case Milestone 1-6 regression baseline](https://github.com/Sharnou/Sharnou-Compiler/issues/9)
- User reports the cumulative 83 cases passed locally through Milestone 6.
- Current repository README says the imported branch did not include the 83 test scripts and fixture directories.
- Required: recover the exact accepted package, compare file-by-file and hash-by-hash against the historical R25-R4/R26.0 archive in issue #1, restore a pristine baseline and manifest, then rerun 83/83 on Windows.
- **Status: BLOCKED.**

### B2 - Milestone 7A Windows acceptance not yet recorded

- Tracking issue: [#10 - Milestone 7A native control-flow verification](https://github.com/Sharnou/Sharnou-Compiler/issues/10)
- Implementation commit: `943d24d857b89b9b30a426c8fb4025c05413d6a8`.
- Test file: `Tests/Test-Stage7A.ps1`.
- Current test inventory: eight positive examples, twelve negative cases, and native instruction/branch encoding checks.
- Required: run 64-bit Windows PowerShell 5.1 in an interactive desktop session; capture every test label, totals, output, exit code, compiler/verifier hashes, and commit SHA.
- **Status: IMPLEMENTATION PRESENT; WINDOWS ACCEPTANCE NOT CONFIRMED.**

### B3 - Self-hosting gate not yet met

- Tracking issue: [#8 - AI Development Plan and Live Session State](https://github.com/Sharnou/Sharnou-Compiler/issues/8)
- Do not generate the full compiler-in-Sharnou implementation until 7A runtime verification and exact frozen 83-case regression restoration/replay are complete.
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
- These findings must be re-audited against the actual current compiler before self-hosting or more complex Engine APIs. They are historical issue findings, not defects newly reproduced in this session.
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
