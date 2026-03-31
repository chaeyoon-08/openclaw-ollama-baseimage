# openclaw-base

OpenClaw + Ollama 기반 Telegram AI 비서 컨테이너 이미지.
gcube 워크로드에 배포하여 환경변수만 설정하면 즉시 사용 가능.

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
├── Ollama (127.0.0.1:11434)       ← 로컬 LLM 추론 서버
└── OpenClaw gateway (127.0.0.1:18789)
        ↕ Telegram Bot API (long-polling)
        Telegram 사용자
```

- API 비용 없음 — 외부 AI API 사용하지 않고 Ollama 로컬 모델만 사용
- gcube 클라우드 저장소는 `/data/data` 경로로 자동 마운트됨

---

## 환경변수

### 필수

| 변수 | 예시 | 설명 |
|---|---|---|
| `TELEGRAM_BOT_TOKEN` | `123456:ABC-DEF...` | [@BotFather](https://t.me/BotFather) 에서 발급 |
| `TELEGRAM_ALLOWED_USER_IDS` | `123456789` 또는 `123456789,987654321` | 봇을 사용할 Telegram 수치형 User ID (쉼표로 여러 명 가능) |
| `OLLAMA_MODEL` | `qwen3:14b` | 사용할 Ollama 모델. **반드시 태그 포함** (예: `:14b`, `:8b`) |

> **OLLAMA_MODEL 주의**: 태그 없이 모델명만 지정하면 `:latest` 로 시도합니다.
> `:latest` 태그가 없는 모델은 다운로드 오류가 발생합니다. 항상 명시적 태그를 사용하세요.
>
> 사용 가능한 태그 확인: https://ollama.com/library

### 선택

GitHub 관련 변수는 모두 선택사항. `GITHUB_USERNAME`과 `GITHUB_EMAIL`이 없으면 GitHub 설정 전체가 스킵됨.

| 변수 | 예시 | 설명 |
|---|---|---|
| `GITHUB_USERNAME` | `your-username` | git config user.name |
| `GITHUB_EMAIL` | `you@example.com` | git config user.email |
| `GITHUB_TOKEN` | `ghp_...` | GitHub Personal Access Token (git push 인증) |
| `GITHUB_REPO_URL` | `https://github.com/you/repo` | 컨테이너 시작 시 `/workspace` 에 클론할 repo URL |

---

## GitHub Personal Access Token 발급 방법

GitHub → Settings → Developer settings → **Personal access tokens** → Tokens (classic) → Generate new token

### 필요 권한 (Scope)

| Scope | 이유 |
|---|---|
| `repo` | private repo 클론(`GITHUB_REPO_URL`) 및 git push(`GITHUB_TOKEN`) |

> public repo만 사용한다면 `repo` 대신 `public_repo` 만 선택해도 됨.

**Fine-grained token** 을 사용하는 경우 (더 세밀한 권한 제어):

| 권한 항목 | 수준 |
|---|---|
| Contents | Read and Write |
| Metadata | Read (자동 포함) |

토큰 생성 후 `GITHUB_TOKEN` 환경변수에 입력. `ghp_` 로 시작하는 문자열.

---

## Telegram User ID 확인 방법

봇을 처음 사용하기 전에 본인의 Telegram 수치형 User ID가 필요합니다.

1. [@userinfobot](https://t.me/userinfobot) 에 `/start` 전송
2. 표시된 `Id:` 숫자를 `TELEGRAM_ALLOWED_USER_IDS` 에 입력

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
| `OLLAMA_MODEL` | 사용할 모델 (예: `qwen3:14b`) |
| `GITHUB_USERNAME` | (선택) GitHub 사용자명 |
| `GITHUB_EMAIL` | (선택) GitHub 이메일 |
| `GITHUB_TOKEN` | (선택) GitHub Personal Access Token |
| `GITHUB_REPO_URL` | (선택) 클론할 repo URL |

**4단계 — 포트 설정**

| 컨테이너 포트 | 용도 |
|---|---|
| `18789` | OpenClaw Control UI 및 gateway |

gcube 워크로드 등록 시 포트 `18789` 를 Service URL로 노출하도록 설정.

**5단계 — 저장소 연결** (선택)

Storage Management에서 Dropbox 또는 AWS S3 연결 후 워크로드에 마운트.
컨테이너 내부에서 `/data/data` 경로로 접근 가능.

**6단계 — 배포 확인**

배포 후 워크로드 로그에서 아래 메시지 확인:

```
[ DONE ] All services started
  Ollama model  : qwen3:14b
  Gateway token : <자동생성토큰>
```

**Control UI 접근:**
```
http://<gcube-service-url>/__openclaw__/
```
접속 후 로그에 출력된 `Gateway token` 값을 입력하면 OpenClaw 관리 화면으로 진입.

로그 출력 후 Telegram에서 봇에게 메시지 보내면 바로 응답.

---

## workspace 백업/복원

컨테이너가 내려가면 `/root/.openclaw/workspace` 내용이 사라집니다.
`GITHUB_REPO_URL`로 클론된 `/workspace`에 백업하여 git push로 보존할 수 있습니다.

### backup.sh

`/root/.openclaw/workspace` 내용을 `/workspace/.openclaw_copy`로 복사합니다.
컨테이너가 내려가면 `/root/.openclaw/workspace`는 사라지므로, 내려가기 전에 실행하여 `git push`로 보존합니다.

```bash
/workspace/backup.sh
# → /workspace/.openclaw_copy 로 복사 후 git push 명령어 안내
```

### restore.sh

`/workspace/.openclaw_copy` 내용을 `/root/.openclaw/workspace`로 복사합니다.
컨테이너 재시작 후 자동 복원이 안 됐을 때 수동으로 이전 작업 내용을 불러옵니다.

```bash
/workspace/restore.sh
# → 복원 후 openclaw 재시작 명령어 안내
```

### 자동 복원

사전에 `backup.sh` + `git push`가 되어 있는 경우, 컨테이너 재시작 시 git repo를 재클론하면서 `.openclaw_copy`가 함께 내려옵니다. entrypoint.sh가 이를 감지하여 자동으로 복원합니다.

### openclaw gateway 재시작 (컨테이너 유지)

```bash
pkill -f openclaw-gateway
# → 3초 이내 자동 재기동, 컨테이너 종료 없음
```

---

## 로컬 테스트

```bash
# .env 파일 생성
cat > .env << 'EOF'
TELEGRAM_BOT_TOKEN=your_bot_token
TELEGRAM_ALLOWED_USER_IDS=your_telegram_user_id
OLLAMA_MODEL=qwen3:8b
EOF

# NVIDIA GPU 있는 경우
docker compose up

# GPU 없는 경우 (CPU 추론, 속도 느림)
docker run --env-file .env ghcr.io/<owner>/openclaw-base:latest
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

---

## 참고

- OpenClaw 문서: https://docs.openclaw.ai
- Ollama 모델 목록: https://ollama.com/library
- gcube 플랫폼 문서: https://data-alliance.github.io/gai-platform-docs/
