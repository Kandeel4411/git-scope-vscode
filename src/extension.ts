import * as vscode from 'vscode';
import { GitExplorerProvider } from './gitExplorer';

export function activate(context: vscode.ExtensionContext) {
  const workspaceRoot = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
  if (!workspaceRoot) return;

  const provider = new GitExplorerProvider();

  context.subscriptions.push(
    vscode.window.registerTreeDataProvider('gitExplorer', provider),
    vscode.window.registerFileDecorationProvider(provider),

    vscode.commands.registerCommand('gitExplorer.refresh', () => provider.refresh()),
    vscode.commands.registerCommand('gitExplorer.newFile', (node) => provider.newFile(node)),
    vscode.commands.registerCommand('gitExplorer.newFolder', (node) => provider.newFolder(node)),
    vscode.commands.registerCommand('gitExplorer.deleteItem', (node) => provider.deleteItem(node)),
    vscode.commands.registerCommand('gitExplorer.renameItem', (node) => provider.renameItem(node)),
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
