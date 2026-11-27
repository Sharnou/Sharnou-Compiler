# AI Session State - Sharnou Compiler

**Last updated:** 2026-11-22 Africa/Cairo
**Repository:** `Sharnou/Sharnou-Compiler`  
**Branch:** `Sharnou-Compiler`  
**Purpose:** Latest durable status for every future AI-assisted compiler/Engine generation, debugging, testing, and repair session.

> This file is the live status snapshot, not a claim that the AI can monitor the repository in the background. Update it at the end of every completed AI work session.

## Current status at a glance

- **Accepted project direction:** self-contained Sharnou compiler, PE32+ linker, runtime/standard library, Engine, IDE, and Honour War for Windows x64.
- **User-reported completed history:** Milestones 1-6 passed on the user's Windows PC.
- **Current development focus:** Milestone 7A implementation is present and Windows-CI verified; the next bounded task is a Milestone 7B proposal and isolated patch plan only.
- **Persistent AI status tracker:** [GitHub issue #8](https://github.com/Sharnou/Sharnou-Compiler/issues/8); update its body and this file after every completed AI generation/repair session.
- **Actionable blockers:** [Issue #9 - restore exact 83-case baseline](https://github.com/Sharnou/Sharnou-Compiler/issues/9); [Issue #10 - Milestone 7A Windows acceptance](https://github.com/Sharnou/Sharnou-Compiler/issues/10).
- **Milestone 7A repository implementation:** present on the `Sharnou-Compiler` branch; implementation commit `943d24d857b89b9b30a426c8fb4025c05413d6a8`.
- **Plan-map documentation commits:** `c403b4b725200000ba89944798a4bcca618c9885` (AI preflight), `5a5b2c89d0c0c0a4d85bb4111ecb145a83be7cb9` (master plan), `aeb086429bc98e5094bf4d881c02b9100e4cb893` (issue register), and `e47dd7d5634ed5ccc9302d2d59241790f6de3bdc` (README links). The current state file was subsequently updated to include GitHub issue numbers.
- **Milestone 7A Windows CI:** current default-branch run 45004368571 passed 23/23 on HEAD 45c83e1941fd74ca1ce94a4f0bc9ffe72a43efe3. User-local 7A acceptance is still NOT REPORTED separately.
- **Frozen 83-case repository baseline:** WINDOWS CI PASS 83/83 on open PR #11 head 135b7eec7bf13fc147756dfaeeb3f92eab57a250, with the 7A 23/23 suite passing on that same head. The five baseline paths remain PR-only and are not yet on default.
- **Next action:** review PR #11 through the normal process without auto-merging; complete the R25-R4 archive comparison; retain ABI gates; prepare 7B as a proposal only until implementation/write authorization.

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


## Scheduled compiler and DevAgent audit - 2026-11-22 08:46 Africa/Cairo

Repository: `Sharnou/Sharnou-Compiler`
Default branch: `Sharnou-Compiler`
Default HEAD at audit start: `25bc8aac1370b1d6024ae538956c49a6bbba4f07`
Status-only issue-register commit: `329f1aac33e4a3ed4f5bbbc03ce3d3667d5776bf`

### Live PR state

- PR #6: OPEN / UNMERGED; head `9dfe1bc09685a6f7deb9d29b5192b1aae0686039`; GitHub reports mergeable=false; compare to default is 15 ahead / 19 behind with merge base `352c65e05524d494970b2d8b52b7089d12d19435`. Five baseline-related paths are added. Compiler, verifier, Stage 7A test, and root Test.ps1 blobs are identical to current default. Do not merge, rebase, or rewrite automatically.
- PR #5: OPEN / UNMERGED / NOT ACCEPTED; head `0b8dee87b699eabcaaac37f111686231fb29a82c`; mergeable=false; 2 ahead / 19 behind. Its 7B implementation is a proposal only.
- PR #7: OPEN / DRAFT; head `ac3849800412b1208acb540ef090ffb3ac0455ca`; mergeable=false. It is a native test orchestrator, not an AI source-generating agent.
- PR #4 and #2 remain open/unmerged; PR #3 is merged. Issues #1, #8, #9, #10 remain open.

### Windows Actions evidence

- Run 44880127825: default HEAD `25bc8aac1370b1d6024ae538956c49a6bbba4f07`; `windows-stage7a` success; encoding check PASS; Stage 7A 23 passed / 0 failed / 23 total; Combined result PASS.
- Run 44700641397: PR #6 head; `windows-m6-83` success; Stage 2 25/25, Stage 4 20/20, PE verifier 4/4, Stage 5 25/25, Stage 6 9/9; frozen baseline PASS 83/83.
- Run 44700641419: same PR #6 head; `windows-stage7a` success; Stage 7A 23/23; Combined result PASS.
- Run 44693097619: PR #5 head; `windows-stage7a` success; Stage 7A 23/23 and proposed Stage 7B 32/32 (15 positive, 13 negative, 4 instruction checks). It did not run the 83-case baseline.
- Run 44758761226: PR #7 head; `windows-stage7a` success; native DevAgent repeated Stage 7A 23/23, verified child exit code 7 propagation, exited 0, and uploaded artifact ID `14654214120`.
- The 83-case intent split is classified as 36 positive / 47 negative; the manifest records suite totals only. No workflow was dispatched in this run.

### Audit findings

- Current default compiler/verifier/Test-Stage7A blobs: `ee01ef77b068df5d149934fbf463c43b34c54bf3`, `3606b57920043882a2277ad41fd0e0578156944a`, `80d8df1c9a6da7c8fb6f2b414c2929f07ba44804`. Recorded SHA-256 values remain `c97bd0c4d9ad94b1b4855bbdcd6f843f563f75b35771106ae8976cae2bbda250`, `953a20c2274eee42eee2523c5608fd48e6dc574e4b5465464e910db560d55179`, and `ffd8a3518d8fc943adb97e319a29a8822d4e5c409226597d0010b40da23eae05`.
- PR #6's baseline runner pins the original M6 archive and compressed payload. It validates the payload and embedded member hashes but does not independently read the original `SHA256SUMS.txt`; the manifest provenance boolean is not independently reproduced by the runner. R25-R4 file-by-file comparison remains NOT RUN.
- Re-review correction: PR #5's `Get-ConstantValue` traverses the RHS when the left operand is dynamic. This is compile-time constant-arithmetic validation, not runtime RHS evaluation. Since the RHS may be reachable, constant divide-by-zero rejection can be a deliberate fail-closed policy. The previous session overclassified this as a confirmed short-circuit defect. The actual gap is missing dynamic-left side-effect tests for AND/OR skip and evaluate paths.
- PR #5 has 15 positive, 13 negative, and 4 opcode-presence checks. It lacks explicit negative tests for Boolean function arguments/returns and a rel32 target decoder. The current branch/loop emitter uses JZ/JNZ and JMP rel32 fixups; loop targets are pushed/popped with try/finally. ABI-critical functions `Emit-CallFunction`, `Set-FrameSize`, `Emit-Prologue`, and `Emit-Epilogue` are unchanged from default. Issue #1's unwind metadata, large-frame stack probing, nonvolatile-register probes, and generic API marshalling remain open.
- The PR #7 native agent is a test orchestrator only. It checks workspace files, tests child-process exit-code propagation, and runs PowerShell tests. It does not generate source or build a self-hosted compiler.

### Native build/runtime status

- Native self-hosted `SharnouCompiler.exe`: NOT BUILT / NOT RUN.
- Native `SharnouDevAgent.exe`: WINDOWS CI PASS as a test orchestrator on PR #7; artifact ID `14654214120`; process exit code 0. Not merged or deployed.
- Autonomous source generation, persistent worker/checkpoint/recovery, Windows-host deployment, and restart/runtime proof: NOT IMPLEMENTED / NOT RUN.

### Changes and next dependency

- Changed paths in this run: `Docs/AI-ISSUE-REGISTER.md` and this session-state file only. No source changes: compiler, verifier, examples, tests, build scripts, workflows, Engine, IDE, and game source are unchanged. No PR changes, merge, rebase, or workflow dispatch.
- Evidence: M1-M6 USER-REPORTED WINDOWS PASS; default 7A and PR #6 baseline/7A WINDOWS CI PASS; PR #5 7B WINDOWS CI PASS on an unaccepted, stale branch; PR #7 native test orchestrator WINDOWS CI PASS; 7B observations REPOSITORY PRESENT / STATIC REVIEWED; self-hosting and autonomous agent NOT RUN / NOT IMPLEMENTED.
- Next bounded task: resolve PR #6's stale/non-mergeable integration path by explicit review without altering the frozen payload. Once baseline is integrated or equivalently included in a fresh isolated candidate branch, prepare the corrected 7B patch plan and require all 138 cases (83 + 23 + 32) to pass on one Windows commit. Keep ABI repair and autonomous agent work separately gated.


## PR mergeability re-check correction - 2026-11-22

The initial PR metadata read in the preceding audit returned `mergeable=false` for PR #6, #5, and #7. Two subsequent live reads returned `mergeable=true` for PR #6, #5, #7, and #4 at then-current default HEAD `c7bd85a108d97800e7f03b338cf60089a18f4f4e`. The later repeated value supersedes the initial value. All remain OPEN / UNMERGED; PR #7 remains DRAFT. Do not describe them as merge-conflict blocked.

The compare endpoints still show divergence: PR #6 15 ahead / 21 behind; PR #5 2 ahead / 21 behind; PR #7 9 ahead / 21 behind; common merge base `352c65e05524d494970b2d8b52b7089d12d19435`. These are stale branches requiring review, not evidence of merge conflicts. PR #6 remains expressly unmerged by this automation. No PR state or source changed.


## Final PR metadata consistency note - 2026-11-22

Repeated live GitHub connector reads returned alternating `mergeable` values for PRs #6, #5, and #7 (false, true, false, then true). Treat the mergeable field as UNSTABLE / UNKNOWN for this session; do not infer conflicts or a clean merge from it. Stable facts: PR #6/#5 remain OPEN / UNMERGED and PR #7 remains OPEN / DRAFT / UNMERGED; head SHAs are unchanged; compare reports divergence. At default HEAD `c7bd85a108d97800e7f03b338cf60089a18f4f4e`, PR #6 was 15 ahead / 21 behind, PR #5 2 ahead / 21 behind, PR #7 9 ahead / 21 behind. Two later status-only documentation commits add two more commits to the default branch; re-run compare before any future branch operation. PR #6 must not be merged by this automation regardless of mergeability metadata. No PR state or source changed.


## Final default HEAD and PR divergence snapshot - 2026-11-22

At default HEAD `e965c0e0848855b48b1e7cfe27707e0d369eb56b`, compare reported PR #6 15 ahead / 25 behind, PR #5 2 ahead / 25 behind, and PR #7 9 ahead / 25 behind, all diverged from merge base `352c65e05524d494970b2d8b52b7089d12d19435`. The earlier two-commit increment referred to the state before the two final consistency-note commits; this snapshot supersedes it. The two status-only commits appended after this snapshot add two more commits to default, so expected behind counts become 27. Re-query before any future branch operation. GitHub mergeable metadata remains UNSTABLE / UNKNOWN after alternating reads. No PR is merged or modified.


## Session update - 2026-11-22 - baseline integration, 7A CI and ABI gate audit

**Session type:** Repository triage, frozen-baseline integration preparation, status synchronization and current-source ABI audit. No compiler or PE-verifier source was modified.

### Starting repository state

- Repository: `Sharnou/Sharnou-Compiler`.
- Default branch: `Sharnou-Compiler`.
- Starting/default HEAD: `d79873e1941b22f1f9eb1413d58e874d77d54e17`.
- Current compiler blob: `ee01ef77b068df5d149934fbf463c43b34c54bf3`; previously recorded content SHA-256 for that exact blob: `c97bd0c4d9ad94b1b4855bbdcd6f843f563f75b35771106ae8976cae2bbda250`.
- Current PE verifier blob: `3606b57920043882a2277ad41fd0e0578156944a`.
- Stage 7A test blob: `80d8df1c9a6da7c8fb6f2b414c2929f07ba44804`; root `Test.ps1` blob: `699eb04aefdf1149aa5807107ce351f8c2aae676`.

### B1 / Issue #9 - frozen M1-M6 83-case suite

The old PR #6 branch is open/unmerged and diverged 15 commits ahead / 27 behind the current default HEAD. It was not merged, rebased, or rewritten.

A fresh feature branch and PR were created to replay the exact same five baseline file blobs from the current default commit:

- Branch: `automation/m6-baseline-current-head-20261122`.
- Commit: `37451e384e2e7e669c8368882225619cc9a67e67`.
- New PR: [#11 - Restore frozen Milestone 6 83-case baseline on current default head](https://github.com/Sharnou/Sharnou-Compiler/pull/11).
- Base commit: `d79873e1941b22f1f9eb1413d58e874d77d54e17`.
- Changed paths (five additions only):
  - `.github/workflows/milestone6-baseline.yml`
  - `StdLib/Graphics.sharnou`
  - `Tests/BaselineM6/M6-83Cases.payload.json.gz.b64`
  - `Tests/BaselineM6/Test-Milestone6Baseline.ps1`
  - `Tests/BaselineM6/manifest.json`
- The exact blob identities from PR #6 were reused. No compiler, PE verifier, Stage 7A test, or existing test source was modified.
- Frozen M6 package SHA-256: `0b6bf15445a5dfd8cbf93450af7fd2f5fd6239d4ed082ab18b09878a94b8b164`.
- Compressed payload SHA-256: `3dd1d7417874159c0bc625edbbc1e8cee1ae7d8a6ea42f30b4dd80ba92102748`; 88 embedded source/fixture members.
- New Windows workflow run [45003405485](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45003405485) started on PR #11 head `37451e384e2e7e669c8368882225619cc9a67e67`. At the time of this status write, job `windows-m6-83` was IN_PROGRESS; no result is claimed yet.
- Earlier PR #6 Windows run [44700641397](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44700641397) logged 83/83 on the old PR head. That historical result is not substituted for PR #11's own run.
- The separate R25-R4 archive file-by-file comparison remains NOT RUN. Its pinned SHA-256 is `CA01AEACB2E35C6E8039E58F15202A01399DAEA3E0A24E7B4D357772C8EF1274`. The two 83-case suites are not assumed identical.
- Issue #9 remains OPEN/BLOCKED pending PR #11 Windows 83/83, default-branch integration through normal review, and the separate R25-R4 comparison. No PR was merged.

### B2 / Issue #10 - Milestone 7A

Default-branch Windows run [44996610001](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44996610001) completed successfully on exact default HEAD `d79873e1941b22f1f9eb1413d58e874d77d54e17`.

- Job: `windows-stage7a`, conclusion `success`.
- Source encoding: ASCII/no-BOM check PASS.
- Test log: 8 positive runtime + 12 negative diagnostic + 3 instruction/branch encoding checks = 23 passed, 0 failed, 23 total.
- Test log includes `Stage 7A test result: PASS` and `Combined result: PASS`.

Classification: **WINDOWS CI PASS**. User-local Milestone 7A acceptance is still NOT REPORTED separately. Issue #10 remains open because the 83-case dependency and evidence reconciliation are still pending.

### H1 / Issue #1 - current Windows x64 ABI re-audit

Re-read current compiler and verifier. Static findings remain:

1. `Set-FrameSize` allows frame sizes up to `0x100000`. `Emit-Prologue` emits `push rbp; mov rbp,rsp; sub rsp,imm32` with no `__chkstk` or per-page stack-touch probe. PE stack commit is `0x1000`.
2. The linker emits only `.text`, `.rdata`, `.idata`, and `.reloc`; exception data directory is not populated. No `.pdata` / `.xdata` unwind records are emitted.
3. The verifier does not validate unwind metadata because the image does not yet contain it.
4. Higher-arity Windows API calls are manually emitted, not produced by a generic signature-driven checked marshaller.
5. No new runtime sentinel tests for nonvolatile registers, RSP alignment, stack arguments or unwind walking were executed in this session.

Classification: **REPOSITORY PRESENT / STATIC REVIEWED**. No ABI runtime test, stack-probe experiment or unwind-walking test was run. Issue #1 remains OPEN. Required gates: documented large-frame probing, Windows x64 unwind metadata and verifier support, nonvolatile-register/RSP/argument-value runtime probes, and validated generic Windows API argument marshalling.

### Issue #8 and scheduled status synchronization

The daily `Sharnou DevAgent Progress` automation was found disabled, despite its saved instructions already containing the mandatory read-first and persist-status protocol. It has been re-enabled. The weekly `Advance Sharnou Stack` automation remains enabled. The three legacy Honour War daily-upgrade automations remain disabled.

This does not provide per-chat-turn background monitoring. The repository read-first and save-after-session requirements remain active, and the scheduled automation runs only on its configured schedule.

### Evidence classification and next actions

- M1-M6: USER-REPORTED WINDOWS PASS.
- M6 frozen 83/83: WINDOWS CI PASS on old PR #6 head; fresh PR #11 run 45003405485 IN PROGRESS at status write.
- M7A: WINDOWS CI PASS 23/23 on current default HEAD, run 44996610001.
- ABI: REPOSITORY PRESENT / STATIC REVIEWED; acceptance BLOCKED.
- Native self-hosted `SharnouCompiler.exe`: NOT BUILT / NOT RUN.
- Autonomous source-generating DevAgent: NOT IMPLEMENTED / NOT RUN. The separate PR #7 artifact remains a test orchestrator, not an AI source generator.

Next dependency order:
1. Complete and inspect PR #11 Windows run 45003405485; require all five historical suite totals and 83/83 with zero failures/skips.
2. Review/integrate PR #11 through the normal PR review process; do not auto-merge.
3. Complete the exact R25-R4 archive comparison.
4. Close M7A local-acceptance evidence only when the user reports it; retain the current Windows CI result.
5. Implement and runtime-validate the ABI gates in issue #1 before starting native self-hosting.
6. Do not adopt the unaccepted 7B proposal in PR #5 without explicit user acceptance and same-commit baseline coverage.

No local Windows command was run by the assistant. No compiler, verifier, Engine or game source was changed. No default-branch source was modified. No PR was merged.


## Follow-up result - PR #11 frozen 83-case baseline - 2026-11-22

Windows Actions run [45003405485](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45003405485) completed successfully on PR #11 head `37451e384e2e7e669c8368882225619cc9a67e67`. Job `windows-m6-83` ID `137149638940` concluded `success`.

Exact log summaries:
- ASCII source / UTF-8 without BOM: PASS.
- Stage 2: 25 passed, 0 failed, 25 total.
- Stage 4: 20 passed, 0 failed, 20 total.
- PE verifier: 4 passed, 0 failed, 4 total.
- Stage 5: 25 passed, 0 failed, 25 total.
- Stage 6: 9 passed, 0 failed, 9 total.
- Aggregate frozen Milestone 1-6 baseline: **83/83 PASS**. No `FAIL:` lines were found in the job log.

Classification: **WINDOWS CI PASS on PR #11**. This is not default-branch integration and not user-local evidence. PR #11 remains open for review. After the two documentation-only default-branch status commits, its base branch is two commits ahead; those commits did not alter compiler or test sources. The PR has not been merged.

Issue #9 remains open until ordinary PR review/integration and the separate R25-R4 archive file-by-file comparison are complete. The R25-R4 comparison remains NOT RUN.


## PR #11 replay complete and branch synchronized - 2026-11-22

- PR #11: https://github.com/Sharnou/Sharnou-Compiler/pull/11
- Feature branch: `automation/m6-baseline-current-head-20261122`
- Current branch head after a non-force two-parent sync with latest default docs: `614a9badfd4aa2b9682bad384147c3b1e6066020`.
- Current default branch parent: `cbc8ea0e0bb65e1a4bf1de748fb9aad8d30433ae`.
- PR compare: 2 commits ahead, 0 behind; only the five intended frozen-baseline files appear in the PR diff.

Windows CI on the source/test tree before the documentation-only sync:
- [45003405485](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45003405485): `windows-m6-83` success, Stage 2 25/25, Stage 4 20/20, PE verifier 4/4, Stage 5 25/25, Stage 6 9/9; aggregate 83/83.
- [45003405576](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45003405576): `windows-stage7a` success, 23/23 on the same predecessor `37451e384e2e7e669c8368882225619cc9a67e67`.
- The sync commit adds only the two status-document commits as the second parent. Compiler, verifier, tests, fixtures, manifest and frozen payload blobs were not changed. No separate CI run is claimed on merge commit `614a9...`.

The default branch still does not contain the baseline; PR #11 remains OPEN / UNMERGED for normal review. The R25-R4 archive comparison remains NOT RUN.


## Final PR #11 state - 2026-11-22

- PR #11 head after synchronization: `939a8b63085e0ef8f2f23b01d5122d4c702e7625`.
- It was based on default HEAD `b90710f05abb85563e6c87885dbd72caba61899d`, compare 3 ahead / 0 behind at the time of that check.
- PR diff remains exactly five baseline files. No compiler, PE verifier, Stage 7A implementation, existing regression script or fixture is changed.
- Windows run 45003405485 passed the frozen M1-M6 suite 83/83, and run 45003405576 passed Stage 7A 23/23, both on predecessor source/test tree commit `37451e384e2e7e669c8368882225619cc9a67e67`. The later PR merge commits only synchronize status-document commits; compiler/verifier/tests/payload blobs are unchanged. No new runtime run is claimed for merge commit `939a8b6...`.
- The final status-doc write itself advances default branch after base `b90710f...`; PR #11 may therefore be one docs-only commit behind after this status write. This does not change its five-file diff or tested code/test blobs.
- PR remains OPEN / UNMERGED for review. The default branch still does not contain the frozen baseline. The R25-R4 archive comparison remains NOT RUN.


## Final current-head Windows validation - 2026-11-22

### PR #11 frozen baseline

- Branch `automation/m6-baseline-current-head-20261122`, exact tested head `3e8dec1475d45ae2537fc30bd398ebe5a7ee7b67`.
- Windows run [45004007198](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45004007198) completed SUCCESS; job `windows-m6-83` ID `137151468446`.
- Results: Stage 2 25/25; Stage 4 20/20; PE verifier 4/4; Stage 5 25/25; Stage 6 9/9; aggregate **83/83 PASS**; ASCII/no-BOM check PASS.
- Windows run [45004007206](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45004007206) completed SUCCESS on the same exact head; job `windows-stage7a` ID `137151468216`; Stage 7A **23/23 PASS**.
- No `FAIL:` result lines appear in either workflow log. These are WINDOWS CI PASS results on PR #11, not user-local runs.

### PR / issue state

- PR #11 is open and not merged. It adds exactly five frozen-baseline files. At this validation snapshot, PR branch compared 4 commits ahead / 0 behind default. Default HEAD at this status write: `bd72a8636e6948bbf4834dff4eae47c0fcf97c01`.
- Issue #9 remains OPEN until normal PR integration and the separate R25-R4 archive file-by-file comparison. The suite is not yet on default.
- Issue #10: default-branch Stage 7A run 44996610001 passed 23/23 on earlier default source HEAD; the PR #11 head also passed 23/23 in run 45004007206. User-local 7A result remains unreported.
- Issue #1 ABI status is unchanged: source-level static findings only; stack probing, unwind metadata, runtime preservation/stack/argument tests, and generic API marshalling remain unimplemented/unverified.
- Issue #8 body and this session-state file have been synchronized. Daily `Sharnou DevAgent Progress` is enabled; weekly `Advance Sharnou Stack` remains enabled. Legacy Honour War daily-upgrade tasks remain disabled.

The default-branch documentation commit below is status-only. No compiler, PE verifier, test, build, Engine, or game source was changed. No PR was merged.


## Latest PR #11 exact-head results - 2026-11-22

PR #11 current tested feature-branch head: `d33778f6f23a006965f25aeb4dfc8e55cdc49d22`.

Same-head Windows CI:
- M1-M6 frozen baseline [run 45004124843](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45004124843), job `windows-m6-83` ID `137151818001`, conclusion success: Stage 2 25/25, Stage 4 20/20, PE verifier 4/4, Stage 5 25/25, Stage 6 9/9; aggregate **83 passed, 0 failed, 83 total**.
- Stage 7A [run 45004124879](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45004124879), job `windows-stage7a` ID `137151817931`, conclusion success: **23 passed, 0 failed, 23 total** (8 positive runtime, 12 negative diagnostic, 3 instruction/branch checks).
- Both workflows report ASCII/no-BOM PASS and no failed test records.
- PR compare before this status-only commit: 5 commits ahead / 0 behind; exactly five frozen-baseline paths in the diff. Default base HEAD at this check: `e0e281ea53c5ace7279d42f949a5ee06cf0d80ee`.

The status-only documentation commit below advances default by one commit; PR #11 will therefore be one docs-only commit behind afterwards. Its compiler, verifier, five baseline files, fixtures and test source are unchanged. No CI result is claimed for any later merge-only PR commit.

Issue #9 remains open: PR review/integration is pending and the separate R25-R4 archive file comparison is NOT RUN. Issue #10 remains open: Windows CI passes but user-local 7A acceptance is not separately recorded. Issue #1 remains open and blocked on ABI implementation/runtime evidence.


## Final baseline and control-flow CI on synchronized PR head - 2026-11-22

PR #11 synchronized head `c525a4491f033dc882488ab84fbb312c5e477061` completed both Windows workflows successfully:
- [45004279512](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45004279512), job `windows-m6-83` ID `137152283687`: Stage 2 25/25, Stage 4 20/20, PE verifier 4/4, Stage 5 25/25, Stage 6 9/9; aggregate **83 passed, 0 failed, 83 total**.
- [45004279593](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45004279593), job `windows-stage7a` ID `137152283815`: **23 passed, 0 failed, 23 total** (8 positive runtime, 12 negative parser/type, 3 instruction/branch checks).
- Both jobs concluded success, both logs report ASCII/no-BOM PASS, and no FAIL test lines were present.

At this point the feature branch was based on default HEAD `81329d675b8383a54709f41c5a3203b422421740`, compare 6 ahead / 0 behind, and the PR diff contained only the five frozen-baseline paths. This status-only documentation commit may move the feature branch one docs-only commit behind; compiler, verifier, tests, fixtures and baseline payload are unchanged.

PR #11 remains OPEN / UNMERGED. The frozen 83-case suite is proven by Windows CI on the PR branch but is not yet in default. The R25-R4 archive comparison remains NOT RUN. M7A is WINDOWS CI PASS; user-local acceptance is still not separately recorded. ABI issue #1 remains OPEN and blocked on implementation/runtime evidence.


## Live compiler audit and Milestone 7B proposal - 2026-11-22

### Repository and branch
- Repository: `Sharnou/Sharnou-Compiler`.
- Default branch: `Sharnou-Compiler`.
- Default HEAD reviewed: `45c83e1941fd74ca1ce94a4f0bc9ffe72a43efe3`.
- Changed compiler/test/workflow paths: **none**. This run performed repository review, Windows CI log inspection, and status-only persistence.
- No feature branch, PR, source file, workflow, or user machine was modified. No workflow was dispatched.

### Milestone 7A and frozen baseline - same-head Windows evidence
- Default-branch Windows run [45004368571](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45004368571), job `windows-stage7a` (`137152555458`), completed SUCCESS on exact default HEAD `45c83e1941fd74ca1ce94a4f0bc9ffe72a43efe3`. Log: ASCII/no-BOM PASS; 8 positive runtime cases, 12 negative diagnostic cases, 3 instruction/branch checks; **23 passed, 0 failed, 23 total**; Stage 7A PASS; Combined PASS.
- PR [#11](https://github.com/Sharnou/Sharnou-Compiler/pull/11), branch `automation/m6-baseline-current-head-20261122`, exact head `135b7eec7bf13fc147756dfaeeb3f92eab57a250`, base SHA `45c83e1941fd74ca1ce94a4f0bc9ffe72a43efe3`, is OPEN / UNMERGED. Compare: 7 ahead / 0 behind; its diff is five baseline-related additions only.
- PR #11 Windows baseline run [45004395351](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45004395351), job `windows-m6-83` (`137152637466`), completed SUCCESS on exact PR head `135b7eec7bf13fc147756dfaeeb3f92eab57a250`. Logs: Stage 2 25/25; Stage 4 20/20; PE verifier 4/4; Stage 5 25/25; Stage 6 9/9; aggregate **83 passed, 0 failed, 83 total**; ASCII/no-BOM PASS.
- PR #11 Windows Stage 7A run [45004395353](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45004395353), job `windows-stage7a` (`137152637335`), completed SUCCESS on the same exact PR head `135b7eec7bf13fc147756dfaeeb3f92eab57a250`: **23 passed, 0 failed, 23 total** (8 positive, 12 negative, 3 instruction/branch checks).
- Thus 7A and all 83 M1-M6 cases have WINDOWS CI PASS on one current PR head, but the baseline remains absent from default until PR #11 is normally reviewed/integrated. This does not replace user-local 7A evidence.

### PR and issue state
- PR #11: OPEN / UNMERGED; current head `135b7eec7bf13fc147756dfaeeb3f92eab57a250`; compare 7 ahead / 0 behind; five additions only.
- PR #6: OPEN / UNMERGED, old head `9dfe1bc09685a6f7deb9d29b5192b1aae0686039`; compare to current default 15 ahead / 37 behind. Do not merge, rebase, or rewrite it automatically.
- PR #5: OPEN / UNMERGED, proposed 7B head `0b8dee87b699eabcaaac37f111686231fb29a82c`; compare 2 ahead / 37 behind, merge base `352c65e05524d494970b2d8b52b7089d12d19435`. It is stale relative to current default and is a proposal, not accepted implementation.
- PR #7: OPEN / DRAFT, head `ac3849800412b1208acb540ef090ffb3ac0455ca`; native DevAgent test orchestrator proposal only.
- PR #4: OPEN / UNMERGED. No PR was modified, approved, or merged.
- Issues #8, #9, #10 and #1 remain OPEN. Issue #9 awaits normal PR #11 review/integration and the separate R25-R4 archive equivalence comparison. Issue #10 still lacks a separate user-local M7A acceptance report. Issue #1 ABI gates remain unresolved.

### Milestone 7A source audit
- Current compiler blob: `ee01ef77b068df5d149934fbf463c43b34c54bf3`; recorded file SHA-256: `c97bd0c4d9ad94b1b4855bbdcd6f843f563f75b35771106ae8976cae2bbda250`.
- PE verifier blob: `3606b57920043882a2277ad41fd0e0578156944a`; recorded file SHA-256: `953a20c2274eee42eee2523c5608fd48e6dc574e4b5465464e910db560d55179`.
- Stage 7A test blob: `80d8df1c9a6da7c8fb6f2b414c2929f07ba44804`; recorded file SHA-256: `ffd8a3518d8fc943adb97e319a29a8822d4e5c409226597d0010b40da23eae05`.
- Static review confirms the current subset: signed integer comparisons, zero/nonzero integer truth conditions, comparison normalization, nested if/while, and label-based near-branch fixups. It explicitly rejects chained comparisons, string comparisons, logical AND/OR, else-if shorthand, and returns nested inside control-flow blocks. The Windows CI suite covers eight positive programs, twelve negative cases, and three instruction checks.
- ABI carry-forward remains: no large-frame stack probe, no `.pdata`/`.xdata` unwind metadata or exception directory, no executed nonvolatile-register/RSP/stack-argument sentinel suite, and no generic signature-driven Windows API marshaller. These are repository/static findings, not new runtime failures. Do not claim self-hosting readiness.

### Milestone 7B proposal - no implementation performed
The current PR #5 candidate reports Windows CI run [44693097619](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44693097619): Stage 7A 23/23 plus candidate Stage 7B 32/32 (15 positive, 13 negative, 4 instruction-presence checks), but it did not include the 83-case frozen baseline and is based on an old branch. Do not port or accept it wholesale.

A bounded proposal for a fresh 7B patch after the baseline is on the accepted base:
1. Boolean scalar values: `true`/`false`, normalized 0/1 storage, Boolean declarations/assignments; reject integer/Boolean implicit conversions and Boolean arithmetic.
2. Precedence and semantics: unary `!`, comparisons, then `&&`, then `||`; strict Boolean operands for logical operators; `==`/`!=` for matching types; ordered comparisons remain integer-only. Preserve existing integer conditions for 7A compatibility while allowing Boolean conditions explicitly.
3. Short-circuit native branches: `&&` skips RHS when left is false; `||` skips RHS when left is true; use existing rel32 fixup machinery. Add dynamic-variable-left side-effect tests for both skip and evaluate paths (the current candidate tests use constant left operands only).
4. Loop control: `break` and `continue` only inside loops; use a nested loop-target stack with push/pop in `try/finally`; break targets the current loop exit and continue targets its condition/header. Add deeper nested-loop and nested-if cases.
5. Nested returns: allow return in nested if/else/loop blocks, emit the existing ABI epilogue for each return edge; keep conservative definite-return analysis (a loop is not assumed to terminate). Functions remain up to four integer parameters and integer return values in this bounded stage; explicitly reject Boolean function arguments/returns until a separate ABI design is accepted.
6. Tests: preserve M6 83 + 7A 23; add runtime positives for Boolean assignment/equality/precedence, dynamic short-circuit skip/evaluate paths, break/continue including nested loops, nested returns; negative tests for mixed types, Boolean arithmetic/ordered comparisons, invalid loop-control placement, Boolean function ABI misuse, and missing return paths; add a rel32 decoder that validates each emitted branch target is within a valid code range rather than only checking opcode presence.
7. Keep the existing Windows x64 call convention and frame contract unchanged: RCX/RDX/R8/R9 integer arguments, EAX integer return, 32-byte shadow space, 16-byte call-site alignment, RBP frame, and existing local/temp stack-slot layout.

Dependency order: obtain normal review/integration of PR #11 (no auto-merge); complete the separate R25-R4 archive comparison; retain Issue #1 ABI gate. Only then create a fresh, isolated 7B feature branch from the accepted current baseline and run **83 + 23 + all 7B tests on the same exact commit**. No source patch, PR update, or workflow dispatch was performed in this run.

### Native compiler / DevAgent state
- Native self-hosted `SharnouCompiler.exe`: NOT BUILT / NOT RUN.
- PR #7 DevAgent: prior Windows CI run `44758761226` and artifact `14654214120` prove only a native test orchestrator. It is not a source-generating AI agent. Persistent autonomous worker/checkpoint/recovery, Windows-host deployment, and restart/runtime proof: NOT IMPLEMENTED / NOT RUN.
- M1-M6 user-local passes remain USER-REPORTED WINDOWS PASS. The current default M7A and same-head PR #11 baseline/7A results above are WINDOWS CI PASS. Source audit is REPOSITORY PRESENT / STATIC REVIEWED. No local Windows execution was performed by the assistant.


## Scheduled audit - 2026-11-23

### Repository and live branch state
- Repository: `Sharnou/Sharnou-Compiler`; default branch: `Sharnou-Compiler`; starting/default HEAD: `12a7daade17ee01519566eea5bc668ecab4a537e`.
- PR #6: OPEN / UNMERGED, branch `automation/restore-m6-83-regression`, head `9dfe1bc09685a6f7deb9d29b5192b1aae0686039`, 15 ahead / 39 behind current default. Its diff is exactly five baseline paths. It remains explicitly not mergeable by this automation.
- PR #11: OPEN / UNMERGED, branch `automation/m6-baseline-current-head-20261122`, head `135b7eec7bf13fc147756dfaeeb3f92eab57a250`, 7 ahead / 2 behind current default. The two commits behind are documentation-only changes to `Docs/AI-ISSUE-REGISTER.md` and `Docs/AI-SESSION-STATE.md`; compiler, verifier, Stage 7A test and workflow blobs match current default. Its diff remains the same five baseline paths.
- PR #5: OPEN / UNMERGED, unaccepted 7B proposal, head `0b8dee87b699eabcaaac37f111686231fb29a82c`.
- PR #7: OPEN / DRAFT, native DevAgent test-orchestrator proposal, head `ac3849800412b1208acb540ef090ffb3ac0455ca`.
- PR #4: OPEN / UNMERGED roadmap/automation proposal, head `c80828005c069956dca4ab3b045adc8afcce397b`.
- Issues #1, #8, #9 and #10 remain OPEN.

### Windows CI evidence
- Default branch run [45006046266](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45006046266), head `12a7daade17ee01519566eea5bc668ecab4a537e`, job `windows-stage7a`: SUCCESS. Stage 7A: 23 passed, 0 failed, 0 skipped; 8 positive runtime cases, 12 negative parser/type cases, 3 instruction/branch checks. ASCII/no-BOM check passed.
- PR #6 exact head: run [44700641397](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44700641397), job `windows-m6-83`, attempt 2: SUCCESS, 83/83; run [44700641419](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44700641419), job `windows-stage7a`, attempt 2: SUCCESS, 23/23.
- PR #11 exact head: run [45004395351](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45004395351), job `windows-m6-83`: SUCCESS, 83/83; run [45004395353](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45004395353), job `windows-stage7a`: SUCCESS, 23/23. Both ran against the same exact PR head.
- The 83-case suite breakdown is Stage 2 25/25, Stage 4 20/20, PE verifier 4/4, Stage 5 25/25 and Stage 6 9/9. Case-intent classification is 36 positive / 47 negative; the manifest and workflow aggregate report suite totals rather than separate polarity totals. The Stage 2 adapter moves the obsolete pre-7A `if` rejection fixture into the positive set in a temporary copy; the frozen payload and original script remain unchanged.
- PR #5 run [44693097619](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44693097619), exact head `0b8dee87b699eabcaaac37f111686231fb29a82c`: SUCCESS, Stage 7A 23/23 and proposed Stage 7B 32/32 (15 positive, 13 negative, 4 instruction checks). It did not run the 83-case baseline.
- PR #7 run [44758761226](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44758761226), exact head `ac3849800412b1208acb540ef090ffb3ac0455ca`: SUCCESS. Native `SharnouDevAgent.exe` was built with SHA-256 `9F128ED96972858B13C763B4324813B3D6A1970737F2403C10C70717CE947341`, executed with process exit code 0, and propagated a child exit code of 7. Artifact ID `14654214120`, ZIP digest `sha256:94a10a4ac3cb48f09c70497f2f9b6f63c46d8eaf183ed987e5a97d39d6aec8d1`, size 2556 bytes; expires 2026-12-04.

### Source and static audit
- Current default compiler blob: `ee01ef77b068df5d149934fbf463c43b34c54bf3`; Windows baseline runner reported compiler SHA-256 `f1cb1ea2920c62c781f317b52ba281c2a7df72f626638a4aab71ff8d2dd47ead`.
- Current PE verifier blob: `3606b57920043882a2277ad41fd0e0578156944a`; Windows baseline runner reported verifier SHA-256 `8efec55da3a1614f30272227f8d8158710337cb06148fb7f98b8fa2ff013a3de`.
- Stage 7A test blob `80d8df1c9a6da7c8fb6f2b414c2929f07ba44804` and workflow blob `2b982f0165495854b52d346637e457932a5b0271` match between default and PR #11.
- Static review confirms the Stage 7A parser accepts if/else and while with integer conditions, supports the six signed integer comparisons, rejects chained comparisons, and uses signed SETcc plus MOVZX. The emitter uses TEST/JZ and JMP rel32 labels through the existing code-fixup pass. The machine-code tests verify opcode byte-pattern presence; they do not independently decode every rel32 displacement and validate its destination.
- The baseline runner pins the original archive SHA-256 `0b6bf15445a5dfd8cbf93450af7fd2f5fd6239d4ed082ab18b09878a94b8b164` and bundle SHA-256 `3dd1d7417874159c0bc625edbbc1e8cee1ae7d8a6ea42f30b4dd80ba92102748`. It verifies the compressed bundle and member hashes embedded in that bundle, but does not read the original `SHA256SUMS.txt`; the manifest's `members_verified_against_original_sha256_manifest` field is not enforced by the runner. The separate R25-R4 archive comparison remains NOT RUN (archive SHA-256 `CA01AEACB2E35C6E8039E58F15202A01399DAEA3E0A24E7B4D357772C8EF1274`).
- PR #5 remains proposal-only. Its tests use constant literal left operands for short-circuit skip/evaluate cases; add dynamic-variable-left side-effect cases. Add explicit Boolean function argument/return rejection tests, deeper nested-loop cases, and a rel32 target decoder. Keep the function ABI integer-only until a separate ABI design is accepted.
- PR #7 is not an AI source-generating agent. Its Sharnou program checks workspace files, probes child exit-code propagation, and launches the Stage 7A PowerShell regression suite. Its `sh_dev_run_process` accepts a command-line string (maximum 1023 bytes), calls CreateProcessA, inherits standard handles and waits indefinitely; no command allowlist, sandbox, timeout, job-object process-tree containment or cancellation is present. Do not expose it to model-generated commands before a reviewed execution policy exists.

### Build/runtime classification and next dependency
- Evidence: WINDOWS CI PASS for default Stage 7A, PR #6 / PR #11 baseline and Stage 7A, PR #5 candidate tests, and PR #7 native test-orchestrator build/runtime. USER-REPORTED WINDOWS PASS remains the evidence class for earlier M1-M6 user-local runs. Source review is REPOSITORY PRESENT / STATIC REVIEWED. Assistant-side local Windows execution: NOT RUN.
- Native self-hosted `SharnouCompiler.exe`: NOT BUILT / NOT RUN. PR #7's native DevAgent artifact is PR-only and is a regression orchestrator, not an AI developer.
- Issue #1 ABI gates remain OPEN: large-frame stack probing, PE unwind metadata, runtime nonvolatile-register/RSP/stack-argument sentinels, and generic checked Windows API-call marshalling. Persistent agent worker/checkpoint/recovery, model connectivity, source generation, Windows-host deployment and restart proof are NOT IMPLEMENTED / NOT RUN.
- No compiler, verifier, test, build-script, runtime, Engine or game source changes were made. No workflow was dispatched. The only intended writes in this session are the authorized status documents and issue records.
- Do not update the accepted development plan: 7B remains unaccepted. Next dependency order is normal human review/integration decision for PR #11 (never auto-merge), complete the R25-R4 file-by-file comparison and retain the Issue #1 ABI gate; only then create a fresh isolated 7B branch and require 83 + 23 + all 7B cases on one exact commit. Before any autonomous agent code execution, design and review a bounded process policy, durable worker/checkpoint/recovery, audit trail and restart test.


## DevAgent autonomy architecture session - 2026-11-24

### User request
The user requested SharnouDevAgent be advanced from a simple test orchestrator to a high-capability development agent: internet/local search, read/download/learn, structured reasoning and planning, specialist agent creation/editing, bug solving and bounded automatic correction, authorized reverse engineering, and optional second opinions from ChatGPT/OpenAI or Perplexity, without requiring those services for local operation.

### Repository preflight and exact source audit
- Mandatory read-first documents read from the current branch: `AGENTS.md`, `AI_START_HERE.md`, `Docs/AI-SESSION-STATE.md`, `Docs/AI-DEVELOPMENT-PLAN.md`, `Docs/AI-ISSUE-REGISTER.md`, and `README.md`.
- Starting default branch HEAD: `cf8a9cd26cf3819d1ee3156155eafa5259c39b05`.
- Current Stage 0 compiler blob `ee01ef77b068df5d149934fbf463c43b34c54bf3` does not contain `sh_dev_run_process`, `CreateProcessA`, or `GetExitCodeProcess`. The DevAgent native test utility is only on open draft PR #7's `automation/sharnou-dev-agent-native` branch.
- PR #7's `Examples/DevAgent.sharnou` checks workspace files, probes child exit-code propagation, and launches the Stage 7A PowerShell regression suite. Its own PR description explicitly states it is a native test/development orchestrator, not an AI source-generating agent.
- PR #7 branch compiler blob `86d9d25350d581b165ee79b0664f8b6640e6408b` implements `sh_dev_run_process(String)->Integer` using `CreateProcessA`, waits with `WaitForSingleObject(INFINITE)`, returns the child code with `GetExitCodeProcess`, and uses a fixed 1024-byte command buffer. Static inspection found no executable allowlist, structured argument vector, timeout, cancellation, Job Object process-tree containment, restricted-token/AppContainer policy, or durable task journal. Do not expose this interface to model-generated command strings.
- PR #7 remains an open draft according to the repository status record. Its Windows run `44758761226` passed as a test orchestrator and uploaded artifact `14654214120`; this is not evidence of AI code generation or autonomous repair.
- The current plan/state still record the frozen 83-case M1-M6 suite as absent from default pending normal PR #11 integration, M7A as Windows-CI tested but not separately user-locally recorded in that state, and ABI issue #1 as open. These preconditions remain material to compiler-controlled autonomy.

### Persisted design
- Added `Docs/SHARNOU-DEVAGENT-AUTONOMOUS-ARCHITECTURE.md` (commit `0e05166c1ef284af9ccdc3ecb2ada19262364c58`).
- Added a README roadmap link (commit `3d8fb0bacb01cf82730d904d1cc2a40f0290765e`).
- Created tracking issue [#14](https://github.com/Sharnou/Sharnou-Compiler/issues/14).
- The architecture specifies an in-process Sharnou-owned local inference runtime, typed tool registry, safe process broker, native WinHTTP search/fetch/download, quarantine/hash/provenance, local knowledge index, task graph and evidence journal, declarative agent manifests, staged patch/rollback loops, authorized static PE/x64 reverse engineering, and optional OpenAI Responses / Perplexity Agent API adapters.
- Remote provider calls are optional. A local model and its weights are required for generative offline reasoning; retrieval memory alone is not model training. Local operations must work with networking disabled.
- Agent-generated operations are limited by capability and workspace policy. No unrestricted shell, privilege escalation, silent policy changes, auto-execution of downloads, auto-merge, or auto-release. External API credentials must be protected with Windows Credential Manager or DPAPI and must not be exposed to prompts/logs.

### Changed paths and execution evidence
- Changed only documentation/tracking: `Docs/SHARNOU-DEVAGENT-AUTONOMOUS-ARCHITECTURE.md`, `README.md`, `Docs/AI-DEVELOPMENT-PLAN.md`, `Docs/AI-SESSION-STATE.md`, `Docs/AI-ISSUE-REGISTER.md`, and issue #8/#14 records.
- No compiler, PE verifier, example, test fixture, build script, workflow, Engine, IDE, or game source was modified. No branch/PR was merged, no workflow was dispatched, and no Windows build or native test was executed by the assistant.
- Evidence classification: REPOSITORY PRESENT / STATIC REVIEWED for the existing DevAgent code and architecture proposal; WINDOWS CI PASS (historical PR #7 test-orchestrator run only); NOT IMPLEMENTED / NOT RUN for the autonomous AI agent and local LLM runtime.

### Dependency-ordered next actions
1. Keep the 83-case restoration/provenance gate and issue #1 ABI audit open; no autonomous compiler write access until these gates are reconciled.
2. Design/implement Phase B process broker first: typed executable IDs and argument arrays, canonical workspace roots, hash allowlists, timeouts/cancellation, process-tree containment, bounded I/O, and negative tests. Do not reuse PR #7's raw command-line API for model-directed execution.
3. Implement native research/read/download and quarantine with host policy and integrity evidence.
4. Build one supported Sharnou-owned local model inference path and prove offline operation with model-file hash and golden-vector tests.
5. Add task planning, evidence memory/restart recovery, agent manifest factory, bounded repair/rollback, and static reverse-engineering tools.
6. Add optional remote AI adapters only after local mode is independently functional and credential/redaction tests pass.

This session is architecture and governance only; it is not a claim that SharnouDevAgent has gained these capabilities.


## Scheduled audit - 2026-11-24 08:15 Africa/Cairo

### Live repository and pull-request state

- Repository: `Sharnou/Sharnou-Compiler`; default branch: `Sharnou-Compiler`.
- Starting default HEAD: `ff24777d241332ffc5a6a43d16cc688ff9f4dff7`.
- The mandatory current-branch documents were read: `AGENTS.md`, `AI_START_HERE.md`, `Docs/AI-SESSION-STATE.md`, `Docs/AI-DEVELOPMENT-PLAN.md`, `Docs/AI-ISSUE-REGISTER.md`, `README.md`, and the renderer roadmap. Directly relevant compiler, verifier, Stage 7A/7B tests, workflow, baseline runner/manifest/payload metadata, DevAgent prototype, architecture, issues and PR discussions were inspected.
- PR #4: OPEN / UNMERGED, roadmap proposal, head `c80828005c069956dca4ab3b045adc8afcce397b`.
- PR #5: OPEN / UNMERGED, unaccepted 7B proposal, head `0b8dee87b699eabcaaac37f111686231fb29a82c`; compare 2 ahead / 46 behind.
- PR #6: OPEN / UNMERGED, frozen baseline restoration, head `9dfe1bc09685a6f7deb9d29b5192b1aae0686039`; compare 15 ahead / 46 behind. Do not merge this PR by automation.
- PR #7: OPEN / DRAFT, native test orchestrator, head `ac3849800412b1208acb540ef090ffb3ac0455ca`; compare 9 ahead / 46 behind.
- PR #11: OPEN / UNMERGED, fresh baseline integration candidate, head `135b7eec7bf13fc147756dfaeeb3f92eab57a250`; compare 7 ahead / 9 behind. Its diff remains exactly the five baseline paths. The nine commits by which it is behind are documentation-only: compare from its merge base `45c83e1941fd74ca1ce94a4f0bc9ffe72a43efe3` to current default changes only the AI plan, issue register, session state, DevAgent architecture document, and README.
- PR #13: OPEN / DRAFT, documentation-only reverse-engineering capability proposal, head `43d2447cdbadb6280fbcc3b190c666c07b97b352`; compare 2 ahead / 5 behind.
- Issues #1, #8, #9, #10, #12 and #14 remain OPEN. No issue state was changed.

### Windows Actions evidence

- Default branch run [45291564684](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45291564684), exact HEAD `ff24777d241332ffc5a6a43d16cc688ff9f4dff7`, job `windows-stage7a` (`138101331576`): SUCCESS. Source encoding/no-BOM PASS; Stage 7A 23 passed, 0 failed, 23 total (8 positive runtime, 12 negative diagnostics, 3 instruction/branch checks). The workflow log did not separately print a numeric PowerShell process exit code; the Actions step and job concluded success.
- PR #6 latest same-head Windows runs remain [44700641397](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44700641397), job `136468493547`, SUCCESS, frozen baseline 83/83; and [44700641419](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44700641419), job `136468505598`, SUCCESS, Stage 7A 23/23. Both were attempt 2 on PR #6 head `9dfe1bc09685a6f7deb9d29b5192b1aae0686039`.
- PR #11 same-head Windows runs [45004395351](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45004395351), job `137152637466`, SUCCESS, 83/83; and [45004395353](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45004395353), job `137152637335`, SUCCESS, Stage 7A 23/23. Both ran on exact PR #11 head `135b7eec7bf13fc147756dfaeeb3f92eab57a250`, so the 83-case suite and Stage 7A passed on one exact commit. Suite totals: Stage 2 25, Stage 4 20, PE verifier 4, Stage 5 25, Stage 6 9; 83 passed, 0 failed. The case-intent split is 36 positive / 47 negative; the runner does not emit a separate skipped counter, and all 83 inventory cases are accounted for.
- The five baseline file blobs on PR #11 are identical to PR #6: workflow `c6a27e24a7d0bad9eaf554bb59c1d81e0f865c47`, graphics module `6644243df729fc0334b617231e40b3496e15016d`, payload `d2c1faa72e702d0575ac1623d89b56c087edddb8`, runner `1bc252b197ba244ea9910ad67b4b8b3cd141138d`, manifest `bbf9a2beb87b84bb51261a28268247d96419424c`. The compiler, verifier, root test runner, Stage 7A test and Stage 7A workflow blobs on current default are identical to PR #11 and PR #6.
- PR #5 run [44693097619](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44693097619), job `136143353548`, SUCCESS: Stage 7A 23/23 and proposed Stage 7B 32/32 (15 positive runtime, 13 negative diagnostics, 4 instruction-pattern checks). It did not run the 83-case baseline and is not acceptance evidence for current default.
- PR #7 run [44758761226](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44758761226), job `136467612083`, SUCCESS: built and PE-verified the native DevAgent test utility, ran it, verified intentional child exit code 7 propagation, and reported DevAgent process exit code 0. Artifact ID `14654214120`; artifact ZIP SHA-256 `94a10a4ac3cb48f09c70497f2f9b6f63c46d8eaf183ed987e5a97d39d6aec8d1`.
- PR #13 documentation-only run [45286151951](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45286151951), job `138082870219`, SUCCESS; Stage 7A 23/23. No code was changed by that PR.
- PR #4 earlier roadmap workflow run `44594385914` concluded success at its recorded head; no new PR #4 workflow was dispatched.

### Compiler, baseline and Milestone 7B audit

- Current compiler SHA-256, reported by the same-source Windows baseline job: `f1cb1ea2920c62c781f317b52ba281c2a7df72f626638a4aab71ff8d2dd47ead`. Current PE verifier SHA-256: `8efec55da3a1614f30272227f8d8158710337cb06148fb7f98b8fa2ff013a3de`. Current Stage 7A test Git blob: `80d8df1c9a6da7c8fb6f2b414c2929f07ba44804`; previously recorded content SHA-256: `ffd8a3518d8fc943adb97e319a29a8822d4e5c409226597d0010b40da23eae05`.
- Stage 7A source review confirms six signed SETcc comparisons normalized by MOVZX, conditional TEST/JZ and JMP rel32 code fixups, unresolved-label rejection, and signed-32-bit displacement bounds. Existing three machine-code checks detect instruction patterns but do not independently validate each branch destination. This is a test-strengthening gap, not a reproduced runtime defect.
- The 83-case baseline is still absent from default. Original M6 archive SHA-256: `0b6bf15445a5dfd8cbf93450af7fd2f5fd6239d4ed082ab18b09878a94b8b164`; compressed payload SHA-256: `3dd1d7417874159c0bc625edbbc1e8cee1ae7d8a6ea42f30b4dd80ba92102748`; recorded original `SHA256SUMS.txt` SHA-256: `61539cb577b3c116d25739cdb8286e3de38410af1d1a39fa1418893799f3c9c9`. The runner verifies the pinned bundle and each restored member against hashes embedded in the payload, but does not independently read/verify the original `SHA256SUMS.txt`. The manifest currently says members were verified against that original manifest; the runner does not enforce that claim. The separate R25-R4 archive comparison (SHA-256 `CA01AEACB2E35C6E8039E58F15202A01399DAEA3E0A24E7B4D357772C8EF1274`) remains NOT RUN.
- PR #5 remains a proposal only. Its dynamic short-circuit lowering uses conditional branches, but the existing side-effect tests use literal left operands; add variable-left skip/evaluate cases for both AND and OR. Add explicit negative tests for Boolean function arguments and Boolean returns while the function ABI remains integer-only; add a deeper nested-loop case; and replace opcode-presence-only checks with a linker fixup self-check that decodes each emitted rel32 displacement and verifies its target label lies within .text. The existing nested-loop test does exercise innermost-loop break/continue.
- Static correction: `Get-ConstantValue` visits the right subtree when the logical left operand is dynamic in order to validate constant arithmetic. This is not proof that the runtime evaluates the RHS and is not a reproduced short-circuit defect; treat it as compile-time validation policy. The concrete gap is the absence of dynamic-left runtime tests.
- Minimum acceptance for a fresh 7B candidate: frozen M1-M6 83 + Stage 7A 23 + existing Stage 7B 32, plus the new required tests, all on one exact Windows commit with zero failures and zero skipped cases. Do not reuse or merge the stale PR #5 branch as the current implementation.

### Native compiler and SharnouDevAgent state

- PR #7 generated native AMD64 PE32+ `SharnouDevAgent.exe` SHA-256 `9F128ED96972858B13C763B4324813B3D6A1970737F2403C10C70717CE947341` on the Windows runner. It is a native test orchestrator only: workspace checks, child-process exit-code propagation, and a Stage 7A regression launch. It is not present on default and does not generate or edit source.
- The PR #7 process intrinsic accepts a raw command string, calls CreateProcessA, inherits standard handles, and waits with INFINITE. There is no allowlist, structured argument boundary, workspace sandbox, timeout/cancellation, Job Object process-tree containment, or output bound. It must not receive model-generated commands.
- Native self-hosted `SharnouCompiler.exe`: NOT BUILT / NOT RUN. Autonomous AI source generation, local inference, durable worker/checkpoint/recovery, deployment and restart proof: NOT IMPLEMENTED / NOT RUN. The architecture document and issue #14 are proposals, not implementation evidence.
- Historical ABI gates in issue #1 remain open: large-frame stack probing, PE unwind metadata, nonvolatile-register/RSP/argument runtime probes, and generic checked Windows API marshalling.

### Scope and next bounded task

- No compiler, verifier, test, fixture, build script, runtime, Engine, IDE, game or workflow source changes. No workflow dispatch, PR creation/modification/merge, deployment, or local Windows execution. The accepted development plan is unchanged because 7B and the additional DevAgent capabilities remain unaccepted proposals.
- Evidence: USER-REPORTED WINDOWS PASS (historical M1-M6 report); WINDOWS CI PASS (default 7A 23/23; PR #11 same-head 83/83 + 7A 23/23; PR #6 83/83 + 7A 23/23; PR #5 proposal 7A 23/23 + 7B 32/32; PR #7 native test orchestrator; PR #13 docs-only workflow); REPOSITORY PRESENT / STATIC REVIEWED (current compiler, baseline runner/manifest, 7B proposal and DevAgent architecture); NOT RUN (R25-R4 archive comparison, ABI runtime probes, user-local 7A acceptance, native self-hosted compiler, autonomous AI agent); BLOCKED (default baseline integration and remaining provenance/ABI gates).
- Next bounded task: obtain normal human review for PR #11 without automated merge; complete the independent R25-R4 archive comparison and resolve the original SHA256SUMS provenance discrepancy. Then complete the ABI gate plan. Only after explicit 7B scope approval, prepare a fresh isolated patch from the then-current default and require the combined baseline + 7A + 7B suite on one exact commit.


### Post-status documentation CI verification - 2026-11-24

The two status-only commits above triggered the existing push workflow; both completed successfully:
- Run [45340099960](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45340099960), exact commit `1d55cd00d93e60d0c57bf5be180b7afe229d2a3d`, job `windows-stage7a` (`138261413749`): SUCCESS; source encoding PASS; Stage 7A 23 passed, 0 failed, 23 total.
- Run [45340141791](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45340141791), exact commit `f4c018f171b45e997615b7e933281a0401804e43`, job `windows-stage7a` (`138261550209`): SUCCESS; source encoding PASS; Stage 7A 23 passed, 0 failed, 23 total.
- These are documentation-only follow-up CI checks, not new compiler-source, baseline, or 7B runs. The PowerShell test step did not print a separate numeric process exit code; the step and job concluded success.
- GitHub issue #8 was updated with the same follow-up evidence. No issue state changed.


## Scheduled audit update - 2026-11-25 08:47 Africa/Cairo

### Live repository and branch state
- Repository: `Sharnou/Sharnou-Compiler`; default branch: `Sharnou-Compiler`.
- Starting HEAD: `b817cc59f281a732f0e4759be87a00ec7ef63df6`. This is the current branch ref verified immediately before this status update.
- The latest default-branch Stage 7A workflow is [45340141791](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45340141791), SUCCESS on parent commit `f4c018f171b45e997615b7e933281a0401804e43`. It ran 23/23 (8 positive, 12 negative, 3 instruction checks). Current HEAD `b817cc5` has no run attached (GitHub returned zero runs for that exact SHA); it is a status-only `[skip ci]` commit after the tested parent.
- Current HEAD, tested parent `f4c018f`, and PR #11 head `135b7eec7bf13fc147756dfaeeb3f92eab57a250` have identical Git blobs for `Stage0/SharnouCompiler.ps1`, `Tools/SharnouPEVerify.ps1`, `Test.ps1`, `Tests/Test-Stage7A.ps1`, and `.github/workflows/stage7a-control-flow.yml`.
- Current blob IDs: compiler `ee01ef77b068df5d149934fbf463c43b34c54bf3`; verifier `3606b57920043882a2277ad41fd0e0578156944a`; root runner `699eb04aefdf1149aa5807107ce351f8c2aae676`; Stage 7A test `80d8df1c9a6da7c8fb6f2b414c2929f07ba44804`; workflow `2b982f0165495854b52d346637e457932a5b0271`.
- Windows CI source SHA-256 values from the same-source PR #11 baseline run: compiler `f1cb1ea2920c62c781f317b52ba281c2a7df72f626638a4aab71ff8d2dd47ead`; PE verifier `8efec55da3a1614f30272227f8d8158710337cb06148fb7f98b8fa2ff013a3de`.

### Current pull-request inventory
All remain OPEN / UNMERGED; no PR was modified or merged.
- PR #2 release database/publisher: head `4f16c9426cd51ad3bdfe97e7f1691a8fa26e218f`, 10 ahead / 56 behind.
- PR #4 roadmap/automation proposal: head `c80828005c069956dca4ab3b045adc8afcce397b`, 5 ahead / 49 behind.
- PR #5 7B candidate: head `0b8dee87b699eabcaaac37f111686231fb29a82c`, 2 ahead / 49 behind; not user-accepted.
- PR #6 frozen baseline restoration: head `9dfe1bc09685a6f7deb9d29b5192b1aae0686039`, 15 ahead / 49 behind. It remains open and must not be merged by automation.
- PR #7 native DevAgent test orchestrator: draft, head `ac3849800412b1208acb540ef090ffb3ac0455ca`, 9 ahead / 49 behind.
- PR #11 preferred baseline integration candidate: head `135b7eec7bf13fc147756dfaeeb3f92eab57a250`, 7 ahead / 12 behind. Its five-file baseline diff is unchanged; the 12 commits behind are documentation-only. It remains open for normal human review, not automatic merge.
- PR #13 reverse-engineering audit documentation: draft, head `43d2447cdbadb6280fbcc3b190c666c07b97b352`, 2 ahead / 8 behind.

### Windows workflow evidence and test accounting
- Default Stage 7A: run [45340141791](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45340141791), job `138261550209`, SUCCESS; 23 passed, 0 failed, 23 total. The log includes ASCII/no-BOM PASS. No explicit process exit code is printed; the job completed successfully.
- PR #6 exact head: [44700641397](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44700641397), attempt 2, SUCCESS, 83/83; and [44700641419](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44700641419), attempt 2, SUCCESS, Stage 7A 23/23.
- PR #11 exact head: [45004395351](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45004395351), SUCCESS, 83/83; and [45004395353](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45004395353), SUCCESS, Stage 7A 23/23. Both tested the same exact PR head.
- PR #5 old candidate: [44693097619](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44693097619), SUCCESS; Stage 7A 23/23 and proposed Stage 7B 32/32 (15 positive runtime, 13 negative diagnostics, 4 instruction-presence checks). It did not run the 83-case baseline.
- PR #7 native utility: [44758761226](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44758761226), attempt 2, SUCCESS. It built and ran the native utility, re-ran Stage 7A 23/23, verified child exit code 7 propagation, and reported DevAgent process exit code 0. Artifact ID `14654214120`.
- PR #13 documentation branch: [45286151951](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45286151951), SUCCESS, Stage 7A 23/23; this is not new implementation evidence.
- Frozen M1-M6 accounting: Stage 2 25, Stage 4 20, PE verifier 4, Stage 5 25, Stage 6 9 = 83. Case-intent classification is 36 positive / 47 negative, inferred from case names; the manifest records suite totals only. The Windows runner reports 83 passed and 0 failed; it does not separately print a skipped count.
- Stage 7A accounting: 8 positive, 12 negative, 3 instruction checks = 23. The Windows log reports 23 passed, 0 failed.
- Stage 7B candidate accounting: 15 positive, 13 negative, 4 instruction checks = 32. The Windows log reports 32 passed, 0 failed.

### Baseline provenance audit
- PR #11 runner blob: `1bc252b197ba244ea9910ad67b4b8b3cd141138d`; manifest blob: `bbf9a2beb87b84bb51261a28268247d96419424c`.
- Frozen M6 archive SHA-256: `0b6bf15445a5dfd8cbf93450af7fd2f5fd6239d4ed082ab18b09878a94b8b164`; compressed payload SHA-256: `3dd1d7417874159c0bc625edbbc1e8cee1ae7d8a6ea42f30b4dd80ba92102748`; original `SHA256SUMS.txt` digest: `61539cb577b3c116d25739cdb8286e3de38410af1d1a39fa1418893799f3c9c9`.
- Reconfirmed: the runner verifies the compressed payload and each member against the hash embedded inside that payload. It does not load or independently verify the original `SHA256SUMS.txt`, despite manifest field `members_verified_against_original_sha256_manifest: true`. This is a provenance-verification gap, not a failed 83-case test.
- R25-R4 archive SHA-256 remains `CA01AEACB2E35C6E8039E58F15202A01399DAEA3E0A24E7B4D357772C8EF1274` (611 entries per issue #1). The Library search found related reports and checksum sidecars but not the archive bytes. No archive download was attempted under the no-download constraint; the file-by-file comparison remains NOT RUN. Issue #9 stays OPEN.
- PR #11 still has the five baseline files only on its feature branch. The 83-case baseline is not integrated into default.

### Milestone 7B proposal audit (no implementation)
- PR #5 remains an old, unaccepted candidate. Its 7B compiler blob is `e884d5223bad5e8fdbb048c5414bc547c4d22ada`; its test blob is `0c0bdbf2b8ec23b1445329b86d9d94b8653e7aed`.
- The four short-circuit side-effect tests use literal left operands (`false &&`, `true ||`, `true &&`, `false ||`). Add runtime tests with Boolean variables on the left for both skip and evaluate paths of AND and OR.
- The implementation emits runtime conditional branches for logical expressions. The `Get-ConstantValue` pass visits a dynamic-left RHS for compile-time constant-arithmetic validation; this is not proof that the runtime evaluates the RHS and no runtime short-circuit defect was reproduced.
- Function parameters are implicitly Integer and function return expressions are explicitly required to be Integer. Boolean arguments/returns should remain rejected while the ABI is integer-only, but the current suite lacks dedicated negative cases for those two contracts.
- The existing nested loop test covers two loop levels. Add a three-level case that proves innermost break/continue do not corrupt parent-loop targets.
- Existing machine checks search for `0F 84`, `0F 85`, `E9`, and `C3` byte patterns; they do not decode rel32 displacements or verify branch destinations/instruction boundaries.
- Minimal proposed test expansion: four dynamic-variable-left short-circuit runtime cases, two Boolean function ABI rejection cases, and one deeper nested-loop runtime case. This would raise the candidate suite from 32 to 39 (20 positive, 15 negative, 4 strengthened machine checks). Require 83 + 23 + 39 = 145 result records on one exact Windows commit before acceptance. This is a proposal only, not an accepted milestone or a test result.
- Do not use PR #5 as a direct implementation base without reconciling its 49-commit divergence. A fresh isolated branch is required after the baseline dependency and explicit implementation authorization.

### Native SharnouDevAgent state
- PR #7 run [44758761226](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44758761226) built a genuine AMD64 PE32+ utility with SHA-256 `9F128ED96972858B13C763B4324813B3D6A1970737F2403C10C70717CE947341`; artifact ZIP ID `14654214120`. The utility process exited 0 and correctly propagated child exit code 7.
- This is a Stage 0 bootstrap-generated native test orchestrator, not a Sharnou-compiled self-hosted compiler or AI source-generating agent.
- No native `SharnouCompiler.exe`, local model inference, autonomous source generation, persistent worker, checkpoint/recovery, Windows-host deployment, or restart proof exists in the verified evidence.
- PR #7 uses a free-form command string with `CreateProcessA` and indefinite wait. No reviewed executable allowlist, typed argument boundary, workspace sandbox, timeout/cancellation, Job Object process-tree containment, or output limit is present. Do not pass model-generated commands to it.

### Evidence classification and work performed
- WINDOWS CI PASS: runs 45340141791, 44700641397, 44700641419, 45004395351, 45004395353, 44693097619, 44758761226, and 45286151951 as described above.
- USER-REPORTED WINDOWS PASS: historical M1-M6 acceptance remains user-reported; no new local execution is claimed.
- REPOSITORY PRESENT / STATIC REVIEWED: current compiler, verifier, 7A tests, baseline runner/manifest, 7B candidate, DevAgent architecture and PR diffs.
- NOT RUN: assistant-side Windows execution, R25-R4 byte comparison, user-local M7A run, ABI runtime sentinels/stack-probe/unwind tests, native self-hosted compiler, and autonomous-agent restart/deployment tests.
- BLOCKED: baseline PR integration/provenance and the outstanding Windows x64 ABI gate in issue #1.
- No compiler, verifier, test, fixture, build script, runtime, Engine, IDE, or game source changed. No workflow was dispatched. No PR was created, edited, merged, or rebased.
- Only this status record is being appended to `Docs/AI-SESSION-STATE.md`; issue #8 is updated separately. The issue register and accepted development plan remain unchanged because no blocker status or accepted scope changed.

### Next bounded task
Normal human review of PR #11 remains the integration decision; do not auto-merge. Complete the R25-R4 comparison only when the archive bytes are supplied through an approved accessible source, and retain issue #1 ABI gates. After the baseline dependency is accepted and the user explicitly authorizes implementation, start a fresh isolated 7B branch with the proposed 39-case coverage and same-commit 145-case Windows gate. DevAgent process-broker security work must precede model-controlled execution.


## Manual DevAgent audit - 2026-11-25 16:45 Africa/Cairo

- Repository: `Sharnou/Sharnou-Compiler`; branch: `Sharnou-Compiler`; starting HEAD: `2dfceaa72b609fd3b8f839605ee5582e7b686151`.
- Read the current `AGENTS.md`, `AI_START_HERE.md`, `README.md`, all six files in `Docs/`, the current open issue set, and the relevant PR #7 / PR #13 context before acting.
- Default-branch source audit: no `DevAgent/` source tree, no `Examples/DevAgent.sharnou`, no `Tests/Test-DevAgent.ps1`, and no `sh_dev_run_process` / `CreateProcessA` DevAgent intrinsic exists on the default branch. The only native DevAgent source reviewed is on stale, open, draft PR #7.
- PR #7 is `automation/sharnou-dev-agent-native`, head `ac3849800412b1208acb540ef090ffb3ac0455ca`; compare to current default is DIVERGED, 9 commits ahead / 50 behind, 9 changed files, and GitHub reports it not mergeable. It must not be treated as the current implementation or merged as-is.
- PR #7 security defects confirmed in its source: `sh_dev_run_process(String)` passes a free-form command line to `CreateProcessA`; the caller can choose the executable and arguments; standard handles are inherited; the wait uses `WaitForSingleObject(INFINITE)`; there is no executable registry/hash allowlist, argument schema, workspace-root confinement, bounded output capture, timeout/cancellation, Job Object process-tree containment, or restricted execution boundary. Do not pass model-generated text to this function and do not rerun this prototype before replacing that interface.
- The only recorded native DevAgent run is Windows Actions run [44758761226](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44758761226), job `136467612083`, on the stale PR #7 head. It succeeded at building and launching a 2,556-byte artifact; the utility propagated child exit code 7, ran the Stage 7A suite twice (23/23 each time), reported its own exit code 0, and uploaded artifact `14654214120`. Its actual response contains `Self-hosted native SharnouCompiler.exe: NOT YET IMPLEMENTED` and `SharnouDevAgent result: PASS`. That PASS means only that the fixed regression-orchestration demonstration completed; it is not an AI-generated diagnosis, source patch, autonomous repair, local inference result, or self-hosting result.
- Issue #14 remains an architecture/implementation request, not an implementation: local inference, planner, durable evidence/task memory, agent profiles, autonomous patch/rollback, and restart recovery are not present. Issue #12 remains a proposal for read-only PE/DLL/shader analysis; no analyzer implementation was found on default.
- Blocking prerequisites remain unchanged: issue #9 / PR #11 still holds the 83-case baseline outside default and requires human review plus the outstanding provenance comparison; issue #1 remains open for large-frame stack probing, PE `.pdata`/`.xdata` unwind metadata, runtime nonvolatile-register/RSP/argument probes, and checked generic API-call marshalling. The DevAgent architecture explicitly requires these preconditions before model-controlled process execution.
- No safe DevAgent implementation was available to execute on the default branch. The old PR #7 workflow was not rerun because doing so would execute its unbounded free-form process runner. No compiler, test, workflow, runtime, or Engine source was modified; no process was launched; no workflow was dispatched; no PR was edited, rebased, or merged.
- Evidence classification: **REPOSITORY PRESENT / STATIC REVIEWED** for the current docs, issue/PR state, and PR #7 source; **WINDOWS CI PASS** for historical run 44758761226 on PR #7 only; **NOT RUN** for any current-default DevAgent, local model, source generation, autonomous repair, timeout/cancellation, sandbox, restart recovery, or PE reverse-engineering execution; **BLOCKED** for safe implementation pending issue #9 and issue #1 gates.
- Next bounded dependency: complete normal human review/integration and provenance work for the frozen baseline, close the ABI gates with Windows runtime evidence, then start a fresh feature branch for the typed, allowlisted process broker and its adversarial tests. Only after those gates should research/knowledge, local inference, planning/subagents, bounded repair, and the optional reverse-engineering/provider phases proceed.


### Automatic documentation-push CI follow-up - 2026-11-25

- The two status-document commits above automatically triggered the existing default-branch Stage 7A workflow; this was not a manual workflow dispatch and did not run DevAgent.
- [Run 45638617425](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45638617425), exact commit `fe368f37eb4204f8eb568f933a9c684a3b22e5f3`: Windows job succeeded; ASCII/no-BOM PASS; Stage 7A 23 passed, 0 failed, 23 total.
- [Run 45638680338](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45638680338), exact commit `6899a086bb9b212a7a1e714d1e8fba375ae28fb6`: Windows job succeeded; ASCII/no-BOM PASS; Stage 7A 23 passed, 0 failed, 23 total; job exit was successful.
- These were documentation-only follow-up runs. They do not rerun PR #7, do not build or launch SharnouDevAgent, and do not close issue #1, #9, #12, or #14. The historical DevAgent response remains the output recorded under run 44758761226.


## DevAgent reverse-engineering capability request - 2026-11-25 18:26 Africa/Cairo

- User requested a Windows Binary Reverse Engineer capability for SharnouDevAgent covering core modules `KERNEL32.dll`, `USER32.dll`, `GDI32.dll`, `D3D11.dll`, and `DXGI.dll`; optional graphics/text modules `D2D1.dll`, `DWrite.dll`, and `DWMAPI.dll`; system integration modules `SHELL32.dll`, `ADVAPI32.dll`, and `OLE32.dll`; and optional/legacy developer modules `D3D11SDKLayers.dll`, `D3DCompiler_47.dll`, and `D3DCompiler_43.dll`. The user also requires an extensible catalog for additional Windows DLLs required by future compiler/Engine features.
- Read the current `AGENTS.md`, `AI_START_HERE.md`, `Docs/AI-SESSION-STATE.md`, `Docs/AI-DEVELOPMENT-PLAN.md`, `Docs/AI-ISSUE-REGISTER.md`, `README.md`, current compiler and PE verifier, Stage 7A tests, and current issues/PRs/commit evidence.
- Starting default-branch HEAD: `4a1b98cafaf499e5f9046fd56b647c0649602b1b` on `Sharnou-Compiler`. No workflow run is attached to this status-only commit.
- The request maps to existing open issue [#12 - Windows Binary Reverse Engineer capability](https://github.com/Sharnou/Sharnou-Compiler/issues/12), which already specifies read-only PE/COFF inspection, the same Windows DLL families, the D3DCompiler entry points `D3DCompile`, `D3DCompileFromFile`, `D3DDisassemble`, and `D3DCreateBlob`, System32-only allowlisted capability probes, and optional D3D11 debug-layer fallback. The additional owner requirement is that the DLL catalog be data-driven and extensible; new DLLs require an explicit role, required/optional/legacy classification, architecture/OS availability evidence, reviewed export allowlist, ABI signature metadata, and provenance before activation.
- Current default branch still contains no DevAgent source, PE/DLL analyzer, DLL catalog, D3DCompiler/DXBC bridge, or System32 runtime probe. Draft PR #7 remains stale/unmerged and is a fixed test orchestrator only; its free-form `CreateProcessA` runner has no executable allowlist, structured argument boundary, timeout, cancellation, Job Object containment, sandbox boundary, or bounded output. It must not receive model-generated commands.
- The repository has no implemented local inference runtime or source-generating DevAgent. A reverse-engineering analyzer would initially be a deterministic read-only specialist tool, not autonomous reasoning or a self-improving AI model.
- The implementation gates remain open: issue #9 (frozen 83-case baseline not integrated into default and provenance comparison pending) and issue #1 (large-frame stack probing, PE unwind metadata, runtime nonvolatile-register/RSP/argument probes, and generic checked API-call marshalling). The issue #12 comment and the issue #14 architecture require these prerequisites before implementation/integration; no source change was made to bypass them.
- Technical design verified against current Microsoft documentation: use `LoadLibraryExW` with `LOAD_LIBRARY_SEARCH_SYSTEM32` and verify the resolved module path before any known export probe; use `GetProcAddress` only for a fixed reviewed export allowlist. `D3DCompile` and `D3DCompileFromFile` compile HLSL; `D3DDisassemble` disassembles compiled HLSL shader bytecode, not native PE machine code; `D3DCreateBlob` creates an `ID3DBlob`. `D3D11SDKLayers.dll` is optional; requesting `D3D11_CREATE_DEVICE_DEBUG` without the required debug layer causes device creation to fail, so normal non-debug creation must remain the fallback.
- Safe first implementation after the gates: static PE parser and bounded AMD64 decoder; DLL import/export/forwarder/ordinal and metadata catalog; System32-only allowlisted export probes; separate HLSL/DXBC tool using verified D3DCompiler runtime; COM `ID3DBlob` lifetime/size validation; tests for malformed binaries, absent/legacy DLLs, wrong architecture, export absence, HLSL diagnostics, blob lifetime, and debug-layer fallback. Never load an arbitrary analyzed DLL into the DevAgent process or execute an analyzed target by default.
- Evidence classification: REPOSITORY PRESENT / STATIC REVIEWED for the issue/architecture/source audit; NOT IMPLEMENTED / NOT RUN for the reverse-engineering capability and DevAgent runtime; BLOCKED for implementation pending issues #9 and #1. No compiler/DevAgent source, test, workflow, Engine, or IDE source changed; no process was launched and no workflow was dispatched.
- Next action: complete the existing baseline and ABI gates, then start a fresh feature branch for the read-only reverse-engineering tools and capability manifest. The stale PR #7 is not a source base.


## Manual DevAgent / Reverse Engineering Agent repair audit - 2026-11-25 19:30 Africa/Cairo

- User requested an active, high-rigor audit and repair of SharnouDevAgent and the Reverse Engineering Agent, followed by another run.
- Starting repository: `Sharnou/Sharnou-Compiler`; branch: `Sharnou-Compiler`; starting HEAD: `0c5ad2f6e13f7018ada6caf4f7f422f74ebb5203`.
- Re-read the current `AGENTS.md`, `AI_START_HERE.md`, `Docs/AI-SESSION-STATE.md`, `Docs/AI-DEVELOPMENT-PLAN.md`, `Docs/AI-ISSUE-REGISTER.md`, `README.md`, DevAgent architecture, current compiler/PE verifier and Stage 7A test references; inspected the current branch tree, issues #1/#8/#9/#12/#14, PRs #7/#11/#13, and relevant Actions evidence.
- Current default tree contains no DevAgent source directory, `Examples/DevAgent.sharnou`, `Tests/Test-DevAgent.ps1`, process-launch intrinsic, static PE analyzer, DLL catalogue, or D3DCompiler/DXBC analysis implementation. The current Stage 0 compiler has no DevAgent or `CreateProcessA` symbols. The IDE README describes the native compiler bridge, not a DevAgent implementation.
- The only native DevAgent prototype remains draft PR #7, branch `automation/sharnou-dev-agent-native`, head `ac3849800412b1208acb540ef090ffb3ac0455ca`. Against this current default HEAD, the branch is DIVERGED: 9 commits ahead / 54 behind; GitHub marks the PR not mergeable. Its 9-file change set includes an example, test harness and 150-line compiler process intrinsic; it is stale and is not a safe base for repair.
- PR #7's `sh_dev_run_process(String)` passes a caller-controlled raw command-line string to `CreateProcessA` with `lpApplicationName = NULL` and handle inheritance enabled; it waits using `WaitForSingleObject(INFINITE)`. The reviewed implementation has no executable identity/hash allowlist, structured argument schema, canonical workspace-root confinement, environment allowlist, bounded stdout/stderr, timeout/cancellation, Job Object process-tree containment, or restricted execution boundary. This is a security/robustness defect, not a suitable agent process API. Do not pass model-generated strings to it and do not rerun the stale prototype.
- Historical PR #7 Windows run [44758761226](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44758761226) validates only its fixed regression-test orchestrator: child exit-code propagation, Stage 7A tests, utility exit 0 and artifact upload. Its own output says `Self-hosted native SharnouCompiler.exe: NOT YET IMPLEMENTED`. It provides no evidence of AI reasoning, source generation, autonomous repair, reverse engineering, durable task recovery, or a safe process broker.
- The Reverse Engineering Agent is also not implemented on the current default branch. Existing issue #12 is a proposal and acceptance specification only: read-only PE/COFF parsing, bounded AMD64 decoding, imports/exports/relocations/unwind/resources, data-driven DLL catalogue, optional D3DCompiler HLSL/DXBC operations, and System32-only allowlisted API probes. PR #13 is documentation-only; it adds no analyzer or agent source.
- Blocking prerequisites remain open: issue #9 (frozen M1-M6 83-case baseline not integrated into default and R25-R4 provenance comparison not completed) and issue #1 (stack probing, PE unwind metadata, runtime nonvolatile-register/RSP/argument probes, and generic checked higher-arity API-call marshalling). These gates must not be bypassed before model-controlled compiler/process execution.
- Evidence: latest default Stage 7A Windows run [45638680338](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45638680338) passed 23/23 on documentation-only commit `6899a086bb9b212a7a1e714d1e8fba375ae28fb6`; it did not run either agent. PR #7 run [44758761226](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44758761226) is historical orchestrator-only evidence on the stale PR branch. No new agent process, analyzer, executable, workflow or Windows runtime test was run in this session.
- Disposition: REPOSITORY PRESENT / STATIC REVIEWED for the current compiler/repository/PR audit; WINDOWS CI PASS only for the historical Stage 7A and orchestrator runs described above; NOT IMPLEMENTED / NOT RUN for the current DevAgent and Reverse Engineering Agent; BLOCKED for safe model-controlled execution by issues #1 and #9.
- No compiler, verifier, agent, Engine, IDE, example, fixture, test, or workflow source was changed. No PR was rebased, merged or edited; no workflow was dispatched; no external compiler/toolchain was used.
- Next dependency-ordered work: (1) complete normal human review/integration and provenance work for the frozen baseline; (2) close the ABI runtime gates; (3) build and adversarially test a typed, allowlisted process broker with workspace confinement, bounded output, timeout/cancellation, Job Object containment and rollback; (4) implement the read-only PE/DLL/export/relocation/unwind analyzer and separate D3DCompiler shader adapter; (5) integrate local inference/planning and bounded source repair only after the tool and recovery/security gates pass. Keep issues #12 and #14 open.
 
## Milestone 7A local regression repair - 2026-11-25

### User-provided Windows validation log

The uploaded `Pasted text(7).txt` is an execution log, not the source package. It reports:

- Engine foundation preflight: 5/5.
- Milestone 7A example build: 22/22.
- Example runtime: 15/15.
- Stage 2: 25/25.
- Stage 4: 20/20.
- PE verifier: 4/4.
- Stage 5: 24/25. The only failure is the absent imported module `Tests\\StdLib\\Collections.sharnou`.
- Stage 6: 9/9.
- Stage 7A: 27/28. The failing `BranchConditionCodes` case expected 13 output lines but received the first 6.

### Repair PR #15

PR [#15 - Repair Stage 5 collection imports and add full Stage 7A branch regression](https://github.com/Sharnou/Sharnou-Compiler/pull/15) is based on default HEAD `f80dae6fc6efccce84bc733a7529664085b3250e` and remains OPEN / UNMERGED.

Changes:
- Restores canonical `StdLib/Collections.sharnou` from the pinned M1-M6 payload. Its original member SHA-256 is `46140cdd516f2d96fb93675af1bbacab79db4daf5e711881103ee27b2cd730e3`.
- Adds `Tests/StdLib/Collections.sharnou` as a compatibility import shim to the canonical module.
- Adds two native compile / PE-verify / runtime tests for the canonical and legacy import paths.
- Adds `Examples/ControlFlow/BranchConditionCodes.sharnou` with all six comparison operators, true/false paths, variable operands and INT32_MIN/INT32_MAX boundaries. Its expected 13-line output matches the output expected by the uploaded log.
- Integrates that fixture into Build.ps1, Run.ps1 and Tests/Test-Stage7A.ps1.

### Windows CI result

Windows Actions run [45696244484](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45696244484) completed SUCCESS on PR #15 head `01fd2d7b6bd6ab4d80a920449bc529fa865634e8`.

Exact job log:
- Source encoding check: PASS (ASCII / UTF-8 without BOM).
- Stage 7A: 24 passed, 0 failed, 24 total.
- The new 13-line signed branch-boundary regression: PASS.
- Canonical `StdLib` import: PASS.
- Legacy `Tests/StdLib` import: PASS.
- Stage 5 collection import tests: 2 passed, 0 failed, 2 total.
- Combined result: PASS.

The 13-line branch test passing means the current compiler implementation did not reproduce the user's truncated-output failure with an independently maintained equivalent fixture. No Stage0 compiler change is justified by the available evidence. The exact local `BranchConditionCodes.sharnou` and expanded local `Test.ps1` were not uploaded, so the original local failure is not yet conclusively reconciled against the new fixture.

The full 83-case M1-M6 baseline is still tracked separately by issue #9 / PR #11. This PR run does not claim 83/83 or the full Stage 5 25-case suite.

Classification: **WINDOWS CI PASS on PR #15; USER-REPORTED LOCAL FAILURE IDENTIFIED; EXACT LOCAL TEST SOURCE NOT AVAILABLE; DEFAULT BRANCH NOT MODIFIED; PR NOT MERGED.**

 
### Branch fixture size cross-check - 2026-11-25

- Uploaded local `BranchConditionCodes.exe`: `codeBytes=1171`, `dataBytes=57` (the user log lines 853-856); its runtime output contains only six labels.
- The PR #15 equivalent 13-output fixture: `codeBytes=3573`, `dataBytes=275`; its Windows run prints the exact 13-line expected output and passes.
- Because each output label is a distinct string constant retained in the generated data section, the much smaller local image strongly suggests the local executable did not contain the seven additional output-label constants. Leading explanation: the local fixture or expected-output list is stale/truncated, or the local fixture uses a construct not represented by the current reproducer. This size evidence does not conclusively distinguish an incomplete source file from a parser-path defect.
- Do not change signed-comparison machine code based on this log alone. Obtain the exact local `BranchConditionCodes.sharnou` to close the remaining ambiguity.


## User-local Milestone 7A Windows validation - 2026-11-25

- The user ran PR #15 source snapshot commit `de4e64e3f45bc142391886033c33a825722a6eca` on Windows from the downloaded folder `Sharnou-Compiler-de4e64e3f45bc142391886033c33a825722a6eca`. Classification: **USER-REPORTED WINDOWS PASS**.
- `Test.ps1`: Stage 7A **24 passed, 0 failed, 24 total** (9 positive runtime cases, 12 negative parser/type cases, 3 native instruction/branch checks); Stage 5 collection imports **2 passed, 0 failed, 2 total**; final **Combined result: PASS**.
- `Build.ps1`: all 9 control-flow examples built as native AMD64 PE32+ images; the repository PE verifier passed on each image. `Run.ps1`: all 9 examples returned exit code 0 and exact expected output.
- The 13-output `BranchConditionCodes` fixture passed. Canonical and legacy collection import paths both passed.
- The log also contains eight `InputObjectNotBound` parameter-binding errors after the command `Get-ChildItem -LiteralPath $PWD -Recurse -File -Filter *.ps1 | .\Test.ps1`. This is a command-composition error: `Test.ps1` has no pipeline-input parameter. The test script subsequently completed and reported PASS. Run the listing command and ` .\Test.ps1` as separate commands; do not pipe file objects into the test runner.
- The execution-policy listing showed Process=Bypass and CurrentUser=RemoteSigned; scripts ran successfully. No execution-policy blocker was observed.
- The user log does **not** run the frozen M1-M6 83-case baseline. PR #11 remains open/unmerged and issue #9 remains a separate gate. Do not describe the current 24+2 local results as an 83-case pass.
- Static re-audit of the compiler at this source snapshot reconfirms issue #1's ABI gaps: `Set-FrameSize` allows frames up to 1 MiB and yields a minimum frame above one 4 KiB page; `Emit-Prologue` subtracts the frame size without a stack probe. The PE writer/verifier still use four sections and no exception directory or `.pdata` / `.xdata` unwind records. These are **REPOSITORY PRESENT / STATIC REVIEWED**, not failures reproduced by this log, and remain open ABI work before full ABI/self-hosting acceptance. See [Microsoft x64 prolog and epilog](https://learn.microsoft.com/en-us/cpp/build/prolog-and-epilog?view=msvc-160) and [x64 exception handling](https://learn.microsoft.com/en-us/cpp/build/exception-handling-x64).
- No compiler or backend source change was justified by this log: its compiler, test, build, and run cases all passed. README and plan test inventory were corrected from eight to nine positive cases and now document the standalone test-runner invocation.

## Windows x64 stack-probe and unwind repair - 2026-11-25

- User requested repair of the remaining stack-probe and unwind defects and a full Milestone download. Work is isolated in [PR #16](https://github.com/Sharnou/Sharnou-Compiler/pull/16), branch `repair/m7a-x64-stack-probe-unwind-20261125`; current code/documentation test snapshot verified by Windows run `45705513598` at head `b1365dc17bb5aeaad74462633fadfdc29b56fa3e`.
- Implemented `Emit-StackProbe`: the function prologue establishes RBP, passes frame size in EAX, calls private leaf `__sharnou_chkstk`, then performs the single fixed `sub rsp, imm32`. The helper probes downward in 4 KiB steps and uses only volatile R10/R11 and flags; it preserves RAX, RCX/RDX/R8/R9, nonvolatile registers and RSP. The helper is a leaf and has no RUNTIME_FUNCTION record.
- Added `New-UnwindInfoBytes` and generated version-1 UNWIND_INFO for the entry routine and each Sharnou function. Records contain UWOP_ALLOC_LARGE (scaled 16-bit or 32-bit form), UWOP_SET_FPREG, and UWOP_PUSH_NONVOL RBP. Added sorted RUNTIME_FUNCTION records in `.pdata`, unwind data in `.xdata`, and the PE32+ exception directory. The linker now emits six sections: `.text`, `.rdata`, `.idata`, `.reloc`, `.pdata`, `.xdata`.
- Changed generated function epilogues to `lea rsp,[rbp+0]; pop rbp; ret`, matching the Windows x64 epilogue pattern. The PE verifier validates section layout, exception directory coverage, sorted runtime-function ranges, unwind version/flags/codes, stack frame sizes, exact prologue bytes, helper bytes and rel32 branch targets.
- Added `Tests/Test-StackProbeUnwind.ps1` and wired it into `Test.ps1`. It compiles and executes a 17,000-local multi-page main frame and a smaller user-function frame; checks both UWOP_ALLOC_LARGE encodings; verifies the generated epilogue; and confirms the PE verifier rejects a truncated exception directory and an unsupported UNWIND_INFO version.
- **WINDOWS CI PASS:** run [45705513598](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45705513598), head `b1365dc17bb5aeaad74462633fadfdc29b56fa3e`: ASCII/no-BOM PASS; Stage 7A 24/24; Stage 5 collection imports 2/2; stack-probe/unwind 6/6; Combined result PASS. The native multi-page executable logged `codeBytes=187553`, passed the PE verifier, and exited 0 with the expected output `16999` then `17000`. Both UNWIND_INFO allocation encodings were exercised.
- PR #16 remains OPEN / UNMERGED; no default-branch source merge was performed. The previous user-provided local run validated PR #15 before these ABI changes. **User-local testing of PR #16 is still pending**; the current new stack/unwind evidence is Windows CI, not a user-PC execution report.
- Issue #1 is partially resolved but remains OPEN: stack probing and PE unwind metadata now have source, verifier and Windows CI coverage. Additional ABI acceptance remains: runtime nonvolatile-register sentinels, RSP/call-site alignment and argument-value probes, and generic checked marshalling for higher-arity Windows API calls. Do not claim complete ABI acceptance.
- The frozen Milestone 1-6 83-case baseline was not run by this PR. Issue #9 / PR #11 remain separate and unmerged. Do not describe the current 24 + 2 + 6 result as 83/83.
- The PowerShell `InputObjectNotBound` messages in the user's log remain explained by piping `Get-ChildItem` FileInfo objects into parameterless `Test.ps1`; those errors are not compiler failures. Invoke `Get-ChildItem ...` and ` .\Test.ps1` as separate commands.


## DevAgent broker phase 1 - 2026-11-26

Integrated candidate PR #18 head `2ee44cef7f3d67b4ccdc26aa391a9e789197197b` is draft and unmerged. Windows CI passed on the same PR merge-ref:

- Stage 7A: 24/24.
- Stage 5 collection imports: 2/2.
- Stack-probe/unwind: 6/6.
- Runtime ABI: PASS. Tests cover nonvolatile sentinels RBX/RBP/RSI/RDI/R12-R15, live RSP alignment, 4/5/6/8 integer argument values, nested argument order, 12-argument Windows API marshalling, and file/window/thread/synchronization probes.
- Frozen M1-M6 baseline: 83/83 (Stage 2 25, Stage 4 20, PE verifier 4, Stage 5 25, Stage 6 9).
- Combined result: PASS.

Windows runs:
- Stage 7A / combined: [45724983298](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45724983298).
- Frozen baseline: [45724983299](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45724983299).

DevAgent process broker phase 1 is implemented and tested:
- `sh_dev_run_tool(Integer,Integer)` is available only with explicit `-EnableDevAgentTools`; disabled by default.
- Six fixed tool IDs; no arbitrary command, executable path, script path, argument vector, or caller-supplied working directory.
- Compiler-pinned SHA-256 tool manifest and per-script runtime SHA-256 verification. Manifest tampering is rejected before native generation; script tampering is rejected before execution.
- Absolute System32 PowerShell path, fixed workspace layout and reparse-point rejection.
- Suspended process creation, Job Object assignment before resume, kill-on-close, process/memory limits, timeout and descendant termination.
- Windows tests cover invalid IDs/timeouts, explicit opt-in, exit-code propagation, manifest tamper, script tamper, junction/reparse rejection, timeout and descendant cleanup.

Security acceptance is still incomplete. Native CNG hashing, full canonical root/ancestor validation, restricted token/AppContainer and workspace ACLs, clean environment, bounded output capture, cancellation, and durable evidence journaling remain outstanding. The broker remains opt-in for test builds only; model-generated process execution remains DISABLED. No merge or release was performed.



## Runtime ABI and DevAgent native broker - latest validated state, 2026-11-26

Integrated PR #18 head `7a15892a944c747f9563961d7c050c909dd3d3a4` is draft/open/unmerged. Windows CI passed on the PR merge ref:
- Stage 7A: 24/24.
- Stage 5 collection imports: 2/2.
- Stack probe/unwind: 6/6.
- Runtime ABI: PASS. Nonvolatile register sentinels cover RBX, RBP, RSI, RDI, R12-R15; live RSP alignment is checked before/during/after calls; argument values and nested ordering are verified for 4, 5, 6, 8, and 16 integer arguments; the 17-parameter and 17-call-argument limits reject before PE output. Higher-arity Win32 API calls are exercised.
- Frozen M1-M6 suite: 83/83 (Stage 2 25, Stage 4 20, PE verifier 4, Stage 5 25, Stage 6 9).
- Combined result: PASS.

Windows evidence:
- Stage 7A / integrated suite: [45772104864](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45772104864).
- Frozen M1-M6: [45772104661](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45772104661).

DevAgent native process broker phase 1 is implemented and Windows-tested:
- `sh_dev_run_tool(tool_id, timeout_ms)` is typed and only registered under explicit `-EnableDevAgentTools`; default compiler builds reject the capability.
- Six fixed compiler-owned test tools; no caller-controlled command string, executable/script path, argv, or working directory.
- Compiler-pinned SHA-256 tool manifest plus native Windows CNG SHA-256 verification of the selected script before `CreateProcessA`; its opened file handle is retained through child completion. Manifest tampering and script tampering fail closed.
- PowerShell resolves from the absolute System32 directory; the workspace root is derived from the broker image path (`Build\\DevAgentBroker\\DevAgentBroker.exe`), not the inherited current directory. Test runs from a foreign working directory pass.
- Checked workspace paths and opened script handles reject reparse points.
- Child process starts suspended with handle inheritance disabled, joins a Job Object before resume, and is subject to kill-on-job-close, active-process, process-memory, job-memory, and timeout limits. Timeout terminates descendants.
- Windows broker tests pass for explicit opt-in, manifest tamper, script tamper, foreign-CWD launch, reparse/junction rejection, invalid tool IDs/timeouts, exit-code propagation, timeout, and descendant termination.

Security acceptance remains incomplete; model-generated process execution is DISABLED. Remaining work: final-path/ancestor canonicalization and ADS/UNC/device-path rejection; restricted token or AppContainer with workspace-only ACLs; clean environment and explicit DLL-search policy; bounded stdout/stderr capture and STARTUPINFOEX handle isolation; cooperative cancellation; durable evidence journal and restart recovery. This is a test-tool broker foundation, not yet a production sandbox. No merge, release, or executable publication occurred.

## AppContainer and workspace-ACL security tranche - 2026-11-26

A follow-on branch `devagent-appcontainer-acl-output-20261126` is stacked on the draft phase-1 broker branch. This tranche corrects the native import-table targets for the AppContainer profile and DACL helper emitters, adds the relevant `USERENV.dll` / `ADVAPI32.dll` API names to the PE verifier allowlist, and adds static source assertions for the helper declarations and IAT mappings.

Important scope boundary:
- The AppContainer profile/SID and ACL-update helper functions are currently declarations in the compiler source. They are **not called by the live `Emit-DevRunTool` execution path**.
- `CreateRestrictedToken`, `CreateProcessAsUserA`, AppContainer process attributes, actual workspace ACL grant/revoke, and bounded stdout/stderr capture are **not yet implemented as an end-to-end runtime path** in this commit.
- No sandbox runtime or adversarial Windows test has passed for this tranche. The static assertions are not proof of runtime isolation.
- The existing process broker remains an explicit opt-in test-only capability, and model-facing process execution remains **DISABLED**.
- Do not merge the follow-on branch or mark the security target complete on this evidence.

Required next gates: wire the restricted primary token and no-capability AppContainer into suspended process creation; apply and reliably revoke least-privilege workspace DACL entries; capture combined stdout/stderr through an explicit STARTUPINFOEX handle list under a hard byte cap; terminate and confirm the entire job on timeout/overflow/failure; then add adversarial Windows tests for token identity, denied filesystem/network access, ACL rollback/restart, handle isolation, output cap, timeout and descendant termination. Clean environment/DLL-search policy and durable evidence journaling remain separate gates.

## Native AppContainer broker integration checkpoint - 2026-11-26

Active implementation branch: `devagent-sandbox-runtime-20261126`, stacked on draft PR #19. Current checkpoint source contains a live `Emit-DevRunTool` execution path for restricted-token/AppContainer startup, handle-based workspace ACLs, and bounded stdout/stderr capture. This supersedes the earlier helper-only checkpoint on PR #19.

Implemented in source (not yet Windows-runtime validated on this branch):
- Eight fixed test-tool IDs and compiler-pinned manifest SHA-256; per-script CNG verification remains in the existing phase-1 path.
- A restricted primary token created with `CreateRestrictedToken(DISABLE_MAX_PRIVILEGE)`.
- A no-capability AppContainer SID attached through `PROC_THREAD_ATTRIBUTE_SECURITY_CAPABILITIES`; before `ResumeThread`, the child primary token is queried for `TokenIsAppContainer`, `TokenHasRestrictions`, and an empty `TokenCapabilities` group list.
- `STARTUPINFOEX` uses a two-call, bounded `InitializeProcThreadAttributeList` sizing sequence and an explicit handle list containing only NUL stdin and the stdout/stderr pipe writer. The parent capture handle and output-file handle are not inherited.
- DACL updates now open the actual directory with `OPEN_REPARSE_POINT`, validate the opened directory handle, preserve unrelated DACL entries through `GetSecurityInfo` + `SetEntriesInAclA`, and apply the merged DACL through `SetSecurityInfo`.
- The source workspace root receives read/execute access for the package SID. Writable access is limited to `Build` and `Build\\DevAgentBroker`.
- The AppContainer runs at Low IL. Mandatory Integrity Control is evaluated before the DACL, so the writable Build directories also receive an inheritable Low IL mandatory label with `NO_WRITE_UP`; the source workspace root is deliberately not relabeled.
- Combined stdout/stderr is drained while the process runs. The read size is clamped to the remaining capacity so a 1 MiB + 1 byte test writes exactly 1 MiB to the captured file and then returns overflow. Output is persisted through the same exclusive, non-inherited output-file handle.
- The child is created suspended, assigned to the Job Object before resume, and termination paths wait for Job Object emptiness before returning.

Static validation performed during source review:
- 16 import descriptors.
- 66 unique imported API names.
- Per-module IAT arrays include their terminating zero thunk and do not overlap.
- Import lookup arrays do not overlap.
- All `Emit-Win64CallIat` targets map to declared imported API slots.
- The exact output-cap reader logic is asserted by the regression script.
- A static regression assertion now verifies Low IL labeling is restricted to the two writable Build directories.

Not yet demonstrated:
- No Windows Actions run has passed for this implementation branch at this checkpoint. Source presence and static layout assertions are not execution evidence.
- The 1 MiB overflow, sandbox write/deny, and token-identity probes must pass on an actual Windows runner before runtime acceptance.
- Persistent package SID and persistent package ACL grants are used. There is no per-invocation random AppContainer identity, transactional DACL rollback, or durable stale-ACL recovery journal. A broker crash can leave a package SID grant behind; treat this as a security blocker.
- The child currently receives an inherited environment block (`lpEnvironment = NULL)); environment sanitization and DLL search-order hardening remain outstanding.
- Full final-path/ancestor race elimination and executable-image provenance remain open.
- Network-denial and explicit cancellation adversarial tests remain open. No network capability SID is declared, but that alone is not a passed network-isolation test.

The branch is **IMPLEMENTATION CANDIDATE / NOT SECURITY-ACCEPTED**. PR #20 must remain draft and unmerged pending Windows CI and adversarial review. The broker remains test-build opt-in only; model-facing process execution remains **DISABLED**. No release or executable publication occurred.
# AI Session State - Sharnou Compiler

**Last updated:** 2026-11-22 Africa/Cairo
**Repository:** `Sharnou/Sharnou-Compiler`  
**Branch:** `Sharnou-Compiler`  
**Purpose:** Latest durable status for every future AI-assisted compiler/Engine generation, debugging, testing, and repair session.

> This file is the live status snapshot, not a claim that the AI can monitor the repository in the background. Update it at the end of every completed AI work session.

## Current status at a glance

- **Accepted project direction:** self-contained Sharnou compiler, PE32+ linker, runtime/standard library, Engine, IDE, and Honour War for Windows x64.
- **User-reported completed history:** Milestones 1-6 passed on the user's Windows PC.
- **Current development focus:** Milestone 7A implementation is present and Windows-CI verified; the next bounded task is a Milestone 7B proposal and isolated patch plan only.
- **Persistent AI status tracker:** [GitHub issue #8](https://github.com/Sharnou/Sharnou-Compiler/issues/8); update its body and this file after every completed AI generation/repair session.
- **Actionable blockers:** [Issue #9 - restore exact 83-case baseline](https://github.com/Sharnou/Sharnou-Compiler/issues/9); [Issue #10 - Milestone 7A Windows acceptance](https://github.com/Sharnou/Sharnou-Compiler/issues/10).
- **Milestone 7A repository implementation:** present on the `Sharnou-Compiler` branch; implementation commit `943d24d857b89b9b30a426c8fb4025c05413d6a8`.
- **Plan-map documentation commits:** `c403b4b725200000ba89944798a4bcca618c9885` (AI preflight), `5a5b2c89d0c0c0a4d85bb4111ecb145a83be7cb9` (master plan), `aeb086429bc98e5094bf4d881c02b9100e4cb893` (issue register), and `e47dd7d5634ed5ccc9302d2d59241790f6de3bdc` (README links). The current state file was subsequently updated to include GitHub issue numbers.
- **Milestone 7A Windows CI:** current default-branch run 45004368571 passed 23/23 on HEAD 45c83e1941fd74ca1ce94a4f0bc9ffe72a43efe3. User-local 7A acceptance is still NOT REPORTED separately.
- **Frozen 83-case repository baseline:** WINDOWS CI PASS 83/83 on open PR #11 head 135b7eec7bf13fc147756dfaeeb3f92eab57a250, with the 7A 23/23 suite passing on that same head. The five baseline paths remain PR-only and are not yet on default.
- **Next action:** review PR #11 through the normal process without auto-merging; complete the R25-R4 archive comparison; retain ABI gates; prepare 7B as a proposal only until implementation/write authorization.

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


## Scheduled compiler and DevAgent audit - 2026-11-22 08:46 Africa/Cairo

Repository: `Sharnou/Sharnou-Compiler`
Default branch: `Sharnou-Compiler`
Default HEAD at audit start: `25bc8aac1370b1d6024ae538956c49a6bbba4f07`
Status-only issue-register commit: `329f1aac33e4a3ed4f5bbbc03ce3d3667d5776bf`

### Live PR state

- PR #6: OPEN / UNMERGED; head `9dfe1bc09685a6f7deb9d29b5192b1aae0686039`; GitHub reports mergeable=false; compare to default is 15 ahead / 19 behind with merge base `352c65e05524d494970b2d8b52b7089d12d19435`. Five baseline-related paths are added. Compiler, verifier, Stage 7A test, and root Test.ps1 blobs are identical to current default. Do not merge, rebase, or rewrite automatically.
- PR #5: OPEN / UNMERGED / NOT ACCEPTED; head `0b8dee87b699eabcaaac37f111686231fb29a82c`; mergeable=false; 2 ahead / 19 behind. Its 7B implementation is a proposal only.
- PR #7: OPEN / DRAFT; head `ac3849800412b1208acb540ef090ffb3ac0455ca`; mergeable=false. It is a native test orchestrator, not an AI source-generating agent.
- PR #4 and #2 remain open/unmerged; PR #3 is merged. Issues #1, #8, #9, #10 remain open.

### Windows Actions evidence

- Run 44880127825: default HEAD `25bc8aac1370b1d6024ae538956c49a6bbba4f07`; `windows-stage7a` success; encoding check PASS; Stage 7A 23 passed / 0 failed / 23 total; Combined result PASS.
- Run 44700641397: PR #6 head; `windows-m6-83` success; Stage 2 25/25, Stage 4 20/20, PE verifier 4/4, Stage 5 25/25, Stage 6 9/9; frozen baseline PASS 83/83.
- Run 44700641419: same PR #6 head; `windows-stage7a` success; Stage 7A 23/23; Combined result PASS.
- Run 44693097619: PR #5 head; `windows-stage7a` success; Stage 7A 23/23 and proposed Stage 7B 32/32 (15 positive, 13 negative, 4 instruction checks). It did not run the 83-case baseline.
- Run 44758761226: PR #7 head; `windows-stage7a` success; native DevAgent repeated Stage 7A 23/23, verified child exit code 7 propagation, exited 0, and uploaded artifact ID `14654214120`.
- The 83-case intent split is classified as 36 positive / 47 negative; the manifest records suite totals only. No workflow was dispatched in this run.

### Audit findings

- Current default compiler/verifier/Test-Stage7A blobs: `ee01ef77b068df5d149934fbf463c43b34c54bf3`, `3606b57920043882a2277ad41fd0e0578156944a`, `80d8df1c9a6da7c8fb6f2b414c2929f07ba44804`. Recorded SHA-256 values remain `c97bd0c4d9ad94b1b4855bbdcd6f843f563f75b35771106ae8976cae2bbda250`, `953a20c2274eee42eee2523c5608fd48e6dc574e4b5465464e910db560d55179`, and `ffd8a3518d8fc943adb97e319a29a8822d4e5c409226597d0010b40da23eae05`.
- PR #6's baseline runner pins the original M6 archive and compressed payload. It validates the payload and embedded member hashes but does not independently read the original `SHA256SUMS.txt`; the manifest provenance boolean is not independently reproduced by the runner. R25-R4 file-by-file comparison remains NOT RUN.
- Re-review correction: PR #5's `Get-ConstantValue` traverses the RHS when the left operand is dynamic. This is compile-time constant-arithmetic validation, not runtime RHS evaluation. Since the RHS may be reachable, constant divide-by-zero rejection can be a deliberate fail-closed policy. The previous session overclassified this as a confirmed short-circuit defect. The actual gap is missing dynamic-left side-effect tests for AND/OR skip and evaluate paths.
- PR #5 has 15 positive, 13 negative, and 4 opcode-presence checks. It lacks explicit negative tests for Boolean function arguments/returns and a rel32 target decoder. The current branch/loop emitter uses JZ/JNZ and JMP rel32 fixups; loop targets are pushed/popped with try/finally. ABI-critical functions `Emit-CallFunction`, `Set-FrameSize`, `Emit-Prologue`, and `Emit-Epilogue` are unchanged from default. Issue #1's unwind metadata, large-frame stack probing, nonvolatile-register probes, and generic API marshalling remain open.
- The PR #7 native agent is a test orchestrator only. It checks workspace files, tests child-process exit-code propagation, and runs PowerShell tests. It does not generate source or build a self-hosted compiler.

### Native build/runtime status

- Native self-hosted `SharnouCompiler.exe`: NOT BUILT / NOT RUN.
- Native `SharnouDevAgent.exe`: WINDOWS CI PASS as a test orchestrator on PR #7; artifact ID `14654214120`; process exit code 0. Not merged or deployed.
- Autonomous source generation, persistent worker/checkpoint/recovery, Windows-host deployment, and restart/runtime proof: NOT IMPLEMENTED / NOT RUN.

### Changes and next dependency

- Changed paths in this run: `Docs/AI-ISSUE-REGISTER.md` and this session-state file only. No source changes: compiler, verifier, examples, tests, build scripts, workflows, Engine, IDE, and game source are unchanged. No PR changes, merge, rebase, or workflow dispatch.
- Evidence: M1-M6 USER-REPORTED WINDOWS PASS; default 7A and PR #6 baseline/7A WINDOWS CI PASS; PR #5 7B WINDOWS CI PASS on an unaccepted, stale branch; PR #7 native test orchestrator WINDOWS CI PASS; 7B observations REPOSITORY PRESENT / STATIC REVIEWED; self-hosting and autonomous agent NOT RUN / NOT IMPLEMENTED.
- Next bounded task: resolve PR #6's stale/non-mergeable integration path by explicit review without altering the frozen payload. Once baseline is integrated or equivalently included in a fresh isolated candidate branch, prepare the corrected 7B patch plan and require all 138 cases (83 + 23 + 32) to pass on one Windows commit. Keep ABI repair and autonomous agent work separately gated.


## PR mergeability re-check correction - 2026-11-22

The initial PR metadata read in the preceding audit returned `mergeable=false` for PR #6, #5, and #7. Two subsequent live reads returned `mergeable=true` for PR #6, #5, #7, and #4 at then-current default HEAD `c7bd85a108d97800e7f03b338cf60089a18f4f4e`. The later repeated value supersedes the initial value. All remain OPEN / UNMERGED; PR #7 remains DRAFT. Do not describe them as merge-conflict blocked.

The compare endpoints still show divergence: PR #6 15 ahead / 21 behind; PR #5 2 ahead / 21 behind; PR #7 9 ahead / 21 behind; common merge base `352c65e05524d494970b2d8b52b7089d12d19435`. These are stale branches requiring review, not evidence of merge conflicts. PR #6 remains expressly unmerged by this automation. No PR state or source changed.


## Final PR metadata consistency note - 2026-11-22

Repeated live GitHub connector reads returned alternating `mergeable` values for PRs #6, #5, and #7 (false, true, false, then true). Treat the mergeable field as UNSTABLE / UNKNOWN for this session; do not infer conflicts or a clean merge from it. Stable facts: PR #6/#5 remain OPEN / UNMERGED and PR #7 remains OPEN / DRAFT / UNMERGED; head SHAs are unchanged; compare reports divergence. At default HEAD `c7bd85a108d97800e7f03b338cf60089a18f4f4e`, PR #6 was 15 ahead / 21 behind, PR #5 2 ahead / 21 behind, PR #7 9 ahead / 21 behind. Two later status-only documentation commits add two more commits to the default branch; re-run compare before any future branch operation. PR #6 must not be merged by this automation regardless of mergeability metadata. No PR state or source changed.


## Final default HEAD and PR divergence snapshot - 2026-11-22

At default HEAD `e965c0e0848855b48b1e7cfe27707e0d369eb56b`, compare reported PR #6 15 ahead / 25 behind, PR #5 2 ahead / 25 behind, and PR #7 9 ahead / 25 behind, all diverged from merge base `352c65e05524d494970b2d8b52b7089d12d19435`. The earlier two-commit increment referred to the state before the two final consistency-note commits; this snapshot supersedes it. The two status-only commits appended after this snapshot add two more commits to default, so expected behind counts become 27. Re-query before any future branch operation. GitHub mergeable metadata remains UNSTABLE / UNKNOWN after alternating reads. No PR is merged or modified.


## Session update - 2026-11-22 - baseline integration, 7A CI and ABI gate audit

**Session type:** Repository triage, frozen-baseline integration preparation, status synchronization and current-source ABI audit. No compiler or PE-verifier source was modified.

### Starting repository state

- Repository: `Sharnou/Sharnou-Compiler`.
- Default branch: `Sharnou-Compiler`.
- Starting/default HEAD: `d79873e1941b22f1f9eb1413d58e874d77d54e17`.
- Current compiler blob: `ee01ef77b068df5d149934fbf463c43b34c54bf3`; previously recorded content SHA-256 for that exact blob: `c97bd0c4d9ad94b1b4855bbdcd6f843f563f75b35771106ae8976cae2bbda250`.
- Current PE verifier blob: `3606b57920043882a2277ad41fd0e0578156944a`.
- Stage 7A test blob: `80d8df1c9a6da7c8fb6f2b414c2929f07ba44804`; root `Test.ps1` blob: `699eb04aefdf1149aa5807107ce351f8c2aae676`.

### B1 / Issue #9 - frozen M1-M6 83-case suite

The old PR #6 branch is open/unmerged and diverged 15 commits ahead / 27 behind the current default HEAD. It was not merged, rebased, or rewritten.

A fresh feature branch and PR were created to replay the exact same five baseline file blobs from the current default commit:

- Branch: `automation/m6-baseline-current-head-20261122`.
- Commit: `37451e384e2e7e669c8368882225619cc9a67e67`.
- New PR: [#11 - Restore frozen Milestone 6 83-case baseline on current default head](https://github.com/Sharnou/Sharnou-Compiler/pull/11).
- Base commit: `d79873e1941b22f1f9eb1413d58e874d77d54e17`.
- Changed paths (five additions only):
  - `.github/workflows/milestone6-baseline.yml`
  - `StdLib/Graphics.sharnou`
  - `Tests/BaselineM6/M6-83Cases.payload.json.gz.b64`
  - `Tests/BaselineM6/Test-Milestone6Baseline.ps1`
  - `Tests/BaselineM6/manifest.json`
- The exact blob identities from PR #6 were reused. No compiler, PE verifier, Stage 7A test, or existing test source was modified.
- Frozen M6 package SHA-256: `0b6bf15445a5dfd8cbf93450af7fd2f5fd6239d4ed082ab18b09878a94b8b164`.
- Compressed payload SHA-256: `3dd1d7417874159c0bc625edbbc1e8cee1ae7d8a6ea42f30b4dd80ba92102748`; 88 embedded source/fixture members.
- New Windows workflow run [45003405485](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45003405485) started on PR #11 head `37451e384e2e7e669c8368882225619cc9a67e67`. At the time of this status write, job `windows-m6-83` was IN_PROGRESS; no result is claimed yet.
- Earlier PR #6 Windows run [44700641397](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44700641397) logged 83/83 on the old PR head. That historical result is not substituted for PR #11's own run.
- The separate R25-R4 archive file-by-file comparison remains NOT RUN. Its pinned SHA-256 is `CA01AEACB2E35C6E8039E58F15202A01399DAEA3E0A24E7B4D357772C8EF1274`. The two 83-case suites are not assumed identical.
- Issue #9 remains OPEN/BLOCKED pending PR #11 Windows 83/83, default-branch integration through normal review, and the separate R25-R4 comparison. No PR was merged.

### B2 / Issue #10 - Milestone 7A

Default-branch Windows run [44996610001](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44996610001) completed successfully on exact default HEAD `d79873e1941b22f1f9eb1413d58e874d77d54e17`.

- Job: `windows-stage7a`, conclusion `success`.
- Source encoding: ASCII/no-BOM check PASS.
- Test log: 8 positive runtime + 12 negative diagnostic + 3 instruction/branch encoding checks = 23 passed, 0 failed, 23 total.
- Test log includes `Stage 7A test result: PASS` and `Combined result: PASS`.

Classification: **WINDOWS CI PASS**. User-local Milestone 7A acceptance is still NOT REPORTED separately. Issue #10 remains open because the 83-case dependency and evidence reconciliation are still pending.

### H1 / Issue #1 - current Windows x64 ABI re-audit

Re-read current compiler and verifier. Static findings remain:

1. `Set-FrameSize` allows frame sizes up to `0x100000`. `Emit-Prologue` emits `push rbp; mov rbp,rsp; sub rsp,imm32` with no `__chkstk` or per-page stack-touch probe. PE stack commit is `0x1000`.
2. The linker emits only `.text`, `.rdata`, `.idata`, and `.reloc`; exception data directory is not populated. No `.pdata` / `.xdata` unwind records are emitted.
3. The verifier does not validate unwind metadata because the image does not yet contain it.
4. Higher-arity Windows API calls are manually emitted, not produced by a generic signature-driven checked marshaller.
5. No new runtime sentinel tests for nonvolatile registers, RSP alignment, stack arguments or unwind walking were executed in this session.

Classification: **REPOSITORY PRESENT / STATIC REVIEWED**. No ABI runtime test, stack-probe experiment or unwind-walking test was run. Issue #1 remains OPEN. Required gates: documented large-frame probing, Windows x64 unwind metadata and verifier support, nonvolatile-register/RSP/argument-value runtime probes, and validated generic Windows API argument marshalling.

### Issue #8 and scheduled status synchronization

The daily `Sharnou DevAgent Progress` automation was found disabled, despite its saved instructions already containing the mandatory read-first and persist-status protocol. It has been re-enabled. The weekly `Advance Sharnou Stack` automation remains enabled. The three legacy Honour War daily-upgrade automations remain disabled.

This does not provide per-chat-turn background monitoring. The repository read-first and save-after-session requirements remain active, and the scheduled automation runs only on its configured schedule.

### Evidence classification and next actions

- M1-M6: USER-REPORTED WINDOWS PASS.
- M6 frozen 83/83: WINDOWS CI PASS on old PR #6 head; fresh PR #11 run 45003405485 IN PROGRESS at status write.
- M7A: WINDOWS CI PASS 23/23 on current default HEAD, run 44996610001.
- ABI: REPOSITORY PRESENT / STATIC REVIEWED; acceptance BLOCKED.
- Native self-hosted `SharnouCompiler.exe`: NOT BUILT / NOT RUN.
- Autonomous source-generating DevAgent: NOT IMPLEMENTED / NOT RUN. The separate PR #7 artifact remains a test orchestrator, not an AI source generator.

Next dependency order:
1. Complete and inspect PR #11 Windows run 45003405485; require all five historical suite totals and 83/83 with zero failures/skips.
2. Review/integrate PR #11 through the normal PR review process; do not auto-merge.
3. Complete the exact R25-R4 archive comparison.
4. Close M7A local-acceptance evidence only when the user reports it; retain the current Windows CI result.
5. Implement and runtime-validate the ABI gates in issue #1 before starting native self-hosting.
6. Do not adopt the unaccepted 7B proposal in PR #5 without explicit user acceptance and same-commit baseline coverage.

No local Windows command was run by the assistant. No compiler, verifier, Engine or game source was changed. No default-branch source was modified. No PR was merged.


## Follow-up result - PR #11 frozen 83-case baseline - 2026-11-22

Windows Actions run [45003405485](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45003405485) completed successfully on PR #11 head `37451e384e2e7e669c8368882225619cc9a67e67`. Job `windows-m6-83` ID `137149638940` concluded `success`.

Exact log summaries:
- ASCII source / UTF-8 without BOM: PASS.
- Stage 2: 25 passed, 0 failed, 25 total.
- Stage 4: 20 passed, 0 failed, 20 total.
- PE verifier: 4 passed, 0 failed, 4 total.
- Stage 5: 25 passed, 0 failed, 25 total.
- Stage 6: 9 passed, 0 failed, 9 total.
- Aggregate frozen Milestone 1-6 baseline: **83/83 PASS**. No `FAIL:` lines were found in the job log.

Classification: **WINDOWS CI PASS on PR #11**. This is not default-branch integration and not user-local evidence. PR #11 remains open for review. After the two documentation-only default-branch status commits, its base branch is two commits ahead; those commits did not alter compiler or test sources. The PR has not been merged.

Issue #9 remains open until ordinary PR review/integration and the separate R25-R4 archive file-by-file comparison are complete. The R25-R4 comparison remains NOT RUN.


## PR #11 replay complete and branch synchronized - 2026-11-22

- PR #11: https://github.com/Sharnou/Sharnou-Compiler/pull/11
- Feature branch: `automation/m6-baseline-current-head-20261122`
- Current branch head after a non-force two-parent sync with latest default docs: `614a9badfd4aa2b9682bad384147c3b1e6066020`.
- Current default branch parent: `cbc8ea0e0bb65e1a4bf1de748fb9aad8d30433ae`.
- PR compare: 2 commits ahead, 0 behind; only the five intended frozen-baseline files appear in the PR diff.

Windows CI on the source/test tree before the documentation-only sync:
- [45003405485](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45003405485): `windows-m6-83` success, Stage 2 25/25, Stage 4 20/20, PE verifier 4/4, Stage 5 25/25, Stage 6 9/9; aggregate 83/83.
- [45003405576](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45003405576): `windows-stage7a` success, 23/23 on the same predecessor `37451e384e2e7e669c8368882225619cc9a67e67`.
- The sync commit adds only the two status-document commits as the second parent. Compiler, verifier, tests, fixtures, manifest and frozen payload blobs were not changed. No separate CI run is claimed on merge commit `614a9...`.

The default branch still does not contain the baseline; PR #11 remains OPEN / UNMERGED for normal review. The R25-R4 archive comparison remains NOT RUN.


## Final PR #11 state - 2026-11-22

- PR #11 head after synchronization: `939a8b63085e0ef8f2f23b01d5122d4c702e7625`.
- It was based on default HEAD `b90710f05abb85563e6c87885dbd72caba61899d`, compare 3 ahead / 0 behind at the time of that check.
- PR diff remains exactly five baseline files. No compiler, PE verifier, Stage 7A implementation, existing regression script or fixture is changed.
- Windows run 45003405485 passed the frozen M1-M6 suite 83/83, and run 45003405576 passed Stage 7A 23/23, both on predecessor source/test tree commit `37451e384e2e7e669c8368882225619cc9a67e67`. The later PR merge commits only synchronize status-document commits; compiler/verifier/tests/payload blobs are unchanged. No new runtime run is claimed for merge commit `939a8b6...`.
- The final status-doc write itself advances default branch after base `b90710f...`; PR #11 may therefore be one docs-only commit behind after this status write. This does not change its five-file diff or tested code/test blobs.
- PR remains OPEN / UNMERGED for review. The default branch still does not contain the frozen baseline. The R25-R4 archive comparison remains NOT RUN.


## Final current-head Windows validation - 2026-11-22

### PR #11 frozen baseline

- Branch `automation/m6-baseline-current-head-20261122`, exact tested head `3e8dec1475d45ae2537fc30bd398ebe5a7ee7b67`.
- Windows run [45004007198](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45004007198) completed SUCCESS; job `windows-m6-83` ID `137151468446`.
- Results: Stage 2 25/25; Stage 4 20/20; PE verifier 4/4; Stage 5 25/25; Stage 6 9/9; aggregate **83/83 PASS**; ASCII/no-BOM check PASS.
- Windows run [45004007206](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45004007206) completed SUCCESS on the same exact head; job `windows-stage7a` ID `137151468216`; Stage 7A **23/23 PASS**.
- No `FAIL:` result lines appear in either workflow log. These are WINDOWS CI PASS results on PR #11, not user-local runs.

### PR / issue state

- PR #11 is open and not merged. It adds exactly five frozen-baseline files. At this validation snapshot, PR branch compared 4 commits ahead / 0 behind default. Default HEAD at this status write: `bd72a8636e6948bbf4834dff4eae47c0fcf97c01`.
- Issue #9 remains OPEN until normal PR integration and the separate R25-R4 archive file-by-file comparison. The suite is not yet on default.
- Issue #10: default-branch Stage 7A run 44996610001 passed 23/23 on earlier default source HEAD; the PR #11 head also passed 23/23 in run 45004007206. User-local 7A result remains unreported.
- Issue #1 ABI status is unchanged: source-level static findings only; stack probing, unwind metadata, runtime preservation/stack/argument tests, and generic API marshalling remain unimplemented/unverified.
- Issue #8 body and this session-state file have been synchronized. Daily `Sharnou DevAgent Progress` is enabled; weekly `Advance Sharnou Stack` remains enabled. Legacy Honour War daily-upgrade tasks remain disabled.

The default-branch documentation commit below is status-only. No compiler, PE verifier, test, build, Engine, or game source was changed. No PR was merged.


## Latest PR #11 exact-head results - 2026-11-22

PR #11 current tested feature-branch head: `d33778f6f23a006965f25aeb4dfc8e55cdc49d22`.

Same-head Windows CI:
- M1-M6 frozen baseline [run 45004124843](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45004124843), job `windows-m6-83` ID `137151818001`, conclusion success: Stage 2 25/25, Stage 4 20/20, PE verifier 4/4, Stage 5 25/25, Stage 6 9/9; aggregate **83 passed, 0 failed, 83 total**.
- Stage 7A [run 45004124879](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45004124879), job `windows-stage7a` ID `137151817931`, conclusion success: **23 passed, 0 failed, 23 total** (8 positive runtime, 12 negative diagnostic, 3 instruction/branch checks).
- Both workflows report ASCII/no-BOM PASS and no failed test records.
- PR compare before this status-only commit: 5 commits ahead / 0 behind; exactly five frozen-baseline paths in the diff. Default base HEAD at this check: `e0e281ea53c5ace7279d42f949a5ee06cf0d80ee`.

The status-only documentation commit below advances default by one commit; PR #11 will therefore be one docs-only commit behind afterwards. Its compiler, verifier, five baseline files, fixtures and test source are unchanged. No CI result is claimed for any later merge-only PR commit.

Issue #9 remains open: PR review/integration is pending and the separate R25-R4 archive file comparison is NOT RUN. Issue #10 remains open: Windows CI passes but user-local 7A acceptance is not separately recorded. Issue #1 remains open and blocked on ABI implementation/runtime evidence.


## Final baseline and control-flow CI on synchronized PR head - 2026-11-22

PR #11 synchronized head `c525a4491f033dc882488ab84fbb312c5e477061` completed both Windows workflows successfully:
- [45004279512](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45004279512), job `windows-m6-83` ID `137152283687`: Stage 2 25/25, Stage 4 20/20, PE verifier 4/4, Stage 5 25/25, Stage 6 9/9; aggregate **83 passed, 0 failed, 83 total**.
- [45004279593](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45004279593), job `windows-stage7a` ID `137152283815`: **23 passed, 0 failed, 23 total** (8 positive runtime, 12 negative parser/type, 3 instruction/branch checks).
- Both jobs concluded success, both logs report ASCII/no-BOM PASS, and no FAIL test lines were present.

At this point the feature branch was based on default HEAD `81329d675b8383a54709f41c5a3203b422421740`, compare 6 ahead / 0 behind, and the PR diff contained only the five frozen-baseline paths. This status-only documentation commit may move the feature branch one docs-only commit behind; compiler, verifier, tests, fixtures and baseline payload are unchanged.

PR #11 remains OPEN / UNMERGED. The frozen 83-case suite is proven by Windows CI on the PR branch but is not yet in default. The R25-R4 archive comparison remains NOT RUN. M7A is WINDOWS CI PASS; user-local acceptance is still not separately recorded. ABI issue #1 remains OPEN and blocked on implementation/runtime evidence.


## Live compiler audit and Milestone 7B proposal - 2026-11-22

### Repository and branch
- Repository: `Sharnou/Sharnou-Compiler`.
- Default branch: `Sharnou-Compiler`.
- Default HEAD reviewed: `45c83e1941fd74ca1ce94a4f0bc9ffe72a43efe3`.
- Changed compiler/test/workflow paths: **none**. This run performed repository review, Windows CI log inspection, and status-only persistence.
- No feature branch, PR, source file, workflow, or user machine was modified. No workflow was dispatched.

### Milestone 7A and frozen baseline - same-head Windows evidence
- Default-branch Windows run [45004368571](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45004368571), job `windows-stage7a` (`137152555458`), completed SUCCESS on exact default HEAD `45c83e1941fd74ca1ce94a4f0bc9ffe72a43efe3`. Log: ASCII/no-BOM PASS; 8 positive runtime cases, 12 negative diagnostic cases, 3 instruction/branch checks; **23 passed, 0 failed, 23 total**; Stage 7A PASS; Combined PASS.
- PR [#11](https://github.com/Sharnou/Sharnou-Compiler/pull/11), branch `automation/m6-baseline-current-head-20261122`, exact head `135b7eec7bf13fc147756dfaeeb3f92eab57a250`, base SHA `45c83e1941fd74ca1ce94a4f0bc9ffe72a43efe3`, is OPEN / UNMERGED. Compare: 7 ahead / 0 behind; its diff is five baseline-related additions only.
- PR #11 Windows baseline run [45004395351](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45004395351), job `windows-m6-83` (`137152637466`), completed SUCCESS on exact PR head `135b7eec7bf13fc147756dfaeeb3f92eab57a250`. Logs: Stage 2 25/25; Stage 4 20/20; PE verifier 4/4; Stage 5 25/25; Stage 6 9/9; aggregate **83 passed, 0 failed, 83 total**; ASCII/no-BOM PASS.
- PR #11 Windows Stage 7A run [45004395353](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45004395353), job `windows-stage7a` (`137152637335`), completed SUCCESS on the same exact PR head `135b7eec7bf13fc147756dfaeeb3f92eab57a250`: **23 passed, 0 failed, 23 total** (8 positive, 12 negative, 3 instruction/branch checks).
- Thus 7A and all 83 M1-M6 cases have WINDOWS CI PASS on one current PR head, but the baseline remains absent from default until PR #11 is normally reviewed/integrated. This does not replace user-local 7A evidence.

### PR and issue state
- PR #11: OPEN / UNMERGED; current head `135b7eec7bf13fc147756dfaeeb3f92eab57a250`; compare 7 ahead / 0 behind; five additions only.
- PR #6: OPEN / UNMERGED, old head `9dfe1bc09685a6f7deb9d29b5192b1aae0686039`; compare to current default 15 ahead / 37 behind. Do not merge, rebase, or rewrite it automatically.
- PR #5: OPEN / UNMERGED, proposed 7B head `0b8dee87b699eabcaaac37f111686231fb29a82c`; compare 2 ahead / 37 behind, merge base `352c65e05524d494970b2d8b52b7089d12d19435`. It is stale relative to current default and is a proposal, not accepted implementation.
- PR #7: OPEN / DRAFT, head `ac3849800412b1208acb540ef090ffb3ac0455ca`; native DevAgent test orchestrator proposal only.
- PR #4: OPEN / UNMERGED. No PR was modified, approved, or merged.
- Issues #8, #9, #10 and #1 remain OPEN. Issue #9 awaits normal PR #11 review/integration and the separate R25-R4 archive equivalence comparison. Issue #10 still lacks a separate user-local M7A acceptance report. Issue #1 ABI gates remain unresolved.

### Milestone 7A source audit
- Current compiler blob: `ee01ef77b068df5d149934fbf463c43b34c54bf3`; recorded file SHA-256: `c97bd0c4d9ad94b1b4855bbdcd6f843f563f75b35771106ae8976cae2bbda250`.
- PE verifier blob: `3606b57920043882a2277ad41fd0e0578156944a`; recorded file SHA-256: `953a20c2274eee42eee2523c5608fd48e6dc574e4b5465464e910db560d55179`.
- Stage 7A test blob: `80d8df1c9a6da7c8fb6f2b414c2929f07ba44804`; recorded file SHA-256: `ffd8a3518d8fc943adb97e319a29a8822d4e5c409226597d0010b40da23eae05`.
- Static review confirms the current subset: signed integer comparisons, zero/nonzero integer truth conditions, comparison normalization, nested if/while, and label-based near-branch fixups. It explicitly rejects chained comparisons, string comparisons, logical AND/OR, else-if shorthand, and returns nested inside control-flow blocks. The Windows CI suite covers eight positive programs, twelve negative cases, and three instruction checks.
- ABI carry-forward remains: no large-frame stack probe, no `.pdata`/`.xdata` unwind metadata or exception directory, no executed nonvolatile-register/RSP/stack-argument sentinel suite, and no generic signature-driven Windows API marshaller. These are repository/static findings, not new runtime failures. Do not claim self-hosting readiness.

### Milestone 7B proposal - no implementation performed
The current PR #5 candidate reports Windows CI run [44693097619](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44693097619): Stage 7A 23/23 plus candidate Stage 7B 32/32 (15 positive, 13 negative, 4 instruction-presence checks), but it did not include the 83-case frozen baseline and is based on an old branch. Do not port or accept it wholesale.

A bounded proposal for a fresh 7B patch after the baseline is on the accepted base:
1. Boolean scalar values: `true`/`false`, normalized 0/1 storage, Boolean declarations/assignments; reject integer/Boolean implicit conversions and Boolean arithmetic.
2. Precedence and semantics: unary `!`, comparisons, then `&&`, then `||`; strict Boolean operands for logical operators; `==`/`!=` for matching types; ordered comparisons remain integer-only. Preserve existing integer conditions for 7A compatibility while allowing Boolean conditions explicitly.
3. Short-circuit native branches: `&&` skips RHS when left is false; `||` skips RHS when left is true; use existing rel32 fixup machinery. Add dynamic-variable-left side-effect tests for both skip and evaluate paths (the current candidate tests use constant left operands only).
4. Loop control: `break` and `continue` only inside loops; use a nested loop-target stack with push/pop in `try/finally`; break targets the current loop exit and continue targets its condition/header. Add deeper nested-loop and nested-if cases.
5. Nested returns: allow return in nested if/else/loop blocks, emit the existing ABI epilogue for each return edge; keep conservative definite-return analysis (a loop is not assumed to terminate). Functions remain up to four integer parameters and integer return values in this bounded stage; explicitly reject Boolean function arguments/returns until a separate ABI design is accepted.
6. Tests: preserve M6 83 + 7A 23; add runtime positives for Boolean assignment/equality/precedence, dynamic short-circuit skip/evaluate paths, break/continue including nested loops, nested returns; negative tests for mixed types, Boolean arithmetic/ordered comparisons, invalid loop-control placement, Boolean function ABI misuse, and missing return paths; add a rel32 decoder that validates each emitted branch target is within a valid code range rather than only checking opcode presence.
7. Keep the existing Windows x64 call convention and frame contract unchanged: RCX/RDX/R8/R9 integer arguments, EAX integer return, 32-byte shadow space, 16-byte call-site alignment, RBP frame, and existing local/temp stack-slot layout.

Dependency order: obtain normal review/integration of PR #11 (no auto-merge); complete the separate R25-R4 archive comparison; retain Issue #1 ABI gate. Only then create a fresh, isolated 7B feature branch from the accepted current baseline and run **83 + 23 + all 7B tests on the same exact commit**. No source patch, PR update, or workflow dispatch was performed in this run.

### Native compiler / DevAgent state
- Native self-hosted `SharnouCompiler.exe`: NOT BUILT / NOT RUN.
- PR #7 DevAgent: prior Windows CI run `44758761226` and artifact `14654214120` prove only a native test orchestrator. It is not a source-generating AI agent. Persistent autonomous worker/checkpoint/recovery, Windows-host deployment, and restart/runtime proof: NOT IMPLEMENTED / NOT RUN.
- M1-M6 user-local passes remain USER-REPORTED WINDOWS PASS. The current default M7A and same-head PR #11 baseline/7A results above are WINDOWS CI PASS. Source audit is REPOSITORY PRESENT / STATIC REVIEWED. No local Windows execution was performed by the assistant.


## Scheduled audit - 2026-11-23

### Repository and live branch state
- Repository: `Sharnou/Sharnou-Compiler`; default branch: `Sharnou-Compiler`; starting/default HEAD: `12a7daade17ee01519566eea5bc668ecab4a537e`.
- PR #6: OPEN / UNMERGED, branch `automation/restore-m6-83-regression`, head `9dfe1bc09685a6f7deb9d29b5192b1aae0686039`, 15 ahead / 39 behind current default. Its diff is exactly five baseline paths. It remains explicitly not mergeable by this automation.
- PR #11: OPEN / UNMERGED, branch `automation/m6-baseline-current-head-20261122`, head `135b7eec7bf13fc147756dfaeeb3f92eab57a250`, 7 ahead / 2 behind current default. The two commits behind are documentation-only changes to `Docs/AI-ISSUE-REGISTER.md` and `Docs/AI-SESSION-STATE.md`; compiler, verifier, Stage 7A test and workflow blobs match current default. Its diff remains the same five baseline paths.
- PR #5: OPEN / UNMERGED, unaccepted 7B proposal, head `0b8dee87b699eabcaaac37f111686231fb29a82c`.
- PR #7: OPEN / DRAFT, native DevAgent test-orchestrator proposal, head `ac3849800412b1208acb540ef090ffb3ac0455ca`.
- PR #4: OPEN / UNMERGED roadmap/automation proposal, head `c80828005c069956dca4ab3b045adc8afcce397b`.
- Issues #1, #8, #9 and #10 remain OPEN.

### Windows CI evidence
- Default branch run [45006046266](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45006046266), head `12a7daade17ee01519566eea5bc668ecab4a537e`, job `windows-stage7a`: SUCCESS. Stage 7A: 23 passed, 0 failed, 0 skipped; 8 positive runtime cases, 12 negative parser/type cases, 3 instruction/branch checks. ASCII/no-BOM check passed.
- PR #6 exact head: run [44700641397](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44700641397), job `windows-m6-83`, attempt 2: SUCCESS, 83/83; run [44700641419](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44700641419), job `windows-stage7a`, attempt 2: SUCCESS, 23/23.
- PR #11 exact head: run [45004395351](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45004395351), job `windows-m6-83`: SUCCESS, 83/83; run [45004395353](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45004395353), job `windows-stage7a`: SUCCESS, 23/23. Both ran against the same exact PR head.
- The 83-case suite breakdown is Stage 2 25/25, Stage 4 20/20, PE verifier 4/4, Stage 5 25/25 and Stage 6 9/9. Case-intent classification is 36 positive / 47 negative; the manifest and workflow aggregate report suite totals rather than separate polarity totals. The Stage 2 adapter moves the obsolete pre-7A `if` rejection fixture into the positive set in a temporary copy; the frozen payload and original script remain unchanged.
- PR #5 run [44693097619](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44693097619), exact head `0b8dee87b699eabcaaac37f111686231fb29a82c`: SUCCESS, Stage 7A 23/23 and proposed Stage 7B 32/32 (15 positive, 13 negative, 4 instruction checks). It did not run the 83-case baseline.
- PR #7 run [44758761226](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44758761226), exact head `ac3849800412b1208acb540ef090ffb3ac0455ca`: SUCCESS. Native `SharnouDevAgent.exe` was built with SHA-256 `9F128ED96972858B13C763B4324813B3D6A1970737F2403C10C70717CE947341`, executed with process exit code 0, and propagated a child exit code of 7. Artifact ID `14654214120`, ZIP digest `sha256:94a10a4ac3cb48f09c70497f2f9b6f63c46d8eaf183ed987e5a97d39d6aec8d1`, size 2556 bytes; expires 2026-12-04.

### Source and static audit
- Current default compiler blob: `ee01ef77b068df5d149934fbf463c43b34c54bf3`; Windows baseline runner reported compiler SHA-256 `f1cb1ea2920c62c781f317b52ba281c2a7df72f626638a4aab71ff8d2dd47ead`.
- Current PE verifier blob: `3606b57920043882a2277ad41fd0e0578156944a`; Windows baseline runner reported verifier SHA-256 `8efec55da3a1614f30272227f8d8158710337cb06148fb7f98b8fa2ff013a3de`.
- Stage 7A test blob `80d8df1c9a6da7c8fb6f2b414c2929f07ba44804` and workflow blob `2b982f0165495854b52d346637e457932a5b0271` match between default and PR #11.
- Static review confirms the Stage 7A parser accepts if/else and while with integer conditions, supports the six signed integer comparisons, rejects chained comparisons, and uses signed SETcc plus MOVZX. The emitter uses TEST/JZ and JMP rel32 labels through the existing code-fixup pass. The machine-code tests verify opcode byte-pattern presence; they do not independently decode every rel32 displacement and validate its destination.
- The baseline runner pins the original archive SHA-256 `0b6bf15445a5dfd8cbf93450af7fd2f5fd6239d4ed082ab18b09878a94b8b164` and bundle SHA-256 `3dd1d7417874159c0bc625edbbc1e8cee1ae7d8a6ea42f30b4dd80ba92102748`. It verifies the compressed bundle and member hashes embedded in that bundle, but does not read the original `SHA256SUMS.txt`; the manifest's `members_verified_against_original_sha256_manifest` field is not enforced by the runner. The separate R25-R4 archive comparison remains NOT RUN (archive SHA-256 `CA01AEACB2E35C6E8039E58F15202A01399DAEA3E0A24E7B4D357772C8EF1274`).
- PR #5 remains proposal-only. Its tests use constant literal left operands for short-circuit skip/evaluate cases; add dynamic-variable-left side-effect cases. Add explicit Boolean function argument/return rejection tests, deeper nested-loop cases, and a rel32 target decoder. Keep the function ABI integer-only until a separate ABI design is accepted.
- PR #7 is not an AI source-generating agent. Its Sharnou program checks workspace files, probes child exit-code propagation, and launches the Stage 7A PowerShell regression suite. Its `sh_dev_run_process` accepts a command-line string (maximum 1023 bytes), calls CreateProcessA, inherits standard handles and waits indefinitely; no command allowlist, sandbox, timeout, job-object process-tree containment or cancellation is present. Do not expose it to model-generated commands before a reviewed execution policy exists.

### Build/runtime classification and next dependency
- Evidence: WINDOWS CI PASS for default Stage 7A, PR #6 / PR #11 baseline and Stage 7A, PR #5 candidate tests, and PR #7 native test-orchestrator build/runtime. USER-REPORTED WINDOWS PASS remains the evidence class for earlier M1-M6 user-local runs. Source review is REPOSITORY PRESENT / STATIC REVIEWED. Assistant-side local Windows execution: NOT RUN.
- Native self-hosted `SharnouCompiler.exe`: NOT BUILT / NOT RUN. PR #7's native DevAgent artifact is PR-only and is a regression orchestrator, not an AI developer.
- Issue #1 ABI gates remain OPEN: large-frame stack probing, PE unwind metadata, runtime nonvolatile-register/RSP/stack-argument sentinels, and generic checked Windows API-call marshalling. Persistent agent worker/checkpoint/recovery, model connectivity, source generation, Windows-host deployment and restart proof are NOT IMPLEMENTED / NOT RUN.
- No compiler, verifier, test, build-script, runtime, Engine or game source changes were made. No workflow was dispatched. The only intended writes in this session are the authorized status documents and issue records.
- Do not update the accepted development plan: 7B remains unaccepted. Next dependency order is normal human review/integration decision for PR #11 (never auto-merge), complete the R25-R4 file-by-file comparison and retain the Issue #1 ABI gate; only then create a fresh isolated 7B branch and require 83 + 23 + all 7B cases on one exact commit. Before any autonomous agent code execution, design and review a bounded process policy, durable worker/checkpoint/recovery, audit trail and restart test.


## DevAgent autonomy architecture session - 2026-11-24

### User request
The user requested SharnouDevAgent be advanced from a simple test orchestrator to a high-capability development agent: internet/local search, read/download/learn, structured reasoning and planning, specialist agent creation/editing, bug solving and bounded automatic correction, authorized reverse engineering, and optional second opinions from ChatGPT/OpenAI or Perplexity, without requiring those services for local operation.

### Repository preflight and exact source audit
- Mandatory read-first documents read from the current branch: `AGENTS.md`, `AI_START_HERE.md`, `Docs/AI-SESSION-STATE.md`, `Docs/AI-DEVELOPMENT-PLAN.md`, `Docs/AI-ISSUE-REGISTER.md`, and `README.md`.
- Starting default branch HEAD: `cf8a9cd26cf3819d1ee3156155eafa5259c39b05`.
- Current Stage 0 compiler blob `ee01ef77b068df5d149934fbf463c43b34c54bf3` does not contain `sh_dev_run_process`, `CreateProcessA`, or `GetExitCodeProcess`. The DevAgent native test utility is only on open draft PR #7's `automation/sharnou-dev-agent-native` branch.
- PR #7's `Examples/DevAgent.sharnou` checks workspace files, probes child exit-code propagation, and launches the Stage 7A PowerShell regression suite. Its own PR description explicitly states it is a native test/development orchestrator, not an AI source-generating agent.
- PR #7 branch compiler blob `86d9d25350d581b165ee79b0664f8b6640e6408b` implements `sh_dev_run_process(String)->Integer` using `CreateProcessA`, waits with `WaitForSingleObject(INFINITE)`, returns the child code with `GetExitCodeProcess`, and uses a fixed 1024-byte command buffer. Static inspection found no executable allowlist, structured argument vector, timeout, cancellation, Job Object process-tree containment, restricted-token/AppContainer policy, or durable task journal. Do not expose this interface to model-generated command strings.
- PR #7 remains an open draft according to the repository status record. Its Windows run `44758761226` passed as a test orchestrator and uploaded artifact `14654214120`; this is not evidence of AI code generation or autonomous repair.
- The current plan/state still record the frozen 83-case M1-M6 suite as absent from default pending normal PR #11 integration, M7A as Windows-CI tested but not separately user-locally recorded in that state, and ABI issue #1 as open. These preconditions remain material to compiler-controlled autonomy.

### Persisted design
- Added `Docs/SHARNOU-DEVAGENT-AUTONOMOUS-ARCHITECTURE.md` (commit `0e05166c1ef284af9ccdc3ecb2ada19262364c58`).
- Added a README roadmap link (commit `3d8fb0bacb01cf82730d904d1cc2a40f0290765e`).
- Created tracking issue [#14](https://github.com/Sharnou/Sharnou-Compiler/issues/14).
- The architecture specifies an in-process Sharnou-owned local inference runtime, typed tool registry, safe process broker, native WinHTTP search/fetch/download, quarantine/hash/provenance, local knowledge index, task graph and evidence journal, declarative agent manifests, staged patch/rollback loops, authorized static PE/x64 reverse engineering, and optional OpenAI Responses / Perplexity Agent API adapters.
- Remote provider calls are optional. A local model and its weights are required for generative offline reasoning; retrieval memory alone is not model training. Local operations must work with networking disabled.
- Agent-generated operations are limited by capability and workspace policy. No unrestricted shell, privilege escalation, silent policy changes, auto-execution of downloads, auto-merge, or auto-release. External API credentials must be protected with Windows Credential Manager or DPAPI and must not be exposed to prompts/logs.

### Changed paths and execution evidence
- Changed only documentation/tracking: `Docs/SHARNOU-DEVAGENT-AUTONOMOUS-ARCHITECTURE.md`, `README.md`, `Docs/AI-DEVELOPMENT-PLAN.md`, `Docs/AI-SESSION-STATE.md`, `Docs/AI-ISSUE-REGISTER.md`, and issue #8/#14 records.
- No compiler, PE verifier, example, test fixture, build script, workflow, Engine, IDE, or game source was modified. No branch/PR was merged, no workflow was dispatched, and no Windows build or native test was executed by the assistant.
- Evidence classification: REPOSITORY PRESENT / STATIC REVIEWED for the existing DevAgent code and architecture proposal; WINDOWS CI PASS (historical PR #7 test-orchestrator run only); NOT IMPLEMENTED / NOT RUN for the autonomous AI agent and local LLM runtime.

### Dependency-ordered next actions
1. Keep the 83-case restoration/provenance gate and issue #1 ABI audit open; no autonomous compiler write access until these gates are reconciled.
2. Design/implement Phase B process broker first: typed executable IDs and argument arrays, canonical workspace roots, hash allowlists, timeouts/cancellation, process-tree containment, bounded I/O, and negative tests. Do not reuse PR #7's raw command-line API for model-directed execution.
3. Implement native research/read/download and quarantine with host policy and integrity evidence.
4. Build one supported Sharnou-owned local model inference path and prove offline operation with model-file hash and golden-vector tests.
5. Add task planning, evidence memory/restart recovery, agent manifest factory, bounded repair/rollback, and static reverse-engineering tools.
6. Add optional remote AI adapters only after local mode is independently functional and credential/redaction tests pass.

This session is architecture and governance only; it is not a claim that SharnouDevAgent has gained these capabilities.


## Scheduled audit - 2026-11-24 08:15 Africa/Cairo

### Live repository and pull-request state

- Repository: `Sharnou/Sharnou-Compiler`; default branch: `Sharnou-Compiler`.
- Starting default HEAD: `ff24777d241332ffc5a6a43d16cc688ff9f4dff7`.
- The mandatory current-branch documents were read: `AGENTS.md`, `AI_START_HERE.md`, `Docs/AI-SESSION-STATE.md`, `Docs/AI-DEVELOPMENT-PLAN.md`, `Docs/AI-ISSUE-REGISTER.md`, `README.md`, and the renderer roadmap. Directly relevant compiler, verifier, Stage 7A/7B tests, workflow, baseline runner/manifest/payload metadata, DevAgent prototype, architecture, issues and PR discussions were inspected.
- PR #4: OPEN / UNMERGED, roadmap proposal, head `c80828005c069956dca4ab3b045adc8afcce397b`.
- PR #5: OPEN / UNMERGED, unaccepted 7B proposal, head `0b8dee87b699eabcaaac37f111686231fb29a82c`; compare 2 ahead / 46 behind.
- PR #6: OPEN / UNMERGED, frozen baseline restoration, head `9dfe1bc09685a6f7deb9d29b5192b1aae0686039`; compare 15 ahead / 46 behind. Do not merge this PR by automation.
- PR #7: OPEN / DRAFT, native test orchestrator, head `ac3849800412b1208acb540ef090ffb3ac0455ca`; compare 9 ahead / 46 behind.
- PR #11: OPEN / UNMERGED, fresh baseline integration candidate, head `135b7eec7bf13fc147756dfaeeb3f92eab57a250`; compare 7 ahead / 9 behind. Its diff remains exactly the five baseline paths. The nine commits by which it is behind are documentation-only: compare from its merge base `45c83e1941fd74ca1ce94a4f0bc9ffe72a43efe3` to current default changes only the AI plan, issue register, session state, DevAgent architecture document, and README.
- PR #13: OPEN / DRAFT, documentation-only reverse-engineering capability proposal, head `43d2447cdbadb6280fbcc3b190c666c07b97b352`; compare 2 ahead / 5 behind.
- Issues #1, #8, #9, #10, #12 and #14 remain OPEN. No issue state was changed.

### Windows Actions evidence

- Default branch run [45291564684](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45291564684), exact HEAD `ff24777d241332ffc5a6a43d16cc688ff9f4dff7`, job `windows-stage7a` (`138101331576`): SUCCESS. Source encoding/no-BOM PASS; Stage 7A 23 passed, 0 failed, 23 total (8 positive runtime, 12 negative diagnostics, 3 instruction/branch checks). The workflow log did not separately print a numeric PowerShell process exit code; the Actions step and job concluded success.
- PR #6 latest same-head Windows runs remain [44700641397](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44700641397), job `136468493547`, SUCCESS, frozen baseline 83/83; and [44700641419](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44700641419), job `136468505598`, SUCCESS, Stage 7A 23/23. Both were attempt 2 on PR #6 head `9dfe1bc09685a6f7deb9d29b5192b1aae0686039`.
- PR #11 same-head Windows runs [45004395351](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45004395351), job `137152637466`, SUCCESS, 83/83; and [45004395353](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45004395353), job `137152637335`, SUCCESS, Stage 7A 23/23. Both ran on exact PR #11 head `135b7eec7bf13fc147756dfaeeb3f92eab57a250`, so the 83-case suite and Stage 7A passed on one exact commit. Suite totals: Stage 2 25, Stage 4 20, PE verifier 4, Stage 5 25, Stage 6 9; 83 passed, 0 failed. The case-intent split is 36 positive / 47 negative; the runner does not emit a separate skipped counter, and all 83 inventory cases are accounted for.
- The five baseline file blobs on PR #11 are identical to PR #6: workflow `c6a27e24a7d0bad9eaf554bb59c1d81e0f865c47`, graphics module `6644243df729fc0334b617231e40b3496e15016d`, payload `d2c1faa72e702d0575ac1623d89b56c087edddb8`, runner `1bc252b197ba244ea9910ad67b4b8b3cd141138d`, manifest `bbf9a2beb87b84bb51261a28268247d96419424c`. The compiler, verifier, root test runner, Stage 7A test and Stage 7A workflow blobs on current default are identical to PR #11 and PR #6.
- PR #5 run [44693097619](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44693097619), job `136143353548`, SUCCESS: Stage 7A 23/23 and proposed Stage 7B 32/32 (15 positive runtime, 13 negative diagnostics, 4 instruction-pattern checks). It did not run the 83-case baseline and is not acceptance evidence for current default.
- PR #7 run [44758761226](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44758761226), job `136467612083`, SUCCESS: built and PE-verified the native DevAgent test utility, ran it, verified intentional child exit code 7 propagation, and reported DevAgent process exit code 0. Artifact ID `14654214120`; artifact ZIP SHA-256 `94a10a4ac3cb48f09c70497f2f9b6f63c46d8eaf183ed987e5a97d39d6aec8d1`.
- PR #13 documentation-only run [45286151951](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45286151951), job `138082870219`, SUCCESS; Stage 7A 23/23. No code was changed by that PR.
- PR #4 earlier roadmap workflow run `44594385914` concluded success at its recorded head; no new PR #4 workflow was dispatched.

### Compiler, baseline and Milestone 7B audit

- Current compiler SHA-256, reported by the same-source Windows baseline job: `f1cb1ea2920c62c781f317b52ba281c2a7df72f626638a4aab71ff8d2dd47ead`. Current PE verifier SHA-256: `8efec55da3a1614f30272227f8d8158710337cb06148fb7f98b8fa2ff013a3de`. Current Stage 7A test Git blob: `80d8df1c9a6da7c8fb6f2b414c2929f07ba44804`; previously recorded content SHA-256: `ffd8a3518d8fc943adb97e319a29a8822d4e5c409226597d0010b40da23eae05`.
- Stage 7A source review confirms six signed SETcc comparisons normalized by MOVZX, conditional TEST/JZ and JMP rel32 code fixups, unresolved-label rejection, and signed-32-bit displacement bounds. Existing three machine-code checks detect instruction patterns but do not independently validate each branch destination. This is a test-strengthening gap, not a reproduced runtime defect.
- The 83-case baseline is still absent from default. Original M6 archive SHA-256: `0b6bf15445a5dfd8cbf93450af7fd2f5fd6239d4ed082ab18b09878a94b8b164`; compressed payload SHA-256: `3dd1d7417874159c0bc625edbbc1e8cee1ae7d8a6ea42f30b4dd80ba92102748`; recorded original `SHA256SUMS.txt` SHA-256: `61539cb577b3c116d25739cdb8286e3de38410af1d1a39fa1418893799f3c9c9`. The runner verifies the pinned bundle and each restored member against hashes embedded in the payload, but does not independently read/verify the original `SHA256SUMS.txt`. The manifest currently says members were verified against that original manifest; the runner does not enforce that claim. The separate R25-R4 archive comparison (SHA-256 `CA01AEACB2E35C6E8039E58F15202A01399DAEA3E0A24E7B4D357772C8EF1274`) remains NOT RUN.
- PR #5 remains a proposal only. Its dynamic short-circuit lowering uses conditional branches, but the existing side-effect tests use literal left operands; add variable-left skip/evaluate cases for both AND and OR. Add explicit negative tests for Boolean function arguments and Boolean returns while the function ABI remains integer-only; add a deeper nested-loop case; and replace opcode-presence-only checks with a linker fixup self-check that decodes each emitted rel32 displacement and verifies its target label lies within .text. The existing nested-loop test does exercise innermost-loop break/continue.
- Static correction: `Get-ConstantValue` visits the right subtree when the logical left operand is dynamic in order to validate constant arithmetic. This is not proof that the runtime evaluates the RHS and is not a reproduced short-circuit defect; treat it as compile-time validation policy. The concrete gap is the absence of dynamic-left runtime tests.
- Minimum acceptance for a fresh 7B candidate: frozen M1-M6 83 + Stage 7A 23 + existing Stage 7B 32, plus the new required tests, all on one exact Windows commit with zero failures and zero skipped cases. Do not reuse or merge the stale PR #5 branch as the current implementation.

### Native compiler and SharnouDevAgent state

- PR #7 generated native AMD64 PE32+ `SharnouDevAgent.exe` SHA-256 `9F128ED96972858B13C763B4324813B3D6A1970737F2403C10C70717CE947341` on the Windows runner. It is a native test orchestrator only: workspace checks, child-process exit-code propagation, and a Stage 7A regression launch. It is not present on default and does not generate or edit source.
- The PR #7 process intrinsic accepts a raw command string, calls CreateProcessA, inherits standard handles, and waits with INFINITE. There is no allowlist, structured argument boundary, workspace sandbox, timeout/cancellation, Job Object process-tree containment, or output bound. It must not receive model-generated commands.
- Native self-hosted `SharnouCompiler.exe`: NOT BUILT / NOT RUN. Autonomous AI source generation, local inference, durable worker/checkpoint/recovery, deployment and restart proof: NOT IMPLEMENTED / NOT RUN. The architecture document and issue #14 are proposals, not implementation evidence.
- Historical ABI gates in issue #1 remain open: large-frame stack probing, PE unwind metadata, nonvolatile-register/RSP/argument runtime probes, and generic checked Windows API marshalling.

### Scope and next bounded task

- No compiler, verifier, test, fixture, build script, runtime, Engine, IDE, game or workflow source changes. No workflow dispatch, PR creation/modification/merge, deployment, or local Windows execution. The accepted development plan is unchanged because 7B and the additional DevAgent capabilities remain unaccepted proposals.
- Evidence: USER-REPORTED WINDOWS PASS (historical M1-M6 report); WINDOWS CI PASS (default 7A 23/23; PR #11 same-head 83/83 + 7A 23/23; PR #6 83/83 + 7A 23/23; PR #5 proposal 7A 23/23 + 7B 32/32; PR #7 native test orchestrator; PR #13 docs-only workflow); REPOSITORY PRESENT / STATIC REVIEWED (current compiler, baseline runner/manifest, 7B proposal and DevAgent architecture); NOT RUN (R25-R4 archive comparison, ABI runtime probes, user-local 7A acceptance, native self-hosted compiler, autonomous AI agent); BLOCKED (default baseline integration and remaining provenance/ABI gates).
- Next bounded task: obtain normal human review for PR #11 without automated merge; complete the independent R25-R4 archive comparison and resolve the original SHA256SUMS provenance discrepancy. Then complete the ABI gate plan. Only after explicit 7B scope approval, prepare a fresh isolated patch from the then-current default and require the combined baseline + 7A + 7B suite on one exact commit.


### Post-status documentation CI verification - 2026-11-24

The two status-only commits above triggered the existing push workflow; both completed successfully:
- Run [45340099960](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45340099960), exact commit `1d55cd00d93e60d0c57bf5be180b7afe229d2a3d`, job `windows-stage7a` (`138261413749`): SUCCESS; source encoding PASS; Stage 7A 23 passed, 0 failed, 23 total.
- Run [45340141791](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45340141791), exact commit `f4c018f171b45e997615b7e933281a0401804e43`, job `windows-stage7a` (`138261550209`): SUCCESS; source encoding PASS; Stage 7A 23 passed, 0 failed, 23 total.
- These are documentation-only follow-up CI checks, not new compiler-source, baseline, or 7B runs. The PowerShell test step did not print a separate numeric process exit code; the step and job concluded success.
- GitHub issue #8 was updated with the same follow-up evidence. No issue state changed.


## Scheduled audit update - 2026-11-25 08:47 Africa/Cairo

### Live repository and branch state
- Repository: `Sharnou/Sharnou-Compiler`; default branch: `Sharnou-Compiler`.
- Starting HEAD: `b817cc59f281a732f0e4759be87a00ec7ef63df6`. This is the current branch ref verified immediately before this status update.
- The latest default-branch Stage 7A workflow is [45340141791](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45340141791), SUCCESS on parent commit `f4c018f171b45e997615b7e933281a0401804e43`. It ran 23/23 (8 positive, 12 negative, 3 instruction checks). Current HEAD `b817cc5` has no run attached (GitHub returned zero runs for that exact SHA); it is a status-only `[skip ci]` commit after the tested parent.
- Current HEAD, tested parent `f4c018f`, and PR #11 head `135b7eec7bf13fc147756dfaeeb3f92eab57a250` have identical Git blobs for `Stage0/SharnouCompiler.ps1`, `Tools/SharnouPEVerify.ps1`, `Test.ps1`, `Tests/Test-Stage7A.ps1`, and `.github/workflows/stage7a-control-flow.yml`.
- Current blob IDs: compiler `ee01ef77b068df5d149934fbf463c43b34c54bf3`; verifier `3606b57920043882a2277ad41fd0e0578156944a`; root runner `699eb04aefdf1149aa5807107ce351f8c2aae676`; Stage 7A test `80d8df1c9a6da7c8fb6f2b414c2929f07ba44804`; workflow `2b982f0165495854b52d346637e457932a5b0271`.
- Windows CI source SHA-256 values from the same-source PR #11 baseline run: compiler `f1cb1ea2920c62c781f317b52ba281c2a7df72f626638a4aab71ff8d2dd47ead`; PE verifier `8efec55da3a1614f30272227f8d8158710337cb06148fb7f98b8fa2ff013a3de`.

### Current pull-request inventory
All remain OPEN / UNMERGED; no PR was modified or merged.
- PR #2 release database/publisher: head `4f16c9426cd51ad3bdfe97e7f1691a8fa26e218f`, 10 ahead / 56 behind.
- PR #4 roadmap/automation proposal: head `c80828005c069956dca4ab3b045adc8afcce397b`, 5 ahead / 49 behind.
- PR #5 7B candidate: head `0b8dee87b699eabcaaac37f111686231fb29a82c`, 2 ahead / 49 behind; not user-accepted.
- PR #6 frozen baseline restoration: head `9dfe1bc09685a6f7deb9d29b5192b1aae0686039`, 15 ahead / 49 behind. It remains open and must not be merged by automation.
- PR #7 native DevAgent test orchestrator: draft, head `ac3849800412b1208acb540ef090ffb3ac0455ca`, 9 ahead / 49 behind.
- PR #11 preferred baseline integration candidate: head `135b7eec7bf13fc147756dfaeeb3f92eab57a250`, 7 ahead / 12 behind. Its five-file baseline diff is unchanged; the 12 commits behind are documentation-only. It remains open for normal human review, not automatic merge.
- PR #13 reverse-engineering audit documentation: draft, head `43d2447cdbadb6280fbcc3b190c666c07b97b352`, 2 ahead / 8 behind.

### Windows workflow evidence and test accounting
- Default Stage 7A: run [45340141791](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45340141791), job `138261550209`, SUCCESS; 23 passed, 0 failed, 23 total. The log includes ASCII/no-BOM PASS. No explicit process exit code is printed; the job completed successfully.
- PR #6 exact head: [44700641397](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44700641397), attempt 2, SUCCESS, 83/83; and [44700641419](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44700641419), attempt 2, SUCCESS, Stage 7A 23/23.
- PR #11 exact head: [45004395351](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45004395351), SUCCESS, 83/83; and [45004395353](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45004395353), SUCCESS, Stage 7A 23/23. Both tested the same exact PR head.
- PR #5 old candidate: [44693097619](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44693097619), SUCCESS; Stage 7A 23/23 and proposed Stage 7B 32/32 (15 positive runtime, 13 negative diagnostics, 4 instruction-presence checks). It did not run the 83-case baseline.
- PR #7 native utility: [44758761226](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44758761226), attempt 2, SUCCESS. It built and ran the native utility, re-ran Stage 7A 23/23, verified child exit code 7 propagation, and reported DevAgent process exit code 0. Artifact ID `14654214120`.
- PR #13 documentation branch: [45286151951](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45286151951), SUCCESS, Stage 7A 23/23; this is not new implementation evidence.
- Frozen M1-M6 accounting: Stage 2 25, Stage 4 20, PE verifier 4, Stage 5 25, Stage 6 9 = 83. Case-intent classification is 36 positive / 47 negative, inferred from case names; the manifest records suite totals only. The Windows runner reports 83 passed and 0 failed; it does not separately print a skipped count.
- Stage 7A accounting: 8 positive, 12 negative, 3 instruction checks = 23. The Windows log reports 23 passed, 0 failed.
- Stage 7B candidate accounting: 15 positive, 13 negative, 4 instruction checks = 32. The Windows log reports 32 passed, 0 failed.

### Baseline provenance audit
- PR #11 runner blob: `1bc252b197ba244ea9910ad67b4b8b3cd141138d`; manifest blob: `bbf9a2beb87b84bb51261a28268247d96419424c`.
- Frozen M6 archive SHA-256: `0b6bf15445a5dfd8cbf93450af7fd2f5fd6239d4ed082ab18b09878a94b8b164`; compressed payload SHA-256: `3dd1d7417874159c0bc625edbbc1e8cee1ae7d8a6ea42f30b4dd80ba92102748`; original `SHA256SUMS.txt` digest: `61539cb577b3c116d25739cdb8286e3de38410af1d1a39fa1418893799f3c9c9`.
- Reconfirmed: the runner verifies the compressed payload and each member against the hash embedded inside that payload. It does not load or independently verify the original `SHA256SUMS.txt`, despite manifest field `members_verified_against_original_sha256_manifest: true`. This is a provenance-verification gap, not a failed 83-case test.
- R25-R4 archive SHA-256 remains `CA01AEACB2E35C6E8039E58F15202A01399DAEA3E0A24E7B4D357772C8EF1274` (611 entries per issue #1). The Library search found related reports and checksum sidecars but not the archive bytes. No archive download was attempted under the no-download constraint; the file-by-file comparison remains NOT RUN. Issue #9 stays OPEN.
- PR #11 still has the five baseline files only on its feature branch. The 83-case baseline is not integrated into default.

### Milestone 7B proposal audit (no implementation)
- PR #5 remains an old, unaccepted candidate. Its 7B compiler blob is `e884d5223bad5e8fdbb048c5414bc547c4d22ada`; its test blob is `0c0bdbf2b8ec23b1445329b86d9d94b8653e7aed`.
- The four short-circuit side-effect tests use literal left operands (`false &&`, `true ||`, `true &&`, `false ||`). Add runtime tests with Boolean variables on the left for both skip and evaluate paths of AND and OR.
- The implementation emits runtime conditional branches for logical expressions. The `Get-ConstantValue` pass visits a dynamic-left RHS for compile-time constant-arithmetic validation; this is not proof that the runtime evaluates the RHS and no runtime short-circuit defect was reproduced.
- Function parameters are implicitly Integer and function return expressions are explicitly required to be Integer. Boolean arguments/returns should remain rejected while the ABI is integer-only, but the current suite lacks dedicated negative cases for those two contracts.
- The existing nested loop test covers two loop levels. Add a three-level case that proves innermost break/continue do not corrupt parent-loop targets.
- Existing machine checks search for `0F 84`, `0F 85`, `E9`, and `C3` byte patterns; they do not decode rel32 displacements or verify branch destinations/instruction boundaries.
- Minimal proposed test expansion: four dynamic-variable-left short-circuit runtime cases, two Boolean function ABI rejection cases, and one deeper nested-loop runtime case. This would raise the candidate suite from 32 to 39 (20 positive, 15 negative, 4 strengthened machine checks). Require 83 + 23 + 39 = 145 result records on one exact Windows commit before acceptance. This is a proposal only, not an accepted milestone or a test result.
- Do not use PR #5 as a direct implementation base without reconciling its 49-commit divergence. A fresh isolated branch is required after the baseline dependency and explicit implementation authorization.

### Native SharnouDevAgent state
- PR #7 run [44758761226](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44758761226) built a genuine AMD64 PE32+ utility with SHA-256 `9F128ED96972858B13C763B4324813B3D6A1970737F2403C10C70717CE947341`; artifact ZIP ID `14654214120`. The utility process exited 0 and correctly propagated child exit code 7.
- This is a Stage 0 bootstrap-generated native test orchestrator, not a Sharnou-compiled self-hosted compiler or AI source-generating agent.
- No native `SharnouCompiler.exe`, local model inference, autonomous source generation, persistent worker, checkpoint/recovery, Windows-host deployment, or restart proof exists in the verified evidence.
- PR #7 uses a free-form command string with `CreateProcessA` and indefinite wait. No reviewed executable allowlist, typed argument boundary, workspace sandbox, timeout/cancellation, Job Object process-tree containment, or output limit is present. Do not pass model-generated commands to it.

### Evidence classification and work performed
- WINDOWS CI PASS: runs 45340141791, 44700641397, 44700641419, 45004395351, 45004395353, 44693097619, 44758761226, and 45286151951 as described above.
- USER-REPORTED WINDOWS PASS: historical M1-M6 acceptance remains user-reported; no new local execution is claimed.
- REPOSITORY PRESENT / STATIC REVIEWED: current compiler, verifier, 7A tests, baseline runner/manifest, 7B candidate, DevAgent architecture and PR diffs.
- NOT RUN: assistant-side Windows execution, R25-R4 byte comparison, user-local M7A run, ABI runtime sentinels/stack-probe/unwind tests, native self-hosted compiler, and autonomous-agent restart/deployment tests.
- BLOCKED: baseline PR integration/provenance and the outstanding Windows x64 ABI gate in issue #1.
- No compiler, verifier, test, fixture, build script, runtime, Engine, IDE, or game source changed. No workflow was dispatched. No PR was created, edited, merged, or rebased.
- Only this status record is being appended to `Docs/AI-SESSION-STATE.md`; issue #8 is updated separately. The issue register and accepted development plan remain unchanged because no blocker status or accepted scope changed.

### Next bounded task
Normal human review of PR #11 remains the integration decision; do not auto-merge. Complete the R25-R4 comparison only when the archive bytes are supplied through an approved accessible source, and retain issue #1 ABI gates. After the baseline dependency is accepted and the user explicitly authorizes implementation, start a fresh isolated 7B branch with the proposed 39-case coverage and same-commit 145-case Windows gate. DevAgent process-broker security work must precede model-controlled execution.


## Manual DevAgent audit - 2026-11-25 16:45 Africa/Cairo

- Repository: `Sharnou/Sharnou-Compiler`; branch: `Sharnou-Compiler`; starting HEAD: `2dfceaa72b609fd3b8f839605ee5582e7b686151`.
- Read the current `AGENTS.md`, `AI_START_HERE.md`, `README.md`, all six files in `Docs/`, the current open issue set, and the relevant PR #7 / PR #13 context before acting.
- Default-branch source audit: no `DevAgent/` source tree, no `Examples/DevAgent.sharnou`, no `Tests/Test-DevAgent.ps1`, and no `sh_dev_run_process` / `CreateProcessA` DevAgent intrinsic exists on the default branch. The only native DevAgent source reviewed is on stale, open, draft PR #7.
- PR #7 is `automation/sharnou-dev-agent-native`, head `ac3849800412b1208acb540ef090ffb3ac0455ca`; compare to current default is DIVERGED, 9 commits ahead / 50 behind, 9 changed files, and GitHub reports it not mergeable. It must not be treated as the current implementation or merged as-is.
- PR #7 security defects confirmed in its source: `sh_dev_run_process(String)` passes a free-form command line to `CreateProcessA`; the caller can choose the executable and arguments; standard handles are inherited; the wait uses `WaitForSingleObject(INFINITE)`; there is no executable registry/hash allowlist, argument schema, workspace-root confinement, bounded output capture, timeout/cancellation, Job Object process-tree containment, or restricted execution boundary. Do not pass model-generated text to this function and do not rerun this prototype before replacing that interface.
- The only recorded native DevAgent run is Windows Actions run [44758761226](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44758761226), job `136467612083`, on the stale PR #7 head. It succeeded at building and launching a 2,556-byte artifact; the utility propagated child exit code 7, ran the Stage 7A suite twice (23/23 each time), reported its own exit code 0, and uploaded artifact `14654214120`. Its actual response contains `Self-hosted native SharnouCompiler.exe: NOT YET IMPLEMENTED` and `SharnouDevAgent result: PASS`. That PASS means only that the fixed regression-orchestration demonstration completed; it is not an AI-generated diagnosis, source patch, autonomous repair, local inference result, or self-hosting result.
- Issue #14 remains an architecture/implementation request, not an implementation: local inference, planner, durable evidence/task memory, agent profiles, autonomous patch/rollback, and restart recovery are not present. Issue #12 remains a proposal for read-only PE/DLL/shader analysis; no analyzer implementation was found on default.
- Blocking prerequisites remain unchanged: issue #9 / PR #11 still holds the 83-case baseline outside default and requires human review plus the outstanding provenance comparison; issue #1 remains open for large-frame stack probing, PE `.pdata`/`.xdata` unwind metadata, runtime nonvolatile-register/RSP/argument probes, and checked generic API-call marshalling. The DevAgent architecture explicitly requires these preconditions before model-controlled process execution.
- No safe DevAgent implementation was available to execute on the default branch. The old PR #7 workflow was not rerun because doing so would execute its unbounded free-form process runner. No compiler, test, workflow, runtime, or Engine source was modified; no process was launched; no workflow was dispatched; no PR was edited, rebased, or merged.
- Evidence classification: **REPOSITORY PRESENT / STATIC REVIEWED** for the current docs, issue/PR state, and PR #7 source; **WINDOWS CI PASS** for historical run 44758761226 on PR #7 only; **NOT RUN** for any current-default DevAgent, local model, source generation, autonomous repair, timeout/cancellation, sandbox, restart recovery, or PE reverse-engineering execution; **BLOCKED** for safe implementation pending issue #9 and issue #1 gates.
- Next bounded dependency: complete normal human review/integration and provenance work for the frozen baseline, close the ABI gates with Windows runtime evidence, then start a fresh feature branch for the typed, allowlisted process broker and its adversarial tests. Only after those gates should research/knowledge, local inference, planning/subagents, bounded repair, and the optional reverse-engineering/provider phases proceed.


### Automatic documentation-push CI follow-up - 2026-11-25

- The two status-document commits above automatically triggered the existing default-branch Stage 7A workflow; this was not a manual workflow dispatch and did not run DevAgent.
- [Run 45638617425](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45638617425), exact commit `fe368f37eb4204f8eb568f933a9c684a3b22e5f3`: Windows job succeeded; ASCII/no-BOM PASS; Stage 7A 23 passed, 0 failed, 23 total.
- [Run 45638680338](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45638680338), exact commit `6899a086bb9b212a7a1e714d1e8fba375ae28fb6`: Windows job succeeded; ASCII/no-BOM PASS; Stage 7A 23 passed, 0 failed, 23 total; job exit was successful.
- These were documentation-only follow-up runs. They do not rerun PR #7, do not build or launch SharnouDevAgent, and do not close issue #1, #9, #12, or #14. The historical DevAgent response remains the output recorded under run 44758761226.


## DevAgent reverse-engineering capability request - 2026-11-25 18:26 Africa/Cairo

- User requested a Windows Binary Reverse Engineer capability for SharnouDevAgent covering core modules `KERNEL32.dll`, `USER32.dll`, `GDI32.dll`, `D3D11.dll`, and `DXGI.dll`; optional graphics/text modules `D2D1.dll`, `DWrite.dll`, and `DWMAPI.dll`; system integration modules `SHELL32.dll`, `ADVAPI32.dll`, and `OLE32.dll`; and optional/legacy developer modules `D3D11SDKLayers.dll`, `D3DCompiler_47.dll`, and `D3DCompiler_43.dll`. The user also requires an extensible catalog for additional Windows DLLs required by future compiler/Engine features.
- Read the current `AGENTS.md`, `AI_START_HERE.md`, `Docs/AI-SESSION-STATE.md`, `Docs/AI-DEVELOPMENT-PLAN.md`, `Docs/AI-ISSUE-REGISTER.md`, `README.md`, current compiler and PE verifier, Stage 7A tests, and current issues/PRs/commit evidence.
- Starting default-branch HEAD: `4a1b98cafaf499e5f9046fd56b647c0649602b1b` on `Sharnou-Compiler`. No workflow run is attached to this status-only commit.
- The request maps to existing open issue [#12 - Windows Binary Reverse Engineer capability](https://github.com/Sharnou/Sharnou-Compiler/issues/12), which already specifies read-only PE/COFF inspection, the same Windows DLL families, the D3DCompiler entry points `D3DCompile`, `D3DCompileFromFile`, `D3DDisassemble`, and `D3DCreateBlob`, System32-only allowlisted capability probes, and optional D3D11 debug-layer fallback. The additional owner requirement is that the DLL catalog be data-driven and extensible; new DLLs require an explicit role, required/optional/legacy classification, architecture/OS availability evidence, reviewed export allowlist, ABI signature metadata, and provenance before activation.
- Current default branch still contains no DevAgent source, PE/DLL analyzer, DLL catalog, D3DCompiler/DXBC bridge, or System32 runtime probe. Draft PR #7 remains stale/unmerged and is a fixed test orchestrator only; its free-form `CreateProcessA` runner has no executable allowlist, structured argument boundary, timeout, cancellation, Job Object containment, sandbox boundary, or bounded output. It must not receive model-generated commands.
- The repository has no implemented local inference runtime or source-generating DevAgent. A reverse-engineering analyzer would initially be a deterministic read-only specialist tool, not autonomous reasoning or a self-improving AI model.
- The implementation gates remain open: issue #9 (frozen 83-case baseline not integrated into default and provenance comparison pending) and issue #1 (large-frame stack probing, PE unwind metadata, runtime nonvolatile-register/RSP/argument probes, and generic checked API-call marshalling). The issue #12 comment and the issue #14 architecture require these prerequisites before implementation/integration; no source change was made to bypass them.
- Technical design verified against current Microsoft documentation: use `LoadLibraryExW` with `LOAD_LIBRARY_SEARCH_SYSTEM32` and verify the resolved module path before any known export probe; use `GetProcAddress` only for a fixed reviewed export allowlist. `D3DCompile` and `D3DCompileFromFile` compile HLSL; `D3DDisassemble` disassembles compiled HLSL shader bytecode, not native PE machine code; `D3DCreateBlob` creates an `ID3DBlob`. `D3D11SDKLayers.dll` is optional; requesting `D3D11_CREATE_DEVICE_DEBUG` without the required debug layer causes device creation to fail, so normal non-debug creation must remain the fallback.
- Safe first implementation after the gates: static PE parser and bounded AMD64 decoder; DLL import/export/forwarder/ordinal and metadata catalog; System32-only allowlisted export probes; separate HLSL/DXBC tool using verified D3DCompiler runtime; COM `ID3DBlob` lifetime/size validation; tests for malformed binaries, absent/legacy DLLs, wrong architecture, export absence, HLSL diagnostics, blob lifetime, and debug-layer fallback. Never load an arbitrary analyzed DLL into the DevAgent process or execute an analyzed target by default.
- Evidence classification: REPOSITORY PRESENT / STATIC REVIEWED for the issue/architecture/source audit; NOT IMPLEMENTED / NOT RUN for the reverse-engineering capability and DevAgent runtime; BLOCKED for implementation pending issues #9 and #1. No compiler/DevAgent source, test, workflow, Engine, or IDE source changed; no process was launched and no workflow was dispatched.
- Next action: complete the existing baseline and ABI gates, then start a fresh feature branch for the read-only reverse-engineering tools and capability manifest. The stale PR #7 is not a source base.


## Manual DevAgent / Reverse Engineering Agent repair audit - 2026-11-25 19:30 Africa/Cairo

- User requested an active, high-rigor audit and repair of SharnouDevAgent and the Reverse Engineering Agent, followed by another run.
- Starting repository: `Sharnou/Sharnou-Compiler`; branch: `Sharnou-Compiler`; starting HEAD: `0c5ad2f6e13f7018ada6caf4f7f422f74ebb5203`.
- Re-read the current `AGENTS.md`, `AI_START_HERE.md`, `Docs/AI-SESSION-STATE.md`, `Docs/AI-DEVELOPMENT-PLAN.md`, `Docs/AI-ISSUE-REGISTER.md`, `README.md`, DevAgent architecture, current compiler/PE verifier and Stage 7A test references; inspected the current branch tree, issues #1/#8/#9/#12/#14, PRs #7/#11/#13, and relevant Actions evidence.
- Current default tree contains no DevAgent source directory, `Examples/DevAgent.sharnou`, `Tests/Test-DevAgent.ps1`, process-launch intrinsic, static PE analyzer, DLL catalogue, or D3DCompiler/DXBC analysis implementation. The current Stage 0 compiler has no DevAgent or `CreateProcessA` symbols. The IDE README describes the native compiler bridge, not a DevAgent implementation.
- The only native DevAgent prototype remains draft PR #7, branch `automation/sharnou-dev-agent-native`, head `ac3849800412b1208acb540ef090ffb3ac0455ca`. Against this current default HEAD, the branch is DIVERGED: 9 commits ahead / 54 behind; GitHub marks the PR not mergeable. Its 9-file change set includes an example, test harness and 150-line compiler process intrinsic; it is stale and is not a safe base for repair.
- PR #7's `sh_dev_run_process(String)` passes a caller-controlled raw command-line string to `CreateProcessA` with `lpApplicationName = NULL` and handle inheritance enabled; it waits using `WaitForSingleObject(INFINITE)`. The reviewed implementation has no executable identity/hash allowlist, structured argument schema, canonical workspace-root confinement, environment allowlist, bounded stdout/stderr, timeout/cancellation, Job Object process-tree containment, or restricted execution boundary. This is a security/robustness defect, not a suitable agent process API. Do not pass model-generated strings to it and do not rerun the stale prototype.
- Historical PR #7 Windows run [44758761226](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44758761226) validates only its fixed regression-test orchestrator: child exit-code propagation, Stage 7A tests, utility exit 0 and artifact upload. Its own output says `Self-hosted native SharnouCompiler.exe: NOT YET IMPLEMENTED`. It provides no evidence of AI reasoning, source generation, autonomous repair, reverse engineering, durable task recovery, or a safe process broker.
- The Reverse Engineering Agent is also not implemented on the current default branch. Existing issue #12 is a proposal and acceptance specification only: read-only PE/COFF parsing, bounded AMD64 decoding, imports/exports/relocations/unwind/resources, data-driven DLL catalogue, optional D3DCompiler HLSL/DXBC operations, and System32-only allowlisted API probes. PR #13 is documentation-only; it adds no analyzer or agent source.
- Blocking prerequisites remain open: issue #9 (frozen M1-M6 83-case baseline not integrated into default and R25-R4 provenance comparison not completed) and issue #1 (stack probing, PE unwind metadata, runtime nonvolatile-register/RSP/argument probes, and generic checked higher-arity API-call marshalling). These gates must not be bypassed before model-controlled compiler/process execution.
- Evidence: latest default Stage 7A Windows run [45638680338](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45638680338) passed 23/23 on documentation-only commit `6899a086bb9b212a7a1e714d1e8fba375ae28fb6`; it did not run either agent. PR #7 run [44758761226](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/44758761226) is historical orchestrator-only evidence on the stale PR branch. No new agent process, analyzer, executable, workflow or Windows runtime test was run in this session.
- Disposition: REPOSITORY PRESENT / STATIC REVIEWED for the current compiler/repository/PR audit; WINDOWS CI PASS only for the historical Stage 7A and orchestrator runs described above; NOT IMPLEMENTED / NOT RUN for the current DevAgent and Reverse Engineering Agent; BLOCKED for safe model-controlled execution by issues #1 and #9.
- No compiler, verifier, agent, Engine, IDE, example, fixture, test, or workflow source was changed. No PR was rebased, merged or edited; no workflow was dispatched; no external compiler/toolchain was used.
- Next dependency-ordered work: (1) complete normal human review/integration and provenance work for the frozen baseline; (2) close the ABI runtime gates; (3) build and adversarially test a typed, allowlisted process broker with workspace confinement, bounded output, timeout/cancellation, Job Object containment and rollback; (4) implement the read-only PE/DLL/export/relocation/unwind analyzer and separate D3DCompiler shader adapter; (5) integrate local inference/planning and bounded source repair only after the tool and recovery/security gates pass. Keep issues #12 and #14 open.
 
## Milestone 7A local regression repair - 2026-11-25

### User-provided Windows validation log

The uploaded `Pasted text(7).txt` is an execution log, not the source package. It reports:

- Engine foundation preflight: 5/5.
- Milestone 7A example build: 22/22.
- Example runtime: 15/15.
- Stage 2: 25/25.
- Stage 4: 20/20.
- PE verifier: 4/4.
- Stage 5: 24/25. The only failure is the absent imported module `Tests\\StdLib\\Collections.sharnou`.
- Stage 6: 9/9.
- Stage 7A: 27/28. The failing `BranchConditionCodes` case expected 13 output lines but received the first 6.

### Repair PR #15

PR [#15 - Repair Stage 5 collection imports and add full Stage 7A branch regression](https://github.com/Sharnou/Sharnou-Compiler/pull/15) is based on default HEAD `f80dae6fc6efccce84bc733a7529664085b3250e` and remains OPEN / UNMERGED.

Changes:
- Restores canonical `StdLib/Collections.sharnou` from the pinned M1-M6 payload. Its original member SHA-256 is `46140cdd516f2d96fb93675af1bbacab79db4daf5e711881103ee27b2cd730e3`.
- Adds `Tests/StdLib/Collections.sharnou` as a compatibility import shim to the canonical module.
- Adds two native compile / PE-verify / runtime tests for the canonical and legacy import paths.
- Adds `Examples/ControlFlow/BranchConditionCodes.sharnou` with all six comparison operators, true/false paths, variable operands and INT32_MIN/INT32_MAX boundaries. Its expected 13-line output matches the output expected by the uploaded log.
- Integrates that fixture into Build.ps1, Run.ps1 and Tests/Test-Stage7A.ps1.

### Windows CI result

Windows Actions run [45696244484](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45696244484) completed SUCCESS on PR #15 head `01fd2d7b6bd6ab4d80a920449bc529fa865634e8`.

Exact job log:
- Source encoding check: PASS (ASCII / UTF-8 without BOM).
- Stage 7A: 24 passed, 0 failed, 24 total.
- The new 13-line signed branch-boundary regression: PASS.
- Canonical `StdLib` import: PASS.
- Legacy `Tests/StdLib` import: PASS.
- Stage 5 collection import tests: 2 passed, 0 failed, 2 total.
- Combined result: PASS.

The 13-line branch test passing means the current compiler implementation did not reproduce the user's truncated-output failure with an independently maintained equivalent fixture. No Stage0 compiler change is justified by the available evidence. The exact local `BranchConditionCodes.sharnou` and expanded local `Test.ps1` were not uploaded, so the original local failure is not yet conclusively reconciled against the new fixture.

The full 83-case M1-M6 baseline is still tracked separately by issue #9 / PR #11. This PR run does not claim 83/83 or the full Stage 5 25-case suite.

Classification: **WINDOWS CI PASS on PR #15; USER-REPORTED LOCAL FAILURE IDENTIFIED; EXACT LOCAL TEST SOURCE NOT AVAILABLE; DEFAULT BRANCH NOT MODIFIED; PR NOT MERGED.**

 
### Branch fixture size cross-check - 2026-11-25

- Uploaded local `BranchConditionCodes.exe`: `codeBytes=1171`, `dataBytes=57` (the user log lines 853-856); its runtime output contains only six labels.
- The PR #15 equivalent 13-output fixture: `codeBytes=3573`, `dataBytes=275`; its Windows run prints the exact 13-line expected output and passes.
- Because each output label is a distinct string constant retained in the generated data section, the much smaller local image strongly suggests the local executable did not contain the seven additional output-label constants. Leading explanation: the local fixture or expected-output list is stale/truncated, or the local fixture uses a construct not represented by the current reproducer. This size evidence does not conclusively distinguish an incomplete source file from a parser-path defect.
- Do not change signed-comparison machine code based on this log alone. Obtain the exact local `BranchConditionCodes.sharnou` to close the remaining ambiguity.


## User-local Milestone 7A Windows validation - 2026-11-25

- The user ran PR #15 source snapshot commit `de4e64e3f45bc142391886033c33a825722a6eca` on Windows from the downloaded folder `Sharnou-Compiler-de4e64e3f45bc142391886033c33a825722a6eca`. Classification: **USER-REPORTED WINDOWS PASS**.
- `Test.ps1`: Stage 7A **24 passed, 0 failed, 24 total** (9 positive runtime cases, 12 negative parser/type cases, 3 native instruction/branch checks); Stage 5 collection imports **2 passed, 0 failed, 2 total**; final **Combined result: PASS**.
- `Build.ps1`: all 9 control-flow examples built as native AMD64 PE32+ images; the repository PE verifier passed on each image. `Run.ps1`: all 9 examples returned exit code 0 and exact expected output.
- The 13-output `BranchConditionCodes` fixture passed. Canonical and legacy collection import paths both passed.
- The log also contains eight `InputObjectNotBound` parameter-binding errors after the command `Get-ChildItem -LiteralPath $PWD -Recurse -File -Filter *.ps1 | .\Test.ps1`. This is a command-composition error: `Test.ps1` has no pipeline-input parameter. The test script subsequently completed and reported PASS. Run the listing command and ` .\Test.ps1` as separate commands; do not pipe file objects into the test runner.
- The execution-policy listing showed Process=Bypass and CurrentUser=RemoteSigned; scripts ran successfully. No execution-policy blocker was observed.
- The user log does **not** run the frozen M1-M6 83-case baseline. PR #11 remains open/unmerged and issue #9 remains a separate gate. Do not describe the current 24+2 local results as an 83-case pass.
- Static re-audit of the compiler at this source snapshot reconfirms issue #1's ABI gaps: `Set-FrameSize` allows frames up to 1 MiB and yields a minimum frame above one 4 KiB page; `Emit-Prologue` subtracts the frame size without a stack probe. The PE writer/verifier still use four sections and no exception directory or `.pdata` / `.xdata` unwind records. These are **REPOSITORY PRESENT / STATIC REVIEWED**, not failures reproduced by this log, and remain open ABI work before full ABI/self-hosting acceptance. See [Microsoft x64 prolog and epilog](https://learn.microsoft.com/en-us/cpp/build/prolog-and-epilog?view=msvc-160) and [x64 exception handling](https://learn.microsoft.com/en-us/cpp/build/exception-handling-x64).
- No compiler or backend source change was justified by this log: its compiler, test, build, and run cases all passed. README and plan test inventory were corrected from eight to nine positive cases and now document the standalone test-runner invocation.

## Windows x64 stack-probe and unwind repair - 2026-11-25

- User requested repair of the remaining stack-probe and unwind defects and a full Milestone download. Work is isolated in [PR #16](https://github.com/Sharnou/Sharnou-Compiler/pull/16), branch `repair/m7a-x64-stack-probe-unwind-20261125`; current code/documentation test snapshot verified by Windows run `45705513598` at head `b1365dc17bb5aeaad74462633fadfdc29b56fa3e`.
- Implemented `Emit-StackProbe`: the function prologue establishes RBP, passes frame size in EAX, calls private leaf `__sharnou_chkstk`, then performs the single fixed `sub rsp, imm32`. The helper probes downward in 4 KiB steps and uses only volatile R10/R11 and flags; it preserves RAX, RCX/RDX/R8/R9, nonvolatile registers and RSP. The helper is a leaf and has no RUNTIME_FUNCTION record.
- Added `New-UnwindInfoBytes` and generated version-1 UNWIND_INFO for the entry routine and each Sharnou function. Records contain UWOP_ALLOC_LARGE (scaled 16-bit or 32-bit form), UWOP_SET_FPREG, and UWOP_PUSH_NONVOL RBP. Added sorted RUNTIME_FUNCTION records in `.pdata`, unwind data in `.xdata`, and the PE32+ exception directory. The linker now emits six sections: `.text`, `.rdata`, `.idata`, `.reloc`, `.pdata`, `.xdata`.
- Changed generated function epilogues to `lea rsp,[rbp+0]; pop rbp; ret`, matching the Windows x64 epilogue pattern. The PE verifier validates section layout, exception directory coverage, sorted runtime-function ranges, unwind version/flags/codes, stack frame sizes, exact prologue bytes, helper bytes and rel32 branch targets.
- Added `Tests/Test-StackProbeUnwind.ps1` and wired it into `Test.ps1`. It compiles and executes a 17,000-local multi-page main frame and a smaller user-function frame; checks both UWOP_ALLOC_LARGE encodings; verifies the generated epilogue; and confirms the PE verifier rejects a truncated exception directory and an unsupported UNWIND_INFO version.
- **WINDOWS CI PASS:** run [45705513598](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45705513598), head `b1365dc17bb5aeaad74462633fadfdc29b56fa3e`: ASCII/no-BOM PASS; Stage 7A 24/24; Stage 5 collection imports 2/2; stack-probe/unwind 6/6; Combined result PASS. The native multi-page executable logged `codeBytes=187553`, passed the PE verifier, and exited 0 with the expected output `16999` then `17000`. Both UNWIND_INFO allocation encodings were exercised.
- PR #16 remains OPEN / UNMERGED; no default-branch source merge was performed. The previous user-provided local run validated PR #15 before these ABI changes. **User-local testing of PR #16 is still pending**; the current new stack/unwind evidence is Windows CI, not a user-PC execution report.
- Issue #1 is partially resolved but remains OPEN: stack probing and PE unwind metadata now have source, verifier and Windows CI coverage. Additional ABI acceptance remains: runtime nonvolatile-register sentinels, RSP/call-site alignment and argument-value probes, and generic checked marshalling for higher-arity Windows API calls. Do not claim complete ABI acceptance.
- The frozen Milestone 1-6 83-case baseline was not run by this PR. Issue #9 / PR #11 remain separate and unmerged. Do not describe the current 24 + 2 + 6 result as 83/83.
- The PowerShell `InputObjectNotBound` messages in the user's log remain explained by piping `Get-ChildItem` FileInfo objects into parameterless `Test.ps1`; those errors are not compiler failures. Invoke `Get-ChildItem ...` and ` .\Test.ps1` as separate commands.


## DevAgent broker phase 1 - 2026-11-26

Integrated candidate PR #18 head `2ee44cef7f3d67b4ccdc26aa391a9e789197197b` is draft and unmerged. Windows CI passed on the same PR merge-ref:

- Stage 7A: 24/24.
- Stage 5 collection imports: 2/2.
- Stack-probe/unwind: 6/6.
- Runtime ABI: PASS. Tests cover nonvolatile sentinels RBX/RBP/RSI/RDI/R12-R15, live RSP alignment, 4/5/6/8 integer argument values, nested argument order, 12-argument Windows API marshalling, and file/window/thread/synchronization probes.
- Frozen M1-M6 baseline: 83/83 (Stage 2 25, Stage 4 20, PE verifier 4, Stage 5 25, Stage 6 9).
- Combined result: PASS.

Windows runs:
- Stage 7A / combined: [45724983298](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45724983298).
- Frozen baseline: [45724983299](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45724983299).

DevAgent process broker phase 1 is implemented and tested:
- `sh_dev_run_tool(Integer,Integer)` is available only with explicit `-EnableDevAgentTools`; disabled by default.
- Six fixed tool IDs; no arbitrary command, executable path, script path, argument vector, or caller-supplied working directory.
- Compiler-pinned SHA-256 tool manifest and per-script runtime SHA-256 verification. Manifest tampering is rejected before native generation; script tampering is rejected before execution.
- Absolute System32 PowerShell path, fixed workspace layout and reparse-point rejection.
- Suspended process creation, Job Object assignment before resume, kill-on-close, process/memory limits, timeout and descendant termination.
- Windows tests cover invalid IDs/timeouts, explicit opt-in, exit-code propagation, manifest tamper, script tamper, junction/reparse rejection, timeout and descendant cleanup.

Security acceptance is still incomplete. Native CNG hashing, full canonical root/ancestor validation, restricted token/AppContainer and workspace ACLs, clean environment, bounded output capture, cancellation, and durable evidence journaling remain outstanding. The broker remains opt-in for test builds only; model-generated process execution remains DISABLED. No merge or release was performed.



## Runtime ABI and DevAgent native broker - latest validated state, 2026-11-26

Integrated PR #18 head `7a15892a944c747f9563961d7c050c909dd3d3a4` is draft/open/unmerged. Windows CI passed on the PR merge ref:
- Stage 7A: 24/24.
- Stage 5 collection imports: 2/2.
- Stack probe/unwind: 6/6.
- Runtime ABI: PASS. Nonvolatile register sentinels cover RBX, RBP, RSI, RDI, R12-R15; live RSP alignment is checked before/during/after calls; argument values and nested ordering are verified for 4, 5, 6, 8, and 16 integer arguments; the 17-parameter and 17-call-argument limits reject before PE output. Higher-arity Win32 API calls are exercised.
- Frozen M1-M6 suite: 83/83 (Stage 2 25, Stage 4 20, PE verifier 4, Stage 5 25, Stage 6 9).
- Combined result: PASS.

Windows evidence:
- Stage 7A / integrated suite: [45772104864](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45772104864).
- Frozen M1-M6: [45772104661](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45772104661).

DevAgent native process broker phase 1 is implemented and Windows-tested:
- `sh_dev_run_tool(tool_id, timeout_ms)` is typed and only registered under explicit `-EnableDevAgentTools`; default compiler builds reject the capability.
- Six fixed compiler-owned test tools; no caller-controlled command string, executable/script path, argv, or working directory.
- Compiler-pinned SHA-256 tool manifest plus native Windows CNG SHA-256 verification of the selected script before `CreateProcessA`; its opened file handle is retained through child completion. Manifest tampering and script tampering fail closed.
- PowerShell resolves from the absolute System32 directory; the workspace root is derived from the broker image path (`Build\\DevAgentBroker\\DevAgentBroker.exe`), not the inherited current directory. Test runs from a foreign working directory pass.
- Checked workspace paths and opened script handles reject reparse points.
- Child process starts suspended with handle inheritance disabled, joins a Job Object before resume, and is subject to kill-on-job-close, active-process, process-memory, job-memory, and timeout limits. Timeout terminates descendants.
- Windows broker tests pass for explicit opt-in, manifest tamper, script tamper, foreign-CWD launch, reparse/junction rejection, invalid tool IDs/timeouts, exit-code propagation, timeout, and descendant termination.

Security acceptance remains incomplete; model-generated process execution is DISABLED. Remaining work: final-path/ancestor canonicalization and ADS/UNC/device-path rejection; restricted token or AppContainer with workspace-only ACLs; clean environment and explicit DLL-search policy; bounded stdout/stderr capture and STARTUPINFOEX handle isolation; cooperative cancellation; durable evidence journal and restart recovery. This is a test-tool broker foundation, not yet a production sandbox. No merge, release, or executable publication occurred.

## AppContainer and workspace-ACL security tranche - 2026-11-26

A follow-on branch `devagent-appcontainer-acl-output-20261126` is stacked on the draft phase-1 broker branch. This tranche corrects the native import-table targets for the AppContainer profile and DACL helper emitters, adds the relevant `USERENV.dll` / `ADVAPI32.dll` API names to the PE verifier allowlist, and adds static source assertions for the helper declarations and IAT mappings.

Important scope boundary:
- The AppContainer profile/SID and ACL-update helper functions are currently declarations in the compiler source. They are **not called by the live `Emit-DevRunTool` execution path**.
- `CreateRestrictedToken`, `CreateProcessAsUserA`, AppContainer process attributes, actual workspace ACL grant/revoke, and bounded stdout/stderr capture are **not yet implemented as an end-to-end runtime path** in this commit.
- No sandbox runtime or adversarial Windows test has passed for this tranche. The static assertions are not proof of runtime isolation.
- The existing process broker remains an explicit opt-in test-only capability, and model-facing process execution remains **DISABLED**.
- Do not merge the follow-on branch or mark the security target complete on this evidence.

Required next gates: wire the restricted primary token and no-capability AppContainer into suspended process creation; apply and reliably revoke least-privilege workspace DACL entries; capture combined stdout/stderr through an explicit STARTUPINFOEX handle list under a hard byte cap; terminate and confirm the entire job on timeout/overflow/failure; then add adversarial Windows tests for token identity, denied filesystem/network access, ACL rollback/restart, handle isolation, output cap, timeout and descendant termination. Clean environment/DLL-search policy and durable evidence journaling remain separate gates.

## Native AppContainer broker integration checkpoint - 2026-11-26

Active implementation branch: `devagent-sandbox-runtime-20261126`, stacked on draft PR #19. Current checkpoint source contains a live `Emit-DevRunTool` execution path for restricted-token/AppContainer startup, handle-based workspace ACLs, and bounded stdout/stderr capture. This supersedes the earlier helper-only checkpoint on PR #19.

Implemented in source (not yet Windows-runtime validated on this branch):
- Eight fixed test-tool IDs and compiler-pinned manifest SHA-256; per-script CNG verification remains in the existing phase-1 path.
- A restricted primary token created with `CreateRestrictedToken(DISABLE_MAX_PRIVILEGE)`.
- A no-capability AppContainer SID attached through `PROC_THREAD_ATTRIBUTE_SECURITY_CAPABILITIES`; before `ResumeThread`, the child primary token is queried for `TokenIsAppContainer`, `TokenHasRestrictions`, and an empty `TokenCapabilities` group list.
- `STARTUPINFOEX` uses a two-call, bounded `InitializeProcThreadAttributeList` sizing sequence and an explicit handle list containing only NUL stdin and the stdout/stderr pipe writer. The parent capture handle and output-file handle are not inherited.
- DACL updates now open the actual directory with `OPEN_REPARSE_POINT`, validate the opened directory handle, preserve unrelated DACL entries through `GetSecurityInfo` + `SetEntriesInAclA`, and apply the merged DACL through `SetSecurityInfo`.
- The source workspace root receives read/execute access for the package SID. Writable access is limited to `Build` and `Build\\DevAgentBroker`.
- The AppContainer runs at Low IL. Mandatory Integrity Control is evaluated before the DACL, so the writable Build directories also receive an inheritable Low IL mandatory label with `NO_WRITE_UP`; the source workspace root is deliberately not relabeled.
- Combined stdout/stderr is drained while the process runs. The read size is clamped to the remaining capacity so a 1 MiB + 1 byte test writes exactly 1 MiB to the captured file and then returns overflow. Output is persisted through the same exclusive, non-inherited output-file handle.
- The child is created suspended, assigned to the Job Object before resume, and termination paths wait for Job Object emptiness before returning.

Static validation performed during source review:
- 16 import descriptors.
- 66 unique imported API names.
- Per-module IAT arrays include their terminating zero thunk and do not overlap.
- Import lookup arrays do not overlap.
- All `Emit-Win64CallIat` targets map to declared imported API slots.
- The exact output-cap reader logic is asserted by the regression script.
- A static regression assertion now verifies Low IL labeling is restricted to the two writable Build directories.

Not yet demonstrated:
- No Windows Actions run has passed for this implementation branch at this checkpoint. Source presence and static layout assertions are not execution evidence.
- The 1 MiB overflow, sandbox write/deny, and token-identity probes must pass on an actual Windows runner before runtime acceptance.
- Persistent package SID and persistent package ACL grants are used. There is no per-invocation random AppContainer identity, transactional DACL rollback, or durable stale-ACL recovery journal. A broker crash can leave a package SID grant behind; treat this as a security blocker.
- The child currently receives an inherited environment block (`lpEnvironment = NULL)); environment sanitization and DLL search-order hardening remain outstanding.
- Full final-path/ancestor race elimination and executable-image provenance remain open.
- Network-denial and explicit cancellation adversarial tests remain open. No network capability SID is declared, but that alone is not a passed network-isolation test.

The branch is **IMPLEMENTATION CANDIDATE / NOT SECURITY-ACCEPTED**. PR #20 must remain draft and unmerged pending Windows CI and adversarial review. The broker remains test-build opt-in only; model-facing process execution remains **DISABLED**. No release or executable publication occurred.

## Abandoned ACL-mutex fail-closed checkpoint - 2026-11-26

Follow-on branch `devagent-abandoned-mutex-failclosed-20261126` changes the native broker's mutex wait contract:
- `WAIT_OBJECT_0` is the only status that continues into AppContainer/ACL setup.
- `WAIT_ABANDONED (0x80)` now returns `-118` (ACL recovery required), releases the owned mutex through common cleanup, and branches around AppContainer SID creation, DACL updates, and child launch.
- Timeout, WAIT_FAILED, and unexpected statuses remain fail-closed.

Reason: the prior code treated `WAIT_ABANDONED` as normal ownership. Windows documents that an abandoned mutex indicates the previous owning thread terminated without releasing it; persistent state protected by the mutex must be checked before reuse. The broker's package-SID ACL state is persistent, so continuing without a recovery journal is unsafe.

This is a **fail-closed blocker**, not recovery. Persistent AppContainer ACEs may still remain after a crash. A protected write-ahead security-descriptor journal, startup recovery, and an adversarial abandoned-mutex test remain required. Model-facing process execution remains DISABLED.


## DevAgent Phase 2B.6 - production broker integration - 2026-11-27

Status: IN PROGRESS / BLOCKED / NOT SECURITY-ACCEPTED.
Parent candidate: PR #24, branch devagent-acl-transaction-recovery-20261126, start head bd411c2fc777006f9b1160ab8d3d5992c2a15afa.

Evidence:
- M6 baseline run 45964360562: PASS, 83/83.
- Stage 7A run 45964360481: FAIL in post-crash ACL journal replay.
- Actual broker result after the parent-crash test: -2685. The native emitter encodes this as -400 - (1000 + readWin32*256 + metadataWin32), which decodes to ERROR_ACCESS_DENIED (5) for both the GENERIC_READ journal open and metadata-only fallback.
- The independent PowerShell CreateFileA control successfully opened the same journal. Therefore do not broaden the DACL or discard the journal; the native path/call-context discrepancy must be isolated first.
- The original test harness captured ACL_RECOVERY_NATIVE_PATH from the broker but did not forward it into GitHub Actions logs. A new diagnostic patch forwards that line and emits the decoded Win32 codes. This is diagnostic instrumentation only; it changes no ACL or execution policy.

Phase 2B.6 acceptance work:
1. Fix native journal recovery and run a crash-at-each-transaction-boundary matrix.
2. Replace the stable AppContainer profile identity with a unique per-execution profile/SID and journal the profile name for crash cleanup.
3. Replace CreateProcessAsUserA lpEnvironment=NULL with an explicit bounded allowlisted Unicode environment and CREATE_UNICODE_ENVIRONMENT; test inherited-secret absence and preserve Win32 203 as a regression gate.
4. Integrate the Phase 2B.5 explicit handle allowlist into the actual native emitter with separate stdout/stderr pipes, bounded concurrent drain, and whole-job termination.
5. Harden the child loader policy; a parent-only SetDefaultDllDirectories call is not accepted as child hardening.
6. Preserve exact opened-object/final-path checks and validate the actual generated PE import table for every native import addition.
7. Pass same-head native ABI, M6 baseline, Stage 7A, AppContainer, ACL crash/recovery, environment, output, loader and cleanup tests.

The existing PR #24 candidate contains real native AppContainer/ACL/job/pipe/journal emitter code but is not production-accepted while crash recovery fails. No model-facing or autonomous execution permission is enabled.


## Phase 2B.8 implementation start - 2026-11-27

### Reconciliation

- Current PR #24 exact head: `6344632746cd0666025a0beb0d31f4752d6480f6` on `devagent-acl-transaction-recovery-20261126`.
- Exact-head Windows run [46003358917](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46003358917) passed Stage 7A 24/24, Runtime ABI, native broker phase-1, targeted crash recovery, exact DACL/mandatory-label restoration, host/child integrity separation, malformed-journal rejection, abandoned-journal recovery and combined result. Companion run [46003358930](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46003358930) passed the M1-M6 baseline 83/83.
- PR #24 remains a large diverged candidate and was not changed, merged or rebased. Phase 2B.7 does not have a separately recorded/accepted complete lifecycle implementation in the reviewed candidate docs; do not mark it complete by inference. PR #24 is treated as the Phase 2B.6 broker/journal integration parent.

### Code-bearing Phase 2B.8 increment

- Isolated stacked branch: `phase-2b8-identity-profile-qualification-20261127`, based exactly on PR #24 head above.
- Draft implementation PR #28 targets PR #24's branch; it is separate from PR #24 and the Phase 2B.8 specification PR #26.
- Added `Tests/Test-DevAgentExecutionIdentity.ps1` and integrated it into root `Test.ps1`.
- The fixture calls CNG `BCryptGenRandom` using the system-preferred RNG, creates uniquely named zero-capability AppContainer profiles, checks SID/name derivation, rejects pre-existing profile adoption, and verifies deletion by successful recreation followed by deletion.
- Added `Docs/PHASE-2B8-CRASH-SAFE-EXECUTION-LIFECYCLE.md` and `Docs/PHASE-2B8-IMPLEMENTATION-LOG.md` to the stacked branch.

### Evidence and limitations

- The new identity fixture is NOT YET WINDOWS-CI-VERIFIED; no assistant-executed Windows test is available in this session. Do not call the increment passed until an exact-head Windows run reports the fixture results.
- This is a test-only API qualification increment. The compiler-emitted broker still uses the stable profile identity; no production broker code, journal format, process launch behavior, or generated executable was changed.
- Before profile name metadata is consumed during restart recovery, design and validate an authenticated journal/key boundary. Do not add unauthenticated profile names to a journal and use them for profile deletion.
- Clean Unicode environment, separate stdout/stderr, child DLL policy, comprehensive crash cut-points and concurrency acceptance remain open.
- Model-facing process execution remains DISABLED. Phase 2B.8 remains NOT SECURITY ACCEPTED.


## Phase 2B.8 Windows evidence update - 2026-11-27

Code-bearing commit: `907281187ffdf9223d4b345a2847c2a1feb883cf`.

- Dedicated Windows run [46021589016](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46021589016): **PASS**. Eight unique CNG-generated AppContainer profile identities/SIDs; eight real suspended child-token inspections (AppContainer=1, expected package SID, Low integrity RID 0x1000, zero capabilities); eight profile delete/recreate/delete verifications. DPAPI user-scope journal-envelope round-trip/tamper/wrong-entropy/cleartext tests pass. Strict v2 fixture parser accepted canonical schema and rejected unsupported version, truncation, trailing byte, profile length overflow and missing workspace identity.
- Frozen M1-M6 baseline [46021589107](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46021589107): **PASS 83/83**.
- Stage 7A/combined run [46021589123](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46021589123): encoding gate PASS; full run still in progress at this note. Earlier exact baseline revision bfb7f573... passed Stage7A combined run 46020834321.
- Identity child-token fixture uses inherited environment while suspended and never resumed; clean Unicode environment is NOT qualified. Attempts to create a custom block hit Win32 203 and were removed from the token test rather than silently treating them as a pass.
- DPAPI user-scope envelope is NOT a trusted writer identity when other same-user processes are in the threat model. The new `Docs/PHASE-2B8-JOURNAL-TRUST-BOUNDARY.md` requires an independently protected writer-authentication trust anchor before native profile metadata is persisted/used for cleanup.
- No production compiler-emitted broker/journal code has changed. Production still uses stable AppContainer profile and v1 ACL journal. Phase 2B.8 remains NOT SECURITY ACCEPTED.
- Model-facing/autonomous process execution remains DISABLED.


### Latest exact-head journal threat-boundary test - 2026-11-27

Dedicated Windows run [46022134602](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46022134602) passed on code commit `a64b81def96b22315b8ab8034bb60c4af1870e32`. The v2 parser now also rejects empty execution ID, malformed SID, descriptor count/length mismatch and unsupported security policy version. A same-user re-protection demonstration passes and confirms that the same-user process can create a different valid DPAPI envelope with the same public optional entropy. This confirms DPAPI is not writer-process authentication. The trust-boundary design gate remains unresolved until a separate service/key identity is approved.


### Phase 2B.8 schema precision update

The journal-v2 test schema was corrected to use Windows `FILE_ID_INFO`: 64-bit volume serial plus the complete 128-bit `FILE_ID_128`. The DPAPI writer-boundary negative/positive characterization now uses a separate PowerShell process running as the same Windows user, rather than protecting the forged record inside the same process. Awaiting exact-head Windows CI before claiming these two latest refinements pass.


### 2026-11-27 exact Windows verification: FILE_ID_INFO + separate-process DPAPI

- Dedicated Windows workflow [46024410650](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46024410650) passed on code commit `fc479378a818bc759f298361c6a298e6c143118e`. It verified eight actual suspended child tokens per generated AppContainer profile (exact SID, AppContainer flag, Low IL 0x1000, zero capabilities), normal profile deletion, strict v2 negatives, 128-bit FILE_ID_INFO workspace identity, and a separate same-user PowerShell process successfully creating a DPAPI envelope that the parent unprotected.
- M1-M6 baseline [46024435843](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46024435843) passed 83/83 on latest workflow head `cb0551dd1d272deb3c12aab9b5131cc3fb6ed2fb`.
- Full combined Stage 7A run [46024435792](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46024435792) was in progress at last inspection. It includes the new sandbox-child DPAPI mint/decrypt characterization. This result is not yet claimed.


### Explicit environment builder primitive - 2026-11-27

- Added `Tests/Test-DevAgentEnvironmentBlock.ps1` to the combined suite and dedicated Windows workflow.
- Run [46025925905](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46025925905) completed **SUCCESS** on `6277f28123b28b56e2710f50d7197239fd034529`: non-NULL Unicode block, 9 entries / 354 UTF-16 code units, SystemRoot/windir/SystemDrive/PATH present, validated hidden drive-current-directory entries preserved, ordinary parent vars discarded, unique parent secret absent.
- Run [46025925771](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46025925771) passed frozen M1-M6 baseline 83/83 on the same commit.
- Limitation: test uses ordinary `CreateProcessW`, not the broker's `CreateProcessAsUserW` + AppContainer security-capability launch. No production broker environment change is made; `lpEnvironment=NULL` remains in the emitted candidate and Win32 203 remains a blocker to integrate until AppContainer-specific proof passes.

## Writer authority and environment qualification update - 2026-11-27

- Added Docs/PHASE-2B8-WRITER-AUTHORITY-SERVICE-DESIGN.md: recommended design is a dedicated Windows service SID owning its non-exportable key and the entire journal/ACL/profile transaction. A generic "sign arbitrary bytes" service is explicitly prohibited. Service installation/upgrade/key-loss recovery is an owner deployment decision; no service has been implemented.
- Added Tests/Test-DevAgentEnvironmentBlock.ps1. Dedicated Windows run 46025925905 passed a bounded 9-entry/354-WCHAR Unicode environment and CreateProcessW launch; required Windows values were correct and a parent secret was absent. This does not qualify the emitted broker's CreateProcessAsUserW AppContainer path.
- Latest combined Stage 7A run 46025926233 includes the built-in SecureString AppContainer DPAPI probe; final job/log result had not yet been inspected when this record was appended.
- Production broker remains unchanged: stable profile identity, v1 journal, lpEnvironment=NULL, merged stdout/stderr. Model-facing execution remains disabled.
