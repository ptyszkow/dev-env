return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      roslyn = {
        mason = false,
        cmd = { "roslyn-language-server", "--stdio", "--autoLoadProjects" },
        filetypes = { "cs" },
        root_dir = function(bufnr, on_dir)
          local root = vim.fs.root(bufnr, function(name)
            return name:match("%.slnx?$") ~= nil
          end) or vim.fs.root(bufnr, function(name)
            return name:match("%.csproj$") ~= nil
          end)
          if root then
            on_dir(root)
          end
        end,
      },
    },
  },
}
