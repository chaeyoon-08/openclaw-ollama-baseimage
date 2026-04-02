# 구현 계획

## 구현 완료

git commit 내역을 확인할 것.

```bash
git log --oneline
```

---

## 현재 진행 (커밋 대기)

### 인프라
- generate-config.sh 분리 (웹 검색 DuckDuckGo 설정 포함)
- reload.sh 작성
- entrypoint.sh 수정 (.env 덤프 + generate-config.sh 호출 + workspace 초기화)
- Dockerfile 수정 (새 스크립트 + workspace COPY)

### 에이전트 설계
- docs/DESIGN.md (전체 설계서)

### workspace 파일
- SOUL.md (페르소나 + 정보 탐색 + 출처 표기 + 사실 보고 + 자가 진단 + 시행착오 학습)
- IDENTITY.md (이름 + 첫 대화/복원 동작)
- AGENTS.md (운영 지침 + 스킬 라우팅 + 메모리 운영 + 프로토콜)
- USER.md (프로필 + 출처 표기 설정)
- TOOLS.md (경로 + 웹 검색 + 외부 provider)
- HEARTBEAT.md (주기적 체크)
- BOOTSTRAP.md (첫 실행 시스템 점검)
- MEMORY.md (기억 인덱스)

### 스킬 (10개)
- onboarding, profile-editor, memory-manager
- skill-creator (간단/상세 모드 + 공식 문서 실시간 조회)
- skill-editor (모델 할당 포함)
- skill-toggle, skill-delete (2단계 확인)
- rule-editor (레드라인 충돌 검사)
- agent-router (스킬별 모델 배치)
- status-dashboard (4가지 뷰: 전체/세부/역할설명/모델별)
- _template/SKILL_TEMPLATE.md (스킬 작성 규칙)

---

## 향후 계획

- 실제 배포 테스트 (Ollama tool calling + 웹 검색 동작 확인)
- preset_image/ 디렉터리 (사용자 니즈 기반 프리셋 스킬 이미지, base 위에 레이어)
- workspace 백업/복원 연동 (backup-manager.sh 통합)
- 에이전트 자가 테스트 기능
- 스킬 버전 관리 + 롤백
- 멀티 에이전트 실제 라우팅 (openclaw.json agents.list)
- ClawHub 스킬 설치 연동
- 복원 완료 시 Telegram 선제 알림
