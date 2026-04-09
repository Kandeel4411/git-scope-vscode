const assert = require('assert').strict;
const proxyquire = require('proxyquire');

function loadGitStatus(execSyncImpl) {
  return proxyquire('../out/gitStatus', {
    child_process: {
      execSync: execSyncImpl,
    },
  });
}

describe('gitStatus', () => {
  it('parses porcelain output into badges and colors', () => {
    const gitStatus = loadGitStatus(() =>
      [
        ' M src/edited.ts',
        'A  src/new.ts',
        ' D src/deleted.ts',
        'R  src/old.ts -> src/renamed.ts',
        'UU src/conflict.ts',
        '?? src/untracked.ts',
      ].join('\n'),
    );

    const changes = gitStatus.getGitChanges('/repo');
    assert.equal(changes.length, 6);
    assert.equal(changes[0].badge, 'M');
    assert.equal(changes[1].badge, 'A');
    assert.equal(changes[2].badge, 'D');
    assert.equal(changes[3].filePath, 'src/renamed.ts');
    assert.equal(changes[4].badge, 'C');
    assert.equal(changes[5].badge, 'U');
  });

  it('returns empty list when git command fails', () => {
    const gitStatus = loadGitStatus(() => {
      throw new Error('git not available');
    });
    assert.deepEqual(gitStatus.getGitChanges('/repo'), []);
  });

  it('returns unique changed roots', () => {
    const gitStatus = loadGitStatus(() => [' M src/a.ts', ' M src/b.ts', ' M README.md'].join('\n'));
    const roots = gitStatus.getChangedRoots('/repo');
    assert.equal(roots.size, 2);
    assert.ok(roots.has('src'));
    assert.ok(roots.has('README.md'));
  });

  it('returns changed paths under a directory', () => {
    const gitStatus = loadGitStatus(() => [' M src/a.ts', 'A  src/nested/b.ts', ' M other/c.ts'].join('\n'));
    const underSrc = gitStatus.getChangesUnder('/repo', 'src');
    assert.equal(underSrc.size, 2);
    assert.ok(underSrc.has('/repo/src/a.ts'));
    assert.ok(underSrc.has('/repo/src/nested/b.ts'));
  });

  it('reads ignored paths and trims directory suffixes', () => {
    const gitStatus = loadGitStatus((command) => {
      if (command.includes('ls-files')) {
        return ['tmp/', '.cache/', 'notes.txt'].join('\n');
      }
      return '';
    });
    const ignored = gitStatus.getIgnoredPaths('/repo');
    assert.ok(ignored.has('/repo/tmp'));
    assert.ok(ignored.has('/repo/.cache'));
    assert.ok(ignored.has('/repo/notes.txt'));
  });
});
