# openclaw-base

OpenClaw + Ollama 기반 Telegram AI 비서 컨테이너 이미지.
환경변수만 설정하면 즉시 사용 가능.

---

## 브랜치별 이미지

| 브랜치 | 이미지 | 설명 |
|---|---|---|
| `main` | `ghcr.io/chaeyoon-08/openclaw-bot:latest` | 기본 구성 — 로컬 LLM + 외부 모델 전환 |
| `feature/agent-structure` | `ghcr.io/chaeyoon-08/openclaw-bot-agent:latest` | 에이전트 구조화 + 스킬 + A2A 올인원 |

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

> **CUDA 12.8.1 선택 이유**: CUDA 13.x부터 Pascal(sm_60/61) 아키텍처 지원이 제거됩니다.
> 12.8.1은 Maxwell(sm_50) ~ Blackwell(sm_120) 전 세대를 지원하는 마지막 안정 버전입니다.

### 사전 설치 도구

`git` `curl` `wget` `nano` `vim` `python3` `pip` `npm` `jq` `build-essential`

### GitHub Actions 자동 빌드

브랜치에 push하면 자동으로 이미지를 빌드하여 ghcr.io에 push합니다.

| 브랜치 | 이미지 태그 |
|---|---|
| `main` | `:latest`, `:main`, `:sha-<7자>` |
| `feature/agent-structure` | `:feature-agent-structure`, `:sha-<7자>` |
| `v*.*.*` 태그 | `:1.2.3`, `:1.2`, `:1`, `:latest` |

별도 시크릿 설정 불필요 — `GITHUB_TOKEN`으로 ghcr.io 인증.
빌드 완료 시 OpenClaw 최신 버전 정보가 상단 "버전 정보" 섹션에 자동 반영됩니다.

---

## main 브랜치

> 이미지: `ghcr.io/chaeyoon-08/openclaw-bot:latest`

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

- Telegram long-polling 방식 → 인바운드 포트 개방 불필요
- 외부 AI provider는 API key 환경변수 설정만으로 자동 등록

### 환경변수

**필수**

| 변수 | 예시 | 설명 |
|---|---|---|
| `TELEGRAM_BOT_TOKEN` | `123456:ABC-DEF...` | [@BotFather](https://t.me/BotFather) 에서 발급 |
| `TELEGRAM_ALLOWED_USER_IDS` | `123456789` | 봇을 사용할 Telegram 수치형 User ID (쉼표로 여러 명) |
| `OLLAMA_MODEL` | `qwen3.5:9b` | 기본 Ollama 모델. **반드시 태그 포함** |

> Ollama 모델 태그 확인: https://ollama.com/library

**선택 — Control UI**

| 변수 | 예시 | 설명 |
|---|---|---|
| `OPENCLAW_GATEWAY_TOKEN` | `my-token` | 토큰 고정. 미설정 시 재시작마다 새 토큰 생성 |

**선택 — 외부 AI provider**

| 변수 | 설명 |
|---|---|
| `ANTHROPIC_API_KEY` | Anthropic Claude |
| `OPENAI_API_KEY` | OpenAI GPT |
| `GEMINI_API_KEY` | Google Gemini |
| `MISTRAL_API_KEY` | Mistral |
| `DEEPSEEK_API_KEY` | DeepSeek |
| `GROQ_API_KEY` | Groq |

**선택 — GitHub 연동**

| 변수 | 설명 |
|---|---|
| `GITHUB_USERNAME` | git config user.name (`GITHUB_EMAIL`과 함께 있어야 활성화) |
| `GITHUB_EMAIL` | git config user.email |
| `GITHUB_TOKEN` | GitHub Personal Access Token |
| `GITHUB_REPO_URL` | 시작 시 `/workspace`에 클론할 repo URL |

---

## 참고

- OpenClaw 문서: https://docs.openclaw.ai
- Ollama 모델 목록: https://ollama.com/library
