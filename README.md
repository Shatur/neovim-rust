# Neovim Rust

**This plugin has been deprecated in favor of [neovim-tasks](https://github.com/Shatur/neovim-tasks)**. I realized that having separate plugins for each build system is inconvenient, so I decided to write a general purpose plugin that could support support any build system.

A Neovim 0.7+ plugin that to provides integration with building, running and debugging projects with output to quickfix.

## Dependencies

- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) for internal helpers.
- [nvim-dap](https://github.com/mfussenegger/nvim-dap) for debugging.

## Commands

Use the command `:Rust` with one of the following arguments:

| Argument                    | Description                                                                                                                                                                                                                                                                                             |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `cargo {subcommand} ...`    | Run the specific cargo `subcommand` (`run`, for example) and print output to quickfix. All additional arguments will be forwared to the command. See `cargo --list` for the list of available subcommands.                                                                                              |
| `debug {subcommand} ...`    | Run debugger on specific cargo `subcommand`. All additional arguments will be forwared to the command. Can be used only with `run` or `test`. Uses the same persistent arguments as the corresponding `subcommand`.                                                                                     |
| `set_args {subcommand} ...` | Set persistent arguments for the specified `subcommand` for `cargo` or globally (using `global` as `subcommand`). When running commands arguments composed in the following order: global, specific to the subcommand being run and then additional temporary arguments that was passed to the command. |
| `cancel`                    | Cancel current running Cargo subcommand like `build` or `run`.                                                                                                                                                                                                                                          |

Also the corresponding Lua functions with the same names as the arguments are available from [`require('rust')`](lua/rust/init.lua).

## Simple usage example

1. Create a new project (`:Rust cargo new my_project`) or open folder with an existing.
2. Optionally set arguments for subcommands (for example, use `:Rust set_args global` to set arguments for all subcommands or `:Rust set_args run` to set arguments for `cargo run`).
3. Run any cargo `subcommand` (for example, `:Rust cargo run` or `:Rust cargo test`) or debug it (for example, `:Rust debug run` or `:Rust debug test`). You can pass additional arguments to these commands, which will be temporarily added to the arguments from 2.

## Configuration

To configure the plugin, you can call `require('rust').setup(values)`, where `values` is a dictionary with the parameters you want to override. Here are the defaults:

```lua
local Path = require('plenary.path')
require('rust').setup({
  parameters_file = 'neovim.json', -- JSON file to store information about selected target, run arguments and build type.
  default_parameters = { args = { global = {} } }, -- The default values in `parameters_file`.
  save_before_build = true, -- Save all buffers before building.
  on_build_output = nil, -- Callback that will be called each time data is received by the current process. Accepts the received data as an argument.
  quickfix = {
    pos = 'botright', -- Where to open quickfix
    height = 10, -- Height of the opened quickfix.
    only_on_error = false, -- Open quickfix window only if target build failed.
  },
  dap_configuration = { type = 'lldb', request = 'launch' }, -- DAP configuration. By default configured to work with `lldb-vscode`.
  dap_open_command = require('dap').repl.open, -- Command to run after starting DAP session. You can set it to `false` if you don't want to open anything or `require('dapui').open` if you are using https://github.com/rcarriga/nvim-dap-ui
})
```

The mentioned `parameters_file` will be created for every project with the following content:

```jsonc
{
  "args": {"run": ["arg1", "arg2"]} // A dictionary with subcommand names and their arguments specified as an array.
}
```

Usually you don't need to edit it manually, you can set its values using the `:Rust set_args <subcommand>` commands.

### CodeLLDB DAP configuration example

```lua
require('rust').setup({
  dap_configuration = {
    type = 'codelldb',
    request = 'launch',
    stopOnEntry = false,
    runInTerminal = false,
  }
})
```

### Advanced usage examples

```lua
progress = ""  -- can be displayed in statusline, updated in on_build_output

require('rust').setup({
  quickfix = {
    only_on_error = true,
  },
  on_build_output = function(lines)
    -- Get only last line
    local match = string.match(lines[#lines], "(%[.*%])")
    if match then
      progress = string.gsub(match, "%%", "%%%%")
    end
  end
})
```

Additionally all `rust` module functions that runs something return `Plenary.job`, so one can also set `on_exit` callbacks:

```lua
function rust_build()
  local job = require('rust').build()
  if job then
    job:after(vim.schedule_wrap(
      function(_, exit_code)
        if exit_code == 0 then
          vim.notify("Target was built successfully", vim.log.levels.INFO, { title = 'Rust' })
        else
          vim.notify("Target build failed", vim.log.levels.ERROR, { title = 'Rust' })
        end
      end
    ))
  end
end
```
