;;; init.el --- Personal Emacs configuration  -*- lexical-binding: t; -*-

;;; Commentary:
;; Personal Emacs configuration.

;;; Code:

;;; 1. 패키지 시스템

(require 'package)

(setq package-archives
      '(("gnu"    . "https://elpa.gnu.org/packages/")
        ("nongnu" . "https://elpa.nongnu.org/nongnu/")
        ("melpa"  . "https://melpa.org/packages/")))

(package-initialize)

;;; 2. 외관 / UI

(menu-bar-mode 1)

(when (fboundp 'tool-bar-mode)
  (tool-bar-mode -1))

(column-number-mode 1)

(show-paren-mode 1)

;;; 3. 언어 / 입력기

(set-language-environment "Korean")

(prefer-coding-system 'utf-8)

;; 두벌식을 쓰려면 "korean-hangul" 로 변경.
(setq default-input-method "korean-hangul390")

(global-set-key (kbd "C-\\") #'toggle-input-method)

;;; 4. 플랫폼별 설정 (macOS)

(when (eq system-type 'darwin)
  (setq mac-option-modifier 'meta
        mac-command-modifier 'super))

;;; 5. 패키지별 설정

;; 새 환경에서 아카이브 캐시(elpa/archives/)가 없으면 한 번만 갱신.
;; 캐시가 있으면 건너뛰므로 매 시작마다 네트워크를 타지 않는다.
(unless package-archive-contents
  (package-refresh-contents))

(use-package evil
  :ensure t
  :init (setq evil-want-keybinding nil)  ; evil-collection 쓸 경우 권장
  :config (evil-mode 1))

(use-package magit
  :ensure t
  :bind ("C-x g" . magit-status))

;; ACP CLI 경로를 이식성 있게 탐색.
;; 1) PATH (executable-find)  2) $PNPM_HOME  3) ~/Library/pnpm 기본값
;; 그래도 못 찾으면 이름만 반환해 실행 시점의 PATH 탐색에 맡긴다.
(defun my/acp-command (bin)
  "Locate ACP CLI BIN portably; return its path or BIN as fallback."
  (or (executable-find bin)
      (let ((pnpm-bin (expand-file-name
                       bin (or (getenv "PNPM_HOME") "~/Library/pnpm"))))
        (and (file-executable-p pnpm-bin) pnpm-bin))
      bin))

;;   M-x agent-shell-openai-start-codex          → OpenAI Codex
;;   M-x agent-shell-anthropic-start-claude-code → Anthropic Claude
(use-package agent-shell
  :ensure t
  :commands (agent-shell-openai-start-codex
             agent-shell-anthropic-start-claude-code)
  :config
  (setq agent-shell-openai-codex-acp-command
        (list (my/acp-command "codex-acp")))
  (setq agent-shell-openai-authentication
        (agent-shell-openai-make-authentication :login t))

  (setq agent-shell-anthropic-claude-acp-command
        (list (my/acp-command "claude-agent-acp")))
  (setq agent-shell-anthropic-authentication
        (agent-shell-anthropic-make-authentication :login t))

  ;; compose 버퍼: C-c C-c 전송 / C-c C-k 취소 / M-p, M-n, M-r 히스토리
  (define-key agent-shell-mode-map (kbd "C-c C-e") #'agent-shell-prompt-compose))

;;; 6. Custom (Emacs 가 자동으로 관리하는 영역)

(custom-set-variables
 '(package-selected-packages '(agent-shell evil magit)))
(custom-set-faces
 )

;;; init.el ends here
