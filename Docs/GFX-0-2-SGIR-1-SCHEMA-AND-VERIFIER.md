# GFX-0.2 — SGIR/1 schema, canonical serialization and verifier

**Status:** Code-bearing implementation candidate. Not accepted until the exact branch head passes the Windows workflow and its evidence is inspected.
**Base:** GFX-0.1 architecture proposal, PR #39.
**Scope:** A first, deliberately small graphics IR contract for the Windows x64 / D3D11 baseline.

## 1. Why this milestone comes first

A shader compiler needs a stable boundary between language semantics and target-specific code generation. If the IR is underspecified, every later frontend, optimizer and backend can disagree about types, control flow, resource bindings or shader-stage interfaces.

GFX-0.2 establishes the contract and rejects malformed IR before it can reach any lowering or runtime stage. It does not yet parse .shshader, emit HLSL/DXBC, create a D3D11 device, load GPU resources, or draw a mesh.

The implementation is intentionally written in the repository's PowerShell/.NET bootstrap environment. It adds no MSVC, Clang, Visual Studio, MSBuild, external assembler/linker, third-party shader compiler, package manager or runtime download.

## 2. Files

- **Schemas/SGIR/1/sgir.schema.json** — machine-readable SGIR/1 structural schema.
- **Tools/SharnouGraphicsIR.ps1** — strict JSON intake, canonical JSON serializer, SHA-256 identity and semantic/CFG/SSA verifier.
- **Examples/GraphicsIR/triangle-minimal.sgir.json** — valid vertex-stage fixture with input/output contract, typed constant buffer, SSA branch/merge and phi node.
- **Tests/Test-SharnouGraphicsIR.ps1** — positive, negative, determinism and canonical-file tests.
- **.github/workflows/gfx-0-2-sgir-verifier.yml** — exact-head Windows Server 2025 gate.

The PowerShell verifier is authoritative for SGIR/1 acceptance. JSON Schema is an editor/interchange aid; JSON Schema alone cannot prove CFG reachability, dominance, phi-edge completeness, or reflection semantics.

## 3. Module envelope

Every SGIR/1 module has exactly these top-level fields:

| Field | Contract |
|---|---|
| schema | Exact string SGIR/1. Unknown schema versions fail closed. |
| moduleId | Stable lowercase ASCII package identity, 1–128 characters. |
| target | Exact initial profile: d3d11, feature level 11_0, shader model 5_0. |
| capabilities | Sorted, unique declared capabilities. Unknown capabilities are rejected. |
| types | Sorted custom type declarations. Built-in scalar IDs are void, bool, i32, u32, f32. |
| resources | Sorted resource declarations with explicit set/binding and stage visibility. |
| entryPoints | Sorted stage entry-point declarations with explicit inputs and outputs. |
| functions | Sorted function declarations and explicit control-flow blocks. |

Unknown properties, missing required properties, duplicate JSON property names, null array elements, unsupported schema versions and unsupported target profiles are rejected. Property names are case-sensitive in the format; the intake scanner additionally rejects case-folded duplicate spellings so PowerShell's object model cannot collapse them.

## 4. Type system in this increment

Built-in values are bool, i32, u32, and f32; void is allowed only as a function return type and resource placeholder where stated.

Custom declarations currently include:

- vector: 2–4 lanes, element type f32, i32 or u32;
- matrix: 2–4 rows and columns, f32, explicit row- or column-major convention;
- struct: named fields with unique names and contiguous zero-based indexes;
- array: a bounded fixed element count and a declared element type.

Type references must resolve. void cannot be used for a struct field or an array element. A constant-buffer resource must reference a declared struct. Cyclic aggregate types and layout computation are deferred to a separately qualified layout pass; they must not be treated as physically laid out by this milestone.

f32 constants are represented as exactly eight uppercase hexadecimal digits containing the IEEE-754 binary32 bit pattern, not JSON decimal floating-point values. This prevents locale-dependent decimal serialization and preserves exact bit patterns.

## 5. Resource and stage contracts

Resources have a stable ID/name, kind (texture2d, sampler, constant_buffer), explicit set and binding, type and sorted stage-visibility list. The current portable binding envelope is set 0–7 and binding 0–127. A duplicate set/binding pair is a hard error. Texture/sampler object types and the complete D3D11 register-mapping policy are intentionally deferred.

The first accepted stages are vertex and pixel. Stage interfaces carry an ID, location, semantic, type and interpolation mode. Locations are unique and strictly increasing within each direction. Semantics are unique within a direction. A vertex entry point must declare exactly one SV_Position output; a pixel entry point must declare SV_Target0.

GFX-0.2 validates declarations and local interface operations. It does not yet verify vertex-to-pixel link compatibility across a complete pipeline; that is a later semantic-analysis milestone.

## 6. Function and control-flow contract

A function declares a return type, entry block, ordered parameters and sorted basic blocks. Every block has an instruction array and exactly one terminator. The initial terminators are:

- branch — one target block;
- branch_conditional — a Boolean condition and distinct true/false targets;
- return — no value for void, exactly one typed value otherwise.

The first supported instruction subset is intentionally small:

| Instruction | Purpose |
|---|---|
| const | Typed scalar constant. |
| load_input | Load a declared input of the owning entry point. |
| construct_vector | Construct a vector from exactly its scalar lanes. |
| add, mul | Same-type scalar or vector arithmetic. |
| phi | Merge values from all incoming predecessor edges. |
| store_output | Store a type-compatible value to a declared stage output. |

There is no implicit conversion, pointer, memory, texture sample, derivative, function call, loop-annotation, optimizer-only or target-specific opcode yet. An unknown opcode is a verifier error, not an opaque extension point.

### CFG/SSA invariants

The verifier checks:

1. Unique function, block, parameter and SSA result IDs in their namespaces.
2. A declared entry block and valid branch targets.
3. Reachability of every block from the function entry block.
4. One terminator per block and valid return-value arity/type.
5. Boolean conditional-branch conditions.
6. Phi instructions before all non-phi instructions in a block.
7. Exactly one phi incoming value for every predecessor edge, with no duplicate/non-predecessor edges.
8. Defined operands, compatible operand/result types, and use-after-definition in a block.
9. Iterative dominator analysis and dominance of ordinary cross-block SSA uses.
10. Phi incoming values that are available at the end of their stated predecessor block.

The current IR does not contain exceptional control flow, irreducible CFG metadata, memory SSA, function calls or structured-loop metadata. Those are not silently inferred.

## 7. Canonical JSON and content identity

Canonical serialization is defined as:

- JSON object keys sorted by ordinal Unicode string comparison;
- array order preserved (the schema separately requires sorted order for declaration sets and location/index collections);
- no insignificant whitespace;
- JSON string escaping for quotes, backslashes and control characters; non-ASCII UTF-16 code units are emitted as Unicode escapes;
- only integer JSON number values; decimal/exponent numeric tokens are forbidden by field validation;
- Boolean literals emitted as lowercase true/false;
- no null values in accepted IR;
- canonical bytes encoded as strict UTF-8 without a BOM.

The module identity digest is SHA-256 over the canonical UTF-8 bytes **without** a trailing line feed. The Canonicalize CLI writes the same canonical JSON followed by one platform line ending, without a BOM. The CLI prints the digest from the no-line-ending representation.

Arrays with set-like semantics are required to arrive in canonical order:
- capabilities and resource stage lists: ordinal string order;
- type/resource/function IDs and entry-point names: ordinal string order;
- basic-block IDs: ordinal string order;
- stage input/output interfaces: increasing location;
- function parameters: contiguous index order;
- struct fields: contiguous index order.

Instruction arrays retain program order. Phi incoming arrays are required to be ordered by predecessor block ID. The verifier does not silently reorder a malformed module before hashing it.

## 8. Failure and diagnostic contract

Every rejection throws a stable SGIR-<code> diagnostic and stops before a package can be produced. No shader package, bytecode, cache entry or runtime artifact is emitted by this milestone.

The intake rejects documents larger than 4 Mi UTF-16 code units, malformed JSON and duplicate property names. The verifier uses bounded declaration counts through field ranges and identifier lengths. Future frontends must add explicit limits for instruction count, function count, nesting, source size and include graph before parsing arbitrary project input.

## 9. CLI

Verify an existing module:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File Tools\SharnouGraphicsIR.ps1 -Action Verify -InputPath Examples\GraphicsIR\triangle-minimal.sgir.json

Write canonical output and print the content digest:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File Tools\SharnouGraphicsIR.ps1 -Action Canonicalize -InputPath Examples\GraphicsIR\triangle-minimal.sgir.json -OutputPath Build\GraphicsIR\triangle.canonical.sgir.json

The None action is the dot-source/library mode used by the test harness. No process is spawned by the verifier.

## 10. Required qualification

The Windows workflow must test the exact checked-out PR head and include:

- positive vertex module verification;
- object-key and whitespace canonicalization determinism;
- canonical no-BOM output and read-back;
- malformed JSON and duplicate property names;
- unsupported schema, unknown field, invalid type, unsupported opcode;
- invalid stage output and input/output type mismatch;
- resource set/binding collision;
- unknown branch target and unreachable block;
- malformed phi edges and undefined SSA values;
- SSA dominance violation;
- return type mismatch;
- the existing Stage 7A regression suite.

The frozen historical 83-case M1–M6 baseline remains a separate open provenance/integration blocker and is not inferred from this focused workflow. GFX-0.2 cannot mark that baseline restored.

## 11. Explicitly out of scope

- .shshader lexer/parser and typed AST (GFX-0.3);
- complete shader semantic analysis and capability legalization (GFX-0.4);
- HLSL emission, D3DCompile/D3DReflect integration or a compiler DLL dependency (GFX-0.5; requires a separate dependency decision);
- runtime shader creation, vertex/index buffers, indexed mesh draw or screenshot (GFX-0.6 and renderer R1);
- glTF/GLB and KTX2 file parsing, skeletal/animation analysis, render-graph analysis;
- optimizer passes, SPIR-V, DXIL, DXC, shader package/cache and IDE panels.

Keep this graphics branch independent from Phase 2B.8. It does not enable child-process execution, model-facing execution, autonomous execution, SCM authority service requests, key provisioning or security acceptance.
