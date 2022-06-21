local Job = require('plenary.job')
local config = require('rust.config')
local utils = {}

-- Modified version of `errorformat` from the official Rust plugin for Vim:
-- https://github.com/rust-lang/rust.vim/blob/4aa69b84c8a58fcec6b6dad6fe244b916b1cf830/compiler/rustc.vim#L32
-- https://github.com/rust-lang/rust.vim/blob/4aa69b84c8a58fcec6b6dad6fe244b916b1cf830/compiler/cargo.vim#L35
-- We display all lines (not only error messages) since we show output in quickfix.
-- Zero-width look-ahead regex is used to avoid marking general messages as errors: %\%%(ignored text%\)%\@!.
local errorformat = [[%Eerror: %\%%(aborting %\|could not compile%\)%\@!%m,]]
  .. [[%Eerror[E%n]: %m,]]
  .. [[%Inote: %m,]]
  .. [[%Wwarning: %\%%(%.%# warning%\)%\@!%m,]]
  .. [[%C %#--> %f:%l:%c,]]
  .. [[%E  left:%m,%C right:%m %f:%l:%c,%Z,]]
  .. [[%.%#panicked at \'%m\'\, %f:%l:%c]]

local function detect_package_name(args)
  for index, value in ipairs(args) do
    if value == '-p' or value == '--package' or value == '--bin' then
      return args[index + 1]
    end
  end
  return nil
end

local function find_executable_packages(packages)
  local executables = {}
  for _, line in pairs(packages) do
    local package = vim.json.decode(line)
    if package.executable and package.executable ~= vim.NIL then
      table.insert(executables, package)
    end
  end
  return executables
end

local function save_all_buffers()
  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    if #vim.api.nvim_buf_get_name(buffer) ~= 0 and vim.api.nvim_buf_get_option(buffer, 'modified') then
      vim.api.nvim_command('silent write')
    end
  end
end

local function append_to_quickfix(lines)
  vim.fn.setqflist({}, 'a', { efm = errorformat, lines = lines })
  -- Scrolls the quickfix buffer if not active
  if vim.bo.buftype ~= 'quickfix' then
    vim.api.nvim_command('cbottom')
  end
  if config.on_build_output then
    config.on_build_output(lines)
  end
end

local function show_quickfix()
  vim.api.nvim_command(config.quickfix.pos .. ' copen ' .. config.quickfix.height)
  vim.api.nvim_command('wincmd p')
end

local function read_to_quickfix()
  -- Modified from https://github.com/nvim-lua/plenary.nvim/blob/968a4b9afec0c633bc369662e78f8c5db0eba249/lua/plenary/job.lua#L287
  -- We use our own implementation to process data in chunks because
  -- default Plenary callback processes every line which is very slow for adding to quickfix.
  return coroutine.wrap(function(err, data, is_complete)
    -- We repeat forever as a coroutine so that we can keep calling this.
    local lines = {}
    local result_index = 1
    local result_line = nil
    local found_newline = nil

    while true do
      if data then
        data = data:gsub('\r', '')

        local processed_index = 1
        local data_length = #data + 1

        repeat
          local start = string.find(data, '\n', processed_index, true) or data_length
          local line = string.sub(data, processed_index, start - 1)
          found_newline = start ~= data_length

          -- Concat to last line if there was something there already.
          --    This happens when "data" is broken into chunks and sometimes
          --    the content is sent without any newlines.
          if result_line then
            result_line = result_line .. line

            -- Only put in a new line when we actually have new data to split.
            --    This is generally only false when we do end with a new line.
            --    It prevents putting in a "" to the end of the results.
          elseif start ~= processed_index or found_newline then
            result_line = line

            -- Otherwise, we don't need to do anything.
          end

          if found_newline then
            if not result_line then
              return vim.api.nvim_err_writeln('Broken data thing due to: ' .. tostring(result_line) .. ' ' .. tostring(data))
            end

            table.insert(lines, err and err or result_line)

            result_index = result_index + 1
            result_line = nil
          end

          processed_index = start + 1
        until not found_newline
      end

      if is_complete and not found_newline then
        table.insert(lines, err and err or result_line)
      end

      if #lines ~= 0 then
        -- Move lines to another variable and send them to quickfix
        local processed_lines = lines
        lines = {}
        vim.schedule(function()
          append_to_quickfix(processed_lines)
        end)
      end

      if data == nil or is_complete then
        return
      end

      err, data, is_complete = coroutine.yield()
    end
  end)
end

function utils.notify(msg, log_level)
  vim.notify(msg, log_level, { title = 'Rust' })
end

function utils.split_args(args)
  if not args then
    return {}
  end

  -- Split on spaces unless "in quotes"
  local splitted_args = vim.fn.split(args, [[\s\%(\%([^'"]*\(['"]\)[^'"]*\1\)*[^'"]*$\)\@=]])

  -- Remove quotes
  for i, arg in ipairs(splitted_args) do
    splitted_args[i] = arg:gsub('"', ''):gsub("'", '')
  end
  return splitted_args
end

function utils.join_args(args)
  if not args then
    return ''
  end

  -- Add quotes if argument contain spaces
  for index, arg in ipairs(args) do
    if arg:find(' ') then
      args[index] = '"' .. arg .. '"'
    end
  end

  return table.concat(args, ' ')
end

function utils.run(cmd, args)
  if not utils.ensure_no_job_active() then
    return
  end

  if config.save_before_build and cmd == config.cmake_executable then
    save_all_buffers()
  end

  if not config.quickfix.only_on_error then
    show_quickfix()
  end

  vim.fn.setqflist({}, ' ', { title = cmd .. ' ' .. table.concat(args, ' ') })
  local is_message_mode = vim.tbl_contains(args, '--message-format=json')
  utils.last_job = Job:new({
    command = cmd,
    args = args,
    cwd = vim.loop.cwd(),
    enabled_recording = is_message_mode,
    on_exit = vim.schedule_wrap(function(_, code, signal)
      append_to_quickfix({ 'Exited with code ' .. (signal == 0 and code or 128 + signal) })
      if (code ~= 0 or signal ~= 0) and config.quickfix.only_on_error then
        show_quickfix()
      end
    end),
  })

  utils.last_job:start()
  utils.last_job.stderr:read_start(read_to_quickfix())
  if not is_message_mode then
    utils.last_job.stdout:read_start(read_to_quickfix())
  end
  return utils.last_job
end

function utils.find_list_element(list, element)
  for index, value in ipairs(list) do
    if value == element then
      return index
    end
  end
  return nil
end

function utils.get_executable_package(packages, args)
  local executables = find_executable_packages(packages)
  if #executables == 1 then
    return executables[1]
  end

  -- Try to detect package name from arguments
  local package_name = detect_package_name(args)
  if not package_name then
    local available_names = {}
    for _, executable in ipairs(executables) do
      table.insert(available_names, executable.target.name)
    end
    utils.notify('Could not determine which binary to run\nUse the `--bin` or `--package` option to specify a binary\nAvailable binaries: ' .. table.concat(available_names, ', '), vim.log.levels.ERROR)
    return
  end

  for _, package in ipairs(executables) do
    if package.target.name == package_name then
      return package
    end
  end

  utils.notify('Unable to find package name ' .. package_name, vim.log.levels.ERROR)
  return nil
end

function utils.ensure_no_job_active()
  if not utils.last_job or utils.last_job.is_shutdown then
    return true
  end
  utils.notify('Another job is currently running: ' .. utils.last_job.command, vim.log.levels.ERROR)
  return false
end

return utils
