-- =============================================================================
-- options.lua --- 기본 에디터 설정
-- 기존 SpaceVim 환경에서 실측한 값을 그대로 재현한다 (migration-plan.md §1.4).
-- =============================================================================

local opt = vim.opt

-- 인코딩
opt.encoding = "utf-8"

-- 들여쓰기 / 탭
opt.expandtab = true   -- 탭을 공백으로
opt.tabstop = 2
opt.shiftwidth = 2
opt.softtabstop = 2
opt.autoindent = true

-- 폴딩 (기존 감각 유지: 수동 폴딩)
opt.foldmethod = "manual"

-- 줄 번호
opt.number = true
opt.relativenumber = true

-- 검색
opt.hlsearch = true
opt.incsearch = true
opt.ignorecase = false
opt.smartcase = false

-- 기타
opt.mouse = "nv"     -- normal / visual 모드에서 마우스 사용
opt.scrolloff = 1
