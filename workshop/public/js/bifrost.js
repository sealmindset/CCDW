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
   * Set the current phase. Animates the Bifrost forward with staggered timing:
   * glow fills first, then walker moves, then circle activates.
   */
  setPhase(phaseName) {
    const index = this.phases.indexOf(phaseName);
    if (index === -1 || index <= this.currentPhaseIndex) return;

    this.currentPhaseIndex = index;
    this.updateProgress();
    setTimeout(() => this.moveWalker(), 200);
    setTimeout(() => this.updatePhaseNodes(), 500);
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
   * Show a bug slightly ahead of the walker's current position.
   * Uses the same percentage-based positioning as the walker.
   */
  showBug() {
    if (!this.bug) return;

    const positionPcts = { 'start': 2, 'phase-1': 8, 'phase-2': 36.7, 'phase-3': 65.3, 'phase-4': 92 };
    const walkerPos = this.walker.getAttribute('data-position') || 'start';
    const pct = (positionPcts[walkerPos] || 8) + 5;
    this.bug.style.left = pct + '%';

    this.bug.classList.remove('hidden', 'defeating');
    this.bugDefeat.classList.add('hidden');
  }

  /**
   * Animate defeating the bug with flash + shrink.
   */
  defeatBug() {
    if (!this.bug) return;

    this.bug.classList.add('defeating');
    this.bugDefeat.classList.remove('hidden');

    setTimeout(() => {
      this.bug.classList.add('hidden');
      this.bug.classList.remove('defeating');
      this.bugDefeat.classList.add('hidden');
    }, 900);
  }

  /**
   * Reset to initial state.
   */
  reset() {
    this.currentPhaseIndex = -1;
    this.glow.setAttribute('data-progress', '0');
    this.glow.classList.remove('celebrating');
    this.walker.setAttribute('data-position', 'start');
    this.walker.classList.remove('celebrating');
    this.phaseNodes.forEach(node => {
      node.classList.remove('active', 'completed');
    });
    if (this.bug) this.bug.classList.add('hidden');
  }

  /**
   * Complete animation -- all phases done, celebration sweep + walker jump.
   */
  complete() {
    this.currentPhaseIndex = this.phases.length - 1;
    this.updateProgress();
    this.moveWalker();

    // Mark all as completed with staggered pops
    this.phaseNodes.forEach((node, i) => {
      setTimeout(() => {
        node.classList.remove('active');
        node.classList.add('completed');
      }, i * 120);
    });

    // Celebration: light sweep across the bridge + walker jump
    setTimeout(() => {
      this.glow.classList.add('celebrating');
      this.walker.classList.add('celebrating');
    }, 500);

    // Clean up celebration classes
    setTimeout(() => {
      this.glow.classList.remove('celebrating');
      this.walker.classList.remove('celebrating');
    }, 2500);
  }
}

// Global instance
window.bifrost = new BifrostController();
