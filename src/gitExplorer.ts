import * as vscode from 'vscode';
import * as path from 'path';
import * as fs from 'fs';
import { getChangedRoots, buildChangedPathSet, getIgnoredPaths, GitChange } from './gitStatus';

export class GitNode extends vscode.TreeItem {
  constructor(
    public readonly label: string,
    public readonly fsPath: string,
    public readonly isDirectory: boolean,
    change?: GitChange,
  ) {
    super(
      label,
      isDirectory
        ? vscode.TreeItemCollapsibleState.Collapsed
        : vscode.TreeItemCollapsibleState.None,
    );

    this.resourceUri = vscode.Uri.file(fsPath);
    this.contextValue = isDirectory ? 'directory' : 'file';

    if (change) {
      this.description = change.badge;
      this.tooltip = `${label} [${change.x}${change.y}]`;
    }

    if (!isDirectory) {
      this.command = {
        command: 'vscode.open',
        title: 'Open File',
        arguments: [vscode.Uri.file(fsPath)],
      };
    }
  }
}

export class GitExplorerProvider
  implements
    vscode.TreeDataProvider<GitNode>,
    vscode.FileDecorationProvider,
    vscode.TreeDragAndDropController<GitNode>
{
  readonly dropMimeTypes = ['application/vnd.code.tree.gitExplorer'];
  readonly dragMimeTypes = ['application/vnd.code.tree.gitExplorer'];
  private _onDidChangeTreeData = new vscode.EventEmitter<GitNode | undefined | null>();
  readonly onDidChangeTreeData = this._onDidChangeTreeData.event;

  private _onDidChangeFileDecorations = new vscode.EventEmitter<vscode.Uri | vscode.Uri[]>();
  readonly onDidChangeFileDecorations = this._onDidChangeFileDecorations.event;

  private changedPaths: Map<string, GitChange> = new Map();
  private ignoredPaths: Set<string> = new Set();
  private workspaceRoot: string;

  constructor() {
    this.workspaceRoot = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath ?? '';
    this.loadChangedPaths();
  }

  private loadChangedPaths() {
    if (!this.workspaceRoot) return;
    this.changedPaths = buildChangedPathSet(this.workspaceRoot);
    this.ignoredPaths = getIgnoredPaths(this.workspaceRoot);
  }

  refresh(): void {
    this.loadChangedPaths();
    this._onDidChangeTreeData.fire(undefined);
    this._onDidChangeFileDecorations.fire([]);
  }

  // ── FileDecorationProvider ─────────────────────────────────────────────────

  provideFileDecoration(uri: vscode.Uri): vscode.FileDecoration | undefined {
    const change = this.changedPaths.get(uri.fsPath);
    if (!change) return undefined;

    const colorMap: Record<GitChange['color'], vscode.ThemeColor> = {
      modified: new vscode.ThemeColor('gitDecoration.modifiedResourceForeground'),
      untracked: new vscode.ThemeColor('gitDecoration.untrackedResourceForeground'),
      added: new vscode.ThemeColor('gitDecoration.addedResourceForeground'),
      deleted: new vscode.ThemeColor('gitDecoration.deletedResourceForeground'),
      renamed: new vscode.ThemeColor('gitDecoration.renamedResourceForeground'),
      conflict: new vscode.ThemeColor('gitDecoration.conflictingResourceForeground'),
    };

    return {
      badge: change.badge,
      color: colorMap[change.color],
      tooltip: `Git: ${change.x}${change.y}`,
    };
  }

  // ── TreeDataProvider ───────────────────────────────────────────────────────

  getTreeItem(element: GitNode): vscode.TreeItem {
    return element;
  }

  getChildren(element?: GitNode): GitNode[] {
    if (!this.workspaceRoot) return [];
    if (!element) return this.getRootNodes();
    return this.getDirectoryChildren(element.fsPath);
  }

  private getRootNodes(): GitNode[] {
    const roots = getChangedRoots(this.workspaceRoot);
    return Array.from(roots.entries())
      .map(([name, change]) => {
        const fullPath = path.join(this.workspaceRoot, name);
        const isDir = fs.existsSync(fullPath) && fs.statSync(fullPath).isDirectory();
        return new GitNode(name, fullPath, isDir, change);
      })
      .sort((a, b) => {
        if (a.isDirectory !== b.isDirectory) return a.isDirectory ? -1 : 1;
        return (a.label as string).localeCompare(b.label as string);
      });
  }

  private getDirectoryChildren(dirPath: string): GitNode[] {
    try {
      const entries = fs.readdirSync(dirPath, { withFileTypes: true });
      return entries
        .filter((e) => e.name !== '.git' && !this.ignoredPaths.has(path.join(dirPath, e.name)))
        .map((e) => {
          const fullPath = path.join(dirPath, e.name);
          const change = this.changedPaths.get(fullPath);
          return new GitNode(e.name, fullPath, e.isDirectory(), change);
        })
        .sort((a, b) => {
          if (a.isDirectory !== b.isDirectory) return a.isDirectory ? -1 : 1;
          return (a.label as string).localeCompare(b.label as string);
        });
    } catch {
      return [];
    }
  }

  // ── Drag and drop ──────────────────────────────────────────────────────────

  handleDrag(source: readonly GitNode[], dataTransfer: vscode.DataTransfer): void {
    dataTransfer.set(
      'application/vnd.code.tree.gitExplorer',
      new vscode.DataTransferItem(source),
    );
  }

  async handleDrop(target: GitNode | undefined, dataTransfer: vscode.DataTransfer): Promise<void> {
    const transferItem = dataTransfer.get('application/vnd.code.tree.gitExplorer');
    if (!transferItem) return;

    const sources: GitNode[] = transferItem.value;
    const destDir = target
      ? target.isDirectory
        ? target.fsPath
        : path.dirname(target.fsPath)
      : this.workspaceRoot;

    for (const source of sources) {
      const destPath = path.join(destDir, path.basename(source.fsPath));
      if (destPath === source.fsPath) continue;
      // Prevent moving a directory into itself
      if (source.isDirectory && destPath.startsWith(source.fsPath + path.sep)) continue;

      try {
        fs.renameSync(source.fsPath, destPath);
      } catch (err: unknown) {
        vscode.window.showErrorMessage(
          `Failed to move "${source.label}": ${err instanceof Error ? err.message : String(err)}`,
        );
      }
    }

    this.refresh();
  }

  // ── File operations ────────────────────────────────────────────────────────

  async newFile(node?: GitNode): Promise<void> {
    const dir = this.resolveTargetDir(node);
    if (!dir) return;

    const name = await vscode.window.showInputBox({
      prompt: 'New file name',
      placeHolder: 'filename.ext',
    });
    if (!name) return;

    const filePath = path.join(dir, name);
    fs.writeFileSync(filePath, '');
    await vscode.window.showTextDocument(vscode.Uri.file(filePath));
    this.refresh();
  }

  async newFolder(node?: GitNode): Promise<void> {
    const dir = this.resolveTargetDir(node);
    if (!dir) return;

    const name = await vscode.window.showInputBox({
      prompt: 'New folder name',
      placeHolder: 'folder-name',
    });
    if (!name) return;

    fs.mkdirSync(path.join(dir, name), { recursive: true });
    this.refresh();
  }

  async deleteItem(node: GitNode): Promise<void> {
    const confirm = await vscode.window.showWarningMessage(
      `Delete "${node.label}"?`,
      { modal: true },
      'Delete',
    );
    if (confirm !== 'Delete') return;

    if (node.isDirectory) {
      fs.rmSync(node.fsPath, { recursive: true, force: true });
    } else {
      fs.unlinkSync(node.fsPath);
    }
    this.refresh();
  }

  async renameItem(node: GitNode): Promise<void> {
    const newName = await vscode.window.showInputBox({
      prompt: 'New name',
      value: node.label as string,
    });
    if (!newName || newName === node.label) return;

    const newPath = path.join(path.dirname(node.fsPath), newName);
    fs.renameSync(node.fsPath, newPath);
    this.refresh();
  }

  private resolveTargetDir(node?: GitNode): string | undefined {
    if (node) {
      return node.isDirectory ? node.fsPath : path.dirname(node.fsPath);
    }
    // No node selected — use workspace root (only if it's itself a changed root)
    return this.workspaceRoot || undefined;
  }
}
