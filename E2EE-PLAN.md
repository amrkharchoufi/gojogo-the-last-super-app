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

### Phase B — key infrastructure *(core landed 2026-08-04)*

**Landed and verified:**
- Vendoring works end to end: `fetch-libsignal.sh` lays slices out per
  destination (`lib/device`, `lib/simulator` — sim arm64+x86_64 lipo'd, device
  arm64 kept separate), pairs them with version-matched Swift sources, and the
  local package `Vendor/LibSignalClient/` builds. Key discovery: upstream's
  `unsafeFlags` is only on its *test* target, and SignalFfi's module map says
  `link "signal_ffi"` — so the manifest needs **no linker settings at all**;
  the app carries only sdk-conditional `LIBRARY_SEARCH_PATHS`.
- **Runtime proof:** `libsignal alive — identity fingerprint: 05928e4f…` from
  the simulator — the Rust FFI executes, not just links. (Temporary smoke test
  in `GojoGoApp.init`; replaced when the publish flow lands.)
- The five protocol stores on `WorldSignalStore`: identity in the Keychain
  (wiped by `clearAll()` on sign-out, so account-bound for free), sessions/
  prekeys/peer identities as protected files, **excluded from backup**
  (per the plan: stale ratchets must never ride a restore; the identity's
  backup path is separate). Base directory prefers the App Group container
  (`group.com.gojo.gojogo`) and falls back to Application Support until the
  entitlement lands. TOFU identity trust; changed keys surface, not auto-trust.
  Note: the app's own `SessionStore` (auth) collides with libsignal's protocol
  name — qualify as `LibSignalClient.SessionStore`.
- Backend key directory in `messaging`: `PUT /v1/keys`,
  `GET /v1/keys/{profileId}/{deviceId}` (one-time prekey consumed via
  conditional-delete-with-retry, so no two senders get the same one; empty pool
  degrades gracefully per X3DH), `GET /v1/keys/count`. `deviceId` in every row
  and path, only `1` accepted. Known v1 gap, documented in the controller: any
  authenticated caller can drain a prekey pool; rate limiting belongs at the
  gateway.
- CI: `Vendor/` cached in both workflows, `vendor_libsignal` step before
  package resolution. (Both workflows fetch the full archive — the 151 MB tar
  isn't separable per slice server-side; the cache makes it a one-time cost.)

**Publish flow landed and verified against the live directory.**
`WorldKeyPublisher.syncIfNeeded()` runs detached on messaging connect: publishes
on first run, tops up when `/count` drops below 20, no-ops otherwise. Private
halves are written to the store *before* the PUT — a bundle the server could
hand out while this device had lost the private half would poison every session
started from it. Prekey ids count monotonically across batches (a reuse would
collide in the directory's zero-padded sort keys). The Phase B smoke test in
`GojoGoApp.init` is retired; the publisher is the real bootstrap now.

**Proof (on-device key store, live server):** after connect, the store held 50
one-time prekeys, 1 signed prekey (id 1), 1 Kyber prekey (id 2),
`nextPreKeyId: 53`, and `published: true`. That flag is written *only* after the
`PUT /v1/keys` returns 204 — so its presence is proof the publish reached the
deployed directory (`30910738705`, green). Backend deploy for the directory
itself also green.

**Phase C gate: PASSED (`WorldSignalSelfCheck`, 2026-08-04).** The two-party
handshake needs a second account, but the two-*store* handshake needs only a
temp directory — and exercises the same five protocol implementations the live
path will use. The loopback runs the real X3DH + Double Ratchet between two
isolated `WorldSignalStore` instances and verifies:

1. `processPreKeyBundle` turns a published bundle into a stored session
2. The first message is a **PreKey** message and opens via `signalDecryptPreKey`
3. The one-time prekey is **spent** — reuse would break the guarantee
4. The session is bidirectional (reply is a **Whisper** message and opens)
5. **Cold start**: brand-new store instances over the same directories still
   decrypt — wrong session persistence would pass every other check and break
   on the app's second launch instead
6. The ratchet **advances** — identical plaintext twice yields different bytes
7. **Out-of-order** delivery decrypts (skipped message keys retained) — this is
   what a dropped socket actually produces, and what `resyncWorld()` guarantees
   will happen in production
8. Ciphertext is **opaque** — the plaintext is not sitting inside it

Why this gate exists: a ratchet deletes each message key on use, so a message
encrypted through a subtly wrong store is not "broken", it is permanently
unreadable by anyone, forever. That is not a defect to discover in production.

**Remaining, needs a second account:** confirm two real devices establish a
session through the deployed directory. Everything up to that point is proven.
**Also pending:** first CI run with the `vendor_libsignal` step (watch the cache
warm on run 2).

### Phase C — swap the cipher *(landed 2026-08-04, unverified against a second account)*

The identity transform is gone. `envelopeVersion` now says which envelope a
message is: **1** is Phase A (opaque to the server's rendering, but readable by
anyone holding the row), **2** is sealed to a libsignal session. Both stay live
on the wire — a thread reaches 2 only once the peer has published a bundle, and
one that never does keeps working at 1.

**Landed:**
- `WorldSignalSession`: address derivation (profile id + `deviceId` 1,
  lowercased without exception — the address name *is* the session filename, so
  a case difference would silently open a second empty session with the same
  person), X3DH from a directory bundle, and the one piece that is ours rather
  than Signal's: a leading byte carrying `CiphertextMessage.MessageType`.
  libsignal's ciphertext doesn't say which of the two types it is and they open
  through different functions.
- `WorldEnvelopeVault`: the decrypt-once ledger. Two facts force it. A message
  key is deleted on use, so a ciphertext opens **exactly once** — and the app
  refetches the newest page on every thread open. And a sender **cannot read
  its own ciphertext**, which is sealed to the peer's ratchet; outgoing
  payloads are banked at seal time under the *client* id, then re-keyed onto
  the server id on the first echo (fetched pages carry `clientId`, so a send
  interrupted before the response still resolves after a relaunch). Failures
  are deliberately never banked — some are transient (files locked before first
  unlock, profile id not loaded yet) and would otherwise become permanent.
- Downgrade rule, enforced at the send path: the readable envelope is legal
  only for a peer who has published **no bundle at all**. That is a property of
  the peer, not of one attempt — so once a session exists, a failure throws and
  the message isn't sent rather than falling back.
- Identity-change recovery on both send and receive: `untrustedIdentity` drops
  the stale session/identity and retries once. Refusing forever would brick a
  thread on a legitimate reinstall. It is not silent — `AppState` drops the
  neutral in-thread line ("… is using a new device"), which per the plan's
  decision is a line and never a modal.
- The merge gained its one exception to "server wins": a refetched copy of a
  message this device already opened arrives unreadable, so `isUndecryptable`
  yields to the local/archived copy. Without it, every reload would rewrite
  history into error bubbles — the exact failure the local-first store exists
  to prevent.
- Sign-out now wipes the vault **and the signal store**. The store held
  `published: true`, so the next account on the device would have been told its
  keys were already in the directory and would never have published at all.

**Phase C gate extended and passing (`WorldSignalSelfCheck`, 2026-08-04):** the
loopback now also drives the code the app calls, not just libsignal — a
directory DTO rebuilt into a working `PreKeyBundle`, the frame byte tagging
PreKey and Whisper correctly (wrong, and every message is unreadable in one
direction), a replayed ciphertext proven *fatal* rather than merely
discouraged, and a reinstalled peer recovered from. Verdict on the simulator:
handshake, ratchet, persistence, opacity, framing, replay fatality and
reinstall recovery.

**Two-party exchange verified end to end (2026-08-04, live server, two
simulators, two accounts).** Bob → Alice, then Alice → Bob:

1. Both devices published bundles: **50 one-time prekeys each** in the deployed
   directory.
2. Bob's first message spent one of Alice's — her pool went **50 → 49**. X3DH
   ran against the live directory, not a loopback.
3. That message is stored as `kind: "encrypted"`, `envelopeVersion: 2`,
   `text: null`, **1831 bytes** whose frame byte is `3` (**PreKey** — it carries
   the identity key, base key and Kyber ciphertext, which is why it is large).
4. Alice's reply is **105 bytes**, frame byte `2` (**Whisper**). That is the
   load-bearing detail: libsignal only emits a Whisper from a session
   established *by decrypting* the peer's PreKey message. A Whisper existing at
   all proves Alice's device opened Bob's message.
5. Both vaults hold the plaintext for **both** messages — each device's own
   under the server id *and* under the client id it was sealed with, the
   re-key working exactly as designed.
6. Neither plaintext appears anywhere in either ciphertext; the stored row
   carries only ids, sender, timestamp and the blob, and the conversation
   preview is the `"Message"` constant.
7. **Cold start of both apps: zero decrypt failures.** Without the vault the
   re-fetched page would have asked libsignal to reopen spent ciphertext and
   rendered two "couldn't be decrypted" bubbles. Alice's archive re-read
   `them: "Hy Alice"` / `me: "Hey bob"`, in order.

Nothing about Phase C is unverified now. The one thing still owed from Phase A
is the push generic-text check, which needs a real device (APNs does not reach
the simulator).

### Phase D — media *(built 2026-08-04, not yet exercised between two devices)*

Phase C sealed the text; a photo still went to the CDN in the clear, which made
the honest claim "end-to-end encrypted unless the message contains a picture".

**Landed:**
- `WorldMediaCrypto`: one random AES-256-GCM key per file, used once. The nonce
  rides inside CryptoKit's `combined`, so the payload carries only the key. GCM
  and not CBC because the tag makes a rewritten CDN object fail loudly rather
  than decode to something subtly different.
- The key travels in `WorldEnvelopePayload.mediaKeys` — `url -> base64 key`,
  keyed by URL rather than positionally, because a video's poster and its movie
  are two files on one item and wire order is not something a receiver should
  have to trust. So media inherits exactly the ratchet's protection.
- **The URL stays visible**, per Phase A: the server reference-counts uploads by
  URL. What leaks is that a message has an attachment and roughly its size.
- `WorldMediaSealer` bridges the ordering problem — a key exists before its URL
  does, because the file has to be encrypted to be uploaded. Inactive by
  default, so avatars, story frames and marketplace photos use the same upload
  helpers untouched.
- **Decryption is by URL lookup, not by threading keys through views.** Every
  media surface in the app addresses a file by URL alone, so a persisted
  `WorldMediaKeyStore` lets `ImageCache` decrypt transparently. `MediaImage`,
  `CachedAsyncImage`, the feed, stories and the marketplace are all unchanged,
  and a URL with no key is used verbatim — which is what keeps every non-chat
  image and every pre-Phase-D attachment rendering.
- Video and audio have no such chokepoint (`AVPlayer` streams a URL itself), so
  `WorldMediaFile` downloads, decrypts once and hands the player a temp file.
  Honest trade: a *long* encrypted video waits for the whole download instead of
  starting on the first chunk. If chat ever carries long-form video, replace
  that, not the crypto.
- The key store is persisted (the URL survives in the archive, so a memory-only
  key would lose every attachment on relaunch — the same trap the vault avoids)
  and wiped on sign-out.
- Media is encrypted only when the envelope will actually be **sealed**, decided
  up front by `WorldSignalSession.canSeal` because uploads start long before the
  envelope is built. A readable envelope would carry the key beside the URL,
  which protects nothing and would only make the server's copy *look* encrypted.

**Self-check extended:** plaintext absent from the sealed bytes, round-trip,
two files never share a key, the wrong key fails, and a single flipped bit fails
— i.e. the GCM tag is genuinely being checked.

**Remaining:** the live two-device check — send a photo and a voice note between
two accounts, confirm the CDN object is ciphertext, and confirm both sides
render it. Not yet done: driving the attachment picker needs UI input the
simulator tooling can't supply (see the Phase C notes).

### Phase E — safety numbers *(landed and verified 2026-08-04)*

The directory stops being trusted infrastructure here. Every session starts from
a bundle **our server** hands out; a server that handed out its own instead
would sit inside a conversation both ends believe is encrypted, and nothing in
C or D would notice — the ratchet works perfectly with the wrong peer.

**Landed:**
- `WorldSafetyNumber`: libsignal's `NumericFingerprintGenerator`, Signal's
  parameters (5200 iterations, version 2) because an interoperable 60-digit
  number is only comparable if both sides derive it identically. Rendered as
  twelve groups of five, monospaced — chunking is not decoration, it is what
  makes reading sixty digits aloud survivable.
- `WorldVerificationStore` records **the key that was vouched for**, not a
  boolean. A boolean would keep claiming "verified" after the key it referred to
  was replaced, which is exactly the attack this phase exists to catch. Three
  states: unverified, verified, changed-after-verification.
- The in-thread notice now splits on that. Unverified → the neutral "using a new
  device" line, because warning on every reinstall trains people to dismiss the
  warning that counts. Verified → an explicit "safety number has changed,
  verify again before sharing anything sensitive".
- **The Phase C downgrade hole is closed.** The mark is not "we have a session"
  (which fires legitimately mid-rollout) but "*they* have sent us a sealed
  message" — only possible once they hold our bundle, after which they have a
  session and can never send v1 again. A v1 envelope from such a peer is not a
  straggler; it renders as "wasn't encrypted and was not shown" rather than
  being read.

**Verified on two devices:** both contact pages render the same number —
`00343 12773 96857 85860 57666 74980 96331 09768 83616 75292 70368 50809` —
computed independently, with local/remote roles reversed. Matching is the proof
each side holds the key the other believes it holds. Marking verified persists
and reads back (green shield, action flips to "Clear verification").

**Both follow-ups landed 2026-08-04:**
- **QR verification** (`SafetyNumberScanner`): renders this side's
  `ScannableFingerprint` as a QR and compares a scanned one through libsignal's
  `compare(againstEncoding:)` — never string equality, because the encoding
  carries a version and a mismatched version must fail loudly rather than
  quietly compare bytes that mean different things. Raw bytes come from the
  QR descriptor's `errorCorrectedPayload`, not `stringValue`, which would have
  already lost anything that isn't valid text. The digits remain, and must:
  they are the path that works on a phone call or a bad camera.
- **Sends are blocked to a contact whose *verified* key changed**, until they
  look at it again. Scoped to verified contacts deliberately — blocking every
  key change would wall off the common case (a reinstall) against the plan's
  explicit "a line, never a modal", but once a user has established what the
  right key was, sending anyway means encrypting to a key they never agreed to.

### Phase F — backup & restore *(crypto landed 2026-08-04; transport blocked)*

Forward secrecy has a bill and this phase is it: a ciphertext opens once, so the
server's copy is a delivery and not an archive, and the only copy of a
conversation is the one on the device.

**Landed and self-checked:**
- `ICloudKeychainStore` — a second keychain, deliberately the opposite of the
  first. Everything in `KeychainStore` is `ThisDeviceOnly` precisely so it
  cannot leave the phone; these two items exist to survive it, so they are
  `kSecAttrSynchronizable` + `AfterFirstUnlock` (`ThisDeviceOnly` is the
  attribute that *blocks* syncing). Scoped by profile id, because one Apple ID
  can sign into two GojoGo accounts.
- Random per-account **backup key**, minted once and then stable — rotating it
  would orphan every existing snapshot.
- The **identity keypair**, wrapped under that key. This is the one that
  matters: restore it and a reinstall is invisible, because contacts keep the
  same safety number. Without it every restore would look exactly like the
  substitution Phase E just taught the app to warn about, which would teach
  users the warning means nothing.
- `WorldBackupSnapshot` — archive files, vault files, media keys and
  verification records, carried as **files verbatim** rather than re-encoded
  models, so a future field can't be silently dropped in the round trip. Sealed
  with AES-GCM under the backup key, so the transport never sees plaintext.
- **Sessions are not in it.** A restored ratchet is stale on arrival and fails
  *silently*; sessions re-establish from the prekey directory under the
  unchanged identity for one round trip.
- Self-check: plaintext absent from the sealed snapshot, round-trip, and a
  snapshot refused under a different account.

**Unblocked 2026-08-04** — iCloud container `iCloud.com.gojo.gojogo` and App
Group `group.com.gojo.gojogo` registered, entitlements added.

- `WorldBackupSync`: one record per account in the **private** database,
  overwritten each time rather than versioned — the only snapshot anybody wants
  is the newest, and versions would multiply storage by however many times the
  app was opened. The payload rides as a `CKAsset`, because CloudKit caps an
  inline field at 1 MB and a real history passes that quickly.
- Export is debounced 30s off the same mutation sites that touch the archive, so
  the backup tracks history rather than a clock without a socket burst becoming
  a burst of uploads.
- Restore runs on connect, **before** `WorldKeyPublisher`. Order is load-bearing:
  publishing a bundle mints an identity if none exists, so a publish that beat
  the restore would hand every contact a changed safety number — indistinguishable
  from the substitution Phase E warns about.
- Every failure is a no-op. No iCloud account, no record, or an unopenable
  record all mean "carry on as a new install"; the local stores are still live.

**The App Group entitlement had a trap, now fixed.** `WorldSignalStore` prefers
the App Group container, so turning the entitlement on *relocates* the store —
and the "one-time file move" the day-one rule promised had never been written.
Without it, the first launch after the entitlement would have read every
session, every prekey private half and the published-keys flag as absent:
sessions failing silently, and the publisher believing it had never published.
The move now runs in `init`, which is the only safe place (one process, no live
ratchet to move under). Verified on device — the session with the peer and
`meta.json` moved across, the legacy path is gone, and the safety number is
unchanged.

**Not yet verified:** CloudKit itself. The simulators have no iCloud account
signed in, so `accountStatus()` is not `.available` and export/restore no-op by
design. This needs a device (or a simulator signed into an Apple ID) to
exercise.

**Still open:** the manual recovery code for the iCloud-off fallback.

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
- ~~A v1 envelope is still accepted on a thread that already has a session.~~
  **Closed in Phase E**, with the sharper mark that made it safe: not "we have a
  session" but "they have sent us a sealed message".
- **History predates the ratchet.** A vault entry lost (app deleted, sign-out)
  makes that message unreadable forever, by anyone. That is forward secrecy
  working, not a bug — and it is what Phase F's encrypted backup answers.
- **Server-side previews are gone** — that is the point, not a regression.
