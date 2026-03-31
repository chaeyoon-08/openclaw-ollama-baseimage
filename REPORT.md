# OpenClaw + Ollama Telegram 봇 gcube 배포 보고서

| 항목 | 내용 |
|---|---|
| 작성일 | 2026-03-31 |
| 작성자 | 채윤 |
| 상태 | 완료 |

---

## 1. 동작 기능

- **Telegram 인터페이스**: 지정된 Telegram 사용자 ID만 봇 사용 허용 (allowlist 방식)
- **로컬 LLM 추론**: Ollama를 통해 gcube GPU에서 직접 모델 추론 — 외부 AI API 미사용
- **자동 초기 설정**: 컨테이너 시작 시 환경변수만으로 Telegram 연동·모델 다운로드·게이트웨이 설정 자동 완료
- **GitHub 연동**: `GITHUB_REPO_URL` 설정 시 `/workspace`에 클론, git 인증 자동 구성
- **workspace 백업/복원** *(테스트 필요)*:
  - `backup.sh` 실행 → `/root/.openclaw/workspace` 내용을 `/workspace/.openclaw_copy`로 복사 후 git push로 보존
  - 컨테이너 재시작 시 git repo 재클론 → `.openclaw_copy`가 포함되어 있으면 자동 복원
  - `restore.sh` 실행 → 수동 복원 후 openclaw gateway 재시작 명령어 안내
- **gateway 자동 재시작** *(테스트 필요)*: `pkill -f openclaw-gateway` 실행 후 3초 이내 자동 재기동 (컨테이너 종료 없음)

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
| Ollama | 0.19.0 | 로컬 LLM 서빙 |
| OpenClaw | latest | AI 게이트웨이 (Telegram 채널 포함) |
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
| 이미지 레지스트리 | `ghcr.io/chaeyoon-08/openclaw-ollama-baseimage` |

**CUDA 12.8.1 선택 이유**
- CUDA 13.x부터 Pascal(sm_60/61) 아키텍처 지원 제거
- 12.8.1은 전 세대 GPU를 지원하는 마지막 안정 버전

**사전 설치 도구**
- `git` `curl` `wget` `nano` `vim`
- `python3` `python3-pip`
- `nodejs(24)` `npm`
- `build-essential` `ca-certificates` `jq` `zstd`

---

## 4. 구현 내용

### Dockerfile
- CUDA runtime 이미지 기반 빌드
- Ollama 설치: `install.sh` 대신 `tar.zst` 직접 해제 방식 적용
  - `install.sh`는 systemd 서비스까지 설치 → 컨테이너 환경에 부적합
  - `/usr/bin/ollama` 바이너리 및 `/usr/lib/ollama` GPU 라이브러리만 추출
- OpenClaw 설치: `npm install -g openclaw@latest`
- Node.js 24: nodesource 공식 저장소를 통해 설치

### entrypoint.sh
- 필수 환경변수 미설정 시 즉시 종료 및 오류 출력
- GitHub 설정: `GITHUB_USERNAME` + `GITHUB_EMAIL` 양쪽 모두 있을 때만 활성화
- Ollama 모델 다운로드: CLI 대신 REST API(`POST /api/pull`, stream) 사용
  - CLI 방식은 non-TTY 환경에서 진행바가 줄바꿈으로 출력 → 로그 수천 줄 발생
  - API 방식으로 전환 후 10% 단위 필터링 → 약 15줄로 감소
- OpenClaw 토큰: 시작 시마다 `/dev/urandom` 기반 32자 자동 생성
- Telegram allowlist: `TELEGRAM_ALLOWED_USER_IDS` (쉼표 구분) → JSON 배열 변환
- `backup.sh` / `restore.sh` 자동 생성 및 `/workspace`에 배치 *(테스트 필요)*
- gateway 재시작 루프: `wait` 대신 3초 주기 상태 확인으로 교체, SIGTERM 정상 종료 처리 *(테스트 필요)*

### GitHub Actions (`docker-publish.yml`)
- 트리거: `main` 브랜치 push, `v*.*.*` 태그, `workflow_dispatch`
- 레지스트리: `ghcr.io` (별도 시크릿 불필요, `GITHUB_TOKEN` 자동 인증)
- 레이어 캐시: `type=gha,mode=max`

---

## 5. 실행 방법

### gcube 배포 시 필수 환경변수

| 변수명 | 예시 | 필수 여부 |
|---|---|---|
| `TELEGRAM_BOT_TOKEN` | `123456:ABC...` | 필수 |
| `TELEGRAM_ALLOWED_USER_IDS` | `123456789` | 필수 |
| `OLLAMA_MODEL` | `qwen3.5:9b` | 필수 (태그 포함) |
| `GITHUB_USERNAME` | `chaeyoon-08` | 선택 |
| `GITHUB_EMAIL` | `...@data-alliance.com` | 선택 |
| `GITHUB_TOKEN` | `ghp_...` | 선택 |
| `GITHUB_REPO_URL` | `https://github.com/...` | 선택 |

### workspace 백업/복원 *(테스트 필요)*

```bash
# 백업 (컨테이너 내려가기 전)
/workspace/backup.sh
git -C /workspace add .openclaw_copy && git -C /workspace commit -m "backup" && git -C /workspace push

# 수동 복원 (재시작 후 자동 복원이 안 된 경우)
/workspace/restore.sh
# → 안내 메시지에 따라 pkill -f openclaw-gateway 실행

# openclaw gateway 재시작 (컨테이너 유지)
pkill -f openclaw-gateway
# → 3초 이내 자동 재기동
```

### 로컬 테스트

```bash
# .env 파일 작성 후
docker compose up          # GPU 있는 경우
docker run --env-file .env ghcr.io/chaeyoon-08/openclaw-ollama-baseimage:latest
```

---

## 6. 향후 계획

- **멀티 에이전트 등록**: OpenClaw에 역할별 에이전트를 복수 등록하여 작업 분리 및 전문화
- **오케스트레이션 기능 추가**: 에이전트 간 태스크 분배·위임 구조 설계 및 구현
