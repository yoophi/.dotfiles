-- =============================================================================
-- markdown --- Marked.app 미리보기 (macOS, Setapp 버전)
--
-- itspriddle/vim-marked 플러그인은 앱 버전이 "2"로 시작할 때만 동작하도록
-- 강제(s:MarkedVersionCheck)하는데, Setapp 의 Marked 는 버전 3 이라
-- "This plugin requires Marked 2" 오류로 :MarkedOpen 이 거부된다.
-- 플러그인 디렉토리를 직접 패치하면 업데이트 때 사라지므로, 동일한
-- :MarkedOpen / :MarkedQuit / :MarkedToggle 을 직접 구현한다.
-- =============================================================================

local marked_app = "/Applications/Setapp/Marked.app"

-- JXA: 지정한 경로의 문서만 닫고, 남은 문서가 없으면 앱을 종료한다.
local close_js = [[
function run(argv) {
  var app = Application(argv[0]);
  if (!app.running()) return;
  if (argv[1]) {
    var doc = app.documents().find(function (d) { return d.path() === argv[1]; });
    if (doc) doc.close();
  }
  if (app.documents().length === 0) app.quit();
}
]]

-- 파일 경로 -> true (현재 Marked 에 열려 있는지 추적, 토글용)
local opened = {}

local function marked_open(file)
  vim.system({ "open", "-a", marked_app, file })
  opened[file] = true
end

local function marked_quit(file)
  vim.system({ "osascript", "-l", "JavaScript", "-e", close_js, marked_app, file })
  opened[file] = nil
end

-- 현재 버퍼의 저장된 파일 경로로 fn 을 호출하는 래퍼
local function with_file(fn)
  return function()
    local file = vim.fn.expand("%:p")
    if file == "" or vim.bo.buftype ~= "" then
      vim.notify("Marked: 저장된 파일이 없습니다.", vim.log.levels.WARN)
      return
    end
    fn(file)
  end
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "markdown", "mkd", "ghmarkdown" },
  callback = function(args)
    vim.api.nvim_buf_create_user_command(args.buf, "MarkedOpen", with_file(marked_open), {})
    vim.api.nvim_buf_create_user_command(args.buf, "MarkedQuit", with_file(marked_quit), {})
    vim.api.nvim_buf_create_user_command(args.buf, "MarkedToggle", with_file(function(file)
      if opened[file] then
        marked_quit(file)
      else
        marked_open(file)
      end
    end), {})
  end,
})

return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "master", -- Neovim 0.11 호환 브랜치
    ft = { "markdown" },
    build = ":TSUpdate",
    opts = {
      ensure_installed = { "markdown", "markdown_inline" },
      highlight = {
        enable = true,
      },
    },
    config = function(_, opts)
      require("nvim-treesitter.configs").setup(opts)
    end,
  },
  -- 버퍼 내 인라인 렌더 (헤더 배경 / 코드블록 / 표 정렬 / 체크박스 등)
  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown" },
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    opts = {},
  },
}
