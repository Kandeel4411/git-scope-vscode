local M = {}

local state = {
  buf = nil,
  win = nil,
  root = nil,
  changed = {},
  expanded = {},
  line_nodes = {},
}

local defaults = {
  keymaps = {
    open = "<CR>",
    toggle_dir = "l",
    collapse_dir = "h",
    new_file = "a",
    new_folder = "A",
    rename = "r",
    delete = "d",
    refresh = "R",
    close = "q",
  },
}

local config = vim.deepcopy(defaults)

local function join_path(...)
  return table.concat({ ... }, "/"):gsub("//+", "/")
end

local function basename(p)
  return vim.fs.basename(p)
end

local function git_status_lines(root)
  local cmd = "git -C " .. vim.fn.shellescape(root) .. " status --porcelain=1 --untracked-files=all"
  local out = vim.fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 then
    return {}
  end
  return out
end

local function status_to_badge(code)
  local c = code:match("[MADRCU?]") or "M"
  if c == "?" then
    return "U"
  end
  return c
end

local function parse_changed(root)
  local changed = {}
  local roots = {}

  for _, line in ipairs(git_status_lines(root)) do
    local xy = line:sub(1, 2)
    local rest = vim.trim(line:sub(4))
    if rest ~= "" then
      local path = rest
      if rest:find(" -> ", 1, true) then
        local parts = vim.split(rest, " -> ", { plain = true })
        path = parts[#parts]
      end
      local abs = join_path(root, path)
      changed[abs] = status_to_badge(xy)
      local top = vim.split(path, "/", { plain = true })[1]
      if top and top ~= "" then
        roots[join_path(root, top)] = true
      end
    end
  end

  local root_list = vim.tbl_keys(roots)
  table.sort(root_list)
  return changed, root_list
end

local function is_dir(path)
  return vim.fn.isdirectory(path) == 1
end

local function scandir(path)
  local entries = vim.fn.readdir(path)
  local out = {}
  for _, name in ipairs(entries) do
    if name ~= ".git" then
      local full = join_path(path, name)
      table.insert(out, {
        name = name,
        path = full,
        is_dir = is_dir(full),
      })
    end
  end
  table.sort(out, function(a, b)
    if a.is_dir ~= b.is_dir then
      return a.is_dir
    end
    return a.name:lower() < b.name:lower()
  end)
  return out
end

local function get_node_at_cursor()
  local lnum = vim.api.nvim_win_get_cursor(state.win)[1]
  return state.line_nodes[lnum]
end

local function ensure_window()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    return
  end
  vim.cmd("topleft 35vsplit")
  state.win = vim.api.nvim_get_current_win()

  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.api.nvim_win_set_buf(state.win, state.buf)
    return
  end

  state.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(state.win, state.buf)
  vim.bo[state.buf].bufhidden = "hide"
  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].swapfile = false
  vim.bo[state.buf].modifiable = false
  vim.bo[state.buf].filetype = "git_scope"
  vim.wo[state.win].number = false
  vim.wo[state.win].relativenumber = false
  vim.wo[state.win].signcolumn = "no"
end

local function render()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end

  local lines = {}
  state.line_nodes = {}

  local function add_node(node, depth)
    local indent = string.rep("  ", depth)
    local marker = node.is_dir and (state.expanded[node.path] and "▾ " or "▸ ") or "  "
    local badge = state.changed[node.path] and (" [" .. state.changed[node.path] .. "]") or ""
    table.insert(lines, indent .. marker .. node.name .. badge)
    state.line_nodes[#lines] = node

    if node.is_dir and state.expanded[node.path] then
      for _, child in ipairs(scandir(node.path)) do
        add_node(child, depth + 1)
      end
    end
  end

  table.insert(lines, "Git Scope")
  state.line_nodes[1] = { header = true }

  local changed, roots = parse_changed(state.root)
  state.changed = changed
  for _, path in ipairs(roots) do
    add_node({
      name = basename(path),
      path = path,
      is_dir = is_dir(path),
    }, 0)
  end

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
end

local function open_node()
  local node = get_node_at_cursor()
  if not node or node.header then
    return
  end
  if node.is_dir then
    state.expanded[node.path] = not state.expanded[node.path]
    render()
    return
  end
  vim.cmd("edit " .. vim.fn.fnameescape(node.path))
end

local function toggle_dir()
  local node = get_node_at_cursor()
  if not node or not node.is_dir then
    return
  end
  state.expanded[node.path] = not state.expanded[node.path]
  render()
end

local function collapse_dir()
  local node = get_node_at_cursor()
  if not node or not node.is_dir then
    return
  end
  state.expanded[node.path] = false
  render()
end

local function target_dir(node)
  if not node or node.header then
    return state.root
  end
  if node.is_dir then
    return node.path
  end
  return vim.fs.dirname(node.path)
end

local function new_file()
  local node = get_node_at_cursor()
  local dir = target_dir(node)
  local name = vim.fn.input("New file: ")
  if name == "" then
    return
  end
  local path = join_path(dir, name)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local f = io.open(path, "w")
  if f then
    f:close()
  end
  render()
  vim.cmd("edit " .. vim.fn.fnameescape(path))
end

local function new_folder()
  local node = get_node_at_cursor()
  local dir = target_dir(node)
  local name = vim.fn.input("New folder: ")
  if name == "" then
    return
  end
  vim.fn.mkdir(join_path(dir, name), "p")
  render()
end

local function rename_item()
  local node = get_node_at_cursor()
  if not node or node.header then
    return
  end
  local new_name = vim.fn.input("Rename to: ", node.name)
  if new_name == "" or new_name == node.name then
    return
  end
  local new_path = join_path(vim.fs.dirname(node.path), new_name)
  local ok, err = os.rename(node.path, new_path)
  if not ok then
    vim.notify("Rename failed: " .. tostring(err), vim.log.levels.ERROR)
  end
  render()
end

local function delete_item()
  local node = get_node_at_cursor()
  if not node or node.header then
    return
  end
  local confirm = vim.fn.confirm('Delete "' .. node.name .. '"?', "&Yes\n&No", 2)
  if confirm ~= 1 then
    return
  end
  local ok
  if node.is_dir then
    ok = vim.fn.delete(node.path, "rf") == 0
  else
    ok = vim.fn.delete(node.path) == 0
  end
  if not ok then
    vim.notify("Delete failed: " .. node.path, vim.log.levels.ERROR)
  end
  render()
end

local function close_win()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
end

local function map(lhs, rhs)
  vim.keymap.set("n", lhs, rhs, { buffer = state.buf, silent = true, nowait = true })
end

local function apply_keymaps()
  local km = config.keymaps
  map(km.open, open_node)
  map(km.toggle_dir, toggle_dir)
  map(km.collapse_dir, collapse_dir)
  map(km.new_file, new_file)
  map(km.new_folder, new_folder)
  map(km.rename, rename_item)
  map(km.delete, delete_item)
  map(km.refresh, render)
  map(km.close, close_win)
end

function M.open()
  state.root = vim.loop.cwd()
  ensure_window()
  apply_keymaps()
  render()
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  vim.api.nvim_create_user_command("GitScope", function()
    M.open()
  end, {})
end

return M
