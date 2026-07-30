#!/usr/bin/env node
// =============================================================================
// nav-proxy.js — tiny zero-dependency reverse proxy that injects the CCDW
// shared top-nav into apps whose HTML we don't own (ttyd terminal, code-server).
//
// It listens on a PUBLIC port and forwards to an INTERNAL target port:
//     browser :7681  -> nav-proxy :7681  -> ttyd        :17681
//     browser :7682  -> nav-proxy :7682  -> ttyd (new)  :17682
//     browser :8080  -> nav-proxy :8080  -> code-server :18080
//
// For text/html responses it injects (before </head> / </body>):
//     <link rel="stylesheet" href="/__nav/shared-nav.css">
//     <link rel="stylesheet" href="/__nav/inject.css">        (app-specific offset)
//     <script src="/__nav/shared-nav.js"></script>
// All three are served by THIS proxy under /__nav/ — same origin, so they pass
// code-server's strict CSP (`script-src 'self'`, `style-src 'self'`). WebSocket
// upgrades (ttyd /ws, code-server) are piped through untouched.
//
// Config via env:
//   NAV_PROXY_PORT   public port to listen on          (required)
//   NAV_TARGET_PORT  internal port to forward to        (required)
//   NAV_APP          'terminal' | 'vscode'              (default: terminal)
//   NAV_ASSETS_DIR   dir holding the nav asset files    (default: welcome dir)
// =============================================================================
'use strict';

const http = require('http');
const net = require('net');
const fs = require('fs');
const path = require('path');

const PORT = parseInt(process.env.NAV_PROXY_PORT || '', 10);
const TARGET = parseInt(process.env.NAV_TARGET_PORT || '', 10);
const APP = process.env.NAV_APP === 'vscode' ? 'vscode' : 'terminal';
const ASSETS = process.env.NAV_ASSETS_DIR || '/opt/claude-code-docker/welcome';
const TARGET_HOST = '127.0.0.1';

if (!PORT || !TARGET) {
    console.error('nav-proxy: NAV_PROXY_PORT and NAV_TARGET_PORT are required');
    process.exit(1);
}

// --- /__nav/ static assets served locally (same origin => CSP 'self' passes) --
const INJECT_CSS = APP === 'vscode' ? 'inject-vscode.css' : 'inject-terminal.css';
const ASSET_MAP = {
    '/__nav/shared-nav.js': { file: 'shared-nav.js', type: 'application/javascript; charset=utf-8' },
    '/__nav/shared-nav.css': { file: 'shared-nav.css', type: 'text/css; charset=utf-8' },
    '/__nav/inject.css': { file: INJECT_CSS, type: 'text/css; charset=utf-8' },
};

const HEAD_INJECT =
    '<link rel="stylesheet" href="/__nav/shared-nav.css">' +
    '<link rel="stylesheet" href="/__nav/inject.css">';
const BODY_INJECT = '<script src="/__nav/shared-nav.js"></script>';
const MARKER = '/__nav/shared-nav.js'; // idempotency guard

function serveAsset(req, res) {
    const a = ASSET_MAP[req.url.split('?')[0]];
    if (!a) return false;
    fs.readFile(path.join(ASSETS, a.file), function (err, buf) {
        if (err) { res.writeHead(404, { 'Content-Type': 'text/plain' }); res.end('nav asset not found'); return; }
        res.writeHead(200, { 'Content-Type': a.type, 'Cache-Control': 'no-store' });
        res.end(buf);
    });
    return true;
}

// Only the TOP-LEVEL page gets the nav. code-server also serves webview/iframe
// documents that carry their own strict `default-src 'none'` CSP — injecting
// there is blocked by the browser and spams the console, so skip them.
// Sec-Fetch-Dest is 'document' for a top-level navigation and 'iframe' for a
// framed one; when the header is absent (non-browser client) fall back to a
// path check for code-server's webview routes.
function isTopLevelDocument(req) {
    const dest = req.headers['sec-fetch-dest'];
    if (dest) return dest === 'document';
    return req.url.indexOf('/webview') === -1 && req.url.indexOf('/vscode-resource') === -1;
}

function injectHtml(html) {
    if (html.indexOf(MARKER) !== -1) return html; // already injected
    if (html.indexOf('</head>') !== -1) html = html.replace('</head>', HEAD_INJECT + '</head>');
    else html = HEAD_INJECT + html;
    if (html.indexOf('</body>') !== -1) html = html.replace('</body>', BODY_INJECT + '</body>');
    else html = html + BODY_INJECT;
    return html;
}

const server = http.createServer(function (cReq, cRes) {
    if (cReq.url.indexOf('/__nav/') === 0) { serveAsset(cReq, cRes); return; }

    // Force uncompressed upstream so the HTML is injectable.
    const headers = Object.assign({}, cReq.headers);
    headers['accept-encoding'] = 'identity';

    const pReq = http.request(
        { host: TARGET_HOST, port: TARGET, method: cReq.method, path: cReq.url, headers: headers },
        function (pRes) {
            const ct = pRes.headers['content-type'] || '';
            const enc = pRes.headers['content-encoding'];
            const isHtml = ct.indexOf('text/html') !== -1;

            // Only rewrite uncompressed top-level HTML; everything else streams as-is.
            if (!isHtml || enc || cReq.method === 'HEAD' || !isTopLevelDocument(cReq)) {
                cRes.writeHead(pRes.statusCode, pRes.headers);
                pRes.pipe(cRes);
                return;
            }

            const chunks = [];
            pRes.on('data', function (d) { chunks.push(d); });
            pRes.on('end', function () {
                const out = Buffer.from(injectHtml(Buffer.concat(chunks).toString('utf8')), 'utf8');
                const h = Object.assign({}, pRes.headers);
                delete h['content-length'];
                delete h['content-encoding'];
                delete h['transfer-encoding'];
                h['content-length'] = String(out.length);
                h['cache-control'] = 'no-store';
                cRes.writeHead(pRes.statusCode, h);
                cRes.end(out);
            });
        }
    );
    pReq.on('error', function (e) {
        cRes.writeHead(502, { 'Content-Type': 'text/plain' });
        cRes.end('nav-proxy upstream error: ' + e.message);
    });
    cReq.pipe(pReq);
});

// --- WebSocket / protocol upgrade passthrough (ttyd /ws, code-server) ---------
// Headers (Host, Origin) are forwarded UNCHANGED so code-server's DNS-rebinding
// check still sees the public origin the browser used.
server.on('upgrade', function (req, socket, head) {
    const up = net.connect(TARGET, TARGET_HOST, function () {
        let raw = req.method + ' ' + req.url + ' HTTP/1.1\r\n';
        for (let i = 0; i < req.rawHeaders.length; i += 2) {
            raw += req.rawHeaders[i] + ': ' + req.rawHeaders[i + 1] + '\r\n';
        }
        raw += '\r\n';
        up.write(raw);
        if (head && head.length) up.write(head);
        up.pipe(socket);
        socket.pipe(up);
    });
    up.on('error', function () { socket.destroy(); });
    socket.on('error', function () { up.destroy(); });
});

server.listen(PORT, '0.0.0.0', function () {
    console.log('nav-proxy [' + APP + '] :' + PORT + ' -> ' + TARGET_HOST + ':' + TARGET);
});
