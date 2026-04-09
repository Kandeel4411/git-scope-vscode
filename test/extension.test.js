const assert = require('assert').strict;
const proxyquire = require('proxyquire');

describe('extension activation', () => {
  it('registers tree view, commands, and watchers', () => {
    const subscriptions = [];
    const commands = [];
    const watchers = [];

    class MockProvider {
      refresh() {}
      newFile() {}
      newFolder() {}
      deleteItem() {}
      renameItem() {}
    }

    function makeWatcher() {
      const callbacks = { change: null, create: null, del: null };
      const watcher = {
        onDidChange: (cb) => (callbacks.change = cb),
        onDidCreate: (cb) => (callbacks.create = cb),
        onDidDelete: (cb) => (callbacks.del = cb),
        callbacks,
      };
      watchers.push(watcher);
      return watcher;
    }

    const vscodeMock = {
      RelativePattern: class {
        constructor(base, pattern) {
          this.base = base;
          this.pattern = pattern;
        }
      },
      workspace: {
        workspaceFolders: [{ uri: { fsPath: '/repo' } }],
        createFileSystemWatcher: () => makeWatcher(),
      },
      window: {
        createTreeView: (id, cfg) => ({ id, cfg }),
        registerFileDecorationProvider: () => ({ kind: 'fileDecorationProvider' }),
      },
      commands: {
        registerCommand: (name, fn) => {
          commands.push({ name, fn });
          return { name };
        },
      },
    };

    const extension = proxyquire.noCallThru().load('../out/extension', {
      vscode: vscodeMock,
      './gitExplorer': { GitExplorerProvider: MockProvider },
    });

    extension.activate({ subscriptions });

    assert.ok(subscriptions.length >= 8);
    assert.equal(commands.length, 5);
    assert.deepEqual(
      commands.map((c) => c.name).sort(),
      [
        'gitExplorer.deleteItem',
        'gitExplorer.newFile',
        'gitExplorer.newFolder',
        'gitExplorer.refresh',
        'gitExplorer.renameItem',
      ],
    );
    assert.equal(watchers.length, 2);
    assert.ok(typeof watchers[0].callbacks.change === 'function');
    assert.ok(typeof watchers[1].callbacks.create === 'function');
    assert.ok(typeof watchers[1].callbacks.del === 'function');
  });
});
