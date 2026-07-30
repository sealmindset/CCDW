// =============================================================================
// Message rendering.
//
// Claude Code does real work mid-answer -- reads files, runs commands. In a
// terminal that scroll is the point; in a messaging UI it is noise. So a turn
// renders as ordinary chat bubbles with quiet one-line activity chips between
// them ("Read server.js", "Ran ls chat/"), collapsed by default. Click a chip
// to see what it actually did.
// =============================================================================

// Verb + subject for a tool call, so the chip reads like a sentence instead of
// a JSON dump. Anything unrecognised falls back to the bare tool name.
function describeTool(name, input) {
  const i = input || {};
  const base = (p) => String(p || '').split('/').filter(Boolean).pop() || String(p || '');
  switch (name) {
    case 'Bash':          return { verb: 'Ran', subject: i.description || i.command || '' };
    case 'Read':          return { verb: 'Read', subject: base(i.file_path) };
    case 'Edit':          return { verb: 'Edited', subject: base(i.file_path) };
    case 'Write':         return { verb: 'Wrote', subject: base(i.file_path) };
    case 'NotebookEdit':  return { verb: 'Edited notebook', subject: base(i.notebook_path) };
    case 'Glob':          return { verb: 'Found files', subject: i.pattern || '' };
    case 'Grep':          return { verb: 'Searched for', subject: i.pattern || '' };
    case 'WebFetch':      return { verb: 'Fetched', subject: i.url || '' };
    case 'WebSearch':     return { verb: 'Searched the web for', subject: i.query || '' };
    case 'Task':          return { verb: 'Delegated to', subject: i.subagent_type || 'an agent' };
    case 'TodoWrite':     return { verb: 'Updated the plan', subject: '' };
    default:              return { verb: name, subject: '' };
  }
}

function toolDetail(name, input) {
  const i = input || {};
  if (name === 'Bash') return i.command || '';
  if (i.file_path) return i.file_path;
  if (i.pattern) return i.pattern + (i.path ? `  in ${i.path}` : '');
  if (i.url) return i.url;
  if (i.query) return i.query;
  try { return JSON.stringify(i, null, 2); } catch { return ''; }
}

window.ChatView = {
  messagesEl: null,
  inputEl: null,
  sendBtn: null,
  typingEl: null,
  onSend: null,
  _renderTimer: null,
  _turnEl: null,        // container for the whole assistant turn
  _bubbleEl: null,      // the text bubble currently being streamed into
  _bubbleText: '',      // text of that bubble only
  _streamingText: '',   // whole turn's text (Artifacts scans this)
  _chips: {},           // tool_use_id -> chip element

  init(messagesEl, inputEl, sendBtn, typingEl) {
    this.messagesEl = messagesEl;
    this.inputEl = inputEl;
    this.sendBtn = sendBtn;
    this.typingEl = typingEl;

    inputEl.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        this.handleSend();
      }
    });
    sendBtn.addEventListener('click', () => this.handleSend());

    inputEl.addEventListener('input', () => {
      inputEl.style.height = 'auto';
      inputEl.style.height = Math.min(inputEl.scrollHeight, 200) + 'px';
    });
  },

  handleSend() {
    const text = this.inputEl.value.trim();
    if (!text || !this.onSend) return;
    this.inputEl.value = '';
    this.inputEl.style.height = 'auto';
    this.onSend(text);
  },

  // --- User messages -------------------------------------------------------
  addUserMessage(content) {
    const div = document.createElement('div');
    div.className = 'message message-user';
    const bubble = document.createElement('div');
    bubble.className = 'message-bubble';
    bubble.textContent = typeof content === 'string' ? content
      : (content || []).filter(c => c.type === 'text').map(c => c.text).join('\n');

    const images = Array.isArray(content) ? content.filter(c => c.type === 'image') : [];
    for (const img of images) {
      const imgEl = document.createElement('img');
      imgEl.src = `data:${img.source.media_type};base64,${img.source.data}`;
      imgEl.className = 'message-image';
      bubble.appendChild(imgEl);
    }

    div.appendChild(bubble);
    this.messagesEl.appendChild(div);
    this.scrollToBottom();
    return div;
  },

  addSystemNote(text, kind) {
    const div = document.createElement('div');
    div.className = `message-note${kind ? ' note-' + kind : ''}`;
    div.textContent = text;
    this.messagesEl.appendChild(div);
    this.scrollToBottom();
    return div;
  },

  // --- Assistant turns -----------------------------------------------------
  startTurn() {
    this._streamingText = '';
    this._chips = {};
    const turn = document.createElement('div');
    turn.className = 'message message-assistant';
    this.messagesEl.appendChild(turn);
    this._turnEl = turn;
    this._bubbleEl = null;
    this._bubbleText = '';
    this.showTyping(true);
    this.scrollToBottom();
  },

  _ensureBubble() {
    if (this._bubbleEl) return this._bubbleEl;
    const bubble = document.createElement('div');
    bubble.className = 'message-bubble streaming';
    bubble.innerHTML = '<span class="cursor-blink"></span>';
    (this._turnEl || this.messagesEl).appendChild(bubble);
    this._bubbleEl = bubble;
    this._bubbleText = '';
    return bubble;
  },

  // Close the bubble being streamed into, so a chip lands after it rather than
  // inside it. The next delta opens a fresh bubble below the chip.
  _sealBubble() {
    if (this._renderTimer) { clearTimeout(this._renderTimer); this._renderTimer = null; }
    if (this._bubbleEl) {
      if (this._bubbleText.trim()) {
        this._bubbleEl.innerHTML = window.renderMarkdown(this._bubbleText);
        this._bubbleEl.classList.remove('streaming');
      } else {
        this._bubbleEl.remove();  // tool ran before any prose -- drop the stub
      }
    }
    this._bubbleEl = null;
    this._bubbleText = '';
  },

  appendStreamText(text) {
    // Open the bubble first: _ensureBubble resets _bubbleText when it creates
    // one, so appending before this would swallow the first delta.
    this._ensureBubble();
    this._streamingText += text;
    this._bubbleText += text;
    if (this._renderTimer) return;
    this._renderTimer = setTimeout(() => {
      this._renderTimer = null;
      if (this._bubbleEl) {
        this._bubbleEl.innerHTML = window.renderMarkdown(this._bubbleText) + '<span class="cursor-blink"></span>';
        this.scrollToBottom();
      }
    }, 50);
  },

  addToolCall(id, name, input, state) {
    this._sealBubble();
    const chip = this._buildChip(name, input, state || 'running');
    (this._turnEl || this.messagesEl).appendChild(chip);
    if (id) this._chips[id] = chip;
    this.scrollToBottom();
    return chip;
  },

  _buildChip(name, input, state) {
    const { verb, subject } = describeTool(name, input);

    const chip = document.createElement('div');
    chip.className = `tool-chip tool-${state}`;

    const head = document.createElement('button');
    head.className = 'tool-chip-head';
    head.type = 'button';

    const dot = document.createElement('span');
    dot.className = 'tool-dot';

    const label = document.createElement('span');
    label.className = 'tool-label';
    label.textContent = verb;

    const subj = document.createElement('code');
    subj.className = 'tool-subject';
    subj.textContent = subject;

    head.append(dot, label);
    if (subject) head.appendChild(subj);

    const body = document.createElement('div');
    body.className = 'tool-chip-body';
    const detail = toolDetail(name, input);
    if (detail) {
      const pre = document.createElement('pre');
      pre.className = 'tool-input';
      pre.textContent = detail;
      body.appendChild(pre);
    }

    head.addEventListener('click', () => chip.classList.toggle('expanded'));
    chip.append(head, body);
    return chip;
  },

  resolveToolCall(id, isError, content, truncated) {
    const chip = this._chips[id];
    if (!chip) return;
    chip.classList.remove('tool-running');
    chip.classList.add(isError ? 'tool-error' : 'tool-done');
    if (content) {
      const pre = document.createElement('pre');
      pre.className = 'tool-output';
      pre.textContent = truncated ? content + '\n…(truncated)' : content;
      chip.querySelector('.tool-chip-body').appendChild(pre);
    }
  },

  finishTurn(usage) {
    this._sealBubble();
    if (this._turnEl && usage) {
      const badge = document.createElement('div');
      badge.className = 'token-badge';
      badge.textContent = `${usage.input_tokens ?? 0}→${usage.output_tokens ?? 0} tokens`;
      this._turnEl.appendChild(badge);
    }
    // A turn that produced nothing renderable would leave an empty gap.
    if (this._turnEl && !this._turnEl.childElementCount) this._turnEl.remove();
    this._turnEl = null;
    this._streamingText = '';
    this._chips = {};
    this.showTyping(false);
  },

  showTyping(show, label) {
    if (!this.typingEl) return;
    this.typingEl.style.display = show ? 'flex' : 'none';
    const text = this.typingEl.querySelector('.typing-text');
    if (text) text.textContent = label || 'Claude is working...';
  },

  setInputEnabled(enabled) {
    this.inputEl.disabled = !enabled;
    this.sendBtn.disabled = !enabled;
    if (enabled) this.inputEl.focus();
  },

  clear() {
    this.messagesEl.innerHTML = '';
    this._turnEl = null;
    this._bubbleEl = null;
    this._chips = {};
  },

  // Replay a stored conversation with the same shape it had while streaming.
  loadMessages(messages) {
    this.clear();
    const chips = {};

    for (const msg of messages) {
      const blocks = Array.isArray(msg.content) ? msg.content
        : [{ type: 'text', text: String(msg.content || '') }];

      if (msg.role === 'user') {
        const results = blocks.filter(b => b.type === 'tool_result');
        if (results.length && results.length === blocks.length) {
          // Plumbing, not a message: attach each result to its chip.
          for (const r of results) {
            const chip = chips[r.tool_use_id];
            if (!chip) continue;
            const text = typeof r.content === 'string' ? r.content
              : (r.content || []).filter(c => c.type === 'text').map(c => c.text).join('\n');
            chip.classList.remove('tool-running');
            chip.classList.add(r.is_error ? 'tool-error' : 'tool-done');
            if (text) {
              const pre = document.createElement('pre');
              pre.className = 'tool-output';
              pre.textContent = text;
              chip.querySelector('.tool-chip-body').appendChild(pre);
            }
          }
          continue;
        }
        this.addUserMessage(blocks);
        continue;
      }

      // Assistant: rebuild the bubble/chip sequence in order.
      const turn = document.createElement('div');
      turn.className = 'message message-assistant';
      for (const b of blocks) {
        if (b.type === 'text' && b.text && b.text.trim()) {
          const bubble = document.createElement('div');
          bubble.className = 'message-bubble';
          bubble.innerHTML = window.renderMarkdown(b.text);
          turn.appendChild(bubble);
        } else if (b.type === 'tool_use') {
          const chip = this._buildChip(b.name, b.input, 'done');
          chips[b.id] = chip;
          turn.appendChild(chip);
        }
      }
      if (msg.usage) {
        const badge = document.createElement('div');
        badge.className = 'token-badge';
        badge.textContent = `${msg.usage.input_tokens ?? 0}→${msg.usage.output_tokens ?? 0} tokens`;
        turn.appendChild(badge);
      }
      if (turn.childElementCount) this.messagesEl.appendChild(turn);
    }
    this.scrollToBottom();
  },

  scrollToBottom() {
    this.messagesEl.scrollTop = this.messagesEl.scrollHeight;
  },
};
