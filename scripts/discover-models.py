#!/usr/bin/env python3
# =============================================================================
# Claude Code Docker - Model Discovery
#
# Asks each provider what models it actually has, instead of relying on the
# hand-edited lists in config/providers.yml. Writes a cache that
# configure-provider.sh prefers over the YAML:
#
#     /home/coder/.claude/models-cache.json
#
# Discovery is best-effort and bounded by a wall-clock deadline. Any provider
# that can't be reached (no network, expired token, no credentials) falls back
# to the values baked into providers.yml, so a cold/offline start still boots
# with a working configuration.
#
# Per-provider strategy -- they are NOT the same shape:
#
#   api-key / claude   GET /v1/models on api.anthropic.com. A real model list.
#   bedrock            `aws bedrock list-inference-profiles`. Bedrock has no
#                      Models API; inference profiles are what Claude Code
#                      actually invokes, and they reflect account model access.
#   azure-foundry      No list API at all -- Foundry exposes admin-created
#                      DEPLOYMENT names, not upstream model ids. We probe:
#                      deployment names here are "<prefix><anthropic-model-id>",
#                      so the candidate list comes from the Anthropic result and
#                      each candidate is confirmed with a 1-token request.
#
# Usage:
#   discover-models.py                 write the cache (used at container start)
#   discover-models.py --print         write nothing, dump the result as JSON
#   discover-models.py --emit-yaml     print a providers.yml with discovered
#                                      models merged in, for committing to git
# =============================================================================

import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

CONFIG_FILE = os.environ.get('CCDW_PROVIDERS_YML', '/opt/claude-code-docker/config/providers.yml')
CACHE_FILE = os.environ.get('CCDW_MODELS_CACHE', '/home/coder/.claude/models-cache.json')
CREDENTIALS_FILE = os.path.expanduser('~/.claude/.credentials.json')
ANTHROPIC_API = 'https://api.anthropic.com/v1/models?limit=100'
ANTHROPIC_VERSION = '2023-06-01'

# Total wall-clock budget. Container start blocks on this, so keep it small --
# every provider check is skipped once the deadline passes.
DEADLINE = float(os.environ.get('CCDW_DISCOVER_TIMEOUT', '25'))
_started = time.time()

FAMILIES = ('fable', 'mythos', 'opus', 'sonnet', 'haiku')

# Last-resort catalog: used only when NO provider could be reached and there is
# nothing in providers.yml either. Keeping it small is deliberate -- it exists
# so the Foundry probe has candidates on a machine with no Anthropic key, not
# as a list anyone should be maintaining by hand.
FALLBACK_CATALOG = [
    'claude-opus-5',
    'claude-opus-4-8',
    'claude-sonnet-5',
    'claude-sonnet-4-6',
    'claude-haiku-4-5',
]


def budget_left():
    return DEADLINE - (time.time() - _started)


def log(msg):
    sys.stderr.write('[discover-models] %s\n' % msg)


# ---------------------------------------------------------------------------
# Model id parsing
#
# Every provider decorates the same underlying id differently:
#   claude-opus-5
#   us.anthropic.claude-opus-4-6-v1:0
#   cogdep-aifoundry-dev-eus2-claude-opus-5
# so family + version are recovered by regex rather than by string equality.
# ---------------------------------------------------------------------------
MODEL_RE = re.compile(r'claude[-.](%s)-(\d+)(?:[-.](\d+))?' % '|'.join(FAMILIES))


def parse_model(model_id):
    m = MODEL_RE.search(model_id)
    if not m:
        return None
    family, major, minor = m.group(1), int(m.group(2)), int(m.group(3) or 0)
    return {'family': family, 'major': major, 'minor': minor}


def core_id(model_id):
    """The bare anthropic-style id inside a decorated one, e.g.
    'cogdep-...-claude-opus-5' -> 'claude-opus-5'. Used to line providers up."""
    m = MODEL_RE.search(model_id)
    return model_id[m.start():] if m else model_id


def rank(model_id):
    """Sort key: newer is greater. Unparseable ids sort last."""
    p = parse_model(model_id)
    if not p:
        return (-1, -1)
    return (p['major'], p['minor'])


def display_name(model_id):
    p = parse_model(model_id)
    if not p:
        return model_id
    version = str(p['major']) if p['minor'] == 0 else '%d.%d' % (p['major'], p['minor'])
    return 'Claude %s %s' % (p['family'].capitalize(), version)


def pick_slots(model_ids):
    """Newest model per family -> the three slots Claude Code reads.

    Claude Code only honours ANTHROPIC_DEFAULT_{SONNET,HAIKU,OPUS}_MODEL, so
    the full discovered list can be offered in the UI but only three ids can be
    wired into the environment. Fable/Mythos fall into the opus slot only if
    nothing in the opus family was found."""
    slots = {}
    for family in ('sonnet', 'haiku', 'opus'):
        candidates = [m for m in model_ids if (parse_model(m) or {}).get('family') == family]
        if candidates:
            slots[family] = max(candidates, key=rank)
    if 'opus' not in slots:
        premium = [m for m in model_ids if (parse_model(m) or {}).get('family') in ('fable', 'mythos')]
        if premium:
            slots['opus'] = max(premium, key=rank)
    return slots


def as_entries(model_ids):
    """Full model list for the picker, newest first."""
    seen, out = set(), []
    for mid in sorted(set(model_ids), key=rank, reverse=True):
        if mid in seen:
            continue
        seen.add(mid)
        p = parse_model(mid) or {}
        out.append({
            'id': mid,
            'family': p.get('family', 'other'),
            'display_name': display_name(mid),
        })
    return out


# ---------------------------------------------------------------------------
# Provider: Anthropic first-party (api-key + OAuth)
# The only provider with a genuine Models API.
# ---------------------------------------------------------------------------
def anthropic_credentials():
    key = os.environ.get('ANTHROPIC_API_KEY')
    if key:
        return {'x-api-key': key}
    # OAuth sessions keep a bearer token in the Claude Code credentials file.
    try:
        with open(CREDENTIALS_FILE) as f:
            creds = json.load(f)
        token = creds.get('claudeAiOauth', {}).get('accessToken')
        if token:
            return {'Authorization': 'Bearer ' + token}
    except Exception:
        pass
    return None


def discover_anthropic():
    headers = anthropic_credentials()
    if not headers:
        return None, 'no credentials'
    timeout = min(8, budget_left())
    if timeout <= 0:
        return None, 'out of time'
    req = urllib.request.Request(ANTHROPIC_API)
    req.add_header('anthropic-version', ANTHROPIC_VERSION)
    for k, v in headers.items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.load(resp)
    except Exception as e:
        return None, str(e)
    ids = [m['id'] for m in data.get('data', []) if parse_model(m.get('id', ''))]
    if not ids:
        return None, 'empty model list'
    return ids, 'api'


# ---------------------------------------------------------------------------
# Provider: AWS Bedrock
# No Models API. Inference profiles are the ids Claude Code invokes and they
# only appear once the account has been granted access to the model.
# ---------------------------------------------------------------------------
def discover_bedrock(region, profile):
    timeout = min(12, budget_left())
    if timeout <= 0:
        return None, 'out of time'
    cmd = ['aws', 'bedrock', 'list-inference-profiles',
           '--region', region, '--output', 'json']
    if profile:
        cmd += ['--profile', profile]
    try:
        proc = subprocess.run(cmd, capture_output=True, timeout=timeout, check=True)
        data = json.loads(proc.stdout)
    except subprocess.CalledProcessError as e:
        # The raw CalledProcessError repr is the whole argv; surface the AWS
        # error line instead, since this string is shown in the Dashboard.
        err = (e.stderr or b'').decode('utf8', 'replace').strip().splitlines()
        return None, (err[-1][:160] if err else 'aws cli returned %d' % e.returncode)
    except subprocess.TimeoutExpired:
        return None, 'aws cli timed out'
    except FileNotFoundError:
        return None, 'aws cli not installed'
    except Exception as e:
        return None, str(e)[:160] or 'aws call failed'
    ids = []
    for p in data.get('inferenceProfileSummaries', []):
        pid = p.get('inferenceProfileId', '')
        if 'anthropic.claude' in pid and parse_model(pid):
            ids.append(pid)
    if not ids:
        return None, 'no anthropic inference profiles'
    return ids, 'aws'


# ---------------------------------------------------------------------------
# Provider: Azure AI Foundry
# Deployment names are created by an admin and there is no list endpoint on the
# gateway, so the only honest discovery is: derive the naming prefix from the
# names already configured, then confirm each candidate with a real request.
# ---------------------------------------------------------------------------
def foundry_prefix(configured_models):
    """'cogdep-aifoundry-dev-eus2-claude-opus-5' -> 'cogdep-aifoundry-dev-eus2-'"""
    for name in configured_models:
        m = MODEL_RE.search(name)
        if m:
            return name[:m.start()]
    return ''


def azure_token(resource):
    timeout = min(10, budget_left())
    if timeout <= 0:
        return None
    try:
        out = subprocess.run(
            ['az', 'account', 'get-access-token', '--resource', resource,
             '--query', 'accessToken', '-o', 'tsv'],
            capture_output=True, timeout=timeout, check=True).stdout
        return out.decode().strip() or None
    except Exception:
        return None


def foundry_deployment_exists(endpoint, deployment, token):
    """One-token request. 404 means the deployment isn't there; anything else
    (200, 400, 429) means the gateway routed it, so it exists."""
    timeout = min(6, budget_left())
    if timeout <= 0:
        return None
    body = json.dumps({
        'model': deployment,
        'max_tokens': 1,
        'messages': [{'role': 'user', 'content': 'hi'}],
    }).encode()
    req = urllib.request.Request(endpoint.rstrip('/') + '/v1/messages', data=body, method='POST')
    req.add_header('Content-Type', 'application/json')
    req.add_header('anthropic-version', ANTHROPIC_VERSION)
    req.add_header('Authorization', 'Bearer ' + token)
    try:
        urllib.request.urlopen(req, timeout=timeout)
        return True
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return False
        if e.code in (401, 403):
            return None  # auth problem, not a statement about the deployment
        return True
    except Exception:
        return None


def discover_foundry(endpoint, token_resource, configured_models, candidate_core_ids):
    prefix = foundry_prefix(configured_models)
    if not prefix or not candidate_core_ids:
        return None, 'no naming prefix or candidates'
    token = azure_token(token_resource)
    if not token:
        return None, 'not signed in to azure'
    found, unknown = [], 0
    # Newest first, so a tight budget still confirms the models people want.
    for core in sorted(set(candidate_core_ids), key=rank, reverse=True):
        if budget_left() <= 2:
            break
        exists = foundry_deployment_exists(endpoint, prefix + core, token)
        if exists is True:
            found.append(prefix + core)
        elif exists is None:
            unknown += 1
            if unknown >= 3:
                return None, 'endpoint unreachable'
    if not found:
        return None, 'no deployments matched'
    return found, 'probe'


# ---------------------------------------------------------------------------
# Cache assembly
# ---------------------------------------------------------------------------
def load_yaml():
    try:
        import yaml
        with open(CONFIG_FILE) as f:
            return yaml.safe_load(f) or {}
    except Exception as e:
        log('cannot read %s: %s' % (CONFIG_FILE, e))
        return {}


def fallback_entry(cfg_models, default_model, reason):
    ids = [v for v in (cfg_models or {}).values() if v]
    return {
        'source': 'fallback',
        'reason': reason,
        'models': as_entries(ids),
        'slots': dict(cfg_models or {}),
        'default_model': default_model,
    }


def discovered_entry(ids, source, default_model, cfg_models):
    slots = pick_slots(ids)
    # Never regress: keep a configured slot the provider didn't report.
    for k, v in (cfg_models or {}).items():
        slots.setdefault(k, v)
    return {
        'source': source,
        'models': as_entries(ids),
        'slots': slots,
        'default_model': default_model,
    }


def build():
    cfg = load_yaml()
    providers = cfg.get('providers', {}) or {}
    result = {'generated_at': int(time.time()), 'providers': {}}

    # Anthropic first -- its result seeds the Foundry candidate list.
    anthropic_ids, anthropic_source = discover_anthropic()
    if anthropic_ids:
        log('anthropic: %d models via %s' % (len(anthropic_ids), anthropic_source))
    else:
        log('anthropic: fallback (%s)' % anthropic_source)

    for key in ('api-key', 'claude'):
        if key not in providers:
            continue
        cfg_models = providers[key].get('models') or {}
        default_model = providers[key].get('default_model') or 'opus'
        if anthropic_ids:
            result['providers'][key] = discovered_entry(
                anthropic_ids, 'anthropic-api', default_model, cfg_models)
        else:
            result['providers'][key] = fallback_entry(cfg_models, default_model, anthropic_source)

    if 'bedrock' in providers:
        b = providers['bedrock']
        cfg_models = b.get('models') or {}
        default_model = b.get('default_model') or 'sonnet'
        region = os.environ.get('AWS_REGION') or b.get('region') or 'us-east-1'
        profile = os.environ.get('AWS_PROFILE') or b.get('profile') or 'sso-bedrock-model-access'
        ids, source = discover_bedrock(region, profile)
        if ids:
            log('bedrock: %d inference profiles' % len(ids))
            result['providers']['bedrock'] = discovered_entry(ids, 'bedrock-api', default_model, cfg_models)
        else:
            log('bedrock: fallback (%s)' % source)
            result['providers']['bedrock'] = fallback_entry(cfg_models, default_model, source)

    if 'azure-foundry' in providers:
        f = providers['azure-foundry']
        cfg_models = f.get('models') or {}
        default_model = f.get('default_model') or 'opus'
        endpoint = os.environ.get('ANTHROPIC_FOUNDRY_BASE_URL') or f.get('endpoint') or ''
        token_resource = f.get('token_resource') or 'https://cognitiveservices.azure.com'
        candidates = [core_id(m) for m in (anthropic_ids or FALLBACK_CATALOG)]
        candidates += [core_id(v) for v in cfg_models.values() if v]
        if endpoint:
            ids, source = discover_foundry(endpoint, token_resource, list(cfg_models.values()), candidates)
        else:
            ids, source = None, 'no endpoint'
        if ids:
            log('foundry: %d deployments confirmed' % len(ids))
            result['providers']['azure-foundry'] = discovered_entry(ids, 'foundry-probe', default_model, cfg_models)
        else:
            log('foundry: fallback (%s)' % source)
            result['providers']['azure-foundry'] = fallback_entry(cfg_models, default_model, source)

    return result


def write_cache(data):
    d = os.path.dirname(CACHE_FILE)
    if d:
        os.makedirs(d, exist_ok=True)
    tmp = CACHE_FILE + '.tmp'
    with open(tmp, 'w') as f:
        json.dump(data, f, indent=2)
    os.replace(tmp, CACHE_FILE)  # atomic: a reader never sees a half-written cache


def emit_yaml(data):
    """Print providers.yml with discovered slots merged in, so the repo copy can
    be brought back in line with reality and committed."""
    try:
        import yaml
    except Exception:
        log('pyyaml unavailable')
        return 1
    with open(CONFIG_FILE) as f:
        cfg = yaml.safe_load(f) or {}
    for key, entry in data.get('providers', {}).items():
        if entry.get('source') == 'fallback':
            continue
        cfg.setdefault('providers', {}).setdefault(key, {})['models'] = entry['slots']
    sys.stdout.write(yaml.safe_dump(cfg, sort_keys=False, default_flow_style=False))
    return 0


def main():
    args = sys.argv[1:]
    data = build()
    if '--emit-yaml' in args:
        return emit_yaml(data)
    if '--print' in args:
        print(json.dumps(data, indent=2))
        return 0
    write_cache(data)
    log('wrote %s' % CACHE_FILE)
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as e:
        # Discovery must never block container start.
        log('failed: %s' % e)
        sys.exit(0)
