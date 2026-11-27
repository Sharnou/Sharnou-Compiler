# Sharnou Compiler and Engine - Accepted Development Plan

**Last maintained:** 2026-11-27
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


## 2026-11-27 - DevAgent Phase 2B.2 native interop and test-only AppContainer fixture

Phase 2B.2 is implemented and Windows-CI validated on PR #18 candidate head `7804e3663cdd6325a39b61204e4e526b7bb0c0a5`:
- [Native interop/AppContainer test fixture](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45912115900): PASS. Runtime CLR interop layout measurement checked 10 structure sizes and 53 field offsets. A test-only P/Invoke fixture made 18 reviewed Win32 API bindings, created a real AppContainer profile, verified the actual fixed child process token (AppContainer=1, exact profile SID, integrity RID <= Low, zero capabilities), checked a normal parent-token negative control, and terminated the suspended child without calling ResumeThread. Result: 11 assertions passed.
- [Frozen M1-M6 baseline](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45912115910): 83/83 PASS.
- [Crash-safe workspace transaction](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45912115940): 44/44 PASS.
- [Native ABI SDK contract](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45912117189): PASS.
- [Integrated Stage 7A](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45912115911): PASS, Stage 7A 24/24, collection imports 2/2, stack probe/unwind 6/6, Runtime ABI PASS and combined regression PASS.

Evidence qualification: the layout runtime probe uses the .NET Framework unmanaged interop marshaler; it is not a native Sharnou compiler-generated `sizeof`/`offsetof` probe. The AppContainer child is started from PowerShell through in-memory P/Invoke, not through the native compiler emitter. The fixture uses a NULL environment pointer, never resumes the child, terminates it immediately after token checks, and does not prove output containment, workspace ACL access, network denial or production broker integration. No native production PE import descriptors or compiler emitter code were modified.

Next accepted DevAgent dependency: Phase 2B.3 - bind the real per-execution AppContainer SID to the dedicated workspace DACL with the narrowest necessary access, integrate that with the already-tested crash-safe ACL transaction, and verify exact descriptor rollback/recovery. Model-controlled process execution remains disabled until every later gate (restricted-token decision, Job Object, handle list, bounded dual-stream output, cancellation and full adversarial tests) passes.


## 2026-11-27 - DevAgent Phase 2B.3: package SID-bound workspace ACLs

Phase 2B.3 is implemented and Windows-CI validated on candidate head `6761c7ab6f251d487a09f592c96071782622b3ab` (PR #18 remains draft/open/unmerged). The dedicated AppContainer workspace ACL workflow [45914498923](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45914498923) passed 30 assertions on Windows Server 2025 x64. The integrated native ABI/AppContainer workflow [45914499001](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45914499001) passed, and the exact-head frozen M1-M6 regression run [45914499087](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45914499087) passed 83/83.

The test-only fixture binds two genuine `CreateAppContainerProfile` SIDs to separate per-execution DACLs. The package receives only the reviewed scratch-workspace mask `0x0013019F`; inheritance is disabled and the package is excluded from the journal, shared parent, other execution, broker-image and compiler-source paths. Actual AppContainer process-token impersonation proves own-workspace read/write/create succeeds and the negative access cases fail with access denied. The suspended child is terminated and waited before rollback. Normal completion and crash recovery restore the exact original owner/group/DACL SDDL, with idempotent second-pass recovery.

The Phase 2B.3 fixture is not the production broker: it uses PowerShell/.NET in-memory P/Invoke, never resumes the child, and does not prove arbitrary code execution, Job Object containment, clean environment, DLL search isolation, output capture, cancellation or network denial. No production compiler/PE import/emitter source was changed. Model-facing process execution remains DISABLED.

Next dependency: Phase 2B.4, separate suspended AppContainer + Job Object lifecycle and token verification before resume, still in a fixed test-only fixture. Phase 2B.3 completion is not authorization to enable autonomous execution.


Phase 2B.3 exact-head regression closure: integrated Stage 7A workflow [45914498926](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45914498926) passed 24/24; collection imports 2/2; stack probe/unwind 6/6; Runtime ABI PASS; M1-M6 83/83; Combined result PASS. The documentation-only follow-up head independently reran Phase 2B.3 ACL [45914740334](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45914740334), integrated ABI/AppContainer [45914740286](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45914740286), workspace security [45914740289](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45914740289), and M1-M6 [45914740282](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45914740282); all passed. PR #18 remains draft/unmerged.


## 2026-11-27 - DevAgent Phase 2B.4: suspended AppContainer + Job Object launch

Phase 2B.4 is Windows-CI validated as a **test-only fixed-image fixture** on candidate head `e82826bf889a110d58b46c9427b8e86b672a0a3a`. Dedicated workflow [45917757166](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45917757166) passed 41 assertions on Windows Server 2025 x64. Integrated ABI/AppContainer workflow [45917757077](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45917757077) passed; M1-M6 baseline [45917757102](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45917757102) passed 83/83; integrated Stage 7A [45917757090](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/45917757090) passed 24/24, collection 2/2, stack/unwind 6/6, Runtime ABI, M1-M6 83/83 and Combined result. Existing workspace security, AppContainer ACL and native ABI contract workflows also passed on the same head.

The fixture configures a Job Object before process creation with kill-on-close, one-active-process and 256 MiB per-process memory policy. It creates only absolute System32 `whoami.exe` suspended in a real AppContainer, assigns it to the Job Object, verifies exact process/job membership, then verifies actual child token AppContainer flag, exact package SID, Low-or-lower integrity and zero capabilities. Only after those gates does it call `ResumeThread`; the prior suspend count is 1, and the process exits 0 within 15 seconds. Four negative controls (post-create/pre-assignment failure, invalid Job Object handle, package-SID mismatch, and deliberately denied final gate) all prove the child is not resumed and is terminated/reaped. Every scenario then verifies exact workspace descriptor restoration and owned profile cleanup. Result: 41/41 assertions.

**Unresolved security boundary:** a custom explicit environment passed to CreateProcessW still returns Win32 error 203 on the Windows Server 2025 runner. This is documented rather than treated as solved. The isolated fixture therefore sets `lpEnvironment=NULL` and inherits the CI runner environment for the fixed trusted whoami image; the script emits a boundary warning. It accepts no user/model command/path/arguments, and does not touch production broker code. The clean explicit production environment remains BLOCKED; it must be independently fixed and validated before production broker integration or model-facing execution.

No production compiler/PE imports/emitter changed. Model-facing process execution remains DISABLED. Next: Phase 2B.5, STARTUPINFOEX handle allowlist and bounded concurrent stdout/stderr capture, while retaining the custom-environment blocker as a separate prerequisite for production acceptance.


## 2026-11-27 - DevAgent Phase 2B.5 candidate: explicit handle allowlist and bounded dual-stream capture

Phase 2B.5 adds a **test-only** STARTUPINFOEX / PROC_THREAD_ATTRIBUTE_HANDLE_LIST fixture and bounded stdout/stderr capture to the devagent-secure-process-broker-20261126 feature branch / PR #18. The candidate is not accepted as Windows-runtime validated until its dedicated Windows workflow and same-head regressions finish successfully.

The fixture uses a fixed SHA-256-pinned PowerShell test child and an absolute System32 PowerShell image. It creates separate stdout/stderr pipes, clears inheritance on both parent read endpoints, keeps the two child write endpoints inheritable, sorts and supplies exactly those two handles in the STARTUPINFOEX handle list, and sets STARTF_USESTDHANDLES. A separate inheritable sentinel handle is deliberately omitted and must be inaccessible to the child. CreateProcessW uses bInheritHandles=TRUE only with the explicit two-handle allowlist. The suspended child is assigned to its Job Object and membership is verified before ResumeThread.

The parent drains stdout and stderr round-robin using PeekNamedPipe and bounded ReadFile calls. The combined capture ceiling is 65,536 bytes, with 4,096-byte reads. Exact-boundary output is accepted; any additional byte produces an explicit CapExceeded result. Timeout, read failure, and output overflow terminate the Job Object, reap the root process, close owned handles, and preserve only bounded partial output marked incomplete. The descendant test verifies membership in the same Job Object before testing that whole-job termination ends it.

The dedicated workflow exercises separate streams, exact-cap and overflow cases, omitted-handle inheritance, timeout, an injected ReadFile failure after partial capture, descendant containment, handle cleanup, x64 structures, and ASCII/no-BOM source policy. It is a test fixture run by PowerShell/.NET P/Invoke, not by compiler-generated production code.

**Acceptance boundary:** the Phase 2B.5 source candidate is not a production broker change. It uses the caller token, inherits the CI environment (lpEnvironment=NULL), does not bind the Phase 2B.3 AppContainer ACL transaction to this child, and does not prove network/DLL-search isolation, production cancellation or durable evidence/restart recovery. The separate Windows Server 2025 clean-environment failure (ERROR_ENVVAR_NOT_FOUND, 203) remains BLOCKED. No production PE imports, compiler emitter, sh_dev_run_tool production path, merge, or release is authorized by this milestone. Model-facing process execution remains **DISABLED**.

**Enablement rule:** Phase 2B.5 completion alone does not enable model-facing or autonomous execution. A later production-integration milestone must close the clean-environment and loader/DLL-search gates, integrate restricted-token/AppContainer + per-execution workspace ACLs with the production broker, integrate the handle list/output cap with the production emitter, add cancellation and durable audit/restart recovery, pass same-head Windows adversarial and regression suites, and receive explicit owner approval for a limited allowlisted canary. General autonomy follows only after that canary is proven and a kill switch is operational. No calendar date is asserted; acceptance is gate-driven.
