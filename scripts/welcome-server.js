// =============================================================================
// Claude Code Docker - Welcome Page Server
// Serves the landing page on port 3000 with a simple status API.
// =============================================================================

const http = require('http');
const fs = require('fs');
const path = require('path');
const { execSync, spawn } = require('child_process');

const welcomeDir = process.env.WELCOME_DIR || '/opt/claude-code-docker/welcome';
const port = parseInt(process.env.WELCOME_PORT, 10) || 3000;
const pendingAuthFile = '/tmp/.pending-auth.json';

const mimeTypes = {
    '.html': 'text/html',
    '.css': 'text/css',
    '.js': 'application/javascript',
    '.png': 'image/png',
    '.svg': 'image/svg+xml',
    '.ico': 'image/x-icon'
};

function getStatus() {
    const status = { docker: 'unavailable', ai_provider: 'none', ai_status: 'unknown', token_minutes_remaining: null, github: 'unauthenticated' };

    try {
        execSync('docker info', { stdio: 'ignore', timeout: 5000 });
        status.docker = 'ok';
    } catch (e) {
        status.docker = 'unavailable';
    }

    const foundryUrl = process.env.ANTHROPIC_FOUNDRY_BASE_URL;
    const apiKey = process.env.ANTHROPIC_API_KEY;
    const foundryKey = process.env.ANTHROPIC_FOUNDRY_API_KEY;
    const bedrock = process.env.CLAUDE_CODE_USE_BEDROCK;

    if (apiKey) {
        status.ai_provider = 'Anthropic API';
        status.ai_status = 'ok';
    } else if (foundryKey) {
        status.ai_provider = 'Azure AI Foundry';
        status.ai_status = 'ok';
    } else if (foundryUrl) {
        status.ai_provider = 'Azure AI Foundry';
        try {
            execSync('az account show', { stdio: 'ignore', timeout: 10000 });
            status.ai_status = 'ok';
            try {
                const tokenJson = execSync('az account get-access-token --resource https://cognitiveservices.azure.com 2>/dev/null', { timeout: 10000 }).toString();
                const match = tokenJson.match(/"expiresOn"\s*:\s*"([^"]+)"/);
                if (match) {
                    const expiry = new Date(match[1]).getTime();
                    const remaining = Math.floor((expiry - Date.now()) / 60000);
                    status.token_minutes_remaining = remaining;
                    if (remaining <= 0) status.ai_status = 'Token expired';
                }
            } catch (e) {}
        } catch (e) {
            status.ai_status = 'Token expired';
        }
    } else if (bedrock === '1') {
        status.ai_provider = 'AWS Bedrock';
        const prof = process.env.AWS_PROFILE || 'sso-bedrock-model-access';
        try {
            execSync('aws sts get-caller-identity --profile ' + prof, { stdio: 'ignore', timeout: 10000 });
            status.ai_status = 'ok';
        } catch (e) {
            status.ai_status = 'Session expired';
        }
    } else if (process.env.CLAUDE_CODE_PROVIDER === 'claude') {
        status.ai_provider = 'Claude Account';
        try {
            const authOut = execSync('claude auth status 2>/dev/null', { timeout: 10000 }).toString();
            status.ai_status = authOut.includes('"loggedIn": true') ? 'ok' : 'Not logged in';
        } catch (e) {
            status.ai_status = 'Not logged in';
        }
    }

    try {
        execSync('gh auth status', { stdio: 'ignore', timeout: 10000 });
        status.github = 'ok';
        try {
            status.github_user = execSync('gh api user -q .login 2>/dev/null', { timeout: 10000 }).toString().trim();
        } catch (e) {}
    } catch (e) {
        status.github = 'unauthenticated';
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
                const lines = fs.readFileSync(path.join(dirPath, f), 'utf8').split('\n');
                let hasAssistant = false;
                for (const line of lines) {
                    if (!line.includes('"assistant"')) continue;
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

        // Raw cost: what it would cost without prompt caching
        // All cache_read tokens would have been full-price input tokens
        // All cache_create tokens would have been full-price input tokens (no 1.25x write premium)
        let rawCost = 0;
        // Re-walk to compute per-model raw cost (cache tokens priced at full input rate)
        // Simpler: use totals with a representative model
        const p = PRICING[model] || PRICING['claude-opus-4-6'];
        rawCost += inputTokens * p.input / 1e6;
        rawCost += outputTokens * p.output / 1e6;
        rawCost += cacheCreateTokens * p.input / 1e6;  // full input price, not cache_write
        rawCost += cacheReadTokens * p.input / 1e6;     // full input price, not cache_read

        const rawTokens = inputTokens + outputTokens + cacheCreateTokens + cacheReadTokens;
        const actualCost = Math.round(cost * 100) / 100;
        const savings = Math.round((rawCost - cost) * 100) / 100;
        const savingsPct = rawCost > 0 ? Math.round((1 - cost / rawCost) * 100) : 0;
        const tokensSaved = cacheReadTokens; // tokens served from cache instead of re-sent

        return {
            has_data: true,
            total_tokens: rawTokens,
            input_tokens: inputTokens,
            output_tokens: outputTokens,
            cache_creation_tokens: cacheCreateTokens,
            cache_read_tokens: cacheReadTokens,
            model: model,
            session_count: sessionCount,
            duration_ms: maxTs > minTs ? maxTs - minTs : 0,
            estimated_cost: actualCost,
            raw_cost: Math.round(rawCost * 100) / 100,
            savings: savings,
            savings_pct: savingsPct,
            tokens_saved: tokensSaved
        };
    } catch (e) {
        return { has_data: false };
    }
}

function getHealth() {
    const stateFile = '/tmp/.health-state.json';
    const telemetryFile = '/home/coder/.claude/health-telemetry.jsonl';

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
    } catch (e) {}

    const auth = { provider: 'none', method: 'none', endpoint_reachable: false };
    const foundryUrl = process.env.ANTHROPIC_FOUNDRY_BASE_URL;
    const foundryKey = process.env.ANTHROPIC_FOUNDRY_API_KEY;
    const apiKey = process.env.ANTHROPIC_API_KEY;
    const bedrock = process.env.CLAUDE_CODE_USE_BEDROCK;

    if (apiKey) {
        auth.provider = 'Anthropic API';
        auth.method = 'api_key';
        auth.endpoint_reachable = state.failure_type !== 'endpoint_unreachable';
    } else if (foundryUrl) {
        auth.provider = 'Azure AI Foundry';
        auth.method = foundryKey ? 'api_key' : 'azure_cli_token';
        auth.endpoint_reachable = state.failure_type !== 'vpn_down' && state.failure_type !== 'endpoint_unreachable';
    } else if (bedrock === '1') {
        auth.provider = 'AWS Bedrock';
        auth.method = process.env.AWS_ACCESS_KEY_ID ? 'access_key' : 'sso';
    } else if (process.env.CLAUDE_CODE_PROVIDER === 'claude') {
        auth.provider = 'Claude Account';
        auth.method = 'oauth';
        auth.endpoint_reachable = state.failure_type !== 'endpoint_unreachable';
    }

    let diskFreeMb = 0;
    try {
        const dfOut = execSync('df -k /home/coder 2>/dev/null | tail -1', { timeout: 5000 }).toString();
        const parts = dfOut.trim().split(/\s+/);
        if (parts.length >= 4) diskFreeMb = Math.round(parseInt(parts[3]) / 1024);
    } catch (e) {}

    let dockerSocket = false;
    try {
        fs.accessSync('/var/run/docker.sock');
        dockerSocket = true;
    } catch (e) {}

    let last5 = [];
    try {
        const lines = fs.readFileSync(telemetryFile, 'utf8').trim().split('\n');
        last5 = lines.slice(-5).map(l => { try { return JSON.parse(l); } catch(e) { return null; } }).filter(Boolean);
    } catch (e) {}

    return {
        status: state.status,
        message: state.message,
        failure_type: state.failure_type,
        ssl_proxy: state.failure_type === 'ssl_proxy',
        last_check: state.last_check,
        recent_failures_1h: state.recent_failures_1h,
        services: state.services,
        auth: auth,
        system: { disk_free_mb: diskFreeMb, docker_socket: dockerSocket },
        telemetry: { last_5_events: last5 }
    };
}

let pendingAuth = null;
let loginProcess = null;
let registeredApps = [];

// Restore pending auth from file (survives page reloads / server restarts)
try {
    if (fs.existsSync(pendingAuthFile)) {
        const saved = JSON.parse(fs.readFileSync(pendingAuthFile, 'utf8'));
        if (saved && saved.timestamp && Date.now() - saved.timestamp < 900000) {
            pendingAuth = saved;
        } else {
            fs.unlinkSync(pendingAuthFile);
        }
    }
} catch(e) {}

function savePendingAuth() {
    try {
        if (pendingAuth) {
            fs.writeFileSync(pendingAuthFile, JSON.stringify(pendingAuth));
        } else {
            if (fs.existsSync(pendingAuthFile)) fs.unlinkSync(pendingAuthFile);
        }
    } catch(e) {}
}


function getRunningApps() {
    const apps = [];
    try {
        const out = execSync(
            'docker ps --format "{{.Names}}\\t{{.Ports}}\\t{{.Status}}\\t{{.Image}}" --filter "status=running" 2>/dev/null',
            { timeout: 5000 }
        ).toString().trim();
        if (!out) return apps;
        for (const line of out.split('\n')) {
            const [name, ports, status, image] = line.split('\t');
            if (!name || name === 'claude-code') continue;
            const portMatches = (ports || '').match(/0\.0\.0\.0:(\d+)->(\d+)/g) || [];
            const exposedPorts = portMatches.map(m => {
                const match = m.match(/0\.0\.0\.0:(\d+)->(\d+)/);
                return match ? { host: parseInt(match[1]), container: parseInt(match[2]) } : null;
            }).filter(Boolean);
            if (exposedPorts.length === 0) continue;
            apps.push({ name, ports: exposedPorts, status: status || '', image: image || '' });
        }
    } catch (e) {}

    for (const reg of registeredApps) {
        if (!apps.find(a => a.name === reg.name)) {
            apps.push(reg);
        } else {
            const existing = apps.find(a => a.name === reg.name);
            if (reg.url) existing.url = reg.url;
            if (reg.label) existing.label = reg.label;
        }
    }
    return apps;
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

    if (req.url === '/api/apps') {
        res.writeHead(200, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' });
        res.end(JSON.stringify(getRunningApps()));
        return;
    }

    if (req.url === '/api/apps/open' && req.method === 'POST') {
        let body = '';
        req.on('data', c => body += c);
        req.on('end', () => {
            try {
                const app = JSON.parse(body);
                if (app.name) {
                    const existing = registeredApps.findIndex(a => a.name === app.name);
                    if (existing >= 0) registeredApps[existing] = { ...registeredApps[existing], ...app, timestamp: Date.now() };
                    else registeredApps.push({ ...app, timestamp: Date.now() });
                }
            } catch (e) {}
            res.writeHead(200, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' });
            res.end(JSON.stringify({ ok: true }));
        });
        return;
    }

    if (req.url === '/api/apps/close' && req.method === 'POST') {
        let body = '';
        req.on('data', c => body += c);
        req.on('end', () => {
            try {
                const { name } = JSON.parse(body);
                registeredApps = registeredApps.filter(a => a.name !== name);
            } catch (e) {}
            res.writeHead(200, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' });
            res.end(JSON.stringify({ ok: true }));
        });
        return;
    }

    if (req.url === '/auth/start' && req.method === 'POST') {
        let body = '';
        req.on('data', c => body += c);
        req.on('end', () => {
            try { pendingAuth = JSON.parse(body); pendingAuth.timestamp = Date.now(); savePendingAuth(); } catch(e) {}
            res.writeHead(200, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' });
            res.end(JSON.stringify({ok:true}));
        });
        return;
    }

    if (req.url === '/auth/pending') {
        res.writeHead(200, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' });
        // Re-read from file in case login-wizard wrote it directly
        try {
            if (fs.existsSync(pendingAuthFile)) {
                const saved = JSON.parse(fs.readFileSync(pendingAuthFile, 'utf8'));
                if (saved && saved.timestamp && Date.now() - saved.timestamp < 900000) {
                    pendingAuth = saved;
                }
            }
        } catch(e) {}
        if (pendingAuth && Date.now() - pendingAuth.timestamp > 900000) { pendingAuth = null; savePendingAuth(); }
        if (pendingAuth) {
            res.end(JSON.stringify({ pending: true, url: pendingAuth.url, code: pendingAuth.code || '', provider: pendingAuth.provider || '' }));
        } else {
            res.end(JSON.stringify({ pending: false }));
        }
        return;
    }

    if (req.url === '/auth/clear' && req.method === 'POST') {
        pendingAuth = null; savePendingAuth();
        res.writeHead(200, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' });
        res.end(JSON.stringify({ok:true}));
        return;
    }

    if (req.method === 'OPTIONS' && (req.url.startsWith('/auth/') || req.url.startsWith('/api/'))) {
        res.writeHead(204, { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'GET,POST,OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type' });
        res.end();
        return;
    }

    if (req.url === '/auth/login' && req.method === 'POST') {
        const h = { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' };
        const apiKey = process.env.ANTHROPIC_API_KEY;
        const foundryUrl = process.env.ANTHROPIC_FOUNDRY_BASE_URL;
        const useBedrock = process.env.CLAUDE_CODE_USE_BEDROCK;

        if (apiKey) { res.writeHead(200, h); res.end(JSON.stringify({ needed: false, provider: 'anthropic' })); return; }

        var provider = 'none', authCmd = '', authArgs = [];
        if (foundryUrl) {
            provider = 'azure';
            try { execSync('az account show', { stdio: 'ignore', timeout: 10000 }); res.writeHead(200, h); res.end(JSON.stringify({ needed: false, provider: 'azure' })); return; } catch(e) {}
            authCmd = 'az'; authArgs = ['login', '--use-device-code'];
        } else if (useBedrock === '1') {
            provider = 'bedrock';
            var prof = process.env.AWS_PROFILE || 'sso-bedrock-model-access';
            try { execSync('aws sts get-caller-identity --profile ' + prof, { stdio: 'ignore', timeout: 10000 }); res.writeHead(200, h); res.end(JSON.stringify({ needed: false, provider: 'bedrock' })); return; } catch(e) {}
            res.writeHead(200, h); res.end(JSON.stringify({ needed: true, provider: 'bedrock', status: 'use-terminal' })); return;
        } else if (process.env.CLAUDE_CODE_PROVIDER === 'claude') {
            provider = 'claude';
            try { var authOut = execSync('claude auth status 2>/dev/null', { timeout: 10000 }).toString(); if (authOut.includes('"loggedIn": true')) { res.writeHead(200, h); res.end(JSON.stringify({ needed: false, provider: 'claude' })); return; } } catch(e) {}
            res.writeHead(200, h); res.end(JSON.stringify({ needed: true, provider: 'claude', status: 'use-terminal' })); return;
        }

        if (provider === 'none') { res.writeHead(200, h); res.end(JSON.stringify({ needed: false, provider: 'none' })); return; }

        // If the terminal's login-wizard is already running, don't spawn a competing auth process
        try {
            execSync('pgrep -f "login-wizard.sh"', { stdio: 'ignore', timeout: 3000 });
            // Wizard is running -- tell the dashboard to use the terminal instead
            res.writeHead(200, h);
            res.end(JSON.stringify({ needed: true, provider: provider, status: 'use-terminal' }));
            return;
        } catch(e) {} // Not running, proceed

        if (loginProcess) { try { loginProcess.kill(); } catch(e) {} loginProcess = null; }

        loginProcess = spawn(authCmd, authArgs, { stdio: ['pipe', 'pipe', 'pipe'] });
        var output = '', codeFound = false, foundCode = '', foundUrl = '';

        var onData = function(d) {
            output += d.toString();
            if (codeFound) return;
            if (provider === 'azure') {
                var cm = output.match(/enter the code ([A-Z0-9]+) to/);
                var um = output.match(/open the page (https:\/\/[^ ]+)/);
                if (cm) { codeFound = true; foundCode = cm[1]; foundUrl = um ? um[1] : 'https://microsoft.com/devicelogin'; pendingAuth = { url: foundUrl, code: foundCode, provider: provider, timestamp: Date.now() }; savePendingAuth(); }
            } else {
                var um2 = output.match(/(https:\/\/[^ \n]+)/);
                var cm2 = output.match(/([A-Z]{4}-[A-Z]{4})/);
                if (um2) { codeFound = true; foundUrl = um2[1]; foundCode = cm2 ? cm2[1] : ''; pendingAuth = { url: foundUrl, code: foundCode, provider: provider, timestamp: Date.now() }; savePendingAuth(); }
            }
        };

        loginProcess.stdout.on('data', onData);
        loginProcess.stderr.on('data', onData);
        loginProcess.on('close', function(exitCode) {
            loginProcess = null;
            if (exitCode === 0) {
                try { execSync('/opt/claude-code-docker/scripts/configure-provider.sh', { timeout: 30000 }); } catch(e) {}
                pendingAuth = null; savePendingAuth();
            }
        });

        var waited = 0;
        var wi = setInterval(function() {
            waited += 250;
            if (codeFound || waited >= 8000) {
                clearInterval(wi);
                res.writeHead(200, h);
                res.end(JSON.stringify(codeFound ? { needed: true, provider: provider, code: foundCode, url: foundUrl } : { needed: true, provider: provider, status: 'waiting' }));
            }
        }, 250);
        return;
    }

    if (req.url === '/auth/github-login' && req.method === 'POST') {
        const h = { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' };
        try { execSync('gh auth status', { stdio: 'ignore', timeout: 10000 }); res.writeHead(200, h); res.end(JSON.stringify({ needed: false })); return; } catch(e) {}

        if (loginProcess) { try { loginProcess.kill(); } catch(e) {} loginProcess = null; }

        loginProcess = spawn('gh', ['auth', 'login', '-p', 'https', '-h', 'github.com', '-w', '--skip-ssh-key'], { stdio: ['pipe', 'pipe', 'pipe'] });
        var ghOutput = '', ghCodeFound = false, ghCode = '', ghUrl = '';

        var ghOnData = function(d) {
            ghOutput += d.toString();
            if (ghCodeFound) return;
            var um = ghOutput.match(/(https:\/\/[^\s]+)/);
            var cm = ghOutput.match(/([A-Z0-9]{4}-[A-Z0-9]{4})/);
            if (um) { ghCodeFound = true; ghUrl = um[1]; ghCode = cm ? cm[1] : ''; pendingAuth = { url: ghUrl, code: ghCode, provider: 'github', timestamp: Date.now() }; savePendingAuth(); }
        };
        loginProcess.stdout.on('data', ghOnData);
        loginProcess.stderr.on('data', ghOnData);
        loginProcess.on('close', function(exitCode) {
            loginProcess = null;
            if (exitCode === 0) {
                try { execSync('gh auth setup-git', { stdio: 'ignore', timeout: 10000 }); } catch(e) {}
                pendingAuth = null; savePendingAuth();
            }
        });

        var ghWaited = 0;
        var ghWi = setInterval(function() {
            ghWaited += 250;
            if (ghCodeFound || ghWaited >= 10000) {
                clearInterval(ghWi);
                res.writeHead(200, h);
                res.end(JSON.stringify(ghCodeFound ? { needed: true, code: ghCode, url: ghUrl } : { needed: true, status: 'waiting' }));
            }
        }, 250);
        return;
    }

    if (req.url === '/auth/github-auto' && req.method === 'POST') {
        // Auto GitHub sign-in: start the device flow, then drive the browser grant
        // headlessly with a pre-seeded GitHub session (gh-session-setup.command).
        const h = { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' };
        try { execSync('gh auth status', { stdio: 'ignore', timeout: 10000 }); res.writeHead(200, h); res.end(JSON.stringify({ needed: false })); return; } catch(e) {}

        const GH_STATE = '/home/coder/Documents/.ccdw/gh-session.json';
        if (!fs.existsSync(GH_STATE)) {
            res.writeHead(200, h);
            res.end(JSON.stringify({ needed: true, error: 'no_session', message: 'One-time setup: run gh-session-setup.command on your Mac to sign in to GitHub once.' }));
            return;
        }

        if (loginProcess) { try { loginProcess.kill(); } catch(e) {} loginProcess = null; }
        loginProcess = spawn('gh', ['auth', 'login', '-p', 'https', '-h', 'github.com', '-w', '--skip-ssh-key'], { stdio: ['pipe', 'pipe', 'pipe'] });
        var gaOut = '', gaFound = false, gaCode = '', gaUrl = '';
        var gaOnData = function(d) {
            gaOut += d.toString();
            if (gaFound) return;
            var um = gaOut.match(/(https:\/\/[^\s]+)/);
            var cm = gaOut.match(/([A-Z0-9]{4}-[A-Z0-9]{4})/);
            if (um && cm) {
                gaFound = true; gaUrl = um[1]; gaCode = cm[1];
                pendingAuth = { url: gaUrl, code: gaCode, provider: 'github', timestamp: Date.now() }; savePendingAuth();
                // Headless auto-authorize using the seeded session (detached).
                try {
                    var pw = spawn('node', ['/opt/claude-code-docker/scripts/gh-playwright-auth.mjs', gaCode, gaUrl, GH_STATE],
                        { cwd: '/opt/claude-code-docker', stdio: 'ignore', detached: true });
                    pw.unref();
                } catch(e) {}
            }
        };
        loginProcess.stdout.on('data', gaOnData);
        loginProcess.stderr.on('data', gaOnData);
        loginProcess.on('close', function(ec) {
            loginProcess = null;
            if (ec === 0) { try { execSync('gh auth setup-git', { stdio: 'ignore', timeout: 10000 }); } catch(e) {} pendingAuth = null; savePendingAuth(); }
        });

        var gaWaited = 0;
        var gaWi = setInterval(function() {
            gaWaited += 250;
            if (gaFound || gaWaited >= 12000) {
                clearInterval(gaWi);
                res.writeHead(200, h);
                res.end(JSON.stringify(gaFound ? { needed: true, automating: true, code: gaCode, url: gaUrl } : { needed: true, status: 'starting' }));
            }
        }, 250);
        return;
    }

    if (req.url === '/auth/check') {
        var ch = { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' };
        var authed = false, prov = 'none';
        if (process.env.ANTHROPIC_API_KEY) { authed = true; prov = 'anthropic'; }
        else if (process.env.ANTHROPIC_FOUNDRY_BASE_URL) {
            prov = 'azure';
            try { execSync('az account show', { stdio: 'ignore', timeout: 10000 }); authed = true; } catch(e) {}
        } else if (process.env.CLAUDE_CODE_USE_BEDROCK === '1') {
            prov = 'bedrock';
            var checkProf = process.env.AWS_PROFILE || 'sso-bedrock-model-access';
            try { execSync('aws sts get-caller-identity --profile ' + checkProf, { stdio: 'ignore', timeout: 10000 }); authed = true; } catch(e) {}
        } else if (process.env.CLAUDE_CODE_PROVIDER === 'claude') {
            prov = 'claude';
            try { var chkAuth = execSync('claude auth status 2>/dev/null', { timeout: 10000 }).toString(); if (chkAuth.includes('"loggedIn": true')) authed = true; } catch(e) {}
        }
        res.writeHead(200, ch);
        res.end(JSON.stringify({ authenticated: authed, provider: prov }));
        return;
    }

    if (req.url === '/api/startup-log') {
        res.writeHead(200, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' });
        try {
            const logPath = '/tmp/.startup-log';
            const lines = fs.existsSync(logPath) ? fs.readFileSync(logPath, 'utf8').trim().split('\n').filter(Boolean) : [];
            res.end(JSON.stringify({ lines }));
        } catch (e) {
            res.end(JSON.stringify({ lines: [] }));
        }
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

const startupLogPath = '/tmp/.startup-log';

function startupLog(msg) {
    try { fs.appendFileSync(startupLogPath, msg + '\n'); } catch (e) {}
}

server.listen(port, '0.0.0.0', () => {
    startupLog('ok|Welcome server|Listening on port ' + port);

    // Background GitHub auth: check status, try refresh, log result
    setImmediate(() => {
        try {
            execSync('gh auth status', { stdio: 'ignore', timeout: 10000 });
            let user = '';
            try { user = execSync('gh api user -q .login 2>/dev/null', { timeout: 10000 }).toString().trim(); } catch (e2) {}
            startupLog('ok|GitHub|' + (user || 'Authenticated'));
        } catch (e) {
            // Try silent refresh (works if refresh token is still valid in gh-config volume)
            try {
                execSync('gh auth refresh', { stdio: 'ignore', timeout: 15000 });
                execSync('gh auth setup-git', { stdio: 'ignore', timeout: 10000 });
                let user = '';
                try { user = execSync('gh api user -q .login 2>/dev/null', { timeout: 10000 }).toString().trim(); } catch (e2) {}
                startupLog('ok|GitHub|' + (user || 'Refreshed'));
            } catch (e2) {
                // Try GH_TOKEN env var as last resort before device code
                if (process.env.GH_TOKEN) {
                    try {
                        execSync('gh auth login --with-token', { input: process.env.GH_TOKEN + '\n', stdio: ['pipe', 'ignore', 'ignore'], timeout: 15000 });
                        execSync('gh auth setup-git', { stdio: 'ignore', timeout: 10000 });
                        startupLog('ok|GitHub|Authenticated via token');
                    } catch (e3) {
                        startupLog('info|GitHub|Sign in via terminal or dashboard');
                    }
                } else {
                    startupLog('info|GitHub|Sign in via terminal or dashboard');
                }
            }
        }
    });
});
