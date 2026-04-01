# gcube test - openclaw+ollama

## 목차

1. 동작 기능
2. 시스템 구성
3. 베이스 이미지 정보
4. 구현 내용
5. 실행 방법
6. Control UI 접근
7. 향후 계획

---

## 1. 동작 기능

더 자세한 내용은 해당 repo의 readme 참고 — [GitHub - chaeyoon-08/openclaw-ollama-baseimage](https://github.com/chaeyoon-08/openclaw-ollama-baseimage)

- **Telegram 인터페이스**: 지정된 Telegram 사용자 ID만 봇 사용 허용 (allowlist 방식)
- **로컬 LLM 추론**: Ollama를 통해 gcube GPU에서 직접 모델 추론
- **외부 AI API 지원**: Anthropic, OpenAI, Gemini, Mistral, DeepSeek, Groq 등 외부 provider API key 환경변수 설정 시 자동 등록
- **자동 초기 설정**: 컨테이너 시작 시 환경변수만으로 Telegram 연동·모델 다운로드·게이트웨이 설정 자동 완료
- **GitHub 연동**: 지정 repo를 `/workspace`에 자동 클론, git 인증 자동 구성
- **workspace 백업/복원**:
  - 자동 임시 백업: workspace 변경 감지 시 3분 디바운싱으로 cloud storage에 자동 저장 (최대 10개 보관)
  - 수동 백업: `backup-manager.sh save [이름]` 실행
  - 복원: `backup-manager.sh restore <이름>` 실행 → openclaw gateway 자동 재시작
- **gateway 자동 재시작**: `pkill -f openclaw-gateway` 실행 후 자동 재기동 (컨테이너 종료 없음)
- **Control UI**: gcube 서비스 URL로 OpenClaw 웹 대시보드 접근 — gateway 토큰 입력 후 바로 연결

---

## 2. 시스템 구성

```
Telegram 사용자
  ↕ long-polling (outbound HTTP, 인바운드 포트 개방 불필요)
OpenClaw Gateway (0.0.0.0:18789)
  ↕ http://localhost:11434
Ollama API (127.0.0.1:11434)
  ↓
GPU (NVIDIA RTX 5090, VRAM 31.8 GiB)
```

| 컴포넌트 | 버전 | 역할 |
|---|---|---|
| 베이스 이미지 | nvidia/cuda:12.8.1-runtime-ubuntu22.04 | CUDA 환경 |
| Ollama | 0.19.0 | 로컬 LLM 서빙 |
| OpenClaw | 2026.3.31 | AI 게이트웨이 (Telegram 채널 포함) |
| Node.js | 24 | OpenClaw 런타임 |
| LLM 모델 | qwen3.5:9b | 추론 모델 (환경변수로 교체 가능) |

---

## 3. 베이스 이미지 정보

| 항목 | 내용 |
|---|---|
| 베이스 이미지 | `nvidia/cuda:12.8.1-runtime-ubuntu22.04` |
| CUDA 버전 | 12.8.1 |
| 지원 GPU 아키텍처 | Maxwell(sm_50) ~ Blackwell(sm_120) |
| OS | Ubuntu 22.04 LTS |
| 최소 호스트 드라이버 | 570.124.06 이상 |
| 시간대 | Asia/Seoul (KST) |
| 이미지 레지스트리 | `ghcr.io/chaeyoon-08/openclaw-ollama-baseimage` |

**CUDA 12.8.1 선택 이유**
- CUDA 13.x부터 Pascal(sm_60/61) 아키텍처 지원 제거
- 12.8.1은 전 세대 GPU를 지원하는 마지막 안정 버전

**사전 설치 도구**
- `git` `curl` `wget` `nano` `vim`
- `python3` `python3-pip`
- `nodejs(24)` `npm`
- `build-essential` `ca-certificates` `jq` `zstd` `inotify-tools`

---

## 4. 구현 내용

### Dockerfile

- CUDA runtime 이미지 기반 빌드
- Ollama 설치: `install.sh` 대신 `tar.zst` 직접 해제 방식 적용
  - `install.sh`는 systemd 서비스까지 설치 → 컨테이너 환경에 부적합
  - `/usr/bin/ollama` 바이너리 및 `/usr/lib/ollama` GPU 라이브러리만 추출
- OpenClaw 설치: `npm install -g openclaw@latest`
- Node.js 24: nodesource 공식 저장소를 통해 설치
- `inotify-tools` 설치: workspace 변경 감지 자동 백업용
- `TZ=Asia/Seoul` 설정: 백업 타임스탬프 한국 시간 기준
- `backup-manager.sh` 설치: `/usr/local/bin/backup-manager.sh`

### entrypoint.sh

- 필수 환경변수 미설정 시 즉시 종료 및 오류 출력
- GitHub 설정: `GITHUB_USERNAME` + `GITHUB_EMAIL` 양쪽 모두 있을 때만 활성화
- Ollama 모델 다운로드: CLI 대신 REST API(`POST /api/pull`, stream) 사용
  - CLI 방식은 non-TTY 환경에서 진행바가 줄바꿈으로 출력 → 로그 수천 줄 발생
  - API 방식으로 전환 후 10% 단위 필터링 → 약 15줄로 감소
- **OpenClaw 토큰**: `OPENCLAW_GATEWAY_TOKEN` 환경변수 설정 시 고정 토큰 사용, 미설정 시 `/dev/urandom` 기반 32자 자동 생성
- **외부 provider 자동 등록**: `ANTHROPIC_API_KEY` 등 API key 환경변수 감지 시 `openclaw.json`에 자동 추가
- Telegram allowlist: `TELEGRAM_ALLOWED_USER_IDS` (쉼표 구분) → JSON 배열 변환
- **자동 임시 백업 루프**: `inotifywait`으로 workspace 변경 감지 → 3분 디바운싱 → cloud storage에 저장 (최대 10개)
- gateway 재시작 루프: SIGTERM 정상 종료 처리

### backup-manager.sh

```bash
backup-manager.sh list               # 백업 목록 조회
backup-manager.sh save [이름]         # 수동 백업 (이름 없으면 타임스탬프 자동 생성)
backup-manager.sh restore <이름>      # 복원 후 gateway 자동 재시작
```

cloud storage 경로: `$STORAGE_PATH/backups/` (기본값: `/mnt/storage/backups/`)

### GitHub Actions (`docker-publish.yml`)

- 트리거: `main` 브랜치 push, `v*.*.*` 태그, `workflow_dispatch`
- 레지스트리: `ghcr.io` (별도 시크릿 불필요, `GITHUB_TOKEN` 자동 인증)
- 레이어 캐시: `type=gha,mode=max`
- README 자동 업데이트: 릴리즈 시 OpenClaw 버전 정보 및 주요 변경사항 한국어 요약 자동 반영

---

## 5. 실행 방법

### gcube 배포 시 환경변수

**필수**

| 변수명 | 예시 | 설명 |
|---|---|---|
| `TELEGRAM_BOT_TOKEN` | `123456:ABC...` | Telegram 봇 토큰 |
| `TELEGRAM_ALLOWED_USER_IDS` | `123456789` | 허용할 Telegram user ID (쉼표로 여러 명) |
| `OLLAMA_MODEL` | `qwen3.5:9b` | 사용할 Ollama 모델 (태그 필수) |

**선택**

| 변수명 | 예시 | 설명 |
|---|---|---|
| `OPENCLAW_GATEWAY_TOKEN` | `my-token` | Control UI 토큰 고정. 미설정 시 자동 생성 |
| `STORAGE_PATH` | `/mnt/storage` | cloud storage 마운트 경로 (기본값: `/mnt/storage`) |
| `ANTHROPIC_API_KEY` | `sk-ant-...` | Anthropic Claude API key |
| `OPENAI_API_KEY` | `sk-...` | OpenAI API key |
| `GEMINI_API_KEY` | `AIza...` | Google Gemini API key |
| `MISTRAL_API_KEY` | `...` | Mistral API key |
| `DEEPSEEK_API_KEY` | `...` | DeepSeek API key |
| `GROQ_API_KEY` | `...` | Groq API key |
| `GITHUB_USERNAME` | `chaeyoon-08` | git config user.name |
| `GITHUB_EMAIL` | `...@data-alliance.com` | git config user.email |
| `GITHUB_TOKEN` | `ghp_...` | GitHub Personal Access Token |
| `GITHUB_REPO_URL` | `https://github.com/...` | 시작 시 `/workspace`에 클론할 repo |

### 로컬 테스트

```bash
# .env 파일 작성 후
docker compose up              # GPU 있는 경우
docker run --env-file .env ghcr.io/chaeyoon-08/openclaw-ollama-baseimage:latest
```

### 백업/복원

```bash
# 수동 백업
backup-manager.sh save my-backup

# 백업 목록 확인
backup-manager.sh list

# 복원
backup-manager.sh restore my-backup

# gateway 재시작 (컨테이너 유지)
pkill -f openclaw-gateway
```

---

## 6. Control UI 접근

OpenClaw 웹 대시보드(`https://<gcube-서비스-URL>`)로 모델·채널·에이전트 설정 관리 가능.

**접속 방법**

1. gcube 서비스 URL 접속 → OpenClaw Gateway Dashboard 화면
2. Gateway Token 입력 (컨테이너 내부 확인: `jq -r '.gateway.auth.token' /root/.openclaw/openclaw.json`)
3. Connect 클릭 → 바로 진입 (device 인증 없음)

**토큰 고정 (권장)**

gcube 워크로드 환경변수에 `OPENCLAW_GATEWAY_TOKEN=원하는값` 설정 시:
- 재시작 후에도 동일 토큰 유지 → 브라우저 세션 유지
- 북마크 URL: `https://<gcube-서비스-URL>/#token=<설정한-토큰값>` → 토큰 자동 입력

---

## 7. 향후 계획

- **에이전트 구조화**: SOUL.md, skills/ 폴더 설계 — 역할별 에이전트 전문화
- **멀티 에이전트 등록**: OpenClaw에 역할별 에이전트를 복수 등록하여 작업 분리 및 전문화
- **오케스트레이션 기능**: 에이전트 간 태스크 분배·위임 구조 설계 및 구현
