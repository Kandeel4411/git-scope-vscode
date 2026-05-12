const assert = require('assert').strict;
const fs = require('fs');
const os = require('os');
const path = require('path');
const proxyquire = require('proxyquire');

class MockEventEmitter {
  constructor() {
    this.event = () => undefined;
    this.fired = [];
  }
  fire(v) {
    this.fired.push(v);
  }
}

class MockTreeItem {
  constructor(label, collapsibleState) {
    this.label = label;
    this.collapsibleState = collapsibleState;
  }
}

class MockThemeColor {
  constructor(id) {
    this.id = id;
  }
}

class MockDataTransferItem {
  constructor(value) {
    this.value = value;
  }
}

function loadGitExplorer(repoRoot, changedPaths) {
  const vscodeMock = {
    TreeItem: MockTreeItem,
    TreeItemCollapsibleState: { None: 0, Collapsed: 1 },
    ThemeColor: MockThemeColor,
    EventEmitter: MockEventEmitter,
    DataTransferItem: MockDataTransferItem,
    Uri: { file: (fsPath) => ({ fsPath }) },
    workspace: { workspaceFolders: [{ uri: { fsPath: repoRoot } }] },
    window: {
      showInputBox: async () => undefined,
      showTextDocument: async () => {},
      showWarningMessage: async () => undefined,
      showErrorMessage: () => {},
    },
  };

  const gitStatusMock = {
    getChangedRoots: () => {
      const roots = new Map();
      for (const [abs, change] of changedPaths.entries()) {
        const rel = path.relative(repoRoot, abs).replace(/\\/g, '/');
        const root = rel.split('/')[0];
        if (!roots.has(root)) roots.set(root, change);
      }
      return roots;
    },
    buildChangedPathSet: () => changedPaths,
    getIgnoredPaths: () => new Set(),
  };

  const mod = proxyquire.noCallThru().load('../out/gitFileExplorer', {
    vscode: vscodeMock,
    './gitStatus': gitStatusMock,
  });
  return mod;
}

describe('Focus directory feature', () => {
  let repoRoot;

  beforeEach(() => {
    repoRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'git-scope-focus-'));
    fs.mkdirSync(path.join(repoRoot, 'src'));
    fs.writeFileSync(path.join(repoRoot, 'src', 'app.ts'), '');
    fs.writeFileSync(path.join(repoRoot, 'src', 'utils.ts'), '');
    fs.writeFileSync(path.join(repoRoot, 'src', 'config.ts'), '');
    fs.mkdirSync(path.join(repoRoot, 'src', 'nested'));
    fs.writeFileSync(path.join(repoRoot, 'src', 'nested', 'deep.ts'), '');
    fs.writeFileSync(path.join(repoRoot, 'README.md'), '');
  });

  afterEach(() => {
    fs.rmSync(repoRoot, { recursive: true, force: true });
  });

  it('focusing a directory hides unchanged files', () => {
    const changed = new Map([
      [path.join(repoRoot, 'src', 'app.ts'), { x: 'M', y: ' ', badge: 'M', color: 'modified' }],
    ]);
    const { GitFileExplorerProvider, GitNode } = loadGitExplorer(repoRoot, changed);
    const provider = new GitFileExplorerProvider();

    const srcNode = provider.getChildren().find((n) => n.label === 'src');
    const beforeFocus = provider.getChildren(srcNode);
    assert.ok(beforeFocus.length > 1, 'should show all files before focus');

    provider.focusDir(srcNode);
    const afterFocus = provider.getChildren(srcNode);
    assert.equal(afterFocus.length, 1, 'should only show changed file');
    assert.equal(afterFocus[0].label, 'app.ts');
  });

  it('unfocusing restores all children', () => {
    const changed = new Map([
      [path.join(repoRoot, 'src', 'app.ts'), { x: 'M', y: ' ', badge: 'M', color: 'modified' }],
    ]);
    const { GitFileExplorerProvider } = loadGitExplorer(repoRoot, changed);
    const provider = new GitFileExplorerProvider();

    const srcNode = provider.getChildren().find((n) => n.label === 'src');
    const originalCount = provider.getChildren(srcNode).length;

    provider.focusDir(srcNode);
    provider.unfocusDir(srcNode);

    const restored = provider.getChildren(srcNode);
    assert.equal(restored.length, originalCount, 'should restore all children after unfocus');
  });

  it('directories with changed descendants are kept visible', () => {
    const changed = new Map([
      [path.join(repoRoot, 'src', 'nested', 'deep.ts'), { x: 'A', y: ' ', badge: 'A', color: 'added' }],
    ]);
    const { GitFileExplorerProvider } = loadGitExplorer(repoRoot, changed);
    const provider = new GitFileExplorerProvider();

    const srcNode = provider.getChildren().find((n) => n.label === 'src');
    provider.focusDir(srcNode);

    const children = provider.getChildren(srcNode);
    const names = children.map((n) => n.label);
    assert.ok(names.includes('nested'), 'nested dir with changed descendant should remain visible');
    assert.ok(!names.includes('app.ts'), 'unchanged file should be hidden');
    assert.ok(!names.includes('utils.ts'), 'unchanged file should be hidden');
  });

  it('focusing with all changed files changes nothing', () => {
    const changed = new Map([
      [path.join(repoRoot, 'src', 'app.ts'), { x: 'M', y: ' ', badge: 'M', color: 'modified' }],
      [path.join(repoRoot, 'src', 'utils.ts'), { x: 'M', y: ' ', badge: 'M', color: 'modified' }],
      [path.join(repoRoot, 'src', 'config.ts'), { x: 'A', y: ' ', badge: 'A', color: 'added' }],
      [path.join(repoRoot, 'src', 'nested', 'deep.ts'), { x: 'M', y: ' ', badge: 'M', color: 'modified' }],
    ]);
    const { GitFileExplorerProvider } = loadGitExplorer(repoRoot, changed);
    const provider = new GitFileExplorerProvider();

    const srcNode = provider.getChildren().find((n) => n.label === 'src');
    const beforeCount = provider.getChildren(srcNode).length;

    provider.focusDir(srcNode);
    const afterCount = provider.getChildren(srcNode).length;
    assert.equal(afterCount, beforeCount, 'all files changed — nothing should be hidden');
  });

  it('contextValue switches between directory and directoryFocused', () => {
    const changed = new Map([
      [path.join(repoRoot, 'src', 'app.ts'), { x: 'M', y: ' ', badge: 'M', color: 'modified' }],
    ]);
    const { GitFileExplorerProvider } = loadGitExplorer(repoRoot, changed);
    const provider = new GitFileExplorerProvider();

    let srcNode = provider.getChildren().find((n) => n.label === 'src');
    assert.equal(srcNode.contextValue, 'directory');

    provider.focusDir(srcNode);
    srcNode = provider.getChildren().find((n) => n.label === 'src');
    assert.equal(srcNode.contextValue, 'directoryFocused');

    provider.unfocusDir(srcNode);
    srcNode = provider.getChildren().find((n) => n.label === 'src');
    assert.equal(srcNode.contextValue, 'directory');
  });

  it('focusing does not affect sibling directories', () => {
    fs.mkdirSync(path.join(repoRoot, 'lib'));
    fs.writeFileSync(path.join(repoRoot, 'lib', 'helper.ts'), '');
    fs.writeFileSync(path.join(repoRoot, 'lib', 'index.ts'), '');

    const changed = new Map([
      [path.join(repoRoot, 'src', 'app.ts'), { x: 'M', y: ' ', badge: 'M', color: 'modified' }],
      [path.join(repoRoot, 'lib', 'helper.ts'), { x: 'M', y: ' ', badge: 'M', color: 'modified' }],
    ]);
    const { GitFileExplorerProvider } = loadGitExplorer(repoRoot, changed);
    const provider = new GitFileExplorerProvider();

    const srcNode = provider.getChildren().find((n) => n.label === 'src');
    provider.focusDir(srcNode);

    const libNode = provider.getChildren().find((n) => n.label === 'lib');
    const libChildren = provider.getChildren(libNode);
    assert.equal(libChildren.length, 2, 'lib dir should still show all files');
  });

  it('focusDir is a no-op for file nodes', () => {
    const changed = new Map([
      [path.join(repoRoot, 'README.md'), { x: 'M', y: ' ', badge: 'M', color: 'modified' }],
    ]);
    const { GitFileExplorerProvider, GitNode } = loadGitExplorer(repoRoot, changed);
    const provider = new GitFileExplorerProvider();

    const fileNode = new GitNode('README.md', path.join(repoRoot, 'README.md'), false);
    provider.focusDir(fileNode);

    const roots = provider.getChildren();
    const readme = roots.find((n) => n.label === 'README.md');
    assert.equal(readme.contextValue, 'file');
  });
});
