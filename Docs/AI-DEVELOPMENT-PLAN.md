# Sharnou Compiler and Engine - Accepted Development Plan

**Last maintained:** 2026-11-20  
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
