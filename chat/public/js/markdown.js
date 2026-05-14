window.renderMarkdown = function renderMarkdown(text) {
  if (!text) return '';

  let html = text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');

  // Code blocks with language tag and copy button
  html = html.replace(/```(\w*)\n([\s\S]*?)```/g, (_, lang, code) => {
    const langLabel = lang ? `<span class="code-lang">${lang}</span>` : '';
    const id = 'cb-' + Math.random().toString(36).slice(2, 8);
    return `<div class="code-block-wrap">${langLabel}<button class="code-copy-btn" data-target="${id}" onclick="copyCode(this)">Copy</button><pre class="md-code-block" id="${id}"><code>${code.trim()}</code></pre></div>`;
  });

  html = html.replace(/`([^`\n]+)`/g, '<code class="md-inline-code">$1</code>');
  html = html.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
  html = html.replace(/(?<!\*)\*([^*\n]+)\*(?!\*)/g, '<em>$1</em>');
  html = html.replace(/^### (.+)$/gm, '<div class="md-h3">$1</div>');
  html = html.replace(/^## (.+)$/gm, '<div class="md-h2">$1</div>');
  html = html.replace(/^# (.+)$/gm, '<div class="md-h1">$1</div>');
  html = html.replace(/^---+$/gm, '<hr class="md-hr">');

  // Tables
  html = html.replace(/^(\|.+\|)\n(\|[-| :]+\|)\n((?:\|.+\|\n?)*)/gm, (_, header, sep, body) => {
    const hCells = header.split('|').filter(c => c.trim()).map(c => `<th>${c.trim()}</th>`).join('');
    const rows = body.trim().split('\n').map(row => {
      const cells = row.split('|').filter(c => c.trim()).map(c => `<td>${c.trim()}</td>`).join('');
      return `<tr>${cells}</tr>`;
    }).join('');
    return `<table class="md-table"><thead><tr>${hCells}</tr></thead><tbody>${rows}</tbody></table>`;
  });

  html = html.replace(/^(\s*)[-*] (.+)$/gm, (_, indent, content) => {
    const depth = Math.floor(indent.length / 2);
    return `<div class="md-li" style="padding-left:${depth * 16 + 8}px">• ${content}</div>`;
  });
  html = html.replace(/^\d+\. (.+)$/gm, '<div class="md-li">• $1</div>');
  html = html.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" target="_blank" rel="noopener" class="md-link">$1</a>');
  html = html.replace(/\n\n/g, '</p><p>');
  html = html.replace(/\n/g, '<br>');
  html = '<p>' + html + '</p>';
  html = html.replace(/<p>\s*<\/p>/g, '');

  return html;
};

window.copyCode = function copyCode(btn) {
  const pre = document.getElementById(btn.dataset.target);
  if (!pre) return;
  navigator.clipboard.writeText(pre.textContent).then(() => {
    btn.textContent = 'Copied!';
    setTimeout(() => btn.textContent = 'Copy', 1500);
  });
};
