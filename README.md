# openclaw-base

OpenClaw + Ollama 기반 Telegram AI 비서 컨테이너 이미지.
gcube 워크로드에 배포하여 환경변수만 설정하면 즉시 사용 가능.

---

<!-- OPENCLAW_VERSION_START -->
## OpenClaw 버전 정보

> 이미지 빌드 시 자동 갱신됩니다.

| 항목 | 내용 |
|---|---|
| 설치 버전 | `2026.4.5` |
| 빌드 날짜 | 2026-04-07 |

### 주요 변경사항

**주요 변경 (Breaking)**

- **Config**: remove legacy public config aliases such as `talk.voiceId` / `talk.apiKey`, `agents.*.sandbox.perSession`, `browser.ssrfPolicy.allowPrivateNetwork`, `hooks.internal.handlers`, and channel/group/room `allow` toggles in favor of the canonical public paths and `enabled`, while keeping load-time compatibility and `openclaw doctor --fix` migration support for existing configs

**업데이트 내용**

- **Agents/video generation**: add the built-in `video_generate` tool so agents can create videos through configured providers and return the generated media directly in the reply
- **Agents/music generation**: ignore unsupported optional hints such as `durationSeconds` with a warning instead of hard-failing requests on providers like Google Lyria
- **Providers/ComfyUI**: add a bundled `comfy` workflow media plugin for local ComfyUI and Comfy Cloud workflows, including shared `image_generate`, `video_generate`, and workflow-backed `music_generate` support, with prompt injection, optional reference-image upload, live tests, and output download
- **Tools/music generation**: add the built-in `music_generate` tool with bundled Google (Lyria) and MiniMax providers plus workflow-backed Comfy support, including async task tracking and follow-up delivery of finished audio
- **Providers**: add bundled Qwen, Fireworks AI, and StepFun providers, plus MiniMax TTS, Ollama Web Search, and MiniMax Search integrations for chat, speech, and search workflows
- **Providers/Amazon Bedrock**: add bundled Mantle support plus inference-profile discovery and automatic request-region injection so Bedrock-hosted Claude, GPT-OSS, Qwen, Kimi, GLM, and similar routes work with less manual setup
- **Control UI/multilingual**: add localized control UI support for Simplified Chinese, Traditional Chinese, Brazilian Portuguese, German, Spanish, Japanese, Korean, French, Turkish, Indonesian, Polish, and Ukrainian
- **Plugins**: add plugin-config TUI prompts to guided onboarding/setup flows, and add `openclaw plugins install --force` so existing plugin and hook-pack targets can be replaced without using the dangerous-code override flag
<!-- OPENCLAW_VERSION_END -->

---

## 이미지 사양

| 항목 | 내용 |
|---|---|
| 베이스 | `nvidia/cuda:12.8.1-runtime-ubuntu22.04` |
| CUDA | 12.8.1 (Pascal ~ Blackwell 전 GPU 지원) |
| 최소 호스트 드라이버 | `>= 570.124.06` |
| OS | Ubuntu 22.04 LTS |
| Node.js | 24 |
| OpenClaw | latest |
| Ollama | latest |

### 사전 설치 도구

`git` `curl` `wget` `nano` `vim` `python3` `pip` `npm` `jq` `build-essential`

---

## 구성

```
컨테이너 내부
├── Ollama (127.0.0.1:11434)          ← 로컬 LLM 추론 서버
└── OpenClaw gateway (0.0.0.0:18789)
        ↕ Telegram Bot API (long-polling)
        Telegram 사용자
```

- API 비용 없음 — 기본 구성은 Ollama 로컬 모델만 사용
- 외부 provider API key 환경변수 설정 시 자동 등록 → `/model` 로 전환 가능
- Telegram long-polling 방식 → gcube 인바운드 포트 개방 불필요

---

## 환경변수

### 필수

| 변수 | 예시 | 설명 |
|---|---|---|
| `TELEGRAM_BOT_TOKEN` | `123456:ABC-DEF...` | [@BotFather](https://t.me/BotFather) 에서 발급 |
| `TELEGRAM_ALLOWED_USER_IDS` | `123456789` 또는 `123456789,987654321` | 봇을 사용할 Telegram 수치형 User ID (쉼표로 여러 명 가능) |
| `OLLAMA_MODEL` | `qwen3.5:9b` | 사용할 Ollama 모델. **반드시 태그 포함** (예: `:9b`, `:14b`) |

> **OLLAMA_MODEL 주의**: 태그 없이 모델명만 지정하면 `:latest` 로 시도합니다.
> `:latest` 태그가 없는 모델은 다운로드 오류가 발생합니다. 항상 명시적 태그를 사용하세요.
>
> 사용 가능한 태그 확인: https://ollama.com/library

### 선택

| 변수 | 예시 | 설명 |
|---|---|---|
| `OPENCLAW_GATEWAY_TOKEN` | `my-fixed-token` | Control UI 연결 토큰. 설정 시 재시작 후에도 동일 토큰 유지. 미설정 시 자동 생성 |
| `ANTHROPIC_API_KEY` | `sk-ant-...` | Anthropic Claude API key |
| `OPENAI_API_KEY` | `sk-...` | OpenAI API key |
| `GEMINI_API_KEY` | `AIza...` | Google Gemini API key |
| `MISTRAL_API_KEY` | `...` | Mistral API key |
| `DEEPSEEK_API_KEY` | `...` | DeepSeek API key |
| `GROQ_API_KEY` | `...` | Groq API key |
| `GITHUB_USERNAME` | `your-username` | git config user.name |
| `GITHUB_EMAIL` | `you@example.com` | git config user.email |
| `GITHUB_TOKEN` | `ghp_...` | GitHub Personal Access Token (git push 인증) |
| `GITHUB_REPO_URL` | `https://github.com/you/repo` | 컨테이너 시작 시 `/workspace` 에 클론할 repo URL |

> GitHub 관련 변수는 모두 선택사항. `GITHUB_USERNAME`과 `GITHUB_EMAIL`이 없으면 GitHub 설정 전체가 스킵됨.

---

## 외부 AI 모델 추가

기본 구성은 Ollama 로컬 모델만 사용합니다. 외부 AI provider를 추가하려면 gcube 워크로드 환경변수에 API key를 설정하고 워크로드를 재시작합니다. 시작 시 API key를 감지하여 OpenClaw 설정에 자동으로 등록합니다.

등록된 외부 모델은 Telegram에서 `/model` 명령어로 전환하여 사용할 수 있습니다.

---

## gcube 워크로드 배포

### 사전 준비: 이미지 공개 설정

ghcr.io 패키지는 기본적으로 비공개. gcube에서 접근하려면 공개로 변경 필요.

1. GitHub → [Packages](https://github.com/chaeyoon-08?tab=packages) 에서 `openclaw-ollama-baseimage` 선택
2. Package settings → Change visibility → **Public** 으로 변경

> 비공개로 유지하고 싶다면 gcube Storage Management에서 ghcr.io 인증 정보를 등록해야 함.

---

### 워크로드 등록 단계

**1단계 — 이미지 입력**

```
ghcr.io/chaeyoon-08/openclaw-ollama-baseimage:latest
```

**2단계 — 리소스 설정**

| 항목 | 권장값 |
|---|---|
| GPU | 1개 이상 |
| 최소 CUDA 버전 | `12.8` |
| Shared Memory | `1GB` 이상 |

**3단계 — 환경변수 설정**

| 변수 | 값 |
|---|---|
| `TELEGRAM_BOT_TOKEN` | BotFather에서 발급한 토큰 |
| `TELEGRAM_ALLOWED_USER_IDS` | 본인 Telegram user ID (예: `8374448391`) |
| `OLLAMA_MODEL` | 사용할 모델 (예: `qwen3.5:9b`) |
| `OPENCLAW_GATEWAY_TOKEN` | (선택) Control UI 토큰 고정값 |
| `ANTHROPIC_API_KEY` | (선택) Claude 사용 시 |
| `OPENAI_API_KEY` | (선택) GPT 사용 시 |

**4단계 — 포트 설정**

| 컨테이너 포트 | 용도 |
|---|---|
| `18789` | OpenClaw Control UI 및 gateway |

gcube 워크로드 등록 시 포트 `18789` 를 Service URL로 노출하도록 설정.

**5단계 — 배포 확인**

배포 후 워크로드 로그에서 아래 메시지 확인:

```
[ DONE ] All services started
  Ollama model  : qwen3.5:9b
  Gateway token : <토큰값>
```

로그 출력 후 Telegram에서 봇에게 메시지를 보내면 바로 응답합니다.

**Control UI 접근:**
```
http://<gcube-service-url>/__openclaw__/
```
로그에 출력된 `Gateway token` 값 입력 후 Connect 클릭.

---

## GitHub Personal Access Token 발급 방법

GitHub → Settings → Developer settings → **Personal access tokens** → Tokens (classic) → Generate new token

### 필요 권한 (Scope)

| Scope | 이유 |
|---|---|
| `repo` | private repo 클론(`GITHUB_REPO_URL`) 및 git push(`GITHUB_TOKEN`) |

> public repo만 사용한다면 `repo` 대신 `public_repo` 만 선택해도 됨.

토큰 생성 후 `GITHUB_TOKEN` 환경변수에 입력. `ghp_` 로 시작하는 문자열.

---

## Telegram User ID 확인 방법

봇을 처음 사용하기 전에 본인의 Telegram 수치형 User ID가 필요합니다.

1. [@userinfobot](https://t.me/userinfobot) 에 `/start` 전송
2. 표시된 `Id:` 숫자를 `TELEGRAM_ALLOWED_USER_IDS` 에 입력

---

## 로컬 테스트

```bash
# .env 파일 생성
cat > .env << 'EOF'
TELEGRAM_BOT_TOKEN=your_bot_token
TELEGRAM_ALLOWED_USER_IDS=your_telegram_user_id
OLLAMA_MODEL=qwen3.5:9b
EOF

# NVIDIA GPU 있는 경우
docker compose up

# GPU 없는 경우 (CPU 추론, 속도 느림)
docker run --env-file .env ghcr.io/chaeyoon-08/openclaw-ollama-baseimage:latest
```

### 직접 빌드

```bash
docker build -t openclaw-base .
docker run --gpus all --env-file .env openclaw-base
```

---

## GitHub Actions 자동 빌드

`main` 브랜치에 push 하거나 `v*.*.*` 태그를 달면 자동으로 이미지를 빌드하여 ghcr.io 에 push 합니다.

**생성되는 이미지 태그:**
- `main` push → `:main`, `:latest`, `:sha-<7자>`
- `v1.2.3` 태그 → `:1.2.3`, `:1.2`, `:1`, `:latest`, `:sha-<7자>`
- 수동 실행 (`workflow_dispatch`) → 선택한 브랜치 기준

별도 시크릿 설정 불필요 — `GITHUB_TOKEN` 으로 ghcr.io 인증.
빌드 완료 시 OpenClaw 최신 버전 정보가 상단 "버전 정보" 섹션에 자동 반영됩니다.

---

## 참고

- OpenClaw 문서: https://docs.openclaw.ai
- Ollama 모델 목록: https://ollama.com/library
- gcube 플랫폼 문서: https://data-alliance.github.io/gai-platform-docs/
