window.Attachments = {
  previewEl: null,
  inputEl: null,
  pending: [],
  onUpdate: null,

  init(previewEl, fileInputEl) {
    this.previewEl = previewEl;
    this.inputEl = fileInputEl;

    fileInputEl.addEventListener('change', () => {
      for (const file of fileInputEl.files) this.addFile(file);
      fileInputEl.value = '';
    });

    document.addEventListener('dragover', (e) => e.preventDefault());
    document.addEventListener('drop', (e) => {
      e.preventDefault();
      for (const file of e.dataTransfer.files) this.addFile(file);
    });
  },

  addFile(file) {
    if (this.pending.length >= 5) return;
    if (file.size > 20 * 1024 * 1024) return;

    const reader = new FileReader();
    reader.onload = () => {
      const isImage = file.type.startsWith('image/');
      if (isImage) {
        const base64 = reader.result.split(',')[1];
        this.pending.push({
          type: 'image',
          source: { type: 'base64', media_type: file.type, data: base64 },
          name: file.name,
        });
      } else {
        this.pending.push({
          type: 'text',
          text: `[File: ${file.name}]\n${reader.result}`,
          name: file.name,
        });
      }
      this.renderPreviews();
      this.onUpdate?.(this.pending);
    };
    if (file.type.startsWith('image/')) reader.readAsDataURL(file);
    else reader.readAsText(file);
  },

  renderPreviews() {
    this.previewEl.innerHTML = this.pending.map((a, i) => {
      if (a.type === 'image') {
        return `<div class="attach-preview">
          <img src="data:${a.source.media_type};base64,${a.source.data}" />
          <button class="attach-remove" data-idx="${i}">×</button>
        </div>`;
      }
      return `<div class="attach-preview attach-file">
        <span>${a.name}</span>
        <button class="attach-remove" data-idx="${i}">×</button>
      </div>`;
    }).join('');

    this.previewEl.querySelectorAll('.attach-remove').forEach(btn => {
      btn.addEventListener('click', () => {
        this.pending.splice(parseInt(btn.dataset.idx), 1);
        this.renderPreviews();
        this.onUpdate?.(this.pending);
      });
    });
  },

  getContent(text) {
    const content = [];
    if (text) content.push({ type: 'text', text });
    for (const a of this.pending) {
      if (a.type === 'image') {
        content.push({ type: 'image', source: a.source });
      } else {
        content.push({ type: 'text', text: a.text });
      }
    }
    this.pending = [];
    this.renderPreviews();
    return content;
  },
};
