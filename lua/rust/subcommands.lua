local rust = require('rust')
local utils = require('rust.utils')
local Job = require('plenary.job')
local subcommands = {}

local cargo_subcommands = nil

local function fetch_cargo_subcommands()
  cargo_subcommands = {}

  local job = Job:new({
    command = 'cargo',
    args = { '--list' },
    enabled_recording = true,
  })
  job:sync()

  if job.code ~= 0 or job.signal ~= 0 then
    utils.notify('Unable to get list of available cargo subcommands', vim.log.levels.ERROR)
    return
  end

  local start_offset = 5
  for index, line in ipairs(job:result()) do
    if index ~= 1 and not line:find('alias:') then
      local subcommand_end = line:find(' ', start_offset)
      table.insert(cargo_subcommands, line:sub(start_offset, subcommand_end))
    end
  end
end

function subcommands.complete(arg, cmd_line)
  local matches = {}

  local words = vim.split(cmd_line, ' ', { trimempty = true })
  if not vim.endswith(cmd_line, ' ') then
    -- Last word is not fully typed, don't count it
    table.remove(words, #words)
  end

  if #words == 1 then
    for subcommand in pairs(rust) do
      if vim.startswith(subcommand, arg) and subcommand ~= 'setup' then
        table.insert(matches, subcommand)
      end
    end
  elseif #words == 2 then
    if not cargo_subcommands then
      fetch_cargo_subcommands()
    end
    if words[2] == 'set_args' then
      for _, subcommand in ipairs(vim.list_extend({ 'global' }, cargo_subcommands)) do
        if vim.startswith(subcommand, arg) then
          table.insert(matches, subcommand)
        end
      end
    elseif words[2] == 'cargo' then
      for _, subcommand in ipairs(cargo_subcommands) do
        if vim.startswith(subcommand, arg) then
          table.insert(matches, subcommand)
        end
      end
    elseif words[2] == 'debug' then
      for _, subcommand in ipairs({ 'run', 'test' }) do
        if vim.startswith(subcommand, arg) then
          table.insert(matches, subcommand)
        end
      end
    end
  end

  return matches
end

function subcommands.run(subcommand)
  local subcommand_func = rust[subcommand.fargs[1]]
  if not subcommand_func then
    utils.notify('No such subcommand: ' .. subcommand.fargs[1], vim.log.levels.ERROR)
    return
  end
  local subcommand_info = debug.getinfo(subcommand_func)
  if subcommand_info.isvararg and #subcommand.fargs - 1 < subcommand_info.nparams then
    utils.notify('Subcommand: ' .. subcommand.fargs[1] .. ' should have at least ' .. subcommand_info.nparams .. ' argument(s)', vim.log.levels.ERROR)
    return
  elseif not subcommand_info.isvararg and #subcommand.fargs - 1 ~= subcommand_info.nparams then
    utils.notify('Subcommand: ' .. subcommand.fargs[1] .. ' should have ' .. subcommand_info.nparams .. ' argument(s)', vim.log.levels.ERROR)
    return
  end
  subcommand_func(unpack(subcommand.fargs, 2))
end

return subcommands
