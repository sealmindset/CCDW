window.ChatAPI = {
  async listConversations() {
    const res = await fetch('/api/conversations');
    return res.json();
  },

  async createConversation(model, systemPrompt) {
    const res = await fetch('/api/conversations', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ model, system_prompt: systemPrompt }),
    });
    return res.json();
  },

  async getConversation(id) {
    const res = await fetch(`/api/conversations/${id}`);
    return res.json();
  },

  async updateConversation(id, fields) {
    const res = await fetch(`/api/conversations/${id}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(fields),
    });
    return res.json();
  },

  async deleteConversation(id) {
    await fetch(`/api/conversations/${id}`, { method: 'DELETE' });
  },

  async stopStream(id) {
    await fetch(`/api/conversations/${id}/stop`, { method: 'POST' });
  },

  async getModels() {
    const res = await fetch('/api/models');
    return res.json();
  },

  async getProviders() {
    const res = await fetch('/api/providers');
    return res.json();
  },

  sendMessage(convId, content, model, onEvent) {
    const body = JSON.stringify({ content, model });
    const ctrl = new AbortController();

    fetch(`/api/conversations/${convId}/messages`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body,
      signal: ctrl.signal,
    }).then(async (res) => {
      const reader = res.body.getReader();
      const decoder = new TextDecoder();
      let buf = '';

      while (true) {
        const { done, value } = await reader.read();
        if (done) { onEvent({ type: 'done' }); break; }

        buf += decoder.decode(value, { stream: true });
        const parts = buf.split('\n\n');
        buf = parts.pop();

        for (const part of parts) {
          const lines = part.split('\n');
          let eventType = '';
          let data = '';
          for (const line of lines) {
            if (line.startsWith('event: ')) eventType = line.slice(7);
            else if (line.startsWith('data: ')) data = line.slice(6);
          }
          if (data) {
            try {
              const parsed = JSON.parse(data);
              onEvent({ type: eventType || parsed.type, data: parsed });
            } catch {}
          }
        }
      }
    }).catch(e => {
      if (e.name !== 'AbortError') {
        onEvent({ type: 'chat:error', data: { message: e.message } });
      }
    });

    return ctrl;
  },
};
