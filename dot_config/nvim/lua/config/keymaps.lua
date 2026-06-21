-- =============================================================================
-- keymaps.lua --- 공통 키맵
-- 플러그인 전용 키맵은 각 lua/plugins/*.lua 의 keys 에 정의한다.
-- =============================================================================

local map = vim.keymap.set

-- 검색 하이라이트 끄기
map("n", "<leader>fh", "<cmd>nohlsearch<cr>", { desc = "검색 하이라이트 끄기" })

-- ---------------------------------------------------------------------------
-- 선택 영역(visual) 마크다운 미리보기
-- ---------------------------------------------------------------------------
-- 현재 visual 선택 영역을 임시 .md 파일로 추출한다.
local function selection_to_tmp_md()
  local l1, l2 = vim.fn.line("v"), vim.fn.line(".")
  if l1 > l2 then
    l1, l2 = l2, l1
  end
  local tmp = vim.fn.tempname() .. ".md"
  vim.fn.writefile(vim.fn.getline(l1, l2), tmp)
  return tmp
end

-- \mp : glow 로 터미널 내부 미리보기
map("x", "<leader>mp", function()
  local tmp = selection_to_tmp_md()
  vim.cmd("botright split | resize 20")
  vim.cmd("terminal glow -p " .. vim.fn.fnameescape(tmp))
  vim.cmd("startinsert")
end, { desc = "선택 영역 Glow 미리보기" })

-- \mP : Marked.app(GUI) 으로 미리보기 (macOS)
map("x", "<leader>mP", function()
  vim.fn.system({ "open", "-a", "/Applications/Setapp/Marked.app", selection_to_tmp_md() })
end, { desc = "선택 영역 Marked 미리보기" })

vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    vim.keymap.set("n", "gd", vim.lsp.buf.definition, {
      buffer = args.buf,
      desc = "정의로 이동",
    })
  end,
})
