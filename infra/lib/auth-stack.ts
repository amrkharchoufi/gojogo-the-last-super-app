import * as path from 'path';
import * as cdk from 'aws-cdk-lib';
import * as cognito from 'aws-cdk-lib/aws-cognito';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import { Construct } from 'constructs';

/**
 * Social sign-in wiring:
 *
 * - **Google** uses Cognito's Hosted UI (OAuth authorization-code grant). The
 *   iOS app opens `/oauth2/authorize?identity_provider=Google` in an
 *   ASWebAuthenticationSession, exchanges the code for Cognito tokens, and the
 *   backend validates those exactly like email tokens. Google client id/secret
 *   are supplied at deploy time via CDK context and are NOT committed:
 *     cdk deploy GojoGoAuthStack \
 *       -c googleClientId=xxx.apps.googleusercontent.com \
 *       -c googleClientSecret=yyy
 *
 * - **Apple** is native (ASAuthorizationController) and does NOT use Cognito
 *   federation. The app posts Apple's identity token to the backend, which
 *   drives a passwordless CUSTOM_AUTH flow to mint tokens for the one
 *   email-keyed Cognito user WITHOUT resetting its password — so email/password
 *   and Apple coexist on the same account. The `authTriggers` Lambda below is
 *   the security gate: it re-validates Apple's signature as the challenge answer.
 *
 * - **Account linking**: the same Lambda's PreSignUp_ExternalProvider trigger
 *   links a first-time Google sign-in to the existing email user by verified
 *   email (AdminLinkProviderForUser). Net effect: email/password + Google +
 *   Apple all resolve to one Cognito user (and one app profile) per email.
 */
export class GojoGoAuthStack extends cdk.Stack {
  readonly userPool: cognito.UserPool;
  readonly userPoolClient: cognito.UserPoolClient;
  readonly userPoolDomain: cognito.UserPoolDomain;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Cognito trigger Lambda: native-Apple CUSTOM_AUTH gate + Google linking.
    // Plain Node (built-in crypto + runtime-bundled AWS SDK) — no build step.
    const authTriggers = new lambda.Function(this, 'AuthTriggers', {
      functionName: 'gojogo-auth-triggers',
      runtime: lambda.Runtime.NODEJS_20_X,
      handler: 'index.handler',
      code: lambda.Code.fromAsset(path.join(__dirname, '..', 'lambda', 'auth-triggers')),
      timeout: cdk.Duration.seconds(10),
      environment: { APPLE_AUDIENCE: 'com.gojo.gojogo' },
    });

    this.userPool = new cognito.UserPool(this, 'UserPool', {
      userPoolName: 'gojogo-users',
      selfSignUpEnabled: true,
      signInAliases: { email: true },
      autoVerify: { email: true },
      standardAttributes: {
        email: { required: true, mutable: true },
      },
      passwordPolicy: {
        minLength: 8,
        requireLowercase: true,
        requireDigits: true,
        requireUppercase: false,
        requireSymbols: false,
      },
      accountRecovery: cognito.AccountRecovery.EMAIL_ONLY,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      lambdaTriggers: {
        preSignUp: authTriggers,
        defineAuthChallenge: authTriggers,
        createAuthChallenge: authTriggers,
        verifyAuthChallengeResponse: authTriggers,
      },
    });

    // The PreSignUp trigger links Google identities to existing users; it reads
    // the pool id from the trigger event. Scope the grant to a static
    // account/region userpool ARN rather than this.userPool.userPoolArn — the
    // pool already depends on this Lambda (lambdaTriggers), so referencing the
    // pool's generated ARN here would create a CloudFormation circular dependency.
    authTriggers.addToRolePolicy(new iam.PolicyStatement({
      actions: ['cognito-idp:ListUsers', 'cognito-idp:AdminLinkProviderForUser'],
      resources: [`arn:aws:cognito-idp:${this.region}:${this.account}:userpool/*`],
    }));

    // Hosted UI domain — hosts the OAuth endpoints used by the Google flow.
    // The prefix is globally unique across all AWS accounts; override with
    // `-c authDomainPrefix=...` if the default is taken.
    const authDomainPrefix =
      (this.node.tryGetContext('authDomainPrefix') as string | undefined) ?? 'gojogo-auth';
    this.userPoolDomain = this.userPool.addDomain('HostedUiDomain', {
      cognitoDomain: { domainPrefix: authDomainPrefix },
    });

    // Google identity provider (Hosted UI federation). Credentials come from
    // CDK context so they never land in source control.
    const googleClientId =
      (this.node.tryGetContext('googleClientId') as string | undefined) ?? 'REPLACE_GOOGLE_CLIENT_ID';
    const googleClientSecret =
      (this.node.tryGetContext('googleClientSecret') as string | undefined) ??
      'REPLACE_GOOGLE_CLIENT_SECRET';

    const googleIdp = new cognito.UserPoolIdentityProviderGoogle(this, 'GoogleIdp', {
      userPool: this.userPool,
      clientId: googleClientId,
      clientSecretValue: cdk.SecretValue.unsafePlainText(googleClientSecret),
      scopes: ['openid', 'email', 'profile'],
      // Map Google's profile onto the Cognito user's standard attributes.
      attributeMapping: {
        email: cognito.ProviderAttribute.GOOGLE_EMAIL,
        givenName: cognito.ProviderAttribute.GOOGLE_GIVEN_NAME,
        familyName: cognito.ProviderAttribute.GOOGLE_FAMILY_NAME,
      },
    });

    // Custom scheme the iOS app registers as its ASWebAuthenticationSession
    // callback. Must match GoogleHostedAuthClient.redirectUri on the client.
    const callbackUrls = ['gojogo://auth/callback'];

    this.userPoolClient = this.userPool.addClient('IosAppClient', {
      userPoolClientName: 'gojogo-ios',
      generateSecret: false,
      authFlows: {
        userSrp: true,
        // Enables testing sign-in from curl/REST clients without SRP.
        userPassword: true,
        // Native Apple: the backend mints tokens for the email-keyed user via a
        // passwordless CUSTOM_AUTH flow (AdminInitiateAuth + respond) gated by
        // the authTriggers Lambda — never touches the user's password.
        custom: true,
      },
      oAuth: {
        flows: { authorizationCodeGrant: true },
        scopes: [
          cognito.OAuthScope.OPENID,
          cognito.OAuthScope.EMAIL,
          cognito.OAuthScope.PROFILE,
        ],
        callbackUrls,
        logoutUrls: callbackUrls,
      },
      supportedIdentityProviders: [
        cognito.UserPoolClientIdentityProvider.COGNITO,
        cognito.UserPoolClientIdentityProvider.GOOGLE,
      ],
      idTokenValidity: cdk.Duration.hours(24),
      accessTokenValidity: cdk.Duration.hours(24),
      refreshTokenValidity: cdk.Duration.days(30),
    });
    // The client can only advertise Google once the IdP exists.
    this.userPoolClient.node.addDependency(googleIdp);

    new cdk.CfnOutput(this, 'UserPoolId', { value: this.userPool.userPoolId });
    new cdk.CfnOutput(this, 'UserPoolClientId', { value: this.userPoolClient.userPoolClientId });
    new cdk.CfnOutput(this, 'IssuerUri', {
      value: `https://cognito-idp.${this.region}.amazonaws.com/${this.userPool.userPoolId}`,
    });
    new cdk.CfnOutput(this, 'HostedUiDomain', {
      value: `${authDomainPrefix}.auth.${this.region}.amazoncognito.com`,
    });
  }
}
