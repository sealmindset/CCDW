window.App = {
  currentConvId: null,
  streamCtrl: null,
  isStreaming: false,
  cwd: null,          // folder for the active conversation (or the next one)

  async init() {
    ChatView.init(
      document.getElementById('messages'),
      document.getElementById('message-input'),
      document.getElementById('btn-send'),
      document.getElementById('typing-indicator')
    );
    Sidebar.init(
      document.getElementById('sidebar'),
      document.getElementById('sidebar-list'),
      document.getElementById('sidebar-search')
    );
    ModelSelector.init(document.getElementById('model-selector'));
    SettingsPanel.init(
      document.getElementById('settings-dialog'),
      document.getElementById('settings-prompt')
    );
    Attachments.init(
      document.getElementById('attach-preview'),
      document.getElementById('file-input')
    );
    Artifacts.init(
      document.getElementById('artifact-pane'),
      document.getElementById('artifact-content'),
      document.getElementById('artifact-tabs')
    );
    WorkdirPicker.init(
      document.getElementById('workdir-dialog'),
      document.getElementById('workdir-list'),
      document.getElementById('workdir-crumb'),
      document.getElementById('btn-workdir-use'),
      document.getElementById('btn-workdir-close')
    );
    WorkdirChip.init(document.getElementById('workdir-chip'), () => this.pickFolder());

    ChatView.onSend = (text) => this.sendMessage(text);
    Sidebar.onSelect = (id) => this.loadConversation(id);
    Sidebar.onNew = () => this.newConversation();
    Sidebar.onDelete = (id) => this.deleteConversation(id);
    Sidebar.onStar = (id) => this.toggleStar(id);

    document.getElementById('btn-new-chat').addEventListener('click', () => this.newConversation());
    document.getElementById('btn-sidebar-toggle').addEventListener('click', () => {
      document.getElementById('sidebar').classList.toggle('collapsed');
    });
    document.getElementById('btn-settings').addEventListener('click', () => SettingsPanel.show());
    document.getElementById('btn-settings-save').addEventListener('click', () => SettingsPanel.save());
    document.getElementById('btn-settings-cancel').addEventListener('click', () => SettingsPanel.cancel());
    document.getElementById('btn-export').addEventListener('click', () => this.exportConversation());
    document.getElementById('btn-stop').addEventListener('click', () => this.stopStream());
    document.getElementById('btn-close-artifact').addEventListener('click', () => Artifacts.close());
    document.getElementById('btn-attach').addEventListener('click', () => {
      document.getElementById('file-input').click();
    });

    await this.loadDefaultCwd();
    await ModelSelector.load();
    await this.loadConversations();
  },

  // --- Folder binding ------------------------------------------------------
  async loadDefaultCwd() {
    // Last folder used wins, so reopening Chat lands where you left off.
    const remembered = localStorage.getItem('chat-cwd');
    try {
      const data = await ChatAPI.getWorkdirRoots();
      this.cwd = remembered || data.default || null;
    } catch {
      this.cwd = remembered || null;
    }
    WorkdirChip.set(this.cwd);
  },

  pickFolder() {
    WorkdirPicker.show(this.cwd, async (picked) => {
      this.cwd = picked;
      localStorage.setItem('chat-cwd', picked);
      WorkdirChip.set(picked);
      if (this.currentConvId) {
        await ChatAPI.updateConversation(this.currentConvId, { cwd: picked });
        ChatView.addSystemNote(`Folder for this conversation is now ${picked}`);
      }
    });
  },

  // --- Conversations -------------------------------------------------------
  async loadConversations() {
    try {
      const convos = await ChatAPI.listConversations();
      Sidebar.setConversations(convos);
    } catch {}
  },

  async newConversation() {
    try {
      const conv = await ChatAPI.createConversation(
        ModelSelector.getModel(), SettingsPanel.getPrompt(), this.cwd);
      this.currentConvId = conv.id;
      this.cwd = conv.cwd || this.cwd;
      WorkdirChip.set(this.cwd);
      ChatView.clear();
      document.getElementById('welcome-screen')?.remove();
      await this.loadConversations();
      Sidebar.setActive(conv.id);
      ChatView.setInputEnabled(true);
      ChatView.inputEl.focus();
    } catch {}
  },

  async loadConversation(id) {
    try {
      const conv = await ChatAPI.getConversation(id);
      this.currentConvId = id;
      document.getElementById('welcome-screen')?.remove();
      ChatView.loadMessages(conv.messages || []);
      Sidebar.setActive(id);
      ChatView.setInputEnabled(true);
      if (conv.cwd) { this.cwd = conv.cwd; WorkdirChip.set(conv.cwd); }
      if (conv.model) {
        ModelSelector.selected = conv.model;
        ModelSelector.render();
      }
    } catch {}
  },

  async deleteConversation(id) {
    try {
      await ChatAPI.deleteConversation(id);
      if (this.currentConvId === id) {
        this.currentConvId = null;
        ChatView.clear();
      }
      await this.loadConversations();
    } catch {}
  },

  async toggleStar(id) {
    const conv = Sidebar.conversations.find(c => c.id === id);
    if (!conv) return;
    try {
      await ChatAPI.updateConversation(id, { starred: !conv.starred });
      await this.loadConversations();
    } catch {}
  },

  // --- Sending -------------------------------------------------------------
  async sendMessage(text) {
    if (!text.trim() && !Attachments.pending.length) return;

    if (!this.currentConvId) {
      const conv = await ChatAPI.createConversation(
        ModelSelector.getModel(), SettingsPanel.getPrompt(), this.cwd);
      this.currentConvId = conv.id;
      this.cwd = conv.cwd || this.cwd;
      WorkdirChip.set(this.cwd);
      document.getElementById('welcome-screen')?.remove();
      await this.loadConversations();
      Sidebar.setActive(conv.id);
    }

    const content = Attachments.getContent(text);
    ChatView.addUserMessage(content);
    ChatView.setInputEnabled(false);

    document.getElementById('btn-stop').style.display = 'flex';
    this.isStreaming = true;
    ChatView.startTurn();

    let usage = null;

    this.streamCtrl = ChatAPI.sendMessage(this.currentConvId, content, ModelSelector.getModel(), (event) => {
      switch (event.type) {
        case 'agent:start':
          ChatView.showTyping(true, 'Claude is working...');
          break;

        case 'agent:status':
          // "requesting" / "tool_use" -- a low-key liveness cue, not a log.
          if (event.data?.status === 'requesting') ChatView.showTyping(true, 'Claude is thinking...');
          break;

        case 'content_block_delta':
          if (event.data?.delta?.text) {
            ChatView.appendStreamText(event.data.delta.text);
            const artifact = Artifacts.detect(ChatView._streamingText);
            if (artifact) Artifacts.show(artifact);
          }
          break;

        case 'agent:tool_use':
          ChatView.addToolCall(event.data?.id, event.data?.name, event.data?.input, 'running');
          ChatView.showTyping(true, 'Claude is working...');
          break;

        case 'agent:tool_result':
          ChatView.resolveToolCall(
            event.data?.tool_use_id, event.data?.is_error, event.data?.content, event.data?.truncated);
          break;

        case 'message_delta':
          if (event.data?.usage) usage = event.data.usage;
          break;

        case 'agent:result':
          if (event.data?.usage) usage = event.data.usage;
          break;

        case 'chat:usage':
          if (event.data) usage = event.data;
          break;

        case 'chat:title_updated':
          this.loadConversations();
          break;

        case 'chat:error':
          ChatView.addSystemNote(event.data?.message || 'Something went wrong.', 'error');
          break;

        // NOTE: message_stop fires once per model round-trip, and a turn with
        // tool use has several. Only the stream closing ends the turn.
        case 'done':
          ChatView.finishTurn(usage);
          this.streamDone();
          break;
      }
    });
  },

  streamDone() {
    this.isStreaming = false;
    this.streamCtrl = null;
    document.getElementById('btn-stop').style.display = 'none';
    ChatView.setInputEnabled(true);
    this.loadConversations();
  },

  stopStream() {
    // Abort the fetch and kill the CLI process; the server persists whatever
    // the turn produced before the signal landed.
    if (this.streamCtrl) this.streamCtrl.abort();
    if (this.currentConvId) ChatAPI.stopStream(this.currentConvId).catch(() => {});
    ChatView.finishTurn();
    ChatView.addSystemNote('Stopped.');
    this.streamDone();
  },

  async exportConversation() {
    if (!this.currentConvId) return;
    try {
      const res = await fetch(`/api/conversations/${this.currentConvId}/export?format=markdown`);
      const text = await res.text();
      const blob = new Blob([text], { type: 'text/markdown' });
      const a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = `conversation-${this.currentConvId.slice(0, 8)}.md`;
      a.click();
      URL.revokeObjectURL(a.href);
    } catch {}
  },
};

document.addEventListener('DOMContentLoaded', () => App.init());
