# AI Session State - Sharnou Compiler

**Last updated:** 2026-11-20  
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
- This session adds `AI_START_HERE.md`, `Docs/AI-DEVELOPMENT-PLAN.md`, `Docs/AI-SESSION-STATE.md`, `Docs/AI-ISSUE-REGISTER.md`, README links, and tracking issues #8, #9, and #10. It does not modify compiler source.
- Future sessions must read the source-of-truth files before any code generation or repair, then update `Docs/AI-SESSION-STATE.md` and issue #8 with the new result.
- Next: capture M7A Windows acceptance and reconcile/restore the exact 83-case baseline before starting 7B self-hosting source generation.
