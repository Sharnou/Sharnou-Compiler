# Sharnou Compiler: Development Automation and Production Gates

Status: Active engineering control plan
Applies to: Sharnou/Sharnou-Compiler
Platform baseline: Windows x64, PowerShell 5.1 bootstrap, AMD64 PE32+
Policy: Sharnou-owned compiler, assembler/code generator, PE writer and verifier; no external compiler, assembler or linker

This document defines the automation that advances the compiler and the evidence required before it can be called self-hosting or production-capable. It supplements, and does not replace, Docs/Compiler-Roadmap.md.

## 1. Verified starting point

The roadmap must distinguish source that exists from capabilities proven by tests.

| Item | Repository status | Evidence boundary |
|---|---|---|
| Stage 0 bootstrap | Present on the default branch | Stage0/SharnouCompiler.ps1 is PowerShell/.NET and emits AMD64 PE32+ output. |
| Milestone 7A | Merged and verified | The checked-in Windows suite contains 8 native runtime positives, 12 negative cases and 3 instruction checks: 23 cases total. |
| Historical Milestone 6 regression baseline | Incomplete in the repository | The previously reported 83-case test harness and fixtures are not present in the current tree. Restore them before claiming continuous 83/83 regression coverage. |
| Native SharnouCompiler.exe | Not implemented | No checked-in Sharnou-written compiler or Stage 0 -> Stage 1 -> Stage 2 bootstrap proof exists. |
| Production release pipeline | Planned | A native self-hosted compiler package, reproducible bootstrap proof and rollback evidence are still required. |

The open compiler roadmap PR is the current documentation branch for the compiler stack plan. Do not overwrite its existing work or merge it automatically.

## 2. Two coordinated automation layers

### GitHub Actions: deterministic validation

GitHub Actions is the authoritative source for repeatable test outcomes. The Windows workflow validates the currently implemented compiler; its daily schedule and manual dispatch make regressions detectable even when no pull request is active.

As the compiler gains capabilities, extend the same CI contract with separate named suites:

1. Source encoding, repository policy and frozen bootstrap identity.
2. Historical Milestone 2-6 regression corpus and Milestone 7A onward.
3. Lexer, parser, semantic analysis and diagnostic tests.
4. Typed IR construction and verifier tests.
5. x64 instruction encoding, ABI, stack alignment and calling-convention tests.
6. PE32+ writer, import table, relocations, unwind metadata and independent verifier tests.
7. Windows loader execution tests for generated native programs.
8. Bootstrap fixed-point tests once the Sharnou-written compiler exists.
9. Package manifest, SHA-256, clean-checkout bootstrap and rollback tests.

A test lane must be reported as blocked or unavailable when the runner cannot provide the required capability. A source scan, mock, static PE parse or skipped test must never be reported as a native runtime pass.

### Background development automation: bounded GitHub work

The recurring development task is the engineering operator, not a substitute for CI. Each run must:

1. Read the current default branch, active PRs, milestones, open issues, latest commits and relevant workflow runs.
2. Read the current implementation and tests before choosing work; do not act from an old roadmap snapshot.
3. Select the earliest incomplete dependency gate in Docs/Compiler-Roadmap.md. Start with restoration of the historical 83-case suite, not a jump to self-hosting.
4. Implement one bounded, reviewable change on a dedicated feature branch.
5. Add positive, negative and regression tests appropriate to the change.
6. Open or update a focused pull request and save every source/documentation change in GitHub.
7. Inspect the actual GitHub Actions run, job logs and produced artifacts. Fix root causes and rerun failed gates when possible.
8. Update milestone status only from recorded repository evidence.
9. Report exact repository, branch, PR, commit SHA, changed paths, workflow run, test counts and unresolved blockers.

Do not create duplicate PRs for the same work. Continue an existing relevant feature branch/PR where possible. Prefer small, independently reviewable commits over giant roadmap-sized implementation changes.

## 3. Required safeguards

- Never merge a pull request, publish a release, delete a branch, rewrite history or change repository security settings through this automation.
- Do not write directly to a protected/default branch. Save implementation work on feature branches and expose it through PRs.
- Do not add secrets, tokens or private credentials to source, logs, issue bodies or artifacts.
- Do not install or download MSVC, Clang, Visual Studio, MSBuild, an external assembler, an external linker or another compiler.
- Do not treat Windows SDK development packages or a third-party build system as an approved compiler substitute.
- Keep the Stage 0 bootstrap and PE verifier independently identifiable by immutable commit/blob hashes.
- Never commit generated EXE, object, library, cache or temporary build files as source.
- Fail closed on unsupported syntax, ABI, PE features, imports, relocations or runtime requirements.
- Do not invent test results, executables, SHA-256 values, screenshots or performance measurements.

## 4. Self-hosting implementation sequence

The detailed compiler feature plan remains in Docs/Compiler-Roadmap.md. The mandatory execution order is:

| Gate | Work package | Exit evidence |
|---|---|---|
| C0 | Restore historical 83-case tests and fixtures; consolidate the runner with Stage 7A | All 83 historical cases and all 23 Stage 7A cases run from a clean Windows checkout with exact counters and preserved logs. |
| C1 | Complete control-flow semantics: booleans, short-circuit logic, break/continue, nested returns and scope rules | Positive/negative behavior tests, call/stack ABI tests and diagnostics tests. |
| C2 | Define primitive types, pointers/handles, arrays/slices, structs, enums, casts and layouts | Compiler layout reports match native runtime probes; invalid operations fail closed. |
| C3 | Introduce typed IR, explicit basic blocks and terminators, IR verifier and baseline non-optimizing x64 lowering | Every supported IR operation has lowering tests; unsupported IR is rejected. |
| C4 | Harden Windows x64 ABI, PE32+ imports/IAT, relocations, unwind metadata, stack probing and deterministic output | Independent PE verifier plus actual Windows loader execution and ABI stress tests. |
| C5 | Implement lexer, parser, AST, semantic analysis, type checking, diagnostics and IR builder in Sharnou source | Stage 0 compiles the Sharnou-written compiler modules; tests agree across bootstrap and native paths. |
| C6 | Implement native x64 instruction emission, fixups, PE writer, linker and command-line driver in Sharnou source | The native compiler creates verified, runnable PE32+ test programs without invoking the Stage 0 emitter at runtime. |
| C7 | Prove the bootstrap fixed point and publish the native compiler release | Stage 0 builds Stage 1; Stage 1 builds Stage 2; Stage 2 builds Stage 3. Each stage passes the same full suite. Reproducibility and rollback are demonstrated. |

A Stage 1 compiler that merely compiles a small demo is not self-hosting. Self-hosting requires the Sharnou-written compiler to compile its own complete source tree, rebuild itself through subsequent generations, and preserve test behavior.

## 5. Production-capable compiler definition

The compiler is production-capable for a declared Windows x64 target only when all of these are proven:

- Clean checkout can bootstrap from the pinned Stage 0 source using only the documented Windows-provided PowerShell/.NET seed.
- Native compiler frontend, semantic analysis, IR, x64 backend, PE writer and linker are Sharnou-owned implementations.
- A documented language, target, ABI, CLI, module and diagnostic contract is versioned.
- The independent PE verifier validates headers, sections, imports, IAT, relocations, unwind information and bounds.
- The Windows loader launches generated executables and test programs produce expected output and exit codes.
- The full historical and current regression suites pass at every bootstrap generation.
- Rebuilds are reproducible; all intentional normalization is documented and narrow.
- Failure paths are tested: malformed source, unsupported features, allocation failure, invalid imports, bad fixups, corrupted PE images and interrupted builds.
- A known-good compiler and bootstrap package can be restored without depending on an external compiler.
- Release artifacts include source commit, bootstrap identity, compiler SHA-256, package SHA-256, test report, target statement and rollback instructions.

Until these gates pass, label the project as Stage 0 bootstrap / pre-self-hosting. Do not call it a production compiler based only on emitted PE files or a successful single test.

## 6. Downstream stack dependency

The compiler is the foundation. The detailed IDE and Engine plans live in their own repositories:

- Sharnou IDE: https://github.com/Sharnou/Sharnou-IDE — see Docs/IDE-Roadmap.md.
- Sharnou Engine: https://github.com/Sharnou/Sharnou-Engine — see docs/PRODUCTION_ROADMAP.md.
- Full compiler, runtime and game sequence: Docs/Compiler-Roadmap.md.

The IDE and Engine must consume pinned compiler contracts and verified artifacts. Neither repository may silently substitute another compiler when the Sharnou compiler is incomplete.

## 7. Status update rule

Every roadmap status change must include the supporting GitHub PR or commit, workflow run URL/ID, exact suite totals, target runner and artifact hashes where applicable. If evidence is absent, retain Planned or Blocked.