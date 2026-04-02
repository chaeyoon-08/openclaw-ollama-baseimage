# 구현 계획

## 구현 완료

```bash
git log --oneline
```

---

## 현재 진행 (커밋 대기)

- workspace 단순화 (SOUL.md, AGENTS.md, USER.md, TOOLS.md만 유지)
- OpenClaw 빌트인 명령어(/model, /skill) 활용 방식으로 전환
- .env.example 기본 모델 qwen3.5:35b로 변경
- 복잡한 에이전트 구조 → feature/agent-structure 브랜치로 분리 보존

---

## 향후 계획

- qwen3.5:35b 배포 테스트 (기본 대화, /model list, /skill 동작 확인)
- API 키 노출 방지 (OpenClaw sandbox/tool 권한 설정 조사)
- 에이전트 구조 고도화 (feature/agent-structure 브랜치에서 진행)
- preset_image/ 디렉터리 (프리셋 스킬 이미지)
