/**
 * Lightweight Markdown Renderer
 * Converts a subset of markdown to HTML for chat messages.
 * No external dependencies. Handles the patterns Claude commonly uses.
 */

window.renderMarkdown = function renderMarkdown(text) {
  if (!text) return '';

  // Escape HTML first
  let html = text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');

  // Code blocks (``` ... ```)
  html = html.replace(/```(\w*)\n([\s\S]*?)```/g, (_, lang, code) => {
    return `<pre class="md-code-block"><code>${code.trim()}</code></pre>`;
  });

  // Inline code (`...`)
  html = html.replace(/`([^`\n]+)`/g, '<code class="md-inline-code">$1</code>');

  // Bold (**...**)
  html = html.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');

  // Italic (*...*)
  html = html.replace(/(?<!\*)\*([^*\n]+)\*(?!\*)/g, '<em>$1</em>');

  // Headers (## ...)
  html = html.replace(/^### (.+)$/gm, '<div class="md-h3">$1</div>');
  html = html.replace(/^## (.+)$/gm, '<div class="md-h2">$1</div>');
  html = html.replace(/^# (.+)$/gm, '<div class="md-h1">$1</div>');

  // Horizontal rule (---)
  html = html.replace(/^---+$/gm, '<hr class="md-hr">');

  // Unordered lists (- item or * item)
  html = html.replace(/^(\s*)[-*] (.+)$/gm, (_, indent, content) => {
    const depth = Math.floor(indent.length / 2);
    return `<div class="md-li" style="padding-left:${depth * 16 + 8}px">\u2022 ${content}</div>`;
  });

  // Ordered lists (1. item)
  html = html.replace(/^\d+\. (.+)$/gm, '<div class="md-li">\u2022 $1</div>');

  // Links [text](url)
  html = html.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" target="_blank" rel="noopener" class="md-link">$1</a>');

  // Line breaks: double newline = paragraph break, single = <br>
  html = html.replace(/\n\n/g, '</p><p>');
  html = html.replace(/\n/g, '<br>');

  // Wrap in paragraph
  html = '<p>' + html + '</p>';

  // Clean up empty paragraphs
  html = html.replace(/<p>\s*<\/p>/g, '');

  return html;
};
