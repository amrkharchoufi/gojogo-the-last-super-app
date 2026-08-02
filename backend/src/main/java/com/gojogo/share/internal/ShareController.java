package com.gojogo.share.internal;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

/**
 * The one public, unauthenticated read in this system that returns somebody's
 * live position — which is exactly what it is for.
 *
 * <p>The token <em>is</em> the authentication. A trip is shared with the people
 * who do not have accounts here: a parent, a flatmate, a friend meeting you at
 * the other end. Requiring them to sign up first is how a safety feature becomes
 * a growth funnel and stops being used.
 *
 * <p>Every failure is the same 404. Expired, revoked, never existed, or a kind
 * this build cannot render all read identically, because telling somebody
 * feeding it guesses which of them was nearly right is telling them something.
 *
 * <pre>
 * curl https://api.gojogo.app/v1/share/8Kx2_qP1nR4vTgLm0aYeZbWc9dHu5sJf
 * </pre>
 */
@RestController
class ShareController {

    private final ShareService share;

    ShareController(ShareService share) {
        this.share = share;
    }

    @GetMapping("/v1/share/{token}")
    SharedPageDto view(@PathVariable String token) {
        return share.resolve(token);
    }
}
