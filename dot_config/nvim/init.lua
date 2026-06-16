-- =============================================================================
-- init.lua --- Neovim 엔트리 파일 (SpaceVim 제거 후 직접 관리)
-- 마이그레이션 계획: ~/private/2026-06-12/neovim-without-spacevim/migration-plan.md
-- =============================================================================

-- leader 키는 플러그인(lazy.nvim) 로드 전에 설정해야 한다.
-- leader = Space, localleader 는 Vim 기본값("\") 사용.
vim.g.mapleader = " "

require("config.options") -- 기본 에디터 설정
require("config.keymaps") -- 공통 키맵
require("config.lazy")    -- 플러그인 매니저 부트스트랩 + 플러그인 로드
