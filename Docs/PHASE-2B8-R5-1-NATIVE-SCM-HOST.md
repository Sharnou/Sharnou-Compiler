# Phase 2B.8 R5.1 - Native SCM service-host implementation gate

Status: R5.1.c implementation candidate is on an isolated branch; exact-head Windows SCM qualification is PENDING. No acceptance is claimed until the generated image and SCM evidence artifact pass on the exact source head.

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

The R5.1.b implementation is tracked in the correctly stacked PR #35 (stacked on PR #33). The compiler now has an explicit callback-signature allowlist:
- `SERVICE_MAIN_FUNCTIONW`: `VOID WINAPI(DWORD, LPWSTR*)`.
- `HANDLER_FUNCTION_EX`: `DWORD WINAPI(DWORD, DWORD, LPVOID, LPVOID)`.

The code generator registers internal code labels in 8-byte .rdata pointer slots, aligns each slot, emits RIP-relative indirect calls through those slots, resolves each code-label VA after final code layout, writes the 64-bit VA into .rdata, and adds the pointer slot's RVA to the multi-target DIR64 relocation set. Unknown callback types, data-key collisions, unresolved labels, invalid pointer slot sizes, and out-of-range references fail compilation.

The test-only builtin `sh_win64_callback_abi_probe()` emits two compiler-owned leaf callbacks with the exact service-main and HandlerEx register widths. It exercises the callback addresses through the relocated pointer table, checks DWORD arguments and full-width pointer arguments in RDX/R8/R9, and fails the executable with a nonzero exit if any check fails. The callback leaf stubs modify only volatile registers and flags, do not allocate stack, and do not require unwind rows. The test additionally inspects the actual PE relocation targets and checks that both callback VAs point into .text, while preserving the original .rdata entry-point anchor.

This probe qualifies the pointer relocation and those two callback ABIs only. It does not start SCM, register a service, provide a production service-main routine, install a Windows service, add a named pipe, or enable execution authority.

## Current exact-head qualification

R5.1.a and R5.1.b have separate exact-head Windows workflows. Their acceptance state must be taken from the matching workflow run and inspected evidence bundle on the exact PR head. Do not infer a pass from successful file creation or a pending workflow.


## R5.1.a and R5.1.b exact-head engineering results — 2026-11-27

### R5.1.a — ACCEPTED for relocation primitive scope

- PR #33, source head `2583faec76d5e469962756d17d2ffabecd6fcd98`.
- Windows Server 2025 x64 exact-head run [46066382172](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46066382172): SUCCESS.
- Focused PE relocation parser/builder suite 21/21; Stage 7A 24/24; Stage 5 collection 25/25; stack-probe/unwind 6/6; Runtime ABI PASS; broker and Phase 2B.8 primitive suites PASS; frozen M1-M6 83/83; Combined PASS.
- Exact-head acceptance manifest generated and verified against checked-out commit.
- Evidence artifact 15231785189, `r5-1a-relocation-evidence`, ZIP SHA-256 `698ebd55dfb66b529cd8b001aa986e4832e995e8f37a68f7906c7db19546b725`; bundle downloaded and inspected.
- Residual: the Low-IL AppContainer DPAPI protection subtest recorded `INCONCLUSIVE` because Windows PowerShell could not load `System.Security` (FileNotFoundException). This is not a pass and remains an outstanding Phase 2B.8 evidence gap.

### R5.1.b — ACCEPTED for typed callback-pointer/ABI primitive scope

- Corrected exact source head: `ab00219f1aa9783c148035b754eebce7269f6fbb`.
- Windows Server 2025 x64 run [46070065850](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46070065850): SUCCESS.
- Focused callback-pointer/Win64 ABI and relocation tests: PASS; combined regression: PASS; frozen M1-M6 baseline: 83/83 PASS.
- Exact-head manifest reports `acceptance=PASS` and `tested_commit=ab00219f1aa9783c148035b754eebce7269f6fbb`.
- Artifact 15232513039, `r5-1b-callback-abi-evidence`, ZIP SHA-256 `b246b9e588d06c956ce59ea6583b7da99f1d9a02f3e35df50e8a5fc9a99ed10f`; bundle downloaded and inspected.
- Residual: Low-IL AppContainer DPAPI protection remains `INCONCLUSIVE` because Windows PowerShell could not load `System.Security`. This is not a pass and remains an outstanding Phase 2B.8 gap.
- R5.1.b does not implement or qualify an SCM service. Model-facing and autonomous execution remain disabled.

### R5.1 boundary and next step

R5.1.a qualifies bounded multi-target DIR64 relocation generation and parsing. R5.1.b qualifies two callback-pointer ABI contracts. Neither creates an SCM service. R5.1.c is next: genuine Sharnou-generated inert Windows SCM host, SERVICE_TABLE_ENTRYW callback wiring, service status/control lifecycle, actual import-table verification, and disposable Windows service install/start/stop/shutdown/failure-injection tests.

No service SID, production CNG key, named-pipe transport, production signed journal, process execution authority or crash recovery is implemented yet. Full Phase 2B.8 remains NOT SECURITY ACCEPTED. Model-facing and autonomous execution remain DISABLED.


## R5.1.c - native Sharnou SCM service implementation candidate - 2026-11-28

Candidate branch: `phase-2b8-r5-1c-native-scm-host-20261128`, based on the corrected R5.1.b source head `ab00219f1aa9783c148035b754eebce7269f6fbb`.

Implementation added on the isolated branch:

- An opt-in `-EnableNativeScmServiceHost` compiler mode and a service-name argument restricted to 1-256 ASCII letters, digits, period, underscore or hyphen. The normal compiler catalog remains selected when the flag is absent; the native service mode exposes only the service-host intrinsic and rejects mixed DevAgent/callback-test modes.
- Sharnou source `Examples/NativeScmServiceHost.sharnou` invokes the dedicated `sh_native_scm_service_host()` intrinsic. A source gate rejects helper functions, imports, additional statements, or noncanonical service-host source in this mode.
- A real `SERVICE_TABLE_ENTRYW` row and all-zero terminator are emitted into .rdata. The service-name pointer, ServiceMain pointer, and HandlerEx pointer are typed code/data pointer fixups, resolved after code layout and emitted as full-width preferred-image VAs with DIR64 relocations.
- Compiler-emitted `SERVICE_MAIN_FUNCTIONW(DWORD, LPWSTR*)` and `HANDLER_FUNCTION_EX(DWORD, DWORD, LPVOID, LPVOID)` callbacks use framed Win64 functions with unwind metadata. ServiceMain registers HandlerEx, reports START_PENDING, creates a manual-reset stop event, reports RUNNING only after initialization, waits for STOP/SHUTDOWN, reports STOP_PENDING, closes the event, and reports STOPPED. HandlerEx signals the stop event for STOP/SHUTDOWN, returns success for INTERROGATE, and rejects unsupported controls.
- A service-only PE import profile allows exactly six KERNEL32 APIs and three ADVAPI32 APIs. The service-specific verifier checks the actual import table, directory sizes, embedded Unicode service name, service-table pointers, null terminator, and exact four-target relocation set (entry anchor plus three pointer slots). The existing general-purpose verifier profile is preserved.
- `Tests/Test-NativeScmServiceHost.ps1` compiles with the repository's Sharnou compiler, independently verifies the generated PE, creates a unique disposable own-process service, starts it through the real SCM, sends INTERROGATE and STOP, verifies STOPPED with PID zero, and deletes the disposable registration in a finally block.
- Workflow `.github/workflows/phase-2b8-r5-1c-native-scm-gate.yml` checks out the exact source head on Windows Server 2025, enforces source encoding, runs the focused SCM test and complete combined regression, and uploads an exact-head evidence bundle.

### R5.1.c qualification boundary

R5.1.c is ACCEPTED for its declared implementation scope on exact-head Windows run `46122764612`, tested source head `85efea1cd17ea03e5040dc6708d0dac1928dcfd5`. The generated executable and exact-head evidence artifact were downloaded and inspected; see the authoritative qualification record appended below.

The focused smoke gate is only R5.1.c implementation qualification. R5.1.d remains mandatory for deeper lifecycle/failure qualification: explicit observation of state transitions, shutdown coverage, dispatcher/registration/event/status failure injection, repeated cycles, timeout and forced termination, orphan detection, handle/process cleanup and recovery evidence. R5.2 remains blocked until R5.1.d passes. R5.3 remains blocked until R5.2 passes; R5.4 remains blocked until R5.3 passes.

Model-facing execution: DISABLED.
Autonomous execution: DISABLED.
Phase 2B.8 security acceptance: NOT ACCEPTED.
Production installation/rollout: NOT AUTHORIZED.


## R5.1.c exact-head acceptance record - 2026-11-28

### Scoped acceptance

**R5.1.c: ACCEPTED for native SCM image generation, independent PE verification, and the demonstrated Windows SCM lifecycle.**

- Exact tested source head: `85efea1cd17ea03e5040dc6708d0dac1928dcfd5`.
- Windows Server 2025 exact-head workflow: [46122764612](https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46122764612), SUCCESS. The workflow's exact-head checkout, encoding gate, native service test, full combined regression, acceptance-manifest generation, evidence collection and upload all completed successfully.
- Evidence artifact: `r5-1c-native-scm-evidence`, artifact id `15253524806`, 27,252 bytes, SHA-256 `7c4fda351a1fa7f117e6fa1615f5d521b3176d786d0cd2de502be5f20ec85556`. The downloaded archive hash was recomputed and matched the Actions artifact digest.
- Exact-head manifest: `acceptance=PASS`; `tested_commit=85efea1cd17ea03e5040dc6708d0dac1928dcfd5`.
- Generated `SharnouAuthorityHost.exe`: 8,704 bytes; SHA-256 `8623ed7fd37153a41b841cad632e30ac6965b5bfee0153a59e0880fb43e43f73`. The hash recomputed from the downloaded evidence artifact matched the service evidence JSON.
- Independent PE verification passed for AMD64 PE32+, the exact two-descriptor/nine-API service import profile, per-DLL API mapping, lookup/IAT terminators, embedded UTF-16 service name, SERVICE_TABLE_ENTRYW and callback pointer targets, the exact DIR64 relocation target set, and x64 unwind information.
- Actual SCM test passed: a unique disposable own-process service was created; RUNNING was observed; INTERROGATE succeeded; STOP moved through STOP_PENDING to STOPPED; SCM reported PID zero; and the service registration was deleted.
- The complete inherited combined regression reported `Combined result: PASS`. Focused totals in the log include Stage 7A 24/24, relocation 21/21, Stage 5 collection 2/2, stack-probe/unwind 6/6, PE verifier 4/4, Stage 2 25/25, Stage 4 20/20, Stage 5 25/25, and Stage 6 9/9; callback ABI, runtime ABI and DevAgent broker primitive gates reported PASS.

### Explicit residual limitation

The inherited combined regression log records an `INCONCLUSIVE` Low-IL AppContainer DPAPI protection diagnostic because the Windows PowerShell process could not load `System.Security` (FileNotFoundException). This diagnostic did not fail the combined regression or R5.1.c SCM gate, but it is not a pass and remains an outstanding Phase 2B.8 evidence gap. Resolve it in the security milestone that owns that test; do not treat R5.1.c acceptance as closing it.

### Next authorized implementation target: R5.1.d

R5.1.d is now the next authorized target. It must remain separate from the accepted R5.1.c smoke qualification and must include:

1. Explicit observation and assertion of START_PENDING, RUNNING, STOP_PENDING and STOPPED, including status fields, checkpoint and wait-hint bounds.
2. SERVICE_CONTROL_SHUTDOWN behavior in addition to STOP and INTERROGATE.
3. Deterministic test-only failure injection for dispatcher startup, HandlerEx registration, event creation, and each SetServiceStatus boundary. Injection controls must not be exposed in the default production compiler/service image.
4. Repeated start-stop and stop/start cycles, duplicate STOP/SHUTDOWN delivery, start/stop races, bounded timeouts and recovery after failed startup.
5. Forced termination and service-process crash tests; independently verify no orphan process, leaked event/handle, stale SCM registration, or incorrectly reported terminal state.
6. Cleanup/recovery tests after interrupted service deletion and after service process exit; retain raw SCM query output, process exit codes, event/fault identifiers and per-case evidence.
7. An exact-head Windows workflow, focused R5.1.d test report, complete inherited regression, and inspected evidence artifact.

R5.2 remains blocked until R5.1.d passes its own exact-head qualification. R5.3 remains blocked until R5.2 passes. R5.4 remains blocked until R5.3 passes.

Model-facing execution: DISABLED.
Autonomous execution: DISABLED.
Phase 2B.8 security acceptance: NOT ACCEPTED.
Production installation/rollout: NOT AUTHORIZED.


## R5.1.d implementation tranche — 2026-11-28

Implementation is isolated on `phase-2b8-r5-1d-scm-lifecycle-20261128`, based on the R5.1.c exact-head qualified source tip. The R5.1.c branch and its accepted evidence are not modified.

### Implemented on the R5.1.d branch

- Added explicit opt-in native SCM test mode, fault selector and bounded pending-state hold. Test controls are rejected without `-EnableNativeScmServiceTestMode`, and test mode is rejected unless the native SCM host mode is also enabled.
- Added deterministic failure injection for dispatcher startup, HandlerEx registration, event creation, and each of START_PENDING, RUNNING, STOP_PENDING and STOPPED `SetServiceStatus` boundaries.
- Added a test-only `Sleep` import at the reserved Kernel32 IAT slot. Production service imports remain the existing minimal nine-API profile.
- Added the `SHARNOU_R5_1_D_TEST_ONLY_V1` data marker to generated test images. The test verifier requires the marker and test import profile; the production verifier rejects the test-only profile.
- Corrected STOP_PENDING error handling so a successful `SetServiceStatus` call does not capture a stale thread last-error value.
- Added a Sharnou-generated callback probe that calls the actual emitted HandlerEx entry point with INTERROGATE, STOP, SHUTDOWN and duplicate STOP. It verifies that INTERROGATE does not signal the event and stop-class controls are idempotently signalled.
- Added a Windows lifecycle qualification script for visible pending/running/stopped states and fields, three start/stop cycles, a start/stop race, duplicate STOP attempt, forced process termination, post-crash restart, deferred deletion recovery and every fault point.
- Added a dedicated exact-head Windows Server 2025 workflow and evidence bundle, separate from R5.1.c.

### Qualification boundary and remaining work

The direct HandlerEx probe is callback-level evidence. It is **not** a real Service Control Manager shutdown broadcast. Windows does not allow an ordinary `ControlService` request to synthesize `SERVICE_CONTROL_SHUTDOWN`; that control is delivered by the operating system during shutdown. Do not report the direct callback probe as proof of OS shutdown delivery. The real shutdown broadcast still requires a disposable Windows VM/host test that can be safely shut down without destroying the CI runner.

R5.1.d is therefore **IMPLEMENTATION IN PROGRESS / EXACT-HEAD WINDOWS QUALIFICATION PENDING** until the dedicated workflow passes and its artifact is downloaded and inspected. Even after the declared workflow scope passes, full R5.1.d acceptance remains blocked on the isolated OS-shutdown delivery test and inspection of all lifecycle/fault artifacts. Do not advance to R5.2 before that acceptance.

The inherited Low-IL AppContainer DPAPI test remains INCONCLUSIVE for the previously documented PowerShell `System.Security` loading issue. This is a separate Phase 2B.8 security evidence gap.

Model-facing execution: DISABLED.
Autonomous execution: DISABLED.
Phase 2B.8 security acceptance: NOT ACCEPTED.
Production service rollout/key provisioning: NOT AUTHORIZED.
