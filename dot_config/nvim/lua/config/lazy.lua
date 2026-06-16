-- =============================================================================
-- lazy.lua --- lazy.nvim 부트스트랩 및 플러그인 로드
-- =============================================================================

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "--branch=stable", lazyrepo, lazypath,
  })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "lazy.nvim 설치 실패:\n", "ErrorMsg" },
      { out, "WarningMsg" },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    { import = "plugins" }, -- lua/plugins/*.lua 자동 로드
  },
  -- 색상 테마는 Neovim 기본값 사용 (최소 구성)
  install = { colorscheme = { "habamax" } },
  checker = { enabled = false }, -- 자동 업데이트 확인 비활성화
})
