import { execSync } from 'child_process';
import * as path from 'path';

export interface GitChange {
  /** X column (index/staged status) */
  x: string;
  /** Y column (worktree/unstaged status) */
  y: string;
  /** Path relative to repo root */
  filePath: string;
  /** Display label: M, A, D, ?, R, ... */
  badge: string;
  /** Tooltip color hint */
  color: 'modified' | 'untracked' | 'added' | 'deleted' | 'renamed' | 'conflict';
}

export function getGitChanges(repoRoot: string): GitChange[] {
  try {
    const output = execSync('git status --porcelain=v1 -uall', {
      cwd: repoRoot,
      encoding: 'utf8',
    });

    const changes: GitChange[] = [];

    for (const raw of output.split('\n')) {
      if (!raw.trim()) continue;

      const x = raw[0];
      const y = raw[1];
      // Handle renames: "R old -> new" — porcelain v1 uses " -> "
      const rest = raw.substring(3).trim();
      const filePath = rest.includes(' -> ') ? rest.split(' -> ')[1] : rest;

      let badge = (x !== ' ' && x !== '?' ? x : y).trim() || '?';
      let color: GitChange['color'] = 'modified';

      if (x === '?' && y === '?') {
        badge = 'U';
        color = 'untracked';
      } else if (x === 'A' || y === 'A') {
        badge = 'A';
        color = 'added';
      } else if (x === 'D' || y === 'D') {
        badge = 'D';
        color = 'deleted';
      } else if (x === 'R' || y === 'R') {
        badge = 'R';
        color = 'renamed';
      } else if ((x === 'U' || y === 'U') || (x === 'A' && y === 'A') || (x === 'D' && y === 'D')) {
        badge = 'C';
        color = 'conflict';
      }

      changes.push({ x, y, filePath, badge, color });
    }

    return changes;
  } catch {
    return [];
  }
}

/** Returns only the unique top-level segments (files or dirs) that have changes. */
export function getChangedRoots(repoRoot: string): Map<string, GitChange> {
  const changes = getGitChanges(repoRoot);
  const roots = new Map<string, GitChange>();

  for (const change of changes) {
    const root = change.filePath.split('/')[0];
    if (!roots.has(root)) {
      roots.set(root, change);
    }
  }

  return roots;
}

/** Returns all changed paths whose first segment matches a given root name. */
export function getChangesUnder(repoRoot: string, relDir: string): Map<string, GitChange> {
  const changes = getGitChanges(repoRoot);
  const map = new Map<string, GitChange>();

  for (const change of changes) {
    const normalized = change.filePath.replace(/\\/g, '/');
    const dir = relDir.replace(/\\/g, '/');
    if (normalized.startsWith(dir + '/') || normalized === dir) {
      map.set(path.join(repoRoot, change.filePath), change);
    }
  }

  return map;
}

/** Build a map of all changed absolute paths for quick lookup. */
export function buildChangedPathSet(repoRoot: string): Map<string, GitChange> {
  const changes = getGitChanges(repoRoot);
  const map = new Map<string, GitChange>();
  for (const c of changes) {
    map.set(path.join(repoRoot, c.filePath), c);
  }
  return map;
}
