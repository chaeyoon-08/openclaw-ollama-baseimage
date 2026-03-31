# SPEC.md — 기술 스펙 (검증된 정보)

> 아래 내용은 공식 문서 및 소스코드를 기반으로 검증된 사항입니다.
> 각 항목에 출처 URL이 명시되어 있습니다.

---

## 베이스 이미지

```
nvidia/cuda:12.8.1-runtime-ubuntu22.04
```

| 항목 | 내용 |
|---|---|
| CUDA 버전 | 12.8.1 — Pascal(sm_60) ~ Blackwell(sm_120) 전 GPU 지원하는 마지막 시리즈 |
| 이미지 변형 | `runtime` — Ollama는 사전 컴파일 바이너리라 devel 불필요 |
| OS | Ubuntu 22.04 LTS (2027년까지 지원) |
| 최소 호스트 드라이버 | `>=570.124.06` (Linux) |
| 지원 compute capability | sm_50(Maxwell) ~ sm_120(Blackwell) |
| CUDA 13.x 변경사항 | Pascal(sm_60/61), Volta(sm_70) 지원 **dropped** → 12.x 선택 이유 |

- 출처: https://hub.docker.com/r/nvidia/cuda
- 출처: https://docs.nvidia.com/cuda/cuda-toolkit-release-notes/
- 출처: https://github.com/ollama/ollama/blob/main/CMakePresets.json (CUDA 12 빌드 타겟: sm_50~sm_120)

---

## Ollama

### 설치 (컨테이너 내부)

```bash
# 출처: https://docs.ollama.com/linux
# tar 방식 사용 이유: install.sh는 systemd 서비스까지 설치 → 컨테이너에 부적합
curl -fsSL https://ollama.com/download/ollama-linux-amd64.tar.zst | tar x -C /usr
# → /usr/bin/ollama 바이너리
# → /usr/lib/ollama/ GPU 라이브러리
```

### 서비스 기동 패턴

```bash
# 출처: https://docs.ollama.com/docker
ollama serve &
until curl -sf http://localhost:11434/ > /dev/null 2>&1; do sleep 1; done
ollama pull "$OLLAMA_MODEL"
```

### 모델명 규칙 (중요)

- 형식: `modelname:tag` (예: `qwen3:14b`)
- **태그 없이 지정하면 `:latest` 로 시도** — `:latest` 가 없는 모델은 `pull model manifest: file does not exist` 오류 발생
- **반드시 명시적 태그 포함** (예: `qwen3:8b`, `qwen3:14b`, `qwen3:32b`)
- qwen3 사용 가능 태그: `0.6b`, `1.7b`, `4b`, `8b`(=latest), `14b`, `30b`, `32b`, `235b`
- 출처: https://ollama.com/library/qwen3

### 필수 환경변수 (Dockerfile ENV)

| 변수 | 값 | 설명 |
|---|---|---|
| `NVIDIA_VISIBLE_DEVICES` | `all` | NVIDIA container runtime에 GPU 전달 |
| `NVIDIA_DRIVER_CAPABILITIES` | `compute,utility` | CUDA compute + nvidia-smi 주입 |
| `OLLAMA_HOST` | `127.0.0.1:11434` | 컨테이너 내부 전용 (외부 노출 불필요) |

- 출처: https://github.com/ollama/ollama/blob/main/Dockerfile
- 출처: https://github.com/ollama/ollama/blob/main/envconfig/config.go

### 선택 환경변수

| 변수 | 기본값 | 설명 |
|---|---|---|
| `OLLAMA_MODELS` | `~/.ollama/models` | 모델 저장 경로 (볼륨 마운트 시 지정) |
| `OLLAMA_KEEP_ALIVE` | `5m` | VRAM 유지 시간 |
| `OLLAMA_FLASH_ATTENTION` | `false` | `1` 설정 시 VRAM 절감 |

### GPU 지원 최소 요구사항
- compute capability 5.0+ (Maxwell 이상)
- 호스트 드라이버 531+
- 출처: https://github.com/ollama/ollama/blob/main/docs/gpu.mdx

---

## OpenClaw

### 설치

```bash
# 출처: https://www.npmjs.com/package/openclaw
npm install -g openclaw@latest
# Node.js 22.16 이상 필수, 24 권장
```

### Gateway 기동

```bash
# 출처: https://docs.openclaw.ai/cli/gateway
openclaw gateway --force
```

| 플래그 | 설명 |
|---|---|
| `--force` | 포트 충돌 시 기존 프로세스 종료 |
| `--allow-unconfigured` | openclaw.json 없이 시작 (부트스트랩용) |
| `--bind <mode>` | `loopback` \| `lan` \| `auto` |

### openclaw.json 구조 (JSON 형식으로 작성, JSON5 파서가 읽음)

```json
{
  "gateway": {
    "mode": "local",
    "port": 18789,
    "bind": "loopback",
    "auth": { "mode": "token", "token": "<token>" }
  },
  "models": {
    "mode": "merge",
    "providers": {
      "ollama": {
        "baseUrl": "http://localhost:11434",
        "apiKey": "ollama",
        "api": "ollama"
      }
    }
  },
  "agents": {
    "defaults": {
      "model": { "primary": "ollama/qwen3:14b" }
    }
  },
  "channels": {
    "telegram": {
      "enabled": true,
      "botToken": "<TELEGRAM_BOT_TOKEN>",
      "dmPolicy": "allowlist",
      "allowFrom": ["123456789"]
    }
  }
}
```

**모델 참조 형식**: `"<provider_key>/<model_id>"` → provider 키가 `ollama` 이면 `"ollama/qwen3:14b"`

- 출처: https://docs.openclaw.ai/gateway/configuration-reference
- 출처: https://docs.openclaw.ai/providers/ollama

### Telegram allowlist (승인 자동화)

| dmPolicy | 동작 |
|---|---|
| `"pairing"` | 첫 메시지 시 코드 발급 → `openclaw pairing approve telegram <CODE>` 수동 실행 필요 |
| `"allowlist"` | `allowFrom` 에 있는 ID는 즉시 사용 가능, **승인 과정 없음** |
| `"open"` | 누구나 사용 가능 (보안 취약) |

- `allowFrom` 형식: 수치형 Telegram user ID 문자열 (`"123456789"`), `@username` 불가
- `TELEGRAM_ALLOWED_USER_IDS` 환경변수(쉼표 구분) → entrypoint.sh에서 JSON 배열로 변환
- 출처: https://docs.openclaw.ai/channels/telegram

---

## 사전 설치 도구

```
git  curl  wget  nano  vim
python3  python3-pip
nodejs (24)  npm
build-essential  ca-certificates  jq
```

---

## 포트 구조

```
Telegram (외부)
    ↕ long-polling (outbound HTTP)
openclaw gateway (127.0.0.1:18789)
    ↓ http://localhost:11434
Ollama API (127.0.0.1:11434)
```

Telegram long-polling: 컨테이너에서 Telegram API로 outbound 요청 → gcube 인바운드 정책 무관하게 동작.

---

## GitHub Actions

| 항목 | 값 |
|---|---|
| 레지스트리 | `ghcr.io` |
| 인증 | `GITHUB_TOKEN` (별도 시크릿 불필요) |
| 필요 권한 | `contents: read`, `packages: write` |
| 트리거 | main push, `v*.*.*` 태그, `workflow_dispatch` |
| 레이어 캐시 | `type=gha,mode=max` |

Action 버전 (2025/2026 기준):

| Action | 버전 |
|---|---|
| `actions/checkout` | `@v6` |
| `docker/setup-buildx-action` | `@v4` |
| `docker/login-action` | `@v4` |
| `docker/metadata-action` | `@v6` |
| `docker/build-push-action` | `@v7` |

- 출처: https://github.com/docker/build-push-action
- 출처: https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry
