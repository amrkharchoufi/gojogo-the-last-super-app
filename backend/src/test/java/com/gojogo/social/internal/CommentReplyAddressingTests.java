package com.gojogo.social.internal;

import com.gojogo.profile.ProfileApi;
import com.gojogo.social.CommentReplied;
import com.gojogo.social.PostCommented;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Who gets told when a reply is posted.
 *
 * <p>Replies are flattened to one level for rendering — a reply to a reply is
 * filed under their shared top-level parent. That flattening must not decide
 * <em>who is notified</em>: answering B's reply inside A's thread is addressed
 * to B, and telling A instead notifies the wrong person while leaving the right
 * one in silence. These two questions used to share a variable, which is exactly
 * how that bug happened; this pins them apart.
 */
class CommentReplyAddressingTests {

    private static final UUID POST_ID = UUID.randomUUID();
    private static final UUID POST_AUTHOR = UUID.randomUUID();
    /// A opened the thread, B answered inside it, C is the one replying now.
    private static final UUID A = UUID.randomUUID();
    private static final UUID B = UUID.randomUUID();
    private static final UUID C = UUID.randomUUID();
    private static final UUID ROOT_COMMENT = UUID.randomUUID();
    private static final UUID B_REPLY = UUID.randomUUID();

    private CommentRepository comments;
    private PostRepository posts;
    private ApplicationEventPublisher events;
    private MentionService mentions;
    private CommentService service;

    @BeforeEach
    void setUp() {
        comments = mock(CommentRepository.class);
        posts = mock(PostRepository.class);
        events = mock(ApplicationEventPublisher.class);
        CommentLikeRepository likes = mock(CommentLikeRepository.class);
        CommentLikeCountUpdater likeCounts = mock(CommentLikeCountUpdater.class);
        FollowRepository follows = mock(FollowRepository.class);
        ProfileApi profiles = mock(ProfileApi.class);
        mentions = mock(MentionService.class);
        // Nobody has blocked anybody in these tests — the addressing rules this
        // file pins are about who a reply answers, not who may see it.
        BlockService blocks = mock(BlockService.class);

        when(posts.findById(POST_ID)).thenReturn(Optional.of(new Post(POST_AUTHOR, "a post", 1.0f)));
        when(follows.followeeIds(any())).thenReturn(Set.of());
        when(profiles.findById(any())).thenReturn(Optional.empty());
        when(mentions.resolve(any(), anyString())).thenReturn(List.of());
        when(mentions.record(any(), any(), any(), anyList(), any(), any(), any()))
            .thenReturn(List.of());
        when(comments.saveAndFlush(any())).thenAnswer(call -> withId(call.getArgument(0)));

        when(comments.findById(ROOT_COMMENT)).thenReturn(Optional.of(comment(ROOT_COMMENT, A, null)));
        when(comments.findById(B_REPLY)).thenReturn(Optional.of(comment(B_REPLY, B, ROOT_COMMENT)));
        when(comments.existsById(ROOT_COMMENT)).thenReturn(true);

        service = new CommentService(comments, likes, likeCounts, posts, follows, blocks,
            profiles, mentions, events);
    }

    @Test
    @DisplayName("replying to a top-level comment notifies its author")
    void repliesToTopLevelNotifyThatAuthor() {
        service.create(C, POST_ID, "agreed", ROOT_COMMENT);

        CommentReplied event = published(CommentReplied.class);
        assertThat(event.parentAuthorId()).isEqualTo(A);
        assertThat(event.parentCommentId()).isEqualTo(ROOT_COMMENT);
    }

    @Test
    @DisplayName("replying to a reply notifies the person answered, not the thread's opener")
    void repliesToAReplyNotifyTheAddressee() {
        service.create(C, POST_ID, "@b good point", B_REPLY);

        CommentReplied event = published(CommentReplied.class);
        // The bug this exists for: the flattening returned A's comment, so A was
        // told that C "replied to your comment" and B — who C actually answered
        // — was told nothing at all.
        assertThat(event.parentAuthorId()).isEqualTo(B);
        assertThat(event.parentCommentId()).isEqualTo(B_REPLY);
    }

    @Test
    @DisplayName("a reply to a reply is still filed under the top-level parent")
    void repliesToAReplyAreFiledOnTheRoot() {
        service.create(C, POST_ID, "@b good point", B_REPLY);

        ArgumentCaptor<Comment> saved = ArgumentCaptor.forClass(Comment.class);
        verify(comments).saveAndFlush(saved.capture());
        assertThat(saved.getValue().getParentId()).isEqualTo(ROOT_COMMENT);
        // The reply count belongs to the thread, not to the reply that was answered.
        verify(comments).bumpReplyCount(eq(ROOT_COMMENT), anyInt());
    }

    @Test
    @DisplayName("a reply notifies the thread, not the post's author")
    void repliesDoNotNotifyThePostAuthor() {
        service.create(C, POST_ID, "agreed", ROOT_COMMENT);

        // A busy thread must not ping the post's author once per answer.
        assertThat(allPublished()).noneMatch(PostCommented.class::isInstance);
    }

    @Test
    @DisplayName("a top-level comment still notifies the post's author")
    void topLevelCommentsNotifyThePostAuthor() {
        service.create(C, POST_ID, "nice", null);

        PostCommented event = published(PostCommented.class);
        assertThat(event.postAuthorId()).isEqualTo(POST_AUTHOR);
        assertThat(allPublished()).noneMatch(CommentReplied.class::isInstance);
    }

    @Test
    @DisplayName("the person replied to is not also told they were tagged")
    void theAddresseeIsSuppressedFromTheTagFanOut() {
        // The composer prefills "@b ", so without this the one action would send
        // B both "replied to your comment" and "mentioned you".
        MentionService mentions = mock(MentionService.class);
        // Nobody has blocked anybody in these tests — the addressing rules this
        // file pins are about who a reply answers, not who may see it.
        BlockService blocks = mock(BlockService.class);
        when(mentions.resolve(any(), anyString())).thenReturn(List.of(new MentionDto(B, "b")));
        when(mentions.record(any(), any(), any(), anyList(), any(), any(), any()))
            .thenReturn(List.of());
        service = new CommentService(comments, mock(CommentLikeRepository.class),
            mock(CommentLikeCountUpdater.class), posts, mock(FollowRepository.class),
            blocks, mock(ProfileApi.class), mentions, events);

        service.create(C, POST_ID, "@b good point", B_REPLY);

        @SuppressWarnings("unchecked")
        ArgumentCaptor<java.util.Collection<UUID>> suppressed =
            ArgumentCaptor.forClass(java.util.Collection.class);
        verify(mentions).record(any(), any(), any(), anyList(), any(), any(), suppressed.capture());
        assertThat(suppressed.getValue()).containsExactly(B);
    }

    @Test
    @DisplayName("a top-level comment that tags the post's author is a mention, not a comment")
    void taggingThePostAuthorInACommentReadsAsAMention() {
        when(mentions.resolve(any(), anyString()))
            .thenReturn(List.of(new MentionDto(POST_AUTHOR, "author")));

        service.create(C, POST_ID, "@author look at this", null);

        // "commented on your post" under a post with forty comments says nothing;
        // being named in one is the fact worth sending, and it is the row that
        // opens the thread rather than the post.
        assertThat(allPublished()).noneMatch(PostCommented.class::isInstance);
        @SuppressWarnings("unchecked")
        ArgumentCaptor<java.util.Collection<UUID>> suppressed =
            ArgumentCaptor.forClass(java.util.Collection.class);
        verify(mentions).record(any(), any(), any(), anyList(), any(), any(), suppressed.capture());
        // Nothing suppressed: the tag fan-out is what tells the author now.
        assertThat(suppressed.getValue()).isEmpty();
    }

    @Test
    @DisplayName("a reply that tags the person answered stays a reply")
    void taggingTheAddresseeInAReplyStaysAReply() {
        // The composer prefills the handle, so reading it as a tag would retire
        // "replied to your comment" for every reply the app itself composes.
        when(mentions.resolve(any(), anyString())).thenReturn(List.of(new MentionDto(A, "a")));

        service.create(C, POST_ID, "@a agreed", ROOT_COMMENT);

        assertThat(published(CommentReplied.class).parentAuthorId()).isEqualTo(A);
    }

    // --- helpers ---

    private <T> T published(Class<T> type) {
        return allPublished().stream()
            .filter(type::isInstance).map(type::cast).findFirst()
            .orElseThrow(() -> new AssertionError("no " + type.getSimpleName() + " published"));
    }

    private List<Object> allPublished() {
        ArgumentCaptor<Object> captor = ArgumentCaptor.forClass(Object.class);
        verify(events, org.mockito.Mockito.atLeast(0)).publishEvent(captor.capture());
        return captor.getAllValues();
    }

    private static Comment comment(UUID id, UUID authorId, UUID parentId) {
        Comment comment = new Comment(POST_ID, authorId, "text", parentId);
        ReflectionTestUtils.setField(comment, "id", id);
        return comment;
    }

    /** JPA assigns the id on flush; the mock repository has to do the same. */
    private static Comment withId(Comment comment) {
        ReflectionTestUtils.setField(comment, "id", UUID.randomUUID());
        return comment;
    }
}
