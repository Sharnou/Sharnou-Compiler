# Learning Path — Sharnou Graphics Compiler, Analysis and 3D Engine

**Status:** Learning plan for the proposed GFX-0.1 architecture; not a claim of implemented features.
**Date:** 2026-11-28

## Purpose

This sequence teaches the compiler, rendering, shader, asset and profiling concepts in the same order that Sharnou should implement them. It avoids starting with complex effects before the compiler, resource model, renderer and diagnostics can explain what is happening.

The target is to understand the full data path from Sharnou source to a verified shader package, from a GLB/KTX2 asset to GPU resources, and from a draw call to measured frame time.

## 1. Learn the four separate problem domains

| Domain | What it answers | Typical failure | Evidence needed |
|---|---|---|---|
| Native compiler | Can Sharnou build the game, engine and IDE executable correctly? | PE headers, imports, relocations, ABI or startup issue | Exact executable hash, PE/import/relocation inspection and real Windows execution |
| Shader compiler | Is the GPU program syntactically and semantically valid for its stage and target? | Type mismatch, invalid stage interface, resource binding or shader-profile error | Typed AST, SGIR verification, target compilation diagnostics and reflection |
| Asset analyzer | Is the model, texture, material, skeleton or animation structurally valid and compatible? | Invalid accessor range, missing tangent/UV, wrong texture channel or unsupported extension | Asset validation report and fixture-based positive/negative tests |
| Renderer/profiler | Did the device execute the intended pipeline and how much work did it cost? | Missing resource, wrong render state, overdraw, bandwidth or GPU stall | Real runtime capture, device queries, frame image and measured timings |

Never use success in one domain as proof of success in another. A shader compiling does not prove that its texture is loaded correctly. A model parsing does not prove that it renders. A rendered frame does not prove that frame time is acceptable.

## 2. Learn compiler construction before writing the shader language

Study these concepts in order:

1. **Lexing:** convert source characters to tokens; understand identifiers, numbers, operators, comments and source locations.
2. **Parsing:** convert tokens into a syntax tree; learn grammar, precedence, associativity, parse errors and recovery boundaries.
3. **Semantic analysis:** resolve names, scopes, overloads, types, stage restrictions and resource declarations.
4. **Typed AST:** represent meaning, not only source spelling. Reject type errors before lowering.
5. **Intermediate representation:** model values and operations in a target-independent representation.
6. **Control-flow graph:** functions, basic blocks, terminators, branches, loops and phi nodes.
7. **SSA and dataflow:** single-assignment values, dominance, use/def chains and safe transformations.
8. **Optimization:** constant folding, dead-code elimination, common-subexpression elimination and simplification with verifier checks.
9. **Target lowering:** convert a verified representation into the instructions and layout constraints of a particular shader target.
10. **Diagnostics and reproducibility:** stable error codes, source mapping, deterministic output, content hashes and atomic cache publication.

### Practice work

- Write down a tiny shader grammar with `vertex` and `pixel` entry points before implementing it.
- Draw an AST for a shader that transforms a vertex and samples one texture.
- Translate that AST manually into typed SGIR values and basic blocks.
- Construct malformed IR: duplicate value ID, invalid phi input, wrong vector type, missing terminator and duplicate resource binding. Define the exact verifier error for each.
- Verify that a failed parse or IR check creates no shader package and does not overwrite a previously valid package.

Do not start with full HLSL compatibility. The first language subset should be small, explicit and testable.

## 3. Learn the 3D math used by every renderer feature

Learn the math in this order:

- vectors, dot/cross products, normalization and coordinate handedness;
- local, world, view and clip spaces;
- model/view/projection matrices and perspective division;
- matrix multiplication order, row/column-major storage and constant-buffer packing;
- quaternions, hierarchical transforms and skeletal joint matrices;
- surface normals, tangent/bitangent bases, barycentric interpolation and texture coordinates;
- depth buffers, near/far planes, depth precision and shadow-map transforms;
- linear-light color, sRGB conversion, HDR values and tone mapping.

### Practice work

1. Render a triangle whose vertices are transformed by a camera matrix.
2. Add an indexed mesh and verify winding, depth testing and bounds.
3. Display UVs as colors, then validate the same UV set through the asset analyzer.
4. Render a normal map in tangent space and inspect tangent/normal consistency.
5. Implement one documented metallic-roughness BRDF and compare its inputs against material metadata.

Keep all math conventions written in the renderer/shader contract. Many graphics bugs are matrix-layout or coordinate-space mismatches, not mysterious GPU faults.

## 4. Learn the D3D11 graphics pipeline and resource model

Study the pipeline as a sequence of explicit contracts:

1. Input assembler: vertex buffers, index buffers, input layouts and topology.
2. Vertex shader: position transform, vertex attributes and stage outputs.
3. Rasterizer: clipping, viewport, culling, fill mode and interpolation.
4. Pixel shader: material evaluation, texture sampling and output color.
5. Output merger: render targets, depth/stencil state, blending and multisampling.

Then learn the resources used by those stages: constant buffers, shader-resource views, textures, samplers, render-target views, depth-stencil views, structured buffers and immutable/dynamic/default usage policies.

Build a binding map shared by the compiler, reflection system, material schema and renderer. Do not let the shader compiler invent one binding layout while the material editor or runtime assumes another.

### Practice work

- Build a real indexed triangle with a vertex buffer, index buffer, input layout, vertex shader, pixel shader and depth buffer.
- Bind one constant buffer and one texture/sampler pair.
- Intentionally swap bindings and verify that reflection validation reports the mismatch before draw submission.
- Resize the window and verify render-target recreation and viewport correctness.

## 5. Learn GPU shader compilation as a separate backend

Understand the difference between a shader source language, a shader intermediate representation, an API bytecode format and final GPU machine instructions.

Sharnou should own its shader language, type rules, SGIR, static analyzer, optimizer, target capability checks, reflection contract, cache identity and package format. The initial D3D11 bridge can lower a restricted SGIR subset to HLSL and call the Microsoft `D3DCompile` API in-process, then use `D3DReflect` to inspect the result. This is a proposed transitional adapter, not proof that the GPU backend is already first-party or that its DLL exists on every Windows installation.

Learn what reflection tells you: vertex input signature, stage outputs, resource bindings, constant-buffer sizes and field offsets. Compare reflection with the expected SGIR interface. If they disagree, reject the shader package.

Portable shader bytecode is not the same as hardware machine code. API-level bytecode/intermediate modules are generally compiled or specialized by the graphics driver for the actual adapter. The final compiler pipeline must include the actual device and driver in runtime compatibility tests.

### Practice work

- Compile a vertex/pixel pair using the supported D3D11 adapter.
- Save the compiler diagnostics blob on success and failure.
- Compare reflected input semantics and resource slots with expected SGIR metadata.
- Compile the same shader twice under the same toolchain/profile and compare canonical package hashes.
- Change one define or include file and confirm that only the affected shader cache identity changes.

## 6. Learn model and texture pipelines

### glTF / GLB

Learn JSON/GLB container structure, buffers, buffer views, accessors, indices, vertex attributes, nodes, transforms, materials, images, skins, inverse-bind matrices and animation channels. Pay attention to bounds checking and the difference between an optional extension and a required extension.

### KTX2 / Basis

Learn KTX2 headers, dimensions, faces/layers, mip levels, DFD, supercompression, Basis Universal payloads and target GPU texture formats. Understand material semantics: base-color/emissive data generally use color-space conversion, while normal/roughness/metallic/AO data are linear values with defined channel conventions.

### Practice work

- Build a tiny valid GLB fixture and invalid fixtures with out-of-range accessors, wrong index bounds, missing attributes, bad joint references and unsupported required extensions.
- Build KTX2 fixtures with truncated payloads, invalid level ranges and incompatible metadata.
- Validate a material by checking texture slots, UV requirements, tangent requirements and expected channel packing.
- Report memory estimates separately from actual GPU allocations and residency.

Authoritative format references: [Khronos glTF Registry](https://registry.khronos.org/glTF/) and [KTX specification](https://registry.khronos.org/KTX/).

## 7. Learn rendering quality in a production-safe feature order

Use this progression for the first Sharnou Engine vertical slice:

| Order | Feature | What you learn and must prove |
|---:|---|---|
| 1 | Unlit indexed geometry | Device, input layout, vertex/index buffers, basic shaders, depth and camera |
| 2 | Textured materials | UVs, sampler/resource bindings, sRGB and mip selection |
| 3 | Metallic-roughness PBR | Linear color, normals/tangents, BRDF and material reflection |
| 4 | Directional lighting and cascaded shadows | Light-space transforms, shadow maps, bias, filtering and cascade stability |
| 5 | Point/spot lights | Attenuation, cone falloff, light culling and bounded light counts |
| 6 | Skeletal animation | Joint indices/weights, palettes, animation sampling and blending |
| 7 | Terrain, streaming and LOD | Bounds, chunk lifecycle, frustum culling, memory budgets and pop control |
| 8 | Particles and atmosphere | GPU/CPU update budgets, transparency, sorting and deterministic tests |
| 9 | HDR and post-processing | HDR render targets, exposure, tone mapping and color correctness |
| 10 | Instancing and optimization | Draw submission, state changes, instance data and measured CPU/GPU costs |

Do not start complex shadowing, large-world streaming or MMO crowd rendering before the first real mesh and shader path is stable.

## 8. Learn graphics analysis: static, runtime and performance

### Static compiler analysis

Run before the program reaches the GPU. Check syntax, types, stage interfaces, resource slots, cbuffer packing, derivatives, loops, unsupported features and shader package consistency. Static analysis can prove some errors absent within its defined model; it cannot predict exact GPU time.

### Asset and pipeline analysis

Check geometry/index/accessor bounds, UV/tangent availability, material slots, skeleton references, texture metadata and render-pass read/write dependencies. Run these checks on import and again before packaging.

### Runtime correctness analysis

Use the D3D11 debug layer in development, check HRESULTs, label objects, track resource lifetime, verify device removal/resize paths and capture real frames. Keep mock devices and simulated tests separate from native GPU results.

### Runtime performance analysis

Record CPU submission time separately from GPU execution time. For D3D11, use timestamp queries inside a timestamp-disjoint interval and read results later without stalling the frame. Reject timestamp deltas when the disjoint flag is true. Track frame time, per-pass GPU time, draw calls, primitives, pixel-shader invocations where available, texture/mesh memory estimates and shader/cache counts.

PIX is useful, but current PIX documentation says it does not directly analyze D3D11 applications; D3D11 capture is possible through D3D11On12. Do not make PIX a requirement for the first D3D11 milestone. The initial Sharnou profiler should use D3D11 queries and its own markers. PIX can be studied and added when a validated D3D11On12/D3D12 route exists.

### A repeatable diagnosis sequence

When a scene is black, incorrect or slow, investigate in this order:

1. Did the asset analyzer accept the exact model/material/texture files?
2. Did the shader frontend parse and type-check the intended entry point?
3. Did the SGIR verifier accept the module without unsupported capabilities?
4. Did target lowering compile and did reflection match resource/layout metadata?
5. Did the renderer create the expected buffers, textures, views and pipeline state?
6. Were the correct resources and constant buffers bound at the exact draw?
7. Did the draw execute, pass depth/stencil and write to the intended render target?
8. Did the captured output look correct?
9. Which measured pass or CPU stage accounts for the frame cost?

Do not jump directly to shader optimization when a missing texture or wrong input layout is the cause.

## 9. IDE skills and workflow

The IDE graphics workbench should show each stage independently: source parsing, type checking, SGIR generation, IR verification, optimization, target lowering, GPU API compile, reflection and package publication.

The learner should be able to select a diagnostic and navigate to its source, select a binding and view expected/reflected slots, select a mesh and inspect vertex attributes, select a render pass and view resource dependencies, and select a frame marker and inspect measured CPU/GPU timings.

Use one compiler/analyzer implementation shared by the IDE and command-line build. Do not duplicate language semantics in UI code.

## 10. Suggested study resources

- Microsoft: [Direct3D 11 programming guide](https://learn.microsoft.com/windows/win32/direct3d11/dx-graphics-overviews).
- Microsoft: [HLSL](https://learn.microsoft.com/windows/win32/direct3dhlsl/dx-graphics-hlsl). Read it as a reference target language, not as the Sharnou language specification.
- Microsoft: [D3DCompile](https://learn.microsoft.com/windows/win32/api/d3dcompiler/nf-d3dcompiler-d3dcompile) and [D3DReflect](https://learn.microsoft.com/windows/win32/api/d3dcompiler/nf-d3dcompiler-d3dreflect).
- Khronos: [glTF 2.0 registry](https://registry.khronos.org/glTF/) and [KTX specification](https://registry.khronos.org/KTX/).
- Khronos: [SPIR-V specification](https://registry.khronos.org/SPIR-V/specs/unified1/SPIRV.html) for a defined intermediate representation and module model.
- Slang: [user guide](https://shader-slang.org/slang/user-guide/) for studying shader language design, compilation and reflection; not an approved Sharnou production dependency.
- Microsoft PIX: [documentation](https://devblogs.microsoft.com/pix/documentation/) and [requirements](https://devblogs.microsoft.com/pix/requirements/); observe the D3D11 capture limitation above.

## 11. What to build first

Do not implement every renderer feature at once. The recommended first graphics implementation is **GFX-0.2 — SGIR/1 schema, canonical serialization and fail-closed verifier**. Start with a tiny test corpus and make malformed-IR rejection airtight. Follow with the shader parser/type checker, then the D3D11 bridge, reflection checks and one genuine indexed mesh.

Parallel asset work should begin with a strictly read-only glTF/GLB structural analyzer, then a KTX2 metadata analyzer. Connect these tools through versioned asset manifests.

Success means the Sharnou compiler can explain and reject bad graphics programs/assets, compile supported shaders deterministically, prove reflection compatibility, render them in the real D3D11 engine and show real profiling data. It does not mean merely producing a pretty sample image.