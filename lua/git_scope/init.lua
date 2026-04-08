local M = {}

local state = {
  buf = nil,
  win = nil,
  prev_win = nil,
  root = nil,
  changed = {},
  expanded = {},
  line_nodes = {},
  filter_query = "",
  dir_cache = {},
  ignored_cache = {},
  ignored_paths = {},
}

local defaults = {
  keymaps = {
    open = "<CR>",
    toggle_dir = "l",
    collapse_dir = "h",
    new_file = "a",
    new_folder = "A",
    filter = "/",
    rename = "r",
    stage_toggle = "s",
    delete = "d",
    refresh = "R",
    close = "q",
  },
}

local config = vim.deepcopy(defaults)

local ns = vim.api.nvim_create_namespace("git_scope_highlights")

local function setup_highlights()
  vim.api.nvim_set_hl(0, "GitScopeTitle", { default = true, link = "Title" })
  vim.api.nvim_set_hl(0, "GitScopeDirectory", { default = true, link = "Directory" })
  vim.api.nvim_set_hl(0, "GitScopeFile", { default = true, link = "Normal" })
  vim.api.nvim_set_hl(0, "GitScopeFileStaged", { default = true, link = "GitSignsAdd" })
  vim.api.nvim_set_hl(0, "GitScopeFileUnstaged", { default = true, link = "GitSignsChange" })
  vim.api.nvim_set_hl(0, "GitScopeFileMixed", { default = true, link = "DiagnosticWarn" })
  vim.api.nvim_set_hl(0, "GitScopeFileExtension", { default = true, link = "Comment" })
  vim.api.nvim_set_hl(0, "GitScopeFileExtensionStaged", { default = true, link = "String" })
  vim.api.nvim_set_hl(0, "GitScopeFileExtensionUnstaged", { default = true, link = "Identifier" })
  vim.api.nvim_set_hl(0, "GitScopeFileExtensionMixed", { default = true, link = "Type" })
  vim.api.nvim_set_hl(0, "GitScopeHiddenDirectory", { default = true, link = "Comment" })
  vim.api.nvim_set_hl(0, "GitScopeMarker", { default = true, link = "Comment" })
  vim.api.nvim_set_hl(0, "GitScopeBadgeModified", { default = true, link = "GitSignsChange" })
  vim.api.nvim_set_hl(0, "GitScopeBadgeAdded", { default = true, link = "GitSignsAdd" })
  vim.api.nvim_set_hl(0, "GitScopeBadgeDeleted", { default = true, link = "GitSignsDelete" })
  vim.api.nvim_set_hl(0, "GitScopeBadgeRenamed", { default = true, link = "DiagnosticHint" })
  vim.api.nvim_set_hl(0, "GitScopeBadgeUntracked", { default = true, link = "DiagnosticInfo" })
  vim.api.nvim_set_hl(0, "GitScopeBadgeConflict", { default = true, link = "DiagnosticError" })
end

local function badge_hl_for(status)
  local map = {
    M = "GitScopeBadgeModified",
    A = "GitScopeBadgeAdded",
    D = "GitScopeBadgeDeleted",
    R = "GitScopeBadgeRenamed",
    U = "GitScopeBadgeUntracked",
    C = "GitScopeBadgeConflict",
  }
  return map[status]
end

local function file_hl_for(change)
  if not change then
    return "GitScopeFile"
  end
  if change.staged and change.unstaged then
    return "GitScopeFileMixed"
  end
  if change.staged then
    return "GitScopeFileStaged"
  end
  if change.unstaged then
    return "GitScopeFileUnstaged"
  end
  return "GitScopeFile"
end

local function extension_hl_for(change)
  if not change then
    return "GitScopeFileExtension"
  end
  if change.staged and change.unstaged then
    return "GitScopeFileExtensionMixed"
  end
  if change.staged then
    return "GitScopeFileExtensionStaged"
  end
  if change.unstaged then
    return "GitScopeFileExtensionUnstaged"
  end
  return "GitScopeFileExtension"
end

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

local function parse_change(xy)
  local staged_code = xy:sub(1, 1)
  local unstaged_code = xy:sub(2, 2)
  local badge_code = unstaged_code ~= " " and unstaged_code or staged_code
  local badge = status_to_badge(badge_code)
  return {
    badge = badge,
    staged = staged_code ~= " " and staged_code ~= "?",
    unstaged = unstaged_code ~= " ",
  }
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
      changed[abs] = parse_change(xy)
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

local function has_staged_changes_for(path)
  local out = vim.fn.systemlist({
    "git",
    "-C",
    state.root,
    "status",
    "--porcelain=1",
    "--",
    path,
  })
  if vim.v.shell_error ~= 0 then
    return false
  end
  for _, line in ipairs(out) do
    local xy = line:sub(1, 2)
    local x = xy:sub(1, 1)
    if x ~= " " and x ~= "?" then
      return true
    end
  end
  return false
end

local function git_run(args)
  vim.fn.system(args)
  return vim.v.shell_error == 0
end

local function load_ignored_paths(root)
  local ignored = {}
  local cmd = "git -C "
    .. vim.fn.shellescape(root)
    .. " status --porcelain=1 --ignored --untracked-files=all"
  local out = vim.fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 then
    return ignored
  end

  for _, line in ipairs(out) do
    local xy = line:sub(1, 2)
    if xy == "!!" then
      local rel = vim.trim(line:sub(4))
      if rel ~= "" then
        if rel:find(" -> ", 1, true) then
          local parts = vim.split(rel, " -> ", { plain = true })
          rel = parts[#parts]
        end
        ignored[rel] = true
      end
    end
  end

  return ignored
end

local function is_dir(path)
  return vim.fn.isdirectory(path) == 1
end

local function to_relpath(path)
  local root = (state.root or ""):gsub("/+$", "")
  local prefix = root .. "/"
  if path == root then
    return "."
  end
  return path:gsub("^" .. vim.pesc(prefix), "")
end

local function is_git_ignored(path)
  local cached = state.ignored_cache[path]
  if cached ~= nil then
    return cached
  end

  local rel = to_relpath(path)
  local ignored = state.ignored_paths[rel] == true or state.ignored_paths[rel .. "/"] == true
  if not ignored then
    -- If an ignored directory is listed, all children should be hidden too.
    local probe = rel
    while probe and probe ~= "." do
      if state.ignored_paths[probe] == true or state.ignored_paths[probe .. "/"] == true then
        ignored = true
        break
      end
      local parent = vim.fs.dirname(probe)
      if not parent or parent == "." or parent == probe then
        break
      end
      if state.ignored_paths[parent] == true or state.ignored_paths[parent .. "/"] == true then
        ignored = true
        break
      end
      probe = parent
    end
  end
  state.ignored_cache[path] = ignored
  return ignored
end

local function scandir(path)
  local cached = state.dir_cache[path]
  if cached then
    return cached
  end

  local entries = vim.fn.readdir(path)
  local out = {}
  for _, name in ipairs(entries) do
    if name ~= ".git" then
      local full = join_path(path, name)
      if not is_git_ignored(full) then
        table.insert(out, {
          name = name,
          path = full,
          is_dir = is_dir(full),
        })
      end
    end
  end
  table.sort(out, function(a, b)
    if a.is_dir ~= b.is_dir then
      return a.is_dir
    end
    return a.name:lower() < b.name:lower()
  end)
  state.dir_cache[path] = out
  return out
end

local function get_node_at_cursor()
  local lnum = vim.api.nvim_win_get_cursor(state.win)[1]
  return state.line_nodes[lnum]
end

local function is_scope_win(win)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return false
  end
  return state.buf and vim.api.nvim_win_get_buf(win) == state.buf
end

local function find_editor_win()
  if state.prev_win and vim.api.nvim_win_is_valid(state.prev_win) and not is_scope_win(state.prev_win) then
    return state.prev_win
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if not is_scope_win(win) then
      return win
    end
  end
  return nil
end

local function open_path_in_editor(path)
  local editor_win = find_editor_win()
  if editor_win then
    vim.api.nvim_set_current_win(editor_win)
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    state.prev_win = editor_win
    return
  end
  vim.cmd("edit " .. vim.fn.fnameescape(path))
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

local function has_filter()
  return state.filter_query and state.filter_query ~= ""
end

local function render()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end

  local lines = {}
  local line_meta = {}
  state.line_nodes = {}

  local function collect_node_lines(node, depth)
    local node_lines = {}
    local node_entries = {}
    local indent = string.rep("  ", depth)
    local is_expanded = node.is_dir and (state.expanded[node.path] or has_filter())
    local marker = node.is_dir and (is_expanded and "▾ " or "▸ ") or "  "
    local change = state.changed[node.path]
    local badge = change and (" [" .. change.badge .. "]") or ""
    local line_text = indent .. marker .. node.name .. badge

    local matched = not has_filter()
    if has_filter() then
      matched = node.name:lower():find(state.filter_query:lower(), 1, true) ~= nil
    end

    if node.is_dir and is_expanded then
      for _, child in ipairs(scandir(node.path)) do
        local child_lines, child_nodes, child_matched = collect_node_lines(child, depth + 1)
        if child_matched then
          matched = true
          vim.list_extend(node_lines, child_lines)
          vim.list_extend(node_entries, child_nodes)
        end
      end
    end

    if matched then
      table.insert(node_lines, 1, line_text)
      table.insert(node_entries, 1, node)
    end

    return node_lines, node_entries, matched
  end

  local title = "Git Scope"
  if has_filter() then
    title = title .. " [/" .. state.filter_query .. "]"
  end
  table.insert(lines, title)
  line_meta[1] = { header = true }
  state.line_nodes[1] = { header = true }

  local changed, roots = parse_changed(state.root)
  state.changed = changed
  for _, path in ipairs(roots) do
    local root_node = {
      name = basename(path),
      path = path,
      is_dir = is_dir(path),
    }
    local root_lines, root_nodes, root_matched = collect_node_lines(root_node, 0)
    if root_matched then
      for i = 1, #root_lines do
        table.insert(lines, root_lines[i])
        local lnum = #lines
        state.line_nodes[lnum] = root_nodes[i]

        local node = root_nodes[i]
        local s = root_lines[i]
        local name_start = s:find(node.name, 1, true)
        if not name_start then
          name_start = 1
        end
        local name_end = name_start + #node.name
        local badge_start = nil
        local badge_end = nil
        local change = state.changed[node.path]
        local status = change and change.badge or nil
        if status then
          local badge = " [" .. status .. "]"
          badge_start = #s - #badge
          badge_end = #s
        end
        local ext_start = nil
        local ext_end = nil
        if not node.is_dir then
          local dot = node.name:match("^.*()%.")
          if dot and dot > 1 and dot <= #node.name then
            ext_start = name_start + dot - 1
            ext_end = name_end
          end
        end
        line_meta[lnum] = {
          is_dir = node.is_dir,
          name = node.name,
          name_start = name_start,
          name_end = name_end,
          ext_start = ext_start,
          ext_end = ext_end,
          badge_start = badge_start,
          badge_end = badge_end,
          status = status,
          change = change,
        }
      end
    end
  end

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for lnum = 1, #lines do
    local meta = line_meta[lnum]
    if meta and meta.header then
      vim.api.nvim_buf_add_highlight(state.buf, ns, "GitScopeTitle", lnum - 1, 0, -1)
    elseif meta then
      local line = lines[lnum]
      local node = state.line_nodes[lnum]
      local marker_start = line:find("[^%s]") and (line:find("[^%s]") - 1) or 0
      local marker_end = math.max((meta.name_start or 1) - 1, marker_start)
      if marker_end > marker_start and node and node.is_dir then
        vim.api.nvim_buf_add_highlight(state.buf, ns, "GitScopeMarker", lnum - 1, marker_start, marker_end)
      end
      vim.api.nvim_buf_add_highlight(
        state.buf,
        ns,
        meta.is_dir and ((meta.name and meta.name:sub(1, 1) == ".") and "GitScopeHiddenDirectory" or "GitScopeDirectory")
          or file_hl_for(meta.change),
        lnum - 1,
        math.max((meta.name_start or 1) - 1, 0),
        math.max((meta.name_end or #line), 0)
      )
      if meta.ext_start and meta.ext_end then
        vim.api.nvim_buf_add_highlight(
          state.buf,
          ns,
          extension_hl_for(meta.change),
          lnum - 1,
          meta.ext_start - 1,
          meta.ext_end
        )
      end
      if meta.badge_start and meta.badge_end and meta.status then
        local hl = badge_hl_for(meta.status)
        if hl then
          vim.api.nvim_buf_add_highlight(state.buf, ns, hl, lnum - 1, meta.badge_start, meta.badge_end)
        end
      end
    end
  end
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
  open_path_in_editor(node.path)
end

local function mouse_open_node()
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then
    return
  end

  local m = vim.fn.getmousepos()
  local winid = tonumber(m.winid or 0)
  local line = tonumber(m.line or 0)
  if winid ~= state.win or line <= 0 then
    return
  end

  vim.api.nvim_set_current_win(state.win)
  local max_line = vim.api.nvim_buf_line_count(state.buf)
  line = math.min(line, max_line)
  vim.api.nvim_win_set_cursor(state.win, { line, 0 })
  open_node()
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
  open_path_in_editor(path)
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

local function clear_caches()
  state.dir_cache = {}
  state.ignored_cache = {}
  state.ignored_paths = load_ignored_paths(state.root)
end

local function stage_toggle_item()
  local node = get_node_at_cursor()
  if not node or node.header then
    return
  end

  local rel = to_relpath(node.path)
  if rel == "." then
    return
  end

  local ok
  if has_staged_changes_for(rel) then
    ok = git_run({ "git", "-C", state.root, "restore", "--staged", "--", rel })
    if not ok then
      ok = git_run({ "git", "-C", state.root, "reset", "HEAD", "--", rel })
    end
  else
    ok = git_run({ "git", "-C", state.root, "add", "--", rel })
  end

  if not ok then
    vim.notify("Failed to toggle stage for: " .. rel, vim.log.levels.ERROR)
    return
  end

  clear_caches()
  render()
end

local function close_win()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.filter_query = ""
  state.dir_cache = {}
  state.ignored_cache = {}
  state.ignored_paths = {}
  vim.api.nvim_echo({ { "" } }, false, {})
end

local function start_filter()
  local input = vim.fn.input("Git Scope / ", state.filter_query or "")
  state.filter_query = vim.trim(input or "")
  render()
end

local function map(lhs, rhs)
  vim.keymap.set("n", lhs, rhs, { buffer = state.buf, silent = true, nowait = true })
end

local function apply_keymaps()
  local km = config.keymaps
  map(km.open, open_node)
  map("<LeftMouse>", mouse_open_node)
  map("<2-LeftMouse>", mouse_open_node)
  map(km.toggle_dir, toggle_dir)
  map(km.collapse_dir, collapse_dir)
  map(km.filter, start_filter)
  map(km.new_file, new_file)
  map(km.new_folder, new_folder)
  map(km.rename, rename_item)
  map(km.stage_toggle, stage_toggle_item)
  map(km.delete, delete_item)
  map(km.refresh, render)
  map(km.close, close_win)
end

function M.open()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_set_current_win(state.win)
    return
  end

  state.prev_win = vim.api.nvim_get_current_win()
  state.root = vim.loop.cwd()
  state.filter_query = ""
  state.dir_cache = {}
  state.ignored_cache = {}
  state.ignored_paths = load_ignored_paths(state.root)
  ensure_window()
  apply_keymaps()
  render()
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  setup_highlights()
  vim.api.nvim_create_user_command("GitScope", function()
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      close_win()
      return
    end
    M.open()
  end, {})
end

return M
