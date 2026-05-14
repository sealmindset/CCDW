window.Artifacts = {
  paneEl: null,
  contentEl: null,
  tabsEl: null,
  activeTab: 'code',
  currentCode: '',
  currentLang: '',

  init(paneEl, contentEl, tabsEl) {
    this.paneEl = paneEl;
    this.contentEl = contentEl;
    this.tabsEl = tabsEl;
  },

  detect(text) {
    // HTML document
    if (/<!DOCTYPE|<html/i.test(text)) {
      const m = text.match(/```(?:html)?\n([\s\S]*?)```/);
      if (m) return { type: 'html', content: m[1] };
    }
    // SVG
    const svgMatch = text.match(/```(?:svg)?\n(<svg[\s\S]*?<\/svg>)\s*```/);
    if (svgMatch) return { type: 'svg', content: svgMatch[1] };
    // Mermaid
    const mermaidMatch = text.match(/```mermaid\n([\s\S]*?)```/);
    if (mermaidMatch) return { type: 'mermaid', content: mermaidMatch[1] };
    // Large code blocks (>10 lines)
    const codeMatch = text.match(/```(\w+)\n([\s\S]*?)```/);
    if (codeMatch && codeMatch[2].split('\n').length > 10) {
      return { type: 'code', lang: codeMatch[1], content: codeMatch[2] };
    }
    return null;
  },

  show(artifact) {
    this.currentCode = artifact.content;
    this.currentLang = artifact.lang || artifact.type;
    this.paneEl.classList.add('open');
    this.renderTabs(artifact.type);
    this.renderContent(artifact);
  },

  renderTabs(type) {
    const tabs = ['code'];
    if (type === 'html' || type === 'svg') tabs.push('preview');
    this.tabsEl.innerHTML = tabs.map(t =>
      `<button class="artifact-tab${t === this.activeTab ? ' active' : ''}" data-tab="${t}">${t === 'code' ? 'Code' : 'Preview'}</button>`
    ).join('');
    this.tabsEl.querySelectorAll('.artifact-tab').forEach(btn => {
      btn.addEventListener('click', () => {
        this.activeTab = btn.dataset.tab;
        this.renderTabs(type);
        this.renderContent({ type, content: this.currentCode, lang: this.currentLang });
      });
    });
  },

  renderContent(artifact) {
    if (this.activeTab === 'preview') {
      if (artifact.type === 'html') {
        this.contentEl.innerHTML = `<iframe class="artifact-iframe" sandbox="allow-scripts" srcdoc="${this.esc(artifact.content)}"></iframe>`;
      } else if (artifact.type === 'svg') {
        this.contentEl.innerHTML = artifact.content;
      }
    } else {
      const escaped = artifact.content.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
      this.contentEl.innerHTML = `<div class="artifact-code-header">
        <span>${artifact.lang || artifact.type}</span>
        <button class="artifact-copy" onclick="navigator.clipboard.writeText(window.Artifacts.currentCode)">Copy</button>
        <button class="artifact-download" onclick="window.Artifacts.download()">Download</button>
      </div><pre class="artifact-code"><code>${escaped}</code></pre>`;
    }
  },

  close() {
    this.paneEl.classList.remove('open');
  },

  download() {
    const ext = { js: 'js', python: 'py', html: 'html', css: 'css', svg: 'svg', mermaid: 'mmd' };
    const blob = new Blob([this.currentCode], { type: 'text/plain' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = `artifact.${ext[this.currentLang] || 'txt'}`;
    a.click();
    URL.revokeObjectURL(a.href);
  },

  esc(s) {
    return s.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  },
};
