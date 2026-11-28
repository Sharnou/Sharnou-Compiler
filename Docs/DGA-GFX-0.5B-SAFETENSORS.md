# DGA-GFX-0.5B - bounded Safetensors inspection and artifact provenance

**Increment:** DGA-GFX-0.5B candidate - container inspection and artifact-lock foundation  
**Parent:** DGA-GFX-0.5A PR #46, exact head 82bf0409ad2d32c4079b28f221838da24b0795b2  
**Runtime status:** PowerShell qualification reader only; native Sharnou reader NOT IMPLEMENTED  
**Activation:** BLOCKED

## 1. Objective

DGA-GFX-0.5B establishes a fail-closed, bounded reader contract for the Safetensors v1 container used by the reference model. It also records upstream artifact identity without pretending that a remote pointer hash is a local independent verification.

This is an inspection and qualification increment. The PowerShell module is a test oracle and artifact-preflight tool; it is not the production Sharnou model reader, does not load tensor payloads, does not allocate tensor storage, and does not enable inference.

## 2. Artifact provenance

Reference repository: HuggingFaceTB/SmolLM2-135M-Instruct  
Immutable repository revision: 02e84e7cc564d9c3ca090f978a4da4698ccaac29

### Weights

- Path: model.safetensors
- Format: Safetensors v1
- Exact byte count: 269060552
- SHA-256: 5af571cbf074e6d21a03528d2330792e532ca608f24ac70a143f6b369968ab8c
- Provenance: upstream Hugging Face Xet pointer at the pinned repository revision.
- Qualification state: PINNED_UPSTREAM_DIGEST; independent local Get-FileHash verification is still required.

The upstream raw pointer reports both the exact byte count and SHA-256. The repository does not contain the 269 MB model file and this change does not download it.

### Tokenizer and chat template

- tokenizer.json is revision-pinned to the same immutable repository commit.
- tokenizer_config.json, which contains the chat-template declaration, is revision-pinned to the same commit.
- Exact byte counts and SHA-256 values are not yet established in this repository.
- Both remain REVISION_PINNED_HASH_PENDING. They are not qualified and cannot be silently treated as pinned artifacts.

### License

The pinned model card declares Apache-2.0. No independently pinned license text file is established by this increment. The lock therefore records MODEL_CARD_DECLARATION_ONLY and keeps license qualification false. A separate license-file/provenance review is required before redistribution or runtime activation.

## 3. Safetensors v1 parser contract

The format reference defines an eight-byte little-endian unsigned header length, followed by UTF-8 JSON and then a tensor data buffer. Tensor offsets are relative to the beginning of that data buffer. Duplicate JSON keys are disallowed.

The inspection reader enforces:

- Regular file only; reject reparse-point paths.
- File length between 8 bytes and the configured 1 GiB cap.
- Header length between 2 bytes and 16 MiB, and fully contained in the file.
- Strict UTF-8 decoding and JSON object root.
- Duplicate-key rejection across all JSON objects, including escaped-equivalent property names.
- JSON nesting depth no greater than 48.
- Optional __metadata__ values must all be strings.
- Tensor records contain exactly dtype, shape and data_offsets.
- Candidate tensor dtype is BF16 only.
- Rank is 1 through 8; every dimension is a positive integer.
- Checked element-count multiplication and a bounded maximum tensor element count.
- Exactly two integer offsets, non-empty, inside the data region and BF16-element aligned.
- Tensor byte length must equal element count multiplied by two.
- Sorted tensor ranges must be contiguous: no overlap, no gap, no trailing unclaimed payload.
- Tensor count is capped at 4096.
- The reader reads only the fixed prefix and bounded JSON header. It never reads tensor payload bytes, maps the file, deserializes executable content, or executes anything.

This is intentionally stricter than a generic multi-dtype reader. Expanding supported dtypes requires a separately reviewed format and model compatibility change.

## 4. Artifact hash verifier

Test-GfxPinnedArtifactFile accepts a lock entry only when it has a full immutable revision, exact byte count, and 64-hex SHA-256. It rejects path traversal, reparse-point files, size mismatch and digest mismatch. Hashing is performed locally over the supplied file using the .NET SHA-256 implementation exposed by Windows PowerShell.

The command-line qualification script verifies the pinned weights when the owner supplies the local file path. It does not download artifacts or make network requests.

## 5. Current implementation boundary

Implemented in this candidate:
- Safetensors v1 bounded header inspector in PowerShell for Windows qualification.
- Strict artifact-lock schema and candidate provenance lock.
- Independent local artifact hash verification function.
- CLI for offline inspection of an owner-supplied weights file.
- Adversarial synthetic fixtures for malformed headers, duplicate keys, dtype, dimensions, overflow, byte-count mismatch, alignment, out-of-range offsets, overlap, gaps, trailing bytes, metadata type, truncation and configured limits.
- Windows PowerShell 5.1 workflow retaining DGA-GFX-0.3 and DGA-GFX-0.4 regression suites.

Not implemented:
- Native Sharnou-language Safetensors reader.
- Actual model-file inspection in CI or this PR.
- Tokenizer/chat-template digest pinning.
- Independent license-file verification.
- Tensor payload loading or mapping.
- Tensor kernels, tokenizer, transformer, KV cache, sampler or native inference.
- SharnouDevAgent model cognition or autonomous code generation.

The existing Sharnou compiler does not yet have a verified complete numeric/memory ABI for the planned FP32/BF16 inference path. This increment does not bypass that prerequisite.

## 6. Security boundary

No network, process launch, shell, dynamic-library loading, repository writes, model tool authority or model self-acceptance is added. The reader treats all model bytes as untrusted data. Model payloads are not executed or interpreted as code.

DGA-GFX readiness remains BLOCKED. Phase 2B.8/R5 remains a separate process-execution security gate.

## 7. Next gates

1. Supply the exact pinned model file and independently verify the local byte count and SHA-256.
2. Run the bounded header inspector against that actual file and compare every tensor record to the pinned architecture manifest.
3. Obtain tokenizer.json and tokenizer_config.json exact byte counts and SHA-256 values from immutable bytes; add them to the lock only after independent verification.
4. Obtain and review the actual license text/provenance for the selected repository revision.
5. Port the parser into Sharnou's native language only after the compiler's checked integer, byte-buffer, file-I/O and memory ownership contracts are verified.
6. Keep DGA-GFX-0.5C tokenizer implementation blocked until artifact identity and tokenizer-specific golden vectors are pinned.

## 8. References

- Safetensors format specification: https://github.com/huggingface/safetensors
- Safetensors JSON schema: https://github.com/huggingface/safetensors/blob/main/docs/safetensors.schema.json
- Pinned model repository: https://huggingface.co/HuggingFaceTB/SmolLM2-135M-Instruct/tree/02e84e7cc564d9c3ca090f978a4da4698ccaac29
- Pinned model weight pointer: https://huggingface.co/HuggingFaceTB/SmolLM2-135M-Instruct/raw/02e84e7cc564d9c3ca090f978a4da4698ccaac29/model.safetensors
- Pinned tokenizer: https://huggingface.co/HuggingFaceTB/SmolLM2-135M-Instruct/blob/02e84e7cc564d9c3ca090f978a4da4698ccaac29/tokenizer.json
- Pinned tokenizer configuration: https://huggingface.co/HuggingFaceTB/SmolLM2-135M-Instruct/blob/02e84e7cc564d9c3ca090f978a4da4698ccaac29/tokenizer_config.json
