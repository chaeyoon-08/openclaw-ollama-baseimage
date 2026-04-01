# OpenClaw + Ollama Telegram 봇 gcube 배포 가이드

> 이 문서는 OpenClaw + Ollama 기반 Telegram AI 봇을 gcube 워크로드에 배포하는 전체 과정을 다룹니다.
> Docker 이미지 빌드부터 Telegram 봇 동작 확인까지 순서대로 진행합니다.

---

## 목차

1. [사전 준비](#1-사전-준비)
2. [Docker 이미지 빌드 (GitHub Actions)](#2-docker-이미지-빌드-github-actions)
3. [gcube 워크로드 배포](#3-gcube-워크로드-배포)
4. [배포 결과 확인](#4-배포-결과-확인)
5. [Telegram 봇 사용](#5-telegram-봇-사용)
6. [트러블슈팅](#6-트러블슈팅)

---

## 개요

### 아키텍처

```
Telegram 사용자
    ↕ (long-polling, outbound)
OpenClaw Gateway (포트 18789)
    ↕
Ollama API (127.0.0.1:11434)
    ↓
로컬 LLM 모델 (예: qwen3.5:9b)
```

- 외부 AI API 비용 없음 — Ollama로 gcube GPU에서 직접 추론
- Telegram long-polling 방식이라 gcube 인바운드 포트 개방 불필요
- 컨테이너 시작 시 환경변수만으로 전체 설정 자동 완료

---

## 1. 사전 준비

### 1-1. Telegram 봇 생성

1. Telegram에서 [@BotFather](https://t.me/BotFather) 에 접속
2. `/newbot` 명령어 입력
3. 봇 이름 및 username 설정 (username은 `_bot`으로 끝나야 함)
4. 발급된 **Bot Token** 보관 (형식: `1234567890:AAF...`)

### 1-2. 본인 Telegram User ID 확인

`TELEGRAM_ALLOWED_USER_IDS`에 입력할 수치형 User ID가 필요합니다.

1. [@userinfobot](https://t.me/userinfobot) 에 `/start` 전송
2. 표시된 `Id:` 숫자 메모

> `@username`은 허용되지 않습니다. 반드시 수치형 ID를 사용하세요.
> 여러 명을 허용하려면 쉼표로 구분합니다. (예: `111111111,222222222`)

### 1-3. 사용할 Ollama 모델 확인

[https://ollama.com/library](https://ollama.com/library) 에서 모델과 태그를 확인합니다.

| 모델 | 태그 예시 | VRAM 요구량 |
|---|---|---|
| qwen3 | `qwen3:8b`, `qwen3:14b`, `qwen3:32b` | 약 6 / 10 / 20 GB |
| qwen3.5 | `qwen3.5:9b` | 약 7 GB |
| llama3 | `llama3:8b` | 약 6 GB |

> **태그를 반드시 포함하세요.** `qwen3`처럼 태그 없이 입력하면 `:latest`를 시도하며,
> `:latest`가 없는 모델은 다운로드 오류가 발생합니다.

---

## 2. Docker 이미지 빌드 (GitHub Actions)

코드 변경이 있을 때만 필요한 단계입니다. 이미 빌드된 이미지를 사용한다면 3단계로 넘어가세요.

### 2-1. 레포지토리 구성 확인

```
openclaw-ollama-baseimage/
├── Dockerfile          ← CUDA + Node.js + Ollama + OpenClaw 설치 정의
├── entrypoint.sh       ← 컨테이너 시작 시 자동 실행되는 설정 스크립트
└── .github/workflows/
    └── docker-publish.yml  ← ghcr.io 자동 빌드/push 워크플로우
```

### 2-2. main 브랜치에 push

`main` 브랜치에 push하면 GitHub Actions가 자동으로:

1. `Dockerfile` 기반으로 이미지 빌드
2. `ghcr.io/<owner>/openclaw-ollama-baseimage`에 push
3. 다음 태그 자동 부여:
   - `:latest` (main 브랜치)
   - `:main`
   - `:sha-<7자리 커밋 해시>`

### 2-3. 이미지 공개 설정

gcube에서 인증 없이 이미지를 pull하려면 패키지를 **공개**로 설정해야 합니다.

1. GitHub → 우측 상단 프로필 → **Packages** 탭
2. `openclaw-ollama-baseimage` 선택
3. 우측 하단 **Package settings** 클릭
4. **Change visibility** → **Public** 선택

> 비공개로 유지하고 싶은 경우: gcube Storage Management에서 ghcr.io 인증 정보를 별도 등록해야 합니다.

---

## 3. gcube 워크로드 배포

### 3-1. 워크로드 생성

gcube 콘솔 → **Workloads** → **New Workload**

### 3-2. 이미지 입력

```
ghcr.io/chaeyoon-08/openclaw-ollama-baseimage:latest
```

### 3-3. 리소스 설정

| 항목 | 권장 설정 |
|---|---|
| GPU | 1개 이상 |
| CUDA 버전 | 12.8 이상 (최소 드라이버 570.124.06) |
| Shared Memory | 1 GB 이상 |

### 3-4. 환경변수 설정

**필수**

| 변수명 | 값 |
|---|---|
| `TELEGRAM_BOT_TOKEN` | BotFather에서 발급한 토큰 |
| `TELEGRAM_ALLOWED_USER_IDS` | 허용할 Telegram User ID (쉼표로 여러 명 가능) |
| `OLLAMA_MODEL` | 사용할 모델 태그 포함 (예: `qwen3.5:9b`) |

**선택 (Control UI 토큰 고정)**

| 변수명 | 값 |
|---|---|
| `OPENCLAW_GATEWAY_TOKEN` | Control UI 연결 토큰 고정값. 미설정 시 매 시작마다 자동 생성 |

**선택 (외부 AI provider)**

| 변수명 | 값 |
|---|---|
| `ANTHROPIC_API_KEY` | Anthropic Claude API key |
| `OPENAI_API_KEY` | OpenAI API key |
| `GEMINI_API_KEY` | Google Gemini API key |
| `MISTRAL_API_KEY` | Mistral API key |
| `DEEPSEEK_API_KEY` | DeepSeek API key |
| `GROQ_API_KEY` | Groq API key |

**선택 (GitHub 연동)**

`GITHUB_USERNAME`과 `GITHUB_EMAIL`이 모두 있어야 GitHub 설정이 활성화됩니다. 하나라도 없으면 GitHub 관련 설정 전체가 스킵됩니다.

| 변수명 | 값 |
|---|---|
| `GITHUB_USERNAME` | GitHub 사용자명 |
| `GITHUB_EMAIL` | GitHub 계정 이메일 |
| `GITHUB_TOKEN` | GitHub Personal Access Token (`repo` 권한 필요) |
| `GITHUB_REPO_URL` | 시작 시 `/workspace`에 클론할 repo URL |

### 3-5. 포트 설정

| 포트 | 용도 |
|---|---|
| `18789` | OpenClaw Gateway / Control UI |

### 3-6. 저장소 연결 (선택)

gcube Storage Management에서 연결한 저장소를 워크로드에 마운트하면 컨테이너 내부에서 `/data/data` 경로로 접근할 수 있습니다.

### 3-7. 배포 시작

설정 완료 후 워크로드를 시작합니다. 첫 배포 시 Ollama 모델 다운로드(수 GB) 시간이 소요됩니다.

---

## 4. 배포 결과 확인

### 4-1. 컨테이너 로그 확인

워크로드 → **Logs** 탭에서 아래 순서대로 로그가 출력되면 정상입니다.

```
[ START ] Validating environment variables
[  OK   ] Required variables present
[  OK   ]   OLLAMA_MODEL             = qwen3.5:9b
[  OK   ]   TELEGRAM_ALLOWED_USER_IDS = 8374448391
[ START ] Starting Ollama service
[  OK   ] Ollama is ready
[ DOING ] Pulling Ollama model: qwen3.5:9b
[ DOING ]   pulling manifest
[ DOING ]   pulling dec52a44569a: 0%
[ DOING ]   pulling dec52a44569a: 10%
...
[ DOING ]   pulling dec52a44569a: 100%
[ DOING ]   verifying sha256 digest
[ DOING ]   writing manifest
[ DOING ]   success
[  OK   ] Model ready: qwen3.5:9b
[ START ] Starting OpenClaw gateway
[ DONE  ] All services started

  Ollama model  : qwen3.5:9b
  Gateway token : xDVFCNWi174i6bZjI3jJtbW0RG6AkrmN

[telegram] [default] starting provider (@your_bot_name)
```

> `OPENCLAW_GATEWAY_TOKEN` 환경변수를 설정하면 재시작 후에도 동일 토큰이 유지됩니다.
> 미설정 시 매 시작마다 새로 생성되므로 로그에서 확인 후 메모해두세요.

### 4-2. Control UI 접속 (선택)

OpenClaw 관리 화면에 접속하려면:

```
http://<gcube-service-url>/__openclaw__/
```

접속 후 로그에서 확인한 `Gateway token` 입력.

---

## 5. Telegram 봇 사용

로그에서 `starting provider` 메시지가 확인되면 Telegram에서 바로 사용 가능합니다.

1. Telegram에서 생성한 봇에게 메시지 전송
2. 봇이 응답하면 정상 동작 확인 완료

> **주의**: 같은 봇 토큰으로 다른 인스턴스(로컬 테스트 등)가 동시에 실행 중이면
> `409: Conflict` 오류가 발생합니다. 반드시 인스턴스를 하나만 실행하세요.

---

## 6. 트러블슈팅

### 모델 다운로드 실패

```
pull model manifest: file does not exist
```

- **원인**: `OLLAMA_MODEL`에 태그가 없거나 잘못된 태그
- **해결**: [https://ollama.com/library](https://ollama.com/library) 에서 정확한 태그 확인 후 재설정

### Telegram 409 Conflict

```
409: Conflict: terminated by other getUpdates request
```

- **원인**: 같은 봇 토큰으로 다른 인스턴스가 동시에 실행 중
- **해결**: 로컬 또는 다른 워크로드에서 실행 중인 봇 프로세스 종료 후 재시작

### GPU 미감지

```
inference compute: no GPU found
```

- **원인**: 워크로드 리소스 설정에서 GPU가 할당되지 않았거나 드라이버 버전 미달
- **해결**: 워크로드 리소스 설정에서 GPU 1개 이상 할당, 호스트 드라이버 버전 570.124.06 이상 확인

### 이미지 pull 실패 (gcube)

- **원인**: ghcr.io 패키지가 비공개 상태
- **해결**: GitHub Packages → Package settings → Change visibility → Public

---

## 참고 링크

| 문서 | URL |
|---|---|
| OpenClaw 공식 문서 | https://docs.openclaw.ai |
| Ollama 모델 라이브러리 | https://ollama.com/library |
| OpenClaw 설정 레퍼런스 | https://docs.openclaw.ai/gateway/configuration-reference |
| Telegram BotFather | https://t.me/BotFather |
| 기술 스펙 (내부) | `spec/SPEC.md` |
| gcube 플랫폼 조사 (내부) | `spec/GCUBE.md` |
