package com.gojogo.services.internal;

import com.gojogo.search.SearchDocument;
import com.gojogo.search.SearchIndexApi;
import com.gojogo.search.SearchKind;
import com.gojogo.search.SearchableContent;
import com.gojogo.services.ServiceUpserted;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

import java.util.Optional;
import java.util.UUID;

/** How a service is findable (Phase 5 M4) — both halves of the seam in one
 *  class (the listener on this module's own event, and the renderer search
 *  calls back), so search imports nothing from this vertical. */
@Component
class ServiceSearchSource implements SearchableContent {

    private final ServiceOfferingRepository offerings;
    private final SearchIndexApi index;

    ServiceSearchSource(ServiceOfferingRepository offerings, SearchIndexApi index) {
        this.offerings = offerings;
        this.index = index;
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    void onServiceUpserted(ServiceUpserted event) {
        index.reindex(SearchKind.SERVICE, event.serviceId());
    }

    @Override
    public SearchKind kind() {
        return SearchKind.SERVICE;
    }

    @Override
    public Optional<SearchDocument> render(UUID refId) {
        return offerings.findById(refId).map(service -> new SearchDocument(
            service.getName(), service.getDescription(), service.getCategory(),
            service.getProviderId(), service.getRatingCount(), service.isBrowsable()));
    }
}
