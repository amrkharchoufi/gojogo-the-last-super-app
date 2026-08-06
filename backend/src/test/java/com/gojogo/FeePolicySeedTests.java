package com.gojogo;

import com.gojogo.payments.FeeApi;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.lang.reflect.Field;
import java.lang.reflect.Modifier;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Every vertical named in {@link FeeApi} has a row in {@code payments.fee_policy},
 * and this is the test that says so.
 *
 * <p><b>It exists because Phase 5 added two and neither got one.</b> {@code V23}
 * seeded DELIVERY at 1500 bps and TRAVEL at an explicit zero, and wrote down why
 * the zero row was there at all: so that the zero is a decision on the record
 * rather than a missing policy read as zero by accident. Phase 5 then added
 * {@code ECONOMY} (M1) and {@code SERVICES} (M3), wired both to ask
 * {@code platformFee} at settlement — and seeded nothing. {@code FeeApi}'s
 * contract is that an unpriced vertical is charged nothing, so <em>every
 * marketplace sale and every service booking settled in full to the seller and
 * the platform earned zero</em>, silently, for as long as the feature existed.
 *
 * <p>Nothing could have caught it. The fee is read through an interface that
 * correctly answers "nothing" when there is no policy — there is no error, no
 * log line and no failing assertion anywhere, because charging nothing is a
 * legitimate answer. It was found by putting one real order through the client
 * and reading the seller's ledger, which is the only place the difference shows.
 *
 * <p>Static, like {@link EnumConstraintTests} and for the same reason: there is
 * no database on the build machine, so the migrations are read as text. An
 * absent row is the bug, so absence is what this looks for — it deliberately
 * does not check the <em>rate</em>, which is a business decision and is allowed
 * to be zero as long as somebody wrote it down.
 */
class FeePolicySeedTests {

    private static final Path MIGRATIONS = Path.of("src/main/resources/db/migration");

    @Test
    @DisplayName("every FeeApi vertical has a seeded fee policy")
    void everyVerticalIsPriced() {
        Set<String> seeded = seededVerticals();
        assertThat(seeded)
            .as("no migration inserts into payments.fee_policy")
            .isNotEmpty();

        assertThat(seeded)
            .as("""
                A vertical with no fee_policy row is charged nothing — FeeApi \
                says so, and that is the right default. It is also silent: the \
                platform simply earns zero on everything that vertical settles, \
                with no error anywhere. Add a row in a new migration, even if \
                the rate is 0, so the zero is a decision rather than an \
                omission.""")
            .containsAll(verticalConstants());
    }

    /** The `String` constants on {@link FeeApi} — the vocabulary a caller uses. */
    private static List<String> verticalConstants() {
        return Stream.of(FeeApi.class.getDeclaredFields())
            .filter(field -> Modifier.isStatic(field.getModifiers())
                && field.getType() == String.class)
            .map(FeePolicySeedTests::valueOf)
            .toList();
    }

    private static String valueOf(Field field) {
        try {
            return (String) field.get(null);
        } catch (IllegalAccessException unreachable) {
            throw new AssertionError("FeeApi constant is not readable: " + field, unreachable);
        }
    }

    /**
     * Every vertical any migration inserts a policy row for. Deliberately
     * union-across-files rather than last-one-wins: policies are
     * effective-dated, so a later row adds a rate rather than replacing the
     * vertical, and the question here is only whether the vertical is priced at
     * all.
     */
    private static Set<String> seededVerticals() {
        Pattern insert = Pattern.compile(
            "INSERT\\s+INTO\\s+payments\\.fee_policy\\b[^;]*;",
            Pattern.CASE_INSENSITIVE | Pattern.DOTALL);
        // The vertical is the first quoted value in each VALUES tuple.
        Pattern tuple = Pattern.compile("\\(\\s*'([A-Z_]+)'");

        Set<String> seeded = new LinkedHashSet<>();
        for (Path migration : migrations()) {
            Matcher statements = insert.matcher(read(migration));
            while (statements.find()) {
                Matcher rows = tuple.matcher(statements.group());
                while (rows.find()) {
                    seeded.add(rows.group(1));
                }
            }
        }
        return seeded;
    }

    private static List<Path> migrations() {
        try (Stream<Path> files = Files.list(MIGRATIONS)) {
            return files.filter(p -> p.getFileName().toString().endsWith(".sql")).toList();
        } catch (IOException unreadable) {
            throw new UncheckedIOException(unreadable);
        }
    }

    private static String read(Path file) {
        try {
            return Files.readString(file, StandardCharsets.UTF_8);
        } catch (IOException unreadable) {
            throw new UncheckedIOException(unreadable);
        }
    }
}
