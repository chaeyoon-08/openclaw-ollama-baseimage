# TOOLS.md -- 도구/경로/시스템 레퍼런스

---

## 파일 시스템 경로

| 항목 | 절대 경로 | 설명 |
|------|----------|------|
| workspace 루트 | `/root/.openclaw/workspace` | 모든 에이전트 설정 파일의 루트 |
| 설정 파일 | `/root/.openclaw/openclaw.json` | OpenClaw gateway 설정. 직접 수정 금지, .env + reload.sh로 관리 |
| 환경변수 파일 | `/root/.openclaw/.env` | 모든 환경변수 저장. 수정 후 reload.sh 실행 필요 |
| 스킬 폴더 | `/root/.openclaw/workspace/skills/` | 각 스킬은 독립 폴더 + SKILL.md로 구성 |
| 스킬 템플릿 | `/root/.openclaw/workspace/skills/_template/SKILL_TEMPLATE.md` | SKILL.md 작성 규칙. skill-creator, skill-editor 참조 |
| 메모리 폴더 | `/root/.openclaw/workspace/memory/` | 상세 기록 파일 저장 위치 |
| 클라우드 저장소 | `$STORAGE_PATH` (기본: `/mnt/storage`) | gcube 클라우드 저장소 마운트 경로 |
| 백업 | `$STORAGE_PATH/backups/` | manual/ (수동), temp/ (자동) |

---

## 설정 갱신 절차

```
환경변수 추가/수정이 필요할 때:

Step 1: .env 파일 수정
  경로: /root/.openclaw/.env
  방법: nano /root/.openclaw/.env (또는 vi, cat >> 등)

Step 2: reload.sh 실행
  명령: bash /usr/local/bin/reload.sh
  동작:
    1. .env 파일 로드
    2. openclaw.json 재생성 (generate-config.sh 호출)
    3. gateway 프로세스 종료 (entrypoint.sh가 자동 재시작)

주의:
  - gateway 재시작 시 현재 세션이 초기화됨
  - 재시작 전 진행 중 작업 있으면 반드시 MEMORY.md + memory/ 에 기록
  - openclaw.json을 직접 수정하면 다음 reload.sh 실행 시 덮어쓰기됨
```

---

## 파일 글자수 제한

> OpenClaw 부트스트랩 제한: 파일당 20,000자, 전체 합산 150,000자.
> 아래는 각 파일의 운영 상한선. 상한선의 75%에 도달하면 정리가 필요하다.

| 파일 | 상한 | 비고 |
|------|------|------|
| SOUL.md | 15,000자 | 원칙 추가 시 기존 내용 압축 검토 |
| AGENTS.md | 15,000자 | 사용자 규칙/모델 배치 증가에 대비 |
| USER.md | 5,000자 | 프로필 + 개인 규칙 |
| TOOLS.md | 5,000자 | 레퍼런스 정보 |
| IDENTITY.md | 3,000자 | 아이덴티티 정보 |
| HEARTBEAT.md | 10,000자 | 사용자 추가 체크 항목 증가에 대비 |
| MEMORY.md | 20,000자 | 초과 시 memory/archive.md로 이동 |
| BOOTSTRAP.md | 5,000자 | 첫 실행 후 자동 삭제 |
| 각 SKILL.md | 15,000자 | 초과 시 보충 파일로 분리 |
| **전체 합산 목표** | **100,000자 이내** | 사용자 스킬 증가 여유분 50,000자 확보 |

```
글자수 확인 방법 (터미널):
  wc -m /root/.openclaw/workspace/파일명.md

75% 경고 기준:
  - SOUL.md: 11,250자 이상이면 정리 필요
  - AGENTS.md: 11,250자 이상이면 정리 필요
  - MEMORY.md: 15,000자 이상이면 아카이브
  - 각 SKILL.md: 11,250자 이상이면 보충 파일 분리
```

---

## 스킬 파일 구조

```
skills/스킬명/
├── SKILL.md           ← 필수: 에이전트 지침 (frontmatter + 본문)
└── (보충 파일)         ← 선택: 스크립트(.py, .sh), 설정(.json), README.md 등

작성 규칙: skills/_template/SKILL_TEMPLATE.md 참조
활성/비활성: SKILL.md frontmatter의 disable-model-invocation 필드
반영 시점: 스킬 변경은 새 세션에서 반영됨
```

---

## 웹 검색

```
기본 설정 (openclaw.json):
  tools.web.search.enabled: true
  tools.web.search.provider: "duckduckgo"
  tools.web.search.maxResults: 5

DuckDuckGo: API 키 불필요, 무료. 기본 프로바이더.
  주의: 비공식 — CAPTCHA/HTML 변경에 취약할 수 있음

유료 프로바이더로 변경 시:
  .env에 해당 API 키 추가 → reload.sh 실행
  지원: BRAVE_API_KEY, TAVILY_API_KEY 등
  openclaw.json tools.web.search.provider 값도 변경 필요
```

---

## 등록 가능한 외부 AI provider

| provider | .env 변수명 | 등록 후 모델 참조 형식 |
|----------|------------|----------------------|
| Anthropic (Claude) | `ANTHROPIC_API_KEY` | `anthropic/모델명` |
| OpenAI (GPT) | `OPENAI_API_KEY` | `openai/모델명` |
| Google (Gemini) | `GEMINI_API_KEY` | `google/모델명` |
| Mistral | `MISTRAL_API_KEY` | `mistral/모델명` |
| DeepSeek | `DEEPSEEK_API_KEY` | `deepseek/모델명` |
| Groq | `GROQ_API_KEY` | `groq/모델명` |

등록 절차: .env에 API 키 추가 → reload.sh 실행 → openclaw.json providers에 자동 반영
