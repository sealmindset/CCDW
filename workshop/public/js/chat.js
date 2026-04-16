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
    const msg = document.createElement('div');
    msg.className = `message ${role}`;

    const bubble = document.createElement('div');
    bubble.className = 'message-bubble';
    bubble.textContent = text;

    msg.appendChild(bubble);
    this.messagesEl.appendChild(msg);
    this.scrollToBottom();

    return msg;
  }

  /**
   * Show typing indicator.
   */
  showTyping() {
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
   * Show quick reply buttons.
   */
  setQuickReplies(options) {
    this.clearQuickReplies();

    if (!options || options.length === 0) return;

    options.forEach(option => {
      const btn = document.createElement('button');
      btn.className = 'quick-reply-btn';
      btn.textContent = option;
      btn.addEventListener('click', () => {
        this.addMessage('user', option);
        this.clearQuickReplies();
        if (this.onSend) {
          this.onSend(option);
        }
      });
      this.quickRepliesEl.appendChild(btn);
    });
  }

  /**
   * Clear quick reply buttons.
   */
  clearQuickReplies() {
    this.quickRepliesEl.innerHTML = '';
  }

  /**
   * Add a welcome message with a warm greeting.
   */
  addWelcome(projectName) {
    this.addMessage('ai',
      `Welcome to Workshop! I'm here to help you build ${projectName ? '"' + projectName + '"' : 'your app'}. ` +
      `Just describe what you're imagining and I'll take care of the rest. ` +
      `What kind of app would you like to build?`
    );
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
