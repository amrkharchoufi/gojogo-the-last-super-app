package com.gojogo.partner.internal;

import jakarta.validation.Valid;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

/**
 * The <em>passenger's</em> side of {@code partner} — the only endpoints in this
 * module a person who is not applying for anything will ever call.
 *
 * <p>They live here rather than in {@code travel} because the thing being
 * verified is a vehicle, and vehicles are this module's: the passenger is
 * standing in for the reviewer who could only ever see a photograph of a
 * registration document. The trip is what prompted the question, not what the
 * question is about.
 *
 * <pre>
 * # what am I being asked?
 * curl -H "Authorization: Bearer $JWT" https://api.gojogo.app/v1/partner/verifications
 *
 * # yes to all five — the badge, and the reward
 * curl -X POST -H "Authorization: Bearer $JWT" -H 'Content-Type: application/json' \
 *   -d '{"driverMatched":true,"photosMatched":true,"plateMatched":true,
 *        "roadworthy":true,"noFraud":true}' \
 *   https://api.gojogo.app/v1/partner/verifications/$ID
 * </pre>
 */
@RestController
class VehicleVerificationController {

    private final VehicleVerificationService verifications;
    private final PartnerCurrentProfile current;

    VehicleVerificationController(VehicleVerificationService verifications,
                                  PartnerCurrentProfile current) {
        this.verifications = verifications;
        this.current = current;
    }

    /** Open invitations only. An answered or lapsed one is not something to show
     *  somebody a card for. */
    @GetMapping("/v1/partner/verifications")
    List<VerificationInviteDto> mine(@AuthenticationPrincipal Jwt jwt) {
        return verifications.myInvitations(current.require(jwt).id());
    }

    @PostMapping("/v1/partner/verifications/{verificationId}")
    VerificationInviteDto answer(@AuthenticationPrincipal Jwt jwt,
                                 @PathVariable UUID verificationId,
                                 @Valid @RequestBody AnswerVerificationRequest body) {
        return verifications.answer(current.require(jwt).id(), verificationId, body);
    }
}
