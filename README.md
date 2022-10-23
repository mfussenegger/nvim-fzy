# nvim-fzy

A `vim.ui.select` implementation for the [fzy][2] CLI.


## Installation

- Requires Neovim (latest stable or nightly)
- Install [fzy][2] and make sure it is in your `$PATH`.
- nvim-fzy is a plugin. Install it like any other plugin:
  - If using [vim-plug][5]: `Plug 'mfussenegger/nvim-fzy'`
  - If using [packer.nvim][6]: `use 'mfussenegger/nvim-fzy'`

## Usage

`nvim-fzy` provides the `vim.ui.select` implementation and a `execute` function
to feed the output of commands to `fzy`.

Create some mappings like this:

```vimL
lua fzy = require('fzy')
nnoremap <silent><leader>ff :lua fzy.execute('fd', fzy.sinks.edit_file)<CR>
nnoremap <silent><leader>fg :lua fzy.execute('git ls-files', fzy.sinks.edit_file)<CR>
nnoremap <silent><leader>fl :lua fzy.execute('ag --nobreak --noheading .', fzy.sinks.edit_live_grep)<CR>
```

See `:help fzy` for more information

![demo](demo/demo.gif)

To get additional pickers to jump to tags and other stuff, you can use it in combination with [nvim-qwahl](https://github.com/mfussenegger/nvim-qwahl)

Enjoy


## Goals

- Have a simple API so people can create their custom actions.
- Include the essentials, but not much more than that.

This plugin is pretty much *done* and won't see feature additions, unless there
is a convincing case to be made.


## Alternatives

- [fzf.vim][1]
- [telescope.nvim][4]


[1]: https://github.com/junegunn/fzf.vim
[2]: https://github.com/jhawthorn/fzy
[4]: https://github.com/nvim-lua/telescope.nvim
[5]: https://github.com/junegunn/vim-plug
[6]: https://github.com/wbthomason/packer.nvim
