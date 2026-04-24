# openclaw-base

gcube GPU 워크로드 전용 OpenClaw + Ollama 컨테이너 이미지.
환경변수 기반으로 Telegram 봇, 로컬 LLM 추론, OpenClaw gateway가 자동 구성되어 기동된다.

이 레포지토리는 브랜치별로 독립된 이미지를 빌드한다.

| 브랜치 | 이미지 | 태그 | 용도 |
|---|---|---|---|
| `main` | `ghcr.io/chaeyoon-08/openclaw-bot` | `:latest`, `:YYYY.MM.DD`, `:sha-<7자>` | 단일 에이전트 — 로컬 LLM + 외부 모델 전환 |
| `multi-agent` | `ghcr.io/chaeyoon-08/openclaw-bot-multi` | `:latest`, `:sha-<7자>` | 멀티 에이전트 + NotebookLM MCP |

---

<!-- OPENCLAW_VERSION_START -->
## OpenClaw 버전 정보

> 이미지 빌드 시 자동 갱신됩니다.

| 항목 | 내용 |
|---|---|
| 설치 버전 | `2026.4.22` |
| 빌드 날짜 | 2026-04-24 |

버전별 변경사항: https://github.com/openclaw/openclaw/releases

<!-- OPENCLAW_VERSION_END -->

---

## 공통 사양

### 베이스 이미지 및 런타임

| 항목 | 값 | 비고 |
|---|---|---|
| 베이스 | `nvidia/cuda:12.8.1-runtime-ubuntu22.04` | |
| CUDA | 12.8.1 | Pascal(sm_60) ~ Blackwell(sm_120) 지원. 13.x부터 Pascal 제거 |
| 최소 호스트 드라이버 | `>= 570.124.06` | |
| OS | Ubuntu 22.04 LTS | 지원 만료: 2027년 |
| Node.js | 24 (nodesource) | OpenClaw 요구사항: 22.16+ |
| OpenClaw | `npm install -g openclaw@latest` | 빌드 시점 최신 버전 고정 |
| Ollama | 공식 tar.zst 최신 바이너리 | 빌드 시점 최신 버전 고정 |
| 노출 포트 | `18789` | OpenClaw gateway + Control UI |

### 공통 파일 구조

```
├── Dockerfile              이미지 빌드 정의
├── entrypoint.sh           컨테이너 시작 진입점
├── generate-config.sh      환경변수 → openclaw.json 변환
├── reload.sh               실행 중 설정 갱신 + gateway 재시작
└── .github/
    ├── workflows/
    │   └── docker-publish.yml  브랜치 push 시 ghcr.io 자동 빌드/push
    └── scripts/
        └── update_readme.py    빌드 시 README OpenClaw 버전 자동 갱신
```

### 파일 간 상호작용

```
컨테이너 기동 시:
  entrypoint.sh
    ├── (필요 시) ollama serve 백그라운드 실행 후 API 헬스체크 대기
    ├── 환경변수 → /home/node/.openclaw/.env 덤프
    ├── generate-config.sh 호출 → /home/node/.openclaw/openclaw.json 생성
    └── openclaw gateway 실행 (비정상 종료 시 자동 재시작)

설정 변경 시:
  reload.sh
    ├── /home/node/.openclaw/.env 수동 수정 후 호출
    ├── generate-config.sh 재호출 → openclaw.json 갱신
    └── openclaw gateway 프로세스 재시작
```

### CI/CD

`docker-publish.yml`은 브랜치 push 시 자동으로:
1. README의 OpenClaw 버전 정보를 `npm view openclaw version`으로 갱신하여 커밋 (`[skip ci]`)
2. 브랜치별 이미지 이름과 태그를 결정하여 ghcr.io에 push

---

## 로컬 개발

```bash
# 이미지 빌드
docker build -t openclaw-bot-multi:local .

# 실행 (최소 필수 변수)
docker run --rm \
  -e TELEGRAM_BOT_TOKEN=<token> \
  -e TELEGRAM_ALLOWED_USER_IDS=<id> \
  -e ORCHESTRATOR_MODEL=ollama/qwen3:14b \
  -p 18789:18789 \
  openclaw-bot-multi:local

# docker-compose로 실행 (.env 파일 사용)
docker compose up --build

# 셸 스크립트 문법 검증
bash -n entrypoint.sh && bash -n generate-config.sh && bash -n reload.sh && bash -n restart.sh
```

---

## 버전 관리 및 업데이트

OpenClaw와 Ollama는 `@latest` / 최신 바이너리를 사용하므로 이미지를 재빌드하면 자동으로 최신 버전이 반영된다. 단, 이 두 컴포넌트가 업데이트될 때는 아래 항목들과의 호환성을 함께 검토해야 한다.

### OpenClaw 업데이트 시 점검 항목

- **Node.js**: OpenClaw가 요구하는 최소 버전이 올라갈 수 있다. 현재 요구사항은 22.16+이며 24를 사용 중. Dockerfile의 `setup_24.x` 버전 변경이 필요할 수 있다.
- **openclaw.json 스키마**: config 키 구조가 변경될 수 있다. `generate-config.sh`에서 생성하는 JSON 키(`gateway`, `agents`, `mcp.servers` 등)가 유효한지 확인 필요. 과거에도 `mcpServers` → `mcp.servers` 같은 변경이 있었다.
- **CLI 명령어**: `entrypoint.sh`와 `reload.sh`에서 사용하는 `openclaw gateway` 명령어 인터페이스가 바뀔 수 있다.

### Ollama 업데이트 시 점검 항목

- **Pull API 응답 형식**: `entrypoint.sh`는 `/api/pull` REST API의 스트리밍 JSON을 파싱하여 진행률을 출력한다. 응답 필드명이 변경되면 로그 출력이 깨질 수 있다.
- **CUDA 요구사항**: Ollama가 지원하는 최소 CUDA/드라이버 버전이 올라갈 수 있다. 베이스 이미지의 CUDA 버전과 호환성 확인 필요.

### CUDA 업데이트 시 점검 항목

- **GPU 지원 범위**: CUDA 13.x부터 Pascal(sm_60/61), Volta(sm_70) GPU가 제거된다. 사용 노드의 GPU 세대 확인 후 업그레이드 여부 결정.
- **호스트 드라이버**: CUDA 버전마다 요구하는 최소 호스트 드라이버 버전이 다르다. gcube 노드의 드라이버가 요구사항을 충족하는지 확인 필요.

---

## openclaw-bot (main 브랜치)

단일 에이전트 최소 구성. 추가 설치 없이 Telegram 봇으로 바로 사용 가능.

### 파일 구조

```
├── entrypoint.sh     환경변수 검증 → Ollama 시작 → 모델 pull → config 생성 → gateway 기동
├── generate-config.sh  OLLAMA_MODEL + Telegram 설정 → openclaw.json (단일 에이전트 구조)
└── reload.sh
```

### generate-config.sh가 생성하는 openclaw.json

- `gateway`: 로컬 모드, 포트 18789, 토큰 인증. `OPENCLAW_GATEWAY_TOKEN` 고정 시 재시작 후에도 동일 토큰 유지; 미설정 시 `/dev/urandom`으로 자동 생성
- `models.providers.ollama`: `http://localhost:11434` 고정. 외부 provider API key(`ANTHROPIC_API_KEY` 등)가 존재하면 해당 provider가 `models.providers`에 자동 추가됨
- `tools.web.search`: DuckDuckGo 기반 웹 검색 기본 활성화 (API 키 불필요)
- `agents.defaults.model.primary`: `OLLAMA_MODEL` 값
- `channels.telegram`: `dmPolicy: allowlist`, `allowFrom`에 `TELEGRAM_ALLOWED_USER_IDS`를 배열로 변환하여 주입

### 런타임 구조

```
컨테이너 (root 실행)
├── ollama serve (127.0.0.1:11434)
└── openclaw gateway (0.0.0.0:18789)
      ↕ Telegram long-polling
```

---

## openclaw-bot-multi (multi-agent 브랜치)

멀티 에이전트 오케스트레이션 + NotebookLM MCP 구성.
요금 폭탄 방어 로직과 비root 실행 보안 구조가 추가됨.

### 추가 설치 패키지

| 패키지 | 설치 방식 | 역할 |
|---|---|---|
| `gosu` | apt | entrypoint(root)에서 gateway를 node 사용자로 전환 실행 |
| `uv` | pip3 | Python 패키지 및 tool 관리자 |
| `notebooklm-mcp-cli` | `uv tool install` (`/opt/uv/tools`) | NotebookLM MCP 서버 |

### 파일 구조

```
├── entrypoint.sh     환경변수 검증 + 요금 방어 → Ollama 조건부 시작 → config 생성
│                     → node 사용자 권한 설정 → workspace 템플릿 초기화 → gateway 기동
├── generate-config.sh  ORCHESTRATOR 모델 + MCP + subagents 구조 → openclaw.json
├── reload.sh           설정 변경 시 in-process reload (SIGUSR1)
├── restart.sh          신규 Ollama 모델 추가 후 gateway full restart
└── templates/          컨테이너 최초 실행 시 workspace에 복사되는 에이전트 초기 파일
    ├── AGENTS.md       오케스트레이션 운영 지침 (cron tier:local 라우팅 등)
    ├── SOUL.md         에이전트 페르소나 정의
    └── MEMORY.md       세션 간 기억 저장소 (sentinel 역할 — 존재 시 템플릿 재복사 방지)
```

### generate-config.sh가 생성하는 openclaw.json

- `gateway`: main과 동일. `controlUi.dangerouslyDisableDeviceAuth: true` 추가 (gcube 환경 Control UI 접근용)
- `models.providers`: `{}` (빈 객체) — `OLLAMA_API_KEY` env var와 함께 OpenClaw가 `/api/tags` 자동 스캔으로 전체 Ollama 모델 표시. `MODEL_API_KEY=provider/key` 형식의 외부 provider는 자동 추가됨
- `tools.web.search`: main과 동일
- `agents.defaults.model.primary`: `ORCHESTRATOR_MODEL` 값
- `agents.defaults.subagents`: `maxSpawnDepth: 1`, `maxConcurrent: 4`. `WORKER_MODELS` 설정 시 첫 번째 항목이 `subagents.model.primary`로 등록됨 — 미설정 시 `ORCHESTRATOR_MODEL` 상속
- `agents.defaults.heartbeat`: Ollama 사용 시 `every: 30m`; 유료 provider 사용 시 `every: 0m`으로 강제 비활성화 (요금 방어)
- `channels.telegram`: main과 동일
- `mcp.servers.notebooklm`: `notebooklm-mcp` 바이너리 직접 호출, `NOTEBOOKLM_MCP_CLI_PATH` 환경변수로 인증 파일 경로 주입
- `mcp.servers.filesystem`: `npx @modelcontextprotocol/server-filesystem`으로 `/workspace` 파일 접근 제공

### 요금 방어 로직

`ORCHESTRATOR_MODEL`이 유료 provider(`anthropic/`, `openai/` 등)인 경우:
- `MODEL_API_KEY`에 해당 provider 키가 없으면 **컨테이너 기동 중단**
- heartbeat **강제 비활성화** (`every: "0m"`) — openclaw#56788, #58137 이슈 대응

### 모델 관리

#### 지원 모델 유형

| 유형 | 등록 방법 | 비고 |
|---|---|---|
| Ollama 오케스트레이터 모델 | `ORCHESTRATOR_MODEL` 환경변수 (1개) | 컨테이너 시작 시 자동 pull |
| Ollama 워커 모델 | `WORKER_MODELS` 환경변수 (공백 구분, 여러 개 가능) | 컨테이너 시작 시 자동 pull, 첫 번째 항목이 subagents 기본 모델로 등록 |
| Ollama 런타임 추가 모델 | 봇 요청으로 `ollama pull` 후 `restart.sh` | `/models`에 자동 표시 |
| 외부 API 모델 | `MODEL_API_KEY` 환경변수 | Anthropic, OpenAI, Google 등 |

vllm, llama.cpp 등 Ollama 이외의 로컬 추론 엔진은 현재 미지원.

#### API 키 보안 정책

API 키(`MODEL_API_KEY`)는 **gcube 환경변수로만** 입력한다. 컨테이너 내부 터미널에서 직접 입력하면 워크로드 재시작 시 초기화된다. gcube 포털 → 워크로드 → 환경변수 설정에서 관리할 것.

#### 런타임 Ollama 모델 추가 (워크로드 재실행 없이)

```bash
# 1. 모델 다운로드 (Ollama_Models/ 마운트 상태이면 클라우드 저장소에 저장됨)
ollama pull qwen3:14b

# 2. gateway restart (모델 목록 재스캔 — SIGUSR1 reload로는 불가, Issue #49568)
bash /usr/local/bin/restart.sh
```

봇(Telegram)에게 요청할 때는 `shell_execute` 도구를 사용한다.

---

### 런타임 구조

```
컨테이너 (entrypoint: root → gateway: node 사용자)
├── ollama serve (127.0.0.1:11434)   ← ollama/ 모델 사용 시에만 기동
├── openclaw gateway (0.0.0.0:18789)
│     ├── Main Agent (ORCHESTRATOR_MODEL)
│     │     └── sessions_spawn → Worker Agent (WORKER_MODELS 첫 번째 항목, maxDepth=1)
│     └── Telegram long-polling
└── MCP 서버 (gateway 자식 프로세스)
      ├── notebooklm-mcp (NOTEBOOKLM_MCP_CLI_PATH 인증 파일 참조)
      └── @modelcontextprotocol/server-filesystem (/workspace)
```

### notebooklm-mcp-cli 변동성 주의

`notebooklm-mcp-cli`는 Google의 공식 API가 아닌 **비공식 내부 API**를 사용하는 커뮤니티 구현체다. 이로 인해 다음과 같은 불안정 요소가 항상 존재한다.

- Google이 내부 API 구조를 변경하면 **예고 없이 동작이 중단**될 수 있다
- 과거에도 인증 파일 구조(`storage_state.json` → `profiles/default/`)와 환경변수명(`NOTEBOOKLM_HOME` → `NOTEBOOKLM_MCP_CLI_PATH`)이 이미 한 차례 변경된 바 있다
- 버전 업데이트 전 [GitHub 이슈](https://github.com/jacob-bd/notebooklm-mcp-cli/issues)에서 인증 구조 변경 여부를 반드시 확인할 것
- 동작 중단 시 `web_search` 도구(DuckDuckGo)로 대체 가능

---

## 참고 링크

- [OpenClaw 공식 문서](https://docs.openclaw.ai/)
- [OpenClaw config 레퍼런스](https://docs.openclaw.ai/gateway/configuration-reference)
- [Ollama 모델 라이브러리](https://ollama.com/library)
- [notebooklm-mcp-cli GitHub](https://github.com/jacob-bd/notebooklm-mcp-cli)
