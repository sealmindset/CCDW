window.ChatView = {
  messagesEl: null,
  inputEl: null,
  sendBtn: null,
  typingEl: null,
  onSend: null,
  _renderTimer: null,
  _streamingEl: null,
  _streamingText: '',

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

  addMessage(role, content, meta) {
    const div = document.createElement('div');
    div.className = `message message-${role}`;

    const bubble = document.createElement('div');
    bubble.className = 'message-bubble';

    if (role === 'assistant') {
      const text = typeof content === 'string' ? content
        : content.filter(c => c.type === 'text').map(c => c.text).join('\n');
      bubble.innerHTML = window.renderMarkdown(text);
    } else {
      const text = typeof content === 'string' ? content
        : content.filter(c => c.type === 'text').map(c => c.text).join('\n');
      bubble.textContent = text;

      // Render image attachments
      const images = Array.isArray(content) ? content.filter(c => c.type === 'image') : [];
      for (const img of images) {
        const imgEl = document.createElement('img');
        imgEl.src = `data:${img.source.media_type};base64,${img.source.data}`;
        imgEl.className = 'message-image';
        bubble.appendChild(imgEl);
      }
    }

    if (meta && meta.usage) {
      const badge = document.createElement('div');
      badge.className = 'token-badge';
      badge.textContent = `${meta.usage.input_tokens}→${meta.usage.output_tokens} tokens`;
      div.appendChild(bubble);
      div.appendChild(badge);
    } else {
      div.appendChild(bubble);
    }

    this.messagesEl.appendChild(div);
    this.scrollToBottom();
    return div;
  },

  startStreaming() {
    this._streamingText = '';
    const div = document.createElement('div');
    div.className = 'message message-assistant';
    const bubble = document.createElement('div');
    bubble.className = 'message-bubble streaming';
    bubble.innerHTML = '<span class="cursor-blink"></span>';
    div.appendChild(bubble);
    this.messagesEl.appendChild(div);
    this._streamingEl = bubble;
    this.showTyping(true);
    this.scrollToBottom();
  },

  appendStreamText(text) {
    this._streamingText += text;
    if (this._renderTimer) return;
    this._renderTimer = setTimeout(() => {
      this._renderTimer = null;
      if (this._streamingEl) {
        this._streamingEl.innerHTML = window.renderMarkdown(this._streamingText) + '<span class="cursor-blink"></span>';
        this.scrollToBottom();
      }
    }, 50);
  },

  finishStreaming(usage) {
    if (this._renderTimer) {
      clearTimeout(this._renderTimer);
      this._renderTimer = null;
    }
    if (this._streamingEl) {
      this._streamingEl.innerHTML = window.renderMarkdown(this._streamingText);
      this._streamingEl.classList.remove('streaming');
      if (usage) {
        const badge = document.createElement('div');
        badge.className = 'token-badge';
        badge.textContent = `${usage.input_tokens}→${usage.output_tokens} tokens`;
        this._streamingEl.parentElement.appendChild(badge);
      }
    }
    this._streamingEl = null;
    this._streamingText = '';
    this.showTyping(false);
  },

  showTyping(show) {
    if (this.typingEl) this.typingEl.style.display = show ? 'flex' : 'none';
  },

  setInputEnabled(enabled) {
    this.inputEl.disabled = !enabled;
    this.sendBtn.disabled = !enabled;
    if (enabled) this.inputEl.focus();
  },

  clear() {
    this.messagesEl.innerHTML = '';
  },

  loadMessages(messages) {
    this.clear();
    for (const msg of messages) {
      this.addMessage(msg.role, msg.content, msg);
    }
  },

  scrollToBottom() {
    this.messagesEl.scrollTop = this.messagesEl.scrollHeight;
  },
};
