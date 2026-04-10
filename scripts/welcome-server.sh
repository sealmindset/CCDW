#!/usr/bin/env bash
# =============================================================================
# Claude Code Docker - Welcome Page Server
# Serves the landing page on port 3000 with a simple status API.
# Uses Node.js (already in the container) for minimal overhead.
# =============================================================================

WELCOME_DIR="/opt/claude-code-docker/welcome"
PORT="${WELCOME_PORT:-3000}"

exec node -e "
const http = require('http');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const welcomeDir = '${WELCOME_DIR}';
const port = ${PORT};

const mimeTypes = {
    '.html': 'text/html',
    '.css': 'text/css',
    '.js': 'application/javascript',
    '.png': 'image/png',
    '.svg': 'image/svg+xml',
    '.ico': 'image/x-icon'
};

function getStatus() {
    const status = { docker: 'unavailable', ai_provider: 'none', ai_status: 'unknown' };

    // Docker check
    try {
        execSync('docker info', { stdio: 'ignore', timeout: 5000 });
        status.docker = 'ok';
    } catch (e) {
        status.docker = 'unavailable';
    }

    // AI provider check
    const foundryUrl = process.env.ANTHROPIC_FOUNDRY_BASE_URL;
    const apiKey = process.env.ANTHROPIC_API_KEY;
    const bedrock = process.env.CLAUDE_CODE_USE_BEDROCK;

    if (apiKey) {
        status.ai_provider = 'Anthropic API';
        status.ai_status = 'ok';
    } else if (foundryUrl) {
        status.ai_provider = 'Azure AI Foundry';
        try {
            execSync('az account show', { stdio: 'ignore', timeout: 10000 });
            status.ai_status = 'ok';
        } catch (e) {
            status.ai_status = 'Token expired';
        }
    } else if (bedrock === '1') {
        status.ai_provider = 'AWS Bedrock';
        status.ai_status = process.env.AWS_ACCESS_KEY_ID ? 'ok' : 'No credentials';
    }

    return status;
}

const server = http.createServer((req, res) => {
    if (req.url === '/api/status') {
        res.writeHead(200, {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        });
        res.end(JSON.stringify(getStatus()));
        return;
    }

    // Serve static files
    let filePath = req.url === '/' ? '/index.html' : req.url;
    filePath = path.join(welcomeDir, filePath);

    const ext = path.extname(filePath);
    const contentType = mimeTypes[ext] || 'text/plain';

    try {
        const content = fs.readFileSync(filePath);
        res.writeHead(200, { 'Content-Type': contentType });
        res.end(content);
    } catch (e) {
        // Fall back to index.html for any unknown path
        try {
            const content = fs.readFileSync(path.join(welcomeDir, 'index.html'));
            res.writeHead(200, { 'Content-Type': 'text/html' });
            res.end(content);
        } catch (e2) {
            res.writeHead(404);
            res.end('Not found');
        }
    }
});

server.listen(port, '0.0.0.0', () => {
    // Silence -- logged by entrypoint
});
"
