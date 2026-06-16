-- =============================================================================
-- editing --- 텍스트 정렬 도구
--   - vim-easy-align: 인터랙티브 정렬 (ga)
--   - tabular: 구분자/패턴 기반 표 정렬 (:Tabularize)
--   - vim-table-mode: 마크다운 표 실시간 정렬·생성 (<Leader>tm 토글)
-- =============================================================================

return {
  {
    "junegunn/vim-easy-align",
    cmd = { "EasyAlign", "LiveEasyAlign" },
    keys = {
      { "ga", "<Plug>(EasyAlign)", mode = { "n", "x" }, desc = "EasyAlign" },
    },
  },
  {
    "godlygeek/tabular",
    cmd = { "Tabularize", "AddTabularPattern", "AddTabularPipeline" },
  },
  {
    "dhruvasagar/vim-table-mode",
    ft = { "markdown", "markdown.mdx" },
    cmd = { "TableModeToggle", "TableModeEnable", "TableModeRealign", "Tableize" },
    init = function()
      -- GitHub Flavored Markdown 호환: 표 코너를 '|' 로 (기본 '+' → GFM 깨짐)
      vim.g.table_mode_corner = "|"
    end,
  },
}
