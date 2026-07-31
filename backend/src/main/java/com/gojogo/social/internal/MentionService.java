package com.gojogo.social.internal;

import com.gojogo.config.ConfigApi;
import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import com.gojogo.social.UserMentioned;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.Collection;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

/**
 * Turns the {@code @handle} tokens in a caption or a comment into rows, and
 * tells the people who were tagged.
 *
 * <p><b>Resolution happens once, on write.</b> The alternative — leave the text
 * alone and re-parse it on every render — looks cheaper until someone changes
 * their handle (which this app allows, see V7) and every tag pointing at them
 * quietly stops working. Storing the profile id at write time makes "tagged"
 * a fact about the post instead of a guess about its spelling.
 *
 * <p><b>A handle that belongs to nobody is not an error.</b> People type "@" for
 * emphasis and misspell names; a caption that 400s because a friend hasn't
 * signed up yet would be a worse product than one that renders the token as
 * plain text. Unresolvable tokens are simply not mentions.
 */
@Service
class MentionService {

    /**
     * Matches the handle grammar {@code Handles.normalize} produces
     * ({@code [a-z0-9_.]}, 2–30 chars), case-insensitively so "@Amina" resolves.
     * The leading boundary stops an email address from reading as a tag:
     * "me@example.com" must not tag @example.
     */
    private static final Pattern MENTION = Pattern.compile(
        "(?<![A-Za-z0-9_.@])@([A-Za-z0-9_.]{2,30})");

    private static final String MAX_PER_POST_KEY = "social.max.mentions.per.post";
    private static final int MAX_PER_POST_DEFAULT = 20;
    private static final String MAX_PER_COMMENT_KEY = "social.max.mentions.per.comment";
    private static final int MAX_PER_COMMENT_DEFAULT = 10;

    private final MentionRepository mentions;
    private final ProfileApi profiles;
    private final ConfigApi config;
    private final ApplicationEventPublisher events;

    MentionService(MentionRepository mentions, ProfileApi profiles, ConfigApi config,
                   ApplicationEventPublisher events) {
        this.mentions = mentions;
        this.profiles = profiles;
        this.config = config;
        this.events = events;
    }

    /**
     * Records the tags in {@code text} and publishes one {@link UserMentioned}
     * per distinct person. Tagging yourself is stored (the caption still
     * underlines it) but notifies nobody — that filter lives in the
     * notifications module, which already ignores self-actions.
     *
     * @param alreadyNotified people this write is telling by another route —
     *                        the replied-to author, who should get one
     *                        "replied to you", not that plus a "mentioned you"
     * @return the tags as the response should carry them
     */
    @Transactional
    List<MentionDto> record(MentionTarget kind, UUID targetId, UUID authorId, String text,
                            UUID postId, UUID commentId, Collection<UUID> alreadyNotified) {
        List<String> handles = parse(text, limitFor(kind));
        if (handles.isEmpty()) {
            return List.of();
        }
        Map<String, ProfileDto> found = profiles.findByHandles(handles);
        List<MentionDto> resolved = handles.stream()
            .map(found::get)
            .filter(java.util.Objects::nonNull)
            .map(p -> new MentionDto(p.id(), p.handle()))
            .toList();
        if (resolved.isEmpty()) {
            return List.of();
        }
        mentions.saveAll(resolved.stream()
            .map(m -> new Mention(kind, targetId, m.profileId(), m.handle()))
            .toList());
        OffsetDateTime now = OffsetDateTime.now();
        for (MentionDto m : resolved) {
            if (m.profileId().equals(authorId) || alreadyNotified.contains(m.profileId())) {
                continue;
            }
            events.publishEvent(new UserMentioned(m.profileId(), authorId, postId, commentId, now));
        }
        return resolved;
    }

    /** The tags on a batch of targets, keyed by target id — one query per page. */
    @Transactional(readOnly = true)
    Map<UUID, List<MentionDto>> forTargets(MentionTarget kind, Collection<UUID> targetIds) {
        if (targetIds.isEmpty()) {
            return Map.of();
        }
        return mentions.findByTargetKindAndTargetIdIn(kind, targetIds).stream()
            .collect(Collectors.groupingBy(Mention::getTargetId,
                Collectors.mapping(m -> new MentionDto(m.getProfileId(), m.getHandle()),
                    Collectors.toList())));
    }

    /**
     * The distinct handles tagged in {@code text}, lowercased, in the order they
     * appear. Distinct because tagging someone three times in one caption is one
     * tag — and, more to the point, one notification.
     *
     * <p>A trailing dot is stripped: handles may contain dots, so "thanks
     * @amina." would otherwise resolve nobody rather than @amina.
     */
    static List<String> parse(String text, int limit) {
        if (text == null || text.isBlank() || text.indexOf('@') < 0) {
            return List.of();
        }
        Set<String> handles = new LinkedHashSet<>();
        Matcher matcher = MENTION.matcher(text);
        while (matcher.find() && handles.size() < limit) {
            String handle = matcher.group(1).toLowerCase(java.util.Locale.ROOT)
                .replaceAll("\\.+$", "");
            if (handle.length() >= 2) {
                handles.add(handle);
            }
        }
        return List.copyOf(handles);
    }

    private int limitFor(MentionTarget kind) {
        return kind == MentionTarget.POST
            ? (int) config.number(MAX_PER_POST_KEY, MAX_PER_POST_DEFAULT)
            : (int) config.number(MAX_PER_COMMENT_KEY, MAX_PER_COMMENT_DEFAULT);
    }
}
