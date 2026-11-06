# R26.0-R2-R8

- Corrects the PEHeaders fixture entry path and invokes the module-level harness.
- Strengthens native-process stdout/stderr capture and failure diagnostics.
- Preserves the frozen R25-R4 source archive, frozen compiler/lexer, R26.0-R2 overlay, PEHeaders hardening helpers, and seven-case x64 ABI test matrix.
- Release validation reruns the 83-case baseline, 70 PEHeaders cases, seven native ABI cases, and PowerShell 5.1 parser/ScriptBlock checks before publication.

Compatibility: this is a PowerShell bootstrap compiler for .sharnou sources. It is not a native C++ compiler driver and does not implement a C++ frontend.
