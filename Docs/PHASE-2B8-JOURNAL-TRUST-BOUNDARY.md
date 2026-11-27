# Phase 2B.8 - Journal Protection Trust Boundary

**Status:** DESIGN GATE - DPAPI PRIMITIVE QUALIFIED; PRODUCTION WRITER AUTHENTICATION NOT APPROVED  
**Date:** 2026-11-27  
**Applies to:** native DevAgent ACL journal, profile metadata and crash recovery.

## 1. What the current Windows evidence proves

The dedicated Windows Phase 2B.8 workflow has demonstrated that the test fixture can:

- protect and unprotect a canonical version-2 journal payload with `CryptProtectData` and `CryptUnprotectData`;
- use user-scope DPAPI (the implementation deliberately does not set `CRYPTPROTECT_LOCAL_MACHINE`);
- bind decryption to the same optional entropy supplied at protection time;
- detect modifications to selected bytes of the protected envelope;
- reject unsupported journal versions, truncation, trailing bytes, an invalid profile-name length, and missing workspace volume identity;
- keep the magic, profile name and package SID out of the protected envelope as cleartext.

The test is a native Windows API and serialization qualification. It does not prove that the compiler-emitted broker is using DPAPI, and it is not an approval to migrate the production journal.

## 2. Important limitation: DPAPI does not identify the writer process

User-scope DPAPI derives protection from the current user's DPAPI context. Optional entropy is additional input to the derivation; it is not a private signing key. A process running as the same user can generally call `CryptProtectData` itself with the same optional entropy and generate a different, valid DPAPI envelope.

Therefore:

- DPAPI tamper rejection is evidence against arbitrary byte-level file modification by an actor that cannot invoke the same protection context.
- DPAPI user-scope protection is not proof that a particular trusted broker instance created a journal.
- A constant embedded entropy string does not establish process identity or writer authenticity.
- A test-only round trip does not establish a protected key boundary against another process running as the same user.

Do not describe the existing DPAPI primitive as an authenticated writer identity mechanism. Do not use a successfully decrypted profile name as sufficient authority to delete an AppContainer profile.

## 3. Required trust-anchor decision before native journal integration

The production design must define who is allowed to create a valid recovery record, not only who can decrypt it. The key/verification authority must be unavailable to the sandbox child and to any same-user process included in the threat model.

Candidate directions that require a separately reviewed design:

1. A dedicated broker service identity (for example, a service SID) owns a non-exportable signing key or protected journal key. The interactive broker submits a bounded transaction to that service through an authenticated IPC contract. The service performs or authorizes journal protection and recovery.
2. A distinct, installation-provisioned key whose private-key ACL is enforced by a separate OS security principal and whose use is brokered by a privileged service. Merely placing a key file under the workspace or protecting it with the same user's DPAPI does not create this separation.
3. If the accepted threat model excludes malicious same-user processes, document that exclusion explicitly and obtain owner/security approval before relying on user-scope DPAPI for the narrower threat model. This is not equivalent to same-user process isolation.

Do not silently select one of these options. The chosen trust anchor, provisioning/rotation, recovery after user-profile reset, backup/restore behavior, access-control owner, and failure/quarantine behavior must be specified and independently reviewed.

## 4. Version-2 record contract under test

The current strict fixture schema uses:

- 8-byte magic `SHARJNL2`;
- explicit version 2;
- non-empty 128-bit execution identifier;
- bounded canonical AppContainer profile name;
- canonical AppContainer package SID;
- 64-bit volume serial plus the full 128-bit `FILE_ID_128` from Windows `FILE_ID_INFO`; a legacy 64-bit file index is not a sufficient canonical identity.
- exactly three bounded security-descriptor records (workspace root, Build, broker directory);
- explicit security-policy version 2;
- no trailing bytes.

The fixture parser validates the bounded wire shape and rejects malformed variants. In production, every descriptor must additionally pass native security-descriptor validation, exact descriptor-length checks, and expected-object/path identity validation before any restore operation. The workspace file identity must be read from a handle to the validated canonical workspace root; a test constant is not sufficient.

The outer journal must be written to an exclusive temporary file, completely written, flushed, closed, and atomically committed before ACL expansion. The protected plaintext and outer envelope must both have strict size ceilings and exact length checks.

## 5. Fail-closed recovery rules

- Unknown versions, malformed lengths, invalid descriptors, missing workspace identity, DPAPI failure, trust-anchor failure, wrong user context, or a failed profile deletion must retain the committed journal.
- No ACL restoration may use unauthenticated or unvalidated profile metadata.
- Recovery must restore exact parent and descendant descriptors, verify the restored descriptors, and only then attempt per-execution profile cleanup.
- Do not retire the journal until all required descriptor restores and profile lifecycle actions are confirmed.
- If the trust-anchor key is unavailable (for example, after user-profile reset or service-key loss), quarantine and require operator recovery; do not guess, reinterpret v1 as v2, or delete profiles based on untrusted data.

## 6. Current disposition

The Windows primitive tests are green on the exact implementation branch at the time of the recorded evidence. The native broker still uses the stable shared AppContainer profile and version-1 ACL journal. No production DPAPI journal, per-execution profile creation, authenticated profile cleanup, or crash-recovery changes have been made.

**Gate:** select and approve a real writer-authentication trust anchor before changing the native broker journal format or using persisted identity metadata for privileged cleanup.
