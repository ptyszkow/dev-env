return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      ty = { mason = false },
      ruff = { mason = false },
      clangd = { mason = false },
    },
  },
}
