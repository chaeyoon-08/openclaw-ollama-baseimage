# openclaw-base

OpenClaw + Ollama 기반 Telegram AI 비서 컨테이너 이미지.
gcube 워크로드에 배포 후 환경변수만 설정하면 즉시 사용 가능.

---

## 브랜치별 이미지

| 브랜치 | 이미지 | 설명 |
|---|---|---|
| `main` | `ghcr.io/chaeyoon-08/openclaw-bot:latest` | 기본 구성 — 로컬 LLM + 외부 모델 전환 |
| `multi-agent` | `ghcr.io/chaeyoon-08/openclaw-bot-multi:latest` | IPAI 멀티 에이전트 + 오케스트레이션 + NotebookLM MCP |

---

<!-- OPENCLAW_VERSION_START -->
## OpenClaw 버전 정보

> 이미지 빌드 시 자동 갱신됩니다.

| 항목 | 내용 |
|---|---|
| 설치 버전 | `2026.4.9` |
| 빌드 날짜 | 2026-04-10 |

버전별 변경사항: https://github.com/openclaw/openclaw/releases

<!-- OPENCLAW_VERSION_END -->

---

## 공통 사양

모든 브랜치 이미지에 공통으로 적용되는 베이스 사양입니다.

### 이미지 사양

| 항목 | 내용 |
|---|---|
| 베이스 | `nvidia/cuda:12.8.1-runtime-ubuntu22.04` |
| CUDA | 12.8.1 (Pascal ~ Blackwell 전 GPU 지원) |
| 최소 호스트 드라이버 | `>= 570.124.06` |
| OS | Ubuntu 22.04 LTS |
| 시간대 | Asia/Seoul (KST) |
| Node.js | 24 |
| OpenClaw | latest |
| Ollama | latest |

> **CUDA 12.8.1 선택 이유**: 12.8.1은 Maxwell(sm_50) ~ Blackwell(sm_120) 전 세대를 지원합니다.
> CUDA 13.x부터 Pascal(sm_60/61) 및 Volta(sm_70) 지원이 제거됩니다.

### 사전 설치 도구

`git` `curl` `wget` `nano` `vim` `python3` `pip` `npm` `jq` `build-essential`

### 이미지 태그

| 브랜치 | 이미지 태그 |
|---|---|
| `main` | `:latest`, `:YYYY.MM.DD`, `:sha-<7자>` |
| `multi-agent` | `:latest`, `:YYYY.MM.DD`, `:sha-<7자>` |

---

## 저장소 구조 (main 브랜치)

```
├── Dockerfile              베이스 이미지 정의 (CUDA + 도구 + Ollama + OpenClaw)
├── entrypoint.sh           컨테이너 시작 시 실행 — 환경변수 검증, Ollama 모델 다운로드, gateway 기동
├── generate-config.sh      환경변수를 읽어 openclaw.json 생성
├── reload.sh               실행 중인 컨테이너에서 설정 변경 후 gateway만 재시작할 때 사용
├── pve/
│   ├── docker-compose.yml  PVE / 독립 Docker 호스트 배포용
│   └── README.md           PVE 배포 가이드
└── .github/
    ├── workflows/
    │   └── docker-publish.yml  브랜치 push 시 이미지 자동 빌드 및 ghcr.io push
    └── scripts/
        └── update_readme.py    빌드 시 README OpenClaw 버전 정보 자동 갱신
```

---

## openclaw-bot

> 브랜치: `main` | 이미지: `ghcr.io/chaeyoon-08/openclaw-bot:latest`

OpenClaw 기본 기능만 사용하는 최소 구성입니다. 추가 설정 없이 바로 Telegram 봇으로 사용할 수 있습니다.

### 기능

- **Telegram 인터페이스**: 지정된 User ID만 허용하는 allowlist 방식
- **로컬 LLM 추론**: Ollama를 통해 GPU에서 직접 모델 추론 — 외부 API 비용 없음
- **외부 AI 모델 전환**: API key 환경변수 설정 시 자동 등록 → `/model`로 전환하여 사용
- **웹 검색**: DuckDuckGo 기반 웹 검색 기본 활성화 (API 키 불필요)
- **자동 초기 설정**: 컨테이너 시작 시 환경변수만으로 전체 설정 자동 완료
- **GitHub 연동**: 지정 repo를 `/workspace`에 자동 클론, git 인증 자동 구성
- **gateway 자동 재시작**: 비정상 종료 시 자동 재기동 (컨테이너 종료 없음)
- **Control UI**: 웹 브라우저에서 OpenClaw 관리 화면 접근 — 토큰 입력 후 바로 연결

### 구성

```
컨테이너 내부
├── Ollama (127.0.0.1:11434)           ← 로컬 LLM 추론 서버
└── OpenClaw gateway (0.0.0.0:18789)
        ↕ Telegram Bot API (long-polling)
        Telegram 사용자
```

- 외부 AI provider는 API key 환경변수 설정만으로 자동 등록 — 설정 파일을 직접 수정할 필요 없음

### 환경변수

**필수**

| 변수 | 예시 | 설명 |
|---|---|---|
| `TELEGRAM_BOT_TOKEN` | `123456:ABC-DEF...` | [@BotFather](https://t.me/BotFather) 에서 발급한 봇 토큰 |
| `TELEGRAM_ALLOWED_USER_IDS` | `123456789` | 봇 사용을 허용할 Telegram 수치형 User ID. 쉼표로 여러 명 가능 (`123,456`) |
| `OLLAMA_MODEL` | `qwen3.5:9b` | 기본으로 사용할 Ollama 모델. **반드시 태그 포함** (예: `:9b`, `:35b`) |
| `OPENCLAW_GATEWAY_TOKEN` | `my-token-1234` | Control UI 및 gateway 연결 토큰. **재시작 후에도 동일한 값으로 고정 필요** — 변경 시 Telegram 연동이 끊길 수 있음 |

> Ollama 모델 태그 확인: https://ollama.com/library

**선택 — 외부 AI provider**

| 변수 | 설명 |
|---|---|
| `ANTHROPIC_API_KEY` | Anthropic Claude 모델 사용 시 설정. 설정 시 `/model`에서 anthropic provider 선택 가능 |
| `OPENAI_API_KEY` | OpenAI GPT 모델 사용 시 설정 |
| `GEMINI_API_KEY` | Google Gemini 모델 사용 시 설정 |
| `MISTRAL_API_KEY` | Mistral 모델 사용 시 설정 |
| `DEEPSEEK_API_KEY` | DeepSeek 모델 사용 시 설정 |
| `GROQ_API_KEY` | Groq 모델 사용 시 설정 |

> **주의**: `/model` 목록에는 OpenClaw 내장 카탈로그의 모든 provider가 표시되지만, 실제로 사용 가능한 것은 **API key를 환경변수로 설정한 provider만**입니다. API key가 없는 provider를 선택하면 기본 Ollama 모델로 자동 폴백됩니다.

**선택 — GitHub 연동**

| 변수 | 설명 |
|---|---|
| `GITHUB_USERNAME` | git config user.name. `GITHUB_EMAIL`과 함께 설정해야 GitHub 연동 활성화 |
| `GITHUB_EMAIL` | git config user.email |
| `GITHUB_TOKEN` | GitHub Personal Access Token. private repo 접근 또는 git push 시 필요 |
| `GITHUB_REPO_URL` | 컨테이너 시작 시 `/workspace`에 자동 클론할 repo URL |

---

## openclaw-bot-multi

> 브랜치: `multi-agent` | 이미지: `ghcr.io/chaeyoon-08/openclaw-bot-multi:latest`

멀티 에이전트 오케스트레이션과 NotebookLM MCP를 갖춘 고급 구성입니다.

### 기능

- **동적 모델 선택**: `ORCHESTRATOR_MODEL` 환경변수 하나로 무료(Ollama) / 유료(Claude, GPT 등) 런타임 전환
- **멀티 에이전트 오케스트레이션**: 메인 에이전트가 `sessions_spawn`으로 서브 에이전트 생성 (depth=1)
- **NotebookLM MCP 연동**: 할루시네이션 방지를 위한 문서 기반 지식 검색 — 비공식 API 기반
- **영구 기억 시스템**: `MEMORY.md` / `SOUL.md` / `AGENTS.md`를 통한 세션 간 기억 유지
- **Telegram 인터페이스**: 지정된 User ID만 허용하는 allowlist 방식
- **자동 초기 설정**: 컨테이너 시작 시 환경변수만으로 전체 설정 자동 완료
- **GitHub 연동**: 지정 repo를 `/workspace`에 자동 클론, git 인증 자동 구성
- **gateway 자동 재시작**: 비정상 종료 시 자동 재기동 (컨테이너 종료 없음)

### 구성

```
gcube 워크로드 (GPU 컨테이너)
├── Ollama (127.0.0.1:11434)       ← ollama/ 모델 사용 시에만 시작
└── OpenClaw gateway (0.0.0.0:18789)
        ↕ Telegram Bot API
        Telegram 사용자
        ├── Main Agent (오케스트레이터)
        │       ↓ sessions_spawn (depth=1)
        ├── Worker Agent 1 (병렬 실행)
        └── Worker Agent 2 (병렬 실행)

MCP 서버:
  ├── NotebookLM — 지식 검색 및 리서치 (비공식 API)
  └── Filesystem  — /workspace 파일 접근
```

### 환경변수

**필수**

| 변수 | 예시 | 설명 |
|---|---|---|
| `TELEGRAM_BOT_TOKEN` | `123456:ABC-DEF...` | [@BotFather](https://t.me/BotFather)에서 발급한 봇 토큰 |
| `TELEGRAM_ALLOWED_USER_IDS` | `123456789` | 허용할 Telegram user ID. 쉼표로 여러 명 가능 |
| `ORCHESTRATOR_MODEL` | `ollama/qwen3:14b` | 오케스트레이터 모델. `provider/model[:tag]` 형식 필수 |
| `OPENCLAW_GATEWAY_TOKEN` | `my-token-1234` | Control UI 토큰. **재시작 후에도 동일한 값으로 고정 필요** |

**ORCHESTRATOR_MODEL 형식**

| 형식 | 예시 | 설명 |
|---|---|---|
| `ollama/<model>:<tag>` | `ollama/qwen3:14b` | 무료 — 컨테이너 내 Ollama 사용. **태그 필수** |
| `anthropic/<model>` | `anthropic/claude-sonnet-4-6` | 유료 — Anthropic Claude |
| `openai/<model>` | `openai/gpt-4o` | 유료 — OpenAI GPT |
| `google/<model>` | `google/gemini-2.0-flash` | 유료 — Google Gemini |

> 유료 provider 사용 시 `WORKER_MODEL=ollama/<model>:<tag>` 설정 필수 — 미설정 시 컨테이너 기동 중단 (요금 방어)

**선택**

| 변수 | 예시 | 설명 |
|---|---|---|
| `WORKER_MODEL` | `ollama/qwen3:4b` | 서브 에이전트 모델. 미설정 시 `ORCHESTRATOR_MODEL` 상속 |
| `MODEL_API_KEY` | `anthropic/sk-ant-xxx` | 유료 provider API 키. 쉼표로 여러 provider 동시 등록 가능 |
| `NOTEBOOKLM_MCP_CLI_PATH` | `/mnt/notebooklm` | NotebookLM 인증 파일 디렉터리. Dropbox 볼륨 마운트 경로와 일치시킬 것 |
| `GITHUB_USERNAME` | `myname` | git config user.name |
| `GITHUB_EMAIL` | `me@example.com` | git config user.email |
| `GITHUB_TOKEN` | `ghp_xxx` | GitHub Personal Access Token |
| `GITHUB_REPO_URL` | `https://github.com/...` | 시작 시 `/workspace`에 자동 클론할 repo |

### 볼륨

| 마운트 | 용도 |
|---|---|
| `ollama-models:/root/.ollama` | Ollama 모델 캐시 (재시작 시 재다운로드 방지) |
| Dropbox `OpenClaw_Data` → `/home/node/.openclaw` | 에이전트 기억·설정·세션 영구 보존 |
| Dropbox `OpenClaw_Auth` → `/mnt/notebooklm` | NotebookLM 인증 파일. `NOTEBOOKLM_MCP_CLI_PATH=/mnt/notebooklm` 환경변수와 함께 설정 |

### NotebookLM 사전 인증

gcube는 브라우저가 없는 헤드리스 환경이므로 로컬 PC에서 인증 파일을 생성한 뒤 Dropbox를 통해 컨테이너에 마운트합니다.

```bash
# 1. notebooklm-mcp-cli 설치 (Google Chrome 필수)
uv tool install notebooklm-mcp-cli

# 2. Google 계정 로그인 (Chrome이 자동으로 열립니다)
nlm login

# 3. 생성된 profiles/default/ 폴더를 Dropbox OpenClaw_Auth/ 에 업로드
# Linux/Mac: ~/.notebooklm-mcp-cli/profiles/default/
# Windows:   %USERPROFILE%\.notebooklm-mcp-cli\profiles\default\
```

> Windows WSL 사용자는 반드시 PowerShell에서 실행하세요 (WSL에서는 브라우저를 열 수 없습니다).
