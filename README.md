# nvim-fzy

Like [fzf.vim][1] but for [fzy][2] and neovim with Lua API.


## Installation

- Requires [Neovim HEAD/nightly][3]
- Install [fzy][2] and make sure it is in your `$PATH`.
- nvim-fzy is a plugin. Install it like any other plugin.
- Call `packadd nvim-fzy` if you install `nvim-fzy` to `'packpath'`.


## Usage

Create some mappings like this:

```
lua fzy = require('fzy')
nnoremap <silent><leader>ff :lua fzy.execute('fd', fzy.sinks.edit_file)<CR>
nnoremap <silent><leader>fb :lua fzy.actions.buffers()<CR>
nnoremap <silent><leader>ft :lua fzy.actions.buf_tags()<CR>
nnoremap <silent><leader>fg :lua fzy.execute('git ls-files', fzy.sinks.edit_file)<CR>
```

Enjoy


[1]: https://github.com/junegunn/fzf.vim
[2]: https://github.com/jhawthorn/fzy
[3]: https://github.com/neovim/neovim/releases/tag/nightly
