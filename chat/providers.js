const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execSync } = require('child_process');

const HOME = process.env.HOME || '/home/coder';
const SETTINGS_PATH = path.join(HOME, '.claude', 'settings.json');
const TOKEN_SCRIPT = path.join(HOME, '.claude', 'get-claude-token.sh');

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

function env(key) {
  const se = readSettingsEnv();
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
    const out = execSync(`aws configure export-credentials --profile ${profile} --format json`, { timeout: 15000 }).toString();
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

  const canonicalRequest = [
    method,
    parsedUrl.pathname,
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

function getModels() {
  const provider = detectProvider();
  if (provider === 'anthropic') {
    return [
      { id: 'claude-opus-4-20250514', label: 'Claude Opus 4', tier: 'heavy' },
      { id: 'claude-sonnet-4-6-20250514', label: 'Claude Sonnet 4.6', tier: 'standard' },
      { id: 'claude-haiku-4-5-20251001', label: 'Claude Haiku 4.5', tier: 'light' },
    ];
  }
  if (provider === 'azure-foundry') {
    const opus = env('ANTHROPIC_DEFAULT_OPUS_MODEL') || 'claude-opus-4-6';
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
    const endpoint = `https://bedrock-runtime.${region}.amazonaws.com/model/${encodeURIComponent(modelId)}/${action}`;

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

module.exports = { detectProvider, getModels, getDefaultModel, buildRequest, getProviderInfo, parseEventStreamMessage, extractBedrockEvent };
