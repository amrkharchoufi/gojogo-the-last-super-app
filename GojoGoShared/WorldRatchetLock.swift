import Foundation

// MARK: - The cross-process ratchet lock (E2EE Phase G — see E2EE-PLAN.md)
//
// This is the file the plan meant by "the hard part", and it is the reason
// Phase G is last.
//
// A Double Ratchet message key is deleted the moment it is used. Until now that
// was survivable because exactly one process ever asked libsignal to decrypt,
// and `WorldEnvelopeVault` made sure it only asked once. Phase G adds a second
// process — the Notification Service Extension — that receives the *same*
// message the socket is delivering to the app, at the same instant, and both
// hold the same session files.
//
// Two failures follow if nothing serialises them:
//
//  1. **Double decrypt.** Both processes open the same ciphertext. One wins;
//     the other gets `duplicatedMessage` and shows an error for a message that
//     arrived perfectly.
//  2. **A torn session.** Worse and quieter. Both load the same `SessionRecord`,
//     both advance it, and the last writer wins — so one side's chain key is
//     silently rolled back, and every subsequent message from that peer fails
//     to decrypt. Nothing about this is recoverable: the keys are gone.
//
// So the unit that must be atomic is not "the file write" but the whole
// **read-session → decrypt → write-session → bank the payload** sequence. That
// is what `WorldEnvelopeOpener` runs inside this lock, in both processes.
//
// `flock` and not a lock file with a pid in it, because flock is held by the
// open file description: if a process is killed — and the extension is killed
// routinely, that is its normal life — the kernel releases the lock. A
// hand-rolled lock file would strand the ratchet behind a dead owner's claim.
//
// The in-process recursion guard is not decoration. `flock` from the same
// process on a *second* descriptor blocks against the first, so a nested call
// would deadlock a thread against itself.

enum WorldRatchetLock {

    private static let gate = NSRecursiveLock()
    private static var depth = 0

    /// The lock file lives in the App Group container — the one place both
    /// processes can name. Without the container there is no second process
    /// worth serialising against (the extension can't read the store either),
    /// so the in-process gate alone is correct.
    private static var lockPath: String? {
        guard let container = WorldAppGroup.containerURL else { return nil }
        return container.appendingPathComponent("signal.lock").path
    }

    /// Runs `body` with exclusive access to the ratchet state, across processes.
    ///
    /// Blocking on purpose. The critical sections are one decrypt long, and the
    /// alternative — giving up and proceeding — is precisely the double-decrypt
    /// this exists to prevent. A caller who cannot afford to wait should not be
    /// touching a ratchet.
    @discardableResult
    static func withLock<T>(_ body: () throws -> T) rethrows -> T {
        gate.lock()
        depth += 1
        var handle: Int32 = -1
        if depth == 1, let path = lockPath {
            let fm = FileManager.default
            if !fm.fileExists(atPath: path) {
                // Created through FileManager for the protection class, which
                // `open(2)` cannot set. It has to match the store's own —
                // complete protection would make the lock unopenable exactly
                // when the extension runs, before the first unlock after a
                // reboot, and an unopenable lock is no lock at all.
                fm.createFile(atPath: path, contents: nil,
                              attributes: [.protectionKey:
                                            FileProtectionType.completeUntilFirstUserAuthentication])
            }
            handle = open(path, O_CREAT | O_RDWR, 0o600)
            if handle >= 0 { flock(handle, LOCK_EX) }
        }
        defer {
            if handle >= 0 {
                flock(handle, LOCK_UN)
                close(handle)
            }
            depth -= 1
            gate.unlock()
        }
        return try body()
    }
}
