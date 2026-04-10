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

`git` `curl` `wget` `nano` `vim` `python3` `pip` `npm` `jq` `build-essential` `gosu` `uv`

### 이미지 태그

| 브랜치 | 이미지 태그 |
|---|---|
| `main` | `:latest`, `:YYYY.MM.DD`, `:sha-<7자>` |
| `multi-agent` | `:latest`, `:YYYY.MM.DD`, `:sha-<7자>` |

---

## 저장소 구조 (multi-agent 브랜치)

```
├── Dockerfile              베이스 이미지 (CUDA + 도구 + Ollama + OpenClaw + gosu + uv + notebooklm-mcp-cli)
├── entrypoint.sh           환경변수 검증, 요금 폭탄 방어, Ollama 조건부 기동, sentinel 초기화, gateway 시작
├── generate-config.sh      환경변수를 읽어 openclaw.json 생성 (멀티 에이전트·MCP·modelTiers 포함)
├── reload.sh               실행 중인 컨테이너에서 설정 변경 후 gateway만 재시작할 때 사용
├── templates/              컨테이너 최초 실행 시 workspace에 복사되는 에이전트 템플릿
│   ├── AGENTS.md           에이전트 운영 지침 (오케스트레이션, cron tier:local 라우팅)
│   ├── SOUL.md             에이전트 페르소나·가치관 정의
│   ├── TOOLS.md            사용 가능한 도구 목록
│   └── MEMORY.md           영구 기억 저장소 초기 파일 (sentinel 역할)
└── .github/
    ├── workflows/
    │   └── docker-publish.yml  브랜치 push 시 이미지 자동 빌드 및 ghcr.io push
    └── scripts/
        └── update_readme.py    빌드 시 README OpenClaw 버전 정보 자동 갱신
```

---

## openclaw-bot-multi

> 브랜치: `multi-agent` | 이미지: `ghcr.io/chaeyoon-08/openclaw-bot-multi:latest`

### 주요 기능

- **동적 모델 선택**: `ORCHESTRATOR_MODEL` 환경변수 하나로 무료(Ollama) / 유료(Claude, GPT 등) 런타임 전환
- **멀티 에이전트 오케스트레이션**: 메인 에이전트가 `sessions_spawn`으로 서브 에이전트 생성 (depth=1)
- **NotebookLM MCP 연동**: 할루시네이션 방지를 위한 문서 기반 지식 검색 — 비공식 API 기반([주의사항 참고](#notebooklm-연동-disclaimer))
- **영구 기억 시스템**: `MEMORY.md` / `SOUL.md` / `AGENTS.md`를 통한 세션 간 기억 유지
- **자율 스킬 확장**: 에이전트가 `openclaw plugins install`로 스스로 도구 설치
- **Telegram 인터페이스**: 지정된 User ID만 허용하는 allowlist 방식
- **자동 초기 설정**: 컨테이너 시작 시 환경변수만으로 전체 설정 자동 완료
- **GitHub 연동**: 지정 repo를 `/workspace`에 자동 클론, git 인증 자동 구성
- **gateway 자동 재시작**: 비정상 종료 시 자동 재기동 (컨테이너 종료 없음)

### 시스템 구조

```
gcube 워크로드 (GPU 컨테이너)
│
├── Ollama (127.0.0.1:11434)       ← ollama/ 모델 사용 시에만 시작
│
└── OpenClaw gateway (0.0.0.0:18789)
        ↕ Telegram Bot API
        Telegram 사용자
        │
        ├── Main Agent (오케스트레이터)
        │       ↓ sessions_spawn (depth=1)
        ├── Worker Agent 1 (병렬 실행)
        └── Worker Agent 2 (병렬 실행)

MCP 서버:
  ├── NotebookLM — 지식 검색 및 리서치 (비공식 API)
  └── Filesystem  — /workspace 파일 접근
```

---

## 배포 전 필수 준비: NotebookLM 사전 인증

> **이 단계를 건너뛰면 NotebookLM MCP 기능을 사용할 수 없습니다.**

NotebookLM MCP는 Google 계정 인증이 필요합니다. gcube는 브라우저가 없는 헤드리스 환경이므로,
**로컬 PC에서 인증 파일을 생성하고 Dropbox를 통해 컨테이너에 마운트하는 방식**을 사용합니다.

### [Step 1] 로컬 PC에서 인증 파일 생성

```bash
# 1. notebooklm-mcp-cli 설치
uv tool install notebooklm-mcp-cli
# 또는: pip install notebooklm-mcp-cli

# 2. Google 계정 로그인 (브라우저가 열립니다)
nlm login

# 3. 인증 파일 확인
# Linux/Mac: ~/.notebooklm-mcp-cli/profiles/default/
# Windows:   %USERPROFILE%\.notebooklm-mcp-cli\profiles\default\
```

### [Step 2] Dropbox 폴더 준비

Dropbox 최상위 경로에 **아래 두 폴더를 모두 생성**합니다. 각 폴더는 역할이 다르므로 반드시 구분해야 합니다.

| 폴더명 | 용도 | 비고 |
|---|---|---|
| `OpenClaw_Auth` | NotebookLM Google 인증 파일 보관 | `profiles/default/` 폴더 통째로 업로드 |
| `OpenClaw_Data` | 에이전트 상태 데이터 전체 보관 | 비워두면 됨 (컨테이너가 자동 초기화) |

`nlm login` 후 생성된 `profiles/default/` 폴더(하위 `cookies.json`, `metadata.json` 포함)를 `OpenClaw_Auth/` 폴더에 업로드합니다. `OpenClaw_Data/`는 지금은 비워둡니다.

### [Step 3] gcube 워크로드 배포 시 설정

gcube 대시보드에서 워크로드 배포 시 **아래 3가지를 반드시 모두 설정해야 합니다.**
하나라도 빠지면 에이전트 기억이 유실되거나 NotebookLM이 동작하지 않습니다.

| # | 설정 항목 | Dropbox 폴더 | 컨테이너 경로 | 역할 |
|---|---|---|---|---|
| ① | 볼륨 마운트 | `OpenClaw_Data` | `/home/node/.openclaw` | 에이전트 기억·설정·세션 영구 보존 |
| ② | 볼륨 마운트 | `OpenClaw_Auth` | `/mnt/notebooklm` | NotebookLM Google 인증 파일 |
| ③ | 환경변수 | — | `NOTEBOOKLM_MCP_CLI_PATH=/mnt/notebooklm` | NotebookLM 경로 지정 |

### 인증 만료 시 재인증

쿠키가 만료되면 Dropbox 파일만 교체하면 됩니다. 워크로드 재배포 불필요.

```bash
nlm login
# 생성된 profiles/default/ 폴더를 Dropbox OpenClaw_Auth/ 폴더에 덮어쓰기
# 그 후 gcube 워크로드 재시작
```

---

> ### NotebookLM 연동 Disclaimer
>
> **이 기능은 Google의 공식 API가 아닙니다.**
>
> NotebookLM MCP(`notebooklm-mcp-cli`)는 브라우저 쿠키를 추출하여 Google NotebookLM의
> **비공식(내부) API**를 호출하는 커뮤니티 구현체입니다.
>
> 이에 따라 다음과 같은 위험이 존재합니다:
> - Google이 내부 API 구조를 변경하면 **예고 없이 작동이 중단**될 수 있습니다
> - 쿠키(인증 토큰)가 만료되면 재인증이 필요합니다
> - Google의 이용 약관 변경에 따라 비공식 API 접근이 차단될 수 있습니다
>
> 중단 시에는 웹 검색(`web_search`) 도구로 대체 가능합니다.

---

## 환경변수

### 필수

| 변수 | 예시 | 설명 |
|---|---|---|
| `TELEGRAM_BOT_TOKEN` | `123456:ABC-DEF...` | [@BotFather](https://t.me/BotFather)에서 발급한 봇 토큰 |
| `TELEGRAM_ALLOWED_USER_IDS` | `123456789` | 허용할 Telegram user ID. 쉼표로 여러 명 가능 |
| `ORCHESTRATOR_MODEL` | `ollama/qwen3:14b` | 오케스트레이터 모델. provider 포함 필수 (아래 표 참고) |
| `OPENCLAW_GATEWAY_TOKEN` | `my-token-1234` | Control UI 토큰. **재시작 후에도 동일한 값으로 고정 필요** |

**ORCHESTRATOR_MODEL 형식**

| 형식 | 예시 | 설명 |
|---|---|---|
| `ollama/<model>:<tag>` | `ollama/qwen3:14b` | 무료 — 컨테이너 내 Ollama 사용. **태그 필수** |
| `anthropic/<model>` | `anthropic/claude-sonnet-4-6` | 유료 — Anthropic Claude |
| `openai/<model>` | `openai/gpt-4o` | 유료 — OpenAI GPT |
| `google/<model>` | `google/gemini-2.0-flash` | 유료 — Google Gemini |
| `mistral/<model>` | `mistral/mistral-large-latest` | 유료 — Mistral |

> Ollama 모델 및 태그 확인: https://ollama.com/library

### 선택

| 변수 | 예시 | 설명 |
|---|---|---|
| `WORKER_MODEL` | `ollama/qwen3:4b` | 서브 에이전트 모델. 미설정 시 `ORCHESTRATOR_MODEL` 상속 |
| `MODEL_API_KEY` | `anthropic/sk-ant-xxx` | 유료 provider API 키. 쉼표로 여러 provider 동시 등록 가능 |
| `NOTEBOOKLM_MCP_CLI_PATH` | `/mnt/notebooklm` | NotebookLM 인증 파일 디렉터리. Dropbox 볼륨 마운트 경로와 일치시킬 것 |
| `GITHUB_USERNAME` | `myname` | git config user.name |
| `GITHUB_EMAIL` | `me@example.com` | git config user.email |
| `GITHUB_TOKEN` | `ghp_xxx` | GitHub Personal Access Token |
| `GITHUB_REPO_URL` | `https://github.com/...` | 시작 시 `/workspace`에 자동 클론할 repo |

**MODEL_API_KEY 형식 예시**

```bash
# 단일 provider
MODEL_API_KEY=anthropic/sk-ant-xxxxxxxx

# 여러 provider 동시 등록 (쉼표 구분)
MODEL_API_KEY=anthropic/sk-ant-xxx,openai/sk-xxx
```

### 볼륨

| 마운트 | 용도 |
|---|---|
| `ollama-models:/root/.ollama` | Ollama 모델 캐시 (재시작 시 재다운로드 방지) |
| Dropbox `OpenClaw_Data` → `/home/node/.openclaw` | 에이전트 기억·설정·세션 영구 보존. **재시작 후에도 MEMORY.md, SOUL.md 유지** |
| Dropbox `OpenClaw_Auth` → `/mnt/notebooklm` | NotebookLM 인증 파일. `NOTEBOOKLM_MCP_CLI_PATH=/mnt/notebooklm` 환경변수와 함께 설정 |

---

## 참고 링크

- [OpenClaw 공식 문서](https://docs.openclaw.ai/)
- [Ollama 모델 라이브러리](https://ollama.com/library)
- [notebooklm-mcp-cli GitHub](https://github.com/jacob-bd/notebooklm-mcp-cli)
- [OpenClaw 멀티 에이전트 가이드](https://docs.openclaw.ai/tools/subagents)
