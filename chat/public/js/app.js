window.App = {
  currentConvId: null,
  streamCtrl: null,
  isStreaming: false,

  async init() {
    // Init modules
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

    // Wire events
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

    // Load data
    await ModelSelector.load();
    await this.loadConversations();
  },

  async loadConversations() {
    try {
      const convos = await ChatAPI.listConversations();
      Sidebar.setConversations(convos);
    } catch {}
  },

  async newConversation() {
    try {
      const model = ModelSelector.getModel();
      const systemPrompt = SettingsPanel.getPrompt();
      const conv = await ChatAPI.createConversation(model, systemPrompt);
      this.currentConvId = conv.id;
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

  async sendMessage(text) {
    if (!text.trim() && !Attachments.pending.length) return;

    // Auto-create conversation if none active
    if (!this.currentConvId) {
      const model = ModelSelector.getModel();
      const systemPrompt = SettingsPanel.getPrompt();
      const conv = await ChatAPI.createConversation(model, systemPrompt);
      this.currentConvId = conv.id;
      document.getElementById('welcome-screen')?.remove();
      await this.loadConversations();
      Sidebar.setActive(conv.id);
    }

    const content = Attachments.getContent(text);
    ChatView.addMessage('user', content);
    ChatView.setInputEnabled(false);

    const stopBtn = document.getElementById('btn-stop');
    stopBtn.style.display = 'flex';
    this.isStreaming = true;

    ChatView.startStreaming();

    let usage = null;
    const model = ModelSelector.getModel();

    this.streamCtrl = ChatAPI.sendMessage(this.currentConvId, content, model, (event) => {
      switch (event.type) {
        case 'content_block_delta':
          if (event.data?.delta?.text) {
            ChatView.appendStreamText(event.data.delta.text);

            // Check for artifacts in accumulated text
            const artifact = Artifacts.detect(ChatView._streamingText);
            if (artifact) Artifacts.show(artifact);
          }
          break;

        case 'message_delta':
          if (event.data?.usage) usage = event.data.usage;
          break;

        case 'chat:usage':
          if (event.data) usage = event.data;
          break;

        case 'chat:title_updated':
          this.loadConversations();
          break;

        case 'chat:error':
          ChatView.finishStreaming(usage);
          ChatView.addMessage('assistant', `Error: ${event.data?.message || 'Unknown error'}`);
          this.streamDone();
          break;

        case 'message_stop':
        case 'done':
          ChatView.finishStreaming(usage);
          this.streamDone();

          // Final artifact check
          const fullText = ChatView._streamingText || '';
          if (fullText) {
            const art = Artifacts.detect(fullText);
            if (art) Artifacts.show(art);
          }
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
    if (this.streamCtrl) {
      this.streamCtrl.abort();
    }
    if (this.currentConvId) {
      ChatAPI.stopStream(this.currentConvId).catch(() => {});
    }
    ChatView.finishStreaming();
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
