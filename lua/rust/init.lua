local utils = require('rust.utils')
local config = require('rust.config')
local dap = require('dap')
local ProjectConfig = require('rust.project_config')
local rust = {}

function rust.setup(values)
  setmetatable(config, { __index = vim.tbl_deep_extend('force', config.defaults, values) })
end

function rust.cargo(subcommand, ...)
  local project_config = ProjectConfig.new()
  local args = vim.list_extend({ subcommand }, project_config.json.args.global) -- Put subcommand first
  vim.list_extend(args, project_config.json.args[subcommand] or {})
  vim.list_extend(args, { ... })
  return utils.run('cargo', args)
end

function rust.debug(subcommand, ...)
  local args = {}
  if subcommand == 'test' then
    table.insert(args, 'test')
    table.insert(args, '--no-run')
  elseif subcommand == 'run' then
    table.insert(args, 'build')
  else
    utils.notify('Unknown debug subcommand: ' .. subcommand)
    return nil
  end
  table.insert(args, '--message-format=json')

  local project_config = ProjectConfig.new()
  vim.list_extend(args, project_config.json.args.global)
  vim.list_extend(args, project_config.json.args[subcommand] or {})
  vim.list_extend(args, { ... })

  local separator = utils.find_list_element(args, '--')
  local job = utils.run('cargo', separator and vim.list_slice(args, 1, separator - 1) or args)
  if not job then
    return
  end

  job:after_success(vim.schedule_wrap(function()
    local executable = utils.get_executable_package(job:result(), args)
    if not executable then
      return
    end

    local dap_config = {
      name = executable.target.name,
      program = executable.executable,
      args = separator and vim.list_slice(args, separator + 1) or {},
      cwd = vim.loop.cwd(),
    }
    dap.run(vim.tbl_extend('force', dap_config, config.dap_configuration))
    vim.api.nvim_command('cclose')
    if config.dap_open_command then
      config.dap_open_command()
    end
  end))

  return job
end

function rust.set_args(subcommand)
  local project_config = ProjectConfig.new()
  vim.ui.input({ prompt = 'Arguments for ' .. subcommand .. ': ', default = project_config.json.type or '', completion = 'file' }, function(input)
    project_config.json.args[subcommand] = input
    project_config:write()
  end)
end

function rust.cancel()
  if not utils.last_job or utils.last_job.is_shutdown then
    utils.notify('No running process')
    return
  end

  utils.last_job:shutdown(1, 9)

  if vim.fn.has('win32') == 1 then
    -- Kill all children
    for _, pid in ipairs(vim.api.nvim_get_proc_children(utils.last_job.pid)) do
      vim.loop.kill(pid, 9)
    end
  else
    vim.loop.kill(utils.last_job.pid, 9)
  end
end

return rust
