# Agent Instructions - Sharnou Compiler

Before any source generation, code modification, bug investigation, test repair, compiler/linker/PE change, Engine work, or issue triage, read these repository documents in this order:

1. `AI_START_HERE.md`
2. `Docs/AI-SESSION-STATE.md`
3. `Docs/AI-DEVELOPMENT-PLAN.md`
4. `Docs/AI-ISSUE-REGISTER.md`
5. `README.md`
6. The exact source files and tests relevant to the requested task.

Also inspect the current branch/head, recent commits, relevant open GitHub issues/PRs, and current CI/test evidence. Do not rely on an old chat summary or generated archive in place of the repository's latest state.

At the end of every completed task, update `Docs/AI-SESSION-STATE.md` and GitHub issue #8. Update the milestone map and issue register when scope, status, or blockers change. Record changed paths, commit/PR, hashes, test totals, actual exit codes/output, and whether evidence is user-reported, static-only, or an actual Windows/CI run.

Follow every constraint and acceptance gate in `AI_START_HERE.md`. In particular, do not use MSVC, Clang, Visual Studio, MSBuild, an external assembler, an external linker, or a hidden external toolchain. Do not claim runtime success without runtime evidence.