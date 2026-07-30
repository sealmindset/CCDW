// =============================================================================
// Folder picker.
//
// A conversation is bound to a folder, which is what lets people talk about a
// project that has nothing to do with Workshop -- any directory on the mounted
// host tree, or a repo they cloned by hand. The header chip shows where the
// current thread is pointed; clicking it opens this browser.
// =============================================================================

window.WorkdirPicker = {
  dialog: null,
  listEl: null,
  crumbEl: null,
  useBtn: null,
  current: null,
  onPick: null,

  init(dialog, listEl, crumbEl, useBtn, closeBtn) {
    this.dialog = dialog;
    this.listEl = listEl;
    this.crumbEl = crumbEl;
    this.useBtn = useBtn;

    useBtn.addEventListener('click', () => {
      const picked = this.current;
      this.dialog.close();
      if (picked) this.onPick?.(picked);
    });
    closeBtn.addEventListener('click', () => this.dialog.close());
  },

  async show(startPath, onPick) {
    this.onPick = onPick;
    await this.navigate(startPath || null);
    this.dialog.showModal();
  },

  async navigate(target) {
    // Committing mid-navigation would bind the conversation to the folder you
    // just left, so the confirm button is dead until the listing lands.
    this.useBtn.disabled = true;
    this.useBtn.textContent = 'Loading…';

    let data;
    try {
      data = await ChatAPI.listWorkdir(target);
    } catch {
      this.listEl.innerHTML = '<div class="wd-empty">Could not read that folder.</div>';
      this.useBtn.disabled = false;
      return;
    }
    this.current = data.path;
    this.renderCrumb(data);
    this.renderList(data);
    this.useBtn.disabled = false;
  },

  renderCrumb(data) {
    this.crumbEl.textContent = data.path;
    this.useBtn.textContent = `Use ${data.path.split('/').filter(Boolean).pop() || data.path}`;
  },

  renderList(data) {
    this.listEl.innerHTML = '';

    if (data.parent) {
      this.listEl.appendChild(this.row('..', data.parent, false, true));
    }
    if (!data.entries.length) {
      const empty = document.createElement('div');
      empty.className = 'wd-empty';
      empty.textContent = 'No sub-folders here. Use this folder, or go up.';
      this.listEl.appendChild(empty);
      return;
    }
    for (const e of data.entries) {
      this.listEl.appendChild(this.row(e.name, e.path, e.git, false));
    }
  },

  row(name, path, isGit, isUp) {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'wd-row' + (isUp ? ' wd-up' : '');

    const icon = document.createElement('span');
    icon.className = 'wd-icon';
    icon.textContent = isUp ? '↑' : '\u{1F4C1}';

    const label = document.createElement('span');
    label.className = 'wd-name';
    label.textContent = name;

    btn.append(icon, label);
    if (isGit) {
      const badge = document.createElement('span');
      badge.className = 'wd-git';
      badge.textContent = 'git';
      btn.appendChild(badge);
    }
    btn.addEventListener('click', () => this.navigate(path));
    return btn;
  },
};

// Small header control showing the folder the active conversation is bound to.
window.WorkdirChip = {
  el: null,
  path: null,

  init(el, onClick) {
    this.el = el;
    el.addEventListener('click', onClick);
  },

  set(path) {
    this.path = path || null;
    if (!this.el) return;
    const short = path ? (path.split('/').filter(Boolean).pop() || path) : 'No folder';
    this.el.textContent = `\u{1F4C1} ${short}`;
    this.el.title = path || 'Pick a folder for this conversation';
  },
};
