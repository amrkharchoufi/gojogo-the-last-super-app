package com.gojogo.moderation.internal;

/**
 * Why somebody reported something.
 *
 * <p>A closed list rather than free text, because the note is optional and most
 * people won't write one: the reason is what makes a queue sortable and what
 * tells a moderator which policy they are applying. It is deliberately short —
 * a picker with twenty options is a picker nobody reads, and every extra choice
 * is one more way to file the same complaint in the wrong bucket.
 */
enum ReportReason {

    SPAM,
    /** Nudity or sexual content. */
    ADULT_CONTENT,
    HATE_SPEECH,
    VIOLENCE,
    HARASSMENT,
    /** Impersonating a person or a business — the reason a verified badge exists. */
    IMPERSONATION,
    SCAM,
    /** Anything the law, rather than the policy, forbids. */
    ILLEGAL,
    /** Self-harm or suicide. Kept separate because the response is a different
     *  one: this is the reason that should reach a human fastest. */
    SELF_HARM,
    INTELLECTUAL_PROPERTY,
    /** The escape hatch. The note carries the weight when this is chosen. */
    OTHER;

    static ReportReason parse(String raw) {
        if (raw != null) {
            for (ReportReason reason : values()) {
                if (reason.name().equalsIgnoreCase(raw.trim())) {
                    return reason;
                }
            }
        }
        return OTHER;
    }
}
