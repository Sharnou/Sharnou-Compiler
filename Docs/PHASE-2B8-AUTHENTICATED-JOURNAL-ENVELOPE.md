# Phase 2B.8 - Authenticated Journal Envelope Contract

**Status:** TEST-ONLY FORMAT AND VERIFIER QUALIFICATION; NOT A PRODUCTION JOURNAL  
**Date:** 2026-11-27  
**Scope:** authenticate a bounded journal payload before profile/SID/descriptor metadata can be parsed or used.

## 1. Threat boundary

The previous Windows evidence establishes that CurrentUser DPAPI is not writer-process authentication. Any same-user process able to call the DPAPI API with the public optional entropy can create a different valid envelope. DPAPI must not authorize profile deletion, ACL restoration, or journal retirement.

The selected architecture assigns durable journal ownership to a dedicated Windows service with a dedicated service SID and a machine-scope non-exportable CNG signing key. The service constructs and validates its own transaction record. The broker must not receive the private key or a generic sign/MAC operation.

## 2. Outer signed-envelope v1

All integer fields are unsigned little-endian values. The envelope is bounded to 16,824 bytes and has exactly this layout:

| Offset | Size | Field | Required value |
|---:|---:|---|---|
| 0 | 8 | Magic | ASCII `SHASIG1!` |
| 8 | 4 | Format version | 1 |
| 12 | 4 | Algorithm | 1 = RSA-3072 / RSA-PSS / SHA-256 |
| 16 | 32 | Key identifier | SHA-256 of the pinned CNG `GenericPublicBlob` |
| 48 | 4 | Payload length | 80..16,384 |
| 52 | 4 | Signature length | 384 |
| 56 | N | Payload | Exact canonical inner journal bytes |
| 56+N | 384 | Signature | RSA-PSS/SHA-256 signature |

The signed input is the ASCII domain separator `Sharnou.DevAgent.AuthenticatedJournal.Signature.v1\0` followed by every byte from offset 0 through the end of the payload. This covers the magic, format, algorithm, key identifier, both lengths and exact payload bytes. The signature itself is not included in the signed input. The fixed signature length is included in the signed header.

The key identifier is not a key locator supplied by the journal. It must match a public key already pinned by the service's protected configuration/key registry. Unknown identifiers, unsupported algorithms and retired keys with no remaining journal ownership are rejected. Rotation must preserve verification for every still-open journal; key loss must quarantine, not regenerate-and-accept.

## 3. Verification order

The parser may inspect only bounded outer framing before authentication: magic, version, algorithm, key identifier, payload length and signature length. It must reject overflows, truncated data, trailing bytes and unsupported values before allocating the payload.

Then it must:

1. Resolve the key identifier only against the service-owned allowlist of pinned public keys.
2. Verify RSA-PSS/SHA-256 over the domain-separated exact header and payload.
3. Only after signature success, parse the inner record and validate its schema.
4. Validate the registered workspace by opening it and independently comparing the final canonical path, volume serial and full 128-bit file ID.
5. Validate each security descriptor and allowed state transition before any restore or deletion operation.

A signed but semantically invalid record is rejected. A record with a valid signature is not an instruction to execute arbitrary descriptor restoration or profile deletion.

## 4. Test fixture and explicit limitations

The Windows test fixture uses an ephemeral test-only RSA-3072 CNG key. It exercises positive verification, a wrong pinned key, an attacker-generated envelope using a different key, tampered payload/signature, unsupported version/algorithm, bad lengths, truncation, trailing bytes, and a valid signature over an invalid inner record.

The fixture is not a production service key. It does not qualify non-exportability, service-SID private-key ACLs, machine-key provisioning, key rotation, service restart, typed IPC, journal durability, path identity, native descriptor semantics or crash recovery.

The existing version-2 payload fixture is also not yet the complete service record. Before production integration, the service-owned canonical record must bind, at minimum:

- Execution GUID, canonical AppContainer profile name and exact package SID.
- Registered workspace final path, volume serial and full 128-bit file ID.
- Fixed tool identifier and exact pinned SHA-256.
- Original root, Build and broker security descriptors, validated as actual self-relative Windows descriptors.
- Security-policy version, transaction state and monotonic transition sequence.
- Service key identifier in the outer envelope.

The service must validate these fields against its own opened handles, tool registry and transaction table. Caller-supplied values are requests, not authority.

## 5. Persistence and recovery rules

The service-owned journal must be stored outside user-writable workspace directories. Write to a new exclusive temporary file, write the complete envelope, flush the file, close it, and atomically commit it with write-through semantics before applying any ACL expansion. Recovery must open by handle, validate file type/link/reparse/path and service-directory identity, verify the signature before reading privileged payload metadata, then verify workspace identity and descriptor semantics.

Restore parent descriptors before descendants. Confirm the service-owned Job Object is empty, restore and read back exact DACL/SACL state, derive the AppContainer SID from the authenticated profile name and compare it to the authenticated SID, then delete only the profile owned by that transaction. Retain the journal and quarantine the workspace on any mismatch or failed restoration/deletion. Retire the journal only after every cleanup predicate is independently verified.

## 6. Gate

This increment qualifies only the outer signature-envelope format and verifier ordering when Windows CI passes on one exact commit. It does not change the emitted broker, migrate the v1 journal, implement the Windows service, or enable restart-time profile deletion.

Model-facing/autonomous process execution remains **DISABLED**.
