# AI Issue Register - Sharnou Compiler

**Last reviewed:** 2026-11-20  
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
