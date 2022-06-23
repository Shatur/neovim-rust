if vim.version().minor < 7 then
  require('rust.utils').notify('Neovim 0.7+ is required for rust plugin', vim.log.levels.ERROR)
  return
end

local subcommands = require('rust.subcommands')

vim.api.nvim_create_user_command('Rust', subcommands.run, { nargs = '*', complete = subcommands.complete, desc = 'Run Rust command' })
