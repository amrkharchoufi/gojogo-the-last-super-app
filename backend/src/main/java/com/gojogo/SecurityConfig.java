package com.gojogo;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;

@Configuration
@EnableWebSecurity
class SecurityConfig {

    @Bean
    SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        http
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
                // Partner review (KYC approvals). Same shape and same reason:
                // there is no admin role to authenticate a reviewer as, so the
                // endpoints guard themselves with PARTNER_ADMIN_TOKEN and, unset,
                // 404 whatever is presented.
                .requestMatchers("/v1/partner/admin/**").permitAll()
                .anyRequest().authenticated())
            .oauth2ResourceServer(oauth2 -> oauth2.jwt(Customizer.withDefaults()));
        return http.build();
    }
}
