local config = require('rust.config')
local Path = require('plenary.path')
local ProjectConfig = {}
ProjectConfig.__index = ProjectConfig

local json_defaults = {
  args = {
    global = {},
  },
}

function ProjectConfig.new()
  local project_config = {}
  local parameters_file = Path:new(config.parameters_file)
  if parameters_file:is_file() then
    project_config.json = vim.json.decode(parameters_file:read())
  else
    project_config.json = {}
  end
  project_config.json = vim.tbl_extend('keep', project_config.json, json_defaults)
  return setmetatable(project_config, ProjectConfig)
end

function ProjectConfig:write()
  local parameters_file = Path:new(config.parameters_file)
  parameters_file:write(vim.json.encode(self.json), 'w')
end

return ProjectConfig
