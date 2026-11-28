# Sharnou Compiler and Engine - Accepted Development Plan

**Last maintained:** 2026-11-20 22:49 Africa/Cairo
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

The branch currently contains a Stage 7A implementation and test runner. The current README identifies eight positive example cases and twelve negative parser/type cases, plus instruction-encoding checks. This does not by itself prove the user's Windows acceptance run; see the session-state and issue register.

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
| Milestone 7A source implementation | Present on current repository branch; Windows acceptance status not yet confirmed in this session |
| Milestone 7A full regression/ABI verification | Pending |
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

Current status: ARCHITECTURE RECORDED; IMPLEMENTATION NOT STARTED; LOCAL INFERENCE NOT BUILT; AUTONOMOUS REPAIR NOT RUN. Acceptance requires offline operation without AI provider credentials, durable restart recovery, process isolation and timeouts, source-hash/evidence journals, passing security/rollback tests, and Windows runtime evidence.


## 11. User-approved advanced bug research and escalation - 2026-11-27

The user has made advanced bug-resolution research a required SharnouDevAgent capability. This extends the autonomous-agent scope; it does not mean the capability is already implemented.

Required workflow for a hard defect:
1. Reproduce the failure and persist the exact source commit, compiler/runtime identity, Windows environment, error/exit code, relevant logs, expected/actual behavior, and a minimal failing test or reduced fixture.
2. Search local source/history/tests and current official documentation, specifications, and upstream issue trackers. Use bounded HTTPS research with source-host policy, redirect/response limits, timestamps, provenance, and citations.
3. When local diagnosis remains unresolved, consult configurable OpenAI and Perplexity developer APIs independently or comparatively. OpenAI integration should use the official Responses API and web-search tool where appropriate. Perplexity integration should use its current documented Agent API and/or Search API. Verify current endpoints, authentication, request/response schemas, models, quotas, and pricing from official documentation during implementation.
4. Do not automate consumer ChatGPT/Perplexity browser sessions, store account passwords/cookies, scrape private sessions, bypass access controls, or treat a ChatGPT subscription as API credentials. Use official developer APIs or approved public search endpoints.
5. Redact secrets, personal data, machine identifiers, private paths, unrelated proprietary source, and credentials before external submission. Keep provider keys outside source control in the protected Windows credential boundary. Enforce opt-in and minimum-context disclosure for private source.
6. Treat web results, provider diagnoses, and generated patches as untrusted evidence. Verify claims against primary sources and local reproduction. Model output cannot grant permissions or execute tools directly; all actions pass the existing typed tool broker and policy engine.
7. Require two independent evidence paths for security-sensitive or high-impact bugs. Record disagreements, confidence, assumptions, unresolved questions, citations, and retrieval timestamps.
8. Enforce per-provider timeouts, retries/backoff, rate-limit handling, cache freshness, request/token/cost budgets, host allow/deny lists, citation checks, and safe fallback when a provider is unavailable.
9. Implement credential-free mock contract tests and live-provider tests only when valid credentials are explicitly provisioned. Acceptance must cover provider 401/timeout/rate-limit/malformed response, adversarial instructions, redaction, provider disagreement, stale/missing sources, budget exhaustion, and an end-to-end reproduced-failure -> research -> minimal patch -> regression -> Windows verification -> pull-request workflow.

Provider consultation is an escalation channel, not a prerequisite for every task. Sharnou must continue safe local/offline work when providers are unavailable. The compiler generates the agent executable; configured AI services provide model reasoning. Neither should be described as the other.

Implementation dependency: complete the safe native runtime transport/JSON/secret boundary, durable task/evidence journal, typed broker, isolated patch workflow, and Windows verification gates before enabling model-facing source modification. This research capability is REQUIRED in the final autonomous agent definition of done, but remains NOT IMPLEMENTED until code, tests, provider contracts, and end-to-end evidence exist.

## 12. User-approved compiler and Engine delivery scope - 2026-11-27

The user has explicitly confirmed the following milestones as required delivery scope. This supersedes earlier historical notes that described 7B as unaccepted scope. This is approval of the deliverables, not approval of any existing PR, not acceptance of its code, and not evidence that a milestone is complete.

### Compiler language and native ABI gates

- **7B:** Boolean semantics; logical operators with runtime short-circuit behavior; break; continue; nested returns. Tests must include dynamic-variable-left AND/OR skip and evaluate paths, nested loop target behavior, Boolean ABI rejection until supported, and verified branch destinations.
- **7C:** Primitive types, structs, pointers, arrays, slices, and explicit memory ownership/lifetime rules, with positive, negative, boundary, and verifier tests.
- **7D:** Typed intermediate representation and a verifier that rejects malformed or invalid IR before code generation.
- **7E:** Windows x64 ABI correctness, PE hardening, unwind metadata, and stack probing, with runtime and independent-verifier evidence.

The old PR #5 remains only a candidate implementation: it is open/unmerged, stale against the current default branch, and its 32-case 7B suite does not run the frozen 83-case baseline or the additional dynamic-left/branch-target tests. Do not merge or copy it automatically. The accepted 7B scope must be implemented or reconciled on a fresh isolated branch after the baseline and ABI dependencies are verified. Require the frozen 83-case suite, current Stage 7A suite, and expanded 7B suite on the same exact Windows-tested commit before calling 7B accepted.

### Engine and Honour War acceptance gates

- **8 / D3D11 geometry:** Native vertex and index buffers and actual indexed-triangle pixels rendered by the real Sharnou Engine executable.
- **9:** Runtime shaders, depth buffer, camera, and 3D transformation pipeline.
- **10:** Runtime textures, PBR materials, lighting, and shadows.
- **11:** glTF/GLB scene and model loading, KTX2 material textures using KHR_texture_basisu, and skeletal animation.
- **12:** Terrain, particles, atmosphere, and measured rendering optimization.
- **13:** Integrated MMORPG camera, characters, combat systems, and world rendering in Honour War.

These are user-approved required outcomes, not currently completed milestones. Source scaffolding, headers, clear/present-only tests, policy checks, and roadmap documents do not satisfy the runtime acceptance criteria. Preserve the runtime asset roles already defined in this plan: glTF/GLB for 3D scenes/models, KTX2 with KHR_texture_basisu for 3D material textures, and AVIF for 2D/UI raster visuals.

### Autonomous Sharnou AI Development Agent

The Sharnou-compiled persistent AI development agent and the advanced bug-research/escalation capability in sections 8 and 11 are also approved required product scope. The final agent must be compiled from Sharnou-language source to a genuine native Windows x64 executable, operate on a configured persistent host, recover durable work after restart, use constrained repository tools, and create evidence-backed pull requests. It must support public Internet research and optional OpenAI and Perplexity developer-API consultations for difficult bugs, with secret redaction, bounded budgets, independent verification, and the same policy gates as local actions.

### Current disposition

- Scope: **USER-APPROVED** for 7B-7E and 8-13, plus the autonomous AI agent and research escalation.
- Implementation: **PENDING**; no milestone is marked complete by this approval.
- Existing PRs: remain open/unmerged unless separately reviewed; this automation must not merge them.
- Dependency order: verify and integrate the frozen M1-M6 baseline/provenance and ABI gates; complete 7B-7E; implement the native runtime and safe process/research interfaces; generate and validate the Sharnou-compiled agent; then complete Engine geometry through world-rendering milestones and integrate Honour War when its prerequisites pass.


## Phase 2B.8 R5.1 qualification status - 2026-11-28

R5.1.a and R5.1.b have passed their bounded exact-head Windows qualification on stacked draft feature branches; neither is integrated into the default branch and neither establishes a running SCM authority service.

- **R5.1.a relocation primitive:** PR #33, exact head `2583faec76d5e469962756d17d2ffabecd6fcd98`; Windows run [46066382172](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46066382172) SUCCESS; relocation suite 21/21, Stage 7A 24/24, frozen M1-M6 83/83, combined PASS. Evidence artifact 15231785189, SHA-256 `698ebd55dfb66b529cd8b001aa986e4832e995e8f37a68f7906c7db19546b725`.
- **R5.1.b typed callback pointers/Win64 ABI:** PR #35, exact head `ab00219f1aa9783c148035b754eebce7269f6fbb`; Windows run [46070065850](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46070065850) SUCCESS; focused callback ABI probe PASS, Stage 7A 24/24, frozen M1-M6 83/83, exact-head manifest PASS. Evidence artifact 15232513039, SHA-256 `b246b9e588d06c956ce59ea6583b7da99f1d9a02f3e35df50e8a5fc9a99ed10f`.
- The R5.1.b manifest states `native_scm_service_implemented=false`. The callback intrinsic remains test-only and opt-in; no native SCM service executable has been generated or run.
- **Next required implementation:** R5.1.c, a genuine inert SCM service image compiled from Sharnou source. It must use exact typed callback signatures, bounded lifecycle state, a verified final PE import table/relocation/exception directory, and disposable Windows SCM installation/start/stop tests. No pipe, key, journal, profile mutation, or child execution belongs in R5.1.c.
- **Next qualification:** R5.1.d must test actual SCM start, SERVICE_RUNNING, STOP/SHUTDOWN/INTERROGATE, STOP_PENDING/STOPPED, initialization failure injection, repeated stop/start, forced termination, process exit, and handle cleanup. R5.2 service SID/CNG key implementation must wait until R5.1.c and R5.1.d pass; R5.3 transport must wait until R5.2 passes.
- PR #36 records R5.2/R5.3 design only and does not waive R5.1.c/.d. The Low-IL AppContainer DPAPI subtest remains INCONCLUSIVE because the Windows PowerShell runner could not load `System.Security`; it is not accepted evidence.

This status overlay changes no milestone scope and does not approve merging any PR, installing a persistent service, enabling model-facing execution, or deploying an autonomous agent. Model-facing and autonomous execution remain DISABLED; Phase 2B.8 remains NOT SECURITY ACCEPTED.


## SharnouDevAgent automatic GFX campaign - 2026-11-28

The user has requested automatic generation, verification, repair and draft-PR submission for all eleven graphics milestones. The machine-readable campaign contract is Projects/DevAgent/GfxCampaign.v1.json, validated against Schemas/DevAgent/GfxCampaign.v1.schema.json; the operating contract is Docs/DEVAGENT-GFX-MILESTONE-AUTOMATION.md.

- Scope: GFX-0.1 through GFX-0.8 and GFX-A.1 through GFX-A.3.
- Existing drafts: GFX-0.1 PR #39; GFX-0.2 PR #41. They must be inspected/reconciled, not regenerated or assumed accepted.
- Campaign policy: isolated worktrees, bounded repairs, typed tools only, exact-head Windows evidence, physical-GPU captures where required, one draft PR per milestone, owner acceptance before downstream integration, no automatic merge/release.
- Current implementation: DGA-GFX-0.1 campaign contract only. The native DevAgent local inference runtime, typed patch/rollback engine, durable restart recovery, accepted process broker and native GitHub/Actions adapter are not implemented/qualified on default. The campaign activation state is therefore BLOCKED.
- Required DevAgent sequence: DGA-0.2 deterministic campaign/DAG/evidence validator; DGA-0.3 durable task journal; DGA-0.4 read-only repository/Actions adapter; DGA-0.5 genuine in-process local inference; DGA-0.6 typed patch transactions; DGA-0.7 qualified process broker and security gates; DGA-0.8 specialist orchestration/review/repair/evidence; DGA-0.9 campaign runner and draft-PR lifecycle.

This approval of the desired campaign outcome does not waive Phase 2B.8, enable model-facing process execution, authorize arbitrary commands, or authorize automatic merges/releases. No campaign milestone is marked complete by the manifest alone.


### DGA-GFX-0.1 campaign PR status - 2026-11-28

Draft PR #42 is open at exact head 3434994d90f603adf82d8460f0977af8b59eb15a, based on default HEAD 36b07383cb0ee1996298724202454eb8aec57d98. Static JSON and dependency-DAG reconciliation found 11 milestone IDs, no missing dependency references and no cycle. This remains a declarative campaign contract only; its executor is not implemented or activated. DGA-0.2 is next.


## DGA-GFX-0.2 - deterministic campaign validation and post-GFX-0.8 evolution

DGA-GFX-0.2 adds a deterministic Windows PowerShell 5.1 contract validator and planner for the GFX campaign. It validates the eleven milestone IDs and graph, strict object fields and policy invariants, PR branch topology (including stacked PR #41), exact-head Windows and physical-GPU evidence contracts, and explicit owner acceptance. The offline CLI produces readiness and blocker reasons but does not generate code or write to GitHub.

The campaign now explicitly continues after GFX-0.8 through primary-source research, provenance capture, reproducible measured baselines, versioned improvement proposals, independent review and human acceptance. It is a declared policy, not a claim that a research daemon is already running.


## DGA-GFX-0.3 - durable task journal and restart recovery

The next DevAgent persistence increment introduces immutable append-only event records, SHA-256 record chaining, deterministic task IDs, idempotent operations, a typed task-state machine, immutable hash-bound checkpoints, and crash/restart recovery. Windows PowerShell 5.1 tests exercise lifecycle replay, repeated recovery, checkpoint restore, idempotency conflicts and corruption detection.

This is a local data-persistence primitive only. It does not enable autonomous model execution, process launch, network research, GitHub writes or a background research service. Hash chaining detects tampering but is not an authentication boundary; service-owned ACLs and the separate Phase 2B.8/R5 controls remain required.


## DGA-GFX-0.3 - qualified durable DevAgent task memory

DGA-GFX-0.3 now has a Windows PowerShell 5.1-qualified append-only task journal, record hash chain, deterministic idempotency keys, immutable checkpoint chain and restart recovery. The final code/test head is 847e9e7c3c5b07d02ce2cb21aa56caac1293e4fa. Both push and PR Windows runs passed; 30 tests passed, 0 failed, with source encoding/BOM and CLI Initialize/Inspect checks passing.

Resume requires a committed durable checkpoint. Replay rejects record sequence gaps, altered event bodies and altered checkpoint bodies. Repeated recovery is idempotent. This layer provides bounded task progress state, not model-conversation storage, an authenticated trust store, or an active background worker. Its Local named mutex coordinates within one Windows logon session only. Service-owned ACLs and Phase 2B.8/R5 gates remain separate prerequisites.
