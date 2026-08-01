package com.gojogo.auth.internal;

import com.gojogo.auth.AdminActor;
import com.gojogo.auth.PlatformAdminApi;
import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.http.HttpStatus;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;
import java.util.Optional;

/** The one implementation of {@link PlatformAdminApi} — see that interface for why. */
@Service
@EnableConfigurationProperties(PlatformAdminProperties.class)
class PlatformAdminService implements PlatformAdminApi {

    /** Cognito puts group membership in the ID token under this claim. */
    private static final String GROUPS_CLAIM = "cognito:groups";

    private static final Logger log = LoggerFactory.getLogger(PlatformAdminService.class);

    private final PlatformAdminProperties props;

    PlatformAdminService(PlatformAdminProperties props) {
        this.props = props;
    }

    /**
     * Said once at startup rather than per controller: an operator who thinks
     * they enabled a surface and sees every path 404 has no other way to find
     * out that their token was two characters too short.
     */
    @PostConstruct
    void announce() {
        log.info("Platform operators: members of the '{}' Cognito group", props.group());
        if (props.tokenEnabled()) {
            log.info("Break-glass admin token is enabled");
        } else if (props.tooShort()) {
            log.warn("PARTNER_ADMIN_TOKEN is shorter than {} characters, so the break-glass "
                + "path stays disabled", PlatformAdminProperties.MIN_TOKEN_LENGTH);
        } else {
            log.info("PARTNER_ADMIN_TOKEN is unset — operator surfaces are group-only");
        }
    }

    @Override
    public AdminActor require(String presentedToken, Jwt jwt) {
        return resolve(presentedToken, jwt).orElseThrow(
            () -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such endpoint"));
    }

    @Override
    public Optional<AdminActor> resolve(String presentedToken, Jwt jwt) {
        if (isPlatformAdmin(jwt)) {
            // Prefer the person: an email in the audit line beats a subject id.
            String who = jwt.getClaimAsString("email");
            return Optional.of(new AdminActor(who == null ? jwt.getSubject() : who, false));
        }
        if (props.matches(presentedToken)) {
            return Optional.of(new AdminActor("break-glass token", true));
        }
        return Optional.empty();
    }

    @Override
    public boolean isPlatformAdmin(Jwt jwt) {
        if (jwt == null) {
            return false;
        }
        List<String> groups = jwt.getClaimAsStringList(GROUPS_CLAIM);
        return groups != null && groups.contains(props.group());
    }

    @Override
    public String groupName() {
        return props.group();
    }
}
