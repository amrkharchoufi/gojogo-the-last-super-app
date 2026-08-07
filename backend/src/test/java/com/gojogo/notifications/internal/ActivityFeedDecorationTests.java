package com.gojogo.notifications.internal;

import com.gojogo.profile.ProfileApi;
import com.gojogo.social.ContentPreview;
import com.gojogo.social.SocialContentApi;
import com.gojogo.social.SocialGraphApi;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.data.domain.Limit;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * What an activity row has to carry to be readable.
 *
 * <p>"Someone liked your post" is not an answer to the question the reader
 * actually has, which is <em>which</em> post — so a row about a post carries
 * that post's thumbnail, and a tag says whether it happened in a caption or in
 * a thread, because those open different screens.
 */
class ActivityFeedDecorationTests {

    private static final UUID ME = UUID.randomUUID();
    private static final UUID ACTOR = UUID.randomUUID();
    private static final UUID POST = UUID.randomUUID();
    private static final UUID COMMENT = UUID.randomUUID();

    private NotificationRepository repo;
    private SocialContentApi content;
    private SocialGraphApi graph;
    private NotificationService service;

    @BeforeEach
    void setUp() {
        repo = mock(NotificationRepository.class);
        content = mock(SocialContentApi.class);
        graph = mock(SocialGraphApi.class);
        ProfileApi profiles = mock(ProfileApi.class);

        when(profiles.findByIds(anyList())).thenReturn(Map.of());
        when(content.postPreviews(any())).thenReturn(Map.of());
        when(content.storyFramePreviews(any())).thenReturn(Map.of());
        when(content.commentPreviews(any())).thenReturn(Map.of());
        when(graph.followeeIds(ME)).thenReturn(Set.of());

        service = new NotificationService(repo, mock(DeviceTokenRepository.class), profiles,
            content, graph, mock(ApnsPushSender.class));
    }

    @Test
    @DisplayName("a like carries the thumbnail of the post it is about")
    void likesCarryTheirPostsThumbnail() {
        given(row("like", POST, null));
        when(content.postPreviews(any()))
            .thenReturn(Map.of(POST, new ContentPreview(POST, "https://cdn/p.jpg", "sunset")));

        NotificationDto dto = service.list(ME, null, 30).items().getFirst();

        assertThat(dto.previewUrl()).isEqualTo("https://cdn/p.jpg");
        // With no comment to quote, the caption is what names the post.
        assertThat(dto.snippet()).isEqualTo("sunset");
        // And the row is not about a thread, so the client must not open one.
        assertThat(dto.commentId()).isNull();
    }

    @Test
    @DisplayName("a comment quotes the comment, not the caption, beside the post's thumbnail")
    void commentsQuoteWhatWasSaid() {
        given(row("comment", POST, COMMENT));
        when(content.postPreviews(any()))
            .thenReturn(Map.of(POST, new ContentPreview(POST, "https://cdn/p.jpg", "sunset")));
        when(content.commentPreviews(any()))
            .thenReturn(Map.of(COMMENT, new ContentPreview(COMMENT, null, "this goes hard")));

        NotificationDto dto = service.list(ME, null, 30).items().getFirst();

        assertThat(dto.previewUrl()).isEqualTo("https://cdn/p.jpg");
        assertThat(dto.snippet()).isEqualTo("this goes hard");
    }

    @Test
    @DisplayName("a tag says where it happened")
    void mentionsSayWhereTheyHappened() {
        given(row("mention", POST, COMMENT));
        assertThat(service.list(ME, null, 30).items().getFirst().text())
            .isEqualTo("mentioned you in a comment");

        given(row("mention", POST, null));
        assertThat(service.list(ME, null, 30).items().getFirst().text())
            .isEqualTo("mentioned you in a post");
    }

    @Test
    @DisplayName("a follow row knows whether you already follow back")
    void followRowsCarryTheGraph() {
        given(row("follow", null, null));
        assertThat(service.list(ME, null, 30).items().getFirst().actorFollowed()).isFalse();

        when(graph.followeeIds(ME)).thenReturn(Set.of(ACTOR));
        assertThat(service.list(ME, null, 30).items().getFirst().actorFollowed()).isTrue();
    }

    @Test
    @DisplayName("a row whose post is gone still renders")
    void rowsOutliveWhatTheyAreAbout() {
        given(row("like", POST, null));
        // postPreviews returns nothing — the post was deleted after the like.
        NotificationDto dto = service.list(ME, null, 30).items().getFirst();

        assertThat(dto.previewUrl()).isNull();
        assertThat(dto.snippet()).isNull();
        assertThat(dto.text()).isEqualTo("liked your post");
    }

    private void given(Notification notification) {
        when(repo.findByRecipientIdOrderByCreatedAtDesc(any(), any(Limit.class)))
            .thenReturn(List.of(notification));
    }

    private static Notification row(String type, UUID postId, UUID commentId) {
        return new Notification(ME, type, ACTOR, postId, commentId, null, OffsetDateTime.now());
    }
}
