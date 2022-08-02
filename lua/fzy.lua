local api = vim.api
local vfn = vim.fn
local M = {}

local function fst(xs)
  return xs and xs[1] or nil
end


local function list_reverse(xs)
  local result = {}
  for i = #xs, 1, -1 do
    table.insert(result, xs[i])
  end
  return result
end


function M.new_popup()
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_keymap(buf, 't', '<ESC>', '<C-\\><C-c>', {})
  api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  local columns = api.nvim_get_option('columns')
  local lines = api.nvim_get_option('lines')
  local width = math.floor(columns * 0.9)
  local height = math.floor(lines * 0.8)
  local opts = {
    relative = 'editor',
    style = 'minimal',
    row = math.floor((lines - height) * 0.5),
    col = math.floor((columns - width) * 0.5),
    width = width,
    height = height,
    border = 'single',
  }
  local win = api.nvim_open_win(buf, true, opts)
  return win, buf
end


local sinks = {}
M.sinks = sinks
function sinks.edit_file(selection)
  if selection and vim.trim(selection) ~= '' then
    vim.cmd('e ' .. selection)
  end
end


function sinks.edit_live_grep(selection)
  -- fzy returns search input if zero results found. This case is mapped to nil as well.
  selection = string.match(selection, ".+:%d+:.+")
  if selection then
    local parts = vim.split(selection, ":")
    local path, line = parts[1], parts[2]
    vim.cmd("e +" .. line .. " " .. path)
  end
end


-- Return a formatted path or name for a bufnr
function M.format_bufname(bufnr)
  return vfn.fnamemodify(api.nvim_buf_get_name(bufnr), ':.')
end


function M.try(...)
  for _,fn in ipairs({...}) do
    local ok, _ = pcall(fn)
    if ok then
      return
    end
  end
end


M.actions = {}


function M.actions.buf_lines()
  local lines = api.nvim_buf_get_lines(0, 0, -1, true)
  local win = api.nvim_get_current_win()
  M.pick_one(lines, 'Lines> ', function(x) return x end, function(result, idx)
    if result then
      api.nvim_win_set_cursor(win, {idx, 0})
      vim.cmd('normal! zvzz')
    end
  end)
end


function M.actions.buffers()
  local bufs = vim.tbl_filter(
    function(b)
      return api.nvim_buf_is_loaded(b) and api.nvim_buf_get_option(b, 'buftype') ~= 'quickfix'
    end,
    api.nvim_list_bufs()
  )
  local format_bufname = function(b)
    local fullname = api.nvim_buf_get_name(b)
    local name
    if #fullname == 0 then
      name = '[No Name] (' .. api.nvim_buf_get_option(b, 'buftype') .. ')'
    else
      name = M.format_bufname(b)
    end
    local modified = api.nvim_buf_get_option(b, 'modified')
    return modified and name .. ' [+]' or name
  end
  M.pick_one(bufs, 'Buffers> ', format_bufname, function(b)
    if b then
      api.nvim_set_current_buf(b)
    end
  end)
end


function M.actions.jumplist()
  local locations = vim.tbl_filter(
    function(loc) return api.nvim_buf_is_valid(loc.bufnr) end,
    vim.fn.getjumplist()[1]
  )
  M.pick_one(
    locations,
    'Jumplist> ',
    function(loc)
      local line
      if api.nvim_buf_is_loaded(loc.bufnr) then
        local ok, lines = pcall(api.nvim_buf_get_lines, loc.bufnr, loc.lnum - 1, loc.lnum, true)
        line = ok and lines[1]
      else
        local fname = api.nvim_buf_get_name(loc.bufnr)
        local f = io.open(fname, "r")
        if f then
          local contents = f:read("*a")
          f:close()
          local lines = vim.split(contents, "\n")
          line = lines[loc.lnum]
        end
      end
      local label =  M.format_bufname(loc.bufnr) .. ':' .. tostring(loc.lnum)
      if line then
        return label .. ': ' .. line
      else
        return label
      end
    end,
    function(loc)
      if loc then
        api.nvim_set_current_buf(loc.bufnr)
        api.nvim_win_set_cursor(0, { loc.lnum, loc.col })
        vim.cmd('normal! zvzz')
      end
    end
  )
end


function M.actions.tagstack()
  local stack = vim.fn.gettagstack()
  M.pick_one(
    stack.items or {},
    'Tagstack> ',
    function(loc) return M.format_bufname(loc.bufnr) .. ': ' .. loc.tagname end,
    function(loc)
      if loc then
        api.nvim_set_current_buf(loc.bufnr)
        api.nvim_win_set_cursor(0, { loc.from[2], loc.from[3] })
        vim.cmd('normal! zvzz')
      end
    end
  )
end


function M.actions.lsp_tags(opts)
  opts = opts or {}
  local params = vim.lsp.util.make_position_params()
  params.context = {
    includeDeclaration = true
  }
  local function kind_matches(symbol)
    if opts.kind == nil then
      return true
    end
    for _, kind in pairs(opts.kind) do
      if symbol.kind == vim.lsp.protocol.SymbolKind[kind] then
        return true
      end
    end
    return false
  end
  local lnum = api.nvim_win_get_cursor(0)[1] - 1
  local function include(symbol)
    if kind_matches(symbol) then
      local range = symbol.range or symbol.location.range
      if opts.mode == 'next' then
        return range.start.line > lnum
      elseif opts.mode == 'prev' then
        return range.start.line < lnum
      else
        return true
      end
    end
    return false
  end
  assert(next(vim.lsp.buf_get_clients()), "Must have a client running to use lsp_tags")
  vim.lsp.buf_request(0, 'textDocument/documentSymbol', params, function(err, result)
    assert(not err, vim.inspect(err))
    if not result then
      return
    end
    local items = {}
    local add_items = nil
    add_items = function(xs, parent)
      for _, x in ipairs(xs) do
        x.__parent = parent
        if include(x) then
          table.insert(items, x)
        end
        if x.children then
          add_items(x.children, x)
        end
      end
    end
    local num_root_primitives = 0
    for _, x in pairs(result) do
      -- 6 is Method, the first kind that is not a container
      -- (File = 1; Module = 2; Namespace = 3; Package = 4; Class = 5;)
      if x.kind >= 6 then
        num_root_primitives = num_root_primitives + 1
      end
    end
    add_items(result)
    M.pick_one(
      items,
      'Tags> ',
      function(item)
        local path = {}
        local parent = item.__parent
        while parent do
          table.insert(path, parent.name)
          parent = parent.__parent
        end
        local kind = vim.lsp.protocol.SymbolKind[item.kind]
        -- Omit the root if there are no non-container symbols on root level
        -- This is for example the case in Java where everything is inside a class
        -- In that case the class name is mostly noise
        if num_root_primitives == 0 and next(path) then
          table.remove(path, #path)
        end
        if next(path) then
          return string.format('[%s] %s: %s', kind, table.concat(list_reverse(path), ' » '), item.name)
        else
          return string.format('[%s] %s', kind, item.name)
        end
      end,
      function(item)
        if not item then return end
        local range = item.range or item.location.range
        api.nvim_win_set_cursor(0, {
          range.start.line + 1,
          range.start.character
        })
        vim.cmd('normal! zvzz')
      end
    )
  end)
end

function M.actions.buf_tags()
  local bufname = api.nvim_buf_get_name(0)
  assert(vfn.filereadable(bufname), 'File to generate tags for must be readable')
  local ok, output = pcall(vfn.system, {
    'ctags',
    '-f',
    '-',
    '--sort=yes',
    '--excmd=number',
    '--language-force=' .. api.nvim_buf_get_option(0, 'filetype'),
    bufname
  })
  if not ok or api.nvim_get_vvar('shell_error') ~= 0 then
    output = vfn.system({'ctags', '-f', '-', '--sort=yes', '--excmd=number', bufname})
  end
  local lines = vim.tbl_filter(
    function(x) return x ~= '' end,
    vim.split(output, '\n')
  )
  local tags = vim.tbl_map(function(x) return vim.split(x, '\t') end, lines)
  M.pick_one(
    tags,
    'Buffer Tags> ',
    fst,
    function(tag)
      if not tag then
        return
      end
      local row = tonumber(vim.split(tag[3], ';')[1])
      api.nvim_win_set_cursor(0, {row, 0})
      vim.cmd('normal! zvzz')
    end
  )
end


function M.actions.quickfix()
  vim.cmd('cclose')
  local items = vfn.getqflist()
  M.pick_one(
    items,
    'Quickfix> ',
    function(item)
      return M.format_bufname(item.bufnr) .. ': ' .. item.text
    end,
    function(item)
      if not item then return end
      vfn.bufload(item.bufnr)
      api.nvim_win_set_buf(0, item.bufnr)
      api.nvim_win_set_cursor(0, {item.lnum, item.col - 1})
      vim.cmd('normal! zvzz')
    end
  )
end


function M.pick_one(items, prompt, label_fn, cb)
  label_fn = label_fn or vim.inspect
  local num_digits = math.floor(math.log(math.abs(#items), 10) + 1)
  local digit_fmt = '%0' .. tostring(num_digits) .. 'd'
  local inputs = vfn.tempname()
  vfn.system(string.format('mkfifo "%s"', inputs))
  local co
  if cb == nil then
    co = coroutine.running()
    assert(co, "If callback is nil the function must run in a coroutine")
    cb = function(choice, idx)
      coroutine.resume(co, choice, idx)
    end
  end

  M.execute(
    string.format('cat "%s"', inputs),
    function(selection)
      os.remove(inputs)
      if not selection or vim.trim(selection) == '' then
        cb(nil)
      else
        local parts = vim.split(selection, '│ ')
        local idx = tonumber(parts[1])
        cb(items[idx], idx)
      end
    end,
    prompt
  )
  local f = io.open(inputs, 'a')
  if f then
    for i, item in ipairs(items) do
      local label = string.format(digit_fmt .. '│ %s', i, label_fn(item))
      f:write(label .. '\n')
    end
    f:flush()
    f:close()
  else
    vim.notify('Could not open tempfile', vim.log.levels.ERROR)
  end
  if co then
    return coroutine.yield()
  end
end


function M.execute(choices_cmd, on_selection, prompt)
  if api.nvim_get_mode().mode ~= 'n' then
    api.nvim_feedkeys(api.nvim_replace_termcodes('<ESC>', true, false, true), 'n', false)
  end
  local tmpfile = vfn.tempname()
  local shell = api.nvim_get_option('shell')
  local shellcmdflag = api.nvim_get_option('shellcmdflag')
  local popup_win, buf = M.new_popup()
  local height = api.nvim_win_get_height(popup_win)
  local fzy = (prompt
    and string.format('%s | fzy -l %d -p "%s" > "%s"', choices_cmd, height, prompt, tmpfile)
    or string.format('%s | fzy -l %d > "%s"', choices_cmd, height, tmpfile)
  )
  local args = {shell, shellcmdflag, fzy}
  vfn.termopen(args, {
    on_exit = function()
      -- popup could already be gone if user closes it manually; Ignore that case
      pcall(api.nvim_win_close, popup_win, true)
      local contents = nil
      local file = io.open(tmpfile)
      if file then
        contents = file:read("*all")
        file:close()
        os.remove(tmpfile)
      end

      -- After on_exit there will be a terminal related cmdline update that would
      -- override any messages printed by the `on_selection` callback.
      -- The timer+schedule combo ensures users see messages printed within the callback
      local timer = vim.loop.new_timer()
      timer:start(0, 0, function()
        timer:stop()
        timer:close()
        vim.schedule(function()
          on_selection(contents)
        end)
      end)
    end;
  })
  api.nvim_buf_call(buf, function()
    vim.cmd('startinsert!')
  end)
end


function M.setup()
  if vim.ui then
    function vim.ui.select(items, opts, on_choice)  -- luacheck: ignore 122
      return M.pick_one(items, opts.prompt, opts.format_item, on_choice)
    end
  end
end

return M
