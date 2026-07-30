// =============================================================================
// Working-directory browsing for Chat.
//
// A conversation is bound to a folder, so the folder picker needs to list the
// mounted host tree. Browsing is confined to the directories the container
// actually binds from the Mac -- listing / would expose credential stores
// (~/.aws, ~/.azure, ~/.claude) that have no business in a folder picker.
// =============================================================================

const fs = require('fs');
const os = require('os');
const path = require('path');

const HOME = process.env.HOME || os.homedir();

// Override with CCDW_CHAT_ROOTS=/a:/b for a differently-mounted install.
const ROOTS = (process.env.CCDW_CHAT_ROOTS
  ? process.env.CCDW_CHAT_ROOTS.split(':')
  : [
      path.join(HOME, 'Documents'),
      path.join(HOME, 'Desktop'),
      path.join(HOME, 'Downloads'),
      '/Volumes',
    ]
).filter(p => p && fs.existsSync(p));

const DEFAULT_CWD = ROOTS[0] || HOME;

function roots() {
  return ROOTS.map(p => ({ path: p, name: path.basename(p) || p }));
}

/** Absolute, symlink-resolved, and inside a root -- or null. */
function resolveSafe(target) {
  if (!target) return null;
  let abs;
  try {
    abs = fs.realpathSync(path.resolve(target));
  } catch {
    return null;
  }
  for (const root of ROOTS) {
    let realRoot;
    try { realRoot = fs.realpathSync(root); } catch { continue; }
    if (abs === realRoot || abs.startsWith(realRoot + path.sep)) return abs;
  }
  return null;
}

function isDir(p) {
  try { return fs.statSync(p).isDirectory(); } catch { return false; }
}

/**
 * List subdirectories of `target`, plus a marker for whether it looks like a
 * project -- the picker shows a git badge so people can find their repos.
 */
function list(target) {
  const dir = resolveSafe(target) || DEFAULT_CWD;
  if (!isDir(dir)) return { path: dir, parent: null, entries: [] };

  let names = [];
  try {
    names = fs.readdirSync(dir, { withFileTypes: true })
      .filter(d => d.isDirectory() && !d.name.startsWith('.'))
      .map(d => d.name)
      .sort((a, b) => a.localeCompare(b, undefined, { sensitivity: 'base' }));
  } catch { /* unreadable dir -- show it as empty rather than erroring */ }

  const entries = names.map(name => {
    const full = path.join(dir, name);
    return { name, path: full, git: isDir(path.join(full, '.git')) };
  });

  // Only offer "up" while it stays inside an allowed root.
  const parent = resolveSafe(path.dirname(dir));
  return {
    path: dir,
    parent: parent && parent !== dir ? parent : null,
    git: isDir(path.join(dir, '.git')),
    entries,
  };
}

/** Sanitise a cwd coming from a stored conversation or a client request. */
function normalize(target) {
  const safe = resolveSafe(target);
  return safe && isDir(safe) ? safe : DEFAULT_CWD;
}

module.exports = { roots, list, normalize, resolveSafe, DEFAULT_CWD };
