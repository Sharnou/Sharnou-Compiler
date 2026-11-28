# GFX-0.1 — Sharnou Graphics Compiler and Analysis Architecture

**Status:** Draft architecture proposal; not implemented and not yet accepted.
**Date:** 2026-11-28
**Platform baseline:** Windows x64, Direct3D 11, DXGI.
**Product target:** Sharnou Compiler + Sharnou IDE + Sharnou Engine + Honour War.
**Scope boundary:** Architecture, contracts, and acceptance plan only. No compiler, GPU backend, renderer feature, or asset-analysis capability is claimed complete by this document.

## 1. Objective

Build a first-party Sharnou Graphics Compiler and Analysis System (SGCAS) that turns shader source, material declarations, scene assets, and renderer pipeline descriptions into verified GPU programs and actionable diagnostics. The system must become a native part of the Sharnou compiler and IDE toolchain rather than a collection of external command-line utilities.

The goal is not simply to compile a shader. The toolchain must explain why a shader or asset is unsafe, unsupported, expensive, incorrectly bound, or incompatible with a target device before the game reaches runtime. It must also connect static findings to real GPU captures and measured frame costs.

SGCAS is a separate compilation domain from the existing native x64 compiler:

| Toolchain | Input | Output | Responsibility |
|---|---|---|---|
| Sharnou native compiler | Sharnou gameplay, engine, IDE and runtime source | AMD64 PE32+ executable/image | CPU instructions, Windows x64 ABI, imports, relocations and executable layout |
| Sharnou Graphics Compiler | Sharnou shader source and verified graphics IR | Target shader bytecode plus reflection/package metadata | Shader semantics, GPU-stage interfaces, resource bindings, optimization and target lowering |
| Graphics/asset analyzer | glTF/GLB, KTX2, material, animation and render-pipeline metadata | Diagnostics, normalized metadata and validation reports | Asset correctness, compatibility, resource cost and pipeline hazards |

A GPU shader blob is not a Windows PE executable and must never be passed to the native PE linker. Conversely, a PE image is not a shader program. The two build graphs meet only through an explicit, versioned renderer/runtime contract.

## 2. Proposed system architecture

```text
Sharnou project
  |
  +-- Sharnou source compiler ----------------------------> PE32+ engine/game/IDE
  |
  +-- Graphics asset intake
  |     +-- glTF / GLB scene and mesh analysis
  |     +-- KTX2 / Basis material texture analysis
  |     +-- material, skeleton, animation and image metadata
  |
  +-- Shader source (*.shshader)
  |     +-- lexer / parser / typed semantic analysis
  |     +-- source-mapped typed AST
  |     +-- SGIR/1 generation
  |     +-- SGIR verifier
  |     +-- target-independent optimization
  |     +-- target capability legalization
  |     +-- D3D11 lowering adapter
  |             +-- constrained HLSL generation
  |             +-- in-process D3DCompile API (proposed bootstrap adapter)
  |             +-- D3DReflect validation
  |
  +-- Shader package + reflection + content hashes
  |
  +-- Renderer pipeline / render-graph validation
        +-- D3D11 resource and pass binding
        +-- real device execution, captures and GPU timings
```

Logical components and interfaces must be separated even if the first implementation is hosted in a single Sharnou process. The compiler frontend must not depend on D3D11 objects. The D3D11 backend must consume verified SGIR and must not parse arbitrary source directly. The IDE must consume structured diagnostics and reflection metadata rather than scraping console output.

### 2.1 Component boundaries

| Component | Owns | Must not own |
|---|---|---|
| Shader frontend | Lexing, parsing, name resolution, type checking, source locations and stage declarations | GPU device/context lifetime or shader cache policy |
| SGIR builder/verifier | Canonical shader IR, control-flow graph, types, capabilities and invariants | HLSL text parsing or device calls |
| Optimization pipeline | Deterministic, verified transformations with pass-by-pass validation | Target driver behavior or implicit resource remapping |
| Target capability model | Required feature set, shader profile, stage/resource limits and unsupported-feature diagnostics | Silent downgrade of required effects |
| D3D11 backend adapter | SGIR lowering, HLSL emission, API compilation, reflection checks and bytecode packaging | Running external `fxc.exe`/`dxc.exe` processes |
| Asset analyzer | Structural validation, semantic metadata and cost estimates | Treating estimates as measured GPU timings |
| Renderer pipeline analyzer | Pass dependencies, attachment contracts, resource transitions/hazards and reflection compatibility | Allocating GPU resources during offline project analysis |
| IDE graphics workbench | Source navigation, diagnostics, bindings, asset inspection, preview and profiling views | Duplicating compiler semantics in UI code |

## 3. Shader language and source model

Proposed shader source extension: `.shshader`. The final grammar and syntax are deliberately deferred to GFX-0.3; this architecture does not freeze a source grammar before the type system and IR are reviewed.

Each shader module must declare:

- a stable module identity and schema version;
- one or more named entry points, each assigned to a specific GPU stage;
- explicit input/output structures and semantics;
- resource declarations with explicit set/binding or an equivalent stable binding key;
- constant-buffer layout and matrix-major convention;
- target capability requirements or a declared minimum capability profile;
- optional compile-time defines and include dependencies, all included in the build hash.

Initial stages are vertex and pixel. Geometry, hull, domain and compute stages may follow only when real renderer use cases and feature-level tests justify them. Mesh shaders, ray tracing, bindless descriptor models and vendor-specific extensions are not part of the initial D3D11 target.

Initial language semantics should favor predictable game shaders: explicit types, explicit resource declarations, no shader recursion, no implicit global mutable state, defined integer overflow behavior, explicit matrix conventions, and bounded resource arrays. The first grammar should avoid pretending to be full C++ or HLSL.

## 4. SGIR/1 — Sharnou Graphics Intermediate Representation

SGIR is a dedicated GPU-program IR. It is not the native compiler's CPU instruction IR and must use a distinct namespace, verifier, serialization version and diagnostics.

### 4.1 Required IR model

SGIR/1 should represent:

- module identity, version, entry point and shader stage;
- target-independent capability requirements;
- typed scalar, vector, matrix, array and structure values;
- explicit resource declarations and binding keys;
- explicit stage input/output interfaces;
- typed arithmetic, comparison, conversion, vector, matrix, texture-sample and control-flow operations;
- functions, basic blocks, branch edges and return values;
- source file/line/column mapping on declarations and instructions;
- reflection-relevant metadata such as resource type, array length, cbuffer field offsets and stage semantics.

The initial control-flow representation should be SSA-style: each value has one definition, blocks have explicit terminators, and merge values use validated phi nodes. Each optimization pass must preserve typing, control-flow validity, source provenance where possible, and declared stage/resource semantics.

### 4.2 Verifier invariants

The SGIR verifier must reject, before target lowering:

1. Unknown opcodes, unsupported schema versions or unknown mandatory capabilities.
2. Duplicate value IDs, invalid use-before-definition, invalid dominance, malformed phi inputs or unreachable malformed terminators.
3. Incompatible operand/result types, illegal vector widths, invalid matrix dimensions or implicit narrowing.
4. Branch targets outside the module, missing terminators, malformed loops or invalid return types.
5. Stage-incompatible operations, including derivative operations outside pixel-stage execution.
6. Mismatched vertex/pixel stage interfaces, duplicate semantics or incompatible interpolation declarations.
7. Duplicate resource bindings, invalid resource kinds, conflicting register mappings or cbuffer layout overflow.
8. Invalid constant-buffer packing, field alignment, array stride, matrix-major layout or CPU/GPU reflection disagreement.
9. Unsupported target features without an explicit diagnostic and no silent feature substitution.
10. Invalid source-map ranges, integer overflow in lengths/offsets or resource-array counts beyond validated limits.

Verifier failure must stop compilation. A malformed or unsupported shader must not produce a cache entry or a loadable package.

### 4.3 Determinism

The same source tree, compiler version, IR schema, target profile, entry point, defines, include contents and compile options must produce the same canonical SGIR hash and package identity. Hash inputs must be length-delimited and versioned; string concatenation without unambiguous boundaries is not acceptable.

## 5. Shader static analysis

The analyzer should run on the typed AST and verified SGIR. Every diagnostic must contain a stable code, severity, source span, concise explanation, affected entry point or resource, and a practical remediation. Warnings must not be silently promoted to success for a required correctness rule.

### 5.1 Semantic and correctness checks

- Type mismatch, implicit conversion, undefined/uninitialized value, invalid swizzle, illegal stage intrinsic, invalid texture sampling operation and incompatible sampler/resource type.
- Vertex-to-pixel interface mismatch, semantic collision, invalid interpolation or missing required position output.
- Constant-buffer packing, structure alignment, field offsets, matrix-major layout and CPU structure/reflection mismatch.
- Duplicate or overlapping bindings, register-space collision, invalid array size and unsupported resource type.
- Derivatives inside non-uniform control flow, invalid derivative stage, unsupported texture operation and unsafe implicit-LOD use.
- Loops that are unbounded or cannot be proven safe for the selected profile; recursion and unsupported dynamic resource indexing.
- Numeric hazards: division by zero where statically knowable, invalid normalization, precision loss, dangerous casts, NaN-sensitive branches and integer overflow where semantics are not defined.

### 5.2 Performance analysis

Static performance analysis must be explicitly labeled as an estimate, never as a benchmark. Candidate findings include:

- expensive texture sampling, unnecessary texture reads, excessive interpolators and oversized constant buffers;
- repeated expressions, redundant conversions, non-coherent branches and avoidable matrix work;
- large static loops, costly transcendental operations and excessive register-pressure proxies;
- shader permutation explosion and repeated identical shader compilation;
- material layouts that prevent batching or force avoidable state changes.

The analyzer must explain why it believes an operation is expensive and identify the source expression or IR instruction. It must not claim an exact GPU register count, occupancy, cycle count or frame-time prediction unless that information comes from a real target compiler/device capture.

## 6. Initial D3D11 backend strategy

The first renderer backend remains Direct3D 11 + DXGI, consistent with the existing renderer roadmap. The recommended bootstrap path is:

1. Sharnou parses and type-checks `.shshader` source.
2. Sharnou builds and verifies SGIR/1.
3. Sharnou performs target-independent optimization and capability checks.
4. The Sharnou D3D11 adapter lowers the supported SGIR subset to constrained HLSL source.
5. The adapter invokes the Microsoft `D3DCompile` API in-process, not an external compiler executable.
6. The adapter captures the bytecode blob and complete error/warning blob, then validates stage and profile.
7. The adapter runs `D3DReflect` and compares reflected inputs, outputs, resources, cbuffer sizes and offsets against Sharnou's expected layout.
8. Only a verified result is committed atomically to the shader cache/package.

`D3DCompile` is a documented API that compiles HLSL source into a bytecode blob and can return a diagnostics blob; `D3DReflect` obtains shader reflection metadata from the compiled shader. These APIs make a practical D3D11 bridge while Sharnou owns the source language, semantic model, IR, analysis, capability checks and package format. See [D3DCompile](https://learn.microsoft.com/windows/win32/api/d3dcompiler/nf-d3dcompiler-d3dcompile) and [D3DReflect](https://learn.microsoft.com/windows/win32/api/d3dcompiler/nf-d3dcompiler-d3dreflect).

### 6.1 Explicit dependency boundary

The in-process D3DCompiler library is a Microsoft graphics-compiler dependency, even though no external process is launched. It is a bootstrap adapter, not evidence that the complete GPU backend is first-party. Its use, target DLL version, redistributable/deployment policy, license terms and supported Windows availability must be approved and tested in a later implementation milestone.

At runtime, the engine must detect the exact required API/library and supported shader profile. It must not silently search arbitrary directories, download a compiler, invoke `fxc.exe` or `dxc.exe`, or switch to an unverified compiler. Missing or incompatible components produce a precise diagnostic and a fail-closed build result.

Do not assume that a D3D11 device supports every shader stage or profile. Query the actual device feature level/capabilities and reject unsupported stages before code generation. The initial quality baseline may require Feature Level 11_0 and Shader Model 5.0, with a separately tested lower-quality profile added only when the renderer explicitly supports it.

### 6.2 Driver compilation boundary

DXBC is a graphics API bytecode representation, not universal hardware machine code. The graphics driver still translates/compiles shader programs for the actual GPU architecture. The same distinction applies to SPIR-V: it is a portable shader intermediate binary, while driver-side register allocation and instruction scheduling remain target-specific. Sharnou should own deterministic shader semantics and target modules, but it must not claim to generate universal GPU ISA from a portable shader package.

Longer-term backends may include D3D12/DXIL and Vulkan/SPIR-V as independent target adapters. DXIL has its own LLVM-IR subset and versioned shader contract; it is not an interchangeable D3D11 bytecode mode. SPIR-V is a structured intermediate binary with SSA-style operations, and validation/target support must be version-pinned. Neither backend should be started until the D3D11 pipeline is correct and measured.

## 7. Graphics asset analyzer

Asset analysis is a first-class part of the same graphics toolchain, but it is not the shader compiler. Its output is a structured asset manifest consumed by the engine and IDE.

### 7.1 glTF / GLB mesh and scene validation

Validate container/version, JSON or GLB chunk structure, buffer/view/accessor ranges, alignment, index bounds, supported topology, node parentage, transform validity, material references, duplicate or missing IDs, and required extensions. Reject unsupported required extensions instead of silently omitting content.

Geometry checks should include missing/invalid positions, normals, tangents, UVs, invalid indices, degenerate triangles, non-finite values, bounds, normal/tangent consistency, unexpected winding, vertex attribute stride, joint index bounds, skin weights, inverse-bind matrices and animation channel references.

Analysis reports should estimate vertex/index memory and identify mesh/material fragmentation, excessive sections, redundant geometry, missing LOD groups and outlier bounds. Cost estimates must state their assumptions.

### 7.2 KTX2 / material-texture validation

Validate KTX2 identifier/header, dimensions, face/layer/level counts, metadata ranges, supercompression scheme, DFD consistency, payload boundaries, and supported Basis/KHR_texture_basisu metadata. Check that texture semantics agree with material use: base color/emissive color-space treatment, linear data for normal/roughness/metallic/AO, channel packing convention, mip completeness, expected dimensions and sampler constraints.

Runtime asset policy remains:

- glTF/GLB for 3D scenes, geometry, hierarchy, skinning and animation;
- KTX2/Basis with `KHR_texture_basisu` for 3D material textures;
- AVIF for appropriate 2D/UI image content, not as a substitute for mesh geometry or the KTX2 material-texture path.

The analyzer must not pretend that parsing a KTX2 header proves successful texture transcoding or GPU upload. Real transcoding, device-format selection and GPU resource creation are separate runtime acceptance tests.

### 7.3 Scene and material analysis

Cross-check material slots, texture bindings, UV set availability, tangent basis requirements, skeleton references, animation targets and renderer capabilities. Report missing required maps separately from optional maps. Predictable fallback materials may be used only where the material schema explicitly marks the corresponding input optional.

## 8. Render-pipeline and resource analysis

Before GPU execution, the engine should expose a declarative render-pass/resource graph. The analyzer validates:

- read/write dependencies, missing producer passes, cycles and invalid pass order;
- resource format, dimensions, mip/layer ranges, sample count and bind flags;
- incompatible simultaneous read/write usage and D3D11 resource hazards;
- render-target/depth compatibility, viewport/scissor constraints and attachment completeness;
- resource lifetime, transient-resource aliasing candidates and peak estimated memory;
- shader reflection against pipeline layouts, vertex formats, constant buffers, SRVs, samplers and stage declarations.

The analyzer must distinguish compile-time graph validation from actual D3D11 runtime state. A graph that passes offline checks still requires device creation and real execution tests.

## 9. Shader package and build cache

Proposed package extension: `.shspkg`. The schema must not be considered frozen until GFX-0.2. Each package should carry:

- package schema and SGIR schema versions;
- Sharnou Graphics Compiler version and backend adapter version;
- source, canonical IR and compiled-bytecode SHA-256 digests;
- target API, profile, device capability requirements and entry point;
- defines, compile flags and complete include-dependency hashes;
- reflection data for stage inputs/outputs, resource bindings, cbuffer sizes/offsets and thread-group dimensions where applicable;
- source map/diagnostic references and reproducibility metadata.

Build output must be written to a temporary file/package, fully validated, hashed and atomically renamed into the cache only after all gates pass. A failed compile must not overwrite a last-known-good package or leave a partially loadable artifact. Cache hits must revalidate package version, hash and reflection contract before renderer use.

## 10. Sharnou IDE graphics workbench

The IDE should progressively provide:

1. Shader editor with stage-aware syntax coloring, source locations and inline diagnostics.
2. Shader build panel showing frontend, SGIR, verifier, optimization, target lowering, API compile and reflection phases independently.
3. SGIR inspection: values, types, blocks, control-flow graph, resource declarations and source mappings.
4. Resource-binding and constant-buffer layout viewer, including the exact reflected offsets/sizes.
5. Asset inspector for glTF hierarchy, mesh attributes, skeletons, animations, KTX2 metadata and material semantics.
6. Material editor and renderer capability panel.
7. Render-graph visualizer showing pass dependencies, resource readers/writers, hazards and estimated lifetimes.
8. Real 3D preview that runs the compiled shader on the selected D3D11 device, with clear indication when preview uses fallback material or reduced capability.
9. Frame capture and profiling view with per-pass CPU/GPU time, draw count, triangles, shader changes, texture memory and resource events.

The IDE must use the same compiler/analyzer libraries as command-line/project builds. A separate UI-only shader parser would create inconsistent results and is not acceptable.

## 11. Security, determinism and reliability

Shader source, includes, imported model files, compressed textures and project metadata are untrusted input. The graphics compiler must use bounded parsing and allocation, explicit maximum source/include sizes, include-depth limits, recursion limits, texture-dimension limits, arithmetic-overflow checks and deterministic failure diagnostics.

Include resolution must be confined to approved project roots. Canonicalize paths, reject path traversal and unauthorized reparse-point/symlink escapes, detect include cycles, and hash the resolved include graph. Do not allow arbitrary process execution from shader directives or asset importers.

Compile requests need explicit deadlines and cancellable stages. Cancellation must not publish incomplete output. GPU device objects are created only through the renderer's device/resource ownership layer, not by the offline analyzer.

Keep the compiler/analyzer read-only against source assets. Imported assets must never be overwritten during analysis or cache generation. Package writes must be atomic and restricted to configured build/cache roots.

## 12. Implementation sequence and acceptance

Graphics compiler milestones (`GFX-*`) are a separate track from renderer feature phases (`R0`-`R11`) in `Renderer-Roadmap-3D-MMORPG.md`. They are intended to supply the missing shader and analysis tools needed by renderer phases R1 onward.

| Milestone | Deliverable | Required acceptance evidence |
|---|---|---|
| GFX-0.1 | Architecture and interface contract (this proposal) | Design review; dependency boundary, data flow, SGIR and acceptance gates agreed |
| GFX-0.2 | SGIR/1 schema, canonical serializer and fail-closed verifier | Golden schema tests; malformed IR negative corpus; deterministic hashes; no emitted package on rejection |
| GFX-0.3 | Shader lexer/parser, source-mapped AST and typed semantic analysis | Positive/negative grammar and type tests; exact line/column diagnostics; no native/GPU output on failure |
| GFX-0.4 | Static analysis and target capability model | Binding/interface/cbuffer/derivative/resource tests; stable diagnostic codes; explicit profile rejection |
| GFX-0.5 | D3D11 HLSL lowering, in-process D3DCompile adapter and D3DReflect contract | Reflection matches SGIR for all golden shaders; exact compiler DLL/profile evidence; deterministic package hashes |
| GFX-0.6 | Renderer shader loading and first real geometry draw | Native Windows D3D11 device execution; actual indexed mesh/triangle render; real frame capture; resize/device-loss/regression tests |
| GFX-A.1 | glTF/GLB structural and mesh analyzer | Valid/invalid corpus; accessor/index/extension tests; stable asset report and memory estimates |
| GFX-A.2 | KTX2 and material-semantic analyzer | Header/DFD/mip/bounds negative corpus; material channel/color-space tests; no false claim of successful GPU upload |
| GFX-A.3 | Scene/material/animation cross-validation | Cross-asset reference tests; skeleton/skin/animation bounds; renderer compatibility diagnostics |
| GFX-0.7 | IDE shader, asset and render-graph workbench | Same diagnostics as CLI; navigation/reflection/inspection tests; preview linked to actual runtime output |
| GFX-0.8 | GPU capture and profiling integration | Per-pass GPU timing from timestamp queries, CPU/GPU separation, named device/scene benchmark artifacts |

Every milestone must preserve the existing native ABI, PE verifier, stack/unwind, SCM security and regression contracts. Graphics work does not authorize changing the Phase 2B.8 process-execution security boundary.

### 12.1 First vertical-slice shader corpus

Before optimizing for complex PBR, the first conformance corpus should include:

- flat-color vertex/pixel shader;
- indexed textured mesh with UVs;
- normal-mapped mesh with explicit tangent basis;
- metallic-roughness material with explicit channel convention;
- depth-only shadow pass;
- skinned vertex shader with bounded joint palette;
- invalid interface, duplicate binding and cbuffer layout cases;
- unsupported capability and malformed IR cases.

The first runtime milestone is intentionally small: compile, reflect, bind and render one real indexed mesh with a real camera and depth buffer. A device-clear or swap-chain-present test alone is not graphics compiler acceptance.

## 13. Design choices and non-goals

- Do not write a general C/C++ shader compiler or clone all of HLSL.
- Do not generate vendor-specific GPU machine instructions or promise portable machine code.
- Do not implement DXIL, Vulkan/SPIR-V or ray tracing before the D3D11 shader-to-render pipeline passes.
- Do not invoke `fxc.exe`, `dxc.exe`, MSVC, Clang, Visual Studio, an external assembler or an external linker.
- Do not add Slang, glslang, shaderc, SPIRV-Tools or another third-party compiler as a production dependency without a separate dependency decision. Such projects may be studied for design/test methodology only.
- Do not regard a static analyzer's performance estimate as a GPU benchmark.
- Do not mark a graphics capability complete from source inspection, generated demo images or mocked render output.

## 14. Reference material

- Microsoft: [D3DCompile](https://learn.microsoft.com/windows/win32/api/d3dcompiler/nf-d3dcompiler-d3dcompile).
- Microsoft: [D3DReflect](https://learn.microsoft.com/windows/win32/api/d3dcompiler/nf-d3dcompiler-d3dreflect).
- Khronos: [SPIR-V Specification](https://registry.khronos.org/SPIR-V/specs/unified1/SPIRV.html).
- Microsoft: [DXIL Specification](https://github.com/microsoft/DirectXShaderCompiler/blob/main/docs/DXIL.rst).
- Slang: [Language and compilation documentation](https://shader-slang.org/slang/user-guide/). Slang is reference material here, not an approved Sharnou dependency.
- Khronos: [SPIRV-Tools](https://github.com/KhronosGroup/SPIRV-Tools). Use its validator and optimizer as study references only; third-party validation cannot replace Sharnou's own SGIR verifier.

## 15. Current implementation status

As of 2026-11-28, the repository contains the existing high-level 3D MMORPG renderer roadmap. This GFX-0.1 proposal adds a dedicated shader-compiler and analysis architecture. It does not add a shader language, SGIR implementation, shader bytecode generator, asset analyzer, material editor, render graph, GPU profiler, or graphics IDE feature.

**Next proposed implementation milestone:** GFX-0.2 — SGIR/1 schema, canonical serialization, and fail-closed verifier. It should begin only after this architecture is reviewed and accepted, and should first be delivered as a testable IR contract without adding a third-party compiler dependency.