# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 목표

gcube 워크로드에 배포할 **OpenClaw + Ollama base Docker image** 구축.
컨테이너를 띄우기만 하면 환경변수 기반으로 Telegram 연동, GitHub 설정, Ollama 모델 다운로드가 자동 완료되는 환경.

**배경**: API 비용 절감(Anthropic 대신 로컬 Ollama) + 보안(로컬 PC 대신 gcube 독립 환경)
**범위**: 컨테이너 내부만 인식. gcube 클라우드 저장소는 `STORAGE_PATH` 환경변수로 지정 (기본값: `/mnt/storage`).

---

## 스펙 문서 참조

| 문서 | 내용 |
|---|---|
| `spec/SPEC.md` | 기술 스펙 — 베이스 이미지, Ollama/OpenClaw 설치 방법, 설정 구조, 포트 |
| `spec/GCUBE.md` | gcube 플랫폼 조사 결과 — 레지스트리, 저장소 마운트, GPU, 네트워크 정책 |

---

## 아키텍처

```
gcube 워크로드 (GPU 컨테이너)
├── Dockerfile          ← CUDA + 기본 도구 + OpenClaw + Ollama 사전 설치
├── entrypoint.sh       ← 환경변수 기반 자동 설정
└── 런타임:
    Telegram ↔ openclaw gateway (127.0.0.1:18789) ↔ Ollama (127.0.0.1:11434)
    gcube 클라우드 저장소 → /mnt/storage (STORAGE_PATH, 볼륨 마운트)
```

---

## 핵심 규칙

- **공식 문서 확인 필수**: `spec/SPEC.md`의 출처 URL 참조. 확인되지 않은 옵션 사용 금지
- **출처 링크 첨부**: 스크립트/설정 파일 상단에 참고한 공식 문서 URL 주석으로 명시
- **자체 검증**: 코드/설정 전달 전 문법 오류, 호환성 확인
- **이모지 금지**: 스크립트 출력에 이모지 사용 금지, ANSI 색상만 사용
- **기존 파일 보호**: 사용자의 개인 문서/작업물을 건드리지 않도록 주의
- **`.sh` 파일 무단 수정 금지**: 명시적으로 요청된 경우에만 수정
- **push 전 반드시 확인**: 코드 작업 완료 후 git push 전에 사용자에게 push 여부를 먼저 물어볼 것

---

## 환경변수 설계

| 변수 | 필수 | 용도 |
|---|---|---|
| `TELEGRAM_BOT_TOKEN` | 필수 | Telegram 봇 연동 |
| `TELEGRAM_ALLOWED_USER_IDS` | 필수 | 봇 허용 수치형 Telegram user ID (쉼표로 여러 명 가능) |
| `OLLAMA_MODEL` | 필수 | 사용할 Ollama 모델. **반드시 태그 포함** (예: `qwen3:14b`) |
| `GITHUB_USERNAME` | 선택 | git config user.name (없으면 GitHub 설정 전체 스킵) |
| `GITHUB_EMAIL` | 선택 | git config user.email (없으면 GitHub 설정 전체 스킵) |
| `GITHUB_TOKEN` | 선택 | GitHub Personal Access Token (git push 인증) |
| `GITHUB_REPO_URL` | 선택 | 시작 시 `/workspace` 에 클론할 repo URL |

---

## 스크립트 로그 스타일

ANSI 색상만, 이모지 없음:

```bash
log_start()  { echo -e "\033[1;34m[ START ]\033[0m $1"; }
log_doing()  { echo -e "\033[0;36m[ DOING ]\033[0m $1"; }
log_ok()     { echo -e "\033[0;32m[  OK   ]\033[0m $1"; }
log_warn()   { echo -e "\033[1;33m[ WARN  ]\033[0m $1"; }
log_error()  { echo -e "\033[0;31m[ ERROR ]\033[0m $1"; }
log_stop()   { echo -e "\033[1;31m[ STOP  ]\033[0m $1"; exit 1; }
log_done()   { echo -e "\033[1;32m[ DONE  ]\033[0m $1"; }
```

---

## 파일 구조

```
base_image/
├── Dockerfile                          ← CUDA + 도구 + Ollama + OpenClaw 설치
├── entrypoint.sh                       ← 환경변수 기반 자동 설정 및 서비스 기동
├── docker-compose.yml                  ← 로컬 테스트용
├── README.md                           ← 이미지 사양, 사용법
├── .github/workflows/docker-publish.yml ← ghcr.io 자동 빌드/push
└── spec/
    ├── SPEC.md                         ← 기술 스펙 (출처 URL 포함)
    └── GCUBE.md                        ← gcube 플랫폼 조사 결과

```

## 참고 프로젝트

기존 구현체 (`openclaw-project/`):
- `openclaw-ollama-dev/` — Ollama 기반 구현 패턴 (setup.sh, run.sh, config/)
- `openclaw-ollama-image/` — Dockerfile, docker-compose.yml 참고
