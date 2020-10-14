local api = vim.api
local vfn = vim.fn
local M = {}


local function popup()
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_keymap(buf, 'i', '<esc>', ':bd', {})
  local columns = api.nvim_get_option('columns')
  local lines = api.nvim_get_option('lines')
  local width = vfn.float2nr(columns * 0.9)
  local height = vfn.float2nr(lines * 0.8)
  local opts = {
    relative = 'editor',
    style = 'minimal',
    row = vfn.float2nr((lines - height) * 0.5),
    col = vfn.float2nr((columns - width) * 0.5),
    width = width,
    height = height
  }
  local win = api.nvim_open_win(buf, true, opts)
  return win, buf, opts
end


M.actions = {}
function M.actions.edit_file(selection)
  if selection then
    vim.cmd('e ' .. selection)
  end
end


function M.execute(choices_cmd, on_selection, prompt)
  local tmpfile = vfn.tempname()
  local shell = api.nvim_get_option('shell')
  local shellcmdflag = api.nvim_get_option('shellcmdflag')
  local popup_win, popup_buf, popup_opts = popup()
  local fzy = (prompt
    and string.format(' | fzy -l %d -p "%s" >', popup_opts.height, prompt)
    or string.format(' | fzy -l %d > ', popup_opts.height)
  )
  local args = {shell, shellcmdflag, choices_cmd .. fzy.. tmpfile}
  vfn.termopen(args, {
    on_exit = function()
      api.nvim_win_close(popup_win, true)
      vim.cmd('bwipeout!' .. popup_buf)
      local file = io.open(tmpfile)
      if file then
        local contents = file:read("*all")
        file:close()
        os.remove(tmpfile)
        on_selection(contents)
      else
        on_selection(nil)
      end
    end;
  })
  vim.cmd('startinsert!')
end


return M
