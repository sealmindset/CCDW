const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const HOME = process.env.HOME || '/home/coder';
const SETTINGS_PATH = path.join(HOME, '.claude', 'settings.json');
const TOKEN_SCRIPT = path.join(HOME, '.claude', 'get-claude-token.sh');

let cachedToken = null;
let tokenExpiresAt = 0;

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

function getModels() {
  const provider = detectProvider();
  if (provider === 'anthropic') {
    return [
      { id: 'claude-opus-4-20250514', label: 'Claude Opus 4', tier: 'heavy' },
      { id: 'claude-sonnet-4-5-20250514', label: 'Claude Sonnet 4.5', tier: 'standard' },
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
  return [];
}

function getDefaultModel() {
  const models = getModels();
  return models.length > 0 ? models[0].id : null;
}

function buildRequest(body) {
  const provider = detectProvider();
  if (!provider) throw new Error('No AI provider configured');

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
  } else if (provider === 'bedrock') {
    throw new Error('Bedrock direct API not supported yet. Use Azure AI Foundry or Anthropic API.');
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
  };
}

function getProviderInfo() {
  const provider = detectProvider();
  return {
    provider,
    name: provider === 'anthropic' ? 'Anthropic API'
        : provider === 'azure-foundry' ? 'Azure AI Foundry'
        : provider === 'bedrock' ? 'AWS Bedrock'
        : 'Not configured',
    authenticated: !!provider,
    models: getModels(),
    defaultModel: getDefaultModel(),
  };
}

module.exports = { detectProvider, getModels, getDefaultModel, buildRequest, getProviderInfo };
