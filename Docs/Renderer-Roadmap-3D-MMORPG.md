# Sharnou Engine: Long-Term 3D MMORPG Renderer Roadmap

**Status:** Accepted long-term product and renderer direction  
**Architecture choice:** Option B - a self-contained Sharnou language, compiler, runtime, IDE, and engine stack  
**Initial graphics backend:** Windows x64 with Direct3D 11 and DXGI  
**Scope:** High-quality third-person 3D MMORPG / ARPG rendering and the engine foundations required to build it

> This document records the target architecture and implementation roadmap. It is not a claim that the listed renderer features are already implemented. Each capability becomes complete only after its implementation, automated tests, and real Windows runtime/visual validation pass.

## 1. Product direction

Sharnou is not intended to stop at a compiler that can open a 3D window or clear a swap chain. The objective is a self-contained development stack capable of building and running a complete, high-performance 3D MMORPG.

The long-term stack is:

- **Sharnou Language:** the engine/game programming language, with explicit native and graphics APIs.
- **Sharnou Compiler:** a self-hosted native x64 compiler and PE32+ linker, with a documented Windows x64 ABI.
- **Sharnou Runtime and Standard Library:** memory, files/assets, collections, diagnostics, windowing, input, threading, synchronization, and graphics resource services.
- **Sharnou Engine:** scene, entity, geometry, materials, animation, physics integration points, rendering, audio integration points, world streaming, and gameplay services.
- **Sharnou IDE:** project editing, compilation, diagnostics, asset inspection, profiling, and runtime launch/debug workflows.
- **Honour War:** the first full-scale game built on the Sharnou stack.

The design deliberately chooses a purpose-built language and toolchain rather than attempting to reproduce the complete C++ language and ABI. The compiler, linker, runtime contracts, asset tools, and engine APIs remain Sharnou-owned. Windows system APIs such as Win32, DXGI, and D3D11 are called through declared native interfaces. No MSVC, Clang, Visual Studio, third-party assembler, or third-party linker is part of the build chain.

## 2. Renderer feature target

The renderer roadmap must deliver all of the following capabilities:

1. Realistic physically based rendering (PBR).
2. Dynamic directional, point, and spot lighting.
3. Cascaded shadow maps.
4. Normal, roughness, metallic, and ambient-occlusion maps.
5. Skeletal animation and animation blending.
6. Large 3D environments and terrain.
7. Particle effects and atmospheric effects.
8. HDR rendering and post-processing.
9. GPU instancing and level-of-detail (LOD) systems.

The target is a coherent renderer with these systems integrated into one frame pipeline, not a collection of isolated demos.

## 3. Rendering architecture

Use a renderer interface above the Windows D3D11 implementation so scene and material systems do not depend directly on window handles or raw COM vtable calls.

### 3.1 Frame pipeline

The intended frame sequence is:

1. Collect the camera, visible scene objects, lights, animation poses, and particle emitters.
2. Update world transforms, animation state, bounds, and visibility.
3. Select LODs and build per-pass draw lists.
4. Render shadow depth passes, including directional-light cascades.
5. Render opaque geometry using PBR materials.
6. Evaluate direct lighting and image-based/environment lighting.
7. Render sky and atmospheric effects.
8. Render transparent geometry and particles with an explicit sort/blend policy.
9. Run HDR post-processing and tone mapping.
10. Render UI and present through DXGI.

Start with a forward renderer or a compact forward-plus path that fits the existing D3D11 foundation. Introduce a deferred path only when profiling and material/lighting requirements justify its memory and complexity. Whichever path is selected must preserve a clear render-pass/resource dependency model.

### 3.2 Device and resource ownership

Centralize ownership and lifetime for the D3D11 device, immediate context, swap chain, back buffers, render-target views, depth-stencil resources, shaders, buffers, textures, samplers, and state objects.

Required behavior:

- Check every HRESULT and validate every returned interface.
- Release COM references deterministically and avoid double release/use-after-release.
- Handle window resize by recreating size-dependent resources.
- Handle device removal/reset and report the failing HRESULT and diagnostic context.
- Keep CPU descriptions of GPU resources so device-dependent resources can be recreated.
- Validate texture dimensions, formats, mip counts, buffer sizes, and shader input layouts before use.
- Keep all GPU resource creation on an explicitly managed render/device thread unless an API is documented as safe for another thread.

The D3D11 backend is the first Windows renderer backend. A future console renderer requires a separate platform backend and the platform's legitimate SDK/API; the Windows D3D11 backend must not be represented as a universal console implementation.

## 4. Geometry, models, and asset pipeline

The engine must create primitive geometry itself and load production 3D assets.

### 4.1 Geometry creation

Implement Sharnou-side geometry builders for:

- Positions, normals, tangents, texture coordinates, vertex colors, and indices.
- Plane, box, sphere, capsule, cylinder, and other debug/procedural primitives.
- Mesh validation, bounds, tangent generation, normal generation, and index validation.
- Static mesh and skinned mesh GPU buffer layouts.
- Mesh sections/material slots and submesh ranges.

Procedural geometry is for runtime generation, collision/debug visualization, terrain patches, and test fixtures. It does not replace an authored 3D model pipeline.

### 4.2 Model and scene import

Use glTF 2.0 / GLB as the primary scene and model interchange format. Import nodes, transforms, meshes, primitives, indices, material assignments, skins, joints, inverse bind matrices, and animation channels. Reject unsupported required glTF extensions instead of silently dropping data.

Runtime asset policy:

- **glTF / GLB:** 3D scenes, mesh geometry, node hierarchies, skins, and animation data.
- **KTX2 with Basis Universal and KHR_texture_basisu:** compressed/transcodable 3D material textures.
- **AVIF:** 2D UI and image content where appropriate; it is not a substitute for glTF geometry or KTX2 material textures.

Build an asset validation/intake layer that checks referenced files, formats, dimensions, texture semantics, and extension requirements before packaging. Keep source assets distinct from runtime-optimized assets and record hashes for deterministic cache/update validation.

## 5. Physically based materials and textures

Adopt a metallic-roughness PBR material model with explicit texture semantics:

- Base color / albedo.
- Tangent-space normal.
- Metallic.
- Roughness.
- Ambient occlusion.
- Optional emissive and opacity data.

A packed metallic-roughness texture may store roughness and metallic in separate channels, but the material schema must define the channel convention. AO may be packed separately or combined only where the import metadata explicitly says how.

The material system must define:

- Linear versus sRGB interpretation for each texture.
- Tangent-space convention and tangent handedness.
- Normal-map reconstruction and filtering rules.
- Mip generation and sampler policy.
- Material constants, texture bindings, and shader permutation keys.
- Safe fallback material behavior for missing optional maps.
- Fail-closed behavior for missing required maps or invalid texture metadata.

Use physically plausible BRDF behavior (metallic-roughness microfacet model, Fresnel response, geometric visibility, and energy conservation). Avoid treating a textured diffuse shader as completed PBR.

## 6. Lighting and shadows

### 6.1 Dynamic lighting

Support these dynamic light types:

- **Directional:** sun/moon or large-distance illumination.
- **Point:** local omnidirectional lights with range and attenuation.
- **Spot:** cone-shaped lights with inner/outer cone parameters and range.

Define a consistent light data layout, color/intensity units, coordinate system, attenuation model, and maximum active-light policy. Begin with a tested per-object light limit, then move to tiled or clustered light assignment as scene scale requires. Light count must not grow without a measured CPU/GPU budget.

### 6.2 Cascaded shadow maps

Implement directional cascaded shadow maps with:

- Camera-frustum split generation and configurable cascade count.
- Stable light-space matrices and practical split distributions.
- Per-cascade depth rendering and atlas/array resource management.
- Depth bias and slope-scaled bias to reduce acne.
- PCF filtering and cascade transition handling.
- Frustum fitting and resolution controls.

Spot-light shadow maps can follow. Point-light shadows (cube-map or dual-paraboloid approach) are a separate later capability and must be profiled before adoption.

## 7. Skeletal animation and blending

Support glTF skins and animation channels, with an engine runtime that provides:

- Skeleton and joint hierarchy.
- Inverse bind matrices and skin weights.
- Translation, rotation, and scale animation tracks.
- Correct interpolation, including quaternion interpolation.
- Animation clips, playback time, looping, and root-motion policy.
- Two-or-more clip blending with blend weights and transition rules.
- Animation state machines for locomotion, attacks, hit reactions, and other game states.
- GPU skinning in the vertex shader as the first high-performance path, with explicit joint palette limits and validation.

The design must cover multiple character instances, per-character animation state, shared skeleton/clip resources, and safe handling of different skeleton variants. Later optimizations can add animation LOD, reduced update frequency for distant actors, and palette/buffer batching.

## 8. Large environments and terrain

Large-world support requires more than large vertex buffers. Implement:

- Chunked world/terrain representation with independently loadable regions.
- Heightfield terrain as an initial terrain path, with configurable material layers and detail maps.
- Quadtree or clipmap-style terrain LOD selection.
- Frustum and distance culling.
- Streaming boundaries, asynchronous IO, and a bounded asset cache.
- Spatial partitioning for static props and dynamic actors.
- World-origin/rebasing strategy if world scale requires it.
- Occlusion culling only after a measurable baseline and correctness tests exist.

Streaming must be bounded by memory budgets and must never stall the render thread on unbounded synchronous disk reads.

## 9. Particles and atmospheric effects

The particle system must provide:

- Emitters, spawn rates, lifetime, velocity, acceleration, size, color, and rotation.
- Billboard and camera-facing particles as the baseline.
- Alpha/additive blend modes with explicit depth behavior.
- Deterministic simulation options for tests and replays.
- Distance/visibility-based particle LOD and hard budget limits.

Atmospheric features should progress from sky gradients, sun direction, fog, and height fog to more advanced scattering. Volumetric fog/cloud approaches are later, optional quality tiers and must not be required for a minimum-spec configuration.

## 10. HDR and post-processing

Use a linear-light HDR scene target (for example, a suitable floating-point render-target format supported by the selected D3D11 device). Add:

1. Exposure and tone mapping.
2. Bloom.
3. Color grading.
4. Screen-space ambient occlusion (SSAO) where the quality/performance tradeoff is acceptable.
5. Anti-aliasing, beginning with a practical low-risk method and adding temporal techniques only when motion vectors and history validation exist.
6. Optional depth of field, motion blur, and other effects behind quality settings.

Define a color-management contract from texture import through lighting and final display. Treat HDR10 swap-chain/display output as a later platform/display capability; do not confuse an internal HDR render target with guaranteed HDR monitor output.

## 11. GPU instancing, culling, and LOD

Support instanced rendering for repeated props, vegetation, buildings, and other shared meshes/materials. Instance data must include transforms and only the per-instance attributes required by the selected shader.

Add mesh LOD groups with distance/screen-size thresholds, hysteresis, bounds validation, and transition policy. Use frustum culling first, then evaluate occlusion and more advanced visibility methods. Batch by compatible mesh, material, shader permutation, and render state without making scene order or transparency incorrect.

Performance targets must be measured on named hardware and scene workloads. Record CPU frame time, GPU frame time, draw calls, visible instances, triangles, texture memory, streaming stalls, and shader/resource changes. Do not claim an FPS target without a reproducible benchmark.

## 12. Sharnou language, compiler, and IDE work required

The engine must be implementable in Sharnou itself. Expand the language/runtime only where the engine needs real capabilities, with tests at every stage.

Required language/runtime areas include:

- Structs/value layouts with defined alignment and field offsets.
- Pointer/handle types and explicit ownership/lifetime rules.
- Arrays, slices, spans, and bounds-checked access where appropriate.
- Enums, bit flags, and typed constants.
- Native function declarations/imports with ABI signatures.
- Callback/function-pointer support for Win32 window procedures and engine callbacks.
- Generic containers or a deliberately small set of typed standard-library containers.
- Deterministic allocation/free APIs and arenas/pools for frame and asset lifetimes.
- Thread-safe queues, events, mutexes, and job-system primitives.
- SIMD/vector math types and verified x64 calling/return rules.
- Shader source/build integration and shader reflection/constant-buffer layout validation.
- Useful compiler diagnostics, module/dependency tracking, incremental builds, and reproducible outputs.

The Sharnou IDE should expose project builds, asset validation, shader diagnostics, runtime launch, frame capture, and CPU/GPU profiling without invoking external programming tools.

## 13. Recommended implementation phases and gates

Each phase is a separately testable milestone. Do not start the next major phase until the prior phase has unit tests, integration tests, and real Windows runtime evidence.

| Phase | Deliverable | Acceptance gate |
|---|---|---|
| R0 | Renderer architecture, resource ownership, device-loss and resize contracts | API/layout tests and lifecycle tests |
| R1 | Geometry builders, mesh buffers, camera, depth buffer, shader pipeline | Render a real indexed 3D mesh, not only a window clear |
| R2 | glTF/GLB scene ingestion and KTX2 texture intake | Load and render an imported model with validated material resources |
| R3 | Metallic-roughness PBR and normal/AO/metallic/roughness maps | Material test scene with channel/color-space validation |
| R4 | Directional, point, and spot lights | Multi-light test scene and light-budget profiling |
| R5 | Cascaded directional shadows and filtering | Moving camera/light shadow test without cascade instability |
| R6 | Skeletons, skinning, animation clips, and blending | Animated character scene with multiple blended clips |
| R7 | Terrain, world chunks, streaming, frustum culling, and LOD | Large terrain/world stress scene with bounded memory |
| R8 | Particles and atmosphere | Deterministic particle and fog/sky test scenes |
| R9 | HDR pipeline and post-processing | HDR scene, exposure/tone-map tests, and display-path validation |
| R10 | GPU instancing and renderer optimization | Reproducible high-instance-count benchmark |
| R11 | Engine/IDE integration and Honour War vertical slice | Playable third-person scene using production asset and animation pipeline |

R1 deliberately requires a real 3D mesh. A successful clear/present test proves device and presentation plumbing, but it is not evidence of geometry rendering.

## 14. Validation and quality gates

Every graphics milestone requires both structural and real runtime validation:

- Compiler positive/negative tests and native ABI tests.
- PE import, relocation, section, and image validation.
- D3D11 device/context/swap-chain and resource-creation HRESULT checks.
- GPU resource lifetime tests and leak checks.
- Window resize, minimize/restore, close, and device-loss tests.
- Deterministic scene tests with repeatable camera, lighting, and assets.
- Real screenshot/frame capture from the running executable.
- Image/pixel checks where deterministic output is possible, with tolerant comparisons for hardware-dependent rendering.
- Performance captures on named machines and documented scene settings.
- Regression of all previously accepted compiler and Engine tests.

A static instruction scan or a generated image is not a substitute for launching the native executable and capturing its actual rendered output.

## 15. Constraints and non-goals

- No MSVC, Clang, Visual Studio, external assembler, or external linker.
- The Sharnou compiler and linker own native executable generation.
- Windows system DLLs are used through explicit imports and verified signatures.
- No dependency is assumed to exist merely because its name is familiar; runtime/API availability and version/capability must be checked.
- No fake executables, placeholder GPU resources, synthetic screenshots, or success receipts.
- D3D11 is the initial Windows backend. Other operating systems or consoles require separate, explicit backends and platform SDK/API contracts.
- Keep the renderer modular so future backend work does not leak into the game-facing Sharnou APIs.

## 16. Definition of done

The long-term renderer objective is achieved only when Sharnou can compile and run a real third-person MMORPG scene that demonstrates:

- Imported and procedurally generated 3D geometry.
- PBR materials using base-color, normal, roughness, metallic, and AO texture data.
- Dynamic directional, point, and spot lighting.
- Cascaded directional shadows.
- Skeletal characters with blended animation.
- Large terrain/environment streaming and LOD.
- Particle and atmospheric effects.
- HDR rendering and post-processing.
- GPU-instanced scene objects and measurable LOD/performance behavior.

The completed system must be built by the Sharnou toolchain, tested through the Sharnou workflow, and demonstrated by real runtime captures from the target Windows PC. This is the product target for Sharnou Engine and the rendering foundation for Honour War; it is not a claim that these capabilities are already implemented.
