package com.gojogo;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import java.util.Arrays;
import java.util.List;

@Configuration
@EnableWebSecurity
class SecurityConfig {

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
                // Partner review (KYC approvals). Still permitAll in the chain
                // because the break-glass token path has no JWT to present —
                // the endpoints authorize themselves, accepting either a caller
                // in the platform-admin Cognito group or PARTNER_ADMIN_TOKEN,
                // and 404ing anyone who is neither (see PlatformAdmins). A
                // bearer token that *is* presented is still validated here, so
                // a forged one never reaches the group check.
                .requestMatchers("/v1/partner/admin/**").permitAll()
                // Sumsub's verdict callback. The caller is a machine with no
                // Cognito account, so its HMAC signature over the raw body is
                // the authentication — checked in KycWebhookController before
                // the body is parsed, and refused outright when no webhook
                // secret is configured.
                .requestMatchers(HttpMethod.POST, "/v1/kyc/webhook").permitAll()
                .anyRequest().authenticated())
            .oauth2ResourceServer(oauth2 -> oauth2.jwt(Customizer.withDefaults()));
        return http.build();
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
