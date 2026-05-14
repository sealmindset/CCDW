window.Sidebar = {
  el: null,
  listEl: null,
  searchEl: null,
  conversations: [],
  activeId: null,
  onSelect: null,
  onNew: null,
  onDelete: null,
  onStar: null,

  init(el, listEl, searchEl) {
    this.el = el;
    this.listEl = listEl;
    this.searchEl = searchEl;

    searchEl.addEventListener('input', () => this.render());
  },

  setConversations(convos) {
    this.conversations = convos;
    this.render();
  },

  setActive(id) {
    this.activeId = id;
    this.render();
  },

  render() {
    const query = this.searchEl.value.toLowerCase();
    let filtered = this.conversations;
    if (query) {
      filtered = filtered.filter(c => c.title.toLowerCase().includes(query));
    }

    const starred = filtered.filter(c => c.starred);
    const unstarred = filtered.filter(c => !c.starred);

    const groups = [];
    if (starred.length) groups.push({ label: 'Starred', items: starred });

    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const yesterday = new Date(today.getTime() - 86400000);
    const week = new Date(today.getTime() - 7 * 86400000);

    const todayItems = [], yesterdayItems = [], weekItems = [], olderItems = [];
    for (const c of unstarred) {
      const d = new Date(c.updated_at);
      if (d >= today) todayItems.push(c);
      else if (d >= yesterday) yesterdayItems.push(c);
      else if (d >= week) weekItems.push(c);
      else olderItems.push(c);
    }

    if (todayItems.length) groups.push({ label: 'Today', items: todayItems });
    if (yesterdayItems.length) groups.push({ label: 'Yesterday', items: yesterdayItems });
    if (weekItems.length) groups.push({ label: 'Previous 7 Days', items: weekItems });
    if (olderItems.length) groups.push({ label: 'Older', items: olderItems });

    let html = '';
    for (const g of groups) {
      html += `<div class="sidebar-group-label">${g.label}</div>`;
      for (const c of g.items) {
        const active = c.id === this.activeId ? ' active' : '';
        const star = c.starred ? ' starred' : '';
        html += `<div class="sidebar-item${active}${star}" data-id="${c.id}">
          <div class="sidebar-item-title">${this.esc(c.title)}</div>
          <div class="sidebar-item-meta">${c.message_count || 0} messages</div>
          <div class="sidebar-item-actions">
            <button class="sidebar-btn-star" data-id="${c.id}" title="${c.starred ? 'Unstar' : 'Star'}">${c.starred ? '★' : '☆'}</button>
            <button class="sidebar-btn-del" data-id="${c.id}" title="Delete">×</button>
          </div>
        </div>`;
      }
    }

    if (!html) {
      html = '<div class="sidebar-empty">No conversations yet</div>';
    }

    this.listEl.innerHTML = html;

    this.listEl.querySelectorAll('.sidebar-item').forEach(el => {
      el.addEventListener('click', (e) => {
        if (e.target.closest('.sidebar-btn-star') || e.target.closest('.sidebar-btn-del')) return;
        this.onSelect?.(el.dataset.id);
      });
    });
    this.listEl.querySelectorAll('.sidebar-btn-star').forEach(el => {
      el.addEventListener('click', () => this.onStar?.(el.dataset.id));
    });
    this.listEl.querySelectorAll('.sidebar-btn-del').forEach(el => {
      el.addEventListener('click', () => this.onDelete?.(el.dataset.id));
    });
  },

  esc(s) {
    const d = document.createElement('div');
    d.textContent = s;
    return d.innerHTML;
  },
};
