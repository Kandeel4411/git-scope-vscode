local failures = 0
local tests = {}
local created_commands = {}
local mapped_keys = {}
local closed_windows = {}
local command_log = {}
local current_win = 1
local next_win = 1
local next_buf = 10
local valid_wins = { [1] = true }
local valid_bufs = {}
local win_buf = {}
local buffer_lines = {}

local function deep_copy(tbl)
  if type(tbl) ~= "table" then
    return tbl
  end
  local copy = {}
  for k, v in pairs(tbl) do
    copy[k] = deep_copy(v)
  end
  return copy
end

local function split(str, sep, opts)
  opts = opts or {}
  local out = {}
  if sep == "" then
    for i = 1, #str do
      out[#out + 1] = str:sub(i, i)
    end
    return out
  end
  local pattern = opts.plain and sep or ("%s"):format(sep)
  local start = 1
  while true do
    local i, j = str:find(pattern, start, opts.plain)
    if not i then
      out[#out + 1] = str:sub(start)
      break
    end
    out[#out + 1] = str:sub(start, i - 1)
    start = j + 1
  end
  return out
end

_G.vim = {
  v = { shell_error = 0 },
  loop = { cwd = function() return "/repo" end },
  api = {
    nvim_create_namespace = function() return 1 end,
    nvim_set_hl = function() end,
    nvim_create_user_command = function(name, cb)
      created_commands[name] = cb
    end,
    nvim_win_is_valid = function(win)
      return valid_wins[win] == true
    end,
    nvim_get_current_win = function()
      return current_win
    end,
    nvim_set_current_win = function(win)
      current_win = win
    end,
    nvim_tabpage_list_wins = function()
      return { 1, 2 }
    end,
    nvim_win_get_buf = function(win)
      return win_buf[win] or 0
    end,
    nvim_buf_is_valid = function(buf)
      return valid_bufs[buf] == true
    end,
    nvim_win_set_buf = function(win, buf)
      win_buf[win] = buf
    end,
    nvim_create_buf = function()
      next_buf = next_buf + 1
      valid_bufs[next_buf] = true
      buffer_lines[next_buf] = {}
      return next_buf
    end,
    nvim_buf_set_lines = function(buf, _, _, _, lines)
      buffer_lines[buf] = lines
    end,
    nvim_buf_clear_namespace = function() end,
    nvim_buf_add_highlight = function() end,
    nvim_win_get_cursor = function()
      return { 1, 0 }
    end,
    nvim_buf_line_count = function(buf)
      return #(buffer_lines[buf] or {})
    end,
    nvim_win_set_cursor = function() end,
    nvim_win_close = function(win)
      valid_wins[win] = false
      closed_windows[#closed_windows + 1] = win
    end,
    nvim_echo = function(msg)
      command_log[#command_log + 1] = msg
    end,
  },
  keymap = {
    set = function(_, lhs, _, opts)
      mapped_keys[#mapped_keys + 1] = { lhs = lhs, buffer = opts and opts.buffer }
    end,
  },
  cmd = function(cmd)
    if cmd == "topleft 35vsplit" then
      next_win = next_win + 1
      valid_wins[next_win] = true
      current_win = next_win
    end
  end,
  notify = function() end,
  log = { levels = { ERROR = 1 } },
  bo = setmetatable({}, {
    __index = function(tbl, key)
      local v = {}
      rawset(tbl, key, v)
      return v
    end,
  }),
  wo = setmetatable({}, {
    __index = function(tbl, key)
      local v = {}
      rawset(tbl, key, v)
      return v
    end,
  }),
  fn = {
    shellescape = function(s)
      return s
    end,
    systemlist = function()
      return {}
    end,
    readdir = function()
      return {}
    end,
    isdirectory = function()
      return 0
    end,
    input = function(_, default)
      return default or ""
    end,
    getmousepos = function()
      return { winid = current_win, line = 1 }
    end,
    mkdir = function()
      return 1
    end,
    delete = function()
      return 0
    end,
    confirm = function()
      return 2
    end,
    fnameescape = function(s)
      return s
    end,
    system = function()
      return ""
    end,
  },
  fs = {
    dirname = function(p)
      local i = p:match("^.*()/")
      if not i then
        return "."
      end
      if i == 1 then
        return "/"
      end
      return p:sub(1, i - 1)
    end,
    basename = function(p)
      local b = p:match("([^/]+)$")
      return b or p
    end,
  },
  deepcopy = deep_copy,
  tbl_keys = function(tbl)
    local out = {}
    for k, _ in pairs(tbl) do
      out[#out + 1] = k
    end
    return out
  end,
  list_extend = function(dst, src)
    for i = 1, #src do
      dst[#dst + 1] = src[i]
    end
    return dst
  end,
  tbl_deep_extend = function(_, base, ext)
    local merged = deep_copy(base)
    ext = ext or {}
    for k, v in pairs(ext) do
      if type(v) == "table" and type(merged[k]) == "table" then
        for k2, v2 in pairs(v) do
          merged[k][k2] = v2
        end
      else
        merged[k] = v
      end
    end
    return merged
  end,
  split = split,
  trim = function(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
  end,
  pesc = function(s)
    return (s:gsub("([^%w])", "%%%1"))
  end,
}

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local mod = require("git_scope")
local t = mod._test

local function add_test(name, fn)
  tests[#tests + 1] = { name = name, fn = fn }
end

local function reset_runtime_state()
  created_commands = {}
  mapped_keys = {}
  closed_windows = {}
  command_log = {}
  current_win = 1
  next_win = 1
  next_buf = 10
  valid_wins = { [1] = true }
  valid_bufs = {}
  win_buf = {}
  buffer_lines = {}
end

local function assert_eq(actual, expected, msg)
  if actual ~= expected then
    error((msg or "assert_eq failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
  end
end

local function assert_true(v, msg)
  if not v then
    error(msg or "assert_true failed")
  end
end

add_test("status_to_badge normalizes untracked", function()
  assert_eq(t.status_to_badge("?"), "U")
  assert_eq(t.status_to_badge("M"), "M")
  assert_eq(t.status_to_badge("A"), "A")
end)

add_test("parse_change computes badge and stage flags", function()
  local mixed = t.parse_change("MM")
  assert_eq(mixed.badge, "M")
  assert_true(mixed.staged)
  assert_true(mixed.unstaged)

  local untracked = t.parse_change("??")
  assert_eq(untracked.badge, "U")
  assert_true(not untracked.staged)
  assert_true(untracked.unstaged)
end)

add_test("highlight selectors map status and change state", function()
  assert_eq(t.badge_hl_for("D"), "GitScopeBadgeDeleted")
  assert_eq(t.file_hl_for({ staged = true, unstaged = false }), "GitScopeFileStaged")
  assert_eq(t.file_hl_for({ staged = false, unstaged = true }), "GitScopeFileUnstaged")
  assert_eq(t.file_hl_for({ staged = true, unstaged = true }), "GitScopeFileMixed")
  assert_eq(t.extension_hl_for(nil), "GitScopeFileExtension")
end)

add_test("ignored path checks include parent ignored directories", function()
  t.set_state({
    root = "/repo",
    ignored_cache = {},
    ignored_paths = { ["build/"] = true },
  })

  assert_true(t.is_git_ignored("/repo/build/main.o"))
  assert_true(not t.is_git_ignored("/repo/src/main.lua"))
  assert_eq(t.to_relpath("/repo/build/main.o"), "build/main.o")
  assert_eq(t.to_relpath("/repo"), ".")
end)

add_test("setup registers GitScope command", function()
  reset_runtime_state()
  mod.setup()
  assert_true(type(created_commands.GitScope) == "function", "GitScope command callback was not registered")
end)

add_test("GitScope command closes existing window", function()
  reset_runtime_state()
  mod.setup()
  t.set_state({ win = 1, filter_query = "abc" })
  created_commands.GitScope()
  assert_eq(#closed_windows, 1)
  assert_eq(closed_windows[1], 1)
end)

add_test("open applies configured keymaps", function()
  reset_runtime_state()
  mod.setup({
    keymaps = {
      open = "o",
      refresh = "x",
    },
  })
  t.set_state({ win = -1, buf = -1 })
  mod.open()

  local seen = {}
  for _, entry in ipairs(mapped_keys) do
    seen[entry.lhs] = true
  end
  assert_true(seen["o"], "custom open keymap not applied")
  assert_true(seen["x"], "custom refresh keymap not applied")
  assert_true(seen["q"], "default close keymap not applied")
end)

add_test("open focuses existing scope window without recreating split", function()
  reset_runtime_state()
  local split_calls = 0
  vim.cmd = function(cmd)
    if cmd == "topleft 35vsplit" then
      split_calls = split_calls + 1
      next_win = next_win + 1
      valid_wins[next_win] = true
      current_win = next_win
    end
  end

  mod.setup()
  t.set_state({ win = 1, buf = -1 })
  mod.open()

  assert_eq(split_calls, 0, "open should not create a new split when scope window is valid")
  assert_eq(current_win, 1, "open should focus existing scope window")
end)

for _, test in ipairs(tests) do
  local ok, err = pcall(test.fn)
  if ok then
    io.write("ok - " .. test.name .. "\n")
  else
    failures = failures + 1
    io.write("not ok - " .. test.name .. "\n")
    io.write("  " .. tostring(err) .. "\n")
  end
end

if failures > 0 then
  io.write("\n" .. failures .. " lua test(s) failed\n")
  os.exit(1)
end

io.write("\nall lua tests passed\n")
