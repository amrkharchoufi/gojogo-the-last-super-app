package com.gojogo.economy.internal;

import com.gojogo.media.MediaApi;
import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * Verified-purchase product reviews (SPECS §6). The verification is the whole
 * point: a review names the completed order it rides on, and an order that
 * isn't the caller's, isn't completed, or doesn't contain the product refuses
 * the review. The aggregate is cached on the product as sum + count.
 */
@Service
class ProductReviewService {

    private final ProductReviewRepository reviews;
    private final ProductRepository products;
    private final ProductOrderRepository orders;
    private final SellerRegistry registry;
    private final ProfileApi profiles;
    private final MediaApi media;

    ProductReviewService(ProductReviewRepository reviews, ProductRepository products,
                         ProductOrderRepository orders, SellerRegistry registry,
                         ProfileApi profiles, MediaApi media) {
        this.reviews = reviews;
        this.products = products;
        this.orders = orders;
        this.registry = registry;
        this.profiles = profiles;
        this.media = media;
    }

    @Transactional
    ProductDtos.ReviewResponse create(UUID me, UUID productId,
                                      ProductDtos.CreateReviewRequest request) {
        Product product = products.findById(productId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such product"));
        ProductOrder order = orders.findById(request.orderId())
            .filter(o -> o.getBuyerId().equals(me))
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such order"));
        if (order.getStatus() != ProductOrderStatus.COMPLETED) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "Reviews open once the order is completed");
        }
        boolean bought = order.getLines().stream()
            .anyMatch(line -> line.getProductId().equals(productId));
        if (!bought) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "That order doesn't contain this product");
        }

        List<String> photos = request.photoUrls() == null ? List.of() : request.photoUrls().stream()
            .filter(u -> u != null && !u.isBlank())
            .toList();
        ProductReview review = reviews.findByProductIdAndAuthorId(productId, me)
            .map(existing -> {
                // A second purchase edits the review rather than stacking a
                // duplicate; the aggregate moves by the difference.
                product.amendReview(existing.getRating(), request.rating());
                existing.amend(order.getId(), request.rating(), request.body());
                return existing;
            })
            .orElseGet(() -> {
                product.recordReview(request.rating());
                return new ProductReview(productId, order.getId(), me,
                    request.rating(), request.body());
            });
        review.replacePhotos(photos);
        ProductReview saved = reviews.save(review);
        products.save(product);
        if (!photos.isEmpty()) {
            media.markReferenced(photos);
        }
        return decorate(List.of(saved)).getFirst();
    }

    /** One reply per review, the seller's (SPECS §6). Replacing it is editing it. */
    @Transactional
    ProductDtos.ReviewResponse reply(UUID ownerUserId, UUID reviewId, String body) {
        Seller seller = registry.requireMine(ownerUserId);
        ProductReview review = reviews.findById(reviewId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such review"));
        Product product = products.findById(review.getProductId())
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such product"));
        if (!product.getSellerId().equals(seller.getId())) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Not your product");
        }
        review.reply(body);
        return decorate(List.of(reviews.save(review))).getFirst();
    }

    @Transactional(readOnly = true)
    List<ProductDtos.ReviewResponse> forProduct(UUID productId, int limit) {
        return decorate(reviews.findByProductIdOrderByCreatedAtDesc(productId,
            PageRequest.of(0, Math.clamp(limit, 1, 100))));
    }

    private List<ProductDtos.ReviewResponse> decorate(List<ProductReview> page) {
        if (page.isEmpty()) {
            return List.of();
        }
        Map<UUID, ProfileDto> authors = profiles.findByIds(page.stream()
            .map(ProductReview::getAuthorId).collect(Collectors.toSet()));
        return page.stream().map(r -> {
            ProfileDto author = authors.get(r.getAuthorId());
            return new ProductDtos.ReviewResponse(
                r.getId(), r.getProductId(), r.getAuthorId(),
                author == null ? "Deleted user"
                    : author.displayName() != null ? author.displayName() : author.handle(),
                author == null ? null : author.avatarUrl(),
                r.getRating(), r.getBody(),
                r.getPhotos().stream().map(ProductReviewPhoto::getImageUrl).toList(),
                r.getReplyBody(), r.getRepliedAt(), r.getCreatedAt());
        }).toList();
    }
}
