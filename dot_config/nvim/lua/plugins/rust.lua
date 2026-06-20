-- =============================================================================
-- rust --- Rust language support
--   - rustaceanvim: rust-analyzer integration, code actions, diagnostics
-- =============================================================================

return {
  {
    "mrcjkb/rustaceanvim",
    version = "^6",
    ft = { "rust" },
    init = function()
      vim.g.rustaceanvim = {
        server = {
          default_settings = {
            ["rust-analyzer"] = {
              cargo = {
                allFeatures = true,
              },
              check = {
                command = "clippy",
              },
            },
          },
        },
      }
    end,
  },
}
