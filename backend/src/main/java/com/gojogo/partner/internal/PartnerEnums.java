package com.gojogo.partner.internal;

import java.util.EnumSet;
import java.util.Set;

/**
 * What kind of business is applying. The kind decides what an approval
 * provisions and which documents are required — everything else about an
 * application is the same whoever is filling it in.
 */
enum PartnerKind {

    /** A restaurant on GojoDelivery. The only kind that can be provisioned today. */
    RESTAURANT,
    /** Ride-hailing. Waits for the Phase 3 {@code dispatch} module. */
    DRIVER,
    /** Delivery courier. Waits for {@code dispatch} too. */
    COURIER;

    /** Whether an approval has somewhere to put this partner yet. */
    boolean isProvisionable() {
        return this == RESTAURANT;
    }

    /**
     * The papers a reviewer needs before this application can even be
     * submitted. Kept deliberately short: a document that isn't going to be
     * checked shouldn't be collected.
     */
    Set<DocumentKind> requiredDocuments() {
        return switch (this) {
            case RESTAURANT -> EnumSet.of(DocumentKind.ID_FRONT, DocumentKind.BUSINESS_LICENSE);
            case DRIVER -> EnumSet.of(DocumentKind.ID_FRONT, DocumentKind.SELFIE);
            case COURIER -> EnumSet.of(DocumentKind.ID_FRONT, DocumentKind.SELFIE);
        };
    }
}

/**
 * Where an application is.
 *
 * <p>{@code REJECTED} is not a dead end — the applicant edits and resubmits the
 * same account, keeping its documents and the reviewer's note, so "fix the
 * blurry licence" is one upload rather than a fresh application.
 */
enum PartnerStatus {

    DRAFT,
    SUBMITTED,
    APPROVED,
    REJECTED,
    /** Approved once, blocked since. The provisioned merchant is switched off
     *  but nothing is deleted, so restoring is a decision, not a rebuild. */
    SUSPENDED;

    /** Only an application nobody is currently reviewing may be edited. */
    boolean isEditable() {
        return this == DRAFT || this == REJECTED;
    }
}

/** An identity or business document. Stored privately; see {@code PartnerService}. */
enum DocumentKind {

    ID_FRONT,
    ID_BACK,
    SELFIE,
    BUSINESS_LICENSE,
    TAX_CERTIFICATE,
    FOOD_PERMIT,
    BANK_DETAILS
}
