// Wiki content layer for the Dashboard server (served at :3000/wiki).
//
// Two markdown sources, no duplicated prose:
//   ccdw     -> docs/confluence/*.md              baked into the image at build
//   make-it  -> ~/.claude/make-it/confluence-docs  read live, so it tracks skill updates
//
// Dependency-free on purpose: welcome-server.js has no node_modules, and no CDN
// may be referenced (SSL-inspecting proxies break external assets).

'use strict';

const fs = require('fs');
const path = require('path');

const SOURCES = {
    'ccdw': process.env.WIKI_DOCS_DIR || '/opt/claude-code-docker/docs/confluence',
    'make-it': process.env.WIKI_MAKEIT_DIR || '/home/coder/.claude/make-it/confluence-docs'
};

// Image lookup order for markdown like ![Dashboard](img/dashboard.png).
const IMG_DIRS = [
    path.join(SOURCES['ccdw'], 'img'),
    path.join(SOURCES['make-it'], 'img')
];

// Reading order, not filename order — the numbers in docs/confluence are creation
// order (11 and 12 were added after the original ten). Files not listed here are
// appended to the group whose `overflow` matches their source, so new docs show up
// in the sidebar without a code change.
const GROUPS = [
    {
        title: 'Start here',
        ids: ['ccdw/01-what-is-ccdw', 'ccdw/02-getting-started', 'ccdw/03-which-page-should-i-use']
    },
    {
        title: 'The pages',
        ids: ['ccdw/04-dashboard', 'ccdw/05-workshop', 'ccdw/06-claude-chat', 'ccdw/07-vs-code', 'ccdw/08-terminal']
    },
    {
        title: 'The make-it framework',
        ids: ['ccdw/11-make-it-framework'],
        overflow: 'make-it'
    },
    {
        title: 'Reference',
        ids: ['ccdw/12-what-ccdw-remembers', 'ccdw/09-troubleshooting', 'ccdw/10-glossary'],
        overflow: 'ccdw'
    }
];

// ---------------------------------------------------------------------------
// Markdown -> HTML
//
// Covers exactly what these doc sets use: ATX headings, fenced code, tables,
// blockquotes, ordered/unordered lists, thematic breaks, bold/italic/strike,
// code spans, links and images. No raw HTML passthrough — everything is escaped.
// ---------------------------------------------------------------------------

function escapeHtml(s) {
    return String(s)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
}

function slugify(s) {
    return String(s)
        .toLowerCase()
        .replace(/[`*_~]/g, '')
        .replace(/[^a-z0-9]+/g, '-')
        .replace(/^-+|-+$/g, '') || 'section';
}

function uniqueSlug(base, seen) {
    var slug = base, n = 2;
    while (seen[slug]) { slug = base + '-' + n; n++; }
    seen[slug] = true;
    return slug;
}

function imgSrc(src) {
    if (/^(https?:)?\/\//i.test(src) || src.charAt(0) === '/') return src;
    return '/api/wiki/img/' + encodeURIComponent(path.basename(src));
}

// Relative links between docs (`01-make-it.md`, `00-overview.md#anchor`) become
// wiki routes inside the same source. Anchors ride along after `::`.
function linkHref(href, source) {
    if (/^(https?:|mailto:|tel:)/i.test(href) || /^(\/|#)/.test(href)) return href;
    var m = /^([^#?]*?)\.md(#(.*))?$/i.exec(href);
    if (m) {
        var slug = path.basename(m[1]);
        return '#/' + source + '/' + slug + (m[3] ? '::' + m[3] : '');
    }
    return href;
}

function renderInline(s, ctx) {
    var codes = [];
    var out = String(s).replace(/`([^`]+)`/g, function (_, c) {
        codes.push('<code>' + escapeHtml(c) + '</code>');
        return '\u0000' + (codes.length - 1) + '\u0000';
    });

    out = escapeHtml(out);

    out = out.replace(/!\[([^\]]*)\]\(\s*([^)\s]+)[^)]*\)/g, function (_, alt, src) {
        return '<img src="' + imgSrc(src) + '" alt="' + alt + '" loading="lazy">';
    });

    out = out.replace(/\[([^\]]+)\]\(\s*([^)\s]+)[^)]*\)/g, function (_, text, href) {
        var h = linkHref(href, ctx.source);
        var external = /^(https?:)?\/\//i.test(h);
        return '<a href="' + h + '"' + (external ? ' target="_blank" rel="noopener noreferrer"' : '') + '>' + text + '</a>';
    });

    out = out.replace(/\*\*\*([^*]+)\*\*\*/g, '<strong><em>$1</em></strong>');
    // Bold may contain single-star italics (`**When *not* to use it:**`), so the
    // inner run allows a lone `*` — the italic pass below then handles it.
    out = out.replace(/\*\*((?:[^*]|\*(?!\*))+?)\*\*/g, '<strong>$1</strong>');
    out = out.replace(/(^|[^*\w])\*([^*\n]+)\*(?![*\w])/g, '$1<em>$2</em>');
    out = out.replace(/~~([^~]+)~~/g, '<del>$1</del>');

    return out.replace(/\u0000(\d+)\u0000/g, function (_, i) { return codes[Number(i)]; });
}

function isTableSeparator(line) {
    if (!line || line.indexOf('-') === -1) return false;
    return /^\s*\|?[\s:|-]+\|[\s:|-]*$/.test(line);
}

function isBlockStart(line) {
    return /^\s*(#{1,6}\s|>|```|~~~|([-*+]|\d+[.)])\s)/.test(line) ||
        /^\s*(-{3,}|\*{3,}|_{3,})\s*$/.test(line) ||
        /^\s*\|/.test(line);
}

// Splits a table row on unescaped pipes that are not inside a code span.
function splitRow(line) {
    var t = line.trim().replace(/^\|/, '').replace(/\|\s*$/, '');
    var cells = [], cur = '', tick = false;
    for (var i = 0; i < t.length; i++) {
        var ch = t[i];
        if (ch === '\\' && t[i + 1] === '|') { cur += '|'; i++; continue; }
        if (ch === '`') tick = !tick;
        if (ch === '|' && !tick) { cells.push(cur); cur = ''; continue; }
        cur += ch;
    }
    cells.push(cur);
    return cells.map(function (c) { return c.trim(); });
}

function renderList(items, ctx) {
    var html = '', stack = [];
    for (var i = 0; i < items.length; i++) {
        var it = items[i];
        while (stack.length && it.indent < stack[stack.length - 1].indent) {
            html += '</li></' + stack.pop().tag + '>';
        }
        if (!stack.length || it.indent > stack[stack.length - 1].indent) {
            stack.push({ tag: it.tag, indent: it.indent });
            html += '<' + it.tag + '>';
        } else {
            html += '</li>';
        }
        html += '<li>' + renderInline(it.text, ctx);
    }
    while (stack.length) html += '</li></' + stack.pop().tag + '>';
    return html;
}

function renderBlocks(lines, ctx, toc, seenSlugs) {
    var out = [];
    var i = 0;

    while (i < lines.length) {
        var line = lines[i];

        if (!line.trim()) { i++; continue; }

        // Fenced code
        var fence = /^\s*(```|~~~)\s*([A-Za-z0-9_+#.-]*)\s*$/.exec(line);
        if (fence) {
            var marker = fence[1], lang = fence[2], buf = [];
            i++;
            while (i < lines.length && lines[i].trim().indexOf(marker) !== 0) { buf.push(lines[i]); i++; }
            i++;
            out.push('<pre><code' + (lang ? ' class="language-' + escapeHtml(lang) + '"' : '') + '>' +
                escapeHtml(buf.join('\n')) + '</code></pre>');
            continue;
        }

        // Headings
        var h = /^\s{0,3}(#{1,6})\s+(.*)$/.exec(line);
        if (h) {
            var level = h[1].length;
            var text = h[2].replace(/\s+#+\s*$/, '').trim();
            var slug = uniqueSlug(slugify(text), seenSlugs);
            if (level === 2 || level === 3) toc.push({ level: level, text: plainInline(text), slug: slug });
            out.push('<h' + level + ' id="' + slug + '">' + renderInline(text, ctx) +
                '<a class="wiki-anchor" href="#/' + ctx.id + '::' + slug + '" aria-label="Link to this section">#</a></h' + level + '>');
            i++;
            continue;
        }

        // Thematic break
        if (/^\s*(-{3,}|\*{3,}|_{3,})\s*$/.test(line)) { out.push('<hr>'); i++; continue; }

        // Table
        if (/^\s*\|/.test(line) && isTableSeparator(lines[i + 1])) {
            var head = splitRow(line);
            var aligns = splitRow(lines[i + 1]).map(function (c) {
                if (/^:.*:$/.test(c)) return 'center';
                if (/:$/.test(c)) return 'right';
                if (/^:/.test(c)) return 'left';
                return '';
            });
            i += 2;
            var thead = '<thead><tr>' + head.map(function (c, k) {
                var a = aligns[k] ? ' style="text-align:' + aligns[k] + '"' : '';
                return '<th' + a + '>' + renderInline(c, ctx) + '</th>';
            }).join('') + '</tr></thead>';
            var body = '';
            while (i < lines.length && /^\s*\|/.test(lines[i])) {
                var cells = splitRow(lines[i]);
                body += '<tr>' + cells.map(function (c, k) {
                    var a = aligns[k] ? ' style="text-align:' + aligns[k] + '"' : '';
                    return '<td' + a + '>' + renderInline(c, ctx) + '</td>';
                }).join('') + '</tr>';
                i++;
            }
            out.push('<div class="wiki-table-wrap"><table>' + thead + '<tbody>' + body + '</tbody></table></div>');
            continue;
        }

        // Blockquote
        if (/^\s*>/.test(line)) {
            var quote = [];
            while (i < lines.length && /^\s*>/.test(lines[i])) {
                quote.push(lines[i].replace(/^\s*>\s?/, ''));
                i++;
            }
            out.push('<blockquote>' + renderBlocks(quote, ctx, [], seenSlugs) + '</blockquote>');
            continue;
        }

        // Lists
        if (/^\s*([-*+]|\d+[.)])\s+/.test(line)) {
            var items = [];
            while (i < lines.length) {
                var m = /^(\s*)([-*+]|\d+[.)])\s+(.*)$/.exec(lines[i]);
                if (m) {
                    items.push({
                        indent: m[1].replace(/\t/g, '  ').length,
                        tag: /\d/.test(m[2].charAt(0)) ? 'ol' : 'ul',
                        text: m[3]
                    });
                    i++;
                    continue;
                }
                if (!lines[i].trim()) {
                    if (i + 1 < lines.length && /^\s*([-*+]|\d+[.)])\s+/.test(lines[i + 1])) { i++; continue; }
                    break;
                }
                // Lazy continuation of the previous item.
                if (items.length && /^\s+\S/.test(lines[i]) && !isBlockStart(lines[i])) {
                    items[items.length - 1].text += ' ' + lines[i].trim();
                    i++;
                    continue;
                }
                break;
            }
            out.push(renderList(items, ctx));
            continue;
        }

        // Paragraph
        var para = [];
        while (i < lines.length && lines[i].trim() && !isBlockStart(lines[i])) { para.push(lines[i]); i++; }
        out.push('<p>' + renderInline(para.join('\n'), ctx).replace(/ {2,}\n/g, '<br>\n') + '</p>');
    }

    return out.join('\n');
}

// Heading text with inline markers removed — for the "On this page" rail.
function plainInline(s) {
    return String(s)
        .replace(/`([^`]+)`/g, '$1')
        .replace(/!\[[^\]]*\]\([^)]*\)/g, '')
        .replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
        .replace(/\*\*?|~~|_/g, '')
        .trim();
}

function renderMarkdown(md, ctx) {
    var lines = String(md).replace(/\r\n?/g, '\n').replace(/\t/g, '    ').split('\n');
    var toc = [];
    var html = renderBlocks(lines, ctx, toc, {});
    return { html: html, toc: toc };
}

// Plain text for the client-side search index. Code blocks are kept (people
// search for `/make-it` and command names), only the fence markers go.
function toPlainText(md) {
    return String(md)
        .replace(/\r\n?/g, '\n')
        .replace(/^\s*(```|~~~).*$/gm, ' ')
        .replace(/`([^`]+)`/g, '$1')
        .replace(/!\[[^\]]*\]\([^)]*\)/g, ' ')
        .replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
        .replace(/^\s{0,3}#{1,6}\s+/gm, '')
        .replace(/^\s*>\s?/gm, '')
        .replace(/^\s*([-*+]|\d+[.)])\s+/gm, '')
        .replace(/^\s*(-{3,}|\*{3,}|_{3,})\s*$/gm, ' ')
        .replace(/\|/g, ' ')
        .replace(/\*\*?|~~/g, '')
        .replace(/[ \t]+/g, ' ')
        .replace(/\n{2,}/g, '\n')
        .trim();
}

// ---------------------------------------------------------------------------
// Document discovery
// ---------------------------------------------------------------------------

function listIds(source) {
    var dir = SOURCES[source];
    var names;
    try { names = fs.readdirSync(dir); } catch (e) { return []; }
    return names
        .filter(function (n) {
            return /\.md$/i.test(n) && n.toLowerCase() !== 'readme.md' && n.charAt(0) !== '_' && n.charAt(0) !== '.';
        })
        .map(function (n) { return source + '/' + n.replace(/\.md$/i, ''); })
        .sort();
}

function resolvePath(id) {
    var m = /^([a-z-]+)\/([A-Za-z0-9][A-Za-z0-9._-]*)$/.exec(String(id || ''));
    if (!m) return null;
    var dir = SOURCES[m[1]];
    if (!dir || m[2].indexOf('..') !== -1) return null;
    var file = path.join(dir, m[2] + '.md');
    if (file.indexOf(dir + path.sep) !== 0) return null;
    return file;
}

// mtime-keyed cache: the baked ccdw docs never change until the image is rebuilt,
// and the make-it docs are refreshed on container start, so a stat is enough.
var cache = Object.create(null);

function readDoc(id) {
    var file = resolvePath(id);
    if (!file) return null;

    var st;
    try { st = fs.statSync(file); } catch (e) { return null; }

    var hit = cache[id];
    if (hit && hit.mtimeMs === st.mtimeMs && hit.size === st.size) return hit.doc;

    var raw;
    try { raw = fs.readFileSync(file, 'utf8'); } catch (e) { return null; }

    var source = id.split('/')[0];
    var heading = /^\s{0,3}#\s+(.*)$/m.exec(raw);
    var title = heading ? plainInline(heading[1]) : prettifyName(id.split('/')[1]);
    var rendered = renderMarkdown(raw, { id: id, source: source });

    var doc = {
        id: id,
        source: source,
        title: title,
        html: rendered.html,
        toc: rendered.toc,
        text: toPlainText(raw)
    };

    cache[id] = { mtimeMs: st.mtimeMs, size: st.size, doc: doc };
    return doc;
}

function prettifyName(name) {
    return String(name).replace(/^\d+[-_]?/, '').replace(/[-_]+/g, ' ').replace(/\b\w/g, function (c) { return c.toUpperCase(); });
}

function buildIndex() {
    var available = Object.create(null);
    var all = [];
    Object.keys(SOURCES).forEach(function (source) {
        listIds(source).forEach(function (id) { available[id] = true; all.push(id); });
    });

    var used = Object.create(null);
    var groups = GROUPS.map(function (g) {
        var ids = g.ids.filter(function (id) { return available[id]; });
        ids.forEach(function (id) { used[id] = true; });
        return { title: g.title, ids: ids, overflow: g.overflow };
    });

    groups.forEach(function (g) {
        if (!g.overflow) return;
        all.forEach(function (id) {
            if (id.indexOf(g.overflow + '/') === 0 && !used[id]) { g.ids.push(id); used[id] = true; }
        });
    });

    return groups
        .filter(function (g) { return g.ids.length; })
        .map(function (g) {
            return {
                title: g.title,
                pages: g.ids.map(function (id) {
                    var doc = readDoc(id);
                    return { id: id, title: doc ? doc.title : prettifyName(id.split('/')[1]) };
                })
            };
        });
}

// Whole corpus as plain text, for the client-side search index.
function buildSearchIndex() {
    var docs = [];
    buildIndex().forEach(function (group) {
        group.pages.forEach(function (p) {
            var doc = readDoc(p.id);
            if (doc) docs.push({ id: doc.id, title: doc.title, group: group.title, text: doc.text });
        });
    });
    return docs;
}

function findImage(name) {
    var base = path.basename(String(name || ''));
    if (!base || base.indexOf('..') !== -1) return null;
    for (var i = 0; i < IMG_DIRS.length; i++) {
        var file = path.join(IMG_DIRS[i], base);
        if (file.indexOf(IMG_DIRS[i] + path.sep) === 0 && fs.existsSync(file)) return file;
    }
    return null;
}

module.exports = {
    SOURCES: SOURCES,
    buildIndex: buildIndex,
    buildSearchIndex: buildSearchIndex,
    readDoc: readDoc,
    findImage: findImage,
    renderMarkdown: renderMarkdown
};
