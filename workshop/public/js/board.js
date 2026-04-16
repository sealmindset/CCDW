/**
 * Board Controller
 * Manages the iterate request board -- tracks change requests,
 * their status, and links them to the iterate chat.
 */

class BoardController {
  constructor(containerId) {
    this.container = document.getElementById(containerId);
    this.requests = [];
    this.nextId = 1;
  }

  /**
   * Add a new request to the board.
   */
  addRequest(text, priority) {
    const request = {
      id: this.nextId++,
      text,
      priority: priority || 'normal',  // quick | normal | big
      status: 'pending',               // pending | in-progress | done
      createdAt: new Date(),
    };

    this.requests.push(request);
    this.render();
    return request;
  }

  /**
   * Update a request's status.
   */
  updateStatus(id, status) {
    const req = this.requests.find(r => r.id === id);
    if (req) {
      req.status = status;
      this.render();
    }
  }

  /**
   * Mark the most recent in-progress request as done.
   */
  completeCurrent() {
    const current = this.requests.find(r => r.status === 'in-progress');
    if (current) {
      current.status = 'done';
      this.render();
    }
  }

  /**
   * Start the next pending request.
   */
  startNext() {
    const next = this.requests.find(r => r.status === 'pending');
    if (next) {
      next.status = 'in-progress';
      this.render();
      return next;
    }
    return null;
  }

  /**
   * Render the board.
   */
  render() {
    this.container.innerHTML = '';

    if (this.requests.length === 0) {
      this.container.innerHTML = '<p class="board-empty">No changes yet. Describe what you\'d like to change in the chat.</p>';
      return;
    }

    // Group by status
    const groups = [
      { label: 'In Progress', items: this.requests.filter(r => r.status === 'in-progress') },
      { label: 'Pending', items: this.requests.filter(r => r.status === 'pending') },
      { label: 'Done', items: this.requests.filter(r => r.status === 'done') },
    ];

    groups.forEach(group => {
      if (group.items.length === 0) return;

      const heading = document.createElement('div');
      heading.className = 'board-group-label';
      heading.textContent = group.label;
      this.container.appendChild(heading);

      group.items.forEach(req => {
        const el = document.createElement('div');
        el.className = `board-item board-${req.status}`;

        const statusIcon = req.status === 'done' ? '\u2713'
          : req.status === 'in-progress' ? '\u25CB'
          : '\u2022';

        const priorityBadge = req.priority === 'big'
          ? '<span class="board-badge big">Feature</span>'
          : req.priority === 'quick'
          ? '<span class="board-badge quick">Quick</span>'
          : '';

        el.innerHTML = `
          <span class="board-item-icon">${statusIcon}</span>
          <span class="board-item-text">${this.escapeHtml(req.text)}</span>
          ${priorityBadge}
        `;

        this.container.appendChild(el);
      });
    });
  }

  escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }
}

// Global instance
window.board = new BoardController('boardItems');
