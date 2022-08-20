local config = require('rust.config')
local Path = require('plenary.path')
local ProjectConfig = {}
ProjectConfig.__index = ProjectConfig

function ProjectConfig.new()
  local project_config = {}
  local parameters_file = Path:new(config.parameters_file)
  if parameters_file:is_file() then
    project_config.json = vim.json.decode(parameters_file:read())
  else
    project_config.json = {}
  end
  project_config.json = vim.tbl_extend('keep', project_config.json, config.default_parameters)
  return setmetatable(project_config, ProjectConfig)
end

function ProjectConfig:write()
  local parameters_file = Path:new(config.parameters_file)
  parameters_file:write(vim.json.encode(self.json), 'w')
end

return ProjectConfig
