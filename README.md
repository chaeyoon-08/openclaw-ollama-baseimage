# openclaw-base

OpenClaw + Ollama 기반 Telegram AI 비서 컨테이너 이미지.
gcube 워크로드에 배포 후 환경변수만 설정하면 즉시 사용 가능.

---

## 브랜치별 이미지

| 브랜치 | 이미지 | 설명 |
|---|---|---|
| `main` | `ghcr.io/chaeyoon-08/openclaw-bot:latest` | 기본 구성 — 로컬 LLM + 외부 모델 전환 |
| `skills` | `ghcr.io/chaeyoon-08/openclaw-bot-skills:latest` | 기본 구성 + 에이전트 성격 부여 + 빌트인 스킬 |
| `multi-agent` | `ghcr.io/chaeyoon-08/openclaw-bot-multi:latest` | 기본 구성 + 멀티 에이전트 + A2A 오케스트레이션 |
| `agent-kit` | `ghcr.io/chaeyoon-08/openclaw-bot-agentkit:latest` | skills + multi-agent 올인원 패키지 |

> `skills`, `multi-agent`, `agent-kit` 브랜치는 현재 개발 중입니다.

---

<!-- OPENCLAW_VERSION_START -->
## OpenClaw 버전 정보

> 이미지 빌드 시 자동 갱신됩니다.

| 항목 | 내용 |
|---|---|
| 설치 버전 | `2026.4.5` |
| 빌드 날짜 | 2026-04-07 |

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

> **CUDA 12.8.1 선택 이유**: CUDA 13.x부터 Pascal(sm_60/61) 아키텍처 지원이 제거됩니다.
> 12.8.1은 Maxwell(sm_50) ~ Blackwell(sm_120) 전 세대를 지원하는 마지막 안정 버전입니다.

### 사전 설치 도구

`git` `curl` `wget` `nano` `vim` `python3` `pip` `npm` `jq` `build-essential`

### GitHub Actions 자동 빌드

브랜치에 push하면 자동으로 이미지를 빌드하여 ghcr.io에 push합니다.

| 브랜치 | 이미지 태그 |
|---|---|
| `main` | `:latest`, `:YYYY.MM.DD`, `:sha-<7자>` |
| `skills` | `:skills`, `:skills-YYYY.MM.DD`, `:sha-<7자>` |
| `multi-agent` | `:multi-agent`, `:multi-agent-YYYY.MM.DD`, `:sha-<7자>` |
| `agent-kit` | `:agent-kit`, `:agent-kit-YYYY.MM.DD`, `:sha-<7자>` |

별도 시크릿 설정 불필요 — `GITHUB_TOKEN`으로 ghcr.io 인증.
빌드 완료 시 OpenClaw 최신 버전 정보가 상단 "버전 정보" 섹션에 자동 반영됩니다.

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
