# openclaw-base

OpenClaw + Ollama 기반 Telegram AI 비서 컨테이너 이미지.
gcube 워크로드에 배포하여 환경변수만 설정하면 즉시 사용 가능.

---

<!-- OPENCLAW_VERSION_START -->
## OpenClaw 버전 정보

> 이미지 빌드 시 자동 갱신됩니다.

| 항목 | 내용 |
|---|---|
| 설치 버전 | `2026.3.31` |
| 빌드 날짜 | 2026-04-01 |

### 주요 변경사항

**주요 변경 (Breaking)**

- **Nodes/exec**: remove the duplicated `nodes.run` shell wrapper from the CLI and agent `nodes` tool so node shell execution always goes through `exec host=node`, keeping node-specific capabilities on `nodes invoke` and the dedicated media/location/notify actions
- **Plugin SDK**: deprecate the legacy provider compat subpaths plus the older bundled provider setup and channel-runtime compatibility shims, emit migration warnings, and keep the current documented `openclaw/plugin-sdk/*` entrypoints plus local `api.ts` / `runtime-api.ts` barrels as the forward path ahead of a future major-release removal
- **Skills/install and Plugins/install**: built-in dangerous-code `critical` findings and install-time scan failures now fail closed by default, so plugin installs and gateway-backed skill dependency installs that previously succeeded may now require an explicit dangerous override such as `--dangerously-force-unsafe-install` to proceed
- **Gateway/auth**: `trusted-proxy` now rejects mixed shared-token configs, and local-direct fallback requires the configured token instead of implicitly authenticating same-host callers
- **Gateway/node commands**: node commands now stay disabled until node pairing is approved, so device pairing alone is no longer enough to expose declared node commands

**업데이트 내용**

- **ACP/plugins**: add an explicit default-off ACPX plugin-tools MCP bridge config, document the trust boundary, and harden the built-in bridge packaging/logging path so global installs and stdio MCP sessions work reliably
- **Agents/LLM**: add a configurable idle-stream timeout for embedded runner requests so stalled model streams abort cleanly instead of hanging until the broader run timeout fires
- **Agents/MCP**: materialize bundle MCP tools with provider-safe names (`serverName__toolName`), support optional `streamable-http` transport selection plus per-server connection timeouts, and preserve real tool results from aborted/error turns unless truncation explicitly drops them
- **Android/notifications**: add notification-forwarding controls with package filtering, quiet hours, rate limiting, and safer picker behavior for forwarded notification events
- **Background tasks**: turn tasks into a real shared background-run control plane instead of ACP-only bookkeeping by unifying ACP, subagent, cron, and background CLI execution under one SQLite-backed ledger, routing detached lifecycle updates through the executor seam, adding audit/maintenance/status visibility, tightening auto-cleanup and lost-run recovery, improving task awareness in internal status/tool surfaces, and clarifying the split between heartbeat/main-session automation and detached scheduled runs
- **Background tasks**: add the first linear task flow control surface with `openclaw flows list|show|cancel`, keep manual multi-task flows separate from one-task auto-sync flows, and surface doctor recovery hints for obviously orphaned or broken flow/task linkage
- **Channels/QQ Bot**: add QQ Bot as a bundled channel plugin with multi-account setup, SecretRef-aware credentials, slash commands, reminders, and media send/receive support
- **Diffs**: skip unused viewer-versus-file SSR preload work so `diffs` view-only and file-only runs do less render work while keeping mode outputs aligned
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

`git` `curl` `wget` `nano` `vim` `python3` `pip` `npm` `jq` `build-essential` `inotify-tools`

---

## 구성

```
컨테이너 내부
├── Ollama (127.0.0.1:11434)          ← 로컬 LLM 추론 서버 (오케스트레이터)
└── OpenClaw gateway (127.0.0.1:18789)
        ↕ Telegram Bot API (long-polling)
        Telegram 사용자

클라우드 저장소 (선택)
└── /mnt/storage                      ← STORAGE_PATH 환경변수로 경로 지정
    ├── providers.json                 ← 외부 AI provider API key
    └── backups/                       ← workspace 백업
        ├── manual/                    ← 사용자 요청 백업
        └── temp/                      ← 자동 임시 백업 (최대 5개)
```

- API 비용 없음 — 기본 구성은 Ollama 로컬 모델만 사용
- 외부 provider 추가 시 클라우드 저장소의 `providers.json`으로 관리
- workspace 변경 시 자동 임시 백업, Telegram으로 수동 백업/복원 가능

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
| `STORAGE_PATH` | `/mnt/storage` | 클라우드 저장소 마운트 경로 (기본값: `/mnt/storage`) |
| `GITHUB_USERNAME` | `your-username` | git config user.name |
| `GITHUB_EMAIL` | `you@example.com` | git config user.email |
| `GITHUB_TOKEN` | `ghp_...` | GitHub Personal Access Token (git push 인증) |
| `GITHUB_REPO_URL` | `https://github.com/you/repo` | 컨테이너 시작 시 `/workspace` 에 클론할 repo URL |

> GitHub 관련 변수는 모두 선택사항. `GITHUB_USERNAME`과 `GITHUB_EMAIL`이 없으면 GitHub 설정 전체가 스킵됨.

---

## 외부 AI 모델 추가

기본 구성은 Ollama 로컬 모델만 사용합니다. 외부 AI provider를 추가하려면 클라우드 저장소의 `providers.json`을 수정하고 gateway만 재시작하면 됩니다. 워크로드 재시작 불필요.

### providers.json 형식

```json
{
  "ANTHROPIC_API_KEY": "sk-ant-...",
  "OPENAI_API_KEY": "sk-...",
  "GEMINI_API_KEY": "..."
}
```

파일 위치: `<STORAGE_PATH>/providers.json` (기본값: `/mnt/storage/providers.json`)

### 지원 Provider 및 키 이름

| Provider | 키 이름 | 비고 |
|---|---|---|
| Anthropic (Claude) | `ANTHROPIC_API_KEY` | `sk-ant-` 로 시작 |
| OpenAI (GPT) | `OPENAI_API_KEY` | `sk-` 로 시작 |
| Google (Gemini) | `GEMINI_API_KEY` | |
| Mistral | `MISTRAL_API_KEY` | |
| DeepSeek | `DEEPSEEK_API_KEY` | |
| Groq | `GROQ_API_KEY` | |

### 적용 방법

1. 클라우드 저장소에 `providers.json` 파일 생성 또는 수정
2. 컨테이너에서 gateway 재시작:
    ```bash
    pkill -f openclaw-gateway
    ```
3. 3초 내 자동 재시작되면서 `providers.json` 재로드 완료

> 설정하지 않은 provider는 자동으로 스킵됩니다. 필요한 것만 추가하면 됩니다.

---

## workspace 백업/복원

컨테이너가 내려가면 `/root/.openclaw/workspace` 내용이 사라집니다.
클라우드 저장소가 연결되어 있으면 Telegram으로 백업/복원을 요청할 수 있습니다.

### 자동 임시 백업

workspace 파일이 변경될 때마다 5분 쿨타임으로 자동 백업을 생성합니다.
`<STORAGE_PATH>/backups/temp/` 에 최대 5개까지 보관하며, 초과 시 가장 오래된 것을 삭제합니다.

### Telegram으로 백업/복원

| 요청 | 동작 |
|---|---|
| "변경사항 저장해줘" | 백업 이름 입력 요청 → 미입력 시 타임스탬프 자동 생성 → `backups/manual/` 에 저장 |
| "백업 목록 알려줘" | manual + temp 백업 목록 출력 |
| "X 백업으로 복원해줘" | workspace 복원 후 gateway 재시작 |

### 백업 이름 규칙

| 종류 | 형식 | 예시 |
|---|---|---|
| 자동 임시 백업 | `temp-YYYYMMDD-HHmm` | `temp-20260401-1430` |
| 수동 백업 (이름 지정) | 사용자 지정 | `my-settings` |
| 수동 백업 (이름 미지정) | `YYYYMMDD-HHmm` | `20260401-1430` |

### openclaw gateway 재시작 (컨테이너 유지)

```bash
pkill -f openclaw-gateway
# → 3초 이내 자동 재기동, 컨테이너 종료 없음
```

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
| `STORAGE_PATH` | (선택) 클라우드 저장소 마운트 경로 (기본값: `/mnt/storage`) |
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

gcube Storage Management에서 Dropbox 또는 AWS S3 연결 후 워크로드에 마운트.
마운트 경로를 `/mnt/storage` 로 지정하면 별도 환경변수 없이 동작.
다른 경로를 사용하는 경우 `STORAGE_PATH` 환경변수에 해당 경로를 지정.

클라우드 저장소 연결 시 사용 가능한 기능:
- `providers.json` 으로 외부 AI provider API key 관리
- Telegram으로 workspace 백업/복원

**6단계 — 배포 확인**

배포 후 워크로드 로그에서 아래 메시지 확인:

```
[ DONE ] All services started
  Ollama model  : qwen3.5:9b
  Gateway token : <자동생성토큰>
```

**Control UI 접근:**
```
http://<gcube-service-url>/__openclaw__/
```
접속 후 로그에 출력된 `Gateway token` 값을 입력하면 OpenClaw 관리 화면으로 진입.

로그 출력 후 Telegram에서 봇에게 메시지 보내면 바로 응답.

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
