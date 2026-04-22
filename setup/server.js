#!/usr/bin/env node
/**
 * Host-Side Setup Server
 * Runs BEFORE docker compose up. Serves the AI provider setup wizard,
 * writes .env, then exits so the install script can continue.
 *
 * Zero npm dependencies — Node built-ins only.
 *
 * Usage:
 *   node setup/server.js --project-dir /path/to/claude-code-docker
 */

const http = require('http');
const fs = require('fs');
const path = require('path');
const { URL } = require('url');
const providers = require('./providers');

// -------------------------------------------------------------------------
// CLI arguments
// -------------------------------------------------------------------------
const args = process.argv.slice(2);
let projectDir = process.cwd();

for (let i = 0; i < args.length; i++) {
  if (args[i] === '--project-dir' && args[i + 1]) {
    projectDir = path.resolve(args[++i]);
  }
}

const ENV_PATH = path.join(projectDir, '.env');

// Pick a port: try 9222, fall back to 9223-9229
const BASE_PORT = 9222;
let serverPort = BASE_PORT;

// -------------------------------------------------------------------------
// Helpers
// -------------------------------------------------------------------------
const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
};

function parseBody(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', chunk => { data += chunk; if (data.length > 1e6) reject(new Error('Body too large')); });
    req.on('end', () => {
      try { resolve(data ? JSON.parse(data) : {}); }
      catch { reject(new Error('Invalid JSON')); }
    });
    req.on('error', reject);
  });
}

function jsonReply(res, status, obj) {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(obj));
}

function serveStatic(res, filePath) {
  const ext = path.extname(filePath);
  const mime = MIME[ext] || 'application/octet-stream';

  try {
    const content = fs.readFileSync(filePath);
    res.writeHead(200, { 'Content-Type': mime });
    res.end(content);
  } catch {
    res.writeHead(404);
    res.end('Not found');
  }
}

// -------------------------------------------------------------------------
// Server
// -------------------------------------------------------------------------
const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost:${serverPort}`);

  // CORS for local development
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return; }

  // ---- API routes ----

  if (url.pathname === '/api/status' && req.method === 'GET') {
    jsonReply(res, 200, providers.getProviderStatus(ENV_PATH));
    return;
  }

  if (url.pathname === '/api/definitions' && req.method === 'GET') {
    jsonReply(res, 200, providers.PROVIDER_DEFS);
    return;
  }

  if (url.pathname === '/api/check-prereqs' && req.method === 'POST') {
    try {
      const body = await parseBody(req);
      jsonReply(res, 200, providers.checkPrerequisites(body.providerId));
    } catch (err) { jsonReply(res, 400, { error: err.message }); }
    return;
  }

  if (url.pathname === '/api/configure' && req.method === 'POST') {
    try {
      const body = await parseBody(req);
      const result = providers.configureProvider(ENV_PATH, body.providerId, body.config);
      jsonReply(res, 200, result);
    } catch (err) { jsonReply(res, 400, { error: err.message }); }
    return;
  }

  if (url.pathname === '/api/test' && req.method === 'POST') {
    try {
      const body = await parseBody(req);
      jsonReply(res, 200, providers.testProvider(body.providerId, body.config));
    } catch (err) { jsonReply(res, 400, { error: err.message }); }
    return;
  }

  if (url.pathname === '/api/done' && req.method === 'POST') {
    jsonReply(res, 200, { ok: true });
    console.log('[setup] Configuration complete. Shutting down setup server.');
    setTimeout(() => process.exit(0), 500);
    return;
  }

  // ---- Static files ----

  let filePath = url.pathname === '/' ? '/index.html' : url.pathname;
  filePath = path.join(__dirname, 'public', filePath);
  serveStatic(res, filePath);
});

// Try ports 9222-9229
function tryListen(port) {
  return new Promise((resolve) => {
    server.once('error', (err) => {
      if (err.code === 'EADDRINUSE' && port < BASE_PORT + 8) {
        resolve(tryListen(port + 1));
      } else {
        console.error(`[setup] Could not start server: ${err.message}`);
        process.exit(1);
      }
    });
    server.listen(port, '127.0.0.1', () => {
      serverPort = port;
      resolve();
    });
  });
}

// 10-minute timeout — if user never completes, exit so install script doesn't hang forever
const TIMEOUT_MS = 10 * 60 * 1000;

tryListen(BASE_PORT).then(() => {
  console.log(`[setup] AI Provider Setup running at http://127.0.0.1:${serverPort}`);
  console.log(`[setup] Waiting for configuration (timeout: 10 minutes)...`);
  console.log(`[setup] Project directory: ${projectDir}`);
  console.log(`[setup] .env path: ${ENV_PATH}`);

  setTimeout(() => {
    console.log('[setup] Timeout reached. Shutting down.');
    process.exit(0);
  }, TIMEOUT_MS);
});
