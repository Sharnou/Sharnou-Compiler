# Sharnou Compiler

The repository contains the PowerShell/.NET Stage 0 native x64 bootstrap compiler. It emits AMD64 PE32+ images directly and does not invoke an external compiler, assembler, or linker.

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
