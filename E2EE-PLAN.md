# GojoMessages end-to-end encryption — plan of record

Single source of truth for the E2EE build. Decisions below were taken with the
owner on 2026-08-04; technical claims marked *verified* were tested against the
real artifacts, not assumed.

## Decisions

| Question | Decision |
|---|---|
| Scheme | **Double Ratchet via libsignal** — not hand-rolled DH. PCS, skipped-message handling and PQ (Kyber) prekeys are exactly the parts that are miserable to build correctly. |
| First-cut scope | **1:1 text + media.** Groups stay plaintext this round. |
| libsignal integration | **Vendored prebuilt** `libsignal_ffi.a` as a local SwiftPM package. No Rust toolchain, no CocoaPods, CI keeps `-project GojoGo.xcodeproj`. |
| Build order | **Envelope first, cipher last.** The full wire/product refactor ships behind a no-op cipher; libsignal swaps in once everything around it is proven. |
| Push (first cut) | **Generic text** ("New message from Amr"). Server stops rendering message content into APNs. |
| Push (later) | **Notification Service Extension** decrypts on-device and rewrites the banner — how Signal shows content. Generic text remains the fallback path forever. |
| History | **Local-first message store** on device. Forced, not chosen — see below. |
| Backup / restore | **CloudKit (encrypted DB) + iCloud Keychain (keys), silent restore.** No user-visible recovery code on the mainstream path; manual recovery code only as the iCloud-off fallback. |
| Reinstall identity | **Identity keypair rides in the encrypted backup** → a legitimate reinstall keeps the same identity and contacts see nothing. Ratchet **session states are never backed up** — stale ratchets fail silently; sessions re-establish fresh via the prekey directory under the unchanged identity. |
| "New device" UX | Neutral in-thread line ("Amr is using a new device"), never a scary modal. Strong warning reserved for a fingerprint mismatch on a contact the user explicitly **verified**. |
| Multi-device | Unsupported in v1, **schema-ready**: `deviceId` in the key directory and envelope from day one, hardcoded to 1. |

## Two consequences that reshape the architecture

**1. Double Ratchet makes server history unreadable — by design.** Each message
key is deleted after one use (that deletion *is* forward secrecy), so a
ciphertext decrypts **exactly once, ever**. The server's stored messages become
one-time deliveries, not an archive. Today's model — refetch pages from DynamoDB
on every open (`reloadLiveConversation`, `loadOlderWorldMessages`) — cannot
survive: messages must land in a **persistent local store at decryption time**,
and the server only serves ciphertext not yet decrypted. Side effect: chats open
faster than today.

**2. The trust model changes knowingly.** Identity keys in iCloud Keychain put
Apple's escrow (passcode-gated, HSM-backed, E2E-encrypted, unreadable by Apple
per their design) inside our trust boundary. Signal-style purists keep keys
device-only precisely to avoid this. Accepted deliberately: the guarantee we are
building — *our backend and AWS cannot read DMs* — is fully intact, and safety
numbers still catch key substitution. A device-only "paranoid mode" is possible
later.

**What v1 honestly is:** "1:1 conversations are end-to-end encrypted; groups are
in transit-encrypted storage." Do not claim more anywhere user-facing.

## Where plaintext lives today (all on the critical path)

| # | Surface | Where |
|---|---|---|
| 1 | Message body | `StoredMessage.text` → DynamoDB `text` attribute |
| 2 | List preview | `preview` denormalised onto **every participant's** membership row (`MessagingRepository.appendMessage`) |
| 3 | Push alert text | `MessageSent.preview` → `MessageNotificationListener` → APNs body |
| 4 | Reply snippets | `replyJson` — quoted text of the replied-to message |
| 5 | Polls | question + option labels |
| 6 | Media | uploaded unencrypted to S3/CDN via `APIClient.uploadMedia` |

## libsignal integration facts *(verified 2026-08-04)*

- **Remote SPM does not work, ever:** libsignal's Swift package links its Rust
  core with `linkerSettings: [.unsafeFlags(...)]`, and SwiftPM forbids
  `unsafeFlags` in remote dependencies. Local (path-based) packages are exempt —
  which is why Signal-iOS vendors it, and why we do.
- **No Rust toolchain needed:** Signal publishes the prebuilt static library its
  own podspec downloads: `build-artifacts.signal.org/libraries/libsignal-client-ios-build-v<V>.tar.gz`
  (151 MB, v0.99.3, fetch verified). It contains **binaries only** — three
  slices (`aarch64-apple-ios` 169 MB, `aarch64-apple-ios-sim` 196 MB,
  `x86_64-apple-ios` 196 MB), no Swift. The Swift sources come from the git tag
  and **must match the binary version exactly** — the FFI is a C ABI and a
  mismatch fails at runtime, not link time.
- **XCFramework wrapping fails — do not retry it:** `xcodebuild
  -create-xcframework` dies with `Unknown header: 0xb17c0de` (LLVM bitcode
  magic). The archive is *mixed* — mostly Mach-O with Rust LTO bitcode members
  that trip the architecture probe. It links fine; it cannot be wrapped.
- **Therefore link the `.a` directly** (what the podspec does): the local
  package ships only Swift sources + the `signal_ffi.h` module map and performs
  no linking; the **app target** carries `OTHER_LDFLAGS = -lsignal_ffi` and a
  per-destination `LIBRARY_SEARCH_PATHS`. Device and simulator slices stay in
  **separate directories** — both are arm64, differing only by platform, so they
  must never be `lipo`'d together (sim-arm64 + x86_64 *are* merged).
- `scripts/fetch-libsignal.sh` exists; fetch, version pairing and layout
  discovery verified. Its packaging step still reflects the dead XCFramework
  approach and needs rewriting to the per-destination layout.

## Day-one rules (cheap now, unfixable later)

The server can never migrate data it cannot read, so these go in from the first
commit even though v1 doesn't use them:

1. `deviceId` in the key-directory schema and the message envelope (hardcoded 1).
2. Session store and key material live in **App Group** locations (shared
   container + shared keychain access group) so the future Notification Service
   Extension can read them without migrating live cryptographic state.
3. Identity keypair stored **wrapped and backup-eligible**; ratchet session
   states flagged **never-backup**.
4. Envelope carries `envelopeVersion` from message one; a missing `cipherBody`
   means legacy plaintext and must render forever.

## Phases

### Phase A — envelope + local store, no-op cipher *(in progress)*
The whole cross-cutting refactor while every payload is still readable — the
"cipher" is an identity transform, so any blank bubble has exactly one suspect.

**Scope refinement (2026-08-04), discovered against the real send path:** two
things stay *outside* the envelope on purpose. **Polls** — the server tallies
votes by mutating the stored poll, which an opaque body can't support; polls
are group-shaped anyway and groups are out of v1. **Media URLs** — the server
reference-counts uploads by URL (`media.markReferenced`), so the pointer stays
visible and Phase D encrypts what's *behind* it. A shared pin's coordinates
are content, so envelope location messages carry them in the payload and skip
the legacy geo media item entirely.

**Landed (builds green, messaging tests green, legacy regression verified):**
- Backend: `SendMessageRequest`/`MessageDto`/`StoredMessage` carry
  `envelopeVersion` + `cipherBody`; stored and echoed opaquely through send,
  fetch, socket fanout, and scheduled delivery. `previewFor("encrypted")` →
  constant `"Message"`; push/reply `snippet` → `"New message"`.
- iOS: `WorldEnvelope` codec (`WorldEnvelopePayload` v1, `WorldMessageCipher`
  protocol, identity-transform `WorldPlaintextCipher`). Send path wraps 1:1
  non-poll content; receive path opens envelopes with per-message fallbacks —
  a payload from a newer build renders as "needs a newer version of GojoGo",
  never as silence. Envelope reply cards are self-contained and carry
  `replyAuthorId` + *canonical* name (a viewer's private rename must never
  ride in a payload the other side reads). Merge keeps locally-derived
  previews from being clobbered by the server's `"Message"` constant.
- No plaintext fallback when sealing fails, deliberately: after Phase C that
  would be a downgrade-attack surface. A message that can't be sealed isn't
  sent.

**Envelope live since 2026-08-04.** The envelope-aware backend deployed green
(`fecbce2`), `WorldEnvelope.sendingEnabled` flipped to `true`, and an envelope
message was verified against the **live API**: sent, cold-restarted the app,
and the message came back from the server as `kind: "encrypted"` +
`cipherBody` and rendered its text. (A backend that dropped the body would
have rendered the "can't be displayed" fallback — that render path is itself
the detector.)

**Local message archive landed** (`WorldMessageArchive`): one JSON file per
conversation under Application Support,
`completeUntilFirstUserAuthentication` file protection (the keychain tokens'
standard), debounced writes, wiped on sign-out and on thread delete. Persisted
from every mutation site via `archiveWorldMessages(_:)`; threads seed from it
in `openWorldConversation`, and list previews fall back to
`lastPreview(_:)` when the server's row says the `"Message"` constant. Media
*bytes* deliberately not archived — URLs only; `ImageCache` keeps the bytes.
Verified: cold start rendered the thread from disk while "Connecting…" was
still up, and the archive-derived preview showed on the list before any fetch.

**Remaining for Phase A:**
- Two-build exchange (needs a second signed-in account/device — single-account
  round-trip through the live server is verified).
- Push generic-text check on a real device (the backend change is deployed;
  APNs doesn't reach the simulator).
- Later, with the ratchet: server fetch narrows to "new ciphertext only" —
  today the fetch still reconciles full pages, which is correct while the
  no-op cipher makes server copies re-readable.

### Phase B — key infrastructure *(parallel-safe; touches no product surface)*
- Rewrite `fetch-libsignal.sh` packaging → per-destination layout; local package
  `Vendor/LibSignalClient/` (manifest tracked; `Sources/` and `lib/` gitignored
  — ~560 MB must never enter git history).
- The five protocol stores (`IdentityKeyStore`, `SessionStore`, `PreKeyStore`,
  `SignedPreKeyStore`, `KyberPreKeyStore`) on App-Group storage per the rules
  above. `KeychainStore` grows a `Data` API.
- Backend key directory: `PUT /v1/keys` (publish bundle),
  `GET /v1/keys/{profileId}/{deviceId}` (**atomically consumes** one one-time
  prekey), `GET /v1/keys/count` (client tops up).
- CI: add `Vendor/` to `cache_paths` in **both** workflows (today's cache only
  covers `$HOME`; the repo checkout is wiped every build, so without this every
  push re-downloads 151 MB). TestFlight workflow fetches the device slice only;
  the compile-check workflow the simulator slices only.
- **Done when:** `IdentityKeyPair.generate()` runs on device and a session
  establishes between two simulators via the directory.

### Phase C — swap the cipher
- Replace the identity transform with libsignal session encrypt/decrypt.
- A thread goes encrypted only when **both** sides have published bundles;
  mixed threads keep working. Failures here have one suspect by construction.

### Phase D — media
- Random per-file key, AES-GCM over the bytes **before** `uploadMedia`; key +
  nonce travel inside the encrypted body. CDN stores ciphertext.
- `ImageCache` / `MediaImage` / viewer decrypt on fetch; cache **decrypted**
  bytes only.

### Phase E — safety numbers *(v1 requirement, not polish)*
- Identity fingerprint on the contact page + explicit verify action. Until users
  can compare fingerprints, the key directory could substitute keys silently —
  the directory is trusted infrastructure exactly until this ships.

### Phase F — backup & restore *(the WhatsApp behaviour, minus the code)*
- Continuous encrypted export of the local store → CloudKit private DB; backup
  key + wrapped identity key → iCloud Keychain (`kSecAttrSynchronizable`).
- Reinstall: phone verify (exists) → find CloudKit backup → key from iCloud
  Keychain → silent restore, same identity, fresh sessions. Contacts see nothing.
- Manual recovery code only as the iCloud-off fallback.

### Phase G — notification previews (NSE)
- New extension target + App Group (storage already positioned by day-one rules).
  APNs payload carries the envelope when ≤ 4 KB (`mutable-content: 1`); larger →
  fetch by id (auth token via shared access group).
- **The hard part:** decryption advances the ratchet, and the NSE and app are
  two processes — one serialized session store with file coordination, or
  double-decrypt corrupts sessions. This is why G is last.
- Codemagic: second bundle id through `xcode-project use-profiles`.

## Known limitations (accepted)

- **Groups plaintext** in v1. Pairwise DH doesn't cover them; sender-keys or MLS
  later — the envelope is protocol-agnostic on purpose.
- **Search** covers only locally-decrypted history (in practice: everything this
  device has ever seen, thanks to the local store).
- **Multi-device** deferred; schema-ready via `deviceId`.
- **Server-side previews are gone** — that is the point, not a regression.
