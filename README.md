# Git Scope

Git Scope is a focused file explorer for changed files.

It shows only directories and files touched by git status, so you can work inside active paths without scanning the full project tree.

## Highlights

- Dedicated activity bar view called **Changed Directories**
- Git status badges on files and roots
- Quick file actions from tree context menu
- Automatic refresh when git index or filesystem state changes
- Neovim module at `lua/git_scope/init.lua`

## Status Badges

- `M`: Modified
- `A`: Added
- `D`: Deleted
- `U`: Untracked
- `R`: Renamed
- `C`: Conflict

Hovering an item shows staged and unstaged status details.

## File Actions

From the tree view context menu:

- **New File**
- **New Folder**
- **Rename**
- **Delete** with confirmation

## Getting Started in VS Code

1. Open a git repository in VS Code.
2. Select the **Git Scope** icon in the activity bar.
3. Use the **Changed Directories** tree to browse changed paths.

Activation is automatic when a `.git` directory exists in the workspace.

## Keybindings

When the Git Scope tree has focus:

- `Enter` or `l`: Open file or expand folder
- `h`: Collapse folder
- `/`: Start filter input in Neovim
- `a`: New file
- `A`: New folder
- `r`: Rename
- `s`: Stage or unstage file or directory in Neovim
- `d`: Delete
- `R`: Refresh
- `q`: Close Git Scope window in Neovim

## LazyVim and Neovim

Create `~/.config/nvim/lua/plugins/git-scope.lua`:

```lua
return {
  {
    "Kandeel4411/git-scope-vscode",
    lazy = true,
    cmd = { "GitScope" },
    keys = {
      {
        "gs",
        function()
          vim.cmd("GitScope")
        end,
        desc = "Git Scope",
        mode = "n",
      },
    },
    config = function()
      require("git_scope").setup()
    end,
  },
}
```

Then run `:Lazy sync` and restart Neovim.

Usage notes:

- Run `:GitScope` in any git repo.
- The panel opens in a left split.
- Use `s` to stage a file or directory.
- Use `s` again to unstage it.

## Requirements

- VS Code `1.85.0` or later
- Git available in your `PATH`

## Development

```bash
npm install
npm run compile
npm run watch
npm run test
npm run package
```

Press `F5` in VS Code to launch an Extension Development Host.

## Contributing

For contribution workflow and hook setup, see `CONTRIBUTING.md`.

Quick start:

```bash
pip install pre-commit
pre-commit install
npm test
pre-commit run -a
```

## License

MIT
