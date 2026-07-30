/**
 * Provider Management Module
 * Handles AI provider detection, configuration, prerequisite checks,
 * connection testing, and auth flows for the Setup wizard.
 *
 * Two categories:
 *   - claudeCode: powers the Claude Code CLI (pick one)
 *   - appDev: credentials for apps built with /make-it (any combination)
 */

const fs = require('fs');
const path = require('path');
const { execSync, spawn } = require('child_process');

const HOME_DIR = process.env.HOME || '/home/coder';
const SETTINGS_PATH = path.join(HOME_DIR, '.claude', 'settings.json');
const PROVIDERS_PATH = path.join(HOME_DIR, '.claude', 'providers.json');
const AWS_CONFIG_PATH = path.join(HOME_DIR, '.aws', 'config');
const TOKEN_SCRIPT_PATH = path.join(HOME_DIR, '.claude', 'get-claude-token.sh');
const MODELS_CACHE_PATH = path.join(HOME_DIR, '.claude', 'models-cache.json');

// Model slot discovered from the live provider at container start by
// scripts/discover-models.py. Used when a wizard model field is left blank, so
// configuring a provider can't overwrite a real deployment name with a stale
// hardcoded one.
function discoveredModel(providerKey, slot) {
  try {
    const cache = JSON.parse(fs.readFileSync(MODELS_CACHE_PATH, 'utf-8'));
    const entry = cache.providers[providerKey];
    if (!entry || entry.source === 'fallback') return '';
    return entry.slots[slot] || '';
  } catch { return ''; }
}

// -------------------------------------------------------------------------
// Provider Definitions
// -------------------------------------------------------------------------
const PROVIDER_DEFS = {
  anthropic: {
    id: 'anthropic',
    name: 'Anthropic API',
    description: 'Direct API access with an Anthropic API key',
    category: 'claudeCode',
    icon: 'anthropic',
    fields: [
      { key: 'apiKey', label: 'API Key', type: 'password', placeholder: 'sk-ant-...',  required: true },
    ],
    models: [
      { id: 'claude-opus-4-6', label: 'Claude Opus 4.6', tier: 'heavy' },
      { id: 'claude-sonnet-4-6', label: 'Claude Sonnet 4.6', tier: 'standard' },
      { id: 'claude-haiku-4-5', label: 'Claude Haiku 4.5', tier: 'light' },
    ],
    defaultModel: 'claude-sonnet-4-6',
    prereqs: [],
  },

  'azure-foundry': {
    id: 'azure-foundry',
    name: 'Azure AI Foundry',
    description: 'Claude via Azure AI Foundry (API key or Azure SSO)',
    category: 'claudeCode',
    icon: 'azure',
    fields: [
      { key: 'endpoint', label: 'Foundry Endpoint URL', type: 'text', placeholder: 'https://your-endpoint.azure.com/anthropic', required: true },
      { key: 'authMode', label: 'Authentication', type: 'select', options: [
        { value: 'apikey', label: 'API Key' },
        { value: 'sso', label: 'Azure SSO (Device Code)' },
      ], required: true },
      { key: 'apiKey', label: 'API Key', type: 'password', placeholder: 'Your Foundry API key', required: false, showWhen: { field: 'authMode', value: 'apikey' } },
      { key: 'tokenResource', label: 'Token Resource', type: 'text', placeholder: 'https://cognitiveservices.azure.com', required: false, showWhen: { field: 'authMode', value: 'sso' }, default: 'https://cognitiveservices.azure.com' },
    ],
    modelFields: [
      { key: 'modelSonnet', label: 'Sonnet Deployment', type: 'text', placeholder: 'claude-sonnet-4-6', default: 'claude-sonnet-4-6' },
      { key: 'modelHaiku', label: 'Haiku Deployment', type: 'text', placeholder: 'claude-haiku-4-5', default: 'claude-haiku-4-5' },
      { key: 'modelOpus', label: 'Opus Deployment', type: 'text', placeholder: 'claude-opus-4-6', default: 'claude-opus-4-6' },
    ],
    defaultModel: 'opus',
    prereqs: [
      { id: 'azure-cli', label: 'Azure CLI', check: 'az', requiredFor: 'sso' },
    ],
  },

  bedrock: {
    id: 'bedrock',
    name: 'AWS Bedrock',
    description: 'Claude via AWS Bedrock with IAM Identity Center SSO',
    category: 'claudeCode',
    icon: 'aws',
    fields: [
      { key: 'ssoStartUrl', label: 'SSO Start URL', type: 'text', placeholder: 'https://d-xxxxxxxxxx.awsapps.com/start', required: true },
      { key: 'ssoRegion', label: 'SSO Region', type: 'text', placeholder: 'us-east-1', required: true, default: 'us-east-1' },
      { key: 'accountId', label: 'AWS Account ID', type: 'text', placeholder: '123456789012', required: true },
      { key: 'roleName', label: 'SSO Role Name', type: 'text', placeholder: 'bedrock-model-access', required: true },
      { key: 'region', label: 'Bedrock Region', type: 'text', placeholder: 'us-east-1', required: true, default: 'us-east-1' },
      { key: 'profileName', label: 'AWS Profile Name', type: 'text', placeholder: 'sso-bedrock-model-access', required: true, default: 'sso-bedrock-model-access' },
    ],
    models: [
      { id: 'us.anthropic.claude-opus-4-6-v1', label: 'Claude Opus 4.6', tier: 'heavy' },
      { id: 'us.anthropic.claude-sonnet-4-6', label: 'Claude Sonnet 4.6', tier: 'standard' },
      { id: 'us.anthropic.claude-haiku-4-5-20251001-v1:0', label: 'Claude Haiku 4.5', tier: 'light' },
    ],
    defaultModel: 'sonnet',
    prereqs: [
      { id: 'aws-cli', label: 'AWS CLI v2', check: 'aws' },
    ],
  },

  openai: {
    id: 'openai',
    name: 'OpenAI',
    description: 'OpenAI API for GPT models in your apps',
    category: 'appDev',
    icon: 'openai',
    fields: [
      { key: 'apiKey', label: 'API Key', type: 'password', placeholder: 'sk-...', required: true },
      { key: 'orgId', label: 'Organization ID (optional)', type: 'text', placeholder: 'org-...', required: false },
      { key: 'baseUrl', label: 'Base URL (optional)', type: 'text', placeholder: 'https://api.openai.com/v1', required: false },
    ],
    models: [
      { id: 'gpt-4o', label: 'GPT-4o', tier: 'heavy' },
      { id: 'gpt-4o-mini', label: 'GPT-4o Mini', tier: 'standard' },
      { id: 'o1', label: 'o1', tier: 'heavy' },
      { id: 'o1-mini', label: 'o1 Mini', tier: 'standard' },
      { id: 'gpt-4-turbo', label: 'GPT-4 Turbo', tier: 'heavy' },
      { id: 'gpt-3.5-turbo', label: 'GPT-3.5 Turbo', tier: 'light' },
    ],
    defaultModel: 'gpt-4o',
    prereqs: [],
  },

  'azure-openai': {
    id: 'azure-openai',
    name: 'Azure OpenAI',
    description: 'Azure-hosted OpenAI models for your apps',
    category: 'appDev',
    icon: 'azure',
    fields: [
      { key: 'endpoint', label: 'Azure OpenAI Endpoint', type: 'text', placeholder: 'https://your-resource.openai.azure.com', required: true },
      { key: 'apiKey', label: 'API Key', type: 'password', placeholder: 'Your Azure OpenAI key', required: true },
      { key: 'apiVersion', label: 'API Version', type: 'text', placeholder: '2024-02-01', required: false, default: '2024-02-01' },
    ],
    modelFields: [
      { key: 'deploymentGpt4', label: 'GPT-4 Deployment Name', type: 'text', placeholder: 'gpt-4o' },
      { key: 'deploymentGpt35', label: 'GPT-3.5 Deployment Name', type: 'text', placeholder: 'gpt-35-turbo' },
    ],
    defaultModel: 'gpt-4o',
    prereqs: [],
  },
};

// -------------------------------------------------------------------------
// Read/Write Helpers
// -------------------------------------------------------------------------
function readSettings() {
  try {
    if (!fs.existsSync(SETTINGS_PATH)) return {};
    return JSON.parse(fs.readFileSync(SETTINGS_PATH, 'utf-8'));
  } catch { return {}; }
}

function writeSettings(settings) {
  const dir = path.dirname(SETTINGS_PATH);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(SETTINGS_PATH, JSON.stringify(settings, null, 2), 'utf-8');
}

function readProviders() {
  try {
    if (!fs.existsSync(PROVIDERS_PATH)) return {};
    return JSON.parse(fs.readFileSync(PROVIDERS_PATH, 'utf-8'));
  } catch { return {}; }
}

function writeProviders(providers) {
  const dir = path.dirname(PROVIDERS_PATH);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(PROVIDERS_PATH, JSON.stringify(providers, null, 2), 'utf-8');
}

// -------------------------------------------------------------------------
// Status Detection
// -------------------------------------------------------------------------
function getProviderStatus() {
  const settings = readSettings();
  const settingsEnv = settings.env || {};
  const appProviders = readProviders();

  // Detect active Claude Code provider
  let activeClaudeProvider = null;

  if (process.env.ANTHROPIC_API_KEY || settingsEnv.ANTHROPIC_API_KEY) {
    activeClaudeProvider = 'anthropic';
  } else if (settingsEnv.CLAUDE_CODE_USE_FOUNDRY === '1' || settingsEnv.ANTHROPIC_FOUNDRY_BASE_URL || process.env.ANTHROPIC_FOUNDRY_BASE_URL) {
    activeClaudeProvider = 'azure-foundry';
  } else if (settingsEnv.CLAUDE_CODE_USE_BEDROCK === '1' || process.env.CLAUDE_CODE_USE_BEDROCK === '1') {
    activeClaudeProvider = 'bedrock';
  } else if (process.env.CLAUDE_CODE_PROVIDER === 'claude') {
    activeClaudeProvider = 'claude';
  }

  const claudeProviders = {};
  const appDevProviders = {};

  for (const [id, def] of Object.entries(PROVIDER_DEFS)) {
    const status = { id, name: def.name, description: def.description, icon: def.icon, configured: false, status: 'not_configured', detail: '' };

    if (def.category === 'claudeCode') {
      status.configured = (activeClaudeProvider === id);
      if (status.configured) {
        status.status = 'active';
        status.detail = getProviderDetail(id, settings, settingsEnv);
      }
      claudeProviders[id] = status;
    } else {
      status.configured = !!(appProviders[id] && appProviders[id].apiKey);
      if (status.configured) {
        status.status = 'configured';
        status.detail = `API key set`;
      }
      appDevProviders[id] = status;
    }
  }

  return {
    claudeCode: { active: activeClaudeProvider, providers: claudeProviders },
    appDev: { providers: appDevProviders },
  };
}

function getProviderDetail(id, settings, env) {
  switch (id) {
    case 'anthropic':
      return 'API key configured';
    case 'azure-foundry': {
      const endpoint = env.ANTHROPIC_FOUNDRY_BASE_URL || '';
      const hasApiKey = !!(env.ANTHROPIC_FOUNDRY_API_KEY);
      const hasTokenHelper = !!(settings.apiKeyHelper);
      if (hasApiKey) return `API key auth - ${endpoint}`;
      if (hasTokenHelper) return `Azure SSO auth - ${endpoint}`;
      return endpoint || 'Configured';
    }
    case 'bedrock': {
      const region = env.AWS_REGION || 'us-east-1';
      const profile = env.AWS_PROFILE || '';
      return `Region: ${region}${profile ? ', Profile: ' + profile : ''}`;
    }
    default:
      return 'Configured';
  }
}

// -------------------------------------------------------------------------
// Prerequisite Checks
// -------------------------------------------------------------------------
function checkPrerequisites(providerId) {
  const def = PROVIDER_DEFS[providerId];
  if (!def) return { checks: [], allPass: true };

  const results = [];

  for (const prereq of (def.prereqs || [])) {
    const result = { id: prereq.id, label: prereq.label, pass: false, detail: '', requiredFor: prereq.requiredFor || null };

    try {
      if (prereq.check === 'aws') {
        const version = execSync('aws --version 2>&1', { timeout: 5000 }).toString().trim();
        const isV2 = /aws-cli\/2\./i.test(version);
        result.pass = isV2;
        result.detail = isV2 ? version.split(' ')[0] : 'AWS CLI v2 required (found v1)';
      } else if (prereq.check === 'az') {
        const version = execSync('az version --output tsv 2>/dev/null | head -1', { timeout: 5000 }).toString().trim();
        result.pass = true;
        result.detail = `Azure CLI ${version}`;
      } else {
        const out = execSync(`command -v ${prereq.check} 2>/dev/null`, { timeout: 5000 }).toString().trim();
        result.pass = !!out;
        result.detail = out ? 'Installed' : 'Not found';
      }
    } catch {
      result.detail = 'Not installed';
    }

    results.push(result);
  }

  return {
    checks: results,
    allPass: results.every(r => r.pass),
  };
}

// -------------------------------------------------------------------------
// Configuration
// -------------------------------------------------------------------------
function configureProvider(providerId, category, config) {
  const def = PROVIDER_DEFS[providerId];
  if (!def) return { success: false, error: 'Unknown provider' };

  try {
    if (category === 'claudeCode') {
      return configureClaudeCodeProvider(providerId, config);
    } else {
      return configureAppDevProvider(providerId, config);
    }
  } catch (err) {
    return { success: false, error: err.message };
  }
}

function configureClaudeCodeProvider(providerId, config) {
  const settings = { env: {} };

  switch (providerId) {
    case 'anthropic': {
      // Anthropic API key: Claude Code reads it from env directly.
      // Write settings.json with the key so getFreshEnv() picks it up.
      settings.env.ANTHROPIC_API_KEY = config.apiKey;
      if (config.defaultModel) settings.model = config.defaultModel;
      // Remove stale token script
      try { fs.unlinkSync(TOKEN_SCRIPT_PATH); } catch {}
      break;
    }

    case 'azure-foundry': {
      settings.env.CLAUDE_CODE_USE_FOUNDRY = '1';
      settings.env.ANTHROPIC_FOUNDRY_BASE_URL = config.endpoint;

      if (config.authMode === 'apikey') {
        settings.env.ANTHROPIC_FOUNDRY_API_KEY = config.apiKey;
        try { fs.unlinkSync(TOKEN_SCRIPT_PATH); } catch {}
      } else {
        // SSO/token mode: create token helper script
        const tokenResource = config.tokenResource || 'https://cognitiveservices.azure.com';
        const script = `#!/bin/bash
TOKEN=$(az account get-access-token --resource "${tokenResource}" --query accessToken -o tsv 2>/dev/null)
if [ -z "$TOKEN" ]; then
    echo "ERROR: Azure token expired or not logged in. Run: az login --use-device-code" >&2
    exit 1
fi
echo "$TOKEN"
`;
        fs.writeFileSync(TOKEN_SCRIPT_PATH, script, { mode: 0o755 });
        settings.apiKeyHelper = TOKEN_SCRIPT_PATH;
      }

      // Model deployments. Blank fields fall back to what discovery confirmed
      // is actually deployed, not to a hardcoded guess.
      settings.env.ANTHROPIC_DEFAULT_SONNET_MODEL =
        config.modelSonnet || discoveredModel('azure-foundry', 'sonnet') || 'claude-sonnet-4-6';
      settings.env.ANTHROPIC_DEFAULT_HAIKU_MODEL =
        config.modelHaiku || discoveredModel('azure-foundry', 'haiku') || 'claude-haiku-4-5';
      settings.env.ANTHROPIC_DEFAULT_OPUS_MODEL =
        config.modelOpus || discoveredModel('azure-foundry', 'opus') || 'claude-opus-4-6';
      if (config.defaultModel) settings.model = config.defaultModel;
      break;
    }

    case 'bedrock': {
      settings.env.CLAUDE_CODE_USE_BEDROCK = '1';
      settings.env.AWS_PROFILE = config.profileName || 'sso-bedrock-model-access';
      settings.env.AWS_REGION = config.region || 'us-east-1';

      if (config.defaultModel) {
        settings.env.ANTHROPIC_MODEL = config.defaultModel;
      }

      // Model overrides; otherwise use whatever Bedrock reported it can run.
      // Left unset when neither is available, so Claude Code keeps its default.
      const bedrockSlots = {
        ANTHROPIC_DEFAULT_SONNET_MODEL: config.modelSonnet || discoveredModel('bedrock', 'sonnet'),
        ANTHROPIC_DEFAULT_HAIKU_MODEL: config.modelHaiku || discoveredModel('bedrock', 'haiku'),
        ANTHROPIC_DEFAULT_OPUS_MODEL: config.modelOpus || discoveredModel('bedrock', 'opus'),
      };
      for (const [k, v] of Object.entries(bedrockSlots)) {
        if (v) settings.env[k] = v;
      }

      // Write AWS CLI config
      writeAwsConfig(config);

      // Remove stale token script
      try { fs.unlinkSync(TOKEN_SCRIPT_PATH); } catch {}
      break;
    }

    default:
      return { success: false, error: 'Unknown Claude Code provider' };
  }

  settings.skipDangerousModePermissionPrompt = true;
  writeSettings(settings);

  return { success: true, provider: providerId };
}

function configureAppDevProvider(providerId, config) {
  const providers = readProviders();

  switch (providerId) {
    case 'openai':
      providers.openai = {
        apiKey: config.apiKey,
        orgId: config.orgId || '',
        baseUrl: config.baseUrl || '',
        defaultModel: config.defaultModel || 'gpt-4o',
      };
      break;

    case 'azure-openai':
      providers['azure-openai'] = {
        endpoint: config.endpoint,
        apiKey: config.apiKey,
        apiVersion: config.apiVersion || '2024-02-01',
        deploymentGpt4: config.deploymentGpt4 || '',
        deploymentGpt35: config.deploymentGpt35 || '',
        defaultModel: config.defaultModel || 'gpt-4o',
      };
      break;

    default:
      return { success: false, error: 'Unknown app dev provider' };
  }

  writeProviders(providers);
  return { success: true, provider: providerId };
}

function writeAwsConfig(config) {
  const dir = path.dirname(AWS_CONFIG_PATH);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

  const profileName = config.profileName || 'sso-bedrock-model-access';
  const sessionName = 'aws-sso';

  // Read existing config to preserve other profiles
  let existingConfig = '';
  try { existingConfig = fs.readFileSync(AWS_CONFIG_PATH, 'utf-8'); } catch {}

  // Remove existing sso-session and this profile if present
  const lines = existingConfig.split('\n');
  const sections = [];
  let currentSection = null;

  for (const line of lines) {
    const sectionMatch = line.match(/^\[(sso-session\s+|profile\s+)?(.+?)\]\s*$/);
    if (sectionMatch) {
      if (currentSection) sections.push(currentSection);
      currentSection = { header: line, lines: [], name: sectionMatch[2] };
    } else if (currentSection) {
      currentSection.lines.push(line);
    }
  }
  if (currentSection) sections.push(currentSection);

  // Filter out our session and profile
  const kept = sections.filter(s =>
    s.name !== sessionName && s.name !== profileName
  );

  // Build new config
  const parts = kept.map(s => s.header + '\n' + s.lines.join('\n')).filter(p => p.trim());

  // Add SSO session
  parts.push(`[sso-session ${sessionName}]
sso_start_url = ${config.ssoStartUrl}
sso_region = ${config.ssoRegion || 'us-east-1'}
sso_registration_scopes = sso:account:access`);

  // Add profile
  parts.push(`[profile ${profileName}]
sso_session = ${sessionName}
sso_account_id = ${config.accountId}
sso_role_name = ${config.roleName}
region = ${config.region || 'us-east-1'}
output = json`);

  fs.writeFileSync(AWS_CONFIG_PATH, parts.join('\n\n') + '\n', 'utf-8');
}

// -------------------------------------------------------------------------
// Connection Testing
// -------------------------------------------------------------------------
function testProvider(providerId, config) {
  config = config || {};
  try {
    switch (providerId) {
      case 'anthropic':
        return testAnthropic(config);
      case 'azure-foundry':
        return testAzureFoundry(config);
      case 'bedrock':
        return testBedrock(config);
      case 'openai':
        return testOpenAI(config);
      case 'azure-openai':
        return testAzureOpenAI(config);
      default:
        return { success: false, error: 'Unknown provider' };
    }
  } catch (err) {
    return { success: false, error: err.message };
  }
}

function testAnthropic(config) {
  const key = config.apiKey;
  if (!key) return { success: false, error: 'API key is required' };

  try {
    const result = execSync(
      `curl -sf --max-time 10 https://api.anthropic.com/v1/messages ` +
      `-H "x-api-key: ${shellEscape(key)}" ` +
      `-H "anthropic-version: 2023-06-01" ` +
      `-H "content-type: application/json" ` +
      `-d '{"model":"claude-haiku-4-5","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}' 2>&1`,
      { timeout: 15000 }
    ).toString();

    const parsed = JSON.parse(result);
    if (parsed.type === 'message') {
      return { success: true, detail: `Connected - model: ${parsed.model}` };
    }
    if (parsed.error) {
      return { success: false, error: parsed.error.message || 'API error' };
    }
    return { success: true, detail: 'Connected to Anthropic API' };
  } catch (err) {
    const msg = err.stdout ? err.stdout.toString() : err.message;
    if (/invalid.*api.*key|authentication/i.test(msg)) {
      return { success: false, error: 'Invalid API key' };
    }
    return { success: false, error: 'Could not reach Anthropic API. Check your network.' };
  }
}

function testAzureFoundry(config) {
  const endpoint = config.endpoint;
  if (!endpoint) return { success: false, error: 'Endpoint URL is required' };

  let authHeader;
  if (config.authMode === 'apikey') {
    if (!config.apiKey) return { success: false, error: 'API key is required' };
    authHeader = `-H "x-api-key: ${shellEscape(config.apiKey)}"`;
  } else {
    // Token-based: try to get a token
    try {
      const tokenResource = config.tokenResource || 'https://cognitiveservices.azure.com';
      const token = execSync(
        `az account get-access-token --resource "${tokenResource}" --query accessToken -o tsv 2>/dev/null`,
        { timeout: 10000 }
      ).toString().trim();
      if (!token) return { success: false, error: 'Could not get Azure token. Run az login first.' };
      authHeader = `-H "Authorization: Bearer ${token}"`;
    } catch {
      return { success: false, error: 'Azure token expired or not logged in. Complete Azure SSO login first.' };
    }
  }

  const model = config.modelSonnet || config.modelHaiku || 'claude-haiku-4-5';
  try {
    const result = execSync(
      `curl -sf --max-time 10 "${shellEscape(endpoint)}/v1/messages" ` +
      `${authHeader} ` +
      `-H "anthropic-version: 2023-06-01" ` +
      `-H "content-type: application/json" ` +
      `-d '{"model":"${shellEscape(model)}","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}' 2>&1`,
      { timeout: 15000 }
    ).toString();

    const parsed = JSON.parse(result);
    if (parsed.type === 'message') {
      return { success: true, detail: `Connected - model: ${parsed.model}` };
    }
    if (parsed.error) {
      return { success: false, error: parsed.error.message || 'API error' };
    }
    return { success: true, detail: 'Connected to Azure AI Foundry' };
  } catch (err) {
    const msg = err.stdout ? err.stdout.toString() : err.message;
    if (/401|403|auth/i.test(msg)) {
      return { success: false, error: 'Authentication failed. Check your credentials.' };
    }
    return { success: false, error: 'Could not reach Azure AI Foundry. Check your endpoint URL and network.' };
  }
}

function testBedrock(config) {
  const profile = config.profileName || 'sso-bedrock-model-access';
  const region = config.region || 'us-east-1';

  try {
    const result = execSync(
      `aws bedrock list-inference-profiles --profile "${shellEscape(profile)}" --region "${shellEscape(region)}" --max-results 1 2>&1`,
      { timeout: 15000 }
    ).toString();

    const parsed = JSON.parse(result);
    if (parsed.InferenceProfileSummaries) {
      return { success: true, detail: `Connected to Bedrock in ${region}` };
    }
    return { success: true, detail: 'Connected to AWS Bedrock' };
  } catch (err) {
    const msg = err.stdout ? err.stdout.toString() : (err.stderr ? err.stderr.toString() : err.message);
    if (/expired|login|UnauthorizedAccess/i.test(msg)) {
      return { success: false, error: 'AWS SSO session expired. Complete SSO login first.' };
    }
    if (/could not connect|timeout/i.test(msg)) {
      return { success: false, error: 'Could not reach AWS. Check your network/VPN.' };
    }
    return { success: false, error: `AWS Bedrock error: ${msg.substring(0, 150)}` };
  }
}

function testOpenAI(config) {
  const key = config.apiKey;
  if (!key) return { success: false, error: 'API key is required' };
  const baseUrl = config.baseUrl || 'https://api.openai.com/v1';

  try {
    const result = execSync(
      `curl -sf --max-time 10 "${shellEscape(baseUrl)}/models" ` +
      `-H "Authorization: Bearer ${shellEscape(key)}" 2>&1`,
      { timeout: 15000 }
    ).toString();

    const parsed = JSON.parse(result);
    if (parsed.data && Array.isArray(parsed.data)) {
      const modelCount = parsed.data.length;
      return { success: true, detail: `Connected - ${modelCount} models available` };
    }
    if (parsed.error) {
      return { success: false, error: parsed.error.message || 'API error' };
    }
    return { success: true, detail: 'Connected to OpenAI' };
  } catch (err) {
    const msg = err.stdout ? err.stdout.toString() : err.message;
    if (/invalid.*api.*key|auth/i.test(msg)) {
      return { success: false, error: 'Invalid API key' };
    }
    return { success: false, error: 'Could not reach OpenAI API. Check your network.' };
  }
}

function testAzureOpenAI(config) {
  if (!config.endpoint) return { success: false, error: 'Endpoint is required' };
  if (!config.apiKey) return { success: false, error: 'API key is required' };
  const apiVersion = config.apiVersion || '2024-02-01';

  try {
    const result = execSync(
      `curl -sf --max-time 10 "${shellEscape(config.endpoint)}/openai/models?api-version=${shellEscape(apiVersion)}" ` +
      `-H "api-key: ${shellEscape(config.apiKey)}" 2>&1`,
      { timeout: 15000 }
    ).toString();

    const parsed = JSON.parse(result);
    if (parsed.data && Array.isArray(parsed.data)) {
      return { success: true, detail: `Connected - ${parsed.data.length} deployments` };
    }
    if (parsed.error) {
      return { success: false, error: parsed.error.message || 'API error' };
    }
    return { success: true, detail: 'Connected to Azure OpenAI' };
  } catch (err) {
    const msg = err.stdout ? err.stdout.toString() : err.message;
    if (/401|403|auth/i.test(msg)) {
      return { success: false, error: 'Authentication failed. Check your API key.' };
    }
    return { success: false, error: 'Could not reach Azure OpenAI. Check your endpoint and network.' };
  }
}

// -------------------------------------------------------------------------
// Auth Flows (interactive)
// -------------------------------------------------------------------------
const activeAuthFlows = new Map();

function startAuthFlow(providerId, action, params) {
  if (providerId === 'azure-foundry' && action === 'sso-login') {
    return startAzureSSOLogin();
  }
  if (providerId === 'bedrock' && action === 'sso-login') {
    return startAwsSSOLogin(params.profileName || 'sso-bedrock-model-access');
  }
  return { success: false, error: 'Unknown auth flow' };
}

function startAzureSSOLogin() {
  // Kill any existing flow
  const existing = activeAuthFlows.get('azure-sso');
  if (existing && existing.process) {
    try { existing.process.kill(); } catch {}
  }

  return new Promise((resolve) => {
    const proc = spawn('az', ['login', '--use-device-code'], {
      stdio: ['pipe', 'pipe', 'pipe'],
      env: { ...process.env, NO_COLOR: '1' },
    });

    const flow = { process: proc, deviceCode: null, url: null, completed: false, error: null };
    activeAuthFlows.set('azure-sso', flow);

    let stderr = '';

    proc.stderr.on('data', (data) => {
      stderr += data.toString();
      // Parse device code and URL from az login output
      const codeMatch = stderr.match(/enter the code\s+([A-Z0-9]+)\s+to/i);
      const urlMatch = stderr.match(/(https:\/\/microsoft\.com\/devicelogin)/i);
      if (codeMatch) flow.deviceCode = codeMatch[1];
      if (urlMatch) flow.url = urlMatch[1];

      // Once we have both, resolve with instructions
      if (flow.deviceCode && flow.url && !flow.resolved) {
        flow.resolved = true;
        resolve({
          pending: true,
          deviceCode: flow.deviceCode,
          url: flow.url,
          message: `Go to ${flow.url} and enter code: ${flow.deviceCode}`,
        });
      }
    });

    proc.on('close', (code) => {
      flow.completed = true;
      if (code === 0) {
        flow.error = null;
      } else {
        flow.error = 'Login failed or was cancelled';
      }
      activeAuthFlows.delete('azure-sso');
    });

    // Timeout: if no device code after 15s, fail
    setTimeout(() => {
      if (!flow.resolved) {
        flow.resolved = true;
        try { proc.kill(); } catch {}
        activeAuthFlows.delete('azure-sso');
        resolve({ success: false, error: 'Azure CLI did not respond. Is it installed?' });
      }
    }, 15000);
  });
}

function startAwsSSOLogin(profileName) {
  const existing = activeAuthFlows.get('aws-sso');
  if (existing && existing.process) {
    try { existing.process.kill(); } catch {}
  }

  return new Promise((resolve) => {
    const proc = spawn('aws', ['sso', 'login', '--profile', profileName], {
      stdio: ['pipe', 'pipe', 'pipe'],
      env: { ...process.env },
    });

    const flow = { process: proc, completed: false, error: null };
    activeAuthFlows.set('aws-sso', flow);

    let output = '';

    proc.stdout.on('data', (data) => { output += data.toString(); });
    proc.stderr.on('data', (data) => { output += data.toString(); });

    // AWS SSO login opens a browser automatically
    // Resolve immediately with pending status
    setTimeout(() => {
      if (!flow.resolved) {
        flow.resolved = true;
        resolve({
          pending: true,
          message: 'A browser window should open for AWS SSO login. Complete the sign-in there.',
          detail: 'If no browser opened, check the terminal for the SSO login URL.',
        });
      }
    }, 2000);

    proc.on('close', (code) => {
      flow.completed = true;
      flow.error = code === 0 ? null : 'SSO login failed or was cancelled';
      activeAuthFlows.delete('aws-sso');
    });

    setTimeout(() => {
      if (!flow.completed) {
        try { proc.kill(); } catch {}
        activeAuthFlows.delete('aws-sso');
      }
    }, 120000); // 2 minute timeout
  });
}

function checkAuthFlowStatus(flowId) {
  const flow = activeAuthFlows.get(flowId);
  if (!flow) return { active: false, completed: true, error: null };

  return {
    active: !flow.completed,
    completed: flow.completed,
    error: flow.error,
    deviceCode: flow.deviceCode || null,
  };
}

// -------------------------------------------------------------------------
// Remove provider configuration
// -------------------------------------------------------------------------
function removeProvider(providerId, category) {
  if (category === 'claudeCode') {
    // Clear settings.json
    try { fs.unlinkSync(SETTINGS_PATH); } catch {}
    try { fs.unlinkSync(TOKEN_SCRIPT_PATH); } catch {}
    return { success: true };
  } else {
    const providers = readProviders();
    delete providers[providerId];
    writeProviders(providers);
    return { success: true };
  }
}

// -------------------------------------------------------------------------
// Utilities
// -------------------------------------------------------------------------
function shellEscape(str) {
  if (!str) return '';
  return str.replace(/'/g, "'\\''");
}

function getDefinitions() {
  return PROVIDER_DEFS;
}

// Write/configure/test/auth functions removed — configuration happens host-side
// via setup/server.js before `docker compose up`.
module.exports = {
  getProviderStatus,
  getDefinitions,
  checkPrerequisites,
};
