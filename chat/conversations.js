const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const HOME = process.env.HOME || '/home/coder';
const CONV_DIR = path.join(HOME, '.claude', 'chat', 'conversations');

function ensureDir() {
  if (!fs.existsSync(CONV_DIR)) fs.mkdirSync(CONV_DIR, { recursive: true });
}

// Tool results are stored in Anthropic's native shape -- a `user` message whose
// blocks are all tool_result. Those are plumbing, not turns: they must not be
// counted in the sidebar or shown as a message the person typed.
function isToolResultOnly(msg) {
  const blocks = Array.isArray(msg.content) ? msg.content : [];
  return blocks.length > 0 && blocks.every(b => b.type === 'tool_result');
}

function filePath(id) {
  return path.join(CONV_DIR, `${id}.json`);
}

function list() {
  ensureDir();
  const files = fs.readdirSync(CONV_DIR).filter(f => f.endsWith('.json'));
  const convos = [];
  for (const f of files) {
    try {
      const data = JSON.parse(fs.readFileSync(path.join(CONV_DIR, f), 'utf-8'));
      convos.push({
        id: data.id,
        title: data.title || 'New conversation',
        created_at: data.created_at,
        updated_at: data.updated_at,
        starred: data.starred || false,
        model: data.model,
        cwd: data.cwd || null,
        message_count: (data.messages || []).filter(m => !isToolResultOnly(m)).length,
      });
    } catch {}
  }
  convos.sort((a, b) => new Date(b.updated_at) - new Date(a.updated_at));
  return convos;
}

function create(model, systemPrompt, cwd) {
  ensureDir();
  // This UUID is handed to `claude --session-id`, so the conversation and the
  // Claude Code session are one and the same -- `claude --resume <id>` in the
  // terminal continues this exact thread.
  const id = crypto.randomUUID();
  const now = new Date().toISOString();
  const conv = {
    id,
    title: 'New conversation',
    created_at: now,
    updated_at: now,
    starred: false,
    model: model || null,
    cwd: cwd || null,
    system_prompt: systemPrompt || '',
    // Set once the CLI has actually created the session on disk; until then a
    // turn must use --session-id rather than --resume.
    session_started: false,
    messages: [],
    total_tokens: { input: 0, output: 0 },
  };
  fs.writeFileSync(filePath(id), JSON.stringify(conv, null, 2));
  return conv;
}

function get(id) {
  const fp = filePath(id);
  if (!fs.existsSync(fp)) return null;
  return JSON.parse(fs.readFileSync(fp, 'utf-8'));
}

function save(conv) {
  conv.updated_at = new Date().toISOString();
  fs.writeFileSync(filePath(conv.id), JSON.stringify(conv, null, 2));
}

function update(id, fields) {
  const conv = get(id);
  if (!conv) return null;
  if (fields.title !== undefined) conv.title = fields.title;
  if (fields.starred !== undefined) conv.starred = fields.starred;
  if (fields.system_prompt !== undefined) conv.system_prompt = fields.system_prompt;
  if (fields.model !== undefined) conv.model = fields.model;
  if (fields.cwd !== undefined) conv.cwd = fields.cwd;
  if (fields.session_started !== undefined) conv.session_started = fields.session_started;
  save(conv);
  return conv;
}

function remove(id) {
  const fp = filePath(id);
  if (fs.existsSync(fp)) fs.unlinkSync(fp);
}

function addMessage(id, role, content, meta) {
  const conv = get(id);
  if (!conv) return null;
  const msg = {
    role,
    content: typeof content === 'string' ? [{ type: 'text', text: content }] : content,
    timestamp: new Date().toISOString(),
    ...meta,
  };
  conv.messages.push(msg);
  if (meta && meta.usage) {
    conv.total_tokens.input += meta.usage.input_tokens || 0;
    conv.total_tokens.output += meta.usage.output_tokens || 0;
  }
  save(conv);
  return msg;
}

function exportMarkdown(id) {
  const conv = get(id);
  if (!conv) return null;
  let md = `# ${conv.title}\n\n`;
  md += `*Created: ${conv.created_at}*\n`;
  if (conv.model) md += `*Model: ${conv.model}*\n`;
  if (conv.cwd) md += `*Folder: ${conv.cwd}*\n`;
  md += '\n---\n\n';
  for (const msg of conv.messages) {
    if (isToolResultOnly(msg)) continue;
    const role = msg.role === 'user' ? 'You' : 'Claude';
    const blocks = Array.isArray(msg.content) ? msg.content : [];
    const parts = [];
    for (const b of blocks) {
      if (b.type === 'text') parts.push(b.text);
      // Actions taken are part of the record, but the arguments are noise in a
      // shared transcript -- name the tool and move on.
      else if (b.type === 'tool_use') parts.push(`_(used ${b.name})_`);
    }
    md += `**${role}:**\n\n${parts.join('\n\n')}\n\n---\n\n`;
  }
  return md;
}

module.exports = { list, create, get, save, update, remove, addMessage, exportMarkdown, isToolResultOnly };
