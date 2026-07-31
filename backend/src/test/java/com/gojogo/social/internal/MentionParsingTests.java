package com.gojogo.social.internal;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * What counts as a tag.
 *
 * <p>The iOS client re-implements this grammar in {@code MentionParser} so it
 * can underline the tags without asking the server which spans they occupy. The
 * two must agree: a token the client draws as tappable but the server never
 * resolved is a dead link, and the reverse is a notification nobody can see the
 * cause of. **Every case below is duplicated in the Swift parser** — change one
 * and change the other.
 */
class MentionParsingTests {

    private static List<String> parse(String text) {
        return MentionService.parse(text, 20);
    }

    @Test
    @DisplayName("plain tags resolve, with or without surrounding punctuation")
    void plainTags() {
        assertThat(parse("@amina look at this")).containsExactly("amina");
        assertThat(parse("shout out to @amina!")).containsExactly("amina");
        assertThat(parse("(@amina)")).containsExactly("amina");
        assertThat(parse("great work @amina\n@yusuf too")).containsExactly("amina", "yusuf");
    }

    @Test
    @DisplayName("a tag is case-insensitive and stored canonically")
    void caseFolding() {
        assertThat(parse("@Amina and @AMINA")).containsExactly("amina");
    }

    @Test
    @DisplayName("a trailing dot is punctuation, not part of the handle")
    void trailingDot() {
        // Handles may contain dots, so this is the one place the grammar has to
        // guess — and "thanks @amina." meaning @amina is the safer guess.
        assertThat(parse("thanks @amina.")).containsExactly("amina");
        assertThat(parse("cc @a.b.c done")).containsExactly("a.b.c");
    }

    @Test
    @DisplayName("an email address is not a tag")
    void emailIsNotATag() {
        assertThat(parse("write to me@example.com")).isEmpty();
        assertThat(parse("me@example.com and @amina")).containsExactly("amina");
    }

    @Test
    @DisplayName("one person tagged twice is one tag")
    void deduplicates() {
        // The point is the notification: three "@amina" must not be three pings.
        assertThat(parse("@amina @amina @amina")).containsExactly("amina");
    }

    @Test
    @DisplayName("a bare or too-short sigil is just text")
    void notTags() {
        assertThat(parse("email @ me")).isEmpty();
        assertThat(parse("@a")).isEmpty();
        assertThat(parse("rated 10@10")).isEmpty();
        assertThat(parse("@@amina")).isEmpty();
        assertThat(parse(null)).isEmpty();
        assertThat(parse("no tags here")).isEmpty();
    }

    @Test
    @DisplayName("the limit caps how many people one body can tag")
    void limit() {
        String spam = "@one @two @three @four @five";
        assertThat(MentionService.parse(spam, 3)).containsExactly("one", "two", "three");
    }
}
