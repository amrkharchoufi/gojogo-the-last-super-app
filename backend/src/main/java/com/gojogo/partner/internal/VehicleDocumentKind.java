package com.gojogo.partner.internal;

/**
 * A vehicle's papers — private objects, same prefix and same short-lived signed
 * reads as the identity documents in V19.
 *
 * <p>Deliberately not part of {@link DocumentKind}: those are claims about a
 * <em>person</em> or a <em>business</em> and are attached to the application,
 * these are claims about one car and are attached to it. A driver with two
 * vehicles has two insurance certificates, and one enum over one table could not
 * say which was which.
 */
enum VehicleDocumentKind {

    REGISTRATION,
    INSURANCE
}
