// Shared top navigation bar — injected into Dashboard, Workshop, Chat
// Detects current page by port/path and highlights the active link.
(function() {
    var host = window.location.hostname;
    var port = window.location.port;
    var path = window.location.pathname;

    var pages = [
        { id: 'dashboard', label: 'Dashboard', port: '3000', icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/></svg>' },
        { id: 'workshop', label: 'Workshop', port: '9200', icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>' },
        { id: 'chat', label: 'Claude Chat', port: '3002', icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>' },
        { id: 'vscode', label: 'VS Code', port: '8080', icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="3" width="20" height="14" rx="2" ry="2"/><line x1="8" y1="21" x2="16" y2="21"/><line x1="12" y1="17" x2="12" y2="21"/></svg>' },
        { id: 'terminal', label: 'Terminal', port: '7681', icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="4 17 10 11 4 5"/><line x1="12" y1="19" x2="20" y2="19"/></svg>' }
    ];

    // Determine active page
    var activePage = 'dashboard';
    if (port === '9200') activePage = 'workshop';
    else if (port === '3002') activePage = 'chat';
    else if (port === '8080') activePage = 'vscode';
    else if (port === '7681') activePage = 'terminal';

    // Build nav HTML
    var nav = document.createElement('nav');
    nav.className = 'shared-topnav';
    var inner = '<div class="shared-topnav-inner"><div class="shared-topnav-breadcrumb">';

    for (var i = 0; i < pages.length; i++) {
        var p = pages[i];
        var href = 'http://' + host + ':' + p.port;
        var cls = p.id === activePage ? ' class="active"' : '';
        if (i > 0) inner += '<span class="nav-sep">/</span>';
        inner += '<a href="' + href + '"' + cls + '>' + p.icon + '<span class="nav-label">' + p.label + '</span></a>';
    }

    inner += '</div></div>';
    nav.innerHTML = inner;

    // CSS is loaded via <link> in the HTML — no dynamic injection needed

    // Insert at top of body
    if (document.body.firstChild) {
        document.body.insertBefore(nav, document.body.firstChild);
    } else {
        document.body.appendChild(nav);
    }
})();
