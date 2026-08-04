// CCDW Wiki front end.
//
// Routes are hashes so the whole thing is one static page served from the
// Dashboard server: #/<source>/<slug>[::<heading-anchor>]
//   #/ccdw/04-dashboard
//   #/make-it/01-make-it::what-it-does
//
// Content comes from /api/wiki/* — markdown rendered server-side. No bundler,
// no dependencies, no CDN.

(function () {
    'use strict';

    var NAV_H = 44;

    var el = {
        tree: document.getElementById('tree'),
        results: document.getElementById('results'),
        search: document.getElementById('searchInput'),
        doc: document.getElementById('doc'),
        toc: document.getElementById('toc'),
        pager: document.getElementById('pager'),
        foot: document.getElementById('foot'),
        sidebar: document.getElementById('sidebar'),
        toggle: document.getElementById('contentsToggle')
    };

    var groups = [];        // [{ title, pages: [{id, title}] }]
    var flat = [];          // pages in reading order, with group titles
    var searchDocs = null;  // lazily fetched plain-text corpus
    var searchPending = null;
    var lastQuery = '';
    var currentId = '';
    var observer = null;

    // ---------------------------------------------------------------- helpers

    function esc(s) {
        return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }

    function escRe(s) {
        return String(s).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    }

    function getJSON(url) {
        return fetch(url, { cache: 'no-store' }).then(function (r) {
            if (!r.ok) throw new Error(url + ' -> ' + r.status);
            return r.json();
        });
    }

    function sourceLabel(id) {
        var source = id.split('/')[0];
        var slug = id.split('/').slice(1).join('/');
        if (source === 'make-it') return '~/.claude/make-it/confluence-docs/' + slug + '.md';
        return 'docs/confluence/' + slug + '.md';
    }

    function parseRoute() {
        var raw = (location.hash || '').replace(/^#\/?/, '');
        if (!raw) return { id: flat.length ? flat[0].id : '', anchor: '' };
        var parts = raw.split('::');
        return { id: decodeURIComponent(parts[0]), anchor: parts[1] ? decodeURIComponent(parts[1]) : '' };
    }

    // ------------------------------------------------------------------- tree

    function renderTree() {
        var html = '';
        groups.forEach(function (g) {
            html += '<div class="wiki-tree-group"><div class="wiki-tree-title">' + esc(g.title) + '</div>';
            g.pages.forEach(function (p) {
                html += '<a href="#/' + esc(p.id) + '" data-id="' + esc(p.id) + '">' + esc(p.title) + '</a>';
            });
            html += '</div>';
        });
        el.tree.innerHTML = html;
    }

    function markActive(id) {
        var links = el.tree.querySelectorAll('a');
        for (var i = 0; i < links.length; i++) {
            if (links[i].getAttribute('data-id') === id) {
                links[i].classList.add('active');
                links[i].scrollIntoView({ block: 'nearest' });
            } else {
                links[i].classList.remove('active');
            }
        }
    }

    // ------------------------------------------------------------------- page

    function loadPage(id, anchor) {
        el.doc.innerHTML = '<p class="wiki-loading">Loading…</p>';
        el.toc.innerHTML = '';
        el.pager.innerHTML = '';
        el.foot.innerHTML = '';

        getJSON('/api/wiki/page?id=' + encodeURIComponent(id)).then(function (page) {
            currentId = page.id;
            document.title = page.title + ' — CCDW Wiki';
            el.doc.innerHTML = page.html;
            markActive(page.id);
            renderToc(page.toc);
            renderPager(page.id);
            el.foot.innerHTML = 'Source: <code>' + esc(sourceLabel(page.id)) + '</code>';
            addCopyButtons();

            if (lastQuery) highlight(lastQuery);

            if (anchor) {
                var target = document.getElementById(anchor);
                if (target) { scrollToEl(target); return; }
            }
            if (lastQuery) {
                var mark = el.doc.querySelector('mark');
                if (mark) { scrollToEl(mark); return; }
            }
            window.scrollTo(0, 0);
        }).catch(function (err) {
            el.doc.innerHTML = '<h1>Page not found</h1><p>Could not load <code>' + esc(id) +
                '</code>. Pick a page from the list on the left.</p>';
            el.foot.textContent = String(err.message || err);
        });
    }

    function scrollToEl(node) {
        var top = node.getBoundingClientRect().top + window.pageYOffset - NAV_H - 12;
        window.scrollTo(0, top < 0 ? 0 : top);
    }

    function renderToc(toc) {
        if (!toc || !toc.length) { el.toc.innerHTML = ''; return; }
        var html = '<div class="wiki-toc-title">On this page</div>';
        toc.forEach(function (h) {
            html += '<a class="lvl-' + h.level + '" href="#/' + esc(currentId) + '::' + esc(h.slug) +
                '" data-slug="' + esc(h.slug) + '">' + esc(h.text) + '</a>';
        });
        el.toc.innerHTML = html;
        spy(toc);
    }

    // Highlights the heading you are currently reading in the right rail.
    function spy(toc) {
        if (observer) { observer.disconnect(); observer = null; }
        if (!window.IntersectionObserver) return;

        var links = {};
        var tocLinks = el.toc.querySelectorAll('a');
        for (var i = 0; i < tocLinks.length; i++) links[tocLinks[i].getAttribute('data-slug')] = tocLinks[i];

        var visible = {};
        observer = new IntersectionObserver(function (entries) {
            entries.forEach(function (e) { visible[e.target.id] = e.isIntersecting; });
            var chosen = '';
            for (var k = 0; k < toc.length; k++) {
                if (visible[toc[k].slug]) { chosen = toc[k].slug; break; }
            }
            Object.keys(links).forEach(function (slug) {
                links[slug].classList.toggle('active', slug === chosen);
            });
        }, { rootMargin: '-' + (NAV_H + 8) + 'px 0px -70% 0px' });

        toc.forEach(function (h) {
            var node = document.getElementById(h.slug);
            if (node) observer.observe(node);
        });
    }

    function renderPager(id) {
        var i = -1;
        for (var k = 0; k < flat.length; k++) if (flat[k].id === id) { i = k; break; }
        if (i === -1) return;

        var html = '';
        if (i > 0) {
            html += '<a class="prev" href="#/' + esc(flat[i - 1].id) + '"><span>Previous</span><strong>' +
                esc(flat[i - 1].title) + '</strong></a>';
        }
        if (i < flat.length - 1) {
            html += '<a class="next" href="#/' + esc(flat[i + 1].id) + '"><span>Next</span><strong>' +
                esc(flat[i + 1].title) + '</strong></a>';
        }
        el.pager.innerHTML = html;
    }

    function addCopyButtons() {
        var pres = el.doc.querySelectorAll('pre');
        for (var i = 0; i < pres.length; i++) {
            (function (pre) {
                var btn = document.createElement('button');
                btn.className = 'wiki-copy';
                btn.type = 'button';
                btn.textContent = 'Copy';
                btn.addEventListener('click', function () {
                    var code = pre.querySelector('code');
                    var text = code ? code.textContent : pre.textContent;
                    var done = function () {
                        btn.textContent = 'Copied';
                        setTimeout(function () { btn.textContent = 'Copy'; }, 1400);
                    };
                    if (navigator.clipboard && navigator.clipboard.writeText) {
                        navigator.clipboard.writeText(text).then(done, function () { btn.textContent = 'Failed'; });
                    } else {
                        var ta = document.createElement('textarea');
                        ta.value = text;
                        document.body.appendChild(ta);
                        ta.select();
                        try { document.execCommand('copy'); done(); } catch (e) { btn.textContent = 'Failed'; }
                        document.body.removeChild(ta);
                    }
                });
                pre.appendChild(btn);
            })(pres[i]);
        }
    }

    // ----------------------------------------------------------------- search

    function tokens(q) {
        return String(q).toLowerCase().split(/\s+/).filter(function (t) { return t.length > 1; });
    }

    function ensureCorpus() {
        if (searchDocs) return Promise.resolve(searchDocs);
        if (!searchPending) {
            searchPending = getJSON('/api/wiki/search').then(function (docs) {
                searchDocs = docs.map(function (d) {
                    return { id: d.id, title: d.title, group: d.group, text: d.text, lcTitle: d.title.toLowerCase(), lcText: d.text.toLowerCase() };
                });
                return searchDocs;
            });
        }
        return searchPending;
    }

    function countOccurrences(haystack, needle) {
        var n = 0, i = haystack.indexOf(needle);
        while (i !== -1 && n < 50) { n++; i = haystack.indexOf(needle, i + needle.length); }
        return n;
    }

    function search(q) {
        var terms = tokens(q);
        if (!terms.length) return [];

        var hits = [];
        searchDocs.forEach(function (d) {
            var score = 0, all = true;
            terms.forEach(function (t) {
                var inTitle = d.lcTitle.indexOf(t) !== -1;
                var inText = countOccurrences(d.lcText, t);
                if (!inTitle && !inText) all = false;
                if (inTitle) score += 20;
                score += Math.min(inText, 12);
            });
            if (all) hits.push({ doc: d, score: score });
        });

        hits.sort(function (a, b) { return b.score - a.score || a.doc.title.localeCompare(b.doc.title); });
        return hits.slice(0, 40).map(function (h) {
            return { id: h.doc.id, title: h.doc.title, group: h.doc.group, snippet: snippet(h.doc, terms) };
        });
    }

    function snippet(doc, terms) {
        var best = -1, term = '';
        terms.forEach(function (t) {
            var i = doc.lcText.indexOf(t);
            if (i !== -1 && (best === -1 || t.length > term.length)) { best = i; term = t; }
        });
        if (best === -1) return esc(doc.text.slice(0, 120)) + '…';

        var start = Math.max(0, best - 55);
        var raw = doc.text.slice(start, start + 190).replace(/\s+/g, ' ');
        var out = esc(raw);
        terms.forEach(function (t) {
            out = out.replace(new RegExp('(' + escRe(esc(t)) + ')', 'gi'), '<mark>$1</mark>');
        });
        return (start > 0 ? '…' : '') + out + '…';
    }

    function renderResults(q) {
        var hits = search(q);
        if (!hits.length) {
            el.results.innerHTML = '<div class="wiki-results-count">No matches for “' + esc(q) + '”</div>';
        } else {
            var html = '<div class="wiki-results-count">' + hits.length + (hits.length === 1 ? ' match' : ' matches') + '</div>';
            hits.forEach(function (h) {
                html += '<a class="wiki-result" href="#/' + esc(h.id) + '">' +
                    '<div class="wiki-result-group">' + esc(h.group) + '</div>' +
                    '<div class="wiki-result-title">' + esc(h.title) + '</div>' +
                    '<div class="wiki-result-snippet">' + h.snippet + '</div></a>';
            });
            el.results.innerHTML = html;
        }
        el.results.hidden = false;
        el.tree.hidden = true;
    }

    function clearResults() {
        el.results.hidden = true;
        el.results.innerHTML = '';
        el.tree.hidden = false;
    }

    // Highlights the active query inside the loaded page, so a search result
    // lands you on the actual sentence rather than the top of the page.
    function highlight(q) {
        var terms = tokens(q);
        if (!terms.length) return;
        var re = new RegExp('(' + terms.map(escRe).join('|') + ')', 'gi');

        var walker = document.createTreeWalker(el.doc, NodeFilter.SHOW_TEXT, {
            acceptNode: function (node) {
                if (!node.nodeValue.trim()) return NodeFilter.FILTER_REJECT;
                var p = node.parentNode;
                while (p && p !== el.doc) {
                    var tag = p.nodeName;
                    if (tag === 'MARK' || tag === 'SCRIPT' || tag === 'STYLE' || tag === 'BUTTON') return NodeFilter.FILTER_REJECT;
                    p = p.parentNode;
                }
                return re.test(node.nodeValue) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
            }
        });

        var targets = [], node;
        while ((node = walker.nextNode())) targets.push(node);

        targets.forEach(function (text) {
            var frag = document.createDocumentFragment();
            var last = 0, m;
            re.lastIndex = 0;
            while ((m = re.exec(text.nodeValue))) {
                if (m.index > last) frag.appendChild(document.createTextNode(text.nodeValue.slice(last, m.index)));
                var mark = document.createElement('mark');
                mark.textContent = m[0];
                frag.appendChild(mark);
                last = m.index + m[0].length;
            }
            if (last < text.nodeValue.length) frag.appendChild(document.createTextNode(text.nodeValue.slice(last)));
            text.parentNode.replaceChild(frag, text);
        });
    }

    // ------------------------------------------------------------------ wiring

    var debounce = null;
    el.search.addEventListener('input', function () {
        var q = el.search.value.trim();
        clearTimeout(debounce);
        if (!q) { lastQuery = ''; clearResults(); return; }
        debounce = setTimeout(function () {
            ensureCorpus().then(function () {
                lastQuery = q;
                renderResults(q);
            }).catch(function () {
                el.results.innerHTML = '<div class="wiki-results-count">Search index unavailable</div>';
                el.results.hidden = false;
                el.tree.hidden = true;
            });
        }, 120);
    });

    el.search.addEventListener('keydown', function (e) {
        if (e.key === 'Escape') {
            el.search.value = '';
            lastQuery = '';
            clearResults();
            el.search.blur();
        }
        if (e.key === 'Enter') {
            var first = el.results.querySelector('a.wiki-result');
            if (first) { location.hash = first.getAttribute('href').slice(1); el.search.blur(); }
        }
    });

    document.addEventListener('keydown', function (e) {
        if (e.key !== '/' || e.metaKey || e.ctrlKey || e.altKey) return;
        var t = e.target;
        if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable)) return;
        e.preventDefault();
        el.search.focus();
        el.search.select();
    });

    el.toggle.addEventListener('click', function () {
        var open = el.sidebar.classList.toggle('open');
        el.toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
    });

    // Picking a page on a phone should close the drawer again.
    el.sidebar.addEventListener('click', function (e) {
        var a = e.target.closest ? e.target.closest('a') : null;
        if (a) el.sidebar.classList.remove('open');
    });

    function route() {
        var r = parseRoute();
        if (!r.id) return;
        if (r.id === currentId) {
            var target = r.anchor ? document.getElementById(r.anchor) : null;
            if (target) { scrollToEl(target); return; }
            if (!r.anchor) { window.scrollTo(0, 0); return; }
        }
        loadPage(r.id, r.anchor);
    }

    window.addEventListener('hashchange', route);

    getJSON('/api/wiki/index').then(function (data) {
        groups = data.groups || [];
        flat = [];
        groups.forEach(function (g) {
            g.pages.forEach(function (p) { flat.push({ id: p.id, title: p.title, group: g.title }); });
        });
        renderTree();
        if (!flat.length) {
            el.doc.innerHTML = '<h1>No pages found</h1><p>The wiki sources are missing from this container.</p>';
            return;
        }
        route();
    }).catch(function (err) {
        el.doc.innerHTML = '<h1>Wiki unavailable</h1><p>Could not load the page index: <code>' +
            esc(String(err.message || err)) + '</code></p>';
    });
})();
