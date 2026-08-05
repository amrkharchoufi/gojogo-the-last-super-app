package com.gojogo.services.internal;

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

/** Verified-booking reviews — the economy review rules, one vertical over:
 *  the review names a COMPLETED booking of this service by this caller. */
@Service
class ServiceReviewService {

    private final ServiceReviewRepository reviews;
    private final ServiceOfferingRepository offerings;
    private final BookingRepository bookings;
    private final ProviderDirectory directory;
    private final ProfileApi profiles;

    ServiceReviewService(ServiceReviewRepository reviews, ServiceOfferingRepository offerings,
                         BookingRepository bookings, ProviderDirectory directory,
                         ProfileApi profiles) {
        this.reviews = reviews;
        this.offerings = offerings;
        this.bookings = bookings;
        this.directory = directory;
        this.profiles = profiles;
    }

    @Transactional
    ServiceDtos.ServiceReviewResponse create(UUID me, UUID serviceId,
                                             ServiceDtos.CreateServiceReviewRequest request) {
        ServiceOffering service = offerings.findById(serviceId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such service"));
        Booking booking = bookings.findById(request.bookingId())
            .filter(b -> b.getCustomerId().equals(me))
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such booking"));
        if (booking.getStatus() != BookingStatus.COMPLETED) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "Reviews open once the booking is completed");
        }
        if (!booking.getServiceId().equals(serviceId)) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "That booking isn't for this service");
        }
        ServiceReview review = reviews.findByServiceIdAndAuthorId(serviceId, me)
            .map(existing -> {
                service.amendReview(existing.getRating(), request.rating());
                existing.amend(booking.getId(), request.rating(), request.body());
                return existing;
            })
            .orElseGet(() -> {
                service.recordReview(request.rating());
                return new ServiceReview(serviceId, booking.getId(), me,
                    request.rating(), request.body());
            });
        ServiceReview saved = reviews.save(review);
        offerings.save(service);
        return decorate(List.of(saved)).getFirst();
    }

    @Transactional
    ServiceDtos.ServiceReviewResponse reply(UUID ownerUserId, UUID reviewId, String body) {
        Provider provider = directory.requireMine(ownerUserId);
        ServiceReview review = reviews.findById(reviewId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such review"));
        ServiceOffering service = offerings.findById(review.getServiceId())
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such service"));
        if (!service.getProviderId().equals(provider.getId())) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Not your service");
        }
        review.reply(body);
        return decorate(List.of(reviews.save(review))).getFirst();
    }

    @Transactional(readOnly = true)
    List<ServiceDtos.ServiceReviewResponse> forService(UUID serviceId, int limit) {
        return decorate(reviews.findByServiceIdOrderByCreatedAtDesc(serviceId,
            PageRequest.of(0, Math.clamp(limit, 1, 100))));
    }

    private List<ServiceDtos.ServiceReviewResponse> decorate(List<ServiceReview> page) {
        if (page.isEmpty()) return List.of();
        Map<UUID, ProfileDto> authors = profiles.findByIds(page.stream()
            .map(ServiceReview::getAuthorId).collect(Collectors.toSet()));
        return page.stream().map(r -> {
            ProfileDto author = authors.get(r.getAuthorId());
            return new ServiceDtos.ServiceReviewResponse(r.getId(), r.getServiceId(),
                r.getAuthorId(),
                author == null ? "Deleted user"
                    : author.displayName() != null ? author.displayName() : author.handle(),
                author == null ? null : author.avatarUrl(),
                r.getRating(), r.getBody(), r.getReplyBody(), r.getRepliedAt(),
                r.getCreatedAt());
        }).toList();
    }
}
