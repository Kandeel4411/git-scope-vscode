const assert = require('assert').strict;
const fs = require('fs');
const os = require('os');
const path = require('path');
const proxyquire = require('proxyquire');

class MockEventEmitter {
  constructor() {
    this.event = () => undefined;
  }
  fire() {}
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

class MockDataTransfer {
  constructor() {
    this.items = new Map();
  }
  set(type, item) {
    this.items.set(type, item);
  }
  get(type) {
    return this.items.get(type);
  }
}

function loadGitExplorer(repoRoot, changedPaths) {
  const calls = {
    showTextDocument: [],
    showErrorMessage: [],
  };

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
      showTextDocument: async (uri) => calls.showTextDocument.push(uri.fsPath),
      showWarningMessage: async () => undefined,
      showErrorMessage: (msg) => calls.showErrorMessage.push(msg),
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

  const mod = proxyquire.noCallThru().load('../out/gitExplorer', {
    vscode: vscodeMock,
    './gitStatus': gitStatusMock,
  });
  return { ...mod, vscodeMock, calls };
}

describe('GitExplorerProvider', () => {
  let repoRoot;

  beforeEach(() => {
    repoRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'git-scope-'));
    fs.mkdirSync(path.join(repoRoot, 'src'));
    fs.writeFileSync(path.join(repoRoot, 'src', 'app.ts'), 'console.log(1);');
    fs.writeFileSync(path.join(repoRoot, 'README.md'), '# docs');
  });

  afterEach(() => {
    fs.rmSync(repoRoot, { recursive: true, force: true });
  });

  it('returns sorted root nodes (directories before files)', () => {
    const changed = new Map([
      [path.join(repoRoot, 'README.md'), { x: 'M', y: ' ', badge: 'M', color: 'modified' }],
      [path.join(repoRoot, 'src', 'app.ts'), { x: 'M', y: ' ', badge: 'M', color: 'modified' }],
    ]);
    const { GitExplorerProvider } = loadGitExplorer(repoRoot, changed);
    const provider = new GitExplorerProvider();
    const roots = provider.getChildren();
    assert.equal(roots.length, 2);
    assert.equal(roots[0].label, 'src');
    assert.equal(roots[1].label, 'README.md');
  });

  it('provides file decorations using git metadata', () => {
    const filePath = path.join(repoRoot, 'src', 'app.ts');
    const changed = new Map([[filePath, { x: 'M', y: ' ', badge: 'M', color: 'modified' }]]);
    const { GitExplorerProvider } = loadGitExplorer(repoRoot, changed);
    const provider = new GitExplorerProvider();
    const deco = provider.provideFileDecoration({ fsPath: filePath });
    assert.equal(deco.badge, 'M');
    assert.equal(deco.tooltip, 'Git: M ');
    assert.equal(deco.color.id, 'gitDecoration.modifiedResourceForeground');
  });

  it('creates files from selected directory nodes', async () => {
    const dirPath = path.join(repoRoot, 'src');
    const changed = new Map([
      [path.join(repoRoot, 'src', 'app.ts'), { x: 'M', y: ' ', badge: 'M', color: 'modified' }],
    ]);
    const loaded = loadGitExplorer(repoRoot, changed);
    loaded.vscodeMock.window.showInputBox = async () => 'new.ts';

    const provider = new loaded.GitExplorerProvider();
    const srcNode = provider.getChildren().find((n) => n.label === 'src');
    await provider.newFile(srcNode);

    const createdPath = path.join(dirPath, 'new.ts');
    assert.ok(fs.existsSync(createdPath));
    assert.deepEqual(loaded.calls.showTextDocument, [createdPath]);
  });

  it('renames and deletes items', async () => {
    const oldPath = path.join(repoRoot, 'README.md');
    const newPath = path.join(repoRoot, 'README2.md');
    const changed = new Map([[oldPath, { x: 'M', y: ' ', badge: 'M', color: 'modified' }]]);
    const loaded = loadGitExplorer(repoRoot, changed);
    loaded.vscodeMock.window.showInputBox = async () => 'README2.md';
    loaded.vscodeMock.window.showWarningMessage = async () => 'Delete';

    const provider = new loaded.GitExplorerProvider();
    const readmeNode = provider.getChildren().find((n) => n.label === 'README.md');
    await provider.renameItem(readmeNode);
    assert.ok(fs.existsSync(newPath));
    assert.ok(!fs.existsSync(oldPath));

    const renamedNode = new loaded.GitNode('README2.md', newPath, false);
    await provider.deleteItem(renamedNode);
    assert.ok(!fs.existsSync(newPath));
  });

  it('blocks dragging a directory into itself', async () => {
    const dir = path.join(repoRoot, 'src');
    const nested = path.join(dir, 'nested');
    fs.mkdirSync(nested);
    const changed = new Map([
      [path.join(repoRoot, 'src', 'app.ts'), { x: 'M', y: ' ', badge: 'M', color: 'modified' }],
    ]);
    const loaded = loadGitExplorer(repoRoot, changed);
    const provider = new loaded.GitExplorerProvider();

    const srcNode = provider.getChildren().find((n) => n.label === 'src');
    const targetNode = provider.getChildren(srcNode).find((n) => n.label === 'nested');

    const dataTransfer = new MockDataTransfer();
    provider.handleDrag([srcNode], dataTransfer);
    await provider.handleDrop(targetNode, dataTransfer);

    assert.ok(fs.existsSync(dir));
    assert.ok(fs.existsSync(nested));
    assert.equal(loaded.calls.showErrorMessage.length, 0);
  });
});
