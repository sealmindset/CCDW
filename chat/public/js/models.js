window.ModelSelector = {
  el: null,
  models: [],
  selected: null,
  onChange: null,

  init(el) {
    this.el = el;
    this.selected = localStorage.getItem('chat-model') || null;
    el.addEventListener('change', () => {
      this.selected = el.value;
      localStorage.setItem('chat-model', this.selected);
      this.onChange?.(this.selected);
    });
  },

  async load() {
    try {
      const data = await ChatAPI.getModels();
      this.models = data.models || [];
      const defaultModel = data.default;
      if (!this.selected && defaultModel) this.selected = defaultModel;
      this.render();
    } catch {}
  },

  render() {
    const tierLabel = { heavy: 'Pro', standard: 'Fast', light: 'Quick' };
    this.el.innerHTML = this.models.map(m => {
      const label = `${m.label} (${tierLabel[m.tier] || m.tier})`;
      const sel = m.id === this.selected ? ' selected' : '';
      return `<option value="${m.id}"${sel}>${label}</option>`;
    }).join('');
  },

  getModel() {
    return this.selected || (this.models[0] && this.models[0].id) || null;
  },
};
