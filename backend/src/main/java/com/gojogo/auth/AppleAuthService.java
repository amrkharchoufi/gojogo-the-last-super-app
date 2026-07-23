package com.gojogo.auth;

import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.jwk.source.JWKSource;
import com.nimbusds.jose.jwk.source.JWKSourceBuilder;
import com.nimbusds.jose.proc.JWSVerificationKeySelector;
import com.nimbusds.jose.proc.SecurityContext;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.proc.DefaultJWTClaimsVerifier;
import com.nimbusds.jwt.proc.DefaultJWTProcessor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.cognitoidentityprovider.CognitoIdentityProviderClient;
import software.amazon.awssdk.services.cognitoidentityprovider.model.AdminInitiateAuthResponse;
import software.amazon.awssdk.services.cognitoidentityprovider.model.AdminRespondToAuthChallengeResponse;
import software.amazon.awssdk.services.cognitoidentityprovider.model.AttributeType;
import software.amazon.awssdk.services.cognitoidentityprovider.model.AuthFlowType;
import software.amazon.awssdk.services.cognitoidentityprovider.model.AuthenticationResultType;
import software.amazon.awssdk.services.cognitoidentityprovider.model.ChallengeNameType;
import software.amazon.awssdk.services.cognitoidentityprovider.model.MessageActionType;
import software.amazon.awssdk.services.cognitoidentityprovider.model.UserNotFoundException;

import java.net.URI;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * Native Sign in with Apple, without Cognito federation.
 *
 * <p>The iOS app runs the native Apple flow and posts the resulting identity
 * token here. We verify that token against Apple's public keys, then treat the
 * verified Apple user as the source of truth for a Cognito user we own:
 * create-or-link it, set a fresh random password, and immediately exchange that
 * password for Cognito tokens via {@code ADMIN_USER_PASSWORD_AUTH}. Downstream
 * ({@code /v1/auth/session}, the resource server) is identical to email/Google.
 */
@Service
class AppleAuthService {

    private static final String APPLE_ISSUER = "https://appleid.apple.com";
    private static final URL APPLE_JWKS = appleJwksUrl();

    private final DefaultJWTProcessor<SecurityContext> jwtProcessor;
    private final CognitoIdentityProviderClient cognito;
    private final String userPoolId;
    private final String appClientId;

    AppleAuthService(
        @Value("${gojogo.apple.audience:${APPLE_AUDIENCE:}}") String appleAudience,
        @Value("${gojogo.cognito.user-pool-id:${COGNITO_USER_POOL_ID:}}") String userPoolId,
        @Value("${gojogo.cognito.app-client-id:${COGNITO_APP_CLIENT_ID:}}") String appClientId,
        @Value("${AWS_REGION:us-east-1}") String region) {

        this.userPoolId = userPoolId;
        this.appClientId = appClientId;

        JWKSource<SecurityContext> keySource = JWKSourceBuilder.create(APPLE_JWKS).build();
        this.jwtProcessor = new DefaultJWTProcessor<>();
        this.jwtProcessor.setJWSKeySelector(new JWSVerificationKeySelector<>(JWSAlgorithm.RS256, keySource));
        // Verifies aud == our bundle id and iss == Apple, and that the core
        // claims are present; exp is enforced automatically.
        this.jwtProcessor.setJWTClaimsSetVerifier(new DefaultJWTClaimsVerifier<>(
            appleAudience,
            new JWTClaimsSet.Builder().issuer(APPLE_ISSUER).build(),
            Set.of("sub", "iat", "exp", "nonce")));

        this.cognito = CognitoIdentityProviderClient.builder()
            .region(Region.of(region))
            .build();
    }

    TokenResponse exchange(AppleSignInRequest request) {
        JWTClaimsSet claims = verifyIdentityToken(request.identityToken(), request.rawNonce());

        String appleSub;
        String email;
        try {
            appleSub = claims.getSubject();
            email = claims.getStringClaim("email");
        } catch (Exception e) {
            throw new AppleAuthException("Malformed Apple token claims", e);
        }
        if (appleSub == null || appleSub.isBlank()) {
            throw new AppleAuthException("Apple token missing subject");
        }
        // Apple always returns an email claim (real, or a private-relay address)
        // when the user grants it; guard for the rare case it is withheld.
        if (email == null || email.isBlank()) {
            email = appleSub.replaceAll("[^A-Za-z0-9]", "") + "@appleid.gojogo";
        }

        // Email is the pool's username (UsernameAttributes=email), so every
        // provider for a given person maps to one Cognito user — that is the
        // account link. We never reset an existing user's password (below), so
        // an email/password account keeps working alongside Apple.
        ensureUser(email);
        return mintTokens(email, request.identityToken());
    }

    private JWTClaimsSet verifyIdentityToken(String identityToken, String rawNonce) {
        JWTClaimsSet claims;
        try {
            claims = jwtProcessor.process(identityToken, null);
        } catch (Exception e) {
            throw new AppleAuthException("Apple identity token failed verification", e);
        }
        // The app set request.nonce = SHA-256(rawNonce); Apple echoes that hash
        // in the token, so the hash of the raw value we were given must match.
        String tokenNonce;
        try {
            tokenNonce = claims.getStringClaim("nonce");
        } catch (Exception e) {
            throw new AppleAuthException("Apple token missing nonce", e);
        }
        if (tokenNonce == null || !tokenNonce.equals(sha256Hex(rawNonce))) {
            throw new AppleAuthException("Apple sign-in nonce mismatch");
        }
        return claims;
    }

    private void ensureUser(String email) {
        try {
            cognito.adminGetUser(b -> b.userPoolId(userPoolId).username(email));
        } catch (UserNotFoundException notFound) {
            // Brand-new Apple-only user. Create it and set a random permanent
            // password purely to move it out of FORCE_CHANGE_PASSWORD so the
            // CUSTOM_AUTH flow can run; the user never knows or needs it. (This
            // only ever touches accounts we just created, so it is not
            // destructive to real email/password users.)
            cognito.adminCreateUser(b -> b
                .userPoolId(userPoolId)
                .username(email)
                .messageAction(MessageActionType.SUPPRESS)
                .userAttributes(
                    AttributeType.builder().name("email").value(email).build(),
                    AttributeType.builder().name("email_verified").value("true").build()));
            String password = "aA1-" + UUID.randomUUID() + UUID.randomUUID();
            cognito.adminSetUserPassword(b -> b
                .userPoolId(userPoolId)
                .username(email)
                .password(password)
                .permanent(true));
        }
    }

    /**
     * Mints tokens through the passwordless CUSTOM_AUTH flow. The single
     * challenge answer is the Apple identity token, which the authTriggers
     * Lambda re-validates — so this never uses or resets the user's password.
     */
    private TokenResponse mintTokens(String email, String identityToken) {
        AdminInitiateAuthResponse init = cognito.adminInitiateAuth(b -> b
            .userPoolId(userPoolId)
            .clientId(appClientId)
            .authFlow(AuthFlowType.CUSTOM_AUTH)
            .authParameters(Map.of("USERNAME", email)));

        if (init.challengeName() != ChallengeNameType.CUSTOM_CHALLENGE) {
            throw new AppleAuthException("Unexpected auth challenge: " + init.challengeNameAsString());
        }

        AdminRespondToAuthChallengeResponse response = cognito.adminRespondToAuthChallenge(b -> b
            .userPoolId(userPoolId)
            .clientId(appClientId)
            .challengeName(ChallengeNameType.CUSTOM_CHALLENGE)
            .session(init.session())
            .challengeResponses(Map.of("USERNAME", email, "ANSWER", identityToken)));

        AuthenticationResultType result = response.authenticationResult();
        if (result == null || result.idToken() == null) {
            throw new AppleAuthException("Cognito did not return tokens for the Apple user");
        }
        return new TokenResponse(
            result.idToken(), result.accessToken(), result.refreshToken(), result.expiresIn());
    }

    private static String sha256Hex(String value) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                .digest(value.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest);
        } catch (Exception e) {
            throw new AppleAuthException("Unable to hash nonce", e);
        }
    }

    private static URL appleJwksUrl() {
        try {
            return URI.create(APPLE_ISSUER + "/auth/keys").toURL();
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }
}
