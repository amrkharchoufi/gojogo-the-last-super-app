// Cognito trigger Lambda — one function, four triggers (switched on triggerSource):
//
//  - DefineAuthChallenge / CreateAuthChallenge / VerifyAuthChallengeResponse
//    implement a passwordless CUSTOM_AUTH flow whose single challenge answer is
//    an Apple identity token. The backend (AppleAuthService) drives this flow via
//    the admin APIs; this Lambda is the security gate that re-validates Apple's
//    signature, so the public CUSTOM_AUTH surface can't be abused without a real
//    Apple token whose email matches the user being signed in.
//
//  - PreSignUp_ExternalProvider links a first-time Google (Hosted UI) sign-in to
//    the existing email-keyed Cognito user by verified email (AdminLinkProviderForUser),
//    so email/password + Google + Apple all resolve to one account/profile.
//
// No external npm deps: Node built-in crypto verifies RS256 straight from a JWK,
// and @aws-sdk/* ships in the Node 20 Lambda runtime.

import https from 'node:https';
import crypto from 'node:crypto';
import {
  CognitoIdentityProviderClient,
  ListUsersCommand,
  AdminLinkProviderForUserCommand,
} from '@aws-sdk/client-cognito-identity-provider';

// Human-readable provider names for the "already registered" message below.
const PROVIDER_LABELS = { Google: 'Google', SignInWithApple: 'Apple' };

const APPLE_ISSUER = 'https://appleid.apple.com';
const APPLE_JWKS_URL = `${APPLE_ISSUER}/auth/keys`;
const APPLE_AUDIENCE = process.env.APPLE_AUDIENCE || 'com.gojo.gojogo';

const cognito = new CognitoIdentityProviderClient({});

let cachedKeys = null;
let cachedKeysAt = 0;

export const handler = async (event) => {
  switch (event.triggerSource) {
    case 'DefineAuthChallenge_Authentication':
      return defineAuthChallenge(event);
    case 'CreateAuthChallenge_Authentication':
      return createAuthChallenge(event);
    case 'VerifyAuthChallengeResponse_Authentication':
      return verifyAuthChallenge(event);
    case 'PreSignUp_ExternalProvider':
      return preSignUpExternal(event);
    case 'PreSignUp_SignUp':
      return preSignUpNative(event);
    default:
      // PreSignUp_AdminCreateUser (the Apple path creates users this way):
      // nothing to link, pass through unchanged.
      return event;
  }
};

// MARK: CUSTOM_AUTH

function defineAuthChallenge(event) {
  const sessions = event.request.session || [];
  if (sessions.length === 0) {
    // Kick off the single custom challenge.
    event.response.issueTokens = false;
    event.response.failAuthentication = false;
    event.response.challengeName = 'CUSTOM_CHALLENGE';
  } else {
    const last = sessions[sessions.length - 1];
    const passed = last.challengeName === 'CUSTOM_CHALLENGE' && last.challengeResult === true;
    event.response.issueTokens = passed;
    event.response.failAuthentication = !passed;
  }
  return event;
}

function createAuthChallenge(event) {
  if (event.request.challengeName === 'CUSTOM_CHALLENGE') {
    // No code is delivered; the answer is the Apple identity token verified below.
    event.response.publicChallengeParameters = { challenge: 'APPLE_IDENTITY_TOKEN' };
    event.response.privateChallengeParameters = {};
    event.response.challengeMetadata = 'APPLE_IDENTITY_TOKEN';
  }
  return event;
}

async function verifyAuthChallenge(event) {
  const token = event.request.challengeAnswer;
  const expectedEmail = (event.request.userAttributes?.email || '').toLowerCase();
  let correct = false;
  try {
    const payload = await verifyAppleToken(token);
    const claimEmail = (payload.email || '').toLowerCase();
    correct = claimEmail.length > 0 && claimEmail === expectedEmail;
  } catch (err) {
    console.error('Apple token verification failed:', err);
  }
  event.response.answerCorrect = correct;
  return event;
}

async function verifyAppleToken(jwt) {
  if (typeof jwt !== 'string') throw new Error('Missing token');
  const [headerB64, payloadB64, sigB64] = jwt.split('.');
  if (!headerB64 || !payloadB64 || !sigB64) throw new Error('Malformed JWT');

  const header = JSON.parse(base64UrlDecode(headerB64).toString('utf8'));
  const payload = JSON.parse(base64UrlDecode(payloadB64).toString('utf8'));

  if (payload.iss !== APPLE_ISSUER) throw new Error('Bad issuer');
  const aud = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
  if (!aud.includes(APPLE_AUDIENCE)) throw new Error('Bad audience');
  const now = Math.floor(Date.now() / 1000);
  if (typeof payload.exp !== 'number' || payload.exp < now) throw new Error('Expired');

  const jwk = await appleKey(header.kid);
  const publicKey = crypto.createPublicKey({ key: jwk, format: 'jwk' });
  const ok = crypto.verify(
    'RSA-SHA256',
    Buffer.from(`${headerB64}.${payloadB64}`),
    publicKey,
    base64UrlDecode(sigB64),
  );
  if (!ok) throw new Error('Bad signature');
  return payload;
}

async function appleKey(kid) {
  if (!cachedKeys || Date.now() - cachedKeysAt > 60 * 60 * 1000) {
    cachedKeys = await fetchJson(APPLE_JWKS_URL);
    cachedKeysAt = Date.now();
  }
  let key = cachedKeys.keys?.find((k) => k.kid === kid);
  if (!key) {
    // Apple rotated keys — refresh once.
    cachedKeys = await fetchJson(APPLE_JWKS_URL);
    cachedKeysAt = Date.now();
    key = cachedKeys.keys?.find((k) => k.kid === kid);
  }
  if (!key) throw new Error('Unknown Apple signing key');
  return key;
}

// MARK: native (email/password) sign-up

// The reverse of the Google/Apple linking below: someone who first signed in
// with Google or Apple now tries to create an email/password account on the
// SAME email. Cognito would reject this with an opaque UsernameExistsException.
// We detect the pre-existing federated user and fail with a clear, actionable
// message telling them which provider to use instead. (We can't silently merge
// here — a native password can't be attached to a federation-only user from a
// PreSignUp trigger; AdminLinkProviderForUser only links the other direction.)
async function preSignUpNative(event) {
  const email = (event.request.userAttributes?.email || '').toLowerCase();
  if (!email) return event;

  let existing;
  try {
    existing = await cognito.send(new ListUsersCommand({
      UserPoolId: event.userPoolId,
      Filter: `email = "${email.replace(/"/g, '')}"`,
      Limit: 5,
    }));
  } catch (err) {
    // Don't block legitimate sign-ups if the lookup itself fails; let Cognito's
    // own duplicate check be the backstop.
    console.error('preSignUpNative ListUsers failed:', err);
    return event;
  }

  const federated = (existing.Users || []).find((u) => u.UserStatus === 'EXTERNAL_PROVIDER');
  if (!federated) return event; // no federated account on this email — normal sign-up

  const provider = (federated.Username || '').split('_')[0];
  const label = PROVIDER_LABELS[provider] || 'a social account';
  // Thrown from a PreSignUp trigger, Cognito surfaces this message to the client.
  throw new Error(
    `This email is already registered through ${label} sign-in. ` +
    `Please continue with ${label} instead.`,
  );
}

// MARK: Google linking

async function preSignUpExternal(event) {
  const email = (event.request.userAttributes?.email || '').toLowerCase();
  event.response.autoConfirmUser = true;
  if (event.request.userAttributes?.email_verified === 'true') {
    event.response.autoVerifyEmail = true;
  }
  if (!email) return event;

  // event.userName is like "Google_1234567890".
  const separator = event.userName.indexOf('_');
  if (separator < 0) return event;
  const providerName = event.userName.slice(0, separator);
  const providerUserId = event.userName.slice(separator + 1);
  if (!providerName || !providerUserId) return event;

  const existing = await cognito.send(new ListUsersCommand({
    UserPoolId: event.userPoolId,
    Filter: `email = "${email}"`,
    Limit: 1,
  }));
  const target = (existing.Users || []).find((u) => u.UserStatus !== 'EXTERNAL_PROVIDER');
  if (!target) return event; // first time we've seen this email — let Cognito create it

  try {
    await cognito.send(new AdminLinkProviderForUserCommand({
      UserPoolId: event.userPoolId,
      DestinationUser: { ProviderName: 'Cognito', ProviderAttributeValue: target.Username },
      SourceUser: {
        ProviderName: providerName, // "Google"
        ProviderAttributeName: 'Cognito_Subject',
        ProviderAttributeValue: providerUserId,
      },
    }));
    event.response.autoVerifyEmail = true;
  } catch (err) {
    // Already linked (idempotent replays) — safe to ignore; anything else fails loud.
    if (err.name !== 'InvalidParameterException') {
      console.error('AdminLinkProviderForUser failed:', err);
      throw err;
    }
  }
  return event;
}

// MARK: helpers

function base64UrlDecode(input) {
  return Buffer.from(input.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
}

function fetchJson(url) {
  return new Promise((resolve, reject) => {
    https
      .get(url, (res) => {
        let body = '';
        res.on('data', (chunk) => (body += chunk));
        res.on('end', () => {
          try {
            resolve(JSON.parse(body));
          } catch (err) {
            reject(err);
          }
        });
      })
      .on('error', reject);
  });
}
