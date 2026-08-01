package com.gojogo.moderation.internal;

import com.gojogo.auth.AccountAdminApi;
import com.gojogo.moderation.ModeratableContent;
import com.gojogo.moderation.ModerationAction;
import com.gojogo.moderation.ModerationTargetKind;
import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.util.EnumMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

/**
 * Filing reports, and working the queue they land in.
 *
 * <p>Every question about the reported <em>thing</em> is delegated to the
 * vertical that owns its kind (see {@link ModeratableContent}); this class owns
 * the queue, the decision, and the one action no vertical can perform —
 * suspending an account.
 */
@Service
class ModerationService {

    private static final Logger log = LoggerFactory.getLogger(ModerationService.class);

    /** How much of a post's text a moderator sees before opening it. */
    private static final int SUMMARY_MAX = 160;

    private final ReportRepository reports;
    private final ProfileApi profiles;
    private final AccountAdminApi accounts;
    /** One handler per kind, resolved once at startup. */
    private final Map<ModerationTargetKind, ModeratableContent> handlers =
        new EnumMap<>(ModerationTargetKind.class);

    ModerationService(ReportRepository reports, ProfileApi profiles, AccountAdminApi accounts,
                      List<ModeratableContent> registered) {
        this.reports = reports;
        this.profiles = profiles;
        this.accounts = accounts;
        for (ModeratableContent handler : registered) {
            ModeratableContent clash = handlers.put(handler.kind(), handler);
            if (clash != null) {
                // Two verticals claiming the same kind means one of them is
                // silently never called. Fail loudly at startup rather than
                // discover it when a takedown does nothing.
                throw new IllegalStateException("Two handlers for " + handler.kind() + ": "
                    + clash.getClass() + " and " + handler.getClass());
            }
        }
        log.info("Moderation: reportable kinds are {}", handlers.keySet());
    }

    // MARK: Reporting

    /**
     * Files a report. Idempotent per (reporter, target): tapping Report twice on
     * the same post is one queue item and a calm "already reported", not a 409 —
     * the second tap is somebody checking that the first one worked.
     */
    @Transactional
    ReportReceipt report(UUID reporterId, String kindRaw, UUID targetId, String reasonRaw,
                         String note) {
        ModerationTargetKind kind = parseKind(kindRaw);
        ModeratableContent handler = handlerFor(kind);
        ModeratableContent.ModerationTarget target = handler.look(targetId).orElseThrow(() ->
            new ResponseStatusException(HttpStatus.NOT_FOUND, "There is nothing there to report"));
        if (reporterId.equals(target.ownerId())) {
            // Not a moral judgement — a report against yourself is a queue item
            // with nothing for a moderator to decide, and the author already has
            // delete.
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "You can't report your own content");
        }

        Optional<Report> existing =
            reports.findByReporterIdAndTargetKindAndTargetId(reporterId, kind, targetId);
        if (existing.isPresent()) {
            return new ReportReceipt(existing.get().getId(), existing.get().getStatus().name(), true);
        }
        Report report = new Report(reporterId, kind, targetId, target.ownerId(),
            ReportReason.parse(reasonRaw), note);
        try {
            report = reports.saveAndFlush(report);
        } catch (DataIntegrityViolationException raced) {
            // Two taps in flight at once. The unique index is the arbiter.
            return reports.findByReporterIdAndTargetKindAndTargetId(reporterId, kind, targetId)
                .map(r -> new ReportReceipt(r.getId(), r.getStatus().name(), true))
                .orElseThrow(() -> raced);
        }
        log.info("Report {} filed against {} {} (owner {})", report.getId(), kind, targetId,
            target.ownerId());
        return new ReportReceipt(report.getId(), report.getStatus().name(), false);
    }

    // MARK: The queue

    @Transactional(readOnly = true)
    List<ReviewReportDto> queue(String statusRaw, String kindRaw, int limit) {
        ReportStatus status = parseStatus(statusRaw);
        ModerationTargetKind kind = kindRaw == null || kindRaw.isBlank() ? null : parseKind(kindRaw);
        var page = PageRequest.of(0, Math.clamp(limit, 1, 200));
        List<Report> rows = kind == null
            ? reports.byStatus(status, page)
            : reports.byStatusAndKind(status, kind, page);
        return decorate(rows);
    }

    @Transactional(readOnly = true)
    ReviewReportDto get(UUID reportId) {
        return decorate(List.of(require(reportId))).getFirst();
    }

    @Transactional(readOnly = true)
    List<ReviewReportDto> history(UUID ownerProfileId, int limit) {
        return decorate(reports.againstOwner(ownerProfileId,
            PageRequest.of(0, Math.clamp(limit, 1, 200))));
    }

    @Transactional(readOnly = true)
    QueueSummary summary() {
        return new QueueSummary(reports.countByStatus(ReportStatus.OPEN));
    }

    // MARK: Deciding

    /**
     * Applies a decision and closes <em>every</em> open report against the same
     * target. Forty rows for one viral post is a queue nobody can work, and the
     * thirty-nine reporters after the first were right about the same thing.
     */
    @Transactional
    ReviewReportDto act(UUID reportId, String actionRaw, String note, String who) {
        Report report = require(reportId);
        ModerationAction action = parseAction(actionRaw);

        if (action == ModerationAction.SUSPEND) {
            suspend(report.getTargetOwnerId(), true, who);
        } else if (action == ModerationAction.RESTORE && report.getAction() == ModerationAction.SUSPEND) {
            // Restore undoes whatever was done. When the last decision was a
            // suspension, restoring is letting them sign in again — not
            // un-hiding content that was never hidden.
            suspend(report.getTargetOwnerId(), false, who);
        } else {
            applyToContent(report, action);
        }

        String outcome = action == ModerationAction.RESTORE ? "restored" : action.name().toLowerCase();
        log.warn("{} {} {} {} on report {}", who, outcome, report.getTargetKind(),
            report.getTargetId(), reportId);
        closeAllOn(report, ReportStatus.ACTIONED, action, who, note);
        return decorate(List.of(report)).getFirst();
    }

    /** Nothing wrong here. Closes this report only — somebody else's complaint
     *  about the same thing may still be a different complaint. */
    @Transactional
    ReviewReportDto dismiss(UUID reportId, String note, String who) {
        Report report = require(reportId);
        report.resolve(ReportStatus.DISMISSED, null, who, note);
        reports.save(report);
        log.info("{} dismissed report {}", who, reportId);
        return decorate(List.of(report)).getFirst();
    }

    private void applyToContent(Report report, ModerationAction action) {
        ModeratableContent handler = handlerFor(report.getTargetKind());
        if (handler.look(report.getTargetId()).isEmpty()) {
            // Gone before a moderator got to it. The report still closes: the
            // outcome asked for has happened, by another route.
            log.info("Report {} target {} {} is already gone", report.getId(),
                report.getTargetKind(), report.getTargetId());
            return;
        }
        try {
            handler.apply(report.getTargetId(), action);
        } catch (UnsupportedOperationException unsupported) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                unsupported.getMessage() == null
                    ? "Cannot " + action + " a " + report.getTargetKind()
                    : unsupported.getMessage());
        }
    }

    /**
     * Suspends or reinstates the account behind a report.
     *
     * <p><b>A business profile is refused, and that is the point.</b> A business
     * has no sign-in of its own — its owner does — so "suspend this shop" would
     * silently lock a person out of everything they have on the platform. The
     * refusal names the owner so the moderator can make that call deliberately.
     */
    private void suspend(UUID ownerProfileId, boolean on, String who) {
        if (ownerProfileId == null) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "This report has no account behind it to suspend");
        }
        ProfileDto owner = profiles.findById(ownerProfileId).orElseThrow(() ->
            new ResponseStatusException(HttpStatus.NOT_FOUND, "No such profile"));
        String subject = profiles.signInSubject(ownerProfileId).orElse(null);
        if (subject == null) {
            UUID personId = profiles.findBusiness(ownerProfileId)
                .map(b -> b.ownerProfileId()).orElse(null);
            throw new ResponseStatusException(HttpStatus.CONFLICT, personId == null
                ? "@" + owner.handle() + " has no sign-in to suspend"
                : "@" + owner.handle() + " is a business profile — suspend its owner ("
                    + personId + ") if that is what you mean");
        }
        boolean applied = on ? accounts.disableSignIn(subject) : accounts.enableSignIn(subject);
        if (!applied) {
            // Never report a suspension that didn't happen. The alternative is a
            // queue that says "handled" over an account still signing in.
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                "Could not reach the identity provider — nothing was changed");
        }
        log.warn("{} {} account @{} ({})", who, on ? "suspended" : "reinstated",
            owner.handle(), ownerProfileId);
    }

    private void closeAllOn(Report decided, ReportStatus outcome, ModerationAction action,
                            String who, String note) {
        decided.resolve(outcome, action, who, note);
        reports.save(decided);
        for (Report sibling : reports.findByTargetKindAndTargetIdAndStatus(
                decided.getTargetKind(), decided.getTargetId(), ReportStatus.OPEN)) {
            if (!sibling.getId().equals(decided.getId())) {
                sibling.resolve(outcome, action, who,
                    "Resolved with report " + decided.getId());
                reports.save(sibling);
            }
        }
    }

    // MARK: Decoration

    private List<ReviewReportDto> decorate(List<Report> rows) {
        if (rows.isEmpty()) {
            return List.of();
        }
        Set<UUID> people = new HashSet<>();
        for (Report r : rows) {
            people.add(r.getReporterId());
            if (r.getTargetOwnerId() != null) {
                people.add(r.getTargetOwnerId());
            }
        }
        Map<UUID, ProfileDto> named = profiles.findByIds(people);
        return rows.stream().map(r -> {
            Optional<ModeratableContent.ModerationTarget> target =
                handlers.containsKey(r.getTargetKind())
                    ? handlers.get(r.getTargetKind()).look(r.getTargetId())
                    : Optional.empty();
            int others = (int) reports.findByTargetKindAndTargetIdAndStatus(
                r.getTargetKind(), r.getTargetId(), ReportStatus.OPEN).stream()
                .filter(o -> !o.getId().equals(r.getId()))
                .count();
            return new ReviewReportDto(
                r.getId(),
                r.getTargetKind().name(),
                r.getTargetId(),
                r.getReason().name(),
                r.getNote(),
                r.getStatus().name(),
                r.getAction() == null ? null : r.getAction().name(),
                r.getReporterId(),
                handle(named.get(r.getReporterId())),
                r.getTargetOwnerId(),
                handle(named.get(r.getTargetOwnerId())),
                target.map(t -> truncate(t.summary())).orElse(null),
                target.isEmpty(),
                target.map(ModeratableContent.ModerationTarget::hidden).orElse(false),
                others,
                r.getReviewedBy(),
                r.getReviewedAt(),
                r.getReviewNote(),
                r.getCreatedAt());
        }).toList();
    }

    private static String handle(ProfileDto profile) {
        return profile == null ? null : profile.handle();
    }

    private static String truncate(String summary) {
        if (summary == null) {
            return null;
        }
        String flat = summary.replaceAll("\\s+", " ").trim();
        return flat.length() <= SUMMARY_MAX ? flat : flat.substring(0, SUMMARY_MAX - 1) + "…";
    }

    private Report require(UUID reportId) {
        return reports.findById(reportId).orElseThrow(() ->
            new ResponseStatusException(HttpStatus.NOT_FOUND, "No such report"));
    }

    /**
     * A kind with no handler is refused by name rather than accepted into a
     * queue nobody could ever close — the same posture the storefront validator
     * takes toward an unknown block type.
     */
    private ModeratableContent handlerFor(ModerationTargetKind kind) {
        ModeratableContent handler = handlers.get(kind);
        if (handler == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Nothing can act on a " + kind + " yet");
        }
        return handler;
    }

    private static ModerationTargetKind parseKind(String raw) {
        try {
            return ModerationTargetKind.parse(raw);
        } catch (IllegalArgumentException unknown) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, unknown.getMessage());
        }
    }

    private static ModerationAction parseAction(String raw) {
        try {
            return ModerationAction.parse(raw);
        } catch (IllegalArgumentException unknown) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, unknown.getMessage());
        }
    }

    private static ReportStatus parseStatus(String raw) {
        if (raw == null || raw.isBlank()) {
            return ReportStatus.OPEN;
        }
        for (ReportStatus status : ReportStatus.values()) {
            if (status.name().equalsIgnoreCase(raw.trim())) {
                return status;
            }
        }
        throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Unknown status: " + raw);
    }
}
