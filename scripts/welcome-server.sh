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

function getUsageStats() {
    const PRICING = {
        'claude-opus-4-6':   { input: 15, output: 75, cache_write: 18.75, cache_read: 1.50 },
        'claude-sonnet-4-6': { input: 3,  output: 15, cache_write: 3.75,  cache_read: 0.30 },
        'claude-haiku-4-5':  { input: 0.80, output: 4, cache_write: 1.00, cache_read: 0.08 }
    };
    try {
        const projectsDir = '/home/coder/.claude/projects';
        if (!fs.existsSync(projectsDir)) return { has_data: false };

        let inputTokens = 0, outputTokens = 0;
        let cacheCreateTokens = 0, cacheReadTokens = 0;
        let minTs = Infinity, maxTs = 0;
        let model = null;
        let sessionCount = 0;
        let cost = 0;

        const dirs = fs.readdirSync(projectsDir, { withFileTypes: true });
        for (const d of dirs) {
            if (!d.isDirectory()) continue;
            const dirPath = path.join(projectsDir, d.name);
            const files = fs.readdirSync(dirPath).filter(f => f.endsWith('.jsonl'));
            for (const f of files) {
                const lines = fs.readFileSync(path.join(dirPath, f), 'utf8').split('\\n');
                let hasAssistant = false;
                for (const line of lines) {
                    if (!line.includes('\"assistant\"')) continue;
                    try {
                        const rec = JSON.parse(line);
                        if (rec.type !== 'assistant' || !rec.message || !rec.message.usage) continue;
                        hasAssistant = true;
                        const u = rec.message.usage;
                        const m = rec.message.model || 'claude-opus-4-6';
                        model = m;
                        inputTokens += (u.input_tokens || 0);
                        outputTokens += (u.output_tokens || 0);
                        cacheCreateTokens += (u.cache_creation_input_tokens || 0);
                        cacheReadTokens += (u.cache_read_input_tokens || 0);
                        const p = PRICING[m] || PRICING['claude-opus-4-6'];
                        cost += (u.input_tokens || 0) * p.input / 1e6;
                        cost += (u.output_tokens || 0) * p.output / 1e6;
                        cost += (u.cache_creation_input_tokens || 0) * p.cache_write / 1e6;
                        cost += (u.cache_read_input_tokens || 0) * p.cache_read / 1e6;
                        if (rec.timestamp) {
                            if (rec.timestamp < minTs) minTs = rec.timestamp;
                            if (rec.timestamp > maxTs) maxTs = rec.timestamp;
                        }
                    } catch (e) {}
                }
                if (hasAssistant) sessionCount++;
            }
        }

        if (sessionCount === 0) return { has_data: false };

        return {
            has_data: true,
            total_tokens: inputTokens + outputTokens + cacheCreateTokens + cacheReadTokens,
            input_tokens: inputTokens,
            output_tokens: outputTokens,
            cache_creation_tokens: cacheCreateTokens,
            cache_read_tokens: cacheReadTokens,
            model: model,
            session_count: sessionCount,
            duration_ms: maxTs > minTs ? maxTs - minTs : 0,
            estimated_cost: Math.round(cost * 100) / 100
        };
    } catch (e) {
        return { has_data: false };
    }
}

function getHealth() {
    const stateFile = '/tmp/.health-state.json';
    const telemetryFile = '/home/coder/.claude/health-telemetry.jsonl';

    // Read shared state from health monitor
    let state = {
        status: 'unknown',
        failure_type: '',
        message: 'Health monitor not yet started',
        last_check: '',
        recent_failures_1h: 0,
        services: {}
    };

    try {
        const raw = fs.readFileSync(stateFile, 'utf8');
        state = JSON.parse(raw);
    } catch (e) {
        // State file doesn't exist yet -- health monitor hasn't run
    }

    // Supplement with live auth info
    const auth = { provider: 'none', method: 'none', endpoint_reachable: false };
    const foundryUrl = process.env.ANTHROPIC_FOUNDRY_BASE_URL;
    const foundryKey = process.env.ANTHROPIC_FOUNDRY_API_KEY;
    const apiKey = process.env.ANTHROPIC_API_KEY;
    const bedrock = process.env.CLAUDE_CODE_USE_BEDROCK;

    if (foundryUrl) {
        auth.provider = 'Azure AI Foundry';
        auth.method = foundryKey ? 'api_key' : 'azure_cli_token';
        auth.endpoint_reachable = state.failure_type !== 'vpn_down' && state.failure_type !== 'endpoint_unreachable';
    } else if (apiKey) {
        auth.provider = 'Anthropic API';
        auth.method = 'api_key';
        auth.endpoint_reachable = state.failure_type !== 'endpoint_unreachable';
    } else if (bedrock === '1') {
        auth.provider = 'AWS Bedrock';
        auth.method = process.env.AWS_ACCESS_KEY_ID ? 'access_key' : 'none';
    }

    // System info
    let diskFreeMb = 0;
    try {
        const dfOut = execSync('df -k /home/coder 2>/dev/null | tail -1', { timeout: 5000 }).toString();
        const parts = dfOut.trim().split(/\\s+/);
        if (parts.length >= 4) diskFreeMb = Math.round(parseInt(parts[3]) / 1024);
    } catch (e) {}

    let dockerSocket = false;
    try {
        fs.accessSync('/var/run/docker.sock');
        dockerSocket = true;
    } catch (e) {}

    // Last 5 telemetry events
    let last5 = [];
    try {
        const lines = fs.readFileSync(telemetryFile, 'utf8').trim().split('\\n');
        last5 = lines.slice(-5).map(l => { try { return JSON.parse(l); } catch(e) { return null; } }).filter(Boolean);
    } catch (e) {}

    return {
        status: state.status,
        message: state.message,
        failure_type: state.failure_type,
        last_check: state.last_check,
        recent_failures_1h: state.recent_failures_1h,
        services: state.services,
        auth: auth,
        system: { disk_free_mb: diskFreeMb, docker_socket: dockerSocket },
        telemetry: { last_5_events: last5 }
    };
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

    if (req.url === '/api/health') {
        res.writeHead(200, {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        });
        res.end(JSON.stringify(getHealth()));
        return;
    }

    if (req.url === '/api/usage') {
        res.writeHead(200, {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        });
        res.end(JSON.stringify(getUsageStats()));
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
