// WebSocket $connect request authorizer. The iOS client opens
//   wss://{api}/{stage}?token={single-use connect ticket}
// and this Lambda spends that ticket, returning an IAM Allow policy whose
// context carries the Cognito subject it was minted for. The $connect handler
// reads that subject to register the connection; nothing downstream trusts a
// client-supplied identity.
//
// WHY A TICKET AND NOT THE ID TOKEN. A wss:// handshake cannot carry an
// Authorization header, so whatever authenticates it ends up in the query
// string — and query strings are written verbatim into API Gateway and
// CloudWatch access logs. An ID token there is an hour of full account access
// sitting in plain text in a log store. A ticket is random, bound to one
// account, dead in ~30s, and consumed by the DeleteItem below as it is read, so
// it works exactly once even inside that window. The backend mints it over an
// ordinary authenticated REST call, where the token rides in a header.
//
// WHY THE PARAMETER IS STILL CALLED `token`. It is the API's declared identity
// source, and API Gateway rejects a $connect that omits a declared identity
// source *before* this Lambda runs. Keeping the name means a build sending a
// ticket and a build sending an ID token both reach here and are told apart on
// shape — a JWT is three dot-separated segments, a ticket is base64url and has
// no dots — instead of older installs being cut off at the gateway with a 401
// nobody can debug from the app. Renaming it is a follow-up for once the
// legacy path is closed.
//
// The legacy ID-token path is accepted while older builds are in the wild.
// Set WS_ALLOW_TOKEN_AUTH=false to close it once the ticket build is adopted.
//
// NOTE: this authorizer must not be cached (authorizerResultTtlInSeconds=0, set
// in the messaging stack). A cached Allow keyed on the credential would hand a
// replayed ticket a connection without ever invoking this code, which is
// exactly the property single-use exists to deny.
//
// No npm deps: Node built-in crypto verifies RS256 straight from a JWK, and
// @aws-sdk/client-dynamodb ships in the Node runtime.

import https from 'node:https';
import crypto from 'node:crypto';
import { DynamoDBClient, DeleteItemCommand } from '@aws-sdk/client-dynamodb';

const ISSUER = process.env.COGNITO_ISSUER_URI; // https://cognito-idp.{region}.amazonaws.com/{poolId}
const APP_CLIENT_ID = process.env.COGNITO_APP_CLIENT_ID;
const JWKS_URL = `${ISSUER}/.well-known/jwks.json`;
const TABLE = process.env.MESSAGING_TABLE;
// Defaults open so a deploy of this Lambda alone cannot lock out installed apps
// that still send a token. Flip to 'false' once the new build is everywhere.
const allowLegacyToken = process.env.WS_ALLOW_TOKEN_AUTH !== 'false';

const ddb = new DynamoDBClient({});

let cachedKeys = null;
let cachedKeysAt = 0;

export const handler = async (event) => {
  try {
    // `ticket` is accepted too, so the query-string name can be migrated later
    // without touching this Lambda again.
    const credential = paramFrom(event, 'ticket') || tokenFrom(event);
    if (!isJwt(credential)) {
      const sub = await spendTicket(credential);
      return policy(sub, 'Allow', event.methodArn, { sub, email: '' });
    }
    if (!allowLegacyToken) throw new Error('ID-token auth is closed; send a ticket');
    const payload = await verify(credential);
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

/** Three dot-separated segments. A base64url ticket contains no dots, so this
 *  separates the two credential shapes with no ambiguity. */
function isJwt(value) {
  return typeof value === 'string' && value.split('.').length === 3;
}

/**
 * Reads and destroys a connect ticket in one call, returning the Cognito
 * subject it was minted for.
 *
 * DeleteItem with ReturnValues=ALL_OLD is what makes this single-use: the
 * delete is atomic, so of two racing handshakes presenting the same ticket
 * exactly one gets the attributes back and the other gets nothing. A check
 * followed by a delete would let both through.
 *
 * The expiry is compared here rather than left to DynamoDB's TTL sweeper, which
 * is lazy by design (rows can linger for hours past their ttl).
 */
async function spendTicket(ticket) {
  if (!TABLE) throw new Error('No messaging table configured');
  const spent = await ddb.send(new DeleteItemCommand({
    TableName: TABLE,
    Key: { pk: { S: `WSTICKET#${ticket}` }, sk: { S: 'TICKET' } },
    ReturnValues: 'ALL_OLD',
  }));
  const row = spent.Attributes;
  // Already spent, never existed, or swept — all the same answer, so a stream
  // of guesses learns nothing from the difference.
  if (!row || !row.sub) throw new Error('Unknown ticket');
  const expiresAt = Number(row.expiresAt?.N ?? 0);
  if (!expiresAt || expiresAt < Math.floor(Date.now() / 1000)) {
    throw new Error('Expired ticket');
  }
  return row.sub.S;
}

/** A named query-string parameter, or null. */
function paramFrom(event, name) {
  const value = event.queryStringParameters && event.queryStringParameters[name];
  return typeof value === 'string' && value.length > 0 ? value : null;
}

function tokenFrom(event) {
  const token = paramFrom(event, 'token');
  if (token) return token;
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
