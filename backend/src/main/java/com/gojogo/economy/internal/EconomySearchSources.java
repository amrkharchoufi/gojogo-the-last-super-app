package com.gojogo.economy.internal;

import com.gojogo.economy.ListingCreated;
import com.gojogo.economy.ProductUpserted;
import com.gojogo.search.SearchDocument;
import com.gojogo.search.SearchIndexApi;
import com.gojogo.search.SearchKind;
import com.gojogo.search.SearchableContent;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

import java.util.Optional;
import java.util.UUID;

/**
 * Economy's two search plugins (Phase 5 M4): the C2C shelf and the merchant
 * catalog, each rendering its own document shape. Each class is both halves of
 * the seam — the listener on this module's own event, and the renderer search
 * calls back — so search imports nothing from economy.
 */
final class EconomySearchSources {

    private EconomySearchSources() {
    }
}

@Component
class ListingSearchSource implements SearchableContent {

    private final ListingRepository listings;
    private final SearchIndexApi index;

    ListingSearchSource(ListingRepository listings, SearchIndexApi index) {
        this.listings = listings;
        this.index = index;
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    void onListingCreated(ListingCreated event) {
        index.reindex(SearchKind.LISTING, event.listingId());
    }

    @Override
    public SearchKind kind() {
        return SearchKind.LISTING;
    }

    @Override
    public Optional<SearchDocument> render(UUID refId) {
        return listings.findById(refId).map(listing -> new SearchDocument(
            listing.getTitle(), listing.getDescription(), listing.getCategory(),
            listing.getSellerId(),
            listing.getSaveCount() + listing.getViewCount(),
            listing.getStatus() == ListingStatus.ACTIVE && !listing.isHidden()));
    }
}

@Component
class ProductSearchSource implements SearchableContent {

    private final ProductRepository products;
    private final SearchIndexApi index;

    ProductSearchSource(ProductRepository products, SearchIndexApi index) {
        this.products = products;
        this.index = index;
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    void onProductUpserted(ProductUpserted event) {
        index.reindex(SearchKind.PRODUCT, event.productId());
    }

    @Override
    public SearchKind kind() {
        return SearchKind.PRODUCT;
    }

    @Override
    public Optional<SearchDocument> render(UUID refId) {
        return products.findById(refId).map(product -> new SearchDocument(
            product.getName(),
            product.getDescription()
                + (product.getBrand() == null ? "" : " " + product.getBrand()),
            product.getCategory(), product.getSellerId(),
            product.getRatingCount(), product.isBrowsable()));
    }
}
