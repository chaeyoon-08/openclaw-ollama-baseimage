# TOOLS.md -- 시스템 경로 레퍼런스

## 경로

| 항목 | 경로 |
|------|------|
| workspace | /root/.openclaw/workspace |
| 설정 파일 | /root/.openclaw/openclaw.json |
| 환경변수 | /root/.openclaw/.env |

## 설정 갱신

```
.env 수정 → bash /usr/local/bin/reload.sh
  = openclaw.json 재생성 + gateway 재시작
```

## 슬래시 명령어

| 명령어 | 동작 |
|--------|------|
| /model | 모델 선택/변경 |
| /model list | 사용 가능한 모델 목록 |
| /skill [이름] | 스킬 실행 |
| /status | 현재 상태 확인 |
| /reset | 새 대화 시작 |
| /help | 도움말 |
