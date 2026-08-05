package com.gojogo;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.oauth2.core.DelegatingOAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2Error;
import org.springframework.security.oauth2.core.OAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2TokenValidatorResult;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtValidators;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import java.util.Arrays;
import java.util.List;

@Configuration
@EnableWebSecurity
class SecurityConfig {

    private static final Logger log = LoggerFactory.getLogger(SecurityConfig.class);

    /**
     * The operator surfaces, which are {@code permitAll} <em>in the chain</em>
     * and authorize themselves through {@code auth.PlatformAdminApi} — accepting
     * either a caller in the {@code platform-admin} Cognito group or the
     * break-glass {@code PARTNER_ADMIN_TOKEN}, and 404ing anyone who is neither.
     * They have to be permitted here because the token path carries no JWT at
     * all, so {@code authenticated()} would 401 before the controller ever ran.
     *
     * <p><b>A named list rather than four inline matchers, because leaving one
     * out is silent.</b> Phase 4 M6 added the dispute queue — the only operator
     * surface that moves money — and did not add it here, so the documented curl
     * runbook 401'd and the queue was reachable only with a platform-admin JWT.
     * Nothing failed, no test covered it, and it shipped. {@code
     * OperatorSurfaceTests} now scans for every handler that declares the
     * break-glass header — which is the exact signature of "this endpoint
     * expects callers with no JWT" — and asserts its path is covered here, so
     * the fifth one cannot repeat it.
     */
    static final List<String> OPERATOR_SURFACES = List.of(
        "/v1/partner/admin/**",
        "/v1/moderation/admin/**",
        "/v1/travel/admin/**",
        "/v1/delivery/admin/**",
        // The ownership-transfer document checkpoint (Phase 5 M2). Nested under
        // the dev-cleanup prefix that is already permitAll above, but named
        // here anyway: membership in this list is what OperatorSurfaceTests
        // checks, and an accident of prefix overlap is not a policy.
        "/v1/economy/admin/transfers/**");

    /**
     * Browser origins allowed to call this API. Empty — the default, and what
     * production runs today — means no CORS headers at all, which is right
     * while the only client is an iOS app: native apps aren't subject to CORS,
     * so an allowance would exist purely for someone else's benefit. GoJoAdmin
     * is a browser client, so its origin goes here when it exists
     * (ARCHITECTURE §10b: config, not architecture).
     */
    private final List<String> allowedOrigins;

    SecurityConfig(@Value("${gojogo.web.allowed-origins:}") String allowedOrigins) {
        this.allowedOrigins = Arrays.stream(allowedOrigins.split(","))
            .map(String::trim)
            .filter(origin -> !origin.isEmpty())
            .toList();
    }

    @Bean
    SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        http
            .cors(cors -> cors.configurationSource(corsConfigurationSource()))
            .csrf(AbstractHttpConfigurer::disable)
            .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/actuator/health", "/actuator/health/**").permitAll()
                // A ResponseStatusException is rendered by forwarding to /error,
                // and Spring Security authorizes that ERROR dispatch too — so
                // without this, any 404/409 raised on a permitAll path came back
                // as a bodyless 401 from the bearer entry point. It carries no
                // data of its own: /error only ever renders the status and
                // message of the request that just failed.
                .requestMatchers("/error").permitAll()
                // Native Apple sign-in runs before the client holds a Cognito
                // token — it validates Apple's token itself and returns one.
                .requestMatchers(HttpMethod.POST, "/v1/auth/apple").permitAll()
                // Dev-only marketplace cleanup. Outside the JWT chain so a wipe
                // is one curl rather than a minted user token — the endpoints
                // guard themselves with ECONOMY_ADMIN_TOKEN and, unset (the
                // production default), 404 whatever is presented.
                .requestMatchers("/v1/economy/admin/**").permitAll()
                // Partner review, the moderation queue, the SOS queue and the
                // dispute queue. All four are permitAll here and authorize
                // themselves in the controller — see OPERATOR_SURFACES above for
                // why they are one list. A bearer token that *is* presented is
                // still validated by this chain, so a forged one never reaches
                // the group check.
                .requestMatchers(OPERATOR_SURFACES.toArray(String[]::new)).permitAll()
                // Sumsub's verdict callback. The caller is a machine with no
                // Cognito account, so its HMAC signature over the raw body is
                // the authentication — checked in KycWebhookController before
                // the body is parsed, and refused outright when no webhook
                // secret is configured.
                .requestMatchers(HttpMethod.POST, "/v1/kyc/webhook").permitAll()
                // Stripe's payment callback, on the same terms as Sumsub's: the
                // caller is a machine, its HMAC signature over the raw body is
                // the authentication, and with no signing secret configured the
                // endpoint refuses everything rather than trusting a payload it
                // cannot check.
                .requestMatchers(HttpMethod.POST, "/v1/payments/webhook").permitAll()
                // Where Stripe's hosted pages send the customer's browser back
                // to. Public because a browser returning from Checkout carries
                // no token — and inert for the same reason: it reads nothing,
                // credits nothing, and only redirects into the app.
                .requestMatchers(HttpMethod.GET, "/v1/payments/return").permitAll()
                // A shared trip (Phase 3 M5). Public because the people a trip
                // is shared with — a parent, a flatmate, somebody meeting you at
                // the other end — are precisely the people with no account here,
                // and making them sign up first is how a safety feature stops
                // being used. The 192-bit token in the path is the whole
                // authentication, the payload is deliberately thin (a first
                // name, a plate, a position), and every failure is the same 404
                // so a stream of guesses learns nothing.
                .requestMatchers(HttpMethod.GET, "/v1/share/**").permitAll()
                .anyRequest().authenticated())
            .oauth2ResourceServer(oauth2 -> oauth2.jwt(Customizer.withDefaults()));
        return http.build();
    }

    /**
     * The bearer-token decoder, with one validator added to Spring's defaults:
     * the token must have been minted for <em>this</em> app client.
     *
     * <p>The default resource-server setup checks signature, issuer and expiry
     * and stops there — so every token the Cognito user pool has ever signed is
     * accepted, whichever app client asked for it. A pool routinely grows a
     * second, lower-trust client (a web console, a partner integration), and a
     * token issued to that client would otherwise arrive here with full user
     * privileges, group claims included. So we pin the audience: a Cognito ID
     * token carries the client id in {@code aud}, an access token in
     * {@code client_id}, and either must equal our configured client.
     *
     * <p>Enforced only when {@code gojogo.cognito.app-client-id} is set, which it
     * is on every real deploy. Left blank — local dev against the placeholder
     * issuer — the check is skipped with a warning rather than locking the door
     * on a key that was never cut.
     */
    @Bean
    JwtDecoder jwtDecoder(
            @Value("${spring.security.oauth2.resourceserver.jwt.issuer-uri}") String issuer,
            @Value("${gojogo.cognito.app-client-id:}") String appClientId) {
        NimbusJwtDecoder decoder = NimbusJwtDecoder.withIssuerLocation(issuer).build();
        OAuth2TokenValidator<Jwt> withIssuer = JwtValidators.createDefaultWithIssuer(issuer);
        if (appClientId == null || appClientId.isBlank()) {
            log.warn("COGNITO_APP_CLIENT_ID is unset — bearer tokens are accepted from any "
                + "app client in the pool. Set it to pin the audience.");
            decoder.setJwtValidator(withIssuer);
        } else {
            decoder.setJwtValidator(new DelegatingOAuth2TokenValidator<>(
                withIssuer, audienceValidator(appClientId.trim())));
        }
        return decoder;
    }

    /** Accepts a token whose {@code aud} (ID token) or {@code client_id} (access
     *  token) is this app client, and refuses every other one. */
    private static OAuth2TokenValidator<Jwt> audienceValidator(String appClientId) {
        OAuth2Error error = new OAuth2Error("invalid_token",
            "The token was not issued for this application", null);
        return jwt -> {
            List<String> audiences = jwt.getAudience();
            String clientId = jwt.getClaimAsString("client_id");
            boolean forUs = (audiences != null && audiences.contains(appClientId))
                || appClientId.equals(clientId);
            return forUs ? OAuth2TokenValidatorResult.success()
                         : OAuth2TokenValidatorResult.failure(error);
        };
    }

    private CorsConfigurationSource corsConfigurationSource() {
        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        if (allowedOrigins.isEmpty()) {
            return source; // no mapping registered → no CORS headers, as today
        }
        CorsConfiguration config = new CorsConfiguration();
        config.setAllowedOrigins(allowedOrigins);
        config.setAllowedMethods(List.of("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"));
        // Authorization for the operator's own token, and the break-glass header.
        config.setAllowedHeaders(List.of("Authorization", "Content-Type",
            "X-Partner-Admin-Token", "X-Economy-Admin-Token"));
        config.setMaxAge(3600L);
        source.registerCorsConfiguration("/**", config);
        return source;
    }
}
