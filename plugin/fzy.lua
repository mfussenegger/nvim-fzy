
if vim.ui then
  function vim.ui.select(items, opts, on_choice)  -- luacheck: ignore 122
    return require('fzy').pick_one(items, opts.prompt, opts.format_item, on_choice)
  end
end
