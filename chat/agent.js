// =============================================================================
// Claude Code driver for Chat.
//
// Chat used to be a thin Messages API client: it could talk, but it could not
// read a file, run a command, or remember anything the terminal knew. This
// module replaces that engine with the real CLI, the same way Workshop does
// (see workshop/server.js spawnCLI), so a Chat conversation has the full tool
// set against the mounted host folders.
//
// Two things make a Chat conversation and a Claude Code session the same object:
//
//   * the conversation UUID is passed as --session-id on the first turn, so the
//     CLI writes its transcript to ~/.claude/projects/<slug>/<convId>.jsonl
//   * every later turn is --resume <convId>
//
// which means `claude --resume <convId>` in the web terminal picks up exactly
// where the browser left off, and vice versa. Nothing is duplicated or synced.
//
// `claude -p` is single-turn: one process per user message, then it exits. That
// maps cleanly onto one HTTP request holding one SSE stream, which is why this
// keeps the existing SSE transport instead of introducing a WebSocket.
// =============================================================================

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const providers = require('./providers');

// Alpine's ARG_MAX is 128KB; anything close to it goes in over stdin instead.
const ARG_MAX_THRESHOLD = 120000;

// Tool results can be enormous (a full file read). Cap what crosses the wire to
// the browser -- the model already has the whole thing.
const RESULT_PREVIEW = 4000;

function freshEnv() {
  // Re-read settings.json on every spawn so a provider or model reconfigured
  // after the chat server started is picked up without a restart.
  return { ...process.env, ...providers.readSettingsEnv(), NO_COLOR: '1' };
}

function buildArgs({ prompt, sessionId, resume, model, systemPrompt, useStdin }) {
  const args = [];
  if (useStdin) args.push('-p');
  else args.push('-p', prompt || '');

  args.push('--verbose', '--output-format', 'stream-json');
  // Without this the CLI emits whole assistant blocks at once and the UI sits
  // blank until the turn finishes. With it we get real token-by-token deltas.
  args.push('--include-partial-messages');
  args.push('--permission-mode', 'bypassPermissions');

  if (resume) args.push('--resume', sessionId);
  else args.push('--session-id', sessionId);

  if (model) args.push('--model', model);
  if (systemPrompt) args.push('--append-system-prompt', systemPrompt);
  return args;
}

/**
 * Run one turn.
 *
 * @param {Object}   opts
 * @param {string}   opts.sessionId    conversation UUID == Claude session id
 * @param {boolean}  opts.resume       false on the first turn of a conversation
 * @param {string}   opts.cwd          working directory for the turn
 * @param {string}   opts.prompt       the user's message
 * @param {string}   [opts.model]      model id, passed through to --model
 * @param {string}   [opts.systemPrompt]
 * @param {Function} opts.onEvent      (eventName, data) => void
 * @param {Function} opts.onDone       ({ blocks, usage, error }) => void
 * @returns {ChildProcess}
 */
function runTurn(opts) {
  const { sessionId, resume, cwd, prompt, model, systemPrompt, onEvent, onDone } = opts;

  const promptBytes = Buffer.byteLength(prompt || '', 'utf-8');
  const useStdin = promptBytes > ARG_MAX_THRESHOLD;
  const args = buildArgs({ prompt, sessionId, resume, model, systemPrompt, useStdin });

  let proc;
  try {
    proc = spawn('claude', args, {
      cwd,
      env: freshEnv(),
      stdio: [useStdin ? 'pipe' : 'ignore', 'pipe', 'pipe'],
    });
  } catch (e) {
    onEvent('chat:error', { message: `Failed to start Claude Code: ${e.message}` });
    onDone({ messages: [], usage: null, error: e.message, started: false });
    return null;
  }

  if (useStdin) {
    proc.stdin.end(prompt || '', 'utf-8');
  }

  // Everything the turn produced, in Anthropic message shape and in the order
  // it happened -- a turn can be assistant/tool_result/assistant/... and the
  // reloaded conversation has to read the same as the live one did.
  const turnMessages = [];
  let usage = null;
  let resultError = null;
  let sawInit = false;
  let stderrTail = '';
  let buf = '';

  function emitLine(line) {
    let event;
    try { event = JSON.parse(line); } catch { return; }

    switch (event.type) {
      case 'system':
        if (event.subtype === 'init') {
          sawInit = true;
          onEvent('agent:init', {
            session_id: event.session_id,
            model: event.model,
            cwd: event.cwd,
            tools: (event.tools || []).length,
            permission_mode: event.permissionMode,
          });
        } else if (event.subtype === 'status') {
          onEvent('agent:status', { status: event.status });
        }
        // hook_started / hook_response are noise for a chat UI.
        break;

      case 'stream_event': {
        // Raw Anthropic SSE events. Forwarded under their own names so the
        // existing browser streaming code handles them without translation.
        const inner = event.event;
        if (!inner || !inner.type) break;
        if (inner.type === 'message_delta' && inner.usage) usage = inner.usage;
        onEvent(inner.type, inner);
        break;
      }

      case 'assistant': {
        // The settled version of the blocks that just streamed. Persisted from
        // here rather than by re-accumulating deltas.
        const blocks = event.message?.content || [];
        if (blocks.length) turnMessages.push({ role: 'assistant', content: blocks });
        for (const block of blocks) {
          if (block.type === 'tool_use') {
            onEvent('agent:tool_use', { id: block.id, name: block.name, input: block.input });
          }
        }
        break;
      }

      case 'user': {
        const results = (event.message?.content || []).filter(b => b.type === 'tool_result');
        if (results.length) turnMessages.push({ role: 'user', content: results });
        for (const block of results) {
          const text = typeof block.content === 'string'
            ? block.content
            : (block.content || []).filter(c => c.type === 'text').map(c => c.text).join('\n');
          onEvent('agent:tool_result', {
            tool_use_id: block.tool_use_id,
            is_error: !!block.is_error,
            content: (text || '').slice(0, RESULT_PREVIEW),
            truncated: (text || '').length > RESULT_PREVIEW,
          });
        }
        break;
      }

      case 'result':
        if (event.usage) usage = event.usage;
        if (event.is_error) resultError = event.result || 'Claude Code reported an error';
        onEvent('agent:result', {
          usage: event.usage || null,
          cost_usd: event.total_cost_usd || 0,
          duration_ms: event.duration_ms || 0,
          num_turns: event.num_turns || 0,
          is_error: !!event.is_error,
        });
        break;
    }
  }

  proc.stdout.on('data', (chunk) => {
    buf += chunk.toString();
    let idx;
    while ((idx = buf.indexOf('\n')) !== -1) {
      const line = buf.slice(0, idx).trim();
      buf = buf.slice(idx + 1);
      if (line) emitLine(line);
    }
  });

  proc.stderr.on('data', (chunk) => {
    // Keep only the tail: this is diagnostic, and some tools are chatty.
    stderrTail = (stderrTail + chunk.toString()).slice(-2000);
  });

  proc.on('error', (err) => {
    const message = err.code === 'ENOENT'
      ? 'Claude Code CLI not found in the container.'
      : `Failed to start Claude Code: ${err.message}`;
    onEvent('chat:error', { message });
    onDone({ messages: turnMessages, usage, error: message, started: sawInit });
  });

  proc.on('close', (code) => {
    if (buf.trim()) emitLine(buf.trim());

    let error = resultError;
    if (!error && code !== 0 && !sawInit) {
      // Never started properly -- stderr is the only useful thing we have.
      error = friendlyStderr(stderrTail) || `Claude Code exited with code ${code}`;
    }
    if (error) onEvent('chat:error', { message: error });
    onDone({ messages: turnMessages, usage, error, started: sawInit });
  });

  return proc;
}

// The CLI's stderr on an auth failure is long and unactionable in a browser.
function friendlyStderr(text) {
  if (!text) return '';
  if (/Azure token expired|az login|AADSTS/i.test(text)) {
    return 'Azure sign-in expired. Open the Web Terminal and run: az login --use-device-code';
  }
  if (/expired.*sso|Token has expired/i.test(text)) {
    return 'AWS session expired. Open the Web Terminal and run: login';
  }
  if (/authentication_failed|401|invalid.*api.?key/i.test(text)) {
    return 'Provider rejected the credentials. Check the Dashboard provider status.';
  }
  const lines = text.trim().split('\n').filter(Boolean);
  return lines.length ? lines[lines.length - 1].slice(0, 300) : '';
}

/**
 * Is a session actually resumable? The transcript lives on disk under a slug of
 * the working directory; if the conversation record says a session exists but
 * the file is gone (volume reset, cwd changed), --resume fails hard and the
 * turn is lost. Falling back to a fresh session is better than an error.
 */
function sessionExists(sessionId, cwd) {
  const home = process.env.HOME || os.homedir();
  const projects = path.join(home, '.claude', 'projects');
  const slug = String(cwd).replace(/[/.]/g, '-');
  const direct = path.join(projects, slug, `${sessionId}.jsonl`);
  if (fs.existsSync(direct)) return true;
  // The slug rule has changed across CLI versions; scan as a fallback.
  try {
    for (const dir of fs.readdirSync(projects)) {
      if (fs.existsSync(path.join(projects, dir, `${sessionId}.jsonl`))) return true;
    }
  } catch { /* no projects dir yet */ }
  return false;
}

module.exports = { runTurn, sessionExists };
