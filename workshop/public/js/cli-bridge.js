/**
 * CLI Bridge -- WebSocket connection to Workshop server.
 * Bridges the browser to Claude Code CLI running on the server.
 */

class CLIBridge {
  constructor() {
    this.ws = null;
    this.sessionId = null;
    this.listeners = new Map();
    this.reconnectAttempts = 0;
    this.maxReconnectAttempts = 5;
  }

  connect() {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const url = `${protocol}//${window.location.host}/ws`;

    this.ws = new WebSocket(url);

    this.ws.onopen = () => {
      this.reconnectAttempts = 0;
      this.emit('connected');
    };

    this.ws.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data);
        this.handleMessage(msg);
      } catch (e) {
        console.error('Failed to parse WebSocket message:', e);
      }
    };

    this.ws.onclose = () => {
      this.emit('disconnected');
      this.attemptReconnect();
    };

    this.ws.onerror = () => {
      // onclose will fire after this
    };
  }

  attemptReconnect() {
    if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      this.emit('reconnect-failed');
      return;
    }
    this.reconnectAttempts++;
    const delay = Math.min(1000 * Math.pow(2, this.reconnectAttempts), 10000);
    setTimeout(() => this.connect(), delay);
  }

  handleMessage(msg) {
    switch (msg.type) {
      case 'connected':
        this.sessionId = msg.sessionId;
        this.emit('session-ready', msg);
        break;

      case 'project-opened':
        this.emit('project-opened', msg);
        break;

      case 'phase-change':
        this.emit('phase-change', msg);
        break;

      case 'question':
        this.emit('question', msg);
        break;

      case 'activity':
        this.emit('activity', msg);
        break;

      case 'process-complete':
        this.emit('process-complete', msg);
        break;

      case 'cancelled':
        this.emit('cancelled', msg);
        break;

      case 'error':
        this.emit('error', msg);
        break;

      default:
        this.emit('message', msg);
    }
  }

  // Send messages to server
  send(msg) {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(msg));
    }
  }

  startProject(name) {
    this.send({ type: 'start-project', name });
  }

  openProject(name) {
    this.send({ type: 'open-project', name });
  }

  sendInput(text) {
    this.send({ type: 'user-input', text });
  }

  sendQuickReply(value) {
    this.send({ type: 'quick-reply', value });
  }

  tryIt() {
    this.send({ type: 'try-it' });
  }

  resumeIt() {
    this.send({ type: 'resume-it' });
  }

  shipIt(mode) {
    this.send({ type: 'ship-it', mode });
  }

  cancel() {
    this.send({ type: 'cancel' });
  }

  // Simple event system
  on(event, callback) {
    if (!this.listeners.has(event)) {
      this.listeners.set(event, []);
    }
    this.listeners.get(event).push(callback);
    return this; // chainable
  }

  off(event, callback) {
    const list = this.listeners.get(event);
    if (list) {
      const idx = list.indexOf(callback);
      if (idx !== -1) list.splice(idx, 1);
    }
  }

  emit(event, data) {
    const list = this.listeners.get(event);
    if (list) {
      list.forEach(cb => cb(data));
    }
  }
}

// Global instance
window.cliBridge = new CLIBridge();
