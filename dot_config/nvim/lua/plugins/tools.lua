-- =============================================================================
-- tools --- 보조 도구
--   - vim-dirdiff: 두 디렉토리 비교 (:DirDiff)
-- =============================================================================

return {
  {
    "will133/vim-dirdiff",
    cmd = { "DirDiff" },
    init = function()
      -- 비교에서 제외할 항목 (콤마 구분 문자열)
      vim.g.DirDiffExcludes = ".git,node_modules,build"
    end,
  },
}
