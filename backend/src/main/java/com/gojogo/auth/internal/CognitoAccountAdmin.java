package com.gojogo.auth.internal;

import com.gojogo.auth.AccountAdminApi;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.cognitoidentityprovider.CognitoIdentityProviderClient;
import software.amazon.awssdk.services.cognitoidentityprovider.model.UserNotFoundException;

/** The one implementation of {@link AccountAdminApi} — see that interface for why. */
@Service
class CognitoAccountAdmin implements AccountAdminApi {

    private static final Logger log = LoggerFactory.getLogger(CognitoAccountAdmin.class);

    private final CognitoIdentityProviderClient cognito;
    private final String userPoolId;

    CognitoAccountAdmin(
            @Value("${gojogo.cognito.user-pool-id:${COGNITO_USER_POOL_ID:}}") String userPoolId,
            @Value("${AWS_REGION:us-east-1}") String region) {
        this.userPoolId = userPoolId == null ? "" : userPoolId.trim();
        // Built even when unconfigured: the client is inert until a call is
        // made, and every call is guarded below. Failing construction would take
        // the whole application down over a feature nobody may use.
        this.cognito = CognitoIdentityProviderClient.builder().region(Region.of(region)).build();
        if (this.userPoolId.isEmpty()) {
            log.info("Account admin off: COGNITO_USER_POOL_ID is unset, so suspensions and "
                + "deletions are recorded but sign-in is not actually disabled");
        }
    }

    @Override
    public boolean disableSignIn(String cognitoSub) {
        if (!usable(cognitoSub)) {
            return false;
        }
        try {
            cognito.adminDisableUser(b -> b.userPoolId(userPoolId).username(cognitoSub));
            // Disabling stops new sign-ins; it does not invalidate the refresh
            // token already on the device, which would keep minting access
            // tokens for the pool's whole refresh window. Both, or neither.
            cognito.adminUserGlobalSignOut(b -> b.userPoolId(userPoolId).username(cognitoSub));
            return true;
        } catch (UserNotFoundException gone) {
            // A profile whose Cognito user is already gone is already unable to
            // sign in, which is the outcome asked for.
            log.info("Cognito user {} not found while disabling — treating as already closed",
                cognitoSub);
            return true;
        } catch (RuntimeException e) {
            log.error("Could not disable Cognito user {}", cognitoSub, e);
            return false;
        }
    }

    @Override
    public boolean enableSignIn(String cognitoSub) {
        if (!usable(cognitoSub)) {
            return false;
        }
        try {
            cognito.adminEnableUser(b -> b.userPoolId(userPoolId).username(cognitoSub));
            return true;
        } catch (RuntimeException e) {
            log.error("Could not re-enable Cognito user {}", cognitoSub, e);
            return false;
        }
    }

    /** A business profile has no Cognito subject at all — its owner does — so a
     *  null here is ordinary rather than exceptional. */
    private boolean usable(String cognitoSub) {
        return !userPoolId.isEmpty() && cognitoSub != null && !cognitoSub.isBlank();
    }
}
