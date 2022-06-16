local LspContainersConfig = {
  -- 'configured', 'all', or a list of server names
  ensure_installed = 'configured',
  container_runtime = "docker",
  root_dir = vim.fn.getcwd(),
  network = "none",
  docker_volume = nil,
  -- table of server names and their configuration, built when "command()" is
  -- called
  configured_servers = {},
}

local lspconfig_keys = {
  cmd = true,
  root_dir = true,
  filetypes = true,
  on_new_config = true,
  on_attach = true,
  commands = true,
  settings = true,
}


local supported_servers = {
  bashls = { image = "docker.io/lspcontainers/bash-language-server" },
  clangd = { image = "docker.io/lspcontainers/clangd-language-server" },
  dockerls = { image = "docker.io/lspcontainers/docker-language-server" },
  eslint = {
    image = 'registry.barth.tech/library/vscode-langservers:latest',
    cmd_builder = function(runtime, workdir, image, network, docker_volume, additional_arguments)
      local base_config = require 'lspconfig.server_configurations.eslint'
      local base_cmd = base_config.default_config.cmd
      additional_arguments = additional_arguments or {}

      local cmd = {runtime, 'run', '--rm', '-i', '-v', workdir..':'..workdir, '-w', workdir, image}
      vim.list_extend(cmd, base_cmd)
      vim.list_extend(cmd, additional_arguments)
      return cmd
    end,
  },
  gopls = {
    cmd_builder = function (runtime, workdir, image, network, docker_volume, additional_arguments)
      local volume = workdir..":"..workdir..":z"
      local env = vim.api.nvim_eval('environ()')
      local gopath = env.GOPATH or env.HOME.."/go"
      local gopath_volume = gopath..":"..gopath..":z"

      local group_handle = io.popen("id -g")
      local user_handle = io.popen("id -u")

      local group_id = string.gsub(group_handle:read("*a"), "%s+", "")
      local user_id = string.gsub(user_handle:read("*a"), "%s+", "")

      group_handle:close()
      user_handle:close()

      local user = user_id..":"..group_id

      local cmd = {
        runtime,
        "container",
        "run",
        "--env",
        "GOPATH="..gopath,
        "--interactive",
        "--network="..network,
        "--rm",
        "--workdir="..workdir,
        "--volume="..volume,
        "--volume="..gopath_volume,
        "--user="..user,
        image
      }
      vim.list_extend(cmd, additional_arguments)
      return cmd
    end,
    image = "docker.io/lspcontainers/gopls",
    network="bridge",
  },
  graphql = { image = "docker.io/lspcontainers/graphql-language-service-cli" },
  html = { image = "docker.io/lspcontainers/html-language-server" },
  intelephense = { image = "docker.io/lspcontainers/intelephense" },
  jsonls = { image = "docker.io/lspcontainers/json-language-server" },
  omnisharp = { image = "docker.io/lspcontainers/omnisharp" },
  powershell_es = { image = "docker.io/lspcontainers/powershell-language-server" },
  prismals = { image = "docker.io/lspcontainers/prisma-language-server" },
  pylsp = {
    image = "registry.barth.tech/library/pylsp:latest",
    cmd_builder = function(runtime, workdir, image, network, docker_volume, additional_arguments)
      local pylsp_config = require('lspconfig/server_configurations/pylsp').default_config
      local lspconfig_utils = require 'lspconfig.util'
      local bufnr = vim.api.nvim_get_current_buf()
      local bufname = vim.api.nvim_buf_get_name(bufnr)

      -- get a sane working directory to mount if one is not set
      -- first branch implementation adapted from:
      -- https://github.com/neovim/nvim-lspconfig/blob/84252b08b7f9831b0b1329f2a90ff51dd873e58f/lua/lspconfig/configs.lua#L80-L88
      if workdir == nil and lspconfig_utils.bufname_valid(bufname) then
        workdir = pylsp_config.root_dir(lspconfig_utils.path.sanitize(bufname))
      end

      -- fallback to using the editor's working directory to determine the root
      -- path
      if workdir == nil then
        local cwd = vim.fn.getcwd()
        workdir = pylsp_config.root_dir(cwd) or cwd
      end

      if additional_arguments == nil then
        additional_arguments = {}
      end

      local container_options = {'--interactive', '--rm', '--volume', workdir..':'..workdir, '--workdir', workdir}
      if vim.env.VIRTUAL_ENV then
        vim.list_extend(container_options, {'--volume', vim.env.VIRTUAL_ENV .. ':/venv'})
      end

      local cmd = {runtime, 'container', 'run'}
      vim.list_extend(cmd, container_options)
      table.insert(cmd, image)
      vim.list_extend(cmd, additional_arguments)

      return cmd
    end,
  },
  pyright = { image = "docker.io/lspcontainers/pyright-langserver" },
  rust_analyzer = { image = "docker.io/lspcontainers/rust-analyzer" },
  solargraph = { image = "docker.io/lspcontainers/solargraph" },
  sumneko_lua = { image = "docker.io/lspcontainers/lua-language-server" },
  svelte = { image = "docker.io/lspcontainers/svelte-language-server" },
  terraformls = { image = "docker.io/lspcontainers/terraform-ls" },
  tsserver = { image = "docker.io/lspcontainers/typescript-language-server" },
  vuels = { image = "docker.io/lspcontainers/vue-language-server" },
  yamlls = { image = "docker.io/lspcontainers/yaml-language-server" },
}


-- default command to run the lsp container
function LspContainersConfig.cmd_builder(runtime, workdir, image, network, docker_volume, additional_arguments)
  additional_arguments = additional_arguments or {}
  if vim.fn.has("win32") then
    workdir = Dos2UnixSafePath(workdir)
  end

  local mnt_volume
  if docker_volume ~= nil then
    mnt_volume = "--volume="..docker_volume..":"..workdir..":z"
  else
    mnt_volume = "--volume="..workdir..":"..workdir..":z"
  end

  local cmd = {
    runtime,
    "container",
    "run",
    "--interactive",
    "--rm",
    "--network="..network,
    "--workdir="..workdir,
    mnt_volume,
    image
  }
  vim.list_extend(cmd, additional_arguments)
  return cmd
end


local function configure(server, user_opts)
  local opts = vim.tbl_extend("force", {}, LspContainersConfig)

  -- If the LSP is known, it override the defaults:
  if supported_servers[server] ~= nil then
    opts = vim.tbl_extend("force", opts, supported_servers[server])
  end

  -- If any opts were passed, those override the defaults:
  if user_opts ~= nil then
    opts = vim.tbl_extend("force", opts, user_opts)
  end

  if not opts.image then
    error(string.format("lspcontainers: no image specified for `%s`", server))
    return 1
  end

  local config = {
    cmd = opts.cmd_builder(opts.container_runtime, opts.root_dir, opts.image, opts.network, opts.docker_volume),
  }

  for name, value in pairs(opts) do
    if lspconfig_keys[name] then
      config[name] = value
    end
  end

  LspContainersConfig.configured_servers[server] = config
  return config
end


local function command(server, user_opts)
  return configure(server, user_opts).cmd
end


Dos2UnixSafePath = function(workdir)
  workdir = string.gsub(workdir, ":", "")
  workdir = string.gsub(workdir, "\\", "/")
  workdir = "/" .. workdir
  return workdir
end


-- callback for job event handlers
local function on_event(_, data, event)
  --if event == "stdout" or event == "stderr" then
  if event == "stdout" then
    if data then
      for _, v in pairs(data) do
        print(v)
      end
    end
  end
end

-- dispatch commands with the configured container runtime
local function runtime(arguments)
  if type(arguments) ~= 'string' then
    error('runtime arguments must be given as a string')
  end

  return vim.fn.jobstart(
    LspContainersConfig.runtime .. " " .. arguments,
    {
      on_stderr = on_event,
      on_stdout = on_event,
      on_exit = on_event,
    }
  )
end


-- used for LspImagesPull and LspImagesRemove
local function _image_list()
  local images = {}
  if type(LspContainersConfig.ensure_installed) == 'table' then
    return LspContainersConfig.ensure_installed
  end

  -- add configured servers, returned for both 'all' and 'configured' values
  for server_name, server_config in pairs(LspContainersConfig.configured_servers) do
    images[server_name] = server_config.image
  end

  if LspContainersConfig.configured_servers == 'all' then
    for server_name, server_config in pairs(supported_servers) do
      if images[server_name] ~= nil then
        images[server_name] = server_config.image
      end
    end
  end

  local imglist = {}
  for _, image in pairs(images) do
    imglist[#imglist + 1] = image
  end
  return imglist
end


-- pull images specified by ensure_installed
local function images_pull()
  local jobs = {}

  for i, image in ipairs(_image_list()) do
    jobs[i] = runtime("image pull "..image)
  end

  local _ = vim.fn.jobwait(jobs)

  print("lspcontainers: Language servers successfully pulled")
end


local function images_remove()
  local jobs = {}

  -- TODO: detect old versions from docker image list
  for _, image in ipairs(_image_list()) do
    table.insert(jobs, #jobs + 1, runtime("image rm --force "..image))
  end

  local _ = vim.fn.jobwait(jobs)

  print("lspcontainers: All language servers removed")
end


vim.cmd [[
  command -nargs=0 LspImagesPull lua require'lspcontainers'.images_pull()
  command -nargs=0 LspImagesRemove lua require'lspcontainers'.images_remove()
]]


-- set global options for lspcontainers
local function setup(options)
  for key, val in pairs(options) do
    LspContainersConfig[key] = val
  end
end


return {
  command = command,
  configure = configure,
  images_pull = images_pull,
  images_remove = images_remove,
  setup = setup,
  supported_servers = supported_servers
}
