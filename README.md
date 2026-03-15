# Git Scope

A VS Code extension that cuts through the noise — showing only the directories and files that have **git changes** in a dedicated activity bar view.

Stop hunting through your entire project tree. Git Scope surfaces exactly what you're working on.

---

## Features

### Changed Directories View
A focused file explorer in the activity bar showing only top-level directories and files with git modifications. Expand any directory to browse its full contents.

### Git Status Badges
Each item is annotated with its git status at a glance:

| Badge | Meaning |
|-------|---------|
| `M` | Modified |
| `A` | Added |
| `D` | Deleted |
| `U` | Untracked |
| `R` | Renamed |
| `C` | Conflicted |

Hover over any item for a detailed tooltip showing both staged and unstaged status.

### File Operations
Right-click any item in the view for a context menu with:
- **New File** — create a file inside the selected directory
- **New Folder** — create a nested directory structure
- **Rename** — rename files and folders inline
- **Delete** — delete with a confirmation prompt

### Real-time Updates
The view automatically refreshes when:
- Files are staged or unstaged
- Commits are made
- Files are created or deleted on disk

---

## Getting Started

1. Open any git repository in VS Code
2. Click the **Git Scope** icon in the activity bar (folder + branch icon)
3. The **Changed Directories** panel will show all paths with git modifications

> Git Scope activates automatically when a `.git` folder is detected in your workspace.

---

## Requirements

- VS Code `1.85.0` or later
- `git` installed and available in your `PATH`

---

## Development

```bash
# Install dependencies
npm install

# Compile TypeScript
npm run compile

# Watch mode
npm run watch

# Package extension
npm run package
```

Press `F5` in VS Code to launch an Extension Development Host with Git Scope loaded.

---

## License

MIT
