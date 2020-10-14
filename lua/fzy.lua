local api = vim.api
local vfn = vim.fn
local M = {}

local function fst(xs)
  return xs and xs[1] or nil
end


local function popup()
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_keymap(buf, 't', '<ESC>', '<C-\\><C-c>', {})
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


local sinks = {}
M.sinks = sinks
function sinks.edit_file(selection)
  if selection then
    vim.cmd('e ' .. selection)
  end
end


function sinks.edit_buf(buf_with_name)
  if buf_with_name then
    local parts = vim.split(buf_with_name, ':')
    local bufnr = parts[1]
    api.nvim_set_current_buf(bufnr)
  end
end


local choices = {}

function choices.from_list(xs)
  return 'echo "' .. table.concat(xs, '\n') .. '"'
end

function choices.buffers()
  local bufs = api.nvim_list_bufs()
  return choices.from_list(vim.tbl_map(
    function(b)
      local bufname = vfn.fnamemodify(api.nvim_buf_get_name(b), ':.')
      return string.format('%d: %s', b, bufname)
    end,
    bufs
  ))
end


M.actions = {}
function M.actions.buffers()
  M.execute(choices.buffers(), sinks.edit_buf, 'Buffers> ')
end

function M.actions.buf_tags()
  local bufname = api.nvim_buf_get_name(0)
  assert(vfn.filereadable(bufname), 'File to generate tags for must be readable')
  local output = vfn.system({
    'ctags',
    '-f',
    '-',
    '--sort=yes',
    '--excmd=number',
    '--language-force=' .. api.nvim_buf_get_option(0, 'filetype'),
    bufname
  })
  local lines = vim.split(output, '\n')
  local tags = vim.tbl_map(function(x) return vim.split(x, '\t') end, lines)
  M.execute(
    choices.from_list(vim.tbl_map(fst, tags)),
    function(selection)
      for _, tag in ipairs(tags) do
        if vim.trim(selection) == vim.trim(tag[1]) then
          local row = tonumber(vim.split(tag[3], ';')[1])
          api.nvim_win_set_cursor(0, {row, 0})
          vim.cmd('normal! zvzz')
        end
      end
    end,
    'Buffer Tags> '
  )
end


function M.from_list(items, on_selection, prompt)
  M.execute(
    choices.from_list(items),
    on_selection,
    prompt
  )
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
