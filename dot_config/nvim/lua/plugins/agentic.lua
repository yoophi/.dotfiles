-- =============================================================================
-- agentic.nvim --- AI 에이전트 (claude-agent-acp)
-- 선결조건: Neovim >= 0.11, Node.js, @agentclientprotocol/claude-agent-acp CLI
-- 키맵은 기존 SpaceVim 부트스트랩(myspacevim.vim)의 값을 그대로 이전했다.
-- =============================================================================

return {
  "carlos-algms/agentic.nvim",
  opts = {
    provider = "codex-acp",
  },
  keys = {
    {
      "<C-\\>",
      function() require("agentic").toggle() end,
      mode = { "n", "v", "i" },
      desc = "Agentic: 채팅 토글",
    },
    {
      "<C-'>",
      function() require("agentic").add_selection_or_file_to_context() end,
      mode = { "n", "v" },
      desc = "Agentic: 선택영역/파일을 컨텍스트에 추가",
    },
    {
      "<C-,>",
      function() require("agentic").new_session() end,
      mode = { "n", "v", "i" },
      desc = "Agentic: 새 세션",
    },
    {
      "<A-i>r",
      function() require("agentic").restore_session() end,
      mode = { "n", "v", "i" },
      desc = "Agentic: 세션 복원",
    },
    {
      "<leader>ad",
      function() require("agentic").add_current_line_diagnostics() end,
      desc = "Agentic: 현재 줄 진단 추가",
    },
    {
      "<leader>aD",
      function() require("agentic").add_buffer_diagnostics() end,
      desc = "Agentic: 버퍼 진단 추가",
    },
  },
}
