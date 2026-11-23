# Sharnou Compiler, Runtime, Engine, and Game Roadmap

Status: Canonical forward development plan
Version: 1.0
Target: Windows x64 first, AMD64 PE32+, Direct3D 11 / DXGI
Bootstrap: PowerShell 5.1 and .NET, followed by a native Sharnou compiler
Policy: No MSVC, Clang, Visual Studio, external assembler, or external linker

This document defines the staged path from the current Stage 0 bootstrap to a self-hosted Sharnou compiler, its standard library and runtime, Sharnou IDE integration, a production-capable Sharnou Engine, and Honour War. It is a plan and status record, not a declaration that future stages are already implemented.

The renderer-specific target and its rendering subsystem gates remain in Docs/Renderer-Roadmap-3D-MMORPG.md. The native source and asset-format rules remain in Docs/FileFormats.md.

## 1. Product objective

The end state is a controlled, reproducible development stack in which Sharnou tools build Sharnou software:

1. Sharnou Language: a purpose-built systems and game-development language.
2. Sharnou Compiler: a self-hosted native x64 compiler, code generator, and PE32+ linker.
3. Sharnou Standard Library and Runtime: memory, strings, collections, diagnostics, files/assets, windowing, input, threading, synchronization, and graphics bindings.
4. Sharnou IDE: project editing, source navigation, diagnostics, builds, asset inspection, launch, debugging, and profiling.
5. Sharnou Engine: scene, entity, geometry, material, rendering, animation, world, audio, and gameplay foundations.
6. Honour War: the first full third-person MMORPG/ARPG project built on the Sharnou stack.

The first supported native target is Windows x64. Other operating systems and consoles are separate targets requiring separately designed platform and ABI backends. A Windows D3D11 executable is not a portable console build.

## 2. Non-negotiable engineering constraints

- The Stage 0 PowerShell/.NET bootstrap is permitted as the initial seed only.
- The native Sharnou compiler must eventually compile Sharnou source without invoking an external compiler.
- Sharnou owns x64 code generation, PE image construction, symbol resolution, imports, relocations, and verification.
- Do not invoke MSVC, Clang, Visual Studio, MSBuild, an external assembler, or an external linker.
- Do not download or install a compiler toolchain to make a test pass.
- Windows system DLLs may be called through explicit, verified imports. API presence and behavior must be checked at runtime.
- Reject unsupported language syntax, ABI types, PE layouts, imports, and asset formats. Do not silently lower unsupported constructs.
- Keep source, examples, test fixtures, and documentation in plain ASCII where required by the project handoff; native Sharnou text formats follow Docs/FileFormats.md (UTF-8 without BOM, LF only, final LF).
- Do not commit generated executables, object files, libraries, or other build outputs as source.
- A feature is complete only when the implementation, positive tests, negative tests, native Windows runtime tests, and evidence are recorded.
- Static byte scans and PE parsing do not replace launching the executable and checking its behavior.

## 3. Checked-in baseline and evidence status

The following status distinction is mandatory:

- Repository-verified: present in the default branch and supported by a recorded repository test or workflow.
- Owner-reported: the user reports that the milestone passed on their Windows PC; the current repository does not necessarily contain the original full test suite.
- Planned: not implemented or not yet supported by the checked-in acceptance tests.

| Area | Current status | Evidence and limitation |
|---|---|---|
| Stage 0 bootstrap | Repository-verified source | Stage0/SharnouCompiler.ps1 is the PowerShell/.NET seed and emits AMD64 PE32+ images directly. |
| Lexer/parser and early language | Owner-reported accepted | Earlier local milestone acceptance is project history; keep its original positive and negative cases under regression. |
| Runtime x64 arithmetic and stack variables | Owner-reported accepted | Earlier local tests reported native ADD, SUB, IMUL, IDIV, stack-backed values, and mutation. |
| Functions, modules, and PE writer | Owner-reported accepted | Earlier local acceptance covered functions, module resolution, four-section PE output, and relocation metadata. |
| Standard-library and Engine foundations | Owner-reported accepted | Earlier local acceptance covered memory, strings, files/assets, logging, collections, windowing, and threading. |
| D3D11/DXGI clear renderer | Owner-reported accepted | Earlier local acceptance covered a real window, device/swap-chain, render target, and bounded clear/present loop. This is not geometry rendering. |
| Milestone 7A control flow | Merged and repository-verified | PR #3 was merged on 2026-11-17. Windows workflow run 44177326789 completed successfully. The checked-in Stage 7A suite covers eight runtime positives, twelve negative cases, and three instruction checks. |
| Historical 83-case Milestone 6 suite | Owner-reported, not fully repository-reproducible | The earlier 83-case suite and all of its fixtures are not present in this repository tree. Restore them before claiming that the full historical baseline is continuously re-run by GitHub Actions. |
| Native Sharnou-written compiler | Planned | No complete self-hosted compiler source or bootstrap fixed-point proof is currently checked in. |
| Full production renderer and Honour War | Planned | See the renderer roadmap and the separate Honour War project. A D3D11 clear test is not a complete renderer or game. |

The 7A workflow proves that the checked-in control-flow test job passed on its Windows runner. It does not prove that the missing historical 83-case suite was rerun in that workflow.

## 4. Compiler development track

### C0 - Baseline recovery and regression consolidation

Objective: make every previously accepted capability reproducible from this repository.

Deliverables:
- Import the complete historical Stage 2 through Stage 6 test harnesses and all fixtures, preserving their original expected behavior.
- Keep the 7A control-flow tests and PE verifier in the default build/test workflow.
- Create one top-level test runner with named suites, per-case PASS/FAIL output, exact counts, and actionable diagnostics.
- Record the current bootstrap compiler SHA-256 and a versioned language/ABI contract.
- Separate repository CI evidence from owner-reported local evidence in the status document.

Acceptance:
- The restored historical suite reproduces the stated 83-case baseline.
- The 7A suite passes in the same Windows x64 job.
- Test accounting equals the number of declared tests; no false PASS summary is possible.
- All negative compiler tests reject input and leave no executable behind.
- The test workflow has no unreviewed external compiler or linker dependency.

### C1 - Complete control-flow semantics (after 7A)

Objective: make control flow sufficiently expressive and fully specified for compiler implementation.

Deliverables:
- Boolean values and explicit truth conversion rules.
- Logical NOT, AND, and OR with documented short-circuit behavior.
- Break and continue with correct nested-loop targets.
- Return from nested blocks with correct epilogues and stack restoration.
- Else-if as defined syntax or an explicitly documented nested-if-only policy.
- Definite assignment, unreachable-code diagnostics, and consistent lexical-scope rules.
- Signed and unsigned comparison semantics once unsigned integer types exist.

Acceptance:
- Positive and negative tests for nested branches, nested loops, short-circuit side effects, break/continue, nested returns, and scope visibility.
- Boundary tests for INT32_MIN, INT32_MAX, zero, and unsigned boundaries when available.
- Disassembly/byte-pattern tests plus executable behavior tests.
- Windows x64 stack alignment and shadow-space tests for calls from every control-flow path.

### C2 - Type system and data representation

Objective: add the data model needed by a compiler, runtime, and engine without guessing at layout.

Deliverables in dependency order:
1. Explicit primitive types: bool, signed/unsigned 8/16/32/64-bit integers, and documented size/alignment rules.
2. Explicit pointer and handle types, null representation, and unsafe/native boundary rules.
3. Fixed-size arrays, slices/spans, and bounds-checked indexing.
4. Structs with stable field offsets, padding, alignment, and layout inspection.
5. Enums and bit flags with explicit underlying types.
6. Function pointers and callback signatures using a documented Windows x64 ABI subset.
7. Constant evaluation, casts, and overflow behavior specified per type.

Acceptance:
- Layout tests compare compiler-reported offsets and sizes with generated runtime probes.
- Negative tests cover invalid casts, overflow, out-of-bounds access, invalid pointer operations, and ABI mismatches.
- Every native boundary has a precise width, signedness, alignment, and ownership contract.
- No implicit C/C++ ABI compatibility is claimed beyond explicitly implemented signatures.

### C3 - Stable intermediate representation and backend contracts

Objective: stop coupling language parsing directly to PE emission.

Deliverables:
- A documented typed intermediate representation (IR).
- Explicit basic blocks, terminators, branches, calls, loads, stores, and returns.
- Symbol tables, source locations, and module dependency identities carried through lowering.
- A baseline non-optimizing x64 backend first.
- Verified instruction encoder helpers and range-checked branch/call fixups.
- Later, independently testable constant folding, dead-code elimination, and local value simplification.

Acceptance:
- AST-to-IR tests and IR verifier tests.
- IR-to-x64 tests for every supported operation and addressing mode.
- Differential tests that compare optimized and unoptimized native program behavior.
- Fail-closed behavior for an IR operation without a defined backend lowering.

### C4 - Native ABI, linker, and PE production hardening

Objective: make native output dependable for larger compiler and engine programs.

Deliverables:
- One written Windows x64 ABI specification for arguments, returns, volatile/nonvolatile registers, stack alignment, shadow space, aggregates, callbacks, and error returns.
- Complete module symbol resolution and import declaration checking.
- PE32+ section and data-directory validation, import and IAT bounds, base relocations, and deterministic section placement.
- Windows x64 unwind metadata in .pdata/.xdata for functions that require stack unwinding.
- Stack probing for large stack frames and explicit stack-frame size limits.
- Runtime exception/error policy that does not rely on undefined behavior.
- Optional debug metadata only after a documented format and verifier exist.
- Deterministic PE output, or a narrowly specified normalization policy for fields that are intentionally variable.

Acceptance:
- Windows loader execution tests for each PE feature.
- Positive and deliberately corrupted PE files for headers, section ranges, imports, relocations, and unwind metadata.
- ABI stress tests with nested calls, recursion after recursion support, many live temporaries, and all supported argument classes.
- No PE image is called valid solely because the compiler wrote it; the independent verifier and Windows loader both have to accept it.

### C5 - Sharnou-written compiler frontend and IR

Objective: implement the language frontend in Sharnou source.

Suggested source layout:
- Compiler/Core: diagnostics, source buffers, spans, interning, and common utilities.
- Compiler/Lexer: token kinds, scanner state, comments, literals, and lexical errors.
- Compiler/Parser: recursive-descent parser and syntax tree construction.
- Compiler/AST: node definitions and traversal.
- Compiler/Types: primitive types, symbol tables, scopes, and type checking.
- Compiler/Semantics: name resolution, imports, definite assignment, and diagnostics.
- Compiler/IR: typed IR construction and verification.
- Compiler/Driver: command-line parsing, build orchestration, and diagnostics output.

Design requirements:
- Keep each compiler subsystem testable independently.
- Use explicit limits and checked allocation until the native allocator is fully proven.
- Avoid using unsupported language features inside the compiler itself.
- Keep the Stage 0 bootstrap source and hash frozen for each bootstrap generation.
- Keep compiler diagnostics deterministic and include file, line, and column.

Acceptance:
- Stage 0 compiles the Sharnou-written compiler source into a native SharnouCompiler.exe.
- The generated compiler can compile all existing test fixtures and examples.
- Frontend tests run against both the Stage 0 and native compiler paths and produce equivalent diagnostics/AST or IR fingerprints.

### C6 - Self-hosted x64 backend and linker

Objective: move code generation and PE linking into the Sharnou-written compiler.

Deliverables:
- Sharnou machine-instruction encoder.
- Register/stack-location policy with documented liveness and spill behavior.
- Branch and RIP-relative fixups with signed displacement range checks.
- PE32+ section writer, imports, relocations, image sizing, and independent verification.
- Native command-line driver supporting source root, output path, include roots, diagnostics, and fail-closed exit codes.
- No hidden fallback to the PowerShell emitter once the native backend is selected.

Acceptance:
- Stage 0 compiles the native compiler (Stage 1).
- Stage 1 compiles the same compiler source (Stage 2).
- Stage 2 compiles it again (Stage 3).
- Deterministic builds produce matching SHA-256 values. If any output field is intentionally variable, the comparison must normalize only that documented field and compare all executable sections, imports, relocations, and behavior.
- Stage 1, Stage 2, and Stage 3 each pass the same regression suite.
- The bootstrap chain, inputs, output hashes, and test logs are recorded.

### C7 - Self-hosted compiler release

Objective: make the native compiler the normal developer tool.

Deliverables:
- A pinned Stage 0 bootstrap archive and hash for recovery.
- A reproducible native compiler release package.
- A compiler version and language-version policy.
- Backward-compatible CLI and project-format policy.
- A no-external-tool validation workflow on a Windows runner.
- A rollback procedure if a new native compiler cannot rebuild itself.

Acceptance:
- A clean checkout can bootstrap the compiler using only the documented Windows-provided seed.
- The resulting native compiler rebuilds itself and all compiler tests.
- No MSVC, Clang, Visual Studio, external assembler, external linker, or downloaded compiler is invoked.
- The pinned bootstrap and every output have auditable SHA-256 values.

## 5. Runtime and standard-library track

This track depends on C2 type/layout contracts, C3 IR, and the ABI/linker gates in C4.

### R1 - Memory and ownership

- Define allocation, reallocation, free, alignment, and out-of-memory behavior.
- Provide arena, pool, and general-purpose allocator interfaces.
- Specify ownership, borrowing, lifetime, aliasing, and thread-safety rules.
- Add leak/double-free/use-after-free diagnostics where the chosen runtime model permits them.
- Keep per-frame and per-asset memory budgets measurable.

### R2 - Strings, paths, and collections

- Define UTF-8 string representation and byte/code-point behavior.
- Add immutable and mutable string operations with capacity checks.
- Add dynamic arrays, slices, maps, queues, and typed collections.
- Add path normalization and root-containment checks consistent with Docs/FileFormats.md.
- Add deterministic serialization and hashing.

### R3 - Files, assets, and diagnostics

- File handles, synchronous/asynchronous reads, writes, flush, and error mapping.
- Bounded streaming reads and verified SHA-256 asset intake.
- Structured logging with severity, categories, timestamps, and optional sinks.
- Diagnostics with source spans, call stacks where available, and stable error codes.
- Cache metadata and corruption recovery rules.

### R4 - Platform, window, input, threading

- Stable Win32 window creation, resize, minimize/restore, close, DPI, and event dispatch.
- Keyboard, mouse, controller, and raw-input abstraction.
- Thread creation, joining, events, mutexes, condition variables, atomics, and thread-safe queues.
- Callback lifetime and thread affinity rules.
- Shutdown sequencing and resource ownership tests.

Acceptance for R1-R4:
- Every API has positive and negative tests, a documented ABI, bounds tests, and failure-injection paths.
- All handles are closed exactly once on success and error paths.
- No API silently returns success after partial failure.

## 6. Sharnou Engine and rendering track

The existing D3D11 clear/present milestone is the platform bootstrap only. The accepted detailed design is Docs/Renderer-Roadmap-3D-MMORPG.md. Its phases are retained and expanded here into compiler dependencies.

### E1 - Platform and graphics lifecycle

- Centralized ownership of HWND, DXGI factory/swap chain, D3D11 device/context, back buffer, RTV, depth buffer, and device-dependent resources.
- Correct resize/minimize/restore and render-target recreation.
- HRESULT validation and diagnostics for all device/resource calls.
- Device-removed/reset detection and resource recreation policy.
- Deterministic shutdown and COM release accounting.

### E2 - First actual geometry renderer

- Vertex/index buffer creation and validation.
- Vertex layouts and input assembler state.
- Vertex and pixel shader loading/creation.
- Constant buffers and matrix conventions.
- Depth testing, viewport, rasterizer state, and indexed draw.
- Render a triangle, then a lit procedural mesh.
- Capture a real runtime frame and validate non-clear pixels.

A swap-chain clear or a screenshot of a blank window does not pass E2.

### E3 - Scene and asset pipeline

- Scene graph/entity model, transforms, cameras, bounds, visibility, and resource handles.
- glTF 2.0/GLB parsing with explicit required-extension checks.
- KTX2 container validation and a supported Basis Universal transcode path.
- AVIF image capability detection and a supported decoder path; never assume every Windows installation includes an AVIF codec.
- Asset manifests, SHA-256 verification, cache, streaming, and offline cached launch.

The canonical format policy is Docs/FileFormats.md. Do not repurpose AVIF for 3D geometry or KTX2 as a scene format.

### E4 - Materials, lighting, and shadows

- Metallic-roughness PBR with explicit linear/sRGB texture semantics.
- Base-color, normal, roughness, metallic, AO, and emissive channels.
- Directional, point, and spot lighting with stable units and budgets.
- Cascaded directional shadows, bias, filtering, and transitions.
- Material validation and fallback policy for optional maps.

### E5 - Characters and animation

- Skeletons, joints, inverse bind matrices, and skin-weight validation.
- Animation clips, interpolation, root-motion policy, blending, and state machines.
- GPU skinning and animation LOD.
- Character test scenes and runtime captures.

### E6 - World and rendering scale

- Terrain chunks, asynchronous streaming, LOD, frustum culling, spatial partitioning, and bounded caches.
- Particles and atmosphere.
- HDR render targets, tone mapping, bloom, color grading, and optional screen-space effects.
- GPU instancing, batching, and measurable renderer budgets.

Acceptance:
- Each E phase includes a real Windows executable, deterministic scene/asset fixtures, runtime capture, output/pixel checks where stable, and CPU/GPU profiling.
- Renderer performance claims identify hardware, driver, scene, resolution, quality settings, and measurement method.

## 7. Sharnou IDE and project workflow

### I1 - Compiler integration

- Stable compiler CLI, structured diagnostics, cancellation, and exit-code contract.
- Project graph and incremental build dependencies.
- Build profiles and reproducible build manifests.
- Run/debug launch and capture of stdout, stderr, exit status, and crash status.

### I2 - Language-aware editing

- Syntax highlighting and grammar versioning.
- Diagnostics and source navigation.
- Symbol search, references, rename, and module dependency views.
- Completion only for symbols with compiler-provided semantic information.

### I3 - Debugging and profiling

- Source-to-machine mapping and a documented debug metadata format.
- Breakpoints, stepping, call stack, locals, memory/register views, and exception diagnostics.
- CPU frame and job profiling; GPU event/timing and resource inspection.
- D3D11 frame capture and render-target inspection.

The IDE must call the Sharnou compiler/runtime contracts. It must not shell out to an unapproved compiler or linker.

## 8. Honour War integration track

Honour War is a consuming project, not a reason to weaken compiler or engine correctness gates.

Integration order:
1. Canonical project file and reproducible Sharnou IDE build.
2. Native Engine startup, logging, configuration, and resource lifecycle.
3. Character data, class definitions, equipment, and inventory.
4. Camera, input, movement, animation, and combat test map.
5. World/terrain streaming and environment art.
6. Skills, enemy AI, loot, progression, quests, and UI.
7. Networking, authoritative server simulation, persistence, and reconnect behavior.
8. Content pipeline, patching, asset hash validation, and offline cached operation.
9. Performance, security, accessibility, and platform validation.
10. Playable vertical slice, then complete game production.

Every gameplay system requires a playable test scene and automated logic tests where practical. MMORPG networking must define authority, replication frequency, prediction/reconciliation, persistence boundaries, abuse limits, and server failure behavior before production content depends on it.

## 9. CI, test evidence, and release gates

Required CI lanes on supported Windows x64 runners:

1. Source encoding and repository policy.
2. Lexer/parser and semantic tests.
3. IR verification and backend instruction tests.
4. ABI and native execution tests.
5. PE verifier positive/negative corpus.
6. Module/import and linker tests.
7. Standard-library unit and Windows API integration tests.
8. Window/D3D11 tests in an interactive desktop-capable runner; headless runners must mark this lane unavailable, not green.
9. Renderer runtime tests and image/frame capture.
10. Self-host bootstrap and fixed-point rebuild tests.
11. IDE integration tests.
12. Honour War smoke and vertical-slice tests.

Every test runner must:
- Print one unambiguous result per case.
- Derive counters from the same result value used for the label.
- Fail if a test was skipped unexpectedly or the actual count differs from the declared count.
- Include expected versus actual output, exit code, and diagnostic text on failure.
- Remove stale output before compilation and ensure failed compilation leaves no executable.
- Preserve the previous known-good compiler and test reports.
- Never fabricate a test result, executable, screenshot, hash, or compiler capability.

Release packages must include source identity, compiler hash, package hash, manifest, test report, and supported target statement. Generated binaries are release artifacts, not normal source-tree content.

## 10. Milestone dependency order

The following order prevents engine or IDE work from depending on unstable compiler behavior:

| Order | Milestone | Depends on | Exit gate |
|---|---|---|---|
| 0 | Restore and pin historical regression baselines | Current repository | Historical tests reproducible |
| 1 | 7A control flow | Existing parser/backend | Merged; Windows CI success |
| 2 | 7B complete flow semantics | 7A | Nested flow, logical operators, break/continue tests |
| 3 | 7C types and layouts | 7B | ABI/layout and bounds tests |
| 4 | 7D IR and native backend contracts | 7C | IR verifier and native differential tests |
| 5 | 7E PE/linker/unwind hardening | 7D | Independent verifier and Windows loader tests |
| 6 | 7F Sharnou compiler frontend/IR sources | 7B-7E | Stage 0 builds compiler modules |
| 7 | 8A self-host native compiler | 7F | Stage1/Stage2/Stage3 fixed-point proof |
| 8 | 8B native compiler release | 8A | Clean bootstrap and no external compiler |
| 9 | 9 standard library/runtime consolidation | 7C-8B | API, ownership, and error-path tests |
| 10 | 10 Engine platform/geometry | 9 | Real indexed geometry rendered |
| 11 | 11 asset pipeline/PBR/animation/world | 10 | Integrated imported-model scene |
| 12 | 12 IDE compiler/debug integration | 8B-11 | Build/run/debug/profile workflow |
| 13 | 13 Honour War vertical slice | 10-12 | Playable end-to-end slice |
| 14 | 14 full production and release | 13 | Performance, stability, content, and operations gates |

Milestone labels may evolve as implementation is split into reviewable pull requests. Do not renumber historical accepted milestones or represent a planned gate as completed.

## 11. Immediate execution queue

The next engineering work should be done in this order:

1. Restore and pin the missing historical 83-case suite and fixtures in the compiler repository.
2. Confirm that merged 7A code and all restored historical cases pass together on the same Windows runner.
3. Specify and implement 7B semantics: boolean values, short-circuit logical operators, break, continue, and nested return.
4. Specify the C2 type/layout model before adding structs, pointers, arrays, and function pointers.
5. Introduce typed IR and verifier tests before implementing optimization.
6. Implement Windows x64 unwind metadata and stack probing before compiler-generated code uses large frames or features requiring unwinding.
7. Only then begin the Sharnou-written compiler frontend and bootstrap chain.

Do not skip directly from 7A to a self-hosting claim. The compiler must first have enough typed data structures, allocation, control flow, and file output to express its own frontend and backend.

## 12. Definition of done for the complete program

The compiler roadmap is complete only when all of the following are demonstrated:

- A native SharnouCompiler.exe is built from Sharnou compiler source using the pinned Stage 0 seed.
- The native compiler rebuilds itself through at least two subsequent stages and passes the same regression suite.
- All native code generation and PE linking are performed by Sharnou-owned code.
- The standard library and runtime cover the documented engine APIs with ownership and ABI contracts.
- Sharnou IDE builds, diagnoses, runs, debugs, and profiles Sharnou projects using that native compiler.
- Sharnou Engine renders imported 3D assets with the documented materials, lighting, animation, world, and post-processing capabilities.
- Honour War runs as a real playable project on the supported target.
- CI and local validation produce reproducible evidence, with no external compiler, assembler, or linker in the build chain.

Until those gates have passed, the roadmap remains open. A successful compiler milestone, a D3D11 clear window, or a self-hosting prototype is not by itself completion of the full Sharnou development stack.
