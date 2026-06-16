-- =============================================================================
-- nerdtree --- 파일 탐색기 (+ git 상태 표시)
-- =============================================================================

return {
  "preservim/nerdtree",
  dependencies = {
    "Xuyuanp/nerdtree-git-plugin",
  },
  cmd = { "NERDTree", "NERDTreeToggle", "NERDTreeFocus", "NERDTreeFind" },
  keys = {
    { "<C-n>", "<cmd>NERDTreeToggle<cr>", desc = "NERDTree 토글" },
    { "<leader>ft", "<cmd>NERDTreeToggle<cr>", desc = "파일 트리 토글" },
    { "<leader>fn", "<cmd>NERDTreeFind<cr>", desc = "현재 파일을 트리에서 찾기" },
  },
}
