# AI Session State - Sharnou Compiler

**Last updated:** 2026-11-20 22:49 Africa/Cairo
**Repository:** `Sharnou/Sharnou-Compiler`  
**Branch:** `Sharnou-Compiler`  
**Purpose:** Latest durable status for every future AI-assisted compiler/Engine generation, debugging, testing, and repair session.

> This file is the live status snapshot, not a claim that the AI can monitor the repository in the background. Update it at the end of every completed AI work session.

## Current status at a glance

- **Accepted project direction:** self-contained Sharnou compiler, PE32+ linker, runtime/standard library, Engine, IDE, and Honour War for Windows x64.
- **User-reported completed history:** Milestones 1-6 passed on the user's Windows PC.
- **Current development focus:** Milestone 7A - native control flow (if/else, while, signed comparisons).
- **Persistent AI status tracker:** [GitHub issue #8](https://github.com/Sharnou/Sharnou-Compiler/issues/8); update its body and this file after every completed AI generation/repair session.
- **Actionable blockers:** [Issue #9 - restore exact 83-case baseline](https://github.com/Sharnou/Sharnou-Compiler/issues/9); [Issue #10 - Milestone 7A Windows acceptance](https://github.com/Sharnou/Sharnou-Compiler/issues/10).
- **Milestone 7A repository implementation:** present on the `Sharnou-Compiler` branch; implementation commit `943d24d857b89b9b30a426c8fb4025c05413d6a8`.
- **Plan-map documentation commits:** `c403b4b725200000ba89944798a4bcca618c9885` (AI preflight), `5a5b2c89d0c0c0a4d85bb4111ecb145a83be7cb9` (master plan), `aeb086429bc98e5094bf4d881c02b9100e4cb893` (issue register), and `e47dd7d5634ed5ccc9302d2d59241790f6de3bdc` (README links). The current state file was subsequently updated to include GitHub issue numbers.
- **Milestone 7A Windows acceptance:** NOT CONFIRMED by the user in the current status record. Do not claim it passed.
- **Frozen 83-case repository baseline:** BLOCKED / not included in the current branch according to the current README. The user previously reported 83 cases passed locally, but the branch must contain the exact source suites and fixtures before the repository can independently rerun them.
- **Next action:** reconcile and restore the exact 83-case suite, then run the complete 7A and frozen baseline tests on 64-bit Windows PowerShell 5.1; record logs, exit codes, and hashes.

## Verified project history (as reported by the user)

| Stage | User-reported result | Evidence classification |
|---|---|---|
| Milestone 1 | Hello.exe built and ran; output "Hello, Sharnou!", exit 0. SHA-256: `6CA5B29FDE63330258C5B4D349C63A27A2D4CB3FA57F07D4375BA6D4F2878F96`. | USER-REPORTED WINDOWS PASS |
| Milestone 2 | Hello and Arithmetic built and ran; 18 tests passed, 0 failed. | USER-REPORTED WINDOWS PASS |
| Milestone 3 | Native arithmetic and runtime variable mutation worked; 25 tests passed, 0 failed. | USER-REPORTED WINDOWS PASS |
| Milestone 4 | Six examples built, PE-verified, and ran; Stage 2 25/25, Stage 4 20/20, PE verifier 4/4. | USER-REPORTED WINDOWS PASS |
| Milestone 5 | Engine preflight 5/5; 12 example/Engine builds passed; Stage 5 25/25; combined PASS. | USER-REPORTED WINDOWS PASS |
| Milestone 6 | Engine preflight 5/5; 12 builds passed; Stage 6 9/9; combined PASS; user confirmed real 60-frame D3D11 window/device/swap-chain/render-target clear/present loop. | USER-REPORTED WINDOWS PASS |

The cumulative regression count is 83: Stage 2 (25) + Stage 4 (20) + PE verifier (4) + Stage 5 (25) + Stage 6 (9).

## Milestone 7A accepted scope

Implement actual native x64 control flow while preserving the existing Windows x64 function calling convention and stack-frame layout.

### Required language behavior

- `if` / `else`.
- `while`.
- Signed integer comparisons `<`, `>`, `<=`, `>=`, `==`, `!=`.
- Nested if/while structures.
- Runtime variable mutation and terminating loops.
- Correct behavior at signed integer comparison boundaries.
- Positive and negative tests for syntax, typing, diagnostics, and execution.
- Preserve prior functions, modules, arithmetic, PE imports, relocations, verifier, standard library, and D3D11 code.

### Condition semantics and documented restrictions

- Integer zero is false; any non-zero integer is true.
- Comparisons yield normalized 0 or 1.
- Nested blocks use lexical scope and each local retains its unique slot in the existing stack-frame allocator.
- Current documented restrictions: no chained comparisons, string comparisons, logical AND/OR, else-if shorthand, or return nested within a control-flow block. Unsupported constructs must be rejected with a line/column diagnostic.
- Preserve the Windows x64 ABI: argument registers, 32-byte shadow space, 16-byte call-site stack alignment, frame pointer, local slots, and function-call behavior.

### Expected native code generation

- Evaluate comparison operands, preserve one in a temporary slot, compare with `CMP`.
- Use signed `SETcc`: `SETL`, `SETG`, `SETLE`, `SETGE`, `SETE`, `SETNE`; normalize with `MOVZX EAX,AL`.
- Test conditions with `TEST EAX,EAX`.
- Generate near conditional branches (`JZ rel32`) and near unconditional branches (`JMP rel32`).
- For a while loop, branch to exit on false and jump back to the condition label after the body.
- Patch branch displacements in a dedicated fixup pass and reject out-of-range or unresolved fixups.

### Repository files observed

- `README.md` documents Stage 7A semantics and known restrictions.
- `Stage0/SharnouCompiler.ps1` contains the compiler source on the current branch.
- `Tests/Test-Stage7A.ps1` declares eight positive and twelve negative cases plus machine-code checks.
- `Examples/ControlFlow/` is the documented fixture root.
- Commit implementing Stage 7A: `943d24d857b89b9b30a426c8fb4025c05413d6a8`.

The existence of these files is repository evidence only. The user's Windows test result for 7A must be recorded separately when supplied.

## Current known blockers and risks

### B1 - Frozen 83-case suite absent from this branch

The current README explicitly states that the Milestone 6 branch imported for this work did not contain the 83-case source suites or fixture directories. The user's earlier local pass is retained as reported history. Before claiming preservation of 83 tests on this branch, recover/pin the exact test scripts and fixtures (including their SHA-256 values), add them without altering their semantics, run all 83 on Windows, and store the run report.

Tracking issue: [Issue #9 - Restore and pin the exact frozen 83-case Milestone 1-6 regression baseline](https://github.com/Sharnou/Sharnou-Compiler/issues/9). Related existing issue: [Issue #1 - R26.0 baseline / ABI audit](https://github.com/Sharnou/Sharnou-Compiler/issues/1). It describes a pinned R25-R4 baseline and ABI audit; do not assume its 83 cases are identical to the user's M1-M6 package without comparing archive contents and hashes. Keep that historical issue open until its scope is reconciled.

### B2 - Stage 7A Windows verification not recorded yet

Tracking issue: [Issue #10 - Milestone 7A Windows acceptance](https://github.com/Sharnou/Sharnou-Compiler/issues/10). Run `Tests/Test-Stage7A.ps1` through the repository `Test.ps1` on 64-bit Windows PowerShell 5.1 in an interactive desktop session. Capture all case outputs, exact pass/fail totals, exit code, compiler SHA-256, verifier SHA-256, branch and commit SHA. The current README expects eight positive programs, twelve negative programs, and instruction/branch encoding checks.

### B3 - ABI audit items in historical Issue #1

Issue #1 records risks that must be rechecked against the current compiler before self-hosting: missing PE unwind metadata for non-leaf functions, missing large-frame stack probing, incomplete nonvolatile-register/runtime ABI probes, and manually marshalled higher-arity Windows API calls rather than a generic signature-driven call builder. These are historical issue findings, not newly reproduced defects in this session. Do not silently mark them fixed.

### B4 - Self-hosting not yet demonstrated

No claim of a native self-hosted SharnouCompiler.exe is recorded here. Before M7 self-hosting, finish and verify control flow, restore the 83-case baseline, inventory the exact compiler source language requirements, then define the 7B+ plan.

## Constraints for all fixes

- Do not use MSVC, Clang, Visual Studio, MSBuild, external assembler, external linker, downloaded compiler, package installation, or another toolchain as a hidden fallback.
- Keep compiler output a genuine x64 PE32+ executable generated by Sharnou's own backend/linker.
- Keep PE imports, IAT, relocations, dynamic section layout, PE verifier, and Windows system DLL boundaries correct.
- Preserve current function calling convention and stack frame unless a separately reviewed ABI change is explicitly accepted.
- Fail closed on unsupported syntax, invalid types, unresolved labels/symbols, bad PE layout, missing APIs, arithmetic/branch errors, or unverified capabilities.
- Every new feature needs positive and negative tests.
- Keep source and scripts ASCII / UTF-8 without BOM.
- Do not claim test success without native Windows/CI evidence.

## Mandatory next-session checklist

1. Read `AI_START_HERE.md`.
2. Read `Docs/AI-SESSION-STATE.md` (this file), `Docs/AI-DEVELOPMENT-PLAN.md`, and `Docs/AI-ISSUE-REGISTER.md`.
3. Read current `README.md`, renderer roadmap if relevant, actual current compiler, PE verifier, `Test.ps1`, Stage 7A tests, and the frozen baseline if present.
4. Inspect current branch, latest commit, open issues, PRs, and CI/test evidence.
5. Resolve B1 and B2 before moving to the native self-hosting compiler.
6. Only then generate or repair source files.
7. At session end, update this state file, plan map if scope/status changed, issue register, and the dedicated GitHub AI status issue.

## Latest session entry - 2026-11-20

- User accepted the Milestone 7 readiness audit: control flow must precede self-hosting.
- User explicitly accepted Milestone 7A requirements: if/else, while, six signed comparisons, native x64 branches, preservation of the calling convention/frame, preservation of 83 regressions, positive/negative edge tests, ASCII/no BOM, and no external native toolchain.
- Repository review found Stage 7A implementation commit `943d24d` and a Stage 7A test runner; repo README simultaneously notes the 83 source suites/fixtures are not present on this branch.
- This session adds `AGENTS.md`, `AI_START_HERE.md`, `Docs/AI-DEVELOPMENT-PLAN.md`, `Docs/AI-SESSION-STATE.md`, `Docs/AI-ISSUE-REGISTER.md`, README links, and tracking issues #8, #9, and #10. It does not modify compiler source.
- Future sessions must read the source-of-truth files before any code generation or repair, then update `Docs/AI-SESSION-STATE.md` and issue #8 with the new result.
- Next: capture M7A Windows acceptance and reconcile/restore the exact 83-case baseline before starting 7B self-hosting source generation.


## Repository and automation status update - 2026-11-20 22:39 Africa/Cairo

This update records the live GitHub state reviewed for the user's request to keep an authoritative plan map, save each AI generation/repair status, track unresolved issues, and require a read-first review before future source work.

### Current branch and Milestone 7A evidence

- Default development branch: `Sharnou-Compiler`.
- Branch HEAD at review: `fc015ba925c001e1f647f3897736f6f4bd64f0dc`.
- Stage 7A implementation commit: `943d24d857b89b9b30a426c8fb4025c05413d6a8`.
- Windows Actions run `44813123428` completed with conclusion `success` on `windows-latest`, at HEAD `fc015ba925c001e1f647f3897736f6f4bd64f0dc`. The job passed source-encoding validation and ran the Stage 7A test entry point. This is **WINDOWS CI PASS**, not a user-local test report.
- Stage 7A declares 8 positive runtime cases, 12 negative diagnostic cases, and 3 instruction/branch encoding checks (23 total). The user has not supplied a separate local 7A run result in this session.

### Open pull requests and evidence boundaries

- **PR #6 - Restore frozen Milestone 6 83-case regression baseline.** Feature branch `automation/restore-m6-83-regression`; head `9dfe1bc09685a6f7deb9d29b5192b1aae0686039`; Windows run `44700641397` succeeded. PR evidence reports 83/83: Stage 2 (25), Stage 4 (20), PE verifier (4), Stage 5 (25), Stage 6 (9). It pins the Milestone 6 package SHA-256 `0b6bf15445a5dfd8cbf93450af7fd2f5fd6239d4ed082ab18b09878a94b8b164`. The PR preserves the original archived tests/fixtures and uses an isolated compatibility adapter for the Stage 2 fixture whose old negative expectation became supported by Stage 7A. **PR is open and unmerged**; the 83-case suite is not yet part of this default branch.
- **PR #5 - Milestone 7B Boolean and control-flow semantics.** Feature branch `automation/milestone-7b-boolean-loop-return`; head `0b8dee87b699eabcaaac37f111686231fb29a82c`; Windows run `44693097619` succeeded. PR reports Stage 7A 23/23 and Stage 7B 32/32. It proposes Boolean values, short-circuit logical operators, break/continue, and nested returns. **It remains open and unmerged.** These additions are not recorded as user-accepted scope by this session; do not merge or silently treat them as approved.
- **PR #7 - Native SharnouDevAgent test/development utility.** Draft PR on `automation/sharnou-dev-agent-native`; head `ac3849800412b1208acb540ef090ffb3ac0455ca`; Windows run `44758761226` succeeded through native example build/run, control-flow regressions, DevAgent run, and artifact upload. The PR explicitly describes this as a native test orchestrator, **not an AI source-generating agent**. It remains open and draft.
- **PR #4 - Complete compiler/Engine roadmap and production automation gates.** Open, unmerged documentation/workflow proposal. Do not assume its scheduled GitHub workflow or PR contents are active on the default branch until merged.
- No pull request was merged or modified during this review.

### Open issues and carry-forward risks

- **Issue #8** remains the canonical AI development/status tracker.
- **Issue #9** remains open because PR #6 is not merged into the default branch, even though its feature branch has a successful Windows 83/83 run.
- **Issue #10** remains open for the Stage 7A acceptance record and the relationship to the restored frozen baseline. The default-branch Stage 7A Windows CI run is now green; retain this as CI evidence and do not mislabel it as the user's local report.
- **Issue #1** remains open for historical Windows x64 ABI and baseline findings: PE unwind metadata, large-frame stack probing, nonvolatile-register/stack/argument runtime probes, and generic checked marshalling for higher-arity Windows API calls. These are historical findings to re-audit, not newly reproduced failures in this review.
- Native self-hosting is not demonstrated. Do not generate the full compiler-in-Sharnou implementation until the accepted control-flow and frozen-baseline gates are reconciled and the source-language gap analysis is completed.

### Persistent read-first and save-after-work protocol

Before every future AI source generation, bug diagnosis, test repair, compiler/PE/ABI/Engine change, or issue triage, read the current branch versions of:
1. `AGENTS.md`
2. `AI_START_HERE.md`
3. `Docs/AI-SESSION-STATE.md`
4. `Docs/AI-DEVELOPMENT-PLAN.md`
5. `Docs/AI-ISSUE-REGISTER.md`
6. `README.md`
7. The exact compiler, verifier, fixtures, tests, renderer roadmap, and open issue/PR context relevant to the requested task.

At the end of each completed AI work session, persist the source paths changed, branch/commit/PR, compiler/verifier/source hashes, exact test totals and outputs, exit codes, evidence classification, blockers, and next action. Update this state file and Issue #8. Update the issue register and create/update actionable GitHub issues when new defects are found. Update the master plan only when accepted scope, dependency order, or milestone status changes. A no-code session must explicitly say that no compiler source was changed and no tests were run by the assistant.

### Automation status and limits

- Existing enabled task automation **Sharnou DevAgent Progress** runs daily.
- Existing enabled task automation **Advance Sharnou Stack** runs weekly.
- Three legacy Honour War daily-upgrade automations remain disabled; do not reactivate them.
- The repository's read-first rule applies to manually initiated AI work; the scheduled tasks are additionally instructed to read and persist the state on every scheduled run.
- There is no event hook that can observe every arbitrary ChatGPT message or guarantee a background save immediately after every user turn. Do not promise unattended, per-message monitoring. Scheduled runs and the mandatory per-session update protocol are the available persistence mechanisms.

### Work performed in this session

- Read the repository's mandatory agent instructions, AI preflight, plan, state, issue register, and README.
- Inspected branch HEAD, open issues, open PRs, Windows Actions runs/jobs, and existing task automations.
- No compiler, PE verifier, example, or test source was generated or modified.
- No native build or test was executed by the assistant. All run results above are GitHub Actions evidence from the linked runs.
- Updated only the project status/governance records and the prompts of the two existing enabled Sharnou compiler/stack automations; no PR was merged and no source implementation was changed.

### Next dependency-ordered actions

1. Review PR #6's archived package identity, adapter, manifest, and full Windows 83/83 logs; integrate it only through the repository's review/approval process.
2. Preserve the Windows CI success for Stage 7A and capture any user-local 7A validation separately.
3. Review the scope and compatibility of PR #5 before treating its Stage 7B features as accepted.
4. Re-audit Issue #1 ABI risks against the actual current compiler before larger compiler/runtime work.
5. After the baseline and control-flow gates are accepted, perform the construct-by-construct Milestone 7B/7C language-gap analysis, then stage the self-hosting implementation plan.


## Latest persisted session - 2026-11-20 22:49 Africa/Cairo

**Session type:** Repository state review and documentation/status persistence only.

**Repository:** Sharnou/Sharnou-Compiler  
**Branch:** Sharnou-Compiler  
**Starting HEAD reviewed:** f5a12b7c967370bb511a8d4ec6c8a6b9f9afc4b9

### User-confirmed and accepted

- Milestones 1-6 remain USER-REPORTED WINDOWS PASS. In particular, M6: Engine foundation preflight 5/5; all 12 example/Engine builds pass; Stage 6 D3D11 suite 9/9; actual window, DXGI/D3D11 device and swap-chain, render target, 60-frame clear/present, and fail-closed runtime handling passed locally.
- The user accepted that self-hosting must be preceded by native control flow.
- Milestone 7A is the next accepted implementation: native if/else, while, signed comparisons (<, >, <=, >=, ==, !=), nested control flow, loop termination, runtime mutation, signed integer edge coverage, source-located diagnostics, and fail-closed unsupported syntax.
- Keep the existing Windows x64 ABI and stack layout intact, including argument registers, 32-byte shadow store, stack alignment, frame pointer, local/temporary slots, and function calls. Keep PE/linker/import/relocation/verification behavior and all 83 M1-M6 regression cases.
- No external compiler/toolchain: no MSVC, Clang, Visual Studio, MSBuild, external assembler, external linker, downloaded compiler, or hidden fallback. Source/scripts/tests remain ASCII or UTF-8 without BOM.

### Live repository evidence and open work

- M7A source/tests are present on the default branch. Windows Actions run 44813123428 succeeded; classify this as WINDOWS CI PASS only. No new user-local M7A execution result was supplied in this session.
- Issue #9 remains open: exact frozen 83-case baseline restoration is represented by PR #6, head 9dfe1bc09685a6f7deb9d29b5192b1aae0686039, Windows CI run 44700641397 with 83/83, but PR #6 remains unmerged. The default branch still lacks the integrated frozen baseline according to current project docs.
- Issue #10 remains open until M7A acceptance evidence is captured and reconciled with the 83-case baseline.
- Issue #1 remains open for historical ABI re-audit: PE unwind metadata, large-frame stack probing, nonvolatile-register/runtime probes, and generic higher-arity Windows API call marshalling.
- PR #5's 7B Boolean/logical/break/continue/nested-return changes are proposed, open, and unmerged; they are not accepted scope without further user approval.
- PR #7 is a draft native test orchestrator, not an AI source-generating agent. PR #4 is an open/unmerged roadmap proposal.
- Native Sharnou compiler self-hosting is NOT DEMONSTRATED and must not be claimed.

### Persistence and read-first agreement

Before each future AI source-generation, bug-fix, compiler/linker/PE/ABI/Engine change, test repair, or issue-triage session, fetch and read current branch versions of AGENTS.md, AI_START_HERE.md, Docs/AI-SESSION-STATE.md, Docs/AI-DEVELOPMENT-PLAN.md, Docs/AI-ISSUE-REGISTER.md, README.md, and all task-specific code/tests/fixtures plus open issues/PRs and latest CI evidence.

At the end of each completed session, update this file and GitHub issue #8 with exact changed paths, branch/commit/PR, file hashes, test totals, exit codes/output, evidence category, issues/blockers, and next action. Update the plan map and issue register when accepted scope or blocker status changes. Preserve history; append status rather than silently replacing prior findings.

Daily Sharnou DevAgent Progress and weekly Advance Sharnou Stack task automations are enabled and already include read-first/persist-status prompts. They save on their configured schedule. They do not observe each arbitrary ChatGPT turn; manually started sessions must follow the repository instructions. The GitHub connector does not expose Projects V2 board writes, so the canonical plan map is Markdown plus linked Issues/PRs, not a visual Kanban update.

### Work performed and evidence classification

- Read the live repository instructions, plan, session state, issue register, README, and issues #8-#10.
- Reviewed default branch head and open PR states #4-#7.
- Inspected automation definitions and confirmed the two Sharnou compiler/stack automations are enabled; three legacy Honour War upgrade automations remain disabled.
- No compiler source, examples, tests, or build scripts changed. No build or test was executed by the assistant. This is a documentation/status update, not a source implementation or runtime validation.

### Next dependency-ordered action

Review PR #6 and exact baseline provenance/adaptation; capture user-local M7A verification separately from CI; re-audit issue #1 ABI findings; then complete compiler language-gap analysis before any full self-hosting compiler source generation.


## Scheduled compiler audit session - 2026-11-21 08:43 Africa/Cairo

### Repository and branch evidence

- Repository: `Sharnou/Sharnou-Compiler`.
- Default branch: `Sharnou-Compiler`.
- Starting default HEAD: `8f181ccf533947e41d1ebdfd39a58a02a46667d9`.
- The latest recorded default-branch Stage 7A Windows run is `44813123428`, conclusion `success`, at `fc015ba925c001e1f647f3897736f6f4bd64f0dc`. The six commits from that run to the starting HEAD changed only `Docs/AI-DEVELOPMENT-PLAN.md`, `Docs/AI-ISSUE-REGISTER.md`, and `Docs/AI-SESSION-STATE.md`. Current compiler/verifier/Stage7A-test/workflow blobs match the tested commit.
- Status-only documentation commits from this session: plan `75fd2281d203892c844cea2b70664239fd2af67a`; issue register `8fb0d5d57bcc6d50ac299c1a7175707e073e93d1`. No compiler, verifier, example, test, workflow, Engine, IDE, or game source was changed.

### Pull requests

- **PR #6** - `automation/restore-m6-83-regression`, head `9dfe1bc09685a6f7deb9d29b5192b1aae0686039`; open, unmerged, mergeable. Base `352c65e05524d494970b2d8b52b7089d12d19435`. Compare against current default reports 15 ahead / 15 behind from that common base; the PR diff is five added baseline/runner/workflow paths. Its compiler, PE verifier, Stage 7A test, and Stage 7A workflow blobs are identical to default.
- **PR #5** - `automation/milestone-7b-boolean-loop-return`, head `0b8dee87b699eabcaaac37f111686231fb29a82c`; open, unmerged, mergeable, not user-accepted. It is two commits ahead and 15 behind current default from the same common base. Changes only the compiler, `Test.ps1`, and a new Stage 7B test script.
- **PR #7** - `automation/sharnou-dev-agent-native`, head `ac3849800412b1208acb540ef090ffb3ac0455ca`; draft/open. It is a native test orchestrator proposal, not an AI source-generating agent.
- **PR #4** - `roadmap/compiler-stack`, head `c80828005c069956dca4ab3b045adc8afcce397b`; open/unmerged roadmap and automation proposal.
- Relevant PR #5/#6/#7 discussions and reviews returned no comments or review submissions. No PR was modified, merged, or created.

### Windows Actions evidence

- **Run 44813123428** - default-branch Stage 7A, `success`, at `fc015ba925c001e1f647f3897736f6f4bd64f0dc`; 23/23 (8 positive, 12 negative, 3 aggregate instruction checks). The current code/test/workflow blobs are unchanged from that commit.
- **Run 44700641397** - PR #6 frozen M1-M6 baseline, `success`, at PR head `9dfe1bc09685a6f7deb9d29b5192b1aae0686039`; Stage 2 25/25, Stage 4 20/20, PE verifier 4/4, Stage 5 25/25, Stage 6 9/9; total 83/83. Case-intent classification from the emitted case names: 36 positive, 47 negative. The manifest records suite totals, not polarity labels. The run log includes two encoding PASS lines in addition to the 83 case results; there were zero FAIL lines. The job conclusion is success; a separate process exit-code line was not emitted.
- **Run 44700641419** - PR #6 Stage 7A, `success`, on the same PR head; 23/23 (8 positive, 12 negative, 3 instruction checks), combined PASS. This is the same 7A compiler/verifier/test source as default.
- **Run 44693097619** - PR #5 Stage 7A + proposed Stage 7B, `success`; Stage 7A 23/23 and Stage 7B 32/32 (15 positive, 13 negative, 4 instruction checks). It did not run the 83-case baseline.
- **Run 44758761226** - PR #7 native DevAgent utility, `success`; built the native PE32+ executable, ran Stage 7A 23/23, then ran `SharnouDevAgent.exe` with explicit process exit code 0 and uploaded artifact ID `14654214120`.
- The run query for current default HEAD `8f181ccf533947e41d1ebdfd39a58a02a46667d9` returned no PR-triggered runs; the default-branch combined status response was empty. Do not infer a new run on that exact HEAD.

### Source hashes and static review

- Current default `Stage0/SharnouCompiler.ps1` SHA-256: `c97bd0c4d9ad94b1b4855bbdcd6f843f563f75b35771106ae8976cae2bbda250` (blob `ee01ef77b068df5d149934fbf463c43b34c54bf3`).
- Current default `Tools/SharnouPEVerify.ps1` SHA-256: `953a20c2274eee42eee2523c5608fd48e6dc574e4b5465464e910db560d55179` (blob `3606b57920043882a2277ad41fd0e0578156944a`).
- Current `Tests/Test-Stage7A.ps1` SHA-256: `ffd8a3518d8fc943adb97e319a29a8822d4e5c409226597d0010b40da23eae05` (blob `80d8df1c9a6da7c8fb6f2b414c2929f07ba44804`).
- These files contain only ASCII bytes and no UTF-8 BOM.
- Static 7A audit: comparison nodes save the left operand in a temp slot, use `CMP EAX,ECX`, signed `SETL/SETG/SETLE/SETGE/SETE/SETNE`, then `MOVZX EAX,AL`. Conditions use `TEST EAX,EAX`; `JZ rel32` and `JMP rel32` fixups compute target minus the next instruction RVA. Lexical scopes and the existing frame/prologue/epilogue path are retained. The three instruction checks are byte-pattern presence scans rather than a full rel32 target decoder.
- Current-source ABI re-audit confirms issue #1 risks: `Set-FrameSize` allows up to 0x100000 bytes; `Emit-Prologue` emits a direct `sub rsp,imm32` without `__chkstk` or page-touch probing; the PE header's stack commit is 0x1000; the linker emits four sections and leaves the exception directory zero, with no `.pdata` / `.xdata`. This is REPOSITORY PRESENT / STATIC REVIEWED, not a reproduced runtime failure. No unwind, large-frame, or nonvolatile-register sentinel runtime test was run.
- Higher-arity Windows API calls remain manually marshalled; no generic signature-driven call builder was found in this audit.

### Frozen baseline provenance and adaptation

- PR #6 manifest pins M6 archive SHA-256 `0b6bf15445a5dfd8cbf93450af7fd2f5fd6239d4ed082ab18b09878a94b8b164`, compressed payload SHA-256 `3dd1d7417874159c0bc625edbbc1e8cee1ae7d8a6ea42f30b4dd80ba92102748`, and original `SHA256SUMS.txt` digest `61539cb577b3c116d25739cdb8286e3de38410af1d1a39fa1418893799f3c9c9`; payload inventory is 88 members. The runner verifies the compressed payload and each member against its embedded hash. It records but does not independently re-read the original SHA256SUMS file.
- A temporary Stage 2 adapter removes the obsolete pre-7A negative `if` expectation and runs that unchanged archived fixture as a positive Stage 7A case. The hash-pinned archived script and fixture remain unchanged.
- The separate R25-R4 archive in issue #1 has SHA-256 `CA01AEACB2E35C6E8039E58F15202A01399DAEA3E0A24E7B4D357772C8EF1274`; its file-by-file comparison with this M6 package remains NOT RUN.

### 7B candidate review (proposal only)

- PR #5 compiler SHA-256: `3c2bfcd0e71e30da8f2be36fa49f6574bd609ebe1a7831a16aa45ae22ebd93b3`; Stage 7B test SHA-256: `5bc84bd4de3418dc37a0a89b6c518e12e7f0d0d7eb17355230ec9fcca563d796`; `Test.ps1` SHA-256: `e743b8615ce49fa52427ee7f9d37d575ade716cbcf6f0231e9bae8d403f09217`.
- Static review covers Boolean values, typed `!`, `&&` / `||` precedence, branch-based short-circuit lowering, nested loop-target stack, and direct epilogues for nested returns. The existing tests prove constant-left short-circuit side-effect suppression, inner-loop break/continue, and nested returns.
- Additional proposal tests: dynamic variable-left short-circuit side effects; outer-loop continue while an inner loop is active; deeper mixed `&&` / `||` branch-target validation; Boolean function argument/return rejection; return-path analysis edge cases; explicit `while(false)`; and standalone `.sharnou` examples. Existing 7B machine checks scan opcode presence and do not decode branch targets. No code was copied from PR #5.

### Native SharnouDevAgent state

- PR #7 CI built `Build/Stage7A/SharnouDevAgent.exe`, SHA-256 `9F128ED96972858B13C763B4324813B3D6A1970737F2403C10C70717CE947341`; the process ran with exit code 0 and artifact ID `14654214120`.
- The program checks workspace files, tests child-process exit propagation, and launches PowerShell to run Stage 7A. It explicitly reports `Self-hosted native SharnouCompiler.exe: NOT YET IMPLEMENTED`.
- Native test utility: WINDOWS CI PASS on open draft PR. Autonomous AI source-generating agent: NOT IMPLEMENTED / NOT RUN. No persistent worker/checkpoint/recovery, Windows-host deployment, or restart/runtime proof exists.

### Changes, blockers, and next task

- Changed paths this session: `Docs/AI-DEVELOPMENT-PLAN.md`, `Docs/AI-ISSUE-REGISTER.md`, and this session-state file only. No compiler, verifier, example, test, workflow, Engine, IDE, or game source changed. No PR changed. No workflow was manually dispatched. No native build or test was run by the assistant.
- Evidence classification: M1-M6 remains USER-REPORTED WINDOWS PASS; M6 83/83 and M7A 23/23 on PR #6 are WINDOWS CI PASS; PR #5 7B 32/32 is WINDOWS CI PASS on an unaccepted candidate branch; current ABI findings are REPOSITORY PRESENT / STATIC REVIEWED; autonomous native AI agent is NOT RUN / NOT IMPLEMENTED.
- Blockers: PR #6 is not integrated; R25-R4 baseline equivalence is not established; issue #1 unwind/stack-probe/runtime ABI gates remain open; PR #5 7B is unaccepted and not tested with the 83-case baseline; native AI agent is not implemented.
- Next bounded task: obtain the user's review decision for PR #6. After baseline integration and explicit implementation authorization, isolate 7B on top of that baseline, close the listed test gaps, and require same-commit Windows CI for 83 + 23 + 32 = 138 results. Keep ABI repair and self-hosting as separately gated work.


## Scheduled compiler audit - 2026-11-21 09:11 Africa/Cairo

### Repository and pull-request state

- Repository: `Sharnou/Sharnou-Compiler`; default branch: `Sharnou-Compiler`.
- Starting default HEAD for this audit: `b46e81b3e9643c1c4be8f8c615a79be329779346`.
- Open issues rechecked: #1, #8, #9, #10. All remain open.
- Open PRs rechecked: #2 (open, not mergeable, release publisher proposal); #4 (open roadmap proposal); #5 (open, unmerged 7B proposal); #6 (open, unmerged baseline restoration); #7 (draft/open native test orchestrator).
- PR #6 head remains `9dfe1bc09685a6f7deb9d29b5192b1aae0686039`. Comparison against default is diverged (default 18 commits ahead, 15 behind from merge base `352c65e05524d494970b2d8b52b7089d12d19435`). PR #6 adds five baseline/runner/workflow paths; its compiler, PE verifier, Stage 7A test and Stage 7A workflow blobs match default. Do not merge it automatically.
- PR #5 head remains `0b8dee87b699eabcaaac37f111686231fb29a82c`; it changes only the compiler, Test.ps1 and Stage 7B test. It is not user-accepted scope.

### Windows Actions evidence

- Default branch run [44878709265](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44878709265): **success** at starting HEAD `b46e81b3e9643c1c4be8f8c615a79be329779346`; Stage 7A 23/23 (8 positive, 12 negative, 3 instruction checks). Job conclusion is success; no separate process exit-code line was emitted.
- PR #6 run [44700641397](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44700641397): **success** at PR head; frozen M1-M6 suites Stage 2 25/25, Stage 4 20/20, PE verifier 4/4, Stage 5 25/25, Stage 6 9/9 = **83/83**. Case-intent classification is 36 positive / 47 negative as recorded in issue #9; the manifest itself stores suite totals, not polarity labels. No FAIL lines; no separate process exit-code line.
- PR #6 run [44700641419](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44700641419): **success** on the same PR head; Stage 7A 23/23 (8 positive, 12 negative, 3 instruction checks). Thus the 83-case baseline and 7A each passed on one feature-branch commit, in separate Windows workflows. They are not yet integrated into default.
- PR #5 run [44693097619](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44693097619): **success**; Stage 7A 23/23 and proposed Stage 7B 32/32 (15 positive, 13 negative, 4 instruction checks). It did not run the 83-case baseline.
- PR #7 run [44758761226](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44758761226): **success**; built the native test-orchestrator utility, ran the Stage 7A regression, then reported `SharnouDevAgent process exit code: 0` and uploaded artifact ID `14654214120`. The executable explicitly reports that self-hosted native SharnouCompiler.exe is not implemented.

### Source identity and audit

- Default compiler: `Stage0/SharnouCompiler.ps1`, SHA-256 `c97bd0c4d9ad94b1b4855bbdcd6f843f563f75b35771106ae8976cae2bbda250`, Git blob `ee01ef77b068df5d149934fbf463c43b34c54bf3`.
- Default PE verifier: `Tools/SharnouPEVerify.ps1`, SHA-256 `953a20c2274eee42eee2523c5608fd48e6dc574e4b5465464e910db560d55179`, Git blob `3606b57920043882a2277ad41fd0e0578156944a`.
- Stage 7A test: `Tests/Test-Stage7A.ps1`, SHA-256 `ffd8a3518d8fc943adb97e319a29a8822d4e5c409226597d0010b40da23eae05`, Git blob `80d8df1c9a6da7c8fb6f2b414c2929f07ba44804`.
- PR #5 candidate compiler SHA-256 `3c2bfcd0e71e30da8f2be36fa49f6574bd609ebe1a7831a16aa45ae22ebd93b3`; Stage 7B test SHA-256 `5bc84bd4de3418dc37a0a89b6c518e12e7f0d0d7eb17355230ec9fcca563d796`; candidate Test.ps1 SHA-256 `e743b8615ce49fa52427ee7f9d37d575ade716cbcf6f0231e9bae8d403f09217`.
- Static M7A review: signed comparisons use CMP/SETcc/MOVZX; conditions use TEST and JZ rel32; loops use rel32 back-jumps. Existing frame/prologue/epilogue and Windows x64 call path are unchanged. Existing machine checks verify byte-pattern presence, not a complete branch-target decode.
- PR #6 baseline runner verifies the compressed payload SHA-256 and each embedded member hash, and uses a temporary adapter to reclassify the archived pre-7A `if` fixture as a positive case. It records the original SHA256SUMS digest but does not independently read/verify that original manifest. The separate R25-R4 archive comparison in issue #1 remains NOT RUN.

### Milestone 7B proposal audit - no implementation

- PR #5 adds Boolean literals/variables, unary NOT, precedence-aware AND/OR, branch-based short-circuit lowering, break/continue with an innermost-loop target stack, and nested return lowering. Its Windows 32/32 result is candidate-branch evidence only.
- Static defect found in the unaccepted PR #5 candidate: `Stage0/SharnouCompiler.ps1` lines 322-326, `Get-ConstantValue` evaluates the right operand when the left side of a logical expression is not a compile-time constant. Consequently a dynamic-left expression such as `flag && (1 / 0 == 0)` is rejected during compilation even when runtime `flag` is false and short-circuit semantics require the right side to be skipped. The OR mirror has the same issue. This is a static source finding, not a reproduced Windows failure. The current tests exercise constant-left short-circuit cases only.
- Before accepting 7B, add dynamic-left AND/OR skip-and-evaluate tests, mixed nested logical expressions, nested inner/outer loop break/continue target tests, explicit Boolean function argument/return rejection tests (the current ABI remains integer-only), deeper return-path/fallthrough cases, and standalone .sharnou examples.
- Replace opcode-presence-only checks with a bounded rel32 branch decoder that verifies every conditional/unconditional branch target lies within .text and resolves to an emitted instruction label. Preserve the existing frame layout and x64 ABI.
- Proposed code correction: when the logical left operand is unknown, return an unknown constant result without evaluating the right subtree for compile-time arithmetic faults; parser type checks already validate both operands. Only evaluate the right subtree when a known left value requires it.
- PR #5 does not include the frozen 83-case baseline. A candidate acceptance workflow must run 83 + 23 + 32 = 138 results on the same commit after the baseline is integrated or included in the isolated feature branch. No implementation branch or patch was created in this run.

### Native compiler and DevAgent state

- Native self-hosted `SharnouCompiler.exe`: **NOT BUILT / NOT RUN**.
- PR #7 native `SharnouDevAgent.exe`: **WINDOWS CI PASS as a test orchestrator only**, process exit 0, artifact ID `14654214120`. It is not an AI source-generating agent. Persistent worker/checkpoint/recovery, Windows-host deployment, and restart/runtime proof are absent.
- Issue #1 ABI gates remain open: unwind metadata, large-frame stack probing, nonvolatile-register/runtime probes, and generic checked Windows API marshalling. These remain separate prerequisites before full self-hosting acceptance.

### Changes and next bounded task

- Changed paths in this status commit: `Docs/AI-SESSION-STATE.md` and `Docs/AI-ISSUE-REGISTER.md` only. No source changes. No compiler/verifier/examples/tests/workflows/Engine/IDE/game files changed. No PR was created, modified or merged; no workflow was manually dispatched; no local Windows build or test was run by the assistant.
- Evidence: **WINDOWS CI PASS** for default M7A 23/23, PR #6 baseline 83/83 and M7A 23/23 on the same PR head, PR #5 candidate 7B 32/32, and PR #7 native test utility. **REPOSITORY PRESENT / STATIC REVIEWED** for compiler/PE source and the 7B candidate defect. **USER-REPORTED WINDOWS PASS** remains the user's M1-M6 report. **NOT RUN / NOT IMPLEMENTED** for self-hosted SharnouCompiler.exe and an autonomous AI source-generating DevAgent.
- Next bounded task: keep PR #6 open for normal review; after the baseline integration decision and explicit implementation authorization, prepare an isolated 7B correction/test patch on top of the frozen baseline. Do not dispatch or merge automatically. Require all 138 same-commit Windows results before accepting 7B. Keep ABI repair and native AI-agent implementation as separately gated tasks.

The resulting status-only commit SHA is recorded in GitHub issue #8 after the ref update.
