/**
 * Chat Controller
 * Manages the chat interface, message rendering,
 * quick replies, and input handling.
 */

class ChatController {
  constructor(containerId, inputId, sendBtnId, quickRepliesId) {
    this.messagesEl = document.getElementById(containerId);
    this.inputEl = document.getElementById(inputId);
    this.sendBtn = document.getElementById(sendBtnId);
    this.quickRepliesEl = document.getElementById(quickRepliesId);
    this.onSend = null; // callback

    this.setupListeners();
  }

  setupListeners() {
    // Send button
    this.sendBtn.addEventListener('click', () => this.handleSend());

    // Enter to send (Shift+Enter for newline)
    this.inputEl.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        this.handleSend();
      }
    });

    // Auto-resize textarea
    this.inputEl.addEventListener('input', () => {
      this.inputEl.style.height = 'auto';
      this.inputEl.style.height = Math.min(this.inputEl.scrollHeight, 120) + 'px';
    });
  }

  handleSend() {
    const text = this.inputEl.value.trim();
    if (!text) return;

    this.addMessage('user', text);
    this.inputEl.value = '';
    this.inputEl.style.height = 'auto';
    this.clearQuickReplies();

    if (this.onSend) {
      this.onSend(text);
    }
  }

  /**
   * Add a message bubble to the chat.
   */
  addMessage(role, text) {
    // A real message clears the status line
    this.clearStatus();

    const msg = document.createElement('div');
    msg.className = `message ${role}`;

    const bubble = document.createElement('div');
    bubble.className = 'message-bubble';

    // AI messages get markdown rendering
    if (role === 'ai' && window.renderMarkdown) {
      bubble.innerHTML = window.renderMarkdown(text);
    } else {
      bubble.textContent = text;
    }

    msg.appendChild(bubble);
    this.messagesEl.appendChild(msg);
    this.scrollToBottom();

    return msg;
  }

  /**
   * Add an error message with optional retry action.
   */
  addError(text, onRetry) {
    const msg = document.createElement('div');
    msg.className = 'message error';

    const bubble = document.createElement('div');
    bubble.className = 'message-bubble';

    const errorText = document.createElement('div');
    errorText.textContent = text;
    bubble.appendChild(errorText);

    if (onRetry) {
      const actions = document.createElement('div');
      actions.className = 'error-actions';

      const retryBtn = document.createElement('button');
      retryBtn.className = 'quick-reply-btn';
      retryBtn.textContent = 'Try Again';
      retryBtn.addEventListener('click', onRetry);
      actions.appendChild(retryBtn);

      bubble.appendChild(actions);
    }

    msg.appendChild(bubble);
    this.messagesEl.appendChild(msg);
    this.scrollToBottom();

    return msg;
  }

  /**
   * Show typing indicator.
   */
  showTyping() {
    if (document.getElementById('typingIndicator')) return; // already showing
    const msg = document.createElement('div');
    msg.className = 'message ai typing';
    msg.id = 'typingIndicator';

    const bubble = document.createElement('div');
    bubble.className = 'message-bubble';
    bubble.innerHTML = '<span class="typing-dot"></span><span class="typing-dot"></span><span class="typing-dot"></span>';

    msg.appendChild(bubble);
    this.messagesEl.appendChild(msg);
    this.scrollToBottom();
  }

  /**
   * Hide typing indicator.
   */
  hideTyping() {
    const typing = document.getElementById('typingIndicator');
    if (typing) typing.remove();
  }

  /**
   * Show or update a muted status line (e.g. "Reading files...").
   * Updates in place — only one status line exists at a time.
   * Does NOT remove the typing indicator; they coexist.
   */
  setStatus(text) {
    let el = document.getElementById('chatStatusLine');
    if (!el) {
      el = document.createElement('div');
      el.className = 'chat-status';
      el.id = 'chatStatusLine';

      const dots = document.createElement('span');
      dots.className = 'status-dots';
      dots.innerHTML = '<span class="status-dot"></span><span class="status-dot"></span><span class="status-dot"></span>';

      const label = document.createElement('span');
      label.className = 'status-label';

      el.appendChild(dots);
      el.appendChild(label);
      this.messagesEl.appendChild(el);
    }

    el.querySelector('.status-label').textContent = text;
    this.scrollToBottom();
  }

  /**
   * Remove the status line.
   */
  clearStatus() {
    const el = document.getElementById('chatStatusLine');
    if (el) el.remove();
  }

  /**
   * Show quick reply buttons as toggleable tags.
   * Clicking a tag inserts/removes it from the input field.
   * User sends when ready via Enter or Send button.
   */
  setQuickReplies(options) {
    this.clearQuickReplies();
    this._selectedTags = new Set();

    if (!options || options.length === 0) return;

    options.forEach(option => {
      const btn = document.createElement('button');
      btn.className = 'quick-reply-btn';
      btn.textContent = option;
      btn.addEventListener('click', () => {
        if (this._selectedTags.has(option)) {
          this._selectedTags.delete(option);
          btn.classList.remove('selected');
        } else {
          this._selectedTags.add(option);
          btn.classList.add('selected');
        }
        this._syncTagsToInput();
        this.inputEl.focus();
      });
      this.quickRepliesEl.appendChild(btn);
    });

    // Hint
    const hint = document.createElement('div');
    hint.className = 'quick-replies-hint';
    hint.textContent = 'pick one or more, or type your own answer below';
    this.quickRepliesEl.appendChild(hint);
  }

  /**
   * Sync selected tags into the input field.
   * Preserves any free-text the user typed after the tags.
   */
  _syncTagsToInput() {
    const tags = Array.from(this._selectedTags);
    // Preserve any user-typed text that isn't a tag
    const currentText = this.inputEl.value;
    const freeText = currentText.split(',')
      .map(s => s.trim())
      .filter(s => s && !this._isKnownTag(s))
      .join(', ');

    const parts = [];
    if (tags.length > 0) parts.push(tags.join(', '));
    if (freeText) parts.push(freeText);

    this.inputEl.value = parts.join(', ');
    // Trigger resize
    this.inputEl.style.height = 'auto';
    this.inputEl.style.height = Math.min(this.inputEl.scrollHeight, 120) + 'px';
  }

  /**
   * Check if a string matches any quick reply option (case-insensitive).
   */
  _isKnownTag(text) {
    if (!this.quickRepliesEl) return false;
    const buttons = this.quickRepliesEl.querySelectorAll('.quick-reply-btn');
    for (const btn of buttons) {
      if (btn.textContent.toLowerCase() === text.toLowerCase()) return true;
    }
    return false;
  }

  /**
   * Show welcome-back action buttons (not text replies -- these dispatch actions).
   */
  setWelcomeActions(options, onAction) {
    this.clearQuickReplies();
    if (!options || options.length === 0) return;

    options.forEach(option => {
      const btn = document.createElement('button');
      btn.className = 'quick-reply-btn welcome-action-btn';
      btn.textContent = option.label;
      btn.addEventListener('click', () => {
        this.clearQuickReplies();
        this.addMessage('user', option.label);
        if (onAction) onAction(option.action);
      });
      this.quickRepliesEl.appendChild(btn);
    });
  }

  /**
   * Clear quick reply buttons.
   */
  clearQuickReplies() {
    this.quickRepliesEl.innerHTML = '';
    this._selectedTags = new Set();
  }

  /**
   * Show a warm startup message with rotating tips while waiting for the CLI.
   * Call stopTips() when the first real response arrives.
   */
  showStartupTips(projectName) {
    this.addMessage('ai',
      `Getting everything set up to start working on ${projectName ? '**' + projectName + '**' : 'your idea'}. So excited!`
    );
    this.showTyping();

    // Create the rotating tip element under the typing indicator
    const tipEl = document.createElement('div');
    tipEl.className = 'message ai tip-rotation';
    tipEl.id = 'tipRotation';

    const bubble = document.createElement('div');
    bubble.className = 'message-bubble tip-bubble';
    tipEl.appendChild(bubble);
    this.messagesEl.appendChild(tipEl);

    const tips = [
      'Workshop turns your plain-English description into a real, working app.',
      'You can ask for changes anytime -- just describe what you want different.',
      'Your app will include login, permissions, and a database -- all set up automatically.',
      'Every app gets its own test users so you can try different roles.',
      'When you\'re happy with your app, the Go Live wizard helps you share it.',
      'Workshop builds real production-quality code, not just a prototype.',
      'You can open the Web Terminal anytime if you want to peek under the hood.',
      'Each project gets a dashboard showing health, pages, users, and test status.',
    ];

    let tipIndex = 0;
    bubble.textContent = tips[0];

    this._tipInterval = setInterval(() => {
      tipIndex = (tipIndex + 1) % tips.length;
      bubble.style.opacity = '0';
      setTimeout(() => {
        bubble.textContent = tips[tipIndex];
        bubble.style.opacity = '1';
      }, 300);
      this.scrollToBottom();
    }, 5000);
  }

  /**
   * Stop the rotating tips and clean up.
   */
  stopTips() {
    if (this._tipInterval) {
      clearInterval(this._tipInterval);
      this._tipInterval = null;
    }
    const tipEl = document.getElementById('tipRotation');
    if (tipEl) tipEl.remove();
  }

  /**
   * Scroll to the bottom of the messages.
   */
  scrollToBottom() {
    requestAnimationFrame(() => {
      this.messagesEl.scrollTop = this.messagesEl.scrollHeight;
    });
  }

  /**
   * Clear all messages.
   */
  clear() {
    this.messagesEl.innerHTML = '';
    this.clearQuickReplies();
  }
}

// Will be instantiated by app.js
window.ChatController = ChatController;
