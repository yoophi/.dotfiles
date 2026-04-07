# dotfiles

개인 설정 파일 및 유틸리티 스크립트 모음.

## 구조

```
.claude/
  statusline.sh   # Claude Code 상태줄 스크립트 (plain text, ASCII bar)
bin/
  sandbox.sh      # 날짜별 sandbox 디렉토리 생성 후 이동
```

## 설치

심볼릭 링크로 연결:

```bash
# Claude Code statusline
ln -sf ~/private/.dotfiles/.claude/statusline.sh ~/.claude/statusline.sh

# bin 스크립트를 PATH에 추가하거나 개별 링크
ln -sf ~/private/.dotfiles/bin/sandbox.sh ~/bin/sandbox.sh
```
