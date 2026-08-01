package com.gojogo.dispatch.internal;

/**
 * Where a worker is between "not working" and "working".
 *
 * <p>One column rather than two booleans, because {@code available && busy} has
 * no meaning and a pair of flags is a pair that will eventually disagree. The
 * platform's own switch — suspension — is separate, and deliberately so: it must
 * survive somebody toggling their availability off and on again.
 */
enum WorkerStatus {

    /** Signed off. The default a provisioned worker starts in. */
    OFFLINE,
    /** Waiting for work, and reporting a position. */
    AVAILABLE,
    /** Mid-job. Set for <em>every</em> registration this person holds, since
     *  there is only one of them and they cannot drive and cycle at once. */
    BUSY
}
