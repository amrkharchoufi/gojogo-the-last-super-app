// WebSocket $connect request authorizer. The iOS client opens
//   wss://{api}/{stage}?token={Cognito ID token}
// and this Lambda validates that token against the Cognito user pool's JWKS
// (same pool as the REST resource server), then returns an IAM Allow policy
// whose context carries the Cognito subject. The $connect handler reads that
// subject to register the connection; nothing downstream trusts a client-
// supplied identity.
//
// No npm deps: Node built-in crypto verifies RS256 straight from a JWK.

import https from 'node:https';
import crypto from 'node:crypto';

const ISSUER = process.env.COGNITO_ISSUER_URI; // https://cognito-idp.{region}.amazonaws.com/{poolId}
const APP_CLIENT_ID = process.env.COGNITO_APP_CLIENT_ID;
const JWKS_URL = `${ISSUER}/.well-known/jwks.json`;

let cachedKeys = null;
let cachedKeysAt = 0;

export const handler = async (event) => {
  const token = tokenFrom(event);
  try {
    const payload = await verify(token);
    return policy(payload.sub, 'Allow', event.methodArn, {
      sub: payload.sub,
      email: payload.email || '',
    });
  } catch (err) {
    console.error('WS authorizer rejected:', err.message);
    // Throwing 'Unauthorized' yields a 401; an explicit Deny yields 403.
    throw new Error('Unauthorized');
  }
};

function tokenFrom(event) {
  if (event.queryStringParameters && event.queryStringParameters.token) {
    return event.queryStringParameters.token;
  }
  if (Array.isArray(event.identitySource) && event.identitySource[0]) {
    return event.identitySource[0];
  }
  throw new Error('Missing token');
}

async function verify(jwt) {
  if (typeof jwt !== 'string') throw new Error('Missing token');
  const [headerB64, payloadB64, sigB64] = jwt.split('.');
  if (!headerB64 || !payloadB64 || !sigB64) throw new Error('Malformed JWT');

  const header = JSON.parse(base64UrlDecode(headerB64).toString('utf8'));
  const payload = JSON.parse(base64UrlDecode(payloadB64).toString('utf8'));

  if (payload.iss !== ISSUER) throw new Error('Bad issuer');
  if (payload.token_use !== 'id') throw new Error('Not an ID token');
  const aud = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
  if (!aud.includes(APP_CLIENT_ID)) throw new Error('Bad audience');
  const now = Math.floor(Date.now() / 1000);
  if (typeof payload.exp !== 'number' || payload.exp < now) throw new Error('Expired');

  const jwk = await signingKey(header.kid);
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

async function signingKey(kid) {
  if (!cachedKeys || Date.now() - cachedKeysAt > 60 * 60 * 1000) {
    cachedKeys = await fetchJson(JWKS_URL);
    cachedKeysAt = Date.now();
  }
  let key = cachedKeys.keys?.find((k) => k.kid === kid);
  if (!key) {
    cachedKeys = await fetchJson(JWKS_URL);
    cachedKeysAt = Date.now();
    key = cachedKeys.keys?.find((k) => k.kid === kid);
  }
  if (!key) throw new Error('Unknown signing key');
  return key;
}

function policy(principalId, effect, resource, context) {
  return {
    principalId,
    policyDocument: {
      Version: '2012-10-17',
      Statement: [{ Action: 'execute-api:Invoke', Effect: effect, Resource: resource }],
    },
    context,
  };
}

function base64UrlDecode(input) {
  return Buffer.from(input.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
}

function fetchJson(url) {
  return new Promise((resolve, reject) => {
    https
      .get(url, (res) => {
        let data = '';
        res.on('data', (c) => (data += c));
        res.on('end', () => {
          try {
            resolve(JSON.parse(data));
          } catch (e) {
            reject(e);
          }
        });
      })
      .on('error', reject);
  });
}
