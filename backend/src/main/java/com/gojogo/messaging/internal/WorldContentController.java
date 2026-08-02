package com.gojogo.messaging.internal;

import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

/**
 * GojoMessages content: the private network's own posts, stories and carousels.
 *
 * <p>Every read here is scoped to the caller's own fanned-out copies, so there is
 * no endpoint on this controller that can return content somebody wasn't sent —
 * including {@code /by/{authorId}}, which reads the <em>caller's</em> feed and
 * filters by author rather than the other way round.
 */
@RestController
class WorldContentController {

    private final WorldContentService content;
    private final CurrentProfile current;

    WorldContentController(WorldContentService content, CurrentProfile current) {
        this.content = content;
        this.current = current;
    }

    /** Stories row + posts, the home screen in one call. */
    @GetMapping("/v1/world/feed")
    WorldFeedDto feed(@AuthenticationPrincipal Jwt jwt) {
        return content.feed(current.require(jwt).id());
    }

    @PostMapping("/v1/world/content")
    WorldContentDto publish(@AuthenticationPrincipal Jwt jwt,
                            @Valid @RequestBody PublishContentRequest request) {
        return content.publish(current.require(jwt).id(), request);
    }

    @DeleteMapping("/v1/world/content/{contentId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void delete(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID contentId) {
        content.delete(current.require(jwt).id(), contentId);
    }

    /** Your own grid — the one read that returns the audience you picked. */
    @GetMapping("/v1/world/content/mine")
    List<WorldContentDto> mine(@AuthenticationPrincipal Jwt jwt,
                               @RequestParam(defaultValue = "post") String kind) {
        return content.mine(current.require(jwt).id(), kind);
    }

    /** What this person published to you — the contact page's shared-content tab. */
    @GetMapping("/v1/world/content/by/{authorId}")
    List<WorldContentDto> byAuthor(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID authorId,
                                   @RequestParam(defaultValue = "post") String kind) {
        return content.byAuthorForViewer(current.require(jwt).id(), authorId, kind);
    }

    @PostMapping("/v1/world/content/{contentId}/seen")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void markSeen(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID contentId) {
        content.markSeen(current.require(jwt).id(), contentId);
    }
}
