# Sharnou Compiler and Engine - Accepted Development Plan

**Last maintained:** 2026-11-25
**Repository:** `Sharnou/Sharnou-Compiler`  
**Default branch observed:** `Sharnou-Compiler`  
**Current focus:** Milestone 7A - native control flow  
**Status source:** `Docs/AI-SESSION-STATE.md`; mandatory process: `AI_START_HERE.md`.

This is the master roadmap/map for the accepted Sharnou direction. A status marked user-reported records the user's Windows validation report, not an independent test executed by the AI.

## 1. Product objective

Build a self-contained development stack:

1. **Sharnou Language** - a purpose-built language for native engine and game development.
2. **Sharnou Compiler** - bootstrap compiler, native x64 code generator, PE32+ linker/verifier, and eventual self-hosted compiler.
3. **Sharnou Runtime and Standard Library** - memory, strings, files/assets, diagnostics/logging, collections, windowing, event processing, threading, synchronization, and graphics facilities.
4. **Sharnou Engine** - scene/world, geometry, materials, animation, rendering, asset streaming, input, and gameplay services.
5. **Sharnou IDE** - source editing, project management, build diagnostics, asset inspection, profiling, and runtime debugging workflows.
6. **Honour War** - the first complete game built using the Sharnou compiler, IDE, runtime, and Engine.

The long-term target is a high-quality, high-performance third-person 3D MMORPG/ARPG, not merely a compiler demo or a window-clearing sample. The accepted renderer architecture and detailed subsystem roadmap are in [Renderer-Roadmap-3D-MMORPG.md](Renderer-Roadmap-3D-MMORPG.md).

## 2. Non-negotiable toolchain and platform decisions

- Target: AMD64 / x64 Windows, producing native PE32+ executables.
- Bootstrap: Windows PowerShell/.NET, available on Windows; the bootstrap writes machine code and PE structures itself.
- Native compiler and linker: Sharnou-owned implementations. Do not invoke MSVC, Clang, Visual Studio, MSBuild, an external assembler, or an external linker.
- No external compiler, assembler, linker, C runtime, package manager, toolchain downloads, or dependency installation may become a hidden build dependency.
- Use Windows system DLL APIs through verified PE import descriptors and the Windows x64 ABI.
- Preserve 16-byte stack alignment at call sites and the 32-byte Windows x64 caller shadow space. Follow the documented argument registers and stack arguments for Windows APIs.
- Fail closed on unsupported language constructs, unresolved symbols, invalid types, unsupported imports, invalid PE fields, missing runtime prerequisites, ABI uncertainty, or failed verification.
- Never fabricate executables, PE metadata, import libraries, compiler capabilities, runtime output, screenshots, or test results.
- Text source and scripts should remain plain ASCII / UTF-8 without BOM. Validate encoding after generation.
- Asset roles: glTF/GLB for 3D scenes and geometry; KTX2 with Basis Universal and `KHR_texture_basisu` for 3D material textures; AVIF for 2D/UI images.

## 3. Completed milestone history (user-reported Windows acceptance)

These entries record the results explicitly reported by the user. The repository must retain or restore the exact test sources and fixtures needed to repeat the checks; a chat report is not a substitute for checked-in regression evidence.

| Milestone | Delivered scope | User-reported Windows result |
|---|---|---|
| 1 | PowerShell/.NET bootstrap; direct AMD64 PE32+ Hello World; direct KERNEL32 imports; Build/Run/Test shortcuts | Build PASS; Run PASS; exit 0. Hello.exe SHA-256: `6CA5B29FDE63330258C5B4D349C63A27A2D4CB3FA57F07D4375BA6D4F2878F96`. |
| 2 | Lexer, recursive-descent parser, multiple statements, comments, integers/strings, variables/assignment, arithmetic precedence, line/column diagnostics | 18 tests passed, 0 failed; Hello and Arithmetic build/run passed. |
| 3 | Native x64 arithmetic instructions, stack-backed variables, runtime loads/stores/mutation, fail-closed arithmetic runtime errors | 25 tests passed, 0 failed; Hello and Arithmetic runtime output passed. |
| 4 | Sharnou functions (up to four integer parameters), return values, lexical scopes, source-module imports and symbol resolution, expanded PE32+ linker and PE verifier | Six examples passed build, PE verification, and run; Stage 2: 25/25; Stage 4: 20/20; PE verifier: 4/4. |
| 5 | Standard library foundations: memory, strings, files/assets, logging, collections, windowing/events, threading/synchronization; five isolated Engine foundation programs | Engine preflight 5/5; all 12 example/Engine builds passed; Stage 5: 25/25; combined PASS. |
| 6 | Win32 window, DXGI/D3D11 device and swap chain, render-target view, solid-color clear/present loop, frame timing and fail-closed error handling | Engine preflight 5/5; all 12 example/Engine builds passed; Stage 6: 9/9; combined PASS. User confirmed a 60-frame real D3D11 clear/present run. |

### Regression baseline

The cumulative Milestone 6 baseline is **83 cases**:

- Stage 2: 25
- Stage 4: 20
- PE verifier: 4
- Stage 5: 25
- Stage 6: 9
- Total: 83

The user reported all relevant suites passed locally. However, the current repository README explicitly says the imported Milestone 6 branch did not contain the 83-case source suites and fixtures. Therefore the status for the repository-reproducible frozen baseline remains **BLOCKED / RESTORE OR PIN THE EXACT 83-CASE TEST SOURCES** until the actual files are checked in and rerun. Do not claim that this repository has rerun 83 tests until it has.

## 4. Milestone 7 - Self-hosting compiler

**Goal:** a Sharnou-written compiler implementation that can be compiled by the existing bootstrap and then compile itself.

Acceptance sequence:

1. Implement the compiler frontend/backend/linker subset in `.sharnou` source files.
2. Compile that source with the current PowerShell/.NET bootstrap.
3. Produce a genuine native `SharnouCompiler.exe`.
4. Run the native compiler against the same Sharnou compiler source.
5. Produce a second native compiler executable.
6. Compare bootstrap-produced and self-produced artifacts using exact hashes where reproducible, plus structural and behavioral equivalence checks where byte identity is not guaranteed.
7. Run the frozen 83-case regression suite with both compiler stages.
8. Record compiler hashes, source hashes, commands, stdout/stderr, exit codes, and test totals.

Do not describe the compiler as self-hosting until the native compiler has successfully compiled its own source and the verification suite has passed.

### Milestone 7A - Native control flow (current accepted prerequisite)

Required language constructs:

- `if` and `else` statements.
- `while` loops.
- Signed integer comparison operators: `<`, `>`, `<=`, `>=`, `==`, `!=`.
- Nested conditional and loop logic, loop termination, variable mutation, and signed integer edge cases.
- Correct source-location diagnostics and fail-closed rejection of unsupported syntax.

Condition semantics documented on the current branch:

- An integer condition of zero is false.
- Any non-zero integer condition is true.
- Comparisons produce normalized integer results 0 or 1.
- Blocks retain lexical scope; declarations inside if/else/while bodies are not visible outside the body.
- Variables continue to use unique slots allocated within the existing function frame.

Native x64 lowering documented on the current branch:

1. Evaluate the left operand and save it in a temporary stack slot.
2. Evaluate the right operand and move it to `ECX`.
3. Restore the left operand into `EAX`.
4. Emit `CMP EAX,ECX`.
5. Emit the signed `SETcc AL` form (`SETL`, `SETG`, `SETLE`, `SETGE`, `SETE`, or `SETNE`).
6. Emit `MOVZX EAX,AL` to normalize the Boolean value.
7. For if conditions, use `TEST EAX,EAX` and a near `JZ rel32` branch.
8. For if/else, emit a near `JMP rel32` over the else block.
9. For while, place a condition label, branch to loop exit on zero, emit the body, and jump back to the condition label.
10. Resolve branch labels and rel32 displacements in the existing code-fixup pass.

Preserve the existing Windows x64 ABI, caller shadow store, stack alignment, frame pointer, local-slot allocation, function calls, imports, dynamic section layout, base relocations, and PE verifier.

Current documented subset restrictions must remain explicit until deliberately implemented and tested: chained comparisons, string comparisons, logical AND/OR, else-if shorthand, and return nested inside a control-flow block are rejected. Use nested if statements for nested logic.

The branch currently contains a Stage 7A implementation and test runner. The current suite contains nine positive runtime cases, twelve negative parser/type cases, and three native instruction/branch checks (24 total). Test.ps1 also runs two Stage 5 collection-import regression cases. User-local Windows results are recorded in the session-state and issue register.

## 5. After 7A - planned self-hosting work

The following are ordered work areas, not yet accepted detailed language specifications. Audit the actual compiler source and tests before assigning exact syntax or implementation scope.

- **7B - Compiler-source language gap analysis:** enumerate every construct used by the proposed compiler source; map each to parser, type checker, IR, and x64 backend support; add missing positive/negative tests.
- **7C - Sharnou compiler frontend implementation:** lexer, parser, AST, semantic checks, module loading, diagnostics, and compiler tests written in Sharnou.
- **7D - Sharnou-native backend and linker implementation:** instruction encoding, fixups, PE32+ construction, imports, relocations, and verifier integration written in Sharnou.
- **7E - Bootstrap/native stage comparison:** build native compiler from bootstrap, then compile the same source with the native compiler; compare outputs and behavior.
- **7F - Self-hosting gate:** frozen regression suite, compiler determinism/equivalence, negative tests, ABI checks, PE verification, and recorded reproducibility evidence.

Do not skip 7A or the baseline restoration gate to start a large self-hosting source generation.

## 6. Engine and graphics direction after compiler maturity

The existing Milestone 6 D3D11 clear/present result is only the graphics foundation. It does not mean a complete 3D renderer exists.

The renderer roadmap should be implemented in independently tested layers:

1. Window/device/swap-chain lifetime, resize, device-removed handling, depth-stencil resources, render-target ownership, and deterministic COM release.
2. Vertex/index buffers, input layouts, shader compilation/integration owned by Sharnou, draw calls, transforms, and a visible triangle/primitive.
3. Camera, coordinate system, scene graph/world transforms, material binding, texture and sampler resources.
4. glTF 2.0 / GLB scene and geometry loading; reject unsupported required extensions.
5. KTX2 / Basis Universal texture intake and GPU upload; AVIF for 2D/UI content only.
6. Metallic-roughness PBR, normals, roughness, metallic, AO, and emissive material channels.
7. Directional, point, and spot lighting; cascaded shadow maps.
8. Skeletal animation, skinning, animation blending, terrain/large environments, particles, atmospheric effects.
9. HDR, post-processing, tone mapping, GPU instancing, and LOD.
10. Profiling, stress testing, memory budgets, runtime asset integrity/cache, and Windows visual/performance acceptance.

See [Renderer-Roadmap-3D-MMORPG.md](Renderer-Roadmap-3D-MMORPG.md) for the detailed frame pipeline, ownership model, asset policy, PBR, lighting/shadows, geometry, animation, and definition of done.

## 7. Sharnou IDE and Honour War integration

After compiler self-hosting and Engine APIs are stable:

- Integrate the native Sharnou compiler into Sharnou IDE without hidden external build tools.
- Version the compiler/IDE project and diagnostic interfaces.
- Build the Engine through the native compiler.
- Port the existing Honour War prototype incrementally; do not replace the project with an unrelated fresh starter.
- Preserve the agreed canonical runtime path when integrating the native runtime: `Build\Runtime\SharnouEngine.exe`.
- Maintain the accepted five-source native runtime contract unless explicitly revised.
- Keep game systems, assets, runtime dependencies, and actual native screenshots/tests distinct from static asset manifests or generated mock images.

## 8. Definition of done for every milestone

A milestone is complete only when all applicable evidence exists:

- Accepted source files and documented language/API behavior.
- Positive and negative tests for new features.
- All frozen prior regression tests preserved and rerun.
- Native PE structural verification.
- Actual Windows execution on the target architecture.
- Correct stdout/stderr and process exit codes for console tests.
- Real window/render output and visual evidence for graphics milestones.
- ABI, calling convention, stack alignment, import, relocation, lifetime, and error-path checks.
- SHA-256 hashes for source/build artifacts and an exact test report.
- Updated `Docs/AI-SESSION-STATE.md`, issue register, and AI status issue.

## 9. Planning status

| Work item | State |
|---|---|
| Milestones 1-6 | User-reported Windows PASS; preserve history and exact baseline |
| 83-case frozen repository baseline | Blocked until source suites/fixtures are restored or pinned and replayed on Windows |
| Milestone 7A source implementation | PR #16; Windows run `45705513598` passed on head `b1365dc17bb5aeaad74462633fadfdc29b56fa3e`; Stage 7A 24/24, Stage 5 imports 2/2, stack-probe/unwind 6/6 | WINDOWS CI PASS; user-local retest of PR #16 still pending |
| Milestone 7A functional + stack-probe/unwind gates | Windows run `45705513598` passed Stage 7A 24/24, imports 2/2, ABI regression 6/6; PE verifier accepted six-section images | WINDOWS CI PASS; issue #1 remains open for nonvolatile-register/runtime RSP/argument probes and generic API marshalling |
| Milestone 7B-7F self-hosting | Planned; do not begin until 7A and regression gates are accepted |
| Post-M6 3D renderer | Long-term roadmap; clear/present is not full 3D rendering |
| Sharnou IDE and Honour War integration | Later dependent work |

The latest status, current blockers, issue links, and next action are maintained in [AI-SESSION-STATE.md](AI-SESSION-STATE.md).


## 10. Live GitHub status overlay - 2026-11-20

This section records current branch/PR evidence without changing the accepted milestone scope above.

| Work item | Current evidence | Status / boundary |
|---|---|---|
| Milestone 7A | Default-branch Windows Actions run `44813123428` succeeded at commit `fc015ba925c001e1f647f3897736f6f4bd64f0dc`; suite declares 8 positive, 12 negative, 3 instruction checks | WINDOWS CI PASS; user-local result not separately reported |
| Frozen Milestone 6 regression baseline | PR #6, head `9dfe1bc09685a6f7deb9d29b5192b1aae0686039`, run `44700641397`, 83/83 Windows pass; original package SHA-256 `0b6bf15445a5dfd8cbf93450af7fd2f5fd6239d4ed082ab18b09878a94b8b164` | PR open/unmerged; baseline restoration verified on feature branch, default branch still awaits integration |
| Milestone 7B proposal | PR #5, head `0b8dee87b699eabcaaac37f111686231fb29a82c`, run `44693097619`; PR reports Stage 7A 23/23 and Stage 7B 32/32 | Proposed branch only; not user-accepted or merged |
| Native DevAgent utility | PR #7 draft; run `44758761226` succeeded through example build/run, regression tests, DevAgent execution and artifact upload | Native test orchestrator proposal; not an AI source-generating agent; open draft |
| Roadmap/automation extension | PR #4 remains open/unmerged | Documentation and scheduled-workflow proposal; not active on the default branch until merged |

Authoritative live details, blockers, hashes, and next actions are maintained in [AI-SESSION-STATE.md](AI-SESSION-STATE.md) and [AI-ISSUE-REGISTER.md](AI-ISSUE-REGISTER.md). The status tracker is [GitHub Issue #8](https://github.com/Sharnou/Sharnou-Compiler/issues/8).

The connected GitHub toolset cannot create or mutate a GitHub Projects V2 board. The roadmap is therefore a versioned Markdown plan map plus linked GitHub Issues/PRs. Do not misrepresent this as a visual Kanban board.


## User-approved session confirmation - 2026-11-20 22:49 Africa/Cairo

- The user explicitly reconfirmed the Milestone 6 Windows acceptance: Engine foundation preflight 5/5; all 12 examples/Engine builds passed; Stage 6 D3D11 suite 9/9; real window/device/swap-chain/render-target setup and a 60-frame clear/present loop passed; combined result PASS. This remains USER-REPORTED WINDOWS PASS.
- The user accepted the Milestone 7 readiness decision that self-hosting must wait for native control flow.
- The user explicitly accepted Milestone 7A as the next implementation scope: native if/else, while, signed integer comparisons <, >, <=, >=, ==, !=, nested logic, loop termination, runtime variable mutation, signed-edge tests, source-located diagnostics, and fail-closed rejection of unsupported constructs.
- Preserve the existing Windows x64 ABI and stack-frame contract: argument registers, 32-byte shadow space, 16-byte call-site alignment, frame pointer, variable/temporary slot allocation, function-call behavior, and existing PE/import/relocation/verifier behavior.
- Preserve the cumulative M1-M6 regression count of 83. Exact repository reproducibility remains tracked by issue #9; the open PR #6 is not merged into the default branch.
- M7A implementation is documented in the current branch, and Windows Actions run 44813123428 is recorded as WINDOWS CI PASS. A separate user-local M7A test result has not been reported; do not infer one from the M6 report or CI.
- PR #5 proposes 7B Boolean/logical short-circuit, break/continue, and nested returns. That proposal is not accepted scope unless the user explicitly approves it.
- Do not begin the full Sharnou-written self-hosting compiler before the 7A acceptance and frozen 83-case baseline gates are satisfied and the compiler-source language-gap analysis is complete.
- Current default branch HEAD reviewed at session start: f5a12b7c967370bb511a8d4ec6c8a6b9f9afc4b9. Open PRs reviewed: #4 roadmap proposal; #5 unaccepted 7B proposal; #6 frozen 83-case restoration with Windows 83/83 CI evidence but not merged; #7 draft native DevAgent test orchestrator, not an AI source-generating agent.
- Existing enabled task automations were inspected: daily Sharnou DevAgent Progress and weekly Advance Sharnou Stack. Both already include mandatory live-repository read-first instructions and scheduled status persistence. Three legacy Honour War daily-upgrade tasks remain disabled.
- Persistence boundary: GitHub repository files and issue #8 are the canonical session record. Scheduled automations save on their configured runs; there is no per-chat-turn event hook or continuous background monitor. Manually initiated sessions must follow AGENTS.md / AI_START_HERE.md, read the live repository before work, and persist status before ending.
- GitHub Projects V2 board-write operations are not exposed by the connected GitHub tool. The accepted plan map is Docs/AI-DEVELOPMENT-PLAN.md plus the live issue register and linked GitHub issues/PRs; do not claim a visual Kanban board was updated.
- No compiler, test, example, build script, or runtime source was changed in this status-only session. No native build or test was run by the assistant. This session performed repository review and governance/status persistence only.
- Next dependency-ordered actions: (1) review PR #6 and exact baseline provenance/adaptation, then integrate only through the normal review process; (2) capture M7A user-local Windows run evidence separately from CI; (3) re-audit historical ABI risks in issue #1; (4) only after gates, define the 7B+ compiler-source language gap and self-hosting plan.


## Live status overlay - 2026-11-21 08:43 Africa/Cairo

This dated evidence overlay supersedes earlier statements that the 83-case suite is wholly missing. It does not change the accepted Milestone 7A scope or accept Milestone 7B implementation.

- Default branch at the start of this review: `Sharnou-Compiler`, HEAD `8f181ccf533947e41d1ebdfd39a58a02a46667d9`. The latest recorded default-branch Stage 7A run is `44813123428`, success at `fc015ba925c001e1f647f3897736f6f4bd64f0dc`. Six commits after that run changed only the three AI status documents; the current compiler, verifier, Stage 7A test, and workflow blobs are identical to the tested commit.
- PR #6 restores the 83-case Milestone 6 suite on `automation/restore-m6-83-regression`, head `9dfe1bc09685a6f7deb9d29b5192b1aae0686039`. It remains open, unmerged, and mergeable. Windows run `44700641397` passed 83/83; run `44700641419` passed Stage 7A 23/23 on the same PR head. The compiler, verifier, Stage 7A test, and Stage 7A workflow blobs match the default branch. The baseline is therefore reproducibly tested with the current 7A code on the PR branch, but is not yet integrated into the default branch.
- The 83 baseline inventory is Stage 2 25, Stage 4 20, PE verifier 4, Stage 5 25, Stage 6 9. Case-intent classification from the emitted case names is 36 positive and 47 negative; the manifest itself records suite totals, not positive/negative labels. The temporary Stage 2 adapter reclassifies the obsolete pre-7A `if` rejection fixture as a positive case without modifying the hash-pinned original script or fixture.
- Baseline provenance remains partly open: the runner verifies the compressed payload SHA-256 and each restored member against the member hash embedded in the payload. The manifest records the original `SHA256SUMS.txt` digest, but the runner does not re-read that original manifest. The requested file-by-file comparison with the separate R25-R4 archive (SHA-256 `CA01AEACB2E35C6E8039E58F15202A01399DAEA3E0A24E7B4D357772C8EF1274`) is still outstanding.
- PR #5 is an existing isolated 7B candidate, not accepted scope: head `0b8dee87b699eabcaaac37f111686231fb29a82c`, open/unmerged/mergeable, based on the same older base commit. Windows run `44693097619` passed Stage 7A 23/23 and Stage 7B 32/32 (15 positive, 13 negative, 4 instruction checks). It does not run the 83-case baseline. Its test sources are embedded in the PowerShell test file rather than maintained as standalone `.sharnou` examples.
- Static 7A review confirms the signed `CMP EAX,ECX` / `SETcc` / `MOVZX` lowering and the `TEST` / `JZ rel32` / `JMP rel32` label fixups are internally consistent. The 7A test's three machine checks are byte-pattern presence checks, not a decoder that independently validates every branch target; the eight positive runtime cases provide the behavioral check.
- The current ABI audit re-confirms issue #1 risks in source: frames can grow to 1 MiB, the prologue subtracts the frame directly without `__chkstk` or page-touch probing, PE stack commit is 4 KiB, and the linker emits only four sections with no `.pdata` / `.xdata` or populated exception directory. This is static evidence, not a reproduced runtime failure. Keep the ABI gate open before self-hosting.
- PR #7 remains a draft native test orchestrator, not an AI source-generating agent. Windows run `44758761226` built `SharnouDevAgent.exe` (SHA-256 `9F128ED96972858B13C763B4324813B3D6A1970737F2403C10C70717CE947341`), ran it with process exit code 0, and uploaded artifact `14654214120`. The program launches PowerShell regression tests and explicitly prints that the self-hosted native compiler is not implemented; there is no persistent autonomous worker, checkpoint/recovery, host deployment, or restart proof.
- Next dependency-ordered work: user review/integration decision for PR #6; then, only with explicit implementation authorization, base a 7B patch on the restored baseline, add standalone Boolean/loop/return examples and the missing edge tests, and require same-commit Windows evidence for 83 + 23 + 32 = 138 result records. Re-audit/resolve issue #1 ABI gaps before claiming self-hosting readiness.


## 8. Autonomous SharnouDevAgent track - requested architecture, not yet implemented

The user has requested a native autonomous development agent with local search/read/download/knowledge ingestion, reasoning and task planning, specialist agent creation/editing, compiler/Engine repair with automatic test-backed corrections, authorized static reverse engineering, and optional second-opinion integrations with OpenAI and Perplexity. The durable architecture and acceptance gates are in [SHARNOU-DEVAGENT-AUTONOMOUS-ARCHITECTURE.md](SHARNOU-DEVAGENT-AUTONOMOUS-ARCHITECTURE.md); tracking issue [#14](https://github.com/Sharnou/Sharnou-Compiler/issues/14).

This is a separate requested product track, not a declaration that an AI agent exists. PR #7 is only a native test orchestrator and remains an open draft; the default-branch compiler has no model-safe process broker. The current PR #7 prototype's raw command string + indefinite wait must not be exposed to model-generated commands. The primary mode must be a Sharnou-owned in-process local model runtime that works offline. OpenAI Responses and Perplexity Agent API adapters are optional only. Tool calls must be typed and permission-scoped, and source repairs must use staging transactions, regression gates, and rollback.

Dependency order: restore/pin the exact 83-case baseline and retain the ABI gates; then build a restricted process broker; then native search/read/download/quarantine and persistent evidence memory; then local model inference; then planner/subagents and validated agent manifests; then bounded self-correction and static reverse engineering; finally optional provider adapters. The default 7A/compiler scope and the self-hosting prerequisite are not bypassed by this parallel DevAgent track.

Current status: ABI PREREQUISITES WINDOWS CI PASS (PR #17); SECURE PROCESS BROKER DESIGN RECORDED BUT NATIVE IMPLEMENTATION NOT STARTED; LOCAL INFERENCE NOT BUILT; AUTONOMOUS REPAIR NOT RUN. Acceptance requires offline operation without AI provider credentials, durable restart recovery, process isolation and timeouts, source-hash/evidence journals, passing security/rollback tests, and Windows runtime evidence.
## 2026-11-25 - stack-probe and unwind repair

PR #16 implements the outstanding large-frame stack-probe and x64 unwind-table defects identified in issue #1. Windows Actions run [45705513598](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45705513598) passed on PR head `b1365dc17bb5aeaad74462633fadfdc29b56fa3e`:

- Stage 7A: 24/24.
- Stage 5 collection import regression: 2/2.
- Stack probe and unwind regression: 6/6, including a native multi-page frame executable, both UWOP_ALLOC_LARGE encodings, function epilogue validation, and two fail-closed corrupted-metadata tests.
- ASCII/no-BOM: PASS; combined result: PASS.

The linker now emits `.pdata` / `.xdata`, a PE exception directory, and a private leaf stack-probe helper that touches each 4 KiB page before the fixed RSP allocation. The verifier validates the six-section layout, runtime-function ranges, unwind records and stack-probe code. PR #16 remains open/unmerged. These checks do not close the separate 83-case baseline gate or all ABI runtime probes; see issues #1 and #9.

 
## 2026-11-26 - ABI gate passed; process broker next

PR #17 now has Windows CI evidence for the runtime ABI tranche and frozen M1-M6 baseline on the same head: Stage 7A 24/24, collection imports 2/2, stack-probe/unwind 6/6, runtime ABI sentinel/alignment/argument/marshalling tests PASS, and M1-M6 83/83. Evidence: [45717111101](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45717111101) and [45717111040](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45717111040).

The next dependency is the secure native process broker. The security contract is recorded in [SHARNOU-DEVAGENT-PROCESS-BROKER-SECURITY-DESIGN.md](SHARNOU-DEVAGENT-PROCESS-BROKER-SECURITY-DESIGN.md). The old raw-string `sh_dev_run_process(String)` prototype is explicitly rejected. The broker must use immutable tool IDs, exact script hashes, workspace confinement, a restricted token, suspended creation, Job Object process-tree containment, timeout/cancellation, bounded output, and adversarial tests. No model-controlled process execution is enabled.



## 2026-11-26 - runtime ABI and broker phase 1 validated

Integrated PR #18 head `7a15892a944c747f9563961d7c050c909dd3d3a4` passed Windows CI. Stage 7A 24/24, collection imports 2/2, stack-probe/unwind 6/6, Runtime ABI PASS, and the frozen M1-M6 suite 83/83. The ABI gate exercises all 16 supported integer arguments, RSP alignment, nonvolatile register sentinels, higher-arity Win32 APIs, and rejects arity 17.

The native DevAgent test-tool process broker phase 1 is now implemented and validated: typed explicit-opt-in API, six fixed tool IDs, SHA-256-pinned manifest, native CNG script hashing, image-derived workspace path independent of CWD, reparse-point checks, suspended process creation, Job Object containment, memory/process limits, timeout, and descendant termination.

Evidence: combined run [45772104864](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45772104864), frozen baseline run [45772104661](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45772104661). PR #18 remains draft/unmerged.

Remaining work before any model-controlled execution: complete executable/workspace canonicalization and ADS/UNC/device rejection; restricted token/AppContainer and workspace-only ACLs; clean environment and DLL-search policy; bounded stdout/stderr capture with STARTUPINFOEX handle isolation; cancellation; durable tool evidence and restart recovery. Until those gates pass, the broker remains disabled for model-generated plans.


## 2026-11-27 - DevAgent Phase 2B.6 production broker integration

Phase 2B.6 is the production-integration and recovery-qualification tranche. The active parent candidate is PR #24, branch devagent-acl-transaction-recovery-20261126, starting head bd411c2fc777006f9b1160ab8d3d5992c2a15afa. Its M6 historical baseline passed 83/83 (run 45964360562), but Stage 7A failed (run 45964360481) during native post-crash ACL recovery. The phase is therefore IN PROGRESS / BLOCKED, not accepted.

The failing run returned -2685 for each broker invocation after WAIT_ABANDONED. The emitter's status encoding decodes this to readWin32=5 and metadataWin32=5 (ERROR_ACCESS_DENIED). An independent PowerShell CreateFileA probe using the same access/share/disposition/flags returned success. This is a native-path/call-context discrepancy, not proof that the workspace DACL should be broadened. A diagnostic patch now forwards the native recovery path to the Actions log and decodes the two Win32 values. Fix the exact discrepancy before making any ACL-policy change.

The milestone also requires a unique AppContainer identity per execution, a versioned recovery journal that can retire a crashed profile after ACL restoration, a deterministic explicit Unicode environment (never lpEnvironment=NULL), production integration of the Phase 2B.5 two-stream handle allowlist, child loader/DLL-search hardening, and same-head crash/adversarial Windows acceptance. New native APIs must be represented in the generated PE import table and checked by the PE verifier; the final executable import table, not a planned manifest, is authoritative.

Model-facing process execution and autonomous execution remain DISABLED.


## Phase 2B.8 implementation sequencing update - 2026-11-27

The Phase 2B.8 specification and acceptance gates are in `Docs/PHASE-2B8-CRASH-SAFE-EXECUTION-LIFECYCLE.md`; the reconciliation and code-increment record are in `Docs/PHASE-2B8-IMPLEMENTATION-LOG.md`.

Current PR #24 head `6344632746cd0666025a0beb0d31f4752d6480f6` has targeted Windows evidence for journal recovery, exact ACL/label rollback and Job Object child termination (run 46003358917), plus companion M1-M6 83/83 evidence (run 46003358930). PR #24 remains the Phase 2B.6 integration parent and is not security accepted. The reviewed repository does not establish a separately completed Phase 2B.7 lifecycle implementation.

Draft PR #28 starts Phase 2B.8 on an isolated branch stacked on that exact PR #24 head. Its first code increment adds a Windows CNG/AppContainer identity primitive test to the combined test suite. It is **NOT YET WINDOWS-CI-VERIFIED** and does not change the production broker or its stable profile behavior.

Next dependencies: verify the identity fixture on Windows; implement actual unique identity creation in the emitted broker; design authenticated journal metadata before recording profile names for restart cleanup; integrate idempotent profile deletion with normal and crash recovery; then implement clean environment, separate bounded streams, DLL hardening and exhaustive lifecycle qualification. Model-generated execution remains disabled until all same-commit security gates and human review pass.


## Phase 2B.8 engineering status - 2026-11-27

The first Windows identity and journal-schema primitives are independently tested. On code-bearing commit `907281187ffdf9223d4b345a2847c2a1feb883cf`, Windows run [46021589016](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46021589016) passed: eight fresh CNG/AppContainer identities, exact child package-SID checks on suspended children, Low IL and zero capabilities, normal profile delete/recreate/delete, DPAPI user-scope envelope protection/tamper checks, and strict v2 fixture schema rejection tests. M1-M6 83/83 passed in [46021589107](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46021589107). Stage 7A combined test run 46021589123 was still in progress at the last status check.

The DPAPI result is deliberately classified as a user-scope protection primitive, not process-writer authentication. A same-user process can use the same DPAPI context and optional entropy to produce a different valid blob. The writer-authentication trust boundary must be decided and reviewed before native v2 journal integration or privileged profile cleanup. See `Docs/PHASE-2B8-JOURNAL-TRUST-BOUNDARY.md`.

No code in the compiler-emitted broker or its v1 journal has yet been changed. Unique per-execution profile creation, persisted authenticated identity, restart-time profile cleanup, explicit Unicode environment, separate streams, child DLL loader policy, cancellation/concurrency and crash-cut qualification remain pending. Model-facing/autonomous execution remains disabled.


### Latest Phase 2B.8 identity/journal evidence - 2026-11-27

The latest dedicated Windows test [46022134602](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46022134602) passed on `a64b81def96b22315b8ab8034bb60c4af1870e32`, including 8 real suspended child-token inspections, distinct AppContainer identities/SIDs, Low IL and zero capabilities, verified normal profile deletion, strict v2 schema negatives, DPAPI tamper/wrong-context checks and an explicit same-user re-protection proof. That last test demonstrates why DPAPI alone does not authenticate the writer process. The production trust anchor remains unresolved; native broker integration must not consume profile cleanup authority from DPAPI-only metadata until this decision is reviewed.


## Phase 2B.8 R5 - Native Windows Execution Authority Service

The dedicated Windows service / service-SID / non-exportable machine CNG key architecture is owner-approved for implementation planning. It remains a separate acceptance and deployment boundary, not authorization to enable process execution.

Dependency-ordered R5 implementation: R5.0 typed bounded IPC protocol; R5.1 native Sharnou-generated SCM service host and service lifecycle tests; R5.2 service SID and protected non-exportable key; R5.3 local named-pipe transport/client authentication; R5.4 service-owned signed durable journal; R5.5 workspace, AppContainer, ACL and Job Object ownership; R5.6 crash/concurrency/restart/operator recovery; R5.7 independent PE-import/evidence verifier and security review.

Current candidate: draft PR #31, branch `phase-2b8-r5-authority-service-protocol-20261127`, stacked on R4 tested source head `b0d3ff96deadd04072d7f63ccb4b2c85b42a5c15`. R5.0 defines the 40-byte IPC v1 request header and five typed operations, provides a test-only strict schema/parser fixture, adds it to Test.ps1, and adds an exact-head Windows Server 2025 CI gate. This protocol tranche is not itself a Windows service.

R5.1 must implement a real Windows SCM host using the Sharnou native code-generation/PE path, validate the actual generated executable import table, and pass service start/stop/control/shutdown tests. Do not use Add-Type as production service code or introduce external compiler/linker dependencies. Keep model-facing and autonomous execution disabled until separate later authorization milestones and complete Phase 2B.8 security acceptance.


## R5.1 Native SCM service-host implementation gates

- R5.1.a: bounded multi-target DIR64 relocation builder; preserve normal output compatibility; PE parser and rebase tests.
- R5.1.b: typed code-label/data-pointer fixups and Win64 callback ABI validation/runtime probes.
- R5.1.c: inert Sharnou-generated SCM service host with exact import-table verification and disposable Windows install/start/stop/shutdown tests.
- Current draft PR #32 contains the service lifecycle specification and compiler preflight only. Do not call it a service implementation or mark it passed.
- R5.2 service identity/key, R5.3 pipe transport, R5.4 signed journal, R5.5 transaction ownership, R5.6 recovery, R5.7 independent review follow only after R5.1.
- Model-facing and autonomous execution remain disabled until full Phase 2B.8 acceptance and separate policy authorization milestones.


## R5.1.a/.b result and R5.1.c dependency — 2026-11-27

R5.1.a is accepted for its relocation primitive scope on exact Windows source head `2583faec76d5e469962756d17d2ffabecd6fcd98`, run 46066382172, artifact 15231785189 (SHA-256 `698ebd55dfb66b529cd8b001aa986e4832e995e8f37a68f7906c7db19546b725`). The 21-case relocation suite and combined compiler/ABI/broker/Phase 2B.8 regression passed, including M1-M6 83/83. Low-IL AppContainer DPAPI protection remains INCONCLUSIVE due to missing System.Security in the CI PowerShell process.

R5.1.b callback ABI implementation passed on predecessor head `beb7f47989b1180dcc83c916422cee5123ce58d2`, run 46066393744, artifact 15230738893 (SHA-256 `90a45413274ff3f86d665fb0ecdf90a03071cc81ca30da076eef139a7317bed1`). That run verifies actual relocated ServiceMain/HandlerEx callback pointers and runtime ABI probes, but the old PR base was stale. The correctly stacked replacement is draft PR #35 (base R5.1.a accepted head); its exact-head run 46067337857 is pending and must pass before PR #35 can be accepted.

Next: R5.1.c actual Sharnou-generated SCM service host and disposable Windows SCM lifecycle tests. These primitive passes do not equal a service implementation or full Phase 2B.8 acceptance. Keep model-facing and autonomous execution disabled.


## R5.1.c implementation candidate - 2026-11-28

The current R5.1.c candidate is isolated on `phase-2b8-r5-1c-native-scm-host-20261128`, stacked directly on the corrected R5.1.b exact source head `ab00219f1aa9783c148035b754eebce7269f6fbb`. It adds a genuine Sharnou-generated Windows SCM executable path, typed relocated service-table/callback pointers, a service-specific exact import profile and PE verification, real disposable Windows SCM smoke tests, and an exact-head Windows Server 2025 workflow. The candidate is **not accepted** until that workflow and its evidence artifact pass on the exact source head.

The focused R5.1.c smoke does not replace R5.1.d. R5.1.d must qualify actual SCM startup/shutdown/failure handling/cleanup and adversarial failure cases before R5.2 can begin. Then and only then: R5.2 service identity/protected CNG key -> R5.3 authenticated local named-pipe IPC -> R5.4 service-owned authenticated durable journal. Model-facing and autonomous execution remain disabled; full Phase 2B.8 is not accepted.


## Current authoritative execution sequence - 2026-11-28

R5.1.c has passed its declared exact-head qualification:
- Tested head `85efea1cd17ea03e5040dc6708d0dac1928dcfd5`.
- Windows Server 2025 run [46122764612](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46122764612): SUCCESS.
- Inspected artifact id `15253524806`, SHA-256 `7c4fda351a1fa7f117e6fa1615f5d521b3176d786d0cd2de502be5f20ec85556`.
- Native service executable SHA-256 `8623ed7fd37153a41b841cad632e30ac6965b5bfee0153a59e0880fb43e43f73`; PE verification and actual disposable SCM lifecycle passed; complete combined regression PASS.

**R5.1.d is now the next authorized milestone.** Implement a separate adversarial Windows SCM lifecycle qualification tranche covering: START_PENDING/RUNNING/STOP_PENDING/STOPPED status and field assertions; SERVICE_CONTROL_SHUTDOWN; test-only failure injection at dispatcher, handler registration, event creation and SetServiceStatus; repeated lifecycle and duplicate controls; start/stop races; timeout and forced termination; process, handle and service-registration orphan checks; crash cleanup and recovery. Ensure the fault injection is absent from normal production builds and verify that absence in the final image/source profile.

Do not begin R5.2 before R5.1.d exact-head acceptance. R5.3 follows R5.2; R5.4 follows R5.3. The inherited Low-IL AppContainer DPAPI protection check remains INCONCLUSIVE because System.Security could not be loaded in the Windows PowerShell test process. It remains a Phase 2B.8 gap even though R5.1.c's scoped gate passed.

Model-facing and autonomous execution remain DISABLED. Phase 2B.8 remains NOT SECURITY ACCEPTED; no production rollout is authorized.
