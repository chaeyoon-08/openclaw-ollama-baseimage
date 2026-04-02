# DESIGN.md -- 설계서

> 최종 업데이트: 2026-04-02

---

## 설계 목표

1. 컨테이너 배포 즉시 Telegram 봇이 동작
2. 환경변수만으로 모델/API 설정 완료
3. OpenClaw 빌트인 명령어(/model, /skill 등)로 관리

---

## 기본 사양

| 항목 | 값 |
|------|-----|
| 톤 | 간결한 실무형, 한국어 |
| 기본 모델 | Ollama qwen3.5:35b (권장) |
| 웹 검색 | DuckDuckGo (기본, API 키 불필요) |
| 모델 관리 | /model 빌트인 명령어 |
| 스킬 관리 | /skill 빌트인 명령어 |

---

## workspace 파일 구조 (최소)

```
/root/.openclaw/workspace/
├── SOUL.md    ← 페르소나, 톤, 레드라인
├── AGENTS.md  ← 운영 지침, 슬래시 명령어 안내
├── USER.md    ← 사용자 프로필
└── TOOLS.md   ← 경로, 슬래시 명령어 레퍼런스
```

---

## 환경변수 & 설정 갱신

```
컨테이너 시작:
  gcube ENV → entrypoint.sh → .env 덤프 + generate-config.sh → openclaw.json

설정 변경:
  .env 수정 → reload.sh → openclaw.json 재생성 + gateway 재시작
```

---

## 향후 계획

- 에이전트 구조 고도화 → feature/agent-structure 브랜치 참조
- preset_image/ (사용자 니즈 기반 프리셋 스킬 이미지)
- 모델별 권장 사양 문서화
