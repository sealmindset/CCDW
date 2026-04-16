/**
 * Bifrost Controller
 * Manages the animated progress bar, phase transitions,
 * walker movement, and bug encounters.
 */

class BifrostController {
  constructor() {
    this.phases = ['ideation', 'design', 'building', 'complete'];
    this.currentPhaseIndex = -1;
    this.isAnimating = false;

    // DOM elements
    this.glow = document.getElementById('bifrostGlow');
    this.walker = document.getElementById('bifrostWalker');
    this.bug = document.getElementById('bifrostBug');
    this.bugDefeat = document.getElementById('bugDefeat');
    this.phaseNodes = document.querySelectorAll('.phase-node');
  }

  /**
   * Set the current phase. Animates the Bifrost forward.
   */
  setPhase(phaseName) {
    const index = this.phases.indexOf(phaseName);
    if (index === -1 || index <= this.currentPhaseIndex) return;

    this.currentPhaseIndex = index;
    this.updateProgress();
    this.updatePhaseNodes();
    this.moveWalker();
  }

  /**
   * Update the glow progress bar.
   */
  updateProgress() {
    const progressMap = [0, 25, 50, 75, 100];
    // For "complete" (index 3), we want 100%
    const progress = this.currentPhaseIndex >= 0
      ? progressMap[this.currentPhaseIndex + 1] || 0
      : 0;
    this.glow.setAttribute('data-progress', progress.toString());
  }

  /**
   * Update phase circle states.
   */
  updatePhaseNodes() {
    this.phaseNodes.forEach((node, i) => {
      node.classList.remove('active', 'completed');
      if (i < this.currentPhaseIndex) {
        node.classList.add('completed');
      } else if (i === this.currentPhaseIndex) {
        node.classList.add('active');
      }
    });
  }

  /**
   * Move the walker icon to the current phase position.
   */
  moveWalker() {
    const positions = ['phase-1', 'phase-2', 'phase-3', 'phase-4'];
    const pos = positions[this.currentPhaseIndex] || 'start';
    this.walker.setAttribute('data-position', pos);
  }

  /**
   * Show a bug at the current walker position.
   * Called when a test fails or an issue is found.
   */
  showBug() {
    if (!this.bug) return;

    // Position bug slightly ahead of walker
    const walkerLeft = parseFloat(getComputedStyle(this.walker).left);
    this.bug.style.left = (walkerLeft + 40) + 'px';

    this.bug.classList.remove('hidden', 'defeating');
    this.bugDefeat.classList.add('hidden');
  }

  /**
   * Animate defeating the bug.
   * Called when the issue is fixed.
   */
  defeatBug() {
    if (!this.bug) return;

    this.bug.classList.add('defeating');
    this.bugDefeat.classList.remove('hidden');

    setTimeout(() => {
      this.bug.classList.add('hidden');
      this.bug.classList.remove('defeating');
      this.bugDefeat.classList.add('hidden');
    }, 800);
  }

  /**
   * Reset to initial state.
   */
  reset() {
    this.currentPhaseIndex = -1;
    this.glow.setAttribute('data-progress', '0');
    this.walker.setAttribute('data-position', 'start');
    this.phaseNodes.forEach(node => {
      node.classList.remove('active', 'completed');
    });
    this.bug.classList.add('hidden');
  }

  /**
   * Complete animation -- all phases done, celebration effect.
   */
  complete() {
    this.currentPhaseIndex = this.phases.length - 1;
    this.updateProgress();
    this.moveWalker();

    // Mark all as completed
    this.phaseNodes.forEach(node => {
      node.classList.remove('active');
      node.classList.add('completed');
    });

    // Add a brief celebration glow
    this.glow.style.filter = 'brightness(1.3)';
    setTimeout(() => {
      this.glow.style.filter = '';
    }, 2000);
  }
}

// Global instance
window.bifrost = new BifrostController();
