import * as vscode from 'vscode';
import { GitFileExplorerProvider } from './gitFileExplorer';

export function activate(context: vscode.ExtensionContext) {
  const workspaceRoot = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
  if (!workspaceRoot) return;

  const provider = new GitFileExplorerProvider();

  context.subscriptions.push(
    vscode.window.createTreeView('gitFileExplorer', {
      treeDataProvider: provider,
      dragAndDropController: provider,
    }),
    vscode.window.registerFileDecorationProvider(provider),

    vscode.commands.registerCommand('gitFileExplorer.refresh', () => provider.refresh()),
    vscode.commands.registerCommand('gitFileExplorer.newFile', (node) => provider.newFile(node)),
    vscode.commands.registerCommand('gitFileExplorer.newFolder', (node) => provider.newFolder(node)),
    vscode.commands.registerCommand('gitFileExplorer.deleteItem', (node) => provider.deleteItem(node)),
    vscode.commands.registerCommand('gitFileExplorer.renameItem', (node) => provider.renameItem(node)),
  );

  // Refresh on git index changes (stage/unstage/commit)
  const gitWatcher = vscode.workspace.createFileSystemWatcher(
    new vscode.RelativePattern(workspaceRoot, '.git/index'),
  );
  gitWatcher.onDidChange(() => provider.refresh());
  gitWatcher.onDidCreate(() => provider.refresh());
  context.subscriptions.push(gitWatcher);

  // Refresh when files are created or deleted
  const fsWatcher = vscode.workspace.createFileSystemWatcher(
    new vscode.RelativePattern(workspaceRoot, '**/*'),
  );
  fsWatcher.onDidCreate(() => provider.refresh());
  fsWatcher.onDidDelete(() => provider.refresh());
  context.subscriptions.push(fsWatcher);
}

export function deactivate() {}
