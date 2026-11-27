# Phase 2B.8 R5.1 - Native SCM service-host implementation gate

Status: DESIGN AND IMPLEMENTATION PREFLIGHT ONLY. No Windows service executable is emitted by this tranche.

## 1. Objective

R5.1 is the first production-code tranche of the Native Windows Execution Authority Service. It must produce a genuine x64 PE32+ Windows service executable from Sharnou source, run under the Windows Service Control Manager (SCM), report service state correctly, and shut down deterministically. It must not accept or execute client requests yet.

The service host is a separate executable from the interactive Sharnou DevAgent/compiler process. Its first version is deliberately inert: it starts, registers its control handler, reports SERVICE_RUNNING, waits for STOP or SHUTDOWN, reports SERVICE_STOP_PENDING, releases owned handles, reports SERVICE_STOPPED, and exits. No process creation, profile mutation, journal writes, signing, pipe listener, or model-facing operation is in scope for R5.1.

## 2. Verified compiler constraints discovered during R5.1 preflight

The current Stage0 PE emitter has an explicit import-set table and hard-coded IAT offsets. The normal compiler path currently emits a single DIR64 relocation for the absolute entry-point anchor. The source-language builtin emitter handles direct, statically named IAT calls; the inspected path does not yet provide a qualified service-table/function-pointer callback mechanism.

A real SCM service host needs at least:
- a correctly laid out SERVICE_TABLE_ENTRYW array with a pointer to a service-main callback and a null terminator;
- a service-main callback with the Windows x64 ABI and a stable service-name pointer;
- a registered HandlerEx callback with the exact callback ABI;
- a SERVICE_STATUS structure with correct field widths and state/control values;
- a stop-event or equivalent bounded wait mechanism;
- valid absolute addresses for callback functions and service-name data;
- correct relocations for every absolute VA embedded in read-only data;
- a verified import table containing only the imports the service image actually uses.

The current one-entry relocation construction is insufficient for a service table containing multiple absolute pointers. Merely adding SCM imports or declaring compiler builtins would produce an incomplete or unsafe image. The speculative import/builtin scaffold was therefore reverted in commit `23a01bd5425bc183aeb5496827e015e75beeac42`; the normal compiler path is restored rather than leaving undefined builtins or unimplemented IAT calls.

## 3. Required implementation order

### R5.1.a - PE relocation and callback-address primitives
1. Replace the single hard-coded relocation entry with a bounded relocation builder accepting explicit relocation targets.
2. Add a code-label-to-RVA fixup that resolves only labels emitted in the current image.
3. Add data-pointer relocation records for callback and service-name fields.
4. Reject duplicate, out-of-image, unaligned, unsupported, and overlapping relocation targets.
5. Keep existing compiler output byte-for-byte stable when no additional relocation targets are registered.
6. Add PE parser tests for relocation blocks, DIR64 target locations, image-base rebasing, and malformed relocation rejection.

### R5.1.b - Win64 callback ABI support
1. Add typed function-pointer/data-address emission; do not use arbitrary integer casts as callback pointers.
2. Validate callback signatures at compile time:
   - SERVICE_MAIN_FUNCTIONW: (DWORD, LPWSTR) -> void;
   - HandlerEx: (DWORD, DWORD, LPVOID, LPVOID) -> DWORD.
3. Verify shadow space, stack alignment, nonvolatile register preservation, and unwind metadata for both callbacks.
4. Add runtime probes that invoke callbacks through the generated pointer table on Windows.

### R5.1.c - SCM lifecycle image
The generated service image may import only the APIs required by this inert host:
- KERNEL32: CreateEventW, SetEvent, WaitForSingleObject, CloseHandle, ExitProcess, GetLastError;
- ADVAPI32: StartServiceCtrlDispatcherW, RegisterServiceCtrlHandlerExW, SetServiceStatus.

The import list is a ceiling for this tranche, not a requirement to retain unused imports. The verifier must compare the actual PE import table to the exact expected set for the produced image; source declarations alone are not evidence.

Service state transitions:
- process entry -> StartServiceCtrlDispatcherW;
- service-main -> RegisterServiceCtrlHandlerExW;
- report SERVICE_START_PENDING with bounded wait hint/checkpoint;
- create the stop event;
- report SERVICE_RUNNING only after successful initialization;
- HandlerEx accepts STOP and SHUTDOWN only, signals the stop event, and returns promptly;
- service-main waits on the stop event;
- report SERVICE_STOP_PENDING;
- close handles;
- report SERVICE_STOPPED with the real Win32 exit code.

Interrogate returns the current SERVICE_STATUS without changing state. Unsupported controls return ERROR_CALL_NOT_IMPLEMENTED. Repeated STOP/SHUTDOWN requests are idempotent. A failed dispatcher, handler registration, event creation, or status report must fail closed and return a nonzero process status; it must never report RUNNING after partial initialization.

## 4. Native source and build contract

- The service host source must be authored in Sharnou language and compiled by the repository's Sharnou compiler.
- No C# Add-Type production host, MSVC, LLVM, MinGW, CMake, MSBuild, external linker, generated placeholder PE, or handwritten executable bytes as a substitute for compiler output.
- PowerShell may orchestrate CI, install/start/stop the test service, inspect the PE, and collect evidence. It is not the production service implementation.
- The service binary must be built only on the approved Windows CI runner using the repository's actual compiler path.
- Service install tests must use a disposable uniquely named service and remove it in a finally block. The workflow must not install a persistent service on a developer workstation.
- The generated image must be inspected after compilation. The actual import table, entry point, sections, relocations, exception directory, and SHA-256 determine acceptance.

## 5. R5.1 Windows acceptance tests

1. Compile the service source using the repository compiler and record compiler/source hashes.
2. Verify PE32+, AMD64, subsystem Windows CUI, entry point, section bounds, imports, relocation directory, exception directory, and absence of unexpected imports.
3. Install a disposable service with a unique name and an explicit binary path.
4. Start it and observe SERVICE_RUNNING within a bounded timeout.
5. Send STOP; observe STOP_PENDING then STOPPED; verify process exit.
6. Repeat with SCM SHUTDOWN and SERVICE_CONTROL_INTERROGATE.
7. Inject initialization failures at dispatcher, handler registration, event creation, and SetServiceStatus boundaries; verify no false RUNNING state and no orphan process/handle.
8. Exercise repeated stop, stop/start cycles, timeout, and forced process termination.
9. Capture raw SCM query output, process exit status, service logs, PE import report, exact source SHA, executable SHA-256, and full test transcript.
10. Run the full frozen combined regression suite on the exact PR head.

R5.1 cannot pass if any lifecycle test is skipped, if the service host is only a test harness, if the import report is based on intended declarations rather than the final PE, or if the workflow did not test the exact source commit.

## 6. Later R5 dependencies

- R5.2: service SID, service identity verification, machine-scope non-exportable CNG signing key, strict private-key ACL, key lifecycle/rotation.
- R5.3: local named-pipe transport, client authentication, bounded framing and authorization binding.
- R5.4: service-owned authenticated durable journal and monotonic transaction state.
- R5.5: service-owned workspace/AppContainer/ACL/Job Object transaction.
- R5.6: crash, concurrency, restart, orphan cleanup, and operator recovery.
- R5.7: independent verifier, adversarial review, Windows 10 and Windows Server qualification.

The R5.0 protocol parser is a test-only contract fixture. It is not a transport, authentication mechanism, service implementation, or authority boundary.

## 7. Security state

R4 is Windows-CI-verified for its declared primitive/regression scope. R5.0 is Windows-CI-verified for its typed protocol parser and inherited regressions. Neither qualifies the R5 authority service.

Model-facing execution: DISABLED.
Autonomous execution: DISABLED.
Phase 2B.8 security acceptance: NOT ACCEPTED.
Production installation/rollout: NOT AUTHORIZED.


## R5.1.a - multi-target relocation implementation

The R5.1.a implementation is tracked in PR #33 and is based on this preflight branch. `Tools/SharnouPERelocations.ps1` now provides a shared builder/parser for canonical PE DIR64 base-relocation blocks. It validates 8-byte target alignment, image and approved initialized-data bounds, duplicate targets, page ordering, sorted offsets, DIR64-only entry types, ABS padding rules, bounded directory size and exact expected target sets. The compiler keeps the original one-target 12-byte .rdata anchor directory byte-for-byte stable. The PE verifier now parses the directory from the generated image instead of assuming exactly one block.

## R5.1.b - typed callback pointer and ABI probe implementation

The R5.1.b implementation is tracked in PR #34 (stacked on PR #33). The compiler now has an explicit callback-signature allowlist:
- `SERVICE_MAIN_FUNCTIONW`: `VOID WINAPI(DWORD, LPWSTR*)`.
- `HANDLER_FUNCTION_EX`: `DWORD WINAPI(DWORD, DWORD, LPVOID, LPVOID)`.

The code generator registers internal code labels in 8-byte .rdata pointer slots, aligns each slot, emits RIP-relative indirect calls through those slots, resolves each code-label VA after final code layout, writes the 64-bit VA into .rdata, and adds the pointer slot's RVA to the multi-target DIR64 relocation set. Unknown callback types, data-key collisions, unresolved labels, invalid pointer slot sizes, and out-of-range references fail compilation.

The test-only builtin `sh_win64_callback_abi_probe()` emits two compiler-owned leaf callbacks with the exact service-main and HandlerEx register widths. It exercises the callback addresses through the relocated pointer table, checks DWORD arguments and full-width pointer arguments in RDX/R8/R9, and fails the executable with a nonzero exit if any check fails. The callback leaf stubs modify only volatile registers and flags, do not allocate stack, and do not require unwind rows. The test additionally inspects the actual PE relocation targets and checks that both callback VAs point into .text, while preserving the original .rdata entry-point anchor.

This probe qualifies the pointer relocation and those two callback ABIs only. It does not start SCM, register a service, provide a production service-main routine, install a Windows service, add a named pipe, or enable execution authority.

## Current exact-head qualification

R5.1.a and R5.1.b have separate exact-head Windows workflows. Their acceptance state must be taken from the matching workflow run and inspected evidence bundle on the exact PR head. Do not infer a pass from successful file creation or a pending workflow.
