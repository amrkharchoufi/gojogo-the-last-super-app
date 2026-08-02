package com.gojogo.messaging.internal;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

/**
 * Wire DTOs for the GojoMessages graph: contacts (phone numbers, never handles),
 * circles (named groups of contacts), and the rich profile that hangs off the
 * phone-verified identity.
 *
 * <p>Circles matter beyond grouping — they are the <em>audience primitive</em>.
 * A post published to a circle is readable by that circle and nobody else, which
 * is why they had to stop being a phone-local UI convenience.
 */
final class WorldGraphDtos {
    private WorldGraphDtos() {}
}

// ---- contacts -------------------------------------------------------------

/** Add somebody to your contacts by number. There is no handle equivalent. */
record AddContactRequest(@NotBlank String phone, @Size(max = 60) String alias) {
}

/**
 * One contact as the owner sees them: their GojoMessages identity, plus the
 * owner's private rename when there is one.
 */
record ContactDto(UUID contactId, String displayName, String avatarUrl, String phone,
                  String alias, Instant addedAt) {

    /** What the owner actually reads on screen. */
    String effectiveName() {
        return alias != null && !alias.isBlank() ? alias
            : (displayName != null ? displayName : "Someone");
    }
}

// ---- circles --------------------------------------------------------------

record SaveCircleRequest(@NotBlank @Size(max = 60) String name,
                         String colorHex,
                         List<UUID> memberIds) {
}

record CircleDto(UUID id, String name, String colorHex, List<UUID> memberIds, Instant createdAt) {
}

// ---- rich profile ---------------------------------------------------------

/**
 * The profile the re-spec hangs off the GojoMessages identity — not off the
 * public account, which keeps its own separate name, avatar and handle.
 *
 * <p>Education is free text. A worldwide schools database is a vendor and a cost,
 * and an autocomplete can be layered onto the same field later without a
 * migration; picking a dataset now would be paying for it before anyone has
 * typed a school name.
 */
record WorldRichProfileDto(
    String bio,
    String gender,
    String city,
    List<String> languages,
    String education,
    String occupation,
    List<String> interests,
    List<String> favouriteBooks,
    List<String> favouriteFilms,
    List<String> favouriteTv,
    List<String> favouriteSport,
    List<String> favouriteGames) {

    static WorldRichProfileDto empty() {
        return new WorldRichProfileDto(null, null, null, List.of(), null, null,
            List.of(), List.of(), List.of(), List.of(), List.of(), List.of());
    }
}

record UpdateRichProfileRequest(
    @Size(max = 300) String bio,
    @Size(max = 40) String gender,
    @Size(max = 80) String city,
    List<String> languages,
    @Size(max = 120) String education,
    @Size(max = 80) String occupation,
    List<String> interests,
    List<String> favouriteBooks,
    List<String> favouriteFilms,
    List<String> favouriteTv,
    List<String> favouriteSport,
    List<String> favouriteGames) {
}

/**
 * Somebody else's GojoMessages identity, as one of their contacts sees it. The
 * rich half is present only when the viewer is actually a contact — a phone
 * number you happen to know is not an entitlement to read somebody's profile.
 *
 * <p>{@code phone} is present one step wider: to a contact, and to anyone this
 * person reached first. It is what an add is made of, so a null here is the
 * client's answer to "can I add them?" as much as it is a hidden number.
 */
record WorldContactProfileDto(UUID profileId, String displayName, String avatarUrl,
                              String phone, String alias, boolean isContact,
                              WorldRichProfileDto profile) {
}

// ---- content --------------------------------------------------------------

/**
 * Who may read a piece of GojoMessages content. There is deliberately no
 * {@code PUBLIC}: a GojoMessages post is seen by the author's contacts or by the
 * circles they picked, and by nobody else, ever. That absence is the feature —
 * adding a third constant here is what would make this system able to leak.
 */
enum WorldAudience {
    /**
     * Everyone the author has as a contact — the people they added, not the
     * people who added them. An audience made of the latter is one the author
     * cannot close.
     */
    CONTACTS,
    /** Only the named circles. */
    CIRCLES
}

record PublishContentRequest(
    @NotNull String kind,
    @Size(max = 2000) String text,
    List<MediaItemDto> mediaItems,
    @NotNull WorldAudience audience,
    List<UUID> circleIds) {
}

/**
 * One piece of GojoMessages content. {@code audience} and {@code circleIds} are
 * returned only to the author — a reader has no business knowing which of the
 * author's circles they landed in.
 */
record WorldContentDto(
    UUID id,
    UUID authorId,
    String authorName,
    String authorAvatarUrl,
    String kind,
    String text,
    List<MediaItemDto> mediaItems,
    Instant createdAt,
    Instant expiresAt,
    boolean seen,
    WorldAudience audience,
    List<UUID> circleIds) {

    /** The reader's copy: strips the audience the author chose. */
    WorldContentDto withoutAudience() {
        return new WorldContentDto(id, authorId, authorName, authorAvatarUrl, kind, text,
            mediaItems, createdAt, expiresAt, seen, null, null);
    }
}

/** The home feed: a stories row, then posts, in one round trip. */
record WorldFeedDto(List<WorldStoryGroupDto> stories, List<WorldContentDto> posts) {
}

/** One author's unexpired stories, grouped the way the row renders them. */
record WorldStoryGroupDto(UUID authorId, String authorName, String authorAvatarUrl,
                          boolean allSeen, List<WorldContentDto> frames) {
}
