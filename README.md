# gcube-openclaw

OpenClaw 기반 멀티 에이전트 오케스트레이션 컨테이너 이미지. 로컬 모델(Ollama)과 외부 API 모델(Claude 등)을 작업 특성에 따라 자동 분업하는 하이브리드 구조입니다.

## 패키지 스펙

| 항목 | 버전 |
|------|------|
| Base Image | `nvidia/cuda:12.8.1-runtime-ubuntu22.04` |
| OS | Ubuntu 22.04 |
| CUDA | 12.8.1 |
| Node.js | 24.x (NodeSource) |
| OpenClaw | 2026.4.15 |
| Ollama | latest |
| Timezone | Asia/Seoul |

## 지원 모델

오케스트레이터와 서브 에이전트 모두 **로컬 모델**과 **외부 API 모델**을 자유롭게 조합할 수 있습니다.

### 로컬 모델 (Ollama)

Ollama Library에 등록된 모든 모델 사용 가능. 컨테이너 시작 시 `ORCHESTRATOR_MODEL`/`WORKER_MODELS`에 지정된 모델이 자동 pull됩니다.

| 모델 | 비고 | 컨텍스트 |
|------|------|---------|
| `glm-4.7-flash:q4_K_M` | 오케스트레이터로 사용 | 64K |
| `gemma4:26b` | 큰 컨텍스트 모델 | 64K |
| `qwen3:14b` | 서브 에이전트 기본값 | 32K |

### 외부 API 모델

`MODEL_API_KEY` 환경변수로 키를 등록하면 사용 가능. 호출 시 `provider/model-name` 형식 (예: `anthropic/claude-sonnet-4-5`).

| Provider | API 종류 | 비고 |
|---------|---------|------|
| `anthropic` | Claude API | 외부 URL 조사·검색에 활용 |
| `openai` | OpenAI Responses API | GPT 계열 |
| `google` | Google Generative AI | Gemini 계열 |
| `mistral` | OpenAI 호환 | Mistral 계열 |
| `deepseek` | OpenAI 호환 | DeepSeek 계열 |
| `groq` | OpenAI 호환 | 고속 추론 |

> 외부 API 모델은 호출 시 비용이 발생합니다. `templates/AGENTS.md`의 컨펌 게이트 규칙에 따라 사용자 승인 후 호출됩니다.

### 사용 예시

권장 조합 예시. 호환되는 모델 조합은 자유롭게 구성 가능합니다.

| 시나리오 | 오케 | 서브 |
|---------|------|------|
| 로컬 only (비용 없음) | `ollama/glm-4.7-flash:q4_K_M` | `ollama/qwen3:14b`, `ollama/gemma4:26b` |
| 하이브리드 | `ollama/glm-4.7-flash:q4_K_M` | `ollama/qwen3:14b`, `anthropic/claude-sonnet-4-5` |

> 위 두 조합은 RTX 5090 환경에서 테스트했습니다. 다른 provider(openai, google 등)는 OpenClaw가 표준적으로 지원하지만 본 이미지에서 별도 검증을 거치지 않았습니다.

## 포트

| 포트 | 용도 |
|------|------|
| `18789` | OpenClaw Gateway (Control UI · 외부 노출) |
| `11434` | Ollama API (내부 전용) |

## 프로젝트 구조

```
.
├── .github/
│   └── workflows/
│       └── docker-publish.yml      # ghcr.io 자동 빌드/push 워크플로우
├── templates/
│   ├── AGENTS.md                   # 오케 에이전트 행동 규칙 템플릿
│   ├── SOUL.md                     # 정체성 템플릿
│   ├── MEMORY.md                   # 영구 기억 템플릿
│   └── skills/                     # 사용자 정의 skill 디렉토리
├── Dockerfile                      # CUDA + Ollama + OpenClaw 이미지
├── entrypoint.sh                   # 컨테이너 자동 설정·기동
├── generate-config.sh              # 환경변수 → openclaw.json 생성
├── reload.sh                       # 설정 갱신 + gateway in-process reload
├── restart.sh                      # gateway full restart (모델 추가 시)
├── .env.example                    # 환경변수 템플릿
└── README.md
```

## 환경변수

워크로드 배포 시 사용자가 지정하는 변수만 정리되어 있습니다. 이미지 내부 고정값(`OLLAMA_*`, `DEFAULT_CONTEXT_WINDOW` 등)은 `Dockerfile` 참조.

### 필수

| 변수 | 설명 |
|------|------|
| `ORCHESTRATOR_MODEL` | 오케스트레이터 모델. `provider/model-name` 형식 (예: `ollama/glm-4.7-flash:q4_K_M`, `anthropic/claude-sonnet-4-5`) |
| `TELEGRAM_BOT_TOKEN` | BotFather에서 발급받은 Telegram Bot Token |
| `TELEGRAM_ALLOWED_USER_IDS` | 접속 허용할 Telegram User ID. 여러 개일 경우 공백 구분 |

### 선택

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `WORKER_MODELS` | (없음) | 서브 에이전트가 사용할 모델 목록. 공백 구분 (예: `ollama/qwen3:14b ollama/gemma4:26b anthropic/claude-sonnet-4-5`) |
| `MODEL_API_KEY` | (없음) | 외부 provider API 키. `provider/key` 형식 (예: `anthropic/sk-ant-...`). 여러 provider일 경우 공백 구분. `ORCHESTRATOR_MODEL`이 ollama가 아니면 필수 |
| `OPENCLAW_GATEWAY_TOKEN` | 자동 생성 | Gateway 인증 토큰. 미설정 시 32-char base64로 자동 생성. 재배포 시 좀비 상태 방지를 위해 고정값 권장 |

### Git 연동 (선택)

워크스페이스를 git repo로 관리할 때만 사용.

| 변수 | 설명 |
|------|------|
| `GITHUB_USERNAME` | git 사용자 이름 |
| `GITHUB_EMAIL` | git 사용자 이메일 |
| `GITHUB_TOKEN` | Personal Access Token (private repo 접근용) |
| `GITHUB_REPO_URL` | 컨테이너 시작 시 `/workspace`로 clone할 repo URL |

## 시작 흐름

```
컨테이너 시작
  │
  ├─ 1. .env 로드 (있는 경우)
  │
  ├─ 2. 필수 환경변수 검증
  │     · ORCHESTRATOR_MODEL, TELEGRAM_BOT_TOKEN, TELEGRAM_ALLOWED_USER_IDS
  │
  ├─ 3. Git 설정 (선택)
  │     · GITHUB_* 변수가 있으면 git config + credential 등록
  │     · GITHUB_REPO_URL이 있으면 /workspace로 clone
  │
  ├─ 4. Ollama 기동
  │     · ollama serve (background)
  │     · /api/tags 응답 대기
  │
  ├─ 5. 모델 pull
  │     · ORCHESTRATOR_MODEL (ollama provider인 경우)
  │     · WORKER_MODELS (ollama 항목만)
  │     · 각 모델에 num_ctx Modelfile 적용
  │
  ├─ 6. workspace 템플릿 복사
  │     · /home/node/.openclaw/workspace/ 초기화
  │     · AGENTS.md, SOUL.md, MEMORY.md (없을 때만)
  │     · results/ 폴더 자동 생성
  │
  ├─ 7. openclaw.json 생성 (generate-config.sh)
  │     · Telegram 채널 설정
  │     · Ollama 모델 등록 + contextWindow 주입
  │     · 외부 provider 등록
  │     · Subagent 기본 모델 지정
  │
  └─ 8. OpenClaw Gateway 실행
        · in-process 재시작 모드 (OPENCLAW_NO_RESPAWN=1)
        · Telegram channel 활성화
```

## 핵심 동작

### 모델 라우팅

오케스트레이터는 `templates/AGENTS.md`에 정의된 라우팅 정책에 따라 작업 특성별로 적절한 모델을 선택해 서브 에이전트로 위임합니다.

| 작업 특성 | 라우팅 정책 |
|-----------|---------|
| 외부 URL 조사·파싱, 시점 키워드 검색, 팩트 검증 | Claude API |
| 로컬 파일 읽기, 포맷 변환, 단순 질의응답 | Ollama 모델 |
| 큰 컨텍스트가 필요한 작업 | gemma4 등 |

Claude API 호출 시에는 사용자 컨펌 게이트가 발동하여 비용을 명시적으로 통제합니다.

### 결과 전달

| 결과 크기 | 처리 방식 |
|-----------|-----------|
| 3000자 미만 | Telegram에 직접 전달 |
| 3000자 이상 / 표·코드 포함 | `workspace/results/` 폴더에 파일 저장, Telegram에는 위치와 개요만 |

상세 규칙은 `templates/AGENTS.md` 참조.

## 빌드 & 배포

GitHub Actions(`.github/workflows/docker-publish.yml`)가 `multi-agent` 브랜치 push 시 자동으로 ghcr.io에 이미지를 빌드·push합니다.

```
브랜치          → 이미지 태그
multi-agent    → ghcr.io/data-alliance/openclaw-bot-multi:latest
                ghcr.io/data-alliance/openclaw-bot-multi:sha-<7자>
```

## VRAM 가이드

RTX 5090 32GB 기준 실측치:

| 모델 조합 | VRAM 사용량 |
|-----------|-------------|
| GLM-4.7-Flash (오케) 단독 | ~21.6 GB (64K context 기준) |
| Gemma4:26b 단독 | ~20.7 GB |
| Qwen3:14b 단독 | ~11.9 GB |

**동시 로드 (`OLLAMA_MAX_LOADED_MODELS=2`)**:
- GLM-4.7-Flash + Qwen3:14b 조합은 32GB GPU에서 경계선에 가까워 swap 발생 가능. 한 모델만 운영하거나 더 큰 GPU 권장.
- GLM-4.7-Flash + Gemma4:26b는 32GB에 들어가지 않음.

`OLLAMA_KV_CACHE_TYPE=q8_0`으로 KV 캐시 8-bit 양자화 적용 (이미지 내부 기본값).

> 외부 API 모델(Claude, GPT 등)은 외부 서버에서 추론하므로 VRAM을 사용하지 않습니다. 하이브리드 구성 시 로컬 GPU 자원을 오케 또는 큰 컨텍스트 작업에 집중 배분 가능.

## 관련 문서

- `templates/AGENTS.md` — 오케 에이전트 행동 규칙 (모델 라우팅, 결과 전달, 컨펌 게이트 등 상세)
- `TUTORIAL.md` — gcube 환경 활용 가이드 (작성 예정)
- `.env.example` — 환경변수 설정 예시

## 버전 히스토리

| 태그 | 내용 |
|------|------|
| `latest` | 멀티 에이전트 오케스트레이션 초판 — Ollama + OpenClaw 2026.4.15, AGENTS.md v5 (결과 전달 규칙 포함), contextWindow 자동 주입 |