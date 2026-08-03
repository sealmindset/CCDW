/**
 * Host-side Provider Configuration
 * Reads/writes .env for AI provider setup before container start.
 * Zero dependencies — Node built-ins only.
 */

const fs = require('fs');
const path = require('path');
const os = require('os');
const { execSync } = require('child_process');

// -------------------------------------------------------------------------
// Provider Definitions (same as workshop/providers.js)
// -------------------------------------------------------------------------
const PROVIDER_DEFS = {
  anthropic: {
    id: 'anthropic',
    name: 'Anthropic API',
    description: 'Direct API access with an Anthropic API key',
    category: 'claudeCode',
    icon: 'anthropic',
    fields: [
      { key: 'apiKey', label: 'API Key', type: 'password', placeholder: 'sk-ant-...', required: true },
    ],
    models: [
      { id: 'claude-opus-5', label: 'Claude Opus 5', tier: 'heavy' },
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
        { value: 'sso', label: 'Azure SSO (sign in after container starts)' },
        { value: 'apikey', label: 'API Key' },
      ], required: true },
      { key: 'apiKey', label: 'API Key', type: 'password', placeholder: 'Your Foundry API key', required: false, showWhen: { field: 'authMode', value: 'apikey' } },
      { key: 'tokenResource', label: 'Token Resource', type: 'text', placeholder: 'https://cognitiveservices.azure.com', required: false, showWhen: { field: 'authMode', value: 'sso' }, default: 'https://cognitiveservices.azure.com' },
    ],
    modelFields: [
      { key: 'modelSonnet', label: 'Sonnet Deployment', type: 'text', placeholder: 'claude-sonnet-4-6', default: 'claude-sonnet-4-6' },
      { key: 'modelHaiku', label: 'Haiku Deployment', type: 'text', placeholder: 'claude-haiku-4-5', default: 'claude-haiku-4-5' },
      { key: 'modelOpus', label: 'Opus Deployment', type: 'text', placeholder: 'claude-opus-5', default: 'claude-opus-5' },
    ],
    defaultModel: 'opus',
    prereqs: [],
    ssoNote: 'Azure SSO sign-in happens automatically when the container starts.',
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
      { key: 'profileName', label: 'AWS Profile Name', type: 'text', placeholder: 'sso-bedrock', required: true, default: 'sso-bedrock' },
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
    ssoNote: 'AWS SSO sign-in happens automatically when the container starts.',
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
// .env Read/Write
// -------------------------------------------------------------------------

function readEnv(envPath) {
  try {
    return fs.readFileSync(envPath, 'utf-8');
  } catch {
    return '';
  }
}

function parseEnv(content) {
  const lines = content.split(/\r?\n/);
  const vars = {};
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eq = trimmed.indexOf('=');
    if (eq < 0) continue;
    const key = trimmed.substring(0, eq).trim();
    const val = trimmed.substring(eq + 1).trim();
    vars[key] = val;
  }
  return vars;
}

function setEnvVars(envPath, varsToSet, varsToComment) {
  let content = readEnv(envPath);
  const lines = content.split(/\r?\n/);
  const eol = content.includes('\r\n') ? '\r\n' : '\n';

  const handled = new Set();

  for (let i = 0; i < lines.length; i++) {
    const trimmed = lines[i].trim();
    const isComment = trimmed.startsWith('#');
    const line = isComment ? trimmed.replace(/^#+\s*/, '') : trimmed;
    const eq = line.indexOf('=');
    if (eq < 0) continue;
    const key = line.substring(0, eq).trim();

    if (varsToSet && key in varsToSet) {
      lines[i] = key + '=' + varsToSet[key];
      handled.add(key);
    } else if (varsToComment && varsToComment.includes(key) && !isComment) {
      lines[i] = '# ' + lines[i];
    }
  }

  if (varsToSet) {
    for (const [key, val] of Object.entries(varsToSet)) {
      if (!handled.has(key)) {
        lines.push(key + '=' + val);
      }
    }
  }

  fs.writeFileSync(envPath, lines.join(eol), 'utf-8');
}

// -------------------------------------------------------------------------
// Status Detection (reads .env)
// -------------------------------------------------------------------------
function getProviderStatus(envPath) {
  const vars = parseEnv(readEnv(envPath));

  let activeClaudeProvider = null;
  if (vars.ANTHROPIC_API_KEY) {
    activeClaudeProvider = 'anthropic';
  } else if (vars.ANTHROPIC_FOUNDRY_BASE_URL) {
    activeClaudeProvider = 'azure-foundry';
  } else if (vars.CLAUDE_CODE_USE_BEDROCK === '1') {
    activeClaudeProvider = 'bedrock';
  }

  const claudeProviders = {};
  const appDevProviders = {};

  for (const [id, def] of Object.entries(PROVIDER_DEFS)) {
    const status = { id, name: def.name, description: def.description, icon: def.icon, configured: false, status: 'not_configured', detail: '' };

    if (def.category === 'claudeCode') {
      status.configured = (activeClaudeProvider === id);
      if (status.configured) {
        status.status = 'active';
        status.detail = getProviderDetail(id, vars);
      }
      claudeProviders[id] = status;
    } else {
      if (id === 'openai') status.configured = !!vars.OPENAI_API_KEY;
      else if (id === 'azure-openai') status.configured = !!(vars.AZURE_OPENAI_ENDPOINT && vars.AZURE_OPENAI_API_KEY);
      if (status.configured) {
        status.status = 'configured';
        status.detail = 'API key set';
      }
      appDevProviders[id] = status;
    }
  }

  return {
    claudeCode: { active: activeClaudeProvider, providers: claudeProviders },
    appDev: { providers: appDevProviders },
  };
}

function getProviderDetail(id, vars) {
  switch (id) {
    case 'anthropic':
      return 'API key configured';
    case 'azure-foundry': {
      const endpoint = vars.ANTHROPIC_FOUNDRY_BASE_URL || '';
      const hasApiKey = !!vars.ANTHROPIC_FOUNDRY_API_KEY;
      return hasApiKey ? `API key auth - ${endpoint}` : `Azure SSO - ${endpoint}`;
    }
    case 'bedrock': {
      const region = vars.AWS_REGION || 'us-east-1';
      const profile = vars.AWS_PROFILE || '';
      return `Region: ${region}${profile ? ', Profile: ' + profile : ''}`;
    }
    default:
      return 'Configured';
  }
}

// -------------------------------------------------------------------------
// Prerequisite Checks (run on host)
// -------------------------------------------------------------------------
function checkPrerequisites(providerId) {
  const def = PROVIDER_DEFS[providerId];
  if (!def) return { checks: [], allPass: true };

  const results = [];

  for (const prereq of (def.prereqs || [])) {
    const result = { id: prereq.id, label: prereq.label, pass: false, detail: '' };

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
        const cmd = process.platform === 'win32' ? `where ${prereq.check} 2>nul` : `command -v ${prereq.check} 2>/dev/null`;
        const out = execSync(cmd, { timeout: 5000 }).toString().trim();
        result.pass = !!out;
        result.detail = out ? 'Installed' : 'Not found';
      }
    } catch {
      result.detail = 'Not installed';
    }

    results.push(result);
  }

  return { checks: results, allPass: results.every(r => r.pass) };
}

// -------------------------------------------------------------------------
// Configure Provider (writes to .env)
// -------------------------------------------------------------------------

const CLAUDE_CODE_KEYS = [
  'ANTHROPIC_API_KEY',
  'CLAUDE_CODE_USE_FOUNDRY',
  'ANTHROPIC_FOUNDRY_BASE_URL',
  'ANTHROPIC_FOUNDRY_API_KEY',
  'CLAUDE_CODE_USE_BEDROCK',
  'AWS_PROFILE',
  'AWS_REGION',
];

function configureProvider(envPath, providerId, config) {
  config = config || {};
  const def = PROVIDER_DEFS[providerId];
  if (!def) return { success: false, error: 'Unknown provider' };

  try {
    if (def.category === 'claudeCode') {
      return configureClaudeCode(envPath, providerId, config);
    } else {
      return configureAppDev(envPath, providerId, config);
    }
  } catch (err) {
    return { success: false, error: err.message };
  }
}

function configureClaudeCode(envPath, providerId, config) {
  const varsToComment = [...CLAUDE_CODE_KEYS];
  const varsToSet = {};

  switch (providerId) {
    case 'anthropic':
      varsToSet.ANTHROPIC_API_KEY = config.apiKey;
      break;

    case 'azure-foundry':
      varsToSet.ANTHROPIC_FOUNDRY_BASE_URL = config.endpoint;
      if (config.authMode === 'apikey' && config.apiKey) {
        varsToSet.ANTHROPIC_FOUNDRY_API_KEY = config.apiKey;
      }
      varsToSet.ANTHROPIC_DEFAULT_SONNET_MODEL = config.modelSonnet || 'claude-sonnet-4-6';
      varsToSet.ANTHROPIC_DEFAULT_HAIKU_MODEL = config.modelHaiku || 'claude-haiku-4-5';
      varsToSet.ANTHROPIC_DEFAULT_OPUS_MODEL = config.modelOpus || 'claude-opus-5';
      break;

    case 'bedrock':
      varsToSet.CLAUDE_CODE_USE_BEDROCK = '1';
      varsToSet.AWS_PROFILE = config.profileName || 'sso-bedrock';
      varsToSet.AWS_REGION = config.region || 'us-east-1';
      writeAwsConfig(config);
      break;

    default:
      return { success: false, error: 'Unknown Claude Code provider' };
  }

  const keysBeingSet = Object.keys(varsToSet);
  const keysToComment = varsToComment.filter(k => !keysBeingSet.includes(k));
  setEnvVars(envPath, varsToSet, keysToComment);

  return { success: true, provider: providerId };
}

function configureAppDev(envPath, providerId, config) {
  const varsToSet = {};

  switch (providerId) {
    case 'openai':
      varsToSet.OPENAI_API_KEY = config.apiKey;
      if (config.orgId) varsToSet.OPENAI_ORG_ID = config.orgId;
      if (config.baseUrl) varsToSet.OPENAI_BASE_URL = config.baseUrl;
      break;

    case 'azure-openai':
      varsToSet.AZURE_OPENAI_ENDPOINT = config.endpoint;
      varsToSet.AZURE_OPENAI_API_KEY = config.apiKey;
      varsToSet.AZURE_OPENAI_API_VERSION = config.apiVersion || '2024-02-01';
      if (config.deploymentGpt4) varsToSet.AZURE_OPENAI_DEPLOYMENT_GPT4 = config.deploymentGpt4;
      if (config.deploymentGpt35) varsToSet.AZURE_OPENAI_DEPLOYMENT_GPT35 = config.deploymentGpt35;
      break;

    default:
      return { success: false, error: 'Unknown app dev provider' };
  }

  setEnvVars(envPath, varsToSet, []);
  return { success: true, provider: providerId };
}

function writeAwsConfig(config) {
  const awsDir = path.join(os.homedir(), '.aws');
  const awsConfigPath = path.join(awsDir, 'config');
  if (!fs.existsSync(awsDir)) fs.mkdirSync(awsDir, { recursive: true });

  const profileName = config.profileName || 'sso-bedrock';
  const sessionName = 'aws-sso';

  let existing = '';
  try { existing = fs.readFileSync(awsConfigPath, 'utf-8'); } catch {}

  const lines = existing.split('\n');
  const sections = [];
  let currentSection = null;

  for (const line of lines) {
    const match = line.match(/^\[(sso-session\s+|profile\s+)?(.+?)\]\s*$/);
    if (match) {
      if (currentSection) sections.push(currentSection);
      currentSection = { header: line, lines: [], name: match[2] };
    } else if (currentSection) {
      currentSection.lines.push(line);
    }
  }
  if (currentSection) sections.push(currentSection);

  const kept = sections.filter(s => s.name !== sessionName && s.name !== profileName);
  const parts = kept.map(s => s.header + '\n' + s.lines.join('\n')).filter(p => p.trim());

  parts.push(`[sso-session ${sessionName}]\nsso_start_url = ${config.ssoStartUrl}\nsso_region = ${config.ssoRegion || 'us-east-1'}\nsso_registration_scopes = sso:account:access`);
  parts.push(`[profile ${profileName}]\nsso_session = ${sessionName}\nsso_account_id = ${config.accountId}\nsso_role_name = ${config.roleName}\nregion = ${config.region || 'us-east-1'}\noutput = json`);

  fs.writeFileSync(awsConfigPath, parts.join('\n\n') + '\n', 'utf-8');
}

// -------------------------------------------------------------------------
// Connection Testing
// -------------------------------------------------------------------------
function testProvider(providerId, config) {
  config = config || {};
  try {
    switch (providerId) {
      case 'anthropic': return testAnthropic(config);
      case 'azure-foundry': return testAzureFoundry(config);
      case 'bedrock': return testBedrock(config);
      case 'openai': return testOpenAI(config);
      case 'azure-openai': return testAzureOpenAI(config);
      default: return { success: false, error: 'Unknown provider' };
    }
  } catch (err) {
    return { success: false, error: err.message };
  }
}

function shellEscape(str) {
  if (!str) return '';
  return str.replace(/'/g, "'\\''");
}

function testAnthropic(config) {
  if (!config.apiKey) return { success: false, error: 'API key is required' };
  try {
    const result = execSync(
      `curl -sf --max-time 10 https://api.anthropic.com/v1/messages ` +
      `-H "x-api-key: ${shellEscape(config.apiKey)}" ` +
      `-H "anthropic-version: 2023-06-01" ` +
      `-H "content-type: application/json" ` +
      `-d '{"model":"claude-haiku-4-5","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}' 2>&1`,
      { timeout: 15000 }
    ).toString();
    const parsed = JSON.parse(result);
    if (parsed.type === 'message') return { success: true, detail: `Connected - model: ${parsed.model}` };
    if (parsed.error) return { success: false, error: parsed.error.message || 'API error' };
    return { success: true, detail: 'Connected to Anthropic API' };
  } catch (err) {
    const msg = err.stdout ? err.stdout.toString() : err.message;
    if (/invalid.*api.*key|authentication/i.test(msg)) return { success: false, error: 'Invalid API key' };
    return { success: false, error: 'Could not reach Anthropic API. Check your network.' };
  }
}

function testAzureFoundry(config) {
  if (!config.endpoint) return { success: false, error: 'Endpoint URL is required' };
  if (config.authMode === 'sso') {
    return { success: true, detail: 'Endpoint saved. Azure SSO sign-in will happen after container starts.', skippedAuth: true };
  }
  if (!config.apiKey) return { success: false, error: 'API key is required' };

  const model = config.modelSonnet || config.modelHaiku || 'claude-haiku-4-5';
  try {
    const result = execSync(
      `curl -sf --max-time 10 "${shellEscape(config.endpoint)}/v1/messages" ` +
      `-H "x-api-key: ${shellEscape(config.apiKey)}" ` +
      `-H "anthropic-version: 2023-06-01" ` +
      `-H "content-type: application/json" ` +
      `-d '{"model":"${shellEscape(model)}","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}' 2>&1`,
      { timeout: 15000 }
    ).toString();
    const parsed = JSON.parse(result);
    if (parsed.type === 'message') return { success: true, detail: `Connected - model: ${parsed.model}` };
    if (parsed.error) return { success: false, error: parsed.error.message || 'API error' };
    return { success: true, detail: 'Connected to Azure AI Foundry' };
  } catch (err) {
    const msg = err.stdout ? err.stdout.toString() : err.message;
    if (/401|403|auth/i.test(msg)) return { success: false, error: 'Authentication failed. Check your credentials.' };
    return { success: false, error: 'Could not reach Azure AI Foundry. Check your endpoint URL and network.' };
  }
}

function testBedrock(config) {
  return { success: true, detail: 'Configuration saved. AWS SSO sign-in will happen after container starts.', skippedAuth: true };
}

function testOpenAI(config) {
  if (!config.apiKey) return { success: false, error: 'API key is required' };
  const baseUrl = config.baseUrl || 'https://api.openai.com/v1';
  try {
    const result = execSync(
      `curl -sf --max-time 10 "${shellEscape(baseUrl)}/models" ` +
      `-H "Authorization: Bearer ${shellEscape(config.apiKey)}" 2>&1`,
      { timeout: 15000 }
    ).toString();
    const parsed = JSON.parse(result);
    if (parsed.data && Array.isArray(parsed.data)) return { success: true, detail: `Connected - ${parsed.data.length} models available` };
    if (parsed.error) return { success: false, error: parsed.error.message || 'API error' };
    return { success: true, detail: 'Connected to OpenAI' };
  } catch (err) {
    const msg = err.stdout ? err.stdout.toString() : err.message;
    if (/invalid.*api.*key|auth/i.test(msg)) return { success: false, error: 'Invalid API key' };
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
    if (parsed.data && Array.isArray(parsed.data)) return { success: true, detail: `Connected - ${parsed.data.length} deployments` };
    if (parsed.error) return { success: false, error: parsed.error.message || 'API error' };
    return { success: true, detail: 'Connected to Azure OpenAI' };
  } catch (err) {
    const msg = err.stdout ? err.stdout.toString() : err.message;
    if (/401|403|auth/i.test(msg)) return { success: false, error: 'Authentication failed. Check your API key.' };
    return { success: false, error: 'Could not reach Azure OpenAI. Check your endpoint and network.' };
  }
}

module.exports = {
  PROVIDER_DEFS,
  getProviderStatus,
  checkPrerequisites,
  configureProvider,
  testProvider,
};
