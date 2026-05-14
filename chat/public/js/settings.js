window.SettingsPanel = {
  dialogEl: null,
  textareaEl: null,
  systemPrompt: '',
  onSave: null,

  init(dialogEl, textareaEl) {
    this.dialogEl = dialogEl;
    this.textareaEl = textareaEl;
    this.systemPrompt = localStorage.getItem('chat-system-prompt') || '';
    textareaEl.value = this.systemPrompt;
  },

  show() {
    this.textareaEl.value = this.systemPrompt;
    this.dialogEl.showModal();
  },

  save() {
    this.systemPrompt = this.textareaEl.value;
    localStorage.setItem('chat-system-prompt', this.systemPrompt);
    this.dialogEl.close();
    this.onSave?.(this.systemPrompt);
  },

  cancel() {
    this.dialogEl.close();
  },

  getPrompt() {
    return this.systemPrompt;
  },
};
