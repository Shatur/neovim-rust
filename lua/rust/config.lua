local config = {
  defaults = {
    parameters_file = 'neovim.json',
    save_before_build = true,
    on_build_output = nil,
    quickfix = {
      pos = 'botright',
      height = 10,
      only_on_error = false,
    },
    dap_configuration = { type = 'lldb', request = 'launch' },
    dap_open_command = require('dap').repl.open,
  },
}

setmetatable(config, { __index = config.defaults })

return config
