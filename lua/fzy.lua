local api = vim.api
local vfn = vim.fn
local M = {}


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
  if api.nvim_get_mode().mode == "i" then
    vim.cmd('stopinsert')
  end
  local tmpfile = vfn.tempname()
  local shell = api.nvim_get_option('shell')
  local shellcmdflag = api.nvim_get_option('shellcmdflag')
  local popup_win, buf = M.new_popup()
  local height = api.nvim_win_get_height(popup_win)
  local fzy
  if prompt then
    fzy = string.format(
      '%s | fzy -l %d -p %s > "%s"',
      choices_cmd,
      height,
      vim.fn.shellescape(prompt),
      tmpfile
    )
  else
    fzy = string.format(
      '%s | fzy -l %d > "%s"',
      choices_cmd,
      height,
      tmpfile
    )
  end
  api.nvim_create_autocmd({'TermOpen', 'BufEnter'}, {
    buffer = buf,
    command = 'startinsert!',
    once = true,
  })
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
end


return M
