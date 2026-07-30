package com.gojogo.social.internal;

import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import com.gojogo.social.StoryReacted;
import com.gojogo.social.StoryReplied;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * The engagement half of stories: reactions, replies, the viewers list and
 * muting. Split from {@link StoryService} (which owns the frames themselves and
 * the rings read) purely for size — both are the same module and schema.
 *
 * <p>Reply privacy is the one rule worth stating out loud: a reply belongs to
 * the conversation between one viewer and the frame's author. The author reads
 * all of them; everybody else reads only their own.
 */
@Service
class StoryEngagementService {

    private static final int MAX_VIEWERS = 200;

    private final StoryService stories;
    private final StoryReactionRepository reactions;
    private final StoryCommentRepository comments;
    private final StoryMuteRepository mutes;
    private final StoryViewRepository views;
    private final ProfileApi profiles;
    private final ApplicationEventPublisher events;

    StoryEngagementService(StoryService stories, StoryReactionRepository reactions,
                           StoryCommentRepository comments, StoryMuteRepository mutes,
                           StoryViewRepository views, ProfileApi profiles,
                           ApplicationEventPublisher events) {
        this.stories = stories;
        this.reactions = reactions;
        this.comments = comments;
        this.mutes = mutes;
        this.views = views;
        this.profiles = profiles;
        this.events = events;
    }

    // MARK: Reactions

    @Transactional
    void react(UUID me, UUID frameId, String emoji) {
        StoryFrame frame = stories.liveFrame(frameId);
        String cleaned = emoji == null ? "" : emoji.trim();
        if (cleaned.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "An emoji is required");
        }
        StoryReaction.Key key = new StoryReaction.Key(frameId, me);
        var existing = reactions.findById(key);
        if (existing.isPresent()) {
            // Swapping emoji isn't a fresh reaction — don't re-notify the author.
            existing.get().changeTo(cleaned);
            return;
        }
        reactions.save(new StoryReaction(frameId, me, cleaned));
        // Seeing a reaction implies having seen the frame.
        stories.markSeen(me, frameId);
        events.publishEvent(new StoryReacted(frameId, frame.getAuthorId(), me, cleaned, OffsetDateTime.now()));
    }

    @Transactional
    void unreact(UUID me, UUID frameId) {
        reactions.deleteByFrameIdAndViewerId(frameId, me);
    }

    // MARK: Replies

    @Transactional
    StoryCommentDto reply(UUID me, UUID frameId, String text) {
        StoryFrame frame = stories.liveFrame(frameId);
        String cleaned = text == null ? "" : text.trim();
        if (cleaned.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "A reply can't be empty");
        }
        StoryComment comment = comments.save(new StoryComment(frameId, me, cleaned));
        stories.markSeen(me, frameId);
        events.publishEvent(new StoryReplied(frameId, frame.getAuthorId(), me,
            comment.getId(), comment.getCreatedAt()));
        return decorate(List.of(comment), me).getFirst();
    }

    /** Every reply if you own the frame; otherwise only the ones you sent. */
    @Transactional(readOnly = true)
    List<StoryCommentDto> replies(UUID me, UUID frameId) {
        StoryFrame frame = stories.liveFrame(frameId);
        List<StoryComment> rows = frame.getAuthorId().equals(me)
            ? comments.findByFrameIdOrderByCreatedAtAsc(frameId)
            : comments.findByFrameIdAndAuthorIdOrderByCreatedAtAsc(frameId, me);
        return decorate(rows, me);
    }

    /** The reply's sender can retract it; the frame's author can clear it. */
    @Transactional
    void deleteReply(UUID me, UUID commentId) {
        StoryComment comment = comments.findById(commentId).orElseThrow(
            () -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such reply"));
        boolean isSender = profiles.actsFor(me, comment.getAuthorId());
        boolean ownsStory = profiles.actsFor(me, stories.liveFrame(comment.getFrameId()).getAuthorId());
        if (!isSender && !ownsStory) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Not your reply");
        }
        comments.delete(comment);
    }

    private List<StoryCommentDto> decorate(List<StoryComment> rows, UUID me) {
        if (rows.isEmpty()) {
            return List.of();
        }
        Map<UUID, ProfileDto> authors = profiles.findByIds(
            rows.stream().map(StoryComment::getAuthorId).collect(Collectors.toSet()));
        return rows.stream().map(c -> {
            ProfileDto p = authors.get(c.getAuthorId());
            return new StoryCommentDto(
                c.getId(),
                c.getFrameId(),
                c.getAuthorId(),
                displayName(p),
                p == null ? null : p.handle(),
                p == null ? null : p.avatarUrl(),
                c.getText(),
                c.getCreatedAt(),
                c.getAuthorId().equals(me));
        }).toList();
    }

    // MARK: Viewers

    /** Owner-only: who watched this frame, newest first, with their reaction. */
    @Transactional(readOnly = true)
    List<StoryViewerDto> viewers(UUID me, UUID frameId) {
        StoryFrame frame = stories.liveFrame(frameId);
        // The owner of the business that posted it counts as the author here —
        // otherwise a business's story has viewers nobody can see.
        if (!profiles.actsFor(me, frame.getAuthorId())) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Not your story");
        }
        List<StoryView> rows = views.findByFrameIdOrderByViewedAtDesc(frameId, PageRequest.of(0, MAX_VIEWERS));
        if (rows.isEmpty()) {
            return List.of();
        }
        Map<UUID, String> emojiByViewer = new HashMap<>();
        for (StoryReaction r : reactions.findByFrameId(frameId)) {
            emojiByViewer.put(r.getViewerId(), r.getEmoji());
        }
        Map<UUID, ProfileDto> people = profiles.findByIds(
            rows.stream().map(StoryView::getViewerId).collect(Collectors.toSet()));

        List<StoryViewerDto> out = new ArrayList<>(rows.size());
        for (StoryView v : rows) {
            ProfileDto p = people.get(v.getViewerId());
            out.add(new StoryViewerDto(
                v.getViewerId(),
                displayName(p),
                p == null ? null : p.handle(),
                p == null ? null : p.avatarUrl(),
                emojiByViewer.get(v.getViewerId()),
                v.getViewedAt()));
        }
        return out;
    }

    // MARK: Mute

    @Transactional
    void mute(UUID me, UUID otherId) {
        if (me.equals(otherId)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "You can't mute yourself");
        }
        StoryMute.Key key = new StoryMute.Key(me, otherId);
        if (!mutes.existsById(key)) {
            mutes.save(new StoryMute(me, otherId));
        }
    }

    @Transactional
    void unmute(UUID me, UUID otherId) {
        mutes.deleteByMuterIdAndMutedId(me, otherId);
    }

    @Transactional(readOnly = true)
    Set<UUID> mutedBy(UUID me) {
        return mutes.mutedIds(me);
    }

    private static String displayName(ProfileDto p) {
        if (p == null) {
            return "Deleted user";
        }
        return p.displayName() != null ? p.displayName() : p.handle();
    }
}
