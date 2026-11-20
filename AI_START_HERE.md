# AI Start Here: Mandatory Sharnou Compiler Project Context

**Purpose:** This file is the mandatory entry point for every future AI-assisted source generation, compiler change, bug investigation, repair, test update, and planning session in this repository.

## Mandatory preflight before doing work

Before generating or modifying any source code, tests, build scripts, linker logic, compiler logic, or issue repair, read these files from the current repository branch:

1. `AI_START_HERE.md` (this file).
2. `Docs/AI-SESSION-STATE.md` (latest known status, blockers, and next action).
3. `Docs/AI-DEVELOPMENT-PLAN.md` (accepted plan and milestone map).
4. `Docs/AI-ISSUE-REGISTER.md` (open defects, risks, and unresolved decisions).
5. `README.md` (current branch instructions and supported language behavior).
6. The exact source files, fixtures, and test runners relevant to the requested change.
7. `Docs/Renderer-Roadmap-3D-MMORPG.md` before any renderer, graphics, asset, or Engine rendering work.

Also inspect the current branch, latest commit, relevant open issues, open pull requests, and latest CI/test evidence before changing files. Record the starting commit SHA in the session update.

**Do not use an old chat summary, an earlier generated ZIP, or an assumed milestone state as a substitute for reading the current repository files.** If a required file or test source is missing, report that fact and stop treating the missing test as passed. Do not silently recreate a supposedly frozen baseline.

## Project identity and non-negotiable boundaries

- Repository: `Sharnou/Sharnou-Compiler`.
- Current default branch at the time this protocol was added: `Sharnou-Compiler`.
- Product: a self-contained Sharnou language, compiler, PE linker, runtime/standard library, Engine, IDE, and ultimately Honour War.
- Native target: AMD64 / x64 Windows PE32+.
- Initial graphics backend: Win32 + DXGI + Direct3D 11.
- Bootstrap currently uses Windows PowerShell/.NET and emits PE32+ images itself.
- Sharnou must own its language frontend, native x64 backend, PE linker, runtime contracts, standard library, and Engine integration.
- Never introduce MSVC, Clang, Visual Studio, MSBuild, an external assembler, an external linker, or a substitute compiler.
- Do not assume an external SDK/toolchain exists on the user's PC. Prefer declared Windows system APIs and fail-closed capability checks.
- Do not download/install dependencies or invent compiler APIs, ABI behavior, import libraries, CRT support, or generated executable results.
- Preserve the Windows x64 calling convention, stack alignment, shadow space, register preservation, import-table correctness, relocation correctness, and existing accepted regression baselines.
- Source, scripts, tests, and generated text artifacts must be plain ASCII / UTF-8 without BOM unless a specific file format requires otherwise.
- Keep the accepted runtime asset policy: glTF/GLB for 3D scenes and geometry; KTX2 with Basis Universal / `KHR_texture_basisu` for 3D material textures; AVIF for 2D/UI imagery. Do not conflate these formats.

## Evidence and status rules

Every status must be labelled as one of:

- **USER-REPORTED WINDOWS PASS** - the user reports the exact test passed on their PC; preserve the report, but do not imply independent execution by the assistant.
- **REPOSITORY PRESENT / STATIC REVIEWED** - files or source logic were inspected, but the native executable was not run.
- **WINDOWS CI PASS** - a recorded Windows CI run passed, with run URL/commit and test totals.
- **NOT RUN** - no execution evidence exists.
- **BLOCKED** - a missing fixture, dependency, ABI guarantee, failed test, or unresolved design decision prevents acceptance.

Never convert a static inspection into a native runtime PASS. Never claim a build, window, rendering operation, or screenshot occurred without execution evidence. Report exact expected and actual outputs, exit codes, test counts, and SHA-256 values when available.

## Required workflow for every future AI work session

### Start
1. Read all mandatory preflight files above.
2. Inspect repository branch/head and current working state.
3. Read the latest issue and PR context related to the task.
4. Reconcile the requested change with accepted milestones and frozen tests.
5. List the intended files to change, files that must remain unchanged, dependencies, risks, and acceptance tests.
6. Identify whether the task is implementation, diagnosis, test repair, or planning. Do not begin broad code generation before the source-of-truth review is complete.

### During work
1. Make the smallest change that fixes the root cause or implements the accepted scope.
2. Preserve unrelated code and frozen baseline files byte-for-byte where required.
3. Add positive and negative tests for new behavior.
4. Keep compiler diagnostics source-located and fail closed on unsupported syntax, invalid ABI/API use, malformed PE structures, or missing required components.
5. Use the repository's own tools and Windows APIs; do not insert external toolchain dependencies.

### Finish and persist
1. Record what was generated or repaired and the exact repository paths changed.
2. Record the starting and resulting commit SHAs or PR/branch reference.
3. Record tests run, exact totals, pass/fail/skip counts, and whether execution was on Windows, CI, or static-only.
4. Record executable/compiler hashes and runtime output where relevant.
5. Update `Docs/AI-SESSION-STATE.md` with the newest status and next action.
6. Update `Docs/AI-DEVELOPMENT-PLAN.md` only when an accepted milestone, dependency, scope, or completion status changes.
7. Update `Docs/AI-ISSUE-REGISTER.md`; create or update a GitHub issue for each actionable blocker. Link the issue from the state file.
8. Update the dedicated AI status issue in GitHub with the latest session summary. Its issue number is recorded in `Docs/AI-SESSION-STATE.md`.
9. Update README links or test instructions when the user-facing workflow changes.
10. Do not report acceptance until the stated acceptance gates genuinely pass.

## Current focus

The immediate accepted engineering task is **Milestone 7A: native control flow** - `if/else`, `while`, signed integer comparisons, correct x64 branch fixups, and preservation of the existing Windows x64 ABI and stack-frame layout. Its detailed status and the repository test-source discrepancy are recorded in `Docs/AI-SESSION-STATE.md`.

The long-term renderer direction is recorded in `Docs/Renderer-Roadmap-3D-MMORPG.md`. Do not start the self-hosted compiler implementation until the control-flow stage and its required regression baseline are validated.

## Automation boundary

This document establishes a durable, repository-hosted protocol. A future AI session must actively fetch and read these files through the connected repository tools before work. The current GitHub integration can read/write repository files and issues, but it does not expose GitHub Projects V2 board operations or autonomously observe an AI generation outside a tool session. Therefore the roadmap is stored as versioned Markdown, actionable blockers are tracked as GitHub Issues, and the AI status issue/file must be updated during each completed session. Do not claim background monitoring or automatic updates while no session or workflow is running.
