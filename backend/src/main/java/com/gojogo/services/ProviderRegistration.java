package com.gojogo.services;

import java.util.UUID;

/**
 * What {@code partner} hands over when a SERVICE_PROVIDER approval provisions —
 * who owns the practice and how it introduces itself. Qualifications, portfolio
 * and the catalog are the owner's to fill in afterwards.
 */
public record ProviderRegistration(UUID ownerUserId, String displayName, String logoUrl) {
}
