const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execSync } = require('child_process');

const HOME = process.env.HOME || '/home/coder';
const SETTINGS_PATH = path.join(HOME, '.claude', 'settings.json');
const TOKEN_SCRIPT = path.join(HOME, '.claude', 'get-claude-token.sh');
const MODELS_CACHE_PATH = process.env.CCDW_MODELS_CACHE
  || path.join(HOME, '.claude', 'models-cache.json');

let cachedToken = null;
let tokenExpiresAt = 0;
let cachedAwsCreds = null;
let awsCredsExpiresAt = 0;

function readSettingsEnv() {
  try {
    const s = JSON.parse(fs.readFileSync(SETTINGS_PATH, 'utf-8'));
    return s.env || {};
  } catch { return {}; }
}

// settings.json is regenerated at container start from live model discovery, so
// for the model slots it is more current than process.env -- the .env written by
// the installer can still name a deployment that has since been retired.
// Everything else (endpoints, auth) keeps env-first precedence.
const SETTINGS_AUTHORITATIVE = new Set([
  'ANTHROPIC_DEFAULT_OPUS_MODEL',
  'ANTHROPIC_DEFAULT_SONNET_MODEL',
  'ANTHROPIC_DEFAULT_HAIKU_MODEL',
]);

function env(key) {
  const se = readSettingsEnv();
  if (SETTINGS_AUTHORITATIVE.has(key) && se[key]) return se[key];
  return process.env[key] || se[key] || '';
}

function detectProvider() {
  if (env('ANTHROPIC_API_KEY')) return 'anthropic';
  if (env('ANTHROPIC_FOUNDRY_BASE_URL') || env('CLAUDE_CODE_USE_FOUNDRY') === '1') return 'azure-foundry';
  if (env('CLAUDE_CODE_USE_BEDROCK') === '1') return 'bedrock';
  if (env('CLAUDE_CODE_PROVIDER') === 'claude') return 'claude';
  return null;
}

function getAzureToken() {
  if (cachedToken && Date.now() < tokenExpiresAt) return cachedToken;
  try {
    if (fs.existsSync(TOKEN_SCRIPT)) {
      const t = execSync(`bash "${TOKEN_SCRIPT}"`, { timeout: 15000 }).toString().trim();
      if (t && !t.startsWith('ERROR')) {
        cachedToken = t;
        tokenExpiresAt = Date.now() + 50 * 60 * 1000;
        return t;
      }
    }
    const t = execSync('az account get-access-token --resource https://cognitiveservices.azure.com --query accessToken -o tsv', { timeout: 15000 }).toString().trim();
    cachedToken = t;
    tokenExpiresAt = Date.now() + 50 * 60 * 1000;
    return t;
  } catch (e) {
    throw new Error('Azure token expired. Run "az login --use-device-code" in the terminal.');
  }
}

function getAwsCredentials() {
  if (cachedAwsCreds && Date.now() < awsCredsExpiresAt) return cachedAwsCreds;
  const profile = env('AWS_PROFILE') || 'sso-bedrock-model-access';
  try {
    const out = execSync(`aws configure export-credentials --profile ${profile}`, { timeout: 15000 }).toString();
    const creds = JSON.parse(out);
    cachedAwsCreds = {
      accessKeyId: creds.AccessKeyId,
      secretAccessKey: creds.SecretAccessKey,
      sessionToken: creds.SessionToken || undefined,
    };
    awsCredsExpiresAt = Date.now() + 10 * 60 * 1000;
    return cachedAwsCreds;
  } catch {
    throw new Error('AWS session expired. Run "login" in the terminal.');
  }
}

function signAwsV4(method, urlStr, headers, body, region, service, credentials) {
  const now = new Date();
  const amzDate = now.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
  const dateStamp = amzDate.slice(0, 8);
  const parsedUrl = new URL(urlStr);

  headers['host'] = parsedUrl.host;
  headers['x-amz-date'] = amzDate;
  if (credentials.sessionToken) {
    headers['x-amz-security-token'] = credentials.sessionToken;
  }
  const payloadHash = crypto.createHash('sha256').update(body || '').digest('hex');

  const signedHeaderKeys = Object.keys(headers).map(k => k.toLowerCase()).sort();
  const signedHeaders = signedHeaderKeys.join(';');
  const canonicalHeaders = signedHeaderKeys.map(k => {
    const origKey = Object.keys(headers).find(h => h.toLowerCase() === k);
    return `${k}:${headers[origKey].toString().trim()}`;
  }).join('\n') + '\n';

  // URI-encode each path segment per AWS SigV4 spec
  const canonicalUri = parsedUrl.pathname.split('/').map(s => encodeURIComponent(s)).join('/');

  const canonicalRequest = [
    method,
    canonicalUri,
    '',
    canonicalHeaders,
    signedHeaders,
    payloadHash,
  ].join('\n');

  const scope = `${dateStamp}/${region}/${service}/aws4_request`;
  const stringToSign = [
    'AWS4-HMAC-SHA256',
    amzDate,
    scope,
    crypto.createHash('sha256').update(canonicalRequest).digest('hex'),
  ].join('\n');

  function hmac(key, data) { return crypto.createHmac('sha256', key).update(data).digest(); }
  const kSigning = hmac(hmac(hmac(hmac(`AWS4${credentials.secretAccessKey}`, dateStamp), region), service), 'aws4_request');
  const signature = crypto.createHmac('sha256', kSigning).update(stringToSign).digest('hex');

  headers['authorization'] = `AWS4-HMAC-SHA256 Credential=${credentials.accessKeyId}/${scope}, SignedHeaders=${signedHeaders}, Signature=${signature}`;
}

// scripts/discover-models.py asks each provider what it actually has at
// container start. When it succeeded, that list is both longer and more current
// than the three env slots -- Claude Code takes an arbitrary id via --model, so
// Chat is not limited to the slots the way the environment variables are.
function discoveredModels(provider) {
  try {
    const cache = JSON.parse(fs.readFileSync(MODELS_CACHE_PATH, 'utf-8'));
    const entry = cache.providers?.[provider === 'anthropic' ? 'api-key' : provider];
    if (!entry || entry.source === 'fallback') return null;
    const slots = entry.slots || {};
    const tierOf = (id) => {
      if (id === slots.haiku) return 'light';
      if (id === slots.sonnet) return 'standard';
      return 'heavy';
    };
    const models = (entry.models || [])
      .filter(m => m.id)
      .map(m => ({ id: m.id, label: m.display_name || m.id, tier: tierOf(m.id) }));
    return models.length ? models : null;
  } catch { return null; }
}

function getModels() {
  const provider = detectProvider();
  const discovered = discoveredModels(provider);
  if (discovered) return discovered;
  if (provider === 'anthropic') {
    return [
      { id: 'claude-opus-4-20250514', label: 'Claude Opus 4', tier: 'heavy' },
      { id: 'claude-sonnet-4-6-20250514', label: 'Claude Sonnet 4.6', tier: 'standard' },
      { id: 'claude-haiku-4-5-20251001', label: 'Claude Haiku 4.5', tier: 'light' },
    ];
  }
  if (provider === 'azure-foundry') {
    const opus = env('ANTHROPIC_DEFAULT_OPUS_MODEL') || 'claude-opus-5';
    const sonnet = env('ANTHROPIC_DEFAULT_SONNET_MODEL') || 'claude-sonnet-4-6';
    const haiku = env('ANTHROPIC_DEFAULT_HAIKU_MODEL') || 'claude-haiku-4-5';
    return [
      { id: opus, label: 'Claude Opus', tier: 'heavy' },
      { id: sonnet, label: 'Claude Sonnet', tier: 'standard' },
      { id: haiku, label: 'Claude Haiku', tier: 'light' },
    ];
  }
  if (provider === 'bedrock') {
    const opus = env('ANTHROPIC_DEFAULT_OPUS_MODEL') || 'us.anthropic.claude-opus-4-6-v1';
    const sonnet = env('ANTHROPIC_DEFAULT_SONNET_MODEL') || 'us.anthropic.claude-sonnet-4-6';
    const haiku = env('ANTHROPIC_DEFAULT_HAIKU_MODEL') || 'us.anthropic.claude-haiku-4-5-20251001-v1:0';
    return [
      { id: opus, label: 'Claude Opus', tier: 'heavy' },
      { id: sonnet, label: 'Claude Sonnet', tier: 'standard' },
      { id: haiku, label: 'Claude Haiku', tier: 'light' },
    ];
  }
  return [];
}

function getDefaultModel() {
  // Prefer the slot the provider config nominates (default_model: opus) over
  // "whatever sorted first", so the default follows configuration, not version
  // arithmetic that happens to tie.
  try {
    const provider = detectProvider();
    const cache = JSON.parse(fs.readFileSync(MODELS_CACHE_PATH, 'utf-8'));
    const entry = cache.providers?.[provider === 'anthropic' ? 'api-key' : provider];
    const preferred = entry?.slots?.[entry?.default_model];
    if (preferred) return preferred;
  } catch { /* fall through to the ordered list */ }
  const models = getModels();
  return models.length > 0 ? models[0].id : null;
}

function buildRequest(body) {
  const provider = detectProvider();
  if (!provider) throw new Error('No AI provider configured');

  if (provider === 'claude') {
    throw new Error('Workshop Chat is not available with Claude Account login. Use Claude Code in the terminal.');
  }

  if (provider === 'bedrock') {
    const region = env('AWS_REGION') || 'us-east-1';
    const modelId = body.model;
    const isStream = !!body.stream;
    const action = isStream ? 'invoke-with-response-stream' : 'invoke';
    const endpoint = `https://bedrock-runtime.${region}.amazonaws.com/model/${modelId}/${action}`;

    const bedrockBody = { ...body };
    delete bedrockBody.model;
    delete bedrockBody.stream;
    bedrockBody.anthropic_version = 'bedrock-2023-05-31';
    const jsonBody = JSON.stringify(bedrockBody);

    const headers = {
      'content-type': 'application/json',
      'accept': isStream ? 'application/vnd.amazon.eventstream' : 'application/json',
      'content-length': Buffer.byteLength(jsonBody).toString(),
    };

    const creds = getAwsCredentials();
    signAwsV4('POST', endpoint, headers, jsonBody, region, 'bedrock', creds);

    const url = new URL(endpoint);
    return {
      hostname: url.hostname,
      port: 443,
      path: url.pathname,
      method: 'POST',
      headers,
      protocol: 'https:',
      body: jsonBody,
      bedrockStream: isStream,
    };
  }

  const headers = {
    'content-type': 'application/json',
    'anthropic-version': '2023-06-01',
  };

  let baseUrl;

  if (provider === 'anthropic') {
    headers['x-api-key'] = env('ANTHROPIC_API_KEY');
    baseUrl = 'https://api.anthropic.com';
  } else if (provider === 'azure-foundry') {
    baseUrl = env('ANTHROPIC_FOUNDRY_BASE_URL');
    if (!baseUrl) throw new Error('ANTHROPIC_FOUNDRY_BASE_URL not set');
    const apiKey = env('ANTHROPIC_FOUNDRY_API_KEY');
    if (apiKey) {
      headers['x-api-key'] = apiKey;
    } else {
      headers['Authorization'] = `Bearer ${getAzureToken()}`;
    }
  }

  const fullUrl = baseUrl.replace(/\/+$/, '') + '/v1/messages';
  const url = new URL(fullUrl);
  const jsonBody = JSON.stringify(body);
  headers['content-length'] = Buffer.byteLength(jsonBody).toString();

  return {
    hostname: url.hostname,
    port: url.port || (url.protocol === 'https:' ? 443 : 80),
    path: url.pathname,
    method: 'POST',
    headers,
    protocol: url.protocol,
    body: jsonBody,
    bedrockStream: false,
  };
}

// Parse one message from an AWS binary event stream buffer.
// Returns { headers, payload, totalLen } or null if buffer is incomplete.
function parseEventStreamMessage(buffer, offset) {
  if (buffer.length - offset < 16) return null;
  const totalLen = buffer.readUInt32BE(offset);
  if (totalLen < 16 || buffer.length - offset < totalLen) return null;
  const headersLen = buffer.readUInt32BE(offset + 4);
  const headersStart = offset + 12;
  const payloadOffset = headersStart + headersLen;
  const payloadLen = totalLen - headersLen - 16;

  const headers = {};
  let pos = headersStart;
  const headersEnd = headersStart + headersLen;
  while (pos < headersEnd) {
    const nameLen = buffer.readUInt8(pos); pos++;
    const name = buffer.toString('utf8', pos, pos + nameLen); pos += nameLen;
    const type = buffer.readUInt8(pos); pos++;
    if (type === 7) {
      const valLen = buffer.readUInt16BE(pos); pos += 2;
      headers[name] = buffer.toString('utf8', pos, pos + valLen); pos += valLen;
    } else if (type === 6) {
      const valLen = buffer.readUInt16BE(pos); pos += 2;
      pos += valLen;
    } else if (type === 0 || type === 1) {
      headers[name] = type === 0;
    } else if (type === 2) { pos++; }
    else if (type === 3) { pos += 2; }
    else if (type === 4) { pos += 4; }
    else if (type === 5 || type === 8) { pos += 8; }
    else if (type === 9) { pos += 16; }
    else { break; }
  }

  const payload = buffer.slice(payloadOffset, payloadOffset + payloadLen);
  return { headers, payload, totalLen };
}

// Extract an Anthropic streaming event from a Bedrock event stream payload
function extractBedrockEvent(payload) {
  try {
    const event = JSON.parse(payload.toString());
    if (event.bytes) {
      return JSON.parse(Buffer.from(event.bytes, 'base64').toString());
    }
    if (event.chunk && event.chunk.bytes) {
      return JSON.parse(Buffer.from(event.chunk.bytes, 'base64').toString());
    }
  } catch {}
  return null;
}

function getProviderInfo() {
  const provider = detectProvider();
  return {
    provider,
    name: provider === 'anthropic' ? 'Anthropic API'
        : provider === 'azure-foundry' ? 'Azure AI Foundry'
        : provider === 'bedrock' ? 'AWS Bedrock'
        : provider === 'claude' ? 'Claude Account'
        : 'Not configured',
    authenticated: !!provider,
    models: getModels(),
    defaultModel: getDefaultModel(),
  };
}

module.exports = { detectProvider, getModels, getDefaultModel, buildRequest, getProviderInfo, parseEventStreamMessage, extractBedrockEvent, readSettingsEnv };
