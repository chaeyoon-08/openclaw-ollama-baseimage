# gcube에 OpenClaw + Ollama Telegram 봇 배포하기

> 이 문서는 gcube 워크로드에 OpenClaw + Ollama 기반 Telegram AI 봇을 배포하는 전 과정을 설명합니다.
> 순서대로 따라하면 Telegram에서 로컬 LLM과 대화할 수 있는 환경이 완성됩니다.

---

## 목차

1. [사전 준비](#1-사전-준비)
2. [gcube 워크로드 생성](#2-gcube-워크로드-생성)
3. [배포 확인](#3-배포-확인)
4. [Telegram 봇 사용](#4-telegram-봇-사용)
5. [Control UI 접근](#5-control-ui-접근)
6. [외부 AI 모델 추가](#6-외부-ai-모델-추가)
7. [트러블슈팅](#7-트러블슈팅)

---

## 1. 사전 준비

### 1-1. Telegram 봇 생성

1. Telegram에서 [@BotFather](https://t.me/BotFather) 접속
2. `/newbot` 입력
3. 봇 이름 설정 (예: `My AI Assistant`)
4. 봇 username 설정 — 반드시 `_bot`으로 끝나야 함 (예: `myai_bot`)
5. 발급된 **Bot Token** 보관 (형식: `1234567890:AAF...`)

### 1-2. 본인 Telegram User ID 확인

`TELEGRAM_ALLOWED_USER_IDS`에 입력할 수치형 ID가 필요합니다.

1. [@userinfobot](https://t.me/userinfobot) 에 `/start` 전송
2. 표시된 `Id:` 숫자 메모

> `@username`은 사용할 수 없습니다. 반드시 수치형 ID를 사용하세요.
> 여러 명을 허용하려면 쉼표로 구분합니다. (예: `111111111,222222222`)

### 1-3. 사용할 Ollama 모델 확인

[ollama.com/library](https://ollama.com/library)에서 모델과 태그를 확인합니다.

| 모델 | 태그 예시 | VRAM 요구량 |
|---|---|---|
| qwen3 | `qwen3:8b`, `qwen3:14b`, `qwen3:32b` | 약 6 / 10 / 20 GB |
| qwen3.5 | `qwen3.5:9b`, `qwen3.5:35b` | 약 7 / 23 GB |
| llama3 | `llama3:8b` | 약 6 GB |

> **태그를 반드시 포함하세요.** `qwen3`처럼 태그 없이 입력하면 `:latest`를 시도하며,
> `:latest`가 없는 모델은 다운로드 오류가 발생합니다.

---

## 2. gcube 워크로드 생성

### 2-1. 새 워크로드 생성

gcube 콘솔 → **Workloads** → **New Workload**

### 2-2. 이미지 입력

```
ghcr.io/chaeyoon-08/openclaw-bot:latest
```

> 이미지가 공개 설정이 되어 있지 않으면 pull 오류가 발생합니다.
> 오류 발생 시 [트러블슈팅 → 이미지 pull 실패](#이미지-pull-실패-gcube) 참고.

### 2-3. 리소스 설정

| 항목 | 권장 설정 |
|---|---|
| GPU | 1개 이상 |
| CUDA 버전 | 12.8 이상 (최소 드라이버 570.124.06) |
| Shared Memory | 1 GB 이상 |

### 2-4. 환경변수 설정

**필수 항목 — 이 세 가지가 없으면 컨테이너가 시작되지 않습니다.**

| 변수명 | 입력값 |
|---|---|
| `TELEGRAM_BOT_TOKEN` | BotFather에서 발급한 토큰 |
| `TELEGRAM_ALLOWED_USER_IDS` | 1단계에서 확인한 본인 Telegram User ID |
| `OLLAMA_MODEL` | 사용할 모델 (예: `qwen3.5:9b`) |

**선택 항목**

| 변수명 | 입력값 | 설명 |
|---|---|---|
| `OPENCLAW_GATEWAY_TOKEN` | 원하는 문자열 (예: `my-token-1234`) | 설정 시 재시작 후에도 동일 토큰 유지. 미설정 시 재시작마다 새 토큰 생성 |
| `ANTHROPIC_API_KEY` | `sk-ant-...` | Claude 모델 사용 시 |
| `OPENAI_API_KEY` | `sk-...` | GPT 모델 사용 시 |
| `GEMINI_API_KEY` | `AIza...` | Gemini 모델 사용 시 |
| `GITHUB_USERNAME` | GitHub 사용자명 | GitHub 연동 시 |
| `GITHUB_EMAIL` | GitHub 계정 이메일 | GitHub 연동 시 |
| `GITHUB_TOKEN` | `ghp_...` | Private repo 접근 시 |
| `GITHUB_REPO_URL` | `https://github.com/...` | 시작 시 `/workspace`에 자동 클론할 repo |

### 2-5. 포트 설정

| 포트 | 용도 |
|---|---|
| `18789` | OpenClaw Gateway / Control UI |

### 2-6. 워크로드 시작

설정 완료 후 워크로드를 시작합니다.

> **첫 배포 시 주의**: Ollama 모델 다운로드에 수 분이 소요됩니다. (모델 크기에 따라 상이)
> 로그에서 진행 상황을 확인할 수 있습니다.

---

## 3. 배포 확인

워크로드 → **Logs** 탭에서 아래 순서대로 로그가 출력되면 정상입니다.

```
[ START ] Validating environment variables
[  OK   ] Required variables present
[  OK   ]   OLLAMA_MODEL              = qwen3.5:9b
[  OK   ]   TELEGRAM_ALLOWED_USER_IDS = 123456789
[ START ] Starting Ollama service
[  OK   ] Ollama is ready
[ DOING ] Pulling Ollama model: qwen3.5:9b
[ DOING ]   pulling manifest
[ DOING ]   pulling dec52a44569a: 10%
[ DOING ]   pulling dec52a44569a: 50%
[ DOING ]   pulling dec52a44569a: 100%
[ DOING ]   verifying sha256 digest
[ DOING ]   success
[  OK   ] Model ready: qwen3.5:9b
[ START ] Starting OpenClaw gateway
[ DONE  ] All services started

  Ollama model  : qwen3.5:9b
  Gateway token : xDVFCNWi174i6bZjI3jJtbW0RG6AkrmN

[telegram] [default] starting provider (@your_bot_name)
```

`Gateway token` 값은 Control UI 접속에 사용합니다. 메모해두세요.

> `OPENCLAW_GATEWAY_TOKEN` 환경변수를 설정했다면 해당 값이 그대로 표시됩니다.

---

## 4. Telegram 봇 사용

로그에서 `starting provider` 메시지가 확인되면 즉시 사용 가능합니다.

1. Telegram에서 생성한 봇 검색 후 시작
2. 메시지 전송 → 봇이 응답하면 정상

### 사용 가능한 명령어

| 명령어 | 설명 |
|---|---|
| `/model` | 현재 사용 중인 모델 확인 및 전환 |
| `/model list` | 사용 가능한 모델 목록 조회 |
| `/model openai/gpt-4o` | 특정 모델로 직접 전환 |

> 외부 AI provider API key를 설정한 경우 `/model list`에서 해당 모델들을 확인할 수 있습니다.

---

## 5. Control UI 접근

OpenClaw 웹 대시보드에서 모델·채널·에이전트 설정을 관리할 수 있습니다.

### 접속 방법

1. gcube 서비스 URL 접속 (포트 18789로 노출된 URL)
2. **Gateway Token** 입력 — 로그에서 확인한 값 또는 `OPENCLAW_GATEWAY_TOKEN`에 설정한 값
3. **Connect** 클릭 → 바로 진입

컨테이너 내부에서 토큰 값 직접 확인:
```bash
jq -r '.gateway.auth.token' /root/.openclaw/openclaw.json
```

### 재시작 후 토큰 유지 (권장)

워크로드를 재시작하면 `OPENCLAW_GATEWAY_TOKEN`을 설정하지 않은 경우 토큰이 새로 생성됩니다.
토큰을 고정하려면 gcube 환경변수에 `OPENCLAW_GATEWAY_TOKEN=원하는값`을 추가하세요.

토큰이 고정되면 북마크 URL로 자동 접속할 수 있습니다:
```
https://<gcube-서비스-URL>/#token=<설정한-토큰값>
```

---

## 6. 외부 AI 모델 추가

기본 구성은 Ollama 로컬 모델만 사용합니다. 외부 AI provider를 추가하면 Telegram에서 `/model` 명령어로 모델을 전환할 수 있습니다.

### 추가 방법

gcube 워크로드 환경변수에 API key를 추가하고 워크로드를 재시작합니다.

| Provider | 환경변수 |
|---|---|
| Anthropic (Claude) | `ANTHROPIC_API_KEY` |
| OpenAI (GPT) | `OPENAI_API_KEY` |
| Google (Gemini) | `GEMINI_API_KEY` |
| Mistral | `MISTRAL_API_KEY` |
| DeepSeek | `DEEPSEEK_API_KEY` |
| Groq | `GROQ_API_KEY` |

재시작 후 로그에서 `Provider registered: anthropic` 등의 메시지가 확인되면 정상 등록된 것입니다.

### 모델 전환

Telegram에서:
```
/model list         ← 사용 가능한 모델 목록 조회
/model 3            ← 번호로 선택
/model anthropic/claude-sonnet-4-6  ← 직접 지정
```

---

## 7. 트러블슈팅

### 봇이 응답하지 않음

```
409: Conflict: terminated by other getUpdates request
```

- **원인**: 같은 봇 토큰으로 다른 인스턴스(로컬 테스트 등)가 동시에 실행 중
- **해결**: 다른 환경에서 실행 중인 봇 프로세스를 종료 후 워크로드 재시작

### 모델 다운로드 실패

```
pull model manifest: file does not exist
```

- **원인**: `OLLAMA_MODEL`에 태그가 없거나 잘못된 태그
- **해결**: [ollama.com/library](https://ollama.com/library)에서 정확한 태그 확인 후 환경변수 수정 → 재시작

### GPU 미감지

```
inference compute: no GPU found
```

- **원인**: GPU 미할당 또는 드라이버 버전 미달
- **해결**: 워크로드 리소스에서 GPU 1개 이상 할당, 호스트 드라이버 570.124.06 이상 확인

### 이미지 pull 실패 (gcube)

- **원인**: ghcr.io 패키지가 비공개 상태
- **해결**: GitHub → Packages → `openclaw-ollama-baseimage` → Package settings → Change visibility → **Public**

### 외부 모델이 `/model list`에 표시되지 않음

- **원인**: API key 환경변수 미설정 또는 오탈자
- **확인**: 워크로드 로그에서 `Provider registered: anthropic` 메시지 유무 확인
- **해결**: 환경변수 값 확인 후 워크로드 재시작

---

## 참고

| 문서 | URL |
|---|---|
| OpenClaw 공식 문서 | https://docs.openclaw.ai |
| Ollama 모델 라이브러리 | https://ollama.com/library |
| GitHub 저장소 | https://github.com/chaeyoon-08/openclaw-ollama-baseimage |
| 컨테이너 이미지 (main) | `ghcr.io/chaeyoon-08/openclaw-bot:latest` |
