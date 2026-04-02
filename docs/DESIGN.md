# DESIGN.md -- 에이전트 구조 설계서

> 최종 업데이트: 2026-04-02
> 구현 시 이 문서를 기준으로 작업합니다.

---

## 1. 설계 목표

1. **배포 즉시 사용 가능**: 기본 에이전트 구조가 잘 갖춰져 있어서 별도 설정 없이 바로 사용
2. **Telegram 자연어 커스텀**: 사용자가 채팅으로 요청하면 설정 파일이 적절히 생성/수정
3. **점진적 확장**: 최소 기능으로 시작, 필요할 때 스킬/모델 추가

---

## 2. 기본 에이전트 사양

| 항목 | 값 |
|------|-----|
| 톤 | 간결한 실무형 |
| 언어 | 한국어 고정 |
| 기본 모델 | Ollama qwen3.5:9b (권장) |
| 웹 검색 | DuckDuckGo (기본, API 키 불필요) |
| 시스템 스킬 | 10개 |
| 사용자 추가 스킬 | Telegram 대화를 통해 생성 |

---

## 3. 핵심 원칙 (SOUL.md에 정의)

| 원칙 | 내용 |
|------|------|
| 정보 탐색 | 웹 검색 > 공식 문서 > 시스템 확인 > 학습 데이터 순서 |
| 출처 표기 | 기본값 "간략" (숨김/간략/상세 3단계, USER.md 설정) |
| 사실 보고 | 거짓 완료 보고 절대 금지. 실제 상태만 보고 |
| 자가 진단 | 문제 발생 시 사용자에게 묻기 전 스스로 원인 파악 시도 |
| 시행착오 학습 | 반복 수정 패턴 감지 시 작업 방식 개선 제안 → 승인 시 규칙 기록 |

---

## 4. 모델 구조

### 기본 (Ollama만)
- 오케스트레이션: `ollama/qwen3.5:9b`
- 모든 스킬이 이 모델로 실행

### 확장 (API 모델 추가 시)
- `.env`에 API 키 등록 → `reload.sh` → 자동 반영
- 스킬별 모델 배치 가능 (AGENTS.md "## 모델 배치" 섹션)
- 지원: Anthropic, OpenAI, Google, Mistral, DeepSeek, Groq

### 모델 배치 한계
- OpenClaw는 스킬→모델 직접 라우팅을 openclaw.json에서 지원하지 않음
- AGENTS.md 텍스트 지침으로 관리 (에이전트의 자발적 준수에 의존)
- 완전 분리 필요 시 → agents.list로 에이전트를 여러 개 만들고 각 workspace에 스킬 배치

---

## 5. 워크스페이스 파일 구조

```
/root/.openclaw/workspace/
├── SOUL.md              ← 페르소나, 톤, 행동 원칙 (정보 탐색, 사실 보고, 자가 진단, 학습)
├── IDENTITY.md          ← 이름, 태그라인, 첫 대화/복원 동작
├── AGENTS.md            ← 운영 지침, 스킬 라우팅, 메모리 운영, 프로토콜
├── USER.md              ← 사용자 프로필 (온보딩에서 채워짐)
├── TOOLS.md             ← 경로, 도구, 웹 검색, 외부 provider 레퍼런스
├── HEARTBEAT.md         ← 주기적 체크리스트
├── BOOTSTRAP.md         ← 첫 실행 시스템 점검 (실행 후 자동 삭제)
├── MEMORY.md            ← 장기 기억 인덱스 (20,000자 이내)
├── memory/              ← 상세 기록 파일
└── skills/              ← 스킬 폴더
    ├── _template/SKILL_TEMPLATE.md  ← 스킬 작성 규칙
    ├── onboarding/
    ├── profile-editor/
    ├── rule-editor/
    ├── skill-creator/
    ├── skill-editor/
    ├── skill-toggle/
    ├── skill-delete/
    ├── memory-manager/
    ├── agent-router/
    ├── status-dashboard/
    └── (사용자 추가 스킬)/
```

---

## 6. 기본 탑재 스킬 (10개)

| 스킬 | 역할 | 주요 특징 |
|------|------|----------|
| onboarding | 첫 대화 5단계 온보딩 | BOOTSTRAP.md 점검 후 연계 |
| profile-editor | 호칭/톤/응답길이/출처표기 변경 | USER.md + SOUL.md 수정 |
| rule-editor | 행동/알림/주기적 체크 규칙 관리 | AGENTS.md + HEARTBEAT.md, 레드라인 충돌 검사 |
| skill-creator | 새 스킬 생성 | 간단(3단계)/상세(12단계) 자동 모드, 공식 문서 실시간 조회 |
| skill-editor | 기존 스킬 수정 | 모델 할당 변경 포함, SKILL_TEMPLATE.md 규칙 준수 확인 |
| skill-toggle | 스킬 on/off | 시스템 스킬 비활성화 경고 |
| skill-delete | 스킬 완전 삭제 | 2단계 확인, 시스템 스킬 보호, 배치/인덱스 정리 |
| memory-manager | 기억 저장/조회/삭제 | MEMORY.md 인덱스 + memory/ 분리, 용량 관리 |
| agent-router | 스킬별 모델 배치 | 모델 목록/배치 조회, 추천 배치 제안 |
| status-dashboard | 전체 현황 조회 | 4가지 뷰 (전체/세부/역할설명/모델별 현황) |

---

## 7. 초기 실행 플로우

```
컨테이너 시작
  → entrypoint.sh
    → .env 덤프
    → generate-config.sh (openclaw.json 생성, 웹 검색 DuckDuckGo 활성화)
    → workspace 초기화 (기본 파일 복사)
    → Ollama 시작 + 모델 다운로드
    → gateway 시작

첫 Telegram 메시지
  → BOOTSTRAP.md 존재 → 시스템 점검 (Ollama, 모델, 웹검색, Telegram, 저장소, 외부 모델)
  → 점검 결과 보고
  → 온보딩 시작 (프로필 수집 → 상태 안내 → 스킬 추가 제안)
```

---

## 8. 환경변수 & 설정 갱신 구조

```
컨테이너 최초 시작:
  gcube ENV → entrypoint.sh → .env 덤프 + generate-config.sh → openclaw.json

사용자가 나중에 설정 변경:
  .env 수정 → reload.sh → generate-config.sh → openclaw.json 재생성 + gateway 재시작
```

| 파일 | 역할 |
|------|------|
| generate-config.sh | .env → openclaw.json 생성 (웹 검색 설정 포함) |
| reload.sh | generate-config.sh 호출 + gateway 재시작 |
| .env | 환경변수 저장 (최초: gcube ENV 덤프, 이후: 사용자 수정) |

---

## 9. 향후 계획

### 단기
- 실제 배포 테스트 (Ollama tool calling + 웹 검색 동작 확인)
- workspace 백업/복원 연동 (backup-manager.sh 통합)

### 중기
- preset_image/ 디렉터리 추가 (사용자 니즈 기반 프리셋 스킬 탑재 이미지)
- 에이전트 자가 테스트 기능
- 스킬 버전 관리 + 롤백

### 장기
- 멀티 에이전트 실제 라우팅 (openclaw.json agents.list)
- ClawHub 스킬 설치 연동
- 복원 완료 시 Telegram 선제 알림
