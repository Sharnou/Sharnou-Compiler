# Sharnou Compiler

The repository contains the PowerShell/.NET Stage 0 native x64 bootstrap compiler. It emits AMD64 PE32+ images directly and does not invoke an external compiler, assembler, or linker.

## AI development governance - read first

Before any AI-assisted source generation, bug investigation, compiler repair, test modification, or Engine change, read [AI_START_HERE.md](AI_START_HERE.md). It defines the mandatory source-of-truth preflight and session-update process.

- [Master development plan and milestone map](Docs/AI-DEVELOPMENT-PLAN.md)
- [Latest AI session state and next action](Docs/AI-SESSION-STATE.md)
- [Known issue and blocker register](Docs/AI-ISSUE-REGISTER.md)
- [Persistent AI status issue #8](https://github.com/Sharnou/Sharnou-Compiler/issues/8)
- [Restore exact 83-case regression baseline - issue #9](https://github.com/Sharnou/Sharnou-Compiler/issues/9)
- [Milestone 7A Windows acceptance - issue #10](https://github.com/Sharnou/Sharnou-Compiler/issues/10)

The AI must read these files from the current branch before every new code-generation or repair session, then update the live state and issue tracker when the session finishes. This is a repository workflow rule; it is not a claim of unattended background monitoring.

## Long-term renderer direction

The accepted product target is a self-contained Sharnou compiler/runtime/IDE/engine stack capable of producing a complete high-performance 3D MMORPG, not merely opening a graphics window. The renderer roadmap covers procedural and imported 3D geometry, glTF/GLB scenes, KTX2 material textures, metallic-roughness PBR, normal/roughness/metallic/AO maps, directional/point/spot lighting, cascaded shadows, skeletal animation and blending, large environments and terrain, particles and atmospheric effects, HDR/post-processing, GPU instancing, and LOD.

The design choice is a purpose-built Sharnou language and toolchain, not a C++-compatible toolchain. Sharnou owns its compiler, linker, runtime, asset pipeline, shader integration, engine APIs, and IDE workflow. The initial rendering backend is Windows x64 with D3D11/DXGI. No MSVC, Clang, Visual Studio, external assembler, or external linker is part of the build chain. Each renderer capability requires native runtime tests and real visual/performance evidence before being marked complete.

See [Docs/Renderer-Roadmap-3D-MMORPG.md](Docs/Renderer-Roadmap-3D-MMORPG.md) for the complete architecture, subsystem details, implementation phases, acceptance gates, and definition of done.

The proposed [Sharnou Graphics Compiler and Analysis Architecture](Docs/GFX-0-1-GRAPHICS-COMPILER-ARCHITECTURE.md) defines a separate typed shader IR, shader/static analysis, D3D11 backend adapter, asset analyzer, reflection contract, and IDE workbench. It is design-only until its milestone acceptance tests pass.

## Milestone 7A - Control flow

Stage 7A adds native if / else, while, and signed integer comparisons.

Supported comparison operators:

- < less than
- > greater than
- <= less than or equal
- >= greater than or equal
- == equal
- != not equal

A condition is an integer expression. Zero is false; any non-zero value is true. Comparisons produce normalized integer values 0 or 1.

Example:

    let index = 0;
    let total = 0;
    while (index < 5) {
        if (index == 2) {
            total = total + 10;
        } else {
            total = total + index;
        }
        index = index + 1;
    }
    print(total);

Blocks use lexical scopes. Variables declared inside an if, else, or while body are not visible outside that body. Each declaration still receives a unique stack slot in the function's existing stack-frame allocation.

The current subset deliberately rejects chained comparisons, string comparisons, else-if shorthand, logical AND/OR operators, and return nested inside a control-flow block. Use nested if statements to express nested conditions.

## Native x64 lowering

The frontend emits comparison nodes. The backend evaluates the left operand, saves it to a temporary stack slot, evaluates the right operand, then emits:

- mov ecx,eax to preserve the right operand
- mov eax,[rbp-disp32] to restore the left operand
- cmp eax,ecx to set the arithmetic flags
- signed SETcc AL (SETL, SETG, SETLE, SETGE, SETE, or SETNE)
- movzx eax,al to normalize the result to 0 or 1

An if condition emits test eax,eax followed by a near JZ rel32 branch. An if/else also emits a near JMP rel32 around the else body. A while loop marks its condition label, emits the condition and JZ rel32 exit, emits the body, and branches back with JMP rel32. Label references use the existing code-fixup pass. The Windows x64 calling convention, 32-byte shadow store, frame pointer, and stack alignment are unchanged.

## Commands

Run from the repository root in 64-bit Windows PowerShell 5.1:

    .\Build.ps1
    .\Run.ps1
    .\Test.ps1
    .\Dev.ps1

Test.ps1 executes Tests\Test-Stage7A.ps1, which compiles and runs eight positive programs, checks twelve invalid programs for line/column diagnostics and absence of output executables, and inspects generated code for all six SETcc forms and the branch/loop instructions.

The PE verifier is Tools\SharnouPEVerify.ps1. It checks the AMD64 PE32+ headers, four-section layout, import descriptors, required system imports, relocation block, and dynamic .text section size.

## Baseline regression note

The Milestone 6 branch imported for this work did not contain the 83-case regression-suite sources or their fixture directories. The previously reported local Milestone 6 pass is retained as project history, but this branch must not claim those 83 cases were rerun until that suite is checked into the repository and executed. The Stage 7A workflow runs the new control-flow suite on a Windows runner.

## Toolchain boundary

The bootstrap is PowerShell/.NET and emits PE32+ output itself. No MSVC, Clang, Visual Studio, external assembler, external linker, compiler package, or download is used.

## Autonomous SharnouDevAgent roadmap

The requested autonomous development-agent architecture is documented in [Docs/SHARNOU-DEVAGENT-AUTONOMOUS-ARCHITECTURE.md](Docs/SHARNOU-DEVAGENT-AUTONOMOUS-ARCHITECTURE.md) and tracked in [issue #14](https://github.com/Sharnou/Sharnou-Compiler/issues/14). The existing native DevAgent prototype on draft PR #7 is a test orchestrator, not an AI source-generating agent. The roadmap requires a safe typed tool broker, local in-process model inference, durable knowledge/task memory, validated agent profiles, bounded repair transactions, static reverse engineering, and optional external-provider adapters. No autonomous source execution is enabled by this documentation change.
