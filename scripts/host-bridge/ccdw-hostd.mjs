// =============================================================================
// ccdw-hostd.mjs — CCDW host bridge daemon (macOS host side)
// -----------------------------------------------------------------------------
// Gives the container a thin, tightly-scoped RPC to a few macOS host binaries
// so the containerized terminal feels native:
//
//   pbcopy / pbpaste   real macOS pasteboard (bidirectional)
//   open               launch a file in its host app, or a URL in the browser
//   reveal             reveal a file in Finder (open -R)
//   notify             post a macOS Notification Center banner
//
// SECURITY MODEL (this endpoint runs commands on the host at the container's
// request, so it is deliberately locked down):
//   * Binds 127.0.0.1 ONLY. On Docker Desktop the container reaches host
//     loopback via host.docker.internal, so no LAN/interface is exposed.
//   * Requires a per-install random token (X-CCDW-Token header), compared in
//     constant time. The token lives in a 0600 file on the shared mount.
//   * Fixed action whitelist. No arbitrary command, ever.
//   * No shell: every host command runs via execFile with an argv array.
//     User-supplied data is passed as arguments, never interpolated into a
//     shell/AppleScript string.
//   * open/reveal only accept an absolute path under an allowed mount root
//     (translated container->host) OR an http/https/mailto URL.
//   * Request body is size-capped.
// =============================================================================

import http from 'node:http';
import { execFile, spawn } from 'node:child_process';
import { timingSafeEqual } from 'node:crypto';

const PORT = parseInt(process.env.CCDW_BRIDGE_PORT || '7690', 10);
const TOKEN = process.env.CCDW_BRIDGE_TOKEN || '';
const MAX_BODY = 8 * 1024 * 1024; // 8 MB clipboard cap

if (!TOKEN) {
  console.error('ccdw-hostd: CCDW_BRIDGE_TOKEN not set — refusing to start.');
  process.exit(1);
}

// Container-path -> host-path prefix map. Longest prefix wins. These mirror the
// bind mounts in docker-compose.yml; the launcher passes the real host targets.
const HOST_HOME = process.env.CCDW_HOST_HOME || '';
const PATH_MAP = [
  ['/home/coder/Documents', process.env.CCDW_HOST_DOCUMENTS || ''],
  ['/home/coder/Downloads', process.env.CCDW_HOST_DOWNLOADS || ''],
  ['/home/coder/Desktop',   process.env.CCDW_HOST_DESKTOP   || ''],
  ['/Volumes',              process.env.CCDW_HOST_VOLUMES   || '/Volumes'],
  // Path parity: the container symlinks HOST_HOME -> /home/coder, so a
  // host-style path (/Users/<you>/...) is identical on both sides — map it
  // to itself so `open`/`reveal` accept it too.
  [HOST_HOME, HOST_HOME],
].filter(([c, host]) => c && host).sort((a, b) => b[0].length - a[0].length);

const URL_SCHEMES = /^(https?|mailto):/i;

function translatePath(containerPath) {
  for (const [cPrefix, hPrefix] of PATH_MAP) {
    if (containerPath === cPrefix || containerPath.startsWith(cPrefix + '/')) {
      return hPrefix + containerPath.slice(cPrefix.length);
    }
  }
  return null; // not under an allowed root
}

function tokenOk(req) {
  const got = req.headers['x-ccdw-token'];
  if (typeof got !== 'string' || got.length !== TOKEN.length) return false;
  try {
    return timingSafeEqual(Buffer.from(got), Buffer.from(TOKEN));
  } catch {
    return false;
  }
}

function send(res, code, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(code, { 'Content-Type': 'application/json' });
  res.end(body);
}

// --- action handlers --------------------------------------------------------

function doPbcopy(body, res) {
  const buf = Buffer.from(body.data || '', 'base64');
  const child = spawn('pbcopy');
  child.on('error', () => send(res, 500, { ok: false, error: 'pbcopy failed' }));
  child.on('close', () => send(res, 200, { ok: true }));
  child.stdin.end(buf);
}

function doPbpaste(_body, res) {
  execFile('pbpaste', { maxBuffer: MAX_BODY, encoding: 'buffer' }, (err, stdout) => {
    if (err) return send(res, 500, { ok: false, error: 'pbpaste failed' });
    send(res, 200, { ok: true, data: stdout.toString('base64') });
  });
}

// Resolve an open/reveal target to a safe argv value: an absolute host path
// under an allowed root, or a whitelisted URL scheme. Returns null if unsafe.
function resolveTarget(target) {
  if (typeof target !== 'string' || target.length === 0) return null;
  if (URL_SCHEMES.test(target)) return target;
  if (!target.startsWith('/')) return null;      // must be absolute container path
  const host = translatePath(target);
  if (!host || !host.startsWith('/')) return null;
  return host;
}

function doOpen(body, res) {
  const t = resolveTarget(body.target);
  if (!t) return send(res, 400, { ok: false, error: 'target not allowed' });
  execFile('open', [t], (err) => {
    if (err) return send(res, 500, { ok: false, error: 'open failed' });
    send(res, 200, { ok: true, resolved: t });
  });
}

function doReveal(body, res) {
  const t = resolveTarget(body.target);
  if (!t || URL_SCHEMES.test(t)) {
    return send(res, 400, { ok: false, error: 'target not allowed' });
  }
  execFile('open', ['-R', t], (err) => {
    if (err) return send(res, 500, { ok: false, error: 'reveal failed' });
    send(res, 200, { ok: true, resolved: t });
  });
}

function doNotify(body, res) {
  const message = String(body.message || '').slice(0, 2000);
  const title = String(body.title || 'CCDW').slice(0, 256);
  // Pass data as argv into AppleScript — no string interpolation, no injection.
  const script = 'on run argv\n'
    + 'display notification (item 1 of argv) with title (item 2 of argv)\n'
    + 'end run';
  execFile('osascript', ['-e', script, message, title], (err) => {
    if (err) return send(res, 500, { ok: false, error: 'notify failed' });
    send(res, 200, { ok: true });
  });
}

const ACTIONS = {
  pbcopy: doPbcopy,
  pbpaste: doPbpaste,
  open: doOpen,
  reveal: doReveal,
  notify: doNotify,
};

// --- server -----------------------------------------------------------------

const server = http.createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/health') {
    return send(res, 200, { ok: true, service: 'ccdw-hostd' });
  }
  if (req.method !== 'POST' || req.url !== '/rpc') {
    return send(res, 404, { ok: false, error: 'not found' });
  }
  if (!tokenOk(req)) {
    return send(res, 403, { ok: false, error: 'forbidden' });
  }

  let size = 0;
  const chunks = [];
  req.on('data', (c) => {
    size += c.length;
    if (size > MAX_BODY) {
      send(res, 413, { ok: false, error: 'too large' });
      req.destroy();
      return;
    }
    chunks.push(c);
  });
  req.on('end', () => {
    let body;
    try {
      body = JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}');
    } catch {
      return send(res, 400, { ok: false, error: 'bad json' });
    }
    const handler = ACTIONS[body.action];
    if (!handler) return send(res, 400, { ok: false, error: 'unknown action' });
    try {
      handler(body, res);
    } catch {
      send(res, 500, { ok: false, error: 'internal' });
    }
  });
});

// 127.0.0.1 ONLY. Never 0.0.0.0 — that would expose the host to the LAN.
server.listen(PORT, '127.0.0.1', () => {
  console.log(`ccdw-hostd listening on 127.0.0.1:${PORT}`);
});
