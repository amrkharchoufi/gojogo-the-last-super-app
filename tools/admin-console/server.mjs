#!/usr/bin/env node
//
// GojoAdmin, locally — the operator console, until the real one exists.
//
// ARCHITECTURE §10b is emphatic that GojoAdmin gets "no private tables and no
// parallel data path": everything it does goes through the same public REST
// surface the iOS app could call. This console holds to that exactly. It has no
// database, no cache and no model of its own — it is a renderer for
// `/v1/partner/admin/**` and `/v1/moderation/admin/**`. When the real GojoAdmin
// arrives, nothing here has to be unwound; this directory is deleted.
//
// ── Why a server at all, rather than an HTML file opened from disk ───────────
//
// Two reasons, and both are about not making production worse to get a local
// tool working:
//
//   1. **CORS stays off in prod.** The backend serves only the iOS app today —
//      `WEB_ALLOWED_ORIGINS` is empty, which means no CORS headers at all. A
//      browser page on localhost calling api.gojogo.app directly would be
//      blocked, and the fix would be to add localhost to an allowlist on the
//      live task definition. Proxying through this process makes every request
//      same-origin, so production needs no change whatsoever.
//
//   2. **The break-glass token never reaches the browser.** It is read from the
//      environment here and attached server-side. Nothing in `public/` has ever
//      seen it: not in a fetch header, not in localStorage, not in the DOM. A
//      token that only exists in one process is a token that cannot leak from a
//      browser extension or a screenshot.
//
// ── What it deliberately will not do ─────────────────────────────────────────
//
// It is **not an open proxy**. A process holding an operator credential that
// forwards any path anybody asks for is a hole, so the allowlist below is the
// whole of what can be reached, and every method is checked against it. It
// binds to 127.0.0.1 only — never 0.0.0.0 — because this credential should not
// be reachable from the network the laptop is on.

import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = fileURLToPath(new URL('.', import.meta.url));
const PUBLIC_DIR = join(HERE, 'public');

const PORT = Number(process.env.PORT || 4319);
const API_BASE = (process.env.GOJOGO_API || 'https://api.gojogo.app').replace(/\/$/, '');
const ADMIN_TOKEN = process.env.PARTNER_ADMIN_TOKEN || '';
const ADMIN_JWT = process.env.GOJOGO_ADMIN_JWT || '';

/**
 * Every API path this console may reach, as a method + regex pair.
 *
 * Written out rather than derived from a prefix on purpose. `/v1/partner/admin`
 * as a bare prefix would also carry any future endpoint added under it,
 * including one nobody meant to expose here — an allowlist that grows by itself
 * is not an allowlist. Adding a screen means adding its route to this list, and
 * that is the intended friction.
 */
const ALLOWED = [
  // Partner review — the queue, one application, and its papers.
  ['GET', /^\/v1\/partner\/admin\/applications(\?.*)?$/],
  ['GET', /^\/v1\/partner\/admin\/applications\/[0-9a-f-]{36}$/],
  ['GET', /^\/v1\/partner\/admin\/applications\/[0-9a-f-]{36}\/documents\/[0-9a-f-]{36}$/],
  ['GET', /^\/v1\/partner\/admin\/vehicles\/[0-9a-f-]{36}\/documents\/[0-9a-f-]{36}$/],
  // Partner papers, filed on the applicant's behalf. Only the presign and the
  // attach are proxied: the bytes go from the browser straight to S3 on the
  // signed URL, so they never pass through this process any more than they pass
  // through the API.
  ['POST', /^\/v1\/partner\/admin\/applications\/[0-9a-f-]{36}\/documents\/presign$/],
  ['PUT', /^\/v1\/partner\/admin\/applications\/[0-9a-f-]{36}\/documents$/],
  ['DELETE', /^\/v1\/partner\/admin\/applications\/[0-9a-f-]{36}\/documents\/[0-9a-f-]{36}$/],
  // Partner decisions.
  ['POST', /^\/v1\/partner\/admin\/applications\/[0-9a-f-]{36}\/(approve|reject|suspend|submit)$/],
  ['POST', /^\/v1\/partner\/admin\/applications\/[0-9a-f-]{36}\/vehicles\/[0-9a-f-]{36}\/review$/],
  ['POST', /^\/v1\/partner\/admin\/applications$/],
  // Moderation.
  ['GET', /^\/v1\/moderation\/admin\/reports(\?.*)?$/],
  ['GET', /^\/v1\/moderation\/admin\/reports\/summary$/],
  ['GET', /^\/v1\/moderation\/admin\/reports\/[0-9a-f-]{36}$/],
  ['GET', /^\/v1\/moderation\/admin\/accounts\/[0-9a-f-]{36}\/reports(\?.*)?$/],
  ['POST', /^\/v1\/moderation\/admin\/reports\/[0-9a-f-]{36}\/(action|dismiss)$/],
  // SOS (Phase 3 M5). Read-only, and there is nothing here to decide: a trip in
  // trouble is dealt with by a person picking up a phone, not by a status
  // changing in a queue. What the surface owes an operator is the trip, who
  // raised it, and who to call.
  ['GET', /^\/v1\/travel\/admin\/sos(\?.*)?$/],
  // Liveness, so the console can say whether the API is even up.
  ['GET', /^\/actuator\/health$/]
];

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon'
};

function isAllowed(method, path) {
  return ALLOWED.some(([m, re]) => m === method && re.test(path));
}

/** The credential, attached here and only here. */
function authHeaders() {
  const headers = { accept: 'application/json' };
  if (ADMIN_JWT) headers.authorization = `Bearer ${ADMIN_JWT}`;
  if (ADMIN_TOKEN) headers['X-Partner-Admin-Token'] = ADMIN_TOKEN;
  return headers;
}

async function readBody(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  return chunks.length ? Buffer.concat(chunks).toString('utf8') : undefined;
}

async function proxy(req, res, path) {
  if (!isAllowed(req.method, path)) {
    // Named rather than a bare 403: the next person to add a screen needs to
    // know that the allowlist is why their call did not go through.
    res.writeHead(403, { 'content-type': 'application/json' });
    res.end(JSON.stringify({
      message: `${req.method} ${path} is not on this console's allowlist. `
        + 'Add it to ALLOWED in server.mjs if the screen genuinely needs it.'
    }));
    return;
  }
  if (!ADMIN_TOKEN && !ADMIN_JWT) {
    res.writeHead(503, { 'content-type': 'application/json' });
    res.end(JSON.stringify({
      message: 'No operator credential. Start with PARTNER_ADMIN_TOKEN=… (see README).'
    }));
    return;
  }

  const body = await readBody(req);
  const headers = authHeaders();
  if (body) headers['content-type'] = 'application/json';

  try {
    const upstream = await fetch(API_BASE + path, { method: req.method, headers, body });
    const text = await upstream.text();
    res.writeHead(upstream.status, {
      'content-type': upstream.headers.get('content-type') || 'application/json'
    });
    res.end(text);
  } catch (err) {
    // The API being unreachable is a normal thing to see on a laptop; say so in
    // the shape the UI already handles rather than crashing the process.
    res.writeHead(502, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ message: `Could not reach ${API_BASE}: ${err.message}` }));
  }
}

async function serveStatic(res, urlPath) {
  const rel = urlPath === '/' ? 'index.html' : normalize(urlPath).replace(/^(\.\.[/\\])+/, '');
  const file = join(PUBLIC_DIR, rel);
  if (!file.startsWith(PUBLIC_DIR)) {
    res.writeHead(403).end('No.');
    return;
  }
  try {
    const bytes = await readFile(file);
    res.writeHead(200, {
      'content-type': MIME[extname(file)] || 'application/octet-stream',
      'cache-control': 'no-store'
    });
    res.end(bytes);
  } catch {
    res.writeHead(404, { 'content-type': 'text/plain' }).end('Not found');
  }
}

const server = createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  if (url.pathname.startsWith('/api/')) {
    await proxy(req, res, url.pathname.slice(4) + url.search);
    return;
  }
  if (url.pathname === '/whoami') {
    // What the console will sign its decisions as. Never the credential itself
    // — only which kind is in play, because "who approved this" is a question
    // the operator should be able to answer before they approve anything.
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({
      api: API_BASE,
      actor: ADMIN_JWT ? 'named operator (platform-admin JWT)' : 'break-glass token',
      named: Boolean(ADMIN_JWT)
    }));
    return;
  }
  await serveStatic(res, url.pathname);
});

// A port clash is the most likely way this fails to start, and an unhandled
// 'error' event turns that into a stack trace about `_listen2`. Say the useful
// thing instead.
server.on('error', err => {
  if (err.code === 'EADDRINUSE') {
    process.stderr.write(
      `\n  Port ${PORT} is already in use — most likely this console is already running.\n`
      + `  Open http://127.0.0.1:${PORT}, or start on another port:  PORT=4320 npm start\n\n`);
    process.exit(1);
  }
  throw err;
});

server.listen(PORT, '127.0.0.1', () => {
  const credential = ADMIN_JWT
    ? 'platform-admin JWT (decisions will be signed with your name)'
    : ADMIN_TOKEN
      ? 'break-glass token (decisions will be signed "admin", with no name)'
      : 'NONE — every call will 503 until you set one';
  process.stdout.write(
    `\n  GojoAdmin console  http://127.0.0.1:${PORT}\n`
    + `  API                ${API_BASE}\n`
    + `  Credential         ${credential}\n\n`
  );
});
