package com.gojogo;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.MethodSource;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Every Java enum that is stored as text behind a SQL {@code CHECK} constraint
 * has to have all of its constants listed in that constraint, and this is the
 * test that says so.
 *
 * <p><b>It exists because Phase 5 added two and nobody widened the check.</b>
 * {@code partner_account_kind_chk} was written in {@code V19} when RESTAURANT,
 * DRIVER and COURIER were the only kinds. Phase 5 M1 added {@code SELLER}, M3
 * added {@code SERVICE_PROVIDER}, both were wired through the one provisioning
 * switch and each was given a vertical to land in — and the constraint was never
 * touched. Creating either kind therefore failed at the insert and surfaced as a
 * generic 409 "Conflicting data", so <em>no seller and no service provider could
 * exist in production at all</em>: the merchant catalog, the digital shelf, the
 * transfer workflow and the whole booking machine were unreachable behind an
 * approval that could not be filed.
 *
 * <p>Nothing else could have caught it. The unit tests never open a database.
 * {@code ModularityTests} reads the module graph. The {@code schema-check} CI
 * job migrates a real Postgres and boots the application — which proves the
 * schema loads, and proves nothing about a constraint no row was ever inserted
 * against. The deploy was green. It was found the first time somebody tried to
 * approve a seller, which is the fourth time in this repo that a path nothing
 * had ever executed turned out not to be a working path.
 *
 * <p>Static rather than behavioural, deliberately: there is no database on the
 * build machine (that is the whole reason this class of bug survives), so the
 * check reads the migrations as text — the same source of truth Flyway applies.
 * The last statement that mentions a constraint by name is the one in force,
 * which is how a later {@code ALTER … DROP/ADD} correctly supersedes the
 * {@code CREATE TABLE} that introduced it.
 *
 * <p><b>Adding an enum that lives behind a check?</b> Add one line to
 * {@link #guarded()}. That is the whole registration.
 */
class EnumConstraintTests {

    /** Where Flyway's migrations live, read as text because nothing here boots. */
    private static final Path MIGRATIONS =
        Path.of("src/main/resources/db/migration");

    /**
     * One guarded pair: the enum, and the constraint its values are stored
     * behind. Kept as an explicit list rather than discovered by reflection —
     * a mapping this important should be something somebody wrote down.
     */
    record Guarded(Class<? extends Enum<?>> type, String constraint) {

        @Override
        public String toString() {
            return type.getSimpleName() + " ⊆ " + constraint;
        }
    }

    static Stream<Guarded> guarded() {
        return Stream.of(
            new Guarded(com.gojogo.payments.LedgerKind.class, "ledger_kind_chk"),
            new Guarded(com.gojogo.dispatch.WorkerKind.class, "worker_kind_chk"),
            // The one this test was written for.
            new Guarded(partnerKind(), "partner_account_kind_chk"));
    }

    /** {@code PartnerKind} is package-private, which is correct — it is nobody
     *  else's vocabulary — so it is reached by name rather than by import. */
    @SuppressWarnings("unchecked")
    private static Class<? extends Enum<?>> partnerKind() {
        try {
            return (Class<? extends Enum<?>>) Class
                .forName("com.gojogo.partner.internal.PartnerKind");
        } catch (ClassNotFoundException renamed) {
            throw new AssertionError(
                "PartnerKind has moved; update EnumConstraintTests", renamed);
        }
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("guarded")
    @DisplayName("every enum constant is allowed by the constraint that stores it")
    void constraintAllowsEveryConstant(Guarded pair) {
        Set<String> allowed = allowedValues(pair.constraint());
        assertThat(allowed)
            .as("no migration defines a constraint named %s", pair.constraint())
            .isNotEmpty();

        List<String> constants = Stream.of(pair.type().getEnumConstants())
            .map(Enum::name)
            .toList();

        assertThat(allowed)
            .as("""
                %s has constants the database will refuse. A row carrying one \
                fails the insert and surfaces as a generic 409, which reads like \
                a duplicate rather than like a missing migration. Widen %s in a \
                new migration.""", pair.type().getSimpleName(), pair.constraint())
            .containsAll(constants);
    }

    /**
     * The value set of the named constraint as the last migration to mention it
     * leaves it — migrations applied in Flyway's own order, so a later
     * {@code DROP}/{@code ADD} wins over the {@code CREATE TABLE} that first
     * declared it.
     */
    private static Set<String> allowedValues(String constraintName) {
        Pattern definition = Pattern.compile(
            "CONSTRAINT\\s+" + Pattern.quote(constraintName)
                + "\\s+CHECK\\s*\\(\\s*\\w+\\s+IN\\s*\\(([^)]*)\\)",
            Pattern.CASE_INSENSITIVE | Pattern.DOTALL);
        Pattern literal = Pattern.compile("'([^']+)'");

        Set<String> allowed = new LinkedHashSet<>();
        for (Path migration : migrationsInOrder()) {
            String sql = read(migration);
            Matcher matcher = definition.matcher(sql);
            while (matcher.find()) {
                // Later definitions in the same file also supersede earlier
                // ones, so each match replaces rather than adds to the set.
                allowed.clear();
                Matcher values = literal.matcher(matcher.group(1));
                while (values.find()) {
                    allowed.add(values.group(1));
                }
            }
        }
        return allowed;
    }

    /** Flyway's order: by version number, not by filename string — `V9` runs
     *  before `V10`, which sorting as text would get backwards. */
    private static List<Path> migrationsInOrder() {
        Pattern version = Pattern.compile("^V(\\d+)__");
        try (Stream<Path> files = Files.list(MIGRATIONS)) {
            List<Path> sql = new ArrayList<>(files
                .filter(p -> p.getFileName().toString().toLowerCase(Locale.ROOT).endsWith(".sql"))
                .toList());
            sql.sort(Comparator.comparingInt(path -> {
                Matcher matcher = version.matcher(path.getFileName().toString());
                return matcher.find() ? Integer.parseInt(matcher.group(1)) : Integer.MAX_VALUE;
            }));
            return sql;
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
